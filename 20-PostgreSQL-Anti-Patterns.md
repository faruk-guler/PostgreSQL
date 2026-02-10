# 20-PostgreSQL-Anti-Patterns

Uzmanlık, ne yapacağını bilmek kadar, **ne yapmayacağını** da bilmektir. İşte PostgreSQL dünyasında sıkça yapılan hatalar ve doğruları.

---

## 1. Schema Tasarımı Hataları

### ❌ Anti-Pattern: Rastgele UUID Primary Key

Primary Key olarak `UUID` (v4) kullanmak, index fragmantasyonuna (parçalanma) yol açar. Rastgele dağılan veriler, diskin farklı yerlerine sürekli yazmaya zorlar.
**✅ Doğru:** Sıralı ID kullanın (`BIGSERIAL`) veya sıralı UUID (`UUIDv7`) tercih edin.

### ❌ Anti-Pattern: NULL Değerlerin Aşırı Kullanımı

`IS NULL` veya `NOT IN (subquery)` sorguları, NULL değerlerle karşılaştığında optimizer'ı şaşırtır ve index kullanımını engeller.
**✅ Doğru:** Mümkünse `NOT NULL` kısıtlaması kullanın ve varsayılan değer (DEFAULT 0 veya '') verin.

### ❌ Anti-Pattern: TEXT yerine VARCHAR(n) Takıntısı

Diğer veritabanlarının aksine, PostgreSQL'de `VARCHAR(255)` ile `TEXT` arasında performans farkı yoktur. Hatta `TEXT` daha esnektir.
**✅ Doğru:** Limit gerekmiyorsa `TEXT` kullanın. Limit gerekiyorsa `VARCHAR(n)` kullanın ama performans için değil, veri bütünlüğü için.

### ❌ Anti-Pattern: Constraint Eksikliği

Foreign Key, Unique, Check constraint'leri "performansı düşürür" diye atlamak, veri bütünlüğünü uygulama koduna bırakmak demektir. Uygulama kodu her zaman güvenilir değildir.
**✅ Doğru:** Veritabanı seviyesinde constraint kullanın. Performans kaybı minimal, veri güvenliği maksimumdir.

```sql
-- Kötü: Constraint yok
CREATE TABLE orders (user_id INT, product_id INT);

-- İyi: Foreign Key ile veri bütünlüğü
CREATE TABLE orders (
    user_id INT REFERENCES users(id),
    product_id INT REFERENCES products(id),
    quantity INT CHECK (quantity > 0)
);
```

---

## 2. Sorgu (Query) Hataları

### ❌ Anti-Pattern: SELECT *

Tüm sütunları çekmek, TOAST verilerini (büyük metinleri) de okumak demektir. Gereksiz I/O ve ağ trafiği yaratır. Index-Only Scan şansını yok eder.
**✅ Doğru:** Sadece ihtiyacınız olan sütunları yazın. `SELECT id, name FROM users;`

### ❌ Anti-Pattern: LIMIT ... OFFSET (Pagination)

`OFFSET 1000000` dediğinizde, veritabanı o 1 milyon satırı okur ve çöpe atar. Sayfa ilerledikçe sorgu yavaşlar.
**✅ Doğru:** Keyset Pagination (Cursor based) kullanın.
`WHERE id > son_görülen_id LIMIT 20`

### ❌ Anti-Pattern: Fonksiyon İçinde Sütun Kullanımı

Indexler sütunun ham hali üzerinedir.
`WHERE YEAR(created_at) = 2024` -> Index kullanamaz (Full Table Scan).
**✅ Doğru:** Aralığa çevirin.
`WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'`

### ❌ Anti-Pattern: `count(*)` Takıntısı

`SELECT count(*) FROM table` PostgreSQL'de yavaştır (MVCC yüzünden her satırın canlı olup olmadığına bakmak zorundadır).
**✅ Doğru:** Tahmini değer yeterliyse `pg_class.reltuples` bakın. Kesin değer gerekliyse ve tablo büyükse, harici bir sayacı trigger ile güncelleyin.

### ❌ Anti-Pattern: LOWER() ile Arama

`WHERE LOWER(email) = 'user@example.com'` index kullanamaz.
**✅ Doğru:** Case-insensitive collation veya functional index kullanın.

```sql
-- Yöntem 1: Functional Index
CREATE INDEX idx_email_lower ON users (LOWER(email));
WHERE LOWER(email) = LOWER('User@Example.com');

-- Yöntem 2: CITEXT veri tipi (Case-Insensitive TEXT)
CREATE EXTENSION citext;
ALTER TABLE users ALTER COLUMN email TYPE citext;
WHERE email = 'User@Example.com';  -- Index kullanır!
```

---

## 3. İndeksleme Hataları

### ❌ Anti-Pattern: Her Sütuna Index

Indexler okumayı hızlandırır ama yazmayı (INSERT/UPDATE) yavaşlatır.
**✅ Doğru:** Sadece filtreleme (`WHERE`), sıralama (`ORDER BY`) ve birleştirme (`JOIN`) yapılan alanları indexleyin.

### ❌ Anti-Pattern: Düşük Kardinalite Index

Sadece "Kadın/Erkek" veya "Aktif/Pasif" gibi 2-3 değeri olan sütunlara B-Tree index atmanın faydası yoktur. Optimizer zaten tabloyu taramayı tercih eder.
**✅ Doğru:** Partial Index kullanın. `CREATE INDEX ON users (email) WHERE status = 'active';`

---

## 4. Konfigürasyon Hataları

### ❌ Anti-Pattern: `max_connections` = 5000

PostgreSQL'de her bağlantı RAM harcar. CPU context switch artar.
**✅ Doğru:** `max_connections` makul bir seviyede (örn: 200-500) tutun ve mutlaka **PgBouncer** kullanın.

### ❌ Anti-Pattern: VACUUM'u Kapatmak

"Sistemi yavaşlatıyor" diye autovacuum'u kapatmak intihardır. Tablolar şişer, işlem yapılamaz hale gelir (`Wraparound`).
**✅ Doğru:** Kapatmayın, **tune edin**. Daha sık ve küçük parçalar halinde çalışmasını sağlayın.

### ❌ Anti-Pattern: JIT Her Zaman İyi Değildir

PostgreSQL 12+ varsayılan olarak JIT açık gelir. Ancak çok kısa süren (OLTP) sorgularda JIT derleme süresi, sorgunun kendisinden uzun sürebilir.
**✅ Doğru:** Eğer basit sorgularınızda latency yüksekse `jit = off` deneyin veya `jit_above_cost` değerini artırın.

---

## Özet: En İyi Pratikler Listesi

1. Connection Pool kullan.
2. Transaction'ları kısa tut.
3. Application tarafında N+1 sorgu yapma.
4. Explain Analyze okumayı öğren.
5. Logları izle (`pg_stat_statements`).
6. Yedekleri (Restore testini) unutma!
