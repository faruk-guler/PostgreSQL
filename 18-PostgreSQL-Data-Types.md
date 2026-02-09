# 18-PostgreSQL-Data-Types

PostgreSQL, dünyada en zengin veri tipi çeşitliliğine sahip veritabanıdır. Bu doküman, standart INTEGER/VARCHAR'ın ötesine geçen güçlü veri tiplerini anlatır.

---

## 1. Arrays (Diziler)

PostgreSQL, sütunlarda dizi (array) saklamanıza izin verir. Bu özellik, ilişkisel modeli esnetir.

### Tanım ve Kullanım

```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    tags TEXT[],                -- Metin dizisi
    prices NUMERIC[]            -- Sayı dizisi
);

-- Veri ekleme
INSERT INTO products (name, tags, prices) 
VALUES ('Laptop', ARRAY['elektronik', 'bilgisayar'], ARRAY[5000, 4800, 4500]);

-- veya süslü parantez ile:
INSERT INTO products (name, tags) 
VALUES ('Telefon', '{"elektronik", "mobil"}');
```

### Array Operatörleri

```sql
-- @> İçerir (Contains)
SELECT * FROM products WHERE tags @> ARRAY['elektronik'];

-- && Kesişim (Overlap)
SELECT * FROM products WHERE tags && ARRAY['mobil', 'tablet'];

-- unnest() - Diziyi satırlara dönüştür
SELECT id, name, unnest(tags) AS tag FROM products;

-- array_length()
SELECT name, array_length(prices, 1) AS price_count FROM products;
```

### GIN Index ile Hızlandırma

```sql
CREATE INDEX idx_tags ON products USING GIN (tags);
```

---

## 2. UUID (Universally Unique Identifier)

Dağıtık sistemlerde çakışmayan benzersiz ID üretmek için kullanılır.

### Kullanım

```sql
-- Extension gerekli (v13+ için core'dan, öncesi için)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- veya v13+ için gen_random_uuid() kullanın (extension gerekmez)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE
);

INSERT INTO users (email) VALUES ('test@example.com');
-- id otomatik olarak: 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' gibi bir değer alır.
```

### UUID vs SERIAL

| Özellik | SERIAL/BIGSERIAL | UUID |
|:--------|:-----------------|:-----|
| Boyut | 4/8 byte | 16 byte |
| Sıralı mı? | Evet (1, 2, 3...) | Hayır (Rastgele) |
| Dağıtık uygun mu? | Hayır (Çakışır) | Evet |
| Index verimliliği | Mükemmel | İyi (v7 ile daha iyi) |

> [!TIP]
> Modern uygulamalarda **UUIDv7** (zamana dayalı, sıralı UUID) tercih edilmelidir. PostgreSQL 17+ gen_random_uuid() ile UUIDv7 döndürür.

---

## 3. Range Types (Aralık Tipleri)

Aralıkları (başlangıç-bitiş) tek bir değer olarak saklar. Rezervasyon sistemleri için mükemmeldir.

### Yerleşik Range Türleri

- `int4range` - Integer aralığı
- `numrange` - Numeric aralığı
- `tsrange` - Timestamp aralığı (zaman dilimi yok)
- `tstzrange` - Timestamp aralığı (zaman dilimi ile)
- `daterange` - Date aralığı

### Kullanım

```sql
CREATE TABLE reservations (
    id SERIAL PRIMARY KEY,
    room TEXT,
    booked_period daterange
);

INSERT INTO reservations (room, booked_period) 
VALUES ('101', '[2024-06-01, 2024-06-05)');  -- 1-4 Haziran (5 Haziran hariç)

-- Çakışma kontrolü (OVERLAPS &&)
SELECT * FROM reservations
WHERE booked_period && '[2024-06-03, 2024-06-07)';

-- Aralıkta mı? (@>)
SELECT * FROM reservations
WHERE booked_period @> '2024-06-02'::date;
```

