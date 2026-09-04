# PostgreSQL Veri Sanallaştırma ve Lakehouse Mimarisi (FDW - Foreign Data Wrappers & S3 Parquet)

Modern kurumsal mimarilerde veriler tek bir merkezde durmaz; farklı PostgreSQL veritabanlarına, mikroservislere, CSV/log dosyalarına ve AWS S3 gibi nesne depolama (Object Storage) alanlarındaki Parquet/ORC veri göletlerine (Data Lakehouse) dağılmıştır. Tüm bu verileri klasik ETL süreçleriyle tek bir yerde toplamaya çalışmak maliyetli, yavaş ve verimsizdir.

PostgreSQL, **SQL/MED (Management of External Data)** standardını uygulayan **Foreign Data Wrapper (FDW)** mimarisi sayesinde harici sistemlerdeki verileri fiziksel olarak kopyalamadan, yerel bir tabloymuş gibi doğrudan sorgulayabilen güçlü bir **Veri Federasyon Merkezi (Query Hub)** olarak çalışır.

---

## 1. FDW Mimarisi ve Çalışma Prensibi

```text
                                [Uygulama İstemcisi]
                                         |
                                         v
                         [PostgreSQL Veri Federasyon Merkezi]
                                         |
         +-------------------------------+-------------------------------+
         |                               |                               |
         v                               v                               v
   postgres_fdw                      file_fdw                     parquet_s3_fdw
         |                               |                               |
         v                               v                               v
[Uzak PG Veritabanı]            [/var/log/app.csv]            [AWS S3 / Parquet Lake]
```

PostgreSQL sorgu planlayıcısı, bir dış tabloya (Foreign Table) istek geldiğinde ilgili FDW sürücüsünü çağırır. Veri uzaktaki kaynaktan sadece ihtiyaç duyulan bloklar halinde akıtılır.

---

## 2. PostgreSQL'den PostgreSQL'e: `postgres_fdw`

Farklı sunuculardaki veya mikroservislerdeki PostgreSQL veritabanlarını birbirine bağlamak için kullanılır.

### 2.1. Sunucu ve Kullanıcı Eşleme (User Mapping) Kurulumu

```sql
-- 1. Eklentiyi aktifleştir
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- 2. Uzak sunucu tanımını yap
CREATE SERVER remote_muhasebe_server
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
    host '10.0.5.20', 
    port '5432', 
    dbname 'muhasebe_prod',
    keep_connections 'on' -- Bağlantıyı açık tutarak TCP handshake yükünü önle
);

-- 3. Yetkilendirme eşlemesi (Local kullanıcı -> Uzak kullanıcı)
CREATE USER MAPPING FOR local_db_user
SERVER remote_muhasebe_server
OPTIONS (
    user 'analiz_user', 
    password 'GizliGucluSifre123!'
);
```

### 2.2. Şemayı İçe Aktarma (IMPORT FOREIGN SCHEMA)

Uzak sunucudaki tabloları tek tek elle tanımlamak yerine topluca içeri alabilirsiniz:

```sql
CREATE SCHEMA remote_muhasebe;

IMPORT FOREIGN SCHEMA public 
LIMIT TO (faturalar, cariler)
FROM SERVER remote_muhasebe_server 
INTO remote_muhasebe;
```

Artık yerel bir tablo gibi sorgulanabilir:
```sql
SELECT c.unvan, sum(f.tutar) 
FROM remote_muhasebe.cariler c
JOIN remote_muhasebe.faturalar f ON c.id = f.cari_id
WHERE f.tarih >= '2026-01-01'
GROUP BY c.unvan;
```

---

## 3. Sorgu İletimi (Query Pushdown) ve Asenkron Yürütme

Bir FDW entegrasyonunun performansını belirleyen en kritik unsur **Query Pushdown** yeteneğidir.

* **Kötü Senaryo (Pushdown Yok):** Uzak sunucudaki 10 milyon fatura satırının tamamı ağ üzerinden yerel PostgreSQL'e çekilir ve filtreleme yerelde yapılır (Ağ kilitlenir).
* **İdeal Senaryo (Tam Pushdown):** `WHERE tarih >= '2026-01-01'` filtresi ve `SUM(tutar)` aggregate işlemi doğrudan uzak PostgreSQL sunucusunda çalıştırılır; yerel sunucuya yalnızca 5 satırlık özet sonuç döner!

