# Fiziksel Küme (Cluster) Mimarisi ve Dosya Yerleşim Rehberi

PostgreSQL'de bir **Veritabanı Kümesi (Database Cluster)**, tek bir çalışan PostgreSQL sunucusu (`postmaster`) tarafından yönetilen veritabanlarının fiziksel ve mantıksal bütünüdür. Birçok veritabanı yöneticisi için diskteki veri dizini (`$PGDATA`) karmaşık bir dosya yığını gibi görünse de, PostgreSQL son derece katı, düzenli ve matematiksel bir dosya yerleşim hiyerarşisine sahiptir.

Bu rehberde; `$PGDATA` dizininin anatomisini, OID ve `relfilenode` ilişkisini, bir tablonun diskteki fiziksel dosyasını bulma yöntemlerini ve 1 GB'lık segment parçalanma mimarisini inceleyeceğiz.

---

## 1. `$PGDATA` Kök Dizininin Anatomisi

Veritabanı kümesinin disk üzerindeki kök dizinine **Base Directory** (`$PGDATA`) denir.

```
$PGDATA/
  ├── PG_VERSION               ◄── Majör Sürüm Numarası (Örn: '16')
  ├── postgresql.conf          ◄── Ana Yapılandırma Dosyası
  ├── postgresql.auto.conf     ◄── ALTER SYSTEM Komutlarıyla Yazılan Dinamik Ayarlar
  ├── pg_hba.conf              ◄── İstemci Kimlik Doğrulama Kuralları
  ├── pg_ident.conf            ◄── İşletim Sistemi ve DB Kullanıcı Eşleme Haritası
  ├── postmaster.pid           ◄── Aktif Süreç ID'si ve Kilit Dosyası
  │
  ├── base/                    ◄── Kullanıcı Veritabanlarının Bulunduğu Dizin (DB OID'leri)
  ├── global/                  ◄── Küme Geneli Ortak Tablolar (pg_database, pg_authid, pg_control)
  ├── pg_wal/                  ◄── Write-Ahead Log (WAL) 16 MB Segment Dosyaları
  ├── pg_tblspc/               ◄── Harici Tablespace Sembolik Bağları (Symlinks)
  ├── pg_xact/                 ◄── İşlem Durum Kayıtları (Commit/Abort Bayrakları)
  ├── pg_multixact/            ◄── Paylaşımlı Satır Kilitleri Durum Verileri
  ├── pg_logical/              ◄── Mantıksal Kod Çözme (Logical Decoding) Durumları
  ├── pg_replslot/             ◄── Replikasyon Yuvası Verileri
  ├── pg_stat/                 ◄── İstatistik Alt Sistemi Verileri
  └── pg_stat_tmp/             ◄── Anlık İstatistiklerin Tutulduğu Geçici Alan
```

---

## 2. Mantıksal Nesnelerden Fiziksel Dosyalara: OID vs relfilenode

PostgreSQL her veritabanı nesnesini (tablo, görünüm, indeks, sekans) sistem kataloglarında **Object Identifier (OID)** ile takip eder. Ancak bir tablonun diskteki dosya adı her zaman OID'si ile aynı değildir; dosya adını belirleyen değer **`relfilenode`**'dur.

```
┌─────────────────────────────────┐
│     Mantıksal Tablo Adı         │  Örn: 'musteriler'
└────────────────┬────────────────┘
                 │ pg_class kataloğu
┌────────────────▼────────────────┐
│     Tablo OID: 24580            │  Sabit Kimlik
│  relfilenode: 24580             │  Fiziksel Dosya Adı
└────────────────┬────────────────┘
                 │ TRUNCATE veya VACUUM FULL
┌────────────────▼────────────────┐
│     Tablo OID: 24580 (Aynı)     │
│  relfilenode: 31205 (Değişti!)  │  Diskte Yeni Dosya Oluştu
└─────────────────────────────────┘
```

