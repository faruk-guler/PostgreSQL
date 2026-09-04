-- ============================================================================
-- Betik: 13-vacuum-progress.sql
-- Amaç: Devam Eden VACUUM ve Autovacuum Süreçlerinin Anlık İlerlemesini İzleme
-- ============================================================================

\echo '=== CANLI VACUUM VE AUTOVACUUM İLERLEME RAPORU ==='

SELECT 
    p.pid,
    p.datname AS veritabani,
    c.relname AS tablo_adi,
    p.phase AS mevcut_asama,
    p.heap_blks_total AS toplam_heap_blok,
    p.heap_blks_scanned AS taranan_heap_blok,
    p.heap_blks_vacuumed AS temizlenen_heap_blok,
    ROUND((p.heap_blks_scanned::numeric / NULLIF(p.heap_blks_total, 0)) * 100, 1) AS heap_tarama_yuzdesi,
    p.index_vacuum_count AS tamamlanan_indeks_temizligi_sayisi,
    p.num_dead_tuples AS bulunan_olu_satir_sayisi,
    p.max_dead_tuples AS bellek_olu_satir_limiti
FROM pg_stat_progress_vacuum p
LEFT JOIN pg_class c ON c.oid = p.relid;

-- ============================================================================
-- AŞAMA (PHASE) AÇIKLAMALARI:
-- 1. 'scanning heap': Tablo sayfaları taranır ve ölü tuple'lar belleğe toplanır.
-- 2. 'vacuuming indexes': Bellek dolunca indekslerdeki ölü göstericiler silinir.
-- 3. 'vacuuming heap': Tablodaki ölü satırlar boş alan olarak işaretlenir.
-- 4. 'truncating heap': Tablonun sonundaki boş sayfalar işletim sistemine iade edilir.
-- ============================================================================

