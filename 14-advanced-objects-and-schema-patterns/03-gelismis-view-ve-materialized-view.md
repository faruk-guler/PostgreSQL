# Gelişmiş View ve Somutlaştırılmış Görünümler (Materialized Views)

> **Bölüm Kapsamı:** Standart View Mimarisi, `WITH CHECK OPTION`, Materialized View, `CONCURRENTLY` Yenileme ve Otomatik Tazeleme Stratejileri

---

PostgreSQL'de görünümler (Views), karmaşık sorguları basitleştirmek, güvenlik katmanı oluşturmak ve veri ambarı sorgularını önbelleklemek için iki farklı biçimde sunulur: **Standart Görünümler (Standard Views)** ve **Somutlaştırılmış Görünümler (Materialized Views)**.

---

## 1. Standart View vs Materialized View Karşılaştırması

| Kriter | Standart Görünüm (View) | Somutlaştırılmış Görünüm (Materialized View) |
| :--- | :--- | :--- |
| **Fiziksel Depolama** | Disk alanı kaplamaz (Yalnızca SQL kuralı saklanır). | Gerçek bir tablo gibi diskte yer kaplar (Veri fizikseldir). |
| **Sorgu Çalışma Şekli** | Her çağrıldığında arka plandaki SQL yeniden çalıştırılır. | Önceden hesaplanmış diskteki anlık kopyadan anında okunur. |
| **İndekslenebilirlik** | İndekslenemez. | **Evet!** Üzerine B-Tree, GIN vb. indeksler kurulabilir. |
| **Veri Güncelliği** | Her zaman anlık (Real-time). | Son `REFRESH` anındaki veriyi gösterir (Snapshot). |
| **Kullanım Alanı** | Güvenlik filtreleme, basit soyutlama. | Ağır analitik, BI raporları, karmaşık JOIN'ler. |

---

## 2. Standart Görünümlerde Güvenlik: `WITH CHECK OPTION`

Güncellenebilir bir View üzerinden veri eklerken veya güncellerken, eklenen verinin view'ın `WHERE` koşuluna uyup uymadığını denetlemek için **`WITH CHECK OPTION`** kullanılır:

```sql
-- Sadece Ankara şubesinin çalışanlarını gösteren view
CREATE OR REPLACE VIEW v_ankara_employees AS
SELECT id, name, department, branch
FROM employees
WHERE branch = 'Ankara'
WITH CHECK OPTION; -- veya WITH LOCAL CHECK OPTION / CASCADED CHECK OPTION

-- Deneme 1: Ankara şubesine yeni personel ekle (Başarılı)
INSERT INTO v_ankara_employees (name, department, branch)
VALUES ('Murat Kaya', 'IT', 'Ankara');

-- Deneme 2: İzmir şubesine personel eklemeye çalış (HATA!)
INSERT INTO v_ankara_employees (name, department, branch)
VALUES ('Canan Demir', 'Satış', 'İzmir');
-- ERROR: new row violates check option for view "v_ankara_employees"
```

*`WITH CHECK OPTION` olmasaydı veri eklenirdi ancak view'ın WHERE koşuluna uymadığı için kullanıcı kendi eklediği kaydı göremezdi.*

---

## 3. Somutlaştırılmış Görünümler (Materialized Views)

Milyonlarca satırlık tablolardan oluşan ağır analitik sorguları her kullanıcı için tekrar tekrar çalıştırmak sunucuyu kilitler. Materialized View bu sorgunun sonucunu diske fiziksel bir tablo gibi dondurur.

### a. Oluşturma ve `WITH NO DATA`

```sql
-- Ağır özetleme sorgusunu Materialized View yap
CREATE MATERIALIZED VIEW mv_monthly_sales AS
SELECT 
    date_trunc('month', order_date)::DATE AS sales_month,
    product_category,
    COUNT(*) AS total_orders,
    SUM(amount) AS total_revenue
FROM orders o
JOIN products p ON o.product_id = p.id
GROUP BY 1, 2
WITH NO DATA; -- Oluşturma anında diske veri doldurmaz (Hızlı kurulum sağlar)
```

### b. İlk Veriyi Doldurma

```sql
REFRESH MATERIALIZED VIEW mv_monthly_sales;
```

### c. Materialized View Üzerine İndeks Tanımlama

Materialized View diskte gerçek bir ilişki (relation) olduğu için üzerine doğrudan indeks kurulabilir:

```sql
-- İndeks oluşturma:
CREATE INDEX idx_mv_sales_month ON mv_monthly_sales (sales_month);
```

---

## 4. Kesintisiz Canlı Yenileme: `REFRESH ... CONCURRENTLY`

Standart bir `REFRESH MATERIALIZED VIEW mv_monthly_sales;` komutu, işlem süresince view üzerine **`EXCLUSIVE` kilit** koyar. Bu sırada hiçbir kullanıcı view'ı okuyamaz (`SELECT` sorguları kilitte bekler).

PostgreSQL, kullanıcıların okuma yapmaya devam edebilmesi için **`CONCURRENTLY`** seçeneğini sunar.

### `CONCURRENTLY` Şartı: Tekil İndeks (UNIQUE INDEX)

`CONCURRENTLY` kullanabilmek için view üzerinde **tüm kolonları kapsayan veya benzersizliği garanti eden en az bir `UNIQUE INDEX` bulunması ZORUNLUDUR**:

```sql
-- 1. Tekil indeks tanımla (Her ay ve kategori kombinasyonu tekildir)
CREATE UNIQUE INDEX idx_mv_sales_unique ON mv_monthly_sales (sales_month, product_category);

-- 2. Artık kilitlemeden arka planda yenileyebilirsiniz!
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_sales;
```

*Bu işlem sırasında PostgreSQL arka planda geçici bir tablo açar, farkları hesaplar ve canlı sistemi kilitlemeden değişiklikleri ana view'a uygular.*

---

## 5. Otomatik Yenileme Stratejileri

Materialized View verileri kaynak tablo değiştikçe otomatik güncellenmez. Kurumsal mimarilerde bu tazeleme şu yöntemlerle otomatikleştirilir:

### Yöntem 1: `pg_cron` ile Zamanlanmış Görev (En Yaygın)

```sql
-- Her gece saat 02:00'de kesintisiz yenile
SELECT cron.schedule('daily-sales-refresh', '0 2 * * *', 
    'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_sales;');
```

### Yöntem 2: Tetikleyici ve LISTEN/NOTIFY Tabanlı Asenkron Yenileme

Kaynak tabloya kritik bir güncelleme geldiğinde `pg_notify` ile bildirim fırlatılır; arka plandaki bir worker (örneğin Python veya Node.js servisi) belirli aralıklarla biriken yenileme talebini çalıştırır.
