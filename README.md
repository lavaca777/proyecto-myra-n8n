# Proyecto MYRA · Automatización de compras por voz

Sistema de registro financiero de compras para **Constructora MYRA**, orquestado con
**n8n Cloud + Supabase (PostgreSQL) + Telegram + IA**. El usuario envía una nota de
voz, el bot extrae los 5 campos críticos (**proyecto, monto, fecha, proveedor y medio
de pago**), pide confirmación y persiste el gasto.

> **Producción:** n8n Cloud + Supabase. Docker Compose y PostgreSQL local se
> mantienen solo para desarrollo y pruebas.

- **Project Charter:** [`docs/charter/proyect charter.md`](docs/charter/proyect%20charter.md)
- **Arquitectura:** [`docs/01-arquitectura.md`](docs/01-arquitectura.md)
- **Diseño de flujos:** [`docs/02-flujos.md`](docs/02-flujos.md)
- **Base de datos:** [`docs/03-base-de-datos.md`](docs/03-base-de-datos.md)
- **Despliegue Cloud:** [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md)
- **Migración desde la carpeta anterior:** [`docs/05-migracion.md`](docs/05-migracion.md)
- **WF-02 Voz → Texto (handoff):** [`docs/06-wf-02-voz-a-texto.md`](docs/06-wf-02-voz-a-texto.md)

---

## Inicio rápido

### Requisitos (solo desarrollo local)

- Docker Desktop corriendo (con Docker Compose v2)
- PowerShell 5.1 o superior
- `cloudflared` instalado y en el `PATH` (solo para probar Telegram desde internet)