> [!IMPORTANT]
> Bir tabloda `TRUNCATE`, `VACUUM FULL` veya `CLUSTER` komutu çalıştırıldığında PostgreSQL tabloyu diskte sıfırdan yeni bir dosyaya yazar. Bu işlem sırasında tablonun **OID'si sabit kalır**, ancak diskteki dosyasını temsil eden **`relfilenode` değişir**.

---

## 3. Bir Tablonun Disk Dosyasını Bulma

Bir tablonun disk üzerinde hangi veritabanı klasöründe ve hangi dosya adıyla saklandığını öğrenmek için yerleşik `pg_relation_filepath()` fonksiyonu kullanılır:

```sql
-- Tablonun göreceli dosya yolunu öğrenme:
SELECT pg_relation_filepath('musteriler');
-- Çıktı: base/16384/24580

-- Detaylı OID ve relfilenode analizi:
SELECT 
    c.relname AS tablo_adi,
    c.oid AS tablo_oid,
    c.relfilenode AS dosya_adi,
    d.datname AS veritabani_adi,
    d.oid AS veritabani_oid
FROM pg_class c
JOIN pg_database d ON d.datname = current_database()
WHERE c.relname = 'musteriler';
```

Diskteki fiziksel konum:
```bash
ls -lh /var/lib/pgsql/16/data/base/16384/24580
```

---

## 4. 1 GB Segment Bölümlendirmesi ve Yardımcı Dosyalar

PostgreSQL, işletim sistemlerinin dosya boyutu sınırlamalarına ve dosya sistemi taşmalarına takılmamak için herhangi bir tablonun veya indeksin fiziksel dosyasını varsayılan olarak **1 GB (1.073.741.824 bayt)** boyutunda segmentlere böler.

Eğer `musteriler` tablosu 3.5 GB büyüklüğe ulaşırsa, diskte şu dosyalar oluşur:

```
base/16384/24580          ◄── 0 - 1 GB Arasındaki Bloklar
base/16384/24580.1        ◄── 1 - 2 GB Arasındaki Bloklar
base/16384/24580.2        ◄── 2 - 3 GB Arasındaki Bloklar
base/16384/24580.3        ◄── Kalan Son Parça (~500 MB)
base/16384/24580_fsm      ◄── Free Space Map (Boş Alan Haritası)
base/16384/24580_vm       ◄── Visibility Map (Görünürlük Haritası)
```

### 4.1. Boş Alan Haritası (`_fsm`)
Her tablo dosyasının yanında bir `<filenode>_fsm` dosyası bulunur. Yeni bir satır (`INSERT`) ekleneceğinde PostgreSQL diskteki tüm 8KB'lık sayfaları taramak yerine `_fsm` dosyasını okuyarak yeterli boş alana sahip sayfayı anında bulur.

### 4.2. Görünürlük Haritası (`_vm`)
`<filenode>_vm` dosyası, her bloktaki satırların tüm aktif oturumlar için görünür (`all-visible`) veya dondurulmuş (`all-frozen`) olup olmadığını iki bitlik bayraklarla tutar. Bu sayede:
1. `VACUUM` temizlenmiş blokları atlayarak disk I/O yapmaz.
2. `Index-Only Scan` sorguları tablo bloklarına hiç gitmeden doğrudan indeksten yanıt döner.

---

## 5. Özel Tablolar ve `pg_filenode.map`

Tüm tabloların `relfilenode` bilgisi `pg_class` sistem kataloğunda saklanır. Ancak şu soru akla gelir: *`pg_class` tablosunun kendi dosyasını bulmak için nereye bakılır?*

Bu döngüsel bağımlılığı çözmek için PostgreSQL, çekirdek sistem kataloglarının (`pg_database`, `pg_class`, `pg_proc` vb.) dosya numaralarını diskte ikili formatta saklanan **`pg_filenode.map`** dosyasında tutar:
- Küme geneli kataloglar için: `$PGDATA/global/pg_filenode.map`
- Veritabanı yerel katalogları için: `$PGDATA/base/<db_oid>/pg_filenode.map`

Bu dosya PostgreSQL motorunun ilk açılışta veritabanı belleğini ayağa kaldırmasını sağlayan en kritik bootstrap bileşenidir.
