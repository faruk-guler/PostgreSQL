# PostgreSQL Hibrit Arama Mimarisi (Hybrid Search: FTS + Trigram + pgvector & RRF)

Geleneksel arama sistemlerinde yalnızca anahtar kelime eşleşmesine (lexical search) odaklanılırken, modern üretken yapay zekâ ve arama sistemlerinde anlamsal benzerlik (semantic search) ön plana çıkmıştır. Ancak tek başına anlamsal vektör araması; ürün kodları (SKU), model numaraları, marka isimleri ve tam kelime eşleşmelerinde yetersiz kalır.

Bu bölümde; PostgreSQL'in yerel **Full-Text Search (FTS)** yeteneklerini, **Trigram (`pg_trgm`)** bulanık aramasını ve **`pgvector`** anlamsal aramasını tek bir potada eriten **Reciprocal Rank Fusion (RRF)** mimarisi uçtan uca incelenmektedir. Harici bir Elasticsearch veya Pinecone kümesine ihtiyaç duymadan, saf PostgreSQL üzerinde kurumsal bir hibrit arama motoru inşa edilecektir.

---

## 1. Leksikal Arama vs. Semantik Arama: Neden Hibrit?

| Kriter | Leksikal Arama (FTS + Trigram) | Semantik Arama (pgvector / Embeddings) |
| :--- | :--- | :--- |
| **Çalışma Prensibi** | Karakter, kök ve kelime sıklığı (TF-IDF / BM25) | Yüksek boyutlu uzayda vektör mesafesi (Cosine, L2) |
| **Güçlü Olduğu Alan** | SKU kodları (`PROD-9812`), özel isimler, tam alıntılar | Kavramsal benzerlik, eşanlamlılar, dil bariyerini aşma |
| **Zayıf Olduğu Alan** | Yazım yanlışı toleransı düşüktür, kavramı anlamaz | Belirli bir kelimenin varlığını garanti edemez |
| **İndeks Türü** | GIN, GiST | HNSW, IVFFlat |

Hibrit arama, her iki yöntemin getirdiği sonuçları birleştirerek hem kavramsal doğruluğu hem de kesin terim eşleşmesini en yüksek sıralama skoruyla kullanıcıya sunar.

---

## 2. PostgreSQL Yerel Full-Text Search (FTS) Mimarisi

PostgreSQL'de metin araması iki temel veri türüne dayanır:
1. `tsvector`: Ayıklanmış, normalize edilmiş (stemmed) ve tekrarlardan arındırılmış sözlük birimleri (lexemes) listesi.
2. `tsquery`: Mantıksal operatörler (`&`, `|`, `!`, `<->`) içeren arama sorgusu.

### 2.1. Türkçe Dil ve Metin Normalizasyonu

Türkçe aramalarda noktalama işaretleri, büyük/küçük harf duyarlılığı ve eklerin temizlenmesi için `unaccent` ve `turkish` sözlükleri birlikte yapılandırılmalıdır:

```sql
-- Gerekli eklentilerin aktifleştirilmesi
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

-- Türkçe için normalize edilmiş tsvector örneği
SELECT to_tsvector('turkish', unaccent('PostgreSQL yüksek performanslı ilişkisel bir veritabanıdır'));
-- Sonuç: 'bir':5 'iliskisel':4 'performans':3 'postgresql':1 'veritabani':6 'yuksek':2
```

### 2.2. Ağırlıklandırma (Weights)

Başlık, özet ve içerik alanlarına farklı önem dereceleri (A: 1.0, B: 0.4, C: 0.2, D: 0.1) atanarak arama alaka düzeyi (ranking) optimize edilir:

```sql
SELECT 
    setweight(to_tsvector('turkish', 'PostgreSQL 16 Mimarisi'), 'A') ||
    setweight(to_tsvector('turkish', 'Derinlemesine iç yapı ve hafıza yönetimi rehberi'), 'B') AS arama_vektoru;
```

---

## 3. Trigram (`pg_trgm`) ile Yazım Yanlışı Toleransı (Fuzzy Search)

Kullanıcı arama kutusuna `postgre` yerine `posgreql` veya `postgreesql` yazdığında FTS eşleşme bulamaz. Trigram analizi, kelimeleri 3 karakterlik kayan pencerelere bölerek benzerlik katsayısı (similarity) hesaplar:

