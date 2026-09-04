# Kapsamlı Veri Tipleri Referans Fihristi

> **Bölüm Kapsamı:** PostgreSQL Yerleşik ve Sistem Veri Tipleri Kataloğu (`\dTS`), Yerleşik Operatörler ve Fonksiyon Kataloğu

---

PostgreSQL, SQL standartlarının sunduğu temel veri tiplerinin çok ötesinde, dünyadaki en geniş yerleşik tip kataloğuna sahiptir. Bu bölümde `\dTS` sistem kataloğunda yer alan tipler mantıksal kategorilere ayrılarak Türkçe açıklamaları, depolama boyutları ve kullanım alanlarıyla sunulmuştur.

---

## 1. Sayısal Tipler (Numeric Types)

| Tip Adı | Depolama | Açıklama ve Aralık |
| :--- | :--- | :--- |
| **smallint** (`int2`) | 2 bayt | Küçük aralıklı tam sayı (-32,768 ile +32,767) |
| **integer** (`int4`, `int`) | 4 bayt | Genel amaçlı standart tam sayı (-2,147,483,648 ile +2,147,483,647) |
| **bigint** (`int8`) | 8 bayt | Çok büyük tam sayılar (~9 kentilyon aralığında) |
| **numeric** / **decimal** | Değişken | Tam hassasiyetli sayı (arbitrary precision); para ve finansal hesaplar için |
| **real** (`float4`) | 4 bayt | Tek hassasiyetli kayan noktalı sayı (6 ondalık basamak hassasiyeti) |
| **double precision** (`float8`)| 8 bayt | Çift hassasiyetli kayan noktalı sayı (15 ondalık basamak hassasiyeti) |
| **smallserial** / **serial** / **bigserial** | 2/4/8 bayt | Otomatik artan tam sayılar (arka planda Sequence nesnesi oluşturur) |
| **money** | 8 bayt | Para birimi miktarı ($ veya yerel para simgeli, 2 ondalıklı) |

---

## 2. Metin ve Karakter Tipleri (Character Types)

| Tip Adı | Depolama | Açıklama |
| :--- | :--- | :--- |
| **character(n)** (`char(n)`) | Sabit `n` | Belirtilen uzunluğa kadar boşlukla doldurulan (blank-padded) metin |
| **character varying(n)** (`varchar(n)`) | Değişken (en çok `n`) | Üst sınırı belirtilmiş değişken uzunluklu metin |
| **text** | Değişken | Sınırsız uzunlukta metin dizgisi (maksimum 1 GB) |
| **"char"** | 1 bayt | Tek bir karakter tutan dahili sistem tipi (tırnaklı yazılır) |
| **name** | 64 bayt (63 efektif) | Sistem nesnesi tanımlayıcılarını (tablo, kolon adı) saklayan dahili tip |
| **cstring** | Değişken | C tarzı null-terminated metin dizgisi (C eklentileri için dahili) |

---

## 3. Tarih ve Zaman Tipleri (Date & Time)

| Tip Adı | Depolama | Format ve Açıklama |
| :--- | :--- | :--- |
| **date** | 4 bayt | Sadece takvim tarihi (Yıl, Ay, Gün: `4713 BC` - `5874897 AD`) |
| **time without time zone** | 8 bayt | Günün saati (zaman dilimsiz: `00:00:00` - `24:00:00`) |
| **time with time zone** (`timetz`) | 12 bayt | Zaman dilimi bilgisi içeren günün saati |
| **timestamp without time zone** | 8 bayt | Tarih ve saat birlikte (zaman dilimi olmadan saklanır) |
| **timestamp with time zone** (`timestamptz`) | 8 bayt | UTC olarak saklanan, istemcinin zaman dilimine göre gösterilen anlık zaman |
| **interval** | 16 bayt | Zaman aralığı (`1 year 2 months 3 days 4 hours`) |

---

## 4. Mantıksal ve İkili Tipler (Boolean & Binary)

