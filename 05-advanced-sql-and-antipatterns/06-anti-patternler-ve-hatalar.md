# PostgreSQL Anti-Pattern'leri ve Sık Yapılan Hatalar

> **Bölüm Kapsamı:** Şema Tasarımı, Sorgu Optimizasyonu, Canlıda Çift Satır Temizleme (`ctid`), `NOT IN` NULL Felaketi, İndeksleme ve Konfigürasyonda Kaçınılması Gereken Kritik DBA Tuzakları.

---

## 1. Schema Tasarımı Hataları

### ❌ Anti-Pattern: İndekssiz Foreign Key Kullanımı

PostgreSQL'de bir `Foreign Key` kısıtlaması, referans verilen (parent) tabloda bir `DELETE` veya `UPDATE` yapıldığında veri bütünlüğünü korumak için referans eden (child) tabloyu kontrol etmek zorundadır. Eğer child tablodaki FK sütununda indeks yoksa, parent tablodaki her silme işleminde child tabloda **Full Table Scan (Tam Tablo Taraması)** yapılır. Daha da kötüsü, bu tarama sırasında child tabloda agresif kilitler (`ShareRowExclusiveLock`) alınır ve tüm sistem kilitlenebilir.

**✅ Doğru:** Her `Foreign Key` sütununa mutlaka bağımsız bir B-Tree indeksi ekleyin.

```sql
-- Kötü: FK var ama indeks yok
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id)
);

-- İyi: FK için indeks eklenmiş
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
```

---

### ❌ Anti-Pattern: Rastgele UUIDv4 Primary Key

Primary Key olarak rastgele `UUIDv4` kullanmak, B-Tree indeksinde ciddi fragmantasyona (parçalanma) yol açar. Rastgele dağılan veriler, diskin farklı sayfalarına sürekli rastgele I/O yapmaya zorlar ve Buffer Pool'u kirletir.

**✅ Doğru:** Sıralı ID kullanın (`BIGINT / IDENTITY`) veya zamana dayalı sıralı UUID (`UUIDv7`) tercih edin.

---

### ❌ Anti-Pattern: TEXT yerine VARCHAR(n) Takıntısı

Diğer veritabanlarının aksine (örneğin eski MySQL sürümleri), PostgreSQL'de `VARCHAR(255)` ile `TEXT` arasında hiçbir performans, depolama veya indeksleme farkı yoktur. İkisi de aynı `varlena` yapısını kullanır.

**✅ Doğru:** İş kuralı gereği bir limit şart değilse (örneğin T.C. Kimlik No 11 karakter olmak zorunda değilse) `TEXT` kullanın. Limit gerekiyorsa bunu bir `CHECK (length(kod) <= 50)` kısıtıyla da yönetebilirsiniz.

---

## 2. Sorgu (Query) Hataları

### ❌ Anti-Pattern: `NOT IN` İçindeki NULL Felaketi (Three-Valued Logic)

SQL standardında `NULL` bir değer değil, bir "Bilinmeyen" (Unknown) durumdur. `NOT IN (alt_sorgu)` yapısında, alt sorgudan dönen kayıtlardan **tek bir tanesi bile `NULL` ise**, ana sorgu istisnasız **SIFIR SATIR** döndürür!

```sql
-- ❌ TEHLİKELİ SORGUSU:
-- Eğer calisanlar tablosunda yonetici_id'si NULL olan tek bir kişi (Örn: CEO) varsa:
SELECT * FROM departmanlar 
WHERE id NOT IN (SELECT yonetici_id FROM calisanlar);
-- Sonuç: 0 satır! (Tüm sistem veri yokmuş gibi davranır).
```

* **Matematiksel Nedeni:** `id NOT IN (1, 2, NULL)` ifadesi SQL motorunda şuna açılır:
  `id <> 1 AND id <> 2 AND id <> NULL`
  `id <> NULL` ifadesi her zaman `UNKNOWN` üretir. Mantıksal `AND` zincirinde bir tane bile `UNKNOWN` olması tüm şartı geçersiz kılar.

**✅ Doğru DBA Çözümü:** Daima `NOT EXISTS` kullanın. `NOT EXISTS` üç değerli mantık tuzağına düşmez, NULL-safe'tir ve optimizörün son derece verimli bir **`Hash Anti Join`** planlamasını sağlar.

```sql
-- ✅ GÜVENLİ VE PERFORMANSLI:
SELECT d.* 
FROM departmanlar d
WHERE NOT EXISTS (
    SELECT 1 FROM calisanlar c WHERE c.yonetici_id = d.id
);
```

---

### ❌ Anti-Pattern: Can Kurtaran `ctid` ile Çift Satır Temizleme (Deduplication)

Canlı sistemlerde `UNIQUE` kısıtı unutulmuş tablolarda mükerrer (duplike) satırlar birikebilir. Yazılımcılar genellikle bu satırları temizlemek için yavaş alt sorgular veya uygulama döngüleri yazar.

* **Kötü Yaklaşım:** `DELETE FROM tablo WHERE id NOT IN (SELECT min(id)...)` (Tüm tabloyu kilitler, bellek taşar).

**✅ Doğru DBA Çözümü (`ctid` Kullanımı):**
`ctid`, bir satırın PostgreSQL veri sayfalarındaki fiziksel konumunu (`Sayfa No, Offset`) temsil eden gizli bir sistem kolonudur. Donanımı yormadan mükerrer satırları silmenin en hızlı yoludur:

```sql
-- DBA Kriz Reçetesi: urun_kodu mükerrer olan satırlardan sadece ilk fiziksel kaydı koru, diğerlerini sil:
DELETE FROM urunler
WHERE ctid NOT IN (
    SELECT min(ctid)
    FROM urunler
    GROUP BY urun_kodu
);
```

