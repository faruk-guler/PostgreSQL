# Temel Contrib Eklentileri: citext, unaccent, btree_gist, pgcrypto ve uuid-ossp

PostgreSQL kaynak koduyla birlikte dağıtılan ve resmi topluluk tarafından sürdürülen eklenti paketlerine **contrib modülleri** denir. Bu modüller harici bir bağımlılık gerektirmeden veritabanının yeteneklerini zenginleştirir.

Bu rehberde; kurumsal projelerde en sık başvurulan beş temel eklentiyi (`citext`, `unaccent`, `btree_gist`, `pgcrypto` ve `uuid-ossp`) üretim senaryolarıyla inceleyeceğiz.

---

## 1. `citext`: Büyük/Küçük Harfe Duyarsız Metin Tipi

Standart PostgreSQL `text` ve `varchar` tipleri harf duyarlıdır (case-sensitive). E-posta adresleri veya kullanıcı adları gibi alanlarda `admin@site.com` ile `Admin@site.com` eşit kabul edilmez.

Geleneksel çözüm sorgularda ve indekslerde `LOWER()` kullanmaktır:
```sql
SELECT * FROM kullanicilar WHERE lower(eposta) = lower('Ahmet@Site.Com');
-- İndeks kullanımı için fonksiyonel indeks şarttır:
CREATE INDEX idx_kullanici_eposta ON kullanicilar (lower(eposta));
```

**Dezavantajlar:**
- Her sorguda `lower()` yazma zorunluluğu kod kalitesini düşürür.
- `UNIQUE` veya `PRIMARY KEY` kısıtları büyük/küçük harf varyasyonlarını engelleyemez.

### 1.1. `citext` Çözümü

```sql
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE musteriler (
    id SERIAL PRIMARY KEY,
    kullanici_adi CITEXT UNIQUE NOT NULL,
    eposta CITEXT UNIQUE NOT NULL
);

INSERT INTO musteriler (kullanici_adi, eposta) 
VALUES ('johndoe', 'John.Doe@example.com');

-- İkinci ekleme harf farkı olsa dahi UNIQUE hatası verir!
-- INSERT INTO musteriler VALUES ('JohnDoe', 'john.doe@example.com'); -> HATA!

-- Doğrudan standart arama (lower() gerekmez, normal B-Tree indeksi kullanılır):
SELECT * FROM musteriler WHERE eposta = 'JOHN.DOE@EXAMPLE.COM';
```

---

## 2. `unaccent`: Aksan ve Yumuşatma Karakteri Süzgeci

Türkçe (`ç, ğ, ı, ö, ş, ü`) ve Avrupa dillerindeki aksanlı harfler (`é, à, ö, ñ, ç`), metin aramalarında kullanıcıların aksansız arama yapması durumunda eşleşmeyi bozar.

`unaccent` eklentisi, aksanlı karakterleri `$SHAREDIR/tsearch_data/unaccent.rules` sözlüğünü kullanarak otomatik olarak düz harflere dönüştüren bir metin arama sözlüğüdür.

```sql
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Doğrudan fonksiyon kullanımı:
SELECT unaccent('İstanbul Şişli ve Çeşme Otelleri');
-- Çıktı: 'Istanbul Sisli ve Cesme Otelleri'

-- Tam Metin Arama (Full Text Search) ile Entegrasyon:
CREATE TEXT SEARCH CONFIGURATION tr_unaccent (COPY = turkish);
ALTER TEXT SEARCH CONFIGURATION tr_unaccent
    ALTER MAPPING FOR hword, hword_part, word
    WITH unaccent, turkish_stem;

-- Artık aksansız yapılan arama aksanlı kelimeyi anında bulur:
SELECT to_tsvector('tr_unaccent', 'Göztepe Spor Kulübü') 
       @@ to_tsquery('tr_unaccent', 'goztepe');
-- Çıktı: true
```

---

## 3. `btree_gist`: Standart Tiplerle Çakışma Önleyici Kısıtlar (Exclusion Constraints)

Normal şartlarda PostgreSQL'in gelişmiş **Hariç Tutma Kısıtları (Exclusion Constraints)** geometrik ve aralık (range) tipleri için GiST indeksleri üzerinde çalışır. Ancak bir otel rezervasyonunda veya toplantı odası uygulamasında:
*"Aynı `oda_id` için tarih aralıkları `&&` (çakışamaz)"* kuralı tanımlamak isterseniz, `oda_id` (integer) tipi GiST tarafından doğrudan desteklenmez.