```sql
-- Benzerlik skoru (0.0 ile 1.0 arası)
SELECT similarity('postgresql', 'posgreql');
-- Sonuç: ~0.6

-- GIN Trigram indeksi ile hızlı filtreleme
CREATE INDEX idx_urunler_ad_trgm ON urunler USING gin (ad gin_trgm_ops);
```

---

## 4. Reciprocal Rank Fusion (RRF) Algoritması

FTS ve pgvector skorları farklı matematiksel aralıklara sahiptir:
* FTS `ts_rank`: Genellikle `0.0` ile `1.0` arasında bağıl bir değerdir ancak mutlak değildir.
* Vektör Cosine Distance: `0.0` (özdeş) ile `2.0` (ters yönlü) arasındadır.

Farklı ölçeklerdeki skorları doğrudan çarpmak veya toplamak yanlı sonuçlar doğurur. **RRF (Reciprocal Rank Fusion)**, ham puanlar yerine dokümanın her iki listedeki **sıralama derecesini (rank)** normalize eder.

### RRF Formülü:
$$RRF(d) = \sum_{m \in M} \frac{1}{k + r_m(d)}$$

* $M$: Arama yöntemleri kümesi (Leksikal + Semantik).
* $r_m(d)$: Dokümanın $m$ yöntemindeki sıralama pozisyonu ($1, 2, 3...$).
* $k$: Sabit yumuşatma faktörü (Endüstri standardı genellikle $k = 60$'tır).

---

## 5. Uçtan Uca Hibrit Arama Motoru Uygulaması

### 5.1. Şema Tasarımı

```sql
DROP TABLE IF EXISTS makaleler CASCADE;

CREATE TABLE makaleler (
    id BIGSERIAL PRIMARY KEY,
    baslik TEXT NOT NULL,
    icerik TEXT NOT NULL,
    sku_kodu VARCHAR(50),
    -- FTS için üretilmiş otomatik tsvector sütunu
    fts_vektor tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('turkish', unaccent(coalesce(baslik, ''))), 'A') ||
        setweight(to_tsvector('turkish', unaccent(coalesce(icerik, ''))), 'B')
    ) STORED,
    -- 1536 boyutlu OpenAI/text-embedding-3-small veya benzeri model çıktısı
    embedding vector(1536)
);

-- İndekslerin Oluşturulması
CREATE INDEX idx_makaleler_fts ON makaleler USING gin (fts_vektor);
CREATE INDEX idx_makaleler_trgm_baslik ON makaleler USING gin (baslik gin_trgm_ops);
CREATE INDEX idx_makaleler_embedding_hnsw ON makaleler USING hnsw (embedding vector_cosine_ops) 
WITH (m = 16, ef_construction = 64);
```

### 5.2. Örnek Veri Girişi

```sql
INSERT INTO makaleler (baslik, icerik, sku_kodu, embedding) VALUES
(
    'PostgreSQL İndeksleme Stratejileri', 
    'B-Tree, GIN, BRIN indekslerinin derinlemesine incelenmesi ve optimizasyon yöntemleri.', 
    'DOC-PG-001',
    (SELECT array_agg(random())::vector(1536) FROM generate_series(1, 1536))
),
(
    'Veritabanı Kilit Yönetimi ve MVCC', 
    'Deadlock tespiti, transaction izolasyon seviyeleri ve Serializable Snapshot Isolation.', 
    'DOC-PG-002',
    (SELECT array_agg(random())::vector(1536) FROM generate_series(1, 1536))
),
(
    'Yapay Zekâ Destekli Vektör Veritabanları', 
    'pgvector eklentisi ile RAG sistemleri kurma ve anlamsal doküman benzerliği.', 
    'DOC-AI-003',
    (SELECT array_agg(random())::vector(1536) FROM generate_series(1, 1536))
);
```

### 5.3. RRF ile Birleşik Hibrit Arama Sorgusu

Aşağıdaki sorgu, verilen bir metin sorgusu (`q_text`) ve vektör embedding'i (`q_vector`) için iki bağımsız CTE çalıştırır, sıralamaları çıkarır ve RRF formülüyle nihai tek bir skor üretir:

```sql
WITH params AS (
    SELECT 
        'indeksleme optimizasyon'::text AS arama_metni,
        (SELECT array_agg(random())::vector(1536) FROM generate_series(1, 1536)) AS arama_vektoru,
        60 AS k_faktoru,
        20 AS limit_adeti
),
-- 1. Leksikal Arama (FTS + Trigram)
lexical_search AS (
    SELECT 
        m.id,
        ROW_NUMBER() OVER (
            ORDER BY ts_rank_cd(m.fts_vektor, plainto_tsquery('turkish', unaccent(p.arama_metni))) DESC
        ) AS rank_lexical
    FROM makaleler m, params p
    WHERE m.fts_vektor @@ plainto_tsquery('turkish', unaccent(p.arama_metni))
       OR m.baslik % p.arama_metni
    LIMIT 50
),
-- 2. Semantik Arama (pgvector HNSW)
semantic_search AS (
    SELECT 
        m.id,
        ROW_NUMBER() OVER (
            ORDER BY m.embedding <=> p.arama_vektoru ASC
        ) AS rank_semantic
    FROM makaleler m, params p
    ORDER BY m.embedding <=> p.arama_vektoru ASC
    LIMIT 50
)
-- 3. RRF Skorlarının Birleştirilmesi
SELECT 
    m.id,
    m.baslik,
    m.sku_kodu,
    COALESCE(1.0 / (p.k_faktoru + l.rank_lexical), 0.0) AS lexical_score,
    COALESCE(1.0 / (p.k_faktoru + s.rank_semantic), 0.0) AS semantic_score,
    (
        COALESCE(1.0 / (p.k_faktoru + l.rank_lexical), 0.0) +
        COALESCE(1.0 / (p.k_faktoru + s.rank_semantic), 0.0)
    ) AS rrf_score
FROM makaleler m
CROSS JOIN params p
LEFT JOIN lexical_search l ON m.id = l.id
LEFT JOIN semantic_search s ON m.id = s.id
WHERE l.id IS NOT NULL OR s.id IS NOT NULL
ORDER BY rrf_score DESC
LIMIT 10;
```

---

## 6. Üretim Ortamı İçin Hibrit Fonksiyon Tasarımı

Uygulama katmanından doğrudan çağrılabilecek, parametrik ve optimize edilmiş bir PL/pgSQL fonksiyonu:

```sql
CREATE OR REPLACE FUNCTION sp_hibrit_arama(
    p_sorgu_metni TEXT,
    p_sorgu_vektor vector(1536),
    p_limit INT DEFAULT 10,
    p_k INT DEFAULT 60
)
RETURNS TABLE (
    makale_id BIGINT,
    baslik TEXT,
    rrf_skor NUMERIC
) 
LANGUAGE sql
STABLE
AS $$
    WITH lexical AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank_cd(fts_vektor, websearch_to_tsquery('turkish', unaccent(p_sorgu_metni))) DESC) AS r_lex
        FROM makaleler
        WHERE fts_vektor @@ websearch_to_tsquery('turkish', unaccent(p_sorgu_metni))
        LIMIT 40
    ),
    semantic AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> p_sorgu_vektor ASC) AS r_sem
        FROM makaleler
        ORDER BY embedding <=> p_sorgu_vektor ASC
        LIMIT 40
    )
    SELECT 
        m.id,
        m.baslik,
        ROUND(
            (COALESCE(1.0 / (p_k + l.r_lex), 0.0) + COALESCE(1.0 / (p_k + s.r_sem), 0.0))::numeric, 
            6
        ) AS rrf_skor
    FROM makaleler m
    LEFT JOIN lexical l ON m.id = l.id
    LEFT JOIN semantic s ON m.id = s.id
    WHERE l.id IS NOT NULL OR s.id IS NOT NULL
    ORDER BY rrf_skor DESC
    LIMIT p_limit;
$$;
```

---

## 7. Performans ve Ölçekleme Notları

1. **HNSW `ef_search` Ayarı:** Vektör aramasında recall (isabet oranı) ve gecikme (latency) dengesi için oturum seviyesinde `SET hnsw.ef_search = 100;` değeri optimize edilmelidir.
2. **`websearch_to_tsquery` Avantajı:** Kullanıcı girdisindeki tırnak işareti (`"kelime grubu"`), `OR` ve `-kelime` (hariç tutma) sözdizimini otomatik olarak geçerli bir `tsquery` yapısına dönüştürür; sözdizimi hatalarını engeller.
3. **Bellek Tüketimi:** GIN indeksleri bellek dostudur ancak HNSW vektör indeksleri tamamen RAM üzerinde (RAM > İndeks Boyutu) tutulmalıdır.
