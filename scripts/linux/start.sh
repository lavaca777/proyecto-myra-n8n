#!/usr/bin/env bash
# =====================================================================
# Levanta PostgreSQL + n8n y aplica migraciones pendientes.
# En el servidor, Docker con restart: unless-stopped ya los levanta al
# bootear; este script sirve para el primer arranque o despues de un pull.
#
# Uso: ./scripts/linux/start.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker
require_env
load_env
ensure_volume

log "Levantando PostgreSQL + n8n..."
docker compose up -d

if wait_postgres 30; then
    "$SCRIPT_DIR/db-migrate.sh"
else
    warn "PostgreSQL no reporto healthy en 30 s."
    warn "Revisa: docker compose logs postgres"
fi

echo
docker compose ps
echo
log "n8n local: http://127.0.0.1:5678"
log "Webhook configurado: ${WEBHOOK_URL:-'(no definido)'}"
