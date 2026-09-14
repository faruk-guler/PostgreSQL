# Yüksek Erişilebilirlik (HA) ve Streaming Replikasyon

Üretim (Production) ortamlarında tek bir veritabanı sunucusuna (Master) bel bağlamak büyük bir risktir. Donanım arızası veya ağ kesintisi yaşandığında sisteminizin kapanmaması için en az bir adet yedek sunucu (Standby/Replica) bulundurulmalıdır.

PostgreSQL'de yüksek erişilebilirlik, **Streaming Replication (Akış Replikasyonu)** mimarisi üzerine kurulur. Bu özellik PostgreSQL 9.0 ile gelmiştir. Buna ek olarak:
- **9.1**: Synchronous replication
- **9.2**: Cascading replication
- **9.3**: Timeline switch following
- **9.5**: Replication slots ve timed delay standbys

---

## 1. Streaming Replication Nasıl Çalışır?

PostgreSQL'de her `INSERT`, `UPDATE`, `DELETE` işlemi önce RAM'e, ardından diske **WAL (Write-Ahead Log)** adlı bir işlem günlüğü dosyasına yazılır. 

Streaming Replication mantığı basittir: Master sunucu üzerinde üretilen WAL dosyaları, anlık olarak ağ üzerinden Standby sunucuya gönderilir (Stream edilir). Standby sunucu bu logları alır ve sanki sorgular kendi üzerinde çalışmış gibi birebir aynı işlemleri (Replay) uygular.

*   **Master Sunucu (Primary):** Okuma ve Yazma (Read/Write) yapılabilen ana sunucudur.
*   **Standby Sunucu (Replica):** Sadece okuma (Read-Only) yapılabilen kopyadır (Hot Standby özelliği açıksa).

### Replikasyon Türleri
*   **Asynchronous (Asenkron) Replikasyon:** Master sorguyu çalıştırır, istemciye "Başarılı" döner, WAL dosyasını arkadan gönderir. Çok hızlıdır, ancak elektrik aniden kesilirse son saniyelerdeki veri henüz Standby'a gitmemiş olabilir.
*   **Synchronous (Senkron) Replikasyon:** Master işlemi yapar, Standby'a yollar ve Standby'dan "Bana ulaştı ve diske yazıldı" onayı gelene kadar istemciye cevap dönmez. Kesinlikle veri kaybı olmaz (Zero Data Loss), ama performansı bir miktar düşürür.

---

## 2. Master Sunucu Yapılandırması

### `postgresql.conf` Parametreleri

**WAL arşivleme yöntemi:**
```ini
wal_level = replica       # 9.6 ve sonrası (minimal, replica, logical)
max_wal_senders = 10      # Eşzamanlı replikasyon bağlantı sayısı
wal_keep_segments = 256   # pg_wal dizininde tutulacak WAL sayısı
archive_mode = on
archive_command = '/usr/pgsql-16/bin/rsyncwal.sh %p %f'
```

**Replication slot yöntemi:**
```ini
wal_level = logical
max_wal_senders = 5
max_replication_slots = 5
```

### Parametrelerin Açıklamaları

**`wal_level`**: WAL içine ne kadar bilgi yazılacağını belirtir:
- `minimal`: Sadece crash recovery için gerekli bilgiler
- `replica`: PITR ve hot standby için gereken ek bilgiler (replikasyon için bu kullanılır)
- `logical`: Logical replication için (en fazla WAL üretir)

**`max_wal_senders`**: Standby sunuculardan eşzamanlı yapılabilecek replikasyon bağlantısı sayısı. Base backup bağlantıları da dahildir.

**`wal_keep_segments`**: `pg_wal` dizininde tutulacak WAL dosyası sayısı. Standby bu sayıdan daha fazla geride kalırsa master gerekli WAL'ları silebilir ve replikasyon durur.

**`archive_command`**: WAL dosyalarının nereye nasıl gönderileceğini belirler. Kullanılabilir makrolar:
- `%p`: Arşivlenecek WAL dosyasının tam yolu
- `%f`: Arşivlenecek dosyanın sadece adı

Örnek rsync scripti (`rsyncwal.sh`):
```bash
#!/bin/bash
rsync -q -ae ssh $1 postgres@192.168.122.85:/pgsql/walarchive/$2

if [ $? != 0 ]; then
    echo "Archiver error:"
    exit 1
fi
exit 0
```

### Replikasyon Kullanıcısı ve pg_hba.conf

```sql
-- Replikasyon kullanıcısı oluştur
CREATE ROLE replicauser WITH REPLICATION LOGIN ENCRYPTED PASSWORD 'sifre';
ALTER ROLE postgres NOREPLICATION;  -- Postgres kullanıcısının replikasyon yetkisini al
```

`pg_hba.conf`'a standby sunucu için izin ekle:
```text
host replication replicauser 192.168.1.10/32 md5
```

PostgreSQL'i restart et.

**Replication slot oluştur:**
```sql
SELECT * FROM pg_create_physical_replication_slot('mgm_slot');
```

---

## 3. Standby Sunucu Kurulumu

### Parolasız SSH (WAL arşivlemesi için)

