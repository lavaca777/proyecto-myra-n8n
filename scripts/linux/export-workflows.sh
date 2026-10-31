#!/usr/bin/env bash
# =====================================================================
# Exporta TODOS los workflows de n8n a n8n/workflows/*.json.
# Uso: ./scripts/linux/export-workflows.sh
# =====================================================================

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

require_docker

container_running myra-n8n || die "myra-n8n no esta corriendo. Ejecuta ./scripts/linux/start.sh"

mkdir -p "$PROJECT_ROOT/n8n/workflows"

log "Exportando workflows a /tmp/wf-export..."
docker compose exec -T n8n sh -lc 'rm -rf /tmp/wf-export && mkdir -p /tmp/wf-export'

if ! docker compose exec -T n8n n8n export:workflow --all --separate --output=/tmp/wf-export; then
    die "Fallo el export de workflows. Revisa los logs de n8n."
fi

count="$(docker compose exec -T n8n sh -lc 'ls -1 /tmp/wf-export/*.json 2>/dev/null | wc -l' | tr -d '[:space:]')"
[ "${count:-0}" -gt 0 ] || die "El export no genero archivos JSON. No se toco la carpeta local."

# Solo despues de un export exitoso se reemplazan los archivos locales.
find "$PROJECT_ROOT/n8n/workflows" -maxdepth 1 -name '*.json' -delete
docker compose cp 'n8n:/tmp/wf-export/.' "$PROJECT_ROOT/n8n/workflows" >/dev/null
docker compose exec -T n8n rm -rf /tmp/wf-export >/dev/null

# Renombrar los archivos (n8n los exporta con el ID) a kebab-case.
if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import json
import pathlib
import re
import unicodedata

folder = pathlib.Path('n8n/workflows')
for current in sorted(folder.glob('*.json')):
    try:
        workflow = json.loads(current.read_text(encoding='utf-8'))
    except Exception:
        continue

    name = workflow.get('name') or current.stem
    normalized = unicodedata.normalize('NFD', name)
    normalized = ''.join(c for c in normalized if unicodedata.category(c) != 'Mn')
    slug = re.sub(r'[^a-z0-9]+', '-', normalized.lower()).strip('-') or current.stem

    target = folder / f'{slug}.json'
    if target == current:
        continue
    if target.exists():
        target = folder / f'{slug}-{current.stem[:6]}.json'
    current.rename(target)
PY
else
    warn "python3 no esta instalado; los archivos quedaron con el ID como nombre."
fi

log "Listo: $count workflow(s) exportado(s) a n8n/workflows/"
find "$PROJECT_ROOT/n8n/workflows" -maxdepth 1 -name '*.json' -printf '  - %f\n' | sort
