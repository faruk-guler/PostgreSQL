# İstemci Bağlantı Varsayılanları ve pgAdmin

PostgreSQL sunucusuna psql veya başka bir istemci ile bağlandığınızda, oturumunuz için bazı varsayılan kurallar ve davranışlar devreye girer. Bu varsayılanlar güvenlik, arama sırası ve işlem (transaction) yalıtımı gibi önemli yapılandırmaları içerir.

---

## 1. Kritik Oturum (Session) Parametreleri

Bir istemci sunucuya bağlandığında aşağıdaki parametreler onun hareket alanını belirler.

### `search_path` (Şema Arama Yolu)
Veritabanında şema adını açıkça belirtmeden (örneğin sadece `SELECT * FROM tablo_adi` diyerek) sorgu çalıştırdığınızda PostgreSQL'in o tabloyu arayacağı şema listesini belirler.
* **Varsayılan Değer:** `"$user", public`
* Bu ayar sayesinde, sorgulanan tablo önce kullanıcı adıyla aynı ada sahip şemada aranır. Orada bulunamazsa genel `public` şemasına bakılır.

### `client_min_messages` (İstemci Mesaj Seviyesi)
Sunucudan istemciye (psql veya uygulamanıza) gönderilecek bildirim, log veya hata mesajlarının minimum önem derecesini belirler.
* **Varsayılan Değer:** `NOTICE`
* Geçerli değerler: `DEBUG5` -> `LOG` -> `NOTICE` -> `WARNING` -> `ERROR`
* (Örneğin bir tablo sildiğinizde sunucudan gelen "Tablo başarıyla silindi" bilgisi bir NOTICE mesajıdır).

### `default_transaction_isolation` (İzolasyon Seviyesi)
PostgreSQL'de başlatılan (BEGIN) her SQL transaction'ının varsayılan izolasyon seviyesini belirler.
* **Varsayılan Değer:** `read committed`
* Eşzamanlı işlemlerde okuma tutarlılığını sağlamak için gerektiğinde `repeatable read` veya `serializable` olarak oturum bazında yükseltilebilir.

### `default_tablespace`
Kullanıcı `CREATE TABLE` veya `CREATE INDEX` derken açıkça bir tablespace (disk alanı) belirtmezse, verinin fiziksel olarak yazılacağı varsayılan dizini belirler.
* Varsayılan olarak boştur ve veritabanının `pg_default` konumunu kullanır.

### `row_security` (Satır Seviyesi Güvenlik)
`on` olduğunda (varsayılan), `CREATE POLICY` ile tanımlanan RLS (Row-Level Security) kuralları uygulanır ve yetkisiz kullanıcılar tablodaki belirli satırları göremez.

---

## 2. Grafiksel İstemci: pgAdmin 4

Komut satırı aracı `psql` uzmanlar ve otomasyon için vazgeçilmez olsa da, PostgreSQL yönetiminde açık kaynaklı ve en popüler grafiksel araç **pgAdmin 4**'tür.

pgAdmin 4 iki farklı modda çalışabilir:
1. **Masaüstü Modu (GUI):** Çapraz platform (Windows, macOS, Linux) destekli bir masaüstü uygulaması olarak kurulur.
2. **Sunucu Modu (WUI):** Docker veya Python wheel olarak bir web sunucusuna (Nginx/Apache arkasına) kurularak, tüm veritabanı yöneticilerinin internet tarayıcısı üzerinden sunuculara erişmesini sağlayan portal modudur.

Ayrıca PostgreSQL ekosisteminde pgAdmin dışında DBeaver, DataGrip (JetBrains) ve TablePlus gibi popüler alternatif grafiksel istemciler (IDE) de sıkça kullanılmaktadır.
