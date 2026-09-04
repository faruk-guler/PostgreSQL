-- ============================================================================
-- Betik: 05-database-sizes.sql
-- Amaç: Veritabanı, Tablo, İndeks ve TOAST Boyutlarının Detaylı Analizi
-- ============================================================================

\echo '=== 1. VERİTABANI BAZINDA DİSK KULLANIM SIRALAMASI ==='
SELECT 
    datname AS veritabani_adi,
    pg_size_pretty(pg_database_size(datname)) AS toplam_boyut,
    ROUND((pg_database_size(datname)::numeric / NULLIF(SUM(pg_database_size(datname)) OVER (), 0)) * 100, 1) AS pay_yuzdesi
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(datname) DESC;

\echo ''
\echo '=== 2. EN BÜYÜK İLK 20 TABLO VE AYRINTILI BİLEŞEN BOYUTLARI ==='
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    pg_size_pretty(pg_relation_size(relid)) AS yalin_veri_boyutu,
    pg_size_pretty(pg_indexes_size(relid)) AS toplam_indeks_boyutu,
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid) - pg_indexes_size(relid)) AS toast_boyutu,
    pg_size_pretty(pg_total_relation_size(relid)) AS genel_toplam_boyut,
    ROUND(
        (pg_indexes_size(relid)::numeric / NULLIF(pg_relation_size(relid), 0)), 
        2
    ) AS indeks_veri_orani
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;

\echo ''
\echo '=== 3. DİKKAT ÇEKEN DURUM: İNDEKSLERİ VERİSİNDEN ÇOK DAHA BÜYÜK TABLOLAR ==='
-- Eğer indeks boyutu veri boyutunun 2-3 katını aşıyorsa, aşırı indeksleme (over-indexing)
-- veya ağır indeks bloat'u (şişkinlik) olabilir!
SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    pg_size_pretty(pg_relation_size(relid)) AS veri_boyutu,
    pg_size_pretty(pg_indexes_size(relid)) AS indeks_boyutu,
    ROUND((pg_indexes_size(relid)::numeric / NULLIF(pg_relation_size(relid), 0)), 1) AS kat_orani
FROM pg_stat_user_tables
WHERE pg_relation_size(relid) > 10 * 1024 * 1024 -- 10MB üzeri tablolar
  AND (pg_indexes_size(relid)::numeric / NULLIF(pg_relation_size(relid), 0)) > 2.0
ORDER BY pg_indexes_size(relid) DESC
LIMIT 10;

\echo ''
\echo '=== 4. TABLESPACE DİSK KULLANIMLARI ==='
SELECT 
    spcname AS tablespace_adi,
    pg_size_pretty(pg_tablespace_size(oid)) AS tablespace_boyutu
FROM pg_tablespace;

