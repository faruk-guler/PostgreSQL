# 02-PostgreSQL-Installation & Production Tuning

PostgreSQL'in üretim ortamlarında (Production) en iyi pratiklerle nasıl kurulacağını ve optimize edileceğini anlatan ana rehber.

> [!IMPORTANT]
> **Platform-Specific Kurulum Rehberleri:**
>
> - **RHEL/Rocky/AlmaLinux:** [02a-PostgreSQL-Installation-RHEL.md](02a-PostgreSQL-Installation-RHEL.md)
> - **Debian/Ubuntu:** [02b-PostgreSQL-Installation-Debian.md](02b-PostgreSQL-Installation-Debian.md)

> [!WARNING]
> Varsayılan işletim sistemi depolarındaki paketler genellikle eskidir. Her zaman resmi **PGDG (PostgreSQL Global Development Group)** depolarını kullanın.

---

## 1. İşletim Sistemi Hazırlığı (OS Tuning)

PostgreSQL kurulmadan önce, işletim sistemi seviyesinde yapılması gereken kritik ayarlar vardır. Bu ayarlar performansın %30-%40 artmasını sağlayabilir.

### a. Disable Transparent Huge Pages (THP)

Linux'un varsayılan bellek yönetim özelliği olan THP, veritabanı iş yükleri için **zararlıdır** ve performans dalgalanmalarına (jitter) neden olur. Kapatılması gerekir.

```bash
# Geçici çözüm (Reboot edince gider)
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Kalıcı çözüm (Grub ayarı)
# /etc/default/grub dosyasında GRUB_CMDLINE_LINUX satırına şunu ekleyin:
# transparent_hugepage=never
# Sonra: grub2-mkconfig -o /boot/grub2/grub.cfg && reboot
```

> [!TIP]
> **THP vs Standard Huge Pages:** Transparent Huge Pages (THP) kapatılmalıdır, ancak performans için **Standard Huge Pages** (`vm.nr_hugepages`) kullanılabilir. Bu, belleği statik olarak ayırır ve TLB (Translation Lookaside Buffer) maliyetini düşürür. Bu ileri seviye bir ayardır ve RAM miktarına göre hesaplanmalıdır.

### b. Swappiness Ayarı

Veritabanı sunucularının diske swap yapmasını (belleği diske taşımasını) istemeyiz. Varsayılan değer (60) çok agresiftir.

```bash
# /etc/sysctl.conf dosyasına ekleyin:
vm.swappiness = 1
# (0 yapmayın, kernel OOM Killer tetikleyebilir. 1 veya 10 güvenlidir.)
```

### c. Dosya Tanımlayıcı (File Descriptor) Limitleri

PostgreSQL çok sayıda dosya açar. Varsayılan limit (1024) yetersizdir.

```bash
# /etc/security/limits.conf dosyasına ekleyin:
postgres soft nofile 65536
postgres hard nofile 65536
```

---

## 2. Kurulum

Platform-specific kurulum talimatları için:

- **RHEL/Rocky/AlmaLinux:** [02a-PostgreSQL-Installation-RHEL.md](02a-PostgreSQL-Installation-RHEL.md)
- **Debian/Ubuntu:** [02b-PostgreSQL-Installation-Debian.md](02b-PostgreSQL-Installation-Debian.md)

---

## 3. İlk Konfigürasyon (postgresql.conf)

Kurulum sonrası varsayılan ayarlar çok muhafazakardır (128MB shared buffer gibi).

**Dosya Yolu:**

- RHEL: `/var/lib/pgsql/18/data/postgresql.conf`
- Debian: `/etc/postgresql/18/main/postgresql.conf`

### Temel Ayarlar

1. **Bağlantı Ayarları:**

    ```ini
    listen_addresses = '*'          # Dışarıdan bağlantı kabul et (Güvenlik pg_hba.conf ile sağlanır)
    max_connections = 200           # Çok yüksek yapmayın. 1000+ bağlantı için PgBouncer kullanın.
    ```

    > [!NOTE]
    > **ICU Collations (PG 12+):** İşletim sistemi güncellemelerinin (glibc) sıralamayı (ORDER BY) bozmasını engellemek için, veritabanı oluştururken "ICU" provider kullanın. PostgreSQL 17'den itibaren bu varsayılan (immutable) provider olabilir.
    > `initdb --locale-provider=icu --icu-locale=tr-TR`

