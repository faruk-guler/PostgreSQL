-- ============================================================================
-- Betik: 07-index-bloat.sql
-- Amaç: B-Tree İndekslerindeki Şişkinlik (Bloat) ve Boşa Harcanan Disk Boyutunu Tespit Etme
-- ============================================================================

\echo '=== B-TREE İNDEKS BLOAT VE BOŞA GİDEN ALAN TAHMİNİ (İLK 20) ==='

WITH btree_index_atts AS (
    SELECT 
        pg_namespace.nspname,
        pg_class.relname,
        pg_class.reltuples,
        pg_class.relpages,
        pg_index.indrelid,
        pg_index.indexrelid,
        pg_index.indnatts,
        pg_index.indkey,
        (current_setting('block_size')::numeric) AS bs,
        CASE -- İndeks sayfa başlık boyutu
            WHEN version() ~ 'PostgreSQL (1[4-9]|[2-9][0-9])' THEN 32
            ELSE 24
        END AS pagehdr
    FROM pg_class
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    JOIN pg_index ON pg_index.indexrelid = pg_class.oid
    JOIN pg_am ON pg_am.oid = pg_class.relam
    WHERE pg_am.amname = 'btree' 
      AND pg_namespace.nspname NOT IN ('pg_catalog', 'information_schema')
      AND pg_class.relpages > 10 -- Çok küçük indeksleri hariç tut
),
index_bloat_calc AS (
    SELECT 
        nspname AS sema_adi,
        relname AS indeks_adi,
        bs * relpages AS toplam_indeks_boyutu_byte,
        reltuples,
        relpages,
        -- Tahmini ideal sayfa boyutu hesabı (ortalama doluluk ve sayfa başlıkları)
        CEIL((reltuples * (32 + 8)) / (bs - pagehdr)) AS tahmini_sayfa
    FROM btree_index_atts
)
SELECT 
    sema_adi,
    indeks_adi,
    pg_size_pretty(toplam_indeks_boyutu_byte::bigint) AS mevcut_boyut,
    pg_size_pretty(GREATEST(toplam_indeks_boyutu_byte - (tahmini_sayfa * 8192), 0)::bigint) AS bosa_harcanan_boyut,
    ROUND(
        (GREATEST(toplam_indeks_boyutu_byte - (tahmini_sayfa * 8192), 0)::numeric / NULLIF(toplam_indeks_boyutu_byte, 0)) * 100, 
        1
    ) AS bloat_yuzdesi
FROM index_bloat_calc
WHERE toplam_indeks_boyutu_byte > 5 * 1024 * 1024 -- En az 5 MB
ORDER BY GREATEST(toplam_indeks_boyutu_byte - (tahmini_sayfa * 8192), 0) DESC
LIMIT 20;

-- ============================================================================
-- DBA NOTU & ÇÖZÜM:
-- Bloat oranı %40'ın üzerinde olan ve yüzlerce megabayt boşa yer tutan indeksler için
-- canlı sistemi kilitlemeden yeniden inşa yöntemi uygulanmalıdır:
--
-- REINDEX INDEX CONCURRENTLY sema_adi.indeks_adi;
-- 
-- Not: CONCURRENTLY parametresi yazma kilitlerini engeller ve kesinti yapmaz.
-- ============================================================================

