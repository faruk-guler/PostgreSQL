# Huge Pages ve NUMA Mimarisi Optimizasyonu

Yüksek bellekli (64 GB - 1 TB+) kurumsal veritabanı sunucularında, PostgreSQL performansını doğrudan belirleyen iki donanım ve çekirdek seviyesi mimari bileşen bulunmaktadır: **Huge Pages (Büyük Bellek Sayfaları)** ve **NUMA (Non-Uniform Memory Access)**.

Bu rehberde; standart 4KB sayfaların yarattığı TLB darboğazını, Huge Pages gereksinimini tam sayıyla hesaplama yöntemini, Transparent Huge Pages (THP) tehlikesini ve NUMA mimarisinde bellek dengesizliğini önleme adımlarını inceleyeceğiz.

---

## 1. Standart 4KB Sayfalar vs Huge Pages (2MB)

İşletim sistemi, fiziksel RAM adreslerini sanal bellek adreslerine eşlemek için **Sayfa Tablosu (Page Table)** kullanır. İşlemci (CPU) bu adresleri hızlandırmak için kendi üzerinde **TLB (Translation Lookaside Buffer)** adında bir önbelleğe sahiptir.

```
[ Standart 4KB Sayfalar ]
64 GB shared_buffers = 16.777.216 Adet Sayfa Girişi ──► TLB Önbelleği Taşar (TLB Miss)
                                                         Yüksek CPU Beklemesi

[ 2MB Huge Pages ]
64 GB shared_buffers = 32.768 Adet Sayfa Girişi      ──► TLB İçine Tam Sığar (TLB Hit)
                                                         Sıfır Sayfalama Gecikmesi
```

Standart sayfa boyutunda milyonlarca giriş TLB önbelleğine sığmaz; CPU her bellek erişiminde RAM'deki sayfa tablosunu taramak zorunda kalır (**TLB Misses**). Huge Pages kullanıldığında sayfa sayısı 512 kat azalır, TLB isabet oranı %99'un üzerine çıkar ve sorgularda %10 ile %30 arasında doğrudan performans artışı elde edilir.

---

## 2. PostgreSQL İçin Huge Pages İhtiyacını Hesaplama

Huge Pages dinamik olarak büyüyemez; işletim sistemi başlangıcında fiziksel RAM'den rezerve edilmelidir.

### 2.1. Adım Adım Hesaplama Prosedürü

1. Öncelikle `postgresql.conf` içinde `huge_pages = off` yapılır ve servis başlatılır:
   ```ini
   huge_pages = off
   ```
   ```bash
   systemctl restart postgresql-16
   ```

2. `postmaster` sürecinin tahsis ettiği paylaşımlı bellek boyutu sorgulanır:
   ```bash
   PID=$(head -n 1 /var/lib/pgsql/16/data/postmaster.pid)
   pmap -d $PID | awk '/rw-s/ && /zero/ {print $2}'
   ```
   Örnek çıktı: `16781312K` (~16 GB)

3. Sistemdeki tek bir Huge Page boyutuna (`Hugepagesize`) bölünür (genellikle 2048 KB):
   ```bash
   python3 -c "print(int(16781312 / 2048) + 100)"
   ```
   Çıktı: `8296` (Güvenlik payı olarak +100 sayfa eklenmiştir).

### 2.2. İşletim Sisteminde Kalıcı Tahsis

Bulunan değer `/etc/sysctl.d/99-hugepages.conf` dosyasına yazılır:

```ini
# /etc/sysctl.d/99-hugepages.conf
vm.nr_hugepages = 8296
```

Çekirdeğe işletilir ve doğrulanır:

```bash
sysctl --system
grep -i HugePages /proc/meminfo
```

Beklenen çıktı:
```text
HugePages_Total:    8296
HugePages_Free:     8296
Hugepagesize:       2048 kB
```

### 2.3. PostgreSQL'de Huge Pages'ı Zorunlu Kılma

`/var/lib/pgsql/16/data/postgresql.conf` içinde:

```ini
huge_pages = on   # 'try' değil 'on' yapılarak Huge Pages olmadan başlaması engellenir
```

