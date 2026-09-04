# PL/pgSQL Programlama, Fonksiyonlar ve Tetikleyiciler

> **Bölüm Kapsamı:** Prosedürel SQL, Stored Procedure vs Function, DML Trigger'lar ve Event Trigger Mimarisi

---

## 1. PL/pgSQL Temelleri

PL/pgSQL, Oracle'ın PL/SQL diline benzer, blok tabanlı bir dildir. SQL ile entegre çalışır.

### İlk Fonksiyon

```sql
CREATE OR REPLACE FUNCTION calculate_discount(price NUMERIC, discount_percent NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN price * (1 - discount_percent / 100);
END;
$$ LANGUAGE plpgsql;

-- Kullanım
SELECT calculate_discount(100, 20); -- 80 döner
```

### Değişkenler ve Kontrol Yapıları

```sql
CREATE OR REPLACE FUNCTION classify_score(score INT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    IF score >= 90 THEN
        result := 'Mükemmel';
    ELSIF score >= 75 THEN
        result := 'İyi';
    ELSIF score >= 50 THEN
        result := 'Orta';
    ELSE
        result := 'Zayıf';
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;
```

### Döngüler (LOOP, FOR, WHILE)

```sql
CREATE OR REPLACE FUNCTION fibonacci(n INT)
RETURNS INT AS $$
DECLARE
    a INT := 0;
    b INT := 1;
    temp INT;
    i INT;
BEGIN
    IF n <= 1 THEN RETURN n; END IF;
    
    FOR i IN 2..n LOOP
        temp := a + b;
        a := b;
        b := temp;
    END LOOP;
    
    RETURN b;
END;
$$ LANGUAGE plpgsql;
```

### Dinamik SQL ve SQL Injection Koruması (`EXECUTE ... USING` ve `format()`)

Tablo veya kolon adlarının çalışma zamanında dinamik olarak belirlendiği sorgularda doğrudan string birleştirme (`||`) yapmak SQL Injection saldırılarına kapı aralar. PostgreSQL bunun için `format()` fonksiyonunu sunar:
- **`%I` (Identifier):** Tablo, şema veya kolon adını güvenle çift tırnak içine alır.
- **`%L` (Literal):** Değerleri güvenle tek tırnak içine alır ve kaçış karakterlerini temizler.
- **`USING`:** Değer parametrelerini parametreli sorgu olarak geçirir.

```sql
CREATE OR REPLACE FUNCTION dynamic_table_count(p_table_name TEXT, p_status TEXT)
RETURNS BIGINT AS $$
DECLARE
    v_total BIGINT;
    v_sql TEXT;
BEGIN
    -- %I tablo adı için, $1 ise USING parametresi için güvenlidir
    v_sql := format('SELECT count(*) FROM %I WHERE status = $1', p_table_name);
    
    EXECUTE v_sql INTO v_total USING p_status;
    RETURN v_total;
END;
$$ LANGUAGE plpgsql;

-- Güvenli çağrı:
SELECT dynamic_table_count('orders', 'completed');
```

---

## 2. Functions vs Procedures (v11+)

PostgreSQL 11'den itibaren `PROCEDURE` desteği gelmiştir.

### Farkları

| Özellik | Function | Procedure |
| :-------- | :--------- | :---------- |
| Transaction Kontrolü | Yok | Var (`COMMIT`/`ROLLBACK` yapabilir) |
| Geri Dönüş Değeri | Zorunlu (`RETURNS`) | Opsiyonel (`OUT` parametreler) |
| Çağırma | `SELECT function()` | `CALL procedure()` |

### Procedure Örneği (Transaction içinde)

```sql
CREATE OR REPLACE PROCEDURE process_orders()
LANGUAGE plpgsql AS $$
DECLARE
    order_rec RECORD;
BEGIN
    FOR order_rec IN SELECT * FROM pending_orders LOOP
        BEGIN
            -- Her siparişi işle
            INSERT INTO processed_orders VALUES (order_rec.*);
            DELETE FROM pending_orders WHERE id = order_rec.id;
            COMMIT; -- Her siparişten sonra commit (atomicity kırar ama bazı senaryolarda gerekli)
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Order % failed: %', order_rec.id, SQLERRM;
            ROLLBACK;
        END;
    END LOOP;
END;
$$;

CALL process_orders();
```

---

## 3. Triggers (Tetikleyiciler)

Trigger, bir tabloda belirli bir olay (INSERT/UPDATE/DELETE) gerçekleştiğinde otomatik olarak çalışan fonksiyondur.

### BEFORE Trigger (Row-Level)

```sql
-- Fonksiyon tanımla
CREATE OR REPLACE FUNCTION update_modified_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW; -- Değiştirilmiş satırı döndür
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı tabloya bağla
CREATE TRIGGER users_update_timestamp
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_modified_timestamp();
```

