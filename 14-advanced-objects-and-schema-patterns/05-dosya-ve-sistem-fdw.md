# Dosya ve Sistem Sanallaştırma: file_fdw Rehberi

> **Bölüm Kapsamı:** `file_fdw` Eklentisi, Sunucu Dosyalarını (CSV/TSV) SQL ile Sorgulama ve PostgreSQL Log Dosyalarını SQL ile Canlı Analiz Etme

---

PostgreSQL'in en pratik özelliklerinden biri, sunucunun yerel diskinde bulunan herhangi bir CSV, TSV veya metin dosyasını veritabanına **ithal etmeden (import etmeden)**, doğrudan bir SQL tablosu gibi sorgulatabilmesidir. Bu yetenek yerleşik **`file_fdw` (Foreign Data Wrapper)** eklentisiyle sağlanır.

---

## 1. `file_fdw` Kurulumu ve Sunucu Tanımlama

`file_fdw`, PostgreSQL resmi paketleriyle birlikte gelen standart bir eklentidir:

```sql
-- 1. Eklentiyi aktifleştir (Superuser yetkisi gerekir)
CREATE EXTENSION IF NOT EXISTS file_fdw;

-- 2. file_fdw için sanal bir sunucu tanımla
CREATE SERVER file_server FOREIGN DATA WRAPPER file_fdw;
```

---

## 2. Kullanım Senaryosu 1: Harici CSV Dosyasını Canlı Tablo Olarak Sorgulama

İşletim sisteminde bir cronjob tarafından her saat güncellenen `/var/data/doviz_kurlari.csv` dosyamız olduğunu varsayalım:

```csv
tarih,para_birimi,alis,satis
2024-05-18,USD,32.25,32.35
2024-05-18,EUR,35.10,35.22
```

Bu dosyayı içeri kopyalamadan doğrudan SQL tablosu haline getirin:

```sql
CREATE FOREIGN TABLE foreign_exchange_rates (
    rate_date DATE,
    currency VARCHAR(3),
    buying_rate NUMERIC(10,4),
    selling_rate NUMERIC(10,4)
) SERVER file_server
OPTIONS (
    filename '/var/data/doviz_kurlari.csv',
    format 'csv',
    header 'true'
);
```

Artık standart bir PostgreSQL tablosu gibi sorgulayabilir, diğer tablolarınızla `JOIN` edebilirsiniz:

```sql
SELECT o.order_id, o.amount, r.selling_rate, (o.amount * r.selling_rate) AS tl_total
FROM orders o
JOIN foreign_exchange_rates r ON r.currency = 'USD'
WHERE o.currency = 'USD';
```

---

## 3. Kullanım Senaryosu 2: PostgreSQL Sunucu Loglarını SQL ile Sorgulama

PostgreSQL loglarını CSV formatında tuttuğunuzda (`log_destination = 'csvlog'`), `file_fdw` kullanarak log dosyasını anında bir tabloya dönüştürebilir ve **hataları, kilitlenmeleri ve yavaş sorguları SQL gücüyle analiz edebilirsiniz**:

### Adım 1: Yabancı Log Tablosunu Oluşturun

```sql
CREATE FOREIGN TABLE postgres_log_table (
    log_time TIMESTAMP(3) WITH TIME ZONE,
    user_name TEXT,
    database_name TEXT,
    process_id INTEGER,
    connection_from TEXT,
    session_id TEXT,
    session_line_num BIGINT,
    command_tag TEXT,
    session_start_time TIMESTAMP WITH TIME ZONE,
    virtual_transaction_id TEXT,
    transaction_id BIGINT,
    error_severity TEXT,
    sql_state_code TEXT,
    message TEXT,
    detail TEXT,
    hint TEXT,
    internal_query TEXT,
    internal_query_pos INTEGER,
    context TEXT,
    query TEXT,
    query_pos INTEGER,
    location TEXT,
    application_name TEXT,
    backend_type TEXT,
    leader_pid INTEGER,
    query_id BIGINT
) SERVER file_server
OPTIONS (
    filename '/var/lib/pgsql/16/data/log/postgresql.csv',
    format 'csv'
);
```

### Adım 2: Log Analiz Sorguları

```sql
-- En çok karşılaşılan ilk 5 hata türü
SELECT error_severity, sql_state_code, message, COUNT(*) AS occurences
FROM postgres_log_table
WHERE error_severity IN ('ERROR', 'FATAL', 'PANIC')
GROUP BY 1, 2, 3
ORDER BY occurences DESC
LIMIT 5;

-- Son 1 saat içinde çalışan ve hata veren sorgular
SELECT log_time, user_name, database_name, message, query
FROM postgres_log_table
WHERE log_time > NOW() - INTERVAL '1 hour' AND error_severity = 'ERROR';
```

---

## 4. Güvenlik ve Yetkilendirme

> [!CAUTION]
> **Superuser Güvenlik Kuralı:** `file_fdw`, sunucunun dosya sistemindeki dosyalara (`/etc/passwd` dahil) erişebilme potansiyeline sahip olduğundan:
> 1. Yabancı tablo oluşturma (`CREATE FOREIGN TABLE`) yetkisi yalnızca **Superuser** rollerine aittir.
> 2. Normal kullanıcılara sadece oluşturulmuş olan yabancı tablo üzerinde okuma (`GRANT SELECT ON foreign_table TO app_user`) yetkisi verilmelidir; asla `file_server` üzerinde doğrudan `USAGE` verilmemelidir.