Servis yeniden başlatıldığında PostgreSQL doğrudan bu ayrılmış bellek havuzunu kullanır:

```bash
systemctl restart postgresql-16
grep -i HugePages /proc/meminfo
```
`HugePages_Free` değerinin azaldığı ve sayfaların PostgreSQL tarafından rezerve edildiği gözlemlenmelidir.

---

## 3. Transparent Huge Pages (THP) Kapatılmalıdır!

Linux çekirdeği ile gelen **Transparent Huge Pages (THP)**, sayfaları arka planda otomatik olarak 2MB'a birleştirmeye (compaction/defragmentation) çalışır.

> [!CAUTION]
> **THP Veritabanları İçin Zehirdir:** PostgreSQL gibi yoğun rastgele bellek erişimi yapan sistemlerde THP arka plan birleştirme süreci (khugepaged) CPU çekirdeklerini %100'e kilitler ve veritabanında saniyeler süren donmalara yol açar. THP mutlaka devre dışı bırakılmalıdır!

### 3.1. THP'yi Devre Dışı Bırakma (RHEL/Debian/Ubuntu)

Geçici olarak:
```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

Kalıcı hale getirmek için Grub önyükleyici parametrelerine ekleyin:

`/etc/default/grub` dosyasında `GRUB_CMDLINE_LINUX` satırına eklenir:
```text
transparent_hugepage=never
```

Grub yapılandırması güncellenir:
```bash
# RHEL / Rocky Linux
grub2-mkconfig -o /boot/grub2/grub.cfg

# Debian / Ubuntu
update-grub
```

---

## 4. NUMA Mimarisi ve Dengesiz Bellek Tüketimi

Modern çok soketli sunucularda her işlemci (CPU Socket) kendi yerel belleğine sahiptir (**NUMA Node**). Bir CPU kendi yerel belleğine çok hızlı erişirken, diğer CPU'nun belleğine erişmesi iç veri yolu (QPI/UPI) üzerinden gerçekleşir ve daha yavaştır.

```
┌───────────────────────────┐         ┌───────────────────────────┐
│        NUMA Node 0        │         │        NUMA Node 1        │
│  [ CPU 0 ] ───► [ RAM 0 ] │◄───────►│  [ CPU 1 ] ───► [ RAM 1 ] │
└───────────────────────────┘ Interconnect└───────────────────────────┘
```

### 4.1. Yaşanan Sorun: NUMA Dengesizliği ve Erken Swap

Varsayılan Linux davranışında bir süreç ilk çalıştığı CPU'nun yerel belleğini doldurursa, diğer NUMA düğümünde onlarca GB boş RAM olmasına rağmen kendi düğümündeki sayfaları Swap alanına gönderebilir (**Zone Reclaim Felaketi**).

### 4.2. Çözüm 1: Zone Reclaim ve NUMA Dengelemeyi Kapatma

`/etc/sysctl.d/99-numa.conf` dosyasına eklenir:

```ini
# 0 = Bellek yetmediğinde yerel sayfaları diske takas etme, diğer NUMA düğümünden al
vm.zone_reclaim_mode = 0

# Otomatik sayfa taşımayı devre dışı bırak (CPU yükünü düşürür)
kernel.numa_balancing = 0
```

### 4.3. Çözüm 2: `numactl --interleave=all` ile Servisi Başlatma

PostgreSQL'in paylaşımlı belleği (`shared_buffers`) tüm NUMA düğümlerine eşit olarak serpiştirilmelidir (interleaved allocation).

Systemd servis dosyasını düzenleyin:

```bash
systemctl edit postgresql-16
```

Açılan pencereye ekleyin:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/numactl --interleave=all /usr/pgsql-16/bin/postmaster -D ${PGDATA}
```

Servisi yeniden yükleyin:

```bash
systemctl daemon-reload
systemctl restart postgresql-16
```

Bu yapılandırma ile PostgreSQL, sunucudaki tüm CPU ve bellek düğümlerini eşit homojenlikte kullanarak maksimum bant genişliğine ulaşır.
