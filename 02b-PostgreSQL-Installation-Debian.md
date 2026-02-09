# 02b-PostgreSQL-Installation-Debian

**Debian / Ubuntu Kurulum Rehberi**

Bu doküman, PostgreSQL'in Debian ve Ubuntu dağıtımlarında nasıl kurulacağını anlatır.

> [!NOTE]
> OS Tuning ve genel konfigürasyon için [02-PostgreSQL-Installation.md](02-PostgreSQL-Installation.md) dosyasına bakın.

---

## 1. Desteklenen Platformlar

PostgreSQL resmi Apt deposu, Debian'ın tüm desteklenen sürümlerini ve mimarileri destekler:

**Desteklenen Debian Sürümleri:**

- trixie (13.x)
- bookworm (12.x)
- bullseye (11.x)
- forky (testing)
- sid (unstable)

**Desteklenen Mimariler:**

- amd64
- arm64
- ppc64el

---

## 2. Kurulum Yöntemleri

### Yöntem 1: Otomatik Konfigürasyon (Önerilen)

```bash
# 1. postgresql-common paketini kurun
sudo apt install -y postgresql-common

# 2. Otomatik repo konfigürasyon scriptini çalıştırın
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh

# 3. PostgreSQL'i kurun (18 yerine istediğiniz sürümü yazın)
sudo apt install -y postgresql-18
```

### Yöntem 2: Manuel Konfigürasyon

```bash
# 1. Gerekli paketleri kurun
sudo apt install -y curl ca-certificates

# 2. Repository signing key'i import edin
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

# 3. Repository konfigürasyon dosyasını oluşturun
. /etc/os-release
sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

# 4. Paket listesini güncelleyin
sudo apt update

# 5. PostgreSQL'i kurun (18 yerine istediğiniz sürümü yazın)
sudo apt install -y postgresql-18
```

> [!NOTE]
> Debian/Ubuntu paketleri kurulum sonrası servisi otomatik başlatır ve bir cluster oluşturur (`main`). Manuel `initdb` gerekmez.

---

## 3. Paket Listesi

| Paket                      | Açıklama                                       |
|:---------------------------|:-----------------------------------------------|
| `postgresql-client-18`     | Client kütüphaneleri ve binary'ler             |
| `postgresql-18`            | Core database server                           |
| `postgresql-doc-18`        | Dokümantasyon                                  |
| `libpq-dev`                | C dili frontend geliştirme için kütüphaneler   |
| `postgresql-server-dev-18` | C dili backend geliştirme için kütüphaneler    |

---

## 4. Dosya Konumları

- **Konfigürasyon:** `/etc/postgresql/18/main/postgresql.conf`
- **Erişim Kontrolü:** `/etc/postgresql/18/main/pg_hba.conf`
- **Veri Dizini:** `/var/lib/postgresql/18/main/`
- **Log Dizini:** `/var/log/postgresql/`

---

## 5. İlk Adımlar

```bash
# Servisi kontrol et
sudo systemctl status postgresql

# postgres kullanıcısına geç
sudo -i -u postgres

# psql'e bağlan
psql

# Şifre belirle
\password postgres

# Çıkış
\q
exit
```

---

## 6. Cluster Yönetimi (Debian/Ubuntu Özel)

Debian/Ubuntu, birden fazla PostgreSQL sürümünü aynı anda çalıştırmanıza izin verir.

```bash
# Tüm cluster'ları listele
pg_lsclusters

# Cluster başlat/durdur
sudo pg_ctlcluster 18 main start
sudo pg_ctlcluster 18 main stop
sudo pg_ctlcluster 18 main restart

# Cluster sil
sudo pg_dropcluster 18 main

# Yeni cluster oluştur
sudo pg_createcluster 18 main2
```

---

## 7. Kaldırma (Uninstallation)

```bash
# 1. Servisi durdur
sudo systemctl stop postgresql

# 2. Cluster'ı sil
sudo pg_dropcluster --stop 18 main

# 3. Paketleri kaldır
sudo apt-get --purge remove postgresql-18 postgresql-client-18 postgresql-contrib-18

# 4. Konfigürasyon ve veri dizinlerini sil
sudo rm -rf /etc/postgresql
sudo rm -rf /var/lib/postgresql
sudo rm -rf /var/log/postgresql
sudo rm -rf /usr/bin/postgres*

# 5. Postgres kullanıcısını kaldır
sudo deluser --remove-home postgres

# 6. Bağımlılık paketlerini temizle
sudo apt-get autoremove
sudo apt-get autoclean

# 7. Paket cache'i temizle
sudo apt-get remove dbconfig-pgsql
```

> [!CAUTION]
> Veri dizinini silmeden önce mutlaka yedek aldığınızdan emin olun!

---

## 8. Doğrulama

```bash
# PostgreSQL tamamen kaldırıldı mı?
which psql
# Çıktı: boş (hiçbir şey) olmalı

# Çalışan process var mı?
ps aux | grep postgres
# Çıktı: sadece grep komutunun kendisi görünmeli

# Veri dizini kaldı mı?
ls -la /var/lib/postgresql
# Çıktı: No such file or directory
```

---

**Sonraki Adım:** [02-PostgreSQL-Installation.md](02-PostgreSQL-Installation.md) dosyasındaki konfigürasyon bölümüne geçin.
