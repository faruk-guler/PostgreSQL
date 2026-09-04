# Gelişmiş İndeksleme: BRIN, SP-GiST ve Bloom Filtreleri

> **Bölüm Kapsamı:** B-Tree Ötesi İndeksleme Stratejileri, Zaman Serisi (IoT) Logları ve Çoklu Sütun Filtreleme

---

## 1. Standart B-Tree Neden Her Yere Yetmez?

PostgreSQL'de aksi belirtilmedikçe `CREATE INDEX` komutu bir **B-Tree** (Balanced Tree) indeksi oluşturur. B-Tree, eşitlik (`=`) ve aralık (`<`, `>`) sorgularında mükemmeldir. 

Ancak bazı durumlarda B-Tree yetersiz kalır:
1. **Devasa Tablolar:** 500 milyon satırlık bir log tablosuna B-Tree atmak RAM'i (Memory) tamamen tüketir. İndeksin kendisi veri tablosundan daha büyük hale gelebilir.
2. **Çok Boyutlu Veri:** Coğrafi koordinatlar (X,Y) veya IP aralıkları B-Tree ile verimli taranamaz.
3. **Çoklu Rastgele Sütunlar:** 10 farklı sütun içeren bir tabloda kullanıcı rastgele kombinasyonlarla arama yapıyorsa, her kombinasyon için B-Tree açmak imkansızdır.

---

## 2. BRIN (Block Range INdex)

BRIN, **Büyük Veri (Big Data)** ve **Zaman Serisi (Time-series / Log)** verileri için yaratılmış mucizevi bir indekstir.

### Nasıl Çalışır?
B-Tree her bir satırın adresini tutarken, BRIN sadece **blok (page) aralıklarının minimum ve maksimum değerlerini** tutar.
Örneğin: "Blok 1 ile Blok 10 arasındaki sayfalarda tarihler 2024-01-01 ile 2024-01-31 arasındadır."

### Avantajı Nedir?
- **Boyut:** B-Tree'den 1000 kat (evet bin kat) daha az yer kaplar!
- **Hız:** Eğer veriniz diske doğal olarak **sıralı** (örneğin `created_at` gibi hep artan) yazılıyorsa BRIN inanılmaz hızlıdır.

### BRIN Kullanım Örneği

```sql
-- 500 Milyon satırlık bir log tablosu düşünelim
CREATE TABLE server_logs (
    id BIGSERIAL PRIMARY KEY,
    log_level VARCHAR(10),
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Kötü (B-Tree): İndeks 15 GB yer kaplayabilir
CREATE INDEX idx_logs_btree ON server_logs (created_at);

-- İyi (BRIN): İndeks sadece 2-3 MB yer kaplar!
CREATE INDEX idx_logs_brin ON server_logs USING brin (created_at);
```

> [!WARNING]
> BRIN indeksleri sadece diske fiziksel olarak sıralı (correlated) yazılan verilerde işe yarar. Rastgele (Random) güncellenen veya yazılan sütunlarda (örneğin UUID'ler) BRIN **kullanılamaz**.

---

## 3. SP-GiST (Space-Partitioned GiST)

SP-GiST, veriyi birbirini örtüşmeyen alanlara bölen ağaç yapılarını destekler (Örneğin: Quad-trees, k-d trees, radix trees). 

### Ne Zaman Kullanılır?
- Telefon numaraları (Prefix aramaları).
- IP Adresleri ve Ağ aralıkları (`inet`, `cidr`).
- Hiyerarşik yapılar ve URL path'leri.

### SP-GiST Örneği

```sql
CREATE TABLE network_traffic (
    id BIGSERIAL PRIMARY KEY,
    source_ip INET,
    destination_ip INET
);

-- SP-GiST ile ağ adreslemesini indekslemek
CREATE INDEX idx_network_spgist ON network_traffic USING spgist (source_ip);

-- Bu sorgu SP-GiST ile ışık hızında çalışır:
SELECT * FROM network_traffic WHERE source_ip << '192.168.1.0/24';
```

---

## 4. Bloom Filtreleri (Bloom Index)

Bloom Filtresi, olasılıksal (probabilistic) bir veri yapısıdır. Bir verinin tabloda **kesinlikle olmadığını** kanıtlayabilir, ancak **olup olmadığını %100 doğrulayamaz** (False-positive dönebilir).

### Ne Zaman Kullanılır?
Bir tabloda 10 farklı "özellik" veya "etiket" sütunu var ve uygulamanız `WHERE feature1 = 'A' AND feature5 = 'B'` gibi rastgele kombinasyonlarda sorgu atıyorsa. Her kombinasyon için B-Tree açmak diski doldurur.

### Bloom Index Örneği

Bloom indeksleri varsayılan olarak kapalıdır, önce extension'ı açmalıyız.

```sql
-- 1. Eklentiyi aktif et
CREATE EXTENSION bloom;

-- 2. 6 farklı özellik sütunu olan bir tablo
CREATE TABLE user_profiles (
    id SERIAL PRIMARY KEY,
    is_active BOOLEAN,
    has_premium BOOLEAN,
    region VARCHAR(50),
    language VARCHAR(10),
    device_type VARCHAR(20)
);

-- 3. Tüm sütunları kapsayan TEK bir Bloom Index oluştur
CREATE INDEX idx_bloom_profiles ON user_profiles 
USING bloom (is_active, has_premium, region, language, device_type);

-- Bu sorgu Bloom filtresi sayesinde süzülerek (Heap'e gitmeden önce elenerek) hızlıca çalışır
SELECT * FROM user_profiles 
WHERE region = 'EU' AND has_premium = true;
```

---

## Özet

- Veriniz milyarlarca satır log/metrik içeriyorsa ve diske zamana göre (sıralı) yazılıyorsa: **BRIN** kullanın.
- Veriniz Ağ (IP), Telefon Numarası veya hiyerarşik yapı içeriyorsa: **SP-GiST** kullanın.
- Tablonuzda çok fazla sütun var ve kullanıcılar bu sütunların rastgele kombinasyonlarıyla arama/filtreleme yapıyorsa: **Bloom** kullanın.
- Sadece standart eşitlik veya sıralama (`ORDER BY`) lazımsa: Alışkın olduğunuz **B-Tree** kullanmaya devam edin.