### Exclusion Constraint (Çakışma Önleme)

```sql
-- Aynı oda için çakışan rezervasyonu engelle
ALTER TABLE reservations 
ADD CONSTRAINT no_overlap 
EXCLUDE USING gist (room WITH =, booked_period WITH &&);
```

---

### 3.1. Multiranges (PG 14+)

Bazen tek bir aralık yetmez (örneğin: "Öğle arası hariç" mesai saatleri). Eskiden bunu `array` ile yapardık, şimdi `multirange` var.

```sql
-- Toplantı odası: 09:00-12:00 VE 13:00-17:00 müsait
SELECT '{[09:00, 12:00), [13:00, 17:00)}'::tsmultirange;

-- Multirange Operatörleri
-- İçeriyor mu?
SELECT '{[09:00, 12:00), [13:00, 17:00)}'::tsmultirange @> '10:00'::timestamp; -- True
SELECT '{[09:00, 12:00), [13:00, 17:00)}'::tsmultirange @> '12:30'::timestamp; -- False

-- Birleştir (Union)
SELECT '{[10:00, 11:00)}'::tsmultirange + '{[11:00, 12:00)}'::tsmultirange;
-- Sonuç: {[10:00, 12:00)} (Otomatik birleşti)
```

---

## 4. Interval (Zaman Aralığı)

Zaman farkını (süre) temsil eder.

```sql
-- Tanım
SELECT INTERVAL '2 hours 30 minutes';
SELECT INTERVAL '1 year 3 months';

-- Hesaplama
SELECT NOW() + INTERVAL '7 days' AS next_week;
SELECT NOW() - created_at AS account_age FROM users;

-- Aralık karşılaştırması
SELECT * FROM logs WHERE created_at > NOW() - INTERVAL '24 hours';
```

---

## 5. Network Types (IP Adresleri)

### inet ve cidr

```sql
CREATE TABLE servers (
    id SERIAL PRIMARY KEY,
    name TEXT,
    ip_address INET,         -- IP adresi (host)
    network CIDR             -- Ağ bloğu
);

INSERT INTO servers (name, ip_address, network) 
VALUES ('web1', '192.168.1.100', '192.168.1.0/24');

-- Ağ içinde mi?
SELECT * FROM servers WHERE ip_address << '192.168.0.0/16';

-- Operatörler
SELECT '192.168.1.5'::inet << '192.168.1.0/24'::cidr;  -- true (İçinde)
SELECT '10.0.0.1'::inet << '192.168.0.0/16'::cidr;     -- false
```

### macaddr

```sql
CREATE TABLE devices (
    id SERIAL,
    mac macaddr
);

INSERT INTO devices (mac) VALUES ('08:00:2b:01:02:03');
```

---

## 6. Composite Types (Özel Veri Tipi)

Kendi yapılandırılmış veri tipinizi tanımlayabilirsiniz.

```sql
-- Tip tanımla
CREATE TYPE address AS (
    street TEXT,
    city TEXT,
    postal_code TEXT
);

-- Tabloda kullan
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT,
    home_address address,
    work_address address
);

INSERT INTO customers (name, home_address, work_address) VALUES (
    'Ali Veli',
    ROW('Atatürk Cad. 123', 'İstanbul', '34000'),
    ROW('İş Merkezi', 'İstanbul', '34001')
);

-- Erişim
SELECT name, (home_address).city FROM customers;
```

---

## 7. ENUM (Sabit Değer Listesi)

Sınırlı seçenek listesi için kullanılır.

```sql
CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered');

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    status order_status DEFAULT 'pending'
);

INSERT INTO orders (status) VALUES ('processing');

-- Sadece tanımlı değerler kabul edilir
INSERT INTO orders (status) VALUES ('cancelled'); -- HATA!

-- Yeni değer ekleme
ALTER TYPE order_status ADD VALUE 'cancelled' AFTER 'delivered';
```

---

