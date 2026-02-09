# 15-PostgreSQL-Advanced-Features

PostgreSQL, standart SQL'den çok daha fazlasını sunar. Bu doküman, veritabanını bir "veri hub'ı" haline getiren ve performansı uçuran ileri özellikleri anlatır.

---

## 1. Foreign Data Wrappers (FDW)

FDW, PostgreSQL'den **harici veri kaynaklarına** (MySQL, Oracle, CSV, API vb.) SQL sorgusu atacağınız bir köprüdür.

### Kullanım Senaryosu

Bir e-ticaret siteniz var. Sipariş verileri PostgreSQL'de, ürün stok bilgileri ise MySQL'de. FDW ile her iki veritabanını tek bir JOIN'de birleştirebilirsiniz.

### Örnek: postgres_fdw (PostgreSQL'den PostgreSQL'e)

```sql
-- 1. Extension'ı aktifleştir
CREATE EXTENSION postgres_fdw;

-- 2. Uzak sunucu tanımla
CREATE SERVER remote_db
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host '192.168.1.100', port '5432', dbname 'analytics');

-- 3. Kullanıcı haritası oluştur
CREATE USER MAPPING FOR postgres
SERVER remote_db
OPTIONS (user 'remote_user', password 'remote_pass');

-- 4. Uzak tabloyu local sistem içine import et
IMPORT FOREIGN SCHEMA public
FROM SERVER remote_db
INTO public;

-- 5. Artık JOIN yapabilirsiniz
SELECT orders.id, products.name
FROM orders
JOIN products ON orders.product_id = products.id;
-- "products" tablosu aslında uzak sunucuda!
```

### Performans Notu

FDW JOIN'leri yavaş olabilir çünkü ağ gecikmesi (latency) vardır. Büyük veri setlerinde "MATERIALIZED VIEW" kullanmayı düşünün.

### Örnek: mysql_fdw (MySQL'den Veri Çekme)

```sql
-- 1. Extension kur (Önce sistem paketini yükleyin: yum install mysql_fdw_16)
CREATE EXTENSION mysql_fdw;

-- 2. MySQL sunucusunu tanımla
CREATE SERVER mysql_server
FOREIGN DATA WRAPPER mysql_fdw
OPTIONS (host '192.168.1.200', port '3306');

-- 3. Kullanıcı haritası
CREATE USER MAPPING FOR postgres
SERVER mysql_server
OPTIONS (username 'mysql_user', password 'mysql_pass');

-- 4. Tabloyu import et
IMPORT FOREIGN SCHEMA legacy_db
FROM SERVER mysql_server
INTO public;

-- Artık MySQL tablosunu PostgreSQL'de sorgulayabilirsiniz!
SELECT * FROM legacy_products WHERE price > 100;
```

### Örnek: file_fdw (CSV Dosyalarını Sorgulama)

```sql
CREATE EXTENSION file_fdw;

CREATE SERVER file_server FOREIGN DATA WRAPPER file_fdw;

-- CSV dosyasını tablo gibi kullan
CREATE FOREIGN TABLE sales_csv (
    date DATE,
    product TEXT,
    amount NUMERIC
) SERVER file_server
OPTIONS (filename '/data/sales.csv', format 'csv', header 'true');

-- Artık CSV'yi SQL ile sorgulayabilirsiniz
SELECT product, SUM(amount) FROM sales_csv GROUP BY product;
```

### FDW Performans İpuçları

- **Predicate Pushdown:** PostgreSQL, `WHERE` koşullarını uzak sunucuya gönderir (tüm veriyi çekmez).
- **use_remote_estimate:** Uzak sunucudan istatistik alarak daha iyi plan yapar.

  ```sql
  ALTER SERVER remote_db OPTIONS (ADD use_remote_estimate 'true');
  ```

---

## 2. Full Text Search (Tam Metin Arama)

Elasticsearch veya Solr yerine PostgreSQL'in yerleşik FTS'sini kullanabilirsiniz.

### Temel Kullanım

```sql
CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    title TEXT,
    body TEXT,
    search_vector tsvector
);

-- tsvector sütununu otomatik güncellemek için trigger
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := 
        setweight(to_tsvector('turkish', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('turkish', COALESCE(NEW.body, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER articles_search_update
BEFORE INSERT OR UPDATE ON articles
FOR EACH ROW EXECUTE FUNCTION update_search_vector();

-- Veri ekle
INSERT INTO articles (title, body) VALUES 
('PostgreSQL vs MySQL', 'PostgreSQL daha performanslıdır...'),
('Full Text Search Rehberi', 'Tam metin arama için Elasticsearch gerekmez...');

-- Arama yap
SELECT title FROM articles
WHERE search_vector @@ to_tsquery('turkish', 'performans');
```

