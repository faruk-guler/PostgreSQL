# PostgreSQL Terimler ve Kavramlar Sözlüğü (Glossary)

> **Bölüm Kapsamı:** PostgreSQL, Veritabanı Mimarisi ve DBA Dünyasında En Sık Karşılaşılan Terimlerin Türkçe Karşılıkları ve Teknik Tanımları

---

PostgreSQL dokümantasyonlarında, kaynak kodlarında ve kurumsal DBA pratiklerinde sıkça kullanılan İngilizce terimlerin Türkçe bilişim karşılıkları (TBD standartları gözetilerek) ve PostgreSQL mimarisindeki işlevsel tanımları aşağıda fihrist olarak listelenmiştir.

---

## 1. Mimari, Bellek ve Arka Plan Süreçleri (Core & Architecture)

| Terim (İngilizce) | Türkçe Karşılığı | PostgreSQL Bağlamında Teknik Tanımı |
| :--- | :--- | :--- |
| **Backend Process** | Arka Uç Süreci | İstemci (Client) her bağlandığında `postmaster` tarafından çatallanan (fork) ve istemcinin sorgularını yürüten Postgres iş parçacığı. |
| **Background Writer (bgwriter)** | Arka Plan Yazarı | `shared_buffers` içindeki kirli (dirty) sayfaları düzenli aralıklarla diske yazarak Checkpoint anındaki I/O yükünü hafifleten süreç. |
| **Buffer / Buffer Cache** | Tampon Bellek / Arabellek | Disk bloklarının RAM üzerinde tutulduğu bellek havuzu (`shared_buffers`). |
| **Checkpointer** | Kontrol Noktası Süreci | Belirli aralıklarla (`checkpoint_timeout`) bellekteki tüm kirli verileri kalıcı diske yazan ve WAL loglarını temizleyen arka plan süreci. |
| **Checkpoint** | Kontrol Noktası | Veritabanının disk ile bellek durumunun eşitlendiği ve sistem çökmesi durumunda toparlanmanın (crash recovery) başlayacağı güvenli nokta. |
| **Database Cluster** | Veritabanı Kümesi | Tek bir PostgreSQL sunucusu (`postmaster`) tarafından yönetilen ve tek bir dosya sistemi dizininde (`$PGDATA`) saklanan veritabanları koleksiyonu. |
| **Data Directory (`$PGDATA`)** | Veri Dizini | Tabloların, WAL loglarının, yapılandırma dosyalarının ve küme verilerinin fiziksel olarak depolandığı kök dizin. |
| **Free Space Map (FSM)** | Boş Alan Haritası | Her tablonun/indeksin yanında bulunan (`_fsm`) ve yeni eklenecek satırlar için sayfa içindeki boş yerleri hızlıca bulan harita. |
| **Heap** | Yığın (Tablo Dosyası) | Tablo satırlarının sırasız bir biçimde 8 KB'lık sayfalar halinde saklandığı ana veri dosyası. |
| **Huge Pages** | Büyük Bellek Sayfaları | Linux çekirdeğinde varsayılan 4 KB bellek sayfaları yerine 2 MB (veya 1 GB) sayfalar kullanarak TLB önbellek kaçırmalarını önleyen bellek modu. |
| **Local Memory** | Yerel Bellek | Her backend sürecine sorgu işleme için özel olarak tahsis edilen bellek alanı (`work_mem`, `temp_buffers`). |
| **MVCC (Multi-Version Concurrency Control)** | Çoklu Sürüm Eşzamanlılık Denetimi | Okuma işlemlerinin yazma işlemlerini, yazma işlemlerinin de okuma işlemlerini kilitlemesini engelleyen, satırların birden çok sürümünü tutan PostgreSQL eşzamanlılık mekanizması. |
| **Page / Block** | Sayfa / Blok | PostgreSQL'de I/O işlemlerinin temel birimi (varsayılan: 8192 bayt / 8 KB). |
| **Postmaster** | Ana Yönetici Süreç | Sunucu başlatıldığında ilk çalışan, paylaşımlı belleği ayıran, portu dinleyen ve gelen her bağlantıya yeni bir backend atayan ana süreç. |
| **Shared Memory** | Paylaşımlı Bellek | Tüm PostgreSQL süreçlerinin ortaklaşa eriştiği RAM bölgesi (`shared_buffers`, kilit tabloları, WAL tamponları). |
| **Tuple / Row** | Demet / Satır | Bir tablodaki tek bir veri kaydı. MVCC gereği bir satırın güncellenmesi yeni bir tuple üretir. |
| **Visibility Map (VM)** | Görünürlük Haritası | Bir sayfadaki tüm satırların tüm aktif transaction'lar için görünür olup olmadığını belirten bit haritası (`_vm`). Index-Only Scan için kritiktir. |
| **WAL (Write-Ahead Logging)** | Önceden Yazma Günlüğü | Veri sayfaları diske yazılmadan önce, yapılan her değişikliğin sırayla yazıldığı dayanıklılık (Durability) ve kurtarma günlüğü (`pg_wal`). |
| **Walwriter** | WAL Yazarı | Bellekteki WAL tamponlarını (`wal_buffers`) düzenli aralıklarla diske yazan arka plan süreci. |
| **Wraparound (XID Wraparound)** | İşlem Kimliği Sarımı | 32-bit transaction ID sayacının (~2 milyar işlem) sıfırlanıp eski verilerin görünmez hale gelme tehlikesi; `VACUUM FREEZE` ile önlenir. |