İki sunucuda da `postgres` kullanıcısı olarak:
```bash
ssh-keygen -t rsa
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# ~/.ssh/id_rsa.pub içeriğini diğer sunucunun authorized_keys dosyasına ekle
```

### pg_basebackup ile Base Backup (Önerilen Yöntem)

```bash
# WAL arşivleme yöntemi
pg_basebackup -D /var/lib/pgsql/16/data -c fast -x -P -Fp -R \
    -h 192.168.1.5 -p 5432 -U replicauser

# Replication slot yöntemi
pg_basebackup -D /var/lib/pgsql/16/standby -c fast -X stream -P -Fp -R \
    -h 192.168.1.5 -p 5432 -U replicauser
```

**Parametreler:**
- `-c fast`: Checkpoint'i hızlı modda yap (ek yük oluşturur ama zaman kazandırır)
- `-x`: Base backup içine WAL dosyalarını ekle (WAL arşivleme yöntemi)
- `-X stream`: WAL stream ile aktar (slot yöntemi)
- `-P`: Yüzde ilerleme göster
- `-Fp`: "Plain" format (replikasyon için önerilen)
- `-R`: `recovery.conf` / `standby.signal` dosyasını otomatik oluştur

### Standby `postgresql.conf` Ayarları

```ini
hot_standby = on              # Salt okunur sorguları kabul et
hot_standby_feedback = on     # Uzun sorgulardaki vacuum çakışmalarını önle
```

**`recovery.conf` veya `postgresql.conf` (PG12+):**

WAL arşivleme yöntemi:
```text
standby_mode = 'on'
primary_conninfo = 'host=192.168.1.5 port=5432 user=replicauser password=test'
restore_command = 'cp /pgsql/walarchive/%f %p'
archive_cleanup_command = 'pg_archivecleanup /pgsql/walarchive %r'
trigger_file = '/var/lib/pgsql/data/mgm.failover'
recovery_target_timeline = 'latest'
```

Replication slot yöntemi:
```text
standby_mode = 'on'
primary_conninfo = 'host=192.168.1.5 port=5432 user=replicauser password=test'
trigger_file = '/var/lib/pgsql/standby/stop.replication'
recovery_target_timeline = 'latest'
primary_slot_name = 'mgm_slot'
```

---

## 4. Cascading Replikasyon

Cascading replication, bir standby sunucudan başka bir standby sunucu oluşturmak anlamına gelir. Yük dağılımı için kullanışlıdır:

```
Master → Standby-1 → Standby-2
```

Standby-1 yapılandırması:
```ini
hot_standby = on          # Hem standby olacak
max_wal_senders = 5       # Hem de Standby-2 için WAL gönderecek
```

---

## 5. Synchronous Replikasyon

Master'daki bir transaction, (en az) 1 standby sunucuya da aynı anda commit edilir.

> [!WARNING]
> Synchronous replication'da en az 1 aktif standby olmak zorundadır. Yoksa master'daki tüm sorgular duraklatılır.

Yapılandırma:

Standby `recovery.conf`:
```text
primary_conninfo = 'host=192.168.1.5 port=5432 user=replicauser password=test application_name=sb1'
```

Master `postgresql.conf`:
```ini
synchronous_standby_names = 'sb1,sb2'
# veya tümünü kabul etmek için:
synchronous_standby_names = '*'
```

---

## 6. Replikasyon İzleme Parametreleri

**`wal_receiver_status_interval`**: Standby sunucunun üst sunucuya replikasyon durumu bildirdiği aralık (Öntanımlı: 10 saniye).

**`hot_standby_feedback`**: Standby'daki uzun sorgular hakkında master'a bilgi gönderir. Açıkken master vacuum'u bekletir (bloat artabilir). Raporlama amaçlı standby'larda önerilir.

**`wal_receiver_timeout`**: Replikasyon bağlantısının zaman aşımı süresi (Öntanımlı: 60 saniye). Master'ın çöküp çökmediğini anlamak için kullanılır.

---

## 7. Replikasyon Gecikmesini İzleme

```sql
-- Replikasyon gecikmesi (byte cinsinden)
SELECT client_hostname, client_addr, 
    pg_wal_lsn_diff(pg_stat_replication.sent_lsn, 
                    pg_stat_replication.replay_lsn) AS byte_lag
FROM pg_stat_replication;

-- Replikasyon durumu
SELECT * FROM pg_stat_replication;

-- Standby üzerinde gecikmeyi kontrol et
SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay;
```

---

## 8. Failover (Yük Devretme)

Master sunucu donanımsal olarak çökerse, Standby sunucuyu yeni Master ilan etme işlemine **Failover** denir.

Standby sunucudayken:
```sql
SELECT pg_promote();
```

> [!WARNING]
> Bir sunucu `pg_promote` ile Master yapıldıktan sonra, eski Master geri gelse bile kaldığı yerden Standby olarak çalışamaz. Eski sunucu formatlanıp (pg_basebackup) yeni Master'a bağlanmak zorundadır. Aksi takdirde **Split-Brain** (verilerin iki farklı Master'a ayrışması) yaşanır.
>
> Üretim ortamlarında Failover işlemleri genellikle **Patroni**, **repmgr** veya **Keepalived** gibi otomatik HA yazılımlarıyla yönetilir.
