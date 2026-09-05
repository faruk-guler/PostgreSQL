# Yüksek Erişilebilirlik (High Availability) ve Replikasyon

> **Bölüm Kapsamı:** Streaming Replication, Logical Replication, Senkron Modlar, Patroni ve Otomatik Yük Devretme

---

## 1. Streaming Replication (Standart Replikasyon)

PostgreSQL'in en yaygın kullanılan HA yöntemidir. Birincil sunucudaki (Primary) tüm değişiklikleri (WAL kayıtlarını) anlık olarak yedek sunucuya (Standby) aktarır.

### Mimari

- **Primary:** Okuma ve Yazma (Read/Write) kabul eder.
- **Standby (Replica):** Sadece Okuma (Read-Only) kabul eder. Raporlama sorgularını buraya yönlendirerek Primary üzerindeki yükü azaltabilirsiniz.

### Kurulum Mantığı

1. Standby sunucusu, Primary'den `pg_basebackup` ile kopyalanır.
2. Standby, Primary'ye bağlanıp WAL kayıtlarını ister (`wal_receiver` süreci).
3. Primary, WAL kayıtlarını gönderir (`wal_sender` süreci).
4. Standby, aldığı kayıtları kendi diskine uygular (`startup` süreci).

### Senkron vs Asenkron

- **Asynchronous (Varsayılan):** Primary, işlemi commit eder etmez istemciye "Tamam" der. Standby'a veri gitmesi saniyelik de olsa gecikebilir. Performans yüksektir ama veri kaybı riski (çok az) vardır.
- **Synchronous:** Primary, en az bir Standby "Ben de yazdım" diyene kadar işlemi bitirmez. Veri kaybı sıfırdır (`RPO=0`) ama Standby yavaşlarsa Primary de yavaşlar.

### Synchronous Replication Modları (Detaylı)

PostgreSQL, `synchronous_commit` parametresi ile farklı senkronizasyon seviyeleri sunar:

```ini
# postgresql.conf
synchronous_commit = remote_apply  # En güvenli mod
```

| Mod | Açıklama | Veri Kaybı Riski | Performans |
| :---- | :--------- | :----------------- | :----------- |
| **off** | Hiç bekleme, anında commit | Yüksek (saniyeler) | En hızlı |
| **local** | Sadece local WAL'a yaz | Orta (crash'te kayıp var) | Hızlı |
| **remote_write** | Standby OS buffer'a yazdı | Düşük (OS crash'te kayıp) | Orta |
| **on** (default) | Standby WAL'a yazdı (disk) | Çok düşük | Yavaş |
| **remote_apply** | Standby veriyi uyguladı | Sıfır (RPO=0) | En yavaş |

**Hangi Standby'lar Senkron?**

```ini
# postgresql.conf
synchronous_standby_names = 'FIRST 1 (standby1, standby2)'
# İlk yanıt veren 1 standby yeterli

# Veya Quorum-based (Çoğunluk):
synchronous_standby_names = 'ANY 2 (standby1, standby2, standby3)'
# 3 standby'dan en az 2'si onaylamalı
```

### Cascading Replication (Kademeli Replikasyon)

Standby sunucular, başka Standby'lara da veri gönderebilir (zincirleme). Bu, coğrafi dağıtım için idealdir.

**Mimari:**

```text
Primary (İstanbul)
  └─> Standby1 (Ankara) 
        └─> Standby2 (İzmir)
```

**Kurulum:**

1. Standby1'i Primary'den normal şekilde oluşturun.
2. Standby2'yi Standby1'den `pg_basebackup` ile kopyalayın:

   ```bash
   pg_basebackup -h standby1_ip -D /var/lib/pgsql/16/data -U replicator -P -R
   ```

3. Standby2, Standby1'e bağlanır ve WAL alır.

**Avantajı:** Primary'nin ağ yükü azalır. Dezavantaj: Standby1 çökerse Standby2 de durur (Patroni bunu otomatik çözer).

---

## 2. Logical Replication (Esnek Replikasyon)

Streaming Replication tüm veritabanını (cluster) kopyalar. Logical Replication ise tablo bazlıdır.

### Kullanım Alanları

