# 09-PostgreSQL-Extensions-Tools

PostgreSQL'in en büyük gücü "Extensibility" (Genişletilebilirlik) özelliğidir. Çekirdeği değiştirmeden yeni veri tipleri, indexler ve diller eklenebilir. Ayrıca production ortamının olmazsa olmazı yan araçlar vardır.

---

## 1. Connection Pooling: PgBouncer

PostgreSQL'de her bağlantı bir işletim sistemi sürecidir (Process). 1000 süreç açmak sunucuyu öldürür.
**Çözüm:** PgBouncer. Uygulama ile veritabanı arasına giren hafif bir vekil sunucudur.

### Kurulum ve Konfigürasyon

```ini
# /etc/pgbouncer/pgbouncer.ini

[databases]
# Veritabanı takma adları
mydb = host=127.0.0.1 port=5432 dbname=mydb

[pgbouncer]
listen_port = 6432
listen_addr = *
auth_type = md5 # veya scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction # EN KRİTİK AYAR
max_client_conn = 10000 # İstemci tarafı limiti
default_pool_size = 20  # Sunucu tarafı limiti (Her DB için)
```

### Pool Modes (Havuz Modları)

1. **Session Pooling:** İstemci bağlanır, işi bitene kadar bir backend sürecini kilitler. (En az verimli)
2. **Transaction Pooling:** İstemci bir transaction (`BEGIN...COMMIT`) başlattığında backend atanır. Commit edince backend başkasına verilir. (En verimli - Tavsiye edilen).
3. **Statement Pooling:** Her tekil SQL sorgusu için backend atanır. (Transaction bütünlüğünü bozar, nadiren kullanılır).

---

## 2. Log Analizi: pgBadger

PostgreSQL logları varsayılan haliyle okunması zordur. `pgBadger`, log dosyalarını tarayıp HTML raporu üreten bir Perl scriptidir.

### Kullanım

1. `postgresql.conf` içinde loglamayı açın (`log_min_duration_statement = 0` hepsi için, veya `1000` ms üzeri için).
2. Log formatını `stderr` ve prefix'i `%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h` yapın.
3. Rapor üretin:

```bash
pgbadger /var/lib/pgsql/16/data/log/postgresql-Fri.log -o rapor.html
```

#### pgBadger Rapor İçeriği

- En çok zaman harcayan sorgular.
- En sık çalışan sorgular.
- Checkpoint sıklığı ve I/O yükü.
- Saat bazında sorgu dağılımı.
- Lock wait süreleri.

---

## 3. Specialty Extensions (Özel İş Yükleri)

PostgreSQL'i "her şeyi yapan veritabanı" haline getiren eklentilerdir.

### a. TimescaleDB (Zaman Serisi)

IoT, metrikler ve finansal veriler için optimize edilmiştir.

- **Hypertable:** Tabloları zamana göre otomatik böler (Partitioning).
- **Compression:** %90 disk tasarrufu sağlar.
- **Continuous Aggregates:** Hızlı raporlama için ön hesaplama yapar.

### b. Citus (Dağıtık SQL)

Veritabanını birden fazla sunucuya (node) yayarak yatayda (scale-out) büyümenizi sağlar.

- **Distributed Tables:** Tabloları şarding yaparak nodelara dağıtır.
- **Parallel SQL:** Tüm CPU'ları aynı anda kullanır.

### c. pgvector (AI & Vector Search)

Yapay zeka (LLM) embeddinglerini saklamak ve benzerlik araması yapmak için kullanılır.

- **Veri Tipi:** `vector(1536)` (OpenAI embedding boyutu)
- **Index:** IVFFlat ve HNSW ile ultra hızlı cosine similarity araması.

```sql
CREATE EXTENSION vector;
CREATE TABLE items (embedding vector(3));
INSERT INTO items VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

---

## 4. Olmazsa Olmaz Eklenti: pg_stat_statements

Veritabanınızda ne olup bittiğini anlamak için **ZORUNLUDUR**. Her sorgunun istatistiğini (kaç kere çalıştı, ne kadar sürdü, kaç satır döndü) tutar.

### Aktifleştirme

```ini
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements' # Restart gerekir
```

```sql
-- Veritabanında eklentiyi oluştur
CREATE EXTENSION pg_stat_statements;
```

### En Yavaş 5 Sorguyu Bulma

```sql
SELECT 
    calls, -- Kaç kere çalıştı
    total_exec_time / calls as avg_time_ms, -- Ortalama süre
    query -- Sorgu metni
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

---

## 5. Coğrafi Bilgi Sistemleri: PostGIS

PostgreSQL'i dünyanın en iyi GIS (Geographic Information System) veritabanı yapan eklentidir.

### Yetenekleri

Sıradan veritabanları sadece `X, Y` koordinatını sayı olarak tutar. PostGIS ise dünyayı "küre" olarak anlar (`Geography` tipi) veya düzlem olarak anlar (`Geometry` tipi).

- **Mesafe Ölçümü:** "Bu noktaya 500 metre yarıçapındaki kafeleri bul." (Küre eğimini hesaba katar).
- **Kesişim:** "Bu arsa parseli, şu orman alanı ile çakışıyor mu?"
- **Formatlar:** GeoJSON, KML, WKT (Well-Known Text) çıktı verebilir.

```sql
CREATE EXTENSION postgis;

-- 500m yarıçapındaki kafeleri bul (GIST Index kullanır)
SELECT name 
FROM cafes 
WHERE ST_DWithin(
    location, 
    ST_SetSRID(ST_MakePoint(28.9784, 41.0082), 4326), -- Ayasofya
    500 -- metre
);
```
