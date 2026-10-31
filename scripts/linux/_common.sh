#!/usr/bin/env bash
# =====================================================================
# Utilidades compartidas por los scripts de Linux.
# Se importa con:  source "$(dirname "$0")/_common.sh"
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

log()  { printf '\033[1;36m[myra]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[myra]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[myra]\033[0m %s\n' "$*" >&2; exit 1; }

require_docker() {
    command -v docker >/dev/null 2>&1 || die "Docker no esta instalado."
    docker compose version >/dev/null 2>&1 || die "Docker Compose v2 no esta disponible."
    docker info >/dev/null 2>&1 || die "El daemon de Docker no responde. Inicia Docker o revisa permisos."
}

require_env() {
    [ -f "$PROJECT_ROOT/.env" ] || die "Falta .env. Copia .env.example a .env y editalo."
}

load_env() {
    # shellcheck disable=SC1091
    set -a
    . "$PROJECT_ROOT/.env"
    set +a
}

ensure_volume() {
    docker volume inspect myra_db_pg_data >/dev/null 2>&1 \
        || docker volume create myra_db_pg_data >/dev/null
}

wait_postgres() {
    local tries="${1:-30}"
    local i status
    for ((i = 1; i <= tries; i++)); do
        status="$(docker inspect --format '{{.State.Health.Status}}' myra-postgres 2>/dev/null || true)"
        if [ "$status" = "healthy" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}
