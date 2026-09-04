# PostgreSQL FDW (Foreign Data Wrapper) Mimarisi ve Dış Veri Entegrasyonu

> **Bölüm Kapsamı:** SQL/MED Standartları, `postgres_fdw` Kurulum ve Yetkilendirme, Ağ/Bellek Optimizasyonu (`fetch_size`, `batch_size`), Query Pushdown Mekanizması, İstatistik Yönetimi (`ANALYZE`) ve DBA Operasyonel Riskleri (Bağlantı Havuzu, 2PC, Güvenlik).

---

## 1. Mimari Genel Bakış: SQL/MED ve FDW Nedir?

PostgreSQL, yalnızca kendi yerel diskindeki verileri yöneten monolitik bir veritabanı değildir. ISO/IEC 9075-9 standardı olan **SQL/MED (Management of External Data)** altyapısını çekirdek seviyesinde destekler. Bu yetenek, **FDW (Foreign Data Wrapper)** eklentileri aracılığıyla dış sistemlerin (farklı PostgreSQL kümeleri, MySQL, Oracle, MongoDB, CSV/Log dosyaları, S3 Parquet göletleri) yerel bir tabloymuş gibi şeffaf bir biçimde sorgulanmasını sağlar.

```text
                                 [Uygulama İstemcisi]
                                          |
                                          v  (Standart SQL Sorgusu)
                          [Yerel PostgreSQL Sunucusu (Hub)]
                                          |
         +--------------------------------+--------------------------------+
         |                                |                                |
         v                                v                                v
  [postgres_fdw]                     [file_fdw]                   [parquet_s3_fdw]
         |                                |                                |
         v (TCP / Libpq)                  v (POSIX I/O)                    v (HTTPS / S3 API)
[Uzak PostgreSQL DB]             [/var/log/server.csv]            [AWS S3 Veri Göleti]
```

### `dblink` vs `postgres_fdw` (DBA Karşılaştırması)

Geçmişte kullanılan `dblink` ile modern `postgres_fdw` arasındaki farklar şunlardır:

| Karşılaştırma Kriteri | `dblink` (Eski Yöntem) | `postgres_fdw` (SQL/MED Standardı) |
| :--- | :--- | :--- |
| **Entegrasyon Düzeyi** | Fonksiyon bazlı (Imperative: `dblink('conn', 'SELECT...')`) | Deklaratif SQL (Declarative: Doğrudan `SELECT`, `INSERT`, `UPDATE`, `DELETE`) |
| **Sorgu Optimizasyonu** | Yok. Uzak sorgu bir kara kutudur. | Tam entegre. Optimizör maliyet hesaplar, indeksleri ve istatistikleri dikkate alır. |
| **Sorgu İletimi (Pushdown)** | Manuel yazılmalıdır. | Otomatik: `WHERE`, `JOIN`, `LIMIT`, `ORDER BY` ve `AGGREGATE` fonksiyonları uzağa itilir. |
| **Transaction Yönetimi** | İstemci kontrolündedir. | Yerel transaction ile tam senkronizedir. |
| **Özerk İşlemler (Autonomous TX)** | **Destekler.** Ana işlem `ROLLBACK` olsa bile uzak veritabanına `COMMIT` atabilir. | **Desteklemez.** Yerel transaction iptal edilirse uzak işlem de geri alınır. |

---

## 2. `postgres_fdw` Kurulumu ve Üretim Ortamı Yapılandırması

İki bağımsız PostgreSQL kümesi arasında (Örn: Yerel Raporlama Sunucusu -> Uzak Muhasebe Sunucusu `10.0.5.50`) üretim standartlarında bir bağlantı kuralım.

### Adım 1: Eklentiyi Kurma
Yerel veritabanında süper kullanıcı (Superuser) yetkisiyle eklenti aktifleştirilir:
```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
```

---

### Adım 2: Dış Sunucuyu (FOREIGN SERVER) Güvenli ve Optimize Tanımlama

> [!WARNING]
> Varsayılan `CREATE SERVER` seçenekleri ağ gecikmesine ve planlayıcı körlüğüne yol açar. Bir DBA, üretim ortamında ağ ve optimizör parametrelerini mutlaka ilk kurulum anında tanımlamalıdır.

