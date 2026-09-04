# Linux Çekirdek (Kernel) Parametreleri ve sysctl Optimizasyonu

PostgreSQL, işletim sistemi çekirdeğine (Linux Kernel) son derece yakın çalışan bir veritabanı motorudur. Birçok kurumsal ortamda donanım ve `postgresql.conf` ayarları mükemmel olsa dahi, varsayılan Linux çekirdek ayarları nedeniyle ani I/O donmaları (stalls), gereksiz takas (swap) kullanımı veya **Out-Of-Memory (OOM) Killer** tarafından PostgreSQL ana sürecinin öldürülmesi gibi felaketler yaşanabilir.

Bu bölümde; `/etc/sysctl.conf` üzerinden yönetilen bellek, takas alanı, kirli sayfalar (dirty pages), IPC paylaşımlı bellek ve dosya tanımlayıcı sınırlarını ele alacağız.

---

## 1. OOM Killer'ı Engelleme ve Bellek Aşımı (Overcommit)

Linux, varsayılan olarak süreçlerin talep ettiği ancak henüz fiziksel olarak kullanmadığı bellekleri "aşırı tahsis" (overcommit) eder (`vm.overcommit_memory = 0`). Bellek tükendiğinde Linux çekirdeği **OOM Killer** mekanizmasını devreye sokar ve en çok bellek tüketen süreci (çoğunlukla `postmaster` veya bir `postgres backend`) anında öldürür (`SIGKILL`).

```
[ Bellek Yetersizliği Anı ]
Linux Kernel (OOM Killer) ────► En Yüksek Puanlı Süreci Bulur ────► SIGKILL
                                  (Genellikle PostgreSQL!)
```

### 1.1. Çözüm: Katı Aşırı Tahsis Koruması

```ini
# /etc/sysctl.d/99-postgresql.conf

# 2 = Asla tahsis edilebilir RAM + Swap toplamından fazlasını verme
vm.overcommit_memory = 2

# Fiziksel RAM'in yüzde kaçı tahsis edilebilir (Örn: %80)
vm.overcommit_ratio = 80
```

> [!WARNING]
> `vm.overcommit_memory = 2` yapıldığında sistemde yeterli büyüklükte bir takas (Swap) alanı bulunmalıdır. Aksi halde PostgreSQL veya işletim sistemi süreçleri `Cannot allocate memory` hatası alabilir.

### 1.2. PostgreSQL Sürecini OOM Puanından Muaf Tutma

Systemd servis seviyesinde PostgreSQL'in OOM Killer tarafından hedef alınmasını engellemek için `OOMScoreAdjust` parametresi kullanılır:

```ini
# /etc/systemd/system/postgresql-16.service.d/override.conf
[Service]
OOMScoreAdjust=-1000
```

---

## 2. Takas (Swap) Davranışı ve `vm.swappiness`

PostgreSQL, sayfaların RAM içinde (`shared_buffers` veya OS Page Cache) kalmasını bekler. Sistemde bol miktarda boş RAM varken dahi Linux'un sayfaları diske (Swap) yazması sorgu sürelerinde milisaniyelerden saniyelere fırlayan gecikmelere (latency spikes) yol açar.

```ini
# /etc/sysctl.d/99-postgresql.conf

# 0: Sadece OOM olmamak için son çare olarak swap kullan
# 1: Veritabanı sunucuları için altın standart (Swap kullanımını minimize eder)
vm.swappiness = 1
```

> [!IMPORTANT]
> Swap alanını tamamen kapatmak (`swapoff -a`) önerilmez! Swap tamamen kapalı olduğunda ani bir bellek sıçramasında çekirdek doğrudan OOM Killer'ı tetikler. `vm.swappiness = 1` ile sistem acil durum hava yastığını korurken normal şartlarda asla takasa başvurmaz.

---

## 3. Kirli Sayfalar (Dirty Pages) ve Checkpoint I/O Donmalarını Önleme

