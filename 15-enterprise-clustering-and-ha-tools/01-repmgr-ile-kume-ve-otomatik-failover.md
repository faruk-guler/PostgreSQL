# repmgr ile Küme Yönetimi ve Otomatik Yük Devretme (Failover)

**repmgr (Replication Manager)**, PostgreSQL streaming replikasyon kümelerini yönetmek, izlemek ve felaket anında otomatik yük devretme (failover) gerçekleştirmek için geliştirilmiş en popüler açık kaynaklı kümeleme araçlarından biridir (EnterpriseDB / 2ndQuadrant).

Bu bölümde; repmgr mimarisini, birincil (primary) ve yedek (standby) sunucuların yapılandırılmasını, `repmgr standby clone` ile veri eşitlemeyi, `repmgrd` servisi ile otomatik yük devretmeyi, tanık (witness) sunucu kavramını ve bölünmüş beyin (split-brain) sendromunu önleyen yalıtım (fencing) stratejilerini ele alacağız.

---

## 1. repmgr Mimarisi ve Temel Kavramlar

```
              ┌────────────────────────┐
              │     Primary Node       │
              │  (node_id=1, node1)    │
              └───────────┬────────────┘
                          │ WAL Streaming
              ┌───────────┴────────────┐
              ▼                        ▼
  ┌───────────────────────┐  ┌───────────────────────┐
  │     Standby Node      │  │     Witness Node      │
  │  (node_id=2, node2)   │  │  (node_id=3, witness) │
  │   [repmgrd active]    │  │    (Sadece Oy Verir)  │
  └───────────────────────┘  └───────────────────────┘
```

| Kavram | Açıklama |
| :--- | :--- |
| **Replication Cluster** | Streaming replikasyon bağlantısı ile birbirine bağlı PostgreSQL sunucular bütünü. |
| **Node (Düğüm)** | Kümedeki bağımsız her bir PostgreSQL sunucusu. |
| **Upstream Node** | Replikasyon akışının alındığı kaynak sunucu (genellikle Primary, basamaklı replikasyonda Standby olabilir). |
| **Failover** | Primary sunucu çöktüğünde veya ulaşılamaz olduğunda, Standby sunuculardan birinin otomatik olarak yeni Primary seçilmesi. |
| **Switchover** | Planlı bakım durumlarında Primary sunucunun bilinçli olarak Standby'a çekilmesi ve bir Standby'ın kesintisiz yükseltilmesi. |
| **Witness Node (Tanık)** | Veri replike etmeyen, sadece küme bölünmelerinde çoğunluk oyunu (quorum) belirlemek için çalışan hafif sunucu. |
| **Fencing (Yalıtım)** | Çöken eski Primary'nin aniden geri gelmesi durumunda iki başlılığı (split-brain) önlemek için izole edilmesi. |

---

## 2. Ortam Hazırlığı ve PostgreSQL Yapılandırması

Örnek senaryomuzda 2 adet veritabanı sunucusu ve 1 adet tanık sunucu bulunmaktadır:
- **node1 (Primary):** `192.168.10.101`
- **node2 (Standby):** `192.168.10.102`
- **witness (Tanık):** `192.168.10.103`

### 2.1. Paket Kurulumu (RHEL/Rocky/Debian)

Tüm düğümlere PostgreSQL sürümüne uygun `repmgr` paketi kurulur:

```bash
# RHEL / Rocky Linux (PostgreSQL 16 için)
dnf install -y repmgr_16

# Debian / Ubuntu
apt-get install -y postgresql-16-repmgr
```

### 2.2. Parolasız SSH Yetkilendirmesi

`repmgr` komutlarının sunucular arasında kesintisiz çalışabilmesi için `postgres` sistem kullanıcıları arasında çift yönlü parolasız SSH anahtarı tanımlanmalıdır:

```bash
# postgres kullanıcısına geçiş yapın
su - postgres
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

# Anahtarları diğer tüm düğümlere kopyalayın
ssh-copy-id -i ~/.ssh/id_ed25519.pub postgres@192.168.10.101
ssh-copy-id -i ~/.ssh/id_ed25519.pub postgres@192.168.10.102
ssh-copy-id -i ~/.ssh/id_ed25519.pub postgres@192.168.10.103
```

