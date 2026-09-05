# PostgreSQL Yapılandırma (`postgresql.conf`) ve Parametre Yönetimi

PostgreSQL'in davranışlarını, performansını, bellek sınırlarını ve dosya konumlarını belirleyen çekirdek yapılandırma sistemi `postgresql.conf` dosyasına dayanır. Parametreleri ayarlamak için çeşitli yöntemler ve kapsamlar (scope) mevcuttur.

---

## 1. Temel Yapılandırma Dosyaları

PostgreSQL başlatıldığında (initdb), veri dizini (`$PGDATA`) içinde varsayılan olarak şu kritik dosyalar oluşur:

* **`postgresql.conf`:** Ana konfigürasyon dosyasıdır. Bellek, disk I/O, loglama ve bağlantı parametreleri burada tutulur.
* **`postgresql.auto.conf`:** SQL üzerinden `ALTER SYSTEM` komutuyla değiştirilen ayarların otomatik olarak yazıldığı dosyadır. Bu dosyadaki değerler `postgresql.conf` dosyasındakileri **ezip geçer (override eder)**. Kesinlikle manuel düzenlenmemelidir.
* **`pg_hba.conf`:** İstemci kimlik doğrulama (Host-Based Authentication) kurallarını belirler.
* **`pg_ident.conf`:** İşletim sistemi kullanıcıları ile PostgreSQL veritabanı kullanıcıları arasındaki haritalamayı (User Name Maps) yapar.

> [!TIP]
> Bu dosyaların yerleri varsayılan olarak `$PGDATA` içerisindedir ancak `postgres` başlatılırken komut satırından `config_file`, `hba_file` ve `ident_file` parametreleriyle farklı bir dizine de yönlendirilebilir.

---

## 2. Parametre Değiştirme ve Etki Alanları (Scope)

Parametreler, etkilemek istediğiniz alana ve süreye göre farklı komutlarla ayarlanır.

### Global Değişiklikler (`ALTER SYSTEM` ve `postgresql.conf`)
Sunucudaki tüm veritabanlarını ve tüm oturumları etkiler.

```sql
-- Tüm sunucu genelinde work_mem ayarını kalıcı olarak değiştir
ALTER SYSTEM SET work_mem = '32MB';
```
*Bu komut, değeri `postgresql.auto.conf` dosyasına yazar.*

> [!IMPORTANT]
> Global yapılandırma dosyalarında (`postgresql.conf` veya `ALTER SYSTEM` ile) yapılan değişikliklerin aktif olabilmesi için sunucunun konfigürasyonu **yeniden okuması** gerekir. SQL üzerinden `SELECT pg_reload_conf();` çalıştırarak veya işletim sisteminden `pg_ctl reload` komutunu göndererek (**SIGHUP** sinyali) sunucuyu kapatmadan ayarları geçerli kılabilirsiniz. `shared_buffers` veya `port` gibi bazı çekirdek parametreleri ise sunucunun baştan başlatılmasını (`restart`) zorunlu kılar.

### Veritabanı veya Rol (Kullanıcı) Bazlı Değişiklikler
Spesifik bir kullanıcı bağlandığında veya belirli bir veritabanı kullanıldığında devreye giren ayarlardır.

```sql
-- Sadece 'rapor_db' veritabanı için geçerli
ALTER DATABASE rapor_db SET work_mem = '64MB';

-- Sadece 'analist' kullanıcısı için geçerli
ALTER ROLE analist SET statement_timeout = '5min';
```

### Oturum (Session) Bazlı Değişiklikler (`SET` / `SHOW`)
Yalnızca mevcut aktif bağlantınız (oturumunuz) boyunca geçerli olan ayarlardır. İstemci bağlantısını kestiğinde değerler kaybolur ve diğer oturumları asla etkilemez.

```sql
-- Mevcut oturum için parametreyi değiştir
SET work_mem = '128MB';

-- Mevcut oturumdaki bir parametreyi görüntüle
SHOW work_mem;

-- Tüm parametreleri listele
SHOW ALL;
```

---

## 3. Sistem Görünümleri (`pg_settings`)

Parametrelerin varsayılan değerleri, şu anki aktif değerleri, minimum/maksimum limitleri ve değişikliğin ne zaman aktif olacağı (restart gerektirip gerektirmediği) gibi detaylı bilgileri `pg_settings` kataloğundan sorgulayabilirsiniz.

```sql
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name = 'shared_buffers';
```
*(Buradaki `context` sütunu, ayarın nasıl değiştirilebileceğini belirtir: `postmaster` ise restart şarttır, `sighup` ise reload yeterlidir, `user` ise SET komutuyla anında değiştirilebilir).*

---

## 4. `postgresql.conf` Dosyasını Modüllere Bölme (`include`)

Büyük ve karmaşık mimarilerde yüzlerce satırlık tek bir `postgresql.conf` kullanmak yerine, ayarlar mantıksal parçalara bölünebilir.

`postgresql.conf` dosyasının en altına şu satırı ekleyerek modüler yapıya geçebilirsiniz:
```ini
include_dir = 'conf.d'
```

Böylece `$PGDATA/conf.d/` dizinindeki tüm `.conf` uzantılı dosyalar yüklenir. Alfabetik sırayla okundukları için çakışan (aynı) parametrelerde en son okunan dosyanın değeri geçerli olur.

Örnek kullanım:
* `conf.d/01_memory.conf`
* `conf.d/02_logging.conf`
* `conf.d/03_replication.conf`
