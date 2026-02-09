# 17-PostgreSQL-Migration-Integration

Mevcut bir veritabanından (MySQL, Oracle, MSSQL) PostgreSQL'e geçiş yapmak teknik ve stratejik bir süreçtir. Bu doküman, başarılı bir migrasyon için gereken adımları ve yaygın tuzakları anlatır.

---

## 1. MySQL'den PostgreSQL'e Geçiş

### Temel Farklar

| Özellik | MySQL | PostgreSQL |
|:--------|:------|:-----------|
| `AUTO_INCREMENT` | Destekleniyor | `SERIAL` veya `IDENTITY` kullan |
| Büyük/Küçük Harf | Case-insensitive (varsayılan) | Case-sensitive (`LOWER()` ile sarmalayın) |
| Limit Sytax | `LIMIT 10 OFFSET 20` | Aynısı ama `OFFSET` önce yazılabilir |
| `ENUM` Tipi | Sütun bazında | Global tip olarak tanımlanır |
| Boolean | `TINYINT(1)` | Gerçek `BOOLEAN` tipi var |

### Migrasyon Araçları

#### a. pgLoader (Önerilen)

`pgLoader`, MySQL'den PostgreSQL'e veriyi otomatik dönüştürerek taşır.

```bash
# RHEL/Rocky Linux
dnf install pgloader

# Migrasyon komutu
pgloader mysql://user:pass@localhost/mydb postgresql://user:pass@localhost/newdb

# Detaylı kontrol için custom config
cat > migration.load <<EOF
LOAD DATABASE
    FROM mysql://root:root@localhost/wordpress
    INTO postgresql://postgres:postgres@localhost/wordpress
WITH include drop, create tables, create indexes, reset sequences
SET maintenance_work_mem to '512MB', work_mem to '64MB'
CAST type datetime to timestamptz drop default drop not null using zero-dates-to-null;
EOF

pgloader migration.load
```

#### b. Foreign Data Wrapper (FDW) Yöntemi

MySQL'i PostgreSQL'den direkt sorgulamak için `mysql_fdw`.

```sql
CREATE EXTENSION mysql_fdw;

CREATE SERVER mysql_server
FOREIGN DATA WRAPPER mysql_fdw
OPTIONS (host '192.168.1.100', port '3306');

CREATE USER MAPPING FOR postgres
SERVER mysql_server
OPTIONS (username 'root', password 'pass');

IMPORT FOREIGN SCHEMA wordpress
FROM SERVER mysql_server
INTO public;

-- Artık MySQL tabloları PostgreSQL'de görünür. Veriyi INSERT-SELECT ile taşıyın.
INSERT INTO new_posts SELECT * FROM old_posts;
```

---

## 2. Oracle'dan PostgreSQL'e Geçiş

Oracle'dan PostgreSQL'e geçiş daha karmaşıktır çünkü Oracle çok fazla proprietary özelliğe sahiptir (PL/SQL paketleri, Sequence syntax vb.).

### ora2pg (Oracle to PostgreSQL Migrator)

```bash
# Kurulum
dnf install ora2pg

# Config dosyası oluştur
ora2pg --init_project myproject
cd myproject

# config/ora2pg.conf dosyasını düzenle
ORACLE_DSN      dbi:Oracle:host=192.168.1.100;sid=ORCL
ORACLE_USER     system
ORACLE_PWD      password
SCHEMA          HR
TYPE            TABLE,VIEW,SEQUENCE,PROCEDURE

# Schema export
ora2pg -c config/ora2pg.conf -t TABLE -o schema.sql

# Data export
ora2pg -c config/ora2pg.conf -t COPY -o data.sql

# PostgreSQL'e import
psql -U postgres -d newdb -f schema/tables/schema.sql
psql -U postgres -d newdb -f data/data.sql
```

### PL/SQL → PL/pgSQL Dönüşümü

Oracle'ın PL/SQL'i ile PostgreSQL'in PL/pgSQL'i benzer ama bazı farklar vardır:

