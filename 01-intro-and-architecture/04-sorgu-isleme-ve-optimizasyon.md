# Sorgu İşleme (Query Processing) ve Optimizasyon Mimarisi

Sorgu işleme (Query Processing), PostgreSQL'in en karmaşık ve yetenekli alt sistemlerinden biridir. PostgreSQL, SQL standartlarının gerektirdiği gelişmiş özellikleri desteklerken aynı zamanda sorguları mümkün olan en verimli şekilde işler.

İstemci tarafından gönderilen SQL sorguları, **Backend Process** (Arka Uç Süreci) içerisinde beş aşamalı bir yaşam döngüsünden geçerek çalıştırılır: **Parser**, **Analyzer**, **Rewriter**, **Planner** ve **Executor**.

---

## 1. Parser (Ayrıştırıcı)

PostgreSQL sunucusu istemciden düz bir SQL metni aldığında, bunu ilk olarak Parser'a iletir. 

* **Sözdizimi Kontrolü (Syntax Check):** Parser, SQL metninin gramer kurallarına uygun olup olmadığını kontrol eder. Eğer bir yazım hatası (syntax error) varsa işlemi durdurur ve anında hata mesajı döndürür.
* **Ayrıştırma Ağacı (Parse Tree):** Sözdizimi geçerliyse, Parser metni makine tarafından okunabilir hiyerarşik bir yapı olan Ayrıştırma Ağacına (`Parse Tree`) dönüştürür.

> [!NOTE]
> Bu aşamada anlamsal bir kontrol yapılmaz. Örneğin; sorguda geçersiz bir tablo adı veya olmayan bir sütun belirtilmiş olsa dahi, sözdizimi doğru olduğu sürece Parser hata vermez. Anlamsal doğrulamalar bir sonraki aşamada (Analyzer) yapılır.

## 2. Analyzer (Analizör)

Analyzer, Parser'ın ürettiği ağacın **anlamsal analizini (semantic analysis)** yapar.

* Tabloların veritabanında gerçekten var olup olmadığını kontrol eder.
* İlgili sütunların veri tiplerini doğrular.
* Kullanıcının nesneler üzerindeki erişim izinlerini (yetkilerini) kontrol eder.
* Geçerli bir **Sorgu Ağacı (Query Tree)** oluşturur. Sorgu ağacı; sorgunun çekmek istediği kolonları (`targetList`), kullanılacak tabloları (`rtable`), birleştirme (JOIN) koşullarını (`jointree`) ve sıralama kurallarını (`sortClause`) içerir.

## 3. Rewriter (Yeniden Yazıcı)

Rewriter, Sorgu Ağacını sistem katalogunda (`pg_rules`) saklanan **kurallara (rules)** göre dönüştüren alt sistemdir.

En yaygın Rewriter kullanım senaryosu **Görünümlerdir (Views)**. Kullanıcı bir görünüme (View) sorgu attığında, Rewriter, sistem kataloğundaki kuralları kullanarak kullanıcının basit `SELECT * FROM view_adi` sorgusunu, view'ın arka planındaki asıl karmaşık tablo sorgusuyla değiştirir (expand eder).

## 4. Planner / Optimizer (Planlayıcı ve İyileştirici)

Planner, Query Processing yaşam döngüsünün kalbidir. Görevi, sorguyu çalıştırmak için mümkün olan en verimli yolu bulmaktır.

* **İstatistiklerin Kullanımı:** `pg_statistic` tablosundaki verileri (tablo büyüklükleri, sütunlardaki veri dağılımları vb.) kullanarak olası çalışma yollarının maliyetini (cost) hesaplar.
* **Erişim Yolu Seçimi:** Veriye ulaşmak için tüm tabloyu sırayla taramak (Sequential Scan) mı, yoksa bir indeks kullanmak (Index Scan / Bitmap Index Scan) mı daha ucuz, buna karar verir.
* **Join Algoritmaları:** Birden fazla tablo birleştiriliyorsa; Nested Loop Join, Hash Join veya Merge Join algoritmalarından en düşük maliyetli olanı seçer.
* En verimli yolu seçerek **Plan Ağacı (Plan Tree)** üretir. 

> [!TIP]
> PostgreSQL'in Planner alt sisteminin sizin sorgunuz için nasıl bir yol seçtiğini (ve neden yavaş çalıştığını) görmek için sorgunuzun başına `EXPLAIN` veya `EXPLAIN ANALYZE` ekleyerek Plan Ağacını inceleyebilirsiniz.

## 5. Executor (Yürütücü / İşletici)

Executor, Planner tarafından üretilen en iyi Plan Ağacını alır ve adım adım (node by node) çalıştırır.

1. **Buffer Manager ile İletişim:** Verileri doğrudan diskten okumak yerine Buffer Manager'a başvurur ve paylaşımlı bellekteki (`shared_buffers`) sayfalara erişir.
2. **Geçici Bellek Kullanımı:** Sıralama (`ORDER BY`), tekilleştirme (`DISTINCT`) ve Hash Join gibi işlemler için kendi yerel belleği olan `work_mem` alanını kullanır.
3. **Satır Döndürme:** Okuduğu verileri istemciye gönderir. Aynı veriye aynı anda başka işlemlerin (transactions) eriştiği senaryolarda izole bir görünüm sunmak için **MVCC (Multi-Version Concurrency Control)** kurallarına göre hareket eder.
