# Despliegue en n8n Cloud + Supabase

Este documento describe el despliegue de producción actual. Ya **no** se usa el
servidor de la UCN, un VPS propio, Nginx/Caddy ni el túnel de Cloudflare para
producción.

La arquitectura de producción es:

```text
Telegram
   │  HTTPS (webhook)
   ▼
n8n Cloud  ──────►  Gemini / Groq (LLM y STT)
   │
   │  PostgreSQL con SSL
   ▼
Supabase (PostgreSQL administrado)
   ▲
   │  heartbeat cada 3 días
   └── workflow [MYRA] 08 · Heartbeat
```

> Docker Compose y PostgreSQL local se mantienen **solo para desarrollo**. No son
> parte del despliegue de producción.

## 1. Cuentas necesarias

| Servicio | Uso | Nota |
|---|---|---|
| n8n Cloud | Orquestador y webhooks | El trial es de 14 días y 1.000 ejecuciones; luego se pasa a Starter/Pro |
| Supabase | PostgreSQL administrado | El plan gratuito se pausa por inactividad; se evita con el heartbeat |
| Telegram | Bot y webhook | El token va en la credencial de n8n Cloud |
| Google Gemini | Extracción de datos | Mantener la credencial de la instancia actual |
| Groq | Transcripción de voz | Mantener la credencial de la instancia actual |

Las cuentas deben quedar a nombre de una persona responsable del cliente o del
equipo, no en una cuenta personal que se vaya a perder.

## 2. Supabase

### 2.1 Crear el proyecto

1. Crear un proyecto en Supabase.
2. Guardar la contraseña de la base en un lugar seguro.
3. Elegir la región más cercana a los usuarios.
4. Confirmar que el proyecto no quede en pausa por inactividad.

### 2.2 Obtener la conexión para n8n

En Supabase: **Project Settings → Database → Connection string**.

Para n8n se recomienda la cadena del **Session Pooler** (IPv4, SSL obligatorio), no
la conexión directa. n8n Cloud se conecta como un cliente PostgreSQL normal.

Formato aproximado:

```text
postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
```

No usar la `service_role` key de Supabase en n8n. El nodo Postgres usa la cadena de
conexión, no las API keys.

### 2.3 Aplicar migraciones

Ejecutar los archivos de `db/migrations/` en orden, desde el **SQL Editor** de
Supabase o con `psql` usando la cadena de conexión:

```text
000_migrations.sql
001_schema_inicial.sql
002_seed_catalogos.sql
003_fuzzy_proyectos.sql
004_admin_pending.sql
005_admin_modo.sql
006_idempotencia_telegram.sql
```

Verificar que quedaron registrados:

```sql
SELECT filename FROM schema_migrations ORDER BY filename;
```

Si se usa `psql`:

```bash
psql "postgresql://.../postgres?sslmode=require" -v ON_ERROR_STOP=1 -f db/migrations/001_schema_inicial.sql
```

### 2.4 Cargar datos iniciales

Cargar clientes, proyectos, alias y el usuario de Telegram. El seed de desarrollo
`db/seeds/dev_demo.sql` tiene un `chat_id` de ejemplo; en producción hay que
reemplazarlo por el real.

```sql
INSERT INTO usuarios (telegram_chat_id, nombre, rol)
VALUES (123456789, 'Nombre real', 'jefe_obra')
ON CONFLICT (telegram_chat_id) DO NOTHING;
```

### 2.5 Respaldos

Revisar qué retención de backups incluye el plan de Supabase. Si no es suficiente:

- exportar periódicamente con `pg_dump`,
- guardar el archivo fuera de Supabase,
- probar una restauración antes de darla por válida.

No basta con que Supabase tenga el proyecto: hay que tener una copia recuperable.

## 3. n8n Cloud

### 3.1 Crear la instancia

1. Crear la instancia en n8n Cloud.
2. Anotar la URL HTTPS estable.
3. Configurar 2FA y invitar solo a las personas necesarias.

### 3.2 Importar workflows

1. Importar los JSON de `n8n/workflows/` desde **Workflows → Import from File**.
2. Recrear las credenciales en n8n Cloud:
   - Telegram
   - Google Gemini
   - Groq
   - Postgres (Supabase)
3. Asignar las credenciales nuevas a cada nodo. Los IDs de credenciales del entorno
   local **no** se importan.
4. Publicar también los sub-workflows. En n8n Cloud no existe el comando local
   `publish:workflow`; se hace desde la UI.
5. Activar WF-01 y verificar que el Telegram Trigger registre el webhook.

Los IDs de workflows y credenciales de la instancia local no sirven en Cloud. Hay que
remapear los nodos `Execute Workflow` y las credenciales después de importar.

### 3.3 Webhook de Telegram

No se usa Cloudflare Tunnel. n8n Cloud entrega una URL HTTPS fija:

```text
https://<instancia>.app.n8n.cloud/webhook/<id>
```

Al activar el Telegram Trigger, n8n registra el webhook contra Telegram. Si el bot no
responde:

