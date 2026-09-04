# Genel Bakış ve İç Mimari

> **Bölüm Kapsamı:** PostgreSQL'e Kapsamlı Giriş ve İç Mimari

---

## Bölüm 1: PostgreSQL Nedir?

### 1.1. Temel Tanım

**PostgreSQL** (genellikle "Postgres" olarak kısaltılır), dünyanın en gelişmiş **açık kaynaklı ilişkisel veritabanı yönetim sistemi** (RDBMS) olarak kabul edilir.

PostgreSQL, verileri **tablolar** halinde saklayan, **SQL** (Structured Query Language) ile sorgulanan ve **ACID** garantisi veren bir veritabanıdır. Ancak sadece klasik bir ilişkisel veritabanı değildir - aynı zamanda NoSQL yetenekleri (JSONB), coğrafi veri desteği (PostGIS) ve çok daha fazlasını sunar.

### 1.2. Tarihçe

| Yıl | Olay |
| :---------- | :-------------------------------------------------------- |
| **1986**  | Berkeley Üniversitesi'nde POSTGRES projesi başladı     |
| **1996**  | SQL desteği eklendi, PostgreSQL adını aldı             |
| **2005**  | Windows desteği eklendi                                |
| **2010**  | Streaming Replication (HA desteği)                     |
| **2017**  | Logical Replication ve Paralel Query                   |
| **2020**  | JIT Compilation ve Partition Pruning                   |
| **2026**  | PostgreSQL 18.x (40 yıllık olgun proje)                |

### 1.3. Neden PostgreSQL?

#### Açık Kaynak ve Özgür

- **Lisans:** PostgreSQL License (MIT benzeri, çok permissive)
- **Maliyet:** $0 - Hiçbir lisans ücreti yok
- **Özgürlük:** Kaynak kodunu değiştirebilir, ticari projede kullanabilirsiniz

#### ACID Garantisi

- **Atomicity:** İşlemler ya tamamen yapılır ya da hiç yapılmaz
- **Consistency:** Veri her zaman geçerli kurallara uyar
- **Isolation:** Eş zamanlı işlemler birbirini etkilemez
- **Durability:** Commit edilen veri asla kaybolmaz

#### Zengin Veri Tipi Desteği

**Standart:** INTEGER, VARCHAR, DATE, TIMESTAMP, BOOLEAN  
**İleri:** JSONB, ARRAY, UUID, INET/CIDR, RANGE, Geometric  
**Özel:** Kendi veri tipinizi tanımlayabilirsiniz

#### NoSQL + SQL Birlikte (Hybrid)

```sql
-- JSON verisi saklayın ve sorgulayın
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    attributes JSONB
);

SELECT * FROM products WHERE attributes @> '{"brand": "Dell"}';
```

### 1.4. PostgreSQL vs Diğerleri

| Özellik              | PostgreSQL | MySQL   | Oracle        | MSSQL        | MongoDB      |
| :--------------------- | :----------- | :-------- | :-------------- | :------------- | :------------- |
| Açık Kaynak          | ✅ Tamamen  | ✅ Kısmen | ❌ Hayır       | ❌ Hayır      | ✅ Kısmen     |
| Lisans Maliyeti      | $0         | $0      | Çok Pahalı    | Pahalı       | $0           |
| ACID                 | ✅ Tam      | ✅ Var   | ✅ Tam         | ✅ Tam        | ⚠️ Sınırlı    |
| JSONB                | ✅ Native   | ⚠️ Yavaş | ✅ Var         | ✅ Var        | ✅ Native     |
| Full Text Search     | ✅ Built-in | ⚠️ Basit | ✅ Gelişmiş    | ✅ Gelişmiş   | ✅ Atlas      |
| GIS Desteği          | ✅ PostGIS  | ⚠️ Zayıf | ✅ Spatial     | ✅ Spatial    | ✅ Geospatial |

### 1.5. Kim Kullanıyor?

- **Apple:** iCloud backend
- **Instagram:** Ana veritabanı (milyarlarca fotoğraf)
- **Spotify:** Kullanıcı verileri
- **Reddit:** Tüm içerik
- **Netflix:** Billing sistemi
- **Uber:** Coğrafi veri
- **NASA:** Uzay verileri

### 1.6. Kullanım Senaryoları

1. **Web Uygulamaları:** Django, Rails, Express backend'leri
2. **Analitik Sistemler:** Veri ambarı, BI raporları
3. **Coğrafi Uygulamalar:** Harita servisleri, lojistik
4. **Finansal Sistemler:** Bankacılık, borsa
5. **IoT ve Zaman Serisi:** Sensör verileri (TimescaleDB)
6. **Hybrid Sistemler:** SQL + NoSQL birlikte

---

