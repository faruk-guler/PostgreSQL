# PostgreSQL ve İlişkisel Veritabanı Terimleri Sözlüğü

Bu sözlük; Türkiye Bilişim Derneği (TBD) Bilişim Terimleri Standartları, PostgreSQL Resmi Kılavuzu ve kurumsal DBA literatürü esas alınarak hazırlanmış, Türkçe ve İngilizce karşılıkları ile teknik açıklamaları içeren kapsamlı bir başvuru kılavuzudur.

---

## Terimler Tablosu

| İngilizce Terim | Türkçe Karşılığı | Teknik Tanım ve Açıklama |
| :--- | :--- | :--- |
| **Archiving** | Arşivleme / Depolama | Dolan WAL (Write-Ahead Log) dosyalarının güvenli bir ikincil depolama alanına taşınması işlemi. |
| **Atomicity** | Bütünlük / Bölünemezlik | ACID prensibinin ilki; bir hareket (transaction) içindeki işlemlerin ya hep birlikte gerçekleşmesi ya da hiçbirinin gerçekleşmemesi kuralı. |
| **Autovacuum** | Otomatik Temizlik / Vakumlama | Ölü satırları (dead tuples) temizleyen ve tablo istatistiklerini (`ANALYZE`) güncelleyen arka plan işçisi. |
| **Backend Process** | Arka Uç Süreci | PostgreSQL sunucusuna bağlanan her bir istemci oturumu için `postmaster` tarafından çatallanan (fork) işletim sistemi süreci. |
| **Background Writer** | Arka Plan Yazarı | Değiştirilmiş (kirli) paylaşımlı bellek sayfalarını Checkpoint öncesinde düzenli olarak diske yazan sistem süreci. |
| **Bitmap Scan** | Biteşlem Taraması | İndeksten dönen blok numaralarını bellekte bir bit haritasında birleştirip sıralı olarak diskten okuyan hibrit tarama yöntemi. |
| **Buffer Cache** | Arabellek Önbelleği | Disk bloklarının hızlı erişim amacıyla RAM üzerinde tutulduğu paylaşımlı bellek alanı (`shared_buffers`). |
| **Cascading Standby** | Basamaklı Yedekleme | Bir Standby sunucunun doğrudan Primary yerine başka bir Standby sunucudan WAL replike etmesi mimarisi. |
| **Checkpoint** | Kontrol Noktası | Bellekteki tüm kirli verilerin diske güvenle yazıldığı ve WAL dosyalarının bu noktaya kadar temizlenebilir hale geldiği senkronizasyon anı. |
| **Collation** | Sıralama Kuralı (Harmanlama) | Metinlerin dile özgü harf sırasına, büyük/küçük harf kurallarına ve aksan duyarlılığına göre dizilmesini belirleyen kurallar bütünü. |
| **Commit** | İşlemek / Kalıcı Kılmak | Bir transaction içinde yapılan tüm DDL/DML değişikliklerinin diske (WAL) yazılarak kalıcı ve görünür hale getirilmesi. |
| **Concurrency Control** | Eşzamanlılık Kontrolü | Çok sayıda kullanıcının aynı veriye aynı anda tutarlı bir şekilde erişmesini sağlayan mekanizma (Bkz: MVCC). |
| **Consistency** | Tutarlılık | Veritabanının her transaction öncesinde ve sonrasında tüm kısıtlara (constraints, foreign keys) harfiyen uyması durumu. |
| **Constraint** | Kısıt | Tablodaki verilerin doğruluğunu denetleyen kurallar (`CHECK`, `UNIQUE`, `NOT NULL`, `FOREIGN KEY`, `EXCLUDE`). |
| **Deadlock** | Karşılıklı Kilitlenme | İki veya daha fazla transaction'ın birbirlerinin kilitlediği kaynakları beklemesi sonucu oluşan sonsuz kilit döngüsü. |
| **Durability** | Dayanıklılık | Bir işlem commit edildikten sonra sistem çökse veya elektrik kesilse dahi verilerin kaybolmayacağının garanti edilmesi. |
| **Execution** | Yürütme / İcra | Ayrıştırılmış ve planlanmış bir SQL sorgu ağacının Executor motoru tarafından satır satır çalıştırılması. |
| **Failover** | Otomatik Yük Devretme | Birincil sunucu arızalandığında yedek sunuculardan birinin otomatik olarak yeni Primary seçilmesi. |
| **Fencing** | Yalıtım / İzole Etme | Çöken eski Primary sunucunun iki başlılığı (split-brain) önlemek amacıyla ağdan veya diskten izole edilmesi. |
| **Foreign Data Wrapper (FDW)** | Yabancı Veri Sarmalayıcısı | PostgreSQL dışındaki veritabanları (MySQL, Oracle, Mongo) veya dosyalara SQL tablosu gibi erişim sağlayan SQL/MED sürücüsü. |
| **Free Space Map (FSM)** | Boş Alan Haritası | Tablo ve indeks sayfalarındaki boş bayt alanlarını takip eden ikili dosya (`<filenode>_fsm`). |
| **Heap** | Yığın / Tablo Gövdesi | Tablo satırlarının (tuples) herhangi bir sıralama olmaksızın bloklar halinde saklandığı fiziksel dosya yapısı. |
| **Hot Standby** | Sıcak Yedek | Replikasyon akışı alırken aynı anda istemcilerin salt okunur (SELECT) sorgular çalıştırmasına izin veren standby modu. |
| **Isolation** | Bağımsızlık / Yalıtım | Eşzamanlı çalışan hareketlerin birbirlerinin ara durumlarını görmesini engelleyen seviyeler (`READ COMMITTED`, `SERIALIZABLE`). |
| **Lock** | Kilit | Birden fazla işlemin aynı satırı veya tabloyu aynı anda değiştirmesini engelleyen koruma mekanizması. |
| **Logical Decoding** | Mantıksal Kod Çözme | WAL içerisindeki ikili motor kayıtlarını SQL seviyesinde INSERT/UPDATE/DELETE akışına dönüştürme işlemi. |
| **Maintenance Work Mem** | Bakım Belleği | `VACUUM`, `CREATE INDEX`, `ALTER TABLE` gibi ağır bakım operasyonlarının kullanabileceği maksimum RAM sınırı. |
| **Materialized View** | Somutlaştırılmış Görünüm | Sorgu sonucunun sanal olmak yerine fiziksel bir tablo gibi diskte saklandığı ve periyodik olarak yenilendiği nesne. |
| **Multi-Version Concurrency Control (MVCC)**| Çok Sürümlü Eşzamanlılık Denetimi | Okuyucuların yazıcıları, yazıcıların okuyucuları kilitlemediği satır sürümleme mimarisi (`xmin`, `xmax`). |
| **Object Identifier (OID)** | Nesne Tanımlayıcısı | Sistem kataloglarındaki tabloları, tipleri ve fonksiyonları tekil olarak numaralandıran 32-bit tamsayı. |
| **Partitioning** | Bölümlendirme | Milyonlarca satırlık büyük bir mantıksal tablonun tarih, liste veya karma (hash) kurallarına göre fiziksel küçük alt tablolara ayrılması. |
| **Plan Tree** | Plan Ağacı | Sorgu iyileştiricinin (Planner) bir SQL ifadesini en düşük maliyetle yürütmek için ürettiği hiyerarşik işlem adımları. |
| **Point-in-Time Recovery (PITR)** | Zamanda Noktaya Dönüş | Temel bir yedeğin üzerine WAL kayıtlarını işleterek veritabanını geçmişteki herhangi bir saniyeye geri döndürme yeteneği. |
| **Primary (Master)** | Birincil Sunucu | Yazma (DML/DDL) ve okuma trafiğini kabul eden ana veritabanı düğümü. |
| **Publication** | Yayın | Mantıksal replikasyonda belirli tabloların veya satırların abonelere sunulmasını sağlayan kaynak nesne. |
| **Quorum** | Karar Çoğunluğu | Dağıtık bir kümede lider seçimi veya replikasyon onayı için gereken minimum anlaşma sayısı (Örn: $N/2 + 1$). |
| **Relation** | İlişki | PostgreSQL'de tablo, indeks, sequence, view ve composite typeların sistem kataloğundaki genel adı (`pg_class`). |
| **Replication Slot** | Replikasyon Yuvası | Standby sunucu onaylayana kadar Primary'nin ilgili WAL segmentlerini silmesini engelleyen koruma yuvası. |
| **Sequential Scan** | Sıralı Tarama | Bir tablonun tüm bloklarının diskten baştan sona sırayla okunması işlemi (Full Table Scan). |
| **Shared Buffers** | Paylaşımlı Bellek | PostgreSQL'in disk bloklarını önbelleğe almak için kullandığı ve tüm alt süreçlerin eriştiği ana RAM havuzu. |
| **Split-Brain** | Bölünmüş Beyin | Ağ kopması durumunda kümedeki iki farklı sunucunun aynı anda kendini Primary ilan etmesi ve veri tutarsızlığı faciası. |
| **Standby (Replica)** | Yedek Sunucu | Primary sunucudan gelen WAL kayıtlarını işleyerek güncel kalan yedek sunucu. |
| **Subscription** | Abonelik | Mantıksal replikasyonda uzaktaki bir yayını dinleyerek verileri yerel tablolara aktaran alıcı nesne. |
| **Switchover** | Planlı Geçiş | Primary ve Standby sunucuların planlı bakım amacıyla sıfır veri kaybıyla yer değiştirmesi operasyonu. |
| **Tablespace** | Tablo Alanı | Veritabanı nesnelerinin dosya sisteminde farklı disk veya dizinlerde saklanmasına olanak tanıyan depolama konumu. |
| **TOAST** | Aşırı Büyük Nitelik Saklama Tekniği | 2 KB'tan büyük veri satırlarını sıkıştırarak ve 2 KB'lık parçalara bölerek ayrı bir alanda saklayan mekanizma. |
| **Transaction** | Hareket / İşlem | Veritabanında bir bütün olarak yürütülen ve ACID ilkelerine tabi olan SQL komutları grubu (`BEGIN ... COMMIT`). |
| **Trigger** | Tetikleyici | Bir tabloda INSERT, UPDATE veya DELETE işlemi gerçekleştiğinde otomatik olarak çalışan PL/pgSQL fonksiyonu. |
| **Tuple** | Satır / Kayıt | Bir tablodaki fiziksel veri satırı (MVCC gereği aynı mantıksal satırın birden fazla tuple sürümü bulunabilir). |
| **Visibility Map (VM)** | Görünürlük Haritası | Bir bloktaki tüm tuple'ların tüm transaction'lar için görünür olduğunu (`all-visible`) işaretleyerek Index-Only Scan'i mümkün kılan dosya. |
| **WAL (Write-Ahead Logging)** | Önceden Yazmalı Günlük | Veri dosyalarında herhangi bir değişiklik yapılmadan önce, değişikliğin diske sıralı olarak kaydedildiği işlem günlüğü. |
| **Witness Node** | Tanık Düğüm | Veri saklamayan, yalnızca küme bölünmelerinde çoğunluk oyu vermek için çalışan hafif sunucu. |
| **Work Mem** | Çalışma Belleği | `ORDER BY`, `DISTINCT`, `Hash Join` gibi sıralama ve karma işlemlerinde her sorgu işlemi için ayrılan RAM limiti. |
| **Wraparound** | Sayacın Başa Dönmesi | 32-bit transaction ID (XID) sayacının 2 milyar sınırı aşarak başa dönmesi ve eski verilerin görünmez hale gelmesi riski. |
