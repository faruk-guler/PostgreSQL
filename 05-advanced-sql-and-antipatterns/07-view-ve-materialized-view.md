# View ve Materialized View

## 1. View (Görünüm)

PostgreSQL'de herhangi bir karmaşıklık düzeyindeki sorgu **view (görünüm)** olarak kaydedilip isimlendirilebilir. View, çok kullanılan ve karmaşık olan sorguların her defasında yeniden yazılmak zorunda kalınmadan çalıştırılmasını sağlar. Temelde veritabanında saklanan kayıtlı bir SQL sorgusudur.

```sql
CREATE VIEW myview AS
    SELECT city, temp_lo, temp_hi, prcp, date, location
        FROM weather, cities
        WHERE city = name;

-- View kullanımı normal bir tablo gibidir:
SELECT * FROM myview;
```

> [!NOTE]
> Bir view, `SELECT` kullanılarak her çağrıldığında **tanımındaki sorguyu o an yeniden çalıştırarak** güncel veriyi getirir. Veri diskte saklanmaz (sadece sorgunun tanımı saklanır).

### View Oluşturma ve Yönetme

```sql
-- Yeni bir view oluşturma
CREATE VIEW aktif_kullanicilar AS
    SELECT id, isim, email
    FROM kullanicilar
    WHERE aktif = TRUE;

-- Mevcut bir view'ı güncelleme (sütun silinemez, sona yeni sütun eklenebilir)
CREATE OR REPLACE VIEW aktif_kullanicilar AS
    SELECT id, isim, email, son_giris
    FROM kullanicilar
    WHERE aktif = TRUE;

-- View silme
DROP VIEW aktif_kullanicilar;

-- Bu view'a bağımlı başka nesneler varsa zincirleme silme
DROP VIEW aktif_kullanicilar CASCADE;
```

---

## 2. Materialized View (Somutlaştırılmış Görünüm)

Verilerin nadir değiştiği, ancak sorgunun çok uzun sürdüğü (milyonlarca satırlık JOIN'ler veya Aggregate işlemleri) tablolardan derlenmiş görünümlerin daha hızlı çalışabilmesi için sorgu sonucunun **diske fiziksel tablo gibi kaydedildiği** özelleşmiş view türüdür.

```sql
CREATE MATERIALIZED VIEW mymatview AS SELECT * FROM mytab;
SELECT * FROM mymatview;
```

### REFRESH (Yenileme)

Materialized View'lar kaynak tablolar güncellendiğinde otomatik güncellenmez. Veriyi tazelemek için manuel olarak tetiklenmesi gerekir:

```sql
REFRESH MATERIALIZED VIEW mymatview;
```

> [!WARNING]
> Standart `REFRESH` işlemi sırasında, view üzerinde `ACCESS EXCLUSIVE` kilidi (lock) oluşturulur. Bu kilit, yenileme işlemi bitene kadar diğer kullanıcıların `SELECT` atmasını engeller.

### CONCURRENTLY ile Kesintisiz Refresh

Büyük analitik view'ları güncellerken kullanıcıların (veya rapor ekranlarının) kilitlenmemesi için `CONCURRENTLY` parametresi kullanılır.

```sql
-- CONCURRENTLY kullanabilmek için en az bir UNIQUE index zorunludur
CREATE UNIQUE INDEX mymatview_unique_idx ON mymatview (id);

-- Kesintisiz yenileme (Okuma işlemleri engellenmez)
REFRESH MATERIALIZED VIEW CONCURRENTLY mymatview;
```

### WITH NO DATA

Eğer view tanımı çok büyükse ve oluşturma anında hemen verinin dolması istenmiyorsa (veriyi gece dolduracaksanız) boş olarak oluşturabilirsiniz:

```sql
CREATE MATERIALIZED VIEW mymatview AS SELECT * FROM mytab
WITH NO DATA;

-- Daha sonra içi doldurulur
REFRESH MATERIALIZED VIEW mymatview;
```

---

## 3. View vs Materialized View Karşılaştırması

| Özellik | View | Materialized View |
| :--- | :--- | :--- |
| **Veri Saklama** | Diskte saklanmaz (Sadece sorgu metni saklanır) | Diskte fiziksel tablo gibi saklanır |
| **Performans** | Her sorguda baştan hesaplandığı için yavaş olabilir | Çok hızlıdır (Hesaplanmış veri okunur) |
| **Güncel Veri** | Her zaman %100 günceldir | Sadece son `REFRESH` anına kadar günceldir |
| **İndeksleme** | İndeks atılamaz (Kaynak tablo indeksleri kullanılır) | Üzerine kendi B-Tree vb. indeksleri atılabilir |
| **Kullanım Yeri** | Basit görünümler, yetki sınırlandırması | BI raporları, DWH, ağır analitik dashboard'lar |

> [!TIP]
> **Otomasyon:** Belli aralıklarla Materialized View güncellemesini işletim sistemi `cron` görevi veya `pg_cron` eklentisi ile otomatikleştirerek, ağır analitik sorguların yanıt süresini dramatik şekilde azaltabilirsiniz:
>
> ```sql
> -- pg_cron ile her saat başı yenile
> SELECT cron.schedule('refresh-matview', '0 * * * *', 
>     'REFRESH MATERIALIZED VIEW CONCURRENTLY mymatview');
> ```