### AFTER Trigger (Audit Log)

```sql
CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT,
    operation TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION log_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW)::jsonb);
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER products_audit
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION log_changes();
```

### c. INSTEAD OF Triggers (View'ları Güncellenebilir Kılma)

Birden fazla tablonun birleşiminden (`JOIN`) oluşan karmaşık View'lar doğrudan `INSERT`, `UPDATE` veya `DELETE` komutlarını kabul etmez (PostgreSQL hata verir). `INSTEAD OF` tetikleyicisi, view'a yapılan bu müdahaleyi araya girerek yakalar ve verileri arka plandaki gerçek tablolara dağıtır:

```sql
-- 1. View Oluştur
CREATE OR REPLACE VIEW v_user_details AS
SELECT u.id AS user_id, u.username, p.phone_number
FROM users u
JOIN user_profiles p ON u.id = p.user_id;

-- 2. INSTEAD OF Trigger Fonksiyonu
CREATE OR REPLACE FUNCTION process_user_details_insert()
RETURNS TRIGGER AS $$
DECLARE
    new_user_id INT;
BEGIN
    -- users tablosuna yaz
    INSERT INTO users (username) VALUES (NEW.username) RETURNING id INTO new_user_id;
    -- user_profiles tablosuna yaz
    INSERT INTO user_profiles (user_id, phone_number) VALUES (new_user_id, NEW.phone_number);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. View üzerine bağla
CREATE TRIGGER trg_user_details_insert
INSTEAD OF INSERT ON v_user_details
FOR EACH ROW EXECUTE FUNCTION process_user_details_insert();

-- Artık View üzerinden direkt INSERT yapılabilir!
INSERT INTO v_user_details (username, phone_number) VALUES ('ayse_y', '+905551234567');
```

### d. Geçiş Tabloları (Transition Tables - Küme Bazlı Tetikleyici)

`FOR EACH ROW` tetikleyicileri milyon satırlık bir `UPDATE` işleminde fonksiyonu 1 milyon kez tetikler ve sistemi felç eder. PostgreSQL 10 ile gelen **Transition Tables**, etkilenen tüm satırları geçici bir tablo (`NEW TABLE` ve `OLD TABLE`) olarak tek seferde statement düzeyinde yakalamanızı sağlar:

```sql
CREATE OR REPLACE FUNCTION audit_bulk_price_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Değişen tüm satırları tek seferde topluca audit tablosuna bas
    INSERT INTO price_audit (product_id, old_price, new_price, changed_at)
    SELECT n.id, o.price, n.price, NOW()
    FROM new_products_table n
    JOIN old_products_table o ON n.id = o.id
    WHERE n.price != o.price;

    RETURN NULL; -- Statement trigger'lar NULL döner
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bulk_audit
AFTER UPDATE ON products
REFERENCING OLD TABLE AS old_products_table NEW TABLE AS new_products_table
FOR EACH STATEMENT EXECUTE FUNCTION audit_bulk_price_changes();
```

---

## 4. Event Triggers (DDL İzleme)

Normal trigger'lar DML (INSERT/UPDATE/DELETE) izler. Event Trigger ise DDL (CREATE, ALTER, DROP) izler.

```sql
CREATE OR REPLACE FUNCTION prevent_table_drop()
RETURNS event_trigger AS $$
BEGIN
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Sadece postgres kullanıcısı tablo silebilir!';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER block_drop_table
ON ddl_command_start
WHEN TAG IN ('DROP TABLE')
EXECUTE FUNCTION prevent_table_drop();
```

---

## 5. Best Practices

### a. Exception Handling

```sql
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Sıfıra bölme hatası!';
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

### b. STABLE vs VOLATILE vs IMMUTABLE

Fonksiyon tanımlarken performans için doğru volatility belirtmek önemlidir:

- **IMMUTABLE:** Aynı inputlar için her zaman aynı output (örn: matematiksel fonksiyonlar). Sorgu planlayıcı sonucu cache'ler.
- **STABLE:** Tek bir statement içinde aynı sonucu döner ama farklı statement'larda değişebilir (örn: `CURRENT_TIMESTAMP`).
- **VOLATILE:** Her çağrıda farklı sonuç dönebilir (örn: `random()`). İndeks kullanımını engelleyebilir.

```sql
CREATE OR REPLACE FUNCTION get_random_number()
RETURNS INT AS $$
BEGIN
    RETURN floor(random() * 100)::INT;
END;
$$ LANGUAGE plpgsql VOLATILE;
```

> [!WARNING]
> Trigger'ları dikkatli kullanın. Yanlış tasarlanmış bir trigger, basit bir INSERT'i çok yavaşlatabilir (Cascade effect).
