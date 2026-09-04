# PostGIS ve Coğrafi Veri (Geospatial) Analizi

> **Bölüm Kapsamı:** Mekansal Veri Modeli, SRID (Kordinat Sistemleri), GiST İndeksleme ve Yakınlık Sorguları

---

## 1. PostGIS Nedir?

PostgreSQL'i "Dünyanın en iyi Açık Kaynak Veritabanı" yapan şeylerin başında **PostGIS** gelir. Sıradan bir veritabanını, harita ve coğrafi bilgi sistemleri (GIS) için özel olarak tasarlanmış bir mekansal veritabanına dönüştürür. 

Eğer bir Yemek Teslimat uygulaması (Kurye nerede?), Taksi çağırma uygulaması veya Gayrimenkul uygulaması yapıyorsanız, PostGIS kullanmak zorundasınız. En yakın restoranı enlem/boylam üzerinden `math.sqrt()` veya Haversine formülü ile hesaplamaya çalışmak sistemi felç eder.

---

## 2. Kurulum ve Temel Kavramlar

PostGIS bir eklentidir ve veritabanı seviyesinde aktifleştirilmesi gerekir.

```sql
-- Eklentiyi kur (İşletim sisteminde postgis paketinin yüklü olması gerekir)
CREATE EXTENSION postgis;
```

### GEOMETRY vs GEOGRAPHY

PostGIS'te iki temel veri tipi vardır:
1. **Geometry:** Düz (kartezyen) bir düzlem kullanır. Matematiksel olarak hızlıdır ancak dünya yuvarlak olduğu için uzun mesafeli hesaplamalarda hata payı yüksektir.
2. **Geography:** Dünyanın küresel yapısını (elipsoit) hesaba katar. Mesafe hesaplamaları her zaman Metre cinsinden ve kesindir, ancak matematiksel işlemleri CPU için daha zahmetlidir. (Küresel uygulamalar için `Geography` önerilir).

---

## 3. Coğrafi Veri Modelleme

Bir restoran tablosu oluşturalım ve konumunu kaydedelim:

```sql
CREATE TABLE restaurants (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    -- Konum (Enlem ve Boylam) için Geography kullanıyoruz (SRID: 4326 WGS84 - GPS standardı)
    location GEOGRAPHY(POINT, 4326) 
);

-- Veri Ekleme (ST_GeomFromText ile WKT formatında veri giriyoruz)
-- Not: Koordinatlar (Boylam, Enlem) sırasıyla girilir (Longitude, Latitude)
INSERT INTO restaurants (name, location)
VALUES 
('Kebapçı Ahmet', ST_GeogFromText('SRID=4326;POINT(28.9784 41.0082)')), -- İstanbul
('Taco Bell', ST_GeogFromText('SRID=4326;POINT(-118.2437 34.0522)')); -- Los Angeles
```

---

## 4. Hayat Kurtaran PostGIS Sorguları

### A. En Yakın N Noktayı Bulma (Nearest Neighbor - KNN)

"Bana en yakın 3 restoranı getir" sorgusu, PostGIS'in `<->` (mesafe) operatörü ve GiST indeksi ile ışık hızında çalışır.

```sql
-- Kuryenin konumu: 28.9800 boylam, 41.0100 enlem
SELECT name, 
       ST_Distance(location, ST_GeogFromText('SRID=4326;POINT(28.9800 41.0100)')) AS distance_meters
FROM restaurants
ORDER BY location <-> ST_GeogFromText('SRID=4326;POINT(28.9800 41.0100)')
LIMIT 3;
```

### B. Belirli Bir Yarıçap (Radius) İçinde Arama

"Bana 5 km (5000 metre) çapındaki restoranları getir."

```sql
SELECT name 
FROM restaurants
WHERE ST_DWithin(
    location, 
    ST_GeogFromText('SRID=4326;POINT(28.9800 41.0100)'), 
    5000 -- Metre cinsinden
);
```

### C. Çokgen (Polygon) İçinde Kalan Noktalar

"Bu kurye Kadıköy sınırları (Polygon) içinde mi?"

```sql
SELECT r.name 
FROM restaurants r, delivery_zones z
WHERE z.zone_name = 'Kadikoy' 
  AND ST_Within(r.location::geometry, z.boundaries::geometry);
```

---

## 5. GiST İndeksi Olmadan PostGIS Hiçbir İşe Yaramaz

Milyonlarca satırlık bir tabloda mesafe veya çokgen hesaplaması yapmak CPU'yu kilitler. PostGIS'in Bounding Box (Kapsayıcı Kutu) mantığıyla çalışabilmesi için **GiST (Generalized Search Tree)** indeksine ihtiyacı vardır.

```sql
-- Konum sütununa mutlaka GiST indeksi ekleyin
CREATE INDEX idx_restaurants_location ON restaurants USING gist (location);
```

**Nasıl Çalışır?** 
GiST indeksi, coğrafi noktaları birbirini kapsayan kutulara böler (R-Tree). Siz "5 km çevremdekileri bul" dediğinizde, önce kutuları tarar (Index Scan), sadece sizin kutunuzla kesişen kutuların içindeki noktaları CPU'ya göndererek kesin mesafeyi ölçtürür. Bu sayede 10 milyon restoranın 9.999.000 tanesi daha işleme girmeden elenir.

## Özet

- Enlem/Boylam verisini FLOAT veya DECIMAL olarak tutmayın. Hesaplamalar hem yavaş olur hem de indekslenemez.
- Kısa mesafe (şehir içi) işler yapıyorsanız Geometry, küresel bir iş (Uçak rotaları) yapıyorsanız Geography kullanın.
- `<->` operatörünü ve GiST indeksini kullanmayı öğrenmeden uygulamanızı canlıya (prod) almayın.
