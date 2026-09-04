# Üretim (Production) Hataları ve Çözüm Senaryoları

Veritabanı sunucularında en sık karşılaşılan başlangıç ve operasyon hatalarının nedenleri ve çözüm yolları aşağıda listelenmiştir.

## 1. Servis Başlatma ve Bağlantı Hataları

### Port Çakışması (Address already in use)
```log
LOG:  could not bind IPv4 socket: Address already in use
HINT:  Is another postmaster already running on port 5432?
FATAL:  could not create TCP/IP listen socket
```
**Neden:** Sunucuda zaten çalışan başka bir PostgreSQL (veya 5432 portunu kullanan başka bir servis) var. 
**Çözüm:** `netstat -plnt | grep 5432` komutu ile portu kimin kullandığına bakın. Eski process asılı kaldıysa `kill` ile sonlandırın veya `postgresql.conf` dosyasından portu `5433` olarak değiştirin.

### Bağlantı Reddedildi (Connection refused)
```log
psql: could not connect to server: Connection refused
        Is the server running on host "server.joe.com" and accepting
        TCP/IP connections on port 5432?
```
**Neden:** Veritabanı dışarıdan gelen TCP/IP bağlantılarını dinlemiyor (sadece localhost'a kapalı).
**Çözüm:** `postgresql.conf` içinde `listen_addresses = '*'` yapılmalıdır. Güvenlik duvarının (Firewall) 5432 portuna izin verip vermediği kontrol edilmelidir.

### Yetki Hatası (Permission denied)
```log
ERROR: could not set permissions on directory "/var/lib/pgsql": Permission denied
```
**Neden:** Genellikle Linux üzerinde SELinux veya AppArmor'un PostgreSQL'in dosyalara erişmesini engellemesinden kaynaklanır. Veya `/var/lib/pgsql` dizininin sahibi `postgres` kullanıcısı değildir.
**Çözüm:** `chown -R postgres:postgres /var/lib/pgsql` komutu ile sahiplik düzeltilir veya SELinux ayarları gevşetilir (`setenforce 0`).

---

## 2. Kaynak Tüketimi Hataları

### Bellek Sınırı (Shared Memory Segment)
```log
FATAL:  could not create shared memory segment: Invalid argument
DETAIL:  Failed system call was shmget(key=5440001, size=4011376640,03600).
```
**Neden:** `postgresql.conf` içindeki `shared_buffers` (Paylaşımlı bellek) değeri, Linux işletim sisteminin izin verdiği çekirdek bellek (SHMMAX) sınırından daha yüksek ayarlanmış.
**Çözüm:** `sysctl.conf` dosyasında `kernel.shmmax` değeri artırılmalı veya PostgreSQL `shared_buffers` değeri düşürülmelidir.

### Disk Dolması (No space left on device)
```log
FATAL:  could not create semaphores: No space left on device
```
**Neden:** Veritabanının veya logların yazıldığı disk tamamen dolmuştur. Disk dolduğunda PostgreSQL anında (PANIC) kapanır.
**Çözüm:** Disk temizlenmeli (Eski loglar, gereksiz Temp dosyaları) veya diskin kapasitesi artırılmalıdır. (Ayrıca Tablespace kullanılarak veriler başka bir diske kaydırılabilir).

---

## 3. Felaket Kurtarma (Failover ve Split-Brain)

Streaming Replication kullanan sistemlerde Master sunucu çökerse ve Standby sunucu (Replica) yeni Master yapılırsa (Failover), eski çöken Master sunucu geri döndüğünde (Network tekrar geldiğinde) ne yapılmalıdır?

### Senaryo 1: Hızlı Geri Dönüş
Eğer eski Master 10 saniye gibi çok kısa bir sürede geri döndüyse ve yeni Master çok ileri gitmediyse: Eski Master'daki `recovery.conf` veya `standby.signal` ayarları yapılarak yeni Master'ın kölesi (Standby) olarak bağlanması sağlanır. Sistem tekrar Master-Standby mimarisine oturur.

### Senaryo 2: Uzun Kesinti ve Ayrışma (Split-Brain Riski)
Eğer eski Master saatler sonra geri gelirse ve bu süre zarfında yeni Master'a binlerce yeni veri yazıldıysa: İki sunucunun da geçmişi (Timeline) birbirinden tamamen kopmuştur. Eski Master'ı mevcut haliyle sisteme Standby olarak **ekleyemezsiniz.**
*   **Çözüm A (Küçük Veritabanları):** Eski Master'ın veri klasörü tamamen silinir ve yeni Master'dan sıfırdan `pg_basebackup` alınır.
*   **Çözüm B (Devasa Veritabanları):** Sıfırdan kopyalama işlemi Terabaytlarca veri için imkansızdır. Bu durumda `pg_rewind` aracı kullanılır. Bu araç, iki sunucu arasındaki zaman çizgisini karşılaştırır, sadece değişen blokları bulur ve eski Master'ı yeni Master'ın arkasına hizalar (Rewind). Muazzam bir zaman tasarrufu sağlar.
