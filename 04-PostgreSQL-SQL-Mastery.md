# 04-PostgreSQL-SQL-Mastery

PostgreSQL, "Dünyanın en gelişmiş açık kaynaklı veritabanı" unvanını sadece kararlılığıyla değil, sunduğu güçlü SQL özellikleri ve veri tipleriyle de hak eder. Bu doküman, standart SQL'in ötesine geçen özellikleri anlatır.

---

## 1. NoSQL on SQL: JSONB

PostgreSQL, MongoDB gibi NoSQL veritabanlarına olan ihtiyacı çoğu senaryoda ortadan kaldırır. `JSONB` (Binary JSON) veri tipi, veriyi sıkıştırılmış, indexlenebilir formatta saklar.

### a. Veri Saklama ve Sorgulama

```sql
-- Tablo oluştur
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    body JSONB
);

-- Veri ekle
INSERT INTO documents (body)
VALUES ('{"title": "PostgreSQL Rehberi", "tags": ["db", "sql"], "author": {"name": "Ali", "active": true}}');

-- JSON içinden veri çekme (->> metin döner, -> json nesnesi döner)
SELECT body->>'title' FROM documents WHERE body->'author'->>'name' = 'Ali';

-- @> Operatörü (Contains / İçerir) - EN HIZLI YÖNTEM
SELECT * FROM documents WHERE body @> '{"tags": ["db"]}';
```

### b. Indexing JSONB (GIN Index)

JSON sorgularını ışık hızına çıkarmak için GIN (Generalized Inverted Index) kullanılır.

```sql
CREATE INDEX idx_gin_docs ON documents USING GIN (body);
-- Artık @> operatörü index kullanır ve milyonlarca kayıt taranmaz.
```

---

## 2. Window Functions (Analitik Güç)

`GROUP BY` kullanmadan, satırları gruplayıp her satır için toplu işlemler yapmanızı sağlar. Veri analizi ve raporlama için vazgeçilmezdir.

### Örnek Senaryo: Satış Raporu

```sql
SELECT 
    department,
    employee_name,
    salary,
    -- Her departman içindeki maaş ortalaması
    AVG(salary) OVER (PARTITION BY department) as avg_dept_salary,
    -- Departman içindeki maaş sıralaması
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) as rank
FROM employees;
```

Bu özellik, önceki satırın değerine erişmek (`LAG`) veya sonraki satıra bakmak (`LEAD`) için de kullanılır (Örneğin: Aylık büyüme oranı hesaplama).

---

## 3. Common Table Expressions (CTEs)

Karmaşık `JOIN`'ler ve iç içe sorgular (Subqueries) yerine `WITH` bloğu kullanarak sorguları okunabilir hale getirin.

### a. Basit Kullanım

```sql
WITH regional_sales AS (
    SELECT region, SUM(amount) as total_sales
    FROM orders
    GROUP BY region
), 
top_regions AS (
    SELECT region
    FROM regional_sales
    WHERE total_sales > (SELECT SUM(total_sales)/10 FROM regional_sales)
)
SELECT *
FROM users
WHERE region IN (SELECT region FROM top_regions);
```

### b. Recursive CTE (Sihirli Kısım)

Hiyerarşik verileri (örneğin Kategori Ağacı veya Organizasyon Şeması) sorgulamak için kullanılır.

```sql
WITH RECURSIVE category_tree AS (
    -- Anchor member (Başlangıç noktası)
    SELECT id, name, parent_id, 1 as level
    FROM categories
    WHERE parent_id IS NULL
    
    UNION ALL
    
    -- Recursive member (Kendini çağıran kısım)
    SELECT c.id, c.name, c.parent_id, ct.level + 1
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree;
```

---

## 4. Partitioning (Bölümlendirme)

Çok büyük tabloları (milyarlarca satır) yönetilebilir, daha küçük parçalara bölme işlemidir. PostgreSQL 10 ve sonrasında "Declarative Partitioning" ile bu iş çok kolaylaşmıştır.

### a. Range Partitioning (Tarih Bazlı)

```sql
-- Ana tablo (Parent)
CREATE TABLE measurements (
    id BIGSERIAL,
    city_id INT,
    logdate DATE NOT NULL,
    temp INT
) PARTITION BY RANGE (logdate);

-- Parçaları oluştur (Child Tables)
CREATE TABLE measurements_y2023 
    PARTITION OF measurements 
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE measurements_y2024 
    PARTITION OF measurements 
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
```

### b. Partitioning Avantajları

1. **Sorgu Hızı:** `WHERE logdate = '2024-05-01'` dediğinizde, PostgreSQL sadece `measurements_y2024` tablosunu tarar (`Partition Pruning`).
2. **Bakım Kolaylığı:** Eski veriyi silmek için `DELETE` (yavaş, kilitli, bloat yaratan) komutu yerine tabloyu sistemden ayırabilirsiniz (`DETACH` ve `DROP`). Bu işlem milisaniyeler sürer.

```sql
# 2023 verisini anında sistemden kopar
ALTER TABLE measurements DETACH PARTITION measurements_y2023;
```

---

## 5. Partition Pruning (Performans Optimizasyonu)

Partition pruning, query planner'ın **gereksiz partition'ları query'den çıkarması**dır. Örneğin 10 partition varsa ama WHERE koşulu sadece 1'ini gerektiriyorsa, PostgreSQL diğer 9'unu taramaz.

