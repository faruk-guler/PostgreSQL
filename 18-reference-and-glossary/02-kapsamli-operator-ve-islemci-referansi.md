# Kapsamlı PostgreSQL Operatör ve İşlemci Referansı

PostgreSQL, zengin genişletilebilir tür sistemi sayesinde SQL standartlarının çok ötesinde geniş bir operatör kütüphanesine sahiptir. Bu başvuru kılavuzunda; mantıksal, karşılaştırma, matematiksel, bit düzeyinde (bitwise), metinsel/düzenli ifade, ağ adresleri, diziler, aralıklar (range) ve JSON/JSONB veri tipleri için kullanılan tüm operatörler tablolar ve pratik SQL örnekleriyle listelenmiştir.

---

## 1. Mantıksal Operatörler ve Üç Değerli Mantık (Three-Valued Logic)

PostgreSQL mantıksal operatörleri `AND`, `OR` ve `NOT` ifadeleridir. PostgreSQL `NULL` değerini "Bilinmeyen" (`UNKNOWN`) olarak değerlendirir.

### 1.1. Doğruluk Tablosu

| `a` | `b` | `a AND b` | `a OR b` | `NOT a` |
| :--- | :--- | :--- | :--- | :--- |
| **TRUE** | **TRUE** | TRUE | TRUE | FALSE |
| **TRUE** | **FALSE**| FALSE | TRUE | FALSE |
| **TRUE** | **NULL** | NULL | TRUE | FALSE |
| **FALSE**| **FALSE**| FALSE | FALSE | TRUE |
| **FALSE**| **NULL** | FALSE | NULL | TRUE |
| **NULL** | **NULL** | NULL | NULL | NULL |

---

## 2. Karşılaştırma Operatörleri ve İfadeleri

| İfade / Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `=`, `<>` veya `!=` | Eşit / Eşit Değil | `5 <> 3` | `true` |
| `<`, `<=`, `>`, `>=` | Küçüktür, Büyüktür | `10 >= 10` | `true` |
| `a BETWEEN x AND y` | Aralıkta mı (x <= a <= y) | `4 BETWEEN 1 AND 5` | `true` |
| `a BETWEEN SYMMETRIC x AND y` | Sıralama bağımsız aralıkta mı | `4 BETWEEN SYMMETRIC 5 AND 1` | `true` |
| `a IS DISTINCT FROM b` | `a` ve `b` farklı mı (NULL duyarlı) | `NULL IS DISTINCT FROM NULL` | `false` |
| `a IS NOT DISTINCT FROM b`| `a` ve `b` aynı mı (NULL duyarlı) | `NULL IS NOT DISTINCT FROM NULL` | `true` |
| `expr IS NULL` / `IS NOT NULL`| Değerin NULL olup olmadığını sınar | `NULL IS NULL` | `true` |
| `num_nulls(a, b, ...)` | Kaç adet NULL olduğunu sayar | `num_nulls(1, NULL, NULL, 4)` | `2` |
| `num_nonnulls(a, b, ...)` | Kaç adet NULL olmayan değer olduğunu sayar | `num_nonnulls(1, NULL, 3)` | `2` |

---

## 3. Matematiksel ve Bit Düzeyinde (Bitwise) Operatörler

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `+`, `-`, `*`, `/` | Toplama, Çıkarma, Çarpma, Bölme | `15 / 4` | `3` (Tamsayı) |
| `%` | Mod Alma (Kalan) | `17 % 5` | `2` |
| `^` | Üs Alma | `2.0 ^ 3.0` | `8.0` |
| `\|/` | Karekök | `\|/ 25.0` | `5` |
| `\|\|/` | Küpkök | `\|\|/ 27.0` | `3` |
| `!` veya `!!` | Faktöriyel | `5 !` | `120` |
| `@` | Mutlak Değer | `@ -15` | `15` |
| `&` | Bitwise AND | `B'10001' & B'01101'` | `00001` |
| `\|` | Bitwise OR | `B'10001' \| B'01101'` | `11101` |
| `#` | Bitwise XOR | `B'10001' # B'01101'` | `11100` |
| `~` | Bitwise NOT | `~ B'10001'` | `01110` |
| `<<`, `>>` | Bitwise Sola / Sağa Kaydırma | `B'10001' << 2` | `00100` |

---

## 4. Metin ve Düzenli İfade (POSIX Regex) Operatörleri

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `\|\|` | Metin Birleştirme (Concatenation) | `'Postgre' \|\| 'SQL'` | `'PostgreSQL'` |
| `LIKE` / `ILIKE` | Joker Eşleme (`%` çoklu, `_` tek karakter) | `'Ahmet' ILIKE 'ah%'` | `true` |
| `SIMILAR TO` | SQL Standardı Regex Eşleme | `'abc' SIMILAR TO '%(b\|d)%'` | `true` |
| `~` | POSIX Regex Eşleşmesi (Büyük/Küçük Duyarlı) | `'PostgreSQL' ~ '.*[0-9]+'` | `false` |
| `~*` | POSIX Regex Eşleşmesi (Harf Duyarsız) | `'Ahmet' ~* '^a.*t$'` | `true` |
| `!~` | Regex Eşleşmeme (Büyük/Küçük Duyarlı) | `'123' !~ '^[0-9]+$'` | `false` |
| `!~*` | Regex Eşleşmeme (Harf Duyarsız) | `'abc' !~* '[a-z]'` | `false` |

