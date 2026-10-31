# Proyecto MYRA · Automatización de compras por voz

Sistema de registro financiero de compras para **Constructora MYRA**, orquestado con
**n8n + PostgreSQL + Telegram + IA**. El usuario envía una nota de voz, el bot extrae
los 5 campos críticos (**proyecto, monto, fecha, proveedor y medio de pago**), pide
confirmación y persiste el gasto.

- **Project Charter:** [`docs/charter/proyect charter.md`](docs/charter/proyect%20charter.md)
- **Arquitectura:** [`docs/01-arquitectura.md`](docs/01-arquitectura.md)
- **Diseño de flujos:** [`docs/02-flujos.md`](docs/02-flujos.md)
- **Base de datos:** [`docs/03-base-de-datos.md`](docs/03-base-de-datos.md)
- **Despliegue UCN:** [`docs/04-despliegue-ucn.md`](docs/04-despliegue-ucn.md)
- **Migración desde la carpeta anterior:** [`docs/05-migracion.md`](docs/05-migracion.md)

---

## Inicio rápido

### Requisitos

- Docker Desktop corriendo (con Docker Compose v2)
- PowerShell 5.1 o superior
- `cloudflared` instalado y en el `PATH` (solo para probar Telegram desde internet)

### Levantar todo (modo desarrollo)

Este es el equivalente al antiguo `start-all.ps1`. Abre **primero** el túnel,
actualiza `WEBHOOK_URL` en `.env` y en la sesión, y **después** levanta PostgreSQL +
n8n, para que el Telegram Trigger nazca con la URL pública correcta. Finalmente aplica
las migraciones.

> ¿Por qué ese orden? Docker Compose prioriza las variables de entorno del proceso
> sobre el archivo `.env`. `dev.ps1` actualiza ambas antes de crear el contenedor;
> si solo se edita `.env`, n8n puede quedar apuntando a `localhost`.

```powershell
# Crear el .env solo si no existe (NO sobrescribir el actual: contiene la key)
if (-not (Test-Path .env)) { Copy-Item .env.example .env }

# Un solo comando: stack + migraciones + tunel + webhook
.\scripts\dev.ps1
```

Al terminar verás:

- n8n: <http://localhost:5678>
- PostgreSQL: `localhost:5433` (usuario `myra`, base `myra`)
- URL pública del túnel, ya configurada como webhook de Telegram

Deja esa ventana abierta mientras pruebas el bot. `Ctrl+C` cierra el túnel, pero
**no** apaga los contenedores.

### Si prefieres hacerlo por pasos

```powershell
.\scripts\start.ps1     # PostgreSQL + n8n + migraciones
.\scripts\tunnel.ps1    # tunel + actualiza WEBHOOK_URL + reinicia n8n
```

El orden importa: primero el stack, después el túnel. `tunnel.ps1` necesita que n8n
esté corriendo (o lo levanta, pero no aplica migraciones).

### Detener

```powershell
.\scripts\stop.ps1
```

> `stop.ps1` **no** borra los datos: los volúmenes y `n8n/data/` se conservan.

### Resumen de scripts · Windows (desarrollo)

| Script | Cuándo usarlo |
|---|---|
| `scripts\dev.ps1` | Todo en uno: túnel primero, luego stack + migraciones + webhook |
| `scripts\start.ps1` | Solo levantar PostgreSQL + n8n (sin túnel) y migrar |
| `scripts\tunnel.ps1` | Abrir el túnel, actualizar el webhook y reiniciar n8n |
| `scripts\stop.ps1` | Apagar los contenedores sin borrar datos |
| `scripts\db-migrate.ps1` | Aplicar migraciones pendientes |
| `scripts\psql.ps1` | Consola SQL |
| `scripts\export-workflows.ps1` | Exportar workflows a JSON antes de commitear |
| `scripts\backup.ps1` | Respaldo de PostgreSQL + workflows + credenciales |

### Resumen de scripts · Linux (servidor)

