# PostgreSQL Veri Tipleri ve Performans Optimizasyonu

Veritabanı tasarımında (Schema Design) doğru veri tipini seçmek, yalnızca veri bütünlüğü (Data Integrity) için değil, aynı zamanda disk alanı tüketimi, bellek (RAM) kullanımı ve indeks (Index) performansı açısından da kritik bir öneme sahiptir. 

PostgreSQL, SQL standartlarındaki temel tiplerin ötesinde, kompleks uygulamalar geliştirmeyi kolaylaştıran gelişmiş veri tipleri sunar.

---

## 1. Sayısal (Numeric) Veri Tipleri

| Veri Tipi | Boyut | Kullanım Senaryosu |
| :--- | :--- | :--- |
| `smallint` (int2) | 2 byte | Küçük tam sayılar (-32.768 ile +32.767). Performans ve yer tasarrufu için tercih edilmelidir (Örn: Durum kodları, yaş). |
| `integer` (int4) | 4 byte | Varsayılan tam sayı tipi (-2.147 Milyar ile +2.147 Milyar). Genellikle ID ve sayaçlar için kullanılır. |
| `bigint` (int8) | 8 byte | Çok büyük tam sayılar. Yüksek hacimli tablolarda Primary Key olarak kullanılması önerilir. |
| `decimal` / `numeric` | Değişken | **Kesin (Exact)** rasyonel sayılar. Özellikle finansal (Para) hesaplamalarda küsurat kaybı (rounding error) yaşamamak için zorunludur. Performansı integer'a göre daha yavaştır. |
| `real` / `double precision` | 4 / 8 byte | **Yaklaşık (Approximate)** ondalıklı sayılar. Bilimsel hesaplamalarda veya kesinliğin çok önemli olmadığı durumlarda hızı nedeniyle tercih edilir (Küsürat kaybı yaşanabilir). |
| `serial` / `bigserial` | 4 / 8 byte | Otomatik artan (Auto-increment) ID oluşturmak için kullanılır. Arka planda bir `SEQUENCE` nesnesi yaratır. (Modern PostgreSQL'de bunun yerine `GENERATED ALWAYS AS IDENTITY` kullanımı tavsiye edilir). |

> [!WARNING]
> Finansal verilerde **ASLA** `real` veya `float` (double precision) kullanmayın! `0.1 + 0.2 = 0.30000000000000004` gibi yuvarlama hatalarına neden olurlar. Parasal veriler için her zaman `numeric(precision, scale)` kullanın.

---

## 2. Metinsel (String) Veri Tipleri

| Veri Tipi | Açıklama | Performans Etkisi |
| :--- | :--- | :--- |
| `char(n)` | Sabit uzunluklu. Veri kısa girilse bile sonunu boşlukla doldurup diski israf eder. | **Kullanımı önerilmez.** Disk alanını israf ettiği için I/O maliyeti yüksektir. |
| `varchar(n)` | Değişken uzunluklu. Sadece girilen karakter kadar yer kaplar. | Maksimum uzunluk kısıtı (Limit) konması gereken yerlerde (`kullanici_adi varchar(50)`) tercih edilir. |
| `text` | Sınırsız değişken uzunluklu metin. Sadece girilen kadar yer kaplar. | PostgreSQL altyapısında `text` ve `varchar(n)` aynı motoru (varlena) kullanır. Performans farkı sıfırdır. |

> [!TIP]
> Diğer veritabanlarının (MySQL vb.) aksine PostgreSQL'de `text` ile `varchar(n)` arasında hız farkı **yoktur**. İkisi de arka planda aynı veri yapısını kullanır. Metin sınırını veritabanında zorlamak istemiyorsanız her yerde `text` kullanabilirsiniz.

---

## 3. Tarih ve Zaman (Date / Time)

Tarihsel hesaplamaların (Örn: Bu faturanın son ödeme tarihi geçti mi?) veri bütünlüğünü bozmadan yapılabilmesi için doğru tip şarttır.

*   **`date`**: Sadece tarihi tutar (Yıl-Ay-Gün).
*   **`timestamp`**: Tarih + Saat bilgisini tutar.
*   **`timestamp with time zone` (timestamptz)**: Tarih + Saat + **Zaman Dilimi (Timezone)** bilgisini tutar. Küresel (Global) uygulamalar geliştirirken kesinlikle `timestamptz` kullanmalısınız. Aksi takdirde, Amerika'dan bağlanan kullanıcı ile Türkiye'den bağlanan kullanıcı aynı saati farklı yorumlar.
*   **`interval`**: Bir zaman aralığını tutar (Örn: `3 days 14 hours`). Tarih toplama/çıkarma işlemlerinde çok güçlüdür (`current_date + interval '1 week'`).

---

## 4. Gelişmiş PostgreSQL Tipleri

### JSON ve JSONB (NoSQL Yetenekleri)
PostgreSQL'i hibrit bir veritabanı (RDBMS + NoSQL) yapan en güçlü özelliktir.

*   **`json`**: Veriyi tam olarak gönderdiğiniz formatta (boşluklar dahil) metin olarak (Text) kaydeder. Her sorguladığınızda verinin baştan ayrıştırılması (Parsing) gerekir (Yavaştır).
*   **`jsonb`**: Veriyi arka planda **Binary** formatta parse ederek kaydeder. Yazarken çok hafif yavaştır ama **okurken ve sorgularken (Index desteği - GIN) devasa bir performans farkı yaratır**. Boşlukları ve gereksiz detayları atar. Uygulamalarınızda her zaman `jsonb` kullanın.

### ENUM (Sıralı Tip)
Sadece önceden belirlenmiş sabit değerlerin girilmesini (Örn: Sipariş durumu -> `bekliyor`, `kargolandi`, `teslim_edildi`) veritabanı seviyesinde zorunlu kılar. Yanlış veri girilmesini engeller ve `text` yerine tam sayı sakladığı için diskten ve bellekten tasarruf sağlar.

### ARRAY (Diziler)
Bir kolonda birden fazla veri tutmanızı sağlar (Örn: `tagler text[]`). İlişkisel tasarıma (Normalization) aykırı görünse de, ayrı bir tablo oluşturmanın (JOIN maliyeti) gereksiz olduğu basit çoklu değerlerde çok etkilidir.

### OID, UUID ve Network Tipleri
*   **UUID:** Evrensel benzersiz kimlik (GUID). Dağıtık mimarilerde ID çakışmasını engellemek için mükemmeldir.
*   **inet / cidr:** IP adreslerini ve ağ maskelerini saklamak için düz metin (`varchar`) yerine bunlar kullanılmalıdır. Hatalı IP girişini engeller ve "Bu IP, şu blokun içinde mi?" (Subnetting) sorgularını donanımsal hızda yapar.
