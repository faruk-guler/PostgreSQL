# Mamonsu ile PostgreSQL İzleme ve Performans Yönetimi

**Mamonsu**, Postgres Professional tarafından geliştirilen, Zabbix tabanlı, yüksek performanslı bir PostgreSQL izleme (monitoring) ve metrik toplama aracıdır. Diğer ajanların (agent) aksine, PostgreSQL'in iç yapısına çok hakimdir ve sunucu performansını, I/O durumunu, bellek kullanımını detaylı olarak izler.

Ayrıca `tune` (ayarlama) ve `report` (raporlama) gibi ekstra yeteneklere sahiptir.

---

## 1. Mimari ve Kurulum

Mamonsu kendi başına veri toplayan aktif bir aracıdır ve bu verileri **Zabbix Server**'a aktarır. Varsayılan kurulumunda 200'e yakın parametreyi izler ve trend analizi yapmanıza imkan tanır.

### Kurulum (RHEL / Debian)

Paket yöneticileri üzerinden kolayca kurulabilir:
```bash
# RHEL / CentOS / Rocky
yum install mamonsu

# Debian / Ubuntu
apt-get install mamonsu
```
Servisi başlatmak için:
```bash
systemctl enable --now mamonsu
```

---

## 2. PostgreSQL ile Entegrasyon (Bootstrap)

Mamonsu'nun veritabanından sağlıklı veri toplayabilmesi için kendine ait bir rolü ve veritabanı olması gerekir.

**Veritabanı Hazırlığı:**
```bash
createdb mamonsu
createuser mamonsu
# mamonsu veritabanına gerekli şema ve yetkileri yükler
mamonsu bootstrap -U postgres -d mamonsu
```

**pg_hba.conf İzni:**
Mamonsu'nun veritabanına şifresiz/güvenli erişebilmesi için `pg_hba.conf` dosyasına şu satır eklenir:
```bash
local   mamonsu   mamonsu   trust
```

---

## 3. Zabbix Konfigürasyonu ve Template Dışa Aktarma

Mamonsu ayarları `/etc/mamonsu/agent.conf` dosyasında tutulur:

```ini
[zabbix]
address = zabbix_sunucu_ipsi  # Zabbix sunucusu
client = pg_sunucu_adi        # Zabbix'teki Host Name ile aynı olmalı!

[postgres]
enabled = True
user = mamonsu
database = mamonsu
```

Zabbix sunucusunda grafikleri görebilmek için XML şablonu dışa aktarılır ve Zabbix arayüzünden içeri (import) aktarılır:
```bash
mamonsu export template template.xml
# Bu template.xml Zabbix arayüzünden yüklenir
```

---

## 4. Ekstra Yetenekler: Raporlama ve Tuning

Mamonsu sadece Zabbix'e veri yollamakla kalmaz, komut satırı üzerinden sistemin anlık röntgenini çekebilir:

**Sistem ve Veritabanı Raporu Almak:**
```bash
mamonsu report
# Sistem I/O, bellek, cache isabet oranları ve kilit (lock) durumlarını özetler
```

**Konfigürasyon Önerisi (Tuning):**
```bash
mamonsu tune --dry-run
# Mevcut donanıma bakarak postgresql.conf için ideal parametreleri (shared_buffers, work_mem vb.) önerir. --dry-run yazılmazsa dosyayı direkt değiştirir.
```