| Script | Cuándo usarlo |
|---|---|
| `scripts/linux/check-server.sh` | Diagnóstico previo: Docker, Node, red, puertos y permisos |
| `scripts/linux/setup.sh` | Primer arranque: `.env`, volumen, carpetas y permisos |
| `scripts/linux/start.sh` | Levantar el stack y aplicar migraciones |
| `scripts/linux/stop.sh` | Apagar sin borrar datos |
| `scripts/linux/status.sh` | Ver contenedores, webhook y migraciones |
| `scripts/linux/logs.sh` | Logs en vivo (`n8n` o `postgres`) |
| `scripts/linux/db-migrate.sh` | Aplicar migraciones pendientes |
| `scripts/linux/export-workflows.sh` | Exportar workflows a JSON |
| `scripts/linux/backup.sh` | Respaldo completo |
| `scripts/linux/restore-db.sh` | Restaurar un `pg_dump` (destructivo) |

> Los `.ps1` son solo para Windows. En el servidor Linux usa `.sh`. Los scripts de
> túnel no se usan en producción: allí hay un dominio fijo y HTTPS.

### Probar el bot de Telegram

Telegram necesita una URL pública HTTPS. En desarrollo se usa un túnel rápido de
Cloudflare. `dev.ps1` ya lo hace; si el stack ya estaba corriendo, basta con:

```powershell
.\scripts\tunnel.ps1
```

El script:

1. Levanta `cloudflared` contra `localhost:5678`.
2. Detecta la URL `https://....trycloudflare.com`.
3. Actualiza `WEBHOOK_URL` en `.env` **y** en la sesión de PowerShell.
4. Reinicia n8n para que use la URL pública en los webhooks.

> El webhook de Telegram se registra cuando **activas el workflow** o cuando usas
> **Test workflow** en el Telegram Trigger. Tener la URL pública configurada no
> registra el webhook por sí solo.

La URL cambia cada vez que reinicias el túnel. En la UCN se debe usar un dominio
fijo o un túnel nombrado (ver [`docs/04-despliegue-ucn.md`](docs/04-despliegue-ucn.md)).

---

## Estructura del proyecto

```text
.
├─ docker-compose.yml          # postgres + n8n (unica fuente de verdad)
├─ .env                        # secretos locales (ignorado por git)
├─ .env.example                # plantilla de desarrollo
├─ .env.production.example     # plantilla para el servidor Linux
├─ db/
│  ├─ migrations/              # esquema y cambios, en orden (000, 001, ...)
│  ├─ seeds/                   # datos de ejemplo para desarrollo
│  └─ backups/                 # pg_dump (ignorado por git)
├─ n8n/
│  ├─ data/                    # volumen real de n8n: SQLite, credenciales, storage
│  └─ workflows/               # workflows exportados a JSON (versionados)
├─ scripts/
│  ├─ *.ps1                    # Windows: desarrollo local
│  └─ linux/
│     ├─ setup.sh              # preparacion del servidor
│     ├─ start.sh / stop.sh
│     ├─ db-migrate.sh
│     ├─ export-workflows.sh
│     ├─ backup.sh / restore-db.sh
│     ├─ status.sh / logs.sh
│     └─ _common.sh
├─ deploy/
│  ├─ nginx/myra.conf          # proxy inverso + WebSockets
│  ├─ caddy/Caddyfile          # alternativa con TLS automatico
│  └─ systemd/myra.service     # arranque opcional al boot
├─ docs/
│  ├─ charter/                 # Project Charter e imagenes
│  ├─ entrevistas/             # transcripciones (los audios no se versionan)
│  ├─ db/                      # modelo relacional
│  └─ prompts/                 # prompts versionados
└─ assets/                     # material de referencia
```

### Regla de oro

- `n8n/data/` es **desechable/restaurable**: contiene la base SQLite de n8n.
- `n8n/workflows/*.json` es la **fuente de verdad versionada** de los flujos.
- Después de cada cambio en la UI de n8n: `.\scripts\export-workflows.ps1` y commit.

---

