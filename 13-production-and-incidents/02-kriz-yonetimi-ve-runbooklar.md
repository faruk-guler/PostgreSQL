# Kriz Yönetimi: DBA Acil Müdahale Senaryoları (Runbooks)

> **Bölüm Kapsamı:** Üretim (production) ortamında karşılaşılan saniyelik kriz anlarında soğukkanlılıkla yapılması gereken acil durum (runbook) prosedürleri.

---

## Veritabanı Sorun Giderme (Troubleshooting) Karar Ağacı

Kriz anında sorunun kaynağını hızlıca tespit etmek için aşağıdaki karar ağacını takip edebilirsiniz:

```mermaid
graph TD
    Start((Kriz Başlangıcı)) --> Q1{Veritabanı<br>Ayakta mı?}
    
    %% DB DOWN BRANCH
    Q1 -->|Hayır (Down)| Q2{Loglarda<br>Ne Yazıyor?}
    Q2 -->|PANIC / No Space| A1[Disk %100 Doldu<br>WAL Panic]
    Q2 -->|OOM Killer| A2[Out of Memory<br>RAM Tükendi]
    Q2 -->|Wraparound| A3[XID Freeze<br>Transaction Sınırı]
    
    A1 --> R1(Runbook 1'e Git)
    A2 --> R4(Runbook 4'e Git)
    A3 --> R2(Runbook 2'e Git)

    %% DB UP BRANCH
    Q1 -->|Evet (Up)| Q3{Uygulama<br>Bağlanabiliyor mu?}
    Q3 -->|Hayır (Timeout/Limit)| A4[Bağlantı Patlaması<br>Max_Connections]
    A4 --> R3(Runbook 3'e Git)
    
    Q3 -->|Evet ama Yavaş| Q4{CPU mu I/O mu<br>Tükendi?}
    Q4 -->|CPU %100| A5[Eksik İndeks<br>Kötü Sorgu<br>Loop]
    Q4 -->|Disk I/O %100| A6[Sürekli Seq Scan<br>Autovacuum Bloat]
    Q4 -->|Normal| A7[Lock / Deadlock<br>Beklemesi]
    
    A5 --> S1(pg_stat_statements İncele)
    A6 --> S2(VACUUM / Index Optimize Et)
    A7 --> S3(pg_locks İncele)
```

---

## 1. Disk %100 Doldu ve PostgreSQL Durdu (WAL Panic)

PostgreSQL'in kurulu olduğu disk (genellikle `/var/lib/postgresql`) veya WAL (Write-Ahead Log) diski %100 dolarsa, veritabanı "PANIC" vererek kendini kapatır. Başlatmaya çalışsanız da hata alırsınız.

### ❌ Asla Yapılmaması Gerekenler
- **ASLA** `pg_wal` (veya `pg_xlog`) dizinindeki dosyaları manuel olarak (rm ile) silmeyin! Veritabanı tutarlılığını kalıcı olarak bozarsınız.

### ✅ Acil Müdahale Adımları (Runbook)

**Adım 1: Diskte geçici yer açın (Logları veya gereksiz dosyaları silin)**
```bash
# Sadece log dosyalarını arşivleyin veya eski logları silin.
find /var/log/postgresql/ -type f -name "*.log" -mtime +7 -exec rm {} \;
```

**Adım 2: Gerekiyorsa PostgreSQL dışı dosya temizliği**
Eğer aynı sunucuda başka uygulamalar varsa, öncelikle onların temp dosyalarını temizleyin. Veritabanının açılması için 100MB bile yeterli olabilir.

**Adım 3: PostgreSQL'i başlatın ve `pg_wal` şişmesini engelleyin**
Eğer replikasyon nedeniyle WAL'lar biriktiyse, veritabanı açılır açılmaz Replication Slot'ları düşürün:
```sql
-- Hangi slot diski dolduruyor?
SELECT slot_name, plugin, slot_type, active, restart_lsn 
FROM pg_replication_slots;

-- Kullanılmayan / takılı kalmış slotu silin (WAL'ların serbest kalmasını sağlar)
SELECT pg_drop_replication_slot('takili_kalan_slot_adi');
```

