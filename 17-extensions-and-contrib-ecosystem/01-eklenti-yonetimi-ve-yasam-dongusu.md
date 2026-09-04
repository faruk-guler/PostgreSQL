# PostgreSQL Eklenti (Extension) Mimarisi ve Yaşam Döngüsü

PostgreSQL'in diğer ilişkisel veritabanı yönetim sistemlerine (RDBMS) kıyasla en ayırt edici gücü, çekirdeğin (core engine) monolitik olmak yerine **son derece modüler ve genişletilebilir (extensible)** olarak tasarlanmış olmasıdır. 

PostgreSQL'e yeni bir veri tipi, indeksleme algoritması, fonksiyon kütüphanesi veya harici veri kaynağı eklemek için çekirdek kodunu yeniden derlemek gerekmez; tüm bu yetenekler **Eklenti (Extension)** mekanizmasıyla anında veritabanına entegre edilebilir.

---

## 1. Eklenti Mekanizması ve Dosya Mimarisi

Bir PostgreSQL eklentisi dosya sisteminde (`$SHAREDIR/extension`) en az iki temel dosyadan oluşur:

```
/usr/pgsql-16/share/extension/
  ├── citext.control              ◄── Eklenti Tanım ve Metadata Dosyası
  ├── citext--1.4.sql             ◄── İlk Kurulum SQL Betiği
  ├── citext--1.4--1.5.sql        ◄── Sürüm Yükseltme Betiği
  └── citext.so (/usr/pgsql-16/lib/) ◄── C ile Derlenmiş Paylaşımlı Kütüphane (Opsiyonel)
```

### 1.1. Kontrol Dosyası (`.control`) Anatomisi

`citext.control` dosyasının içeriği:

```ini
# citext extension
comment = 'data-type for case-insensitive character strings'
default_version = '1.6'
module_pathname = '$libdir/citext'
relocatable = true
trusted = true
```

| Parametre | Anlamı |
| :--- | :--- |
| `default_version` | Sürüm belirtilmediğinde kurulacak sürüm numarası. |
| `module_pathname` | Çağrılacak C ikili dosyasının (`.so`) disk konumu. |
| `relocatable` | `true` ise eklenti nesneleri istenen şemaya (`ALTER EXTENSION ... SET SCHEMA`) taşınabilir. |
| `trusted` | `true` ise bu eklentiyi kurmak için `superuser` yetkisi gerekmez; veritabanında `CREATE` yetkisi olan normal kullanıcı da kurabilir (PG 13+). |

---

## 2. Eklenti Yaşam Döngüsü Komutları

### 2.1. Kurulum (`CREATE EXTENSION`)

```sql
-- Eklentiyi varsayılan şemaya kurma
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Eklentiyi belirli bir şemaya kurma
CREATE EXTENSION citext SCHEMA utils;

-- Bağımlı eklentileriyle birlikte kurma (CASCADE)
CREATE EXTENSION postgis CASCADE;
```

### 2.2. Sürüm Yükseltme (`ALTER EXTENSION ... UPDATE`)

PostgreSQL majör veya minör sürümü güncellendiğinde, eklentinin yeni özelliklerini ve hata düzeltmelerini devreye almak için:

```sql
-- Eklentiyi varsayılan en son sürüme yükseltme
ALTER EXTENSION citext UPDATE;

-- Belirli bir sürüme geçiş yapma
ALTER EXTENSION postgis UPDATE TO '3.4.2';
```

### 2.3. Kaldırma (`DROP EXTENSION`)

```sql
-- Eklentiyi kaldırma (İçerdiği tipler kullanılmıyorsa)
DROP EXTENSION IF EXISTS citext;

-- Eklentiye bağımlı tüm tablo ve görünümlerle birlikte kaldırma (DİKKAT!)
DROP EXTENSION citext CASCADE;
```

---

## 3. Eklenti Katalog Tabloları ve Sorgulama

PostgreSQL, kurulu ve kurulabilir tüm eklentileri sistem kataloglarında takip eder:

### 3.1. Sisteme Yüklenebilir Eklentileri Listeleme

```sql
SELECT name, default_version, installed_version, comment 
FROM pg_available_extensions 
ORDER BY name;
```

### 3.2. Aktif Veritabanında Kurulu Eklentileri Görme

```sql
SELECT 
    e.extname AS eklenti_adi,
    e.extversion AS kurulu_surum,
    n.nspname AS kuruldugu_sema,
    c.description AS aciklama
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
LEFT JOIN pg_description c ON c.objoid = e.oid;
```

psql kısayolu ile listelemek için:
```text
\dx
```

### 3.3. Eklentinin Sahip Olduğu Nesneleri Görme

Bir eklenti sisteme onlarca fonksiyon ve tip ekleyebilir. Hangi nesnelerin bu eklentiye ait olduğunu öğrenmek için:

```sql
SELECT 
    classid::regclass AS nesne_turu,
    objid::regprocedure AS nesne_adi
FROM pg_depend 
WHERE refobjid = (SELECT oid FROM pg_extension WHERE extname = 'citext');
```

---

## 4. `shared_preload_libraries` Gerektiren Eklentiler

Standart eklentiler sorgu anında dinamik olarak belleğe yüklenir. Ancak veritabanı motorunun kanca (hook) noktalarına bağlanan veya arka plan işçisi (background worker) başlatan derin sistem eklentileri, **PostgreSQL başlatılırken** belleğe alınmak zorundadır.

Örnek eklentiler:
- `pg_stat_statements` (Sorgu performans istatistikleri)
- `pgaudit` (Güvenlik denetim loglaması)
- `pg_cron` (Veritabanı içi zamanlanmış görevler)
- `timescaledb` (Zaman serisi motoru)
- `auto_explain` (Yavaş sorguları otomatik EXPLAIN ile loglama)

### 4.1. Yapılandırma (`postgresql.conf`)

```ini
shared_preload_libraries = 'pg_stat_statements, pgaudit, auto_explain'
```

> [!IMPORTANT]
> `shared_preload_libraries` parametresine eklenen eklentilerin aktif olabilmesi için PostgreSQL servisinin mutlaka yeniden başlatılması (`systemctl restart postgresql`) şarttır. `reload` yetersizdir.

---

## 5. Eklenti Güvenliği ve Yetkilendirme

Geçmişte eklenti kurmak yalnızca `superuser` ayrıcalığına sahipti. Bu durum, yazılımcıların veya uygulama kullanıcılarının test ve geliştirme ortamlarında DBA bağımlılığına yol açardı.

### 5.1. Güvenilir Eklentiler (Trusted Extensions)

PostgreSQL 13 ile birlikte gelen "Güvenilir Eklentiler" özelliği sayesinde, kontrol dosyasında `trusted = true` olarak işaretlenen eklentiler, süper yetkili olmayan ancak ilgili veritabanında `CREATE` hakkı olan kullanıcılara açılabilir:

```sql
-- Veritabanı sahibi olan standart kullanıcı:
\c eticaret_db uygulama_usr

-- Superuser olmadan kurulabilir:
CREATE EXTENSION citext;
CREATE EXTENSION pgcrypto;
```

Eğer bir eklenti dosya sistemine doğrudan erişiyorsa (örn: `file_fdw`, `adminpack`), asla `trusted` yapılamaz ve yalnızca `superuser` tarafından yönetilebilir.