### 2.3. Primary Sunucu Yapılandırması (`postgresql.conf`)

`node1` üzerinde aşağıdaki parametreler düzenlenir:

```ini
# /var/lib/pgsql/16/data/postgresql.conf
listen_addresses = '*'
wal_level = 'replica'
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
archive_mode = on
archive_command = '/bin/true'  # veya kurumsal arşiv betiği

# repmgr kütüphanesini önden yükleyin
shared_preload_libraries = 'repmgr'
```

### 2.4. Kullanıcı ve Veritabanı Tanımlama

`repmgr` küme metaverilerini kendi özel veritabanında tutar:

```sql
-- Primary (node1) üzerinde çalıştırın
CREATE USER repmgr WITH SUPERUSER REPLICATION LOGIN ENCRYPTED PASSWORD 'GucluRepmgrParolasi';
CREATE DATABASE repmgr OWNER repmgr;
ALTER ROLE repmgr SET search_path TO repmgr, "$user", public;
```

### 2.5. İstemci Doğrulama (`pg_hba.conf`)

Tüm sunucuların `pg_hba.conf` dosyasına aşağıdaki erişim kuralları eklenir ve reload edilir:

```text
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   replication     repmgr                                  trust
host    replication     repmgr          127.0.0.1/32            trust
host    replication     repmgr          192.168.10.0/24         scram-sha-256
local   repmgr          repmgr                                  trust
host    repmgr          repmgr          127.0.0.1/32            trust
host    repmgr          repmgr          192.168.10.0/24         scram-sha-256
```

---

## 3. repmgr Yapılandırması ve Düğümlerin Kaydı

### 3.1. Primary (`node1`) Yapılandırması

`/etc/repmgr/16/repmgr.conf` dosyasını oluşturun:

```ini
node_id=1
node_name='node1'
conninfo='host=192.168.10.101 user=repmgr dbname=repmgr connect_timeout=2 password=GucluRepmgrParolasi'
data_directory='/var/lib/pgsql/16/data'
use_replication_slots=yes
```

Primary sunucuyu repmgr'a kaydedin:

```bash
su - postgres
repmgr -f /etc/repmgr/16/repmgr.conf primary register
```

Çıktı:
```text
INFO: connecting to primary database...
NOTICE: attempting to install extension "repmgr"
NOTICE: "repmgr" extension successfully installed
NOTICE: primary node record (id: 1) registered
```

Küme durumunu kontrol edin:

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

---

## 4. Standby Düğümün Klonlanması (`node2`)

Standby olacak `node2` üzerinde PostgreSQL servisi durdurulur ve veri dizini tamamen boşaltılır:

```bash
systemctl stop postgresql-16
rm -rf /var/lib/pgsql/16/data/*
```

`node2` için `/etc/repmgr/16/repmgr.conf` dosyası oluşturulur:

```ini
node_id=2
node_name='node2'
conninfo='host=192.168.10.102 user=repmgr dbname=repmgr connect_timeout=2 password=GucluRepmgrParolasi'
data_directory='/var/lib/pgsql/16/data'
use_replication_slots=yes
```

### 4.1. Klonlama Tatbikatı (`--dry-run`)

Klonlama öncesi ağ ve izin kontrollerini test edin:

```bash
su - postgres
repmgr -h 192.168.10.101 -U repmgr -d repmgr -f /etc/repmgr/16/repmgr.conf standby clone --dry-run
```

Herhangi bir hata yoksa gerçek klonlama başlatılır:

```bash
repmgr -h 192.168.10.101 -U repmgr -d repmgr -f /etc/repmgr/16/repmgr.conf standby clone --fast-checkpoint
```

### 4.2. Standby Başlatma ve Kayıt

Veriler çekildikten sonra servis başlatılır ve repmgr'a kaydedilir:

```bash
systemctl start postgresql-16

# Standby olarak kümeye tanıtın
repmgr -h 192.168.10.101 -U repmgr -d repmgr -f /etc/repmgr/16/repmgr.conf standby register
```

