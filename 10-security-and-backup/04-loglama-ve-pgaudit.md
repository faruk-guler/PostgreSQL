# Veritabanı Loglama ve Audit (PgAudit)

PostgreSQL'de sunucu sağlığını izlemek, yavaş sorguları bulmak ve güvenlik ihlallerini tespit etmek için loglama yapılandırması hayati öneme sahiptir. Varsayılan ayarlar performans odaklı olduğu için çoğu loglamayı kapalı tutar.

## 1. Temel Loglama Parametreleri (`postgresql.conf`)

### Log Hedefi ve Toplama

**`log_destination`**: PostgreSQL'in hangi yöntemle log göndereceğini belirtir:
- `stderr`: Standart error'a yaz
- `csvlog`: CSV formatında tut (analiz araçları için)
- `syslog`: syslog daemon üzerinden gönder
- `eventlog`: Windows Event Logger

**`logging_collector`**: `stderr` veya `csvlog` seçilmişse log toplayıcı süreci başlatır. Bu ayar için PostgreSQL'i yeniden başlatmak gerekir.

**`log_directory`**: Logların tutulacağı dizin (`$PGDATA`'ya göre göreceli veya mutlak yol).

**`log_filename`**: Log dosyasının adı. `date` komutu makrolarını kullanabilir: `'postgresql-%a.log'` → `postgresql-Mon.log`

**`log_truncate_on_rotation`**: Log rotate edildiğinde mevcut dosyanın üzerine yazmayı etkinleştirir.

**`log_rotation_age`**: WAL dosyalarının belirtilen süre sonunda rotate edilmesini sağlar. (Öntanımlı: `1d`)

**`log_rotation_size`**: Log dosyaları belirtilen boyuta gelince otomatik rotate edilir.

### Log İçeriği Kontrol Parametreleri

**`log_line_prefix`**: Log satırlarının başına eklenecek önek. Analiz programları (PgBadger) için çok önemlidir.

| Makro | Açıklama |
|---|---|
| `%a` | Uygulama adı (application name) |
| `%u` | Kullanıcı adı |
| `%d` | Veritabanı adı |
| `%r` | Uzak host ve port |
| `%h` | Uzak host adresi |
| `%p` | Process ID |
| `%t` | Milisaniye olmadan timestamp |
| `%m` | Milisaniyeli timestamp |
| `%i` | Komut etiketi (idle, authentication, SQL vs.) |
| `%e` | SQL state ID |
| `%c` | Oturum ID'si |
| `%l` | O oturumdaki satır no |
| `%s` | Oturum başlama zamanı |
| `%v` | Virtual transaction ID |
| `%x` | Transaction ID |

**`client_min_messages`**: İstemcilere gönderilecek mesajların seviyesi. (`debug5` → `error`)

**`log_min_messages`**: Log dosyasına gönderilecek mesajların miktarı.

**`log_min_error_statement`**: Hataya neden olan SQL mesajının loglanıp loglanmaması. Öntanımlı: `error`.

**`log_min_duration_statement`**: Milisaniye cinsinden belirtilen bu süreden uzun sorguları loglar. `0` = tüm sorgular, `-1` = kapalı.

**`log_statement`**: Hangi SQL ifadelerinin loglanacağı:
- `none`: Hiçbiri (öntanımlı)
- `ddl`: CREATE/DROP/ALTER gibi DDL ifadeleri
- `mod`: DDL + INSERT/UPDATE/COPY/TRUNCATE vs.
- `all`: Tam audit için tüm ifadeler

**`log_lock_waits`**: `deadlock_timeout`'tan fazla süre kilit beklenmesi durumunda log düşer. Örnek:
```log
LOG: process 32603 still waiting for ShareLock on transaction 3284 after 1000.125 ms
STATEMENT: UPDATE film SET fulltext = 'NewFullText';
```

**`log_temp_files`**: Belirtilen boyuta eşit ya da büyük geçici dosya oluştuğunda loglar. `0` = tüm geçici dosyalar. `work_mem` yetersizliğini tespit etmek için kullanılır.

**`log_connections`** / **`log_disconnections`**: Bağlantıları ve kopmaları loglar. Yoğun sunucularda ek yük oluşturabilir ancak audit için açılmalıdır.

**`log_checkpoints`**: Checkpoint bilgilerini loglar (PgBadger analizi için kritik).

**`log_error_verbosity`**: Hata mesajlarının ayrıntı miktarı. `VERBOSE` modunda SQLSTATE, kaynak dosya, fonksiyon ve satır numarası da loglanır.

---

## 2. Temel Loglama Ayarları (Pratik Yapılandırma)

```ini
# Logların Nereye Yazılacağı
logging_collector = on            # Loglama servisini açar
log_directory = 'log'             # Log klasörü (PGDATA içinde)
log_filename = 'postgresql-%a.log'# Haftanın gününe göre dosyalar
log_truncate_on_rotation = on     # Eski dosyanın üzerine yazar

# Nelerin Loglanacağı
log_connections = on              # Bağlantıları yazar
log_disconnections = on           # Kopmaları yazar
log_lock_waits = on               # Kilit beklemelerini yazar
log_temp_files = 0                # Disk'e dökülen sort/hash sorgularını bulur
log_checkpoints = on              # Checkpoint bilgileri

# Yavaş Sorguları Bulmak (Milisaniye Cinsinden)
log_min_duration_statement = 500  # 500ms'den uzun her sorguyu loga yazar
```

### Log Çıktısını Şekillendirme (`log_line_prefix`)

```ini
# Önerilen yapı (PgBadger uyumlu)
log_line_prefix = '< user=%u db=%d host=%h pid=%p app=%a time=%m > '
# Çıktısı:
# < user=postgres db=satis host=192.168.1.10 pid=4520 app=pgAdmin time=2024-01-01 10:00:00.123 >
```

---

## 3. Güvenlik ve İzleme için Önerilen Parametreler

| Parametre | Önerilen Değer | Açıklama |
|---|---|---|
| `log_connections` | `on` | Audit için zorunlu |
| `log_disconnections` | `on` | Audit için zorunlu |
| `log_statement` | `all` | Tam audit (dikkatli kullanın) |
| `log_min_duration_statement` | `1000` (ms) → yavaş yavaş düşür | Yavaş sorgu tespiti |
| `log_checkpoints` | `on` | Mutlaka açın |
| `log_lock_waits` | `on` | Tüm kurulumlarda |
| `log_temp_files` | `0` | Tüm kurulumlarda |
| `log_line_prefix` | `'< user=%u db=%d host=%h pid=%p app=%a time=%m > '` | Analiz için |

`log_statement = all` çıktısı:
```log
< user=postgres db=bilgemyte host=[local] pid=27245 time=2024-05-13 12:26:50.331 > LOG: statement: INSERT INTO il VALUES('35','İzmir','1');
< user=postgres db=bilgemyte host=[local] pid=27245 time=2024-05-13 12:26:50.333 > LOG: duration: 2.067 ms
```

---

## 4. Pgbadger ile Log Analizi

Log dosyaları insan gözüyle okunamayacak kadar çok veri içerir. `Pgbadger` adlı açık kaynaklı perl scripti, bu log dosyalarını okuyarak muazzam HTML performans raporları çıkartır (hangi sorgular yavaş, ne zaman yoğunluk var vb.).

*Bunun çalışabilmesi için `log_min_duration_statement` ve `log_line_prefix` ayarlarının düzgün yapılmış olması gerekir.*

---

## 5. Güvenlik Denetimi ve İz İzleme (PgAudit)

Yasal zorunluluklar (BDDK, SPK, GDPR, KVKK) gereği, sistem yöneticileri dahil **"Kim, ne zaman, hangi veriye baktı ve neyi değiştirdi?"** sorularının kayıt altına alınması gerekebilir.

PostgreSQL standart logları çok ilkel kalır. Bu iş için **`pgaudit`** (PostgreSQL Audit Extension) kullanılır.

> [!NOTE]
> pgaudit ücretsiz ve açık kaynak kodludur. PostgreSQL'in kendi loglama altyapısını kullandığı için ayrı bir logger daemon çalışmaz.

### Kurulum ve Ayarlama

```bash
# RPM tabanlı sistemler
yum install pgaudit_16

# Debian/Ubuntu
apt install postgresql-16-pgaudit
```

```ini
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements, pgaudit'  # Restart gerektirir
pgaudit.log = 'all'           # Tüm işlemleri izle
pgaudit.log_parameter = 'on'  # SQL parametrelerini de logla
pgaudit.log_relation = 'on'   # Her relation için ayrı log satırı
```

```sql
-- Veritabanında uzantıyı aktif et
CREATE EXTENSION pgaudit;
```

### `pgaudit.log` Seçenekleri

| Değer | İzlenen İşlemler |
|---|---|
| `READ` | SELECT ve COPY işlemleri |
| `WRITE` | INSERT, UPDATE, DELETE, TRUNCATE ve COPY |
| `FUNCTION` | DO blokları ve fonksiyon çağrıları |
| `ROLE` | GRANT, REVOKE, CREATE/ALTER/DROP ROLE |
| `DDL` | ROLE dışındaki tüm DDL'ler |
| `MISC` | DISCARD, FETCH, CHECKPOINT, VACUUM gibi diğer komutlar |

Birleşik kullanım örnekleri:
```ini
pgaudit.log = 'ALL'          # Hepsini logla
pgaudit.log = 'ALL, -READ'   # READ dışındakileri logla
pgaudit.log = 'READ, WRITE'  # Sadece okuma ve yazma
```

### PgAudit Log Çıktısı

```log
< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:35:58.582 > LOG: statement: CREATE TABLE t3 (c1 int);
< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:35:58.583 > LOG: AUDIT: SESSION,2,1,DDL,CREATE TABLE,TABLE,public.t3,CREATE TABLE t3 (c1 int);,<not logged>
< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:35:58.585 > LOG: duration: 3.092 ms

< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:36:06.291 > LOG: statement: INSERT INTO t3 VALUES (1);
< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:36:06.291 > LOG: AUDIT: SESSION,3,1,WRITE,INSERT,TABLE,public.t3,INSERT INTO t3 VALUES (1);,<not logged>

< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:36:09.940 > LOG: statement: DROP TABLE t3;
< user=postgres db=postgres host=[local] pid=29129 time=2024-07-23 12:36:09.941 > LOG: AUDIT: SESSION,4,1,DDL,DROP TABLE,TABLE,public.t3,DROP TABLE t3;,<not logged>
```

Standart log çıktısı:
```log
LOG: AUDIT: SESSION,3,1,WRITE,INSERT,TABLE,public.urunler,INSERT INTO urunler VALUES(1);
```

Bu sayede log takip sistemleri (SIEM, Elasticsearch) bu standart çıktıları kolayca analiz edebilir.

### Neler İzlenmeli? (Kapsamlı Yapılandırma)

*   `READ`: Kimin hangi veriye baktığı (KVKK için)
*   `WRITE`: INSERT, UPDATE, DELETE işlemleri
*   `DDL`: Tablo oluşturma, düşürme, yetki değiştirme
*   `ROLE`: Kullanıcı ve rol değişiklikleri


Aşağıdaki ayarlar `postgresql.conf` üzerinden yapılandırılır:

```ini
# Logların Nereye Yazılacağı
logging_collector = on            # Loglama servisini açar
log_directory = 'log'             # Log klasörü (PGDATA içinde)
log_filename = 'postgresql-%a.log'# Haftanın gününe göre dosyalar (örn: postgresql-Mon.log)
log_truncate_on_rotation = on     # Yeni haftaya girildiğinde eski dosyanın üzerine yazar

# Nelerin Loglanacağı
log_connections = on              # Kimlerin veritabanına bağlandığını yazar
log_disconnections = on           # Kimlerin koptuğunu yazar
log_lock_waits = on               # Başka bir kullanıcının kilitlediği tabloyu bekleyenleri yazar
log_temp_files = 0                # Sort/Hash işlemleri için belleğe sığmayıp diske (Temp) yazan sorguları bulur

# Yavaş Sorguları Bulmak (Milisaniye Cinsinden)
log_min_duration_statement = 500  # 500 milisaniyeden (Yarım saniye) uzun süren her sorguyu loga yazar. Performans iyileştirmesi için DBA'lerin en yakın dostudur.
```

### Log Çıktısını Şekillendirme (`log_line_prefix`)
Log satırlarının başına zaman, kullanıcı, veritabanı gibi meta bilgileri eklemek analiz programları (PgBadger gibi) için çok önemlidir.

```ini
log_line_prefix = '%m [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
# Çıktısı: 2024-01-01 10:00:00 [4520]: [1-1] user=ali,db=satis,app=pgAdmin,client=192.168.1.10 LOG: ...
```

---

## 2. Pgbadger ile Log Analizi

Log dosyaları insan gözüyle okunamayacak kadar çok veri içerir. `Pgbadger` adlı açık kaynaklı perl scripti, bu log dosyalarını okuyarak muazzam HTML performans raporları (Hangi sorgular yavaş, ne zaman yoğunluk var vb.) çıkartır. 

*Bunun çalışabilmesi için yukarıdaki `log_min_duration_statement` ve `log_line_prefix` ayarlarının düzgün yapılmış olması gerekir.*

---

## 3. Güvenlik Denetimi ve İz İzleme (PgAudit)

Yasal zorunluluklar (BDDK, SPK, GDPR, KVKK) gereği, sistem yöneticileri dahil **"Kim, ne zaman, hangi veriye baktı ve neyi değiştirdi?"** sorularının kayıt altına alınması gerekebilir.

PostgreSQL standart logları sorguları loglasa da, bu denetim amaçları için çok ilkel kalır. Bu iş için **`pgaudit`** (PostgreSQL Audit Extension) kullanılır.

### Kurulum ve Ayarlama
Yum veya Apt üzerinden kurulduktan sonra sisteme eklenmelidir:

```ini
# postgresql.conf
shared_preload_libraries = 'pgaudit'  # Servis restart gerektirir
pgaudit.log = 'ALL'                   # Okuma, Yazma, DDL dahil her şeyi izle
pgaudit.log_relation = 'on'           # Sorguda hangi tabloya/view'a gidildiğini ayrı ayrı göster
```

```sql
-- Veritabanında uzantıyı aktif et
CREATE EXTENSION pgaudit;
```

### Neler İzlenmeli? (`pgaudit.log`)
Tüm operasyonları (`ALL`) loglamak diskte aşırı yer tutabilir. Sadece spesifik işlemleri izleyebilirsiniz:
*   `READ`: Sadece `SELECT` ve veri okuma işlemlerini izler (KVKK için kimin hangi veriye baktığı).
*   `WRITE`: `INSERT`, `UPDATE`, `DELETE` işlemleri.
*   `DDL`: Tablo oluşturma, düşürme, yetki değiştirme işlemleri (`CREATE`, `DROP`, `ALTER`).

Örnek bir PgAudit Log Çıktısı:
```log
LOG: AUDIT: SESSION,3,1,WRITE,INSERT,TABLE,public.urunler,INSERT INTO urunler VALUES(1);
```
Bu sayede log takip sistemleri (SIEM, Elasticsearch) bu standart çıktıları kolayca analiz edebilir.
