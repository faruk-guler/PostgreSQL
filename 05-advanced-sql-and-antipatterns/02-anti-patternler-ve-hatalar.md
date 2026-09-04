# PostgreSQL Anti-Pattern'leri ve Sık Yapılan Hatalar

> **Bölüm Kapsamı:** Şema Tasarımı, Sorgu Optimizasyonu, İndeksleme ve Konfigürasyonda Kaçınılması Gereken Tuzaklar

---

## 1. Schema Tasarımı Hataları

### ❌ Anti-Pattern: İndekssiz Foreign Key Kullanımı

PostgreSQL'de bir `Foreign Key` (Yabancı Anahtar) kısıtlaması, referans verilen (parent) tabloda bir `DELETE` veya `UPDATE` yapıldığında veri bütünlüğünü korumak için referans eden (child) tabloyu kontrol etmek zorundadır. Eğer child tablodaki FK sütununda indeks yoksa, parent tablodaki her silme işleminde child tabloda **Full Table Scan (Tam Tablo Taraması)** yapılır. Daha da kötüsü, bu tarama sırasında child tabloda agresif kilitler (locks) alınır ve sistem kilitlenebilir.

**✅ Doğru:** Her `Foreign Key` sütununa mutlaka bağımsız bir B-Tree indeksi ekleyin.

```sql
-- Kötü: FK var ama indeks yok
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id)
);

-- İyi: FK için indeks eklenmiş
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
```

### ❌ Anti-Pattern: Rastgele UUID Primary Key

Primary Key olarak `UUID` (v4) kullanmak, indeks fragmantasyonuna (parçalanma) yol açar. Rastgele dağılan veriler, diskin farklı yerlerine sürekli yazmaya zorlar.
**✅ Doğru:** Sıralı ID kullanın (`BIGSERIAL`) veya sıralı UUID (`UUIDv7`) tercih edin.

### ❌ Anti-Pattern: TEXT yerine VARCHAR(n) Takıntısı

Diğer veritabanlarının aksine, PostgreSQL'de `VARCHAR(255)` ile `TEXT` arasında performans farkı yoktur. Hatta `TEXT` daha esnektir.
**✅ Doğru:** Limit gerekmiyorsa `TEXT` kullanın. Limit gerekiyorsa `VARCHAR(n)` kullanın ama performans için değil, veri bütünlüğü için.

---

## 2. Sorgu (Query) Hataları

### ❌ Anti-Pattern: `NOT IN` İçindeki NULL Tuzağı

Eğer `NOT IN` ile bir alt sorgu (subquery) yazarsanız ve alt sorgudan dönen kayıtlardan **sadece bir tanesi bile NULL ise**, ana sorgu **sıfır satır** döndürür. Bu, SQL standardındaki `NULL` (Bilinmeyen) karşılaştırma mantığından kaynaklanır.

**✅ Doğru:** Her zaman `NOT EXISTS` kullanın. Hem NULL tuzağına düşmezsiniz, hem de genellikle daha performanslı çalışır.

```sql
-- Kötü ve Tehlikeli: Eğer users tablosunda bir tane NULL id varsa sonuç boş döner
SELECT * FROM products WHERE id NOT IN (SELECT user_id FROM users);

-- İyi ve Güvenli:
SELECT * FROM products p 
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = p.id);
```

### ❌ Anti-Pattern: LIMIT ... OFFSET ile Derin Sayfalama (Deep Paging)

`OFFSET 1000000 LIMIT 20` dediğinizde, veritabanı o 1 milyon satırı okur, çöpe atar ve son 20 satırı size verir. Sayfa ilerledikçe sorgu yavaşlar ve CPU'yu felç eder.

**✅ Doğru:** Keyset Pagination (Cursor based) kullanın.

```sql
-- Kötü (Derin sayfalarda çöker)
SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 50 OFFSET 50000;

-- İyi (Her zaman indeks üzerinden çok hızlıdır)
SELECT * FROM audit_logs 
WHERE created_at < '2024-05-10 14:00:00' 
ORDER BY created_at DESC LIMIT 50;
```

### ❌ Anti-Pattern: Fonksiyon İçinde Sütun Kullanımı (SARGability İhlali)

B-Tree indeksler sütunun ham değeri üzerine kuruludur. MySQL'den gelen geliştiricilerin sıklıkla yazdığı `WHERE YEAR(created_at) = 2024` sorgusu, `created_at` üzerindeki indeksi devre dışı bırakır ve Seq Scan'e neden olur.

**✅ Doğru:** Sorguyu indekse uygun tarih aralığına çevirin (`SARGable` sorgu):
`WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'`

### ❌ Anti-Pattern: `count(*)` Takıntısı

`SELECT count(*) FROM table` PostgreSQL'de yavaştır (MVCC yüzünden her satırın canlı olup olmadığına bakmak zorundadır).
**✅ Doğru:** Tahmini değer yeterliyse `pg_class.reltuples` bakın.

---

## 3. İndeksleme Hataları

### ❌ Anti-Pattern: Düşük Kardinalite İndeks

Sadece "Kadın/Erkek" veya "Aktif/Pasif" gibi 2-3 değeri olan sütunlara B-Tree indeks atmanın faydası yoktur. Optimizer zaten tabloyu taramayı tercih eder.
**✅ Doğru:** Kısmi (Partial) İndeks kullanın. `CREATE INDEX ON users (email) WHERE status = 'active';`

---

## 4. Konfigürasyon ve İşletim Hataları

### ❌ Anti-Pattern: Idle in Transaction (Transaction'ı Açık Unutmak)

Uygulamanız bir `BEGIN` bloğu başlatıp (`SELECT` veya `UPDATE` yaptıktan sonra) `COMMIT` veya `ROLLBACK` demeden veritabanı bağlantısını açık bırakırsa bu bir felakettir. Bu "Idle in Transaction" durumları:
1. **Autovacuum'u Bloke Eder:** Kilitlenen transaction'dan daha yeni olan ölü satırlar temizlenemez, sistem hızla şişer (Bloat).
2. **Tablo Kilitlerini Tutar:** DDL işlemlerini engeller.

**✅ Doğru:** Uygulama tarafında connection'ları düzgün kapatın ve PostgreSQL tarafında bir sigorta (timeout) belirleyin.

```sql
-- postgresql.conf içerisine ekleyin (örneğin 60 saniye)
idle_in_transaction_session_timeout = 60000
```

### ❌ Anti-Pattern: VACUUM'u Kapatmak

"Sistemi yavaşlatıyor" diye autovacuum'u kapatmak intihardır. Tablolar şişer, sistem `Wraparound` hatası ile tamamen kapanır.
**✅ Doğru:** Kapatmayın, daha sık ve küçük parçalar halinde çalışmasını sağlayacak şekilde **tune edin**.

---

## Özet: En İyi Pratikler Listesi

1. FK'lerin hepsinde indeks olduğundan emin ol.
2. Connection Pool kullan (PgBouncer).
3. Transaction'ları çok kısa tut, "Idle in Transaction" oluşumuna izin verme.
4. Explain Analyze okumayı öğren.
5. Logları izle (`pg_stat_statements`).
