# 06-PostgreSQL-Performance-Tuning

Performans sorunları genellikle kodun kendisine değil (Python/Java), veritabanına atılan sorguya ve veritabanının bu sorguyu nasıl "planladığına" dayanır. PostgreSQL'in sorgu planlayıcısı (Query Planner) çok zekidir ama bazen yardıma ihtiyaç duyar.

---

## 1. Sorgu Analizi (EXPLAIN)

MySQL'deki `EXPLAIN`'den çok daha detaylıdır. Sorgunun nasıl çalıştırılacağını (Execution Plan) gösterir.

### Anahtar Komutlar

- `EXPLAIN`: Sadece tahmini planı gösterir (Sorguyu çalıştırmaz).
- `EXPLAIN ANALYZE`: Sorguyu gerçekten çalıştırır ve gerçek süreyi gösterir.
- `EXPLAIN (ANALYZE, BUFFERS)`: **En önemlisi.** Sorgunun diskten (veya RAM'den) kaç sayfa (Page/Block) okuduğunu gösterir. I/O sorunlarını bulmanın tek yoludur.

### Okuma Tipleri (Scan Types)

1. **Seq Scan (Sequential Scan):** Tablonun *tamamını* baştan sona okur. Küçük tablolarda hızlıdır, büyüklerde felakettir.
2. **Index Scan:** İndeksi kullanarak direkt satıra gider. Hızlıdır.
3. **Index Only Scan:** Veriyi almak için tablonun kendisine (Heap) gitmeye gerek kalmadan, sadece index dosyasından cevabı döner. **En hızlısıdır.**
4. **Bitmap Heap Scan:** Önce indexi tarayıp satırların yerlerini bir haritada (Bitmap) toplar, sonra tabloyu o haritaya göre okur. Çok sayıda satır dönecekse Index Scan'den daha verimlidir.

---

## 2. Indexing Strategies (İndeksleme Stratejileri)

"Her kolona index ekleyelim" yaklaşımı yanlıştır. Indexler yazma hızını (INSERT/UPDATE/DELETE) yavaşlatır.

### a. B-Tree (Varsayılan ve En Yaygın)

Eşitlik (`=`) ve Aralık (`<`, `<=`, `>`, `>=`) sorguları için kullanılır. Sıralama (`ORDER BY`) işlemlerini de hızlandırır.

- Kullanım: ID, Tarih, Email gibi alanlar.

### b. GIN (Generalized Inverted Index)

Karmaşık veri tipleri (JSONB, Array, Full Text Search) için kullanılır.

- Kullanım: "Etiketler dizisinde 'acil' olanları bul" veya "JSON belgesinde 'status: active' olanları bul".

### c. GiST (Generalized Search Tree)

Geometrik veriler (PostGIS) ve KNN (En yakın komşu) aramaları için kullanılır.

- Kullanım: "Konumuma en yakın 5 restoranı bul".

### d. BRIN (Block Range Index)

Çok büyük (Terabyte seviyesinde) ve sıralı giden (Tarih gibi) tablolar için mucizedir.

- Boyutu B-Tree indexin %1'i kadardır.
- Milyarlarca satırlık Log veya IoT sensör verisi tablolarında kullanılır.

### e. Partial Index (Kısmi İndeks)

Tablonun sadece bir kısmını indexler. Disk alanından tasarruf sağlar.

- Örnek: Sadece aktif kullanıcıları indexle (Pasif kullanıcılarla işim yok).

```sql
CREATE INDEX idx_active_users ON users (email) WHERE status = 'active';
```

---

## 3. Autovacuum Tuning

PostgreSQL'in en yanlış anlaşılan sürecidir. **Asla kapatmayın!**
PostgreSQL MVCC (Multi-Version Concurrency Control) kullandığı için, silinen/güncellenen satırlar diskte "ölü" (dead tuple) olarak kalır. Autovacuum bunları temizler.

### Bloat (Şişkinlik) Sorunu

Autovacuum yetişemezse, tablo dosyasının boyutu sürekli büyür ama içindeki faydalı veri artmaz. Buna "Bloat" denir.

### Tuning Parametreleri (postgresql.conf)

Varsayılan ayarlar (özellikle büyük veritabanları için) çok yavaştır.

```ini
# Varsayılan: Autovacuum, tablonun %20'si değişince tetiklenir.
# Büyük tablo (100 Milyon satır) için bu 20 Milyon demektir -> Çok geç!
autovacuum_vacuum_scale_factor = 0.05  # %5'e düşürün (Daha sık, daha küçük temizlik)

# Varsayılan: Temizlik maliyeti limiti (200). Çok düşük.
# Modern SSD diskler için arttırın ki işlem yarıda kesilip durmasın.
autovacuum_vacuum_cost_limit = 2000

# Varsayılan: Naptime (1dk). Birden fazla DB varsa azaltılabilir.
autovacuum_naptime = 1min
```

> [!TIP]
> Tablo bazında özel ayar yapabilirsiniz. Çok güncellenen `orders` tablosu için daha agresif bir vakum ayarı:
> `ALTER TABLE orders SET (autovacuum_vacuum_scale_factor = 0.01);`

---

## 4. Connection & Memory Tuning

### a. Bağlantı Limitleri (Connection Limits)

PostgreSQL process-based olduğu için her bağlantı pahalıdır.

- **`max_connections` (Default: 100):** Fiziksel sunucuda CPU çekirdek sayısı x 4'ü geçmemeye çalışın. 1000+ bağlantı gerekiyorsa **MUTLAKA PgBouncer** kullanın.
- **`superuser_reserved_connections` (Default: 3):** Acil durumlar için kenara ayrılan bağlantı sayısı. Bunu 5-10 yapın ki `max_connections` dolsa bile siz bağlanıp sorunu çözebilin.

### b. Checkpoint Tuning (I/O Dengeleme)

Varsayılan ayarlar, WAL dosyaları dolduğunda (max_wal_size) aniden tüm disk I/O'sunu tüketebilir (I/O Spike). Bunu zamana yaymak gerekir.

**Amaç:** Checkpoint işlemini o kadar yavaş yap ki, bir sonraki checkpoint zamanı gelene kadar disk I/O'su sürekli ama düşük seviyede olsun (Smooth I/O).

```ini
# Checkpoint daha seyrek olsun (default 5min)
checkpoint_timeout = 30min 

# İşlemi son ana bırakma, %90'lık zamana yay (PG 14+ default 0.9)
checkpoint_completion_target = 0.9

# Disk alanı varsa arttırın (Checkpoint sıklığını azaltır)
max_wal_size = 4GB 
min_wal_size = 1GB

# Checkpoint warning loglarına dikkat edin!
# "checkpoints are occurring too frequently" hatası alıyorsanız max_wal_size arttırın.
```

---

## 5. Query Optimizer Internals (Sorgu Planlayıcı)

PostgreSQL "Cost-Based Optimizer" (CBO) kullanır. Her potansiyel plan için bir maliyet hesaplar ve en ucuzunu seçer.

### a. Cost Parametreleri

Optimizer'ın kararlarını bu sabitler belirler:

```ini
# Disk I/O Maliyetleri
seq_page_cost = 1.0        # Sıralı okuma (HDD için referans)
random_page_cost = 4.0     # Rastgele okuma (HDD'de 4x daha pahalı)
# SSD Kullanıyorsanız: random_page_cost = 1.1 yapın!

# CPU Maliyetleri
cpu_tuple_cost = 0.01      # Bir satırı işleme
cpu_index_tuple_cost = 0.005 # Index satırını işleme
cpu_operator_cost = 0.0025 # + - * / gibi işlem maliyeti
```

### b. GEQO (Genetic Query Optimizer)

Çok fazla tabloyu join ediyorsanız (varsayılan: 12+), PostgreSQL tüm kombinasyonları denemek yerine Genetik Algoritma kullanır.

```ini
geqo = on
geqo_threshold = 12
```

### c. Planı Manipüle Etmek (Hata Ayıklama)

Optimizer yanlış karar veriyorsa (örn: Index varken Seq Scan yapıyorsa), geçici olarak bazı yöntemleri kapatabilirsiniz:

```sql
SET enable_seqscan = off;  -- Seq scan yapmayı "çok pahalı" hale getirir
SET enable_nestloop = off; -- Nested loop join sevmez
-- Sorguyu çalıştır, planı gör, sonra tekrar aç!
```

---

## 6. Cache Warming (pg_prewarm)

Sunucu yeniden başladığında Shared Buffers (RAM) boştur ve ilk sorgular yavaştır. `pg_prewarm` ile tabloları RAM'e yükleyebilirsiniz.

```sql
CREATE EXTENSION pg_prewarm;

-- Tabloyu belleğe yükle
SELECT pg_prewarm('products');

-- Otomatik yükleme için postgresql.conf:
# shared_preload_libraries = 'pg_prewarm'
# pg_prewarm.autoprewarm = on
```

---

## 6. Parallel Query (Çok Çekirdekli Sorgu Gücü)

PostgreSQL 10+ ile gelen bu özellik, tek bir sorguyu birden fazla CPU çekirdeğinde paralel çalıştırarak **3-10x hızlandırma** sağlayabilir.

### Nasıl Çalışır?

Büyük bir tablo taraması (Seq Scan) veya JOIN işlemi, birden fazla "worker" sürecine bölünür. Her worker, tablonun bir kısmını işler ve sonuçlar birleştirilir.

### Konfigürasyon (postgresql.conf)

```ini
# Sistem genelinde toplam paralel worker sayısı
max_parallel_workers = 8  # CPU çekirdek sayınızın %50-75'i

# Tek bir sorgu için maksimum worker sayısı
max_parallel_workers_per_gather = 4  # 2-4 arası ideal

# Paralel işlem başlatma maliyeti (düşürürseniz daha sık kullanılır)
parallel_setup_cost = 1000  # Varsayılan: 1000
parallel_tuple_cost = 0.1   # Varsayılan: 0.1

# Paralel işlem için minimum tablo boyutu
min_parallel_table_scan_size = 8MB   # Varsayılan: 8MB
min_parallel_index_scan_size = 512kB # Varsayılan: 512kB
```

### EXPLAIN ile Kontrol

```sql
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM large_table WHERE status = 'active';

-- Çıktıda "Gather" ve "Parallel Seq Scan" görürseniz paralel çalıştı:
-- Gather (cost=... rows=... workers=4)
--   Workers Planned: 4
--   Workers Launched: 4
--   -> Parallel Seq Scan on large_table
```

### Limitasyonlar

Parallel query **her zaman** kullanılmaz. Şu durumlarda devre dışı kalır:

- Transaction içinde `SERIALIZABLE` isolation level kullanılıyorsa
- `CURSOR` kullanılıyorsa
- `FOR UPDATE/SHARE` lock varsa
- Tablo çok küçükse (min_parallel_table_scan_size altında)

> [!TIP]
> OLTP (çok kısa sorgular) sistemlerde paralel query gereksizdir. Sadece OLAP (analitik, uzun süren) sorgularda aktif edin. `max_parallel_workers_per_gather = 0` yaparak tablo bazında devre dışı bırakabilirsiniz.
