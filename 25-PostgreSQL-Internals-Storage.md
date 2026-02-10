# 25-PostgreSQL-Internals-Storage

PostgreSQL Master Guide'ın bu son bölümünde, verinin diskteki en küçük yapı taşına iniyoruz. Veritabanı motorunun dosyaları nasıl yazdığını bilmek, hem performansı hem de veri kurtarma (Recovery) süreçlerini anlamak için kritiktir.

---

## 1. Sayfa Yapısı (Page Layout)

PostgreSQL veriyi **8 KB**'lık sabit boyutlu sayfalarda (block) tutar. Her sayfa işletim sistemindeki bir dosyanın (1GB'lık dosyalar halinde bölünür) parçasıdır.

### Sayfanın Anatomisi

1. **Page Header (24 bayt):** Sayfanın ID'si, boş alanın yeri (Free Space), LSN (En son hangi WAL işlemi yazıldı) gibi bilgileri tutar.
2. **Item Pointers (Line Pointers):** Sayfa içindeki her bir satırın (tuple) nerede başladığını gösteren 4 baytlık işaretçiler dizisidir.
3. **Free Space:** Yeni satırların eklendiği boş alan (Sayfanın ortasındadır).
4. **Items (Tuples):** Fiziksel veri satırları (Sayfanın altından yukarı doğru büyür).
5. **Special Area:** Index sayfalarında komşu sayfa bağlantılarını tutan özel alan.

---

## 2. Satır Yapısı (Tuple Layout)

Her bir veri satırı (Tuple) kendi başlığına (Header) sahiptir.

### Tuple Header Bileşenleri

- **xmin:** Satırı oluşturan Transaction ID.
- **xmax:** Satırı silen veya güncelleyen Transaction ID (MVCC için kritik).
- **ctid:** Satırın fiziksel adresi (sayfa_no, index_no).
- **Null Bitmap:** Hangi sütunların NULL olduğunu gösteren bir bit dizisi.

> [!NOTE]
> Yazılım dünyasında bir satırı güncellediğinizde (UPDATE), PostgreSQL eski satırı silinmiş (Dead) işaretler ve diske yeni bir satır (Tuple) yazar. Bu yüzden UPDATE işlemleri de diskte yer kaplar.

---

## 3. pageinspect: Diski Röntgenlemek

PostgreSQL ile birlikte gelen `pageinspect` eklentisi, bir sayfanın içini SQL ile görmenizi sağlar.

```sql
CREATE EXTENSION pageinspect;

-- 'users' tablosunun 0. sayfasındaki header bilgisini gör
SELECT * FROM page_header(get_raw_page('users', 0));

-- Sayfa içindeki satırları (tuple) listele
SELECT * FROM heap_page_items(get_raw_page('users', 0));
```

---

## 4. TOAST (The Oversized-Attribute Storage Technique)

PostgreSQL sayfaları 8KB'dır. Eğer bir satır (örneğin uzun bir TEXT) bu sayfaya sığmazsa ne olur? **TOAST** devreye girer.

- **Strateji:** Büyük veri sıkıştırılır.
- **Hala sığmazsa:** Veri 2KB'lık parçalara bölünür ve ana tablonun dışındaki gizli bir "TOAST tablosunda" saklanır.
- **Fayda:** `SELECT id FROM table` dediğinizde, büyük metin verisi TOAST'ta olduğu için hiç okunmaz ve sorgu hızı düşmez.

---

## 5. Visibility Map & Free Space Map

- **FSM (Free Space Map):** Hangi sayfalarda ne kadar boş yer olduğunu tutar. Yeni bir satır ekleneceği zaman PostgreSQL bu haritaya bakar.
- **VM (Visibility Map):** Hangi sayfaların tamamen "temiz" (Index-Only Scan yapılabilir) olduğunu işaretler. Vacuum hızını artırır.

---

## 6. Uzman Özeti: Veri Nasıl Akar?

1. Uygulama **INSERT** gönderir.
2. PostgreSQL **FSM**'ye bakıp boş yeri olan bir sayfa (block) bulur.
3. Veriyi **Shared Buffers** (RAM) içindeki o sayfaya yazar.
4. İşlemi **WAL** (Write-Ahead Log) dosyasına asenkron veya senkron yazar.
5. **Checkpointer** düzenli aralıklarla RAM'deki bu "kirli" sayfaları diske kalıcı olarak basar.

Bu süreç PostgreSQL'in neden hem güvenli hem de hızlı olduğunun temel sırrıdır.

---

## 7. HOT Updates (Heap Only Tuple)

**Sorun:** Normal bir UPDATE işleminde PostgreSQL hem yeni tuple yazar hem de tüm indexleri günceller. Bu çok maliyetlidir.

**HOT Çözümü:** Eğer güncellenen sütunlar indexli değilse VE yeni tuple aynı sayfaya (page) sığıyorsa, PostgreSQL indexleri hiç güncellemez!

### HOT Nasıl Çalışır?

1. `UPDATE users SET last_login = now() WHERE id = 123;`
2. PostgreSQL kontrol eder: `last_login` sütunu indexli mi? → Hayır.
3. Yeni tuple aynı sayfaya sığıyor mu? → Evet.
4. **Sonuç:** Sadece heap'te (tabloda) yeni tuple yazar, indexlere dokunmaz.

### HOT'un Faydaları

- **Index bloat azalır** - Indexler gereksiz büyümez.
- **UPDATE hızlanır** - Index yazma maliyeti ortadan kalkar.
- **VACUUM daha verimli** - Dead tuple'lar aynı sayfada olduğu için temizleme kolay.

### HOT İstatistiklerini Görüntüleme

```sql
SELECT schemaname, tablename, 
       n_tup_upd AS total_updates,
       n_tup_hot_upd AS hot_updates,
       CASE WHEN n_tup_upd > 0 
            THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 2) 
            ELSE 0 
       END AS hot_update_ratio
FROM pg_stat_user_tables
WHERE n_tup_upd > 0
ORDER BY hot_update_ratio ASC
LIMIT 10;
```

> [!TIP]
> **HOT Optimizasyonu:** Sık güncellenen sütunları (örn: `last_seen`, `view_count`) indexlemeyin. Bunları ayrı bir tabloya taşımayı düşünün.

### HOT'u Engelleyen Durumlar

1. **Indexli sütun güncelleniyor** - Index'i de güncellemek zorundasınız.
2. **Sayfa dolu** - Yeni tuple aynı sayfaya sığmıyor, başka sayfaya yazılıyor.
3. **FILLFACTOR düşük** - Sayfada yeterli boş alan bırakılmamış.

**Çözüm:** Sık güncellenen tablolarda `FILLFACTOR` ayarını düşürün:

```sql
ALTER TABLE users SET (fillfactor = 70);
VACUUM FULL users;  -- Tabloyu yeniden yazar
```

---

---

**Tebrikler!** PostgreSQL Master Guide serisini tamamladınız. Artık PostgreSQL'in kurulumundan iç mimarisine kadar her konuda tam bir ustalık seviyesindesiniz.
