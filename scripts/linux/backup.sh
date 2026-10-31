#!/usr/bin/env bash
# =====================================================================
# Respaldo completo:
#   1. pg_dump de PostgreSQL
#   2. workflows exportados a n8n/workflows/
#   3. credenciales de n8n (cifradas con la encryption key)
#
# Uso: ./scripts/linux/backup.sh
# Retencion: 14 dias.
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker
require_env
load_env
ensure_volume

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$PROJECT_ROOT/db/backups"
mkdir -p "$BACKUP_DIR"

# --- PostgreSQL ---
if ! container_running myra-postgres; then
    log "Levantando PostgreSQL para el respaldo..."
    docker compose up -d postgres >/dev/null
    wait_postgres 30 || die "PostgreSQL no esta healthy. No se puede respaldar."
fi

DUMP_NAME="myra_${STAMP}.dump"
log "Respaldando PostgreSQL ($DUMP_NAME)..."
docker compose exec -T postgres pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc -f "/tmp/$DUMP_NAME"
docker compose cp "postgres:/tmp/$DUMP_NAME" "$BACKUP_DIR/$DUMP_NAME" >/dev/null
docker compose exec -T postgres rm -f "/tmp/$DUMP_NAME" >/dev/null
chmod 600 "$BACKUP_DIR/$DUMP_NAME"

# --- n8n ---
if container_running myra-n8n; then
    log "Exportando workflows..."
    if ! "$SCRIPT_DIR/export-workflows.sh"; then
        warn "No se pudieron exportar los workflows. Se continua con el resto del respaldo."
    fi

    CRED_NAME="credentials_${STAMP}.json"
    log "Respaldando credenciales de n8n ($CRED_NAME)..."
    if docker compose exec -T n8n n8n export:credentials --all --output="/tmp/$CRED_NAME"; then
        docker compose cp "n8n:/tmp/$CRED_NAME" "$BACKUP_DIR/$CRED_NAME" >/dev/null
        docker compose exec -T n8n rm -f "/tmp/$CRED_NAME" >/dev/null
        chmod 600 "$BACKUP_DIR/$CRED_NAME"
    else
        warn "No se pudieron exportar las credenciales de n8n."
    fi
else
    warn "n8n no esta corriendo: se omite el export de workflows y credenciales."
fi

# --- Retencion ---
find "$BACKUP_DIR" -maxdepth 1 -type f -mtime +14 -delete

log "Respaldo completado en $BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' \
    | sort -r | head -n 5
