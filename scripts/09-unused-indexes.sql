-- ============================================================================
-- Betik: 09-unused-indexes.sql
-- Amaç: Hiç Kullanılmayan (Sıfır Taranan) ve Mükerrer İndeksleri Tespit Etme
-- Tehlike: Her gereksiz indeks INSERT/UPDATE/DELETE işlemlerini dramatik yavaşlatır!
-- ============================================================================

\echo '=== 1. HİÇ KULLANILMAYAN İNDEKS LİSTESİ (Sıfır Tarananlar, PK ve Unique Hariç) ==='
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    indexrelname AS indeks_adi,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS indeks_boyutu,
    idx_scan AS taranma_sayisi,
    idx_tup_read AS okunan_satir_sayisi,
    idx_tup_fetch AS alinan_satir_sayisi
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE 0 = idx_scan
  AND NOT indisprimary -- Primary Key'leri koru
  AND NOT indisunique   -- Unique kısıtları koru
  AND pg_relation_size(i.indexrelid) > 1024 * 1024 -- 1MB üzeri
ORDER BY pg_relation_size(i.indexrelid) DESC;

\echo ''
\echo '=== 2. MÜKERRER VEYA ÖN EK (PREFIX) ÇAKIŞAN İNDEKS ANALİZİ ==='
-- Örnek: (a, b) indeksi varken ayrıca sadece (a) indeksi açılmışsa, (a) indeksi gereksizdir!
SELECT 
    indrelid::regclass AS tablo_adi,
    array_to_string(indkey, ' ') AS indeks_kolon_kodlari,
    COUNT(*) AS mukerrer_indeks_sayisi,
    string_agg(indexrelid::regclass::text, ' | ') AS cakisan_indeksler
FROM pg_index
WHERE indisvalid
GROUP BY indrelid, indkey
HAVING COUNT(*) > 1;

-- ============================================================================
-- DBA NOTU & EYLEM:
-- Sıfır taranan indeksleri kaldırmadan önce veritabanının istatistik toplama
-- süresinin (pg_stat_database.stats_reset) yeterince uzun olduğundan 
-- (en az birkaç hafta/ay, aylık raporlama döngülerini görecek kadar) emin olun.
-- 
-- Güvenli silme komutu:
-- DROP INDEX CONCURRENTLY IF EXISTS sema.indeks_adi;
-- ============================================================================

