-- ============================================================================
-- Betik: 08-table-bloat.sql
-- Amaç: Tablolardaki Ölü Satırlar (Dead Tuples), Şişkinlik ve Autovacuum Etkinliği
-- ============================================================================

\echo '=== 1. EN ÇOK ÖLÜ SATIRA (DEAD TUPLE) SAHİP İLK 20 TABLO ==='
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    n_live_tup AS canli_satir_sayisi,
    n_dead_tup AS olu_satir_sayisi,
    ROUND((n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0)) * 100, 2) AS olu_satir_yuzdesi,
    pg_size_pretty(pg_relation_size(relid)) AS tablo_boyutu,
    last_vacuum AS son_manuel_vacuum,
    last_autovacuum AS son_autovacuum,
    last_autoanalyze AS son_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 20;

\echo ''
\echo '=== 2. AUTOVACUUM EŞİĞİNİ AŞMIŞ ANCAK HENÜZ TEMİZLENMEMİŞ TABLOLAR ==='
-- Varsayılan autovacuum formülü: 50 + (0.20 * n_live_tup)
WITH autovac_settings AS (
    SELECT 
        current_setting('autovacuum_vacuum_threshold')::numeric AS base_threshold,
        current_setting('autovacuum_vacuum_scale_factor')::numeric AS scale_factor
)
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    n_live_tup,
    n_dead_tup,
    ROUND(s.base_threshold + (s.scale_factor * n_live_tup)) AS tetiklenme_esik_degeri,
    n_dead_tup - ROUND(s.base_threshold + (s.scale_factor * n_live_tup)) AS esigi_asan_olu_satir,
    last_autovacuum
FROM pg_stat_user_tables, autovac_settings s
WHERE n_dead_tup > (s.base_threshold + (s.scale_factor * n_live_tup))
ORDER BY (n_dead_tup - (s.base_threshold + (s.scale_factor * n_live_tup))) DESC
LIMIT 15;

-- ============================================================================
-- DBA NOTU:
-- Yüksek dead tuple oranı tablonun diskte şişmesine (table bloat) ve 
-- sequential scan'lerin gereksiz yere uzamasına sebep olur.
--
-- Çözümler:
-- 1. Manuel hafif temizlik: VACUUM VERBOSE sema.tablo_adi;
-- 2. Diski işletim sistemine geri iade etmek (sıfır kesintiyle):
--    pg_repack --table sema.tablo_adi -d veritabani
-- 3. Tabloya özel autovacuum ayarı:
--    ALTER TABLE sema.tablo_adi SET (autovacuum_vacuum_scale_factor = 0.05);
-- ============================================================================

