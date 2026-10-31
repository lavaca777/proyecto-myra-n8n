# Despliegue en servidores UCN (Linux)

El objetivo del charter es operar con **costo $0** en infraestructura universitaria.
Este documento cubre el despliegue en un servidor Linux fijo.

## 1. Desarrollo vs producción

| Aspecto | Desarrollo (Windows) | Producción (Linux/UCN) |
|---|---|---|
| n8n | Docker Compose local | Docker Compose en el servidor |
| PostgreSQL | Contenedor local, puerto 5433 | Contenedor interno, **sin** puerto público |
| URL pública | Quick tunnel de Cloudflare (cambia) | Dominio fijo + HTTPS (Nginx/Caddy o túnel nombrado) |
| Scripts | `scripts/*.ps1` | `scripts/linux/*.sh` |
| Respaldos | Manual (`backup.ps1`) | Cron diario (`backup.sh`) |
| Logs | Consola | `docker compose logs` + rotación de Docker |

> Los scripts `.ps1` **no funcionan en Linux**. Usan rutas de Windows, `Start-Process`
> y PowerShell. En el servidor usa los `.sh`. Si tienes `pwsh` instalado podrían
> ejecutarse algunos, pero no es el camino recomendado.

## 2. Qué scripts necesitas en el servidor

| Script | Para qué |
|---|---|
| `scripts/linux/check-server.sh` | Diagnóstico previo: Docker, Node, red, puertos y permisos |
| `scripts/linux/setup.sh` | Primer arranque: `.env`, volumen, carpetas y permisos |
| `scripts/linux/start.sh` | Levantar el stack y aplicar migraciones |
| `scripts/linux/stop.sh` | Apagar sin borrar datos |
| `scripts/linux/status.sh` | Ver contenedores, webhook y migraciones |
| `scripts/linux/logs.sh` | Ver logs en vivo |
| `scripts/linux/db-migrate.sh` | Aplicar migraciones pendientes |
| `scripts/linux/export-workflows.sh` | Exportar workflows a JSON para git |
| `scripts/linux/backup.sh` | Respaldo de PostgreSQL + workflows + credenciales |
| `scripts/linux/restore-db.sh` | Restaurar un `pg_dump` (destructivo) |

Los scripts de túnel (`dev.ps1`, `tunnel.ps1`) **no se usan en producción**. En el
servidor hay una URL fija y no hace falta tunel rápido.

## 3. Requisitos del servidor

- Linux con Docker Engine + Docker Compose v2.
- Git.
- Puerto 80 y 443 para el proxy inverso (o túnel saliente si no hay IP pública).
- Salida a internet para Telegram y Gemini.
- Un dominio o subdominio, por ejemplo `myra.ucn.cl`.
- Acceso SSH y permisos para Docker (`sudo` o grupo `docker`).

Verificar:

```bash
docker --version
docker compose version
git --version
```

### 3.1 Diagnóstico antes de instalar

Si no sabes qué tiene el servidor o no tienes sudo, ejecuta:

```bash
bash scripts/linux/check-server.sh
```

Revisa especialmente:

- `groups` y `docker ps`: si apareces en el grupo `docker` y `docker ps`
  funciona, puedes usar contenedores sin sudo.
- `docker compose version`: debe existir el plugin v2.
- `node --version`: n8n 2.x necesita Node 20.19–24.x (solo si no usarás Docker).
- `curl` a `api.telegram.org` y `generativelanguage.googleapis.com`: confirma
  salida a internet.
- `ss -ltn | grep 5678`: confirma que el puerto está libre.
- `systemctl --user` y `tmux`: opciones para dejar n8n corriendo tras cerrar SSH.

### 3.2 Si no hay Docker ni acceso de administrador

Para **probar** n8n no necesitas Docker ni root. n8n 2.x se puede ejecutar en el
espacio del usuario con Node.js:

```bash
# Requiere Node 20.19 a 24.x
node --version

mkdir -p ~/n8n-test && cd ~/n8n-test
npx n8n@2.42.6
```

- Abre la UI desde tu PC con un túnel SSH:
  ```bash
  ssh -L 5678:localhost:5678 usuario@servidor
  ```
  y visita `http://localhost:5678`.
- Para Telegram necesitas HTTPS público. Puedes usar un túnel de Cloudflare
  ejecutado como usuario (sin sudo):
  ```bash
  cloudflared tunnel --url http://localhost:5678
  ```
  Luego inicia n8n con `WEBHOOK_URL=https://....trycloudflare.com/ npx n8n@2.42.6`.
- Para que siga corriendo al cerrar SSH, usa `tmux`:
  ```bash
  tmux new -s n8n
  npx n8n@2.42.6
  # Ctrl+B, luego D para desconectarte
  ```

> n8n 3.x ya no soporta `npx`/`npm`; por eso fijamos `2.42.6`. Para el proyecto
> completo (PostgreSQL + credenciales compartidas) sí conviene Docker.

## 4. Primer despliegue

### 4.1 Clonar

