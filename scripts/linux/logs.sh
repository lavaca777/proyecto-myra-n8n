#!/usr/bin/env bash
# =====================================================================
# Logs en vivo. Por defecto n8n; puedes pasar postgres u otro servicio.
# Uso: ./scripts/linux/logs.sh [servicio]
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker

SERVICE="${1:-n8n}"
docker compose logs -f --tail=100 "$SERVICE"