---

## 2. Transaction ID Wraparound (XID Freeze) Krizi

PostgreSQL her işleme 32-bit'lik bir ID (XID) atar. XID sınırı (~2.1 milyar) dolmaya yaklaştığında sistem *"WARNING: database is not accepting commands to avoid wraparound data loss"* hatası vererek kendini salt-okunur (read-only) duruma alır.

### ✅ Acil Müdahale Adımları (Runbook)

**Adım 1: Single-User Mode (Tek Kullanıcı Modu) ile başlatma**
Veritabanı normal yollarla sorgu kabul etmiyorsa servisi durdurup single-user modunda başlatın:
```bash
systemctl stop postgresql-16
sudo -u postgres -D /var/lib/pgsql/16/data postgres --single -D /var/lib/pgsql/16/data postgres
```

**Adım 2: Manuel Vacuum Freeze (Dondurma)**
Single-user modunda direkt SQL komutu yazabilirsiniz:
```sql
VACUUM FREEZE VERBOSE;
```
Bu işlem veritabanı boyutuna göre uzun sürebilir. Sadece en sorunlu (en yaşlı) tabloyu tespit edebiliyorsanız sadece o tabloya `VACUUM FREEZE tablo_adi;` yapın.

---

## 3. Bağlantı Patlaması (Max_Connections Aşıldı)

Sistem *"FATAL: sorry, too many clients already"* hatası veriyor ve veritabanı kilitlendi, hiçbir uygulama bağlanamıyor. Siz de (DBA) `psql` ile bağlanamıyorsunuz.

### ✅ Acil Müdahale Adımları (Runbook)

**Adım 1: Acil (Reserved) Bağlantı Açma**
PostgreSQL `superuser_reserved_connections` parametresi ile (varsayılan: 3) sadece superuser'lara özel boş bağlantı ayırır. Hemen `postgres` kullanıcısı ile doğrudan terminalden bağlanın:
```bash
psql -U postgres -d postgres
```

**Adım 2: Boşta Duran (Idle) Bağlantıları Kapatma (Terminate)**
Tüm slotları dolduran ama hiçbir şey yapmayan bağlantıları topluca vurun:
```sql
-- 5 dakikadan uzun süredir "idle" olan tüm bağlantıları kapat
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < current_timestamp - INTERVAL '5 minutes'
  AND pid <> pg_backend_pid();
```

---

## 4. OOM (Out of Memory) Killer Veritabanını Kestiğinde

Linux işletim sistemi belleği tükettiğinde OOM-Killer devreye girer ve en çok RAM tüketen prosesi (genellikle PostgreSQL/postmaster) öldürür. Loglarda `Killed process 1234 (postgres)` veya *"terminating connection due to administrator command"* görülür.

### ✅ Acil Müdahale Adımları (Runbook)

**Adım 1: Kernel OOM Loglarını İnceleyin**
```bash
dmesg -T | egrep -i 'killed process'
```

**Adım 2: Geçici Olarak Bellek Tüketimini (work_mem) Azaltın**
Eğer OOM sebebi spesifik bir analitik sorguysa, `work_mem` yüksek olabilir.
```sql
-- Mevcut oturumda veya sistem genelinde düşürün
ALTER SYSTEM SET work_mem = '4MB';
SELECT pg_reload_conf();
```

**Adım 3: Swap ve Overcommit Ayarı (Önlem)**
PostgreSQL dokümanları `vm.overcommit_memory = 2` önerir (OOM killer'ı pasifize eder ve bellek bittiğinde fail verir, veritabanını öldürmez):
```bash
sysctl -w vm.overcommit_memory=2
```

---

> **Özet:** Kriz anlarında en önemli kural **panik yapmamaktır**. Logları inceleyin, `pg_wal` ve konfigürasyon dosyalarına asla manuel müdahale etmeyin.
