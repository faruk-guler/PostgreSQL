# 02a-PostgreSQL-Installation-RHEL

**RHEL / Rocky Linux / AlmaLinux Kurulum Rehberi**

Bu doküman, PostgreSQL'in Red Hat Enterprise Linux, Rocky Linux ve AlmaLinux dağıtımlarında nasıl kurulacağını anlatır.

> [!NOTE]
> OS Tuning ve genel konfigürasyon için [02-PostgreSQL-Installation.md](02-PostgreSQL-Installation.md) dosyasına bakın.

---

## 1. Desteklenen Platformlar

PostgreSQL Yum Repository, Red Hat ailesi dağıtımların tümünü destekler:

- RHEL (Red Hat Enterprise Linux)
- Rocky Linux
- AlmaLinux
- Oracle Linux

Son iki minor release'i destekler (örn: RHEL 10.0 ve 10.1).

> [!WARNING]
> Fedora sunucu dağıtımları için önerilmez (kısa destek döngüsü nedeniyle). Production ortamları için RHEL/Rocky/AlmaLinux kullanın.

---

## 2. Kurulum Yöntemleri

### Yöntem 1: PostgreSQL Yum Repository (Önerilen - En Güncel Sürüm)

```bash
# 1. Varsayılan postgresql modülünü devre dışı bırakın (RHEL 8/9 için, çakışmayı önler)
sudo dnf -y module disable postgresql

# 2. PGDG Repository RPM'ini kurun
# RHEL/Rocky/AlmaLinux 10 için:
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# RHEL/Rocky/AlmaLinux 9 için:
# sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# RHEL/Rocky/AlmaLinux 8 için:
# sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# 3. PostgreSQL Server'ı kurun (18 yerine istediğiniz sürümü yazın)
sudo dnf install -y postgresql18-server

# 4. Veritabanını initialize edin (Sadece ilk kurulumda)
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb

# 5. Servisi başlatın ve otomatik açılışa ekleyin
sudo systemctl enable postgresql-18
sudo systemctl start postgresql-18
```

### Yöntem 2: Dağıtım Deposundan (Varsayılan Sürüm)

Eğer en son sürüm yerine dağıtımın varsayılan sürümünü kullanmak isterseniz:

```bash
# Doğrudan kurulum
sudo dnf install -y postgresql-server

# Post-installation (RHEL/Rocky/AlmaLinux 10, 9, 8 veya Fedora 41+ için)
sudo postgresql-setup --initdb
sudo systemctl enable postgresql.service
sudo systemctl start postgresql.service
```

---

## 3. Dağıtım Varsayılan Sürümleri

| Dağıtım                    | PostgreSQL Sürümü                    |
|:---------------------------|:-------------------------------------|
| RHEL/Rocky/AlmaLinux 10    | 16                                   |
| RHEL/Rocky/AlmaLinux 9     | 16, 15, 13 (modüller ile)            |
| RHEL/Rocky/AlmaLinux 8     | 15, 13, 12, 10, 9.6 (modüller ile)   |
| Fedora 43                  | 18                                   |
| Fedora 42                  | 16                                   |

---

## 4. Paket Listesi

| Paket                  | Açıklama                                     |
|:-----------------------|:---------------------------------------------|
| `postgresql-client`    | Client kütüphaneleri ve binary'ler           |
| `postgresql-server`    | Core database server                         |
| `postgresql-contrib`   | Ek modüller (pg_stat_statements vb.)         |
| `postgresql-devel`     | C dili geliştirme için kütüphaneler          |

---

## 5. Dosya Konumları

- **Konfigürasyon:** `/var/lib/pgsql/18/data/postgresql.conf`
- **Erişim Kontrolü:** `/var/lib/pgsql/18/data/pg_hba.conf`
- **Veri Dizini:** `/var/lib/pgsql/18/data/`
- **Log Dizini:** `/var/lib/pgsql/18/data/log/`

---

## 6. İlk Adımlar

```bash
# Servisi kontrol et
sudo systemctl status postgresql-18

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

## 7. Kaldırma (Uninstallation)

```bash
# 1. Servisi durdur
sudo systemctl stop postgresql-18
sudo systemctl disable postgresql-18

# 2. Paketleri kaldır
sudo dnf remove -y postgresql18*

# 3. Veri ve konfigürasyon dizinlerini sil
sudo rm -rf /var/lib/pgsql/18
sudo rm -rf /usr/pgsql-18

# 4. Repository'yi kaldır (opsiyonel)
sudo dnf remove -y pgdg-redhat-repo

# 5. Postgres kullanıcısını kaldır (opsiyonel)
sudo userdel -r postgres
```

> [!CAUTION]
> Veri dizinini silmeden önce mutlaka yedek aldığınızdan emin olun!

---

**Sonraki Adım:** [02-PostgreSQL-Installation.md](02-PostgreSQL-Installation.md) dosyasındaki konfigürasyon bölümüne geçin.
