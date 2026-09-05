# Barman ile Kurumsal Yedekleme ve Felaket Kurtarma (PITR)

**Barman (Backup and Recovery Manager)**, kurumsal PostgreSQL ortamları için 2ndQuadrant (EnterpriseDB) tarafından açık kaynak olarak geliştirilen, merkezi bir yedekleme ve felaket kurtarma yönetim yazılımıdır. 

Standart `pg_dump` veya lokal betiklerin aksine Barman; fiziksel blok seviyesinde tam (full) ve arttırımlı (incremental) yedekleme, sürekli WAL arşivleme, yedek saklama politikaları (retention policy) ve sıfır veri kaybı hedefiyle **Zamanda Noktaya Dönüş (Point-in-Time Recovery - PITR)** imkânı sunar.

---

## 1. Barman Mimarisi ve Çalışma Prensibi

```
┌─────────────────────────┐               ┌─────────────────────────┐
│ PostgreSQL Sunucusu     │               │ Barman Yedekleme Sunucu │
│ (192.168.10.101)        │               │ (192.168.10.200)        │
│                         │               │                         │
│  pg_receivewal / rsync  │ WAL Akışı     │  /var/lib/barman/       │
│ ───────────────────────┼──────────────►│    ├── base/            │
│                         │ (Sürekli)     │    └── incoming/ (WAL)  │
│                         │               │                         │
│  pg_basebackup / rsync  │ Base Backup   │  Katalog & Metadata     │
│ ───────────────────────┼──────────────►│  Saklama Politikaları   │
└─────────────────────────┘               └────────────┬────────────┘
                                                       │
                                  PITR Geri Yükleme    │ barman recover
                                                       ▼
                                          ┌─────────────────────────┐
                                          │ Yeni Kurtarma Sunucusu  │
                                          │ (192.168.10.105)        │
                                          └─────────────────────────┘
```

| Özellik | Açıklama |
| :--- | :--- |
| **Merkezi Yönetim** | Onlarca PostgreSQL kümesi tek bir Barman sunucusu üzerinden kataloglanıp yedeklenebilir. |
| **Sıfır Veri Kaybı (RPO ≈ 0)** | `pg_receivewal` ile streaming WAL arşivleme sayesinde sunucu tamamen yansa dahi son saniyedeki veriler Barman'da mevcuttur. |
| **Saklama Politikası (Retention)** | Eski yedekleri ve gereksiz WAL dosyalarını belirlenen süre penceresine göre (örn. 14 gün) otomatik temizler. |
| **Uzaktan PITR** | İstenilen bir tarih ve saate (`target-time`) ait durum, tek bir komutla uzaktaki yeni bir sunucuya kurulabilir. |

---

## 2. Kurulum ve Ortam Hazırlığı

Örnek IP dağılımı:
- **PostgreSQL Sunucusu:** `192.168.10.101` (`postgres` kullanıcısı)
- **Barman Sunucusu:** `192.168.10.200` (`barman` kullanıcısı)

### 2.1. Paket Kurulumu

```bash
# Barman sunucusunda (RHEL/Rocky Linux)
dnf install -y barman barman-cli rsync

# Debian / Ubuntu
apt-get install -y barman barman-cli rsync
```

### 2.2. Çift Yönlü Parolasız SSH Yetkilendirmesi

Barman ve PostgreSQL sunucuları birbirine SSH anahtarlarıyla şifresiz bağlanabilmelidir:

```bash
# 1. Barman sunucusunda: barman kullanıcısının anahtarını postgres sunucusuna aktarın
su - barman
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub postgres@192.168.10.101

# 2. PostgreSQL sunucusunda: postgres kullanıcısının anahtarını barman sunucusuna aktarın
su - postgres
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub barman@192.168.10.200
```

---

## 3. PostgreSQL Sunucu Yapılandırması

PostgreSQL tarafında WAL arşivleme ve replikasyon akışı Barman sunucusuna doğru yönlendirilir:

```ini
# /var/lib/pgsql/16/data/postgresql.conf
listen_addresses = '*'
wal_level = 'replica'
archive_mode = on
archive_command = 'rsync -a %p barman@192.168.10.200:/var/lib/barman/pg-prod/incoming/%f'
max_wal_senders = 10
max_replication_slots = 10
```

