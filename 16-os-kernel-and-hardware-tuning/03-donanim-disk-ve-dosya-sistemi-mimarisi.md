# Donanım, Depolama (RAID) ve Dosya Sistemi Mimarisi

PostgreSQL'in işlem kapasitesi (TPS) ve sorgu yanıt süreleri, üzerinde koştuğu fiziksel donanım mimarisi ve disk alt sistemi ile doğrudan sınırlıdır. Yanlış bir RAID topolojisi, hatalı bir dosya sistemi seçimi veya optimize edilmemiş bir disk zamanlayıcısı, en güçlü sunucularda bile veritabanını %70'e varan oranlarda yavaşlatabilir.

Bu bölümde; CPU ve RAM boyutlandırmasını, Donanımsal vs Yazılımsal RAID mimarilerini, WAL ve Veri disklerinin fiziksel ayrımını, Linux I/O zamanlayıcılarını, Read-Ahead ayarlarını, dosya sistemi (XFS, ext4 ve CoW uyarıları) optimizasyonlarını ve işlemci güç yönetimini ele alacağız.

---

## 1. Donanım Planlaması: CPU ve RAM

```text
                       ┌─────────────────────────┐
                       │    İşlemci (CPU)        │
                       │ Tek Çekirdek Hızı (GHz) │
                       │    > Çekirdek Sayısı    │
                       └────────────┬────────────┘
                                    │
                       ┌────────────▼────────────┐
                       │     Bellek (RAM)        │
                       │    Çalışma Kümesi       │
                       │ (Working Set) RAM'e Sığmalı
                       └────────────┬────────────┘
                                    │
                       ┌────────────▼────────────┐
                       │      Depolama (I/O)     │
                       │  NVMe PCIe / RAID 10    │
                       │ (WAL ve DATA Ayrılmış)  │
                       └─────────────────────────┘
```

### 1.1. CPU: Saat Hızı (Clock Speed) vs Çekirdek Sayısı

- **OLTP (İşlemsel) Sistemler İçin:** PostgreSQL, her istemci bağlantısı için ayrı bir alt süreç (`backend process`) açar. Tekil bir OLTP sorgusu tek bir çekirdekte yürütüldüğünden, yüksek saat hızı (3.5+ GHz) düşük sorgu gecikmesi (latency) için birincil önceliktir.
- **OLAP (Analitik) Sistemler İçin:** Büyük veri taramalarında PostgreSQL paralel sorgu motoru (`max_parallel_workers_per_gather`) devreye girer. Bu senaryolarda çok çekirdekli işlemciler (32-64+ çekirdek) avantaj sağlar.

### 1.2. RAM Boyutu ve Önbellek Verimi

- **Çalışma Kümesi (Working Set):** En sık erişilen indekslerin ve sıcak tabloların toplam boyutu fiziksel RAM içine sığmalıdır.
- **İki Katmanlı Önbellekleme:** PostgreSQL, disk bloklarını hem kendi tamponunda (`shared_buffers`) hem de Linux çekirdeğinin sayfa önbelleğinde (**Linux Page Cache**) tutar. RAM boyutu yeterli olduğunda, disk okuma ihtiyacı neredeyse sıfıra iner.

---

## 2. Depolama Mimarisi ve RAID Topolojileri

### 2.1. RAID Karşılaştırma Matrisi

| RAID Tipi | Okuma Hızı | Yazma Hızı | Hata Toleransı | Minimum Disk | Kullanılabilir Alan | Kurumsal Değerlendirme |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **RAID 0** | Çok Yüksek | Çok Yüksek | **YOK (0)** | 2 | %100 | **Asla Kullanmayın!** (Veri kaybı kesin) |
| **RAID 1** | Yüksek | Normal | 1 Disk | 2 | %50 | Küçük veya yedek sistemler |
| **RAID 5** | Yüksek | **Çok Düşük (Parity Cezası)** | 1 Disk | 3 | %67 - %85 | **Önerilmez!** (Yazma darboğazı) |
| **RAID 6** | Yüksek | **Aşırı Düşük (Çift Parity)** | 2 Disk | 4 | %50 - %75 | Sadece Soğuk Arşiv / Yedek |
| **RAID 10 (1+0)** | **En Yüksek** | **En Yüksek** | **1 Disk Kesin** (Ayrı çiftlerden $N/2$) | 4 | %50 | **PostgreSQL İçin Altın Standart!** |

> [!IMPORTANT]
> **RAID 10 Hata Toleransı:** RAID 10'da hata toleransı garanti olarak **1 disktir**. Birbirinin kopyası olmayan farklı ayna çiftlerinden (mirror pairs) olması şartıyla birden fazla diskin bozulması tolere edilebilir; ancak aynı ayna grubundaki iki disk arızalanırsa tüm veri dizisi çöker.

