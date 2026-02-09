# 12-PostgreSQL-Quick-Reference

Bu doküman, günlük işlemlerde hızlı referans için en sık kullanılan komutları ve sorguları içerir.

---

## 1. psql Temel Komutlar

```bash
# Bağlantı
psql -U username -d database_name -h hostname -p 5432

# Şifresiz bağlantı için .pgpass dosyası
echo "localhost:5432:*:postgres:password" > ~/.pgpass
chmod 600 ~/.pgpass
```

### Meta-Komutlar (Backslash)

| Komut | Açıklama |
|:------|:---------|
| `\l` | Veritabanlarını listele |
| `\c dbname` | Veritabanına bağlan |
| `\dt+` | Tabloları listele (boyut dahil) |
| `\di+` | İndeksleri listele |
| `\du` | Kullanıcıları listele |
| `\dn` | Şemaları listele |
| `\df` | Fonksiyonları listele |
| `\dv` | View'ları listele |
| `\d tablename` | Tablo yapısını göster |
| `\x auto` | Genişletilmiş görünüm (otomatik) |
| `\timing on` | Sorgu süresini göster |
| `\e` | Editörü aç (son sorguyu düzenle) |
| `\! command` | Shell komutu çalıştır |
| `\q` | Çıkış |

---

## 2. Sık Kullanılan Sorgular

### Veritabanı Boyutu

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) 
FROM pg_database 
ORDER BY pg_database_size(datname) DESC;
```

### Tablo Boyutları (Top 10)

```sql
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

### Aktif Bağlantılar

```sql
SELECT datname, usename, client_addr, state, query
FROM pg_stat_activity
WHERE state != 'idle';
```

### Kilitlenen Sorgular

```sql
SELECT blocked_locks.pid AS blocked_pid,
       blocking_locks.pid AS blocking_pid,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

### Index Kullanım İstatistikleri

```sql
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;
-- idx_scan = 0 olan indexler kullanılmıyor, silinebilir.
```

### Cache Hit Ratio (Hedef: >99%)

```sql
SELECT 
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit)  as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100 AS cache_hit_ratio
FROM pg_statio_user_tables;
```

---

## 3. Yedekleme ve Geri Yükleme

```bash
# Logical Backup (Custom Format)
pg_dump -U postgres -F c -f backup.dump dbname

# Geri Yükle
pg_restore -U postgres -d newdb backup.dump

# Physical Backup
pg_basebackup -h localhost -U replication_user -D /backup/base -F t -z -P

# Globals (Kullanıcılar, Roller)
pg_dumpall --globals-only > globals.sql
```

---

## 4. Performans ve Bakım

```bash
# Vakum (Manuel)
VACUUM ANALYZE tablename;

# Reindex (Concurrent - Kilitlemeden)
REINDEX INDEX CONCURRENTLY idx_name;

# Bloat Kontrolü (pg_stat_user_tables)
SELECT schemaname, tablename, n_dead_tup, n_live_tup,
       round(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_ratio
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;
```

---

## 5. Güvenlik

```sql
-- Kullanıcı oluştur
CREATE ROLE appuser WITH LOGIN PASSWORD 'securepass';

-- Yetki ver
GRANT CONNECT ON DATABASE mydb TO appuser;
GRANT USAGE ON SCHEMA public TO appuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;

-- Gelecekteki tablolar için
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO appuser;

-- Şifre değiştir
ALTER ROLE appuser WITH PASSWORD 'newpass';
```

---

## 6. Troubleshooting

### Servis Durumu

```bash
# RHEL/Rocky
systemctl status postgresql-16

# Log dosyası
tail -f /var/lib/pgsql/16/data/log/postgresql-*.log
```

### Bağlantı Sorunları

```bash
# pg_hba.conf kontrol
cat /var/lib/pgsql/16/data/pg_hba.conf

# Portu dinliyor mu?
ss -tulpn | grep 5432

# Firewall
firewall-cmd --list-all
```

### Yavaş Sorgu Tespiti (pg_stat_statements)

```sql
SELECT calls, mean_exec_time, query
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```
