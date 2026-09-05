-- ============================================================================
-- Betik: 02-connection-activity.sql
-- Amaç: Anlık Bağlantı Havuzu Durumu, max_connections Limiti ve Uzun Süren İşlemler
-- ============================================================================

\echo '=== 1. BAĞLANTI DURUM ÖZETİ VE LİMİT KULLANIMI ==='
WITH limit_info AS (
    SELECT setting::int AS max_conn FROM pg_settings WHERE name = 'max_connections'
),
conn_info AS (
    SELECT count(*) AS total_conn FROM pg_stat_activity
)
SELECT 
    ci.total_conn AS toplam_aktif_baglanti,
    li.max_conn AS max_connections_limiti,
    ROUND((ci.total_conn::numeric / li.max_conn) * 100, 1) AS doluluk_yuzdesi,
    li.max_conn - ci.total_conn AS kalan_baglanti_kapasitesi
FROM conn_info ci, limit_info li;

\echo ''
\echo '=== 2. BAĞLANTI DURUM DAĞILIMI (STATE SUMMARY) ==='
SELECT 
    COALESCE(state, 'arka plan / sistem') AS baglanti_durumu,
    COUNT(*) AS oturum_sayisi,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS yuzde
FROM pg_stat_activity
GROUP BY state
ORDER BY oturum_sayisi DESC;

\echo ''
\echo '=== 3. TEHLİKELİ DURUM: IDLE IN TRANSACTION OLAN OTURUMLAR (> 1 DAKİKA) ==='
-- Bu oturumlar transaction başlatıp kapatmadığı için VACUUM'u engeller ve XID yaşını ilerletir!
SELECT 
    pid,
    usename AS kullanici,
    client_addr AS istemci_ip,
    application_name AS uygulama,
    state,
    NOW() - state_change AS bekleme_suresi,
    NOW() - xact_start AS islem_omru,
    LEFT(query, 120) AS son_calisan_sorgu
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND (NOW() - state_change) > INTERVAL '1 minute'
ORDER BY bekleme_suresi DESC;

\echo ''
\echo '=== 4. ŞU ANDA EN UZUN SÜREDİR ÇALIŞAN AKTİF SORGULAR (> 10 SANİYE) ==='
SELECT 
    pid,
    usename AS kullanici,
    client_addr AS istemci_ip,
    NOW() - query_start AS calisma_suresi,
    wait_event_type,
    wait_event,
    LEFT(query, 160) AS calisan_sorgu
FROM pg_stat_activity
WHERE state = 'active'
  AND pid <> pg_backend_pid()
  AND (NOW() - query_start) > INTERVAL '10 seconds'
ORDER BY calisma_suresi DESC
LIMIT 10;

-- ============================================================================
-- DBA NOTU & EYLEM PLANI:
-- 1. max_connections %80'i aştıysa PgBouncer veya pgcat gibi bir connection 
--    pooler entegrasyonu acilen devreye alınmalıdır.
-- 2. "idle in transaction" durumunda kalan bağlantıları otomatik sonlandırmak için:
--    ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
--    SELECT pg_reload_conf();
-- ============================================================================