### 2.2. Neden PostgreSQL İçin RAID 5 veya 6 Kullanılmamalıdır?

RAID 5 ve 6'da her küçük rastgele yazma işleminde disk denetleyicisi 4 adımlı **Write Penalty** uygular:

1. Eski veriyi oku
2. Eski pariteyi oku
3. Yeni pariteyi hesapla
4. Yeni veriyi ve pariteyi diske yaz

PostgreSQL'de WAL logları ve rastgele veri güncellemeleri yoğun olduğunda parite hesaplaması denetleyiciyi kilitler. Ayrıca bir disk arızalandığında dizinin yeniden inşası (rebuild) günlerce sürer ve bu sırada sistem performansı %80'e varan oranda düşer. **Üretim veritabanlarında mutlaka RAID 10 tercih edilmelidir.**

### 2.3. Donanımsal RAID vs Linux Yazılımsal RAID (`mdadm` on NVMe)

- **Geleneksel SAS/SATA Diskler:** Donanımsal RAID kartları (BBU / Flash-Backed Write Cache ile birlikte) güvenli **Write-Back** modu sağladığı için tercih edilir.
- **Modern PCIe NVMe SSD'ler:** Donanım RAID kartları doğrudan CPU'ya bağlı çok şeritli (PCIe 4.0/5.0) NVMe veri yolunda bant genişliği darboğazı yaratabilir. Bu nedenle modern NVMe sunucularında Linux çekirdeğinin doğrudan yönettiği **`mdadm` Yazılımsal RAID 10** mimarisi sıklıkla daha yüksek IOPS ve daha düşük gecikme sunar.

---

## 3. WAL ve Veri Disklerinin Fiziksel Ayrımı (Architecture Isolation)

Yüksek işlem hacimli (High-Throughput OLTP) sistemlerde en kritik mimari kural, **WAL (Write-Ahead Logging)** diskleri ile **Veri Tabloları (Data / Heap)** disklerini fiziksel olarak birbirinden ayırmaktır.

```text
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     Disk Dizisi 1: DATA         │       │      Disk Dizisi 2: WAL         │
│         (/data/pgsql)           │       │         (/wal/pgsql)            │
│                                 │       │                                 │
│  - Rastgele Okuma / Yazma (8KB) │       │  - Saf Sıralı Yazma (Append)    │
│  - $PGDATA/base                 │       │  - $PGDATA/pg_wal               │
│  - Checkpoint Flush Yükü        │       │  - fsync Gecikmesi Sıfır        │
└─────────────────────────────────┘       └─────────────────────────────────┘
```

### 3.1. Neden Ayrılmalıdır?

1. **I/O Çatışmasının Önlenmesi:** Tablo güncellemeleri ve Checkpoint süreçleri diske **rastgele (random) 8KB'lık sayfalar** yazar. WAL ise diskin sonuna sürekli **sıralı (sequential) bloklar** ekler. Aynı fiziksel disk kullanıldığında, rastgele veri yazmaları sıralı WAL yazmalarını bekletir ve transaction commit gecikmelerini fırlatır.
2. **Sembolik Bağ (Symlink) ile Taşıma:**

```bash
# Servisi durdurun
systemctl stop postgresql-16

# pg_wal dizinini yeni fiziksel NVMe diskine taşıyın
mv /var/lib/pgsql/16/data/pg_wal /mnt/fast_nvme_wal/

# Sembolik bağ oluşturun
ln -s /mnt/fast_nvme_wal/pg_wal /var/lib/pgsql/16/data/pg_wal

# İzinleri doğrulayın ve servisi başlatın
chown -h postgres:postgres /var/lib/pgsql/16/data/pg_wal
systemctl start postgresql-16
```

---

## 4. Linux I/O Zamanlayıcıları ve Read-Ahead Optimizasyonu

Linux çekirdeği, disklere gönderilen I/O isteklerini sıralamak ve önceliklendirmek için zamanlayıcılar kullanır.

```bash
# Mevcut disk zamanlayıcısını sorgulama
cat /sys/block/nvme0n1/queue/scheduler
# [none] mq-deadline kyber bfq
```

### 4.1. Önerilen I/O Zamanlayıcıları

- **NVMe SSD Sürücüler:** Donanımın kendisi binlerce paralel donanımsal kuyruğa sahip olduğundan ek çekirdek işlem yükü getirmemek için zamanlayıcı kapatılmalıdır (`none`):
  ```bash
  echo none > /sys/block/nvme0n1/queue/scheduler
  ```
- **SATA / SAS SSD Sürücüler:** `mq-deadline` zamanlayıcısı okuma gecikmesini garantiye alır:
  ```bash
  echo mq-deadline > /sys/block/sda/queue/scheduler
  ```