## Convenciones de n8n

### Nombres

| Elemento | Convención | Ejemplo |
|---|---|---|
| Workflow | `[MYRA] NN · Nombre` | `[MYRA] 03 · Extracción de gasto` |
| Sub-workflow | `[MYRA] NN · Nombre` | `[MYRA] 00 · Maestras` |
| Nodo | Verbo + objeto | `Buscar proyecto por alias` |
| Credencial | `MYRA · Servicio` | `MYRA · Postgres local` |
| Tag | `modulo:...` / `estado:...` | `modulo:voz`, `estado:dev` |

### Reglas de diseño

1. **Un workflow = una responsabilidad.** Se comunican con `Execute Sub-workflow`.
2. **El LLM extrae, no escribe en la base.** La persistencia se hace con nodos
   deterministas (Postgres) y validaciones explícitas.
3. **El estado de la conversación vive en PostgreSQL** (`registros_entrada.estado` y
   `campo_pendiente`), no en la memoria del agente. Así sobrevive a reinicios.
4. **Confirmación con botones inline** (`callback_query`), no texto libre.
5. **Nada se guarda en `gastos` sin los 5 campos válidos.** El proyecto es obligatorio.
6. **Idempotencia:** un mismo mensaje de Telegram no puede generar dos gastos.
7. **Credenciales y `.env` nunca se versionan.**

### Tags sugeridos

`modulo:entrada`, `modulo:voz`, `modulo:registro`, `modulo:admin`, `modulo:reportes`,
`estado:dev`, `estado:prod`.

---

## Flujos

| WF | Nombre | Responsabilidad |
|---|---|---|
| 00 | Maestras | Proyectos + alias, medios de pago, categorías y validación de usuario |
| 01 | Telegram Router | Recibe el update y enruta voz / texto / foto / botón |
| 02 | Voz → Texto | Descarga el audio y lo transcribe (STT) |
| 03 | Extracción | LLM + validación de los 5 campos + fuzzy match de proyecto |
| 04 | Confirmación | Máquina de estados, correcciones y persistencia del gasto |
| 05 | Comandos | `/start`, `/proyectos`, `/resumen`, `/ultimos`, `/cancelar` |
| 06 | Reportes | Resumen semanal CSV/Excel (Could) |
| 07 | Errores | Error Trigger + aviso al administrador |

El detalle de nodos y transiciones está en [`docs/02-flujos.md`](docs/02-flujos.md).

---

## Base de datos

El esquema está en [`db/migrations/`](db/migrations/). En una base nueva, Docker
ejecuta los archivos en orden alfabético. Para una base existente:

```powershell
.\scripts\db-migrate.ps1
```

Migraciones actuales:

| Archivo | Contenido |
|---|---|
| `000_migrations.sql` | Tabla de control `schema_migrations` |
| `001_schema_inicial.sql` | Tablas, índices, trigger y vista `v_gastos_detalle` |
| `002_seed_catalogos.sql` | Medios de pago y categorías iniciales |
| `003_fuzzy_proyectos.sql` | `pg_trgm` para buscar proyectos por similitud |

Consola SQL:

```powershell
.\scripts\psql.ps1
```

---

## Respaldos

```powershell
.\scripts\backup.ps1      # Windows
```

```bash
./scripts/linux/backup.sh  # Linux / servidor
```

Genera en `db/backups/`:

- `myra_YYYYMMDD_HHmmss.dump` → PostgreSQL (`pg_dump -Fc`)
- `credentials_YYYYMMDD_HHmmss.json` → credenciales de n8n (cifradas con la key)
- Actualiza `n8n/workflows/*.json`

Retención automática: 14 días. **No** se versionan los respaldos.

---

## Servidor Linux (UCN)

En el servidor **no se usan los `.ps1` ni el túnel rápido**. Hay un dominio fijo y
los scripts son `.sh`.