---

## 5. JSON ve JSONB Operatörleri

| Operatör | Dönen Tür | Tanım | Örnek |
| :--- | :--- | :--- | :--- |
| `->` | `json / jsonb` | Anahtar veya indeks ile eleman çeker | `'{"a": {"b":"foo"}}'::jsonb -> 'a'` |
| `->>` | `text` | Değeri doğrudan metin olarak çeker | `'{"a": 123}'::jsonb ->> 'a'` |
| `#>` | `json / jsonb` | Yol dizisi ile iç içe nesne çeker | `'{"a": {"b": ["c", "d"]}}'::jsonb #> '{a,b,1}'` |
| `#>>` | `text` | Yol dizisindeki değeri metin olarak çeker | `'{"a": {"b": ["c", "d"]}}'::jsonb #>> '{a,b,1}'` |
| `@>` | `boolean` | Sol taraf sağ tarafı içeriyor mu? (Contains) | `'{"a":1, "b":2}'::jsonb @> '{"b":2}'` |
| `<@` | `boolean` | Sol taraf sağ tarafın içinde mi? (Contained) | `'{"b":2}'::jsonb <@ '{"a":1, "b":2}'` |
| `?` | `boolean` | Belirtilen anahtar mevcut mu? | `'{"a":1, "b":2}'::jsonb ? 'b'` |
| `?\|` | `boolean` | Dizideki anahtarlardan HERHANGİ BİRİ var mı?| `'{"a":1}'::jsonb ?\| array['a', 'z']` |
| `?&` | `boolean` | Dizideki anahtarların TAMAMI var mı? | `'{"a":1, "b":2}'::jsonb ?& array['a', 'b']` |
| `-` | `jsonb` | Anahtarı veya indeksi JSON'dan siler | `'{"a":1, "b":2}'::jsonb - 'a'` |
| `#-` | `jsonb` | Belirtilen yoldaki alanı siler | `'{"a": {"b": 1}}'::jsonb #- '{a,b}'` |

---

## 6. Dizi (Array) Operatörleri

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `@>` | Diziyi içeriyor mu? | `ARRAY[1,2,3,4] @> ARRAY[2,3]` | `true` |
| `<@` | Dizinin içinde mi? | `ARRAY[2,3] <@ ARRAY[1,2,3,4]` | `true` |
| `&&` | Kesişim var mı? (Overlaps) | `ARRAY[1,2] && ARRAY[2,3]` | `true` |
| `\|\|` | Dizi birleştirme / eleman ekleme | `ARRAY[1,2] \|\| ARRAY[3,4]` | `{1,2,3,4}` |

---

## 7. Aralık (Range) Operatörleri

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `@>` | Aralığı veya elemanı içeriyor mu? | `int4range(10, 20) @> 15` | `true` |
| `<@` | Aralığın içinde mi? | `15 <@ int4range(10, 20)` | `true` |
| `&&` | Aralıklar çakışıyor mu? (Overlap) | `int4range(1, 10) && int4range(8, 15)` | `true` |
| `<<` | Tamamen solunda mı? (Strictly left) | `int4range(1, 5) << int4range(6, 10)` | `true` |
| `>>` | Tamamen sağında mı? (Strictly right) | `int4range(10, 15) >> int4range(1, 5)` | `true` |
| `-|-`| Bitişik mi? (Adjacent) | `int4range(1, 5) -\|- int4range(5, 10)` | `true` |
| `+` | İki aralığı birleştirir (Union) | `int4range(1, 5) + int4range(5, 10)` | `[1,10)` |
| `*` | İki aralığın kesişimi (Intersection) | `int4range(1, 10) * int4range(5, 15)` | `[5,10)` |

---

## 8. Ağ Adresi (inet / cidr) Operatörleri

| Operatör | Tanım | Örnek | Sonuç |
| :--- | :--- | :--- | :--- |
| `<<` | Alt ağı mı? (Strictly contained) | `inet '192.168.1.5' << inet '192.168.1.0/24'` | `true` |
| `<<=` | Alt ağı veya eşit mi? | `inet '192.168.1.0/24' <<= inet '192.168.1.0/24'` | `true` |
| `>>` | Üst ağı mı? (Strictly contains) | `inet '192.168.0.0/16' >> inet '192.168.1.0/24'` | `true` |
| `&&` | Ağlar kesişiyor mu? | `inet '192.168.1.0/24' && inet '192.168.0.0/16'` | `true` |
| `~` | Bitwise NOT (Tersleme) | `~ inet '192.168.1.1'` | `63.87.254.254` |
| `+`, `-` | IP adresine ekleme / çıkarma | `inet '192.168.1.1' + 5` | `192.168.1.6` |
