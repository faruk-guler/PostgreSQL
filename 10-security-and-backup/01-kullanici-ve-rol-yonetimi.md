# Kullanıcı ve Rol Yönetimi (RBAC)

PostgreSQL'de kullanıcı (User) ve grup (Group) ayrımı yoktur. Her şey bir **Rol (Role)** olarak tanımlanır. Giriş yapabilen (Login) rollere geleneksel olarak "Kullanıcı", giriş yapamayan ama yetki kümesi olarak kullanılan rollere ise "Grup" denir.

---

## 1. Rol (Role) Oluşturma

Sisteme bağlanacak roller oluşturulurken onlara atanan temel yetkiler (Attributes) belirlenir. 

```sql
-- Giriş yetkisi (LOGIN) olan şifreli bir kullanıcı oluşturma
CREATE ROLE mehmet LOGIN PASSWORD 'Guv3nliSifre!123';

-- (VEYA) Kısayol olarak CREATE USER kullanılabilir 
CREATE USER mehmet PASSWORD 'Guv3nliSifre!123';

-- Giriş yetkisi OLMAYAN bir grup rolü oluşturma
CREATE ROLE raporlama_grubu NOLOGIN;
```

### Rol Nitelikleri (Attributes)
Bir rol oluştururken veya sonradan değiştirirken şu nitelikler eklenebilir:
*   `LOGIN` / `NOLOGIN`: Veritabanına bağlanabilme yetkisi.
*   `SUPERUSER` / `NOSUPERUSER`: Tüm kısıtlamaları (Bypass) aşan, veritabanının en yetkili kullanıcısı (Sınırlı kullanılmalıdır).
*   `CREATEDB` / `NOCREATEDB`: Yeni veritabanı oluşturabilme yetkisi.
*   `CREATEROLE` / `NOCREATEROLE`: Başka roller oluşturma/silme yetkisi.

```sql
-- Mehmet kullanıcısına veritabanı oluşturma yetkisi verelim
ALTER ROLE mehmet CREATEDB;
```

---

## 2. Grup ve Yetki Ataması (GRANT)

Bir rolün yetkilerini başka bir role (Kullanıcıya) devredebilirsiniz. Bu sayede RBAC (Role-Based Access Control) sistemi kurulur.

```sql
-- 1. Yetki paketleri (Gruplar) oluştur
CREATE ROLE okuyucular NOLOGIN;
CREATE ROLE yazicilar NOLOGIN;

-- 2. Kullanıcılar oluştur
CREATE USER ali PASSWORD '123';
CREATE USER ayse PASSWORD '456';

-- 3. Kullanıcıları gruplara ata (GRANT)
GRANT okuyucular TO ali;
GRANT yazicilar TO ayse;
GRANT okuyucular TO ayse; -- Ayşe hem yazıcı hem okuyucu oldu
```

### INHERIT (Yetki Mirası) Özelliği
Eğer bir rol `INHERIT` parametresi ile oluşturulmuşsa (PostgreSQL 16'ya kadar varsayılan olarak böyledir), atandığı grubun yetkilerini **otomatik olarak** doğrudan kullanabilir.

Eğer `NOINHERIT` ile oluşturulmuşsa, kullanıcı sisteme girdiğinde grubun yetkilerini hemen kullanamaz. Sadece geçici olarak o gruba bürünmesi (Switch) gerekir:
```sql
SET ROLE okuyucular;
-- ... işlemleri yap ...
RESET ROLE;
```

---

## 3. Rollerin Listelenmesi ve Silinmesi

### Listeleme (psql)
`\du` veya `\du+` komutu kullanılarak sistemdeki tüm roller ve nitelikleri görüntülenebilir.

### Rol Silme (DROP ROLE)
Bir rolü silebilmek için, o rolün sahip olduğu hiçbir tablo veya nesne **olmamalıdır**. Eğer varsa, önce bu nesnelerin sahipliği başkasına devredilmelidir.

```sql
-- 1. Mehmet'in sahip olduğu her şeyi postgres kullanıcısına devret
REASSIGN OWNED BY mehmet TO postgres;

-- 2. Mehmet'in üzerinde olan GRANT (Erişim) yetkilerini temizle
DROP OWNED BY mehmet;

-- 3. Artık güvenle silebiliriz
DROP ROLE mehmet;
```