| Tip Adı | Depolama | Açıklama |
| :--- | :--- | :--- |
| **boolean** (`bool`) | 1 bayt | Mantıksal değer: `TRUE`, `FALSE`, `NULL` (üç değerli mantık) |
| **bytea** | Değişken | Ham ikili veri (resim, ses, şifreli veri blokları) |
| **bit(n)** | `n` bit | Sabit uzunluklu bit dizgisi (`B'10101'`) |
| **bit varying(n)** (`varbit(n)`)| Değişken | Değişken uzunluklu bit dizgisi |

---

## 5. Yapılandırılmış ve Doküman Tipleri (JSON & XML)

| Tip Adı | Depolama | Açıklama |
| :--- | :--- | :--- |
| **json** | Metin olarak | Metin formatında JSON doğrulaması yapan tip (orijinal boşlukları korur) |
| **jsonb** | İkili (Binary) | Ayrıştırılmış, sıkıştırılmış ve indekslenebilir ikili JSON formatı |
| **jsonpath** | Değişken | SQL/JSON path sorgulama dili ifadelerini saklayan tip |
| **xml** | Metin olarak | XML standartlarına uygun doküman içeriği ve XPath desteği |

---

## 6. Ağ ve Donanım Adresi Tipleri (Network Types)

| Tip Adı | Depolama | Açıklama |
| :--- | :--- | :--- |
| **inet** | 7 veya 19 bayt | IPv4 veya IPv6 ana bilgisayar adresi ve isteğe bağlı alt ağ maskesi |
| **cidr** | 7 veya 19 bayt | IPv4 veya IPv6 ağ adresi / yönlendirme bloğu |
| **macaddr** | 6 bayt | Standart Ethernet donanım adresi (`08:00:2b:01:02:03`) |
| **macaddr8** | 8 bayt | EUI-64 formatındaki genişletilmiş donanım adresi |

---

## 7. Geometrik Tipler (Geometric Types)

| Tip Adı | Depolama | Format / Temsil |
| :--- | :--- | :--- |
| **point** | 16 bayt | İki boyutlu düzlemde nokta: `(x, y)` |
| **line** | 32 bayt | Sonsuz doğru denklemi: `{A, B, C}` (`Ax + By + C = 0`) |
| **lseg** | 32 bayt | İki nokta arasındaki doğru parçası: `((x1, y1), (x2, y2))` |
| **box** | 32 bayt | Eksenlere paralel dikdörtgen kutu: `((x1, y1), (x2, y2))` |
| **path** | Değişken | Açık veya kapalı çokgen yol: `[(x1, y1), ...]` |
| **polygon** | Değişken | Kapalı çokgen alanı: `((x1, y1), ...)` |
| **circle** | 24 bayt | Daire: `<(x, y), r>` (merkez ve yarıçap) |

---

## 8. Aralık ve Çoklu-Aralık Tipleri (Range & Multirange)

| Range Tipi | Multirange Tipi (PG 14+) | Temel Veri Türü |
| :--- | :--- | :--- |
| **int4range** | **int4multirange** | `integer` aralıkları (`[1, 10)`) |
| **int8range** | **int8multirange** | `bigint` aralıkları |
| **numrange** | **nummultirange** | `numeric` aralıkları |
| **tsrange** | **tsmultirange** | `timestamp without time zone` aralıkları |
| **tstzrange** | **tstzmultirange** | `timestamp with time zone` aralıkları |
| **daterange** | **datemultirange** | `date` aralıkları (rezervasyon sistemleri için) |

---

## 9. Kimlik ve Sistem Tanımlayıcıları (Identifiers)

| Tip Adı | Depolama | Açıklama |
| :--- | :--- | :--- |
| **uuid** | 16 bayt | Evrensel benzersiz tanımlayıcı (RFC 4122) |
| **oid** | 4 bayt | PostgreSQL sistem nesnesi tanımlayıcısı (Object Identifier) |
| **cid** | 4 bayt | Transaction içindeki komut sıra tanımlayıcısı (Command Identifier) |
| **xid** / **xid8** | 4 / 8 bayt | 32-bit klasik ve 64-bit tam Transaction kimliği |
| **tid** | 6 bayt | Bir satırın diski üzerindeki fiziksel koordinatı `(block, offset)` |
| **pg_lsn** | 8 bayt | WAL içindeki Log Sequence Number konumu (`16/B374D848`) |
| **pg_snapshot** / **txid_snapshot** | Değişken | MVCC aktif transaction görünüm penceresi (snapshot) |

