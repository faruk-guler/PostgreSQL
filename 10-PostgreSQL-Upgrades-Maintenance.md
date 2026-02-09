# 10-PostgreSQL-Upgrades-Maintenance

Veritabanı yaşayan bir organizmadır. Bakım yapılmazsa yavaşlar, şişer ve hastalanır.

---

## 1. Upgrade Strategies (Sürüm Yükseltme)

PostgreSQL sürümleri "Major" (Ana) ve "Minor" (Ara) olarak ikiye ayrılır.

- **Minor (16.1 -> 16.2):** Sadece binary dosyaları değiştirip servisi yeniden başlatırsınız. Veri dosyaları değişmez. Kesinti süresi: Saniyeler.
- **Major (15 -> 16):** Veri dosyası formatı değişebilir. İşlem gerektirir.

### Yöntem A: pg_upgrade (Standart)

Veriyi fiziksel olarak kopyalamadan, sadece sistem tablolarını yükseltir (`--link` modu).
**Avantaj:** Terabyte'lık veritabanını dakikalar içinde yükseltir.
**Dezavantaj:** Veritabanını durdurmanız gerekir (Downtime).

```bash
# 1. Eski ve Yeni sürümleri yükle
dnf install postgresql15-server postgresql16-server

# 2. Yeni kümeyi initialize et
/usr/pgsql-16/bin/postgresql-16-setup initdb

# 3. Servisleri durdur
systemctl stop postgresql-15 postgresql-16

# 4. Yükseltmeyi başlat (Link modu ile)
/usr/pgsql-16/bin/pg_upgrade \
  -b /usr/pgsql-15/bin -B /usr/pgsql-16/bin \
  -d /var/lib/pgsql/15/data -D /var/lib/pgsql/16/data \
  --link

# 5. Yeni servisi başlat
systemctl start postgresql-16
```

### Yöntem B: Logical Replication (Kesintisiz - Zero Downtime)

Kritik sistemler için kullanılır.

1. Yeni sunucuya boş bir PostgreSQL 16 kurun.
2. Eski sunucudan (15) yeni sunucuya (16) "Logical Replication" başlatın.
3. Veriler senkronize olunca uygulamayı yeni sunucuya yönlendirin.

---

## 2. Maintenance Tasks (Rutin Bakım)

Otomatik vakum (`autovacuum`) her şeyi halletmez. DBA olarak yapmanız gerekenler:

### a. REINDEX (İndeksleri Yeniden Oluşturma)

Zamanla index dosyaları şişer ve verimsizleşir (Fragmentation).
PostgreSQL 12 ve üzeri, `REINDEX` işlemini **CONCURRENTLY** (Kilitlemeden) yapabilir.

```sql
-- Production sistemde çalışır, tabloyu kilitlemez.
REINDEX INDEX CONCURRENTLY idx_users_email;

-- Tüm şemayı onar
REINDEX SCHEMA CONCURRENTLY public;
```

### b. VACUUM FULL (Dikkat!)

Tablo çok fazla şişmişse (Bloat > %50), standart `VACUUM` diskte yer açmaz, sadece yerin tekrar kullanılmasını sağlar. Diskte yer açmak için `VACUUM FULL` gerekir.
**UYARI:** Bu komut tabloyu **Exclusive Lock** ile kilitler! Çalıştığı süre boyunca tabloya okuma/yazma yapılamaz. Sadece bakım penceresinde çalıştırın veya `pg_repack` aracı kullanın.

### c. pg_checksums (Veri Bozulması Kontrolü)

Diskte bit çürümesi (Bit rot) olup olmadığını kontrol eder.
Veritabanı kapalıyken çalıştırılır.

```bash
/usr/pgsql-16/bin/pg_checksums --check -D /var/lib/pgsql/16/data
```

Not: Eğer `initdb` sırasında checksums açılmadıysa (default kapalıdır), sonradan açmak için tüm veriyi yeniden yazmak gerekir. Production kurulumlarında mutlaka `--data-checksums` ile optimize edilmelidir.

---

## 3. İzleme Kontrol Listesi (Daily Checklist)

Sabah kahvenizi içerken kontrol etmeniz gereken kritik sorgular:

### a. Replication Lag (Standby sunucular geride mi?)