1. **Sürüm Yükseltme (Zero-Downtime Upgrade):** PostgreSQL 14'ten 16'ya kesintisiz geçiş. Veriyi yeni sürüme replike edip trafiği oraya yönlendirebilirsiniz.
2. **ETL / Data Warehouse:** Sadece raporlama için gerekli tabloları analitik sunucusuna aktarmak.
3. **Farklı OS:** Linux'tan Windows'a veya tam tersi replikasyon.

### Yapı (Pub/Sub)

- **Publication (Yayıncı):** Hangi tabloların gönderileceğini seçer.

  ```sql
  CREATE PUBLICATION my_pub FOR TABLE users, orders;
  ```

- **Subscription (Abone):** Yayına abone olur ve veriyi çeker.

  ```sql
  CREATE SUBSCRIPTION my_sub CONNECTION 'host=primary_ip dbname=mydb' PUBLICATION my_pub;
  ```

---

## 3. Automatic Failover (Otomatik Geçiş)

**Kritik Bilgi:** PostgreSQL'in ("Core") kendisinde "Otomatik Failover" mekanizması YOKTUR. Eğer Primary çökerse, Standby kendiliğinden Primary olmaz. Bunu sizin tetiklemeniz (`pg_ctl promote`) gerekir.

Bu süreci otomatize etmek için harici araçlar kullanılır.

### a. Patroni (Endüstri Standardı)

Python ile yazılmış, modern ve en güvenilir HA çözümüdür.

- **Nasıl Çalışır:** Sunucuların durumunu "Distributed Key-Value Store" (etcd, Consul veya ZooKeeper) üzerinde tutar.
- **Leader Election:** Primary çökerse, Patroni instance'ları aralarında oylama yapar ve en güncel Standby'ı yeni Primary ilan eder.
- **Split-Brain Koruması:** Eskiden Primary olan sunucu geri gelirse, onun artık Primary olmadığını bilir ve onu Standby olarak sisteme ekler.

### b. HAProxy & PgBouncer

Uygulamanızın her failover işleminde IP adresi değiştirmesi zordur. Bunun yerine uygulama her zaman bir "Load Balancer"a (HAProxy) bağlanır.

- HAProxy, Patroni'nin API'sine sorarak "Şu an Primary kim?" diye öğrenir ve trafiği oraya yönlendirir.

**Modern HA Mimarisi (Patroni + HAProxy + PgBouncer)**

```mermaid
graph TD
    App[Uygulama Sunucuları] -->|Read/Write (Port 5000)| HAProxy[HAProxy Load Balancer]
    App -->|Read-Only (Port 5001)| HAProxy
    
    HAProxy -->|Health Check| PatroniAPI(Patroni REST API)
    
    subgraph Node 1 (Aktif)
        Patroni1[Patroni] -->|Yönetir| PG1[(PostgreSQL Primary)]
        PgBouncer1[PgBouncer] --> PG1
    end
    
    subgraph Node 2 (Pasif)
        Patroni2[Patroni] -->|Yönetir| PG2[(PostgreSQL Standby)]
        PgBouncer2[PgBouncer] --> PG2
    end
    
    subgraph Node 3 (Pasif)
        Patroni3[Patroni] -->|Yönetir| PG3[(PostgreSQL Standby)]
        PgBouncer3[PgBouncer] --> PG3
    end
    
    HAProxy -->|R/W Trafik| PgBouncer1
    HAProxy -.->|R/O Trafik| PgBouncer2
    HAProxy -.->|R/O Trafik| PgBouncer3
    
    PG1 ===>|Streaming Replication| PG2
    PG1 ===>|Streaming Replication| PG3
    
    etcd[(etcd Cluster)] -.->|DCS State| Patroni1
    etcd -.->|DCS State| Patroni2
    etcd -.->|DCS State| Patroni3
```

### c. Alternatif HA Araçları ve Mimari Karşılaştırma

PostgreSQL ekosisteminde Patroni dışında da yaygın kullanılan yüksek erişilebilirlik çözümleri bulunmaktadır. Projenin altyapı karmaşıklığına göre doğru aracı seçmek hayati önem taşır:

