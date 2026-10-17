# Diseño de flujos

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
| 4 | `¿Autorizado?` | IF | `usuario.id` existe |
| 5 | `Responder no autorizado` | Telegram | Mensaje simple; fin |
| 6 | `Router` | Switch | Por `tipo`: `comando`, `callback`, `voz`, `texto`, `foto` |
| 7 | `→ WF-02` | Execute Workflow | Voz |
| 8 | `→ WF-05` | Execute Workflow | Comando |
| 9 | `→ WF-04` | Execute Workflow | Callback o texto con estado pendiente |
| 10 | `→ WF-03` | Execute Workflow | Texto nuevo sin estado pendiente |
| 11 | `→ WF-06` | Execute Workflow | Foto (Could) |

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

> **Importante:** el Telegram Trigger actual solo escucha `message`. Hay que agregar
> `callback_query` o los botones de confirmación no llegarán nunca.

---

## WF-02 · Voz → Texto

**Tipo:** sub-workflow
**Entrada:** `{ registro_id, file_id, usuario_id, chat_id }`

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `Ejecutar` | Execute Workflow Trigger | Input del router |
| 2 | `Descargar audio` | Telegram | Recurso `file`, operación `getFile`, `fileId`, **Download = true** |
| 3 | `Convertir a base64` | Code | `Buffer.from($binary.data.data).toString('base64')` |
| 4 | `Transcribir (Gemini)` | HTTP Request | Ver request abajo |
| 5 | `Extraer texto` | Code | `candidates[0].content.parts[0].text` |
| 6 | `Guardar transcripción` | Postgres | `UPDATE registros_entrada SET transcripcion=$2, duracion_ms=$3 WHERE id=$1` |
| 7 | `→ WF-03` | Execute Workflow | Pasar `registro_id`, `texto`, `usuario_id`, `chat_id` |

### Request de transcripción

```http
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
Content-Type: application/json

{
  "contents": [{
    "parts": [
      { "text": "Transcribe literalmente este audio en español de Chile. No resumas, no interpretes. Devuelve solo la transcripción." },
      { "inline_data": { "mime_type": "audio/ogg", "data": "{{ $json.audio_base64 }}" } }
    ]
  }],
  "generationConfig": { "temperature": 0 }
}
```

Consideraciones:

- La credencial de Gemini se puede usar como *Predefined Credential* en el nodo
  HTTP Request. Si no aparece, guarda la API key en `.env` como `GEMINI_API_KEY`.
- Telegram entrega **OGG/Opus**. Si Gemini rechaza el formato, convertir con ffmpeg
  a `audio/wav` o usar Whisper como respaldo.
- Registrar `modelo_ia` en `registros_entrada` para comparar precisión entre modelos.
- Si la transcripción falla, responder: "No pude escuchar bien. ¿Puedes repetirlo o
  escribirlo?" y dejar el registro en `error`.

---

## WF-03 · Extracción

**Tipo:** sub-workflow
**Entrada:** `{ registro_id, texto, usuario_id, chat_id }`
**Salida:** mensaje de confirmación o pregunta por el campo faltante.

### Nodos

