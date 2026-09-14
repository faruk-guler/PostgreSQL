# PL/pgSQL, Fonksiyonlar ve Prosedürler

PostgreSQL'de iş mantığını (Business Logic) veritabanı katmanında (Sunucu tarafında) çalıştırmak için SQL komutlarına prosedürel kontrol yapıları (`IF/ELSE`, `LOOP`, `EXCEPTION`) ekleyen **PL/pgSQL** dili kullanılır.

PL/pgSQL'in tasarım amaçları:
- Fonksiyon ve tetikleyici yazmakta kullanılabilmesi
- SQL diline kontrol yapıları ekleyebilmesi
- Karmaşık hesaplamalar yapabilmesi
- Tüm kullanıcı tanımlı tipleri, fonksiyonları ve operatörleri miras alabilmesi

> [!NOTE]
> PostgreSQL 9.0 ve sonrasında PL/pgSQL varsayılan olarak kurulmaktadır.

---

## 1. PL/pgSQL Dilinin Yapısı ve Blok Yapısı

PL/pgSQL blok yapılı bir dildir. Fonksiyonun gövdesi **blok** olarak adlandırılır:

```sql
[ <<etiket>> ]
[ DECLARE
    tanımlamalar ]
BEGIN
    ifadeler
END [ etiket ];
```

**Tam örnek:**
```sql
DO $$ 
DECLARE
    kullanici_adi VARCHAR := 'Ahmet';
    satis_tutari NUMERIC;
BEGIN
    SELECT tutar INTO satis_tutari FROM satislar WHERE isim = kullanici_adi;
    
    IF satis_tutari > 1000 THEN
        RAISE NOTICE '% adlı kullanıcının satışı 1000''den büyük.', kullanici_adi;
    END IF;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'Kayıt bulunamadı!';
END $$;
```

> [!NOTE]
> `BEGIN / END` anahtar sözcüklerini transaction kontrolünde kullanılan ifadelerle karıştırmamak gereklidir. Burada sadece gruplama amacıyla kullanılır; transaction başlatıp durdurmaz.

---

## 2. Değişken Tanımlamalar (Declarations)

Bir bloktaki tüm değişkenler deklerasyonlar kısmında tanımlanmalıdır:

```sql
-- Söz dizimi
name [ CONSTANT ] type [ COLLATE collation_name ] [ NOT NULL ] [ { DEFAULT | := | = } expression ];

-- Örnekler
user_id integer;
quantity numeric(5);
url varchar;
myrow tablename%ROWTYPE;       -- Tablonun satır tipi
myfield tablename.columnname%TYPE;  -- Belirli bir kolonun tipi
arow RECORD;                   -- Herhangi bir satır yapısı
```

Fonksiyon parametreleri `$1`, `$2` gibi tanımlayıcılarla erişilir. Takma isim (alias) kullanımı:

```sql
CREATE FUNCTION sales_tax(subtotal real) RETURNS real AS $$
BEGIN
    RETURN subtotal * 0.06;  -- subtotal = $1 ile aynı
END;
$$ LANGUAGE plpgsql;
```

---

## 3. Fonksiyon (FUNCTION) vs Prosedür (PROCEDURE)

PostgreSQL 11'e kadar sadece Fonksiyonlar vardı. 11. sürümle birlikte Prosedürler de eklendi.

| Özellik | Fonksiyon (FUNCTION) | Prosedür (PROCEDURE) |
| :--- | :--- | :--- |
| **Geri Dönüş Değeri** | Mutlaka bir değer döndürür (veya `VOID`). | Geri dönüş değeri yoktur (Sadece `INOUT` parametrelerle). |
| **Çağrılma Şekli** | `SELECT my_func();` | `CALL my_proc();` |
| **Transaction Yönetimi**| **İçinde `COMMIT` veya `ROLLBACK` yapılamaz.** | **İçinde `COMMIT` ve `ROLLBACK` YAPILABİLİR!** |
| **Kullanım Yeri** | Select sorguları, View'lar, Index ifadeleri. | Sadece `CALL` ile çağrılır. |

### Tek Değer Döndüren Fonksiyon
```sql
CREATE OR REPLACE FUNCTION siparis_toplami_getir(p_kullanici_id INT) 
RETURNS NUMERIC AS $$
DECLARE
    v_toplam NUMERIC;
BEGIN
    SELECT COALESCE(SUM(tutar), 0) INTO v_toplam 
    FROM siparisler 
    WHERE kullanici_id = p_kullanici_id;
    RETURN v_toplam;
END;
$$ LANGUAGE plpgsql;

SELECT siparis_toplami_getir(5);
```

