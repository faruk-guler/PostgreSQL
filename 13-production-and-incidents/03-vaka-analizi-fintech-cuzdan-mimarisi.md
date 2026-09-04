# Capstone 1: FinTech Cüzdan (Wallet) Mimarisi

> **Bölüm Kapsamı:** Sıfır hata, bakiye kaybı olmayan (Zero-Loss) uçtan uca ödeme/cüzdan (Ledger) veritabanı mimarisinin tasarımı, İzolasyon seviyeleri ve Idempotency.

---

Finansal (FinTech) sistemlerde veritabanı tasarlamak sıradan bir web sitesine benzemez. Kullanıcının bakiyesinin aynı saniyede 10 kere çekilmeye (Race Condition) karşı dirençli olması, giden paranın mutlaka bir yere girdiğinin çift taraflı (Double-Entry) kanıtlanması gerekir.

## 1. Veri Modelleme (Double-Entry Ledger)

Bakiyeyi sadece `users` tablosunda bir `balance` sütununda tutmak yanlıştır. Veritabanında bir "Muhasebe Defteri" (Ledger) tutulmalıdır. Giren para +, çıkan para - olarak ayrı satırlara yazılır. Toplam bakiye bu satırların toplamıdır.

```sql
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    currency VARCHAR(3) DEFAULT 'TRY',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID REFERENCES accounts(id),
    amount NUMERIC(15, 2) NOT NULL, -- Çıkan para eksi, giren artı
    reference_id VARCHAR(100) UNIQUE NOT NULL, -- Idempotency Key!
    type VARCHAR(50) NOT NULL, -- 'DEPOSIT', 'WITHDRAWAL', 'TRANSFER'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Idempotency (Tekrarlanabilirlik) Anahtarı
Kullanıcı ödeme yap butonuna 5 kere basarsa, parası 5 kere mi düşecek? Hayır. `reference_id` sütunundaki `UNIQUE` constraint sayesinde aynı sipariş numarası/referans ile gelen ikinci insert işlemi `unique_violation` (Hata 23505) fırlatarak işlemi reddeder.

## 2. Para Transferi Fonksiyonu (Race Condition Önleme)

A kullanıcısından B kullanıcısına 100 TL gönderirken "Race Condition"ı (aynı anda parasını çekme) engellemenin 2 yolu vardır.

### Yöntem 1: Row-Level Lock (Satır Kilidi)
Verileri okurken `FOR UPDATE` kullanarak işlemi bitirene kadar o bakiyeyi (satırı) başkasına kitlersiniz.

```sql
BEGIN;

-- A hesabını kitle ve bakiyesini kontrol et
SELECT coalesce(sum(amount), 0) INTO current_balance 
FROM transactions 
WHERE account_id = 'A_ID' FOR UPDATE;

IF current_balance < 100 THEN
    RAISE EXCEPTION 'Yetersiz bakiye';
END IF;

-- A'dan parayı düş (-)
INSERT INTO transactions (account_id, amount, reference_id, type)
VALUES ('A_ID', -100, 'ref_123', 'TRANSFER_OUT');

-- B'ye parayı ekle (+)
INSERT INTO transactions (account_id, amount, reference_id, type)
VALUES ('B_ID', 100, 'ref_123', 'TRANSFER_IN');

COMMIT;
```

### Yöntem 2: Serializable İzolasyon Seviyesi
Kilit yönetimi ile uğraşmak istemiyorsanız (çünkü deadlock riski yüksektir), veritabanına "Sanki dünyada bu işlemden başka hiçbir işlem o an yapılmıyormuş gibi davran" diyebilirsiniz.

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;

-- Bakiyeyi hesapla
SELECT sum(amount) FROM transactions WHERE account_id = 'A_ID';
-- (Uygulama katmanında kontrol et, bakiye yetiyorsa yaz)

INSERT INTO transactions ...
INSERT INTO transactions ...

COMMIT;
```
*Not: Serializable seviyesinde iki işlem aynı anda bakiyeyi etkileyecek okuma/yazma yaparsa PostgreSQL "Serialization Failure" (Hata 40001) fırlatır. Uygulamanızın bu hatayı yakalayıp (Catch) işlemi 1-2 saniye sonra tekrar etmesi (Retry) gerekir.*

## 3. Performans İçin Bakiye Cache Tablosu

Milyonlarca transaction olduğunda `SUM(amount)` yapmak sistemi yorar (Tablo boyutu büyüdükçe yavaşlar).
Sisteme (denormalize) bir `account_balances` tablosu eklenir. Ancak bu tablo sadece bir Trigger veya dikkatli bir Transaction ile `transactions` tablosuyla eşzamanlı (Atomic) güncellenir.

```sql
CREATE TABLE account_balances (
    account_id UUID PRIMARY KEY REFERENCES accounts(id),
    current_balance NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (current_balance >= 0),
    version BIGINT NOT NULL DEFAULT 1 -- Optmistic Locking için
);
```

**`CHECK (current_balance >= 0)`** constraint'i, veritabanı düzeyindeki son kaledir. Kodunuz hata yapsa bile, eksi bakiyeye düşüren bir UPDATE işlemi bu kısıtlamaya çarpar ve geri alınır (Rollback).
