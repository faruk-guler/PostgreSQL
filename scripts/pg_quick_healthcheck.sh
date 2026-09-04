#!/usr/bin/env bash
# ============================================================================
# Betik: pg_quick_healthcheck.sh
# Amaç: Linux Terminalinden Tek Tuşla Hızlı PostgreSQL Sağlık ve Performans Raporu
# Kullanım: ./pg_quick_healthcheck.sh [veritabani_adi] [kullanici] [port]
# ============================================================================

set -e

DB_NAME="${1:-postgres}"
DB_USER="${2:-postgres}"
DB_PORT="${3:-5432}"

# Renk kodları
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}        POSTGRESQL MASTER GUIDE - HIZLI SAĞLIK VE DURUM RAPORU        ${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo -e "Tarih        : $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Hedef DB     : ${DB_NAME}"
echo -e "Kullanıcı    : ${DB_USER}"
echo -e "Port         : ${DB_PORT}"
echo ""

# 1. PostgreSQL Çalışıyor mu?
echo -e "${YELLOW}[1/6] PostgreSQL Servis Durumu ve Sürümü:${NC}"
if ! psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -t -A -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${RED}HATA: PostgreSQL sunucusuna bağlanılamadı! Lütfen servis durumunu kontrol edin.${NC}"
    exit 1
fi
PG_VER=$(psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -t -A -c "SELECT version();")
UPTIME=$(psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -t -A -c "SELECT date_trunc('second', current_timestamp - pg_postmaster_start_time());")
echo -e "${GREEN}✓ Bağlantı Başarılı!${NC}"
echo -e "Sürüm : ${PG_VER}"
echo -e "Uptime: ${UPTIME}"
echo ""

# 2. Disk Doluluk Durumu
echo -e "${YELLOW}[2/6] Veri Dizini (PGDATA) Disk Kullanımı:${NC}"
PG_DATA=$(psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -t -A -c "SHOW data_directory;")
df -h "${PG_DATA}" | awk 'NR==1 || NR==2 {print $0}'
echo ""

# 3. Bağlantı Durumu ve max_connections
echo -e "${YELLOW}[3/6] Bağlantı Havuzu ve Limit Durumu:${NC}"
psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "
SELECT 
    count(*) AS toplam_baglanti,
    current_setting('max_connections')::int AS limit,
    ROUND((count(*)::numeric / current_setting('max_connections')::int) * 100, 1) AS doluluk_yuzdesi
FROM pg_stat_activity;"
echo ""

# 4. Idle in Transaction Tehlikesi
echo -e "${YELLOW}[4/6] 1 Dakikadan Uzun 'idle in transaction' Oturumları:${NC}"
IDLE_COUNT=$(psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -t -A -c "
SELECT count(*) FROM pg_stat_activity 
WHERE state = 'idle in transaction' AND (now() - state_change) > interval '1 minute';")
if [ "${IDLE_COUNT}" -gt 0 ]; then
    echo -e "${RED}DİKKAT: ${IDLE_COUNT} adet takılı kalmış 'idle in transaction' oturumu var!${NC}"
    psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "
    SELECT pid, usename, client_addr, now() - state_change AS bekleme_suresi, substring(query, 1, 60) AS son_sorgu
    FROM pg_stat_activity WHERE state = 'idle in transaction' AND (now() - state_change) > interval '1 minute';"
else
    echo -e "${GREEN}✓ Harika! Takılı kalmış transaction bulunmuyor.${NC}"
fi
echo ""

# 5. Buffer Cache Hit Ratio
echo -e "${YELLOW}[5/6] Buffer Cache Hit Oranı (Hedef: > %99):${NC}"
psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "
SELECT 
    datname,
    ROUND((blks_hit::numeric / NULLIF(blks_hit + blks_read, 0)) * 100, 2) AS cache_hit_yuzde
FROM pg_stat_database WHERE datname = current_database();"
echo ""

# 6. Transaction ID Wraparound Riski
echo -e "${YELLOW}[6/6] Transaction ID (XID) Yaşı ve Wraparound Riski:${NC}"
psql -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "
SELECT 
    datname,
    age(datfrozenxid) AS xid_yasi,
    ROUND((age(datfrozenxid)::numeric / 2000000000) * 100, 2) AS risk_yuzdesi
FROM pg_database WHERE datname = current_database();"

echo ""
echo -e "${BLUE}======================================================================${NC}"
echo -e "${GREEN}Tarama Tamamlandı.${NC}"