2. **Bellek Ayarları (16GB RAM'li sunucu için örnek):**

    ```ini
    shared_buffers = 4GB            # Toplam RAM'in %25'i
    work_mem = 16MB                 # Sorgu/Bağlantı başına. Çok arttırmayın!
    maintenance_work_mem = 1GB      # Bakım işlemleri için.
    effective_cache_size = 12GB     # OS File Cache + Shared Buffers (Toplam RAM'in %75'i)
    ```

3. **Checkpoint ve WAL:**

    ```ini
    wal_level = replica             # Replikasyon için gerekli
    min_wal_size = 1GB
    max_wal_size = 4GB
    checkpoint_completion_target = 0.9  # I/O yükünü zamana yayar (Daha pürüzsüz performans)
    ```

4. **SSD Optimizasyonu:**

    ```ini
    random_page_cost = 1.1          # SSD için 1.1, HDD için 4.0 varsayılır. Sorgu planlayıcıyı etkiler.
    ```

> [!TIP]
> Sunucunuzun RAM ve CPU özelliklerine göre otomatik config üretmek için **PGTune** (<https://pgtune.leopard.in.ua/>) aracını kullanabilirsiniz.

---

## 4. Ağ ve Erişim Güvenliği (pg_hba.conf)

Bu dosya, "Kim, Nereden, Hangi Veritabanına, Nasıl" bağlanabilir sorusunun cevabıdır.

**Dosya Yolu:**

- RHEL: `/var/lib/pgsql/18/data/pg_hba.conf`
- Debian: `/etc/postgresql/18/main/pg_hba.conf`

**Örnek Konfigürasyon:**

```bash
# TÜR     DB        USER      ADRES           YÖNTEM

# 1. Local bağlantılar (Sunucu içinden - unix socket)
local   all       postgres                  peer    # Linux kullanıcısı ile eşleşme (Şifresiz, güvenli)
local   all       all                       scram-sha-256

# 2. Remote bağlantılar (Uygulama Sunucuları - IPv4)
host    app_db    app_user  10.0.0.50/32    scram-sha-256

# 3. Yönetim bağlantıları (Admin VLAN)
host    all       admin     192.168.1.0/24  scram-sha-256

# 4. Geri kalan herkesi REDDET (Best Practice: Açıkça belirtmeseniz de varsayılan davranıştır ama görünür olması iyidir)
# host    all       all       0.0.0.0/0       reject
```

> [!IMPORTANT]
> `trust` yöntemini **ASLA** production ortamında kullanmayın. Şifresiz erişim verir.
> `md5` yerine artık daha güvenli olan `scram-sha-256` standarttır.

---

## 5. Değişiklikleri Uygulama

Ayarları yaptıktan sonra servisi yeniden başlatın veya reload edin.

```bash
# Reload (Bağlantıları kesmez, çoğu ayar için yeterli)
sudo systemctl reload postgresql-18  # RHEL
sudo systemctl reload postgresql     # Debian

# Restart (Bağlantıları keser, bazı ayarlar için gerekli)
sudo systemctl restart postgresql-18 # RHEL
sudo systemctl restart postgresql    # Debian
```

---

## 6. Tablespace Yönetimi (İsteğe Bağlı)

Tablespace, verileri farklı disklerde saklamanızı sağlar. Örneğin, sıcak verileri SSD'de, arşiv verileri HDD'de tutabilirsiniz.

```sql
-- 1. Disk üzerinde dizin oluştur
-- mkdir -p /mnt/fast_ssd/pg_tablespace
-- chown postgres:postgres /mnt/fast_ssd/pg_tablespace

-- 2. Tablespace oluştur
CREATE TABLESPACE fast_storage LOCATION '/mnt/fast_ssd/pg_tablespace';

-- 3. Yeni tablo oluştururken kullan
CREATE TABLE critical_data (
    id SERIAL PRIMARY KEY,
    data TEXT
) TABLESPACE fast_storage;

-- 4. Var olan tabloyu taşı
ALTER TABLE my_table SET TABLESPACE fast_storage;

-- 5. Tüm tablespace'leri listele
\db+
```

> [!WARNING]
> Tablespace dizinini silmek veya mount edilen diski çıkarmak, PostgreSQL'in çökmesine yol açar. Mutlaka yedekleme stratejinize tablespace'leri de dahil edin.

---

**Sonraki Adımlar:**

- [03-PostgreSQL-Basic-Operations.md](03-PostgreSQL-Basic-Operations.md) - psql kullanımı ve temel işlemler
- [06-PostgreSQL-Performance-Tuning.md](06-PostgreSQL-Performance-Tuning.md) - İleri seviye performans optimizasyonu
