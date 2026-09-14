# pgLoader ile Veritabanı Göçü ve Veri Aktarımı

`pgLoader`, PostgreSQL için geliştirilmiş yüksek performanslı bir veri kopyalama aracıdır. Sadece CSV okumakla kalmaz; **MS SQL Server, MySQL veya SQLite** gibi başka veritabanlarından PostgreSQL’e göç (migration) işlemleri için de yaygın olarak kullanılır.

## 1. Çalışma Modları ve Özellikleri

pgLoader temelde iki çalışma moduna sahiptir:
1. **Dosyadan Okuma:** CSV, DBF, dBase gibi dosya formatlarını okuyarak hedef veritabanına `COPY` komutuyla (çok hızlı bir şekilde) yükleme yapar.
2. **Doğrudan Veritabanından Göç (Kesintisiz Göç):** Kaynak ve hedef veritabanlarına aynı anda bağlanır. Kaynak veritabanının katalog tablolarına erişerek şemayı okur, aynı yapıyı (tablolar, indeksler, constraint'ler) PostgreSQL'de oluşturur ve verileri eşzamanlı olarak aktarır.

> [!TIP]
> pgLoader verileri bellekte okuyup anında transform edebilir. Hatalı kayıtları `reject.dat` ve `reject.log` dosyalarına ayırarak işlemin kesintiye uğramasını engeller.

---

## 2. Kurulum

pgLoader, Debian/Ubuntu veya RHEL sistemlerde paket yöneticileri ile kolayca kurulabilir:

```bash
# Debian / Ubuntu
sudo apt-get install pgloader  

# RHEL / Rocky Linux
sudo yum install pgloader
```

---

## 3. Komut Satırı Kullanımı (Basit Mod)

Hazırladığınız bir CSV dosyasını (`load.csv`) doğrudan hedef veritabanına aktarmak için tek satırlık şu komut kullanılabilir:

```bash
pgloader load.csv pgsql://kullanici:sifre@localhost/hedef_db
```

---

## 4. Yapılandırma Dosyası ile Gelişmiş Yükleme (.load)

Veri yükleme işlemi sırasında delimiter, encoding, header atlama veya memory limitleri gibi detayları yönetmek için bir `.load` konfigürasyon dosyası kullanılır.

**Örnek: `pgload_test.load` dosyası**
```sql
LOAD CSV
   FROM 'GeoLiteCity-Blocks.csv' WITH ENCODING iso-8859-1
        HAVING FIELDS (startIpNum, endIpNum, locId)
   INTO postgresql://user@localhost:54393/dbname
        TARGET TABLE geolite.blocks
        TARGET COLUMNS (
           iprange ip4r using (ip-range startIpNum endIpNum),
           locId
        )
   WITH truncate,
        skip header = 2,
        fields optionally enclosed by '"',
        fields escaped by backslash-quote,
        fields terminated by ','
   
   SET work_mem to '32 MB', maintenance_work_mem to '64 MB';
```

Bu dosya oluşturulduktan sonra şu komutla çalıştırılır:
```bash
pgloader pgload_test.load
```

> [!NOTE]
> `WITH truncate` seçeneği, veri yüklenmeden önce hedef tablonun içeriğini temizler. `work_mem` ayarları ise aktarım sırasında PostgreSQL'e ne kadar bellek ayıracağınızı belirler. Daha fazla detay için [pgloader resmi dokümantasyonunu](https://pgloader.readthedocs.io/) inceleyebilirsiniz.