---

## 2. Depolama, Bakım ve Optimizasyon (Storage & Maintenance)

| Terim (İngilizce) | Türkçe Karşılığı | PostgreSQL Bağlamında Teknik Tanımı |
| :--- | :--- | :--- |
| **Autovacuum** | Otomatik Temizleme | Arka planda ölü satırları (`dead tuples`) temizleyen, FSM ve VM'i güncelleyen ve tablo istatistiklerini (`ANALYZE`) toplayan otomatik mekanizma. |
| **Bloat** | Şişkinlik | `UPDATE` ve `DELETE` işlemleri sonrası boşalan ancak işletim sistemine geri iade edilmeyen ölü satırların diskte ve indekste yarattığı gereksiz yer kaplama. |
| **Cost** | Maliyet | Sorgu planlayıcının (Planner) belirli bir sorgu planı için tahmin ettiği bağıl hesaplama ve I/O yükü birimi. |
| **Deadlock** | Kilitlenme / Karşılıklı Kilit | İki veya daha fazla transaction'ın birbirlerinin kilitlediği kaynakları beklemesi sonucu oluşan ve `deadlock_timeout` ile çözülen kilit döngüsü. |
| **Fillfactor** | Doluluk Oranı | Bir tablo veya indeks sayfasına veri eklenirken sayfanın ne kadarının doldurulacağını belirten yüzde ayarı (HOT güncellemeleri için alan bırakır). |
| **HOT (Heap-Only Tuples)** | Yalnızca Yığın Demetleri | Yapılan bir `UPDATE` işleminde indekslenen kolonlar değişmediğinde, yeni satırın aynı sayfaya yazılıp indekslerin güncellenmesine gerek bırakmayan optimizasyon. |
| **Index-Only Scan** | Yalnızca İndeks Taraması | Aranan tüm kolonların indekste bulunduğu ve VM sayesinde heap tablosuna hiç gitmeden doğrudan indeksten cevap dönen en hızlı tarama türü. |
| **Lock** | Kilit | Eşzamanlı erişimlerde veri bütünlüğünü korumak için nesneler (tablo, satır, sayfa) üzerine konulan erişim kısıtı. |
| **Partitioning** | Bölümleme | Çok büyük bir tablonun belirli anahtarlara göre (Range, List, Hash) daha küçük fiziksel tablolara (`partitions`) bölünmesi. |
| **Partition Pruning** | Bölüm Eleme | Sorgu yürütülürken `WHERE` koşuluna uymayan partition tablolarının yürütme planından tamamen çıkarılması. |
| **Sequential Scan (Seq Scan)** | Sıralı Tarama | Bir tablodaki tüm sayfaların baştan sona tek tek okunması (indeks kullanılmaması). |
| **TOAST (The Oversized-Attribute Storage Technique)** | Aşırı Boyutlu Nitelik Depolama Tekniği | 8 KB'lık sayfa boyutuna sığmayan büyük veri kolonlarının (büyük text, jsonb, bytea) otomatik sıkıştırılıp ayrı bir alanda parçalanarak saklanması. |
| **Vacuum** | Temizleme | MVCC sonucu oluşan ölü satırların bıraktığı boş alanları tekrar kullanılabilir hale getiren bakım komutu. |

---

## 3. Replikasyon ve Yüksek Erişilebilirlik (HA & Replication)