```sql
CREATE SERVER srv_muhasebe_prod
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host '10.0.5.50',
        port '5432',
        dbname 'muhasebe_db',
        sslmode 'verify-full',            -- Ağ trafiğini TLS ile şifrele ve sertifikayı doğrula
        keep_connections 'on',             -- Her sorguda TCP el sıkışmasını tekrarlama (PG 14+)
        fetch_size '10000',                -- Ağdan veriyi 100 satır yerine 10.000 satırlık bloklarla çek
        batch_size '1000',                 -- Toplu INSERT işlemlerini çoklu satır olarak ilet (PG 14+)
        use_remote_estimate 'true',        -- Planlayıcının uzak istatistikleri ve indeksleri okumasını sağla
        fdw_startup_cost '100.0',          -- Ağ gecikmesi başlangıç maliyeti çarpanı
        fdw_tuple_cost '0.2',              -- Satır aktarım maliyeti çarpanı
        async_capable 'true'               -- Paralel/asenkron dış tablo taramalarına izin ver (PG 14+)
    );
```

---

### Adım 3: Yetkilendirme (Kritik DBA Adımı)

Yerel kullanıcıların (`rapor_user`) bu dış sunucuya erişebilmesi için `USAGE` hakkı verilmelidir. Bu adım atlanırsa `permission denied for foreign server` hatası alınır:

```sql
GRANT USAGE ON FOREIGN SERVER srv_muhasebe_prod TO rapor_user;
```

---

### Adım 4: Kullanıcı Eşleştirmesi (USER MAPPING)

Yerel kullanıcının uzaktaki veritabanında hangi kullanıcı kimliğiyle oturum açacağı belirlenir:

```sql
CREATE USER MAPPING FOR rapor_user
    SERVER srv_muhasebe_prod
    OPTIONS (
        user 'svc_raporlama_read',
        password 'CokGucluUzakSifre!2026'
    );
```

> [!CAUTION]
> **Şifre Güvenliği Riski:** `CREATE USER MAPPING` ile girilen şifreler sistem kataloğunda (`pg_user_mapping`) açık metin (plaintext) saklanır. `SUPERUSER` veya `pg_dumpall` alan herhangi biri bu şifreyi görebilir. 
> **Güvenlik Çözümleri:**
> 1. Uzak sunucuda parola yerine **SSL İstemci Sertifikası** (`sslcert`, `sslkey`) kullanın.
> 2. PostgreSQL işletim sistemi kullanıcısının (`postgres`) ev dizinindeki `~/.pgpass` dosyasını yapılandırarak şifreyi veritabanı kataloglarından tamamen arındırın.

---

### Adım 5: Yabancı Tablo ve Şema İçe Aktarma

#### Yöntem A: Kontrollü Şema Aktarımı (`IMPORT FOREIGN SCHEMA`)
Uzak sunucudaki yüzlerce tabloyu yerel kataloğa kontrolsüz yığmak yerine, sadece ihtiyaç duyulan tablolar izole bir şemaya çekilmelidir:

```sql
-- 1. Yerelde izole bir şema oluştur
CREATE SCHEMA IF NOT EXISTS uzak_muhasebe;
GRANT USAGE ON SCHEMA uzak_muhasebe TO rapor_user;

-- 2. Uzak şemayı LIMIT TO ile filtreleyerek içe aktar
IMPORT FOREIGN SCHEMA public
    LIMIT TO (faturalar, fatura_kalemleri, cariler)
    FROM SERVER srv_muhasebe_prod
    INTO uzak_muhasebe;
```

#### Yöntem B: Tek Bir Tabloyu Özelleştirerek Bağlama (`CREATE FOREIGN TABLE`)
Eğer uzaktaki tablonun sadece belirli kolonlarını çekmek veya kolon isimlerini yerelde farklı kullanmak istiyorsanız:

```sql
CREATE FOREIGN TABLE uzak_muhasebe.fatura_ozet (
    id BIGINT,
    fatura_no VARCHAR(32) OPTIONS (column_name 'belge_numarasi'),
    tutar NUMERIC(15,2),
    olusturma_tarihi DATE
)
SERVER srv_muhasebe_prod
OPTIONS (
    schema_name 'public', 
    table_name 'faturalar',
    fetch_size '5000' -- Tablo bazında fetch_size ezilebilir
);

GRANT SELECT ON uzak_muhasebe.fatura_ozet TO rapor_user;
```

---

## 3. Performans Optimizasyonu ve Pushdown Mekanizması

