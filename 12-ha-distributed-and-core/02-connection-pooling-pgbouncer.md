# PgBouncer ve Connection Pooling

PostgreSQL veritabanı, gelen her bir bağlantı (Connection) için bellekte 5-10 MB harcayan ayrı bir işletim sistemi süreci (Process) başlatır. Eğer web uygulamanız aynı anda 2000 bağlantı açmaya çalışırsa (Özellikle PHP veya Serverless Lambda mimarilerinde), sunucunuzun RAM'i saniyeler içinde tükenir (Out Of Memory) ve sistem çöker.

Bu sorunu çözmek için araya bir **Connection Pooler (Bağlantı Havuzlayıcı)** olan `PgBouncer` kurulur.

## 1. PgBouncer Nedir?

PgBouncer, uygulama ile PostgreSQL arasına giren, inanılmaz derecede hafif (bağlantı başına sadece 2KB bellek harcayan) bir ara katmandır (Proxy).

**Nasıl Çalışır?**
Uygulama 5000 tane bağlantıyı PgBouncer'a açar. PgBouncer bunu sorunsuzca karşılar. Ancak PgBouncer arka planda veritabanına sadece 50 tane gerçek (kalıcı) bağlantı açar. Uygulamadan gelen 5000 sorguyu sıraya sokarak bu 50 hattan veritabanına gönderir. Veritabanı (PostgreSQL) sadece 50 bağlantı varmış gibi çok rahat, stressiz ve maksimum performansta çalışır.

## 2. PgBouncer Pooling Modları

PgBouncer `pgbouncer.ini` dosyasındaki `pool_mode` ayarına göre üç farklı stratejiyle çalışır:

1.  **Session (Oturum) Modu:** İstemci bağlanır, bağlantıyı kesene kadar arkadaki 50 kanaldan biri o istemciye özel tahsis edilir. Web uygulamalarında değil, uzun süren bağlantılarda (ETL, pgAdmin) kullanılır.
2.  **Transaction (İşlem) Modu (ÖNERİLEN):** İstemci bir Transaction (Örn: BEGIN; UPDATE; COMMIT;) açtığı anda arkadan bir hat tahsis edilir. COMMIT olduğu anda hat hemen havuza iade edilir ve başkası kullanır. **Web projelerinde en yüksek performansı veren ve kullanılması gereken moddur.**
3.  **Statement (Sorgu) Modu:** Transaction açılmasına bile izin vermez, tek bir sorgu (SELECT) için hat tahsis eder, sorgu bittiği an hattı iade eder. Çok kısıtlıdır.

---

## 3. PgBouncer Kurulum ve Ayar Mantığı

1. PgBouncer kurulur.
2. `pgbouncer.ini` ayarlanır:
```ini
[databases]
# İstemciler 'urun_db' diye bağlanacak, biz arkada pg_server'a bağlayacağız.
urun_db = host=192.168.1.5 port=5432 dbname=urun_db

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 10000   # Uygulamanın açabileceği maks bağlantı
default_pool_size = 100   # Veritabanına açılacak gerçek maks hat sayısı
```
3. Uygulama tarafındaki (Örn: Node.js, Java, Python) veritabanı bağlantı metninde Port `5432` yerine `6432` (PgBouncer) yapılır.

> [!TIP]
> PgBouncer'ın bir diğer efsanevi özelliği de veritabanı sunucusunu (PostgreSQL) bakım için yeniden başlatmanız gerektiğinde ortaya çıkar. PgBouncer üzerinden PostgreSQL'i duraklattığınızda (`PAUSE`), uygulamalar hata almaz, sadece birkaç saniye bekler. Siz PostgreSQL'i restart edip `RESUME` dediğinizde her şey hiçbir hata fırlatılmadan kaldığı yerden devam eder!
