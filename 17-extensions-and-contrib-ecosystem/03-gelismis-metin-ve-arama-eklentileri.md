# Gelişmiş Metin, Benzerlik ve Ağaç Eklentileri: pg_trgm, fuzzystrmatch ve ltree

Metin arama ve hiyerarşik veri yapıları, ilişkisel veritabanlarının en çok zorlandığı alanların başında gelir. PostgreSQL, standart SQL'in sınırlarını aşan **trigram metin benzerliği (`pg_trgm`)**, **fonetik ve mesafe analizi (`fuzzystrmatch`)** ve **hiyerarşik ağaç yapıları (`ltree`)** eklentileriyle harici arama motorlarına (Elasticsearch vb.) duyulan ihtiyacı büyük ölçüde ortadan kaldırır.

---

## 1. `pg_trgm`: Trigram Benzerlik Analizi ve İndeksleme

Bir metnin 3 ardışık karakterlik parçalarına **Trigram** denir. Örneğin `'postgres'` kelimesinin trigramları:
`"  p", " po", "pos", "ost", "stg", "tgr", "gre", "res", "es "` şeklindedir.

Standart B-Tree indeksleri `LIKE 'kelime%'` (önek) aramalarını desteklerken, `LIKE '%kelime%'` (baştan jokerli) sorgularında **Full Table Scan** yapmak zorundadır. `pg_trgm` eklentisi, GIN veya GiST indeksleri üzerinde trigram eşleşmesi yaparak bu sorguları binlerce kat hızlandırır.

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

### 1.1. Benzerlik Fonksiyonları ve Operatörler

```sql
-- Trigram parçalarını görme:
SELECT show_trgm('PostgreSQL');

-- İki metin arasındaki benzerlik oranı (0.0 ile 1.0 arası):
SELECT similarity('PostgreSQL', 'Postgre');
-- Çıktı: 0.7

-- Kelime benzerliği (Metin içinde geçiş oranı):
SELECT word_similarity('sql', 'Gelişmiş PostgreSQL Kılavuzu');
-- Çıktı: 1.0
```

| Operatör | Anlamı | Açıklama |
| :--- | :--- | :--- |
| `text % text` | Benzerlik Eşiği | İki metin `pg_trgm.similarity_threshold` (varsayılan 0.3) üzerinde benziyorsa `true` döner. |
| `text <-> text` | Trigram Mesafesi | 1 - similarity. En yakın sonuçları sıralamak için (KNN ORDER BY) kullanılır. |
| `text <% text` | Kelime Benzerliği | İlk kelime ikinci metin parçasında geçiyorsa `true` döner. |

### 1.2. `LIKE '%...%'` ve Otomatik Tamamlama İndeksleme Reçetesi

Milyonlarca ürünün bulunduğu bir e-ticaret tablosunda:

```sql
CREATE TABLE urunler (
    id SERIAL PRIMARY KEY,
    ad TEXT NOT NULL
);

-- GIN Trigram İndeksi Oluşturma:
CREATE INDEX idx_urunler_ad_trgm ON urunler USING gin (ad gin_trgm_ops);

-- Artık baştan ve sondan jokerli aramalar doğrudan indeksten yanıtlanır:
EXPLAIN ANALYZE 
SELECT * FROM urunler WHERE ad ILIKE '%bluetooth kulaklık%';
-- Plan Çıktısı: Bitmap Index Scan on idx_urunler_ad_trgm (Milisaniyenin altında yanıt!)
```

### 1.3. Yazım Hatalarını Tolere Eden Arama (Fuzzy Search)

Kullanıcı "bilgiseyar" yazsa bile veritabanındaki "bilgisayar" ürününü en yakın mesafeye göre sıralama:

```sql
SELECT ad, similarity(ad, 'bilgiseyar') AS benzerlik
FROM urunler
WHERE ad % 'bilgiseyar'
ORDER BY ad <-> 'bilgiseyar'
LIMIT 5;
```

---

## 2. `fuzzystrmatch`: Fonetik Eşleme ve Düzenleme Mesafesi

