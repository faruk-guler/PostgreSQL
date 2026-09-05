# İleri Seviye Sorgulama ve JOIN İşlemleri

> **Bölüm Kapsamı:** Tablo Birleştirme (JOIN) Türleri, `DISTINCT ON` ile Bellek Tasarrufu, İlişkili Toplu DML (`UPDATE ... FROM`, `DELETE ... USING`), Alt Sorgu Optimizasyonları, Standart Sayfalama (`FETCH WITH TIES`) ve NULL-Güvenli Operatörler.

---

## 1. JOIN (Tablo Birleştirme) Türleri ve Davranışları

İlişkisel veritabanlarında normalize edilmiş tabloları birleştirmek için `JOIN` kullanılır. Bir DBA için JOIN'in türü kadar optimizörün arka planda seçtiği algoritma (**Nested Loop**, **Hash Join**, **Merge Join**) hayati önem taşır.

### `INNER JOIN` (Kesişim)

Her iki tabloda da eşleşme şartını sağlayan sadece **ortak** kayıtları getirir.

```sql
SELECT k.ad, s.tutar
FROM kullanicilar k
INNER JOIN siparisler s ON k.id = s.kullanici_id;
```

### `LEFT JOIN` (Sol Öncelikli)

Soldaki tablonun **tamamını** getirir. Sağdaki tabloda eşleşme yoksa o kolonlara `NULL` basar.

```sql
SELECT k.ad, s.tutar
FROM kullanicilar k
LEFT JOIN siparisler s ON k.id = s.kullanici_id;
```

### `RIGHT JOIN` ve `FULL OUTER JOIN`

* **`RIGHT JOIN`:** Sağdaki tablonun tamamını getirir, solda eşleşmeyenleri `NULL` yapar. (Genellikle okunabilirlik açısından tabloların yeri değiştirilip `LEFT JOIN` tercih edilir).
* **`FULL OUTER JOIN`:** Her iki tablodaki **tüm** kayıtları getirir. Eşleşmeyen taraflara `NULL` koyar.

### `CROSS JOIN` (Kartezyen Çarpım)

İki tablodaki tüm satırları birbirleriyle çarpar. Tablo 1'de 100.000, Tablo 2'de 10.000 satır varsa 1 milyar satır üretir. Genellikle `ON` şartı unutulduğunda kaza eseri oluşur ve belleği tüketerek sunucuyu OOM (Out of Memory) krizine sokabilir.

> [!TIP]
> **`USING` Sözdizimi:** İki tabloda da birleştirilen kolon isimleri aynıysa, `ON t1.id = t2.id` yerine `USING (id)` yazılabilir. `USING`, birleşen kolonu tekil bir sütun olarak çıktıya yansıtır.

---

## 2. PostgreSQL'e Özgü Güç: `DISTINCT ON (...)` ile Bellek Tasarrufu

Birçok yazılımcı, *"Her kategorideki/müşterideki en son kaydı getir"* ihtiyacı için Pencere Fonksiyonu (Window Function) yazar:

```sql
-- ❌ YAZILIMCI YAKLAŞIMI (Ağır Maliyetli):
SELECT * FROM (
    SELECT id, musteri_id, tutar, tarih,
           ROW_NUMBER() OVER (PARTITION BY musteri_id ORDER BY tarih DESC) AS rn
    FROM siparisler
) sub WHERE rn = 1;
```

* **DBA Analizi:** Bu sorgu 50 milyon satırlık tabloda çalıştırıldığında PostgreSQL tüm tabloyu RAM'e alır, `WindowAgg` çalıştırır ve `work_mem` yetersizse diske geçici dosya (`spill to disk / temporary files`) yazar. Disk I/O tavan yapar.

### ✅ DBA Çözümü: `DISTINCT ON` ve İndeks Desteği

```sql
-- ✅ POSTGRESQL OPTİMİZE YAKLAŞIM:
SELECT DISTINCT ON (musteri_id) musteri_id, id, tutar, tarih
FROM siparisler
ORDER BY musteri_id, tarih DESC;
```

> [!IMPORTANT]
> **Kritik Kural:** `DISTINCT ON` ifadesinde belirtilen kolonlar, `ORDER BY` ifadesinin **en solundaki (ilk) kolonlar** ile birebir aynı sırada başlamak zorundadır.
>
> Bu sorguyu desteklemek için şu kompozit B-Tree indeks tanımlandığında:
>
> ```sql
> CREATE INDEX idx_siparisler_musteri_tarih ON siparisler (musteri_id, tarih DESC);
> ```
>
> PostgreSQL optimizörü hiçbir sıralama (Sort) yapmaz; indeksi baştan sona tek geçişte (`Index Scan`) okur ve her müşteri için ilk gördüğü satırı alıp diğerlerini atlar. **Sorgu süresi dakikalardan milisaniyelere iner!**

---

## 3. İlişkili Toplu DML: `UPDATE ... FROM` ve `DELETE ... USING`

Canlı sistemde başka bir tablodaki eşleşmeye göre toplu veri güncellemek veya silmek gerektiğinde PostgreSQL standart dışı ama çok güçlü iki sözdizimi sunar.

### `UPDATE ... FROM` (Join ile Güncelleme)

MySQL'deki `UPDATE t1 JOIN t2 ...` sözdizimi PostgreSQL'de desteklenmez. Bunun yerine `FROM` cümleciği kullanılır:

```sql
-- İptal edilen faturalara ait tüm siparişlerin durumunu güncelle
UPDATE siparisler s
SET durum = 'iptal_edildi',
    guncellenme_tarihi = NOW()
FROM faturalar f
WHERE s.fatura_id = f.id
  AND f.durum = 'iptal';
```

### `DELETE ... USING` (Join ile Silme)

