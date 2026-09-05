# Tablo Bölümlendirme (Partitioning)

PostgreSQL'de Partitioning (Bölümlendirme), milyonlarca veya milyarlarca satırdan oluşan devasa bir tablonun mantıksal olarak tek bir tablo gibi görünürken, fiziksel (diskte) olarak daha küçük alt tablolara (parçalara) ayrılmasıdır. (Divide and Conquer - Böl ve Yönet mantığıdır).

## 1. Neden Kullanmalıyız? (Avantajları)

1.  **Sorgu Performansı (Partition Pruning):** Bir sorgu attığınızda, PostgreSQL sadece ilgili parçayı okur. Diğer devasa parçaları (Partition) hiç taramaz.
2.  **Toplu Veri Silme (Drop Partition):** 100 milyon satırlık eski bir veriyi `DELETE` ile silmek saatler sürer ve tablonun şişmesine (Bloat) neden olur. Partitioning ile ilgili eski veri parçasını tablodan ayırmak (`DETACH`) veya düşürmek (`DROP TABLE`) saniyeler sürer ve anında diskte yer açar.
3.  **İndeks Yönetimi:** İndeks boyutları devasa boyutlara çıkmaz, her parçanın kendi daha küçük indeksi olur ve bu indeksler belleğe (RAM) çok rahat sığar.
4.  **Data Aging (Veri Yaşlandırma):** Eski yılları barındıran parçaları yavaş ve ucuz disklere, son 1 ayın verisini barındıran parçaları hızlı (NVMe SSD) disklere koyabilirsiniz.

---

## 2. Bölümlendirme Yöntemleri

PostgreSQL, Declarative Partitioning (Bildirimsel Bölümlendirme) özelliği ile üç farklı yöntemi destekler:

### RANGE (Aralık) Bölümlendirmesi
En çok kullanılan yöntemdir. Genellikle "Tarih" veya "Sayı" aralıklarına göre yapılır. (Örn: 2023 satışları, 2024 satışları...)

### LIST (Liste) Bölümlendirmesi
Belirli bir listeye ait spesifik değerlere göre gruplama yapar. (Örn: `durum` kolonu 'Aktif' olanlar bir bölüme, 'Pasif' olanlar bir bölüme veya `sehir` kolonu 'İstanbul', 'Ankara' olanlar gibi).

### HASH (Karma) Bölümlendirmesi
Verileri belirli bir hash fonksiyonuna ve belirlenen modülüs (parça sayısı) değerine göre rastgele ancak dengeli bir şekilde dağıtır. Verilerin tüm parçalara eşit dağıtılmasını istediğiniz durumlarda (Load Balancing) kullanılır.

---

## 3. Örnek: Range Partitioning Uygulaması

Logları veya ölçüm verilerini (Örn: IOT Cihaz verileri) aylık parçalara bölelim.

**1. Ana Tablonun Oluşturulması (Partitioned Table):**
Tabloyu oluştururken `PARTITION BY` anahtar kelimesi ile bölümlendirme stratejisini belirliyoruz. Ana tabloya doğrudan veri yazılamaz.

```sql
CREATE TABLE olcumler (
    cihaz_id        int not null,
    log_tarihi      date not null,
    sicaklik        int,
    nem_orani       int
) PARTITION BY RANGE (log_tarihi);
```

**2. Alt Bölümlerin (Partitions) Oluşturulması:**
Ocak ve Şubat ayları için iki alt tablo oluşturalım.

```sql
-- Ocak 2024 Bölümü
CREATE TABLE olcumler_y2024m01 PARTITION OF olcumler
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Şubat 2024 Bölümü
CREATE TABLE olcumler_y2024m02 PARTITION OF olcumler
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

-- Herhangi bir bölüme girmeyen verilerin patlamaması için Default (Varsayılan) Bölüm
CREATE TABLE olcumler_default PARTITION OF olcumler DEFAULT;
```

**3. İndekslerin Oluşturulması:**
Her bölüme indeksleri ayrı ayrı atmanız gerekir.

```sql
CREATE INDEX ON olcumler_y2024m01 (log_tarihi);
CREATE INDEX ON olcumler_y2024m02 (log_tarihi);
```

> [!CAUTION]
> Eğer bir tablo bölümlendirilmişse (Partitioned) ve bir Primary Key (Birincil Anahtar) veya Unique kısıtlama eklemek isterseniz, bu kısıtlamanın (Index'in) içinde **Bölümleme Anahtarı (Partition Key)** kesinlikle yer almak zorundadır! (Yukarıdaki örnekte `log_tarihi` kolonu `cihaz_id` ile birlikte PK olmalıdır).

---

## 4. Bölüm Yönetimi (Ekleme ve Çıkarma)

Eski (Ocak 2024) verilerini tamamen sistemden uçurmak:
```sql
DROP TABLE olcumler_y2024m01; 
-- Milyonlarca satır saniyeler içinde silinir.
```

Eski veriyi ana tablodan ayırıp yedek olarak kenarda bekletmek:
```sql
ALTER TABLE olcumler DETACH PARTITION olcumler_y2024m01;
-- Artık "olcumler" tablosuna SELECT attığınızda bu veri gelmez. Ama bağımsız bir tablo olarak kenarda durur.
```
