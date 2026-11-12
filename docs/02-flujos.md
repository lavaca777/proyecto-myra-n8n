# Diseño de flujos

> **Producción actual:** la base es PostgreSQL administrado en Supabase. Los nodos `Postgres` y las consultas SQL de este documento se mantienen; solo cambia la conexión/credencial.

Este documento es la especificación para construir los workflows en n8n. El orden
recomendado es: **00 → 01 → 03 (solo texto) → 04 → 02 (voz) → 05 → 06 → 07**.

Convención de nombres: `[MYRA] NN · Nombre`. Tags: `modulo:*` y `estado:dev`.

---

## WF-00 · Maestras

**Tipo:** sub-workflow (`Execute Workflow Trigger`)
**Responsabilidad:** entregar catálogos y validar usuarios.

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `Cuando se ejecuta` | Execute Workflow Trigger | Input: `{ accion, chat_id? }` |
| 2 | `Proyectos activos` | Postgres | SQL de abajo |
| 3 | `Medios de pago` | Postgres | `SELECT id, nombre FROM medios_pago WHERE activo ORDER BY nombre` |
| 4 | `Categorías del bot` | Postgres | `SELECT id, nombre FROM categorias WHERE activo AND usa_bot ORDER BY nombre` |
| 5 | `Usuario (opcional)` | Postgres | Solo si viene `chat_id` |
| 6 | `Armar catálogo` | Code | Devuelve `{ proyectos, medios_pago, categorias, usuario }` |

### SQL de proyectos (con alias)

```sql
SELECT p.id,
       p.nombre,
       c.nombre AS cliente,
       COALESCE(
         json_agg(pa.alias ORDER BY pa.alias) FILTER (WHERE pa.alias IS NOT NULL),
         '[]'::json
       ) AS alias
FROM proyectos p
JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN proyecto_alias pa ON pa.proyecto_id = p.id
WHERE p.activo
GROUP BY p.id, p.nombre, c.nombre
ORDER BY p.nombre;
```

### Búsqueda fuzzy (se usa en WF-03)

```sql
WITH candidatos AS (
  SELECT p.id,
         p.nombre,
         c.nombre AS cliente,
         GREATEST(
           similarity(unaccent(lower(p.nombre)), unaccent(lower($1))),
           COALESCE(MAX(similarity(unaccent(lower(pa.alias)), unaccent(lower($1)))), 0)
         ) AS score
  FROM proyectos p
  JOIN clientes c ON c.id = p.cliente_id
  LEFT JOIN proyecto_alias pa ON pa.proyecto_id = p.id
  WHERE p.activo
  GROUP BY p.id, p.nombre, c.nombre
)
SELECT id, nombre, cliente, score
FROM candidatos
WHERE score >= 0.35
ORDER BY score DESC
LIMIT 3;
```

Regla: si el primer candidato tiene `score < 0.55`, **no** se asigna automáticamente;
se pregunta al usuario. Si hay dos candidatos con diferencia < 0.10, también se
pregunta (ambigüedad).

---

## WF-01 · Telegram Router

**Tipo:** workflow principal con Telegram Trigger
**Responsabilidad:** identificar al usuario y enrutar sin lógica de negocio.

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `Telegram Trigger` | Telegram Trigger | Updates: **`message` y `callback_query`** |
| 2 | `Normalizar update` | Code | Ver contrato abajo |
| 3 | `Buscar usuario` | Postgres | `SELECT id, nombre, rol FROM usuarios WHERE telegram_chat_id = $1 AND activo` |
| 4 | `Evaluar autorizacion` | Code | Normaliza el usuario encontrado y su rol |
| 5 | `Autorizado` | Switch | Autorizado → continuar; si no → `Responder no autorizado` |
| 6 | `Buscar admin pendiente` / `¿Admin pendiente?` | Postgres / Switch | Recupera la sesión de `admin_pending` |
| 7 | `Router` | Switch | Por `tipo`: `texto`, `comando`, `voz`, `callback`, `foto` |
| 8 | `Enviar a extraccion` | Execute Workflow | Texto nuevo o con gasto pendiente → WF-03 |
| 9 | `Enviar a comandos` | Execute Workflow | Comando o callback `cmd:*` → WF-05 |
| 10 | `Enviar a confirmacion` | Execute Workflow | Callback `confirm/edit/cancel` → WF-04 |
| 11 | `Call [MYRA] 02 · Voz a Texto` / `Voz como texto` | Execute Workflow / Code | Audio → WF-02; luego se enruta el texto |
| 12 | `Enviar a maestras` / `Enviar voz a maestras` | Execute Workflow | Sesión admin → WF-07/07A |
| 13 | `Armar respuesta` / `Responder generico` | Code / Telegram | Foto u otro tipo: OCR pendiente; pide texto o audio |

