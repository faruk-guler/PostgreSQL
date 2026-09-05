# Görünümler (Views) ve Materialized Views

Veritabanında çok sık kullanılan, birden fazla tabloyu birleştiren (JOIN) ve karmaşık filtrelemeler (WHERE) içeren sorguları her seferinde baştan yazmak yerine, bu sorguları sanal bir tablo gibi kaydedebiliriz. Buna **View** denir.

---

## 1. Standart View (Görünüm) Nedir?

`VIEW`, fiziksel olarak diskte bir yer kaplamaz, veri tutmaz. Sadece bir sorgunun isimlendirilmiş, paketlenmiş (Alias) halidir.

Siz view'a her `SELECT` attığınızda, PostgreSQL arka planda view'ı oluşturan asıl SQL sorgusunu çalıştırır ve verileri canlı olarak getirir.

```sql
-- View Oluşturma
CREATE VIEW aktif_kullanici_siparisleri AS
    SELECT k.isim, k.eposta, s.siparis_tutari, s.siparis_tarihi
    FROM kullanicilar k
    INNER JOIN siparisler s ON k.id = s.kullanici_id
    WHERE k.durum = 'Aktif';

-- Kullanımı (Sanki gerçek bir tabloymuş gibi sorgulanabilir)
SELECT * FROM aktif_kullanici_siparisleri WHERE siparis_tutari > 500;
```

### Avantajları:
1.  **Güvenlik:** Kullanıcılara tabloların (Örn: Maaş bilgilerinin) sadece belirli kısımlarını göstermek için kullanılır.
2.  **Okunabilirlik:** Çok uzun sorguları kısaltır, spagetti SQL yazımını önler.

---

## 2. Materialized View (Fizikselleştirilmiş Görünüm)

Raporlama (BI) araçlarında, geçmiş verileri analiz etmek için devasa tablolarda milyarlarca satır üzerinde SUM(), AVG() gibi aggregate fonksiyonları çalıştırılır. Standart bir `VIEW` kullanırsanız, rapor her açıldığında bu ağır hesaplamalar baştan yapılır ve sistem kilitlenebilir.

**`MATERIALIZED VIEW`**, view'ı oluşturan sorguyu **çalıştırır, hesaplar ve sonucunu diskte gerçek bir tablo gibi fiziksel olarak kaydeder.**

```sql
-- Materialized View Oluşturma
CREATE MATERIALIZED VIEW aylik_satis_raporu AS
    SELECT extract(year from tarih) as yil, extract(month from tarih) as ay, sum(tutar) as toplam
    FROM satislar
    GROUP BY 1, 2;
```

Sorgulama yaptığınızda milisaniyeler içinde cevap döner (Çünkü cevap zaten hesaplanıp diske yazılmıştır). Hatta bu görünüm üzerine **Index** bile oluşturabilirsiniz.

```sql
CREATE UNIQUE INDEX idx_aylik_rapor ON aylik_satis_raporu (yil, ay);
```

### Veriyi Güncellemek (Refresh)
Asıl tablolar (`satislar`) güncellense bile, `MATERIALIZED VIEW` içindeki veri **otomatik olarak DEĞİŞMEZ**. Değişmesi için sizin tetiklemeniz (Refresh) gerekir. (Genellikle bunu geceleri çalışan bir cron job ile yaparlar).

```sql
-- Veriyi asıl tablolardan tekrar çeker ve günceller
REFRESH MATERIALIZED VIEW aylik_satis_raporu;
```

> [!CAUTION]
> Düz `REFRESH` komutu, view'ı güncellerken tabloyu kilitler (Lock). O esnada rapor ekranını açan bir kullanıcı, sayfanın yüklenmesini beklemek zorunda kalır (Blocking). 
> 
> Bunu çözmek için **`CONCURRENTLY`** parametresi kullanılır. Tabloyu kilitlemeden arka planda veriyi günceller. (Bunun çalışabilmesi için view'da mutlaka bir **UNIQUE INDEX** olması şarttır).

```sql
-- Lock atmadan veriyi güncelleme (Production'da her zaman bu kullanılmalıdır)
REFRESH MATERIALIZED VIEW CONCURRENTLY aylik_satis_raporu;
```
