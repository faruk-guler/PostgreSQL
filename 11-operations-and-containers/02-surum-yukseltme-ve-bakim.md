# Sürüm Yükseltme ve Rutin Bakım

> **Bölüm Kapsamı:** pg_upgrade ile Hızlı Geçiş, Logical Replication ile Sıfır Kesinti ve XID Wraparound Önleme

---

## 1. Upgrade Strategies (Sürüm Yükseltme)

PostgreSQL sürümleri "Major" (Ana) ve "Minor" (Ara) olarak ikiye ayrılır.

- **Minor (16.1 -> 16.2):** Sadece binary dosyaları değiştirip servisi yeniden başlatırsınız. Veri dosyaları değişmez. Kesinti süresi: Saniyeler.
- **Major (15 -> 16):** Veri dosyası formatı değişebilir. İşlem gerektirir.

### Yöntem A: pg_upgrade (Standart ve Link Modu)

Veriyi fiziksel olarak kopyalamadan, işletim sistemindeki hard-link mekanizmasını kullanarak sadece sistem tablolarını yükseltir (`--link` modu).

- **Avantaj:** Terabaytlarca veritabanını dakikalar (hatta saniyeler) içinde yükseltir.
- **Dezavantaj:** Veritabanını durdurmanız gerekir (Downtime).

#### 1. Yükseltme Öncesi Kontroller (Pre-Flight Checks)

Gerçek yükseltmeye geçmeden önce **`--check`** parametresi ile simülasyon yapılmalıdır. Bu komut hiçbir veriyi değiştirmez, sadece uyumluluğu doğrular:

```bash
# Simülasyon (Dry-Run):
/usr/pgsql-16/bin/pg_upgrade \
  -b /usr/pgsql-15/bin -B /usr/pgsql-16/bin \
  -d /var/lib/pgsql/15/data -D /var/lib/pgsql/16/data \
  --check
```

> [!IMPORTANT]
> **Pre-Flight Kritik Kontrol Noktaları:**
> 1. **Data Checksums:** Eski kümede checksum açıksa (`data_checksums = on`), yeni küme de mutlaka `initdb -k` ile başlatılmış olmalıdır; aksi halde pg_upgrade reddedilir.
> 2. **Paylaşımlı Kütüphaneler (Shared Libraries):** Eski veritabanında `postgis`, `pg_stat_statements`, `timescaledb` gibi eklentiler varsa, bunların yeni PostgreSQL sürümü için derlenmiş paketleri (`dnf install postgis34_16`) yeni sunucuya önceden kurulmalıdır.
> 3. **Bağlantı Olmamalı:** Eski kümede hiçbir aktif işlem veya `prepared transaction` kalmamış olmalıdır.

#### 2. Yükseltmenin Yürütülmesi (`--link`)

```bash
# 1. Servisleri durdur
systemctl stop postgresql-15 postgresql-16

# 2. Link modu ile yükselt (Dosyaları kopyalamaz, hard-link yapar)
/usr/pgsql-16/bin/pg_upgrade \
  -b /usr/pgsql-15/bin -B /usr/pgsql-16/bin \
  -d /var/lib/pgsql/15/data -D /var/lib/pgsql/16/data \
  --link

# 3. Yeni servisi başlat
systemctl start postgresql-16
```

#### 3. Yükseltme Sonrası Zorunlu Adımlar (Post-Upgrade)

Yükseltme sonrası yeni kümede tablo istatistikleri boş olduğu için query planner geçici olarak kötü planlar seçebilir. Bunun önüne geçmek için 3 aşamalı analiz çalıştırılır:

```bash
# 1. Hızlıdan derine 3 aşamalı istatistik üretimi (Sorgu hızını anında toparlar):
/usr/pgsql-16/bin/vacuumdb --all --analyze-in-stages

# 2. Eski veri dosyalarını temizle (pg_upgrade tarafından üretilen script ile):
./delete_old_cluster.sh
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

### c. Transaction ID Wraparound (XID Wraparound)

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
