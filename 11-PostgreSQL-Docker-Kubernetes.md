# 11-PostgreSQL-Docker-Kubernetes

PostgreSQL'i konteyner (Container) içinde çalıştırmak artık "State of the Art" kabul ediliyor. Ancak veritabanı "Stateful" (Durumlu) bir uygulamadır, web sunucusu gibi "Stateless" değildir. Yanlış yapılandırma veri kaybına yol açar.

---

## 1. Docker Best Practices

Basit bir `docker run postgres` komutu **Production için yeterli değildir**.

### Dockerfile vs Resmi İmaj

Genellikle kendi imajınızı oluşturmak yerine resmi `postgres:16-alpine` veya `postgres:16-bookworm` kullanın. Sadece özel eklenti (Extension) gerekiyorsa Dockerfile yazın.

### Persistence (Kalıcılık)

Konteyner ölürse veri de ölür. Veriyi kalıcı yapmak için **Volume** kullanmak zorundasınız.

```bash
docker run -d \
  --name pg-prod \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -v pgdata_vol:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:16
```

### Konfigürasyon Yönetimi

`postgresql.conf` dosyasını konteyner içine mount ederek yönetmek zordur. Bunun yerine `command` parametresi ile ayarları ezebilirsiniz:

```bash
docker run ... postgres:16 \
  -c shared_buffers=1GB \
  -c max_connections=200 \
  -c work_mem=16MB
```

---

## 2. Kubernetes: The Cloud Native Way

Kubernetes üzerinde PostgreSQL çalıştırmak için "Helm Chart" (Bitnami gibi) kullanmak kolaydır ancak **Day-2 Operations** (Yedekleme, Failover, Upgrade) zordur.
Bu yüzden **Kubernetes Operator** kullanmak endüstri standardıdır.

### CloudNativePG (CNPG) Operator

Şu an dünyadaki en gelişmiş ve önerilen PostgreSQL operatörüdür (EnterpriseDB tarafından desteklenir).

- **Özellikleri:**
  - Otomatik Failover (Patroni'ye gerek kalmaz, kendisi yönetir).
  - S3/MinIO üzerine otomatik WAL arşivleme ve Base Backup.
  - "Point-in-Time Recovery" (PITR) işlemini tek satır Yaml değişikliği ile yapar.
  - Rolling Updates (Kesintisiz sürüm yükseltme).

### Örnek Cluster YAML (cluster.yaml)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: mk-postgres-cluster
spec:
  instances: 3 # 1 Primary, 2 Replica (HA)
  
  # Depolama (PVC)
  storage:
    size: 10Gi
  
  # Yedekleme (S3)
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/pg-backups/
      endpointURL: https://s3.amazonaws.com
      s3Credentials:
        accessKeyId:
          name: aws-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-creds
          key: SECRET_ACCESS_KEY
```

### Kurulum

> [!NOTE]
> Aşağıdaki komut sürüm 1.22.1 içindir. Kurulum yapmadan önce [Releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) sayfasından en güncel sürümü kontrol edin.

```bash
# 1. Operatörü kur
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.1.yaml

# 2. Cluster'ı oluştur
kubectl apply -f cluster.yaml

# 3. Durumu izle
kubectl get cluster
```

---

## 3. StatefulSet vs Operator

- **StatefulSet (Helm):** Size bir PostgreSQL verir ama yönetimi size bırakır. Yedekleme scriptlerini siz yazarsınız. Failover manueldir.
- **Operator (CNPG/Zalando):** Size "Yönetilen PostgreSQL Hizmeti" (RDS gibi) verir. Yedekleme, izleme, failover operatörün sorumluluğundadır.
- **Tavsiye:** Production ortamında kesinlikle **Operator** (özellikle CNPG) kullanın.