| # | Nodo | Tipo | Detalle |
|---|---|---|---|
| 1 | `Ejecutar` | Execute Workflow Trigger | |
| 2 | `→ WF-00 Maestras` | Execute Workflow | Trae proyectos, medios de pago y categorías |
| 3 | `Crear registro` | Postgres | `INSERT INTO registros_entrada (... estado='procesando') RETURNING id` (si no existe) |
| 4 | `Armar prompt` | Set / Code | Inyecta catálogos + texto + fecha de hoy |
| 5 | `Extraer JSON (Gemini)` | HTTP Request / LLM Chain | `response_mime_type: application/json` |
| 6 | `Parsear JSON` | Code | Limpia ```json, valida tipos, calcula faltantes |
| 7 | `Buscar proyecto` | Postgres | Fuzzy SQL de WF-00 |
| 8 | `Resolver proyecto` | Code | Aplica reglas de confianza/ambigüedad |
| 9 | `Normalizar datos` | Code | Monto CLP, fecha ISO, medio de pago, categoría |
| 10 | `Guardar borrador` | Postgres | `UPDATE registros_entrada SET json_extraido=$2, estado=$3, campo_pendiente=$4` |
| 11 | `¿Faltan datos?` | IF | |
| 12 | `Preguntar campo` | Telegram | Una sola pregunta directa |
| 13 | `Pedir confirmación` | Telegram | Resumen + botones inline |

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
**Entrada:** `{ tipo, registro_id?, callback_data?, texto?, chat_id, usuario_id }`

### 4.1 Callback

| `callback_data` | Acción |
|---|---|
| `confirm:<id>` | Validar y persistir |
| `edit:<id>` | Preguntar qué campo corregir y guardar `campo_pendiente` |
| `cancel:<id>` | `estado='cancelado'` + mensaje |

### 4.2 Texto o voz con estado pendiente

1. Buscar el último `registros_entrada` del usuario con
   `estado IN ('falta_dato','pendiente_confirmacion')`.
2. Si no hay, tratarlo como gasto nuevo (→ WF-03).
3. Si hay y `campo_pendiente` está definido, actualizar ese campo con el nuevo texto
   o audio.
4. Volver a validar y mostrar el resumen.

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

Si no devuelve fila:

- El registro ya estaba confirmado → responder "Este gasto ya estaba registrado".
- O faltan datos → no se actualizó `reg`; volver a validar.

Después, si hay comprobante (foto), insertar en `comprobantes` con el `gasto_id`.

---

## WF-05 · Comandos

**Tipo:** sub-workflow
**Entrada:** `{ comando, chat_id, usuario_id, rol }`

| Comando | Respuesta |
|---|---|
| `/start` | Bienvenida + ejemplo de uso + proyectos disponibles |
| `/proyectos` | Lista de proyectos activos con alias |
| `/resumen` | Total del mes por proyecto (usar `v_gastos_detalle`) |
| `/ultimos` | Últimos 5 gastos del usuario |
| `/cancelar` | Cancela el registro pendiente |
| `/ayuda` | Lista de comandos |

### SQL de `/resumen`

```sql
SELECT proyecto,
       COUNT(*) AS compras,
       SUM(monto_total) AS total
FROM v_gastos_detalle
WHERE fecha_gasto >= date_trunc('month', current_date)
GROUP BY proyecto
ORDER BY total DESC;
```

### SQL de `/ultimos`

```sql
SELECT fecha_gasto, proyecto, proveedor, monto_total, medio_pago
FROM v_gastos_detalle
WHERE registrado_por = $1
ORDER BY registrado_en DESC
LIMIT 5;
```

`/resumen` y `/proyectos` solo para roles `administrador` y `gerencia` si se decide
restringir; para el prototipo se pueden dejar abiertos a todos los usuarios activos.

---

## WF-06 · OCR de comprobantes (Could)

**Tipo:** sub-workflow
**Entrada:** `{ file_id, chat_id, usuario_id }`

1. Telegram `getFile` con Download.
2. Gemini Vision (`inline_data` con `image/jpeg`).
3. Prompt: extraer RUT del proveedor, folio, fecha, monto total y tipo de documento.
4. Combinar con el texto que acompañe la foto (si existe).
5. Seguir el mismo camino de WF-03 y WF-04.
6. Guardar `telegram_file_id` y `texto_ocr` en `comprobantes`.

No es requisito del MVP. Se implementa después de estabilizar voz.

---

## WF-07 · Errores

**Tipo:** workflow con `Error Trigger`
**Responsabilidad:** centralizar fallos.

1. `Error Trigger` recibe `workflow`, `execution`, `trigger`.
2. Code: extrae `execution.id`, `workflow.name`, `lastNodeExecuted`, mensaje.
3. Postgres: registra en `registros_entrada.error_detalle` si hay `registro_id`; si no,
   solo log estructurado.
4. Telegram: avisa a todos los usuarios con rol `administrador` o `gerencia`.
5. Opcional: responder al chat de origen con un mensaje genérico.

En n8n: **Settings → Error Workflow → `[MYRA] 07 · Errores`** en cada workflow.

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

Criterios del charter a verificar:

- 100% de los gastos con `proyecto_id`.
- Tiempo de registro < 60 s.
- Precisión de extracción > 80% en audios con ruido moderado.
