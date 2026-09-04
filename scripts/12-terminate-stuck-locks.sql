-- ============================================================================
-- Betik: 12-terminate-stuck-locks.sql
-- Amaç: Kilit Tutan veya Donmuş Oturumları Güvenli Şekilde Sonlandırma Rehberi
-- ============================================================================

\echo '=== DİKKAT: BU BETİK MÜDAHALE VE SONLANDIRMA ARAÇLARI İÇERİR ==='

-- 1. YÖNTEM: KİBAR İPTAL (CANCEL) - Sadece çalışan sorguyu durdurur, oturumu açık tutar.
-- SELECT pg_cancel_backend(12345);

-- 2. YÖNTEM: ZORLA SONLANDIRMA (TERMINATE) - Oturumu ve bağlantıyı tamamen keser.
-- SELECT pg_terminate_backend(12345);

\echo ''
\echo '=== 10 DAKİKADAN UZUN SÜREDİR DİĞERLERİNİ BLOKLAYAN OTURUMLAR İÇİN KILL LİSTESİ ==='

SELECT 
    pid,
    usename,
    client_addr,
    NOW() - query_start AS toplam_sure,
    'SELECT pg_cancel_backend(' || pid || ');' AS kibar_iptal_komutu,
    'SELECT pg_terminate_backend(' || pid || ');' AS zorla_kesme_komutu,
    SUBSTRING(query, 1, 100) AS calisan_sorgu
FROM pg_stat_activity
WHERE pid IN (
    -- Başka en az bir oturumu bloklayan PID'ler
    SELECT DISTINCT UNNEST(pg_blocking_pids(blocked.pid))
    FROM pg_stat_activity blocked
    WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0
)
AND pid <> pg_backend_pid()
AND (NOW() - query_start) > INTERVAL '10 minutes';

-- ============================================================================
-- PROD TAVSİYESİ (OTOMATİK ÇÖZÜM):
-- Manuel oturum öldürmek yerine postgresql.conf üzerinde lock zaman aşımları
-- tanımlanmalıdır:
--
-- statement_timeout = '30s'               -- Tek bir sorgunun azami süresi
-- lock_timeout = '5s'                     -- Kilit alma sırasındaki azami bekleme
-- idle_in_transaction_session_timeout = '2min' -- Boşta kilit tutan transaction limiti
-- ============================================================================