---

## 10. Tam Metin Arama Tipleri (Full Text Search)

| Tip Adı | Açıklama |
| :--- | :--- |
| **tsvector** | Metin arama için ayıklanmış, köklerine indirgenmiş ve sıralanmış terim listesi |
| **tsquery** | Arama operatörlerini (`&`, `\|`, `!`, `<->`) içeren arama sorgusu nesnesi |
| **gtsvector** | GiST indeksleri tarafından kullanılan dahili metin vektörü temsili |

---

## 11. Kayıtlı Nesne Tipleri (Reg* Types)

PostgreSQL, sistem kataloglarındaki OID değerlerini otomatik olarak insan tarafından okunabilir nesne adlarına eşleyen özel tipler sunar:

| Tip Adı | Eşleştiği Nesne | Örnek |
| :--- | :--- | :--- |
| **regclass** | Tablo, View, İndeks, Sequence | `'users'::regclass` -> OID |
| **regtype** | Veri tipi | `'integer'::regtype` |
| **regproc** / **regprocedure** | Fonksiyon / Prosedür (argümanlı) | `'now'::regproc` |
| **regoper** / **regoperator** | Operatör | `'+(int4,int4)'::regoperator` |
| **regrole** | Kullanıcı veya Rol | `'postgres'::regrole` |
| **regnamespace** | Şema (Namespace) | `'public'::regnamespace` |
| **regconfig** | Metin Arama Konfigürasyonu | `'turkish'::regconfig` |
| **regdictionary** | Metin Arama Sözlüğü | `'simple'::regdictionary` |
| **regcollation** | Sıralama kuralı (Collation) | `'tr-TR-x-icu'::regcollation` |

---

## 12. Dahili ve Psödo Tipler (Pseudo-Types)

Bu tipler bir tablonun sütun tipi olarak kullanılamaz; fonksiyon parametreleri ve dönüş değerlerinde dinamik veya sistem düzeyinde kullanılır:

| Tip Adı | Açıklama |
| :--- | :--- |
| **record** | Önceden tanımlanmamış herhangi bir bileşik (composite) satır yapısı |
| **anyelement** / **anyarray** | Polimorfik temel tip ve buna karşılık gelen dizi tipi |
| **anycompatible** | Birbiriyle uyumlu ortak bir türe dönüştürülebilen polimorfik tip ailesi |
| **anyrange** / **anymultirange** | Herhangi bir aralık türünü kabul eden polimorfik tip |
| **void** | Bir değer döndürmeyen fonksiyonların dönüş tipi |
| **trigger** / **event_trigger** | DML veya DDL tetikleyici fonksiyonlarının dönüş tipi |
| **refcursor** | Sorgu imleci (cursor) referansı tutan tip |
| **internal** | PostgreSQL iç C fonksiyonları arasında veri aktaran opak yapı |
| **language_handler** | PL dillerini bağlayan çağrı işleyici tipi |
| **fdw_handler** | Foreign Data Wrapper eklentileri için işleyici fonksiyon dönüş tipi |
| **index_am_handler** | İndeks erişim metotları (B-Tree, GIN vb.) için işleyici tipi |
| **table_am_handler** | Tablo depolama erişim metotları (Heap, AFS vb.) için işleyici tipi |
| **aclitem** | Erişim kontrol listesi izin girişi (GRANT/REVOKE kayıtları) |

---

## 13. PostgreSQL Özel Operatör ve Fonksiyon Kataloğu

PostgreSQL, zengin tip ekosistemini destekleyen geniş bir yerleşik operatör ve fonksiyon kütüphanesine sahiptir. Sistemdeki tüm operatörleri `\do`, fonksiyonları ise `\df` komutlarıyla psql üzerinden listeleyebilirsiniz.

### a. Gelişmiş Karşılaştırma ve Mantıksal Operatörler

