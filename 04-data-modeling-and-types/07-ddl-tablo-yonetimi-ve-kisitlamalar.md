# Tablo Yönetimi, Kısıtlamalar (Constraints) ve Çapraz VTYS DDL Rehberi

> **Bölüm Kapsamı:** Tablo Yaşam Döngüsü (`CREATE`, `ALTER`, `DROP`), Bütünlük Kısıtlamaları (`PK`, `FK`, `UNIQUE`, `CHECK`, `NOT NULL`), `ON DELETE` Eylemleri, Çapraz VTYS Sözdizimi Farkları (`MODIFY` vs `ALTER COLUMN`), Kısıtlamaların Geçici Kapatılması / Toplu Veri Yükleme ve Temel İndeksleme.

---

## 1. Giriş ve Veri Tanımlama Dili (DDL)

İlişkisel veritabanlarının (RDBMS) temel taşı, verilerin belirli kurallara ve ilişkilere bağlı olarak depolandığı **Tablo (Relation)** yapılarıdır. **DDL (Data Definition Language)** komutları, veritabanının fiziksel ve mantıksal iskeletini inşa eder.

Bir tablonun tasarımı, verinin bütünlüğünü (Data Integrity) doğrudan belirler. Hatalı kurgulanmış kısıtlamalar (constraints) ya da eksik indeksler, production ortamında performans çöküşlerine ve kirli verilere (dirty data) neden olur.

---

## 2. Bütünlük Kısıtlamaları (Data Integrity Constraints)

Kısıtlamalar, veritabanına eklenen veya güncellenen kayıtların belirlenen iş kurallarına uymasını zorunlu kılan kurallardır.

### a. PRIMARY KEY (Birincil Anahtar)
Bir tablodaki her satırı benzersiz (unique) kılan ve `NULL` değer kabul etmeyen kuraldır. PostgreSQL otomatik olarak birincil anahtar üzerinde benzersiz bir B-Tree indeksi oluşturur.

```sql
-- Tek Kolonlu PK
CREATE TABLE departmanlar (
    departman_id SERIAL PRIMARY KEY,
    departman_adi VARCHAR(50) NOT NULL
);

-- Bileşik (Composite) PK (Birden fazla kolonun birleşimiyle tekillik)
CREATE TABLE proje_gorevlendirme (
    proje_id INT NOT NULL,
    personel_id INT NOT NULL,
    gorev_tanimi VARCHAR(100),
    PRIMARY KEY (proje_id, personel_id)
);
```

### b. FOREIGN KEY (Yabancı Anahtar) ve Referans Bütünlüğü
İki tablo arasındaki ilişkiyi kurar. Bir tablodaki kolonun, diğer tablonun `PRIMARY KEY` veya `UNIQUE` kolonuna başvurmasını zorunlu kılar.

```sql
CREATE TABLE calisanlar (
    calisan_id SERIAL PRIMARY KEY,
    ad VARCHAR(50) NOT NULL,
    soyad VARCHAR(50) NOT NULL,
    departman_id INT,
    CONSTRAINT fk_calisan_departman 
        FOREIGN KEY (departman_id) 
        REFERENCES departmanlar(departman_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
```

#### `ON DELETE` / `ON UPDATE` Silme ve Güncelleme Eylemleri

Ana (Parent) tablodaki bir kayıt silindiğinde veya güncellendiğinde, çocuk (Child) tablonun nasıl davranacağını belirleyen 5 seçenek vardır:

| Seçenek | Davranış | Kullanım Amacı |
| :--- | :--- | :--- |
| **`CASCADE`** | Ana tablodaki satır silinirse/güncellenirse, ilişkili tüm çocuk kayıtlar da otomatik olarak silinir veya güncellenir. | Fatura -> Fatura Kalemleri ilişkisi gibi bağımlı modeller. |
| **`RESTRICT`** | Eğer çocuk tabloda ilişkili kayıt varsa, ana tablodaki silme/güncelleme işlemini anında engeller ve hata fırlatır. Kısıtlama denetimi ertelenemez (`immediate`). | Kritik verilerin yanlışlıkla silinmesini engellemek. |
| **`NO ACTION`** | SQL standardında varsayılandır. `RESTRICT` gibi silmeyi engeller; ancak `DEFERRABLE` (ertelenebilir) tanımlanmışsa kontrol transaction sonuna ertelenebilir. | Standart ilişkisel bütünlük garantisi. |
| **`SET NULL`** | Ana tablodaki satır silindiğinde, çocuk tablodaki yabancı anahtar kolonu otomatik olarak `NULL` yapılır. | Çalışanın departmanı kapatıldığında çalışanın kurumda kalması hali. |
| **`SET DEFAULT`** | Ana tablodaki satır silindiğinde, çocuk tablodaki kolon tanımlı varsayılan değere (`DEFAULT`) atanır. | Varsayılan bir havuza veya 'Genel' departmanına aktarma. |

