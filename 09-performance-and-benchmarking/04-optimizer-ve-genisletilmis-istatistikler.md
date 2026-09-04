# PostgreSQL Optimizer İstatistikleri ve Sorgu Planlayıcı Mühendisliği (Optimizer & Extended Statistics)

PostgreSQL sorgu planlayıcısı maliyet tabanlıdır (Cost-Based Optimizer - CBO). Bir sorgu çalıştırıldığında planlayıcı, tablolardaki verilerin disk üzerindeki dağılımını, tekillik oranlarını ve korelasyonlarını bilmeden doğru bir yürütme planı (Execution Plan) seçemez. Eğer istatistikler eksik veya yanıltıcıysa, planlayıcı 10 satır beklediği bir sorguda 10 milyon satırla karşılaşır; hızlı bir `Index Scan` yerine felaketle sonuçlanan bir `Nested Loop` veya geçici diske taşan (spill to disk) bir `Hash Join` seçer.

Bu bölümde; `pg_statistic` / `pg_stats` iç yapısı, çok sütunlu korelasyon tuzakları, Genişletilmiş İstatistikler (**Extended Statistics**) ve planlayıcıyı kontrol altına alma teknikleri incelenmektedir.

---

## 1. İstatistik Motorunun Kalbi: `pg_stats` Anatomisi

PostgreSQL, `ANALYZE` komutu çalıştığında her tablodan istatistiksel bir örneklem (`default_statistics_target` kadar kova) toplar ve bunu `pg_statistic` kataloğuna yazar. Bu veriler `pg_stats` görünümü üzerinden incelenir:

```sql
SELECT 
    attname AS sutun_adi,
    null_frac AS null_orani,
    avg_width AS ortalama_bayt,
    n_distinct AS tekil_deger_tahmini,
    correlation AS disk_korelasyonu
FROM pg_stats
WHERE tablename = 'siparisler' AND attname = 'durum';
```

### 1.1. Kritik Metriklerin Anlamı

| Alan Adı | Değer Aralığı / Anlamı | Planlayıcı Kararına Etkisi |
| :--- | :--- | :--- |
| **`n_distinct`** | `>= 0`: Sabit tekil sayı (örn: 5 durum).<br>`< 0`: Toplam satır sayısına oran (`-1.0` = %100 tekil / PK). | Hash Join bellek boyutunu ve Group By maliyetini belirler. |
| **`most_common_vals` (MCV)** | Sütunda en sık geçen değerlerin listesi. | Eşitlik (`=`) filtrelerinde kardinaliteyi doğrudan hesaplar. |
| **`most_common_freqs` (MCF)** | MCV listesindeki değerlerin tabloda bulunma yüzdesi. | Örneğin durum='TAMAMLANDI' tablonun %85'i ise Index Scan yerine Seq Scan seçtirir. |
| **`histogram_bounds`** | MCV dışındaki değerlerin eşit aralıklı dağılım kovaları. | Aralık sorgularında (`BETWEEN`, `>`, `<`) seçicilik (selectivity) hesaplar. |
| **`correlation`** | `-1.0` ile `+1.0` arası. Mantıksal sıra ile fiziksel disk sırasının uyumu. | `1.0`'e yakınsa doğrudan hızlı **Index Scan**, `0.0` ise dağınık disk blokları yüzünden **Bitmap Index Scan** seçilir. |

---

## 2. Varsayımsal Bağımsızlık Tuzağı (Independence Assumption)

PostgreSQL planlayıcısı varsayılan olarak **her sütunun birbirinden tamamen bağımsız olduğunu** kabul eder:

$$P(A \cap B) = P(A) \times P(B)$$

### Gerçek Hayat Felaket Senaryosu:
Bir otomobil ilan tablosunda `marka = 'Audi'` ve `model = 'A4'` filtreleri verildiğini düşünelim:
* Tabloda 1.000.000 araç var.
* `marka = 'Audi'` oranı %5'tir (50.000 satır).
* `model = 'A4'` oranı %1'dir (10.000 satır).
* Planlayıcı bağımsızlık varsayımı ile: $0.05 \times 0.01 = 0.0005$ (%0.05) yani **500 satır** geleceğini hesaplar.
* **Gerçekte:** A4 modellerinin neredeyse tamamı Audi'dir! Gerçek sonuç **10.000 satırdır (20 kat hata)!**

