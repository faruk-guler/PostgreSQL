# JSON/JSONB ve NoSQL Özellikleri

PostgreSQL sadece ilişkisel bir veritabanı (RDBMS) değildir; aynı zamanda çok güçlü bir belge (Document / NoSQL) veritabanı olarak da çalışır. Modern uygulama geliştirmede, şeması belirsiz (Schema-less) veya sürekli değişen verileri (Örn: Kullanıcı ayarları, API yanıtları, ürün özellikleri) saklamak için JSON çok sık kullanılır.

---

## 1. JSON vs JSONB

PostgreSQL, JSON verileri saklamak için iki veri tipine sahiptir:
*   **`json`**: Veriyi gönderdiğiniz **metin (Text) formatında** aynen saklar. Boşluklar ve satır sonları (Indentation) korunur. Veri ekleme (Insert) çok az daha hızlıdır ancak sorgulama yaparken (Read) verinin her seferinde yeniden parse edilmesi gerekir. İndeksleme yeteneği yoktur.
*   **`jsonb` (Önerilen)**: Veriyi ayrıştırıp **Binary formatta** kaydeder. Gereksiz boşlukları (Whitespace) atar, anahtarları sıralar. GIN (Generalized Inverted Index) ile indekslenebilir. Milyonlarca satırlık JSON verisinin içindeki bir anahtarı milisaniyeler içinde bulmanızı sağlar. **Uygulamalarınızda her zaman `jsonb` kullanın.**

---

## 2. JSON Operatörleri

| Operatör | Ne İşe Yarar? | Örnek (Sonuç) |
| :--- | :--- | :--- |
| `->` | Objeden anahtarı (key) bulur ve JSON formatında döndürür. | `'{"a": {"b":"foo"}}'::jsonb -> 'a'` (Sonuç: `{"b":"foo"}`) |
| `->>` | Objeden anahtarı bulur ve **METİN (TEXT)** formatında döndürür. En çok kullanılan operatördür. | `'{"isim": "Ahmet"}'::jsonb ->> 'isim'` (Sonuç: `'Ahmet'`) |
| `#>` | İçiçe geçmiş (Nested) JSON'da yola (Path) göre JSON objesi bulur. | `'{"a": {"b": {"c":"foo"}}}'::jsonb #> '{a,b}'` (Sonuç: `{"c":"foo"}`) |
| `#>>`| Yola (Path) göre metin bulur. | `'{"kisi": {"yas": 30}}'::jsonb #>> '{kisi, yas}'` (Sonuç: `'30'`) |

---

## 3. Gelişmiş JSONB Operatörleri (Arama ve Güncelleme)

JSONB verilerini sorgulamak, MongoDB gibi veritabanlarına çok benzer.

*   **`@>` (Kapsıyor mu? - Contains):** En çok kullanılan arama operatörüdür. İndeks kullanabildiği için çok hızlıdır.
    ```sql
    -- "kullanici_ayarlari" kolonunda { "tema": "karanlik" } ayarı olanları getir
    SELECT * FROM kullanicilar 
    WHERE kullanici_ayarlari @> '{"tema": "karanlik"}'::jsonb;
    ```
*   **`?` (Anahtar Var Mı? - Has Key):** En üst düzeyde belirli bir anahtarın (Key) olup olmadığını kontrol eder.
    ```sql
    -- "kullanici_ayarlari" kolonunda "bildirimler" anahtarı var mı?
    SELECT * FROM kullanicilar 
    WHERE kullanici_ayarlari ? 'bildirimler';
    ```
*   **`||` (Birleştirme - Concatenation):** İki JSON objesini birleştirir veya günceller.
    ```sql
    -- Mevcut JSON verisine "dil" ayarını ekler (varsa ezer)
    UPDATE kullanicilar 
    SET kullanici_ayarlari = kullanici_ayarlari || '{"dil": "tr"}'::jsonb;
    ```
*   **`-` (Silme - Delete):** Belirtilen anahtarı siler.
    ```sql
    -- "tema" ayarını JSON objesinden uçurur
    UPDATE kullanicilar 
    SET kullanici_ayarlari = kullanici_ayarlari - 'tema';
    ```

---

## 4. JSON İndeksleme (GIN Index)

Eğer bir JSON kolonunun içinde sık sık arama (Örn: `@>` operatörüyle) yapıyorsanız, mutlaka GIN indeksi oluşturmalısınız. Yoksa veritabanı her sorguda Full Table Scan yapar.

```sql
-- GIN (Generalized Inverted Index) oluşturma
CREATE INDEX idx_kullanici_ayarlari ON kullanicilar USING GIN (kullanici_ayarlari);
```

### Path İndeksi (B-Tree)
Eğer JSON'un içindeki sadece **belirli bir değere** göre (Örn: `->> 'email'`) eşitlik araması yapıyorsanız, o yola özel klasik B-Tree indeksi de oluşturabilirsiniz (Daha az yer kaplar).

```sql
CREATE INDEX idx_kullanici_email ON kullanicilar ((kullanici_ayarlari ->> 'email'));
```
