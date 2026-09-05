#!/usr/bin/env bash
# ============================================================================
# Betik: backup-and-retention.sh
# Amaç: Günlük Sıkıştırılmış Yedekleme (pg_dump Custom Format + Globals) 
#       ve Otomatik Yaşlandırma / Rotasyon (Retention) Betiği
# Kullanım: Crontab içerisine eklenebilir.
# Örnek: 0 2 * * * /path/to/backup-and-retention.sh >> /var/log/pg_backup.log 2>&1
# ============================================================================

set -e

# ================= AYARLAR =================
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-postgres}"
DB_PORT="${DB_PORT:-5432}"
RETENTION_DAYS="${RETENTION_DAYS:-7}" # Kaç günden eski yedekler silinecek?
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_TAG="[PG_BACKUP]"

echo "${LOG_TAG} $(date '+%Y-%m-%d %H:%M:%S') - Yedekleme süreci başlatıldı."

# Yedek dizini yoksa oluştur
mkdir -p "${BACKUP_DIR}"

BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"
GLOBALS_FILE="${BACKUP_DIR}/globals_${TIMESTAMP}.sql.gz"

# 1. Global Nesnelerin Yedeği (Kullanıcılar, Roller, Şifreler, Tablespace'ler)
echo "${LOG_TAG} Global roller ve yetkiler yedekleniyor..."
pg_dumpall -U "${DB_USER}" -p "${DB_PORT}" --globals-only | gzip > "${GLOBALS_FILE}"
echo "${LOG_TAG} Globals yedeği alındı: ${GLOBALS_FILE}"

# 2. Veritabanı Mantıksal Yedeği (Custom Format -Fc)
# -Fc: En yüksek seviyede sıkıştırma sağlar, pg_restore ile paralel geri yüklenebilir!
echo "${LOG_TAG} '${DB_NAME}' veritabanı yedeği alınıyor..."
pg_dump -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -F c -b -v -f "${BACKUP_FILE}"
echo "${LOG_TAG} Veritabanı yedeği başarıyla alındı: ${BACKUP_FILE}"

# 3. Checksum (Bütünlük Doğrulama) Dosyası Üretme
echo "${LOG_TAG} SHA256 checksum üretiliyor..."
sha256sum "${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"

# 4. Eski Yedekleri Temizleme (Retention Policy)
echo "${LOG_TAG} ${RETENTION_DAYS} günden eski yedekler temizleniyor..."
find "${BACKUP_DIR}" -name "*.dump" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;
find "${BACKUP_DIR}" -name "*.sha256" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;
find "${BACKUP_DIR}" -name "globals_*.sql.gz" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;

echo "${LOG_TAG} $(date '+%Y-%m-%d %H:%M:%S') - Yedekleme ve temizlik işlemi başarıyla tamamlandı!"