Başka bir tablodaki kritere göre ana tablodan satır silmek için `USING` kullanılır:

```sql
-- Kara listedeki kullanıcıların bekleyen bildirimlerini temizle
DELETE FROM bildirimler b
USING kara_liste k
WHERE b.kullanici_id = k.kullanici_id
  AND k.engel_tarihi >= CURRENT_DATE - INTERVAL '30 days';
```

> [!CAUTION]
> **DBA Kilit Uyarısı (Lock Bloat):**
> 5 milyon satırı tek bir `UPDATE ... FROM` veya `DELETE ... USING` ile çalıştırmak, o satırların tamamında `RowExclusiveLock` tutar, WAL akışını şişirir ve Streaming Replication gecikmesini (Lag) fırlatır.
>
> Canlı sistemde bu işlem **küçük paketler (Chunking)** halinde yapılmalıdır:
>
> ```sql
> -- 10.000'lik paketlerle silme örneği (Bir bash veya python döngüsü içinde)
> DELETE FROM bildirimler
> WHERE id IN (
>     SELECT id FROM bildirimler
>     WHERE durum = 'okundu' AND tarih < NOW() - INTERVAL '6 months'
>     LIMIT 10000
> );
> COMMIT;
> ```

---

## 4. Alt Sorgular (Subqueries) ve Optimizasyon

```sql
-- Basit Skaler Alt Sorgu (Ortalama fiyattan pahalı ürünler)
SELECT urun_adi, fiyat
FROM urunler
WHERE fiyat > (SELECT avg(fiyat) FROM urunler);
```

### Alt Sorgu Operatörleri: `ANY` / `SOME` ve `ALL`

* **`= ANY(ARRAY[...] veya Alt Sorgu)`:** `IN` operatörünün dinamik dizi veya alt sorgu halidir.

  ```sql
  -- Ankara veya İzmir depolarında bulunan ürünler
  SELECT * FROM urunler 
  WHERE depo_id = ANY(SELECT id FROM depolar WHERE sehir IN ('Ankara', 'İzmir'));
  ```

* **`> ALL(Alt Sorgu)`:** Alt sorgudan dönen **tüm değerlerin hepsinden büyük** olanları getirir.

  ```sql
  -- Stajyerlerin hepsinin maaşından daha yüksek maaş alan çalışanlar
  SELECT * FROM calisanlar 
  WHERE maas > ALL(SELECT maas FROM calisanlar WHERE unvan = 'Stajyer');
  ```

---

## 5. Küme İşlemleri (UNION, INTERSECT, EXCEPT)

İki farklı sorgunun sonucunu satır bazında birleştirmek için kullanılır. İki sorgunun kolon sayıları ve tipleri birebir uyumlu olmalıdır.

* **`UNION` vs `UNION ALL`:**
  * `UNION`: Satırları birleştirir ve ardından bellekte **SORT / HASH** yaparak mükerrerleri eler (Ağır maliyet).
  * `UNION ALL`: Mükerrer kontrolü yapmadan verileri doğrudan alt alta ekler. **DBA kuralı: Tekilleştirme zorunlu değilse daima `UNION ALL` kullanılmalıdır.**
* **`INTERSECT`**: İki kümenin kesişimini getirir.
* **`EXCEPT`**: Birinci sorguda olup ikinci sorguda olmayanları getirir (Küme farkı).

---

## 6. Standart Sayfalama: `FETCH FIRST n ROWS WITH TIES`

PostgreSQL 13+ ile gelen SQL:2008 standardı, klasik `LIMIT / OFFSET`'in yarattığı adaletsiz sonuçları çözer.

```sql
-- ❌ Klasik LIMIT: 3. kişiyle aynı puana sahip 4. kişiyi sayfadan keser atar:
SELECT ogrenci_adi, puan FROM sinav_sonuclari ORDER BY puan DESC LIMIT 3;

-- ✅ Modern SQL Standardı (WITH TIES): 
-- 3. sıradaki öğrenciyle AYNI PUANA sahip başkaları da varsa onları da sayfaya dahil eder!
SELECT ogrenci_adi, puan 
FROM sinav_sonuclari 
ORDER BY puan DESC 
FETCH FIRST 3 ROWS WITH TIES;
```

---

## 7. Koşullu Mantık ve NULL-Güvenli Operatörler

### `COALESCE` ve `NULLIF` (Sıfıra Bölünme Koruması)

Sistem izleme ve DBA script'lerinde en sık kullanılan iki fonksiyondur:

```sql
-- 1. NULL Değere Varsayılan Değer Atama
SELECT unvan, COALESCE(telefon, 'Telefon Belirtilmemiş') FROM personeller;

-- 2. Sıfıra Bölünme (Division by Zero) Hatasını Önleme (NULLIF):
-- Eğer payda 0 ise NULL yap, böylece işlem hata fırlatmaz, NULL döner:
SELECT 
    bolum_adi,
    ROUND((basarili_gorevler::numeric / NULLIF(toplam_gorevler, 0)) * 100, 2) AS basari_yuzdesi
FROM gorev_istatistikleri;
```

### `IS DISTINCT FROM` (NULL-Safe Eşitlik)

SQL standardında `NULL = NULL` ifadesi `TRUE` değil `UNKNOWN` döner. İki değerin NULL olup olmadığını da dikkate alarak eşitliğini kontrol etmek için bu operatör kullanılır:

```sql
-- Standart '=' sorgusu her iki taraf da NULL olduğunda eşleşmeyi YAKALAYAMAZ:
-- 'IS NOT DISTINCT FROM' her iki taraf NULL ise TRUE döner:
SELECT * FROM denetim_kayitlari
WHERE eski_deger IS DISTINCT FROM yeni_deger;
```
