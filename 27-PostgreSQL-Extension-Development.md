# 27-PostgreSQL-Extension-Development

**Kendi PostgreSQL Eklentinizi Yazın!**

PostgreSQL'in en büyük gücü **Extensibility** (Genişletilebilirlik) özelliğidir. Bir eklenti (extension) ile veritabanına yeni veri tipleri, fonksiyonlar, index metodları ve hatta arka plan işçileri ekleyebilirsiniz.

---

## 1. Extension Anatomisi

Bir eklenti en az iki dosyadan oluşur:

1. **Control File (`mylib.control`):** Metadata (versiyon, açıklama vb.)
2. **SQL Script (`mylib--1.0.sql`):** CREATE FUNCTION, CREATE TYPE vb. komutlar

### Dosya Konumu

Linux sistemlerde genellikle:
`/usr/pgsql-16/share/extension/`

---

## 2. İlk Eklentimiz: `audit_log`

Basit bir "Audit" eklentisi yapalım. Tablolardaki değişiklikleri loglayan bir fonksiyon içersin.

### Adım 1: Control Dosyası (`audit_log.control`)

```ini
# audit_log extension
comment = 'Simple table auditing extension'
default_version = '1.0'
relocatable = true
module_pathname = '$libdir/audit_log'
```

### Adım 2: SQL Dosyası (`audit_log--1.0.sql`)

```sql
-- Şikayet etmesin (psql)
\echo Use "CREATE EXTENSION audit_log" to load this file. \quit

CREATE TABLE audit_history (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT now(),
    username TEXT DEFAULT current_user
);

CREATE OR REPLACE FUNCTION audit_trigger_func() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_history (table_name, operation, old_data)
        VALUES (TG_TABLE_NAME, 'DELETE', row_to_json(OLD)::JSONB);
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_history (table_name, operation, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'UPDATE', row_to_json(OLD)::JSONB, row_to_json(NEW)::JSONB);
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_history (table_name, operation, new_data)
        VALUES (TG_TABLE_NAME, 'INSERT', row_to_json(NEW)::JSONB);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

### Adım 3: Kurulum ve Test

Bu dosyaları extension dizinine kopyaladıktan sonra:

```sql
CREATE EXTENSION audit_log;

-- Kullanım
CREATE TRIGGER trg_audit_users
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
```

---

## 3. C Dili ile Eklenti (Advanced)

Performans kritik olduğu zaman C ile eklenti yazılır.

**Gereksinimler:** `postgresql-devel` (veya `libpq-dev`), `gcc`, `make`.

### Örnek: `my_add` Fonksiyonu

**my_ext.c:**

```c
#include "postgres.h"
#include "fmgr.h"
#include "utils/geo_decls.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(my_add);

Datum
my_add(PG_FUNCTION_ARGS)
{
    int32 arg1 = PG_GETARG_INT32(0);
    int32 arg2 = PG_GETARG_INT32(1);

    PG_RETURN_INT32(arg1 + arg2);
}
```

**Makefile:**

```makefile
MODULES = my_ext
EXTENSION = my_ext
DATA = my_ext--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

**my_ext--1.0.sql:**

```sql
CREATE FUNCTION my_add(integer, integer) RETURNS integer
AS 'MODULE_PATHNAME', 'my_add'
LANGUAGE C STRICT;
```

**Compile & Install:**

```bash
make
sudo make install
```

---

## 4. Background Workers

Eklentiler arka planda çalışan süreçler (process) başlatabilir. Cron job gibi çalışırlar ama veritabanı yaşam döngüsüne dahildirler.

**Kullanım Alanları:**

- Düzenli veri temizliği
- Harici sistemden veri çekme (ETL)
- Monitoring agent

```c
/* _PG_init içinde worker register edilir */
void _PG_init(void) {
    BackgroundWorker worker;
    memset(&worker, 0, sizeof(worker));
    worker.bgw_flags = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
    worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
    /* ... detaylar ... */
    RegisterBackgroundWorker(&worker);
}
```

---

## 5. Hooks (Kancalar)

PostgreSQL'in çekirdek işlemlerine müdahale edebilirsiniz:

- **Planner Hook:** Sorgu planı oluşurken araya gir (örn: `pg_hint_plan`)
- **Executor Hook:** Sorgu çalışmadan önce/sonra (örn: `pg_stat_statements`)
- **ProcessUtility Hook:** DDL komutlarını yakala

---

## 6. PGXN (PostgreSQL Extension Network)

Yazdığınız eklentiyi [PGXN.org](https://pgxn.org/) üzerinde yayınlayarak toplulukla paylaşabilirsiniz.

---

## Best Practices

1. **Schema Kullanımı:** Eklenti nesnelerini public şemasına doldurmayın. `@extschema@` değişkenini kullanın.
2. **Upgrade Scriptleri:** `my_ext--1.0--1.1.sql` scriptleri ile `ALTER EXTENSION UPDATE` desteği verin.
3. **Test:** `pg_regress` ile regresyon testleri yazın.
