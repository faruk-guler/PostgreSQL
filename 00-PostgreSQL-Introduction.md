# 00-PostgreSQL-Introduction

**PostgreSQL'e Giriş: Dünyanın En Gelişmiş Açık Kaynak Veritabanı**

---

## 1. PostgreSQL Nedir?

PostgreSQL (kısaca "Postgres"), nesne-ilişkisel (object-relational) bir veritabanı yönetim sistemidir (RDBMS). Açık kaynaklı, ACID uyumlu ve SQL standardına en yakın veritabanı sistemlerinden biridir.

### Temel Özellikler

- **Tamamen Açık Kaynak:** MIT benzeri PostgreSQL License (ticari kullanım serbest)
- **ACID Uyumlu:** Atomicity, Consistency, Isolation, Durability garantisi
- **Zengin Veri Tipleri:** JSON, Array, UUID, Range types, Geospatial (PostGIS)
- **Genişletilebilir:** Kendi veri tipinizi, fonksiyonunuzu, indexinizi yazabilirsiniz
- **Multi-Platform:** Linux, Windows, macOS, BSD

---

## 2. Tarihçe

| Yıl | Olay |
|:----|:-----|
| **1986** | Berkeley Üniversitesi'nde POSTGRES projesi başlatıldı (Prof. Michael Stonebraker) |
| **1996** | SQL desteği eklendi, isim PostgreSQL oldu |
| **2005** | Windows desteği eklendi (v8.0) |
| **2010** | Streaming Replication (v9.0) |
| **2017** | Logical Replication (v10) |
| **2023** | SQL/JSON standardı ve performans iyileştirmeleri (v16) |

> **İlginç Bilgi:** PostgreSQL, 40 yıllık geçmişiyle sürekli gelişen nadir projelerden biridir.

---

## 3. Neden PostgreSQL?

### a. Açık Kaynak vs Ticari

| Özellik | PostgreSQL | Oracle | MySQL (Enterprise) |
| :--- | :--- | :--- | :--- |
| Lisans Maliyeti | **$0** | $47,500/CPU | $5,000+/sunucu |
| Vendor Lock-in | Yok | Var | Var (Oracle'a ait) |
| Community Desteği | Aktif | Ticari | Orta |
| Advanced Features | Full | Full | Kısıtlı |

### b. SQL Standardına Uyum

PostgreSQL, SQL:2016 standardının %99'una uyumludur. Bu, kodunuzu başka veritabanlarına taşımanızı kolaylaştırır.

### c. Extensibility (Genişletilebilirlik)

Başka hiçbir veritabanı PostgreSQL kadar esnek değildir:

```sql
-- Kendi aggregate fonksiyonunuzu yazın
CREATE AGGREGATE my_avg (float8) (
    sfunc = float8_accum,
    stype = float8[],
    finalfunc = float8_avg
);

-- Kendi index türünüzü ekleyin (örn: bloom filter)
CREATE INDEX ON users USING bloom (email);
```

---

## 4. Kullanım Senaryoları

### a. Web Uygulamaları

- **Django, Ruby on Rails, Node.js:** PostgreSQL varsayılan veritabanı
- JSON desteği sayesinde MongoDB benzeri esneklik + SQL gücü
- Örnek: Instagram, Spotify, Twitch

### b. Veri Ambarı (Data Warehousing)

- Paralel query desteği
- Partitioning ile petabyte ölçeği
- OLAP workload'ları (Window Functions, CTEs)

### c. Coğrafi Bilgi Sistemleri (GIS)

- **PostGIS** eklentisi ile dünyanın en güçlü açık kaynak GIS veritabanı
- Örnek: Uber, OpenStreetMap

### d. Zaman Serisi Verileri

- **TimescaleDB** eklentisi ile IoT, metrikler, log verisi
- Örnek: Monitoring sistemleri, finans uygulamaları

---

## 5. PostgreSQL Ekosistemi

### Resmi Araçlar

- **psql:** Komut satırı istemcisi
- **pg_dump/pg_restore:** Yedekleme araçları
- **pgAdmin:** Web tabanlı GUI

### Popüler Eklentiler

- **PostGIS:** Coğrafi veri desteği
- **TimescaleDB:** Zaman serisi optimizasyonu
- **Citus:** Distributed SQL (yatay ölçekleme)
- **pg_stat_statements:** Query performans izleme
- **pgvector:** Vector search (AI/ML)

### Cloud Sağlayıcılar

- **AWS RDS/Aurora PostgreSQL**
- **Google Cloud SQL**
- **Azure Database for PostgreSQL**
- **Supabase** (Firebase alternatifi)

---

## 6. PostgreSQL vs Diğerleri

### PostgreSQL vs MySQL

| Özellik | PostgreSQL | MySQL |
|:--------|:-----------|:------|
| **ACID** | Tam destek | InnoDB'de var |
| **JSON** | JSONB (binary, indexlenebilir) | JSON (text tabanlı) |
| **Window Functions** | Tam destek | v8.0+ (sınırlı) |
| **CTE (WITH)** | Recursive destekli | v8.0+ |
| **Partitioning** | Declarative (otomatik) | Manuel |
| **Replication** | Sync/Async/Logical | Async (eski) |
| **Full Text Search** | Yerleşik | Eklenti gerekli |
| **Lisans** | PostgreSQL (özgür) | GPL (Oracle'a ait) |

**Özet:** Karmaşık sorgular, veri bütünlüğü, genişletilebilirlik → **PostgreSQL**  
Basit CRUD, yüksek okuma trafiği → **MySQL**

### PostgreSQL vs MongoDB

PostgreSQL'deki **JSONB** tipi, MongoDB'nin tüm esnekliğini sağlar AMA SQL gücünü de verir:

```sql
-- MongoDB-style query, PostgreSQL'de
SELECT data->>'name' AS name
FROM users
WHERE data @> '{"city": "Istanbul"}';

-- Artı JOIN, Transaction, Foreign Key avantajları!
```

---

## 7. Kim Kullanıyor?

### Tech Giants

- **Apple:** iCloud altyapısı
- **Instagram:** 100+ TB PostgreSQL
- **Spotify:** Kullanıcı verileri ve analitics
- **Reddit:** Tüm veritabanı
- **Twitch:** Canlı yayın metadata

### Kurumsal

- **ABD Devleti:** Askeri sistemler
- **IMDB:** Film veritabanı
- **Skype:** İletişim kayıtları

---

## 8. Başlangıç İçin Sonraki Adımlar

1. **Mimari Anlayın:** [01-PostgreSQL-Overview-Architecture](01-PostgreSQL-Overview-Architecture.md)
2. **Kurulumu Yapın:** [02-PostgreSQL-Installation](02-PostgreSQL-Installation.md)
3. **Temel İşlemleri Öğrenin:** [03-PostgreSQL-Basic-Operations](03-PostgreSQL-Basic-Operations.md)
4. **SQL Ustalığı:** [04-PostgreSQL-SQL-Mastery](04-PostgreSQL-SQL-Mastery.md)

---

## 9. PostgreSQL Felsefesi

> *"We don't just store data, we help you understand it."*  
> — PostgreSQL Community

PostgreSQL, sadece bir veritabanı değil, bir veri platformudur. Extensibility sayesinde:

- Machine Learning (pgvector, MADlib)
- Graph queries (Apache AGE)
- Time-series (TimescaleDB)
- Geospatial (PostGIS)

hepsini **tek bir veritabanında** yapabilirsiniz.

---

**Şimdi PostgreSQL yolculuğunuza [Mimari Anlayışı](01-PostgreSQL-Overview-Architecture.md) ile devam edin!** 🚀
