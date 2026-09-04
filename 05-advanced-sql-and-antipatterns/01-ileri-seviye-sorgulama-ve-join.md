# İleri Seviye Sorgulama ve JOIN İşlemleri

Veritabanından veriyi en doğru ve en performanslı şekilde çekmek, ilişkisel veritabanı yönetiminin temelidir. PostgreSQL'de (DQL - Data Query Language) tablo birleştirme ve sorgu optimizasyonu işlemleri oldukça gelişmiştir.

---

## 1. JOIN (Tablo Birleştirme) Türleri ve Davranışları

İlişkisel veritabanlarında veriler parçalanmış (Normalize edilmiş) tablolarda tutulur. Bu tabloları birleştirmek için `JOIN` kullanılır.

### `INNER JOIN` (Kesişim)
Her iki tabloda da (Eşleşme şartını sağlayan) sadece **ortak** olan kayıtları getirir. En performanslı ve en çok kullanılan JOIN türüdür.

```sql
-- Kullanıcılar ve Siparişler tablolarını eşleştirir.
-- Sadece siparişi olan kullanıcılar listelenir.
SELECT k.ad, s.tutar
FROM kullanicilar k
INNER JOIN siparisler s ON k.id = s.kullanici_id;
```

### `LEFT JOIN` (Sol Öncelikli)
Soldaki tablonun **tamamını** getirir. Sağdaki tabloda eşleşme yoksa o kolonlara `NULL` basar. "Tüm kullanıcıları getir, siparişi olanların tutarını yaz, olmayanların tutarı boş (NULL) gelsin" mantığıdır.

```sql
SELECT k.ad, s.tutar
FROM kullanicilar k
LEFT JOIN siparisler s ON k.id = s.kullanici_id;
```

### `RIGHT JOIN` ve `FULL OUTER JOIN`
*   **`RIGHT JOIN`:** Sağdaki tablonun tamamını getirir, solda eşleşmeyenleri `NULL` yapar. Pratikte nadir kullanılır, çünkü tabloların yerini değiştirip `LEFT JOIN` yapmak daha okunabilirdir.
*   **`FULL OUTER JOIN`:** Her iki tablodaki **tüm** kayıtları getirir. Eşleşmeyen taraflara `NULL` koyar. (Örn: Hem hiç sipariş vermeyen kullanıcıları, hem de hangi kullanıcıya ait olduğu belli olmayan yetim siparişleri aynı anda bulmak).

### `CROSS JOIN` (Kartezyen Çarpım)
İki tablodaki tüm satırları birbirleriyle eşleştirir (Çarpar). Tablo 1'de 10 satır, Tablo 2'de 10 satır varsa 100 satır döner. Çok tehlikelidir, genellikle `ON` şartı unutulduğunda yanlışlıkla oluşur ve belleği tüketir (OOM - Out of Memory).

> [!TIP]
> `USING` Sözdizimi: Eğer iki tabloda da birleştirdiğiniz kolonların isimleri birebir aynıysa (Örn: iki tabloda da `kullanici_id` varsa), `ON t1.kullanici_id = t2.kullanici_id` yerine sadece `USING (kullanici_id)` yazarak kodu kısaltabilirsiniz.

---

## 2. Alt Sorgular (Subqueries)

Sorgu içinde sorgu çalıştırma yöntemidir. Genellikle `WHERE`, `FROM` veya `SELECT` içinde kullanılırlar.

```sql
-- WHERE İçinde kullanımı
-- Sadece ortalamanın üzerinde fiyatı olan ürünleri getirir
SELECT urun_adi, fiyat
FROM urunler
WHERE fiyat > (SELECT avg(fiyat) FROM urunler);
```

> [!WARNING]
> `IN (Alt Sorgu)` yapısı, eğer alt sorgu çok büyük bir sonuç seti döndürüyorsa ciddi performans sorunlarına yol açar. Mümkün olduğunca alt sorguları `EXISTS` operatörüne veya `INNER JOIN` yapısına dönüştürün. `EXISTS`, eşleşmeyi bulduğu an aramayı durdurur (Short-circuit).

---

## 3. Kümeleme ve İstatistik (GROUP BY ve HAVING)

Verileri belirli gruplara ayırıp (Örn: Şehre göre) o grubun özet bilgisini (`sum`, `count`, `avg`, `max`, `min`) almak için kullanılır.

*   **`GROUP BY`**: Satırları gruplara ayırır.
*   **`HAVING`**: **Gruplanmış** veriler üzerinde WHERE filtresi uygulamak için kullanılır. (`WHERE` satırları filtrelerken, `HAVING` grupları filtreler).

```sql
-- Şehirlere göre toplam satışı bulur
-- Fakat sadece toplam satışı 10.000 TL'yi geçen şehirleri listeler
SELECT sehir, SUM(satis_tutari) AS toplam_satis
FROM satislar
GROUP BY sehir
HAVING SUM(satis_tutari) > 10000;
```

---

## 4. Küme İşlemleri (UNION, INTERSECT, EXCEPT)

İki farklı sorgunun sonucunu birleştirmek veya kesiştirmek için kullanılır. İki sorgunun da döndürdüğü kolon sayısı ve veri tipleri aynı olmak zorundadır.

*   **`UNION`**: İki sorgunun sonucunu birleştirir (Alt alta ekler). Tekrar eden (Duplike) satırları tek satıra indirir. Eğer tüm satırları (tekrar edenler dahil) istiyorsanız **`UNION ALL`** kullanmalısınız (Daha hızlıdır).
*   **`INTERSECT`**: Sadece iki sorgunun sonucunda da **ortak** olarak bulunan satırları getirir.
*   **`EXCEPT`**: Birinci sorguda olup, ikinci sorguda **olmayan** kayıtları getirir. (A kümesi fark B kümesi).

---

## 5. Sayfalama (LIMIT ve OFFSET)

Sonuçları sınırlandırmak için kullanılır (Pagination).

```sql
-- En yüksek puanlı 3 öğrenciyi getirir
SELECT * FROM ogrenciler
ORDER BY puan DESC
LIMIT 3;

-- 11. satırdan itibaren 10 kayıt getirir (2. Sayfa mantığı)
SELECT * FROM ogrenciler
ORDER BY puan DESC
LIMIT 10 OFFSET 10;
```

> [!CAUTION]
> Çok yüksek `OFFSET` değerleri (`OFFSET 100000`) performansı öldürür. Çünkü veritabanı 100.000 satırı bellekten okur, çöpe atar ve 100.001'inci satırdan itibaren getirmeye başlar. Büyük tablolarda Keyset Pagination (Seek Method) kullanılmalıdır (`WHERE id > last_seen_id LIMIT 10`).