> [!TIP]
> **Canlı Sistemde Parçalı Deduplication:**
> Eğer tabloda 100 milyon satır varsa, yukarıdaki sorgu tek transaction'da çalıştırılmamalıdır. Bunun yerine tablonun tarih veya ID aralıklarına göre `WHERE olusturma_tarihi >= ...` filtresiyle parça parça işletilmelidir.

---

### ❌ Anti-Pattern: LIMIT ... OFFSET ile Derin Sayfalama (Deep Paging)

`OFFSET 1000000 LIMIT 20` dendiğinde, veritabanı 1.000.000 satırı bellekten okur, çöpe atar ve son 20 satırı getirir. Sayfa numarası arttıkça sorgu dakikalar sürer ve CPU'yu kilitler.

**✅ Doğru:** Keyset Pagination (Seek Method / Cursor Based) kullanın:

```sql
-- ❌ Kötü (Derin sayfalarda çöker):
SELECT * FROM audit_logs ORDER BY id DESC LIMIT 20 OFFSET 500000;

-- ✅ İyi (Her sayfada aynı mikrosaniye hızında):
SELECT * FROM audit_logs 
WHERE id < 4999980 -- Bir önceki sayfanın son ID'si
ORDER BY id DESC 
LIMIT 20;
```

---

### ❌ Anti-Pattern: Fonksiyon İçinde Sütun Kullanımı (SARGability İhlali)

B-Tree indeksler sütunun ham değeri üzerine kuruludur. Bir sütunu fonksiyon içine aldığınızda (`WHERE date(created_at) = '2026-05-01'`), optimizör indeksi kullanamaz ve **Seq Scan (Tam Tablo Taraması)** yapar.

**✅ Doğru:** Sorguyu indekse uygun aralığa çevirin (`SARGable` sorgu):
```sql
-- İndeksi tam kullanan doğru yazım:
WHERE created_at >= '2026-05-01 00:00:00' 
  AND created_at < '2026-05-02 00:00:00'
```

---

### ❌ Anti-Pattern: Canlıda Devasa DML İşlemleri (Massive DML Bloat)

Canlı sistemde `UPDATE siparisler SET durum = 'arsiv' WHERE tarih < '2023-01-01';` diyerek tek seferde 10 milyon satırı güncellemek intihardır:
1. MVCC mimarisi gereği 10 milyon yeni ölü satır (Dead Tuple) oluşur, tablo boyutu anında iki katına çıkar (Bloat).
2. Devasa WAL akışı oluşur, Streaming Replication gecikmesi (Lag) fırlar.
3. 10 milyon satır kilitlendiği için diğer tüm `UPDATE/DELETE` işlemleri kilit kuyruğunda bekler.

**✅ Doğru DBA Çözümü:** İşlemi transaction blokları halinde parçalayın (Batching / Chunking):
```sql
-- 10.000'lik paketlerle güncelleyip her adımda COMMIT atmak:
DO $$
DECLARE
    rows_updated INT;
BEGIN
    LOOP
        UPDATE siparisler
        SET durum = 'arsiv'
        WHERE id IN (
            SELECT id FROM siparisler
            WHERE durum <> 'arsiv' AND tarih < '2023-01-01'
            LIMIT 10000
        );
        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;
        COMMIT;
        PERFORM pg_sleep(0.1); -- Replikasyon gecikmesini önlemek için kısa mola
    END LOOP;
END $$;
```

---

## 3. Konfigürasyon ve İşletim Hataları

### ❌ Anti-Pattern: "Idle in Transaction" Oturumlarını Açık Unutmak

Uygulamanın bir `BEGIN` başlatıp bağlantıyı kapatmadan açık unutması:
1. **Autovacuum'u Bloke Eder:** Kilitlenen transaction'ın `xmin` değerinden daha yeni olan hiçbir ölü satır temizlenemez. Tüm veritabanı hızla şişer (Bloat).
2. **Tablo Kilitlerini Tutar:** En ufak bir DDL işlemi bile kilit kuyruğuna takılır ve arkasından gelen tüm `SELECT`'leri kilitler.

**✅ Doğru:** `postgresql.conf` içine mutlaka güvenlik sigortası koyun:
```ini
idle_in_transaction_session_timeout = 60000  # 60 saniye sonra açık unutulan oturumu sonlandır
```

---

### ❌ Anti-Pattern: Autovacuum'u Kapatmak

"Sistemi yavaşlatıyor" gerekçesiyle autovacuum'u kapatmak felakettir. Tablolar hızla şişer, istatistikler bayatlar ve 2 milyar işlem sınırı aşıldığında sistem **Transaction Wraparound** hatasıyla kendini korumak için salt-okunur (read-only) kilitler!

**✅ Doğru:** Autovacuum'u kapatmayın; I/O hızını artıracak ve daha az kaynak tüketecek şekilde optimize edin (`autovacuum_vacuum_cost_limit`, `autovacuum_max_workers`).

---

## Özet: DBA Kontrol Listesi

1. Tüm Foreign Key sütunlarında B-Tree indeks tanımlı mı?
2. Alt sorgularda `NOT IN` yerine `NOT EXISTS` tercih ediliyor mu?
3. Derin sayfalama yerine Keyset Pagination kullanılıyor mu?
4. Mükerrer kayıtlar `ctid` ile diski kitlemeden temizleniyor mu?
5. `idle_in_transaction_session_timeout` parametresi aktif mi?
6. Toplu DML işlemleri paketler (chunk) halinde mi işletiliyor?
