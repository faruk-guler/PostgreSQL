# Connection Pooling (Bağlantı Havuzu) Derinlemesine İnceleme

> **Bölüm Kapsamı:** Neden Pooler Şarttır? PgBouncer, Supavisor ve Odyssey Karşılaştırması, Havuzlama Modları

---

## 1. PostgreSQL'de Bağlantı (Connection) Neden Pahalıdır?

PostgreSQL, gelen her yeni istemci (client) bağlantısı için işletim sisteminde yepyeni bir **Process (Süreç)** oluşturur (Buna `forking` denir). Threads (İş parçacığı) kullanan MySQL'in aksine, Process mimarisi inanılmaz derecede izoledir ve güvenlidir (Bir sorgu çökerse tüm veritabanı çökmez), ancak **çok ağırdır**.

- Her bağlantı ortalama **5-10 MB RAM** harcar.
- 1000 bağlantı = Sadece bağlantıları ayakta tutmak için ~10 GB RAM kaybı.
- Binlerce Process arasındaki CPU Context Switch (Bağlam Değişimi), veritabanının asıl işini yapmasını engeller.

**Kural:** `max_connections` değerini 5000 yapmak çözümsüzlüktür. Doğru çözüm `max_connections = 200` tutup, önüne bir **Connection Pooler** koymaktır.

---

## 2. Pooler Modları (Pooling Modes)

Bağlantı havuzları gelen istekleri üç farklı mantıkla arkadaki PostgreSQL'e iletir:

### A. Session Pooling (Oturum Havuzlama)
İstemci Pooler'a bağlanır, Pooler da veritabanına bağlanır. İstemci `DISCONNECT` diyene kadar o bağlantı o istemciye aittir.
- **Kullanım:** Çok nadir (Örn: Özel SET parametrelerine veya Prepared Statements'a çok ihtiyaç duyan legacy uygulamalar).
- **Ölçeklenebilirlik:** Düşüktür.

### B. Transaction Pooling (İşlem Havuzlama - Endüstri Standardı)
İstemciye, sadece bir `BEGIN ... COMMIT` bloğu (veya tek bir sorgu) boyunca veritabanı bağlantısı tahsis edilir. İşlem (Transaction) biter bitmez, bağlantı hemen havuza iade edilir ve sıradaki istemciye verilir.
- **Kullanım:** %95 oranında bu mod kullanılır.
- **Ölçeklenebilirlik:** Mükemmeldir. 10.000 istemciyi, sadece 100 gerçek veritabanı bağlantısı ile idare edebilirsiniz.
- **Dikkat:** `SET SESSION` gibi komutlar çalışmaz (Çünkü sonraki sorgunun hangi gerçek bağlantıya düşeceği belli değildir).

### C. Statement Pooling (İfade Havuzlama)
Her bir SQL ifadesi için bağlantı tahsis edilir (Transaction bloğu içinde bile olsa).
- **Kullanım:** `AUTOCOMMIT` açık olan çok kısıtlı senaryolar. Genelde tercih edilmez.

---

## 3. Popüler Connection Pooler Araçları

| Araç | Geliştirici | Mimari | Özellikler ve Öne Çıkanlar |
| :--- | :--- | :--- | :--- |
| **PgBouncer** | Topluluk | Single-Thread (C) | Yılların efsanesi, endüstri standardı. Çok hafiftir, 1 CPU çekirdeği ile 10.000 bağlantı tutabilir. Ancak Single-Thread olduğu için modern çok çekirdekli sunucularda dar boğaza (bottleneck) girebilir (Bu durumda birden fazla PgBouncer ayağa kaldırmak gerekir). |
| **Odyssey** | Yandex | Multi-Thread (C) | PgBouncer'ın Single-Thread kısıtlamasını çözmek için yazılmıştır. Çok yüksek trafikli (Yüzbinlerce bağlantı) sistemlerde, tek bir process ile tüm CPU çekirdeklerini kullanarak devasa havuzlar oluşturabilir. |
| **Supavisor** | Supabase | Elixir (Erlang VM) | PostgreSQL'in bulut tabanlı modern yıldızı Supabase tarafından yazılmıştır. Multi-tenant (çoklu kiracı) mimariler düşünülerek tasarlandığı için SaaS uygulamalarına çok uygundur. Milyonlarca bağlantıyı idare edebilir. |
| **Pgpool-II** | Topluluk | Multi-Process | Sadece havuzlama yapmaz, aynı zamanda Load Balancing (Okuma/Yazma ayırma) ve Query Caching yapar. Çok yeteneklidir ancak PgBouncer'a göre oldukça ağırdır. Konfigürasyonu zordur. |

---

## 4. Uygulama İçi (Client-Side) Havuzlar vs. Harici (Server-Side) Havuzlar

- **Client-Side (Uygulama İçi):** HikariCP (Java), `psycopg` pool (Python), `pgx` (Go). Uygulamanızın içinde çalışır. Eğer 50 adet Kubernetes Pod'u ayağa kaldırırsanız ve her birinin boyutu 20 olan havuzu varsa, veritabanına 1000 bağlantı gider! Ölçeklenemez.
- **Server-Side (PgBouncer vb.):** Veritabanının hemen önüne kurulur. 50 Kubernetes Pod'u PgBouncer'a 1000 bağlantı atar, PgBouncer veritabanına sadece 50 bağlantı yollar.

> [!TIP]
> **En İyi Pratik:** İkisini birlikte kullanın. Uygulama içinde küçük bir havuz (Latency'i düşürmek için TCP handshake maliyetini alır), veritabanı önünde ise PgBouncer (Veritabanını korumak için).

---

## 5. Üretim Seviyesi PgBouncer Konfigürasyonu (`pgbouncer.ini`)

Aşağıda, 7/24 yüksek trafik alan bir PostgreSQL kümesi için optimize edilmiş `pgbouncer.ini` örneği yer almaktadır:

```ini
[databases]
* = host=127.0.0.1 port=5432 auth_user=pgbouncer

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid

; Ağ Dinleme Ayarları
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

; Havuz Modu (Transaction = En Yüksek Ölçeklenebilirlik)
pool_mode = transaction

; Bağlantı Limitleri
max_client_conn = 10000
default_pool_size = 50
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 5.0
max_db_connections = 100

; Zaman Aşımları ve Koruma
server_idle_timeout = 600
client_idle_timeout = 0
query_timeout = 0
server_connect_timeout = 15.0
```

---

## 6. PgBouncer Yönetim Konsolu ve Canlı İzleme

PgBouncer özel bir sanal veritabanı (`pgbouncer`) üzerinden canlı havuz istatistiklerini sunar:

```bash
# Yönetim konsoluna bağlanma
psql -p 6432 -U postgres -d pgbouncer
```

### Kritik Tanılama Sorguları:

```sql
-- 1. Havuzların durumunu inceleme (cl_active = çalışan istemciler, cl_waiting = havuzda sıra bekleyenler!)
SHOW POOLS;

-- 2. Bağlı olan istemcileri ve bekleme sürelerini görme
SHOW CLIENTS;

-- 3. PostgreSQL backend bağlantılarının durumunu görme (sv_idle = boşta hazır bekleyenler)
SHOW SERVERS;

-- 4. Anlık bellek ve I/O istatistikleri
SHOW STATS;
```

> [!IMPORTANT]
> `SHOW POOLS` çıktısında `cl_waiting` değeri sıfırdan büyükse ve sürekli artıyorsa, istemciler boşta veritabanı bağlantısı bekliyor demektir. Bu durumda `default_pool_size` artırılmalı veya uzun süren transaction'lar incelenmelidir.

