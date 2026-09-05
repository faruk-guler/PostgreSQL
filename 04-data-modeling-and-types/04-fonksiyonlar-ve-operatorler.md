# Temel Fonksiyonlar ve Operatörler

PostgreSQL, SQL standartlarındaki temel operatörlerin (Toplama, Çıkarma, Mantıksal VE/VEYA) çok ötesine geçerek metin işleme, desen eşleştirme, tarih manipülasyonu ve regex konusunda son derece geniş bir dahili kütüphane sunar.

Kullanılabilir tüm fonksiyonları ve operatörleri `psql` ekranında `\df` (Display Functions) ve `\do` (Display Operators) komutlarıyla listeleyebilirsiniz.

---

## 1. Desen Eşleştirme (Pattern Matching)

Bir metnin (String) içinde belirli bir kalıbı veya kelimeyi aramak için kullanılır. Performans (İndeks kullanımı) açısından kalıbın nasıl yazıldığı çok önemlidir.

### `LIKE` ve `ILIKE` (Klasik Arama)
*   **`LIKE`**: Büyük-küçük harf duyarlıdır (Case-sensitive). Sadece aradığınız kelime tam olarak eşleşirse sonuç döner.
*   **`ILIKE`**: Büyük-küçük harfe duyarsızdır (Case-insensitive). Sadece PostgreSQL'e özgüdür.
*   **`%` (Yüzde)**: Herhangi bir sayıda (0 veya daha fazla) karakterin yerini tutar.
*   **`_` (Alt çizgi)**: Sadece tek bir karakterin yerini tutar.

```sql
SELECT * FROM urunler WHERE ad LIKE 'MacBook%';  -- 'MacBook' ile başlayanlar (İndeks kullanabilir)
SELECT * FROM urunler WHERE ad ILIKE '%macbook%'; -- İçinde 'macbook' geçenler (Genelde Full Table Scan yapar)
SELECT * FROM urunler WHERE ad LIKE 'a_c';        -- 'abc', 'adc' gibi 3 harfli olanlar
```

### `SIMILAR TO` ve POSIX Regex (Düzenli İfadeler)
Çok daha karmaşık kuralları aramak için Regex gücünü kullanabilirsiniz.

| Operatör | Anlamı | Örnek |
| :--- | :--- | :--- |
| `~` | Büyük-küçük harf duyarlı Regex eşleşmesi (Matches) | `'thomas' ~ '.*thomas.*'` (true) |
| `~*` | Büyük-küçük harf duyarsız Regex eşleşmesi | `'thomas' ~* '.*Thomas.*'` (true) |
| `!~` | Regex Eşleşmemesi (Does not match) | `'thomas' !~ '.*Thomas.*'` (true) |

---

## 2. Metinsel (String) Fonksiyonlar

Metinleri birleştirmek, kırpmak, içinden parça almak veya dönüşüm yapmak için kullanılır.

*   **`||` (Bitiştirme - Concatenation):** İki metni (veya metin + sayıyı) yan yana birleştirir.
    ```sql
    SELECT 'Postgre' || 'SQL'; -- Sonuç: 'PostgreSQL'
    ```
*   **`char_length(string)`:** Metnin içindeki karakter sayısını döner.
*   **`lower(string)` / `upper(string)`:** Metni tamamen küçük harfe veya tamamen büyük harfe çevirir.
*   **`trim([characters] from string)`:** Metnin başındaki ve sonundaki istenmeyen karakterleri (genelde boşluk) temizler.
*   **`substring(string from int for int)`:** Metnin içinden, belirli bir sıradan başlayarak belirli bir uzunlukta parça alır.

---

## 3. Tarih ve Zaman Fonksiyonları

PostgreSQL tarih hesaplamaları konusunda çok yeteneklidir. Tarihler birbirleriyle veya `INTERVAL` (zaman aralığı) tipleriyle işleme sokulabilir.

### Zaman Hesaplamaları (Dört İşlem)
```sql
-- Tarihe gün ekleme
SELECT date '2023-10-01' + integer '7'; -- Sonuç: 2023-10-08

-- Tarihe saat/dakika ekleme
SELECT timestamp '2023-10-01 10:00' + interval '2 hours 30 minutes'; -- Sonuç: 2023-10-01 12:30:00

-- İki tarih arasındaki farkı bulma (Gün cinsinden döner)
SELECT date '2023-10-15' - date '2023-10-01'; -- Sonuç: 14
```

### Zaman Formatlama ve Ayıklama
*   **`now()` veya `current_timestamp`**: Sistemin şu anki zamanını (Transaction başlangıcını) getirir.
*   **`age(timestamp, timestamp)`**: İki tarih arasındaki farkı insan dilinde ("2 years 3 mons 14 days") verir. Doğum günü hesaplamaları için birebirdir.
*   **`extract(field FROM timestamp)` / `date_part()`**: Tarihin içinden sadece yılı, ayı veya günü koparıp tam sayı olarak verir.
    ```sql
    SELECT extract(year FROM now()); -- Sonuç: 2023
    ```
*   **`to_char(timestamp, text)`**: Tarihi istenen formatta (Örn: GG/AA/YYYY) metne çevirir.
    ```sql
    SELECT to_char(now(), 'DD/MM/YYYY HH24:MI'); -- Sonuç: 15/10/2023 14:30
    ```

---

## 4. Karşılaştırma ve Mantıksal Operatörler

*   **Temel Operatörler:** `=`, `<>`, `<`, `>`, `<=`, `>=`
*   **Aralık Kontrolü:** `BETWEEN x AND y` (x ve y dahildir).
*   **Benzersizlik (Distinct):** `IS DISTINCT FROM`. Bu operatör NULL değerlerin birbiriyle kıyaslanmasında standart `=` operatörünün yaşadığı mantıksal çökmeleri (NULL = NULL -> NULL'dur, true değildir) engeller ve NULL'ları güvenli kıyaslar.
*   **Boşluk Kontrolü:** `IS NULL` ve `IS NOT NULL`.
*   **Mantıksal Bağlaçlar:** `AND`, `OR`, `NOT`. (Öncelik sırası: `NOT` -> `AND` -> `OR`).