```bash
sudo mkdir -p /opt/proyecto-myra-n8n
sudo chown "$USER":"$USER" /opt/proyecto-myra-n8n
git clone https://github.com/lavaca777/proyecto-myra-n8n.git /opt/proyecto-myra-n8n
cd /opt/proyecto-myra-n8n
```

### 4.2 Configurar `.env`

```bash
cp .env.production.example .env
chmod 600 .env
nano .env
```

Completar:

- `DB_PASSWORD`: clave larga y distinta de `postgres`.
- `N8N_ENCRYPTION_KEY`:
  - Si migras las credenciales del PC: la **misma** clave exacta.
  - Si empiezas de cero: `openssl rand -hex 32`.
- `WEBHOOK_URL`: `https://myra.ucn.cl/` (HTTPS y con barra final).
- `N8N_BIND=127.0.0.1` y `PG_BIND=127.0.0.1` si el proxy está en el mismo host.
- `N8N_PROXY_HOPS=1` con Nginx/Caddy en el host; `2` si hay Cloudflare delante.

### 4.3 Preparar y arrancar

```bash
./scripts/linux/setup.sh
./scripts/linux/start.sh
```

`setup.sh` crea el volumen `myra_db_pg_data`, las carpetas y ajusta permisos. Si lo
corres como root, deja `n8n/data` y `n8n/workflows` con UID/GID `1000` (el usuario
`node` de la imagen n8n). Si no eres root, revisa el aviso.

`start.sh` levanta PostgreSQL + n8n y aplica las migraciones.

Verificar:

```bash
./scripts/linux/status.sh
docker compose ps
docker compose logs -f n8n
```

- n8n local: `http://127.0.0.1:5678`
- PostgreSQL: `127.0.0.1:5433` (solo para administración local)

### 4.4 Primer login de n8n

Abre `https://myra.ucn.cl` (después de configurar el proxy) y crea la cuenta de
propietario. Si migraste `n8n/data` desde el PC, usa el usuario que ya existía.

## 5. HTTPS y dominio

Telegram exige una URL HTTPS válida. Elige una opción:

### Opción A · Nginx + Certbot (recomendado si hay IP pública)

```bash
sudo apt update
sudo apt install nginx certbot python3-certbot-nginx
sudo cp deploy/nginx/myra.conf /etc/nginx/sites-available/myra
sudo ln -s /etc/nginx/sites-available/myra /etc/nginx/sites-enabled/myra
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d myra.ucn.cl
```

El archivo ya incluye los headers de WebSocket que n8n necesita. Certbot agrega el
bloque HTTPS y la redirección. El dominio debe apuntar al servidor y el puerto 80
debe estar accesible desde internet para que Certbot valide.

### Opción B · Caddy

```bash
sudo apt install caddy
sudo cp deploy/caddy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy obtiene el certificado automáticamente.

### Opción C · Cloudflare Tunnel (si no hay IP pública)

Sirve si el servidor está detrás de NAT o la UCN no abre puertos. El servidor hace
una conexión saliente y no necesita abrir 80/443.

```bash
# En el servidor
cloudflared tunnel login
cloudflared tunnel create myra
cloudflared tunnel route dns myra myra.ucn.cl
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: <UUID-del-tunel>
credentials-file: /home/<usuario>/.cloudflared/<UUID>.json
ingress:
  - hostname: myra.ucn.cl
    service: http://127.0.0.1:5678
  - service: http_status:404
```

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

En este caso `WEBHOOK_URL=https://myra.ucn.cl/` y `N8N_PROXY_HOPS=2` (Cloudflare +
n8n). No uses `trycloudflare.com` en producción.

## 6. Migraciones

En una base nueva, Docker ejecuta `db/migrations/*.sql` al inicializar el volumen.
Para una base existente o después de un `git pull`:

```bash
./scripts/linux/db-migrate.sh
```

El script revisa `schema_migrations` y solo aplica lo pendiente. Es idempotente.

## 7. Respaldos

```bash
./scripts/linux/backup.sh
```

Genera en `db/backups/`:

- `myra_YYYYMMDD_HHMMSS.dump` → PostgreSQL (`pg_dump -Fc`)
- `credentials_YYYYMMDD_HHMMSS.json` → credenciales de n8n (cifradas)
- Actualiza `n8n/workflows/*.json`

Retención automática: 14 días.

Cron diario a las 03:00:

```cron
0 3 * * * cd /opt/proyecto-myra-n8n && ./scripts/linux/backup.sh >> /var/log/myra-backup.log 2>&1
```

Además, copia `db/backups/` y `n8n/workflows/` a un almacenamiento externo (OneDrive
institucional, otro servidor, etc.). Un respaldo en el mismo disco no protege ante
falla de hardware.

> La `N8N_ENCRYPTION_KEY` **no** se guarda en el repositorio. Anótala en un gestor de
> secretos institucional. Sin ella, el respaldo de credenciales no sirve.

## 8. Seguridad

