# PostgreSQL Master Guide - Complete Documentation Series

**Kapsamlı PostgreSQL Eğitim Serisi: Sıfırdan Uzmanlığa**

Bu dizin, PostgreSQL'in her yönünü kapsayan **29 modüllük** kapsamlı bir dokümantasyon setidir. Her doküman, production ortamlarına odaklanarak, gerçek dünya senaryolarında kullanılabilecek pratik bilgiler içerir.

---

## 📚 Modül Listesi

### Giriş (Introduction)

1. [PostgreSQL Nedir?](00-PostgreSQL-Introduction.md) - Tanım, tarihçe, kullanım senaryoları  **(YENİ)**

### Temel Seviye (Foundation)

1. [PostgreSQL Architecture](01-PostgreSQL-Overview-Architecture.md) - İç mimari ve süreç yapısı
2. [Installation & Production Tuning](02-PostgreSQL-Installation.md) - Genel kurulum ve konfigürasyon
   - [02a - RHEL/Rocky/AlmaLinux Kurulum](02a-PostgreSQL-Installation-RHEL.md)
   - [02b - Debian/Ubuntu Kurulum](02b-PostgreSQL-Installation-Debian.md)
3. [Basic Operations](03-PostgreSQL-Basic-Operations.md) - psql mastery ve kullanıcı yönetimi
4. [SQL Mastery](04-PostgreSQL-SQL-Mastery.md) - JSONB, Window Functions, CTEs

### DBA Operasyonları (Administration)

1. [Backup & Recovery](05-PostgreSQL-Backup-Recovery.md) - pg_dump, PITR, pgBackRest
2. [Performance Tuning](06-PostgreSQL-Performance-Tuning.md) - EXPLAIN, indexleme stratejileri
3. [High Availability](07-PostgreSQL-High-Availability.md) - Streaming/Logical Replication
4. [Security Hardening](08-PostgreSQL-Security-Hardening.md) - SSL/TLS, RLS, pgaudit
5. [Extensions & Tools](09-PostgreSQL-Extensions-Tools.md) - PgBouncer, pgBadger, PostGIS
6. [Upgrades & Maintenance](10-PostgreSQL-Upgrades-Maintenance.md) - pg_upgrade, VACUUM, XID Wraparound

### Modern Deployment (Cloud Native)

1. [Docker & Kubernetes](11-PostgreSQL-Docker-Kubernetes.md) - CloudNativePG, Operators

### İleri Seviye Geliştirme (Advanced)

1. [Quick Reference](12-PostgreSQL-Quick-Reference.md) - Hızlı komutlar
2. [PL/pgSQL & Triggers](13-PostgreSQL-PL-pgSQL-Triggers.md) - Fonksiyonlar ve prosedürler
3. [Monitoring & Logging](14-PostgreSQL-Monitoring-Logging.md) - Prometheus, Grafana, İstatistikler
4. [Advanced Features](15-PostgreSQL-Advanced-Features.md) - FDW, FTS, Mat Views
5. [Concurrency & Transactions](16-PostgreSQL-Concurrency-Transactions.md) - MVCC, Locks, Isolation Levels

### Entegrasyon ve Veri Yönetimi (Integration)

1. [Migration Strategies](17-PostgreSQL-Migration-Integration.md) - Oracle/MySQL to PG
2. [Data Types Deep Dive](18-PostgreSQL-Data-Types.md) - Arrays, UUID, Range, Collations
3. [App Development Best Practices](19-PostgreSQL-App-Development.md) - Drivers, Connection Pooling
4. [Anti-Patterns](20-PostgreSQL-Anti-Patterns.md) - Yapılmaması gerekenler
5. [Data Types Reference](21-PostgreSQL-Data-Types-Reference.md) - Tüm veri tipleri listesi

### Ustalık Seviyesi (Mastery)

1. [Benchmarking](22-PostgreSQL-Benchmarking-pgbench.md) - pgbench ile performans testi
2. [Maintenance Tools](23-PostgreSQL-Maintenance-Tools.md) - pg_repack, Bloat yönetimi
3. [Distributed PostgreSQL](24-PostgreSQL-Distributed-Citus-Timescale.md) - Citus, TimescaleDB

### Uzman Seviye (Expert)

1. [Internals & Storage](25-PostgreSQL-Internals-Storage.md) - Page layout, TOAST
2. [Specialty Features](26-PostgreSQL-Specialty-Features.md) - LISTEN/NOTIFY, JIT, 2PC
3. [Extension Development](27-PostgreSQL-Extension-Development.md) - C ve SQL ile eklenti yazımı **(YENİ)**

---

## 🎯 Önerilen Okuma Sırası

**Yeni Başlayanlar:** 01 → 02 → 03 → 04 → 12 (Quick Ref)  
**DBA'ler:** 01 → 05 → 06 → 07 → 08 → 10 → 23  
**Developerlar:** 01 → 13 → 18 → 19 → 20  
**Mimari/Architect:** 01 → 07 → 11 → 24 → 25  
**Performance Tuning:** 06 → 14 → 22  

---

## ⚡ Hızlı Erişim

- **PostgreSQL nedir?** → [01-Overview-Architecture](01-PostgreSQL-Overview-Architecture.md)
- **Kurulum hatası mı?** → [02-Installation](02-PostgreSQL-Installation.md)
- **Sorgu yavaş mı?** → [06-Performance-Tuning](06-PostgreSQL-Performance-Tuning.md)
- **Yedek al?** → [05-Backup-Recovery](05-PostgreSQL-Backup-Recovery.md)
- **Replikasyon kur?** → [07-High-Availability](07-PostgreSQL-High-Availability.md)
- **Kubernetes'de çalıştır?** → [11-Docker-Kubernetes](11-PostgreSQL-Docker-Kubernetes.md)

---

**Toplam Sayfa Sayısı:** ~140 KB metin (yaklaşık 150+ A4 sayfa)  
**Hazırlayan:** PostgreSQL Master Guide Project  
**Son Güncelleme:** 2026-02-09
