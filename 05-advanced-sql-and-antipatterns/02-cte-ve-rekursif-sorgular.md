# CTE (Ortak Tablo İfadeleri) ve Rekürsif Sorgular

PostgreSQL'de karmaşık sorguları, içiçe geçmiş (Nested) onlarca alt sorgudan (Subquery) kurtarmak, daha okunabilir hale getirmek ve bazı durumlarda performansı artırmak için **CTE (Common Table Expressions)** yani `WITH` yapısı kullanılır.

---

## 1. CTE (WITH) Kullanımı

`WITH` ifadesi, sorgunun çalışma süresi (Execution) boyunca var olan geçici bir tablo (veya değişken) tanımlamanıza olanak sağlar.

### Neden CTE Kullanmalıyız?
1.  **Okunabilirlik (Readability):** Matruşka gibi iç içe geçmiş parantezleri ayırır, kodu yukarıdan aşağıya doğru okunabilir, modüler bloklar haline getirir.
2.  **Yeniden Kullanılabilirlik (Reusability):** Oluşturduğunuz geçici tabloyu, ana sorgu içinde veya diğer CTE'ler içinde defalarca (Join vb. ile) kullanabilirsiniz.

### Basit CTE Örneği

```sql
-- 1. Aşama: Bölgesel satışları toplayan geçici bir tablo oluştur
WITH bolgesel_satislar AS (
    SELECT bolge, SUM(tutar) AS toplam_satis
    FROM siparisler
    GROUP BY bolge
), 
-- 2. Aşama: O bölgesel satışların en yüksek 10'luk dilimine girenleri bul
en_iyi_bolgeler AS (
    SELECT bolge
    FROM bolgesel_satislar
    WHERE toplam_satis > (SELECT SUM(toplam_satis) / 10 FROM bolgesel_satislar)
)
-- 3. Aşama (Ana Sorgu): En iyi bölgelerde satılan ürünlerin dökümünü al
SELECT bolge, urun, SUM(adet) 
FROM siparisler
WHERE bolge IN (SELECT bolge FROM en_iyi_bolgeler)
GROUP BY bolge, urun;
```

> [!NOTE]
> PostgreSQL 12 sürümünden itibaren, CTE'ler varsayılan olarak (inline) ana sorguya yedirilerek (Query Planner tarafından) optimize edilir. Eski sürümlerde CTE bir "Optimization Fence" (Optimizasyon Bariyeri) oluştururdu.

---

## 2. DML (Insert, Update, Delete) ile CTE Kullanımı (RETURNING)

PostgreSQL'in en güçlü özelliklerinden biri, bir tabloya veri eklerken (INSERT) veya silerken (DELETE) değiştirdiği kayıtları `RETURNING` komutuyla geri döndürebilmesidir. Bunu CTE ile birleştirerek muazzam iş akışları kurabilirsiniz.

### Silinen Verileri Arşive Taşıma

```sql
-- Aktif tablodan sildiği kayıtları alır, anında arşiv tablosuna kaydeder.
WITH silinenler AS (
    DELETE FROM aktif_siparisler
    WHERE durum = 'Iptal'
    RETURNING *   -- Silinen tüm satırların datasını döndürür
)
INSERT INTO iptal_arsivi
SELECT * FROM silinenler;
```

Bu yapı, normalde uygulama katmanında yapılacak 2 ayrı sorguyu ve veriyi network üzerinden uygulamaya taşıma maliyetini tamamen ortadan kaldırır. Tek bir atomik transaction içinde işlem veritabanı motorunda çözülür.

---

## 3. Rekürsif (Öz-Yinelemeli) Sorgular (WITH RECURSIVE)

Klasik SQL, Hiyerarşik (Ağaç, Yorum-Cevap, Kategori-Alt Kategori) veri modellerini sorgulamak konusunda yetersiz kalır. PostgreSQL'de `WITH RECURSIVE` yapısı, bir sorgunun sonucunun tekrar aynı sorguya girdi olarak beslenmesini sağlar.

### `WITH RECURSIVE` Yapısı
Rekürsif bir CTE iki ana parçadan oluşur ve aralarında `UNION` veya `UNION ALL` bulunur:
1.  **Anchor (Çapa) Member:** Başlangıç noktasını belirler. (Döngünün nereden başlayacağı).
2.  **Recursive Member:** Bir önceki adımın sonucunu kaynak tablo gibi kullanarak (CTE'nin adını referans alarak) döngüyü sürdürür. Şart sağlanana kadar çalışmaya devam eder.

### Örnek 1: Seri Üretimi (Döngü)
1'den 100'e kadar olan sayıları ve toplamlarını bulan basit bir döngü.

```sql
WITH RECURSIVE t(n) AS (
    -- Anchor: Döngüye 1 ile başla
    VALUES (1)
    
    UNION ALL
    
    -- Recursive: Bir önceki dönen "n" değerine 1 ekle.
    -- Sınır şartı: n değeri 100'den küçük olduğu sürece devam et.
    SELECT n + 1 FROM t WHERE n < 100
)
SELECT sum(n) FROM t;
```

### Örnek 2: Organizasyon Şeması (Hiyerarşi)
Personel ve Yöneticilerinin (Manager) aynı tabloda tutulduğu bir ağaç yapısında, CEO'dan (En üst) başlayarak tüm organizasyon şemasını çıkarma.

```sql
WITH RECURSIVE organizasyon_semasi AS (
    -- Anchor: En tepedeki kişiyi bul (Yöneticisi NULL olan CEO)
    SELECT id, ad, yonetici_id, 1 as seviye
    FROM personel
    WHERE yonetici_id IS NULL
    
    UNION ALL
    
    -- Recursive: Yukarıdan dönen tablonun (organizasyon_semasi) personellerini bul 
    -- ve onların yonetici_id'leri ile eşleştirerek alt kademelere in.
    SELECT p.id, p.ad, p.yonetici_id, o.seviye + 1
    FROM personel p
    INNER JOIN organizasyon_semasi o ON p.yonetici_id = o.id
)
SELECT * FROM organizasyon_semasi ORDER BY seviye;
```

> [!WARNING]
> Ağaç yapılarında (Özellikle dışardan gelen / kirli verilerde) bazen veri hataları nedeniyle "Döngüsel Referans" (A kişisi B'nin yöneticisi, B kişisi C'nin yöneticisi, C kişisi de A'nın yöneticisi) oluşabilir. Bu durum `WITH RECURSIVE` sorgusunun **sonsuz döngüye (Infinite Loop)** girmesine ve sunucunun kilitlenmesine neden olabilir.
