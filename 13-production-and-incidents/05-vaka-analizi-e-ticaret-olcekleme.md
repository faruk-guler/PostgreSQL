# Capstone 2: E-Ticaret Ölçekleme ve AI Arama (Scale & Search)

> **Bölüm Kapsamı:** Milyonlarca siparişin aktığı bir E-Ticaret sistemini yatayda (Read Replica) ve dikeyde (Partitioning) ölçekleme ve pgvector ile modern AI destekli (Benzer Ürün Bul) arama motoru kurulumu.

---

Klasik bir yapıda `orders` tablosuna milyonlarca kayıt girdiğinde, veritabanı şişer (table bloat) ve raporlama sorguları yavaşlar. 

## 1. Siparişleri Tarihe Göre Bölmek (Table Partitioning)

`orders` tablosunu dev bir monolith olarak tutmak yerine aylık parçalara (Partition) bölerek, son ayın (sıcak veri) küçük ve hızlı olmasını sağlıyoruz.

```sql
-- Ana (Parent) Tabloyu Partitioned olarak oluştur
CREATE TABLE orders (
    id BIGSERIAL,
    customer_id BIGINT,
    total_amount NUMERIC(10, 2),
    status VARCHAR(20),
    created_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (created_at);

-- 2026 Ocak Ayı Tablosu (Sadece Ocak ayındaki kayıtlar buraya düşer)
CREATE TABLE orders_2026_01 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- 2026 Şubat Ayı Tablosu
CREATE TABLE orders_2026_02 PARTITION OF orders
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
```

**Avantajı:** `SELECT * FROM orders WHERE created_at >= '2026-02-10'` dediğinizde PostgreSQL akıllıca davranıp (Partition Pruning) Ocak tablosuna hiç bakmaz, sadece Şubat tablosunu okur.

## 2. CQRS - Yük Dağıtımı (Read Replica Mimarisi)

Uygulamanız saniyede 10.000 sipariş alırken, aynı veritabanında patronun "Aylık satış raporunu" çekmesi sistemi kilitler. Okuma (Read) ve Yazma (Write) işlemleri ayrılmalıdır (CQRS Pattern).

- **Master (Primary) Sunucu:** Sadece `INSERT`, `UPDATE`, `DELETE` işlemleri yapar.
- **Replica (Standby) Sunucu:** Primary'den Stream Replication ile saniyelik güncellenir. Raporlar, `SELECT` sorguları, kullanıcı profil görüntüleme işlemleri buraya yönlendirilir.

**Yazılım Tarafında (Örn: Node.js / Java):**
```javascript
// Master Bağlantısı (Yazma işlemleri)
const masterDB = new Pool({ host: 'db-master.internal' });
await masterDB.query("INSERT INTO orders...");

// Replica Bağlantısı (Okuma işlemleri)
const replicaDB = new Pool({ host: 'db-replica.internal' });
await replicaDB.query("SELECT * FROM orders WHERE customer_id = $1");
```

## 3. "Buna Benzer Ürünler" - pgvector ve Yapay Zeka Entegrasyonu

E-Ticaret sitelerinde en çok kâr getiren yer "Bunu alanlar şunu da aldı" veya "Benzer Ürünler" kısmıdır. Eski LIKE '%kırmızı tişört%' sorguları yerine vektörel arama (Semantic Search) kullanılır.

**Adım 1: Eklentiyi Açın ve Tabloyu Düzenleyin**
```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200),
    description TEXT,
    category VARCHAR(50),
    embedding vector(1536) -- OpenAI embedding vektörü boyutu
);
```

**Adım 2: Hızlı Arama için HNSW İndeksi Oluşturun**
```sql
CREATE INDEX idx_products_embedding ON products 
USING hnsw (embedding vector_cosine_ops);
```

**Adım 3: Benzer Ürünleri Bulma (Cosine Similarity)**
Kullanıcı bir "Kırmızı Desenli Kışlık Kazak" inceliyor. Bu ürünün Embedding vektörünü alıp, ona en yakın 5 ürünü (`<=>` operatörü ile) anında getiriyoruz:
```sql
-- $1 = İncelenen ürünün vektörü
SELECT name, description, 1 - (embedding <=> $1) AS similarity_score
FROM products
ORDER BY embedding <=> $1
LIMIT 5;
```

Bu yapı sayesinde, kelimeler eşleşmese bile anlam olarak benzeyen (Örn: Kazak - Hırka) ürünleri mili-saniyeler içinde müşteriye önerebilirsiniz. 
