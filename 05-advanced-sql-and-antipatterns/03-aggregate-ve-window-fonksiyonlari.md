# Aggregate, Window Fonksiyonları ve Gelişmiş Gruplama

PostgreSQL, analitik sorgular (OLAP) ve raporlama (BI) için veri ambarlarında (Data Warehouse) kullanılan çok güçlü özetleme ve bölümleme yeteneklerine sahiptir.

---

## 1. Aggregate (Özetleme) Fonksiyonları

Birden çok satırdaki veriyi matematiksel bir işlemden geçirerek **tek bir sonuç** döndüren fonksiyonlardır. 

*   `COUNT(*)`: Satır sayısını sayar.
*   `SUM(kolon)`: Toplam değeri bulur.
*   `AVG(kolon)`: Ortalamayı alır.
*   `MAX(kolon)` / `MIN(kolon)`: En büyük ve en küçük değerleri bulur.

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
*   `ROW_NUMBER()`: Her satıra sırayla 1, 2, 3.. diye numara verir.
*   `RANK()`: Sıralama yapar ama eşit olanlara aynı sırayı verir (1, 2, 2, 4) - 3. sıra atlanır.
*   `DENSE_RANK()`: Sıralama yapar ama atlamaz (1, 2, 2, 3).
*   `LEAD()` / `LAG()`: Bir önceki veya bir sonraki satırın verisini o anki satıra çeker (Aydan aya % büyüme / düşme hesaplamak için mükemmeldir).
*   `FIRST_VALUE()` / `LAST_VALUE()`: Bölümdeki ilk veya son kaydı getirir.

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