## Bölüm 2: PostgreSQL Mimarisi

Bu bölüm, PostgreSQL'in iç yapısını, nasıl çalıştığını ve bileşenlerinin birbiriyle nasıl etkileşime girdiğini derinlemesine inceler. Production ortamlarında performans sorunlarını çözmek ve doğru konfigürasyon yapmak için bu mimariyi anlamak kritiktir.

### 2.1. Process Architecture (Süreç Mimarisi)

PostgreSQL, **Process-based** (Süreç tabanlı) bir mimariye sahiptir. MySQL veya Oracle'ın bazı modlarında olduğu gibi "Thread-based" değildir.

```text
┌─────────────────────────────────────┐
│   İstemci (psql, pgAdmin, App)      │
└──────────────┬──────────────────────┘
               │ TCP/IP veya Unix Socket
┌──────────────▼──────────────────────┐
│   Postmaster (Ana Süreç)            │
│   - Bağlantı yönetimi               │
│   - Backend süreçleri oluşturur     │
└──────────────┬──────────────────────┘
               │
    ┌──────────┴──────────┬──────────┐
    ▼                     ▼          ▼
┌─────────┐         ┌─────────┐  ┌─────────┐
│Backend 1│         │Backend 2│  │Backend N│
│(Sorgu 1)│         │(Sorgu 2)│  │(Sorgu N)│
└────┬────┘         └────┬────┘  └────┬────┘
     │                   │            │
     └───────────┬───────┴────────────┘
                 ▼
    ┌────────────────────────────┐
    │   Shared Memory            │
    │   - Shared Buffers (Cache) │
    │   - WAL Buffers            │
    └────────────┬───────────────┘
                 ▼
    ┌────────────────────────────┐
    │   Disk (Veri Dosyaları)    │
    │   - Tables, Indexes        │
    │   - WAL (Write-Ahead Log)  │
    └────────────────────────────┘
```

#### a. Postmaster (Main Process)

