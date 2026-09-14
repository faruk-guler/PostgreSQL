# Yedekleme ve Kurtarma (Backup & Recovery)

> **Bölüm Kapsamı:** Mantıksal ve Fiziksel Yedekleme, PITR (Point-in-Time Recovery) ve pgBackRest

---

## 1. Logical Backups (pg_dump ve pg_dumpall)

SQL komutları (`CREATE TABLE`, `COPY`, `INSERT INTO`...) şeklinde alınan mantıksal yedektir.

- **Kullanım:** Küçük/Orta ölçekli veritabanları, majör sürüm yükseltme (Major Upgrade - örn. PG 15 -> 17), veri aktarımı veya belirli tablo/şemaları taşımak için idealdir.
- **Çalışma Prensibi ve Kilitler:** `pg_dump`, yedek almaya başladığı anda veritabanının bir anlık görüntüsünü (snapshot) tek bir `REPEATABLE READ` transaction içinde dondurur. Yedeklenecek tablolarda **`ACCESS SHARE`** kilidi talep eder. Bu kilit okuma ve yazma (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) işlemlerini **engellemez**; yalnızca tablo yapısını değiştirecek DDL (`ALTER TABLE`, `DROP TABLE`, `VACUUM FULL`) işlemlerini bekletir.
- **Dezavantaj:** Veri boyutu büyüdükçe (yüzlerce GB veya TB) veri yükleme (`RESTORE`) ve indekslerin baştan inşa süresi çok uzar. Incremental (fark) yedek alamaz.

### pg_dump Formatları ve Parametreleri

`pg_dump` varsayılan olarak verileri hızlı yükleme sağlayan `COPY` formatında üretir.

| Format | Parametre | Açıklama |
| :--- | :--- | :--- |
| **Plain Text** | `-F p` | Standart SQL metin dosyası. `psql` ile yüklenir. Sürüm kontrolüne atılabilir, ancak `pg_restore` ile seçici yüklenemez. |
| **Custom** | `-F c` | **Önerilen kurumsal format.** Otomatik sıkıştırılmış ikili (binary) formattır. Yalnızca `pg_restore` ile açılır; tablo ve şema bazında filtrelenebilir. |
| **Directory** | `-F d` | Çıktıyı bir dizin altına her tablo için ayrı dosyalar halinde yazar. `-j` parametresi ile **paralel yedekleme** destekler. |
| **Tar** | `-F t` | UNIX tar arşividir. Custom formata göre üstünlüğü yoktur, boyutu büyüktür ve paralel çalışamaz; kullanımı önerilmez. |

```bash
# 1. Custom Format ile tam veritabanı yedeği (-f veya >)
pg_dump -h localhost -U postgres -d e_commerce -F c -f /backup/ecommerce_$(date +%F).dump

# 2. Çok çekirdekli paralel yedek alma (Directory Format + 4 İş Parçacığı)
pg_dump -h localhost -U postgres -d e_commerce -F d -j 4 -f /backup/ecommerce_dir_backup

# 3. Belirli şemaları ve tabloları filtreleme (Düzenli ifade / Regex destekler)
# Sadece "crm" ve "accounting" şemaları
pg_dump -U postgres -d e_commerce -n 'crm' -n 'accounting' -F c -f /backup/crm_acc.dump

# Belirli bir tabloyu yedeğe dahil etme (-t) veya hariç tutma (-T)
pg_dump -U postgres -d e_commerce -t 'public.orders_*' -T 'public.orders_archive_*' -F c -f /backup/active_orders.dump

# 4. Geri yüklemede tabloyu baştan temizleme (-c / --clean ve --if-exists)
pg_dump -U postgres -d e_commerce -c --if-exists -F c -f /backup/clean_ecommerce.dump
```

---

### pg_dumpall: Küme Düzeyinde Mantıksal Yedek

