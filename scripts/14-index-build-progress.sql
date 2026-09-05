-- ============================================================================
-- Betik: 14-index-build-progress.sql
-- Amaç: CREATE INDEX ve REINDEX Süreçlerinin Canlı İlerlemesini İzleme
-- ============================================================================

\echo '=== CANLI İNDEKS OLUŞTURMA (CREATE / REINDEX) İLERLEME RAPORU ==='

SELECT 
    p.pid,
    p.datname AS veritabani,
    c.relname AS tablo_adi,
    COALESCE(i.relname, 'Yeni İndeks') AS indeks_adi,
    p.command AS calisan_komut,
    p.phase AS mevcut_asama,
    p.blocks_total AS toplam_blok,
    p.blocks_done AS islenen_blok,
    ROUND((p.blocks_done::numeric / NULLIF(p.blocks_total, 0)) * 100, 1) AS blok_tamamlanma_yuzdesi,
    p.tuples_total AS toplam_satir,
    p.tuples_done AS islenen_satir,
    ROUND((p.tuples_done::numeric / NULLIF(p.tuples_total, 0)) * 100, 1) AS satir_tamamlanma_yuzdesi
FROM pg_stat_progress_create_index p
LEFT JOIN pg_class c ON c.oid = p.relid
LEFT JOIN pg_class i ON i.oid = p.index_relid;

-- ============================================================================
-- AŞAMA (PHASE) AÇIKLAMALARI:
-- 1. 'initializing': İndeks meta verileri ve katalog hazırlığı.
-- 2. 'building index: scanning table': Tablo baştan sona taranarak indeks anahtarları toplanır.
-- 3. 'building index: sorting tuples': Toplanan anahtarlar bellekte (maintenance_work_mem) sıralanır.
-- 4. 'building index: loading tuples in tree': B-Tree sayfaları doldurulur.
-- 5. 'waiting for ...': CONCURRENTLY modunda eski snapshot ve transaction'ların tamamlanması beklenir.
-- ============================================================================