> [!TIP]
> **Transaction İçi Erteleme (`DEFERRABLE INITIALLY DEFERRED`):**
> Döngüsel bağımlılık olan (Circular Dependency) senaryolarda (Örn: Tablo A Tablo B'ye, Tablo B Tablo A'ya bakar) normalde kayıt eklenemez. Kısıtlama `DEFERRABLE INITIALLY DEFERRED` olarak tanımlanırsa, referans kontrolü işlem anında değil `COMMIT` atılırken yapılır:
> ```sql
> CONSTRAINT fk_ornek FOREIGN KEY (ref_id) REFERENCES diger_tablo(id) DEFERRABLE INITIALLY DEFERRED;
> ```

### c. UNIQUE (Tekillik) Kısıtlaması
Kolondaki değerlerin benzersiz olmasını zorunlu kılar. 

* **Standart Davranış ve NULL Tuzağı:** SQL standardına ve klasik PostgreSQL davranışına göre `NULL` bir değer olmadığı (bilinmeyen olduğu) için, varsayılan olarak bir `UNIQUE` sütuna birden fazla `NULL` eklenebilir.
* **PostgreSQL 15+ İnovasyonu (`NULLS NOT DISTINCT`):**
  Eğer `NULL` değerlerin de tekil olmasını (yani yalnızca bir adet NULL eklenebilmesini) istiyorsanız:
  ```sql
  CREATE TABLE musteriler (
      id SERIAL PRIMARY KEY,
      eposta VARCHAR(100),
      CONSTRAINT uq_eposta UNIQUE NULLS NOT DISTINCT (eposta)
  );
  ```

### d. CHECK (Koşul Denetimi) Kısıtlaması
Satırın belirli bir mantıksal şartı (`BOOLEAN`) sağlamasını zorunlu kılar.

```sql
CREATE TABLE siparis_kalemleri (
    id SERIAL PRIMARY KEY,
    adet INT CHECK (adet > 0),
    birim_fiyat NUMERIC(10,2) CHECK (birim_fiyat >= 0),
    indirim_orani NUMERIC(3,2) CHECK (indirim_orani BETWEEN 0.00 AND 1.00),
    eposta TEXT CHECK (eposta ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);
```

### e. NOT NULL Kısıtlaması
Kolonun değer almasını zorunlu kılar, boş (`NULL`) geçilemez.

---

## 3. Tablo Yapısını Değiştirme (`ALTER TABLE`) ve Çapraz VTYS Farkları

Geleneksel veritabanı ders kitaplarında gösterilen sözdizimleri ile modern PostgreSQL sözdizimi arasında bazı önemli farklar vardır:

### a. Kolon Tipi Değiştirme: `MODIFY` vs `ALTER COLUMN ... TYPE`

* **Oracle & MySQL Sözdizimi:**
  ```sql
  -- Oracle / MySQL:
  ALTER TABLE personel MODIFY maas NUMERIC(12,2);
  ```
* **PostgreSQL Sözdizimi:**
  PostgreSQL'de `MODIFY` anahtar kelimesi yoktur. Standart ANSI `ALTER COLUMN` kullanılır:
  ```sql
  -- PostgreSQL:
  ALTER TABLE personel ALTER COLUMN maas TYPE NUMERIC(12,2);
  
  -- Tip dönüşümü otomatik yapılamıyorsa USING yan tümcesi gerekir:
  ALTER TABLE personel ALTER COLUMN telefon TYPE BIGINT USING (telefon::BIGINT);
  
  -- NOT NULL ekleme / kaldırma:
  ALTER TABLE personel ALTER COLUMN maas SET NOT NULL;
  ALTER TABLE personel ALTER COLUMN maas DROP NOT NULL;
  ```

### b. Kolon ve Tablo Yeniden Adlandırma (Renaming)

* **Geleneksel / Diğer VTYS:**
  ```sql
  -- Bazı sistemlerde:
  ALTER TABLE personel RENAME adi pers_adi;
  RENAME TABLE personel TO calisanlar;
  ```
* **PostgreSQL Standart Sözdizimi:**
  ```sql
  -- Kolon adı değiştirme:
  ALTER TABLE personel RENAME COLUMN adi TO pers_adi;
  
  -- Tablo adı değiştirme:
  ALTER TABLE personel RENAME TO calisanlar;
  ```

### c. Kolon Ekleme ve Silme
```sql
-- Yeni Kolon Ekleme:
ALTER TABLE personel ADD COLUMN eposta VARCHAR(100);

-- Kolon Silme (ve varsa bağımlı view/constraint'leri temizleme):
ALTER TABLE personel DROP COLUMN eposta CASCADE;
```

---

## 4. Kısıtlamaları Geçici Olarak Devre Dışı Bırakma (Constraint Disabling / Toplu Veri Yükleme)

Veritabanına milyonlarca satır veri aktarırken (ETL, veri ambarı yüklemeleri, migration), her satır için Foreign Key veya Trigger kontrollerinin çalışması işlemi saatlerce yavaşlatabilir.

