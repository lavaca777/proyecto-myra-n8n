#!/usr/bin/env bash
# =====================================================================
# Preparacion inicial del servidor Linux.
#   - Verifica Docker / Compose
#   - Crea .env si no existe
#   - Crea el volumen de PostgreSQL
#   - Crea y ajusta permisos de n8n/data
#   - Valida la URL publica
#
# Uso: ./scripts/linux/setup.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker

# 1. .env
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    if [ -f "$PROJECT_ROOT/.env.production.example" ]; then
        cp "$PROJECT_ROOT/.env.production.example" "$PROJECT_ROOT/.env"
        source_name=".env.production.example"
    else
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        source_name=".env.example"
    fi
    chmod 600 "$PROJECT_ROOT/.env"
    warn "Se creo .env a partir de $source_name."
    warn "Edita DB_PASSWORD, N8N_ENCRYPTION_KEY y WEBHOOK_URL antes de continuar:"
    warn "  nano $PROJECT_ROOT/.env"
    exit 0
fi
chmod 600 "$PROJECT_ROOT/.env"

# 2. Volumen y carpetas
ensure_volume
mkdir -p "$PROJECT_ROOT/n8n/data" "$PROJECT_ROOT/n8n/workflows" "$PROJECT_ROOT/db/backups"

# 3. Permisos para el usuario node de la imagen n8n (UID 1000)
if [ "$(id -u)" -eq 0 ]; then
    chown -R 1000:1000 "$PROJECT_ROOT/n8n/data" "$PROJECT_ROOT/n8n/workflows"
    log "Permisos de n8n/data y n8n/workflows ajustados a 1000:1000."
else
    owner="$(stat -c '%u' "$PROJECT_ROOT/n8n/data" 2>/dev/null || echo '?')"
    if [ "$owner" != "1000" ]; then
        warn "n8n/data pertenece a UID $owner. Si n8n no puede escribir, ejecuta:"
        warn "  sudo chown -R 1000:1000 $PROJECT_ROOT/n8n/data $PROJECT_ROOT/n8n/workflows"
    fi
fi

# 4. SELinux (RHEL / CentOS / Rocky)
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    warn "SELinux esta en Enforcing. Si los contenedores no leen los bind mounts,"
    warn "agrega ':z' a los volumes de docker-compose.yml o ejecuta:"
    warn "  sudo setsebool -P container_manage_cgroup true"
fi

# 5. Validar URL publica
load_env
case "${WEBHOOK_URL:-}" in
    https://*) ;;
    *)
        warn "WEBHOOK_URL no empieza con https://. Telegram exige HTTPS."
        ;;
esac
case "${WEBHOOK_URL:-}" in
    *localhost*|*127.0.0.1*|*trycloudflare.com*)
        warn "WEBHOOK_URL parece de desarrollo: $WEBHOOK_URL"
        warn "En el servidor debe ser un dominio fijo, por ejemplo https://myra.ucn.cl/"
        ;;
esac

if [ "${N8N_ENCRYPTION_KEY:-}" = "cambia_esta_clave_por_una_aleatoria" ]; then
    warn "N8N_ENCRYPTION_KEY sigue con el valor de ejemplo. Cambiala antes de arrancar."
fi

log "Preparacion lista."
log "Revisa .env y luego ejecuta: ./scripts/linux/start.sh"
