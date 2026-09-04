# SaaS ve Çok Kiracılı (Multi-Tenancy) Mimari Desenleri

> **Bölüm Kapsamı:** Database-per-tenant vs Schema-per-tenant vs Shared Schema (RLS), Otomatik Kiracı İzolasyonu, Session Variables ve Bağlantı Havuzu Güvenliği

---

## 1. SaaS Dünyasında Çok Kiracılı (Multi-Tenant) Mimari Nedir?

Bir SaaS (Software as a Service) uygulaması geliştirirken en temel mimari karar, farklı müşterilerin (kiracıların / tenants) verilerinin veritabanında nasıl ayrılacağıdır.

Yanlış bir mimari karar:

- Farklı müşterilerin verilerinin birbirine sızmasına (büyük güvenlik ve KVKK/GDPR skandalı),
- Bakım maliyetlerinin ve migration sürelerinin kontrol edilemez şekilde patlamasına,
- "Noisy Neighbor" (Tek bir büyük müşterinin diğer tüm müşterileri yavaşlatması) problemine yol açar.

---

## 2. Üç Temel Multi-Tenancy Modelinin Kıyaslaması

PostgreSQL'de bir SaaS mimarisi inşa ederken 3 temel yaklaşım mevcuttur:

```text
1. Database-per-Tenant : Her müşteri için tamamen ayrı bir veritabanı (Örn: db_tenant_a, db_tenant_b)
2. Schema-per-Tenant   : Tek bir veritabanı içinde her müşteri için ayrı bir şema (Örn: schema_tenant_a)
3. Shared Schema (RLS) : Tek bir veritabanı ve tek bir şema; satır bazında Row-Level Security ile filtreleme
```

### Karşılaştırma Tablosu