FDW mimarisinde sistemin başarısını belirleyen yegane kriter **Pushdown (Sorgunun Uzak Sunucuya İletilmesi)** yeteneğidir.

```text
[KÖTÜ SENARYO: Pushdown Başarısız]
Uzak Sunucu (10M Satır) =====[ Ağ Üzerinden 10 Milyon Satır Akar ]=====> Yerel Sunucu (RAM Tüketimi + Filtreleme)

[İYİ SENARYO: Tam Pushdown Başarılı]
Uzak Sunucu (Filtreler, Toplar, Sıralar) =====[ Sadece 1 Satırlık Sonuç ]=====> Yerel Sunucu
```

### 3.1. Neler Uzak Sunucuya İtilebilir (Pushdown Edilebilir)?
1. **Predicate Pushdown (`WHERE`):** Uzak sunucunun anlayabildiği yerleşik operatörler (`=`, `>`, `<`, `BETWEEN`, `IN`).
2. **Join Pushdown:** Eğer sorgudaki iki dış tablo **aynı dış sunucuda (`SERVER`)** bulunuyorsa, PostgreSQL 9.6+ aralarındaki `JOIN` işlemini yerelde yapmak yerine doğrudan uzak sunucuya tek bir SQL olarak gönderir.
3. **Aggregate Pushdown (`GROUP BY`, `SUM`, `COUNT`):** PostgreSQL 10+ ile birlikte toplama fonksiyonları yerel sunucuya çekilmeden uzak sunucuda hesaplanır.
4. **Ordering Pushdown (`ORDER BY` & `LIMIT`):** Uzaktaki indeks kullanılarak sıralanır ve yalnızca `LIMIT` kadar satır ağdan taşınır.

### 3.2. Pushdown'ı Bozan ve Ağı Kilitleyen Tuzaklar
* **Volatile / Yerel Fonksiyonlar:** Eğer `WHERE` koşulunda yerelde tanımlanmış bir fonksiyon veya `VOLATILE` nitelikli bir ifade (`WHERE olusturma_tarihi > my_local_function()`) kullanırsanız, PostgreSQL uzak sunucuya filtre **gönderemez**. Tablonun tamamını ağ üzerinden çeker ve filtrelemeyi yerelde uygular!
* **Veri Tipi / Collation Uyumsuzluğu:** İki sunucu arasındaki `COLLATION` veya karakter seti farklıysa, metin tabanlı sıralamalar (`ORDER BY`) ve karşılaştırmalar yerel sunucuya devredilir.

### 3.3. Optimizör İstatistikleri ve `ANALYZE` Zorunluluğu

Yerel PostgreSQL motoru, uzak tablonun fiziksel boyutunu bilemez. Varsayılan olarak tabloyu **1000 satır** kabul eder:
* **Tehlike:** Uzaktaki 100 milyonluk tablo yerel bir tabloyla birleştirildiğinde, optimizör bunu 1000 satır sandığı için **Nested Loop Join** planlar ve sorgu saatlerce asılı kalır.
* **DBA Reçetesi:**
  1. `use_remote_estimate 'true'` yapılandırmasıyla sorgu anında uzaktan gerçek maliyet tahminleri çekilir.
  2. Dış tablo oluşturulduktan sonra yerelde mutlaka **`ANALYZE`** çalıştırılmalıdır:
     ```sql
     ANALYZE uzak_muhasebe.faturalar;
     ```
     *(PostgreSQL arka planda uzak tabloya bir `SAMPLE` sorgusu atarak yerel `pg_statistic` tablosunu doldurur).*

---

## 4. Bir DBA'in Bilmesi Gereken 5 Operasyonel Kriz Riski

### 1. Ağ Saturasyonu ve `fetch_size` Felaketi
* **Problem:** Varsayılan `fetch_size` 100 satırdır. 1 milyon satır çeken bir raporlama sorgusu için sunucu uzak makineyle **10.000 kez ağ paket alışverişi (round-trip)** yapar.
* **Sonuç:** Ağ arayüzü (NIC) kilitlenir, TCP gecikmesi (latency) nedeniyle sorgu dakikalar sürer.
* **Çözüm:** Server veya tablo düzeyinde `OPTIONS (fetch_size '10000')` tanımlayın.

