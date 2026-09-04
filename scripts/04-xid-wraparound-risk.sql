-- ============================================================================
-- Betik: 04-xid-wraparound-risk.sql
-- Amaç: Transaction ID (XID) Tüketimi ve Wraparound Felaket Riski Denetimi
-- Hedef: 2 Milyar limitine yaklaşan tabloları tespit edip acil müdahale sağlamak
-- ============================================================================

\echo '=== 1. VERİTABANI BAZINDA XID WRAPAROUND YAKLAŞMA YÜZDESİ ==='
-- 2 Milyar limite kalan mesafe kritik seviyeye (%100'e) gelirse PostgreSQL
-- veri kaybını önlemek için kendini salt-okunur (read-only) kipine kilitler!
SELECT 
    datname AS veritabani,
    age(datfrozenxid) AS en_eski_xid_yasi,
    2000000000 - age(datfrozenxid) AS wraparounda_kalan_xid_sayisi,
    ROUND((age(datfrozenxid)::numeric / 2000000000) * 100, 2) AS wraparound_riski_yuzde,
    CASE 
        WHEN (age(datfrozenxid)::numeric / 2000000000) > 0.80 THEN 'ACİL KRİTİK: HEMEN VACUUM FREEZE YAPILMALI!'
        WHEN (age(datfrozenxid)::numeric / 2000000000) > 0.50 THEN 'UYARI: Freeze yaşı yüksek'
        ELSE 'SAĞLIKLI'
    END AS durum
FROM pg_database
WHERE datallowconn
ORDER BY age(datfrozenxid) DESC;

\echo ''
\echo '=== 2. TABLO DÜZEYİNDE EN YAŞLI İLK 15 TABLO (EN ÇOK DONDURULMAYI BEKLEYENLER) ==='
SELECT 
    c.oid::regclass AS tablo_adi,
    age(c.relfrozenxid) AS tablo_xid_yasi,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS tablo_toplam_boyutu,
    ROUND((age(c.relfrozenxid)::numeric / 2000000000) * 100, 2) AS tehlike_yuzdesi,
    current_setting('autovacuum_freeze_max_age')::bigint - age(c.relfrozenxid) AS agresif_autovacuum_baslama_kalan_xid
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 't', 'm') -- Tablolar, TOAST ve Materialized View'lar
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY age(c.relfrozenxid) DESC
LIMIT 15;

\echo ''
\echo '=== 3. MULTIXACT YAŞI KONTROLÜ (pg_multixact) ==='
SELECT 
    c.oid::regclass AS tablo_adi,
    mxid_age(c.relminmxid) AS multixact_yasi,
    ROUND((mxid_age(c.relminmxid)::numeric / 2000000000) * 100, 2) AS multixact_tehlike_yuzdesi
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 't', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY mxid_age(c.relminmxid) DESC
LIMIT 10;

-- ============================================================================
-- DBA NOTU & EYLEM PLANI:
-- Yaşı 1.5 Milyarı aşan tablolar tespit edilirse, sistem kilitlenmeden önce
-- düşük trafikli bir zamanda manuel dondurma başlatılmalıdır:
-- 
-- VACUUM FREEZE VERBOSE ANALYZE public.cok_eski_tablo;
-- ============================================================================

