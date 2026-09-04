# Transaction (İşlem) Yönetimi ve Concurrency

Veritabanlarında aynı anda binlerce kullanıcının veri okuması ve yazması (Concurrency) durumunda tutarlılığın (Consistency) bozulmaması için **Transaction** ve **İzolasyon Seviyeleri** kullanılır.

---

## 1. Transaction Nedir? (ACID Prensipleri)

Birbiriyle bağlantılı birden fazla veritabanı işleminin (INSERT, UPDATE, DELETE) **tek bir paket (atomik)** halinde çalıştırılmasıdır.

**Kural (Ya Hep Ya Hiç):** Paketteki işlemlerin tamamı başarılı olursa veri diske kalıcı olarak yazılır (`COMMIT`). Eğer işlemlerin herhangi bir aşamasında (sunucu çökmesi, bakiye yetersizliği, elektrik kesintisi vb.) bir hata oluşursa, yapılan tüm değişiklikler iptal edilir ve veritabanı en baştaki haline döner (`ROLLBACK`).

### Örnek: Havale İşlemi (A'dan B'ye 100$ Transfer)
Bu işlem iki UPDATE gerektirir. Eğer ilki çalışıp, ikincisi çalışmadan sistem çökerse para yok olur. Bunu engellemek için Transaction kullanılır.

```sql
BEGIN; -- İşlem Paketini Başlat

-- 1. A'nın bakiyesinden düş
UPDATE hesaplar SET bakiye = bakiye - 100 WHERE isim = 'A';

-- 2. B'nin bakiyesini artır
UPDATE hesaplar SET bakiye = bakiye + 100 WHERE isim = 'B';

COMMIT; -- Her şey başarılıysa, değişiklikleri kalıcı hale getir
```

### Savepoint (Ara Kayıt Noktası)
Devasa bir transaction içinde, hata durumunda her şeyi geri almak (`ROLLBACK`) yerine sadece belirli bir noktaya geri dönmek isterseniz `SAVEPOINT` kullanabilirsiniz.

```sql
BEGIN;
UPDATE sepet SET durum = 'Odendi' WHERE id = 1;

SAVEPOINT odeme_alindi; -- Ara nokta

-- Eğer kargo sistemi çökerse, sadece kargo kısmını iptal et, ödemeyi tut.
UPDATE kargo SET durum = 'Gonderildi' WHERE sepet_id = 1;
-- HATA ALINDI!
ROLLBACK TO odeme_alindi; -- Kargo UPDATE'ini geri alır, sepet UPDATE'ini korur.

COMMIT;
```

---

## 2. İzolasyon Seviyeleri (Isolation Levels)

PostgreSQL'de aynı tablo üzerinde aynı anda işlem yapan A ve B kullanıcıları birbirlerinin yaptığı değişiklikleri **hangi aşamada** görür? Bunu belirleyen ayara İzolasyon Seviyesi denir. 

PostgreSQL'de varsayılan seviye `READ COMMITTED`'dır. (SQL Standardındaki `READ UNCOMMITTED - Dirty Read` PostgreSQL'de uygulanmaz, Read Committed gibi çalışır).

### 1. READ COMMITTED (PostgreSQL Varsayılanı)
*   Bir işlem (A), diğer bir işlemin (B) sadece **COMMIT edilmiş (kesinleşmiş)** verilerini görebilir.
*   **Sorunu (Non-Repeatable Read):** A işlemi bir sorguyu çalıştırır (Örn: X=10). B işlemi arkadan gelir ve veriyi değiştirip COMMIT eder (X=20). A işlemi aynı sorguyu *aynı transaction içinde* ikinci kez çalıştırdığında sonucu farklı (X=20) bulur.

### 2. REPEATABLE READ
*   Bir transaction (A) başladığı anda (ilk komutu çalıştırdığında) veritabanının bir **Snapshot'ını (Fotoğrafını)** çeker ve işlem boyunca sadece o anki verileri görür.
*   Dışarıda başka biri (B) veriyi değiştirip `COMMIT` etse bile, A işlemi bunu görmez (İlk sorguda X=10 okuduysa, işlem bitene kadar X hep 10 olarak kalır).
*   **Sorunu:** Eğer hem A hem de B aynı anda aynı satırı güncellemeye çalışırsa (Concurrent Update), ilk COMMIT eden kazanır. İkinci işlem "Could not serialize access due to concurrent update" hatası alıp iptal olur (Uygulamanın `ROLLBACK` atıp işlemi baştan denemesi (Retry) gerekir).

### 3. SERIALIZABLE (En Katı Seviye)
*   Sanki veritabanında aynı anda işlem yapan kimse yokmuş, tüm transaction'lar kuyruğa girmiş ve **tek tek sırayla (Seri halde)** çalışıyormuş gibi davranır.
*   Uygulama katmanında "Phantom Read" dahil hiçbir tutarsızlık olmaz.
*   **Dezavantajı:** Performansı çok düşürür ve çok sık kilitlenme (Locking/Deadlock) ve ardışıklaştırma (Serialization) hataları üretir.

---

## 3. Explicit Locking (Elle Kilitleme)

PostgreSQL arka planda otomatik kilitler (Row-Level Lock) kullansa da, bazen sizin manuel müdahale etmeniz gerekir.

### `SELECT ... FOR UPDATE`
Banka veya biletleme (Ticket) sistemlerinde, bir bakiyeyi okuyup üzerine işlem yapacaksanız, o satırı okurken **kilitlemeniz** gerekir.

```sql
BEGIN;

-- A hesabının bakiyesini oku VE KİLİTLE! (B işlemi bu satırı değiştiremez ve okuyamaz)
SELECT bakiye FROM hesaplar WHERE isim = 'A' FOR UPDATE;

-- Bakiyeyi kontrol et ve güncelle
UPDATE hesaplar SET bakiye = bakiye - 100 WHERE isim = 'A';

COMMIT; -- Kilit burada serbest kalır
```

> [!TIP]
> Performans için her zaman kilitleri satır bazında (Row-Level: `FOR UPDATE`) atın. Asla tabloyu tamamen kilitlemeyin (`LOCK TABLE`). 