- `N8N_BIND=127.0.0.1` y `PG_BIND=127.0.0.1`: n8n y PostgreSQL no se exponen directo.
- Firewall: solo SSH, 80 y 443. No abras 5678 ni 5433.
- `chmod 600 .env`.
- No reutilices la contraseña de desarrollo.
- Crea la cuenta de n8n con el correo institucional y no la compartas.
- Si usas Cloudflare Tunnel, no necesitas abrir 80/443.
- Revisa los logs y el espacio en disco:

```bash
df -h
docker system df
```

## 9. Operación diaria

```bash
./scripts/linux/status.sh          # estado general
./scripts/linux/logs.sh            # logs de n8n
./scripts/linux/logs.sh postgres   # logs de PostgreSQL
./scripts/linux/db-migrate.sh      # migraciones pendientes
./scripts/linux/export-workflows.sh
./scripts/linux/backup.sh
./scripts/linux/stop.sh
./scripts/linux/start.sh
```

Docker con `restart: unless-stopped` levanta los contenedores al bootear. Si prefieres
systemd:

```bash
sudo cp deploy/systemd/myra.service /etc/systemd/system/myra.service
sudo systemctl daemon-reload
sudo systemctl enable --now myra
sudo systemctl status myra
```

## 10. Migrar los datos desde el PC

Si quieres conservar los workflows, credenciales y datos de prueba:

1. En el PC, detén n8n y haz un respaldo:
   ```powershell
   .\scripts\stop.ps1
   .\scripts\backup.ps1
   ```
2. Copia al servidor:
   - `n8n/data/` completo (SQLite, `config`, storage)
   - El `.dump` más reciente de `db/backups/`
3. En el servidor:
   ```bash
   # Detener n8n antes de copiar datos
   ./scripts/linux/stop.sh

   # Copiar n8n/data (scp/rsync) y ajustar permisos
   sudo chown -R 1000:1000 n8n/data

   # Restaurar PostgreSQL
   ./scripts/linux/start.sh
   ./scripts/linux/restore-db.sh db/backups/myra_AAAAAMMDD_HHMMSS.dump
   ```
4. Mantén la **misma** `N8N_ENCRYPTION_KEY` en el `.env` del servidor. Si no, las
   credenciales de `n8n/data` no se descifran.

Si empiezas de cero en el servidor, no copies `n8n/data`: n8n crea su base nueva y
tendrás que recrear las 3 credenciales (Telegram, Gemini, Postgres).

## 11. Checklist de salida a producción

- [ ] `.env` con clave de base fuerte y `N8N_ENCRYPTION_KEY` correcta.
- [ ] `WEBHOOK_URL` con dominio HTTPS y barra final.
- [ ] `N8N_BIND=127.0.0.1` y `PG_BIND=127.0.0.1`.
- [ ] Proxy inverso con WebSockets funcionando.
- [ ] `./scripts/linux/status.sh` sin errores.
- [ ] Telegram webhook registrado y `/start` responde.
- [ ] Usuarios reales cargados en `usuarios`.
- [ ] Proyectos, alias, medios de pago y categorías cargados.
- [ ] Migraciones aplicadas (`schema_migrations` al día).
- [ ] Respaldo automático probado (restaurar en una base de prueba).
- [ ] Workflows exportados a `n8n/workflows/` y commiteados.
- [ ] Error Workflow configurado en cada workflow.
- [ ] Monitoreo básico: `docker compose ps`, logs y espacio en disco.
- [ ] Documento de operación entregado a MYRA.

## 12. Problemas comunes

### n8n no puede escribir en `n8n/data`

```bash
sudo chown -R 1000:1000 n8n/data n8n/workflows
```

La imagen n8n corre como usuario `node` (UID 1000).

### Error de permisos con SELinux (RHEL/CentOS/Rocky)

```bash
getenforce
```

Si está en `Enforcing`, agrega `:z` a los bind mounts en `docker-compose.yml`:

```yaml
- ./n8n/data:/home/node/.n8n:z
- ./n8n/workflows:/workflows:z
```

### El webhook de Telegram no llega

1. Verifica `WEBHOOK_URL` con `./scripts/linux/status.sh`.
2. Prueba el dominio desde fuera: `curl -I https://myra.ucn.cl/`.
3. Revisa que el proxy tenga los headers de WebSocket.
4. Revisa `docker compose logs n8n`.
5. Consulta Telegram:
   ```bash
   curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
   ```

### `port is already allocated`

Puede quedar un stack anterior o un contenedor suelto:

```bash
docker ps -a
docker stop <nombre>
```

### El contenedor quedó con `N8N_WEBHOOK_URL` viejo

```bash
docker compose up -d --force-recreate n8n
```

Si cambiaste `.env`, Compose debe recrear el contenedor para tomar la variable.

## 13. Rollback

```bash
git log --oneline -5
git checkout <commit-anterior>
./scripts/linux/start.sh
```

Si el problema es de datos:

1. Detén n8n.
2. Restaura el último `pg_dump` con `restore-db.sh`.
3. Verifica `schema_migrations` y los workflows.