### Contrato del Code `Normalizar update`

```js
const update = $json;
const msg = update.message;
const cb = update.callback_query;

const from = (msg?.from) ?? (cb?.from);
const chatId = (msg?.chat?.id) ?? (cb?.message?.chat?.id);
const texto = msg?.text ?? '';
const esComando = texto.startsWith('/');

let tipo = 'texto';
if (cb) tipo = 'callback';
else if (msg?.voice) tipo = 'voz';
else if (msg?.photo) tipo = 'foto';
else if (esComando) tipo = 'comando';

return [{
  json: {
    tipo,
    telegram_chat_id: chatId,
    telegram_user_id: from?.id,
    telegram_message_id: msg?.message_id ?? cb?.message?.message_id,
    texto,
    comando: esComando ? texto.split(/\s+/)[0].replace('/', '').toLowerCase() : null,
    callback_data: cb?.data ?? null,
    file_id: msg?.voice?.file_id ?? null,
    duracion_seg: msg?.voice?.duration ?? null,
    nombre_usuario: [from?.first_name, from?.last_name].filter(Boolean).join(' '),
    update_id: update.update_id
  }
}];
```

> **Importante:** el Telegram Trigger ya escucha `message` y `callback_query`.
> Los callbacks `cmd:*`, `exp:*`, `adm:*` y `confirm:/edit:/cancel:` se normalizan antes de enrutar.

---

## WF-02 · Voz → Texto

**Tipo:** sub-workflow
**Entrada:** `{ file_id, duracion_seg, telegram_chat_id, telegram_message_id, usuario, nombre_usuario, autorizado }`
**Salida:** `{ ...entrada, texto_transcrito, transcripcion_ok, stt_no_speech_prob, stt_avg_logprob }`

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `When Executed by Another Workflow` | Execute Workflow Trigger | Recibe el audio desde WF-01 |
| 2 | `Descargar audio` | Telegram | Recurso `file`, operación `getFile`, **Download = true** |
| 3 | `Preparar audio` | Code | Valida binario, tamaño máximo 20 MB y MIME de audio; normaliza a OGG/Opus |
| 4 | `¿Audio válido?` | Switch | Válido → Groq; inválido → mensaje específico |
| 5 | `Transcribir con Groq` | HTTP Request | `whisper-large-v3`, `language=es`, `verbose_json`, temperatura 0 |
| 6 | `Extraer transcripcion` | Code | Obtiene `text`, `no_speech_prob` y `avg_logprob`; calcula `transcripcion_ok` |
| 7 | `Transcripcion OK?` | Switch | OK → devolver; error → mensaje |
| 8 | `Responder audio invalido` / `Responder error audio` | Telegram | Mensajes claros antes de terminar |
| 9 | `Devolver transcripcion` | Code | Devuelve el texto a WF-01 |

### Reglas

- Telegram entrega notas de voz OGG/Opus; Groq Whisper las acepta directamente.
- Si el archivo supera **20 MB**, no es audio o no se pudo descargar, se responde sin llamar a Groq.
- Se rechaza si `texto` está vacío, `no_speech_prob >= 0.5` o `avg_logprob <= -0.8`.
- WF-01 recibe el texto y decide el destino:
  - WF-03 si es un gasto normal.
  - WF-07A si el administrador está en modo maestras.
- `registros_entrada` se crea en WF-03, no aquí; allí se guardan `tipo`, `telegram_file_id` y `duracion_ms` (duración del audio).

---

## WF-03 · Extracción

