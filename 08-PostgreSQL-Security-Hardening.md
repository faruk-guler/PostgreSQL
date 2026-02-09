# 08-PostgreSQL-Security-Hardening

Veritabanı güvenliği, sadece "güçlü şifre" koymaktan ibaret değildir. Bu doküman, PostgreSQL sunucunuzu "askeri standartlarda" (Defense in Depth) nasıl koruyacağınızı anlatır.

---

## 1. Network Encryption (SSL/TLS)

Varsayılan olarak PostgreSQL bağlantıları şifresiz olabilir. Araya giren biri (Man-in-the-Middle) veriyi okuyabilir.

### Sertifika Oluşturma (Self-Signed)

```bash
# 1. Private Key oluştur (Şifresiz)
openssl genrsa -out server.key 2048
chmod 400 server.key # Sadece sahibi okuyabilsin

# 2. Sertifika (CRT) oluştur
openssl req -new -x509 -days 3650 -nodes -text -out server.crt \
  -key server.key -subj "/CN=db.example.com"

# 3. Dosyaları veri dizinine taşı
mv server.key server.crt /var/lib/pgsql/16/data/
chown postgres:postgres /var/lib/pgsql/16/data/server.*
```

### Konfigürasyon (postgresql.conf)

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
# İstemcilerin de sertifika zorunluluğu olsun mu? (Mutual TLS)
# ssl_ca_file = 'root.crt'
```

### Zorlama (pg_hba.conf)

Sadece SSL bağlantılarını kabul et:

```bash
# Sadece SSL bağlantılarına izin ver (hostssl)
hostssl  all  all  0.0.0.0/0  scram-sha-256
```

---

## 2. Transparent Data Encryption (TDE)

PostgreSQL (Community sürüm) maalesef Oracle veya MSSQL gibi yerleşik "TDE" (Veri dosyasını şifreleme) özelliğine **henüz** sahip değildir.

### Çözüm: Disk Encryption (LUKS)

Veritabanı dosyalarının durduğu diski (`/var/lib/pgsql`) işletim sistemi seviyesinde şifrelemek en güvenli ve performanslı yoldur.

1. Linux LUKS (Linux Unified Key Setup) kullanarak bölümü şifreleyin.
2. Sunucu açılırken şifreyi girip diski mount edin.
3. PostgreSQL servisini başlatın.
*(Diskin çalınması durumunda veriler okunamaz olur.)*

---

## 3. Auditing (Denetim İzleri) - pgaudit

"Kim, ne zaman, hangi tabloya, ne yaptı?" sorusunun cevabı için standart loglar yetersizdir. `pgaudit` eklentisi şarttır.

### Kurulum

```bash
# RHEL 9
sudo dnf install pgaudit_16
```

### Konfigürasyon

```ini
# postgresql.conf
shared_preload_libraries = 'pgaudit'  # Restart gerekir

pgaudit.log = 'write, ddl' # Sadece yazma ve yapı değişikliklerini logla (SELECT hariç)
pgaudit.log_catalog = off  # Sistem tablolarını loglama (Gürültüyü azalt)
pgaudit.log_client = on    # Logları istemciye de (gerekiyorsa) göster
log_line_prefix = '%m [%p] %u@%d ' # Zaman, PID, User@DB
```

---

## 4. Row Level Security (RLS)

Uygulama seviyesinde `WHERE company_id = 5` demek yerine, güvenliği veritabanına gömmek için kullanılır.

### Senaryo: Çok Firmalı (Multi-Tenant) SaaS

Her kullanıcı sadece kendi firmasının verisini görsün.

```sql
-- 1. Tabloyu oluştur
CREATE TABLE invoices (
    id SERIAL PRIMARY KEY,
    company_name TEXT,
    amount NUMERIC
);

-- 2. RLS'yi aç
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

-- 3. Politika (Policy) yaz
CREATE POLICY company_isolation_policy ON invoices
    FOR ALL -- (SELECT, INSERT, UPDATE, DELETE)
    USING (company_name = current_user); -- Kullanıcı adı ile şirket adı eşleşmeli