```sql
-- Primary sunucuda çalıştırın
SELECT client_addr, state, sync_state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS pending_bytes
FROM pg_stat_replication;
```

### b. Long Running Queries & Transaction ID Wraparound

```sql
-- 1 saatten uzun çalışan sorgular
SELECT pid, usename, state, now() - xact_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle' AND (now() - xact_start) > interval '1 hour';
```

### 3-2. Transaction ID Wraparound (XID Wraparound)

**Bu, production'da karşılaşabileceğiniz en tehlikeli durumdur!** Veri kaybına yol açabilir.

#### Sorun Nedir?

PostgreSQL her transaction'a 32-bit bir ID (XID) verir. 2 milyar transaction sonra sayaç sıfırlanır (wraparound) ve **eski veriler "gelecekte" görünür hale gelir** - bu da VERİ KAYBI demektir!

#### Belirtiler

```sql
-- WARNING logları
WARNING: database "mydb" must be vacuumed within 1000000 transactions
ERROR: database is not accepting commands to avoid wraparound data loss
```

Son durum: **Veritabanı READ-ONLY moduna geçer!** (Disaster!)

#### Neden Olur?

- `autovacuum` kapatılmış veya çok yavaş
- Çok uzun süren transaction'lar (`idle in transaction` state)
- Büyük tablolarda `VACUUM` hiç çalışmamış

#### Monitoring (İzleme)

```sql
-- Mevcut XID age kontrol (Kritik eşik: 200M altında olmalı)
SELECT datname, age(datfrozenxid) AS xid_age,
       pg_size_pretty(pg_database_size(datname)) AS db_size
FROM pg_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY age(datfrozenxid) DESC;

-- Tehlike seviyesi
-- 0-100M: Güvenli (Yeşil)
-- 100M-200M: Dikkat (Sarı)
-- 200M-400M: Tehlikeli (Turuncu)
-- 400M+: KRİTİK - Acil VACUUM! (Kırmızı)

-- Tablo bazında kontrol
SELECT schemaname, relname, age(relfrozenxid) AS xid_age,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname))
FROM pg_stat_all_tables
WHERE age(relfrozenxid) > 200000000
ORDER BY age(relfrozenxid) DESC
LIMIT 20;
```

#### Önleme (Prevention)

```sql
-- postgresql.conf - Otomatik freeze ayarları
autovacuum = on  # ASLA KAPATMAYIN!
autovacuum_freeze_max_age = 200000000  # Varsayılan (200M)
autovacuum_multixact_freeze_max_age = 400000000

-- Aggressive vacuum
autovacuum_vacuum_cost_limit = -1  # Sınırsız (Default: 200)
autovacuum_vacuum_scale_factor = 0.05  # Daha sık vacuum (Default: 0.2)

-- Manual freeze (acil durum)
VACUUM FREEZE;  # Yavaş ama garantili

-- Tablo bazında
VACUUM FREEZE VERBOSE users;
```

#### Acil Durum Prosedürü

Eğer database READ-ONLY'ye düştüyse:

```bash
# 1. Yeni bağlantıları engelle
echo "listen_addresses = ''" >> /var/lib/pgsql/data/postgresql.conf
systemctl reload postgresql

# 2. Tek kullanıcı moduna geç
pg_ctl stop -D /var/lib/pgsql/data
pg_ctl start -D /var/lib/pgsql/data -o "-c max_connections=1"

# 3. Superuser olarak bağlan ve FREEZE
psql -U postgres -d mydb
VACUUM FREEZE VERBOSE;

# 4. Normal mod
pg_ctl restart -D /var/lib/pgsql/data
```

> [!CAUTION]
> **En iyi önlem izlemektir!** Daily monitoring checklist'inizde XID age kontrolü mutlaka olmalı. 100M'u geçtiğinde alarm çalmalı.

```sql
-- Transaction ID yaşını kontrol et
SELECT datname, age(datfrozenxid) 
FROM pg_database 
ORDER BY age(datfrozenxid) DESC;
```

### c. Disk Usage

```sql
-- Veritabanı boyutları
SELECT datname, pg_size_pretty(pg_database_size(datname)) 
FROM pg_database 
ORDER BY pg_database_size(datname) DESC;
```