**Tipo:** sub-workflow
**Entrada:** `{ texto, tipo, telegram_message_id, telegram_file_id?, duracion_ms?, usuario, telegram_chat_id }`
**Salida:** mensaje de confirmación o pregunta por el campo faltante.

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `Cuando se ejecuta` | Execute Workflow Trigger | Recibe el texto normalizado desde WF-01 |
| 2 | `Maestras` | Execute Workflow | Trae proyectos, medios de pago y categorías |
| 3 | `Buscar pendiente` | Postgres | Busca el último registro abierto del usuario |
| 4 | `Continuacion` | Switch | Corregir, recordar confirmación o crear registro |
| 5 | `Crear registro` | Postgres | Inserta `tipo`, `telegram_message_id`, `telegram_file_id`, `transcripcion`, `duracion_ms`; evita duplicados por mensaje |
| 6 | `¿Registro nuevo?` | Switch | Si el mensaje ya existía, ignora el duplicado |
| 7 | `Preparar contexto` | Code | Arma el texto y el estado de la conversación |
| 8 | `Preparar prompt` | Code | Inyecta catálogos + texto + fecha de hoy |
| 9 | `Extraer con Gemini` | LLM Chain | `response_mime_type: application/json` |
| 10 | `Armar extraccion` / `Normalizar extraccion` | Code | Parsea el JSON, valida tipos y normaliza montos/fechas |
| 11 | `Buscar proyecto` | Postgres | Fuzzy SQL de WF-00 |
| 12 | `Resolver proyecto` | Code | Aplica reglas de confianza/ambigüedad |
| 13 | `Decidir estado` / `Guardar borrador` | Code / Postgres | Define `estado` y `campo_pendiente`, y guarda el borrador |
| 14 | `¿Faltan datos?` | Switch | Pregunta, saluda, rechaza no-gasto o pide confirmación |
| 15 | `Enviar pregunta` / `Enviar confirmacion` | Telegram | Pregunta puntual o resumen con botones |
| 16 | `Responder no gasto` / `Enviar saludo` | Telegram / Execute Workflow | Salidas auxiliares |
| 17 | `Preguntar confirmacion pendiente` | Telegram | Recuerda confirmar el registro abierto |
| 18 | `Ignorar duplicado` | NoOp | No vuelve a escribir un mensaje ya procesado |

### Prompt de extracción

Ver [`docs/prompts/extraccion_gasto_v1.md`](prompts/extraccion_gasto_v1.md).
El prompt debe recibir:

- Texto transcrito.
- Fecha actual en `America/Santiago`.
- Lista de proyectos activos con alias.
- Medios de pago y categorías válidas.

### Contrato del JSON del LLM

```json
{
  "intencion": "saludo | gasto | otro",
  "proyecto": "Obra Peñuelas",
  "monto_total": 45990,
  "fecha": "2026-10-17",
  "proveedor": "Sodimac",
  "medio_pago": "Tarjeta de débito",
  "categoria": "Materiales",
  "descripcion": "Tornillos y silicona",
  "confianza": {
    "proyecto": 0.92,
    "monto_total": 0.99,
    "fecha": 1.0,
    "proveedor": 0.88,
    "medio_pago": 0.9
  }
}
```

`intencion` clasifica el mensaje como `saludo`, `gasto` u `otro`.

Reglas de normalización:

| Campo | Regla |
|---|---|
| `monto_total` | Entero CLP. "45 mil" → 45000; "45.990" → 45990; "cuarenta y cinco mil" → 45000 |
| `fecha` | ISO `YYYY-MM-DD`. "hoy"/"ayer" se resuelven en el Code node, no en el LLM |
| `proveedor` | Texto limpio, sin "en"/"de". Se crea si no existe |
| `medio_pago` | Debe coincidir con `medios_pago`; si no, se pregunta |
| `categoria` | Solo si `usa_bot = TRUE`; si no, `null` |
| `proyecto` | Debe existir en el catálogo o en alias; si no, se pregunta |

### Mensaje de confirmación

```text
Registraré este gasto:

🏗️ Proyecto: Obra Peñuelas
💵 Monto: $45.990
📅 Fecha: 17-10-2026
🏪 Proveedor: Sodimac
💳 Pago: Tarjeta de débito
📂 Categoría: Materiales

[ ✅ Confirmar ]  [ ✏️ Corregir ]  [ ❌ Cancelar ]
```

`callback_data`:

- `confirm:<registro_id>`
- `edit:<registro_id>`
- `cancel:<registro_id>`

---

## WF-04 · Confirmación y persistencia

**Tipo:** sub-workflow
**Entrada:** `{ registro_id?, callback_data, chat_id, usuario_id }`

### 4.1 Callback

| `callback_data` | Acción |
|---|---|
| `confirm:<id>` | Validar y persistir |
| `edit:<id>` | Preguntar qué campo corregir y guardar `campo_pendiente` |
| `cancel:<id>` | `estado='cancelado'` + mensaje |

### 4.2 Texto o voz con estado pendiente

El router envía el texto a WF-03, que busca el último `registros_entrada` del usuario
con `estado IN ('falta_dato','pendiente_confirmacion')`:

- Si hay `campo_pendiente`, actualiza ese campo con el nuevo texto o audio y vuelve a
  validar.
