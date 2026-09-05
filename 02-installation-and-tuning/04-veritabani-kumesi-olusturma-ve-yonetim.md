# Veritabanı Kümesi Oluşturma ve Yönetim (`initdb` & `pg_ctl`)

PostgreSQL sunucusunu kullanmaya başlamadan önce disk üzerinde verilerin ve yapılandırma dosyalarının tutulacağı alanı hazırlamanız gerekir. Bu alana **Veritabanı Kümesi (Database Cluster)** veya kısaca **Data Dizinini (`$PGDATA`)** denir. Bir küme, tek bir PostgreSQL hizmeti (instance) tarafından yönetilen birden fazla veritabanını barındırabilir.

---

## 1. Veritabanı Kümesi Başlatma (`initdb`)

Kümeyi oluşturmak için PostgreSQL kurulumuyla gelen `initdb` aracı kullanılır. 

```bash
# PostgreSQL kullanıcısına (postgres) geçiş yapın
su - postgres

# Kümeyi başlatın (-D ile veri dizini yolunu belirtin)
initdb -D /var/lib/pgsql/data
```

Bu işlem tamamlandığında veri dizini içinde `postgresql.conf`, `pg_hba.conf`, ana veritabanı `postgres` ve şablon veritabanı `template1` otomatik olarak oluşturulur.

> [!CAUTION]
> Veri dizini (`$PGDATA`) içindeki dosyalar yetkisiz erişimden korunmalıdır. `initdb` işlemi, dizin izinlerini otomatik olarak sadece `postgres` kullanıcısının erişebileceği şekilde (`chmod 0700`) ayarlar. Bu izinleri manuel olarak gevşetmek (örneğin `chmod 777`) veritabanının çalışmayı reddetmesine neden olur!

---

## 2. Sunucuyu Başlatma (`pg_ctl start`)

Veritabanı kümesini başlattıktan sonra, sunucu sürecini (`postgres`) ayağa kaldırmanız gerekir. Arka planda güvenli ve loglanmış bir şekilde başlatmak için `pg_ctl` sarmalayıcısı kullanılır.

```bash
pg_ctl start -D /var/lib/pgsql/data -l /var/lib/pgsql/data/server.log
```

* `-D`: Veri dizininin konumu.
* `-l`: Sunucu loglarının (başlatma hataları, uyarılar) yazılacağı dosya.

### Linux systemd Hizmeti ile Başlatma

Modern Linux dağıtımlarında `pg_ctl` yerine genellikle `systemctl` aracı kullanılır. Arka planda systemd'nin nasıl yapılandırıldığını anlamak için tipik bir servis dosyası şöyledir:

```ini
[Unit]
Description=PostgreSQL database server
After=network.target

[Service]
Type=notify
User=postgres
ExecStart=/usr/pgsql-16/bin/postgres -D /var/lib/pgsql/16/data
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed

[Install]
WantedBy=multi-user.target
```
Sunucuyu başlatmak ve sistem açılışına eklemek için:
```bash
systemctl start postgresql-16
systemctl enable postgresql-16
```

---

## 3. Sunucuyu Kapatma (`pg_ctl stop`)

PostgreSQL sunucusunu kapatırken ana sürece (parent process) gönderilen sinyale bağlı olarak 3 farklı kapatma modu (Shutdown Mode) mevcuttur:

### Akıllı Kapatma (Smart Shutdown - `SIGTERM`)
Varsayılan kapatma yöntemidir.
* Sunucu yeni bağlantı (login) isteklerini reddeder.
* Mevcut bağlı oturumların ve sorguların işlemlerini bitirmesini **bekler**.
* Herkes işini bitirdikten sonra (kimse kalmadığında) güvenli bir şekilde kapanır.
```bash
pg_ctl stop -D /var/lib/pgsql/data -m smart
```

### Hızlı Kapatma (Fast Shutdown - `SIGINT`)
Pratikte en çok kullanılan yöntemdir (örneğin systemctl stop komutu bunu tetikler).
* Yeni bağlantıları reddeder.
* Aktif olan tüm oturumları iptal edip (Rollback) zorla keser.
* Kalan son işlemleri diske yazar ve saniyeler içinde sunucuyu kapatır.
```bash
pg_ctl stop -D /var/lib/pgsql/data -m fast
```

### Anında Kapatma (Immediate Shutdown - `SIGQUIT`)
Yalnızca acil durumlarda (sunucu yanıt vermiyorsa) kullanılmalıdır.
* Her şeyi olduğu gibi bırakarak ana süreci ve tüm alt süreçleri acımasızca öldürür.
* Normal kapatma prosedürleri (Checkpoint vb.) uygulanmaz.
* Sunucu bir sonraki açılışında **Çökme Kurtarma (Crash Recovery)** modunda başlar ve WAL (Write-Ahead Log) dosyalarını baştan oynatarak tutarlılığı sağlamak zorunda kalır (açılış süresi uzar).
```bash
pg_ctl stop -D /var/lib/pgsql/data -m immediate
```

> [!WARNING]
> Sunucu süreçlerini işletim sistemi seviyesinde kapatmak için asla `kill -9` (`SIGKILL`) **KULLANMAYIN!** Bu, paylaşımlı bellekte (Shared Memory) veri bozulmalarına ve semafor sızıntılarına yol açabilir. Her zaman `pg_ctl` veya servisin kendi kapatma yöntemlerini kullanın.
