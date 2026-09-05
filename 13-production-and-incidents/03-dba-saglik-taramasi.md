# PostgreSQL DBA Günlük Sağlık Taraması (Health Check Scriptleri)

> **Bölüm Kapsamı:** Bir Veritabanı Yöneticisi'nin (DBA) veya otomatik izleme sistemlerinin her sabah veya belirli aralıklarla çalıştırıp veritabanının genel durumunu (röntgenini) çekeceği standartlaştırılmış SQL Toolkit'i.

---

## 1. Veritabanı Cache Hit Ratio (Önbellek Başarısı)

Performansın en büyük belirleyicisi diske gitmeden bellekten (RAM) okunan veri oranıdır. İdeal değer **%99 ve üzeri** olmalıdır.

```sql
SELECT 
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit)  as heap_hit,
  ROUND(sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read) + 0.0001) * 100, 2) as ratio
FROM 
  pg_statio_user_tables;
```
*Not: Eğer bu oran %95'in altındaysa, sunucuda yeterli `shared_buffers` veya RAM (OS cache) yok demektir.*

---

## 2. Kullanılmayan (Dead) İndeksler

İndeksler okumayı hızlandırır ancak yazmayı yavaşlatır. Hiç kullanılmayan indeksler sistemi yorar.

```sql
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    idx_scan AS number_of_scans
FROM
    pg_stat_user_indexes i
JOIN 
    pg_index idx ON idx.indexrelid = i.indexrelid
WHERE
    idx_scan = 0
    AND idx.indisunique IS FALSE
ORDER BY
    pg_relation_size(i.indexrelid) DESC;
```
*Çözüm: Bu listede yüksek boyutlu ve 0 scan (hiç okunmamış) indeksler varsa `DROP INDEX CONCURRENTLY` ile silinmelidir.*

---

## 3. Tablo Şişkinliği (Table Bloat) Kestirimi

PostgreSQL'de silinen/güncellenen satırlar anında diskten silinmez (Dead Tuples). Vacuum zamanında temizleyemezse tablo şişer (Bloat).

```sql
-- Gerçek bloat oranı için pgstattuple extension'ı önerilir ancak 
-- istatistiksel bloat tespiti için ölü satır sayısına bakılabilir:
SELECT 
  relname AS "Table Name", 
  n_live_tup AS "Live Tuples", 
  n_dead_tup AS "Dead Tuples", 
  ROUND((n_dead_tup::numeric / (n_live_tup + n_dead_tup + 0.0001)) * 100, 2) AS "Bloat %",
  last_autovacuum AS "Last AutoVacuum"
FROM 
  pg_stat_user_tables 
WHERE 
  n_dead_tup > 10000 
ORDER BY 
  "Bloat %" DESC;
```
*Çözüm: Bloat oranı %20'leri aşıyorsa `VACUUM ANALYZE` yapılmalı veya autovacuum ayarları agresifleştirilmelidir.*

---

## 4. İndekslenmemiş Foreign Key (Yabancı Anahtar) Tespiti

Eğer bir Foreign Key sütununda indeks yoksa, ana tablodan kayıt silindiğinde referans tablo tamamen kilitlenir (Table Scan + ShareLock). Bu, üretim ortamlarında en büyük deadlock ve yavaşlık sebeplerinden biridir.

```sql
-- İndeks eksik olan FK'leri bulma
SELECT
    c.conrelid::regclass AS table_name,
    c.conname AS foreign_key_name,
    a.attname AS column_name
FROM
    pg_constraint c
JOIN
    pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE
    c.contype = 'f'
    AND NOT EXISTS (
        SELECT 1
        FROM pg_index i
        WHERE i.indrelid = c.conrelid
          AND a.attnum = ANY(i.indkey)
    );
```
*Çözüm: Bu listede dönen tüm sütunlara uygun indeks (B-Tree) tanımlayın.*

---

## 5. Sequence Tüketim Riski (Max Value Sınırı)

`serial` veya `integer` tipindeki primary key'ler 2.1 milyar sınırına dayanabilir. Sınır dolarsa yeni veri eklenemez (Yıkıcı kesinti).

```sql
-- Sadece integer ID'li sequence'lerin doluluk oranını tespit eder
SELECT 
    s.relname AS sequence_name,
    pg_sequence_last_value(s.oid) AS current_value,
    2147483647 AS max_value, -- integer (4 byte) max değeri
    ROUND((pg_sequence_last_value(s.oid)::numeric / 2147483647) * 100, 2) AS percent_used
FROM 
    pg_class s
JOIN 
    pg_namespace n ON n.oid = s.relnamespace
WHERE 
    s.relkind = 'S'
ORDER BY 
    percent_used DESC;
```
*Çözüm: Yüzde 80 üzerine çıkan ID alanları mutlaka `BIGINT`'e taşınmalıdır.*

---

## 6. Uzun Süren ve Kilitlenen İşlemler (Long Running TX)

30 dakikadan uzun süredir çalışan ve sistemi meşgul eden sorgular:

```sql
SELECT 
    pid, 
    usename, 
    datname, 
    state, 
    current_timestamp - xact_start AS duration, 
    query 
FROM 
    pg_stat_activity 
WHERE 
    state != 'idle' 
    AND xact_start < current_timestamp - INTERVAL '30 minutes'
ORDER BY 
    duration DESC;
```