`pg_dumpall`, kümedeki tüm veritabanlarını ve veritabanı bağımsız **global nesneleri** (kullanıcı rolleri, şifre hash'leri, yetkiler, tablespace tanımları) tek bir adımda yedekler.

> [!IMPORTANT]
> `pg_dump` kullanıcıları ve rolleri YEDEKLEMEZ! Tek bir veritabanını kurtarırken roller eksikse yükleme yetki hatalarıyla çöker. Bu yüzden global nesneleri ayrı almak zorunludur:
>
> ```bash
> # Sadece rolleri ve tablespace'leri (global nesneleri) metin olarak al
> pg_dumpall -U postgres -g > /backup/globals_$(date +%F).sql
> 
> # Ya da sadece rolleri almak için:
> pg_dumpall -U postgres -r > /backup/all_roles.sql
> 
> # Ya da sadece tablespace tanımları için:
> pg_dumpall -U postgres -t > /backup/all_tablespaces.sql
> ```
> 
> **En İyi Pratik:** `pg_dumpall` yalnızca düz metin (plain text) çıktısı verdiği için tüm kümenin büyük verisini onunla almak pratik değildir. Kurumsal yedekleme stratejisinde önce `pg_dumpall -g` ile global nesneler metin olarak saklanır; ardından her bir veritabanı `pg_dump -F c` ile ayrı ayrı sıkıştırılmış ikili formatta yedeklenir.

---

### pg_restore: Seçici ve Paralel Geri Yükleme

`-F c` veya `-F d` ile alınan yedekler `pg_restore` ile olağanüstü bir esneklikle yönetilir:

```bash
# 1. Yedeğin içindekileri yüklemeden listeleme / inceleme (-l)
pg_restore -l /backup/ecommerce.dump | less

# 2. Tam geri yükleme (-d hedef veritabanı)
pg_restore -U postgres -d new_db -v /backup/ecommerce.dump

# 3. Seçici geri yükleme: Sadece tek bir tabloyu veya şemayı yükleme
pg_restore -U postgres -d new_db -t customers /backup/ecommerce.dump
pg_restore -U postgres -d new_db -n crm /backup/ecommerce.dump

# 4. Yalnızca Şema (-s) veya Yalnızca Veri (-a) yükleme
pg_restore -U postgres -d test_db --schema-only /backup/ecommerce.dump
pg_restore -U postgres -d test_db --data-only -t customers /backup/ecommerce.dump

# 5. PARALEL RESTORE (-j): Süreyi dramatik şekilde düşürür!
# Verileri ve ardından indeksleri aynı anda birden fazla CPU iş parçacığıyla oluşturur
time pg_restore -U postgres -d new_db -j 4 /backup/ecommerce.dump
```

> [!NOTE]
> **Paralel Geri Yükleme Performans Kazancı:**
> 100 milyon satırlık bir tabloda yapılan tek iş parçacıklı (`-j 1`) geri yükleme 7 dakika 30 saniye sürerken; 4 çekirdekli bir sunucuda `-j 4` parametresiyle paralel restore yapıldığında süre 2 dakikanın altına iner.

---

## 2. Physical Backups (Fiziksel Yedekleme)

Veritabanının disk üzerindeki bloklarını ve dosyalarını (`base/`, `global/`, `pg_wal/`) bayt seviyesinde kopyalar.

### A. pg_basebackup
Canlı (Hot) çalışan veritabanında kesinti olmadan fiziksel tam yedek alır.
- **Avantaj:** Geri yükleme hızı disk I/O hızına bağlıdır; indeksleri sıfırdan hesaplamaz, doğrudan hazır açılır. Replikasyon slave kurulumunun ve PITR sürecinin temelidir.

```bash
# Standart Base Backup alma
# -h: Host, -D: Hedef klasör (boş olmalı)
# -F p: Düz dosya kopyası (veya -F t: tar formatı)
# -X stream: Yedekleme esnasında üretilen WAL dosyalarını eşzamanlı çek
# -c fast: Checkpoint'i anında tetikle (beklemesin)
# -P: İlerleme durumunu göster (Progress)
pg_basebackup -h 192.168.1.10 -U replicator -D /backup/base_$(date +%F) -F p -X stream -c fast -P
```

### B. Dosya Sistemi Seviyesinde Yedekleme (File System Level) ve Riskleri
PostgreSQL veri dizinini (`$PGDATA`) doğrudan işletim sistemi komutlarıyla (`tar`, `cp`, `rsync`) kopyalamak mümkündür; ancak çok kritik kurallar vardır:

```bash
# Tehlikeli / Yanıltıcı Yöntem (PostgreSQL çalışırken ham tar almak):
tar -czvf /tmp/corrupted_pgdata.tar.gz /var/lib/postgresql/data/ # BOZUK VERİ RİSKİ!
```

> [!CAUTION]
> **Veri Bütünlüğü Uyarısı:**
> PostgreSQL bellekteki dirty buffer'ları sürekli diske yazar. Servis canlıyken düz `tar` veya `cp` komutu çalıştırılırsa, kopyalanan dosyaların bir kısmı sayfa yazımının ortasında (torn write) yakalanır ve yedek **tutarsız (inconsistent) ve açılamaz** hale gelir.
> 
> **Doğru Uygulama:**
> 1. Ya PostgreSQL servisi tamamen durdurulmalı (`systemctl stop postgresql` - Soğuk Yedek),
> 2. Ya da `pg_backup_start('etiket')` fonksiyonu çalıştırılıp dosya kopyalaması bittikten sonra `pg_backup_stop()` çağrılmalı ve ilgili aralıktaki tüm WAL dosyaları arşivlenmelidir (pg_basebackup bunu arka planda otomatik ve güvenli yapar).

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

#### Adım 4: Kurtarma Tatbikatı ve Doğrulama (DR Drill)

Felaket senaryolarına hazır olmak için periyodik olarak ayrı bir test ortamında PITR prosedürünü uygulayın:

```ini
# postgresql.auto.conf (veya postgresql.conf)
restore_command = 'cp /backup/wal/%f %p'
recovery_target_time = '2024-05-18 14:34:59'
recovery_target_action = 'promote'
```

Servis başlatıldığında PostgreSQL WAL loglarını belirtilen hedef zamana kadar oynatacak, ardından veritabanını okuma/yazma modunda açacaktır. Log dosyasında `database system was not properly shut down; automatic recovery in progress` ve sonrasında `database system is ready to accept connections` satırlarını kontrol edin.

---

## 4. Kurumsal Yedekleme Araçları: pgBackRest vs Barman

Manuel bash scriptleri veya çıplak `pg_basebackup` yerine, kurumsal (Enterprise) ortamlarda yedekleme yaşam döngüsünü, katalog yönetimini ve PITR süreçlerini otomatikleştiren iki lider açık kaynak araç kullanılır: **pgBackRest** ve **Barman (Backup and Recovery Manager)**.

### a. pgBackRest
C diliyle sıfırdan yazılmış, olağanüstü performanslı modern endüstri standardı:
- **Delta Restore:** Geri yükleme sırasında mevcut veri dizinindeki sağlam dosyaları tekrar kopyalamaz; yalnızca değişen blokları yazar. Terabaytlarca veritabanını saatler yerine dakikalar içinde ayağa kaldırır.
- **Doğrudan Bulut Entegrasyonu:** AWS S3, Google Cloud Storage, Azure Blob gibi nesne depolarına yerel (native) ve şifreli (AES-256) olarak paralel yazar.
- **Çok İş Parçacıklı (Multi-thread):** Sıkıştırma ve transfer işlemlerini birden çok CPU çekirdeğine dağıtır.

### b. Barman (Backup and Recovery Manager)
2ndQuadrant (EDB) tarafından geliştirilen ve özellikle merkezi yedek sunucusu mimarisinde yaygın kullanılan Python tabanlı araç:
- **Merkezi Yedekleme Sunucusu:** Tek bir Barman sunucusu ağ üzerindeki onlarca farklı PostgreSQL kümesini yönetebilir.
- **İki Farklı Çalışma Modu:**
  - *Streaming Mode:* `pg_receivewal` kullanarak WAL kayıtlarını ağ üzerinden streaming replikasyon protokolüyle sıfır veri kaybıyla (`RPO=0`) anlık çeker.
  - *Rsync/SSH Mode:* SSH üzerinden rsync ve hard-link kullanarak veritabanının artımlı (incremental) kopyalarını saklar.

### c. pgBackRest vs Barman Karşılaştırması

| Özellik / Kriter | pgBackRest | Barman |
| :--- | :--- | :--- |
| **Geliştirildiği Dil** | C (En yüksek I/O performansı) | Python |
| **Delta Restore Yeteneği** | Var (Çok Hızlı) | Kısmi / Deneysel |
| **Bulut Nesne Depolama (S3/GCS/Azure)** | Doğrudan yerel entegrasyon | Eklenti / Script desteğiyle |
| **WAL Arşivleme Yöntemi** | `archive_command` ile push | `pg_receivewal` (streaming) veya SSH |
| **Yedek Doğrulama (Checksums)** | Sayfa düzeyinde tam checksum | Katalog ve dosya boyutu kontrolü |
| **Mimari Tercih** | Dedicated sunucu veya doğrudan DB node | Genellikle ayrı bir merkezi yedek sunucusu |

> [!TIP]
> **Hangi Aracı Seçmelisiniz?**
> - Veri hacminiz terabaytlar seviyesindeyse, Kubernetes/Cloud kullanıyorsanız ve kurtarma sürenizi (RTO) en aza indirmek istiyorsanız **pgBackRest** bir numaralı tercihtir.
> - On-premise veri merkezinde tek bir sunucudan çok sayıda bağımsız sanal makineyi merkezi olarak yedeklemek ve `pg_receivewal` ile streaming WAL toplamak istiyorsanız **Barman** güçlü bir alternatiftir.

---

### d. Uygulamalı pgBackRest Kurulum ve PITR Rehberi

Aşağıda **DB Sunucusu** (`192.168.1.10`) ile bağımsız **Yedek Sunucusu** (`192.168.1.20`) arasındaki üretim mimarisi adım adım verilmiştir:

#### 1. Karşılıklı Parolasız SSH Yetkilendirmesi
pgBackRest'in iki sunucu arasında güvenli veri ve komut taşıması için `postgres` sistem kullanıcısı düzeyinde anahtar tabanlı SSH gerekir:

```bash
# Hem DB hem Yedek sunucusunda 'postgres' kullanıcısıyla:
su - postgres
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# DB sunucusunun genel anahtarını Yedek sunucusuna ekleyin:
# ~/.ssh/authorized_keys dosyasının izinleri 600 olmalıdır:
chmod 600 ~/.ssh/authorized_keys
```

#### 2. `/etc/pgbackrest.conf` Yapılandırması

*Yedek Sunucusunda (`192.168.1.20`):*
```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
process-max=4
log-level-console=info
log-level-file=detail

[prod_cluster]
pg1-path=/var/lib/postgresql/16/main
pg1-host=192.168.1.10
pg1-user=postgres
```

*Veritabanı Sunucusunda (`192.168.1.10`):*
```ini
[global]
repo1-host=192.168.1.20
repo1-user=postgres
log-level-console=info

[prod_cluster]
pg1-path=/var/lib/postgresql/16/main
```

#### 3. PostgreSQL Arşivleme Ayarları (`postgresql.conf` veya `ALTER SYSTEM`)
```sql
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=prod_cluster archive-push %p';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
```
*Ayarların geçerli olması için PostgreSQL servisini yeniden başlatın (`systemctl restart postgresql`).*

#### 4. Stanza Oluşturma ve Sağlık Kontrolü
Yedek sunucusunda stanza'yı başlatıp WAL aktarım hattını test edin:

```bash
# Stanza metadata'sını oluştur
pgbackrest --stanza=prod_cluster stanza-create

# Bağlantı ve arşivleme testi (OK dönmeli)
pgbackrest --stanza=prod_cluster check
```

#### 5. Yedek Alma ve Cron Otomasyonu
```bash
# Manuel Tam (Full) Yedek:
pgbackrest --stanza=prod_cluster --type=full backup

# Cron Tanımı (/etc/cron.d/pgbackrest):
# Her Pazar gece 02:00'de Full Yedek, hafta içi Diff Yedek:
0 2 * * 0 postgres pgbackrest --stanza=prod_cluster --type=full backup
0 2 * * 1-6 postgres pgbackrest --stanza=prod_cluster --type=diff backup
```

#### 6. pgBackRest ile Felaketten Kurtarma (PITR)
Bir veri kaybı veya yanlış tablo silinmesi anında, yedek sunucusu üzerinden hedef veritabanı sunucusuna zaman hedefli geri yükleme:

```bash
# 1. DB sunucusunda PostgreSQL servisini durdurun ve veri dizinini temizleyin
systemctl stop postgresql
rm -rf /var/lib/postgresql/16/main/*

# 2. Yedek sunucusundan hedef zamana (Time Target) PITR Restore tetikleyin:
pgbackrest --stanza=prod_cluster \
  --delta \
  --type=time \
  --target="2026-09-14 12:45:00" \
  --target-action=promote \
  restore

# 3. PostgreSQL'i başlatın
systemctl start postgresql
```

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
