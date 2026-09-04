# PostgreSQL Tablo Kalıtımı (Table Inheritance) ve Nesne-İlişkisel Tasarım

> **Bölüm Kapsamı:** PostgreSQL'e Özgü Tablo Kalıtımı (`INHERITS`), `ONLY` Söz Dizimi, Kalıtım vs Yabancı Anahtarlar (Foreign Keys) ve Çok Biçimlilik (Polymorphism)

---

PostgreSQL, saf bir ilişkisel veritabanı (RDBMS) değil, **Nesne-İlişkisel Veritabanı Yönetim Sistemi (ORDBMS)** olarak tasarlanmıştır. Bu felsefenin en belirgin yansımalarından biri, nesne yönelimli programlamadaki (OOP) sınıf kalıtımına benzeyen **Tablo Kalıtımı (Table Inheritance)** özelliğidir.

---

## 1. Tablo Kalıtımı Mantığı ve Temel Söz Dizimi

Tablo kalıtımında bir üst tablo (Parent Table) genel kolonları ve şablonu tanımlarken, alt tablolar (Child Tables) üst tablonun tüm kolonlarını devralır (`INHERIT`) ve kendine özgü ek kolonlar tanımlar.

### Örnek Senaryo: Coğrafi Yerleşim ve Başkentler

```sql
-- 1. Üst Tablo: Şehirler
CREATE TABLE cities (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    population BIGINT,
    altitude INT
);

-- 2. Alt Tablo: Başkentler (cities tablosundan türer)
CREATE TABLE capitals (
    state_capital_of TEXT NOT NULL,
    embassy_count INT DEFAULT 0
) INHERITS (cities);
```

`capitals` tablosunu tanımlarken `name`, `population` ve `altitude` kolonlarını tekrar yazmadık; bu kolonlar otomatik olarak `cities` tablosundan miras alındı.

```sql
-- Veri ekleme
INSERT INTO cities (name, population, altitude)
VALUES ('İzmir', 4400000, 2);

INSERT INTO capitals (name, population, altitude, state_capital_of, embassy_count)
VALUES ('Ankara', 5800000, 938, 'Türkiye', 135);
```

---

## 2. Sorgulama ve `ONLY` Anahtar Sözcüğü

Tablo kalıtımının en güçlü yönü, üst tablo sorgulandığında PostgreSQL'in **tüm alt tabloları da otomatik olarak taramasıdır**:

### a. Tüm Hiyerarşiyi Sorgulama

```sql
-- cities tablosunu sorguladığımızda hem İzmir hem Ankara döner!
SELECT name, altitude FROM cities;

-- Çıktı:
--  name  | altitude 
-- -------+----------
--  İzmir |        2
--  Ankara|      938
```

### b. Sadece Üst Tabloyu Sorgulama (`ONLY`)

Eğer alt tablolardaki satırları dahil etmek **istemiyorsanız**, tablonun önüne `ONLY` anahtar sözcüğü eklenir:

```sql
-- Sadece doğrudan cities tablosuna eklenen satırları getirir:
SELECT name, altitude FROM ONLY cities;

-- Çıktı:
--  name  | altitude 
-- -------+----------
--  İzmir |        2
```

Aynı `ONLY` kuralı `UPDATE` ve `DELETE` işlemleri için de geçerlidir:
- `UPDATE cities SET altitude = altitude + 10;` -> Tüm şehirleri ve başkentleri günceller.
- `UPDATE ONLY cities SET altitude = altitude + 10;` -> Sadece üst tablodaki şehirleri günceller.

---

## 3. Tablo Kalıtımı vs Yabancı Anahtar (Foreign Key)

Yazılım mimarları nesne hiyerarşilerini veritabanında modellerken genellikle iki yaklaşım arasında kalır:

| Kriter / Özellik | Tablo Kalıtımı (`INHERITS`) | Yabancı Anahtar (`FOREIGN KEY`) |
| :--- | :--- | :--- |
| **Sorgu Performansı** | `SELECT * FROM parent` tek seferde tüm alt tipleri getirir (JOIN gereksizdir). | Alt verileri çekmek için `LEFT JOIN` gerekir. |
| **Tekil İndeks Kısıtı (UNIQUE/PK)** | **Eksidir:** Her alt tablonun PK'sı kendi içindedir. Üst tablo genelinde global tekillik zorlanamaz. | **Artıdır:** Ana tabloda oluşturulan PK tüm alt tablolarda mutlak tekillik sağlar. |
| **Dış Anahtar Bütünlüğü** | Üst tabloya referans veren bir FK alt tablodaki satırları otomatik görmez. | Kusursuz `ON DELETE CASCADE` desteği. |
| **Şema Değişikliği** | Üst tabloya eklenen kolon anında tüm alt tablolara yansır. | Her tabloya manuel `ALTER TABLE` gerekir. |

### Ne Zaman Kalıtım Tercih Edilmeli?
- Varlıklar arasında gerçek bir "IS-A" (dır/dir) ilişkisi varsa (Örn: *Fatura bir Muhasebe Belgesidir*, *Sedan bir Taşıttır*).
- Çok biçimli (Polymorphic) raporlama sorgularında sürekli onlarca tabloyu JOIN etmek istemiyorsanız.

### Ne Zaman Yabancı Anahtar Tercih Edilmeli?
- Tablolar arasında kesin veri bütünlüğü ve global tekil anahtar (`UNIQUE`) garantisi şartsa.
- Standart ORM araçları (Hibernate, Entity Framework, Prisma) ile çalışıyorsanız (Çoğu ORM PostgreSQL kalıtımını desteklemez, FK ilişkilerini tercih eder).

---

## 4. Kalıtımın Sınırları ve Dikkat Edilmesi Gerekenler

> [!WARNING]
> **Kalıtım Kısıtlamaları:**
> 1. **Global Uniqueness Yoktur:** `cities` tablosunda `id = 1` olan bir kayıt varken, `capitals` tablosuna da `id = 1` eklenebilir. B-Tree indeksler tablolar arasında paylaşılamaz.
> 2. **Tarihsel Not (Partitioning):** PostgreSQL 10 öncesinde veritabanı bölümleme (partitioning) kalıtım ve tetikleyiciler (`INHERITS + TRIGGER`) ile yapılıyordu. Güncel PostgreSQL sürümlerinde bölümleme için kalıtım **KULLANILMAMALIDIR**; mutlaka Bölüm 05'te anlattığımız **Declarative Partitioning (`PARTITION BY`)** tercih edilmelidir.
