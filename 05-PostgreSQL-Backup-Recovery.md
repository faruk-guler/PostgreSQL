# 05-PostgreSQL-Backup-Recovery

Veritabanı yöneticisinin en önemli görevi veriyi korumaktır. PostgreSQL iki ana yedekleme stratejisi sunar: **Logical** (Mantıksal) ve **Physical** (Fiziksel).

---

## 1. Logical Backups (pg_dump)

SQL komutları (`CREATE TABLE`, `INSERT INTO`...) şeklinde alınan yedektir.

- **Kullanım:** Küçük/Orta ölçekli veritabanları, sürüm yükseltme (Major Upgrade) veya belirli tabloları almak için idealdir.
- **Dezavantaj:** Veri boyutu büyüdükçe (TB seviyesi) yedeği geri yüklemek (`RESTORE`) çok uzun sürer.

### pg_dump ile Yedek Alma

```bash
# Standart "Plain Text" SQL yedeği (Okunabilir ama yavaştır)
pg_dump -U postgres my_database > backup.sql

# "Custom Format" (Sıkıştırılmış, Esnek - TAVSİYE EDİLEN)
# -F c: Custom format
# -f: Output file
pg_dump -U postgres -F c -f my_database.dump my_database

# Paralel yedek için Directory format kullanın:
# -F d: Directory format
# -j 4: 4 CPU çekirdeği kullanarak paralel yedek al
pg_dump -U postgres -F d -f my_database_dir -j 4 my_database
```

### pg_restore ile Geri Yükleme

"Custom Format" yedeğin en büyük avantajı, içinden istediğiniz parçayı seçebilmenizdir.

```bash
# Tüm veritabanını geri yükle (Database önceden yaratılmış olmalı)
pg_restore -U postgres -d new_database my_database.dump

# Sadece "users" tablosunu geri yükle
pg_restore -U postgres -d new_database -t users my_database.dump

# Sadece şema yapısını (Data yok) geri yükle
pg_restore -U postgres -d new_database --schema-only my_database.dump
```

> [!WARNING]
> `pg_dump`, kullanıcıları (roles) ve grupları YEDEKLEMEZ! Bunlar "Global" nesnelerdir.
> Bunları almak için `pg_dumpall --globals-only` kullanın.

---

## 2. Physical Backups (pg_basebackup)

Veritabanı dosyalarının (`base/`, `global/`) birebir kopyasını alır.

- **Kullanım:** Büyük veritabanları, Replikasyon kurulumu ve PITR (Point-In-Time Recovery) için zorunludur.
- **Avantaj:** Geri yükleme hızı disk kopyalama hızı kadardır (Çok hızlı).

### pg_basebackup Kullanımı

```bash
# -h: Host
# -D: Destination directory (Boş olmalı)
# -F t: Format tar (Tek bir tar dosyası yerine tar'lanmış dosyalar)
# -z: Gzip compression (Sıkıştır)
# -P: Progress göster
pg_basebackup -h localhost -U replication_user -D /backup/daily_backup -F t -z -P
```

---

## 3. Point-in-Time Recovery (PITR) - Zaman Makinesi

"Dün saat 14:35:00'daki veritabanı haline geri dönmek istiyorum." dediğinizde PITR kullanılır. Bunun için **Base Backup** + **WAL Archives** (Arşivlenmiş Loglar) gerekir.

### Kurulum Adımları

#### Adım 1: Arşivlemeyi Aç (postgresql.conf)

```ini
# WAL Level Configuration
wal_level = replica             # minimal | replica | logical
# minimal: Sadece crash recovery
# replica: Streaming replication (önerilen, varsayılan)
# logical: Logical replication + CDC

# Archive Mode
archive_mode = on               # Arşivlemeyi başlat
archive_timeout = 300           # 5 dakikada bir zorla arşivle (Optional)

# Archive Command Examples
# Lokal (test için)
archive_command = 'test ! -f /backup/wal/%f && cp %p /backup/wal/%f'

# Uzak sunucuya rsync
# archive_command = 'rsync -a %p backup-server:/wal_archive/%f'

# Kompresyonlu (gzip)
# archive_command = 'gzip < %p > /backup/wal/%f.gz'

# Production (S3 ile - wal-g kullanarak)
# archive_command = 'wal-g wal-push %p'

# WAL Compression (PG 15+)
wal_compression = zstd          # on | off | pglz | lz4 | zstd
# Disk I/O azalır, CPU biraz artar (önerilen: zstd)

# WAL Segment Size (Compile-time, sadece bilgi)
# Default: 16MB (pg_controldata ile kontrol edin)
```

> [!TIP]
> **archive_command Test:** Komutunuza `|| true` ekleyerek hataları yutmayın! PostgreSQL hata alırsa arşivleme durur ve WAL segmentleri dolar.

#### Adım 2: PITR Recovery Target Options

PostgreSQL'e "nereye kadar" geri yükleme yapacağını söylersiniz.

```bash
# recovery.signal dosyası oluştur (PG 12+)
touch /var/lib/pgsql/16/data/recovery.signal

# postgresql.auto.conf veya postgresql.conf'a ekle
```

**Recovery Target Seçenekleri:**