Linux belleğinde değiştirilmiş ancak henüz diske yazılmamış sayfalara **Dirty Page** denir. Linux varsayılan olarak `vm.dirty_ratio = 20` ve `vm.dirty_background_ratio = 10` değerleriyle gelir.

**Problem:** 256 GB RAM'e sahip bir sunucuda `%20`, yaklaşık **51 GB** kirli veri anlamına gelir! PostgreSQL Checkpoint tetiklendiğinde veya Linux arka plan yazarı uyandığında diske bir anda 50 GB veri pompalanır ve depolama denetleyicisi (RAID controller/SAN) kilitlenir; sistem onlarca saniye boyunca hiçbir sorguya yanıt veremez (**I/O Freeze**).

### 3.1. Çözüm: Bayt Bazlı Sabit Limitler (`dirty_bytes`)

Yüksek bellekli veritabanı sunucularında yüzdelik oranlar yerine sabit bayt limitleri kullanılmalıdır:

```ini
# /etc/sysctl.d/99-postgresql.conf

# Disk denetleyicisinin tampon belleğine uygun değerler (Örn: 64MB - 256MB)
vm.dirty_background_bytes = 67108864    # 64 MB (Arka planda diske yazmaya başlama eşiği)
vm.dirty_bytes = 268435456              # 256 MB (Süreçleri durdurup diske yazmaya zorlama eşiği)
```

Bu sayede kirli veriler küçük ve düzenli dalgalar halinde diske aktarılır; checkpoint dalgalanmaları tamamen pürüzsüzleşir.

---

## 4. Paylaşımlı Bellek ve IPC Limitleri (System V / POSIX)

PostgreSQL 9.3 öncesinde System V paylaşımlı belleğine (`shmmax`) bağımlıydı. Modern PostgreSQL sürümleri POSIX paylaşımlı belleği (`mmap`) kullansa da bazı eklentiler ve sistem alt yapıları için IPC limitlerinin doğru tanımlanması şarttır:

```ini
# /etc/sysctl.d/99-postgresql.conf

# Maksimum paylaşımlı bellek segment boyutu (Bayt cinsinden - Örn: 64 GB)
kernel.shmmax = 68719476736

# Toplam tahsis edilebilir paylaşımlı bellek sayfası (4KB sayfa hesabı)
kernel.shmall = 16777216

# Maksimum semafor limitleri (semmsl, semmns, semopm, semmni)
kernel.sem = 250 32000 100 128
```

---

## 5. Dosya Tanımlayıcıları ve Ağ Soketi Ayarları

Yüzlerce eşzamanlı bağlantının ve binlerce açık tablo dosyasının bulunduğu sistemlerde işletim sistemi limitleri artırılmalıdır:

### 5.1. Sistem Genel Sınırları (`sysctl`)

```ini
# /etc/sysctl.d/99-postgresql.conf

# Sistem geneli açılabilecek dosya sayısı
fs.file-max = 2097152

# TCP bağlantı kuyruk uzunluğu (SYN Flood ve yoğun bağlantı dalgaları için)
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

# Kapanan soketlerin hızlıca yeniden kullanılabilmesi
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
```

### 5.2. Kullanıcı Seviyesi Limitler (`limits.conf`)

`/etc/security/limits.d/99-postgresql.conf` dosyasına eklenir:

```text
postgres    soft    nofile    65536
postgres    hard    nofile    65536
postgres    soft    nproc     4096
postgres    hard    nproc     4096
postgres    soft    memlock   unlimited
postgres    hard    memlock   unlimited
```

---

## 6. Ayarların Yürürlüğe Alınması ve Doğrulama

Oluşturulan parametreleri yeniden başlatmaya gerek kalmadan uygulamak için:

```bash
# sysctl ayarlarını yükleyin
sysctl --system

# Doğrulama
sysctl vm.overcommit_memory vm.swappiness vm.dirty_bytes
```
