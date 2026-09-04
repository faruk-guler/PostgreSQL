# EXPLAIN ve Sorgu Analizi

Veritabanında yavaş çalışan sorguları bulmak ve performans darboğazlarını (Bottleneck) tespit etmek için `EXPLAIN` ve `EXPLAIN ANALYZE` komutları kullanılır.

## 1. EXPLAIN Nedir?

`EXPLAIN`, sorguyu çalıştırmadan PostgreSQL'in **Query Planner (Sorgu Planlayıcı)** motorunun o sorguyu veritabanından nasıl çekeceğine dair **Tahmini Planını (Execution Plan)** ekrana basar.

`EXPLAIN ANALYZE` ise tahminde bulunmaz, sorguyu **gerçekten çalıştırır** ve milisaniye cinsinden gerçek çalışma sürelerini ve okuduğu satır sayılarını gösterir.

> [!WARNING]
> `EXPLAIN ANALYZE` sorguyu **gerçekten** çalıştırır. Eğer bir `DELETE` veya `UPDATE` sorgusunu inceliyorsanız, verileriniz gerçekten silinir/güncellenir! Bu durumu engellemek için `EXPLAIN ANALYZE` komutunu bir `BEGIN; ... ROLLBACK;` bloğu içinde kullanmalısınız.

## 2. EXPLAIN Çıktısındaki Temel Kavramlar

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kisiler WHERE yas > 30;
```

**Çıktı Terimleri:**
*   **Cost (Maliyet):** `cost=0.00..18334.00`
    *   İlk rakam (0.00): İlk satırı bulmak için harcanan tahmini maliyet.
    *   İkinci rakam (18334.00): Tüm sonuçları getirmek için harcanan toplam tahmini maliyet. (Maliyet birimi "disk sayfasını ardışık okuma" birimidir, milisaniye değildir).
*   **Rows:** Sorgu sonucunda dönmesi beklenen satır sayısı.
*   **Width:** Dönen her bir satırın bayt cinsinden tahmini genişliği.
*   **Actual Time:** `actual time=0.874..96.455` (Sadece ANALYZE ile görünür). Milisaniye cinsinden gerçek çalışma süresi. İlk rakam ilk satırı getirme süresi, ikinci rakam tüm satırları getirme süresi.
*   **Buffers (Bellek/Disk Kullanımı):** `shared hit=224 read=8110`
    *   `shared hit`: Verinin **RAM (Bellek)** üzerinden okunan blok sayısı (Çok hızlı).
    *   `shared read`: Verinin **Harddiskten (Disk)** okunan blok sayısı (Yavaş).
    *   Amacımız `hit` oranını artırıp `read` oranını düşürmektir.

## 3. Tarama (Scan) Türleri

Sorgu planlayıcı, tabloyu nasıl okuyacağına karar verir. En yaygın okuma yöntemleri şunlardır:

### Seq Scan (Sequential Scan - Ardışık Tarama)
Tablonun en başından en sonuna kadar satır satır tüm diskin okunmasıdır. Tablo çok büyükse **aşırı yavaştır**. Bir index yoksa veya okunan veri tüm tablonun çok büyük bir kısmını kaplıyorsa (%20'den fazla) Planner tarafından bilerek seçilebilir.

### Index Scan (İndeks Taraması)
Aranılan verinin B-Tree index üzerinden bulunmasıdır. Önce Index okunur, sonra bulunan adres (pointer) üzerinden asıl tabloya (Heap) gidilip satırın tamamı getirilir. Çok hızlıdır.

### Index Only Scan (Sadece İndeks Taraması)
Eğer `SELECT` ile çektiğiniz kolonların **tamamı** zaten index'in içinde varsa (Örn: `SELECT id FROM tablo WHERE id = 5`), veritabanı asıl tabloya (Heap) hiç gitmez. Veriyi doğrudan Index'in içinden alır. **En hızlı** tarama türüdür.

### Bitmap Heap Scan
Sorgu eğer tablonun orta büyüklükteki bir kısmını (%5-%10 arası) getirecekse kullanılır. Önce indexten tüm satırların adresleri toplanıp bir Bitmap (Harita) oluşturulur, sonra tabloya gidip fiziksel sıraya göre topluca okunur. Disk kafasının oradan oraya atlamasını (Random I/O) engelleyerek performansı artırır.

## 4. Join (Birleştirme) Stratejileri

İki tablo birleştirilirken Planner'ın kullandığı 3 temel yöntem vardır:
*   **Nested Loop:** Dıştaki tablonun her satırı için içteki tablo baştan sona (veya index'ten) taranır. (Küçük tablolarda veya çok iyi indexlenmiş büyük tablolarda etkilidir).
*   **Hash Join:** Önce tablolardan birinin (genelde küçük olanın) Memory'de (work_mem) bir Hash tablosu (Sözlük) oluşturulur. Diğer tablo taranırken eşleşmeler bu sözlükten bulunur. Tablolar büyükse ve "=" operatörü kullanılıyorsa çok etkilidir.
*   **Merge Join:** Birleştirilecek her iki tablo da birleştirme kolonuna göre **önceden sıralanır (Sort)**. Sonra iki tablo yan yana konup tek geçişte eşleştirilir. 

> [!TIP]
> Çoğu zaman yavaş çalışan bir Hash Join veya Merge Join gördüğünüzde, veritabanının `work_mem` (çalışma belleği) ayarını artırmak performansı doğrudan hızlandırır.
