# İndeks Türleri ve Optimizasyon

İndeksler (Indexes), veritabanındaki milyarlarca satır arasından aradığımız veriyi saliseler içinde bulmamızı sağlayan veri yapılarıdır. Kitapların sonundaki "Fihrist (Dizin)" yapısı ile birebir aynı mantıkta çalışırlar.

İndeksler okuma (SELECT) performansını muazzam ölçüde artırırken, her yeni kayıtta indeksin de güncellenmesi gerektiği için yazma (INSERT/UPDATE/DELETE) performansını bir miktar düşürürler ve diskte yer kaplarlar.

---

## 1. PostgreSQL İndeks Türleri

PostgreSQL, ihtiyaca göre şekillenen çok çeşitli indeks algoritmalarına sahiptir:

### B-Tree (Balanced Tree)
*   **Kullanım Yeri:** Standart, varsayılan indeks türüdür.
*   **Özellikleri:** Eşitlik (`=`) ve aralık (`<`, `>`, `BETWEEN`) sorgularında mükemmel çalışır. Veriyi diskte her zaman alfabetik/sayısal olarak **sıralı** tutar. Bu sayede `ORDER BY` komutlarında ekstra sıralama işlemine (Sort) gerek bırakmaz.

### Hash
*   **Kullanım Yeri:** Sadece eşitlik (`=`) aramaları için.
*   **Özellikleri:** B-Tree'den daha az yer kaplar ve '=' aramalarında biraz daha hızlıdır. Ancak `<`, `>`, `ORDER BY` gibi işlemleri desteklemez. Çok nadir kullanılır.

### GIN (Generalized Inverted Index)
*   **Kullanım Yeri:** Array'ler, JSON/JSONB objeleri ve Full-Text Search (Tam metin araması).
*   **Özellikleri:** Bir hücrenin içinde birden fazla değerin saklandığı durumlarda (Örn: Bir belgenin içindeki kelimeler, bir JSONB içindeki yüzlerce key-value) harika çalışır. `@>` (Kapsar mı?) operatörü ile kullanılır.

### GiST (Generalized Search Tree)
*   **Kullanım Yeri:** 2D ve 3D geometrik/coğrafi veriler (PostGIS).
*   **Özellikleri:** Nesnelerin birbiriyle olan konumsal ilişkisini (Kesişiyor mu, içinde mi, yakınında mı?) hızlıca bulmayı sağlar.

### BRIN (Block Range Index)
*   **Kullanım Yeri:** IoT cihazları, log tabloları, zaman serisi verileri gibi **sürekli artan (linear)** verilerin tutulduğu devasa (Terabaytlık) tablolar.
*   **Özellikleri:** Satır satır değil, disk blokları bazında minimum ve maksimum değerleri tutar. Milyarlarca satırlık bir tabloda B-Tree 10 GB yer kaplarken, BRIN sadece 5 MB yer kaplar. 

---

## 2. İleri Düzey İndeks Stratejileri

### Çoklu Kolon İndeksi (Composite Index)
Bir sorguda sürekli olarak iki kolonu birden `WHERE` şartına yazıyorsanız (Örn: İsim ve Soyisim) tek bir indeksi iki kolona atayabilirsiniz.

```sql
CREATE INDEX idx_kisi_ad_soyad ON kisiler (ad, soyad);
```
*Kural:* Kolon sırası çok önemlidir. `WHERE ad = 'Ali'` derseniz bu indeks çalışır, ama `WHERE soyad = 'Yılmaz'` derseniz bu indeks **çalışmaz**. Çünkü fihrist `ad` kolonuna göre sıralanmıştır. En seçici (Farklı varyasyonu en çok olan) kolonu başa yazın.

### Kısmi İndeks (Partial Index)
Tablodaki verilerin sadece küçük bir kısmı sizin için önemliyse, indeksin boyutunu ufaltmak için bir `WHERE` şartıyla indeks oluşturabilirsiniz.

```sql
-- Sadece silinmemiş kayıtları indeksle! 
-- (Disk tasarrufu sağlar ve indeksi küçülterek hızlandırır)
CREATE INDEX idx_aktif_uyeler ON uyeler (eposta) WHERE silindi_mi = false;
```

### Expression Index (Fonksiyon/İfade İndeksi)
Sorgularda bir fonksiyon kullanıyorsanız standart indeksler iptal olur. (Örn: `WHERE lower(eposta) = 'ali@mail.com'` derseniz `eposta` indeksi çalışmaz). Fonksiyonun sonucunu indeksleyebilirsiniz:

```sql
CREATE INDEX idx_kucuk_harf_eposta ON uyeler (lower(eposta));
```

---

## 3. İndeks Oluştururken Canlı Sistemi Kilitlememek

Büyük bir tabloda `CREATE INDEX` komutu çalıştırdığınızda, indeks oluşturulana kadar tabloya yeni veri yazılması (INSERT/UPDATE/DELETE) engellenir. Canlı (Production) sistemlerde bu kesinti (Downtime) yaratır.

Bunu engellemek için `CONCURRENTLY` parametresi kullanılır. İndeksi arka planda yavaş yavaş oluşturur, tabloyu kilitlemez.

```sql
CREATE INDEX CONCURRENTLY idx_buyuk_tablo_uye_id ON devasa_tablo (uye_id);
```
