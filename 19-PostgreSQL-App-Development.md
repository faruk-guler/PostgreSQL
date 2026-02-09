# 19-PostgreSQL-App-Development

Veritabanı ne kadar iyi ayarlanırsa ayarlansın, uygulama kodu kötüyse performans yerlerde sürünür. Bu doküman, geliştiriciler için PostgreSQL ile konuşmanın "doğru" yolunu anlatır.

---

## 1. Altın Kurallar

1. **Asla her istekte yeni bağlantı açıp kapatma.** Connection Pool kullan.
2. **ORM'lere körü körüne güvenme.** N+1 sorgu sorununa dikkat et.
3. **İş mantığını transaction içine hapset.** "Yarım kalan" işlemler veriyi bozar.
4. **Hataları doğru yakala.** "Serialization Failure" (40001) hatasında işlemi yeniden dene (Retry).

---

## 2. Python ile Bağlantı (psycopg 3)

Modern Python projelerinde `psycopg2` yerine yeni nesil `psycopg` (v3) kullanılmalıdır.

### Kurulum

```bash
pip install "psycopg[binary,pool]"
```

### Connection Pool Örneği

```python
import time
from psycopg_pool import ConnectionPool
from psycopg.errors import SerializationFailure

# Pool'u uygulama başlarken bir kere oluştur
pool = ConnectionPool(
    conninfo="postgresql://user:pass@localhost/mydb",
    min_size=4,
    max_size=20
)

def transfer_funds(from_id, to_id, amount):
    # Retry Loop (Serialization hatası için)
    while True:
        try:
            with pool.connection() as conn:
                with conn.cursor() as cur:
                    # Transaction bloğu
                    with conn.transaction():
                        # Parayı çek
                        cur.execute(
                            "UPDATE accounts SET balance = balance - %s WHERE id = %s",
                            (amount, from_id)
                        )
                        # Parayı yatır
                        cur.execute(
                            "UPDATE accounts SET balance = balance + %s WHERE id = %s",
                            (amount, to_id)
                        )
            # Başarılı olursa döngüden çık
            print("Transfer başarılı!")
            break
            
        except SerializationFailure:
            # PostgreSQL "Çakışma var, işlemi baştan yap" dedi.
            print("Çakışma algılandı, tekrar deneniyor...")
            time.sleep(0.1)
            continue
            
        except Exception as e:
            print(f"Kritik hata: {e}")
            break
```

---

## 3. Go ile Bağlantı (pgx v5)

Go dünyasında standart sürücü `lib/pq` değil, performans canavarı **`pgx`**'tir.

### Kurulum

```bash
go get github.com/jackc/pgx/v5
```

### Batch Insert (Toplu Kayıt)

Tek tek `INSERT` yapmak yerine `CopyFrom` kullanarak saniyede on binlerce kayıt atabilirsiniz.

```go
package main

import (
 "context"
 "github.com/jackc/pgx/v5"
 "github.com/jackc/pgx/v5/pgxpool"
)

func main() {
 dbpool, _ := pgxpool.New(context.Background(), "postgres://user:pass@localhost/mydb")
 defer dbpool.Close()

 rows := [][]interface{}{
  {"Ahmet", 25},
  {"Ayşe", 30},
  {"Mehmet", 22},
 }

 // COPY protokolü ile ultra hızlı insert
 copyCount, err := dbpool.CopyFrom(
  context.Background(),
  pgx.Identifier{"users"},
  []string{"name", "age"},
  pgx.CopyFromRows(rows),
 )
    
    if err != nil {
        panic(err)
    }
    println("Eklenen kayıt:", copyCount)
}
```

---

## 4. Pipeline Mode (v14+)

İstemci-Sunucu arasındaki "Git-Gel" (Round-Trip) süresini düşürmek için Pipeline modu kullanılır. Çok sayıda küçük sorgu için `AsyncIO` benzeri bir hız sağlar.

**Senaryo:** 5 farklı tablodan, birbirine bağımlı olmayan veriler çekeceksiniz.

```python
# Psycopg 3 Pipeline Örneği
with conn.pipeline():
    cur.execute("SELECT count(*) FROM users")
    cur.execute("SELECT count(*) FROM orders")
    cur.execute("SELECT count(*) FROM products")
    # Sorgular sunucuya tek pakette gitti, cevaplar tek pakette döndü.
```

---

## 5. Prepared Statements (Hazırlanmış Sorgular)

SQL Injection'dan korunmanın ve performansı artırmanın yoludur. Sorgu planı (Query Plan) önbelleğe alınır.

Yanlış:

```python
# GÜVENSİZ VE YAVAŞ
cur.execute(f"SELECT * FROM users WHERE id = {user_id}")
```

### 5-b. Plan Caching & Invalidation

PostgreSQL `PREPARE` edilen sorgular için iki tür plan kullanır:

1. **Custom Plan:** Her execution için parametreye özel plan (İlk 5 çalıştırma).
2. **Generic Plan:** Parametrelerden bağımsız, cache'lenmiş plan (6. çalıştırmadan sonra - eğer maliyeti uygunsa).

**Plan Caching Mode (PG 12+):**

```sql
-- Otomatik (Varsayılan)
SET plan_cache_mode = 'auto';

-- Zorla Custom Plan (Veri dağılımı çok dengesizse - örn: status='ACTIVE' %90, 'BANNED' %1)
SET plan_cache_mode = 'force_custom_plan';

-- Zorla Generic Plan (Çok basit sorgular için planning süresinden tasarruf)
SET plan_cache_mode = 'force_generic_plan';
```

**Plan Invalidation:**
Prepared statement planları şu durumlarda geçersiz olur (ve yeniden planlanır):

- Tablo yapısı değişirse (ALTER TABLE, CREATE INDEX)
- `ANALYZE` sonrası istatistikler ciddi oranda değişirse

```sql
-- Tüm cache'i temizle
DEALLOCATE ALL;
```

Doğru:

```python
# GÜVENLİ VE HIZLI
cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

### Server-Side Prepare

Eğer aynı sorguyu milyonlarca kez çalıştıracaksanız, PostgreSQL tarafında prepare edin:

```sql
PREPARE get_user (int) AS SELECT * FROM users WHERE id = $1;

-- Defalarca çağır
EXECUTE get_user(101);
EXECUTE get_user(102);
```

Çoğu modern sürücü (driver) bunu sizin yerinize otomatik yapar.

---

## 6. Hata Kodları

Uygulamanız şu SQLSTATE kodlarını özel olarak ele almalıdır:

| Kod | Anlamı | Aksiyon |
|:----|:-------|:--------|
| **40001** | `serialization_failure` | Transaction'ı baştan başlat (Retry). |
| **40P01** | `deadlock_detected` | Transaction'ı baştan başlat. |
| **57014** | `query_canceled` | Timeout yedin. Sorgunu optimize et. |
| **23505** | `unique_violation` | Bu veri zaten var. Kullanıcıya bildir. |
| **08*** | `connection_exception` | Bağlantı koptu. Pool'u yenile. |
