-- ============================================================================
-- Betik: 06-top-slow-queries.sql
-- Amaç: pg_stat_statements Kullanarak Üretim Ortamında En Maliyetli Sorguları Bulma
-- Gereksinim: shared_preload_libraries = 'pg_stat_statements' ve CREATE EXTENSION pg_stat_statements;
-- ============================================================================

\echo '=== 1. TOPLAM SÜREYE GÖRE EN ÇOK SUNUCU KAYNAĞI TÜKETEN İLK 10 SORGU ==='
SELECT 
    ROUND(total_exec_time::numeric, 2) AS toplam_sure_ms,
    calls AS cagrilma_sayisi,
    ROUND(mean_exec_time::numeric, 2) AS ortalama_sure_ms,
    ROUND(stddev_exec_time::numeric, 2) AS standart_sapma_ms,
    ROUND((100 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS toplam_yuku_payi_yuzde,
    rows AS donen_toplam_satir,
    SUBSTRING(query, 1, 150) AS sorgu_ozeti
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 10;

\echo ''
\echo '=== 2. ORTALAMA ÇALIŞMA SÜRESİ EN UZUN OLAN İLK 10 SORGU (SLOW QUERIES) ==='
SELECT 
    ROUND(mean_exec_time::numeric, 2) AS ortalama_sure_ms,
    ROUND(max_exec_time::numeric, 2) AS en_uzun_calisma_ms,
    calls AS cagrilma_sayisi,
    ROUND(total_exec_time::numeric, 2) AS toplam_sure_ms,
    SUBSTRING(query, 1, 150) AS sorgu_ozeti
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND calls > 5 -- En az 5 kez çalışmış olanlar
ORDER BY mean_exec_time DESC
LIMIT 10;

\echo ''
\echo '=== 3. EN ÇOK DİSKTEN OKUMA (I/O) YAPAN İLK 10 SORGU ==='
SELECT 
    shared_blks_read AS diskten_okunan_blok,
    shared_blks_hit AS bellekten_okunan_blok,
    ROUND(
        (shared_blks_hit::numeric / NULLIF(shared_blks_hit + shared_blks_read, 0)) * 100, 
        2
    ) AS sorgu_cache_hit_orani,
    calls AS cagrilma_sayisi,
    SUBSTRING(query, 1, 150) AS sorgu_ozeti
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY shared_blks_read DESC
LIMIT 10;

-- ============================================================================
-- DBA NOTU:
-- Bir sorgunun yürütme planını incelemek için psql içinde:
-- EXPLAIN (ANALYZE, BUFFERS, SETTINGS) <sorguyu_buraya_yapistirin>;
-- İstatistikleri sıfırlamak için:
-- SELECT pg_stat_statements_reset();
-- ============================================================================