Kelimelerin yazılışından ziyade okunuş benzerliğini (Soundex/Metaphone) veya iki kelimeyi birbirine dönüştürmek için gereken harf değiştirme sayısını (Levenshtein) hesaplar.

```sql
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
```

### 2.1. Levenshtein Mesafesi

Bir kelimeyi diğerine dönüştürmek için gereken minimum ekleme, silme ve değiştirme işlem adedi:

```sql
SELECT levenshtein('Ahmet', 'Mehmet');
-- Çıktı: 2 ('A' silindi, 'M' ve 'e' eklendi)

SELECT levenshtein('PostgreSQL', 'Postgre');
-- Çıktı: 3
```

### 2.2. Metaphone ve Double Metaphone (Fonetik Arama)

İsimlerin telaffuz kodlarını çıkararak ses benzerliğine göre eşleme yapar:

```sql
-- İngilizce/Evrensel fonetik kod:
SELECT dmetaphone('Smith'), dmetaphone('Smyth');
-- Her ikisi de 'SM0' kodunu üretir!

-- Veritabanında isim sorgularken:
SELECT * FROM yazarlar WHERE dmetaphone(soyad) = dmetaphone('Schmidt');
```

---

## 3. `ltree`: Hiyerarşik Ağaç Veri Yapıları

E-ticaret kategori ağaçları, organizasyon şemaları ve dosya dizinleri gibi hiyerarşik yapıları standart ilişkisel tablolarda `parent_id` ile tutmak, sorgulama anında maliyetli `WITH RECURSIVE` sorguları gerektirir.

`ltree` eklentisi; hiyerarşik etiket yollarını (örn: `Elektronik.Bilgisayar.Dizustu`) özel bir veri tipi olarak saklar ve tek bir operatörle alt veya üst tüm dalları anında sorgular.

```sql
CREATE EXTENSION IF NOT EXISTS ltree;
```

### 3.1. Hiyerarşik Tablo Oluşturma ve Veri Ekleme

```sql
CREATE TABLE kategoriler (
    id SERIAL PRIMARY KEY,
    yol LTREE NOT NULL
);

INSERT INTO kategoriler (yol) VALUES 
('Elektronik'),
('Elektronik.Bilgisayar'),
('Elektronik.Bilgisayar.Dizustu'),
('Elektronik.Bilgisayar.Masaustu'),
('Elektronik.Telefon'),
('Elektronik.Telefon.AkilliTelefon'),
('Moda.Giyim.Erkek');

-- Ağaç sorgularını hızlandırmak için GiST indeksi:
CREATE INDEX idx_kategoriler_yol ON kategoriler USING gist (yol);
```

### 3.2. Ağaç Operatörleri ile Sorgulama

```sql
-- 1. 'Elektronik.Bilgisayar' dalının tüm alt kategorilerini getir (<@ alt dalı mı?)
SELECT yol FROM kategoriler WHERE yol <@ 'Elektronik.Bilgisayar';
-- Çıktı:
-- Elektronik.Bilgisayar
-- Elektronik.Bilgisayar.Dizustu
-- Elektronik.Bilgisayar.Masaustu

-- 2. 'Dizustu' kategorisinin tüm üst atalarını getir (@> ata dalı mı?)
SELECT yol FROM kategoriler WHERE yol @> 'Elektronik.Bilgisayar.Dizustu';
-- Çıktı:
-- Elektronik
-- Elektronik.Bilgisayar
-- Elektronik.Bilgisayar.Dizustu

-- 3. Düzenli İfade (lquery) ile arama: Elektronik altındaki 2. seviye tüm dallar
SELECT yol FROM kategoriler WHERE yol ~ 'Elektronik.*{1}';
-- Çıktı:
-- Elektronik.Bilgisayar
-- Elektronik.Telefon
```

> [!TIP]
> `ltree`, PostgreSQL içerisinde karmaşık ağaç dolaşma işlemlerini standart bir B-Tree/GiST indeksi hızına indirerek grafik (Graph) veritabanlarına olan ihtiyacı ortadan kaldırır.
