# PL/pgSQL, Fonksiyonlar ve Prosedürler

PostgreSQL'de iş mantığını (Business Logic) veritabanı katmanında (Sunucu tarafında) çalıştırmak için SQL komutlarına prosedürel kontrol yapıları (`IF/ELSE`, `LOOP`, `EXCEPTION`) ekleyen **PL/pgSQL** dili kullanılır.

## 1. PL/pgSQL Dilinin Yapısı

PL/pgSQL kodları bloklar halinde yazılır. Standart bir blok şu şekildedir:

```sql
DO $$ 
DECLARE
    -- Değişkenler burada tanımlanır (Zorunlu değilse yazılmaz)
    kullanici_adi VARCHAR := 'Ahmet';
    satis_tutari NUMERIC;
BEGIN
    -- İşlemler (SQL Sorguları, If-Else vb.)
    SELECT tutar INTO satis_tutari FROM satislar WHERE isim = kullanici_adi;
    
    IF satis_tutari > 1000 THEN
        RAISE NOTICE '% adlı kullanıcının satışı 1000''den büyük.', kullanici_adi;
    END IF;
EXCEPTION
    -- Hata yakalama (Zorunlu değil)
    WHEN no_data_found THEN
        RAISE EXCEPTION 'Kayıt bulunamadı!';
END $$;
```

---

## 2. Fonksiyon (FUNCTION) vs Prosedür (PROCEDURE)

PostgreSQL 11'e kadar sadece Fonksiyonlar vardı. 11. sürümle birlikte Prosedürler de eklendi. Aralarındaki en kritik fark **Transaction (TCL)** yönetimi ve **Geri Dönüş Değeridir**.

| Özellik | Fonksiyon (FUNCTION) | Prosedür (PROCEDURE) |
| :--- | :--- | :--- |
| **Geri Dönüş Değeri** | Mutlaka bir değer (`RETURNS integer`, `RETURNS TABLE` vb.) döndürür (veya `VOID`). | Geri dönüş değeri (Return) yoktur (Sadece `INOUT` parametrelerle dönebilir). |
| **Çağrılma Şekli** | `SELECT my_func();` | `CALL my_proc();` |
| **Transaction Yönetimi**| **İçinde `COMMIT` veya `ROLLBACK` yapılamaz.** Tek bir dev transaction bloğudur. | **İçinde `COMMIT` ve `ROLLBACK` YAPILABİLİR!** (Örn: Çok uzun süren gece batch'lerinde her 100 kayıtta bir COMMIT atmak). |
| **Kullanım Yeri** | Select sorguları içinde, View'larda, Index oluştururken kullanılabilir. | Sadece bağımsız bir çağrı (`CALL`) ile çalışır, sorgu içine gömülemez. |

### Fonksiyon Örneği (Sipariş Toplamı Döndüren)
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

-- Çağrılışı:
SELECT siparis_toplami_getir(5);
```

### Prosedür Örneği (Maaş Artışı ve Commit)
```sql
CREATE OR REPLACE PROCEDURE toplu_maas_artisi() 
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM personel LOOP
        UPDATE personel SET maas = maas * 1.10 WHERE id = r.id;
        COMMIT; -- Her personelde bir COMMIT atar (Fonksiyonda yapılamaz!)
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Çağrılışı:
CALL toplu_maas_artisi();
```

---

## 3. Kontrol Yapıları

### Döngüler (Loops)
`LOOP`, `FOR` ve `WHILE` döngüleri ile işlemler tekrarlanabilir.

```sql
-- FOR Döngüsü ile 1'den 10'a sayma
FOR i IN 1..10 LOOP
    RAISE NOTICE 'Sayı: %', i;
END LOOP;

-- Dinamik sorgu sonucu üzerinde FOR ile gezinme
FOR r IN SELECT id, isim FROM ogrenciler LOOP
    RAISE NOTICE 'Öğrenci: %', r.isim;
END LOOP;
```

### Şartlar (If-Else)
```sql
IF durum = 'Aktif' THEN
    -- aktif işlemi
ELSIF durum = 'Pasif' THEN
    -- pasif işlemi
ELSE
    -- diğer durumlar
END IF;
```

---

## 4. Cursor (İmleç) Yönetimi

Milyonlarca satır döndüren bir `SELECT` sorgusunu PL/pgSQL içine alıp işlerseniz (Örn: `FOR r IN SELECT...`), veritabanı tüm satırları önce **RAM'e yükler** ve `OOM (Out Of Memory)` hatasına (Sunucu çökmesine) sebep olabilir.

Bunu engellemek için **Cursor** kullanılır. Cursor, verileri parça parça (Chunk) belleğe alır.

```sql
DECLARE
    -- Cursor tanımı
    c_kullanicilar CURSOR FOR SELECT id, eposta FROM milyonluk_tablo;
    v_kayit RECORD;
BEGIN
    OPEN c_kullanicilar;
    LOOP
        -- Belleği yormamak için her turda tek satır okur (veya FETCH NEXT n ROWS)
        FETCH c_kullanicilar INTO v_kayit;
        EXIT WHEN NOT FOUND; -- Kayıt kalmadıysa çık
        
        -- Mail gönderme işlemi vs..
    END LOOP;
    CLOSE c_kullanicilar;
END;
```

> [!TIP]
> PL/pgSQL fonksiyonlarını derlendiği haliyle (`CREATE OR REPLACE`) kullanmak, her çağrıldığında yeniden parse edilmelerini önlediği için dışarıdan kod (Python, Java) ile veri işlemekten **çok daha hızlıdır** (Network I/O olmaz).
