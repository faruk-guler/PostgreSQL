# 23-PostgreSQL-Maintenance-Tools (Bloat Management)

PostgreSQL'in MVCC yapısı gereği, silinen veya güncellenen satırlar diske fiziksel olarak hemen silinmez, "ölü" (dead) olarak işaretlenir. Autovacuum bunları temizlese de, bazen tablolar "şişer" (Bloat). Bu doküman, şişkinliği yönetme ve sıfır kesintiyle temizleme yollarını anlatır.

---

## 1. Bloat (Şişkinlik) Nedir?

Tablonuzda 1GB veri var ama diskte 5GB yer kaplıyorsa, 4GB "Bloat" var demektir.

- **Neden Olur?** Yoğun UPDATE/DELETE işlemleri ve yavaş/yanlış ayarlanmış Autovacuum.
- **Zararı Nedir?** Full table scan'ler yavaşlar, indexler büyür, yedekleme süresi uzar.

---

## 2. Şişkinliği Tespit Etme

Hangi tabloda ne kadar boş yer olduğunu bulmak için şu sorguyu kullanabilirsiniz:

```sql
SELECT
  schemaname, relname,
  n_dead_tup, -- Ölü satır sayısı
  n_live_tup, -- Canlı satır sayısı
  (n_dead_tup::float / (n_live_tup + n_dead_tup + 1) * 100)::numeric(5,2) AS bloat_ratio
FROM pg_stat_all_tables
WHERE (n_live_tup + n_dead_tup) > 1000
ORDER BY bloat_ratio DESC;
```

---

## 3. pg_repack: Sıfır Kesinti ile Bakım

Standart `VACUUM FULL` tablonun boyutunu küçültür ama tabloyu tamamen **kilitler** (Okuma/Yazma yapılamaz). Production ortamında bu kabul edilemez.
**Çözüm:** `pg_repack`.

`pg_repack`, arka planda yeni bir tablo oluşturur, verileri oraya taşır ve son anda isim değiştirir. İşlem sırasında tabloya yazmaya devam edebilirsiniz.

### Kurulum (RHEL 9)

```bash
sudo dnf install pg_repack_16
```

### Kullanım

```bash
# Sadece bir tabloyu repackle
pg_repack -t items -d mydb

# Tüm veritabanını repackle
pg_repack -d mydb
```

> [!CAUTION]
> `pg_repack` çalışırken geçici olarak diskinizde tablonun 2 katı kadar boş yer olması gerekir. Ayrıca CPU ve I/O yükünü artırır, trafiğin az olduğu saatlerde yapılması önerilir.

---

## 4. Index Maintenance (İndeks Bakımı)

İndeksler tablolardan daha hızlı şişebilir.

### REINDEX CONCURRENTLY (v12+)

PostgreSQL 12 ile gelen bu özellik, sorguları engellemeden indeksi yeniden oluşturmanızı sağlar.

```sql
REINDEX INDEX CONCURRENTLY idx_users_email;
-- veya tüm tabloyu:
REINDEX TABLE CONCURRENTLY users;
```

---

## 5. pg_squeeze (Alternatif)

`pg_repack`'e benzer bir araçtır ama bir eklenti (extension) olarak çalışır. Belirli bir bloat eşiği aşıldığında otomatik çalışacak şekilde ayarlanabilir. EnterpriseDB (EDB) tarafından desteklenir.

---

## 6. Uzman Tavsiyeleri

1. **Daima Önce Analiz Et:** Gereksiz yere repack yapmak sadece sunucuyu yorar. Bloat oranı %20 altındaysa genellikle dokunulmaz.
2. **Autovacuum'u Suçlama, Tune Et:** Eğer tablolar sürekli şişiyorsa, `06-Performance-Tuning` bölümündeki Autovacuum ayarlarını tekrar gözden geçirin.
3. **Büyük Silme İşlemleri:** Milyonlarca satır silecekseniz, sildikten hemen sonra bir `ANALYZE` çalıştırın ki query planner güncel durumu görsün.
4. **Monitoring:** `pg_stat_progress_vacuum` görünümü ile arka planda çalışan vacuum işlemlerinin ilerlemesini takip edin.
