# Streaming ve Mantıksal (Logical) Replikasyon Mimarisi

PostgreSQL, modern veri mimarilerinde yüksek erişilebilirlik (HA), felaket kurtarma (DR), okuma ölçeklendirme ve veri entegrasyonu sağlamak amacıyla iki temel replikasyon mekanizması sunar: **Fiziksel Streaming Replikasyon** ve **Mantıksal (Logical) Replikasyon**.

Bu rehberde; her iki replikasyon modelinin iç çalışma prensiplerini, eşzamanlı (sync) ve eşzamansız (async) modları, replikasyon yuvalarını (replication slots), basamaklı (cascading) replikasyonu ve mantıksal yayın/abone (pub/sub) mimarisini derinlemesine inceleyeceğiz.

---

## 1. Fiziksel ve Mantıksal Replikasyon Karşılaştırması

```
[ FİZİKSEL STREAMING REPLİKASYON ]
Primary: WAL Blokları (16MB Segmentler) ──────► Standby: Birebir Disk Kopyası (Salt Okunur)
(Tüm küme, aynı OS mimarisi, aynı PG majör sürümü)

[ MANTIKSAL (LOGICAL) REPLİKASYON ]
Publisher: Değişiklik Akışı (Decoded Row Changes) ──► Subscriber: INSERT/UPDATE/DELETE
(Farklı tablolar, farklı PG sürümleri, hedefte yazılabilir tablolar)
```

| Kriter | Fiziksel Streaming Replikasyon | Mantıksal (Logical) Replikasyon |
| :--- | :--- | :--- |
| **Birim Düzeyi** | Tüm veritabanı kümesi ($PGDATA) | Veritabanı veya seçili tablolar |
| **Sürüm Uyumluluğu** | Aynı majör PostgreSQL sürümü zorunlu | **Farklı majör sürümler arasında çalışır** (Örn: PG 14 ➔ PG 16) |
| **Hedef Düğümün Durumu** | Salt okunur (Hot Standby) | **Okunabilir ve Yerel Olarak Yazılabilir** |
| **DDL ve Şema Değişiklikleri** | Otomatik replike edilir | Otomatik replike **edilmez** (Elle uygulanmalıdır) |
| **Bölümlendirme ve Süzme** | Yapılamaz (Tüm veritabanları akar) | **WHERE koşulları ve kolon listeleriyle süzülebilir** |
| **Sekanslar (Sequences)** | Otomatik replike edilir | Değerler otomatik senkronize edilmez |

---

## 2. Fiziksel Streaming Replikasyon Mimarisi

### 2.1. Kritik Yapılandırma Parametreleri (`postgresql.conf`)

```ini
# Primary Sunucu
wal_level = 'replica'             # Minimum 'replica' seviyesi zorunludur
max_wal_senders = 10              # Eşzamanlı walsender süreç sayısı
max_replication_slots = 10        # Replikasyon yuvası üst limiti
wal_keep_size = 4096MB            # Disk dolmadan önce tutulacak WAL miktarı (PG 13+)

# Standby Sunucu
hot_standby = on                  # Standby üzerinde SELECT sorgularına izin ver
hot_standby_feedback = on         # Standby'daki uzun sorguların vacuum tarafından silinmesini önle
```

### 2.2. Replikasyon Yuvaları (Replication Slots)

Geleneksel yapılarda standby geride kaldığında primary WAL segmentlerini silebilir ve replikasyon çökerdi. **Replication Slot**, Standby ilgili LSN noktasını onaylayana kadar Primary'nin WAL silmesini donanımsal olarak engeller:

```sql
-- Primary üzerinde replikasyon yuvası oluşturma
SELECT pg_create_physical_replication_slot('standby_node2_slot');

-- Mevcut yuvaları ve gecikmeleri izleme
SELECT slot_name, plugin, active, wal_status, restart_lsn 
FROM pg_replication_slots;
```

> [!CAUTION]
> Eğer bir Standby uzun süre kapanır veya çökerse, ilgili Replication Slot Primary diskinde WAL dosyalarının birikmesine ve diskin %100 dolmasına neden olabilir! Kullanılmayan yuvalar `pg_drop_replication_slot('slot_adi')` ile silinmelidir.

### 2.3. Eşzamanlı (Synchronous) vs Eşzamansız (Asynchronous) Modlar

PostgreSQL'de bir işlemin (`COMMIT`) ne zaman başarılı sayılacağını `synchronous_commit` ve `synchronous_standby_names` yönetir:

```ini
# Primary üzerinde:
synchronous_standby_names = 'FIRST 1 (node2, node3)'  # node2 aktifse ona, çökerse node3'e yaz
# veya quorum oylaması:
# synchronous_standby_names = 'ANY 2 (node2, node3, node4)'
```

