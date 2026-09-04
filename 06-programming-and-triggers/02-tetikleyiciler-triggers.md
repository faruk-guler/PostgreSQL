# Tetikleyiciler (Triggers)

Tetikleyiciler, veritabanındaki bir tabloda (veya view'da) önceden belirlenmiş bir olay (`INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`) gerçekleştiğinde **otomatik olarak** devreye giren PL/pgSQL fonksiyonlarıdır.

En yaygın kullanım alanları:
*   Veri denetimi (Audit Logging - Kim ne zaman neyi değiştirdi?)
*   Kompleks iş kurallarının kontrolü (Örn: "Stok sıfırın altındaysa satışı engelle")
*   Data Warehousing (Satış eklendiğinde toplam ciro tablosunu otomatik güncelle)

---

## 1. Tetikleyici Mimarisi

Bir tetikleyici oluşturmak iki aşamalıdır:
1.  Önce tetiklendiğinde çalışacak **Tetikleyici Fonksiyonu** oluşturulur. Bu fonksiyon `RETURNS trigger` olmak zorundadır ve giriş parametresi almaz.
2.  Daha sonra `CREATE TRIGGER` komutu ile fonksiyon tabloya bağlanır.

### Zamanlama ve Seviye
Tetikleyiciler çalışma zamanına göre üçe ayrılır:
*   **`BEFORE`**: Veritabanı veriyi tabloya yazmadan hemen önce araya girer. Veriyi değiştirmek (Örn: metni tamamen büyük harfe çevirmek) veya kaydı iptal etmek (`RAISE EXCEPTION`) için kullanılır.
*   **`AFTER`**: Veri tabloya başarıyla yazıldıktan sonra çalışır. Başka tablolara log (kayıt) atmak veya özet tabloları güncellemek için kullanılır.
*   **`INSTEAD OF`**: Sadece `VIEW` (Görünüm) nesnelerinde çalışır. View üzerine Insert yapılamadığı için, gelen insert isteğini yakalayıp asıl tablolara yönlendirmek için kullanılır.

> [!WARNING]
> Tetikleyiciler çok güçlüdür ancak kötü yazılırlarsa performansı öldürürler. Özellikle `FOR EACH ROW` (Her satır için çalış) tanımlanmış bir tetikleyici, `UPDATE urunler SET fiyat = fiyat * 1.10;` gibi 1 Milyon satırı güncelleyen bir sorguda **1 Milyon kez** çalışacaktır!

---

## 2. Tetikleyici Özel Değişkenleri

PL/pgSQL bir tetikleyici fonksiyonu içindeyken sisteme dair bilgileri otomatik olarak bazı özel değişkenlere doldurur:

| Değişken | Açıklama | Hangi İşlemde Doludur? |
| :--- | :--- | :--- |
| **`NEW`** | Tabloya eklenecek/güncellenecek **yeni** satırın verilerini tutan `RECORD`. | `INSERT`, `UPDATE` |
| **`OLD`** | Tablodan silinecek veya güncellenmeden önceki **eski** satırın verilerini tutar. | `UPDATE`, `DELETE` |
| **`TG_OP`** | Tetikleyicinin hangi işlem sonucu çağrıldığını tutar. | Tümü (Değeri: 'INSERT', 'UPDATE', 'DELETE' veya 'TRUNCATE') |
| **`TG_TABLE_NAME`** | Tetikleyicinin bağlandığı tablonun adı. | Tümü |

---

## 3. Örnek: Audit Logging (Değişiklik Tarihçesi) Tutma

Veritabanlarındaki en klasik trigger uygulamasıdır. `personel` tablosunda yapılan her işlemi `personel_log` tablosuna kaydedelim.

### 1. Log Tablosunu Oluşturalım
```sql
CREATE TABLE personel_log(
    islem_turu CHAR(1),     -- I (Insert), U (Update), D (Delete)
    islem_zamani TIMESTAMP, -- Ne zaman yapıldı?
    kullanici TEXT,         -- Kim yaptı?
    eski_isim TEXT,
    yeni_isim TEXT
);
```

### 2. Tetikleyici Fonksiyonunu Yazalım
```sql
CREATE OR REPLACE FUNCTION log_personel_degisikligi() 
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO personel_log VALUES ('I', now(), current_user, NULL, NEW.isim);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO personel_log VALUES ('U', now(), current_user, OLD.isim, NEW.isim);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO personel_log VALUES ('D', now(), current_user, OLD.isim, NULL);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;
```

### 3. Tetikleyiciyi Tabloya Bağlayalım
```sql
CREATE TRIGGER personel_log_trigger
AFTER INSERT OR UPDATE OR DELETE ON personel
FOR EACH ROW EXECUTE FUNCTION log_personel_degisikligi();
```

---

## 4. Örnek: Veri Bütünlüğünü (Data Integrity) Korumak

`BEFORE` trigger'ı kullanarak yanlış veri girişini engelleyebiliriz.

```sql
CREATE OR REPLACE FUNCTION maas_kontrolu() 
RETURNS TRIGGER AS $$
BEGIN
    -- Maaş eksi değer olamaz
    IF NEW.maas < 0 THEN
        RAISE EXCEPTION 'Maaş sıfırdan küçük olamaz! Girilen Değer: %', NEW.maas;
    END IF;
    
    -- Her şey yolundaysa kaydın işlenmesine izin ver
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Tabloya bağlama
CREATE TRIGGER maas_kontrol_trigger
BEFORE INSERT OR UPDATE ON personel
FOR EACH ROW EXECUTE FUNCTION maas_kontrolu();
```
> [!CAUTION]
> `BEFORE` tetikleyicilerinde mutlaka `RETURN NEW;` yapmalısınız (Insert ve Update için). Eğer `RETURN NULL;` derseniz, PostgreSQL işlemi sessizce iptal eder ve kayıt tabloya **yazılmaz**.
