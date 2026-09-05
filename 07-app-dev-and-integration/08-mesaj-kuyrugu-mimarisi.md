# PostgreSQL Mesaj Kuyrukları ve Olay Güdümlü Mimari (Queueing: SKIP LOCKED & LISTEN/NOTIFY)

Yazılım mimarilerinde arka plan görevlerini (e-posta gönderimi, PDF oluşturma, webhook tetikleme, veri senkronizasyonu) yönetmek için genellikle Redis, RabbitMQ veya Kafka gibi harici mesaj kuyrukları sisteme dahil edilir. Ancak bu durum iki büyük sorun doğurur:
1. **İki Aşamalı Yazma Problemi (Dual-Write Problem):** Veritabanı kaydı başarılı olup kuyruğa mesaj yazılamadığında veya tersi olduğunda veri tutarsızlığı oluşur.
2. **Operasyonel Yük:** Ekstra bir kümenin (cluster) kurulumu, bakımı, yedeklenmesi ve izlenmesi gerekir.

PostgreSQL; **`SELECT ... FOR UPDATE SKIP LOCKED`** ve **`LISTEN / NOTIFY`** mekanizmaları sayesinde, ek bir kuyruk yazılımına ihtiyaç duymadan ACID güvenceli, saniyede binlerce görev işleyebilen son derece dayanıklı bir mesaj kuyruğu motoru olarak çalışabilir.

---

## 1. Geleneksel Kuyruk Anti-Pattern'i vs. SKIP LOCKED

Eski tip veritabanı kuyruklarında yaygın yapılan hata, satırları sorgulayıp ardından durumunu güncellemektir:

```sql
-- ANTİ-PATTERN (Deadlock ve Kilit Yarışı Riski):
SELECT id FROM gorevler WHERE durum = 'BEKLIYOR' LIMIT 1;
-- Uygulama satırı alır, sonra:
UPDATE gorevler SET durum = 'ISLENIYOR' WHERE id = 101;
```

Bu yöntem eşzamanlı (concurrent) çalışan onlarca worker olduğunda kilit yarışına (lock contention) ve aynı görevin birden fazla worker tarafından işlenmesine (race condition) yol açar.

### `SKIP LOCKED` Çözümü:

```text
Worker 1: Satır 1'i kilitledi (FOR UPDATE)
Worker 2: Satır 1'in kilitli olduğunu gördü, BEKLEMEDİ, doğrudan Satır 2'yi kilitledi!
Worker 3: Satır 1 ve 2 kilitli, doğrudan Satır 3'ü kilitledi!
```

`SKIP LOCKED`, kilitli olan satırları beklemeden es geçer (skip eder) ve ilk boştaki satırı atomik olarak rezerve eder. Hiçbir worker kilit için birbirini beklemez; kuyruk kilitlenmesi sıfıra iner.

---

## 2. Transactional Outbox Deseni (Dual-Write Koruması)

Bir kullanıcının siparişini oluştururken aynı anda "Sipariş Onay E-postası" kuyruk görevini de yazmamız gerekir:

```sql
BEGIN;

-- 1. Asıl İş Mantığı
INSERT INTO siparisler (musteri_id, tutar) VALUES (42, 1250.00);

-- 2. Kuyruk Görevi (Aynı Transaction İçinde!)
INSERT INTO gorev_kuyrugu (gorev_tipi, yuk_verisi) 
VALUES ('SIPARIS_ONAY_MAILI', '{"siparis_id": 42, "eposta": "musteri@example.com"}');

COMMIT;
```

Eğer transaction hata alırsa (rollback), ne sipariş kaydedilir ne de e-posta kuyruğa girer. Veri tutarsızlığı imkânsız hale gelir.

---

## 3. Üretim Kalitesinde Kuyruk Şeması ve Dead-Letter Queue

Tam teşekküllü bir kuyruk sistemi; görev önceliği (priority), yeniden deneme (retry) limitleri, gecikmeli çalışma (delay) ve başarısız işler (Dead-Letter Queue - DLQ) mekanizmalarını içermelidir:

```sql
CREATE TYPE gorev_durumu AS ENUM ('BEKLIYOR', 'ISLENIYOR', 'TAMAMLANDI', 'BASARISIZ');

CREATE TABLE gorev_kuyrugu (
    id BIGSERIAL PRIMARY KEY,
    gorev_tipi VARCHAR(100) NOT NULL,
    yuk_verisi JSONB NOT NULL,
    durum gorev_durumu DEFAULT 'BEKLIYOR',
    oncelik INT DEFAULT 100, -- Düşük sayı = Yüksek öncelik
    deneme_sayisi INT DEFAULT 0,
    maks_deneme INT DEFAULT 5,
    son_hata TEXT,
    calisma_zamani TIMESTAMPTZ DEFAULT clock_timestamp(),
    olusturulma_zamani TIMESTAMPTZ DEFAULT clock_timestamp(),
    guncellenme_zamani TIMESTAMPTZ DEFAULT clock_timestamp()
);

-- Hızlı kuyruk çekimi için kısmi (partial) indeks
CREATE INDEX idx_gorevler_kuyruk_taramasi 
ON gorev_kuyrugu (oncelik ASC, calisma_zamani ASC) 
WHERE durum = 'BEKLIYOR';
```

---

## 4. Atomik Görev Çekme (Worker Lock & Fetch)

