# 14-PostgreSQL-Monitoring-Logging

Production ortamında PostgreSQL'i izlemek (Monitoring), sorunları kullanıcılar fark etmeden tespit etmek için kritiktir. Bu doküman, modern metrik toplama ve log analizi yaklaşımlarını anlatır.

---

## 1. Prometheus + Grafana (Endüstri Standardı)

### postgres_exporter Kurulumu

`postgres_exporter`, PostgreSQL metriklerini Prometheus formatında sunan bir araçtır.

```bash
# RHEL/Rocky Linux 9
wget https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.linux-amd64.tar.gz
tar -xvf postgres_exporter-0.15.0.linux-amd64.tar.gz
mv postgres_exporter-0.15.0.linux-amd64/postgres_exporter /usr/local/bin/

# Monitoring kullanıcısı oluştur
psql -U postgres -c "CREATE ROLE postgres_exporter WITH LOGIN PASSWORD 'password';"
psql -U postgres -c "GRANT pg_monitor TO postgres_exporter;"

# Bağlantı URL'sini tanımla
export DATA_SOURCE_NAME="postgresql://postgres_exporter:password@localhost:5432/postgres?sslmode=disable"

# Exporter'ı başlat
/usr/local/bin/postgres_exporter &
```

### systemd Servisi Olarak Çalıştırma

```ini
# /etc/systemd/system/postgres_exporter.service
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target

[Service]
Type=simple
User=postgres
Environment="DATA_SOURCE_NAME=postgresql://postgres_exporter:password@localhost:5432/postgres"
ExecStart=/usr/local/bin/postgres_exporter
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now postgres_exporter
```

### Grafana Dashboard

postgres_exporter ile Prometheus entegre olduktan sonra, Grafana'da hazır bir dashboard import edin:

- Dashboard ID: **9628** (PostgreSQL Database)

---

## 2. pg_stat_* Views (System Catalog)

PostgreSQL'in kendi izleme araçları, `pg_stat_*` viewlarıdır.

### En Önemli View'lar

#### a. pg_stat_activity (Aktif Bağlantılar)

```sql
SELECT pid, usename, application_name, client_addr, state, 
       now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;
```

#### b. pg_stat_database (Veritabanı İstatistikleri)

```sql
SELECT datname, numbackends, 
       xact_commit, xact_rollback,
       blks_read, blks_hit,
       round(blks_hit::numeric / (blks_hit + blks_read) * 100, 2) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1');
```

#### c. pg_stat_user_tables (Tablo İstatistikleri)

```sql
SELECT schemaname, relname, seq_scan, idx_scan, 
       n_tup_ins, n_tup_upd, n_tup_del,
       n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;
-- seq_scan yüksek olan tablolarda index eksikliği olabilir.
```

#### d. Statistics Collection & Configuration

PostgreSQL'in query planner'ı doğru kararlar verebilmek için (index kullansam mı, hash join mi yapsam?) istatistiklere muhtaçtır.

```bash
# postgresql.conf Ayarları
track_activities = on          # pg_stat_activity (Default: on)
track_counts = on              # pg_stat_user_tables (Autovacuum için kritik!)
track_io_timing = on           # I/O sürelerini ölçer (EXPLAIN ANALYZE için)
track_functions = all          # PL/pgSQL fonksiyon istatistikleri
track_wal_io_timing = on       # WAL yazma süreleri (PG 14+)
```

**Statistics Target (Örneklem Boyutu):**

Varsayılan olarak PostgreSQL bir tablodan 100 satır örnekler. Büyük tablolarda bu yetmez.

```sql
-- Varsayılanı değiştir (Database geneli)
ALTER DATABASE mydb SET default_statistics_target = 100;  -- Default: 100

-- Tablo/Kolon bazlı (Daha yaygın)
-- Örn: 'status' kolonu çok dağılım gösteriyorsa
ALTER TABLE orders ALTER COLUMN status SET STATISTICS 1000;

-- Ayar sonrası mutlaka ANALYZE çalıştırın!
ANALYZE orders;
```

**Auto-Analyze Formülü:**

`ANALYZE` ne zaman otomatik çalışır?
`threshold + (scale_factor * table_size)`

Örn: 1 milyon satırlık tablo için (`threshold=50`, `scale_factor=0.1`):
`50 + (0.1 * 1,000,000) = 100,050` satır değiştiğinde analyze tetiklenir.

#### d. pg_stat_user_indexes (Index Kullanımı)

```sql
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexname NOT LIKE '%_pkey'
ORDER BY pg_relation_size(indexrelid) DESC;
-- Hiç kullanılmayan, diskte yer kaplayan indexler.
```

---

## 3. Logging Best Practices

### postgresql.conf Ayarları

