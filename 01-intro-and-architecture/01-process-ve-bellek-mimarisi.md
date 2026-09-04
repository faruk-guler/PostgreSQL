# PostgreSQL Process ve Bellek (Memory) Mimarisi

PostgreSQL, **multi-process (çoklu süreç)** mimarisine sahip istemci/sunucu tipi ilişkisel bir veritabanı yönetim sistemidir. İş parçacığı (thread) yerine işletim sistemi süreçlerini (process) kullanır. Bu sayede bir süreçte meydana gelen çökme (crash) diğer süreçleri etkilemez, izolasyon ve kararlılık (stability) en üst düzeye çıkar.

Bir veritabanı kümesini yöneten tüm süreçlerin oluşturduğu bütüne **PostgreSQL Sunucusu (PostgreSQL Server)** denir.

---

## 1. Process (Süreç) Mimarisi

PostgreSQL mimarisinde süreçler beş temel gruba ayrılır:

### 1.1. Postgres Server Process (Ana Süreç)
Önceki sürümlerde `postmaster` olarak bilinen bu süreç, PostgreSQL sunucusundaki **tüm süreçlerin atasıdır (parent process)**.
* `pg_ctl start` komutuyla başlatılır.
* Bellekte paylaşımlı bellek (Shared Memory) alanını tahsis eder.
* Arka plan süreçlerini (Background Processes) başlatır.
* Varsayılan olarak **5432** portunu dinler ve istemcilerden gelen bağlantı isteklerini kabul eder.
* Her yeni bağlantı isteği için işletim sisteminden yeni bir süreç çatallar (fork) ve buna **Backend Process** denir.

### 1.2. Backend Process (Arka Uç Süreci)
Ana süreç tarafından her bir istemci oturumu için özel olarak başlatılan süreçtir. Sistemde `postgres` olarak da adlandırılır.
* İstemci ile TCP/IP veya Unix Domain Socket üzerinden iletişim kurar.
* Gelen SQL sorgularını ayrıştırır, planlar ve çalıştırır.
* Aynı anda yalnızca **bir** veritabanı üzerinde işlem yapabilir.
* İstemcinin bağlantısı kesildiğinde süreç sonlandırılır ve bellek işletim sistemine iade edilir.

> [!WARNING]
> PostgreSQL'in dahili bir bağlantı havuzlama (Connection Pooling) yeteneği yoktur. Web uygulamaları gibi çok sık bağlantı açıp kapatan sistemlerde sürekli süreç yaratma (forking) maliyeti CPU'yu tüketebilir. Bu gibi durumlarda **PgBouncer** veya **PgPool-II** gibi harici havuzlama yazılımları kullanılması kritik önem taşır.

### 1.3. Background Processes (Arka Plan Süreçleri)
Veritabanının sağlığını, disk yazmalarını ve bakım işlemlerini yöneten çekirdek süreçlerdir.

| Süreç Adı | Görev Tanımı |
| :--- | :--- |
| **`background writer`** | Paylaşımlı bellekteki değiştirilmiş (kirli/dirty) sayfaları düzenli olarak diske yazarak Checkpoint anındaki I/O yükünü hafifletir. |
| **`checkpointer`** | `checkpoint_timeout` süresi dolduğunda veya WAL boyutu aşıldığında tüm kirli sayfaları diske yazıp Checkpoint işlemini tamamlar. |
| **`autovacuum launcher`** | Veritabanındaki ölü satırları (dead tuples) temizleyen ve istatistikleri güncelleyen arka plan işçilerini yönetir. |
| **`wal writer`** | WAL (Write-Ahead Log) tamponlarındaki işlem kayıtlarını (transaction logs) periyodik olarak diske yazarak veri kaybını önler. |
| **`stats collector`** | Veritabanı etkinliği, okunan/yazılan satır sayısı gibi istatistikleri toplar (`pg_stat_activity` görünümleri için). |
| **`logger`** | Veritabanı hata, uyarı ve bilgi mesajlarını yapılandırılan log dosyalarına yazar. |
| **`archiver`** | Dolan 16 MB'lık WAL dosyalarını ikincil bir güvenli depolama alanına kopyalar (Sürekli Yedekleme / PITR için). |

### 1.4. Replikasyon Süreçleri (Replication Processes)
Standby (Yedek) sunuculara veri aktarımını sağlayan `walsender` ve `walreceiver` süreçleridir.

### 1.5. Background Worker Processes
PostgreSQL eklentileri (Extensions) veya kullanıcı tanımlı modüller tarafından başlatılabilen esnek arka plan işçileridir (Örn: `pg_cron` veya mantıksal replikasyon işçileri).

---

## 2. Bellek (Memory) Mimarisi

PostgreSQL belleği iki ana kategoriye ayırır: **Local Memory (Yerel Bellek)** ve **Shared Memory (Paylaşımlı Bellek)**.

### 2.1. Local Memory (Yerel Bellek)
Sadece işlemi yürüten ilgili **Backend Process** tarafından erişilebilen ve sorgu bazlı tahsis edilen bellek alanıdır.

* **`work_mem`**: `ORDER BY`, `DISTINCT`, `Hash Join` gibi sıralama ve karma işlemleri için kullanılır. Karmaşık sorgularda (örneğin birden fazla Hash Join varsa) bu bellek her işlem için *ayrı ayrı* tahsis edilir.
* **`maintenance_work_mem`**: `VACUUM`, `CREATE INDEX`, `ALTER TABLE ADD FOREIGN KEY` gibi ağır bakım operasyonları için kullanılan, normal çalışma belleğinden daha büyük tutulan alandır.
* **`temp_buffers`**: Oturum bazlı oluşturulan geçici tabloların (Temporary Tables) verilerini önbelleğe almak için kullanılır.

> [!TIP]
> `work_mem` değerini çok yüksek ayarlamak, eşzamanlı bağlanan kullanıcı sayısı arttığında sunucunun tüm RAM'ini tüketerek işletim sisteminin **OOM (Out of Memory) Killer** mekanizmasını tetiklemesine neden olabilir.

### 2.2. Shared Memory (Paylaşımlı Bellek)
PostgreSQL sunucusu başlatıldığında tahsis edilen ve tüm arka uç ve arka plan süreçleri tarafından ortaklaşa erişilen devasa bellek havuzudur.

* **`shared_buffers`**: PostgreSQL'in en kritik bellek alanıdır. Tablo ve indekslere ait 8 KB'lık disk blokları diskten okunarak bu havuza yüklenir. Sonraki okuma/yazma işlemleri disk yerine doğrudan bu RAM alanı üzerinden çok hızlı bir şekilde gerçekleştirilir. (Genellikle sunucu toplam RAM'inin %25'i kadar ayarlanması önerilir).
* **`wal_buffers`**: İşlem günlüklerinin (WAL) diske yazılmadan önce geçici olarak biriktirildiği alandır. Herhangi bir çökme durumunda veri bütünlüğünü sağlayan ACID mimarisinin kalbidir.
* **`commit_log (CLOG)`**: Eşzamanlılık kontrolü (Concurrency Control - MVCC) mekanizması için tüm işlemlerin durum bayraklarını (`in_progress`, `committed`, `aborted`) tutan özel bir yapıdır.
