# PostgreSQL 17 SQL/JSON Standartları ve JSON_TABLE() Ustalığı

> **Bölüm Kapsamı:** ANSI SQL:2023 Standardı, JSON_TABLE() ile JSON Verisini Tabloya Dönüştürme, JSON_QUERY, JSON_EXISTS ve İleri JSONB Optimizasyonu

---

## 1. PostgreSQL'de JSON Devrimi: Geleneksel JSONB'den SQL:2023 Standardına

PostgreSQL, 9.4 sürümünden beri ikili JSON formatı olan **JSONB** ile NoSQL veritabanlarını geride bırakan bir hız ve esneklik sunmaktadır. Ancak geleneksel sözdiziminde kullanılan operatörler (`->`, `->>`, `#>`, `?`, `?|`) PostgreSQL'e özgüydü ve karmaşık iç içe (nested) JSON yapılarını ilişkisel tablolara dönüştürmek için hantal fonksiyonlar (`jsonb_to_recordset`, `jsonb_array_elements`) gerekiyordu.

**PostgreSQL 17**, resmi ANSI SQL standardı olan **SQL/JSON (SQL:2023)** özelliklerini çekirdeğe entegre ederek bu alanda tarihi bir devrim gerçekleştirdi.

Artık JSON verileri, karmaşık fonksiyonlara veya harici kodlara gerek kalmadan, doğrudan resmi SQL standardı ile sorgulanabilir ve gerçek bir ilişkisel tablo gibi satır-sütun formatına açılabilir.

---

## 2. `JSON_TABLE()` ile JSON'ı Doğrudan İlişkisel Tabloya Çevirme

`JSON_TABLE()`, bir JSON metnini veya JSONB sütununu girdi olarak alıp, belirlenen JSONPath yoluna göre satırlara ve sütunlara ayıran bir **Table-Valued Function (Tablo Değerli Fonksiyon)**'dır.

### Temel Sözdizimi (Syntax)

```sql
SELECT *
FROM JSON_TABLE(
    json_kaynagi,
    'jsonpath_satir_ifadesi'
    COLUMNS (
        sutun_adi_1 veri_tipi PATH 'jsonpath_sutun_ifadesi',
        sutun_adi_2 veri_tipi PATH 'jsonpath_sutun_ifadesi'
    )
) AS takma_ad;
```

### Pratik Örnek: E-Ticaret Sipariş JSON'ını Parçalama

Elimizde bir ödeme ağ geçidinden gelen aşağıdaki gibi bir sipariş JSON'ı olduğunu varsayalım:

```json
{
  "order_id": "ORD-2026-9918",
  "customer": "Faruk Güler",
  "items": [
    { "sku": "PG-BOOK-01", "name": "PostgreSQL Master Guide", "price": 450.00, "qty": 2 },
    { "sku": "KBD-MECH-02", "name": "Mekanik Klavye", "price": 1850.50, "qty": 1 }
  ]
}
```

Bu JSON verisini hiçbir harici ETL yazmadan tek bir `JSON_TABLE()` sorgusuyla satırlara dökelim:

```sql
SELECT jt.*
FROM JSON_TABLE(
    '{
      "order_id": "ORD-2026-9918",
      "customer": "Faruk Güler",
      "items": [
        { "sku": "PG-BOOK-01", "name": "PostgreSQL Master Guide", "price": 450.00, "qty": 2 },
        { "sku": "KBD-MECH-02", "name": "Mekanik Klavye", "price": 1850.50, "qty": 1 }
      ]
    }'::jsonb,
    '$.items[*]'
    COLUMNS (
        order_code   TEXT           PATH 'lax $.order_id',
        customer_name TEXT          PATH 'lax $.customer',
        item_sku     TEXT           PATH '$.sku',
        item_name    TEXT           PATH '$.name',
        unit_price   NUMERIC(10,2)  PATH '$.price',
        quantity     INT            PATH '$.qty',
        total_price  NUMERIC(10,2)  EXISTS PATH '$.price' -- Alan varlık kontrolü
    )
) AS jt;
```

#### Dönen İlişkisel Sonuç

| order_code | customer_name | item_sku | item_name | unit_price | quantity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| ORD-2026-9918 | Faruk Güler | PG-BOOK-01 | PostgreSQL Master Guide | 450.00 | 2 |
| ORD-2026-9918 | Faruk Güler | KBD-MECH-02 | Mekanik Klavye | 1850.50 | 1 |

---

## 3. İç İçe Dizileri Açma: `NESTED PATH`

Gerçek hayat verilerinde dizilerin içinde başka alt diziler bulunur. Örneğin: Bir siparişin içinde birden fazla ürün, her ürünün altında ise uygulanan farklı indirimler veya vergiler (`discounts: [...]`) yer alabilir.

Geleneksel PostgreSQL'de bunu yapmak için birden fazla `CROSS JOIN LATERAL jsonb_array_elements()` yazmak gerekirdi ve kartezyen çarpım hatalarına yol açardı.

PostgreSQL 17'de `NESTED PATH` yapısıyla bu işlem deklaratif olarak çözülür:

```sql
SELECT jt.*
FROM JSON_TABLE(
    '{
      "branch": "Kadıköy",
      "sales": [
        {
          "invoice": "INV-101",
          "products": [
            { "name": "Laptop", "tags": ["elektronik", "bilgisayar"] },
            { "name": "Mouse",  "tags": ["aksesuar"] }
          ]
        }
      ]
    }'::jsonb,
    '$.sales[*]'
    COLUMNS (
        invoice_no TEXT PATH '$.invoice',
        NESTED PATH '$.products[*]' COLUMNS (
            product_name TEXT PATH '$.name',
            NESTED PATH '$.tags[*]' COLUMNS (
                tag_name TEXT PATH '$'
            )
        )
    )
) AS jt;
```