### SETOF ile Küme Döndüren Fonksiyon
```sql
CREATE OR REPLACE FUNCTION get_all_foo() RETURNS SETOF foo AS
$BODY$
DECLARE
    r foo%rowtype;
BEGIN
    FOR r IN
        SELECT * FROM foo WHERE fooid > 0
    LOOP
        RETURN NEXT r; -- Mevcut satırı döndür ve devam et
    END LOOP;
    RETURN;
END
$BODY$
LANGUAGE plpgsql;

SELECT * FROM get_all_foo();
```

### RETURN QUERY ile Fonksiyon
```sql
CREATE FUNCTION get_available_flightid(date) RETURNS SETOF integer AS
$BODY$
BEGIN
    RETURN QUERY SELECT flightid
                   FROM flight
                  WHERE flightdate >= $1
                    AND flightdate < ($1 + 1);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No flight at %.', $1;
    END IF;
    RETURN;
END
$BODY$
LANGUAGE plpgsql;
```

### Prosedür (COMMIT ile)
```sql
CREATE OR REPLACE PROCEDURE toplu_maas_artisi() 
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM personel LOOP
        UPDATE personel SET maas = maas * 1.10 WHERE id = r.id;
        COMMIT; -- Her personelde bir COMMIT (Fonksiyonda yapılamaz!)
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CALL toplu_maas_artisi();
```

---

## 4. Kontrol Yapıları

### Şart İfadeleri (IF / CASE)

```sql
-- IF...ELSIF...ELSE
IF number = 0 THEN
    result := 'zero';
ELSIF number > 0 THEN
    result := 'positive';
ELSIF number < 0 THEN
    result := 'negative';
ELSE
    result := 'NULL';
END IF;
```

CASE iki formda kullanılır:

```sql
-- Form 1: Arama ifadesi ile
CASE x
    WHEN 1, 2 THEN
        msg := 'one or two';
    ELSE
        msg := 'other';
END CASE;

-- Form 2: Şart ifadeleri ile
CASE
    WHEN x BETWEEN 1 AND 10 THEN msg := 'small';
    WHEN x BETWEEN 11 AND 100 THEN msg := 'medium';
    ELSE msg := 'large';
END CASE;
```

### Döngüler

**Sonsuz LOOP:**
```sql
<<myloop>>
LOOP
    -- İşlemler
    EXIT myloop WHEN koşul;     -- Koşul sağlandığında çık
    CONTINUE WHEN koşul;        -- Koşul sağlandığında sonraki tura atla
END LOOP myloop;
```

**WHILE döngüsü:**
```sql
WHILE boolean_ifade LOOP
    -- Koşul FALSE olana kadar çalışır
END LOOP;
```

**FOR döngüsü — Sayısal aralık:**
```sql
FOR i IN 1..10 LOOP
    RAISE NOTICE 'Sayı: %', i;
END LOOP;

FOR i IN REVERSE 10..1 LOOP
    -- 10, 9, 8 ... 1
END LOOP;

FOR i IN REVERSE 10..1 BY 2 LOOP
    -- 10, 8, 6, 4, 2
END LOOP;
```

**FOR döngüsü — Sorgu sonucu üzerinde:**
```sql
FOR r IN SELECT id, isim FROM ogrenciler LOOP
    RAISE NOTICE 'Öğrenci: %', r.isim;
END LOOP;

-- Materialized view yenileme örneği
CREATE FUNCTION cs_refresh_mviews() RETURNS integer AS $$
DECLARE
    mviews RECORD;
BEGIN
    FOR mviews IN SELECT * FROM cs_materialized_views ORDER BY sort_key LOOP
        EXECUTE format('TRUNCATE TABLE %I', mviews.mv_name);
        EXECUTE format('INSERT INTO %I %s', mviews.mv_name, mviews.mv_query);
    END LOOP;
    RETURN 1;
END;
$$ LANGUAGE plpgsql;
```

---

## 5. Cursor (İmleç) Yönetimi

Milyonlarca satır döndüren bir `SELECT` sorgusunu PL/pgSQL içine alıp işlerseniz (Örn: `FOR r IN SELECT...`), veritabanı tüm satırları önce **RAM'e yükler** ve `OOM (Out Of Memory)` hatasına (Sunucu çökmesine) sebep olabilir.