### Pushdown ve Asenkron Ayarlarının Optimize Edilmesi:

```sql
ALTER SERVER remote_muhasebe_server OPTIONS (
    ADD use_remote_estimate 'true',  -- Maliyeti hesaplamak için uzak istatistikleri oku
    ADD fdw_startup_cost '100.0',
    ADD fdw_tuple_cost '0.2',
    ADD async_capable 'true'         -- Birden fazla uzak sunucuyu paralel sorgula
);
```

`EXPLAIN` çıktısında `Remote SQL: SELECT ...` ibaresini görüyorsanız, filtreler ve join'ler uzak sunucuya başarıyla pushdown edilmiş demektir.

---

## 4. Dosya Entegrasyonu: `file_fdw` ile Sıfır-ETL Log Analizi

Sunucudaki log veya CSV dosyalarını veritabanına aktarmadan (import etmeden) doğrudan SQL ile sorgulayabilirsiniz:

```sql
CREATE EXTENSION IF NOT EXISTS file_fdw;

CREATE SERVER file_server FOREIGN DATA WRAPPER file_fdw;

CREATE FOREIGN TABLE app_sistem_loglari (
    log_zamani TIMESTAMPTZ,
    log_seviyesi VARCHAR(10),
    hata_kodu VARCHAR(50),
    mesaj TEXT
) SERVER file_server
OPTIONS (
    filename '/var/log/app/error.log', 
    format 'csv', 
    delimiter ','
);

-- Doğrudan SQL ile log analizi
SELECT log_seviyesi, count(*) 
FROM app_sistem_loglari 
WHERE log_zamani >= NOW() - INTERVAL '1 hour'
GROUP BY log_seviyesi;
```

---

## 5. AWS S3 ve Parquet Veri Göleti (Data Lakehouse) Entegrasyonu

Büyük veri mimarilerinde soğuk veriler (cold data) AWS S3 veya MinIO üzerinde sıkıştırılmış kolonsal **Apache Parquet** formatında saklanır. PostgreSQL; `parquet_s3_fdw` veya **DuckDB FDW** aracılığıyla bu dosyalara doğrudan SQL ile erişebilir:

```sql
-- DuckDB FDW veya Parquet FDW tanımlaması
CREATE EXTENSION IF NOT EXISTS duckdb_fdw;

CREATE SERVER lakehouse_s3 FOREIGN DATA WRAPPER duckdb_fdw;

CREATE FOREIGN TABLE s3_tarihsel_siparisler (
    siparis_id BIGINT,
    musteri_id BIGINT,
    tutar NUMERIC,
    siparis_tarihi DATE
) SERVER lakehouse_s3
OPTIONS (
    source 's3://kurumsal-veri-golu/siparisler_*.parquet'
);

-- PostgreSQL sıcak verisi ile S3 soğuk verisini UNION ALL ile birleştirme
SELECT id, musteri_id, tutar, tarih FROM siparisler -- Canlı OLTP Tablosu (Sıcak Veri)
UNION ALL
SELECT siparis_id, musteri_id, tutar, siparis_tarihi FROM s3_tarihsel_siparisler -- S3 Parquet (Soğuk Veri);
```

---

## 6. Güvenlik ve Ağ Best Practice'leri

1. **Bağlantı Şifreleme:** Dış sunucu tanımlarında mutlaka `sslmode 'require'` veya `verify-full` parametresini kullanın.
2. **Kısıtlı Yetki:** `USER MAPPING` oluştururken uzak sunucuda asla `postgres` (superuser) hesabını kullanmayın; sadece ilgili tablolara salt okunur (`SELECT`) yetkisi olan servis hesapları tanımlayın.
3. **Zaman Aşımı Koruması:** Ağ kopmalarında yerel sorgunun kilitli kalmaması için uzak sunucuda `statement_timeout` ayarlanmalıdır.