| İfade / Operatör | Açıklama | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `a IS DISTINCT FROM b` | NULL duyarlı eşitsizlik kontrolü (biri NULL diğeri değerse TRUE döner; ikisi de NULL ise FALSE döner) | `NULL IS DISTINCT FROM 1` | `true` |
| `a IS NOT DISTINCT FROM b` | NULL duyarlı eşitlik kontrolü (ikisi de NULL ise TRUE döner) | `NULL IS NOT DISTINCT FROM NULL` | `true` |
| `a BETWEEN SYMMETRIC x AND y` | Sınır değerlerinin sırasına bakılmaksızın (`min(x,y)` ve `max(x,y)`) aralık kontrolü | `5 BETWEEN SYMMETRIC 10 AND 1` | `true` |
| `num_nonnulls(...)` | Argümanlar arasındaki NULL olmayan değerlerin sayısını döner | `num_nonnulls(1, NULL, 'a', NULL)` | `2` |
| `num_nulls(...)` | Argümanlar arasındaki NULL değerlerin sayısını döner | `num_nulls(1, NULL, 'a', NULL)` | `2` |

### b. Matematiksel ve Bit Düzeyinde (Bitwise) Operatörler

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `\|/` | Karekök operatörü | `\|/ 25` | `5` |
| `\|\|/` | Küpkök operatörü | `\|\|/ 27` | `3` |
| `@` | Mutlak değer operatörü | `@ -15` | `15` |
| `&` | Bitwise AND (ve) | `B'1010' & B'1100'` | `B'1000'` |
| `\|` | Bitwise OR (veya) | `B'1010' \| B'1100'` | `B'1110'` |
| `#` | Bitwise XOR (özel veya) | `B'1010' # B'1100'` | `B'0110'` |
| `~` | Bitwise NOT (değil) | `~ B'1010'` | `B'0101'` |
| `<<` / `>>` | Bitwise sola / sağa kaydırma | `B'0001' << 2` | `B'0100'` |

> [!NOTE]
> **Modernizasyon Notu:** Eski PostgreSQL sürümlerinde faktöriyel için kullanılan önek/sonek `!` ve `!!` operatörleri PostgreSQL 14 ile birlikte kullanımdan kaldırılmıştır (deprecated). Güncel PostgreSQL sürümlerinde doğrudan `factorial(n)` fonksiyonu kullanılmalıdır.

### c. Metinsel Arama ve Regex Desen Eşleştirme Operatörleri

PostgreSQL, SQL standardındaki `LIKE` operatörünün yanında gelişmiş POSIX uyumlu düzenli ifadeleri (Regular Expressions) destekler:

| Operatör | Açıklama | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `ILIKE` | Büyük/küçük harf duyarsız `LIKE` (PostgreSQL'e özgü) | `'PostgreSQL' ILIKE 'post%'` | `true` |
| `SIMILAR TO` | SQL99 standardı ve regex karması desen eşleme | `'abc' SIMILAR TO '%(b\|d)%'` | `true` |
| `~` | POSIX Regex ile eşleşme (Büyük/küçük harf duyarlı) | `'Faruk Guler' ~ '[Ff]aruk'` | `true` |
| `~*` | POSIX Regex ile eşleşme (Büyük/küçük harf DUYARSIZ) | `'PostgreSQL' ~* '^post'` | `true` |
| `!~` | POSIX Regex ile EŞLEŞMEME (Büyük/küçük harf duyarlı) | `'admin' !~ '[0-9]'` | `true` |
| `!~*` | POSIX Regex ile EŞLEŞMEME (Büyük/küçük harf DUYARSIZ) | `'root' !~* '^A'` | `true` |

### d. İkili Veri (`bytea`) Fonksiyonları

Ham ikili verileri (hash, kriptografik anahtarlar, dosya blokları) işlemek için yerleşik fonksiyonlar:

- `encode(bytea_data, 'hex' | 'base64')`: İkili veriyi metin tabanlı formata çevirir.
- `decode('string', 'hex' | 'base64')`: Hex veya Base64 metni ham `bytea` formatına dönüştürür.
- `sha256(bytea)` / `sha512(bytea)`: Kriptografik özet hesaplar.
- `get_byte(bytea, offset)` ve `set_byte(bytea, offset, new_value)`: İkili dizi üzerindeki belirli baytı okur veya değiştirir.

