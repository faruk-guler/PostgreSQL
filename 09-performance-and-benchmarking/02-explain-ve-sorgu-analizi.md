# EXPLAIN ve Sorgu Analizi

Veritabanında yavaş çalışan sorguları bulmak ve performans darboğazlarını (Bottleneck) tespit etmek için `EXPLAIN` ve `EXPLAIN ANALYZE` komutları kullanılır.

## 1. EXPLAIN Nedir?

`EXPLAIN`, sorguyu çalıştırmadan PostgreSQL'in **Query Planner (Sorgu Planlayıcı)** motorunun o sorguyu veritabanından nasıl çekeceğine dair **Tahmini Planını (Execution Plan)** ekrana basar.

`EXPLAIN ANALYZE` ise tahminde bulunmaz, sorguyu **gerçekten çalıştırır** ve milisaniye cinsinden gerçek çalışma sürelerini ve okuduğu satır sayılarını gösterir.

> [!WARNING]
> `EXPLAIN ANALYZE` sorguyu **gerçekten** çalıştırır. Eğer bir `DELETE` veya `UPDATE` sorgusunu inceliyorsanız, verileriniz gerçekten silinir/güncellenir! Bu durumu engellemek için `EXPLAIN ANALYZE` komutunu bir `BEGIN; ... ROLLBACK;` bloğu içinde kullanmalısınız.

### EXPLAIN Seçenekleri

| Seçenek | Varsayılan | Değer | Açıklama |
|---|---|---|---|
| `ANALYZE` | `TRUE` | Boolean | Sorguyu çalıştırıp gerçekte çalışan değerleri verir |
| `VERBOSE` | `TRUE` | Boolean | Her sorgu nodu için detaylı çıktı gösterir |
| `COSTS` | `TRUE` | Boolean | Her akış için maliyetleri ayrı ayrı gösterir |
| `BUFFERS` | `FALSE` | Boolean | Bellek kullanımıyla ilgili bilgileri gösterir |
| `TIMING` | `TRUE` | Boolean | Gerçekleştirme zamanlarını gösterir |
| `FORMAT` | `TEXT` | TEXT/XML/JSON/YAML | Çıktı formatı |

---

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
*   **Loops:** İşlemi kaç kere yaptığını gösterir (iç içe döngülerde önemlidir).
*   **Planning time:** Query Planner'ın en hızlı planı bulmak için harcadığı süre.
*   **Execution time:** Sorgunun gerçekleştirilmesi için harcanan toplam süre.

**Gerçek EXPLAIN çıktısı:**
```
-- İlk sorguda tamamı disk okumasından geliyor (read)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM foo;
 Seq Scan on foo (cost=0.00..18334.00 rows=1000000 width=37) (actual time=0.874..96.455 rows=1000000 loops=1)
   Buffers: shared read=8334
 Planning time: 0.055 ms
 Execution time: 139.152 ms

-- Aynı sorguyu tekrar çalıştırınca bir kısmı bellekten gelmekte (hit)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM foo;
 Seq Scan on foo (cost=0.00..18334.00 rows=1000000 width=37) (actual time=0.099..86.507 rows=1000000 loops=1)
   Buffers: shared hit=224 read=8110
```

### Filter

WHERE ile filtre koyulduğunda `Filter` ve `Rows Removed by Filter` bilgisi eklenir:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM foo WHERE c1 > 500;
 Seq Scan on foo (cost=0.00..20834.00 rows=999567 width=37) (actual time=0.150..113.683 rows=999500 loops=1)
   Filter: (c1 > 500)
   Rows Removed by Filter: 500
   Buffers: shared hit=8334
```

### Maliyet Hesaplama Formülü

Cost değerleri `pg_class` tablosundaki istatistiklerden hesaplanır:

```sql
SELECT relpages * current_setting('seq_page_cost')::float4
     + reltuples * current_setting('cpu_tuple_cost')::float4
     + reltuples * current_setting('cpu_operator_cost')::float4 AS total_cost
FROM pg_class
WHERE relname = 'foo';
```

---

## 3. Tarama (Scan) Türleri

Sorgu planlayıcı, tabloyu nasıl okuyacağına karar verir. En yaygın okuma yöntemleri şunlardır:

### Seq Scan (Sequential Scan - Ardışık Tarama)
Tablonun en başından en sonuna kadar satır satır tüm diskin okunmasıdır. Tablo çok büyükse **aşırı yavaştır**. Bir index yoksa veya okunan veri tüm tablonun çok büyük bir kısmını kaplıyorsa (%20'den fazla) Planner tarafından bilerek seçilebilir.

### Index Scan (İndeks Taraması)
Aranılan verinin B-Tree index üzerinden bulunmasıdır. Önce Index okunur, sonra bulunan adres (pointer) üzerinden asıl tabloya (Heap) gidilip satırın tamamı getirilir.

```sql
EXPLAIN (ANALYZE) SELECT * FROM foo WHERE c1 < 500 AND c2 LIKE 'abcd%';
 Index Scan using foo_c1_idx on foo (cost=0.42..24.51 rows=1 width=37) (actual time=0.362..0.362 rows=0 loops=1)
   Index Cond: (c1 < 500)
   Filter: (c2 ~~ 'abcd%'::text)
   Rows Removed by Filter: 499
