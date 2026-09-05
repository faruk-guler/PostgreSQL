# Yapay Zeka, Vektör Veritabanı (pgvector) ve RAG Mimarisi

> **Bölüm Kapsamı:** Embedding Vektörleri, HNSW ve IVFFlat İndeksleri, Kosinüs Benzerliği, Hibrit Arama (RRF) ve Python ile RAG Pipeline

---

## 1. Yapay Zeka Dünyasında PostgreSQL ve Vektörler

Büyük Dil Modelleri (LLM'ler; GPT-4, Claude, Llama 3 vb.) metinleri, görselleri ve sesleri anlamlandırabilmek için onları yüzlerce veya binlerce boyuttan oluşan sayısal dizilere dönüştürür. Bu sayısal koordinatlara **Embedding (Vektör Temsili)** denir.

Örneğin, *"veritabanı performansı"* ve *"SQL optimizasyonu"* cümleleri anlamsal olarak birbirine çok yakın olduğu için çok boyutlu uzayda aralarındaki mesafe birbirine son derece yakındır.

```text
Geleneksel Arama (BM25 / FTS) : Kelime eşleşmesine bakar ("araba" ile "otomobil" farklı kelimedir).
Semantik Vektör Arama         : Anlama bakar ("araba" ile "otomobil" vektör uzayında komşudur).
```

### Neden Özel Vektör Veritabanı (Pinecone, Chroma) Yerine PostgreSQL?

Piyasada yalnızca vektör araması yapan özel motorlar bulunsa da modern veri mimarilerinde **PostgreSQL + pgvector** ezici bir üstünlük kazanmıştır:

1. **Tek Veri Tabanı (No Data Duplication):** Müşteri bilgileriniz, faturalarınız ve yapay zeka embeddingleriniz aynı veritabanındadır. Veriyi harici sistemlere senkronize etmek için karmaşık ETL boru hatlarına ihtiyaç kalmaz.
2. **ACID Güvencesi:** Bir ürün silindiğinde veya güncellendiğinde vektörü de aynı transaction içinde atomik olarak güncellenir.
3. **İlişkisel Filtreleme + Vektör Arama (Metadata Filtering):** Yalnızca *"Anlamsal olarak 'spor ayakkabı' ile eşleşen"* değil; *"Son 3 günde stoğa giren, fiyatı 2000 TL altında olan ve Kadıköy şubesinde bulunan"* ürünleri tek bir SQL sorgusunda `JOIN` ve `WHERE` koşuluyla filtreleyebilirsiniz.

---

## 2. pgvector Kurulumu ve `vector` Veri Tipi

`pgvector`, PostgreSQL'e C seviyesinde vektör depolama, mesafe operatörleri ve gelişmiş indeksleme yetenekleri kazandıran açık kaynaklı bir eklentidir.

### Eklentiyi Etkinleştirme

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### Tablo Tanımlama ve Boyutlar

Vektör sütunu oluştururken modelinizin ürettiği boyut sayısını (`dimension`) belirtmeniz gerekir:

- **OpenAI text-embedding-3-small:** 1536 boyut
- **OpenAI text-embedding-3-large:** 3072 boyut
- **BGE / BERT / Nomad Modelleri:** 384, 768 veya 1024 boyut

```sql
CREATE TABLE document_embeddings (
    id BIGSERIAL PRIMARY KEY,
    document_title TEXT NOT NULL,
    chunk_content TEXT NOT NULL,
    metadata JSONB,
    embedding vector(1536), -- OpenAI embedding boyutu
    created_at TIMESTAMPTZ DEFAULT now()
);
```

### Veri Ekleme

Vektörler SQL'e standart bir dizi sözdizimiyle metin olarak iletilir:

```sql
INSERT INTO document_embeddings (document_title, chunk_content, embedding)
VALUES (
    'PostgreSQL Mimarisi',
    'Shared Buffers bellek alanı disk bloklarını RAM üzerinde önbelleğe alır.',
    '[0.0142, -0.0521, 0.0891, ...]' -- 1536 elemanlı sayı dizisi
);
```

---

## 3. Vektör Mesafe Metrikleri ve SQL Operatörleri

İki embedding arasındaki anlamsal benzerliği hesaplamak için üç temel matematiksel metrik kullanılır. `pgvector` bu metrikler için optimize edilmiş özel SQL operatörleri sunar:

| Operatör | Metrik Adı | Matematiksel Karşılığı | Kullanım Senaryosu |
| :--- | :--- | :--- | :--- |
| `<=>` | **Cosine Distance (Kosinüs)** | $1 - \frac{A \cdot B}{\|A\| \|B\|}$ | Metin ve LLM embeddingleri için **en yaygın standart**. |
| `<->` | **L2 Distance (Öklid Mesafesi)** | $\sqrt{\sum (A_i - B_i)^2}$ | Görüntü işleme ve geometrik yakınlık. |
| `<#>` | **Negative Inner Product** | $-(A \cdot B)$ | Normalize edilmiş modellerde maksimum hız. |

> [!TIP]
> **Kosinüs Mesafesi vs Benzerliği:**  
> `<=>` operatörü **mesafeyi** verir (0 = birebir aynı, 1 = dik/alakasız, 2 = zıt).  
> Benzerlik (Similarity) skoru elde etmek için: `1 - (embedding <=> '[...]')` formülü kullanılır.

### En Benzer 5 Parçayı Bulma Sorgusu

```sql
SELECT 
    id,
    document_title,
    chunk_content,
    ROUND((1 - (embedding <=> '[0.0142, -0.0521, 0.0891, ...]'))::numeric, 4) AS similarity_score
FROM document_embeddings
WHERE (metadata->>'category') = 'postgresql-internals'
ORDER BY embedding <=> '[0.0142, -0.0521, 0.0891, ...]'
LIMIT 5;
```

---

## 4. İndeksleme Stratejileri: HNSW vs IVFFlat (Deep Dive)

Tabloda 10.000'den fazla vektör olduğunda her satırı tek tek karşılaştırmak (K-Nearest Neighbors - KNN Seq Scan) kabul edilemez bir CPU yükü oluşturur. Bunun için **Approximate Nearest Neighbor (ANN)** indeksleri kullanılır.

`pgvector` iki farklı ANN indeksi destekler:

```text
1. IVFFlat : Kümeleme (Inverted File Index) tabanlı. Hızlı indekslenir, az RAM tüketir.
2. HNSW    : Çizge (Hierarchical Navigable Small World) tabanlı. Ultra hızlı arama, yüksek doğruluk (recall).
```

### Karşılaştırma Tablosu

| Kriter | IVFFlat | HNSW (Önerilen Standart) |
| :--- | :--- | :--- |
| **Arama Hızı (QPS)** | Orta / Yüksek | **Çok Yüksek** |
| **Doğruluk (Recall %)** | %85 - %95 (Parametrelere bağlı) | **%98 - %99.9** |
| **İndeks İnşa Süresi** | Çok Hızlı | Daha Yavaş |
| **RAM Tüketimi** | Düşük | Yüksek (Graph bellekte tutulmalıdır) |
| **Eğitim (Warmup)** | Veri olmadan kurulamaz (önceden satır gerekir) | Sıfır veriyle kurulabilir, veri eklendikçe büyür |

---

### A. HNSW İndeksi Oluşturma (Modern Üretim Standardı)

HNSW, verileri çok katmanlı bir otoyol ağı gibi birbirine bağlar. Arama en üst katmanda geniş sıçramalarla başlar ve hedef noktaya yaklaştıkça alt katmanlara inerek hassaslaşır.

```sql
CREATE INDEX idx_docs_hnsw_cosine 
ON document_embeddings 
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

#### HNSW Parametreleri

- **`m` (Varsayılan 16):** Her düğümün (node) sahip olacağı maksimum bağlantı sayısı. Arttıkça (örn: 32) arama doğruluğu artar, ancak indeks boyutu büyür.
- **`ef_construction` (Varsayılan 64):** İndeks inşa edilirken taranacak aday listesi derinliği. Değer yükseldikçe (örn: 128) indeks inşası uzar ancak arama kalitesi mükemmelleşir.
- **`hnsw.ef_search` (Sorgu Esnasında):** Arama anında taranacak komşu sayısıdır. Oturum bazında değiştirilebilir:

  ```sql
  -- Çok hassas aramalarda derinliği artır:
  SET hnsw.ef_search = 100;
  ```

---

### B. IVFFlat İndeksi Oluşturma

IVFFlat, vektör uzayını Voronoi hücrelerine (kullanıcı tarafından belirlenen sayıda kümeye) böler.

```sql
-- Tabloda en az 10.000+ satır olmalıdır!
CREATE INDEX idx_docs_ivfflat_cosine 
ON document_embeddings 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

- **`lists` Kuralı:** $Lists \approx \sqrt{Toplam Satır Sayısı}$ (1 milyon satır için `lists = 1000`).
- **Sorgu Parametresi:**

  ```sql
  -- Arama anında kaç kümenin kontrol edileceği (doğruluk vs hız dengesi):
  SET ivfflat.probes = 10;
  ```

---

## 5. Hibrit Arama (Hybrid Search): FTS + Vektör Arama

Gerçek hayat senaryolarında semantik arama tek başına bazen başarısız olur. Örneğin kullanıcı bir hata kodu (`PG-08001`) veya özel bir ürün kodu (`SN-99824X`) aradığında, vektör modeli bu kodun anlamını bilmediği için alakasız sonuçlar getirebilir.

Bu sorunun çözümü: **Hibrit Arama (Keyword Search + Semantic Search)**.

PostgreSQL'in yerleşik **Full Text Search (`tsvector`)** motoru ile **pgvector** aynı tabloda birleştirilir ve **RRF (Reciprocal Rank Fusion)** algoritmasıyla sıralanır:

```sql
-- 1. Tabloya FTS sütunu ekle ve indeksle
ALTER TABLE document_embeddings ADD COLUMN fts_tokens tsvector 
GENERATED ALWAYS AS (to_tsvector('turkish', document_title || ' ' || chunk_content)) STORED;

CREATE INDEX idx_docs_fts ON document_embeddings USING gin (fts_tokens);

-- 2. Hibrit Arama Sorgusu (RRF Algoritması)
WITH 
-- A. Semantik Vektör Arama Sıralaması
semantic_search AS (
    SELECT id, RANK() OVER (ORDER BY embedding <=> '[0.014, -0.052, ...]') AS sem_rank
    FROM document_embeddings
    ORDER BY embedding <=> '[0.014, -0.052, ...]'
    LIMIT 20
),
-- B. Anahtar Kelime (FTS) Arama Sıralaması
keyword_search AS (
    SELECT id, RANK() OVER (ORDER BY ts_rank_cd(fts_tokens, query) DESC) AS kw_rank
    FROM document_embeddings, plainto_tsquery('turkish', 'autovacuum bellek optimizasyonu') query
    WHERE fts_tokens @@ query
    LIMIT 20
)
-- C. Reciprocal Rank Fusion ile Skorları Birleştir (k = 60 sabiti)
SELECT 
    d.id,
    d.document_title,
    d.chunk_content,
    COALESCE(1.0 / (60 + s.sem_rank), 0.0) +
    COALESCE(1.0 / (60 + k.kw_rank), 0.0) AS hybrid_score
FROM document_embeddings d
LEFT JOIN semantic_search s ON d.id = s.id
LEFT JOIN keyword_search k ON d.id = k.id
WHERE s.id IS NOT NULL OR k.id IS NOT NULL
ORDER BY hybrid_score DESC
LIMIT 5;
```

---

## 6. Python ile Uçtan Uca RAG (Retrieval-Augmented Generation) Pipeline'ı

Aşağıdaki örnekte Python (`psycopg 3` ve OpenAI kütüphanesi) kullanılarak PostgreSQL üzerinde çalışan modern bir RAG fonksiyonu yer almaktadır:

```python
import psycopg
from openai import OpenAI

client = OpenAI(api_key="your-openai-api-key")

def get_embedding(text: str) -> list[float]:
    """OpenAI API'sinden 1536 boyutlu embedding vektörü alır."""
    response = client.embeddings.create(
        input=text,
        model="text-embedding-3-small"
    )
    return response.data[0].embedding

def ask_postgresql_rag(user_question: str) -> str:
    # 1. Kullanıcı sorusunu vektöre çevir
    query_vector = get_embedding(user_question)

    # 2. PostgreSQL'den en benzer 3 doküman parçasını çek
    connection_string = "postgresql://faruk:secret@localhost:5432/ragdb"
    
    with psycopg.connect(connection_string) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT chunk_content
                FROM document_embeddings
                ORDER BY embedding <=> %s::vector
                LIMIT 3;
            """, (query_vector,))
            
            rows = cur.fetchall()
            context = "\n---\n".join([row[0] for row in rows])

    # 3. Alınan context'i prompt olarak LLM'e besle
    prompt = f"""
    Sen uzman bir PostgreSQL asistanısın. Yalnızca aşağıdaki bağlamı kullanarak soruyu yanıtla:
    
    BAĞLAM:
    {context}
    
    SORU:
    {user_question}
    """

    completion = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}]
    )
    
    return completion.choices[0].message.content

# Örnek Çalıştırma
if __name__ == "__main__":
    cevap = ask_postgresql_rag("Autovacuum neden tablomu kilitlemez?")
    print(cevap)
```

---

## 7. Üretim Seviyesi Performans ve Boyutlandırma İpuçları

1. **`maintenance_work_mem` Hayatidir:**  
   HNSW indeksi oluştururken PostgreSQL, bağlantı grafını RAM üzerinde kurar. Eğer `maintenance_work_mem` küçük kalırsa (varsayılan 64MB), indeks oluşturma saatler sürebilir.

   ```sql
   SET maintenance_work_mem = '4GB';
   CREATE INDEX ... USING hnsw ...;
   ```

2. **HNSW İndeksi RAM'e Sığmalıdır:**  
   HNSW indeksinin diskten okunması çok yavaştır. `pg_size_pretty(pg_relation_size('idx_docs_hnsw_cosine'))` komutu ile indeks boyutunu ölçün ve `shared_buffers` veya işletim sistemi disk önbelleğinin (RAM) bu boyutu rahatça kapsadığından emin olun.

3. **Maksimum Boyut Sınırı:**  
   PostgreSQL'de standart indeks limitleri nedeniyle bir satırdaki maksimum vektör boyutu varsayılan olarak **2.000 boyuttur** (OpenAI 1536 boyutu sorunsuz desteklenir). 3.072 boyut gibi devasa vektörler için HNSW indeksinde yarı hassasiyetli (Half-precision / float16) eklentiler veya boyut indirgeme teknikleri kullanılır.
