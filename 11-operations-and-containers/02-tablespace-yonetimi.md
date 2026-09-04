# Tablespace (Veri Depolama Alanı) Yönetimi

PostgreSQL'de **Tablespace**, veritabanı yöneticisinin, tabloların, indekslerin ve geçici nesnelerin sunucunun diskinde fiziksel olarak nerede saklanacağını (Hangi dizin/klasör) belirlemesini sağlayan mantıksal bir kavramdır.

## 1. Tablespace Neden Kullanılır?

1.  **Disk Alanı Tükenmesi:** PostgreSQL'in kurulu olduğu disk bölümü (Örn: `/var/lib/pgsql/`) dolduğunda ve diski mantıksal olarak (LVM vb.) büyütemediğinizde, sisteme yeni bir disk takıp bu diske yeni bir tablespace oluşturarak veritabanının çalışmaya devam etmesini sağlayabilirsiniz.
2.  **Performans Mimarisi (Data Placement):** Veritabanı performansını (I/O) artırmak için donanımsal optimizasyon yapılabilir:
    *   Çok sık sorgulanan (Sıcak veri - Hot Data) bir indeks veya tablo için inanılmaz hızlı bir SSD/NVMe disk bağlanır ve bir "fast_tablespace" oluşturulur.
    *   Çok nadir sorgulanan (Soğuk veri - Archive/Cold Data) ama yer kaplayan eski arşiv tabloları için yavaş ama kapasitesi çok büyük bir HDD disk (SATA) bağlanır ve bir "archive_tablespace" oluşturulur.
3.  **Geçici Dosyalar (Temp Data):** Ağır sıralama (ORDER BY) ve karma işlemleri RAM'e (work_mem) sığmadığında diskte "Temp" dosyalar oluşturur. Bu dosyaların yazılacağı tablespace'i RamDisk (Sistem RAM'inin disk gibi gösterilmesi) gibi aşırı hızlı bir birime yönlendirerek performans patlaması yaratabilirsiniz.

---

## 2. Tablespace Nasıl Oluşturulur ve Kullanılır?

Bir tablespace oluşturmak için sistemde boş bir dizin olması ve bu dizinin sahipliğinin (Owner) işletim sistemindeki `postgres` kullanıcısında olması gerekir.

```bash
# İşletim sistemi üzerinde yeni bir dizin (Örn: Hızlı diskimize mount edilen yer)
mkdir /mnt/hizli_ssd/pg_data
chown postgres:postgres /mnt/hizli_ssd/pg_data
```

```sql
-- 1. Veritabanı içinde Tablespace'i oluştur (Sadece SUPERUSER yapabilir)
CREATE TABLESPACE ssd_tablespace LOCATION '/mnt/hizli_ssd/pg_data';

-- 2. Artık tabloları ve indeksleri doğrudan bu alanda (Hızlı diskte) yaratabiliriz
CREATE TABLE urun_katalogu (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(100)
) TABLESPACE ssd_tablespace;

CREATE INDEX idx_urun_ad ON urun_katalogu(ad) TABLESPACE ssd_tablespace;
```

---

## 3. Sistem Tablespace'leri

PostgreSQL kurulum (initdb) aşamasında varsayılan olarak iki adet tablespace oluşturur. 

*   **`pg_default`:** `CREATE TABLE` komutuna özel bir tablespace verilmediğinde verilerin varsayılan olarak yazıldığı ana alandır (Genelde `/var/lib/pgsql/data` içindedir).
*   **`pg_global`:** PostgreSQL'in kendi iç işleyişini yürüttüğü sistem kataloglarının ve paylaşımlı tabloların (Örn: Rol listeleri, Veritabanı isimleri vb.) tutulduğu sistem tablespace'idir.

Sisteminizdeki mevcut Tablespace'leri görmek için:
```sql
-- psql komutu
\db

-- SQL Sorgusu
SELECT spcname, spcowner, pg_tablespace_location(oid) FROM pg_tablespace;
```

---

## 4. Verileri Taşıma (ALTER)

Önceden varsayılan alanda (pg_default) duran bir tabloyu veya indeksi sonradan başka bir tablespace'e (Yani başka bir fiziksel diske) taşıyabilirsiniz.

```sql
-- Tüm tabloyu ve içindeki verileri fiziksel olarak SSD'ye kopyala ve eskisini sil
ALTER TABLE musteriler SET TABLESPACE ssd_tablespace;

-- Bir indeksi başka diske taşı
ALTER INDEX idx_musteri_isim SET TABLESPACE ssd_tablespace;
```

> [!WARNING]
> Bir tabloyu başka bir tablespace'e taşıdığınızda (`ALTER TABLE ... SET TABLESPACE`), PostgreSQL o tabloyu tamamen kilitler (Access Exclusive Lock) ve arka planda verileri satır satır yeni klasöre kopyalamaya başlar. Çok büyük tablolarda canlı sistemler (Production) için bu işlem saatler sürebilir ve kesintiye (Downtime) neden olur. Planlı bir bakım penceresinde (Maintenance Window) yapılmalıdır.