```bash
git clone https://github.com/lavaca777/proyecto-myra-n8n.git
cd proyecto-myra-n8n

cp .env.production.example .env
chmod 600 .env
nano .env          # DB_PASSWORD, N8N_ENCRYPTION_KEY, WEBHOOK_URL

./scripts/linux/setup.sh
./scripts/linux/start.sh
./scripts/linux/status.sh
```

Configuración típica detrás de Nginx/Caddy en el mismo host:

```dotenv
WEBHOOK_URL=https://myra.ucn.cl/
N8N_BIND=127.0.0.1
PG_BIND=127.0.0.1
N8N_PROXY_HOPS=1
```

- Proxy inverso: `deploy/nginx/myra.conf` o `deploy/caddy/Caddyfile`.
- Arranque al boot: `restart: unless-stopped` o `deploy/systemd/myra.service`.
- Respaldo diario: `./scripts/linux/backup.sh` desde cron.
- Guía completa: [`docs/04-despliegue-ucn.md`](docs/04-despliegue-ucn.md).

> Si migras `n8n/data/` desde el PC, mantén la misma `N8N_ENCRYPTION_KEY` y ajusta
> permisos con `sudo chown -R 1000:1000 n8n/data n8n/workflows`.

---

## Seguridad

- `.env` está en `.gitignore`. No lo subas nunca.
- La `N8N_ENCRYPTION_KEY` es la misma que usaba la instancia anterior. Si se pierde,
  hay que volver a crear las 3 credenciales (Telegram, Gemini, Postgres).
- La contraseña `postgres` es solo para desarrollo local. En la UCN se debe cambiar
  y rotar la clave.
- El repo puede ser público: revisa `git status` antes de cada commit.

---

## Problemas frecuentes

### n8n no abre

```powershell
docker compose ps
docker compose logs -f n8n
```

Si Docker Desktop no está corriendo, `start.ps1` lo avisa.

### Error `port is already allocated` en 5433

Puede que el stack anterior (`Myra_db`) siga activo con `restart: unless-stopped`:

```powershell
docker ps
docker stop myra_db-postgres-1
```

### El bot no responde en Telegram

1. Verifica que `WEBHOOK_URL` en `.env` sea la URL pública actual.
2. Ejecuta `.\scripts\tunnel.ps1` de nuevo (la URL del túnel cambia).
3. Revisa en n8n: **Workflow → Telegram Trigger → Webhook** y los logs de ejecución.

### El contenedor quedó apuntando a localhost

Revisa la variable real del contenedor:

```powershell
docker inspect myra-n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | Select-String WEBHOOK
```

Debe mostrar `N8N_WEBHOOK_URL=https://....trycloudflare.com/`. Si muestra
`http://localhost:5678/`, ejecuta:

```powershell
.\scripts\dev.ps1
```

No basta con editar el `.env` y reiniciar: Docker Compose prioriza la variable
`WEBHOOK_URL` que ya está cargada en la sesión de PowerShell. `dev.ps1` y
`tunnel.ps1` actualizan el archivo **y** la variable del proceso antes de recrear
el contenedor.

### Las credenciales no se pueden descifrar

La `N8N_ENCRYPTION_KEY` del `.env` no coincide con la que cifró los datos.
Restaura el valor original (`n8n/data/config` lo conserva) y reinicia:

```powershell
docker compose up -d --force-recreate n8n
```

### Cambié el esquema y no se aplica

Los scripts de `db/migrations/` solo se ejecutan automáticamente cuando el volumen
está vacío. Usa `.\scripts\db-migrate.ps1`.

---

## Estado actual

- [x] Estructura del proyecto ordenada
- [x] Compose unificado (PostgreSQL + n8n)
- [x] Workflows y credenciales migrados desde la instancia anterior
- [x] Esquema dividido en migraciones
- [ ] WF-00 Maestras
- [ ] WF-01 Telegram Router
- [ ] WF-02 Voz → Texto
- [ ] WF-03 Extracción
- [ ] WF-04 Confirmación y persistencia
- [ ] WF-05 Comandos
- [ ] WF-06 Reportes
- [ ] Despliegue UCN
