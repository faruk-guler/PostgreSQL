# Vacuum ve Veritabanı Bakımı

PostgreSQL mimarisinde `UPDATE` ve `DELETE` işlemleri sanılanın aksine satırları diskten hemen fiziksel olarak silmez. Sadece silinmiş olarak (Dead Tuple) işaretler. (Buna MVCC - Multiversion Concurrency Control mimarisi denir).

## 1. Dead Tuple ve "Table Bloat" (Tablo Şişmesi)

Eğer bir tablodan her gün 1 milyon satır siliyor veya güncelliyorsanız, o satırların diskte kapladığı yerler (Dead Tuple) geri verilmez. Bir süre sonra tablonun içinde aslında 5 milyon satır veri olmasına rağmen, diskte 50 milyon satırlık yer kaplamaya başlar. Buna **Table Bloat (Şişme)** denir.

Şişen tablolar:
1.  Diskinizi gereksiz yere doldurur.
2.  Sorgu performansını (Sequential Scan'ler uzun süreceği için) yerle bir eder.
3.  Cache (RAM) verimini düşürür.

---

## 2. VACUUM Nedir?

`VACUUM`, tablolardaki bu "ölü satırları" (Dead Tuples) tarayıp temizleyen ve diskin o kısımlarını PostgreSQL'in yeni INSERT'ler için kullanabileceği şekilde "boş" olarak işaretleyen temizlik komutudur.

### Normal VACUUM
*   Ölü satırları işaretler ve yeniden kullanılabilir hale getirir.
*   **Diskteki fiziksel boyutu (Dosya boyutunu) KÜÇÜLTMEZ.** Sadece boşalan yerlere yeni verilerin yazılmasını sağlar.
*   Tabloyu **kilitlemez** (Non-blocking). Canlı sistemde rahatça çalışır.

```sql
VACUUM urunler;
```

### VACUUM FULL
*   Tabloyu sıfırdan, ölü satırlar olmadan yepyeni bir dosyaya baştan kopyalar.
*   **Diskteki fiziksel boyutu gerçek anlamda küçültür** ve işletim sistemine boş alanı geri verir.
*   **TABLOYU EKSKLÜZİF KİLİTLER (Access Exclusive Lock).** İşlem bitene kadar tabloya SELECT bile atılamaz. Canlı sistemlerde mesai saatleri içinde kesinlikle kullanılmamalıdır.

```sql
VACUUM FULL urunler;
```

---

## 3. Autovacuum Deamon (Otomatik Temizlikçi)

PostgreSQL'in içinde `autovacuum` adında arka planda çalışan bir çöp toplayıcı (Garbage Collector) servisi vardır. Tabloların ne kadar kirlendiğini takip eder ve limitleri aşan tablolara otomatik olarak standart `VACUUM` atar.

> [!TIP]
> Eskiden DBA'ler her gece manuel Vacuum çalıştırırdı. Günümüzde `autovacuum` sistemi çok gelişmiştir. **Kesinlikle kapatılmamalıdır (autovacuum = on)**. Çok hızlı değişen, devasa tablolarda autovacuum yetişemiyorsa, manuel müdahale etmek yerine `autovacuum` ayarlarını agresifleştirmek (daha sık çalışmasını sağlamak) en doğru çözümdür.

---

## 4. ANALYZE ve İstatistikler

PostgreSQL'in Query Planner (Sorgu Planlayıcı) motorunun doğru çalışabilmesi (Index mi kullansın, Seq Scan mi yapsın kararı) için veritabanındaki verilerin dağılım istatistiklerine ihtiyacı vardır. 

`ANALYZE` komutu, tablolardan rastgele örneklem (Sample) alarak bu istatistikleri günceller.

```sql
ANALYZE urunler;
```
Genellikle temizlik işlemiyle birleştirilir:
```sql
VACUUM ANALYZE urunler;
```

Autovacuum servisi, tıpkı otomatik vacuum attığı gibi, çok değişen tablolara otomatik `ANALYZE` de atar. Ancak çok devasa bir veri yüklemesi (Bulk Insert) yaptıysanız, autovacuum'u beklemeden manuel olarak `ANALYZE` çalıştırmanız performans sorunlarını anında çözecektir.
