# Özel Yetenekler (Specialty Features)

> **Bölüm Kapsamı:** LISTEN/NOTIFY Olay Tabanlı Mesajlaşma, JIT (Just-In-Time) Derleme ve Two-Phase Commit (2PC)

---

Bu modülde, PostgreSQL'in sıklıkla bilinmeyen ama belirli mimari senaryolar için kritik öneme sahip olan ileri düzey yetenekleri ele alınmaktadır.


## 1. LISTEN/NOTIFY: Event-Driven Programming

PostgreSQL, bir Pub-Sub (Publisher-Subscriber) mesajlaşma sistemi sağlar. Bu özellik, uygulamaların veritabanındaki olaylara **gerçek zamanlı** tepki vermesini sağlar.

### Kullanım Senaryosu

Bir e-ticaret sitenizde sipariş durumu değiştiğinde, frontend'in anında bildirim alması gerekiyorsa, polling (sürekli veritabanını sorgulamak) yerine LISTEN/NOTIFY kullanabilirsiniz.

### Basit Örnek

**Session 1 (Listener):**

```sql
LISTEN siparis_guncelleme;

-- Artık bu session, "siparis_guncelleme" kanalındaki mesajları dinliyor.
-- Mesaj geldiğinde psql'de iletiler görünür.
```

**Session 2 (Publisher):**

```sql
-- Bir sipariş durumu değiştiğinde:
UPDATE orders SET status = 'shipped' WHERE id = 123;

-- Diğer uygulamalara bildir:
NOTIFY siparis_guncelleme, '{"order_id": 123, "status": "shipped"}';
```

### Uygulama Kodu ile Kullanım (Python)

```python
import psycopg
import select

conn = psycopg.connect("dbname=mydb")
conn.autocommit = True

cur = conn.cursor()
cur.execute("LISTEN siparis_guncelleme")

print("Olaylar bekleniyor...")
while True:
    if select.select([conn], [], [], 5) == ([], [], []):
        print("Timeout (5 saniye olay yok)")
    else:
        conn.poll()
        while conn.notifies:
            notify = conn.notifies.pop(0)
            print(f"Olay alındı: {notify.payload}")
```

> [!TIP]
> NOTIFY mesajları transaction içinde gönderilirse, COMMIT edilene kadar gönderilmez. Bu, veri tutarlılığını sağlar.

---

## 2. JIT Compilation (Just-In-Time)

PostgreSQL 11 ile gelen JIT, sorgu çalıştırma sırasında makine kodunu dinamik olarak derler. Özellikle karmaşık ifadeler (expressions) ve büyük veri setlerinde %30-40 hızlanma sağlayabilir.

### Kontrol ve Aktifleştirme

```sql
-- JIT etkin mi?
SHOW jit;

-- Varsayılan olarak açık ama eşik değerleri yüksektir
SHOW jit_above_cost;        -- 100000 (maliyeti bu değeri aşan sorgu)
SHOW jit_inline_above_cost; -- 500000
```

### JIT Kullanımını İzleme

```sql
EXPLAIN (ANALYZE, VERBOSE) 
SELECT sum(price * quantity) 
FROM large_table 
WHERE category = 'electronics';

-- Çıktıda "JIT:" bloğu görünürse kullanıldı demektir.
```

### JIT için Ön Koşullar

- LLVM kurulu olmalı (Çoğu modern dağıtımda varsayılan).
- Büyük veri setleri ve hesaplama yoğun sorgular için faydalıdır.

---

## 3. Two-Phase Commit (2PC) - Distributed Transactions

Normal bir transaction tek bir veritabanında atomiktir. Ancak birden fazla veritabanı arasında (örneğin: PostgreSQL + Oracle) transaction yapıyorsanız, "İki-Fazlı Commit" protokolü kullanılır.

### Kullanım Senaryosu

Bir bankacılık uygulamasında, kullanıcının hesabından para çekilip başka bir sistemdeki hesaba yatırılması gerekiyorsa, her iki işlem de ya birlikte başarılı olmalı ya da hiçbiri olmamalı.

### Örnek Akış

```sql
-- 1. Transaction başlat ve işlemleri yap
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;

-- 2. Transaction'ı "hazır" durumuna getir (Commit etme ama durumu kaydet)
PREPARE TRANSACTION 'transfer_123';

-- Şu anda transaction hala açık ama bekleme modunda
```

**Dış sistemde (örneğin Oracle) benzer hazırlık yapılır.**

```sql
-- 3. Her iki taraf hazırsa, ikisini de birden commit et:
COMMIT PREPARED 'transfer_123';

-- Eğer bir tarafta sorun çıkarsa:
ROLLBACK PREPARED 'transfer_123';
```

> [!CAUTION]
> Prepared Transactions, PostgreSQL'de varsayılan olarak **kapalıdır**. Aktifleştirmek için `max_prepared_transactions` değerini `postgresql.conf`'ta 0'dan büyük yapın (örn: 10).

### Unutulan Prepared Transactions

Eğer bir 2PC transaction commit/rollback edilmezse, veritabanında "takılı kalır" ve bazı kaynakları kilitler. İzlemek için:

```sql
SELECT * FROM pg_prepared_xacts;
```

---

## 4. Özet

Bu 3 özellik, PostgreSQL'in "klasik ilişkisel veritabanı" sınırlarını aşan yeteneklerini gösterir:

- **LISTEN/NOTIFY:** Event-driven architecture desteği.
- **JIT:** Modern derleyici optimizasyonları ile ağır analitik yüklerin hızlandırılması.
- **2PC:** Enterprise dağıtık mimarilerde atomik işlemler.