```

### Index Only Scan (Sadece İndeks Taraması)
Eğer `SELECT` ile çektiğiniz kolonların **tamamı** zaten index'in içinde varsa, veritabanı asıl tabloya (Heap) hiç gitmez. **En hızlı** tarama türüdür.

```sql
EXPLAIN (ANALYZE) SELECT c1 FROM foo WHERE c1 < 500;
 Index Only Scan using foo_c1_idx on foo (cost=0.42..23.37 rows=454 width=4) (actual time=0.066..0.295 rows=499 loops=1)
   Index Cond: (c1 < 500)
   Heap Fetches: 499
```

### Bitmap Heap Scan
Sorgu eğer tablonun orta büyüklükteki bir kısmını (%5-%10 arası) getirecekse kullanılır. Önce indexten tüm satırların adresleri toplanıp bir Bitmap (Harita) oluşturulur, sonra tabloya gidip fiziksel sıraya göre topluca okunur. Disk kafasının oradan oraya atlamasını (Random I/O) engelleyerek performansı artırır.

```sql
EXPLAIN SELECT * FROM tenk1 WHERE unique1 < 100;
 Bitmap Heap Scan on tenk1 (cost=5.07..229.20 rows=101 width=244)
   Recheck Cond: (unique1 < 100)
   ->  Bitmap Index Scan on tenk1_unique1 (cost=0.00..5.04 rows=101 width=0)
         Index Cond: (unique1 < 100)
```

**Recheck Cond:** `work_mem` bitmap için yetersizse "lossy" moda geçer ve page başına 1 bit'e düşer. Bu durumda ilgili blokların satırları yeniden kontrol edilir.

**BitmapAnd / BitmapOr:** Birden fazla index'ten gelen bitmap'lerin birleştirilmesi:

```sql
EXPLAIN SELECT * FROM tenk1 WHERE unique1 < 100 AND unique2 > 9000;
 Bitmap Heap Scan on tenk1 (cost=25.08..60.21 rows=10 width=244)
   Recheck Cond: ((unique1 < 100) AND (unique2 > 9000))
   ->  BitmapAnd (cost=25.08..25.08 rows=10 width=0)
         ->  Bitmap Index Scan on tenk1_unique1 (...)
               Index Cond: (unique1 < 100)
         ->  Bitmap Index Scan on tenk1_unique2 (...)
               Index Cond: (unique2 > 9000)
```

---

## 4. Join (Birleştirme) Stratejileri

İki tablo birleştirilirken Planner'ın kullandığı 3 temel yöntem vardır:

*   **Nested Loop:** Dıştaki tablonun her satırı için içteki tablo baştan sona (veya index'ten) taranır. (Küçük tablolarda veya çok iyi indexlenmiş büyük tablolarda etkilidir).

```sql
EXPLAIN SELECT * FROM foo, bar WHERE foo.x = bar.x;
-- Index kullanılamıyorsa:
 Nested Loop
   Join Filter: (foo.x = bar.x)
   ->  Seq Scan on bar
   ->  Seq Scan on foo

-- Index varsa:
 Nested Loop
   ->  Seq Scan on foo
   ->  Index Scan using bar_pkey on bar
         Index Cond: (bar.x = foo.x)
```

*   **Hash Join:** Önce tablolardan birinin (genelde küçük olanın) Memory'de (`work_mem`) bir Hash tablosu oluşturulur. Diğer tablo taranırken eşleşmeler bu sözlükten bulunur.

```sql
 Hash Join
   Hash Cond: (foo.x = bar.x)
   ->  Seq Scan on foo
   ->  Hash
         ->  Seq Scan on bar
```

*   **Merge Join:** Birleştirilecek her iki tablo da birleştirme kolonuna göre **önceden sıralanır**. Sonra iki tablo yan yana konup tek geçişte eşleştirilir.

```sql
 Merge Join
   Merge Cond: (foo.x = bar.x)
   ->  Sort
         Sort Key: foo.x
         ->  Seq Scan on foo
   ->  Sort
         Sort Key: bar.x
         ->  Seq Scan on bar
```

> [!TIP]
> Çoğu zaman yavaş çalışan bir Hash Join veya Merge Join gördüğünüzde, veritabanının `work_mem` (çalışma belleği) ayarını artırmak performansı doğrudan hızlandırır.

---

## 5. Sorgu Planlayıcısını Yönlendirme

Planlayıcının bir özelliği devre dışı bırakılarak farklı plan oluşturması sağlanabilir:

```sql
-- Normal plan: Merge Join kullanır
EXPLAIN SELECT * FROM tenk1 t1, onek t2 WHERE t1.unique1 < 100 AND t1.unique2 = t2.unique2;

-- Sort'u devre dışı bırakarak farklı plan oluştur
SET enable_sort = off;
EXPLAIN SELECT * FROM tenk1 t1, onek t2 WHERE t1.unique1 < 100 AND t1.unique2 = t2.unique2;
-- Sonuç: Index Scan kullanır
```

> [!WARNING]
> Bu seçenekler test amaçlıdır; üretim ortamında session başına kullanın. Planlayıcı genellikle doğru kararı verir.

---

## 6. Log Analizi: PgBadger

```bash
# Kurulum
yum install perl-ExtUtils-MakeMaker make
git clone https://github.com/dalibo/pgbadger.git
cd pgbadger && perl Makefile.PL && make && sudo make install
```

`postgresql.conf` ayarları:
```ini
log_min_duration_statement = 0
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
```

Rapor oluşturma:
```bash
pgbadger -f stderr -s 10 -q \
  -o /var/www/html/pgbadger/report_$(date +%Y-%m-%d).html \
  /var/lib/pgsql/16/data/log/postgresql-Mon.log
```


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