- Si está en `pendiente_confirmacion`, recuerda que debe confirmar con los botones.
- Si no hay registro pendiente, lo trata como un gasto nuevo.

WF-04 solo procesa callbacks; no recibe texto libre.

### 4.3 Persistencia atómica

El `INSERT` debe ser idempotente y no permitir confirmar dos veces. Una sola query:

```sql
WITH prov AS (
  INSERT INTO proveedores (nombre, nombre_normalizado)
  VALUES ($2, $3)
  ON CONFLICT (nombre_normalizado)
  DO UPDATE SET nombre = EXCLUDED.nombre
  RETURNING id
), reg AS (
  UPDATE registros_entrada
  SET estado = 'confirmado', campo_pendiente = NULL
  WHERE id = $1 AND estado = 'pendiente_confirmacion'
  RETURNING id, usuario_id, json_extraido
)
INSERT INTO gastos (
  proyecto_id, usuario_id, proveedor_id, medio_pago_id, categoria_id,
  descripcion, monto_total, fecha_gasto, origen, registro_entrada_id
)
SELECT $4, r.usuario_id, prov.id, $5, $6,
       $7, $8, $9, $10, r.id
FROM reg r CROSS JOIN prov
ON CONFLICT (registro_entrada_id) DO NOTHING
RETURNING id;
```

`origen` se toma de `registros_entrada.tipo` (`texto`, `voz` o `foto`), no de un
valor fijo. Si no devuelve fila:

- El registro ya estaba confirmado → responder "Este gasto ya estaba registrado".
- O faltan datos → no se actualizó `reg`; volver a validar.

El comprobante/OCR todavía no se persiste; queda pendiente para una iteración
posterior.

---

## WF-05 · Comandos

**Tipo:** sub-workflow
**Entrada:** `{ comando, chat_id, usuario_id, rol }`

| Comando | Respuesta |
|---|---|
| `/start` | Bienvenida + ejemplo + proyectos disponibles |
| `/proyectos` | Proyectos activos con alias |
| `/resumen` | Total del mes por proyecto; solo admin/gerencia |
| `/ultimos` | Últimos 5 del usuario; admin/gerencia ven todo el equipo |
| `/cancelar` | Cancela el gasto pendiente del usuario |
| `/exportar` o `/gastos` | Exporta todos los gastos en Excel/CSV; solo admin/gerencia |
| `/maestras` | Administración de proyectos; solo admin/gerencia |
| `/ayuda`, `/help`, `/h` | Ayuda según el rol |

Menús por rol:

- `jefe_obra`: Proyectos, Últimos, Cancelar, Ayuda.
- `administrador`/`gerencia`: Proyectos, Resumen, Últimos, Cancelar, Maestras, Exportar, Ayuda.

### SQL de `/resumen`

```sql
SELECT proyecto,
       COUNT(*)::int AS compras,
       SUM(monto_total)::bigint AS total
FROM v_gastos_detalle
WHERE fecha_gasto >= date_trunc('month', (now() AT TIME ZONE 'America/Santiago'))::date
GROUP BY proyecto
ORDER BY total DESC;
```

### SQL de `/ultimos`

```sql
SELECT g.fecha_gasto,
       p.nombre AS proyecto,
       pr.nombre AS proveedor,
       g.monto_total,
       mp.nombre AS medio_pago,
       u.nombre AS registrado_por
FROM gastos g
JOIN proyectos p ON p.id = g.proyecto_id
JOIN usuarios u ON u.id = g.usuario_id
LEFT JOIN proveedores pr ON pr.id = g.proveedor_id
LEFT JOIN medios_pago mp ON mp.id = g.medio_pago_id
WHERE (g.usuario_id = $1 OR $2::boolean)
  AND g.estado = 'confirmado'
ORDER BY g.registrado_en DESC
LIMIT 5;
```

`$1` es el usuario actual y `$2` indica si es admin/gerencia. `/cancelar` usa
`usuario.id` y cancela registros en `falta_dato` o `pendiente_confirmacion`.

---

## WF-06 · Exportaciones

**Tipo:** sub-workflow. **Solo `administrador` y `gerencia`.**
**Comando:** `/exportar` o su alias `/gastos`.

El flujo solo pregunta:

1. Formato: Excel (`.xlsx`) o CSV.
2. Rango: últimos 30 días o toda la tabla.

No se pregunta por proyecto: **siempre exporta todos los proyectos**. El archivo
incluye la columna Proyecto para filtrar en Excel. La consulta filtra gastos
confirmados y el rango de fechas.

### Columnas del archivo