### Geleneksel Ders Kitabı Yaklaşımı (Oracle / MS SQL):
```sql
-- Oracle / SQL Server:
ALTER TABLE siparis DISABLE CONSTRAINT fk_musteri;
-- ... Toplu veri yükleme ...
ALTER TABLE siparis ENABLE CONSTRAINT fk_musteri;
```

### PostgreSQL Mimarisi ve Çözümleri:
PostgreSQL'de `ALTER TABLE ... DISABLE CONSTRAINT` komutu **yoktur**. PostgreSQL veri bütünlüğünü sıkı bir şekilde garanti eder. Ancak kurumsal seviyede bunu yönetmenin üç profesyonel yolu vardır:

#### 1. Oturum Seviyesinde Replikasyon Rolünü Kullanmak (En Hızlı Yöntem)
Yalnızca mevcut oturum için kısıtlamaları ve tetikleyicileri askıya alır:
```sql
-- Kısıtlamaları ve tetikleyicileri devre dışı bırak:
SET session_replication_role = 'replica';

-- ... Hızlı toplu INSERT / COPY işlemi ...

-- Normale dön:
SET session_replication_role = 'origin';
```

#### 2. Tablo Tetikleyicilerini Kapatmak (Foreign Key'ler Arka Planda Sistem Tetikleyicisidir)
```sql
-- Superuser yetkisiyle Foreign Key tetikleyicilerini askıya alma:
ALTER TABLE siparis DISABLE TRIGGER ALL;

-- ... Toplu veri yükleme ...

-- Tekrar devreye alma:
ALTER TABLE siparis ENABLE TRIGGER ALL;
```

#### 3. Sıfır Kesinti (Zero-Downtime) `NOT VALID` Stratejisi
Canlı sistemlerde büyük bir tabloya kısıtlama eklerken tabloyu kilitlememek (Exclusive Lock almamak) için iki adımlı yöntem kullanılır:
```sql
-- 1. Adım: Kısıtlamayı sadece yeni gelecek satırlar için aç (Anında biter, tabloyu kilitlemez):
ALTER TABLE siparis 
ADD CONSTRAINT fk_siparis_musteri 
FOREIGN KEY (musteri_id) REFERENCES musteriler(id) NOT VALID;

-- 2. Adım: Mevcut eski verileri arka planda doğrula (SELECT seviyesinde kilit alır, canlı sistemi durdurmaz):
ALTER TABLE siparis VALIDATE CONSTRAINT fk_siparis_musteri;
```

---

## 5. Temel İndeksleme Mantığı (Giriş Seviyesi)

İndeks, tablodaki satırlara hızlı erişim sağlamak için veritabanı motorunun arka planda tuttuğu ek bir arama ağacıdır (genellikle Dengeli B-Tree).

### Neden İndeks Kullanılır?
* **İndekssiz Tablo:** Veritabanı aranan kaydı bulmak için tablonun ilk sayfasından son sayfasına kadar her satırı tek tek okur (**Sequential Scan / Tam Tablo Taraması**). Milyonlarca satırda bu işlem saniyeler hatta dakikalar sürer.
* **İndeksli Tablo:** Bir kitabın sonundaki fihrist gibidir. Aranan değer $O(\log N)$ karmaşıklığında bulunur ve doğrudan satırın diskteki sayfasına (`ctid`) gidilir (**Index Scan**).

### Temel İndeks DDL Komutları
```sql
-- 1. Temel B-Tree İndeksi Oluşturma:
CREATE INDEX idx_personel_soyad ON personel (soyad);

-- 2. Azalan Sırada (DESC) ve NULL değerleri öne/arkaya koyarak indeksleme:
CREATE INDEX idx_personel_maas ON personel (maas DESC NULLS LAST);

-- 3. Canlı Sistemde Okuma/Yazmayı Durdurmadan İndeks Oluşturma (Production Standartı):
CREATE INDEX CONCURRENTLY idx_personel_brut ON personel (brut);

-- 4. İndeksi Silme:
DROP INDEX idx_personel_soyad;
DROP INDEX CONCURRENTLY idx_personel_brut;
```

---

## 6. Özet Karşılaştırma Matrisi

| İşlem | Oracle / MS SQL / MySQL | PostgreSQL Standartı |
| :--- | :--- | :--- |
| **Kolon Tipi Değiştirme** | `ALTER TABLE t MODIFY col INT;` | `ALTER TABLE t ALTER COLUMN col TYPE INT;` |
| **Kolon Adı Değiştirme** | `ALTER TABLE t RENAME col TO new_col;` | `ALTER TABLE t RENAME COLUMN col TO new_col;` |
| **Toplu Yüklemede FK Kapatma** | `ALTER TABLE t DISABLE CONSTRAINT c;` | `SET session_replication_role = 'replica';` veya `DISABLE TRIGGER ALL;` |
| **Büyük Tabloya Kilit Atmadan FK** | Özel DDL scriptleri | `ADD CONSTRAINT ... NOT VALID` + `VALIDATE CONSTRAINT` |
| **Canlıda İndeksleme** | `ONLINE = ON` (MSSQL/Oracle) | `CREATE INDEX CONCURRENTLY` |
