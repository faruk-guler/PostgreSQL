# FDW (Foreign Data Wrapper) ve Dış Veri Bağlantıları

PostgreSQL, sadece kendi içindeki verileri yönetmekle kalmaz, aynı zamanda standart **SQL/MED** (Management of External Data) mimarisi sayesinde dışarıdaki farklı veri kaynaklarını sanki yerel bir tabloymuş gibi sorgulayabilir. Bunu sağlayan eklenti altyapısına **FDW (Foreign Data Wrapper)** denir.

Eski dönemlerde kullanılan `dblink` eklentisinin modern, güvenli ve çok daha performanslı halidir.

## 1. FDW İle Neler Yapılabilir?

*   **postgres_fdw:** Başka bir PostgreSQL sunucusundaki tabloları kendi sunucunuzdaymış gibi `SELECT`, `INSERT`, `UPDATE` atarak kullanabilirsiniz.
*   **mysql_fdw / tds_fdw:** MySQL veya Microsoft SQL Server'daki tablolara bağlanıp join yapabilirsiniz.
*   **file_fdw:** Sunucudaki `.csv` veya `.txt` dosyalarını sanki bir tabloymuş gibi SQL ile sorgulayabilirsiniz.
*   **Diğerleri:** Oracle, MongoDB, Redis, Twitter (X) API'si, Google E-Tablolar (Sheets) için bile yazılmış açık kaynaklı FDW eklentileri mevcuttur.

---

## 2. postgres_fdw Kullanımı (Uzaktaki PostgreSQL'e Bağlanma)

Uzaktaki bir muhasebe veritabanındaki (Örn: 192.168.1.50) `fatura` tablosunu kendi yerel (Local) raporlama veritabanımıza bağlayalım.

### Adım 1: Eklentiyi Aktif Et
Öncelikle yerel veritabanında eklenti kurulur:
```sql
CREATE EXTENSION postgres_fdw;
```

### Adım 2: Dış Sunucuyu (Server) Tanımla
Uzaktaki sunucunun adres ve veritabanı bilgilerini tanımlıyoruz. Şifre girmedik, bu sadece donanımsal bir tanımdır.
```sql
CREATE SERVER muhasebe_sunucusu 
    FOREIGN DATA WRAPPER postgres_fdw 
    OPTIONS (host '192.168.1.50', port '5432', dbname 'muhasebe_db');
```

### Adım 3: Kullanıcı Eşleştirmesi (User Mapping)
Yerel veritabanındaki bir kullanıcının (Örn: `rapor_user`), uzaktaki sunucuya hangi şifre ve kullanıcıyla gireceğini eşleştiriyoruz.
```sql
CREATE USER MAPPING FOR rapor_user 
    SERVER muhasebe_sunucusu
    OPTIONS (user 'uzak_api_user', password 'GizliSifre123');
```

### Adım 4: Tabloyu İçeri Alma (Foreign Table)

**Yöntem A: Sadece tek bir tabloyu manuel olarak bağlamak**
```sql
CREATE FOREIGN TABLE dis_fatura (id int, tutar numeric, tarih date)
    SERVER muhasebe_sunucusu 
    OPTIONS (schema_name 'public', table_name 'fatura');
```
Bu yöntemle uzaktaki `fatura` tablosunu kendi veritabanımızda `dis_fatura` ismiyle görürüz.

**Yöntem B: Tüm şemayı topluca içe aktarmak (IMPORT FOREIGN SCHEMA)**
Uzaktaki sunucunun `public` şemasındaki onlarca tabloyu tek tek yazmak yerine, yereldeki boş bir şemaya (`muhasebe_sema`) topluca otomatik aktarabilirsiniz:
```sql
CREATE SCHEMA muhasebe_sema;

IMPORT FOREIGN SCHEMA public 
    FROM SERVER muhasebe_sunucusu
    INTO muhasebe_sema;
```

Artık sanki kendi veritabanımızdaymış gibi SQL yazabiliriz:
```sql
SELECT * FROM muhasebe_sema.fatura WHERE tutar > 5000;
```
*(Arka planda PostgreSQL bu sorguyu uzak sunucuya iletir, sadece filtreye uyan kayıtları ağ üzerinden geri çeker).*

---

## 3. file_fdw Kullanımı (CSV Dosyasını SQL ile Okuma)

Dışarıdan gelen devasa bir CSV dosyasını veritabanına yüklemek (INSERT) yerine doğrudan olduğu yerden SQL ile okumak için kullanılır.

```sql
-- 1. Eklentiyi kur
CREATE EXTENSION file_fdw;

-- 2. Sunucuyu oluştur
CREATE SERVER dosya_sunucusu FOREIGN DATA WRAPPER file_fdw;

-- 3. CSV dosyasını tablo olarak bağla
CREATE FOREIGN TABLE log_verileri (ip_adresi text, islem_tarihi timestamp, mesaj text) 
    SERVER dosya_sunucusu 
    OPTIONS ( filename '/var/lib/pgsql/data/server_loglari.csv', format 'csv', header 'true' );
```

Artık dosyayı canlı olarak sorgulayabilirsiniz:
```sql
SELECT * FROM log_verileri WHERE ip_adresi = '192.168.1.10';
```
*(Dosya işletim sistemi seviyesinde güncellendikçe, `SELECT` sorgunuz anında yeni satırları görecektir).*