> Esto no es el entorno de producción. Producción usa n8n Cloud y Supabase; ver
> [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

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

> La producción no usa Docker, Nginx, Caddy, VPS ni servidor UCN. Ver
> [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

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

La URL cambia cada vez que reinicias el túnel. Eso es solo para desarrollo; en
producción n8n Cloud entrega una URL HTTPS fija.

---

## Estructura del proyecto

```text
.
├─ docker-compose.yml          # postgres + n8n solo para desarrollo local
├─ .env                        # secretos locales (ignorado por git)
├─ .env.example                # plantilla de desarrollo local
├─ db/
│  ├─ migrations/              # esquema y cambios, en orden (000, 001, ...)
│  ├─ seeds/                   # datos de ejemplo para desarrollo
│  └─ backups/                 # pg_dump (ignorado por git)
├─ n8n/
│  ├─ data/                    # n8n local: SQLite, credenciales, storage (solo dev)
│  └─ workflows/               # workflows exportados a JSON (versionados)
├─ scripts/
│  └─ *.ps1                    # Windows: desarrollo local
├─ docs/
│  ├─ charter/                 # Project Charter e imagenes
│  ├─ entrevistas/             # transcripciones (los audios no se versionan)
│  ├─ db/                      # modelo relacional
│  └─ prompts/                 # prompts versionados
└─ assets/                     # material de referencia
```

### Regla de oro

- `n8n/data/` es **desechable/restaurable** y solo existe en desarrollo local:
  contiene la base SQLite de n8n. En producción no se copia a n8n Cloud.
- `n8n/workflows/*.json` es la **fuente de verdad versionada** de los flujos.
- Después de cada cambio en la UI de n8n local: `.\scripts\export-workflows.ps1` y
  commit. En Cloud, exportar/importar desde la UI cuando corresponda.

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
| 06 | Exportaciones | Descarga de gastos para administración (Excel/CSV, filtros por fecha y proyecto) |
| 07 | Maestras | Alta de proyectos, clientes y alias; edición y desactivación |
| 08 | Errores | Error Trigger + aviso al administrador |
| 09 | Heartbeat | Consulta periódica a Supabase para evitar la pausa por inactividad |
| 08 | Heartbeat | Consulta periódica a Supabase para evitar la pausa por inactividad |

El detalle de nodos y transiciones está en [`docs/02-flujos.md`](docs/02-flujos.md).

---

## Base de datos

El esquema está en [`db/migrations/`](db/migrations/). En producción se aplica en
Supabase desde el SQL Editor o con `psql`; en desarrollo local, Docker ejecuta los
archivos en orden alfabético y, para una base local existente:

```powershell
.\scripts\db-migrate.ps1
```

Producción: ver [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

Migraciones actuales:

| Archivo | Contenido |
|---|---|
| `000_migrations.sql` | Tabla de control `schema_migrations` |
| `001_schema_inicial.sql` | Tablas, índices, trigger y vista `v_gastos_detalle` |
| `002_seed_catalogos.sql` | Medios de pago y categorías iniciales |
| `003_fuzzy_proyectos.sql` | `pg_trgm` para buscar proyectos por similitud |
| `004_admin_pending.sql` | Estado temporal para la administración de maestras |

Consola SQL local:

```powershell
.\scripts\psql.ps1
```

En Supabase, usar el **SQL Editor** del panel.

---

## Respaldos

### Producción (Supabase)

Revisar la retención del plan y exportar periódicamente con `pg_dump` usando la
cadena de conexión de Supabase. Guardar el archivo fuera de Supabase y probar la
restauración. Ver [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

### Desarrollo local

```powershell
.\scripts\backup.ps1
```

Genera en `db/backups/`:

- `myra_YYYYMMDD_HHmmss.dump` → PostgreSQL local (`pg_dump -Fc`)
- `credentials_YYYYMMDD_HHmmss.json` → credenciales de n8n (cifradas con la key)
- Actualiza `n8n/workflows/*.json`

Retención automática: 14 días. **No** se versionan los respaldos.

---

## Producción (n8n Cloud + Supabase)

La producción **no** usa servidor Linux, VPS, Nginx, Caddy, Cloudflare Tunnel ni
Docker Compose. Se compone de:

- **n8n Cloud:** workflows, credenciales, webhook HTTPS estable.
- **Supabase:** PostgreSQL administrado para los datos del negocio.
- **`[MYRA] 08 · Heartbeat`:** workflow cada 3 días para evitar la pausa por
  inactividad de Supabase.
- **Telegram, Gemini y Groq:** se conectan desde n8n Cloud con sus credenciales.

Pasos resumidos:

1. Crear el proyecto en Supabase y aplicar `db/migrations/`.
2. Importar los workflows en n8n Cloud y recrear las credenciales.
3. Publicar los sub-workflows y activar WF-01.
4. Configurar el heartbeat y verificar que envíe alertas si falla.
5. Ejecutar las pruebas manuales de [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

Guía completa: [`docs/04-despliegue-cloud.md`](docs/04-despliegue-cloud.md).

---

## Seguridad

- `.env` está en `.gitignore`. No lo subas nunca.
- En producción, las credenciales viven en n8n Cloud: Telegram, Gemini, Groq y la
  cadena de conexión de Supabase.
- La contraseña `postgres` es solo para desarrollo local. No usar esa contraseña en
  Supabase.
- No guardar la `service_role` key de Supabase en n8n ni en el repositorio. El nodo
  Postgres usa la cadena de conexión, no las API keys.
- Habilitar 2FA en n8n Cloud y Supabase; limitar quién administra las cuentas.
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

En desarrollo local:

1. Verifica que `WEBHOOK_URL` en `.env` sea la URL pública actual.
2. Ejecuta `.\scripts\tunnel.ps1` de nuevo (la URL del túnel cambia).
3. Revisa en n8n: **Workflow → Telegram Trigger → Webhook** y los logs de ejecución.

En producción (n8n Cloud):

1. Revisa que WF-01 esté activo.
2. Revisa que el Telegram Trigger escuche `message` y `callback_query`.
3. Revisa las ejecuciones de n8n Cloud.
4. Revisa que Supabase no esté pausado.

### Supabase aparece pausado

El plan gratuito se pausa por inactividad. Revisar el workflow
`[MYRA] 08 · Heartbeat` y reactivar el proyecto desde el panel de Supabase. Después,
verificar que el heartbeat vuelva a ejecutarse.

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
- [x] Compose unificado para desarrollo local (PostgreSQL + n8n)
- [x] Esquema dividido en migraciones
- [x] WF-00 Maestras
- [x] WF-01 Telegram Router
- [x] WF-02 Voz → Texto
- [x] WF-03 Extracción
- [x] WF-04 Confirmación y persistencia
- [x] WF-05 Comandos
- [x] WF-06 Exportaciones
- [x] WF-07 Maestras (alta de proyectos)
- [ ] WF-07 edición/desactivación de proyectos
- [ ] WF-08 Errores
- [ ] WF-09 Heartbeat
- [ ] Despliegue en n8n Cloud + Supabase
