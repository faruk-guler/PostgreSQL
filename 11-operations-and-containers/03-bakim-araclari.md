# Bakım Araçları ve Şişkinlik Yönetimi (Bloat Management)

> **Bölüm Kapsamı:** MVCC Şişkinliği (Bloat) Tespiti, pg_repack İç İşleyişi, Sıfır Kesinti Bakım ve pg_squeeze

---

## 1. Bloat (Şişkinlik) Nedir?

PostgreSQL MVCC (Multi-Version Concurrency Control) mimarisi kullanır. Bir satırı `UPDATE` ettiğinizde veya `DELETE` ile sildiğinizde, o satır anında diskten silinmez; "ölü" (dead tuple) olarak işaretlenir. 
Eğer tablonuzda 1GB canlı veri var ama diskte 5GB yer kaplıyorsa, 4GB "Bloat" var demektir.

- **Zararı Nedir?** Full table scan'ler çok yavaşlar, bellek (RAM) gereksiz yere ölü satırlarla dolar, yedekleme süreleri uzar.

---

## 2. Şişkinliği Tespit Etme

Hangi tabloda ne kadar ölü satır (bloat) olduğunu bulmak için sistem kataloglarını sorgulayabiliriz:

```sql
SELECT
  schemaname, relname,
  n_dead_tup, -- Ölü satır sayısı
  n_live_tup, -- Canlı satır sayısı
  (n_dead_tup::float / (n_live_tup + n_dead_tup + 1) * 100)::numeric(5,2) AS bloat_ratio
FROM pg_stat_all_tables
WHERE (n_live_tup + n_dead_tup) > 10000
ORDER BY bloat_ratio DESC;
```
*(Not: Daha kesin hesaplamalar için `pgstattuple` eklentisi kullanılır, ancak yukarıdaki sorgu günlük izleme için yeterlidir.)*

---

## 3. pg_repack: Sıfır Kesinti ile Derin Temizlik

Standart `VACUUM FULL` komutu tablonun boyutunu fiziksel olarak küçültür ancak tabloyu **AccessExclusiveLock** ile tamamen kilitler (Okuma ve Yazma yapılamaz). Production ortamında 100GB'lık bir tablo için saatlerce sürecek bir kilitlenme kabul edilemez.

**Çözüm:** `pg_repack` eklentisi.

### pg_repack Nasıl Çalışır? (İç İşleyiş ve Kilit Mekaniği)

`pg_repack` sihrini şu adımlarla gerçekleştirir:

1. **Hazırlık:** Hedef tablo üzerinde geçici bir log tablosu ve bir trigger oluşturur (sadece saliselik bir kilit gerektirir).
2. **Kopyalama:** Arka planda tablonun yepyeni, tamamen sıkıştırılmış, bloatsız bir kopyasını oluşturur. Bu sırada ana tabloya gelen tüm `INSERT/UPDATE/DELETE` işlemleri trigger sayesinde log tablosuna kaydedilir.
3. **Senkronizasyon:** Kopyalama bittiğinde, log tablosundaki değişiklikleri yeni tabloya uygular.
4. **Yer Değiştirme (Swap):** Her şey senkronize olduğunda, ana tablo ile yeni tablonun isimlerini (dosya isimlerini) milisaniyelik bir kilit alarak değiştirir. Eski şişkin tabloyu siler (DROP).

### Kurulum ve Kullanım

```bash
# RHEL/AlmaLinux için kurulum
sudo dnf install pg_repack_16

# Veritabanında eklentiyi aktifleştir (Sadece bir kez)
psql -d mydb -c "CREATE EXTENSION pg_repack;"
```

```bash
# Sadece spesifik bir tabloyu repackle
pg_repack -t users_table -d mydb

# Sadece spesifik bir indeksi repackle
pg_repack -i idx_users_email -d mydb
```

### ⚠️ Kritik pg_repack Uyarıları ve Donanım Gereksinimleri

1. **Disk Alanı:** `pg_repack` tabloyu kopyaladığı için işlemin yapılabilmesi için **tablonun ve indekslerinin boyutu kadar EKSTRA boş disk alanı** gerekir. Disk %80 doluysa `pg_repack` yapamazsınız!
2. **CPU ve I/O Yükü:** İşlem ciddi oranda disk I/O ve CPU tüketir. Yoğun trafiğin olduğu saatlerde (peak hours) çalıştırılması önerilmez.
3. **Primary Key Zorunluluğu:** Repack edilecek tablonun mutlak surette bir `Primary Key` veya `NOT NULL UNIQUE` indeksi olması şarttır (Trigger'ın satırları eşleştirebilmesi için).

---

## 4. İndeks Bakımı (Index Maintenance)

Tablolardan ziyade indeksler çok daha hızlı şişer (B-Tree yapısı gereği). Sadece indeksleri yenilemek çoğu zaman performansı geri kazanmak için yeterlidir.

### REINDEX CONCURRENTLY (v12+)

PostgreSQL 12 ile gelen bu özellik, sorguları engellemeden (okuma/yazma kilitlenmesi yapmadan) indeksi yeniden oluşturmanızı sağlar.

```sql
-- Mevcut indexi kilitlemeden arka planda yenisini yapar ve değiştirir
REINDEX INDEX CONCURRENTLY idx_audit_created_at;

-- Bir tablodaki tüm indeksleri concurrently yeniler
REINDEX TABLE CONCURRENTLY audit_logs;
```

---

## 5. Uzman Tavsiyeleri

1. **Autovacuum'u Suçlama, Tune Et:** Eğer tablolarınız sürekli ve çok hızlı şişiyorsa, `pg_repack` bir çözüm değil, ağrı kesicidir. Asıl çözüm Autovacuum'u daha agresif çalışacak şekilde (`autovacuum_vacuum_scale_factor` düşürmek, `autovacuum_vacuum_cost_limit` artırmak) optimize etmektir.
2. **Düzenli İzleme:** İzleme sisteminize (Prometheus) bloat oranını gösteren bir metrik ekleyin. Bloat %30'u aştığında haftalık bakım penceresinde (maintenance window) repack planlayın.
