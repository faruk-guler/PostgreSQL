# 03-PostgreSQL-Basic-Operations

PostgreSQL yönetiminin kalbi `psql` komut satırı aracıdır. Grafik arayüzler (pgAdmin, DBeaver) güzeldir, ancak sunucu çöktüğünde veya script yazarken `psql` hayat kurtarır.

---

## 1. psql Mastery (Komut Satırı Sanatı)

`psql`, SQL komutlarını çalıştırmanın yanı sıra "Meta-Komutlar" (backslash `\` ile başlayanlar) sunar.

### En Sık Kullanılan Meta-Komutlar

| Komut | Açıklama |
| :--- | :--- |
| `\l` | List Databases (Veritabanlarını listele) |
| `\c db_name` | Connect (Başka bir veritabanına bağlan) |
| `\dt+` | List Tables (Sadece tabloları detaylı göster - boyut dahil) |
| `\du` | List Users (Kullanıcıları ve yetkilerini listele) |
| `\dn` | List Schemas (Şemaları listele) |
| `\d table_name` | Describe (Tablo yapısını, indexleri göster) |
| `\x auto` | Expanded Display (Çıktı ekrana sığmazsa dikey moda geçer - Çok yararlı!) |
| `\timing on` | Sorgu süresini göster (Performance tuning için şart) |
| `\q` | Quit (Çıkış) |

### Trick: .pgpass Dosyası (Şifresiz Giriş)

Otomasyon scriptlerinde veya hızlı girişte şifre sormasını engellemek için `home` dizininde `.pgpass` dosyası oluşturulur.

**Format:** `hostname:port:database:username:password`

```bash
# Dosya oluştur (Linux)
echo "localhost:5432:*:postgres:gizliSifre" > ~/.pgpass
chmod 600 ~/.pgpass

# Artık şifre sormaz:
psql -U postgres
```

---

## 2. Roles & Privileges (Güvenlik Yönetimi)

PostgreSQL'de "User" ve "Group" kavramı yoktur, hepsi "Role"dür. `LOGIN` yetkisi olan role "User" denir.

### a. Rol Oluşturma Best Practice

Production ortamında asla uygulama bağlantısı için `postgres` (superuser) kullanmayın!

```sql
-- 1. Yetkisiz bir kullanıcı oluştur
CREATE ROLE app_user WITH LOGIN PASSWORD 'GüçlüBirŞifre';

-- 2. Yetkileri manuel ver (Permission Denied by Default)
-- Veritabanına bağlanabilsin
GRANT CONNECT ON DATABASE my_database TO app_user;

-- Şemayı kullanabilsin
GRANT USAGE ON SCHEMA public TO app_user;

-- Tablolarda işlem yapabilsin
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
```

### b. ALTER DEFAULT PRIVILEGES (Geleceği Yönetmek)

Bu komut PostgreSQL'de en çok unutulan ama en kritik güvenlik ayarıdır. Yukarıdaki `GRANT` komutları sadece **mevcut** tabloları etkiler. Yeni oluşturulacak tablolar için yetki devretmeniz gerekir.

```sql
-- "postgres" kullanıcısı tarafından oluşturulacak her yeni tablo için
-- "app_user"a otomatik okuma yetkisi ver.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
GRANT SELECT ON TABLES TO app_user;
```

---

## 3. Logical Organization (Mantıksal Yapı)

PostgreSQL hiyerarşisi şöyledir:
**Instance (Cluster) -> Database -> Schema -> Table**

### Neden Schema (Şema) Kullanmalıyız?

MySQL'in aksine, PostgreSQL'de bir veritabanı içinde birden fazla "namespace" (alan adı) oluşturabilirsiniz. Buna Schema denir.

- **Kullanım Alanı 1 (Multi-Tenancy):** Aynı veritabanında `musteri_a` şeması ve `musteri_b` şeması oluşturup aynı tablo isimlerini (`users`, `orders`) çakışmadan kullanabilirsiniz.
- **Kullanım Alanı 2 (Organizasyon):** `public` şemasına her şeyi yığmak yerine, `app.users`, `log.audit`, `finance.invoices` gibi ayırabilirsiniz.

```sql
-- Şema oluştur
CREATE SCHEMA finance;

-- Tablo oluştur (Şema adıyla)
CREATE TABLE finance.invoices (
    id SERIAL PRIMARY KEY,
    amount NUMERIC(10, 2)
);

-- Hangi şemada olduğunuzu görün
SHOW search_path;

-- Varsayılan şemayı değiştir
SET search_path TO finance, public;

-- Yeni tabloya veriyi kopyala
INSERT INTO archive_logs SELECT * FROM logs WHERE logdate < '2023-01-01';
```

---

## 4. Bulk Data Loading (COPY Komutu)

Büyük miktarda veriyi PostgreSQL'e aktarmanın en hızlı yolu `COPY` komutudur. `INSERT` komutundan **10-100x daha hızlıdır**.

### CSV'den Veri Yükleme

```sql
-- Tablo oluştur
CREATE TABLE products (
    id INT,
    name TEXT,
    price NUMERIC
);

-- CSV dosyasından yükle
COPY products FROM '/tmp/products.csv' WITH (FORMAT csv, HEADER true);

-- Veya sadece belirli kolonları yükle
COPY products (name, price) FROM '/tmp/products.csv' CSV HEADER;
```

### PostgreSQL'den CSV'ye Aktarma

```sql
-- Tüm tabloyu CSV'ye aktar
COPY products TO '/tmp/export.csv' WITH (FORMAT csv, HEADER true);

-- Sorgu sonucunu CSV'ye aktar
COPY (SELECT * FROM products WHERE price > 100) TO '/tmp/expensive.csv' CSV HEADER;
```

### psql ile COPY (\copy)

Sunucu yerine **istemci** tarafındaki dosyayı kullanmak için `\copy` kullanın (backslash ile):

```bash
# psql içinde
\copy products FROM 'C:/data/products.csv' CSV HEADER
```

### Performans İpuçları

1. **Index'leri geçici olarak kaldırın:** Büyük yüklemeden önce index'leri drop edin, sonra yeniden oluşturun.
2. **UNLOGGED tablo kullanın:** Geçici yüklemeler için WAL yazmayı kapatın.

   ```sql
   CREATE UNLOGGED TABLE temp_load (...);
   ```

3. **maintenance_work_mem arttırın:** Index oluşturma hızlanır.

---

## 5. Monitoring & Maintenance (İzleme ve Bakım)

Bir DBA (Database Administrator) olarak gününüzün çoğu bu sorgularla geçer.

### a. Şu an kim ne yapıyor? (pg_stat_activity)

```sql
SELECT pid, usename, client_addr, state, query
FROM pg_stat_activity
WHERE state != 'idle';
```

*Bu sorgu, o anda çalışan veya kilitlenmiş sorguları gösterir.*

### b. Tablo Şişkinliği (Diskte kapladığı yer)

```sql
SELECT schemaname, relname, pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 10;
```

### c. Kilitleme Sorunlarını Bulma (Blocking Locks)

Bazen bir işlem diğerini bekletir. Bunu bulmak için:

```sql
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename  AS blocked_user,
       blocking_locks.pid     AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocking_activity.query   AS blocking_statement
FROM  pg_catalog.pg_locks       blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks       blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

---

## 6. Connection Strings & Parameters

Uygulamanızın veritabanına nasıl bağlandığını bilmek, troubleshooting ve güvenlik için kritiktir.

### a. Standard Connection String (libpq Format)

PostgreSQL'in resmi C kütüphanesi (libpq) bu formatı kullanır. Çoğu driver (psycopg, pgx, JDBC) bunu destekler.

```bash
postgresql://[user[:password]@][host][:port][/dbname][?param1=value1&...]

# Örnekler
postgresql://postgres:mypass@localhost:5432/mydb
postgresql://app_user@192.168.1.100/production
postgresql://user@/mydb  # Unix socket (port yok, lokal bağlantı)
postgresql://user@localhost/mydb?sslmode=require&application_name=web_app
```

### b. Legacy Connection String (Key=Value Format)

Bazı eski uygulamalar bu formatı kullanır:

```bash
host=localhost port=5432 dbname=mydb user=postgres password=secret sslmode=require
```

### c. JDBC URL

Java uygulamaları için:

```
jdbc:postgresql://host:port/database?param=value

# Örnek
jdbc:postgresql://localhost:5432/mydb?ssl=true&sslfactory=org.postgresql.ssl.NonValidatingFactory
```

### d. Önemli Connection Parametreleri

| Parametre | Değerler | Açıklama | Önerilen Production Değeri |
|:----------|:---------|:---------|:---------------------------|
| `sslmode` | disable, allow, prefer, **require**, verify-ca, **verify-full** | SSL zorlama seviyesi | `require` veya `verify-full` |
| `application_name` | string | `pg_stat_activity`'de görünür, debugging için | Uygulama adı (örn: `web_backend`) |
| `connect_timeout` | seconds | Bağlantı timeout (varsayılan: sınırsız!) | `10` |
| `options` | `-c param=value` | Session-level parametreler | `-c statement_timeout=30s` |
| `sslrootcert` | path | CA sertifika dosyası (`verify-full` için gerekli) | `/etc/ssl/certs/ca.crt` |
| `sslcert` | path | Client sertifikası (Mutual TLS için) | `/app/certs/client.crt` |
| `sslkey` | path | Client private key | `/app/certs/client.key` |

### e. Production Connection String Örneği

```python
# Python (psycopg3)
import psycopg

conn = psycopg.connect(
    "postgresql://app_user@prod-db.example.com:5432/mydb"
    "?sslmode=verify-full"
    "&sslrootcert=/etc/ssl/certs/ca-certificates.crt"
    "&application_name=web_app_v2"
    "&connect_timeout=10"
    "&options=-c statement_timeout=60s"
)
```

```go
// Go (pgx)
connString := "postgres://app_user@prod-db:5432/mydb?sslmode=verify-full&application_name=api_server"
dbpool, err := pgxpool.New(context.Background(), connString)
```

### f. Environment Variables

Güvenlik için password'u connection string'den ayırın:

```bash
# .env file
export PGHOST=prod-db.example.com
export PGPORT=5432
export PGDATABASE=mydb
export PGUSER=app_user
export PGPASSWORD=secret123  # AMAN! Git'e eklemeyin!
export PGSSLMODE=require

# Uygulama sadece şunu yapar
psql  # Otomatik environment'tan alır
```

### g. Troubleshooting: Connection Refused

```bash
# 1. PostgreSQL çalışıyor mu?
systemctl status postgresql

# 2. Port dinliyor mu?
sudo ss -tlnp | grep 5432

# 3. Firewall açık mı?
sudo firewall-cmd --list-ports  # RHEL/Rocky
sudo ufw status  # Ubuntu

# 4. pg_hba.conf izin veriyor mu?
tail -20 /var/lib/pgsql/data/pg_hba.conf

# 5. postgresql.conf listen ediyor mu?
grep listen_addresses /var/lib/pgsql/data/postgresql.conf
# Uzak bağlantı için: listen_addresses = '*'
```

> [!TIP]
> **Production'da `application_name` kullanın!** Aynı anda 100 bağlantı varken hangi uygulama/servis olduğunu anlamanız hayat kurtarır:
>
> ```sql
> SELECT application_name, count(*) 
> FROM pg_stat_activity 
> GROUP BY application_name;
> 
> -- Çıktı:
> -- web_backend        | 45
> -- api_server         | 30
> -- batch_processor    | 5
> ```
