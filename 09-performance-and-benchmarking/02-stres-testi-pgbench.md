# Yük Testi ve Kapasite Planlama (pgbench)

> **Bölüm Kapsamı:** Stres Testleri, Yüzdelik Gecikme (P95/P99 Latency) Analizi, Özel Test Senaryoları ve Boyutlandırma

---

## 1. pgbench Nedir?

`pgbench`, TPC-B (Transaction Processing Performance Council) standardına dayalı bir test aracıdır. Varsayılan olarak 5 `SELECT`, `UPDATE` ve `INSERT` içeren bir işlem setini döngüsel olarak çalıştırır. Amacı, sisteminizin maksimum TPS kapasitesini ve yük altındaki gecikme (latency) davranışını ölçmektir.

### Hazırlık (Initialization)

Test yapmadan önce, veritabanını test verileriyle doldurmanız gerekir.

```bash
# -i: Initialize (Tabloları ve veriyi oluşturur)
# -s 100: Scale factor (100 = ~1.5GB veri, her biri 100.000 satırlık 15 account parçası)
pgbench -i -s 100 mydb
```

---

## 2. Test Çalıştırma ve P95/P99 Analizi

Standart testlerin yanı sıra, özellikle gerçek dünya senaryolarında ortalama gecikme (Average Latency) çok yanıltıcı olabilir. 100 işlemin 99'u 1ms sürebilir, ancak 1 işlem kilitlenme yüzünden 1 saniye sürebilir. Bu durumda ortalama düşük görünür ama P99 feci durumdadır.

### Profesyonel Test Senaryosu (Latency Yüzdelikleri ile)

```bash
# -c 50: 50 eşzamanlı istemci
# -j 4: 4 worker thread (CPU'nuza göre ayarlayın)
# -T 120: 120 saniye (2 dakika) boyunca test et
# --aggregate-interval=10: Her 10 saniyede bir log yaz
# --latency-limit=500: 500ms'den uzun süren işlemleri "geç/kötü" say
# --percentiles=90,95,99: Gecikme yüzdeliklerini göster
pgbench -c 50 -j 4 -T 120 \
  --aggregate-interval=10 \
  --latency-limit=500 \
  --percentiles=90,95,99 \
  mydb
```

### Sonuçları Yorumlama

Karşınıza çıkan özette şunlara dikkat edin:

1. **TPS (Transactions Per Second):** Bağlantı kurma süresi hariç TPS değerinizin yüksek ve *istikrarlı* olması gerekir.
2. **P95 Latency:** İşlemlerin %95'i bu sürenin altında tamamlandı.
3. **P99 Latency:** İşlemlerin %99'u bu sürenin altında tamamlandı. Eğer Average Latency 5ms iken, P99 Latency 300ms ise, sisteminizde periyodik kilitlenmeler, disk I/O darboğazı veya Autovacuum engelleri var demektir.

---

## 3. Özel Senaryolar (Custom Scripts)

Uygulamanızın gerçek yükünü simüle etmek için pgbench'in kendi SQL dosyanızı okumasını sağlayabilirsiniz.

**`search.sql`:**

```sql
-- Rastgele bir ID seç
\set id random(1, 1000000)

-- Senaryonuz:
BEGIN;
UPDATE products SET view_count = view_count + 1 WHERE id = :id;
SELECT name, price FROM products WHERE id = :id;
COMMIT;
```

**Çalıştır:**

```bash
# Sadece kendi scriptimizi çalıştır
pgbench -f search.sql -c 100 -j 8 -T 300 mydb
```

---

## 4. Connection Pooling (Bağlantı Havuzu) Stres Testi

PostgreSQL'de bağlantılar çok maliyetlidir (her biri bir OS process'idir). `max_connections = 2000` yapmak yerine **PgBouncer** kullanmak zorunludur. Bunu pgbench ile kanıtlayabilirsiniz.

### Test 1: Doğrudan PostgreSQL (Pooler Yok)

1000 istemcinin doğrudan PG'ye bağlanmaya çalışması:

```bash
# -C: Her transaction için bağlantıyı kapatıp yeniden aç (Uygulamanızın havuzu yoksa böyle davranır)
pgbench -c 1000 -j 16 -T 60 -C -p 5432 mydb
```
*Sonuç:* Veritabanı büyük ihtimalle çökecek, bağlantılar reddedilecek (`FATAL: sorry, too many clients already`) veya TPS yerlerde sürünecektir.

### Test 2: PgBouncer Üzerinden (Transaction Mode)

```bash
# PgBouncer portuna (örneğin 6432) bağlanarak aynı testi yapın
pgbench -c 1000 -j 16 -T 60 -C -p 6432 mydb
```
*Sonuç:* PgBouncer bu 1000 isteği alacak, arkadaki (örneğin 50) gerçek veritabanı bağlantısı üzerinden kuyruğa sokup eritecektir. Veritabanı CPU'su asla %100'de kilitlenmeyecek, TPS yüksek kalacaktır.

---

## 5. Capacity Planning (Kapasite Planlama)

Kaç kullanıcıya hizmet verebilirsiniz?

- **TPS < 100:** Geliştirme/Lab ortamı.
- **TPS 100 - 1000:** Küçük-Orta ölçekli uygulama.
- **TPS 1000 - 10000:** Yüksek trafikli sistem (Hobi projelerinden fazlası).
- **TPS > 50000:** Bankacılık/Telecom seviyesi (Çok iyi konfigürasyon, pooler ve donanım gerekir).

### Sizing (Boyutlandırma) İpuçları

1. **RAM (shared_buffers):** En sıcak verilerinizin (Working Set) RAM'e sığması gerekir. Test sırasında `pg_stat_bgwriter` üzerinden disk I/O'sunu izleyin.
2. **I/O (Disk):** Yazma odaklı testlerde (`-i` sonrası default test) disk IOPS sınırı dar boğaz yaratır. SSD/NVMe zorunludur.
3. **Testi Isıtın (Warm-up):** Veriler diske değil RAM'e çıkana kadar ilk 1-2 dakika sonuçlar düşük çıkabilir. Uzun süreli (`-T 300`) testler daha güvenilirdir.