| Terim (İngilizce) | Türkçe Karşılığı | PostgreSQL Bağlamında Teknik Tanımı |
| :--- | :--- | :--- |
| **Archiving** | Arşivleme | Dolan WAL segment dosyalarının (`16 MB`) kalıcı bir harici depolama veya yedekleme alanına aktarılması (`archive_command`). |
| **Cascading Replication** | Kademeli Replikasyon | Bir Standby sunucunun, Primary yerine başka bir Standby'dan WAL verisi alarak çoğaltma yapması (ağ bant genişliği tasarrufu sağlar). |
| **DCS (Distributed Configuration Store)** | Dağıtık Yapılandırma Deposu | Patroni gibi HA çözümlerinde küme liderini belirlemek ve split-brain'i önlemek için kullanılan konsensüs sistemi (etcd, Consul, ZooKeeper). |
| **Failover** | Yük Devretme | Birincil sunucu çöktüğünde veya ulaşılamaz olduğunda, bir Standby sunucunun otomatik veya manuel olarak yeni Primary ilan edilmesi. |
| **Logical Replication** | Mantıksal Replikasyon | Veritabanı nesnelerinin ve veri değişikliklerinin WAL'dan çözümlenerek SQL düzeyinde yayıncı/abone (`Publisher/Subscriber`) modeliyle aktarılması. |
| **Node** | Düğüm / Uç | Bir veritabanı kümesinde yer alan bağımsız sunucu veya sanal makine. |
| **Primary (Master)** | Birincil Sunucu | Okuma ve yazma işlemlerini kabul eden, kümenin ana aktif veritabanı düğümü. |
| **Promote** | Yükseltme | Salt-okunur (Read-Only) moddaki bir Standby sunucunun bağımsız okuma/yazma moduna geçirilerek Primary yapılması. |
| **Publisher** | Yayıncı | Mantıksal replikasyonda verilerini dışarıya aktaran kaynak veritabanı. |
| **Receiver (`walreceiver`)** | Alıcı Süreç | Standby sunucuda çalışan ve Primary'deki `walsender` sürecinden WAL bloklarını çeken arka plan süreci. |
| **Recovery** | Kurtarma / Toparlanma | Sistem çökmesi sonrası WAL kayıtlarının okunarak veritabanının tutarlı hale getirilmesi veya PITR ile yedekten geri dönülmesi. |
| **Replication Slot** | Replikasyon Yuvası | Standby sunucu çevrimdışı olsa bile Primary sunucunun o Standby'ın ihtiyaç duyduğu WAL dosyalarını silmesini engelleyen garanti mekanizması. |
| **Sender (`walsender`)** | Gönderici Süreç | Primary sunucuda çalışan ve WAL kayıtlarını ağ üzerinden bağlı Standby düğümlere ileten süreç. |
| **Split-Brain** | Çift Başlılık Tehlikesi | Ağ kopması durumunda birden fazla düğümün kendisini aynı anda Primary ilan etmesi sonucu verilerin birbirinden kopması ve çatışması. |
| **Standby (Replica)** | Yedek Sunucu | Primary'den gelen WAL kayıtlarını sürekli uygulayarak eşitlenen ve sorgulamaya açık tutulabilen kopya sunucu. |
| **Streaming Replication** | Akış Replikasyonu | WAL kayıtlarının dosya bazında değil, üretildikleri anda bayt/blok düzeyinde Standby sunucuya akıtılması. |
| **Subscriber** | Abone | Mantıksal replikasyonda yayıncıdan gelen tablo değişikliklerini kendi üzerine uygulayan hedef veritabanı. |
| **Switchover** | Kontrollü Görev Değişimi | Planlı bakım sırasında Primary ile Standby sunucunun veri kaybı olmadan yer değiştirmesi. |

---

## 4. Güvenlik, Kimlik Doğrulama ve Ağ (Security & Networking)