| Kriter | 1. Database-per-Tenant | 2. Schema-per-Tenant | 3. Shared Schema + RLS (Önerilen) |
| :--- | :--- | :--- | :--- |
| **Veri İzolasyonu** | En Yüksek (Fiziksel) | Yüksek (Mantıksal) | **Çok Yüksek (Çekirdek Düzeyinde)** |
| **Altyapı Maliyeti** | Çok Yüksek (Her DB RAM harcar) | Orta | **En Düşük (Maksimum Kaynak Verimi)** |
| **Migration Kolaylığı** | Kabus (10.000 DB'ye şema güncelleme) | Zor (10.000 şema) | **En Kolay (Tek bir `ALTER TABLE`)** |
| **Ölçeklenebilirlik** | 100 - 500 Müşteriye kadar | 500 - 2.000 Müşteriye kadar | **100.000+ Müşteri** |
| **Cross-Tenant Raporlama** | Çok Zor (FDW gerekir) | Zor | **Çok Kolay (Doğrudan SQL Analizi)** |

> [!IMPORTANT]
> **Modern SaaS Kararı:**  
> Özel regülasyonlar (Sağlık, Bankacılık) gerektirmedikçe, modern bulut mimarilerinde endüstri standardı **Shared Schema + Row-Level Security (RLS)** modelidir.

---

## 3. Row-Level Security (RLS) ile Otomatik Kiracı İzolasyonu

Row-Level Security (RLS), PostgreSQL çekirdeğinde çalışan bir güvenlik motorudur. Bir tabloya RLS politikası uygulandığında, uygulama ne kadar dikkatsiz SQL yazarsa yazsın (`SELECT * FROM orders` dese dahi), veritabanı motoru sorguya gizlice `WHERE tenant_id = ...` filtresi enjekte eder.

### Adım Adım Kurulum

#### 1. Tabloyu Oluşturma

Her kiracıya ait tabloda mutlaka bir `tenant_id` sütunu bulunmalıdır:

```sql
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

#### 2. RLS'i Etkinleştirme ve Zorunlu Kılma

Varsayılan olarak tablolar RLS korumasına sahip değildir:

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Tablo sahibinin (owner) dahi kurallara uymasını zorunlu kıl:
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

#### 3. İzolasyon Politikasını (Policy) Tanımlama

Kiracının kimliğini bir PostgreSQL oturum parametresinden (`current_setting`) okuyalım:

```sql
CREATE POLICY tenant_isolation_policy ON orders
AS RESTRICTIVE
FOR ALL
TO app_user -- Uygulamanın bağlandığı veritabanı rolü
USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
```

- **`USING`:** `SELECT`, `UPDATE`, `DELETE` işlemlerinde hangi satırların okunabileceğini sınırlar.
- **`WITH CHECK`:** `INSERT` veya `UPDATE` işlemlerinde başka bir kiracıya ait veri yazılmasını fiziksel olarak engeller.

---

## 4. Uygulama Seviyesinde Oturum Yönetimi (Session Variables)

Uygulamanız (Node.js, Python, Go, Java vb.) veritabanından bir bağlantı aldığında, transaction'ın başında aktif kiracının kimliğini ayarlar:

```sql
BEGIN;

-- Aktif kiracının ID'sini yerel oturuma ata (Sadece bu transaction için geçerlidir):
SET LOCAL app.current_tenant_id = 'c8b418a0-97b1-4f12-9214-e274a2b16d8a';

-- Artık geliştirici "WHERE tenant_id = ..." yazmayı unutsa bile:
SELECT * FROM orders; -- YALNIZCA o kiracının siparişleri döner!

INSERT INTO orders (tenant_id, customer_name, total_amount) 
VALUES ('c8b418a0-97b1-4f12-9214-e274a2b16d8a', 'Ahmet Yılmaz', 750.00); -- Başarılı

-- Başka bir kiracının ID'si ile eklemeye çalışırsa RLS hata fırlatır:
INSERT INTO orders (tenant_id, customer_name, total_amount) 
VALUES ('99999999-9999-9999-9999-999999999999', 'Hileli Kayıt', 10.00);
-- ERROR: new row violates row-level security policy for table "orders"

COMMIT;
```

### ⚠️ PgBouncer ve Bağlantı Havuzu (Connection Pool) Tuzağı

Bağlantı havuzu (PgBouncer) `transaction pooling` modunda çalışıyorsa, bir transaction bittiğinde bağlantı başka bir kiracıya verilebilir.

- **KESİNLİKLE YAPMAYIN:** `SET app.current_tenant_id = '...'` (Oturum kalıcı olur, sonraki istek önceki müşterinin verisini görebilir!).
- **MUTLAKA KULLANIN:** `SET LOCAL app.current_tenant_id = '...'` (`SET LOCAL` ifadesi sadece o anki `BEGIN ... COMMIT` bloğunda yaşar ve transaction tamamlandığında otomatik silinir).

---

## 5. Çok Kiracılı Mimaride İndeksleme Stratejileri

RLS her sorguya arka planda `tenant_id` filtresi eklediği için indeksleme tasarımı hayati önem taşır:

### 1. Kompozit (Bileşik) İndeks Kuralı

Tek başına `tenant_id` üzerine indeks atmak genellikle yetersizdir. Müşteri sorguları daima tarih, durum veya müşteri adına göre filtrelenir.

```sql
-- Kötü:
CREATE INDEX idx_orders_tenant ON orders (tenant_id);
CREATE INDEX idx_orders_date ON orders (created_at);

-- Mükemmel (Composite B-Tree):
-- Sol baştaki sütun DAİMA tenant_id olmalıdır!
CREATE INDEX idx_orders_tenant_created 
ON orders (tenant_id, created_at DESC);

CREATE INDEX idx_orders_tenant_status 
ON orders (tenant_id, status) 
WHERE status != 'completed'; -- Partial Composite Index
```

---

## 6. "Noisy Neighbor" Problemi ve Hibrit Sharding

Bir SaaS sisteminde 10.000 küçük müşteri varken, sisteme Trendyol veya Amazon gibi devasa bir kurumsal müşteri ("Balina Kiracı") gelebilir. Bu dev kiracının verisi diğer tüm müşterilerin disk önbelleğini (RAM) işgal edebilir.

### Çözüm: Declarative Partitioning ile Büyük Kiracıyı Ayırma

PostgreSQL'in deklaratif bölümlendirme (List Partitioning) yeteneği ile dev kiracıyı fiziksel olarak kendi bağımsız tablosuna taşıyabilirsiniz:

```sql
-- Ana tabloyu tenant_id'ye göre List Partitioning yap:
CREATE TABLE enterprise_orders (
    id BIGSERIAL,
    tenant_id UUID NOT NULL,
    order_data JSONB,
    PRIMARY KEY (id, tenant_id)
) PARTITION BY LIST (tenant_id);

-- Standart küçük müşteriler için ortak partition:
CREATE TABLE orders_shared_tenants 
PARTITION OF enterprise_orders DEFAULT;

-- Dev müşteri (VIP Tenant) için tamamen ayrı fiziksel partition:
CREATE TABLE orders_whale_client 
PARTITION OF enterprise_orders 
FOR VALUES IN ('a1b2c3d4-0000-0000-0000-000000000001');

-- Bu VIP partition'ı isterseniz tamamen farklı ve ultra hızlı bir NVMe Tablespace'e taşıyabilirsiniz!
```

---

## 7. Python (psycopg3) ile Otomatik Tenant Middleware Enjeksiyonu

Uygulama kodunda her fonksiyonun içine elle `SET LOCAL` yazmak hataya davetiyedir. Bunun yerine veritabanı katmanında bir context manager / middleware kullanılır:

```python
import psycopg
from contextlib import contextmanager

class TenantDatabase:
    def __init__(self, dsn: str):
        self.pool = psycopg.ConnectionPool(dsn, min_size=5, max_size=20)

    @contextmanager
    def tenant_session(self, tenant_id: str):
        with self.pool.connection() as conn:
            with conn.transaction():
                with conn.cursor() as cur:
                    # Transaction başında tenant'ı enjekte et
                    cur.execute("SET LOCAL app.current_tenant_id = %s;", (tenant_id,))
                    yield cur
                # Transaction bitince otomatik commit olur ve SET LOCAL temizlenir

# Kullanım Örneği
db = TenantDatabase("postgresql://app_user:pass@localhost:5432/saas_db")

# Faruk Ltd. (Tenant 1) için sorgu
with db.tenant_session("c8b418a0-97b1-4f12-9214-e274a2b16d8a") as cursor:
    cursor.execute("SELECT id, customer_name FROM orders;")
    print("Müşteri 1 Siparişleri:", cursor.fetchall())

# Sistem yöneticisi veya yazılımcı filtre yazmayı unutsa dahi başka kiracının verisi asla sızmaz!
```

---

## 8. Kiracı Verisini Silme (Offboarding / GDPR Unutulma Hakkı)

Bir müşteri aboneliğini sonlandırdığında tek bir SQL ile tüm verilerini ilişkisel bütünlük içinde temizleyebilirsiniz:

```sql
-- Cascade kısıtlaması sayesinde tenant silindiğinde 
-- o tenant'a ait orders, invoices, logs tablolarındaki tüm satırlar atomik olarak silinir:
DELETE FROM tenants WHERE id = 'c8b418a0-97b1-4f12-9214-e274a2b16d8a';
```
