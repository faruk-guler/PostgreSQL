# Veritabanı Loglama ve Audit (PgAudit)

PostgreSQL'de sunucu sağlığını izlemek, yavaş sorguları bulmak ve güvenlik ihlallerini tespit etmek için loglama yapılandırması hayati öneme sahiptir. Varsayılan ayarlar performans odaklı olduğu için çoğu loglamayı kapalı tutar.

## 1. Temel Loglama Ayarları (`postgresql.conf`)

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