```ini
# Log Destination
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'  # Günlük rotasyon (Pazartesi, Salı vb.)
log_rotation_age = 1d
log_rotation_size = 0

# Ne loglanmalı?
log_min_duration_statement = 1000  # 1 saniyeden uzun sorgular loglanır
log_connections = on
log_disconnections = on
log_duration = off  # Her sorgunun süresini loglama (Çok gürültü yapar)
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_lock_waits = on  # Kilitleme sorunlarını logla
log_temp_files = 0  # Geçici dosya kullanımını logla (Sort/Hash için disk kullanımı)

# Error Severity
log_min_messages = WARNING
log_min_error_statement = ERROR
```

### Log Analizi (pgBadger)

Bölüm 09'da- **PgBadger:** Logları analiz edip HTML rapor üretir (Mutlaka kullanın).

### Windows Event Log Entegrasyonu

Eğer PostgreSQL'i Windows üzerinde çalıştırıyorsanız, logları Event Viewer'da görmek için:

1. Olay kaynağını kaydet (CMD Administrator):

    ```cmd
    regsvr32 "C:\Program Files\PostgreSQL\16\lib\pgevent.dll"
    ```

2. `postgresql.conf` ayarını değiştir:

    ```ini
    log_destination = 'eventlog'
    event_source = 'PostgreSQL'
    ```

```bash
# Haftalık rapor
pgBadger -f stderr /var/lib/pgsql/16/data/log/postgresql-*.log -o /var/www/html/pgbadger/weekly_report.html

# Raporun içeriği:
# - En yavaş 50 sorgu
# - Saat bazında sorgu dağılımı
# - Checkpoint sıklığı
# - Lock wait süreleri
```

---

## 4. Alerting (Uyarı Kuralları)

Prometheus Alert Manager ile kritik durumları bildirebilirsiniz.

### Örnek Alert Kuralları (prometheus.yml)

```yaml
groups:
  - name: postgresql_alerts
    rules:
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL instance is down"
      
      - alert: HighConnectionUsage
        expr: (pg_stat_database_numbackends / pg_settings_max_connections) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Connection usage is above 80%"
      
      - alert: ReplicationLag
        expr: pg_replication_lag > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag is above 10 seconds"
```

---

## 5. Custom Metrics (Özel Metrikler)

Bazı durumlarda, iş mantığınıza özgü metrikler toplamanız gerekebilir.

### postgresql.conf ile Exporter'a Özel Sorgu Eklemek

`queries.yaml` dosyası oluşturun:

```yaml
pg_custom:
  query: "SELECT COUNT(*) AS pending_orders FROM orders WHERE status = 'pending'"
  metrics:
    - pending_orders:
        usage: "GAUGE"
        description: "Number of pending orders"
```

Exporter'ı bu dosya ile başlatın:

```bash
postgres_exporter --extend.query-path=/etc/postgres_exporter/queries.yaml
```

Artık Grafana'da `pg_custom_pending_orders` metriğini görebilirsiniz.

---

## 6. Cache Analysis (pg_buffercache)

`pg_buffercache` extension'ı, shared_buffers (RAM cache) içeriğini analiz etmenizi sağlar.

### Kurulum ve Kullanım

```sql
CREATE EXTENSION pg_buffercache;

-- Hangi tablolar RAM'de en çok yer kaplıyor?
SELECT 
    c.relname,
    COUNT(*) AS buffers,
    pg_size_pretty(COUNT(*) * 8192) AS cache_size
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;

-- Cache hit ratio (Genel)
SELECT 
    SUM(CASE WHEN usagecount > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 AS cache_hit_ratio
FROM pg_buffercache;
```

### Ne Zaman Kullanılır?

- Shared_buffers boyutunu optimize etmek istediğinizde
- Hangi tabloların "hot" (sık erişilen) olduğunu görmek için
- Cache eviction sorunlarını tespit etmek için

---

## 7. Advanced pg_stat_activity Queries

### Uzun Süren Sorguları Bul ve Sonlandır

```sql
-- 5 dakikadan uzun süren sorguları listele
SELECT 
    pid,
    now() - query_start AS duration,
    usename,
    query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;

-- Belirli bir sorguyu sonlandır
SELECT pg_terminate_backend(12345); -- PID'yi buraya yazın
```

### Idle in Transaction Sorunları

```sql
-- "Idle in transaction" durumunda 10 dakikadan fazla bekleyen bağlantılar
SELECT 
    pid,
    usename,
    application_name,
    now() - state_change AS idle_duration,
    query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '10 minutes';

-- Bunları sonlandır (Dikkatli kullanın!)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '30 minutes';
```

### Bağlantı Sayısı Kontrolü

```sql
-- Kullanıcı bazında aktif bağlantı sayısı
SELECT 
    usename,
    COUNT(*) AS connection_count,
    MAX(now() - backend_start) AS oldest_connection
FROM pg_stat_activity
GROUP BY usename
ORDER BY connection_count DESC;
```
