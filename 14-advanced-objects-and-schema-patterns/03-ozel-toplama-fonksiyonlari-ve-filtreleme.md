# Özel Toplama Fonksiyonları (User-Defined Aggregates) ve FILTER Cümleciği

> **Bölüm Kapsamı:** Kullanıcı Tanımlı Toplama Fonksiyonları (`CREATE AGGREGATE`), Koşullu Toplama (`FILTER Clause`) ve Sıralı Küme Fonksiyonları (`WITHIN GROUP`)

---

PostgreSQL; `SUM`, `AVG`, `COUNT`, `MIN`, `MAX` gibi standart toplama fonksiyonlarının yanı sıra, geliştiricilerin kendi özel toplama algoritmalarını tanımlamasına (`CREATE AGGREGATE`) ve verileri tek bir sorguda koşullu olarak özetlemesine (`FILTER`) olanak tanır.

---

## 1. Koşullu Toplama: `FILTER (WHERE ...)` Cümleciği

Raporlama sorgularında belirli bir koşulu sağlayan satırları özetlemek için geleneksel SQL'de karmaşık `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` ifadeleri yazılırdı. SQL:2003 standardında tanımlanan ve PostgreSQL'in kusursuz uyguladığı **`FILTER`** cümleciği bu ihtiyacı çok daha temiz ve performanslı çözer:

```sql
SELECT 
    department,
    -- Toplam çalışan
    COUNT(*) AS total_employees,
    -- Sadece aktif olan çalışanlar
    COUNT(*) FILTER (WHERE is_active = true) AS active_employees,
    -- Sadece yöneticilerin maaş ortalaması
    AVG(salary) FILTER (WHERE is_manager = true) AS avg_manager_salary,
    -- Son 30 günde işe girenler
    COUNT(*) FILTER (WHERE hire_date > NOW() - INTERVAL '30 days') AS new_hires
FROM employees
GROUP BY department;
```

> [!TIP]
> **Pivot Tablo Simülasyonu:** `FILTER` cümleciği tek bir `GROUP BY` ile satırları sütunlara dönüştüren (Pivot) raporlar üretmek için en hızlı yöntemdir.

---

## 2. Sıralı Küme Fonksiyonları (Ordered-Set Aggregates)

Bazı istatistiksel hesaplamalar, verilerin toplanmadan önce belirli bir sırada dizilmesini gerektirir. PostgreSQL bunun için **`WITHIN GROUP (ORDER BY ...)`** söz dizimini sunar:

### a. Medyan ve Yüzdelik Dilim (`percentile_cont` / `percentile_disc`)

Aritmetik ortalama uç değerlerden (outliers) kolayca etkilenirken, Medyan (ortanca değer) veri kümesinin gerçek eğilimini gösterir:

```sql
SELECT 
    department,
    -- Sürekli medyan (%50. persentil)
    percentile_cont(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
    -- %95. persentil (Performans testlerinde SLA ölçümü için)
    percentile_cont(0.95) WITHIN GROUP (ORDER BY response_time_ms) AS p95_latency
FROM api_metrics
GROUP BY department;
```

### b. En Sık Geçen Değer (Mod - `mode()`)

```sql
-- Her departmanda en çok kullanılan unvan (Mod)
SELECT department, mode() WITHIN GROUP (ORDER BY job_title) AS most_common_title
FROM employees
GROUP BY department;
```

---

## 3. Kullanıcı Tanımlı Toplama Fonksiyonları (`CREATE AGGREGATE`)

PostgreSQL'de yerleşik olmayan özel bir hesaplama gerektiğinde (örneğin finans ve biyolojide sık kullanılan **Geometrik Ortalama - Geometric Mean**) sıfırdan bir aggregate yazılabilir.

Bir toplama fonksiyonu 3 bileşenden oluşur:
1. **Durum Değişkeni (`stype`):** Ara sonuçları tutan bellek değişkeni.
2. **Durum Geçiş Fonksiyonu (`sfunc`):** Her yeni satır geldiğinde ara sonucu güncelleyen fonksiyon.
3. **Nihai Fonksiyon (`finalfunc`):** Tüm satırlar bittiğinde son sonucu üreten fonksiyon (Opsiyonel).

### Adım Adım Uygulama: Geometrik Ortalama Hesaplayıcı

Geometrik ortalama formülü: $\sqrt[n]{x_1 \cdot x_2 \cdots x_n}$

#### 1. Durum Geçiş Fonksiyonu
Bu fonksiyon iki değer tutmalıdır: Sayıların çarpımı ve satır sayısı. Durum tipi olarak iki elemanlı bir `FLOAT8[]` dizisi kullanabiliriz (`[çarpım, adet]`):

```sql
CREATE OR REPLACE FUNCTION geom_mean_state(state FLOAT8[], val FLOAT8)
RETURNS FLOAT8[] AS $$
BEGIN
    IF val IS NULL OR val <= 0 THEN
        RETURN state; -- Negatif veya NULL değerleri yoksay
    END IF;
    -- state[1]: kümülatif çarpım, state[2]: eleman sayısı
    RETURN ARRAY[state[1] * val, state[2] + 1];
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

#### 2. Nihai Fonksiyon (Final Function)
Tüm satırlar okunduktan sonra $n$. dereceden kök alır:

```sql
CREATE OR REPLACE FUNCTION geom_mean_final(state FLOAT8[])
RETURNS FLOAT8 AS $$
BEGIN
    IF state[2] = 0 THEN
        RETURN NULL;
    END IF;
    -- Çarpımın (1 / n) üssünü al
    RETURN power(state[1], 1.0 / state[2]);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

#### 3. Toplama Fonksiyonunu Oluşturma (`CREATE AGGREGATE`)

```sql
CREATE AGGREGATE geometric_mean (FLOAT8) (
    SFUNC = geom_mean_state,
    STYPE = FLOAT8[],
    FINALFUNC = geom_mean_final,
    INITCOND = '{1.0, 0}' -- Başlangıç durumu: çarpım=1.0, adet=0
);
```

#### 4. Kullanım

```sql
-- Test tablosu oluştur
CREATE TABLE returns (roi FLOAT8);
INSERT INTO returns VALUES (1.10), (1.05), (1.20), (1.15);

-- Özel fonksiyonumuzu tıpkı yerleşik SUM/AVG gibi çağırın:
SELECT geometric_mean(roi) FROM returns;
-- Çıktı: ~1.1235
```

---

## 4. Paralel Toplama Desteği (Parallel Aggregation)

PostgreSQL'in yazdığınız özel aggregate fonksiyonunu birden çok CPU çekirdeğinde paralel olarak çalıştırabilmesi için bir **Birleştirme Fonksiyonu (`COMBINEFUNC`)** ekleyebilirsiniz:

```sql
CREATE OR REPLACE FUNCTION geom_mean_combine(state1 FLOAT8[], state2 FLOAT8[])
RETURNS FLOAT8[] AS $$
BEGIN
    RETURN ARRAY[state1[1] * state2[1], state1[2] + state2[2]];
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Aggregate tanımına ekleyin:
-- COMBINEFUNC = geom_mean_combine, PARALLEL = SAFE
```
Bu sayede milyonlarca satırlık tablolarda özel aggregate'iniz tüm CPU çekirdeklerini kullanarak paralel hesaplanır.
