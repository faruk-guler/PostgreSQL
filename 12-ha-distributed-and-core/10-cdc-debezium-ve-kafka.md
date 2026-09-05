# Change Data Capture (CDC): Debezium ve Kafka

> **Bölüm Kapsamı:** Gerçek Zamanlı Veri Akışı (Streaming), Logical Replication Kavramları, Debezium Mimarisi ve Event-Driven Microservices

---

## 1. Change Data Capture (CDC) Nedir?

Geleneksel mimarilerde, veritabanındaki bir değişikliği (INSERT/UPDATE/DELETE) başka bir sisteme (örneğin Elasticsearch, Redis veya Veri Ambarı) aktarmak için sürekli veritabanına `SELECT * FROM users WHERE updated_at > last_check` gibi sorgular (Polling) atılırdı. 
Bu yöntem hem veritabanını yorar hem de gecikmeli (latency) çalışır. Ayrıca silinen (DELETE) kayıtları yakalayamazsınız!

**Çözüm CDC'dir:** Veritabanının kendi iç loglarını (WAL - Write Ahead Log) okuyarak, her değişikliği anlık ve garantili bir şekilde bir mesaj kuyruğuna (Kafka) gönderme işlemine Change Data Capture denir.

---

## 2. PostgreSQL Logical Replication ve WAL

CDC işleminin kalbinde PostgreSQL'in **Logical Decoding** yeteneği yatar.

PostgreSQL'de iki tür replikasyon vardır:
1. **Physical (Streaming) Replication:** Byte-byte diskteki veriyi kopyalar. Primary ve Replica birebir aynı olmalıdır. (Bkz: Standart HA).
2. **Logical Replication:** WAL loglarını okur, bunları SQL benzeri mantıksal olaylara (`INSERT tablo_adi id=5`) çevirir. 

Logical Replication kullanabilmek için `postgresql.conf` dosyasında şu ayar şarttır:
```ini
wal_level = logical
```

---

## 3. Debezium Mimarisi

Debezium, Red Hat tarafından desteklenen, veritabanlarından CDC verisi okumak için endüstri standardı haline gelmiş bir Apache Kafka Connect eklentisidir.

### Sistem Nasıl Çalışır?

1. **Uygulama** -> PostgreSQL'e `UPDATE users SET status = 'active' WHERE id = 1` yazar.
2. PostgreSQL bu değişikliği kendi WAL dosyasına kaydeder.
3. **Debezium (Kafka Connector)**, PostgreSQL'e sanki bir "Replica" sunucuymuş gibi bağlanır (Replication Slot oluşturur).
4. Debezium, WAL'dan bu değişikliği okur ve JSON (veya Avro) formatına çevirir.
5. Debezium bu JSON mesajını **Apache Kafka**'daki `server1.public.users` adlı bir konuya (Topic) fırlatır.
6. **Diğer Mikroservisler** -> Kafka'yı dinleyerek saniyeler içinde Elasticsearch'ü, Cache'i veya Analitik veritabanını günceller.

---

## 4. Debezium İçin PostgreSQL Hazırlığı

Debezium'un veritabanını izleyebilmesi için özel bir kullanıcıya ve yetkilere ihtiyacı vardır.

```sql
-- 1. CDC için özel bir kullanıcı oluştur (Süper yetkilere ihtiyaç yok, sadece replikasyon yetkisi yeter)
CREATE ROLE debezium_user REPLICATION LOGIN PASSWORD 'cok_gizli_sifre';

-- 2. İlgili tablolara okuma yetkisi ver
GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium_user;

-- 3. Replica Identity Ayarı (Kritik!)
-- UPDATE ve DELETE işlemlerinde, Debezium'un satırın "eski" halini (before state) bilmesi için tablonun Replica Identity'sini ayarlamak gerekir.
ALTER TABLE users REPLICA IDENTITY FULL; 
-- (Not: FULL yapmak tüm sütunların eski halini loglar, diski biraz yorar. Sadece PK yeterliyse DEFAULT bırakılabilir).
```

### pg_hba.conf Ayarı
Debezium'un IP adresinden gelen replikasyon bağlantılarına izin vermelisiniz:
```text
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    replication     debezium_user   10.0.0.50/32            scram-sha-256
```

---

## 5. CDC Mesaj Formatı (Debezium Payload)

Debezium'un Kafka'ya gönderdiği tipik bir mesaj şu şekildedir:

```json
{
  "before": {
    "id": 1,
    "email": "user@old.com",
    "status": "pending"
  },
  "after": {
    "id": 1,
    "email": "user@old.com",
    "status": "active"
  },
  "source": {
    "version": "1.9.5.Final",
    "connector": "postgresql",
    "db": "mydb",
    "schema": "public",
    "table": "users",
    "txId": 5021,
    "lsn": 29384729
  },
  "op": "u" // u = Update, c = Create(Insert), d = Delete
}
```

Bu yapı sayesinde Kafka'yı dinleyen bir "Search Service" (Örn: Elasticsearch consumer'ı), verinin sadece yeni halini değil, eski halini de bilerek indeksleri kusursuz güncelleyebilir.

---

## 6. Sık Karşılaşılan Sorunlar ve Çözümleri

### ❌ Replication Slot'un Şişmesi (WAL Birikmesi)
Eğer Kafka veya Debezium çökerse, PostgreSQL veriyi göndereceği yeri beklediği için WAL dosyalarını diskten silmez. Günler geçerse PostgreSQL sunucusunun **diski %100 dolar ve sunucu çöker!**

**✅ Çözüm:** 
PostgreSQL 13+ ile gelen `max_slot_wal_keep_size` parametresini ayarlayın. Bu değer aşılırsa, PostgreSQL kendi canını kurtarmak için replication slot'u kırar ve diski temizler (Debezium veriyi baştan okumak -snapshot- zorunda kalır ama veritabanı ayakta kalır).
```ini
max_slot_wal_keep_size = 50GB
```

### ❌ DDL Değişiklikleri (Şema Değişmesi)
Tabloya yeni sütun eklediğinizde Debezium bunu yakalar, ancak hedef sistemler (Consumer'lar) bu yeni JSON yapısına (Schema Registry) hazır değilse Kafka pipeline'ı patlayabilir. Şema değişiklikleri her zaman koordineli yapılmalıdır.
