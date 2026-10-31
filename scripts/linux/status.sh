#!/usr/bin/env bash
# =====================================================================
# Estado rapido del stack: contenedores, salud, webhook y migraciones.
# Uso: ./scripts/linux/status.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker
require_env
load_env

echo "=== Contenedores ==="
docker compose ps
echo

echo "=== Webhook configurado ==="
docker inspect myra-n8n --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^N8N_WEBHOOK_URL=' || echo "(n8n no esta corriendo)"
echo

echo "=== n8n local ==="
if curl -fsS -m 5 -o /dev/null http://127.0.0.1:5678/; then
    echo "OK: http://127.0.0.1:5678/ responde"
else
    echo "No responde en http://127.0.0.1:5678/"
fi
echo

echo "=== Migraciones ==="
if container_running myra-postgres; then
    docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT filename, applied_at FROM schema_migrations ORDER BY filename;" 2>/dev/null \
        || echo "(sin tabla schema_migrations)"
else
    echo "(postgres no esta corriendo)"
fi
