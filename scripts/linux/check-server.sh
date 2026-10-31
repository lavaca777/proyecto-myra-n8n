#!/usr/bin/env bash
# =====================================================================
# Diagnostico del servidor para n8n.
# Solo lectura: no instala, no modifica y no pide sudo.
#
# Uso:
#   bash scripts/linux/check-server.sh
#
# Pega la salida completa para decidir el camino de despliegue.
# =====================================================================

set -u
export LC_ALL=C

section() { printf '\n=== %s ===\n' "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }
cmd_version() {
    local out
    out="$("$@" 2>&1 | head -n 1 || true)"
    printf '%s' "${out:-(sin salida)}"
}

section "Sistema"
echo "hostname: $(hostname 2>/dev/null || true)"
echo "usuario:  $(id -un 2>/dev/null || true) (uid=$(id -u 2>/dev/null || true))"
echo "grupos:   $(id -Gn 2>/dev/null || true)"
echo "home:     ${HOME:-?}"
echo "shell:    ${SHELL:-?}"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "os:       ${PRETTY_NAME:-?}"
else
    echo "os:       $(uname -s 2>/dev/null || true)"
fi
echo "kernel:   $(uname -srm 2>/dev/null || true)"
echo "uptime:   $(uptime -p 2>/dev/null || true)"

section "Recursos"
echo "CPUs: $(nproc 2>/dev/null || echo '?')"
echo "RAM:"
free -h 2>/dev/null || echo "  (free no disponible)"
echo "Disco:"
df -h "${HOME:-/}" 2>/dev/null || df -h 2>/dev/null || true
echo "ulimit -n: $(ulimit -n 2>/dev/null || echo '?')"

section "Permisos"
if [ -w "${HOME:-/nonexistent}" ]; then
    echo "HOME escribible: SI"
else
    echo "HOME escribible: NO"
fi
if sudo -n true 2>/dev/null; then
    echo "sudo sin password: SI"
else
    echo "sudo sin password: no (normal)"
fi

section "Docker"
if have docker; then
    echo "docker: $(cmd_version docker --version)"
    echo "compose: $(cmd_version timeout 8 docker compose version)"
    echo "docker info:"
    timeout 8 docker info --format '  Server {{.ServerVersion}} / {{.OperatingSystem}}' 2>&1 || echo "  (sin acceso al daemon)"
    echo "docker ps:"
    timeout 8 docker ps --format '  {{.Names}}' 2>&1 | head -n 5 || true
else
    echo "docker: no instalado"
fi
if have docker-compose; then
    echo "docker-compose v1: $(cmd_version docker-compose --version)"
fi
if [ -S /var/run/docker.sock ]; then
    ls -l /var/run/docker.sock 2>/dev/null || true
fi

section "Alternativas de contenedores"
for c in podman apptainer singularity; do
    if have "$c"; then
        echo "$c: $(cmd_version "$c" --version)"
    else
        echo "$c: no"
    fi
done

section "Node / n8n"
for c in node npm npx n8n; do
    if have "$c"; then
        echo "$c: $(cmd_version "$c" --version)"
    else
        echo "$c: no"
    fi
done

section "Otras herramientas"
for c in git curl wget tmux screen cloudflared python3 sqlite3 psql jq; do
    if have "$c"; then
        echo "$c: $(command -v "$c")"
    else
        echo "$c: no"
    fi
done

section "Red saliente (HTTPS)"
if have curl; then
    for url in \
        https://api.telegram.org \
        https://generativelanguage.googleapis.com \
        https://registry.npmjs.org \
        https://docker.n8n.io
    do
        code="$(curl -sS -o /dev/null -m 8 -w '%{http_code}' "$url" 2>/dev/null || echo '000')"
        echo "$url -> HTTP $code"
    done
else
    echo "curl no instalado; no se puede probar la red saliente."
fi

section "IP y puertos"
echo "IPs locales: $(hostname -I 2>/dev/null || true)"
if have curl; then
    echo "IP publica:  $(curl -sS -m 8 https://ifconfig.me 2>/dev/null || echo '(no se pudo consultar)')"
fi
if have ss; then
    echo "Puerto 5678:"
    ss -ltn 2>/dev/null | grep -E ':5678\b' || echo "  libre (no hay listener)"
elif have netstat; then
    echo "Puerto 5678:"
    netstat -ltn 2>/dev/null | grep -E ':5678\b' || echo "  libre (no hay listener)"
else
    echo "ss/netstat: no disponible"
fi
if have python3; then
    python3 - <<'PY'
import socket
s = socket.socket()
try:
    s.bind(("127.0.0.1", 5678))
    print("Puede bindear 127.0.0.1:5678: SI")
except OSError as exc:
    print(f"Puede bindear 127.0.0.1:5678: NO ({exc})")
finally:
    s.close()
PY
fi

section "Persistencia de procesos"
if have systemctl; then
    echo "systemctl --user: $(cmd_version systemctl --user is-system-running)"
    if have loginctl; then
        echo "linger: $(cmd_version loginctl show-user "$(id -un)" -p Linger)"
    fi
else
    echo "systemctl: no disponible"
fi
if have crontab; then
    if crontab -l >/dev/null 2>&1; then
        echo "crontab: disponible (ya tiene tareas)"
    else
        echo "crontab: disponible (sin tareas)"
    fi
fi
if have tmux; then
    echo "tmux: disponible (puedes dejar n8n corriendo con 'tmux new -s n8n')"
fi

section "SELinux"
if have getenforce; then
    echo "getenforce: $(cmd_version getenforce)"
else
    echo "SELinux: no disponible"
fi

section "Resumen"
echo "Copia esta salida completa para decidir el camino de despliegue."
