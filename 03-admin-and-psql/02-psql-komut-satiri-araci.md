# psql Komut Satırı Aracı

`psql`, PostgreSQL sunucusunun bir numaralı etkileşimli (interaktif) komut satırı istemcisidir. Veritabanı sorguları çalıştırmak, sonuçları görüntülemek, otomatik betikler (scripts) yürütmek ve sunucu yönetimi yapmak için kullanılır.

Oracle'ın `sqlplus` aracına benzer ancak çok daha esnek ve gelişmiş meta-komutlara (backslash `\` komutları) sahiptir.

---

## 1. Sunucuya Bağlanma

En temel haliyle `psql` yazarak bulunduğunuz işletim sistemi kullanıcısıyla aynı adlı veritabanına bağlanırsınız.

```bash
# Yerel soket üzerinden postgres kullanıcısıyla bağlanma
su - postgres
psql

# TCP/IP üzerinden uzaktaki bir sunucuya bağlanma (Parola sorar)
psql -h 192.168.1.50 -p 5432 -U dba_kullanicisi -d sirket_db -W

# Connection String (URI) kullanarak bağlanma (Önerilen modern yöntem)
psql postgresql://dba_kullanicisi:Parola123@192.168.1.50:5432/sirket_db?sslmode=require
```

### Sık Kullanılan Bağlantı Parametreleri

| Parametre | Açıklama |
| :--- | :--- |
| `-h`, `--host` | Sunucu IP adresi veya hostname |
| `-p`, `--port` | Sunucu dinleme portu (Varsayılan 5432) |
| `-U`, `--username` | Veritabanı kullanıcı adı |
| `-d`, `--dbname` | Bağlanılacak hedef veritabanı |
| `-W`, `--password` | Güvenlik için parola sor (Zorla prompt) |
| `-c`, `--command` | Etkileşimsiz mod: Tek bir SQL sorgusu çalıştır ve çık |
| `-f`, `--file` | Bir dosyadan `.sql` betiği oku ve çalıştır |

---

## 2. Temel Meta-Komutlar (`\` Komutları)

`psql` içerisindeyken SQL standartlarına ek olarak sunucuyu yönetmek ve hızlı bilgi almak için `\` ile başlayan meta-komutlar kullanılır. Bu komutların sonuna noktalı virgül (`;`) konmaz.

| Komut | Kısayolu | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `\l` | List | Sunucudaki tüm **veritabanlarını** listeler. |
| `\c db_adi` | Connect | Mevcut oturumu kapatmadan başka bir **veritabanına geçer**. |
| `\dt` | Display Tables | Mevcut şemadaki (genellikle `public`) **tabloları** listeler. |
| `\d tablo_adi` | Describe | Bir tablonun kolonlarını, tiplerini, indekslerini ve kısıtlarını (Foreign Key vb.) detaylı gösterir. (`\d+` daha da detaylandırır). |
| `\du` veya `\dg` | Display Users/Groups | Veritabanındaki tüm **kullanıcıları ve rolleri** yetkileriyle listeler. |
| `\dn` | Display Namespaces | Mevcut **şemaları** listeler. |
| `\df` | Display Functions | Veritabanındaki **fonksiyonları** listeler. |
| `\dx` | Display Extensions | Kurulu **eklentileri** (extensions) listeler (Örn: `pg_stat_statements`). |
| `\conninfo` | Connection Info | Hangi kullanıcıyla, hangi IP'den ve hangi porttan bağlandığınızı söyler. |
| `\x` | Expanded Display | Tablo çıktılarını yatay yerine **dikey (sütun sütun)** gösterir (Çok kolonlu tabloları okumak için hayat kurtarır). |
| `\q` | Quit | `psql` oturumunu kapatır ve terminale döner. |

---

## 3. Otomasyon ve Betik Çalıştırma

`psql` sadece etkileşimli kullanım için değil, bash betikleriyle (scripts) birlikte otomatik görevler (cron jobs) çalıştırmak için de mükemmeldir.

**Dışarıdan Tek Komut Yollama:**
```bash
psql -d rapor_db -c 'SELECT count(*) FROM satislar;'
```

**Dosyadan SQL Çalıştırma (Backup Yükleme vb.):**
```bash
psql -d rapor_db -f verileri_yukle.sql
# Veya
psql -d rapor_db < verileri_yukle.sql
```

**Sonucu CSV'ye Aktarma:**
```bash
psql -d rapor_db -A -F"," -c "SELECT * FROM satislar" > satis_raporu.csv
```

---

## 4. AutoCommit Davranışı

> [!WARNING]
> Oracle'ın `sqlplus` aracı varsayılan olarak işlemleri RAM'de tutar ve siz açıkça `COMMIT` diyene kadar diske yazmaz (`autocommit off`). 
> **PostgreSQL `psql` ise varsayılan olarak `autocommit ON` modunda çalışır.** Çalıştırdığınız her `INSERT` veya `UPDATE` anında işlenir. 

Yanlışlıkla veri silmeyi önlemek ve Oracle davranışını taklit etmek için oturum bazlı `autocommit` kapatılabilir:

```sql
\set AUTOCOMMIT off
-- Artık işlemlerinizi manuel commit etmelisiniz:
BEGIN;
  DELETE FROM log_tablosu WHERE tarih < '2023-01-01';
COMMIT;
```
*(Bunu kalıcı yapmak için işletim sistemi kullanıcınızın ev dizinine `~/.psqlrc` dosyası açıp içine `\set AUTOCOMMIT off` yazabilirsiniz).*
