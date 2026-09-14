# Aggregate, Window Fonksiyonları ve Gelişmiş Gruplama

PostgreSQL, analitik sorgular (OLAP) ve raporlama (BI) için veri ambarlarında (Data Warehouse) kullanılan çok güçlü özetleme ve bölümleme yeteneklerine sahiptir.

---

## 1. Aggregate (Özetleme) Fonksiyonları

Birden çok satırdaki veriyi matematiksel bir işlemden geçirerek **tek bir sonuç** döndüren fonksiyonlardır.

* `COUNT(*)`: Satır sayısını sayar.
* `SUM(kolon)`: Toplam değeri bulur.
* `AVG(kolon)`: Ortalamayı alır.
* `MAX(kolon)` / `MIN(kolon)`: En büyük ve en küçük değerleri bulur.
* `STDDEV(kolon)`: Standart sapmayı hesaplar.

> [!WARNING]
> Aggregate fonksiyonlar (`min`, `max`, `avg`, `sum`, `stddev`) sorgunun **WHERE** kısmında doğrudan kullanılamaz. Alt sorgu kullanmak gerekir.

```sql
-- YANLIŞ: Bu çalışmaz
SELECT city FROM weather WHERE temp_lo = max(temp_lo);

-- DOĞRU: Alt sorgu ile
SELECT city FROM weather
    WHERE temp_lo = (SELECT max(temp_lo) FROM weather);
```

### GROUP BY ve HAVING

```sql
-- Her şehir için en yüksek sıcaklık
SELECT city, max(temp_lo)
    FROM weather
    GROUP BY city;

-- HAVING ile gruplama sonrası filtre
SELECT city, max(temp_lo)
    FROM weather
    GROUP BY city
    HAVING max(temp_lo) < 40;

-- WHERE (önceden) + HAVING (sonradan) birlikte
SELECT city, max(temp_lo)
    FROM weather
    WHERE city LIKE 'S%'    -- Gruplamadan önce filtreler
    GROUP BY city
    HAVING max(temp_lo) < 40; -- Gruplamadan sonra filtreler
```

**WHERE vs HAVING farkı:** WHERE gruplamadan önceki satırları seçer. HAVING ise GROUP BY ile gruplama yapıldıktan sonra grupları süzer.

---

## 2. Window (Bölümleme) Fonksiyonları

Window fonksiyonları, birbiriyle ilişkili satırları seçerek oluşturulan alt gruplar üzerinde çeşitli hesaplamalar yapabilir. Aggregate fonksiyonlardan farkı: **satırları tek satıra indirgemez**, orijinal satırları koruyarak yanlarına ek bilgi ekler.

### OVER ve PARTITION BY

```sql
-- Her departmandaki her kişinin maaşı + departman ortalaması
SELECT depname, empno, salary, 
       avg(salary) OVER (PARTITION BY depname) 
FROM empsalary;

-- Çıktı:
--  depname   | empno | salary |          avg
-- -----------+-------+--------+-----------------------
--  develop   |    11 |   5200 | 5020.0000000000000000
--  develop   |     7 |   4200 | 5020.0000000000000000
--  personnel |     5 |   3500 | 3700.0000000000000000
--  sales     |     1 |   5000 | 4866.6666666666666667
```

### Sıralama (rank, row_number, dense_rank)

```sql
-- Departman içinde maaş sıralaması
SELECT depname, empno, salary,
       rank() OVER (PARTITION BY depname ORDER BY salary DESC)
FROM empsalary;

-- Çıktı:
--  develop   |     8 |   6000 |    1
--  develop   |    10 |   5200 |    2
--  develop   |    11 |   5200 |    2  (eşit - 3.lük yok)
--  develop   |     9 |   4500 |    4
```

### Bölümsüz Window (Tüm tablo üzerinde)