### a. Pruning Etkin mi?

```sql
-- Varsayılan: ON
SHOW enable_partition_pruning;  -- on
```

### b. Pruning Nasıl Çalışır?

```sql
-- Senaryo: 12 aylık partition var (2023-01 ... 2023-12)
EXPLAIN SELECT * FROM measurements WHERE logdate = '2023-06-15';

-- Query Plan:
-- Append  (cost=...)
--   -> Seq Scan on measurements_2023_06  (actual rows=...)
-- (Diğer 11 partition pruned edildi!)
```

### c. Compile-Time vs Runtime Pruning

```sql
-- 1. Compile-Time Pruning (Sabit değer, çok hızlı)
SELECT * FROM measurements WHERE logdate = '2023-06-15';
-- Planlama sırasında 11 partition elenır

-- 2. Runtime Pruning (Parametre, biraz yavaş)
PREPARE stmt AS SELECT * FROM measurements WHERE logdate = $1;
EXECUTE stmt('2023-06-15');
-- Execution sırasında pruning olur
```

### d. Partition-Wise Join & Aggregate (PG 11+)

Her partition için ayrı JOIN/AGGREGATE yapılır, paralellik artar.

```sql
-- Partition-wise join (büyük partition'larda faydalı)
SET enable_partitionwise_join = on;

SELECT m.*, o.order_id
FROM measurements m
JOIN orders o ON m.city_id = o.city_id AND m.logdate = o.order_date;
-- Her partition ayrı ayrı join edilir (paralel)

-- Partition-wise aggregate
SET enable_partitionwise_aggregate = on;

SELECT logdate, SUM(temp) 
FROM measurements 
GROUP BY logdate;
-- Her partition'da ayrı SUM yapılır, sonra birleştirilir
```

### e. Pruning Kontrolü (EXPLAIN)

```sql
-- Pruning test
EXPLAIN (ANALYZE, BUFFERS) 
SELECT count(*) FROM measurements WHERE logdate BETWEEN '2023-01-01' AND '2023-03-31';

-- Çıktı:
-- Partitions pruned: 9  ← Sadece Q1 (3 partition) tarandı!
-- Buffers: shared hit=...
```

> [!TIP]
> **Partition key'i WHERE'de kullanın!** Eğer partition key (logdate) sorguda yoksa, tüm partition'lar taranır (pruning çalışmaz).

---

## 6. Veri Birleştirme: MERGE (UPSERT)

PostgreSQL 15 ile gelen `MERGE` komutu, karmaşık `INSERT ... ON CONFLICT` veya PL/pgSQL mantıklarını tek bir standart SQL komutuna indirger. Özellikle ETL süreçleri için çok güçlüdür.

```sql
-- Senaryo: Günlük satışları ana stok tablosuna işleme
MERGE INTO inventory i
USING daily_sales s ON i.product_id = s.product_id

-- Ürün varsa stoğu güncelle
WHEN MATCHED THEN
    UPDATE SET quantity = i.quantity - s.quantity

-- Ürün yoksa yeni kayıt aç (veya hata ver/bir şey yapma)
WHEN NOT MATCHED THEN
    INSERT (product_id, quantity)
    VALUES (s.product_id, -s.quantity);
```

---

## 7. Cursors (Büyük Veri Setlerini Parça Parça İşleme)

Cursor, milyonlarca satırlık sonucu bir anda RAM'e yüklemek yerine, satır satır veya küçük gruplar halinde işlemenizi sağlar.

### Kullanım Senaryosu

Bir raporlama scripti yazıyorsunuz ve 10 milyon satırlık sonucu işlemeniz gerekiyor. Tüm veriyi `SELECT` ile çekip RAM'e yüklerseniz sunucu çökebilir.

### Temel Kullanım

```sql
BEGIN;

-- Cursor tanımla
DECLARE my_cursor CURSOR FOR
    SELECT id, name, email FROM users WHERE status = 'active';

-- İlk 1000 satırı al
FETCH 1000 FROM my_cursor;

-- Sonraki 1000 satırı al
FETCH 1000 FROM my_cursor;

-- Cursor'ı kapat
CLOSE my_cursor;

COMMIT;
```

### Scroll Cursor (İleri-Geri Hareket)

```sql
DECLARE scroll_cursor SCROLL CURSOR FOR SELECT * FROM products;

FETCH NEXT FROM scroll_cursor;      -- Sonraki satır
FETCH PRIOR FROM scroll_cursor;     -- Önceki satır
FETCH FIRST FROM scroll_cursor;     -- İlk satır
FETCH LAST FROM scroll_cursor;      -- Son satır
FETCH ABSOLUTE 100 FROM scroll_cursor; -- 100. satır
```

### Cursor vs Array

| Özellik | Cursor | Array (ARRAY_AGG) |
|:--------|:-------|:------------------|
| Bellek kullanımı | Düşük (parça parça) | Yüksek (tümü RAM'de) |
| Performans | Yavaş (network roundtrip) | Hızlı (tek seferde) |
| Kullanım | Çok büyük veri setleri | Küçük/orta veri setleri |

> [!WARNING]
> Cursor kullanımı transaction içinde olmalıdır (`BEGIN...COMMIT`). Transaction dışında `WITH HOLD` kullanabilirsiniz ama connection kapanınca cursor kaybolur.
