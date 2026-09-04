-- ============================================================================
-- Betik: 10-missing-indexes.sql
-- Amaç: İndeks Eksikliği Nedeniyle Ağır Sequential Scan Yapan Tabloları Bulma
-- ============================================================================

\echo '=== AĞIR SEQUENTIAL SCAN YAPAN VE İNDEKS ADAYI OLAN TABLOLAR ==='

SELECT 
    schemaname AS sema,
    relname AS tablo_adi,
    seq_scan AS sequential_scan_sayisi,
    seq_tup_read AS seq_okunan_toplam_satir,
    idx_scan AS index_scan_sayisi,
    CASE 
        WHEN (seq_scan + idx_scan) > 0 THEN
            ROUND((seq_scan::numeric / (seq_scan + idx_scan)) * 100, 1)
        ELSE 0
    END AS seq_scan_orani_yuzde,
    n_live_tup AS canli_satir_sayisi,
    pg_size_pretty(pg_relation_size(relid)) AS tablo_boyutu
FROM pg_stat_user_tables
WHERE (seq_scan + idx_scan) > 100
  AND pg_relation_size(relid) > 10 * 1024 * 1024 -- 10 MB üzeri tablolar
  AND seq_scan > idx_scan
ORDER BY seq_tup_read DESC
LIMIT 15;

-- ============================================================================
-- DBA NOTU & EYLEM:
-- Bu listede başı çeken tablolar CPU ve Disk I/O darboğazlarının ana kaynağıdır.
-- İlgili tabloya gelen sorguları pg_stat_statements'tan filtreleyip WHERE ve JOIN
-- koşullarında kullanılan sütunlara B-Tree / Composite indeks ekleyin:
--
-- CREATE INDEX CONCURRENTLY idx_tablo_kolon ON sema.tablo_adi (kolon_adi);
-- ============================================================================

