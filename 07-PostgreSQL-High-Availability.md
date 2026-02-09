# 07-PostgreSQL-High-Availability

Veritabanınız çöktüğünde işletmeniz duruyorsa, "High Availability" (Yüksek Erişilebilirlik) bir lüks değil, zorunluluktur. PostgreSQL bu konuda çok güçlü replikasyon yeteneklerine sahiptir.

## Diğer HA Çözümleri

- **Repmgr:** Replikasyon yönetimi için klasik ve popüler bir araçtır. Patroni kadar otonom değildir ancak kurulumu daha basittir. Failover süreçlerini manuel veya yarı-otomatik yönetir.
- **PgPool-II:** Sadece bir Connection Pool değil, aynı zamanda Load Balancer ve HA yöneticisidir. Sorguları (SELECT) farklı node'lara dağıtabilir (Query Routing) ve Watchdog özelliği ile VIP yönetimi yapar.

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
|:----|:---------|:-----------------|:-----------|
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

```
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

> [!WARNING]
> Kendi yazdığınız Shell scriptleriyle otomatik failover yapmaya çalışmayın! "Split-Brain" (İki sunucunun da kendini Primary sanıp veri yazması) felaketine yol açabilir. Veri bütünlüğü için Patroni kullanın.