-- 4. Kullanıcıları oluştur ve test et
CREATE ROLE apple WITH LOGIN;
CREATE ROLE google WITH LOGIN;

GRANT ALL ON invoices TO apple, google;

-- "apple" olarak bağlanan, sadece "apple" verisini görür.
-- "google" verisini SELECT atsa bile 0 satır döner.
```

> [!TIP]
> RLS kullanırken `superuser` (postgres) her şeyi görmeye devam eder. Testleri normal kullanıcılarla yapın (`SET ROLE apple;`).

---

## 5. SCRAM Authentication (Modern Kimlik Doğrulama)

Eski `md5` yöntemi artık güvensizdir (Rainbow table saldırılarına açıktır). PostgreSQL 10+ ile gelen `scram-sha-256` (Salted Challenge Response Authentication Mechanism) standarttır.

### Neden SCRAM?

1. **Sunucuda şifre tutulmaz:** Hash'in hash'i tutulur.
2. **Man-in-the-Middle koruması:** Server sahte ise istemci bunu anlar.
3. **PCI-DSS Uyumlu:** Modern güvenlik standartlarını karşılar.

```ini
# postgresql.conf
password_encryption = scram-sha-256
```

Hali hazırda MD5 ile şifrelenmiş kullanıcılar varsa, şifrelerini yenilemeleri gerekir (Otomatik dönüşmez):

```sql
-- 1. Önce şifreleme yöntemini değiştir
-- 2. Sonra şifreyi yenile (Otomatik olarak SCRAM hash üretilir)
ALTER ROLE app_user WITH PASSWORD 'yeniGucluSifre';
```

---

## 6. İleri Seviye Bağlantı Güvenliği (Bonus)

### Local Connection Spoofing Önleme

Bir saldırgan kendi veritabanını başlatıp, sizin sunucunuzmuş gibi davranabilir (Spoofing). Bunu önlemek için Unix Domain Socket güvenliğini sıkılaştırın.

1. **`unix_socket_directories`**: Sadece `postgres` kullanıcısının yazabildiği bir dizin seçin (varsayılan `/var/run/postgresql` genellikle güvenlidir).
2. **`requirepeer`**: İstemci tarafında sunucunun kimliğini doğrulamak için `libpq` parametresi kullanın.

### GSSAPI & Kerberos

Enterprise ortamlarda (Active Directory vb.) şifre yönetimi yerine **Kerberos** bileti ile authentication yapmak için GSSAPI kullanılır.

```bash
# pg_hba.conf örneği
# TYPE  DATABASE        USER            ADDRESS                 METHOD
hostgssenc all          all             0.0.0.0/0               gss include_realm=0
```

Bu, TCP trafiğinin otomatik olarak şifrelenmesini de sağlar (SSL alternatifi olarak).

### Connection Modes (SSL Zorlama)

İstemci tarafında `sslmode` parametresi ile sunucunun kimliği doğrulanabilir:

- **`require`**: SSL ister ama sertifikayı doğrulamaz (Self-signed OK).
- **`verify-ca`**: Sertifikanın güvenilir bir CA'dan (kök sertifika) geldiğini doğrular.
- **`verify-full`**: `verify-ca` + Sunucu adının (CN) sertifikadaki isimle eşleştiğini doğrular (Man-in-the-Middle koruması için en iyisi).

---

## 7. Security Invoker Views (PG 15+)

Normalde View'lar, **oluşturan kişinin** (owner) yetkileriyle çalışır (Security Definer). Bu bazen güvenlik açığı yaratır. PostgreSQL 15 ile, View'ın **sorguyu çalıştıran kişinin** yetkileriyle çalışması özelliği geldi.

```sql
CREATE VIEW v_sensitive_data
WITH (security_invoker = true) -- Kritik ayar
AS
SELECT * FROM sensitive_table;

-- Artık 'v_sensitive_data' sorgulandığında, sorgulayan kullanıcının
-- 'sensitive_table' üzerinde yetkisi olup olmadığı kontrol edilir.
```