Kalıcı hale getirmek için `/etc/udev/rules.d/60-scheduler.rules` oluşturulur:

```text
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
```

### 4.2. Disk Önden Okuma (Read-Ahead) Ayarı (`blockdev`)

Linux varsayılan olarak her disk okumasında ardışık blokları da önden okur (örn: 256-512 sektör / 128-256 KB). Ancak OLTP veritabanları rastgele 8 KB bloklar okur; yüksek read-ahead gereksiz I/O tüketir.

```bash
# Mevcut read-ahead değerini sorgulama (sektör cinsinden - 512 bayt)
blockdev --getra /dev/nvme0n1

# OLTP için önden okumayı sıfırlayın veya düşürün (Örn: 0 veya 64 sektör / 32 KB)
blockdev --setra 0 /dev/nvme0n1
```

> [!TIP]
> Read-ahead kapatıldığında PostgreSQL kendi akıllı önden getirme mekanizmasını (`effective_io_concurrency`) kullanarak disk I/O'sunu çok daha verimli yönetir.

---

## 5. Dosya Sistemi Mimarisi: XFS vs ext4 ve CoW Uyarıları

PostgreSQL için sektör standardı dosya sistemleri **XFS** ve **ext4**'tür. Büyük veritabanlarında ve yüksek eşzamanlı yazma operasyonlarında paralel tahsis algoritmaları sayesinde **XFS** genellikle daha yüksek kararlılık sunar.

### 5.1. Kritik Mount Seçenekleri (`/etc/fstab`)

Dosya okumalarında diske son erişim zaman damgasını yazmayı kapatmak (`noatime`) disk I/O'sunu ciddi oranda azaltır:

```text
# XFS için optimize edilmiş /etc/fstab satırı
UUID=xxxx-xxxx-xxxx  /var/lib/pgsql  xfs  noatime,logbufs=8,logbsize=256k,allocsize=64M  0 2

# ext4 için optimize edilmiş /etc/fstab satırı
UUID=xxxx-xxxx-xxxx  /var/lib/pgsql  ext4 noatime,data=ordered,errors=remount-ro         0 2
```

> [!CAUTION]
> Asla `barrier=0` (veya `nobarrier`) seçeneğini kullanmayın! Elektrik kesintisi veya sunucu çökmesi anında dosya sistemi metaverisi bozulabilir ve veritabanı kurtarılamaz hale gelebilir.

### 5.2. Copy-on-Write (CoW) Dosya Sistemleri Uyarısı: Btrfs ve ZFS

**Btrfs** veya **ZFS** gibi Copy-on-Write dosya sistemleri, bir blok güncellendiğinde eski bloğun üzerine yazmak yerine yeni bir blok tahsis eder.

PostgreSQL gibi yoğun rastgele 8KB blok güncellemesi yapan sistemlerde CoW mimarisi şu felaketlere yol açar:

1. **Aşırı Dosya Parçalanması (Severe Fragmentation):** Veritabanı dosyaları yüzbinlerce küçük parçaya bölünür, ardışık taramalar bile felç olur.
2. **Çift Yazma Cezası (Write Amplification):** PostgreSQL zaten WAL ile veri tutarlılığı sağlarken, dosya sisteminin de CoW yapması diske iki kat veri yazılmasına neden olur.

**Eğer Btrfs kullanılmak zorundaysa:** Veritabanı dizini oluşturulurken CoW mutlaka kapatılmalıdır:

```bash
mkdir -p /var/lib/pgsql/16/data
chattr +C /var/lib/pgsql/16/data
```

---

## 6. İşlemci Güç Yönetimi (CPU Power Governor)

Birçok modern işletim sisteminde Linux çekirdeği enerji tasarrufu sağlamak için işlemci frekansını dinamik olarak düşürür (`powersave` veya `ondemand`). Ani bir SQL sorgusu geldiğinde işlemcinin uyanması ve frekans yükseltmesi (wake-up latency) sorgularda mikro-gecikmelere yol açar.

Sunucu işlemcisi sabit maksimum frekansta (`performance`) kilitlenmelidir:

```bash
# cpupower paketini yükleyin
dnf install -y kernel-tools      # RHEL / Rocky Linux
apt-get install -y linux-cpupower # Debian / Ubuntu

# Tüm çekirdekleri 'performance' moduna alın
cpupower frequency-set -g performance

# Doğrulama
cpupower frequency-info
```

Ayrıca sunucu BIOS / UEFI menüsünde **C-States** ve **P-States** enerji tasarrufu modları devre dışı bırakılarak **"Maximum Performance"** profili aktif edilmelidir.