---

## 4. SQL/JSON Sorgulama ve Filtreleme Fonksiyonları

PostgreSQL 17 ile gelen diğer standart SQL/JSON fonksiyonları:

### A. `JSON_EXISTS()`: Kriter Kontrolü

Bir JSON dokümanı içinde belirli bir koşulu sağlayan bir öğenin var olup olmadığını kontrol eder. `WHERE` koşullarında devrim niteliğinde kolaylık sağlar:

```sql
-- Sepetinde 1000 TL üzeri ürün olan siparişleri getir
SELECT id, customer_id
FROM orders
WHERE JSON_EXISTS(order_payload, '$.items[*] ? (@.price > 1000)');
```

### B. `JSON_VALUE()`: Tekil Skalar Değer Çıkarma

JSONPath üzerinden tek bir skalar değeri (metin, sayı, boolean) SQL veri tipine dönüştürerek çeker:

```sql
SELECT 
    id,
    JSON_VALUE(order_payload, '$.customer.email' RETURNING text) AS customer_email,
    JSON_VALUE(order_payload, '$.total_amount' RETURNING numeric) AS total
FROM orders;
```

- **`ON EMPTY` ve `ON ERROR` Davranışları:**

  ```sql
  -- Alan bulunamazsa varsayılan değer dön, format hatası olursa NULL dön:
  JSON_VALUE(order_payload, '$.discount' RETURNING numeric DEFAULT 0 ON EMPTY NULL ON ERROR)
  ```

### C. `JSON_QUERY()`: Alt JSON Nesnesi veya Dizisi Çıkarma

Bir alanı skalar olarak değil, yine bir JSON/JSONB yapısı olarak koruyarak çıkarmak için kullanılır:

```sql
-- Müşterinin adres nesnesini olduğu gibi JSONB olarak al
SELECT 
    id,
    JSON_QUERY(order_payload, '$.shipping_address' WITHOUT ARRAY WRAPPER) AS address_json
FROM orders;
```

---

## 5. SQL/JSON İnşaat (Constructor) Fonksiyonları

SQL tablolarından standart JSON nesneleri üretmek için yeni ANSI fonksiyonları:

```sql
-- Eski: json_build_object('id', id, 'name', name)
-- Yeni SQL Standardı:
SELECT JSON_OBJECT(
    'user_id': id,
    'full_name': first_name || ' ' || last_name,
    'active': is_active,
    'created': now() FORMAT JSON
) AS user_json
FROM users;

-- Dizi Üretimi:
SELECT JSON_ARRAY(10, 20, 'metin', true NULL ON NULL);
```

---

## 6. Performans: `JSON_TABLE` ve İndeksleme Stratejileri

`JSON_TABLE` sorgularının hızlı çalışması için JSONB sütunlarının doğru indekslenmesi gerekir:

### 1. JSONPath Operatör Sınıfı (`jsonb_path_ops`)

Eğer `JSON_EXISTS` veya JSONPath filtreleri kullanıyorsanız, genel GIN yerine `jsonb_path_ops` indeksi diskte %60 daha az yer kaplar ve çok daha hızlı çalışır:

```sql
CREATE INDEX idx_orders_jsonpath ON orders USING gin (order_payload jsonb_path_ops);
```

### 2. İfade İndeksi (Expression Index) ile Birleştirme

Sık filtrelenen bir JSONPath alanı varsa, o alanı `JSON_VALUE` ile doğrudan indeksleyebilirsiniz:

```sql
-- JSON içindeki müşteri kodunu doğrudan B-Tree ile indeksle:
CREATE INDEX idx_orders_cust_id ON orders (
    (JSON_VALUE(order_payload, '$.customer.id' RETURNING text))
);

-- Bu sorgu doğrudan B-Tree Index Scan kullanır:
SELECT * FROM orders 
WHERE JSON_VALUE(order_payload, '$.customer.id') = 'CUST-8812';
```

---

## 7. Gerçek Hayat Senaryosu: Üçüncü Parti Webhook Verilerini Tabloya Aktarma

Ödeme altyapılarından (Stripe, iyzico vb.) gelen ham webhook kayıtlarını sakladığımız bir `raw_webhooks` tablosunu düşünelim. Bu JSON'ı ilişkisel sipariş detay tablosuna dönüştüren gerçekçi ETL sorgusu:

```sql
INSERT INTO normalized_order_items (order_id, sku, product_name, price, quantity)
SELECT 
    w.id AS webhook_id,
    jt.sku,
    jt.product_name,
    jt.price,
    jt.quantity
FROM raw_webhooks w
CROSS JOIN JSON_TABLE(
    w.payload,
    '$.event_data.line_items[*]'
    COLUMNS (
        sku          TEXT          PATH '$.price.product.sku',
        product_name TEXT          PATH '$.description',
        price        NUMERIC(10,2) PATH '$.amount_subtotal' / 100.0,
        quantity     INT           PATH '$.quantity'
    )
) AS jt
WHERE w.event_type = 'checkout.session.completed';
```

Bu yöntem sayesinde uygulama tarafında döngüler yazıp tek tek `INSERT` atmak yerine, PostgreSQL'in güçlü C çekirdeğinde tek bir `INSERT ... SELECT` ile saniyede on binlerce JSON kaydı ilişkisel tablolara sıfır CPU kaybıyla aktarılabilir.