```ini
# 1. Zamana Göre (En Yaygın)
recovery_target_time = '2024-02-09 14:35:00+03'
# Belirtilen zamana kadar replay et, sonra dur

# 2. Transaction ID'ye Göre
recovery_target_xid = '987654321'
# İlgili XID commit edilene kadar

# 3. LSN'ye Göre (Log Sequence Number - PG 10+)
recovery_target_lsn = '0/3000000'
# Belirli bir WAL konumuna kadar

# 4. Named Restore Point
recovery_target_name = 'before_migration'
# Önceden oluşturulmuş restore point:
# SELECT pg_create_restore_point('before_migration');

# 5. İlk Tutarlı Noktada Dur
recovery_target = 'immediate'
# Base backup'tan sonraki ilk tutarlı halde dur

# 6. Recovery Sonrası Davranış
recovery_target_action = 'promote'  # promote | pause | shutdown
# promote: Otomatik olarak primary'ye geç (önerilen)
# pause: Manuel müdahale için bekle
# shutdown: Kapat (manuel restart gerekir)

# 7. Recovery Timeline
recovery_target_timeline = 'latest'  # latest | 1 | 2 | 3...
# Çoklu recovery sonrası timeline seç

# 8. Inclusive/Exclusive
recovery_target_inclusive = true  # true | false
# true: Hedef transaction dahil
# false: Hariç
```

#### Adım 3: Geri Yükleme (Recovery) Senaryosu

Diyelim ki birisi yanlışlıkla `DROP TABLE customers` çalıştırdı.

**Test Senaryosu:**

```bash
# 1. Hata öncesi restore point oluştur (gelecekte kullanmak için)
psql -c "SELECT pg_create_restore_point('before_drop');"

# 2. Hata yap (test)
psql -c "DROP TABLE customers;"

# 3. PostgreSQL'i durdur
systemctl stop postgresql

# 4. Veri dizinini yedekle
mv /var/lib/pgsql/16/data /var/lib/pgsql/16/data.backup

# 5. Base backup'ı extract et
tar -xzf /backup/base_backup.tar.gz -C /var/lib/pgsql/16/data

# 6. WAL arşivini kopyala (erişilebilir olmalı)
# Eğer archive_command S3'e yazıyorsa restore_command S3'ten okur

# 7. recovery.signal + postgresql.auto.conf oluştur
touch /var/lib/pgsql/16/data/recovery.signal
cat >> /var/lib/pgsql/16/data/postgresql.auto.conf << EOF
restore_command = 'cp /backup/wal/%f %p'
recovery_target_name = 'before_drop'
recovery_target_action = 'promote'
EOF

# 8. Servisi başlat
systemctl start postgresql

# 9. Logları izle
tail -f /var/lib/pgsql/16/data/log/postgresql-*.log
# "database system is ready to accept connections" mesajını bekle

# 10. Verify
psql -c "SELECT count(*) FROM customers;"  # Tablonun geri geldiğini doğrula
```

> [!CAUTION]
> **PITR Production Checklist:**
>
> - Restore test'i mutlaka yapın (ayda bir)
> - WAL arşivinin disk dolmamasını izleyin
> - `archive_command` failure alarm kurun
> - Base backup + WAL arşivini farklı storage'larda tutun (DR için)

#### Adım 4: Recovery Testi (DR Drill)

recovery_target_time = '2024-05-18 14:34:59'

# Hedefe ulaşınca dur ve yazmaya aç

recovery_target_action = 'promote'

```

1. Servisi başlat. PostgreSQL logları oynatıp belirtilen zamanda duracak ve sistemi açacaktır.

---

## 4. Modern Yedekleme Araçları (pgBackRest)

Manuel scriptler yerine, Enterprise dünyasında standart haline gelmiş araçlar vardır. En popüleri **pgBackRest**'tir.

- **Özellikleri:** Delta restore (sadece değişen blokları geri yükler), S3 desteği, Paralel işlem, Encryption.
- Production ortamları için `pg_basebackup` yerine `pgBackRest` öğrenmeniz şiddetle tavsiye edilir.

---

## 5. Backup Verification (Yedek Doğrulama)

**Kritik Kural:** Test edilmemiş yedek, yedek değildir!

### pg_verifybackup (PostgreSQL 13+)

```bash
# Base backup'ı doğrula
pg_verifybackup /backup/daily_backup

# Çıktı:
# backup successfully verified
# veya hata mesajı
```

### Restore Testi (Aylık Yapılmalı)

```bash
# 1. Test sunucusuna geri yükle
pg_basebackup -h production_server -D /test/restore_test -U replicator -P

# 2. Test sunucusunu başlat
pg_ctl -D /test/restore_test start

# 3. Veritabanına bağlan ve kontrol et
psql -h localhost -p 5433 -U postgres -c "SELECT COUNT(*) FROM critical_table;"

# 4. Test sunucusunu durdur ve temizle
pg_ctl -D /test/restore_test stop
rm -rf /test/restore_test
```

### Backup Monitoring (pg_stat_archiver)

```sql
-- WAL arşivleme durumunu kontrol et
SELECT 
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time
FROM pg_stat_archiver;

-- failed_count > 0 ise arşivleme sorunu var!
```

### Otomatik Yedek Testi (Cron Script)

```bash
#!/bin/bash
# /usr/local/bin/test_backup.sh

BACKUP_DIR="/backup/latest"
TEST_DIR="/tmp/restore_test_$$"

# Geri yükle
pg_basebackup -h localhost -D $TEST_DIR -U replicator -P || exit 1

# Başlat
pg_ctl -D $TEST_DIR -o "-p 5433" start || exit 1

# Test sorgusu çalıştır
psql -h localhost -p 5433 -U postgres -c "SELECT 1;" || exit 1

# Temizle
pg_ctl -D $TEST_DIR stop
rm -rf $TEST_DIR

echo "Backup verification successful!"
```