| Terim (İngilizce) | Türkçe Karşılığı | PostgreSQL Bağlamında Teknik Tanımı |
| :--- | :--- | :--- |
| **Audit** | Denetim | Veritabanında kimin, ne zaman, hangi veriyi değiştirdiğini veya hangi sorguyu çalıştırdığını kayıt altına alma faaliyeti. |
| **Cipher** | Şifreleme Algoritması | Verilerin ağ üzerinden taşınırken veya diskte saklanırken gizliliğini koruyan matematiksel şifreleme standardı (AES, RSA). |
| **Host-Based Authentication (`pg_hba.conf`)** | Ana Makine Tabanlı Kimlik Doğrulama | Hangi istemci IP adresinin, hangi veritabanına, hangi kullanıcı adı ve hangi şifreleme yöntemiyle bağlanabileceğini belirleyen güvenlik yapılandırma dosyası. |
| **mTLS (Mutual TLS)** | Karşılıklı Taşıma Katmanı Güvenliği | Hem istemcinin sunucu sertifikasını doğruladığı, hem de sunucunun istemci sertifikasını (`clientcert=verify-full`) zorunlu kıldığı çift taraflı güvenli iletişim. |
| **Passphrase** | Güvenlik Parolası | Özel anahtarları (Private Key) şifrelemek için kullanılan karmaşık parola cümlesi. |
| **Private Key** | Özel Anahtar | SSL/TLS şifrelemesinde sadece sunucu veya istemcinin kendisinde bulunması gereken gizli anahtar. |
| **Requirepeer** | Eş Süreç Kimlik Zorunluluğu | Unix domain socket bağlantılarında, sokete bağlanan istemci sürecinin işletim sistemi seviyesindeki sahibini doğrulayan parametre. |
| **RLS (Row-Level Security)** | Satır Düzeyinde Güvenlik | Bir tablodaki satırların, oturumu açan kullanıcının yetkilerine göre filtrelenerek gizlenmesini sağlayan güvenlik mekanizması. |
| **SCRAM-SHA-256** | Güvenli Parola Doğrulama Protokolü | Parolanın ağ üzerinden asla ham veya md5 formatında geçmediği, tuzlanmış (salted) meydan okuma-yanıt tabanlı modern kimlik doğrulama standardı. |
| **Server Spoofing** | Sunucu Sahtekarlığı | Kötü niyetli bir sürecin gerçek veritabanı sunucusunun portunu veya soketini taklit ederek istemci şifrelerini çalmaya çalışması. |
| **Superuser** | Süper Kullanıcı | Veritabanı kümesindeki tüm güvenlik kontrollerini, izinleri ve kısıtlamaları aşabilen tam yetkili rol (`postgres`). |

---

## 5. SQL, Sorgu İşleme ve Veri Tipleri (SQL & Query Engine)

| Terim (İngilizce) | Türkçe Karşılığı | PostgreSQL Bağlamında Teknik Tanımı |
| :--- | :--- | :--- |
| **Aggregate Function** | Toplama / Özetleme Fonksiyonu | Birden çok satırı girdi olarak alıp tek bir özet değer üreten fonksiyon (`COUNT`, `SUM`, `AVG`). |
| **Cascading Delete** | Kademeli Silme | Bir üst tablodaki satır silindiğinde ona bağlı yabancı anahtar (`FOREIGN KEY`) içeren alt tablodaki satırların da otomatik silinmesi. |
| **Constraint** | Kısıt | Tablodaki verilerin belirli kurallara uymasını zorunlu kılan kural (`PRIMARY KEY`, `NOT NULL`, `CHECK`, `UNIQUE`). |
| **CTE (Common Table Expression)** | Ortak Tablo İfadesi | `WITH` cümleciğiyle tanımlanan, ana sorgu süresince geçici bir sonuç kümesi oluşturan ve özyinelemeli (recursive) olabilen SQL yapısı. |
| **Execution Plan** | Yürütme Planı | Sorgu planlayıcının bir SQL cümlesini çalıştırmak için seçtiği en düşük maliyetli adımlar kümesi (`EXPLAIN ANALYZE`). |
| **Extended Query Protocol** | Genişletilmiş Sorgu Protokolü | İstemcilerin Parse, Bind, Execute adımlarını ayrı ayrı çalıştırdığı ve SQL Injection riskini ortadan kaldıran parametreli sorgu protokolü. |
| **Parse Tree** | Ayrıştırma Ağacı | SQL metninin dilbilgisi kurallarına göre çözümlenmesiyle oluşturulan sözdizimsel ağaç yapısı. |
| **Planner / Optimizer** | Planlamacı / İyileştirici | Veritabanı istatistiklerini (`pg_statistic`) kullanarak olası yürütme yolları arasından en düşük maliyetli olanı seçen motor bileşeni. |
| **Transaction** | İşlem / Hareket | Ya hep ya hiç prensibine dayanan, ACID özelliklerini taşıyan mantıksal birim (`BEGIN ... COMMIT / ROLLBACK`). |
| **View / Materialized View** | Görünüm / Somutlaştırılmış Görünüm | Bir SQL sorgusunun sanal tablo olarak saklanması; Materialized View ise sorgu sonucunun diske fiziksel bir tablo gibi yazılarak önbelleklenmesi. |
| **Window Function** | Pencere Fonksiyonu | Satırları tek bir grupta eritmeden (`GROUP BY` yapmadan), belirli bir pencere aralığı (`OVER (PARTITION BY ...)`) üzerinden kümülatif veya analitik hesaplama yapan fonksiyon. |

---

> [!TIP]
> **Terminoloji Notu:** PostgreSQL belgelerinde `relation` kelimesi yalnızca tabloları değil; indeksleri, sequence'ları, view'ları ve TOAST tablolarını da kapsayan genel katalog terimidir.