| Oracle | PostgreSQL |
|:-------|:-----------|
| `SYSDATE` | `CURRENT_TIMESTAMP` |
| `NVL(a, b)` | `COALESCE(a, b)` |
| `DECODE()` | `CASE` ifadesi |
| Paketler (Packages) | Şemalar (Schemas) ile organize edin |

---

## 3. MSSQL'den PostgreSQL'e Geçiş

Microsoft SQL Server'dan geçişte dikkat edilmesi gereken noktalar:

### T-SQL vs PL/pgSQL

| MSSQL | PostgreSQL |
|:------|:-----------|
| `IDENTITY(1,1)` | `SERIAL` veya `IDENTITY` |
| `GETDATE()` | `CURRENT_TIMESTAMP` |
| `TOP 10` | `LIMIT 10` |
| `[BracketedIdentifiers]` | `"DoubleQuoted"` |
| `@@ROWCOUNT` | `GET DIAGNOSTICS row_count = ROW_COUNT;` |

### SSIS Replacement (ETL)

MSSQL'deki SSIS (Integration Services) için PostgreSQL'de alternatifler:

- **Apache Airflow:** Modern, Python-based ETL orkestrasyon aracı.
- **Pentaho Data Integration (Kettle):** Açık kaynak ETL aracı.
- **pg_cron:** Basit zamanlı görevler için yeterli.

---

## 4. Data Validation (Migrasyon Sonrası Doğrulama)

Migrasyon tamamlandıktan sonra veri bütünlüğünü doğrulamak şarttır.

### Row Count Karşılaştırması

```sql
-- Kaynak (MySQL)
SELECT COUNT(*) FROM users;

-- Hedef (PostgreSQL)
SELECT COUNT(*) FROM users;
```

### Checksum ile Karşılaştırma

```sql
-- MySQL
SELECT MD5(CONCAT_WS(',', id, name, email)) AS hash FROM users ORDER BY id;

-- PostgreSQL
SELECT MD5(CONCAT_WS(',', id::TEXT, name, email)) AS hash FROM users ORDER BY id;

-- Hash'leri diffleyin (Python/Bash script ile)
```

### Foreign Key Bütünlük Kontrolü

```sql
-- Yetim kayıtları bul (Foreign key olmayan satırlar)
SELECT * FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id
WHERE c.id IS NULL;
```

---

## 5. ETL Patterns (Extract, Transform, Load)

### Pattern 1: Batch Processing (Toplu İşlem)

Büyük veri setlerini küçük parçalar halinde taşıyın.

```sql
-- 100K kayıtlık parçalar
DO $$
DECLARE
    offset_val INT := 0;
    batch_size INT := 100000;
BEGIN
    LOOP
        INSERT INTO new_table
        SELECT * FROM foreign_table
        LIMIT batch_size OFFSET offset_val;
        
        EXIT WHEN NOT FOUND;
        offset_val := offset_val + batch_size;
        COMMIT;
    END LOOP;
END $$;
```

### Pattern 2: Change Data Capture (CDC)

Sadece değişen verileri taşımak için `updated_at` timestamp kullanın.

```sql
-- Son senkronizasyondan sonraki değişiklikler
SELECT * FROM source_table
WHERE updated_at > '2024-05-01 10:00:00';
```

### Pattern 3: Incremental Load

İlk seferde full yük, sonrasında sadece yeni kayıtları ekleyin (UPSERT).

```sql
INSERT INTO target_table (id, name, email)
SELECT id, name, email FROM source_table
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, email = EXCLUDED.email;
```

---

## 6. Best Practices

1. **Test Ortamında Dene:** Production'a migrasyon yapmadan, tam bir copy üzerinde test edin.
2. **Downtime Planlayın:** Sıfır-downtime migrasyon için Logical Replication kullanın.
3. **Performans Testi:** Migrasyon sonrası sorguları tekrar benchmark edin (`EXPLAIN ANALYZE`).
4. **İstatistikleri Güncelleyin:** `VACUUM ANALYZE` çalıştırın ki sorgu planlayıcı doğru kararlar versin.
