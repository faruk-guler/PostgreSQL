# 22-PostgreSQL-Benchmarking-pgbench

Bir veritabanının gerçek performansı, boş bir sistemde "SELECT 1" çalıştırarak değil, yük altında (stress test) ölçülür. PostgreSQL ile birlikte gelen `pgbench`, bu iş için standart araçtır.

---

## 1. pgbench Nedir?

`pgbench`, TPC-B (Transaction Processing Performance Council) standardına dayalı bir test aracıdır. Varsayılan olarak 5 SELECT, UPDATE ve INSERT içeren bir işlem setini döngüsel olarak çalıştırır.

### Hazırlık (Initialization)

Test yapmadan önce, veritabanını test verileriyle doldurmanız gerekir.

```bash
# -i: Initialize
# -s 100: Scale factor (100 = ~1.5GB veri, 1.5M satır)
pgbench -i -s 100 mydb
```

---

## 2. Test Çalıştırma

### Temel Senaryo

```bash
# -c 10: 10 eşzamanlı istemci (clients)
# -j 2: 2 worker thread (kendi CPU'nuzun yarısı kadar önerilir)
# -T 60: 60 saniye boyunca test et
# -P 5: Her 5 saniyede bir ara rapor ver
pgbench -c 10 -j 2 -T 60 -P 5 mydb
```

### Önemli Parametreler

- **`-S` (Select-only):** Sadece okuma performansı ölçer. RAM/Disk cache performansını test etmek için idealdir.
- **`-N` (Skip-update):** Yazma yükünü azaltır (sadece SELECT ve INSERT).
- **`-f script.sql`:** Kendi SQL senaryonuzu test edin.

---

## 3. Sonuçları Yorumlama (TPS)

Test bittiğinde karşınıza şöyle bir özet gelir:

```text
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 100
query mode: simple
number of clients: 10
number of threads: 2
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 45230
number of failed transactions: 0 (0.000%)
latency average = 13.266 ms
initial connection time = 15.420 ms
tps = 753.843210 (including connections establishing)
tps = 755.123456 (excluding connections establishing)
```

### Kritik Metrikler

1. **TPS (Transactions Per Second):** Saniyede işlenen işlem sayısı. Ne kadar yüksekse o kadar iyi.
2. **Latency Average:** Bir işlemin ortalama yanıt süresi (milisaniye). Ne kadar düşükse o kadar iyi. 20ms altı idealdir.
3. **TPS (excluding connections):** Bağlantı kurma süresi hariç performans. Pooler (PgBouncer) kullanıyorsanız bu değer daha gerçekçidir.

---

## 4. Özel Senaryolar (Custom Scripts)

Uygulamanızın gerçek yükünü simüle etmek için kendi SQL dosyanızı oluşturun.

**`search.sql`:**

```sql
\set id random(1, 1000000)
SELECT * FROM products WHERE id = :id;
```

**Çalıştır:**

```bash
pgbench -f search.sql -c 50 -j 4 -T 120 mydb
```

---

## 5. Capacity Planning (Kapasite Planlama)

Kaç kullanıcıya hizmet verebilirsiniz?

### 1-2-10 Kuralı

- **TPS < 100:** Geliştirme/Lab ortamı.
- **TPS 100 - 1000:** Küçük-Orta ölçekli uygulama.
- **TPS 1000 - 10000:** Yüksek trafikli sistem (Hobi projelerinden fazlası).
- **TPS > 50000:** Bankacılık/Telecom seviyesi (Çok iyi konfigürasyon ve donanım gerekir).

### Sizing (Boyutlandırma)

1. **RAM:** En sıcak verilerinizin (Working Set) RAM'e sığması gerekir. `shared_buffers` ayarı test sonuçlarını %200 etkileyebilir.
2. **I/O (Disk):** Yazma odaklı testlerde (`-i` sonrası default test) disk IOPS sınırı dar boğaz yaratır. SSD/NVMe zorunludur.
3. **CPU:** Okuma odaklı (`-S`) testlerde CPU hızı ve thread sayısı belirleyicidir.

---

## 6. Benchmarking İpuçları

1. **Testi Isıtın (Warm-up):** Veriler RAM'e çıkana kadar ilk 1-2 dakika sonuçlar düşük çıkabilir. Uzun süreli (`-T 300`) testler daha güvenilirdir.
2. **İzole Edin:** Test yaparken sunucuda başka ağır işlem (backup vb.) olmamasına dikkat edin.
3. **PgBouncer Farkı:** Aynı testi `-c 100` ile PgBouncer varken ve yokken yapın. Pooler'ın TPS'i nasıl koruduğunu (Latency spike'ları engellediğini) göreceksiniz.
