#!/usr/bin/env bash
# =====================================================================
# Aplica las migraciones pendientes de db/migrations/.
# Es idempotente: usa schema_migrations para no repetir archivos.
#
# Uso: ./scripts/linux/db-migrate.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker
require_env
load_env
ensure_volume

log "Asegurando PostgreSQL..."
docker compose up -d postgres >/dev/null

wait_postgres 30 || die "PostgreSQL no esta healthy. Revisa: docker compose logs postgres"

# Saber si la tabla de control existe (sin provocar error de psql).
table_exists="$(docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
    -tAc "SELECT to_regclass('public.schema_migrations') IS NOT NULL;" | tr -d '[:space:]')"

applied=""
if [ "$table_exists" = "t" ]; then
    applied="$(docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -tAc "SELECT filename FROM schema_migrations;" | tr -d '\r')"
fi

for file in "$PROJECT_ROOT"/db/migrations/*.sql; do
    [ -e "$file" ] || continue
    name="$(basename "$file")"

    if printf '%s\n' "$applied" | grep -qxF "$name"; then
        log "SKIP  $name"
        continue
    fi

    log "APPLY $name"
    docker compose cp "$file" "postgres:/tmp/$name" >/dev/null
    docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 -f "/tmp/$name"

    # Registro defensivo; las migraciones actuales ya se registran solas.
    docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -c "INSERT INTO schema_migrations (filename) VALUES ('$name') ON CONFLICT DO NOTHING;" \
        >/dev/null
    docker compose exec -T postgres rm -f "/tmp/$name" >/dev/null
done

log "Migraciones al dia."