### GIN Index ile Hızlandırma

```sql
CREATE INDEX idx_search ON articles USING GIN (search_vector);
-- Artık milyonlarca kayıtta bile anında arama yapar.
```

### Ranking (İlgililik Puanı)

```sql
SELECT title, ts_rank(search_vector, query) AS rank
FROM articles, to_tsquery('turkish', 'performans') query
WHERE search_vector @@ query
ORDER BY rank DESC;
```

---

## 3. Materialized Views (Materyalize Edilmiş Görünümler)

Normal VIEW, her sorgulandığında altındaki SQL'i yeniden çalıştırır. MATERIALIZED VIEW ise sonucu diskde saklar - bir tür "cache".

### Kullanım

```sql
-- Yavaş analitik sorgu
CREATE MATERIALIZED VIEW sales_summary AS
SELECT 
    DATE_TRUNC('month', order_date) AS month,
    SUM(amount) AS total_sales,
    COUNT(*) AS order_count
FROM orders
GROUP BY month;

-- İlk kez oluşturulduğunda veriler hesaplanır ve diske yazılır.
-- Artık hızlı:
SELECT * FROM sales_summary WHERE month = '2024-01-01';

-- Veriyi güncelleme (Manuel)
REFRESH MATERIALIZED VIEW sales_summary;

-- Kesintisiz güncelleme (CONCURRENTLY - Unique index gerektirir)
CREATE UNIQUE INDEX ON sales_summary (month);
REFRESH MATERIALIZED VIEW CONCURRENTLY sales_summary;
```

### Otomatik Yenileme (Cron veya pg_cron)

```sql
-- pg_cron extension ile her gece 02:00'da yenile
CREATE EXTENSION pg_cron;

SELECT cron.schedule('refresh-sales', '0 2 * * *', 
    'REFRESH MATERIALIZED VIEW CONCURRENTLY sales_summary');
```

---

## 4. Table Inheritance (Tablo Mirası)

PostgreSQL'de bir tablo diğerinden "miras alabilir" (Object-Oriented kavram).

### Kullanım Senaryosu

Bir şehirler veritabanınız var. Her şehir benzer alanlara sahip ama bazı şehirler ekstra alanlara sahip.

```sql
-- Ana tablo (Parent)
CREATE TABLE cities (
    name TEXT,
    population BIGINT,
    altitude INT
);

-- Alt tablo (Child) - Başkentler için ekstra alanlar
CREATE TABLE capitals (
    country TEXT
) INHERITS (cities);

-- Veri ekle
INSERT INTO cities VALUES ('İstanbul', 16000000, 100);
INSERT INTO capitals VALUES ('Ankara', 5500000, 900, 'Türkiye');

-- Parent tabloyu sorgula - Child satırlar da gelir
SELECT * FROM cities;
-- Hem İstanbul hem Ankara döner

-- Sadece parent tabloyu sorgula
SELECT * FROM ONLY cities;
-- Sadece İstanbul döner
```

> [!WARNING]
> Table Inheritance, modern PostgreSQL'de **önerilmez**. Bunun yerine **Partitioning** veya **JSONB** kullanın. Çünkü inheritance'ta bazı kısıtlamalar (Unique constraint) çocuk tablolara geçmez.

---

## 5. Advisory Locks (Uygulama Seviyesi Kilitler)

PostgreSQL'in row-level locklarının aksine, "advisory lock" tamamen uygulamanızın kontrolündedir. Satırlardan bağımsız, soyut bir kilittir.

### Kullanım Senaryosu

Bir cron job'ınız var ve iki sunucuda da çalışıyor. Aynı anda her ikisinin de tetiklenmesini istemiyorsunuz.

```sql
-- İşi başlatmadan önce kilit almayı dene
SELECT pg_try_advisory_lock(12345);
-- true → Kilidi aldın, işe devam et
-- false → Kilit başkasında, işten çık

-- İş bittiğinde kilidi serbest bırak
SELECT pg_advisory_unlock(12345);
```

Advisory locklar session-based'dir. Bağlantı kopunca otomatik serbest bırakılır.