1. Revisar que WF-01 esté activo.
2. Revisar que el Telegram Trigger escuche `message` y `callback_query`.
3. Revisar el estado del webhook en el nodo.
4. Revisar las ejecuciones de n8n Cloud.

### 3.4 Límites de ejecución

- El trial tiene 1.000 ejecuciones.
- Los sub-workflows no consumen el límite mensual del plan.
- WF-01 sí consume una ejecución por mensaje recibido.
- Revisar el límite del plan antes de usarlo con varios usuarios.

### 3.5 Retención de audios

Aunque la base no guarde el audio, n8n Cloud puede conservar el binario en el
historial de ejecuciones. Si el cliente no quiere retener audios, revisar la
configuración de guardado de ejecuciones exitosas y la retención del plan.

## 4. Heartbeat para evitar la pausa de Supabase

El plan gratuito de Supabase pausa el proyecto después de **7 días sin actividad**
(verificar la política vigente al momento de contratar). Para un cliente sin soporte
informático, eso significa que el bot puede dejar de funcionar después de unas
vacaciones.

Crear un workflow independiente:

```text
[MYRA] 08 · Heartbeat
Schedule Trigger (cada 3 días)
   → Postgres: SELECT 1;
   → IF error → Telegram al administrador
```

Si Supabase no considera suficiente una consulta de solo lectura, usar una escritura
explícita con la tabla `heartbeat`:

```sql
INSERT INTO heartbeat (id, last_ping)
VALUES (1, now())
ON CONFLICT (id) DO UPDATE SET last_ping = now();
```

Si se usa la tabla `heartbeat`, agregarla con una migración nueva.

Reglas:

- Mantener el workflow activo.
- Que el error del heartbeat llegue a una persona real.
- No confundir el heartbeat con los backups: son cosas distintas.
- Si n8n Cloud queda sin plan o sin pago, el heartbeat también se detiene.

## 5. Migración desde el entorno local

1. Exportar los workflows actuales a `n8n/workflows/`.
2. Crear el proyecto Supabase y aplicar migraciones.
3. Importar los workflows en n8n Cloud.
4. Recrear credenciales y remapear IDs.
5. Publicar WF-00, WF-02, WF-03 y WF-04.
6. Configurar y activar el heartbeat.
7. Ejecutar las pruebas manuales.

No copiar `n8n/data/` desde el PC a n8n Cloud. Esa carpeta contiene SQLite,
credenciales locales y storage de ejecuciones; en Cloud no aplica.

## 6. Pruebas mínimas después del despliegue

- [ ] Texto completo: crea registro y pide confirmación.
- [ ] Texto incompleto: pregunta el dato faltante.
- [ ] Voz completa: transcribe y sigue el flujo.
- [ ] Voz incompleta: pide el dato faltante.
- [ ] Audio en silencio o ruidoso: responde error de STT y no crea gasto.
- [ ] Corrección puntual: cambia solo el dato indicado.
- [ ] Confirmar: inserta el gasto una sola vez.
- [ ] Doble confirmación: no duplica.
- [ ] Cancelar: deja el registro cancelado.
- [ ] Usuario no autorizado: no accede a la IA ni a la base.
- [ ] Mensaje fuera de contexto: no crea gasto.
- [ ] `/start`, `/proyectos`, `/resumen`, `/ultimos`, `/ayuda`: responden con datos.
- [ ] `/help` y `/h`: muestran la ayuda.
- [ ] Un saludo como “hola” abre el menú de `/start`.
- [ ] Un saludo con datos de gasto, por ejemplo “hola, gasté 3.000 en Copec”, sigue el flujo de extracción.
- [ ] Los botones inline ejecutan el comando y editan el mensaje.
- [ ] `/cancelar`: cancela el registro pendiente.
- [ ] `/maestras`: solo administradores pueden crear proyectos.
- [ ] Alta de proyecto con cliente existente, alias y confirmación final.
- [ ] Heartbeat: ejecución exitosa y sin pausa de Supabase.

## 7. Operación

| Tema | Responsable |
|---|---|
| Cuenta y pago de n8n Cloud | Dueño del proyecto/cliente |
| Proyecto y backups de Supabase | Dueño del proyecto/cliente |
| Credenciales de Telegram/Gemini/Groq | Equipo técnico |
| Revisión de ejecuciones fallidas | Equipo técnico |
| Respuesta a pausa de Supabase | Alerta del heartbeat |

Revisar mensualmente:

- ejecuciones fallidas,
- límite de ejecuciones del plan,
- espacio y salud de Supabase,
- backups,
- cuotas de Gemini/Groq,
- vigencia de tokens y credenciales.

## 8. Lo que ya no se usa en producción

- Servidor Linux de la UCN.
- VPS propio.
- Docker Compose en producción.
- Nginx/Caddy.
- Cloudflare Tunnel o `trycloudflare.com`.
- Los scripts Linux del despliegue anterior (eliminados).
- `n8n/data/` como fuente de producción.

Estos elementos pueden seguir existiendo para desarrollo local o como referencia
histórica, pero no son parte del despliegue actual.