| `synchronous_commit` Seviyesi | Açıklama | Performans / Güvenlik |
| :--- | :--- | :--- |
| `off` | WAL diske yazılmadan önce istemciye commit yanıtı döner. | En hızlı, çökmede birkaç ms kayıp olabilir. |
| `local` | Sadece yerel diske flush edilince commit kabul edilir (Standby beklenmez). | Standart async replikasyon. |
| `on` (Varsayılan sync) | WAL yerel diske ve Standby'ın belleğine/diskine yazılana kadar commit bekler. | Yüksek veri güvenliği, ağ gecikmesi eklenir. |
| `remote_apply` | WAL, Standby üzerinde **fiziksel olarak veritabanına işlenene (apply)** kadar commit bekler. | Kesin tutarlılık (Read-after-write consistency), en yavaş. |

### 2.4. Basamaklı Replikasyon (Cascading Standby)

Çok sayıda standby sunucunun Primary üzerindeki ağ ve CPU yükünü (walsender) hafifletmek için Standby sunucular birbirine zincirlenebilir:

```
[ Primary ] ──► [ Standby 1 (Upstream) ] ──► [ Standby 2 ]
                                         ──► [ Standby 3 ]
```

`Standby 2`'nin `primary_conninfo` parametresi doğrudan `Standby 1`'in IP adresini gösterecek şekilde yapılandırılır.

---

## 3. Mantıksal (Logical) Replikasyon Mimarisi

Mantıksal replikasyon; PostgreSQL 10 ile gelen, veritabanı değişikliklerini satır tabanlı mantıksal mesajlara dönüştüren (Logical Decoding) Publication ve Subscription modelidir.

```
┌─────────────────────────────────┐                 ┌─────────────────────────────────┐
│       PUBLISHER (Kaynak)        │                 │       SUBSCRIBER (Hedef)        │
│                                 │                 │                                 │
│  CREATE PUBLICATION pub_siparis │  WAL Decoding   │  CREATE SUBSCRIPTION sub_siparis│
│  FOR TABLE siparisler           ├────────────────►│  CONNECTION '...'               │
│  WHERE (durum = 'ONAYLANDI')    │  Mantıksal Akış │  PUBLICATION pub_siparis        │
└─────────────────────────────────┘                 └─────────────────────────────────┘
```

### 3.1. Ön Koşullar

Kaynak (Publisher) sunucuda:

```ini
# postgresql.conf
wal_level = 'logical'
max_replication_slots = 10
max_wal_senders = 10
```

Hedef (Subscriber) sunucuda replike edilecek tabloların şeması önceden oluşturulmuş olmalıdır.

### 3.2. Publication (Yayın) Oluşturma

```sql
-- 1. Tüm tabloları yayınlama
CREATE PUBLICATION tum_tablolar FOR ALL TABLES;

-- 2. Yalnızca belirli tabloları yayınlama
CREATE PUBLICATION musteri_yayini FOR TABLE musteriler, iletisim_bilgileri;

-- 3. Satır filtreli (Row-Filter) ve kolon kısıtlamalı yayın (PG 15+)
CREATE PUBLICATION tr_siparisler FOR TABLE siparisler (id, musteri_id, tutar, durum)
WHERE (ulke = 'TR' AND durum != 'IPTAL');
```

### 3.3. Subscription (Abonelik) Oluşturma

Hedef sunucu üzerinde abonelik başlatılır:

```sql
CREATE SUBSCRIPTION tr_siparis_abone
CONNECTION 'host=192.168.10.101 port=5432 dbname=eticaret user=repl_user password=GucluParola'
PUBLICATION tr_siparisler
WITH (copy_data = true, create_slot = true);
```

Parametreler:
- `copy_data = true`: Abonelik başladığında mevcut verilerin ilk anlık görüntüsünü (initial snapshot) otomatik olarak hedefe kopyalar.
- `create_slot = true`: Kaynak sunucuda otomatik olarak mantıksal replikasyon yuvası oluşturur.

---

## 4. Replikasyon Durumu ve Gecikme (Lag) İzleme

### 4.1. Primary Üzerinden Akış İzleme

```sql
SELECT 
    client_addr, 
    application_name, 
    state, 
    sync_state,
    sync_priority,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS gonderim_gecikmesi_byte,
    pg_wal_lsn_diff(sent_lsn, write_lsn) AS disk_yazma_gecikmesi_byte,
    pg_wal_lsn_diff(write_lsn, flush_lsn) AS flush_gecikmesi_byte,
    pg_wal_lsn_diff(flush_lsn, replay_lsn) AS isletim_gecikmesi_byte
FROM pg_stat_replication;
```

### 4.2. Standby Üzerinden Alıcı Durumu

```sql
SELECT 
    status, 
    receive_start_lsn, 
    received_lsn, 
    last_msg_send_time, 
    last_msg_receipt_time, 
    latest_end_lsn 
FROM pg_stat_wal_receiver;
```

### 4.3. Mantıksal Replikasyon Çatışma (Conflict) Çözümü

Eğer subscriber tarafında hedef tabloda aynı Primary Key'e sahip bir satır elle eklenmişse, publisher'dan gelen INSERT işlemi bir çakışmaya (duplicate key error) neden olur ve abonelik kilitlenir.

Çözüm:
1. Hedefteki çakışan satır düzeltilir veya silinir.
2. Ya da işlem atlatılır (PG 15+):
   ```sql
   ALTER SUBSCRIPTION tr_siparis_abone SKIP (lsn = '0/16B2D40');
   ```
