#!/usr/bin/env bash
# =====================================================================
# Restaura un pg_dump sobre la base de datos del servidor.
# DESTRUCTIVO: reemplaza la base actual. Pide confirmacion.
#
# Uso: ./scripts/linux/restore-db.sh db/backups/myra_AAAAAMMDD_HHMMSS.dump
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker
require_env
load_env

DUMP="${1:-}"
[ -n "$DUMP" ] && [ -f "$DUMP" ] || die "Uso: $0 ruta/al/myra_YYYYMMDD_HHMMSS.dump"

warn "Esto reemplaza la base '$DB_NAME' del servidor con:"
warn "  $DUMP"
read -r -p "Escribe RESTAURAR para continuar: " confirm
[ "$confirm" = "RESTAURAR" ] || die "Cancelado."

container_running myra-postgres || die "myra-postgres no esta corriendo."

log "Deteniendo n8n para evitar escrituras..."
docker compose stop n8n >/dev/null 2>&1 || true

log "Restaurando..."
docker compose cp "$DUMP" postgres:/tmp/restore.dump >/dev/null
docker compose exec -T postgres dropdb -U "$DB_USER" --if-exists --force "$DB_NAME"
docker compose exec -T postgres createdb -U "$DB_USER" "$DB_NAME"
if ! docker compose exec -T postgres pg_restore -U "$DB_USER" -d "$DB_NAME" \
    --no-owner --no-privileges /tmp/restore.dump; then
    warn "pg_restore termino con errores o advertencias. Revisa la salida."
fi
docker compose exec -T postgres rm -f /tmp/restore.dump >/dev/null

log "Levantando n8n..."
docker compose up -d n8n >/dev/null

"$SCRIPT_DIR/db-migrate.sh"
log "Restauracion completada."
