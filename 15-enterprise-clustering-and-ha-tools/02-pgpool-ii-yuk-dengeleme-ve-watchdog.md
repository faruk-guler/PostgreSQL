# PgPool-II ile Yük Dengeleme, Bağlantı Havuzlama ve Watchdog

**PgPool-II**, PostgreSQL sunucuları ile istemci (client) uygulamaları arasında yer alan çok amaçlı bir ara katman yazılımıdır (middleware). İlk olarak basit bir bağlantı havuzlayıcı (connection pooler) olarak geliştirilmiş olsa da günümüzde okuma yükü dengeleme (read load balancing), otomatik yazma yönlendirme, bağlantı kuyruklama ve **Watchdog** servisi sayesinde yüksek erişilebilirlik sağlayan kurumsal bir çözümdür.

---

## 1. PgPool-II Temel Yetenekleri ve PgBouncer Karşılaştırması

```
                       ┌─────────────────────────┐
                       │  İstemci Uygulamaları   │
                       └────────────┬────────────┘
                                    │ Port 9999 (VIP)
                       ┌────────────▼────────────┐
                       │   PgPool-II (Watchdog)  │
                       │ [Pooler + Load Balancer]│
                       └─────┬─────────────┬─────┘
           Yazma (DML/DDL)   │             │   Okuma (SELECT)
                             ▼             ▼
                   ┌──────────────┐   ┌──────────────┐
                   │ Primary Node │──►│ Standby Node │
                   │  (Port 5432) │   │  (Port 5432) │
                   └──────────────┘   └──────────────┘
                         Streaming Replication
```

### PgPool-II vs PgBouncer Karşılaştırması

| Özellik | PgBouncer | PgPool-II |
| :--- | :--- | :--- |
| **Bağlantı Havuzlama** | Çok hafif, yüksek performanslı | Var (Süreç tabanlı) |
| **Okuma Yükü Dengeleme (Load Balancing)** | Yok (Tüm trafiği tek adrese iletir) | **Var** (SELECT sorgularını replikalara dağıtır) |
| **Yazma / Okuma Ayrımı** | Yok (Uygulamanın çift DataSource açması gerekir) | **Var** (SQL sorgusunu analiz edip otomatik yönlendirir) |
| **Fazla Bağlantıyı Kuyruklama** | Var | Var (`num_init_children` sınırında bekletir) |
| **Sorgu Önbellekleme (Query Cache)** | Yok | **Var** (Bellekte SELECT sonuçlarını tutabilir) |
| **Kendi İçinde HA (Yedeklilik)** | Harici araç gerekir (Keepalived vb.) | **Var (Watchdog + Sanal IP / VIP)** |
| **Kaynak Tüketimi** | Çok düşük (Tek thread event-loop) | Orta/Yüksek (Her bağlantı için alt süreç açar) |

---

## 2. PgPool-II Kurulumu ve Temel Yapılandırma

### 2.1. Paket Kurulumu

```bash
# RHEL / Rocky Linux (PostgreSQL 16)
dnf install -y pgpool-II-pg16

# Debian / Ubuntu
apt-get install -y pgpool2
```

### 2.2. Temel Yapılandırma (`pgpool.conf`)

`/etc/pgpool-II/pgpool.conf` dosyası oluşturulur ve kritik parametreler ayarlanır:

```ini
# Ağ ve Port Ayarları
listen_addresses = '*'
port = 9999
pcp_listen_addresses = '*'
pcp_port = 9898

# Çalışma Modu
load_balance_mode = on          # Okuma yükünü standby düğümlere dağıt
master_slave_mode = on          # Master-Standby mimarisini etkinleştir
master_slave_sub_mode = 'stream'# Streaming replikasyon kullanılıyor

# Replikasyon Gecikme Kontrolü (Lag Detection)
sr_check_period = 5             # 5 saniyede bir replikasyon gecikmesini kontrol et
sr_check_user = 'postgres'
sr_check_database = 'postgres'
delay_threshold = 10485760      # Standby gecikmesi 10 MB'ı aşarsa o düğüme SELECT gönderme!

# Bağlantı Havuzu Sınırları
num_init_children = 64          # Eşzamanlı maksimum istemci alt süreci
max_pool = 4                    # Her çocuk sürecin tutabileceği veritabanı bağlantısı
connection_cache = on
reset_query_list = 'ABORT; DISCARD ALL'
```

### 2.3. Veritabanı Düğümlerinin Tanımlanması

Kümedeki PostgreSQL sunucuları backend blokları halinde listelenir:

