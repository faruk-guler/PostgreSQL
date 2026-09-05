# PostgreSQL Sıfır Kesintili Şema Değişiklikleri (Zero-Downtime Online DDL & Migrations)

Büyük ölçekli, 7/24 kesintisiz hizmet veren sistemlerde şema değişikliği (DDL) yapmak, veritabanı mühendisliğinin en riskli operasyonlarından biridir. Yanlış bir `ALTER TABLE` veya `CREATE INDEX` komutu, `AccessExclusiveLock` kilidi talep ederek arkasından gelen tüm `SELECT`, `INSERT` ve `UPDATE` işlemlerini kuyruğa sokar; bağlantı havuzunu (connection pool) saniyeler içinde tüketir ve sistemi çökertebilir (Cascading Outage).

Bu bölümde; milyarlarca satırlık tablolarda sıfır kesintiyle (zero-downtime) indeks oluşturma, kısıt ekleme, sütun türü değiştirme ve şema evrimi mimarisi incelenmektedir.

---

## 1. DDL Kilit Anatomisi ve Kuyruk Tıkanması (Lock Queue Starvation)

PostgreSQL'de DDL operasyonları genellikle en yüksek kilit seviyesi olan `AccessExclusiveLock` talep eder.

```text
[Uzun Süren SELECT Sorgusu]  ---> Tabloyu okuyor (AccessShareLock)
                                        |
[ALTER TABLE Komutu Gelir]   ---> AccessExclusiveLock beklemeye başlar
                                        |
[Yeni Gelen SELECT / INSERT] ---> Kuyruğa takılır! Bekleyen DDL yüzünden BLOCKED olur!
```

Kilit kuyruğunda bir `AccessExclusiveLock` beklediği andan itibaren, arkasından gelen en basit `SELECT` sorguları bile engellenir. Bu durum saniyeler içinde bağlantı havuzunun dolmasına yol açar.

### Altın Kural: `lock_timeout` Zorunluluğu

Canlı sistemlerde hiçbir DDL komutu korumasız çalıştırılmamalıdır:

```sql
-- DDL oturumunda kilidin maksimum bekleme süresi (örn: 2 saniye)
SET lock_timeout = '2s';

-- Eğer 2 saniye içinde kilit alınamazsa işlem iptal olur, sistem kilitlenmez
ALTER TABLE siparisler ADD COLUMN teslimat_notu TEXT;
```

---

## 2. Sıfır Kesintili İndeksleme: `CREATE INDEX CONCURRENTLY`

Normal bir `CREATE INDEX`, tabloya yazma (`INSERT/UPDATE/DELETE`) işlemlerini tamamen engeller. `CONCURRENTLY` anahtarı, yazmaları engellemeden arka planda indeks oluşturur.

```sql
CREATE INDEX CONCURRENTLY idx_kullanicilar_eposta ON kullanicilar (eposta);
```

### 2.1. CONCURRENTLY İç Mimarisi (3 Faz)
1. **Faz 1:** Sistem kataloğuna indeks metaverisi yazılır.
2. **Faz 2 (İlk Tarama):** Mevcut veriler taranır ve indekse eklenir. Bu sırada gelen yeni yazma işlemleri de izlenir.
3. **Faz 3 (İkinci Tarama):** İşlem sırasında eklenen/güncellenen satırlar taranarak indeks doğrulanır (Valid).

### 2.2. Hata Durumu ve `INVALID` İndeks Felaketi

Eğer `CONCURRENTLY` işlemi sırasında bir deadlock, timeout veya disk hatası oluşursa, indeks disk üzerinde **`INVALID`** olarak kalır:
* Bu indeks sorgular tarafından **kullanılamaz**.
* Ancak her `INSERT/UPDATE` işleminde disk ve CPU tüketerek güncellenmeye devam eder!

#### Canlı Sistemde `INVALID` İndeks Tespiti ve Temizliği:

```sql
-- Geçersiz (INVALID) indekslerin listelenmesi
SELECT 
    schemaname,
    relname AS tablo_adi,
    indexrelname AS indeks_adi,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS boyut
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE i.indisvalid = false;

-- Temizleme: Asla doğrudan DROP INDEX demeyin, canlıda yine CONCURRENTLY kullanın
DROP INDEX CONCURRENTLY IF EXISTS idx_kullanicilar_eposta;
```

---

## 3. Güvenli Kısıt (Constraint) Ekleme: `NOT VALID` Modeli

Milyonlarca satırlık bir tabloya `FOREIGN KEY` veya `CHECK` kısıtı eklemek tüm tabloyu doğrulamak için baştan sona kilitler. Çözüm, kısıtı iki aşamada eklemektir:

### Adım 1: Kısıtı Doğrulamadan Ekle (`NOT VALID`)
Sadece anlık bir metadata kilidi alır ve anında tamamlanır. Yeni yazılan veriler kısıta uymak zorundadır ancak eski veriler henüz taranmaz:

```sql
SET lock_timeout = '2s';

ALTER TABLE siparisler 
ADD CONSTRAINT fk_siparis_musteri 
FOREIGN KEY (musteri_id) REFERENCES musteriler(id) 
NOT VALID;
```