- Veritabanı ilk başlatıldığında çalışan ana süreçtir (`postgres` binary'si)
- **Görevi:**
  - İstemcilerden gelen bağlantı isteklerini dinler (default port: 5432)
  - Her yeni bağlantı için yeni bir "Backend Process" fork eder
  - Arka plan süreçlerini başlatır ve yönetir
  - Shutdown veya crash durumunda recovery işlemlerini yönetir

#### b. Backend Processes (Client Connections)

- Her bir istemci bağlantısı, sunucuda kendine ait özel bir `postgres` süreci (PID) ile eşleşir
- Bu süreç, istemciden gelen SQL sorgularını alır, planlar, çalıştırır ve sonucu döndürür

> [!IMPORTANT]
> Her bağlantı bir işletim sistemi süreci olduğu için, çok yüksek sayıda (1000+) bağlantı CPU ve RAM üzerinde baskı yaratır. Production ortamlarında mutlaka **PgBouncer** gibi bir Connection Pooler kullanılmalıdır.

#### c. Background Processes (Arka Plan Süreçleri)

Sistemin sağlıklı çalışması için perde arkasında çalışan kritik süreçler:

1. **Background Writer (BgWriter):**
   - `Shared Buffers` üzerindeki "kirli" (değişmiş) sayfaları diske yazar
   - Checkpointer sürecinin yükünü hafifletir

2. **Checkpointer:**
   - Periyodik olarak tüm kirli sayfaları diske yazar
   - Crash durumunda kurtarma işleminin başlayacağı güvenli noktadır
   - WAL dosyalarının geri dönüştürülmesini sağlar

3. **Autovacuum Launcher:**
   - Tablolardaki "ölü" satırları temizler
   - İstatistikleri günceller (Query Planner için hayati)

4. **WAL Writer:**
   - WAL tamponundaki verileri diske (`pg_wal` dizinine) yazar
   - Veri bütünlüğünü sağlayan en kritik süreçtir

5. **Archiver (Opsiyonel):**
   - WAL dosyalarını yedekleme amacıyla başka bir konuma kopyalar
   - PITR (Point In Time Recovery) için gereklidir

6. **Stats Collector:**
   - Veritabanı istatistiklerini toplar (`pg_stat_*` view'ları)

### 2.2. Memory Architecture (Bellek Mimarisi)

PostgreSQL, belleği iki ana kategoride kullanır: **Shared Memory** (Paylaşımlı) ve **Local Memory** (Süreç Başına).

#### Shared Memory (Tüm Süreçler Tarafından Kullanılır)

1. **Shared Buffers:**
   - Veritabanı sayfalarının (8KB bloklar) RAM'de önbelleğe alındığı alandır
   - Disk I/O'yu azaltır (En önemli performans parametresi)
   - **Önerilen:** Toplam RAM'in %25'i (Örn: 64GB RAM → 16GB Shared Buffers)

2. **WAL Buffers:**
   - WAL kayıtlarının diske yazılmadan önce tutulduğu tampon
   - Varsayılan: 16MB (Genellikle yeterlidir)

3. **CLOG (Commit Log) Buffers:**
   - Transaction commit durumlarını tutar (MVCC için kritik)

#### Local Memory (Her Backend Süreci İçin Ayrı)

1. **work_mem:**
   - Sorting, hashing, join işlemleri için kullanılır
   - **Dikkat:** Her sorgu birden fazla `work_mem` alanı kullanabilir!
   - Örnek: 5 paralel sort → 5 × work_mem RAM kullanımı

2. **maintenance_work_mem:**
   - `VACUUM`, `CREATE INDEX`, `ALTER TABLE` gibi bakım işlemleri için
   - `work_mem`'den daha yüksek olabilir (Örn: 1-2GB)

3. **temp_buffers:**
   - Geçici tablolar için kullanılır

### 2.3. Storage Architecture (Depolama Mimarisi)

#### Veri Dizini Yapısı

```text
/var/lib/pgsql/16/data/
├── base/              # Veritabanı dosyaları (Her DB bir alt dizin)
├── global/            # Cluster-wide tablolar (pg_database)
├── pg_wal/            # WAL (Write-Ahead Log) dosyaları
├── pg_xact/           # Transaction commit durumları
├── pg_multixact/      # Multi-transaction durumları
├── pg_tblspc/         # Tablespace sembolik linkleri
├── postgresql.conf    # Ana konfigürasyon
└── pg_hba.conf        # Erişim kontrolü
```

#### WAL (Write-Ahead Logging)

PostgreSQL'in veri bütünlüğünü garanti eden mekanizma:

1. **Çalışma Prensibi:**
   - Veri değişikliği önce WAL'a yazılır (Sequential I/O - Hızlı)
   - Sonra Shared Buffers'da değiştirilir
   - En son diske yazılır (Random I/O - Yavaş)

2. **Avantajları:**
   - Crash durumunda WAL'dan recovery yapılabilir
   - Streaming Replication için gereklidir
   - PITR (Point-in-Time Recovery) sağlar

#### TOAST (The Oversized-Attribute Storage Technique)

Büyük değerlerin (>2KB) saklanması için özel mekanizma:

- Büyük TEXT, JSONB, BYTEA değerleri otomatik olarak sıkıştırılır ve ayrı tabloda saklanır
- Ana tabloda sadece pointer (referans) tutulur
- Performans artışı sağlar

### 2.4. MVCC (Multi-Version Concurrency Control)

PostgreSQL'in eş zamanlı işlemleri yönetme mekanizması:

#### Nasıl Çalışır?

- Her satırın birden fazla versiyonu olabilir
- Her transaction kendi "snapshot"ını görür
- Okuma işlemleri yazma işlemlerini bloklamaz (ve tersi)

#### Tuple Header (Satır Başlığı)

Her satır şu bilgileri taşır:

- **xmin:** Bu satırı oluşturan transaction ID
- **xmax:** Bu satırı silen transaction ID (0 ise hala geçerli)
- **ctid:** Satırın fiziksel konumu (page + offset)

#### VACUUM'un Önemi

- MVCC nedeniyle eski satır versiyonları birikir ("bloat")
- `VACUUM` bu ölü satırları temizler
- `autovacuum` otomatik olarak çalışır (Mutlaka aktif olmalı!)

### 2.5. Query Processing (Sorgu İşleme)

Bir SQL sorgusunun yaşam döngüsü:

```text
1. Parser       → SQL'i parse tree'ye çevirir
2. Rewriter     → View'ları ve rule'ları uygular
3. Planner      → En optimal execution plan'ı seçer
4. Executor     → Plan'ı çalıştırır, sonuç döndürür
```

#### Query Planner

- Sorguyu çalıştırmanın farklı yollarını değerlendirir
- Maliyet tahminleri yapar (CPU, I/O, Memory)
- İstatistiklere dayanır (`ANALYZE` komutu ile güncellenir)

**Örnek Plan Tipleri:**

- **Sequential Scan:** Tüm tabloyu tarar
- **Index Scan:** Index kullanır
- **Bitmap Scan:** Birden fazla index birleştirir
- **Nested Loop:** İki tabloyu join eder

---

## Özet

PostgreSQL, **güçlü**, **esnek**, **ücretsiz** ve **güvenilir** bir veritabanıdır. Process-based mimarisi, MVCC mekanizması ve WAL sistemi sayesinde hem yüksek performans hem de veri güvenliği sağlar.

**Motto:** "The World's Most Advanced Open Source Relational Database" 🐘