```ini
# Primary Sunucu
backend_hostname0 = '192.168.10.101'
backend_port0 = 5432
backend_weight0 = 1             # Master'a da okuma yükü verilsin mi (0 = sadece yazma)
backend_data_directory0 = '/var/lib/pgsql/16/data'
backend_flag0 = 'ALLOW_TO_FAILOVER'

# Standby 1 Sunucusu
backend_hostname1 = '192.168.10.102'
backend_port1 = 5432
backend_weight1 = 2             # Standby sunucuya 2 kat daha fazla SELECT yönlendir
backend_data_directory1 = '/var/lib/pgsql/16/data'
backend_flag1 = 'ALLOW_TO_FAILOVER'
```

---

## 3. Okuma ve Yazma Trafiğinin Doğrulanması

PgPool servisini başlatın:

```bash
systemctl enable --now pgpool-II
```

PgPool portu üzerinden bağlanarak yükün nasıl dağıtıldığını test edin:

```bash
psql -h 127.0.0.1 -p 9999 -U postgres -d postgres
```

Sorguladığınızda gelen IP adresini inceleyin:

```sql
-- SELECT sorgusu (Standby düğüme yönlendirilir)
SELECT inet_server_addr();
-- Çıktı: 192.168.10.102

-- INSERT/UPDATE sorgusu (Otomatik olarak Primary'e yönlendirilir)
CREATE TABLE siparisler (id serial primary key, urun text);
INSERT INTO siparisler (urun) VALUES ('Laptop');
```

PgPool log dosyasında SQL yönlendirmesi izlenebilir:

```text
LOG: DB node id: 1 backend pid: 14202 statement: SELECT inet_server_addr();
LOG: DB node id: 0 backend pid: 14589 statement: INSERT INTO siparisler (urun) VALUES ('Laptop');
```

---

## 4. Watchdog ile Yüksek Erişilebilirlik (Virtual IP)

PgPool sunucusunun kendisinin çökmesi (Single Point of Failure - SPOF) riskine karşı **Watchdog** servisi kullanılır. Watchdog, iki veya daha fazla PgPool sunucusunun birbirini kalp atışıyla (heartbeat) izlemesini ve ortak bir **Sanal IP (Virtual IP - VIP)** kullanmasını sağlar.

```ini
# /etc/pgpool-II/pgpool.conf (Watchdog Ayarları)
use_watchdog = on
wd_hostname = '192.168.10.51'     # Kendi IP'si
wd_port = 9000
wd_authkey = 'GizliWatchdogAnahtari'

# Sanal IP (VIP) Yapılandırması
delegate_IP = '192.168.10.50'     # Uygulamaların bağlanacağı ortak VIP
if_cmd_path = '/sbin'
if_up_cmd = '/usr/bin/sudo /sbin/ip addr add $_IP_$/24 dev eth0 label eth0:0'
if_down_cmd = '/usr/bin/sudo /sbin/ip addr del $_IP_$/24 dev eth0'
arping_cmd = '/usr/bin/sudo /sbin/arping -U $_IP_ -w 1 -I eth0'

# Diğer Watchdog Düğümü
other_wd_hostname0 = '192.168.10.52'
other_wd_port0 = 9000
```

> [!TIP]
> Watchdog aktif olduğunda, aktif PgPool düğümü çökerse diğer PgPool düğümü Virtual IP'yi (`192.168.10.50`) kendi ağ kartına bağlar (Gratuitous ARP gönderir). Uygulamalar hiçbir yapılandırma değiştirmeden aynı IP üzerinden veritabanına erişmeye devam eder.

---

## 5. PCP (Pgpool Child Process) Yönetim Konsolu

PgPool alt süreçlerini, düğüm durumlarını ve istatistiklerini komut satırından yönetmek için PCP arabirimi kullanılır:

```bash
# PCP yetkilendirme parolası oluşturma (md5 veya sha256)
pg_md5 YoneticiParolasi
# Çıktı: 8287458823facb8ff918dbfabcd22ccb
```

`/etc/pgpool-II/pcp.conf` dosyasına eklenir:
```text
pcpadmin:8287458823facb8ff918dbfabcd22ccb
```

### 5.1. Sık Kullanılan PCP Komutları

```bash
# Kümedeki PostgreSQL düğüm sayısını öğrenme
pcp_node_count -U pcpadmin -h 127.0.0.1 -p 9898

# Düğümlerin rolünü, ağırlığını ve durumunu görme
pcp_node_info -U pcpadmin -h 127.0.0.1 -p 9898 0
# Çıktı: 192.168.10.101 5432 2 0.333333 up primary

pcp_node_info -U pcpadmin -h 127.0.0.1 -p 9898 1
# Çıktı: 192.168.10.102 5432 2 0.666667 up standby

# Havuz bağlantı istatistikleri
pcp_pool_status -U pcpadmin -h 127.0.0.1 -p 9898
```
