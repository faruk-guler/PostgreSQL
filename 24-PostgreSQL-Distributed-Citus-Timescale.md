# 24-PostgreSQL-Distributed-Citus-Timescale

Tek bir PostgreSQL sunucusu terabaytlarca veriyi işleyebilir, ancak bazen performans veya kapasite sınırlarına dayanılır. Bu doküman, PostgreSQL'i yatayda nasıl ölçekleyeceğinizi (Scale-out) anlatır.

---

## 1. Citus: Distributed PostgreSQL

Citus, PostgreSQL'i bir "Distributed Database" (Dağıtık Veritabanı) haline getiren bir eklentidir. Veriyi birden fazla sunucuya (node) böler (shard) ve sorguları paralel olarak tüm sunucularda çalıştırır.

### Mimari

- **Coordinator Node:** Uygulamanın bağlandığı ana sunucu. Sorguları node'lara dağıtır.
- **Worker Nodes:** Verinin asıl durduğu ve hesaplamanın yapıldığı sunucular.

### Kullanım Senaryosu: Multi-tenant SaaS

Binlerce müşteriniz varsa ve her müşterinin milyonlarca verisi varsa, Citus ile her müşteriyi farklı bir worker'a atayabilirsiniz.

```sql
CREATE EXTENSION citus;

-- Tabloyu oluştur (Normal bir tablo gibi)
CREATE TABLE github_events (
    id bigint,
    user_id int,
    repo_name text,
    created_at timestamptz
);

-- Tabloyu dağıt (Distribute)
SELECT create_distributed_table('github_events', 'user_id');

-- Artık user_id'ye göre veri farklı sunuculara otomatik dağılacaktır.
```

---

## 2. TimescaleDB: Zaman Serisi Canavarı

Eğer sisteminiz saniyede on binlerce log, sensör verisi veya borsa verisi üretiyorsa, standart PostgreSQL yavaşlayabilir. TimescaleDB, bu verileri "Hypertable" adı verilen yapılarla optimize eder.

### Yetenekleri

- **Hypertables:** Veriyi otomatik olarak zaman aralıklarına (chunks) böler.
- **Compression:** Eski verileri %90 oranında sıkıştırır.
- **Continuous Aggregates:** Dashboardlar için istatistikleri arka planda önceden hesaplar.

```sql
CREATE EXTENSION timescaledb;

-- 1. Normal tablo
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id INT,
    temperature DOUBLE PRECISION
);

-- 2. Hypertable'a dönüştür (7 günlük parçalar halinde)
SELECT create_hypertable('sensor_data', 'time', chunk_time_interval => INTERVAL '7 days');

-- 3. Sıkıştırma politikasını aç (30 günden eski veriler sıkışsın)
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id'
);
SELECT add_compression_policy('sensor_data', INTERVAL '30 days');
```

---

## 3. Distributed SQL vs NoSQL

Neden hala PostgreSQL (Citus/Timescale) kullanmalısınız?

- **Full SQL Desteği:** Complex JOIN'ler, Window Functions vb. çalışmaya devam eder.
- **ACID Garantisi:** Transaction bütünlüğü korunur.
- **Zengin Ekosistem:** Grafik araçları, kütüphaneler olduğu gibi kullanılabilir.

---

## 4. Alternatif Dağıtık Çözümler

### a. YugabyteDB / CockroachDB

Bu sistemler "PostgreSQL Compatible" (PostgreSQL uyumlu) olarak sıfırdan yazılmıştır. Google Spanner mimarisini kullanırlar.

- **Avantaj:** Native HA ve otomatik sharding.
- **Dezavantaj:** Bazı çok özel PostgreSQL eklentileri çalışmayabilir.

### b. Greenplum

Büyük veri analitiği (Data Warehousing / OLAP) için özelleşmiş bir PostgreSQL türevidir. Milyarlarca satır üzerinde karmaşık analitik sorgular için tasarlanmıştır.

---

## 5. Ne Zaman Ölçeklemeli?

1. **Tek Sunucu Sınırı:** Tek bir NVMe disk veya RAM kapasitesi yetmiyorsa.
2. **Yazma Darboğazı:** Saniyede 50.000+ INSERT/UPDATE geliyorsa.
3. **Analitik Sorgular:** Tek bir CPU'nun gücü büyük veri setlerini taramaya yetmiyorsa.

> [!TIP]
> Ölçeklemeye (Horizontal Scaling) gitmeden önce mutlaka **06-Performance-Tuning** (Vertical Scaling) adımlarını tükettiğinizden emin olun. Genellikle daha büyük bir makineye geçmek, dağıtık bir sistemi yönetmekten daha ucuzdur.
