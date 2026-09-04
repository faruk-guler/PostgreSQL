-- ============================================================================
-- Betik: 03-replication-lag.sql
-- Amaç: Streaming Replication Durumu, Gecikme (Lag) ve Slot Takibi
-- ============================================================================

\echo '=== 1. SUNUCU ROLÜ ==='
SELECT 
    CASE 
        WHEN pg_is_in_recovery() THEN 'STANDBY (REPLICA) - Salt Okunur Düğüm'
        ELSE 'PRIMARY (LEADER) - Yazılabilir Ana Düğüm'
    END AS sunucu_rolu;

\echo ''
\echo '=== 2. PRIMARY ÜZERİNDEKİ REPLICA DURUMLARI VE GECİKMELERİ ==='
SELECT 
    client_addr AS replica_ip,
    application_name AS replica_adi,
    state AS baglanti_durumu,
    sync_state AS senkron_tipi, -- async, sync, potential, quorum
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS gonderilmeyi_bekleyen_byte,
    pg_wal_lsn_diff(sent_lsn, write_lsn) AS diske_yazilmayi_bekleyen_byte,
    pg_wal_lsn_diff(write_lsn, flush_lsn) AS flush_bekleyen_byte,
    pg_wal_lsn_diff(flush_lsn, replay_lsn) AS replay_edilmeyi_bekleyen_byte,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS toplam_lag_boyutu,
    write_lag,
    flush_lag,
    replay_lag AS calisma_gecikmesi
FROM pg_stat_replication;

\echo ''
\echo '=== 3. REPLICATION SLOT DURUMLARI VE WAL BİRİKMESİ ==='
-- Aktif olmayan bir replication slot, WAL segmentlerinin silinmesini engelleyerek
-- diskin %100 dolmasına sebep olan en yaygın 1 numaralı üretim felaketidir!
SELECT 
    slot_name AS slot_adi,
    plugin AS mantiksal_eklenti,
    slot_type AS slot_tipi,
    active AS su_anda_aktif_mi,
    wal_status,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS diskte_tutulan_wal_boyutu
FROM pg_replication_slots;

\echo ''
\echo '=== 4. STANDBY DÜĞÜMDE İSENİZ: SON YAZILAN İŞLEM ZAMANI VE GECİKME ==='
SELECT 
    pg_last_wal_receive_lsn() AS alinan_son_lsn,
    pg_last_wal_replay_lsn() AS islenen_son_lsn,
    pg_last_xact_replay_timestamp() AS son_islenen_transaction_zamani,
    NOW() - pg_last_xact_replay_timestamp() AS yaklasik_gecikme_suresi
WHERE pg_is_in_recovery();

-- ============================================================================
-- DBA NOTU & EYLEM PLANI:
-- 1. `diskte_tutulan_wal_boyutu` GB'larca büyüyor ve `active = false` ise:
--    O slot terk edilmiştir. Disk dolmadan önce slot düşürülmelidir:
--    SELECT pg_drop_replication_slot('terk_edilmis_slot');
-- 2. `max_slot_wal_keep_size` parametresi (örn. 50GB) ayarlanarak slotun 
--    diski doldurması engellenebilir.
-- ============================================================================

