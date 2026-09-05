# Bulut Yönetilen PostgreSQL Servisleri ve Mimari Tuzaklar (AWS Aurora, GCP AlloyDB vs Bare-Metal / K8s)

Modern bulut sağlayıcıları (AWS, Google Cloud, Azure), PostgreSQL'i "Yönetilen Servis" (Managed Service) olarak sunarak yedekleme, otomatik yama, yüksek erişilebilirlik ve ölçekleme operasyonlarını soyutlar. Ancak bir bulut veritabanının arka planındaki mimariyi, getirdiği kısıtlamaları ve gizli maliyet tuzaklarını bilmeyen mimarlar; ciddi performans darboğazları ve astronomik faturalarla karşılaşırlar.

Bu bölümde; **AWS Aurora**, **GCP AlloyDB**, standart RDS/Cloud SQL mimarileri ile **Bare-Metal / Kubernetes (CloudNativePG)** altyapıları derinlemesine karşılaştırılmaktadır.

---

## 1. AWS Aurora Mimarisi: "The Log is the Database"

Standart PostgreSQL'de her işlem için hem WAL hem de kirli veri sayfaları (Dirty Buffers) periyodik olarak diske yazılır (Checkpoint). AWS Aurora bu paradigmayı kökten değiştirmiştir:

```text
[Standart PostgreSQL]
Compute Engine  --->  [EBS Volume: WAL + Data Pages + Checkpointer]

[AWS Aurora]
Compute Engine  --->  SADECE WAL Kayıtlarını İletir
                             |
                      [Dağıtık Storage Katmanı]
                      (6 Kopya / 3 AZ / Storage Nodes)
                      Arka planda sayfaları Storage kendisi üretir!
```

### 1.1. Aurora Depolama ve Quorum Modeli
* **6 Kopya / 3 Kullanılabilirlik Alanı (AZ):** Her veri parçası (10 GB'lık segmentler) 3 farklı AZ'ye dağıtılmış 6 depolama düğümüne yazılır.
* **Yazma Quorum (4/6):** 6 düğümden 4'ü WAL kaydını diske yazdığını onayladığı anda transaction commit edilir. Bir AZ tamamen çökse dahi yazmalar durmaz.
* **Okuma Quorum (3/6):** Veri bütünlüğü storage katmanında self-healing (kendi kendini onarma) ile korunur.
* **Sıfır Replikasyon Gecikmesi (Sub-10ms Lag):** Okuma replikaları (Read Replicas) ana sunucuyla aynı paylaşılan depolama katmanını (Shared Distributed Storage) okur. Replikaya ayrıca WAL akışı aktarılmaz; bu sayede replika gecikmesi ihmal edilebilir düzeydedir.

---

## 2. GCP AlloyDB ve Kolonsal Hızlandırıcı (Columnar Engine)

GCP AlloyDB, Aurora benzeri ayrık depolama mimarisini (Compute/Storage decoupling) bir adım öteye taşır:
* **Analytical Columnar Engine:** Bellek içinde (RAM) sıkıştırılmış kolonsal bir format tutar.
* Hem OLTP sorgularını (satır bazlı) hem de ağır analitik (OLAP) raporlama sorgularını aynı veritabanında harici bir veri ambarına gerek kalmadan çalıştırabilir.

---

## 3. Yönetilen Bulut Servislerinin Kritik Kısıtlamaları ve Tuzakları

Yönetilen servisler hayatı kolaylaştırsa da bir DBA için ciddi engeller barındırır:

### 3.1. `superuser` Yetkisinin Olmaması
AWS RDS/Aurora (`rds_superuser`) ve GCP Cloud SQL (`cloudsqlsuperuser`) size gerçek `postgres` süper kullanıcı yetkisini **asla vermez**:
* Sunucu işletim sistemine (Linux terminaline) SSH erişimi yoktur.
* `COPY ... PROGRAM` gibi işletim sistemiyle etkileşen komutlar çalıştırılamaz.
* Çekirdek parametrelerin bazıları (örn. `shared_preload_libraries`) keyfi değiştirilemez; yalnızca izin verilen parametre grupları (Parameter Groups) üzerinden yönetilir.

### 3.2. Özel C Eklentisi (Custom C Extensions) Yüklenemez
Sadece bulut sağlayıcının izin verdiği resmi eklentiler (pgvector, PostGIS, pg_stat_statements vb.) kurulabilir. Şirket içi yazılmış özel bir C eklentisi veya derleme gerektiren üçüncü parti bir kütüphane sisteme entegre edilemez.

### 3.3. Disk IOPS Darboğazı ve Burst Kredisi Tükenmesi
Standart AWS RDS (gp2/gp3) disklerde IOPS limiti veritabanı boyutuna ve sağlanan (provisioned) limite bağlıdır. Büyük bir veri aktarımı veya kontrolsüz `VACUUM` çalıştığında:
* Disk I/O kredileri (burst balance) tükenir.
* `DiskQueueDepth` fırlar ve sorgu süreleri milisaniyelerden dakikalara çıkar.

### 3.4. Maliyet Patlaması (Cost Spikes)
* **Aurora I/O Faturalandırması:** Klasik Aurora'da her 1 milyon I/O işlemi için ücret kesilir. Kötü optimize edilmiş bir sorgu, önbellekte bulunmayan milyonlarca sayfayı diski tarayarak faturayı bir gecede binlerce dolar artırabilir (Çözüm: *Aurora I/O-Optimized* seçeneği).
* **Egress (Dışa Veri Akışı) Ücretleri:** Farklı AZ'ler veya bölgeler (regions) arasındaki replikasyon trafiği ve veri indirmeleri beklenmedik faturalara neden olur.

---

## 4. Karar Matrisi: Hangi Mimaride Hangi Seçenek?

| Kriter | AWS Aurora / GCP AlloyDB | Standart RDS / Cloud SQL | K8s (CloudNativePG) / Bare-Metal |
| :--- | :--- | :--- | :--- |
| **Operasyonel İş Yükü** | Sıfıra yakın (Otomatik Failover/Depolama) | Düşük (Yedekleme/Yama otomatik) | Orta/Yüksek (DBA ve Kubernetes uzmanlığı şart) |
| **Okuma Ölçekleme** | 15 Replikaya kadar, 0 gecikmeli | Replikasyon gecikmesi (lag) riski var | Fiziksel Streaming Replication limiti yok |
| **Maliyet (Yüksek Hacimde)**| Çok Yüksek | Orta / Yüksek | En Düşük (Yalnızca donanım/sunucu maliyeti) |
| **Özelleştirme & Kontrol** | Düşük (Kısıtlı parametreler) | Düşük (Kısıtlı parametreler) | %100 Tam Kontrol (Linux kernel + Süper kullanıcı) |
| **Vendor Lock-in** | Yüksek (Storage katmanı tescillidir) | Düşük (Standart PG dump alınabilir) | Sıfır (Tamamen açık kaynak ve taşınabilir) |

---

## 5. Mühendislik Tavsiyesi

1. **Hızlı Başlayan Girişimler (Startups):** DBA kadrosu kurmak yerine **AWS Aurora** veya **GCP Cloud SQL** ile başlamak hız kazandırır.
2. **Büyük Veri & Yüksek Trafik (Scale-ups):** Aylık bulut veritabanı maliyetiniz 10.000$ barajını aştığında, **Kubernetes üzerinde CloudNativePG** veya doğrudan **Bare-Metal NVMe** sunuculara geçiş yapmak maliyeti %70-80 oranında düşürür ve donanım I/O performansını katlar.
