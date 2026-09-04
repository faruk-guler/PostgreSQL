# PostgreSQL Konteynerleştirme ve Kubernetes (CloudNativePG)

> **Bölüm Kapsamı:** Docker Best Practices, Kubernetes Operatörleri ve CloudNativePG (CNPG) Prodüksiyon Mimarisi

---

## 1. Docker Ortamında PostgreSQL (Best Practices)

PostgreSQL'i Docker üzerinde ayağa kaldırmak geliştirme ortamları için çok kolaydır, ancak verinin kalıcılığı (persistence) ve performansı için birkaç kurala uymak gerekir.

### Geliştirici (Dev) Ortamı İçin `docker-compose.yml`

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:16-alpine
    container_name: dev_postgres
    environment:
      POSTGRES_USER: devuser
      POSTGRES_PASSWORD: devpassword
      POSTGRES_DB: appdb
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      # Başlangıç SQL scriptlerini yüklemek için:
      - ./init-scripts:/docker-entrypoint-initdb.d
    # Performans için shm_size (Shared Memory) artırılmalıdır!
    shm_size: 1g
    restart: unless-stopped

volumes:
  pgdata:
```

> [!WARNING]
> `shm_size` (Shared Memory) Docker'da varsayılan olarak `64MB` gelir. PostgreSQL'in karmaşık sorgularda (özellikle paralel sorgular veya büyük sort işlemleri) yetersiz bellek hatası vermemesi için bu değer mutlaka artırılmalıdır.

---

## 2. Kubernetes: Cloud Native Veritabanı Yaklaşımı

Kubernetes üzerinde veritabanı çalıştırmak eskiden "anti-pattern" olarak görülürdü. Ancak günümüzde **Operatör Pattern** sayesinde PostgreSQL, Kubernetes üzerinde kendi kendini yönetebilen (self-healing) bir mimariye kavuştu.

Piyasadaki popüler operatörler:
- **Zalando Postgres Operator**
- **CrunchyData PGO**
- **CloudNativePG (CNPG)** (EnterpriseDB - Tavsiye Edilen)

---

## 3. CloudNativePG (CNPG) Prodüksiyon Mimarisi

CloudNativePG, Kubernetes'in felsefesine en uygun, standart Kubernetes API'lerini kullanarak (CRD) çalışan modern bir operatördür.

### Özellikleri:
- Otomatik Failover (Bir Pod çökerse diğeri Primary olur).
- Entegre **PgBouncer** (Bağlantı Havuzu).
- Entegre **Barman** ile S3 (AWS/MinIO) üzerine Point-In-Time-Recovery (PITR) yedekleme.
- Otomatik TLS Sertifika yönetimi.

### Prodüksiyon Seviyesi CNPG `Cluster` Manifestosu

Gerçek dünyada bir Kubernetes ortamına kurulacak tam teşekküllü bir PostgreSQL YAML örneği:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: prod-postgres-cluster
  namespace: database
spec:
  instances: 3 # 1 Primary, 2 Replica (Yüksek Erişilebilirlik)
  
  # Veritabanı İmajı
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  
  # Yüksek Erişilebilirlik ve Anti-Affinity (Pod'ları farklı Node'lara dağıt)
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

  # Veri Depolama (Persistent Volume Claim)
  storage:
    size: 500Gi
    storageClass: fast-nvme-storage

  # PostgreSQL Konfigürasyon Optimizasyonu
  postgresql:
    parameters:
      shared_buffers: "4GB"
      max_connections: "500"
      work_mem: "32MB"
      maintenance_work_mem: "1GB"

  # Bootstrap (İlk Kurulum ve Secret Yönetimi)
  bootstrap:
    initdb:
      database: app_db
      owner: app_user
      secret:
        name: app-db-credentials # Şifrelerin tutulduğu Kubernetes Secret

  # Barman ile S3 Üzerine Yedekleme (PITR)
  backup:
    barmanObjectStore:
      destinationPath: "s3://my-postgres-backups/"
      endpointURL: "https://s3.eu-central-1.amazonaws.com"
      s3Credentials:
        accessKeyId:
          name: aws-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-creds
          key: SECRET_ACCESS_KEY
      # WAL Dosyalarının sıkıştırılıp gönderilmesi
      wal:
        compression: gzip
    retentionPolicy: "30d" # Yedekleri 30 gün sakla
```

### PgBouncer Entegrasyonu (Connection Pooling)

CNPG ile PgBouncer kurmak, ayrı bir `Pooler` kaynağı tanımlamak kadar basittir:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: prod-postgres-pooler
  namespace: database
spec:
  cluster:
    name: prod-postgres-cluster # Yukarıdaki Cluster ismi
  instances: 2 # PgBouncer replika sayısı
  type: rw # Read-Write yönlendirmesi
  pgbouncer:
    poolMode: transaction # En verimli mod
    parameters:
      max_client_conn: "5000"
      default_pool_size: "100"
```

## Özet

- Docker Compose kullanırken `shm_size` ve `volumes` tanımlarını unutmayın.
- Kubernetes üzerinde çıplak `StatefulSet` yazmak yerine **mutlaka** CNPG veya CrunchyData gibi bir **Operatör** kullanın.
- Yedeklemeleri pod içine değil, S3 gibi Object Storage birimlerine (`barmanObjectStore`) yönlendirin.