## 8. JSONB Hatırlatma (Karşılaştırma)

JSON için Bölüm 04'e bakın. Kısaca:

| Özellik | JSONB | Composite Type | ENUM |
|:--------|:------|:---------------|:-----|
| Esneklik | Çok yüksek | Orta | Düşük |
| Şema zorunlu mu? | Hayır | Evet | Evet |
| Index desteği | GIN | Kısıtlı | B-Tree |
| Kullanım | Dinamik veri | Yapısal veri | Sabit listeler |

---

## 9. Generated Columns (Hesaplanmış Sütunlar)

PostgreSQL 12+ ile gelen bu özellik, bir sütunun değerinin diğer sütunlardan otomatik hesaplanmasını sağlar.

```sql
CREATE TABLE rectangles (
    width NUMERIC,
    height NUMERIC,
    -- Alan otomatik hesaplanır ve diskte saklanır (STORED)
    area NUMERIC GENERATED ALWAYS AS (width * height) STORED
);

INSERT INTO rectangles (width, height) VALUES (10, 20);
-- area sütunu otomatik olarak 200 olur.
-- area sütununa manuel INSERT yapamazsınız!
```

-- area sütununa manuel INSERT yapamazsınız!

```

**Avantajı:** Trigger yazmaktan kurtarır ve indexlenebilir.

---

## 10. Collations & Locales (Dil ve Sıralama)

Metin verilerinin nasıl sıralanacağını (Sorting) ve karşılaştırılacağını (Comparison) belirler. Özellikle Türkçe ("i" vs "ı") gibi dillerde kritiktir.

### a. ICU vs Libc

PostgreSQL 15+ ile birlikte **ICU (International Components for Unicode)** collations standart hale gelmeye başladı. `libc` (işletim sistemi kütüphanesi) version upgrade'lerinde index bozulmalarına yol açabiliyordu.

### b. Case-Insensitive (Büyük/Küçük Harf Duyarsız) Sıralama

```sql
-- "Nondeterministic" collation oluştur (PG 12+)
CREATE COLLATION case_insensitive (
    PROVIDER = icu,
    LOCALE = 'und-u-ks-level2',
    DETERMINISTIC = false
);

CREATE TABLE users (
    username TEXT COLLATE case_insensitive
);

INSERT INTO users VALUES ('Admin'), ('admin'); 
-- HATA! Unique constraint varsa 'Admin' ve 'admin' aynı kabul edilir.

-- Sorguda kullanım
SELECT * FROM users WHERE username = 'ADMIN';
-- 'Admin' text'ini bulur (LIKE veya ILIKE kullanmadan!)
```

### c. Türkçe Sıralama Sorunu

```sql
-- Varsayılan C collation'da:
-- I, i, Ş, ş sıralaması yanlıştır.

-- Doğru sıralama için:
SELECT * FROM names ORDER BY name COLLATE "tr-TR-x-icu";
```

> [!WARNING]
> **Collation Versioning:** İşletim sisteminizi güncellediğinizde `libc` versiyonu değişirse, B-Tree indexleriniz bozulabilir. PG 15+ bunu algılar ve uyarır. Çözüm: `REINDEX` veya `ICU` kullanmak.

---

## Best Practices

1. **Doğru Tipi Seçin:** Tarih için `DATE`, para için `NUMERIC(10,2)`, binary için `BYTEA` kullanın.
2. **Generated Columns:** Hesaplanabilir veriler için Application tarafı yerine veritabanı özelliğini kullanın.
3. **ENUM dikkatli kullanın:** Değer eklemek kolaydır ama silmek zordur (pg_enum'dan manuel müdahale gerekir).
4. **Array'leri aşırı kullanmayın:** Normalleştirme genellikle daha iyidir. Ancak etiketler veya küçük listeler için uygundur.
5. **UUID için v7 tercih edin:** İndex verimliliği için sıralı UUID'ler (v7) daha iyidir.