### Adım 2: Kısıtı Arka Planda Doğrula (`VALIDATE CONSTRAINT`)
Bu işlem yalnızca `ShareUpdateExclusiveLock` alır. Tabloya yazma, güncelleme ve silme işlemleri **kesintisiz devam eder**:

```sql
ALTER TABLE siparisler VALIDATE CONSTRAINT fk_siparis_musteri;
```

---

## 4. Büyük Tablolarda Sütun Tipi Değiştirme (Expand & Contract Deseni)

Bir `INTEGER` sütununu (örneğin müşteri bakiyesi veya sipariş numarası tükenmek üzereyken) `BIGINT` yapmak tüm tabloyu fiziksel olarak yeniden yazar (Table Rewrite) ve tablo saatlerce kilitlenebilir.

Bunu sıfır kesintiyle çözmek için **Expand and Contract (Genişlet ve Daralt)** deseni uygulanır:

```text
Faz 1: Yeni Sütunu Ekle (id_bigint)
Faz 2: Trigger ile Çift Yazma (Dual-Writing) Başlat
Faz 3: Geçmiş Verileri Küçük Parçalarla (Batch) Yeni Sütuna Taşı
Faz 4: Uygulama Kodunu Yeni Sütunu Okuyacak Şekilde Güncelle (Deploy)
Faz 5: Eski Sütunu ve Trigger'ı Güvenle Kaldır
```

### Uygulama Adımları:

```sql
-- Faz 1: Yeni sütun ekleme (Anında biter)
ALTER TABLE odemeler ADD COLUMN tutar_yeni BIGINT;

-- Faz 2: Çift yazma trigger fonksiyonu
CREATE OR REPLACE FUNCTION trg_sync_odemeler_tutar()
RETURNS TRIGGER AS $$
BEGIN
    NEW.tutar_yeni := COALESCE(NEW.tutar_yeni, NEW.tutar::bigint);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_odemeler_dual_write
BEFORE INSERT OR UPDATE ON odemeler
FOR EACH ROW EXECUTE FUNCTION trg_sync_odemeler_tutar();

-- Faz 3: Geçmiş veriyi 10.000'lik paketlerle arkada güncelleme (Lock engelleme)
DO $$
DECLARE
    v_rows_updated INT := 1;
BEGIN
    WHILE v_rows_updated > 0 LOOP
        UPDATE odemeler
        SET tutar_yeni = tutar::bigint
        WHERE id IN (
            SELECT id FROM odemeler 
            WHERE tutar_yeni IS NULL 
            LIMIT 10000
        );
        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
        COMMIT; -- Her 10.000 satırda kilitleri serbest bırak
        PERFORM pg_sleep(0.1); -- Disk I/O rahatlatma
    END LOOP;
END $$;
```

---

## 5. Güvenli `NOT NULL` Sütun Ekleme Stratejisi

PostgreSQL 11 öncesinde `DEFAULT` değer içeren bir sütun eklemek tüm tabloyu kilitlerdi. PostgreSQL 11+ ile sabit `DEFAULT` değerler metadata seviyesinde eklenir (hızlıdır). Ancak `NOT NULL` kısıtı tüm satırların kontrol edilmesini gerektirir.

### Güvenli Yaklaşım (PG 11+):

```sql
-- 1. Sütunu DEFAULT ile ekle (Metadata only - Anında)
ALTER TABLE musteriler ADD COLUMN aktif_mi BOOLEAN DEFAULT true;

-- 2. NOT NULL kısıtını CHECK ile NOT VALID olarak tanımla
ALTER TABLE musteriler ADD CONSTRAINT chk_musteriler_aktif_not_null 
CHECK (aktif_mi IS NOT NULL) NOT VALID;

-- 3. Canlıda doğrula (Yazmaları engellemez)
ALTER TABLE musteriler VALIDATE CONSTRAINT chk_musteriler_aktif_not_null;
```

---

## 6. Sıfır Kesintili Canlı Tablo Yeniden Düzenleme: `pg_repack`

Tablodaki aşırı şişkinliği (bloat) gidermek veya birincil anahtar sırasına göre tabloyu fiziksel olarak yeniden dizmek (`CLUSTER`) normalde tabloyu kilitler. `pg_repack`, trigger ve shadow log tablosu mimarisi kullanarak bunu canlıda kilit almadan yapar:

```bash
# Tabloyu kilitletmeden canlıda yeniden inşa etme
pg_repack -h localhost -U postgres -d e_ticaret --table siparisler
```

---

## 7. Üretim Ortamı Sıfır Kesinti Kuralları Özeti

1. **Hiçbir zaman doğrudan `CREATE INDEX` çalıştırmayın;** her zaman `CREATE INDEX CONCURRENTLY` kullanın ve işlem bittiğinde `indisvalid` durumunu denetleyin.
2. **Her DDL işleminden önce mutlaka `SET lock_timeout = '2s';` çalıştırın.**
3. **Doğrudan `ALTER TABLE ... ADD CONSTRAINT` yapmayın;** önce `NOT VALID`, ardından `VALIDATE CONSTRAINT` yaklaşımını izleyin.
4. **Büyük veri güncellemelerini tek bir `UPDATE` ile yapmayın;** `LIMIT` ve `pg_sleep` içeren batch döngüleri kullanın.
