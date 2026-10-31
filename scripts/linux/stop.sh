#!/usr/bin/env bash
# =====================================================================
# Detiene los contenedores SIN borrar datos.
# Uso: ./scripts/linux/stop.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker

log "Deteniendo PostgreSQL + n8n..."
docker compose down

log "Listo. Los datos se conservan en n8n/data y en el volumen myra_db_pg_data."