### 2. Uzak Bağlantı Tüketimi (Connection Storm)
* **Problem:** Yerel sunucuda çalışan 200 adet istemci oturumu FDW tablosuna dokunduğu anda, uzak PostgreSQL sunucusunda da anında 200 adet bağımsız TCP bağlantısı açılır.
* **Sonuç:** Uzak sunucunun `max_connections` limiti tükenir ve uzak üretim veritabanı kilitlenir.
* **Çözüm:** 
  * Uzak veritabanının önüne mutlaka **PgBouncer (Transaction Pooling)** mimarisi koyun.
  * FDW tanımında `host` olarak doğrudan veritabanını değil, PgBouncer portunu gösterin.

### 3. Asılı Kalan İşlemler (Hanging Transactions) ve Ağ Kopmaları
* **Problem:** Uzak sunucuda uzun süren bir sorgu çalışırken ağ bağlantısı koparsa, yerel oturum kilitli kalabilir (`idle in transaction`).
* **Çözüm:** 
  * Uzak sunucuda bağlantı limitleri koyun:
    ```sql
    ALTER SERVER srv_muhasebe_prod OPTIONS (ADD extensions 'statement_timeout=30000');
    ```
  * İşletim sistemi seviyesinde TCP Keepalive parametrelerini (`tcp_keepalives_idle`, `tcp_keepalives_interval`) sıkılaştırın.

### 4. İki Aşamalı Commit (Two-Phase Commit / 2PC) Sınırı
* **Problem:** Yerel bir transaction içinde hem yerel bir tabloya hem de birden fazla uzak FDW tablosuna `INSERT/UPDATE` yapılıyorsa dağıtık işlem oluşur.
* **Risk:** Tam bu esnada elektrik veya ağ kesilirse atomik bütünlük bozulabilir.
* **Çözüm:** Dağıtık yazma yapılacaksa PostgreSQL kümelerinde `max_prepared_transactions` parametresi aktif edilmeli ve loglar izlenmelidir.

### 5. DDL ve Şema Değişikliklerinin Otomatik Yansımaması
* **Problem:** Uzak sunucudaki `faturalar` tablosundan bir kolon silinir veya veri tipi `INT`'ten `BIGINT`'e değiştirilirse, yerel FDW bunu otomatik algılamaz.
* **Sonuç:** Yerel kullanıcılar sorgu attığında `ERROR: relation "public.faturalar" does not match foreign table` hatasıyla karşılaşır.
* **Çözüm:** Şema değişikliklerinde yerelde tabloyu yeniden import edin:
  ```sql
  IMPORT FOREIGN SCHEMA public LIMIT TO (faturalar) FROM SERVER srv_muhasebe_prod INTO uzak_muhasebe;
  ```

---

## 5. İlgili Konular ve İç Çapraz Referanslar

* 📁 **Dosya Sisteminden Tablo Okuma:** [`04-dosya-ve-sistem-fdw-file-fdw.md`](./04-dosya-ve-sistem-fdw-file-fdw.md)
* 🧩 **FDW ile Sharding ve Dağıtık Bölümleme:** [PostgreSQL Partitioning Kılavuzu](../11-operations-and-containers/01-partitioning-kavrami-ve-kullanimi.md)
* ⚡ **Uzak Bağlantı Yönetimi ve Havuzlama:** [PgBouncer Mimarisi](../12-ha-distributed-and-core/02-connection-pooling-pgbouncer.md)
* 🌐 **Büyük Veri ve S3 Entegrasyonu:** [Lakehouse ve Veri Sanallaştırma](../12-ha-distributed-and-core/10-veri-sanallastirma-ve-lakehouse.md)
* 🚨 **Kriz ve Kilitlenme Yönetimi:** [Kriz Yönetimi ve Runbook'lar](../13-production-and-incidents/01-kriz-yonetimi-ve-runbooklar.md)

## 6. Resmi Kaynaklar ve İleri Okuma

* 📖 [PostgreSQL Official Documentation - postgres_fdw](https://www.postgresql.org/docs/current/postgres-fdw.html)
* 📖 [PostgreSQL Official Documentation - IMPORT FOREIGN SCHEMA](https://www.postgresql.org/docs/current/sql-importforeignschema.html)
* 📖 [PostgreSQL SQL/MED (Management of External Data) Standards](https://wiki.postgresql.org/wiki/SQL/MED)
* 📖 [PostgreSQL Query Optimization with Foreign Data Wrappers](https://www.postgresql.org/docs/current/fdwhandler.html)