Planlayıcı 500 satır geleceğini zannettiği için diğer tabloyla birleşirken yanlışlıkla bir `Nested Loop` seçer ve sorgu saniyelerce hatta dakikalarca kilitlenir.

---

## 3. Çözüm: Genişletilmiş İstatistikler (`CREATE STATISTICS`)

PostgreSQL 10+ ile gelen `CREATE STATISTICS`, ilişkili sütunlar arasındaki çok boyutlu dağılımı planlayıcıya öğretir.

### 3.1. Fonksiyonel Bağımlılıklar (`dependencies`)

Bir sütunun değeri bilindiğinde diğer sütunun değerini tahmin etmeyi sağlar:

```sql
CREATE STATISTICS stat_araba_marka_model (dependencies) 
ON marka, model FROM arabalar;

ANALYZE arabalar;
```

Oluşan bağımlılık katsayısını inceleme:
```sql
SELECT stxname, stxdndeps FROM pg_statistic_ext_data d
JOIN pg_statistic_ext s ON s.oid = d.stxoid
WHERE s.stxname = 'stat_araba_marka_model';
-- Çıktı: {"1 => 2": 0.99} (Model biliniyorsa Marka %99 bellidir)
```

### 3.2. Çok Sütunlu Ortak Değerler (`mcv` - Multivariate Most Common Values)

Aralık ve eşitlik kombinasyonlarında iki sütunun birlikte hangi frekanslarla tekrar ettiğini kaydeder:

```sql
CREATE STATISTICS stat_musteri_sehir_ilce (mcv) 
ON il, ilce FROM musteriler;

ANALYZE musteriler;
```

Bu istatistik oluşturulduktan sonra `WHERE il = 'İstanbul' AND ilce = 'Kadıköy'` sorgusunda planlayıcı tahmini %100 doğru kardinaliteyi yakalar ve doğru indeks/join algoritmasını seçer.

---

## 4. İstatistik Hassasiyetini Artırma (`STATISTICS TARGET`)

Varsayılan olarak `default_statistics_target = 100` kovadır (sample boyutu). Çok dengesiz (skewed) dağılıma sahip devasa tablolarda bu değer yetersiz kalabilir.

Tüm veritabanı genelinde artırmak `ANALYZE` süresini ve bellek tüketimini artırır. Bunun yerine yalnızca kritik ve dengesiz sütunlarda hedef artırılmalıdır:

```sql
-- Sadece bu kritik sütun için örneklem kovasını 100'den 1000'e çıkar
ALTER TABLE islemler ALTER COLUMN islem_kodu SET STATISTICS 1000;

-- Yeni örneklemi derle
ANALYZE islemler (islem_kodu);
```

---

## 5. İfade İstatistikleri (Expression Statistics)

PostgreSQL 14+, fonksiyonel ifadeler üzerinde de istatistik toplamayı destekler:

```sql
-- Ay bazında gruplanmış sipariş tarihi için genişletilmiş istatistik
CREATE STATISTICS stat_siparisler_aylik ON (date_trunc('month', siparis_tarihi)) FROM siparisler;
ANALYZE siparisler;
```

---

## 6. Acil Durum Plan Kilitleme: `pg_hint_plan`

Üretim ortamında acil bir performans krizinde istatistik güncellemesi yapmaya vakit yoksa veya planlayıcı inatla yanlış indeks/join seçiyorsa `pg_hint_plan` eklentisi ile sorguya doğrudan müdahale edilebilir:

```sql
/*+
    SeqScan(s)
    IndexScan(m idx_musteri_pk)
    Leading((s m))
    HashJoin(s m)
*/
SELECT s.id, m.ad
FROM siparisler s
JOIN musteriler m ON s.musteri_id = m.id
WHERE s.durum = 'BEKLEMEDE';
```

Bu mekanizma bir cankurtarandır; ancak kalıcı bir mimari çözüm değildir. Asıl yapılması gereken, istatistikleri ve şema tasarımını doğru inşa etmektir.
