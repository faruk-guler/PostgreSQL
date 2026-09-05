# Yedekleme ve PITR (Belirli Bir Ana Geri Dönüş)

PostgreSQL'de sadece "SQL Dump (Dışa aktarma)" alarak kurumsal seviyede bir yedekleme (Backup) stratejisi oluşturulamaz. Kurumsal ortamlar için WAL arşivlemesi tabanlı PITR (Point-In-Time Recovery) mimarisi şarttır.

## 1. Neden pg_dump Yetersizdir? (Mantıksal Yedekleme)

`pg_dump` komutu veritabanının yapısını ve içindeki verileri düz metin (SQL script) veya sıkıştırılmış arşiv dosyası olarak dışarı çıkartır.
*   **Dezavantaj 1:** Her gün gece 02:00'de pg_dump aldığınızı düşünün. Ertesi gün saat 14:00'te sistem çökerse, son 12 saatteki tüm verileri kalıcı olarak kaybedersiniz!
*   **Dezavantaj 2:** Dev (Terabaytlık) veritabanlarında pg_dump almak saatler sürer ve sunucuyu yorar. 

Bununla birlikte, pg_dump veritabanını başka bir sunucuya taşımak veya geliştirme (Development) ortamlarına aktarmak için mükemmel bir araçtır.

```bash
# Veritabanını yedeğini Custom (Sıkıştırılmış Binary) formatta alma
pg_dump -h 127.0.0.1 -U postgres -Fc -f yedek_dosyasi.dump urun_db

# Yedeği geri yükleme
pg_restore -h 127.0.0.1 -U postgres -d urun_db yedek_dosyasi.dump
```

---

## 2. Kurumsal Çözüm: Fiziksel Yedekleme ve PITR

Veri kaybına tahammülü olmayan sistemler (Banka, E-Ticaret, Sağlık) **Fiziksel Yedekleme** (Base Backup + WAL Archiving) kullanır.

### Mimarinin Temeli
1.  Haftada bir kez, tüm veri klasörünün (Verilerin diskteki binary hallerinin) kopyası alınır. Buna **Base Backup (Temel Yedek)** denir.
2.  PostgreSQL üzerinde yapılan her işlem zaten 16 MB'lık **WAL (İşlem Günlüğü)** dosyalarına yazılmaktadır.
3.  Doldukça kapanan her bir WAL dosyası, ağ üzerinden başka bir güvenli yedekleme sunucusuna kopyalanır (WAL Archiving).

### PITR (Point-In-Time Recovery) Nedir?
Eğer yanlışlıkla saat 13:45'te `DROP TABLE musteriler;` komutu çalıştırılırsa, felaket senaryosu başlar. PITR ile bu tabloyu geri getirmek şöyledir:
1.  Veritabanı durdurulur ve mevcut bozuk veri klasörü silinir.
2.  Hafta sonu alınan **Base Backup** geri yüklenir.
3.  Yedek sunucusunda biriken binlerce **WAL dosyası** PostgreSQL'e verilir ve şu talimat verilir: *"Bu logları baştan itibaren sırayla çalıştır, ancak saat 13:44:59'a geldiğinde işlemi durdur."*
4.  PostgreSQL tüm verileri hızlı çekimde oynatarak, tam o faciadan 1 saniye önceki haline geri döner. **Veri kaybı SIFIRDIR.**

---

## 3. Yedekleme Yazılımları (PgBackRest ve Barman)

Fiziksel yedekleme işlemlerini (Base backup alma, WAL dosyalarını sıkıştırıp S3/NFS disklerine yollama, PITR yaparken saat hesaplama) manuel scriptlerle yapmak çok tehlikelidir.

Üretim ortamlarında bu işler için iki büyük kurumsal açık kaynak yazılım kullanılır:
*   **PgBackRest:** Kurumsal olarak en yaygın, en hızlı (paralel yedekleme) ve Amazon S3 gibi bulut entegrasyonu en güçlü olan yedekleme aracıdır.
*   **Barman (Backup and Recovery Manager):** 2ndQuadrant tarafından geliştirilen, felaket kurtarma senaryoları (Disaster Recovery) ve PITR yetenekleriyle ünlü bir diğer güçlü araçtır.

> [!IMPORTANT]
> Üretim ortamlarında `pg_dump`'a güvenmeyin. Mutlaka `PgBackRest` veya `Barman` gibi bir araç kurarak, WAL arşivlemesini aktif edin (postgresql.conf'da `archive_mode = on`). Aksi takdirde anlık çökmelerde büyük veri kayıpları yaşarsınız.
