# Despliegue en servidores UCN

El objetivo del charter es operar con **costo $0** en infraestructura universitaria.
Este documento separa claramente el entorno de desarrollo (PC) del de producción (UCN).

## 1. Diferencias entre entornos

| Aspecto | Desarrollo (PC) | Producción (UCN) |
|---|---|---|
| n8n | Docker Compose local | Docker Compose en servidor |
| PostgreSQL | Contenedor local, puerto 5433 | Contenedor interno, **sin** puerto público |
| URL pública | Quick tunnel de Cloudflare (cambia) | Dominio fijo + proxy inverso HTTPS |
| Credenciales | `.env` local | `.env` del servidor + secretos institucionales |
| Respaldos | Manual (`scripts/backup.ps1`) | Cron diario + copia externa |
| Logs | Consola | Rotación de logs / journald |
| Usuarios | Uno o dos de prueba | Jefes de obra reales |

## 2. Requisitos del servidor

- Docker Engine + Docker Compose v2.
- Puerto 80/443 para el proxy inverso (o el que asigne la UCN).
- Salida a internet para Telegram y Gemini.
- Un dominio o subdominio institucional, por ejemplo `myra.ucn.cl`.
- Acceso SSH y permisos para levantar contenedores.

## 3. Pasos de instalación

### 3.1 Clonar y configurar

```bash
git clone https://github.com/lavaca777/proyecto-myra-n8n.git
cd proyecto-myra-n8n
cp .env.example .env
nano .env
```

En `.env` de producción:

- `DB_PASSWORD`: clave fuerte, distinta de `postgres`.
- `N8N_ENCRYPTION_KEY`: **la misma** que usa la instancia que tiene las credenciales.
  Si se migra desde el PC, copiar el valor exacto.
- `WEBHOOK_URL`: `https://myra.ucn.cl/` (con barra final).

### 3.2 Levantar

```bash
docker compose up -d
docker compose ps
docker compose logs -f n8n
```

### 3.3 Aplicar migraciones

En una base nueva se aplican solas. Si se restauró un respaldo:

```bash
docker compose exec -T postgres psql -U myra -d myra -c "SELECT filename FROM schema_migrations ORDER BY filename;"
```

Si faltan archivos, aplicar el `.sql` correspondiente con `psql -f`.

### 3.4 Proxy inverso con HTTPS

Ejemplo con Caddy (gestiona certificados automáticamente):

```caddyfile
myra.ucn.cl {
    reverse_proxy localhost:5678
}
```

Con Nginx:

```nginx
server {
    listen 80;
    server_name myra.ucn.cl;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

> n8n usa WebSockets para la UI. Sin `Upgrade`/`Connection` la interfaz se queda
> cargando.

### 3.5 Webhook de Telegram

1. Verificar que `WEBHOOK_URL` sea la URL pública.
2. Reiniciar n8n:

```bash
docker compose up -d --force-recreate n8n
```

3. Abrir el workflow del Telegram Trigger y guardarlo; n8n registra el webhook.
4. Probar con `/start` desde un chat autorizado.

Si el webhook queda "colgado", se puede consultar:

```bash
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
```

No hace falta borrar el webhook manualmente: n8n lo administra.

## 4. Seguridad

- No publicar `5433` en producción. En el compose, eliminar el bloque `ports` de
  PostgreSQL o dejarlo como `127.0.0.1:5433:5432` solo si se necesita administración local.
- El puerto `5678` puede quedar en `127.0.0.1:5678:5678` si el proxy corre en el mismo
  host. Si el proxy está en otro contenedor, usar una red interna de Docker.
- Cambiar `DB_PASSWORD` y no reutilizar la de desarrollo.
- Mantener `N8N_ENCRYPTION_KEY` fuera del repositorio.
- Configurar el firewall: solo 80/443 y SSH.
- n8n incluye autenticación de usuario; crear una cuenta institucional y no compartirla.
- Revisar permisos de los archivos `.env` (`chmod 600`).

## 5. Respaldos en producción

Cron diario (ejemplo a las 03:00):

```cron
0 3 * * * cd /opt/proyecto-myra-n8n && ./scripts/backup.sh >> /var/log/myra-backup.log 2>&1
```

Como los scripts están en PowerShell (Windows), en Linux conviene un `backup.sh`
equivalente:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p backups
docker compose exec -T postgres pg_dump -U myra -d myra -Fc > "backups/myra_${STAMP}.dump"
docker compose exec -T n8n n8n export:workflow --all --separate --output=/workflows
docker compose exec -T n8n n8n export:credentials --all --output=/tmp/credentials.json
docker compose cp n8n:/tmp/credentials.json "backups/credentials_${STAMP}.json"
find backups -type f -mtime +14 -delete
```

Además, copiar `backups/` y `n8n/workflows/` a un almacenamiento externo (OneDrive
institucional, servidor de respaldo, etc.). Un respaldo en el mismo servidor no protege
ante falla de disco.

## 6. Migrar los datos desde el PC

Si ya hay datos reales en desarrollo y se quieren llevar a la UCN:

1. En el PC: `.\scripts\backup.ps1` y copiar el `.dump` más reciente.
2. En el servidor: restaurar el dump (ver `docs/03-base-de-datos.md`).
3. Copiar `n8n/data/` completo (con n8n detenido) o importar los workflows JSON y
   volver a crear las credenciales.
4. Mantener la misma `N8N_ENCRYPTION_KEY`.

> Si se copia `n8n/data/`, las credenciales siguen cifradas y funcionan. Si se importan
> los workflows en una instancia nueva, hay que recrear las 3 credenciales.

## 7. Checklist de salida a producción

- [ ] `.env` con clave de base fuerte y `N8N_ENCRYPTION_KEY` correcta.
- [ ] `WEBHOOK_URL` con dominio HTTPS y barra final.
- [ ] Proxy inverso con WebSockets funcionando.
- [ ] Telegram webhook registrado y `/start` responde.
- [ ] Usuarios reales cargados en `usuarios` (whitelist).
- [ ] Proyectos, alias, medios de pago y categorías cargados.
- [ ] Migraciones aplicadas (`schema_migrations` al día).
- [ ] Respaldo automático probado (restaurar en una base de prueba).
- [ ] Workflows exportados a `n8n/workflows/` y commiteados.
- [ ] Error Workflow configurado en cada workflow.
- [ ] Monitoreo básico: `docker compose ps`, logs y espacio en disco.
- [ ] Documento de operación entregado a MYRA.

## 8. Rollback

Si una actualización rompe el servicio:

```bash
git log --oneline -5
git checkout <commit-anterior>
docker compose up -d --build
```

Si el problema es de datos:

1. Detener n8n.
2. Restaurar el último `pg_dump`.
3. Volver a levantar.
4. Verificar `schema_migrations` y los workflows.
