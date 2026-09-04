# Veritabanı Göçleri (Migrations) ve CI/CD Süreçleri

> **Bölüm Kapsamı:** Database-as-Code, Şema Versiyonlama, Flyway, Liquibase ve CI/CD Pipeline Entegrasyonu

---

## 1. "Database as Code" (DaC) Kavramı

Geleneksel veritabanı yönetiminde, DBA veya geliştirici production sunucusuna bağlanır ve manuel olarak `CREATE TABLE` veya `ALTER TABLE` komutlarını çalıştırır. Bu yaklaşım modern yazılım süreçleri (Agile/DevOps) için büyük bir risktir.

**Neden Migration (Göç) Araçları Kullanmalıyız?**
1. **Versiyon Kontrolü:** Veritabanı şemasındaki her değişiklik (tıpkı uygulama kodu gibi) Git üzerinde tutulmalıdır.
2. **Tekrarlanabilirlik:** Bir geliştiricinin lokalinde çalışan veritabanı şeması, Staging ve Production ortamında da **birebir aynı** şekilde kurulabilmelidir.
3. **Geri Alma (Rollback):** Hatalı bir `ALTER` komutunu anında eski haline getirebilmek (Undo) gerekir.

---

## 2. Popüler Migration Araçları Karşılaştırması

| Araç | Yazım Dili / Format | Kimler İçin Uygun? | Özellikler |
| :--- | :--- | :--- | :--- |
| **Flyway** | Saf SQL (`.sql`) | Saf SQL yazmayı seven DBA'ler ve Backend geliştiriciler | Çok hızlı, basit, öğrenme eğrisi sıfır. Sadece SQL yazar ve çalıştırırsınız. |
| **Liquibase** | XML, YAML, JSON, SQL | Enterprise (Büyük) Ekipler, Farklı DB Türleri Kullananlar | Veritabanı bağımsız (Aynı XML ile hem Oracle hem PG yönetilebilir). Gelişmiş Rollback. |
| **Alembic** | Python | Python / Django / FastAPI Geliştiricileri | SQLAlchemy ile tam uyumlu. |
| **Prisma** | Prisma Schema | Node.js / TypeScript Geliştiricileri | ORM ile iç içe, çok popüler. |

---

## 3. Flyway ile Temel Çalışma Mantığı

Flyway, veritabanınızda `flyway_schema_history` adında özel bir tablo oluşturur ve hangi script'lerin başarıyla çalıştığını takip eder.

### Dosya İsimlendirme Standardı

Flyway scriptleri özel bir isim formatına sahip olmalıdır:
`V<Versiyon>__<Açıklama>.sql` *(Not: İki adet alt çizgi `__` içerir)*

- `V1__init_schema.sql` (İlk veritabanı oluşturma)
- `V2__add_users_table.sql`
- `V3__add_index_to_email.sql`

### Örnek Migration Dosyası (`V2__add_users_table.sql`)

```sql
-- DDL Komutları
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- DML Komutları (Veri manipülasyonu da eklenebilir)
INSERT INTO users (email) VALUES ('admin@example.com');
```

---

## 4. CI/CD (Sürekli Entegrasyon) Pipeline Entegrasyonu

Veritabanı migration'larını manuel olarak lokalden çalıştırmak yerine, Github Actions, Gitlab CI veya Jenkins üzerinden **otomatize** etmelisiniz.

### GitHub Actions Örnek YAML (Flyway CI/CD)

Aşağıdaki pipeline, `main` dalına kod (veya .sql dosyası) push edildiğinde veritabanını otomatik günceller:

```yaml
name: Database Migration (Flyway)

on:
  push:
    branches:
      - main
    paths:
      - 'db/migrations/**' # Sadece db klasörü değişirse çalıştır

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repo
        uses: actions/checkout@v4

      - name: Run Flyway Migrate
        uses: flyway/flyway-github-action@v2
        with:
          url: jdbc:postgresql://${{ secrets.DB_HOST }}:5432/${{ secrets.DB_NAME }}
          user: ${{ secrets.DB_USER }}
          password: ${{ secrets.DB_PASSWORD }}
          locations: filesystem:db/migrations
          command: migrate
```

---

## 5. İleri Seviye Migration Pratikleri (Zero-Downtime)

Production veritabanında migration çalıştırırken sistemin **kesintiye uğramaması (Zero-Downtime)** için şu kurallara dikkat edin:

1. **Transaction İçinde DDL:** PostgreSQL, `ALTER TABLE` gibi DDL komutlarını Transaction (`BEGIN ... COMMIT`) içinde çalıştırabilen nadir veritabanlarındandır. Flyway bunu varsayılan olarak destekler. Bir hata olursa tablo yarım kalmaz, tamamen Rollback olur.
2. **Kilitleri (Locks) Gözlemleyin:** Büyük bir tabloya sütun eklerken varsayılan değer (DEFAULT) verirseniz tablo tamamen kilitlenebilir (PG 11 öncesi için). Modern PG sürümlerinde güvenlidir.
3. **İndeks Oluşturma:** `CREATE INDEX` komutu tabloyu yazmaya (UPDATE/INSERT) kilitler. Migration script'lerinizde **daima** `CREATE INDEX CONCURRENTLY` kullanın.
4. **Sütun Silme (Drop Column):** Bir sütunu silmek istiyorsanız, önce kod (Uygulama) katmanında o sütunun kullanımını kaldırın (Deploy edin). Ardından veritabanından sütunu silen migration'ı çalıştırın. İkisini aynı anda yapmak uygulamanın hata vermesine neden olur.