`pg_hba.conf` içerisine Barman sunucusunun erişimi tanımlanır:

```text
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    all             postgres        192.168.10.200/32       scram-sha-256
host    replication     postgres        192.168.10.200/32       scram-sha-256
```

---

## 4. Barman Yapılandırması (`barman.conf`)

Barman sunucusunda `/etc/barman.conf` global ayarları ve sunucu bloğu tanımlanır:

```ini
# /etc/barman.conf
[barman]
barman_user = barman
barman_home = /var/lib/barman
log_file = /var/log/barman/barman.log
compression = gzip
immediate_checkpoint = true
basebackup_retry_times = 3
basebackup_retry_sleep = 30
archiver = on

# --- pg-prod Veritabanı Kümesi Tanımı ---
[pg-prod]
description = "Üretim PostgreSQL Veritabanı"
ssh_command = ssh postgres@192.168.10.101
conninfo = host=192.168.10.101 user=postgres port=5432 dbname=postgres
backup_method = rsync

# 14 günlük kurtarma penceresi belirle
retention_policy_mode = auto
retention_policy = RECOVERY WINDOW OF 14 DAYS
wal_retention_policy = main
```

---

## 5. Sağlık Denetimi ve Yedekleme Operasyonları

Tüm komutlar Barman sunucusunda `barman` kullanıcısı ile çalıştırılır:

```bash
su - barman
```

### 5.1. Sistem Sağlık Denetimi (`barman check`)

Yedekleme öncesinde bağlantı, izin ve arşiv durumları kontrol edilir:

```bash
barman check pg-prod
```

Beklenen çıktı:
```text
Server pg-prod:
        PostgreSQL: OK
        superuser or standard user with backup privileges: OK
        wal_level: OK
        directories: OK
        retention policy settings: OK
        backup maximum age: OK (latest backup age: 2 hours)
        compression settings: OK
        failed backups: OK (there are 0 failed backups)
        minimum redundancy requirements: OK (have 2 backups, expected at least 1)
        ssh: OK (PostgreSQL server)
        not in recovery: OK
        archive_mode: OK
        archive_command: OK
        continuous archiving: OK
        archiver errors: OK
```

### 5.2. Manuel ve Otomatik Yedekleme

```bash
# Elle tam (base) yedek başlatma
barman backup pg-prod

# Mevcut yedekleri listeleme
barman list-backup pg-prod

# Belirli bir yedeğin ayrıntılarını sorgulama
barman show-backup pg-prod 20260904T103000
```

Otomatik zamanlanmış yedekleme için `/etc/cron.d/barman` tanımlanır:

```text
# Her gece 02:30'da tam yedek al
30 02 * * * barman [ -x /usr/bin/barman ] && /usr/bin/barman -q backup pg-prod

# Her dakika WAL arşivleme ve katalog bakımını çalıştır
*  *  * * * barman [ -x /usr/bin/barman ] && /usr/bin/barman -q cron
```

---

## 6. Felaket Anında Zamanda Noktaya Dönüş (PITR) Tatbikatı

Bir yazılımcı veya DBA yanlışlıkla saat `14:15:00`'te kritik bir tabloyu `DROP TABLE` ile uçurduğunda, Barman ile tam saat `14:14:50` anına dönülebilir:

```bash
# Hedef sunucuya (örn: 192.168.10.105) uzaktan PITR başlatma
barman recover --target-time="2026-09-04 14:14:50+03:00" \
               --remote-ssh-command="ssh postgres@192.168.10.105" \
               pg-prod \
               20260904T103000 \
               /var/lib/pgsql/16/data/
```

Bu komut:
1. İlgili tarihten önceki en güncel temel yedeği hedef sunucuya aktarır.
2. Saat `14:14:50` anına kadar olan tüm WAL segmentlerini aktarır.
3. Otomatik olarak `postgresql.auto.conf` içerisine kurtarma yönergelerini yazar:
   ```ini
   restore_command = 'cp /var/lib/pgsql/wal_restore/%f %p'
   recovery_target_time = '2026-09-04 14:14:50+03:00'
   recovery_target_action = 'promote'
   ```
4. `standby.signal` dosyasını oluşturarak PostgreSQL'i kurtarma modunda başlatmaya hazır hale getirir.