- **repmgr (Replication Manager):** 2ndQuadrant tarafından geliştirilen popüler bir replikasyon yönetim aracıdır. En büyük avantajı, harici bir dağıtık mutabakat deposuna (`etcd`, `Consul` vb.) ihtiyaç duymamasıdır; tüm küme durumunu PostgreSQL içindeki `repmgr` şemasında tutar. `repmgrd` arka plan servisi ile otomatik failover yapabilir. Ancak ağ kopmalarında Split-Brain'i engellemek için mutlaka bir **Witness Node (Şahit Düğüm)** ve çok dikkatli bir fencing mekanizması kurulmalıdır.
- **PgPool-II:** Veritabanı ile uygulama arasına giren bir proxy katmanıdır. Connection pooling ve yük dengelemenin (Read/Write splitting) yanı sıra dahili **Watchdog** servisi ile sanal IP (VIP) tabanlı failover sunar. Ancak SQL ayrıştırma (parse) ek yükü getirir ve karmaşık failover senaryolarında Patroni kadar sağlam bir konsensüs sunamaz.

#### HA Çözümleri Karşılaştırma Matrisi

| Kriter / Özellik | Patroni | repmgr | PgPool-II |
| :--- | :--- | :--- | :--- |
| **Konsensüs Mekanizması** | DCS (`etcd`, `Consul`, `K8s`) | Veritabanı İçi Tablo + Quorum | Watchdog Heartbeat / VIP |
| **Split-Brain Koruması** | **Kusursuz (Raft/Paxos garantili)** | Dikkat gerektirir (Witness şart) | Eşik değerine bağlı (Split-brain riski var) |
| **Harici Bağımlılık** | Evet (etcd veya Consul kümesi) | Hayır (Tamamen yerel Postgres) | Hayır |
| **Konteyner / Cloud / K8s Uyumu** | Mükemmel (Endüstri Standardı) | Orta | Orta |
| **Yük Dengeleme (R/W Splitting)** | Harici (HAProxy / PgBouncer ile) | Harici (HAProxy ile) | Yerleşik (SQL düzeyinde analiz) |
| **Önerilen Kullanım Alanı** | Sıfır veri kaybı hedefleyen kurumsal, dinamik ve bulut sistemler | Ayrı bir DCS kümesi kurmak istemeyen klasik on-premise sunucular | Tek bir araçla hem havuzlama hem basit HA isteyen ortamlar |

---

## 4. Replication Slots (Replikasyon Yuvaları)

**Kritik Sorun:** Eğer bir Standby sunucu uzun süre çevrimdışı kalırsa, Primary sunucu WAL dosyalarını silebilir (archive_command çalışmasa bile). Standby geri geldiğinde "WAL dosyası bulunamadı" hatası alır ve replikasyon kopar.

**Çözüm:** Replication Slots. Primary sunucuya "Bu Standby için WAL'ları sakla" diye talimat verir.

### Replication Slot Oluşturma

Primary sunucuda:

```sql
-- Physical Replication Slot (Streaming için)
SELECT * FROM pg_create_physical_replication_slot('standby_slot_1');

-- Mevcut slotları görüntüle
SELECT slot_name, slot_type, active, restart_lsn 
FROM pg_replication_slots;
```

Standby sunucunun `postgresql.conf` dosyasında:

```ini
primary_slot_name = 'standby_slot_1'
```

### Dikkat Edilmesi Gerekenler

> [!CAUTION]
> **Disk Dolma Riski:** Eğer Standby sunucu hiç geri gelmezse, Primary sunucu WAL dosyalarını sonsuza kadar saklar ve disk dolar! Kullanılmayan slotları mutlaka silin:
>
> ```sql
> SELECT pg_drop_replication_slot('standby_slot_1');
> ```

### Monitoring

```sql
-- Slot'un ne kadar WAL biriktirdiğini kontrol et
SELECT slot_name, 
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

---

## 5. Best Practices Özeti

1. **Patroni kullanın** - Manuel failover risklidir.
2. **Replication Slots kullanın** - Ama izleyin!
3. **Synchronous Replication** sadece kritik veriler için - Performans maliyeti yüksektir.
4. **HAProxy + PgBouncer** kombinasyonu ile uygulama tarafını basitleştirin.
5. **Test edin** - Failover senaryolarını production'a geçmeden önce mutlaka test edin.

> [!WARNING]
> Kendi yazdığınız Shell scriptleriyle otomatik failover yapmaya çalışmayın! "Split-Brain" (İki sunucunun da kendini Primary sanıp veri yazması) felaketine yol açabilir. Veri bütünlüğü için Patroni kullanın.
