# İleri Düzey Eşzamanlılık: Savepoints, 2PC ve Kilit Çakışma Matrisi

> **Bölüm Kapsamı:** Savepoints ile Kısmi Geri Alma, İki Aşamalı Commit (Two-Phase Commit / 2PC), Orphan Transaction Tehlikesi, 8 Seviyeli Tablo Kilit Matrisi ve Advisory Locks (Danışma Kilitleri)

---

PostgreSQL'in eşzamanlılık (concurrency) mekanizması basit `BEGIN ... COMMIT` işlemlerinin çok ötesindedir. Büyük hacimli veri akışlarında, mikroservis mimarilerinde ve dağıtık transaction koordinasyonunda kullanılan kritik ileri seviye mekanizmalar aşağıda detaylandırılmıştır.

---

## 1. Savepoints (Kayıt Noktaları ve Kısmi Geri Alma)

PostgreSQL'de standart bir transaction içinde herhangi bir SQL ifadesi hata verirse (`ERROR`), transaction anında **"aborted"** durumuna düşer. Bu andan sonra `COMMIT` deseniz bile tüm transaction geri alınır (`ROLLBACK`) ve şu meşhur hata döner:

```log
ERROR: current transaction is aborted, commands ignored until end of transaction block
```

### Savepoint Kullanımı

Savepoint'ler, bir işlem bloğu içinde kontrol noktaları oluşturarak hata oluştuğunda **tüm işlemi iptal etmek yerine sadece hata veren noktaya kadar geri dönmeyi** sağlar:

```sql
BEGIN;

-- 1. Müşteriyi ekle
INSERT INTO customers (id, name) VALUES (101, 'Ahmet Yılmaz');

-- 2. Güvenli nokta oluştur
SAVEPOINT sp_order_step;

-- 3. Hatalı bir işlem dene (Örn: Olmayan ürün veya kısıt ihlali)
INSERT INTO orders (id, customer_id, amount) VALUES (501, 101, -250); 
-- ERROR: check constraint "orders_amount_check" violated

-- 4. Hatanın ardından sadece Savepoint'e geri dön (Transaction kurtarılır!)
ROLLBACK TO SAVEPOINT sp_order_step;

-- 5. Doğru veriyi ekle ve commit et
INSERT INTO orders (id, customer_id, amount) VALUES (501, 101, 250);

-- Savepoint'i bellekten temizle (Opsiyonel)
RELEASE SAVEPOINT sp_order_step;

COMMIT; -- Başarıyla kaydedilir!
```

> [!TIP]
> **İç İçe Savepoint'ler (Nested Savepoints):** Bir transaction içinde hiyerarşik olarak birden fazla savepoint açılabilir. `ROLLBACK TO SAVEPOINT` çağrısı, o savepoint'ten sonra tanımlanmış tüm alt savepoint'leri otomatik olarak geçersiz kılar.

---

## 2. Dağıtık İşlemler: Two-Phase Commit (2PC)

Mikroservisler veya birden fazla bağımsız veritabanı (örneğin iki ayrı PostgreSQL sunucusu veya bir ödeme sağlayıcı entegrasyonu) arasında ACID garantisi sağlamak için **İki Aşamalı İşlem (Two-Phase Commit / 2PC)** kullanılır.

Standart bir transaction istemci bağlantısı koptuğunda otomatik olarak `ROLLBACK` edilir. Ancak 2PC ile hazırlanan bir transaction, **oturum kapansa ve hatta PostgreSQL sunucusu yeniden başlasa (reboot) dahi diske (`pg_twophase/`) kilitli kalır** ve harici bir koordinatörün onayını bekler.

### 2PC Adımları

```sql
-- 1. Aşama: İşlemleri yap ve Hazırla (Prepare)
BEGIN;
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
PREPARE TRANSACTION 'tx_havale_20240518_9981';

-- Bu aşamada transaction sunucudan ayrılır (detach edilir).
-- İstemci bağlantısını kapatsa bile işlem askıda ve güvenle bekler!
```

Koordinatör diğer sunuculardan da "Hazırım" onayını aldığında 2. aşamayı tetikler:

```sql
-- 2. Aşama: Nihai Karar (Commit veya Rollback)
COMMIT PREPARED 'tx_havale_20240518_9981';

-- Veya diğer serviste hata çıktıysa geri al:
-- ROLLBACK PREPARED 'tx_havale_20240518_9981';
```

### 2PC Yapılandırması ve Askıda Kalan (Orphan) İşlem Tehlikesi

2PC kullanabilmek için `postgresql.conf` içinde parametrenin açılması gerekir:

```ini
max_prepared_transactions = 100  # max_connections ile aynı veya orantılı olmalıdır
```

```sql
-- Askıda kalan 2PC işlemlerini izleyin:
SELECT gid, prepared, owner, database FROM pg_prepared_xacts;
```