```sql
-- Tüm tablonun toplamını her satıra ekle
SELECT salary, sum(salary) OVER () FROM empsalary;

-- Kümülatif toplam (ORDER BY ile, PARTITION BY olmadan)
SELECT salary, sum(salary) OVER (ORDER BY salary) FROM empsalary;
-- Çıktı: 3500→3500, 3900→7400, 4200→11600...
```

### Birden Fazla Window Fonksiyonu — WINDOW Tanımı

```sql
-- Aynı partition'ı birden fazla fonksiyonda kullanmak
SELECT sum(salary) OVER w, avg(salary) OVER w
  FROM empsalary
  WINDOW w AS (PARTITION BY depname ORDER BY salary DESC);
```

### Window Fonksiyonları Kataloğu

| Fonksiyon | Açıklama |
|---|---|
| `row_number()` | Bölüm içindeki satır numarası (1'den başlar) |
| `rank()` | Sıralama (eşit değerlerde boşluk bırakır: 1,2,2,4) |
| `dense_rank()` | Sıralama (eşit değerlerde boşluk bırakmaz: 1,2,2,3) |
| `percent_rank()` | Yüzdesel sıralama: `(rank()-1) / (toplam-1)` |
| `cume_dist()` | Kümülatif dağılım değeri |
| `ntile(n)` | Bölümü n eşit parçaya böler |
| `lag(value, offset)` | Önceki satırın değeri |
| `lead(value, offset)` | Sonraki satırın değeri |
| `first_value(value)` | Bölümdeki ilk değer |
| `last_value(value)` | Bölümdeki son değer |
| `nth_value(value, n)` | Bölümdeki n.inci değer |

---

## 3. GROUPING SETS — Özelleştirilmiş Alt Toplamlar

Tek bir `GROUP BY` içinde **farklı kombinasyonlardan oluşan birden fazla gruplamayı** aynı anda çalıştırır.

```sql
SELECT yil, ay, urun, SUM(satis)
FROM satislar
GROUP BY GROUPING SETS (
    (yil, urun),  -- Yıl + ürüne göre toplam
    (ay),         -- Sadece aya göre toplam
    ()            -- Genel toplam
);
```

---

## 4. ROLLUP — Hiyerarşik Alt Toplamlar

Hiyerarşik (büyükten küçüğe) kümülatif toplamlar alır.

```sql
SELECT yil, ay, sum(satis) 
FROM satislar
GROUP BY ROLLUP (yil, ay);
```

Yukarıdaki komut arka planda şunu yapar: `GROUPING SETS ((yil, ay), (yil), ())`. (Önce aya göre, sonra o yılın genel toplamı, en son da tüm yılların genel toplamı).

---

## 5. CUBE — Tüm Kombinasyonlar

Verilen kolonların **ihtimal dahilindeki tüm çapraz varyasyonları** için alt toplam alır.

```sql
SELECT marka, beden, sum(satis)
FROM satislar
GROUP BY CUBE (marka, beden);
```

Arka plandaki karşılığı: `GROUPING SETS ((marka, beden), (marka), (beden), ())`. Hem markalara göre toplamı, hem bedenlere göre toplamı, hem marka+beden kesişimini hem de genel toplamı verir.

> [!WARNING]
> Aggregate fonksiyonları `WHERE` şartı içerisinde **KULLANILAMAZLAR**. Çünkü `WHERE` satırları filtreler, gruplama işlemi ise satırlar filtrelendikten **sonra** yapılır. Eğer gruplanmış veri üzerinde bir filtre (Örn: "Toplam satışı 1000'den büyük olanlar") yapmak istiyorsanız, `HAVING` kullanmalısınız.

```sql
-- YANLIŞ KULLANIM (Hata verir)
SELECT departman FROM personel WHERE AVG(maas) > 5000;

-- DOĞRU KULLANIM
SELECT departman, AVG(maas) 
FROM personel 
GROUP BY departman 
HAVING AVG(maas) > 5000;
```

---

## 2. Window (Bölümleme) Fonksiyonları (`OVER PARTITION BY`)

Aggregate fonksiyonları verileri **sıkıştırır (Compress)** ve tek satıra indirger. Bu yüzden normal kolonlarla (Örn: `ad, soyad`) aynı SELECT içinde (GROUP BY yapmadan) gösterilemezler.

**Window Fonksiyonları**, veriyi tek satıra indirgemeden (orijinal satırları kaybetmeden) o satırın bağlı bulunduğu grubun istatistiğini satırın yanına eklemeyi sağlar.

### Neden Kullanılır?

"Bana personellerin adını, kendi departmanındaki en yüksek maaşı ve bu personelin maaşının o en yüksek maaşa olan farkını getir." gibi zor analitik sorguları alt sorgulara (Subqueries) gerek kalmadan çok yüksek performansla çözer.

```sql
SELECT 
    ad, 
    departman, 
    maas, 
    -- 1. Window: Bu satırın departmanındaki ortalama maaş
    AVG(maas) OVER (PARTITION BY departman) AS departman_ortalamasi,
    
    -- 2. Window: Kendi departmanındaki maaş sıralaması
    RANK() OVER (PARTITION BY departman ORDER BY maas DESC) AS departman_ici_sira
FROM personel;
```

### Önemli Window Fonksiyonları

* `ROW_NUMBER()`: Her satıra sırayla 1, 2, 3.. diye numara verir.
* `RANK()`: Sıralama yapar ama eşit olanlara aynı sırayı verir (1, 2, 2, 4) - 3. sıra atlanır.
* `DENSE_RANK()`: Sıralama yapar ama atlamaz (1, 2, 2, 3).
* `LEAD()` / `LAG()`: Bir önceki veya bir sonraki satırın verisini o anki satıra çeker (Aydan aya % büyüme / düşme hesaplamak için mükemmeldir).
* `FIRST_VALUE()` / `LAST_VALUE()`: Bölümdeki ilk veya son kaydı getirir.

---

## 3. Gelişmiş Gruplama Kümeleri (`GROUPING SETS`, `ROLLUP`, `CUBE`)

Bazen aynı tablo üzerinde birden fazla boyutta rapora (Aynı anda hem Marka bazında toplam, hem Beden bazında toplam, hem de Genel Toplam) ihtiyaç duyulur. Eskiden bu, 3 ayrı sorgu yazılıp `UNION ALL` ile birleştirilerek yapılırdı (Bu tabloyu 3 kez Full Scan yapmak demekti).

PostgreSQL, bunu **tek bir taramada** yapabilen analitik gruplama komutları sunar.

### `GROUPING SETS`

Hangi kolon kombinasyonlarına göre gruplama (Alt Toplam) yapılacağını manuel olarak belirtirsiniz. Boş parantez `()` genel toplamı (Grand Total) verir.

```sql
SELECT marka, beden, sum(satis) 
FROM satislar
GROUP BY GROUPING SETS ((marka), (beden), ());
```

### `ROLLUP` (Hiyerarşik Alt Toplamlar)

Soldan sağa doğru hiyerarşik olarak (Örn: Yıl -> Ay -> Gün) alt toplamlar alır.

```sql
SELECT yil, ay, sum(satis) 
FROM satislar
GROUP BY ROLLUP (yil, ay);
```

Yukarıdaki komut arka planda şunu yapar: `GROUPING SETS ((yil, ay), (yil), ())`. (Önce aya göre, sonra o yılın genel toplamı, en son da tüm yılların genel toplamı).

### `CUBE` (Tüm Kombinasyonlar)

Verilen kolonların **ihtimal dahilindeki tüm çapraz varyasyonları** için alt toplam alır.

```sql
SELECT marka, beden, sum(satis)
FROM satislar
GROUP BY CUBE (marka, beden);
```

Arka plandaki karşılığı: `GROUPING SETS ((marka, beden), (marka), (beden), ())`. Hem markalara göre toplamı, hem bedenlere göre toplamı, hem marka+beden kesişimini hem de genel toplamı verir.