`btree_gist` eklentisi, standart skaler tiplerin (`int`, `text`, `timestamp`, `uuid`) GiST indekslerinde eşitlik (`=`) ve büyüklük operatörleriyle kullanılmasına imkan tanır.

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE oda_rezervasyonlari (
    id SERIAL PRIMARY KEY,
    oda_no INT NOT NULL,
    tarih_araligi TSRANGE NOT NULL,
    
    -- Çakışma kısıtı: Aynı oda_no için tarih aralıkları asla kesişemez!
    CONSTRAINT cakisamayan_rezervasyon 
    EXCLUDE USING gist (oda_no WITH =, tarih_araligi WITH &&)
);

-- İlk rezervasyon (101 numaralı oda, 1 - 5 Eylül)
INSERT INTO oda_rezervasyonlari (oda_no, tarih_araligi)
VALUES (101, tsrange('2026-09-01 14:00', '2026-09-05 11:00'));

-- İkinci rezervasyon (Farklı oda, aynı tarih - BAŞARILI)
INSERT INTO oda_rezervasyonlari (oda_no, tarih_araligi)
VALUES (102, tsrange('2026-09-02 14:00', '2026-09-04 11:00'));

-- Üçüncü rezervasyon (101 numaralı oda, çakışan tarih - ANINDA HATA VERİR!)
INSERT INTO oda_rezervasyonlari (oda_no, tarih_araligi)
VALUES (101, tsrange('2026-09-04 10:00', '2026-09-06 11:00'));
-- ERROR: conflicting key value violates exclusion constraint "cakisamayan_rezervasyon"
```

---

## 4. `pgcrypto`: Veritabanı İçi Şifreleme ve Kriptografi

Veritabanı katmanında parola özetleme (hashing), simetrik şifreleme ve dijital imza işlemleri için kullanılır.

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

### 4.1. Güvenli Parola Saklama (`crypt` + Blowfish Salt)

```sql
CREATE TABLE kullanici_hesaplari (
    id SERIAL PRIMARY KEY,
    kullanici_adi TEXT UNIQUE,
    parola_hash TEXT NOT NULL
);

-- Blowfish (bcrypt) maliyet faktörü 10 ile şifreleme:
INSERT INTO kullanici_hesaplari (kullanici_adi, parola_hash)
VALUES ('ahmet', crypt('CokGizliSifre!2026', gen_salt('bf', 10)));

-- Parola Doğrulama:
SELECT (parola_hash = crypt('CokGizliSifre!2026', parola_hash)) AS parola_dogru_mu
FROM kullanici_hesaplari 
WHERE kullanici_adi = 'ahmet';
-- Çıktı: true
```

### 4.2. Simetrik Veri Şifreleme (AES / PGP)

Hassas kredi kartı veya kimlik numaralarını diskte şifreli saklama:

```sql
-- Şifreleme (AES-256)
SELECT pgp_sym_encrypt('TR980006100511123456789012', 'SirketGizliAnahtari') AS sifreli_iban;

-- Çözümleme (Decryption)
SELECT pgp_sym_decrypt(
    pgp_sym_encrypt('TR980006100511123456789012', 'SirketGizliAnahtari'), 
    'SirketGizliAnahtari'
) AS cozulmus_iban;
-- Çıktı: 'TR980006100511123456789012'
```

---

## 5. `uuid-ossp`: Standart Evrensel Benzersiz Tanımlayıcılar

Dağıtık sistemlerde ve mikroservis mimarilerinde çakışmasız kimlik üretimi için RFC 4122 uyumlu UUID'ler tercih edilir:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE siparis_kayitlari (
    siparis_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tutar NUMERIC(10,2) NOT NULL,
    olusturma_tarihi TIMESTAMPTZ DEFAULT now()
);

INSERT INTO siparis_kayitlari (tutar) VALUES (1450.75);
SELECT * FROM siparis_kayitlari;
-- siparis_id: 3c6f1a8e-2b47-4e92-8173-9a84f3c7e0d1
```

> [!TIP]
> PostgreSQL 13 ve sonrasında, `uuid-ossp` eklentisine gerek kalmadan doğrudan çekirdeğe gömülü `gen_random_uuid()` fonksiyonu kullanılabilir. PostgreSQL 17 ile birlikte zamana göre sıralı **UUIDv7** standardı da çekirdeğe dahil edilmiştir.