ID, Fecha, Cliente, Proyecto, Categoría, Proveedor, Descripción,
Medio de pago, Monto, Registrado por y Origen.

### Consideraciones

- Los montos quedan como números para que Excel los sume.
- Las fechas se muestran como `dd-mm-aaaa`.
- Si no hay datos, se responde sin generar archivo.
- El CSV se genera en UTF-8; Excel es el formato recomendado.
- El rango de 30 días usa la fecha de `America/Santiago`.

---

## WF-07 · Administración de proyectos

> Diseño detallado: [`07-admin-proyectos.md`](07-admin-proyectos.md).

**Tipo:** tres workflows. **Solo `administrador` y `gerencia`.**

| Workflow | Responsabilidad |
|---|---|
| `[MYRA] 07 · Maestras` | Sesión, menú, callbacks, listado, cancelar y salir |
| `[MYRA] 07A · Interpretar operación` | LLM, parseo, fuzzy matching, validación y borrador |
| `[MYRA] 07B · Ejecutar operación` | Persistencia determinista y respuesta final |

Acepta texto y audio; WF-01 transcribe y envía el texto a 07A cuando hay una sesión
de administración activa.

Acciones:

- Crear proyecto (nombre, cliente, alias).
- Editar nombre y agregar alias.
- Desactivar o reactivar un proyecto.
- Desactivar/reactivar todos los proyectos de un cliente.
- Desactivar/reactivar todos los proyectos.
- Listar proyectos activos e inactivos.
- Salir del modo administración.

El estado de la operación vive en `admin_pending` y expira a las 2 horas. La
confirmación se hace con botones; la escritura solo ocurre al confirmar.

---

## WF-08 · Errores

**Estado:** pendiente de implementación.

**Tipo:** workflow con `Error Trigger`
**Responsabilidad:** centralizar fallos.

1. `Error Trigger` recibe `workflow`, `execution`, `trigger`.
2. Code: extrae `execution.id`, `workflow.name`, `lastNodeExecuted`, mensaje.
3. Postgres: registra en `registros_entrada.error_detalle` si hay `registro_id`; si no,
   solo log estructurado.
4. Telegram: avisa a todos los usuarios con rol `administrador` o `gerencia`.

En n8n: **Settings → Error Workflow → `[MYRA] 08 · Errores`** en cada workflow.

---

## WF-09 · Heartbeat

**Estado:** pendiente de implementación.

**Tipo:** workflow con `Schedule Trigger`
**Responsabilidad:** evitar la pausa por inactividad de Supabase.

1. `Schedule Trigger` cada 3 días.
2. Postgres: `SELECT 1;` o un upsert en una tabla `heartbeat`.
3. Si falla, avisar al administrador por Telegram.

---

## Plan de pruebas

| # | Caso | Resultado esperado |
|---|---|---|
| 1 | Texto con los 5 campos | Confirmación y gasto persistido |
| 2 | Texto sin proyecto | Pregunta solo por el proyecto |
| 3 | "la obra de Peñuelas" | Fuzzy match correcto o pregunta si es ambiguo |
| 4 | "45 mil" / "45.990" / "cuarenta y cinco mil" | `monto_total = 45000` / `45990` |
| 5 | "hoy" / "ayer" | Fecha correcta en `America/Santiago` |
| 6 | Proveedor nuevo | Se crea en `proveedores` sin duplicar |
| 7 | Doble clic en Confirmar | Un solo gasto; segundo mensaje "ya registrado" |
| 8 | Usuario no autorizado | Rechazo sin tocar la IA |
| 9 | Audio con ruido | Transcripción aceptable o reintento |
| 10 | Cancelar | `estado='cancelado'`, sin gasto |
| 11 | Corrección de un campo | Se actualiza y vuelve a confirmar |
| 12 | Reinicio de n8n en medio del flujo | El estado pendiente se conserva |
| 13 | Audio en modo maestras | Se transcribe y llega a 07A |
| 14 | Desactivar todos los proyectos de un cliente | Resumen + confirmación; solo cambia los activos |
| 15 | `/gastos` o `/exportar` | Pregunta formato y rango, exporta todos los proyectos |
| 16 | Mismo update de Telegram dos veces | Un solo `registro_entrada` |
| 17 | Fecha futura | Se rechaza y se pregunta la fecha |
| 18 | Audio de más de 20 MB | Mensaje claro, sin llamar a Groq |

Criterios del charter a verificar:

- 100% de los gastos con `proyecto_id`.
- Tiempo de registro < 60 s.
- Precisión de extracción > 80% en audios con ruido moderado.