Bunu engellemek için **Cursor** kullanılır. Cursor, verileri parça parça (Chunk) belleğe alır.

### Cursor Tanımlama

```sql
DECLARE
    curs1 refcursor;                      -- Bağımsız cursor (herhangi bir sorgu için)
    curs2 CURSOR FOR SELECT * FROM tenk1; -- Bağlı cursor
    curs3 CURSOR (key integer) FOR SELECT * FROM tenk1 WHERE unique1 = key; -- Parametrik
```

### Cursor Açma (OPEN)

```sql
-- Bağımsız cursor açma
OPEN curs1 FOR SELECT * FROM foo WHERE key = mykey;

-- Dinamik sorgu ile açma
OPEN curs1 FOR EXECUTE format('SELECT * FROM %I WHERE col1 = $1', tabname) USING keyvalue;

-- Bağlı cursor açma
OPEN curs2;
OPEN curs3(42);
OPEN curs3(key := 42);  -- İsimli parametre
```

### FETCH, MOVE, CLOSE

```sql
DECLARE
    c_kullanicilar CURSOR FOR SELECT id, eposta FROM milyonluk_tablo;
    v_kayit RECORD;
BEGIN
    OPEN c_kullanicilar;
    LOOP
        FETCH c_kullanicilar INTO v_kayit;
        EXIT WHEN NOT FOUND;
        -- İşlem...
    END LOOP;
    CLOSE c_kullanicilar;
END;
```

**Çeşitli FETCH kullanımları:**
```sql
FETCH curs1 INTO rowvar;
FETCH curs2 INTO foo, bar, baz;
FETCH LAST FROM curs3 INTO x, y;
FETCH RELATIVE -2 FROM curs4 INTO x;
```

**MOVE (veri almadan konum değiştir):**
```sql
MOVE curs1;
MOVE LAST FROM curs3;
MOVE FORWARD 2 FROM curs4;
```

**Cursor konumundaki satırı güncelle/sil:**
```sql
UPDATE foo SET dataval = myval WHERE CURRENT OF curs1;
DELETE FROM table WHERE CURRENT OF cursor;
```

> [!TIP]
> PL/pgSQL fonksiyonlarını derlendiği haliyle (`CREATE OR REPLACE`) kullanmak, her çağrıldığında yeniden parse edilmelerini önlediği için dışarıdan kod (Python, Java) ile veri işlemekten **çok daha hızlıdır** (Network I/O olmaz).

---

## 6. Hata Yakalama (Exception Handling)

```sql
BEGIN
    statements
EXCEPTION
    WHEN condition [ OR condition ... ] THEN
        handler_statements
    [ WHEN condition [ OR condition ... ] THEN
          handler_statements ]
END;
```

**Örnek:**
```sql
BEGIN
    INSERT INTO mytab(firstname, lastname) VALUES('Tom', 'Jones');
    x := x + 1;
    y := x / 0;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'caught division_by_zero';
        RETURN x;
    WHEN unique_violation THEN
        -- Duplicate key, görmezden gel
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Yabancı anahtar hatası: %', SQLERRM;
END;
```

**Yaygın hata koşulları:**
- `no_data_found` — SELECT sonuç döndürmedi
- `too_many_rows` — INTO tek satır beklerken birden fazla döndü
- `unique_violation` — Benzersizlik kısıtlaması ihlali
- `foreign_key_violation` — Yabancı anahtar ihlali
- `division_by_zero` — Sıfıra bölme
- `check_violation` — CHECK constraint ihlali

---

## 7. Dinamik SQL (EXECUTE)

Tablo adı veya kolon adı gibi dinamik içerikler için `EXECUTE` kullanılır:

```sql
-- Basit dinamik sorgu
EXECUTE 'SELECT count(*) FROM ' || quote_ident(tabname) INTO count;

-- FORMAT ile güvenli kullanım (önerilen)
EXECUTE format('SELECT * FROM %I WHERE %I = $1', table_name, col_name) 
    USING value_var;
```

> [!WARNING]
> Dinamik SQL'de SQL injection'a karşı `format()` + `%I` (identifier/tanımlayıcı) ve `%L` (literal) kullanın. Asla kullanıcı girdisini doğrudan string birleştirme ile sorguya eklemeyin.