Artık küme durumu kontrol edildiğinde:

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

```text
 ID | Name  | Role    | Status    | Upstream | Location | Priority | Timeline | Connection string
----+-------+---------+-----------+----------+----------+----------+----------+-------------------------------------------------------------
 1  | node1 | primary | * running |          | default  | 100      | 1        | host=192.168.10.101 user=repmgr dbname=repmgr connect_timeout=2
 2  | node2 | standby |   running | node1    | default  | 100      | 1        | host=192.168.10.102 user=repmgr dbname=repmgr connect_timeout=2
```

---

## 5. Otomatik Yük Devretme (`repmgrd`) ve Fencing

Otomatik yük devretme için her düğümde `repmgrd` arka plan servisi çalışmalıdır.

### 5.1. `repmgr.conf` İçinde Failover Kuralları

Tüm düğümlerdeki `/etc/repmgr/16/repmgr.conf` dosyasına şu satırlar eklenir:

```ini
failover='automatic'
promote_command='/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby promote --log-to-file'
follow_command='/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby follow --log-to-file --upstream-node-id=%n'

# Zaman aşımları ve yeniden bağlanma denemeleri
reconnect_attempts=4
reconnect_interval=5

# Servis yönetim komutları
service_start_command   = 'sudo systemctl start postgresql-16'
service_stop_command    = 'sudo systemctl stop postgresql-16'
service_restart_command = 'sudo systemctl restart postgresql-16'
service_reload_command  = 'sudo systemctl reload postgresql-16'

log_file='/var/log/repmgr/repmgr.log'
log_level='INFO'
```

### 5.2. Sudoers İzinleri

`postgres` kullanıcısının servisi yönetebilmesi için `/etc/sudoers.d/postgres` dosyası tanımlanmalıdır:

```text
Defaults:postgres !requiretty
postgres ALL = NOPASSWD: /usr/bin/systemctl stop postgresql-16, /usr/bin/systemctl start postgresql-16, /usr/bin/systemctl restart postgresql-16, /usr/bin/systemctl reload postgresql-16
```

### 5.3. Servisi Başlatma ve İzleme

```bash
systemctl daemon-reload
systemctl enable --now repmgr16.service
```

Olayları izlemek için:

```bash
repmgr -f /etc/repmgr/16/repmgr.conf cluster events
```

---

## 6. Tanık Sunucu (Witness Server) ve Split-Brain Koruması

İki düğümlü bir yapıda ağ koptuğunda (network split), her iki sunucu da diğerinin öldüğünü düşünerek kendini Primary ilan edebilir (**Split-Brain**). Bunu engellemek için kümede 3. bir oy hakkı olmalıdır.

Eğer 3. bir tam veritabanı sunucusu için kaynak yoksa, hafif bir **Witness Server** kurulur:

```bash
# witness sunucusunda
repmgr -f /etc/repmgr/16/repmgr.conf witness register -h 192.168.10.101 -U repmgr -d repmgr
```

> [!IMPORTANT]
> Tanık sunucu PostgreSQL verilerini barındırmaz; yalnızca küme metaveri tablosunu güncel tutar ve kriz anında çoğunluk (quorum) oylamasına katılarak yanlış düğümün Primary olmasını engeller.

---

## 7. Planlı Geçiş (Switchover) Operasyonu

Bakım veya donanım yükseltmesi amacıyla Primary sunucuyu planlı ve sıfır veri kaybıyla değiştirmek için Standby düğümden şu komut verilir:

```bash
# node2 üzerinde çalıştırın:
repmgr -f /etc/repmgr/16/repmgr.conf standby switchover --dry-run
repmgr -f /etc/repmgr/16/repmgr.conf standby switchover
```

Bu işlem sırasıyla:
1. `node1` üzerindeki trafiği durdurur ve servisi güvenle kapatır.
2. `node1` üzerindeki son WAL kayıtlarının `node2`'ye akmasını bekler.
3. `node2`'yi Primary rolüne yükseltir (`promote`).
4. `node1`'i `node2`'nin altına yeni Standby olarak bağlar (`follow`).
