# Güvenlik, Bağlantı İzinleri ve Şifreleme

PostgreSQL veritabanı güvenliği iki temel katmandan oluşur: Dışarıdan veritabanına bağlantı (pg_hba.conf) ve veritabanı içi erişim yetkileri (GRANT ve RLS).

---

## 1. Host Bazlı Kimlik Doğrulama (`pg_hba.conf`)

Bir uygulamanın veya kullanıcının PostgreSQL'e bağlanabilmesi için önce `pg_hba.conf` dosyasından vize alması gerekir. Dosyadaki satırlar yukarıdan aşağıya doğru okunur; eşleşen ilk kural uygulanır.

**Yazım Formatı:**
`TYPE  DATABASE  USER  ADDRESS  METHOD`

```text
# ÖRNEK pg_hba.conf DOSYASI

# 1. Local (Unix Socket) üzerinden postgres kullanıcısı şifresiz girebilir (peer)
local   all             postgres                                peer

# 2. Raporlama kullanıcısı kendi makinesinden bağlanabilir (md5/scram-sha-256)
host    satis_db        raporcu         192.168.1.100/32        scram-sha-256

# 3. Yazılımcılar tüm IP'lerden, sadece SSL zorunluluğu ile bağlanabilir
hostssl all             +developer_grubu 0.0.0.0/0              scram-sha-256

# 4. Kalan TÜM bağlantı taleplerini reddet (Güvenlik)
host    all             all             0.0.0.0/0               reject
```

### Bağlantı (Method) Türleri
*   **`trust`:** Şifre sormadan koşulsuz alır (Sadece Localhost için önerilir).
*   **`scram-sha-256`:** En güvenli şifreli doğrulama metodudur (MD5 artık eskimiştir).
*   **`peer`:** Linux işletim sistemindeki kullanıcı adınız neyse (Örn: postgres), veritabanına da o kullanıcıyla şifresiz girmenizi sağlar (Sadece `local` için).
*   **`reject`:** Koşulsuz reddeder (Kara liste).

---

## 2. SQL Erişim Yetkileri (GRANT / REVOKE)

Bağlantı sağlandıktan sonra, tablolar ve nesneler üzerindeki işlemler yetkilere tabidir. Yeni oluşturulan bir tablo sadece sahibine (Owner) aittir, kimse okuyamaz.

```sql
-- 1. Tabloyu Okuma ve Yazma yetkisi verme
GRANT SELECT, INSERT, UPDATE, DELETE ON musteri_listesi TO satis_uygulamasi;

-- 2. Sadece belirli bir kolonu (Örn: Maas) güncelleme yetkisi verme
GRANT UPDATE (maas) ON personel TO ik_uzmani;

-- 3. Verilen bir yetkiyi geri alma (REVOKE)
REVOKE DELETE ON musteri_listesi FROM satis_uygulamasi;
```

> [!WARNING]
> Varsayılan olarak `PUBLIC` (Yani tüm kullanıcılar) şeması üzerinde nesne oluşturma ve yetkilendirmeler herkese açıktır. Güvenli sistemlerde bu kapatılır: `REVOKE ALL ON SCHEMA public FROM PUBLIC;`

---

## 3. Satır Bazlı Güvenlik (Row Level Security - RLS)

Sadece tabloya değil, **tablonun içindeki satırlara** da erişim kısıtlaması getirilebilir. Çok kullanıcılı SaaS uygulamalarında (Tenant Data Isolation) mükemmeldir.

Örneğin, her satış elemanı sadece **kendi girdiği** müşterileri görebilsin:

```sql
-- 1. RLS özelliğini tablo üzerinde aktif et (Bunu yapınca varsayılan olarak kimse hiçbir satırı göremez)
ALTER TABLE musteriler ENABLE ROW LEVEL SECURITY;

-- 2. Bir kural (Politika) yaz
CREATE POLICY satici_kendi_musterisini_gorur ON musteriler 
FOR SELECT 
USING (satici_kullanici_adi = current_user);
```

---

## 4. SSL (Şifreli Bağlantı) Yapılandırması

İstemci ile veritabanı arasındaki network trafiğinin (Şifrelerin ve verilerin) ağ izleyicileri tarafından (Man-in-the-Middle) okunmasını engellemek için SSL aktif edilmelidir.

1.  Linux üzerinde OpenSSL ile SSL Sertifikası oluşturulur (`server.key`, `server.crt`).
2.  `postgresql.conf` dosyası düzenlenir:
    ```ini
    ssl = on
    ssl_cert_file = '/var/lib/pgsql/13/data/server.crt'
    ssl_key_file = '/var/lib/pgsql/13/data/server.key'
    # Sadece güçlü algoritmaları kullan
    ssl_ciphers = 'HIGH:!SSLv2:!SSLv3:!aNULL'
    ```
3.  `pg_hba.conf` dosyasında bağlantı türü `host` yerine `hostssl` yapılır.