> [!CAUTION]
> **DBA Felaket Senaryosu (Orphan 2PC):** Dağıtık mimaride koordinatör çöker ve hazırlanan işlemi `COMMIT PREPARED` veya `ROLLBACK PREPARED` ile sonlandırmayı unutursa, bu transaction sonsuza kadar askıda kalır!
> 1. İlgili tablolardaki kilitleri bırakmaz.
> 2. `pg_xact` durumunu tuttuğu için `VACUUM`'ın eski satırları temizlemesini engeller (Büyük Bloat).
> 3. En tehlikelisi: Transaction ID sayacını dondurarak **XID Wraparound** krizine ve veritabanının acil durum modunda kapanmasına neden olur!
> **Kural:** `pg_prepared_xacts` tablosunu Prometheus ile izleyin ve 1 saatten eski işlemleri otomatik alarm mekanizmasına bağlayın.

---

## 3. Tablo Kilit Çakışma Matrisi (Lock Conflict Matrix)

PostgreSQL, tablo düzeyinde **8 farklı kilit modu** uygular. Hangi SQL komutunun hangi kilit seviyesini aldığını ve hangi işlemlerin birbirini beklettiğini bilmek, kilitlenme (deadlock ve lock waiting) krizlerini çözmenin temelidir.

### 8 Tablo Kilit Seviyesi ve Üreten Komutlar:
1. **Access Share (AS):** `SELECT` (Yalnızca Access Exclusive ile çakışır).
2. **Row Share (RS):** `SELECT FOR UPDATE`, `SELECT FOR SHARE`.
3. **Row Exclusive (RX):** `INSERT`, `UPDATE`, `DELETE`.
4. **Share Update Exclusive (SUE):** `VACUUM` (standart), `ANALYZE`, `CREATE INDEX CONCURRENTLY`, `ALTER TABLE VALIDATE`.
5. **Share (S):** `CREATE INDEX` (standart - okumaya izin verir, yazmayı engeller).
6. **Share Row Exclusive (SRE):** `CREATE TRIGGER`, nadir DDL'ler.
7. **Exclusive (X):** `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
8. **Access Exclusive (AE):** `DROP TABLE`, `TRUNCATE`, `VACUUM FULL`, `REINDEX TABLE`, `CLUSTER`, `ALTER TABLE ADD COLUMN`.

### Çakışma Matrisi Tablosu

Aşağıdaki tabloda **X** işareti, ilgili iki kilit modunun birbiriyle çakıştığını ve biri çalışırken diğerinin bekleyeceğini (Lock Wait) gösterir:

| Talep Edilen / Mevcut Kilit | AS | RS | RX | SUE | S | SRE | X | AE |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Access Share (AS)** | | | | | | | | **X** |
| **Row Share (RS)** | | | | | | | **X** | **X** |
| **Row Exclusive (RX)** | | | | | **X** | **X** | **X** | **X** |
| **Share Update Exclusive (SUE)** | | | | **X** | **X** | **X** | **X** | **X** |
| **Share (S)** | | | **X** | **X** | | **X** | **X** | **X** |
| **Share Row Exclusive (SRE)** | | | **X** | **X** | **X** | **X** | **X** | **X** |
| **Exclusive (X)** | | **X** | **X** | **X** | **X** | **X** | **X** | **X** |
| **Access Exclusive (AE)** | **X** | **X** | **X** | **X** | **X** | **X** | **X** | **X** |

> [!NOTE]
> **Önemli Çıkarım:** `CREATE INDEX CONCURRENTLY` (SUE modu), `INSERT`, `UPDATE` ve `DELETE` (RX modu) ile **ÇAKIŞMAZ**! Bu yüzden canlı sistemde index atarken `CONCURRENTLY` parametresi sistemi durdurmaz.

---

## 4. Danışma Kilitleri (Advisory Locks)

Veritabanındaki belirli bir tablo veya satırı kilitlemek yerine, uygulamanızın iş mantığı için **tamamen sanal bir sayısal anahtar (`BIGINT`) üzerinden kilit almasını** sağlar. Veritabanı tablosuna hiçbir kilit konulmaz; kilit bellekte (`shared_buffers` lock tablosunda) tutulur ve son derece hızlıdır.

### Kullanım Senaryosu: Cronjob / Worker Dağıtık Koordinasyonu
Aynı anda 5 ayrı pod veya sunucuda çalışan bir arka plan görevinin (örneğin "Ay Sonu Fatura Üretimi") aynı anda iki makine tarafından çalıştırılmasını önlemek:

```sql
-- 1. Kilidi almaya çalış (Non-blocking / Beklemeden dene)
SELECT pg_try_advisory_lock(99001);

-- Çıktı:
-- true  -> Kilit alındı, görevi sadece bu worker çalıştıracak!
-- false -> Başka bir worker şu an bu görevi yapıyor, pas geç!
```

```sql
-- İşlem tamamlandığında kilidi bırak:
SELECT pg_advisory_unlock(99001);
```

### Transaction Düzeyinde Advisory Lock:
İşlem bittiğinde kilidin otomatik serbest bırakılmasını istiyorsanız:
```sql
BEGIN;
SELECT pg_advisory_xact_lock(99001);
-- İşlemler...
COMMIT; -- Kilit transaction bitince otomatik serbest bırakılır
```
