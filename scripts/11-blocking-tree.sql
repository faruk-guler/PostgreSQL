-- ============================================================================
-- Betik: 11-blocking-tree.sql
-- Amaç: Kilit Ağacı (Lock Tree) - Hangi Oturum Kimi Kilitliyor?
-- ============================================================================

\echo '=== 1. KİLİTLENEN VE KİLİTLEYEN OTURUMLARIN AYRINTILI LİSTESİ ==='

SELECT 
    blocked_locks.pid     AS kilitlenen_pid,
    blocked_activity.usename  AS kilitlenen_kullanici,
    blocking_locks.pid    AS kilitleyen_pid,
    blocking_activity.usename AS kilitleyen_kullanici,
    blocked_activity.query    AS kilitlenen_sorgu,
    blocking_activity.query   AS kilitleyen_sorgu,
    NOW() - blocked_activity.query_start AS kilitlenme_suresi
FROM  pg_catalog.pg_locks         blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks         blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

\echo ''
\echo '=== 2. pg_blocking_pids İLE TEK SATIRDA KİLİT ENGELİ ÖZETİ ==='

SELECT 
    pid AS kilitlenen_pid,
    pg_blocking_pids(pid) AS engelleyen_pid_listesi,
    NOW() - state_change AS bekleme_suresi,
    wait_event_type,
    wait_event,
    SUBSTRING(query, 1, 120) AS bekleyen_sorgu
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

