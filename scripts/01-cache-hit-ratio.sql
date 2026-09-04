-- ============================================================================
-- Betik: 01-cache-hit-ratio.sql
-- Amaç: PostgreSQL Shared Buffer Cache ve Index Cache Hit Oranlarını Ölçme
-- Hedef: Üretim ortamlarında Cache Hit Ratio > %99.0 olmalıdır.
-- ============================================================================

\echo '=== GENEL VERİTABANI BUFFER CACHE HIT RATIO ==='
SELECT 
    datname AS veritabani_adi,
    blks_read AS diskten_okunan_blok,
    blks_hit AS bellekten_okunan_blok,
    ROUND(
        (blks_hit::numeric / NULLIF(blks_hit + blks_read, 0)) * 100, 
        2
    ) AS cache_hit_orani_yuzde
FROM pg_stat_database
WHERE datname = current_database();

\echo ''
\echo '=== EN ÇOK DİSK I/O YAPAN İLK 10 TABLO VE CACHE ORANLARI ==='
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    heap_blks_read AS diskten_okunan,
    heap_blks_hit AS bellekten_okunan,
    ROUND(
        (heap_blks_hit::numeric / NULLIF(heap_blks_hit + heap_blks_read, 0)) * 100, 
        2
    ) AS tablo_cache_hit_yuzde
FROM pg_statio_user_tables
WHERE (heap_blks_read + heap_blks_hit) > 1000
ORDER BY heap_blks_read DESC
LIMIT 10;

\echo ''
\echo '=== EN ÇOK DİSK I/O YAPAN İLK 10 İNDEKS VE CACHE ORANLARI ==='
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    indexrelname AS indeks_adi,
    idx_blks_read AS diskten_okunan_idx,
    idx_blks_hit AS bellekten_okunan_idx,
    ROUND(
        (idx_blks_hit::numeric / NULLIF(idx_blks_hit + idx_blks_read, 0)) * 100, 
        2
    ) AS indeks_cache_hit_yuzde
FROM pg_statio_user_indexes
WHERE (idx_blks_read + idx_blks_hit) > 1000
ORDER BY idx_blks_read DESC
LIMIT 10;

-- ============================================================================
-- DBA NOTU & EYLEM PLANI:
-- 1. Oran %95'in altındaysa: RAM yetersizliği, yetersiz shared_buffers veya 
--    eksik indeksler nedeniyle büyük tabloların Sequential Scan ile RAM'i 
--    süpürmesi söz konusu olabilir.
-- 2. Çok sık taranan tablolar için pg_prewarm eklentisiyle tablolar açılışta 
--    RAM'e ısıtılabilir (prewarm).
-- ============================================================================

