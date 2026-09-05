# Yüksek Erişilebilirlik (HA) ve Streaming Replikasyon

Üretim (Production) ortamlarında tek bir veritabanı sunucusuna (Master) bel bağlamak büyük bir risktir. Donanım arızası veya ağ kesintisi yaşandığında sisteminizin kapanmaması için en az bir adet yedek sunucu (Standby/Slave) bulundurulmalıdır.

PostgreSQL'de yüksek erişilebilirlik, **Streaming Replication (Akış Replikasyonu)** mimarisi üzerine kurulur.

---

## 1. Streaming Replication Nasıl Çalışır?

PostgreSQL'de her `INSERT`, `UPDATE`, `DELETE` işlemi önce RAM'e, ardından diske **WAL (Write-Ahead Log)** adlı bir işlem günlüğü dosyasına yazılır. 

Streaming Replication mantığı basittir: Master sunucu üzerinde üretilen bu WAL dosyaları veya blokları, anlık olarak ağ (Network) üzerinden Standby sunucuya gönderilir (Stream edilir). Standby sunucu bu logları alır ve sanki sorgular kendi üzerinde çalışmış gibi birebir aynı işlemleri (Redo/Replay) uygular.

*   **Master Sunucu (Primary):** Okuma ve Yazma (Read/Write) yapılabilen ana sunucudur.
*   **Standby Sunucu (Replica):** Sadece okuma (Read-Only) yapılabilen kopyadır (Hot Standby özelliği açıksa).

### Replikasyon Türleri
*   **Asynchronous (Asenkron) Replikasyon:** Master sunucu sorguyu çalıştırır, istemciye (Client) "Başarılı" döner, WAL dosyasını arkadan gönderir. Çok hızlıdır, ancak elektrik aniden kesilirse son saniyelerdeki veri henüz Standby'a gitmemiş olabilir.
*   **Synchronous (Senkron) Replikasyon:** Master sunucu işlemi yapar, Standby'a yollar ve Standby'dan "Bana ulaştı ve diske yazıldı" onayı gelene kadar istemciye cevap dönmez. Kesinlikle veri kaybı olmaz (Zero Data Loss), ama performansı bir miktar düşürür (Ağ gecikmesi kadar).

---

## 2. Replikasyon Kurulum Adımları (Özet)

**A. Master Sunucu (192.168.1.5) Hazırlıkları**
1. Replikasyon yapacak özel bir kullanıcı oluşturulur:
   ```sql
   CREATE ROLE replicauser WITH REPLICATION LOGIN ENCRYPTED PASSWORD 'sifre';
   ```
2. `pg_hba.conf` dosyasında bu kullanıcıya Standby IP'sinden izin verilir:
   ```text
   host replication replicauser 192.168.1.10/32 md5
   ```
3. `postgresql.conf` içinde WAL ayarları açılır:
   ```ini
   wal_level = replica
   max_wal_senders = 10
   ```
4. Sunucu yeniden başlatılır (Restart).

**B. Standby Sunucu (192.168.1.10) Hazırlıkları**
1. Standby sunucu tamamen boşaltılır ve Master'ın tüm veri klasörü (Base Backup) ağ üzerinden kopyalanır:
   ```bash
   pg_basebackup -h 192.168.1.5 -U replicauser -D /var/lib/pgsql/13/data -Fp -Xs -P -R
   ```
   *(Buradaki `-R` parametresi, otomatik olarak Master'a bağlanma ayarlarını içeren dosyayı oluşturur).*
2. `postgresql.conf` içinde Standby'ın okumaya açık olması sağlanır:
   ```ini
   hot_standby = on
   ```
3. Standby sunucu başlatılır (Start). Artık veriler anlık olarak senkronize olacaktır.

---

## 3. Failover (Yük Devretme)

Master sunucu donanımsal olarak çökerse, Standby sunucuyu yeni Master ilan etme işlemine **Failover** denir.

Standby sunucudayken bu komut çalıştırılırsa, sunucu anında "Okuma/Yazma" (Master) moduna geçer:
```sql
SELECT pg_promote();
```

> [!WARNING]
> Bir sunucu `pg_promote` ile Master yapıldıktan sonra, eski Master sunucu geri gelse bile kaldığı yerden Standby olarak çalışmaya devam edemez. Eski sunucu formatlanıp (pg_basebackup atılıp) yeni Master'a bağlanmak zorundadır (Aksi takdirde Split-Brain, yani aynı veritabanının iki farklı Master'a ayrışması ve verilerin bozulması senaryosu yaşanır). 
> 
> Üretim ortamlarında Failover işlemleri genellikle **Patroni**, **repmgr** veya **Keepalived** gibi otomatik HA yazılımlarıyla yönetilir.
