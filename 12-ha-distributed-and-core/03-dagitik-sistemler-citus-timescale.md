# Dağıtık PostgreSQL: Citus ve TimescaleDB

> **Bölüm Kapsamı:** Büyük Veri (Big Data), Yatay Ölçekleme (Sharding), Zaman Serisi Veritabanları ve Dağıtık Mimariler

---

## 1. Neden Dağıtık PostgreSQL?

Tek bir sunucunun CPU, RAM ve Disk sınırlarına ulaştığınızda (Dikey Ölçekleme / Scale-Up bittiğinde), veriyi birden fazla sunucuya bölmek (Yatay Ölçekleme / Scale-Out) zorunlu hale gelir. PostgreSQL, çekirdeğinde yerel bir Sharding desteğine sahip olmasa da, güçlü **Extension** (Eklenti) mimarisi sayesinde dünyadaki en iyi dağıtık veritabanlarından birine dönüşebilir.

---

## 2. Citus: Distributed PostgreSQL (Yatay Ölçekleme)

Citus (Microsoft tarafından satın alındı ve tamamen Açık Kaynak yapıldı), PostgreSQL'i devasa bir dağıtık veritabanına dönüştürür. Uygulamanız sanki tek bir PostgreSQL'e bağlanıyormuş gibi hisseder, ancak Citus (Coordinator node) arka planda veriyi ve sorguları onlarca Worker node'a böler.

### Ne Zaman Kullanılır?
- **Multi-Tenant SaaS:** Binlerce müşteriniz varsa ve verileri izole etmek istiyorsanız (Tenant ID üzerinden sharding).
- **Gerçek Zamanlı Analitik:** TB'larca veri üzerinde saniyenin altında dönmesi gereken Dashboard sorguları.

### Somut Sharding Örneği (SaaS Mimarisi)

Bir SaaS uygulamasında tabloyu `tenant_id` üzerinden Worker düğümlere (node) bölmek için:

```sql
-- 1. Citus eklentisini aktif et
CREATE EXTENSION citus;

-- 2. Standart tablonuzu oluşturun
CREATE TABLE events (
    tenant_id INT,
    event_id uuid,
    event_type VARCHAR(50),
    payload JSONB,
    created_at TIMESTAMP DEFAULT now(),
    PRIMARY KEY (tenant_id, event_id) -- Shard key mutlaka PK içinde olmalı!
);

-- 3. Sihirli Komut: Tabloyu dağıt (Shard et)
-- tenant_id kolonunu baz alarak veriyi Worker node'lara paylaştırır
SELECT create_distributed_table('events', 'tenant_id');
```

**Sorgu Dağıtımı Nasıl Çalışır?**
Siz `SELECT * FROM events WHERE tenant_id = 5` sorgusunu Coordinator'a attığınızda, Citus bu verinin sadece Worker 3'te olduğunu bilir ve sorguyu direkt oraya yönlendirir. Ağ trafiği inanılmaz düşer, I/O hızı katlanır.

---

## 3. TimescaleDB: Zaman Serisi Canavarı

TimescaleDB, PostgreSQL'i IoT sensörleri, finansal tik verileri veya sunucu logları gibi zaman serisi (Time-Series) verilerini işlemek için optimize eder. 

### Temel Konsept: Hypertable

TimescaleDB, milyarlarca satırı tek bir tablo gibi gösterir ancak veriyi diskte otomatik olarak zamana (örneğin günlük veya haftalık "chunk"lara) göre fiziksel parçalara böler.

### Somut Hypertable Örneği (IoT Metrikleri)

```sql
-- 1. Eklentiyi kur
CREATE EXTENSION timescaledb;

-- 2. Standart bir tablo oluştur (Zaman sütunu zorunludur)
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INT NOT NULL,
    temperature DOUBLE PRECISION,
    cpu_load DOUBLE PRECISION
);

-- 3. Sihirli Komut: Tabloyu Hypertable'a çevir
-- Veriyi her 1 günlük parçalara (chunk) böler
SELECT create_hypertable('sensor_data', 'time', chunk_time_interval => INTERVAL '1 day');
```

### Neden TimescaleDB?
1. **Sürekli Hızlı INSERT:** Standart PostgreSQL tablosu büyüdükçe indeks ağacı RAM'e sığmaz ve yazma hızı çöker. TimescaleDB, güncel "chunk" indeksini hep RAM'de tuttuğu için yıllar geçse de yazma hızı sabit kalır.
2. **Continuous Aggregates (Sürekli Özetler):** Milyarlarca satırdan saatlik ortalama almak zordur. TimescaleDB bunu arka planda sürekli hesaplar.

```sql
-- Arka planda otomatik hesaplanan saatlik özet tablosu
CREATE MATERIALIZED VIEW sensor_hourly_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket,
       sensor_id,
       AVG(temperature) as avg_temp
FROM sensor_data
GROUP BY bucket, sensor_id;
```

---

## 4. Karşılaştırma: Hangisini Seçmeli?

| Özellik | Citus | TimescaleDB | Standart PostgreSQL (Partitioning) |
| :--- | :--- | :--- | :--- |
| **Kullanım Amacı** | SaaS, Ölçekleme (Scale-Out) | IoT, Metrik, Zaman Serisi | Genel Veri, Orta-Büyük Tablolar |
| **Veri Dağıtımı** | Farklı Fiziksel Sunuculara (Nodes) | Tek Sunucuda Fiziksel Parçalara (Chunks) | Tek Sunucuda Mantıksal Parçalara |
| **SQL Desteği** | Çoğu standart (Bazı kısıtlamalar var) | Tamamen standart PostgreSQL | Tamamen standart PostgreSQL |
| **Karmaşıklık** | Yüksek (Cluster yönetimi gerekir) | Düşük-Orta | Düşük |

> [!TIP]
> Eğer donanım sınırlarına henüz çarpmadıysanız, Native PostgreSQL Partitioning (Bölümlendirme) ile başlayın. Citus veya TimescaleDB gibi güçlü araçları **gerçekten ihtiyacınız olduğunda** devreye alın.