Worker uygulamaları (Go, Python, Node.js veya Java), kuyruktan iş çekerken aşağıdaki tek ve atomik sorguyu çalıştırır:

```sql
WITH rezerve_edilen AS (
    SELECT id
    FROM gorev_kuyrugu
    WHERE durum = 'BEKLIYOR'
      AND calisma_zamani <= clock_timestamp()
    ORDER BY oncelik ASC, calisma_zamani ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
)
UPDATE gorev_kuyrugu k
SET durum = 'ISLENIYOR',
    deneme_sayisi = deneme_sayisi + 1,
    guncellenme_zamani = clock_timestamp()
FROM rezerve_edilen r
WHERE k.id = r.id
RETURNING k.id, k.gorev_tipi, k.yuk_verisi, k.deneme_sayisi;
```

Bu sorgu:
1. En yüksek öncelikli ve zamanı gelmiş ilk uygun görevi bulur.
2. `FOR UPDATE SKIP LOCKED` ile kilitler.
3. Durumunu anında `ISLENIYOR` yapar.
4. Görev parametrelerini worker'a döner.

---

## 5. Sıfır Gecikme (0 ms) İçin `LISTEN` ve `NOTIFY`

Worker'ların veritabanını sürekli `SELECT` ile yoklaması (polling) gereksiz CPU ve I/O tüketir. PostgreSQL'in yerel yayın/abone (Pub/Sub) mekanizması olan `LISTEN` ve `NOTIFY`, yeni bir görev eklendiğinde worker'ları anında uyandırır:

### 5.1. Trigger ile Otomatik Bildirim Tetikleme:

```sql
CREATE OR REPLACE FUNCTION trg_yeni_gorev_bildirimi()
RETURNS TRIGGER AS $$
BEGIN
    -- Kanala görev ID'sini içeren bildirim gönder
    PERFORM pg_notify('kuyruk_yeni_gorev', NEW.id::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_gorev_eklendi
AFTER INSERT ON gorev_kuyrugu
FOR EACH ROW
WHEN (NEW.durum = 'BEKLIYOR')
EXECUTE FUNCTION trg_yeni_gorev_bildirimi();
```

### 5.2. Worker Dinleme Prensibi (Pseudocode / psql):

```sql
-- Worker oturum açtığında kanalı dinlemeye başlar
LISTEN kuyruk_yeni_gorev;

-- Yeni bir INSERT yapıldığında PostgreSQL bağlantıya anında asenkron mesaj iletir:
-- Asynchronous notification "kuyruk_yeni_gorev" with payload "1054" received from server process.
```

Worker mesajı aldığı anda `SELECT ... FOR UPDATE SKIP LOCKED` sorgusunu çalıştırarak görevi işler; böylece görev eklenmesiyle işlenmesi arasındaki gecikme milisaniyenin altına iner.

---

## 6. Hata Yönetimi ve Üstel Geri Çekilme (Exponential Backoff)

Görev işlenirken harici bir API çöktüyse veya hata alındıysa, görevin anında tekrar denenmesi sistemi boğabilir. Üstel geri çekilme ile çalışma zamanı ileriye ötelenir:

```sql
CREATE OR REPLACE FUNCTION sp_gorev_hata_kaydet(
    p_gorev_id BIGINT,
    p_hata_mesaji TEXT
)
RETURNS VOID AS $$
DECLARE
    v_deneme INT;
    v_maks INT;
BEGIN
    SELECT deneme_sayisi, maks_deneme INTO v_deneme, v_maks
    FROM gorev_kuyrugu WHERE id = p_gorev_id;

    IF v_deneme >= v_maks THEN
        -- Maksimum deneme aşıldı: Dead Letter Queue (DLQ) durumuna al
        UPDATE gorev_kuyrugu
        SET durum = 'BASARISIZ',
            son_hata = p_hata_mesaji,
            guncellenme_zamani = clock_timestamp()
        WHERE id = p_gorev_id;
    ELSE
        -- Üstel geri çekilme: (deneme ^ 3) * 10 saniye sonra tekrar dene
        UPDATE gorev_kuyrugu
        SET durum = 'BEKLIYOR',
            son_hata = p_hata_mesaji,
            calisma_zamani = clock_timestamp() + (POWER(v_deneme, 3) * INTERVAL '10 second'),
            guncellenme_zamani = clock_timestamp()
        WHERE id = p_gorev_id;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

---

## 7. PostgreSQL Kuyrukları Ne Zaman Kullanılmalı, Ne Zaman Kullanılmamalı?

| Senaryo | PostgreSQL (SKIP LOCKED) | RabbitMQ / Kafka / Redis |
| :--- | :--- | :--- |
| **İş Akışı Gereksinimi** | İş verisi ile kuyruğun aynı atomik transaction'da olması şart (Sipariş + Mail, Fatura + Ödeme) | Saf log akışı, IoT sensör verisi, telemetri |
| **Hacim (Throughput)** | Saniyede 100 - 10.000 görev | Saniyede 50.000+ - 1.000.000+ mesaj |
| **Operasyonel Sadeleşme**| Tek veritabanı, sıfır harici servis, standart SQL yedekleme | İlave küme (Cluster), Zookeeper/KRaft, ek monitoring |
| **Mesaj Saklama** | İstenildiği kadar geçmişe dönük sorgulanabilir, SQL ile raporlanabilir | Geçici bellek (Redis) veya TTL kısıtlı retention |
