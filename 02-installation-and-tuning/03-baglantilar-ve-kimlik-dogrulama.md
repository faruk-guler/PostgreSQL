# Bağlantılar (Connections), SSL ve Kimlik Doğrulama

PostgreSQL, ağ (network) üzerinden gelen bağlantıların nasıl dinleneceğini, eşzamanlı olarak kaç bağlantı kabul edileceğini ve bu bağlantıların nasıl şifreleneceğini (SSL) sıkı bir şekilde kontrol eder. Bu ayarlar çoğunlukla `postgresql.conf` üzerinden yapılandırılır ve çoğu sunucunun yeniden başlatılmasını (restart) gerektirir.

---

## 1. Ağ (Network) ve Dinleme Ayarları

PostgreSQL'in dış dünyaya açıldığı kapıları aşağıdaki parametreler belirler. Varsayılan olarak PostgreSQL sadece `localhost`'u dinler, dışarıdan (uzaktan) bağlantı kabul etmez.

*   **`listen_addresses`**: Sunucunun hangi TCP/IP arayüzlerini dinleyeceğini belirtir.
    *   `'localhost'`: Sadece sunucunun kendisinden gelen bağlantıları kabul eder (Güvenli, varsayılan).
    *   `'*'`: Sunucudaki tüm IPv4 ve IPv6 arayüzlerini dış dünyaya açar (Üretime alırken en yaygın kullanım).
    *   `'192.168.1.50, localhost'`: Sadece belirli IP adreslerini dinler.
*   **`port`**: Sunucunun dinlediği TCP portudur. Varsayılan **5432**'dir.
*   **`unix_socket_directories`**: (Sadece Linux/Unix). Ağ yığınına (TCP/IP) girmeden işletim sistemi çekirdeği üzerinden çok hızlı yerel bağlantılar kurmak için kullanılan soket dosyalarının oluşturulacağı dizindir (Varsayılan: `/tmp` veya `/var/run/postgresql`).

> [!WARNING]
> `listen_addresses = '*'` yapsanız bile, uzak bir bilgisayardan bağlanabilmek için **`pg_hba.conf`** dosyasında o IP bloğuna açıkça izin (GRANT) vermeniz gerekmektedir. İkisi birbirini tamamlar.

---

## 2. Bağlantı Kapasitesi ve Limitler

*   **`max_connections`**: Veritabanına aynı anda bağlanabilecek maksimum istemci (client) sayısıdır. Varsayılan **100**'dür. Bu değeri çok yüksek tutmak (örneğin 5000), her bağlantı işletim sisteminde bir süreç (Backend Process) oluşturduğu için RAM'i (özellikle `work_mem`) hızla tüketir. Yüksek bağlantı gerekiyorsa **PgBouncer** kullanılmalıdır.
*   **`superuser_reserved_connections`**: `max_connections` sınırına ulaşıldığında sıradan kullanıcıların bağlanmasını engellerken, Veritabanı Yöneticisinin (DBA) sistemi kurtarabilmesi, izleyebilmesi veya sorun çözebilmesi için süper kullanıcılara ayrılmış gizli bağlantı slotudur. Varsayılan **3**'tür. 

---

## 3. TCP Keepalives (Zombi Bağlantıları Temizleme)

Bazen istemci (uygulama) ağın kopması, elektrik kesilmesi veya donması nedeniyle veritabanına "kapanma (FIN)" sinyali gönderemeden ortadan kaybolabilir. Sunucu bu zombi bağlantıları açık tutmaya devam eder. Bunu önlemek için işletim sistemi seviyesinde *TCP Keepalive* probları gönderilir:

*   **`tcp_keepalives_idle`**: Ağda hiçbir hareket yokken, sunucunun istemciye "Orada mısın?" mesajı göndermeden önce bekleyeceği süredir.
*   **`tcp_keepalives_interval`**: İstemciden cevap gelmezse, sorunun tekrarlanma sıklığıdır.
*   **`tcp_keepalives_count`**: İstemcinin bağlantısı koptu kabul edilmeden önce gönderilecek başarısız mesaj sayısıdır.

---

## 4. Güvenlik ve Şifreleme (SSL / TLS)

Gidip gelen verilerin ağ üzerinde (Man-in-the-Middle) dinlenmesini engellemek için PostgreSQL yerleşik **OpenSSL** desteğiyle gelir. 

### Temel SSL Parametreleri
*   **`ssl`**: `on` yapılarak SSL motoru aktif edilir.
*   **`ssl_cert_file`**: Sunucu sertifikası (`server.crt`). İstemciye sunucunun kimliğini kanıtlar.
*   **`ssl_key_file`**: Sunucunun özel anahtarı (`server.key`). Sertifikanın gerçekten bu sunucuya ait olduğunu kriptografik olarak imzalar. Dosya izinleri kesinlikle `0600` (sadece postgres kullanıcısı okuyabilir) olmalıdır!
*   **`ssl_min_protocol_version`**: İzin verilen en eski SSL/TLS protokolü. Sektör standardı gereği günümüzde en az **`TLSv1.2`** veya **`TLSv1.3`** seçilmelidir. Eski sürümler güvensizdir.

> [!TIP]
> İstemcilerin (uygulamaların) SSL kullanımını **ZORUNLU** kılmak için `pg_hba.conf` dosyasında bağlantı tipini `host` yerine **`hostssl`** olarak belirtmelisiniz.

### Test Amaçlı Self-Signed (Kendinden İmzalı) SSL Oluşturma
Üretim (Production) ortamlarında Let's Encrypt veya kurumunuzun Sertifika Otoritesi (CA) tarafından imzalanmış sertifikalar kullanılmalıdır. Ancak test/geliştirme ortamları için aşağıdaki OpenSSL komutuyla hızlıca 365 günlük bir sertifika üretebilirsiniz:

```bash
# Veri dizinine ($PGDATA) geçin
cd /var/lib/pgsql/16/data

# 2048 bitlik yeni bir anahtar ve sertifika oluşturun
openssl req -new -x509 -days 365 -nodes -text -out server.crt \
  -keyout server.key -subj "/CN=dbhost.sirketim.local"

# Private Key (Özel Anahtar) izinlerini kısıtlayın
chmod 0600 server.key

# PostgreSQL'i yeniden başlatın
pg_ctl restart
```
