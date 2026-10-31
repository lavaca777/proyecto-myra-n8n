# WF-02 · Voz → Texto

Documento de handoff para implementar el flujo de notas de voz de Telegram.

## 1. Objetivo

Recibir una nota de voz, transcribirla con Gemini y entregarle el texto a WF-03 para
que siga el mismo camino que un mensaje de texto: extracción, fuzzy match de proyecto,
confirmación y persistencia.

WF-02 **no crea gastos ni registros** en `registros_entrada`. Solo transforma audio en
texto y llama a WF-03. El dueño de WF-03 es quien mantiene la lógica de estado.

## 2. Estado actual

- WF-01 ya normaliza los mensajes de voz y los marca como `tipo = 'voz'`.
- El Router de WF-01 tiene 5 salidas. La salida **2 (voz)** hoy va a un placeholder
  (`Armar respuesta`).
- WF-03 ya funciona para texto, incluyendo:
  - extracción con Gemini,
  - continuación de un registro pendiente (`falta_dato`),
  - fuzzy match de proyecto,
  - confirmación y persistencia.
- La tabla `registros_entrada` ya soporta `tipo = 'voz'`, `telegram_file_id` y
  `duracion_ms`.

## 3. Contrato de entrada

WF-01 entrega un ítem como este:

```json
{
  "tipo": "voz",
  "telegram_chat_id": 8907302907,
  "telegram_user_id": 8907302907,
  "telegram_message_id": 123,
  "texto": "",
  "comando": null,
  "callback_data": null,
  "file_id": "AgACAgEAAxkBAA...",
  "duracion_seg": 12,
  "nombre_usuario": "Carlos Tapia",
  "update_id": 123456,
  "usuario": {
    "id": 1,
    "nombre": "Usuario Demo",
    "rol": "jefe_obra"
  },
  "autorizado": true
}
```

## 4. Contrato de salida hacia WF-03

WF-02 debe devolver el mismo ítem, agregando:

```json
{
  "tipo": "voz",
  "texto": "Anota doce mil quinientos en Copec, pagué con débito...",
  "duracion_ms": 12000
}
```

- `texto` es la transcripción.
- `tipo` debe seguir siendo `voz`.
- `file_id` y `duracion_seg` se conservan.
- WF-03 usará `texto`, `tipo`, `file_id` y `duracion_ms`.

## 5. Nodos de WF-02

Workflow nuevo: `[MYRA] 02 · Voz a Texto`.
Tipo: sub-workflow (`Execute Workflow Trigger`).

### 5.1 `Cuando se ejecuta`

- Nodo: Execute Workflow Trigger.
- `inputSource`: `passthrough`.
- typeVersion: `1.2`.

### 5.2 `Descargar audio`

- Nodo: Telegram.
- Recurso: `file`.
- Operación: `getFile`.
- `fileId`: `={{ $json.file_id }}`.
- `download`: `true`.
- Credencial: `Telegram account`.
- Salida: binario en la propiedad `data`.

### 5.3 `Preparar audio`

Nodo Code. Convierte el binario a base64 y conserva el ítem original:

```js
const base = $('Cuando se ejecuta').first().json;
const buffer = await this.helpers.getBinaryDataBuffer(0, 'data');
const binario = items[0].binary.data;

return [{
  json: {
    ...base,
    audio_base64: buffer.toString('base64'),
    mime_type: binario.mimeType || 'audio/ogg'
  }
}];
```

### 5.4 `Transcribir con Gemini`

Nodo HTTP Request:

- Método: `POST`.
- URL:
  ```text
  https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent
  ```
- Autenticación: `Predefined Credential Type` → `Google Gemini(PaLM) API`.
  - Si el nodo HTTP Request no ofrece esa credencial, usar el nodo de Gemini que
    soporte audio o consultar al dueño del proyecto antes de hardcodear una API key.
- Body JSON:

```json
{
  "contents": [{
    "parts": [
      {
        "text": "Transcribe literalmente este audio en español de Chile. No resumas, no interpretes. Devuelve solo la transcripción."
      },
      {
        "inline_data": {
          "mime_type": "{{ $json.mime_type }}",
          "data": "{{ $json.audio_base64 }}"
        }
      }
    ]
  }],
  "generationConfig": {
    "temperature": 0
  }
}
```

**Riesgo de formato:** Telegram entrega OGG/Opus. Si Gemini responde `400` por el
formato, hay que convertir a WAV/MP3 o usar un STT alternativo. No asumir que funciona
hasta probarlo con una nota de voz real.

### 5.5 `Extraer transcripcion`

Nodo Code:

```js
const base = $('Preparar audio').first().json;
const response = $input.first().json;
const texto = response.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || '';

if (!texto) {
  throw new Error('No se pudo transcribir el audio');
}

return [{
  json: {
    ...base,
    texto,
    tipo: 'voz',
    duracion_ms: (base.duracion_seg || 0) * 1000
  }
}];
```

### 5.6 `Enviar a extraccion`

Nodo Execute Workflow:

- Workflow: `[MYRA] 03 · Extracción`.
- ID de WF-03: `1232930e-38d8-4f18-b5a4-667760438170`.
- Source: `database`.
- Mode: `once`.
- Entrada: el ítem de `Extraer transcripcion`.

WF-03 hará el resto: crea/continúa el registro, extrae los campos, pregunta lo que
falta o envía la confirmación.

## 6. Cambios de integración

### 6.1 WF-01

Agregar un nodo Execute Workflow `Enviar a voz`:

- Workflow: `[MYRA] 02 · Voz a Texto`.
- Source: `database`.
- Mode: `once`.

Cambiar la conexión del Router:

- Salida **2 (voz)** → `Enviar a voz`.
- La salida 2 hoy va a `Armar respuesta`; reemplazarla.

El resto del Router queda igual:

| Salida | Tipo | Destino |
|---|---|---|
| 0 | texto | `Enviar a extraccion` (WF-03) |
| 1 | comando | `Comando` |
| 2 | voz | `Enviar a voz` (WF-02) |
| 3 | callback | `Enviar a confirmacion` (WF-04) |
| 4 | foto | `Armar respuesta` (placeholder) |

### 6.2 WF-03

WF-03 hoy crea el registro con `tipo = 'texto'` fijo. Hay que cambiarlo para que use
los datos del ítem de entrada. Es un cambio pequeño y compatible con texto:

```sql
INSERT INTO registros_entrada (
  usuario_id, tipo, telegram_message_id, telegram_file_id,
  transcripcion, duracion_ms, estado
)
VALUES ($1, $2, $3, $4, $5, $6, 'procesando')
RETURNING id;
```

Query parameters:

```text
={{ [
  $('Cuando se ejecuta').first().json.usuario.id,
  $('Cuando se ejecuta').first().json.tipo,
  $('Cuando se ejecuta').first().json.telegram_message_id,
  $('Cuando se ejecuta').first().json.file_id,
  $('Cuando se ejecuta').first().json.texto,
  $('Cuando se ejecuta').first().json.duracion_ms
] }}
```

Para texto, `tipo='texto'`, `file_id=null` y `duracion_ms=null`; el resto del flujo no
cambia.

No crear un registro en WF-02: WF-03 es el único dueño de `registros_entrada`.

## 7. Manejo de errores

- Si falla la descarga del archivo: responder “No pude descargar el audio” y no llamar
  a WF-03.
- Si la transcripción viene vacía o Gemini falla: responder “No pude escuchar bien.
  Intenta de nuevo o escribe el gasto” y no llamar a WF-03.
- Si el audio dura más de 60 segundos: opcionalmente rechazarlo con un mensaje claro
  (el charter apunta a notas cortas).
- No guardar nada en `gastos` desde WF-02.
- Si se usa `On Error: Continue`, agregar una salida de error explícita para responder
  al usuario y cortar el flujo.

## 8. Pruebas

1. **Voz completa**
   - “Anota 12.500 en Copec, pagué con débito, obra Peñuelas, cargué bencina.”
   - Esperado: extracción de los 5 campos y confirmación.

2. **Voz sin proyecto**
   - “Anota 12.500 en Copec, pagué con débito, cargué bencina.”
   - Esperado: pregunta por el proyecto.
   - Luego responder por texto “Peñuelas” y verificar que **continúa el mismo registro**
     (no crea otro).

3. **Voz con ruido**
   - Verificar que la transcripción sea aceptable o que el bot pida repetir.

4. **Voz fuera de contexto**
   - “Hola, ¿cómo estás?”
   - Esperado: “No pude identificar un gasto…”, sin crear un gasto.

5. **Audio largo**
   - Más de 60 segundos: verificar el comportamiento definido (procesar o rechazar).

6. **Verificación en base**

```sql
SELECT id, tipo, telegram_file_id, duracion_ms, estado, campo_pendiente,
       left(transcripcion, 80) AS transcripcion,
       json_extraido->>'proyecto_nombre' AS proyecto,
       json_extraido->>'monto_total' AS monto
FROM registros_entrada
ORDER BY id DESC
LIMIT 5;
```

Debe aparecer `tipo='voz'`, `telegram_file_id` no nulo y `duracion_ms` aproximado a la
duración del audio.

## 9. Criterios de aceptación

- [ ] Una nota de voz se transcribe y sigue el mismo flujo que un texto.
- [ ] Se conserva `tipo='voz'`, `file_id` y `duracion_ms` en `registros_entrada`.
- [ ] No se crea un registro duplicado al continuar un gasto pendiente.
- [ ] Los 5 campos se extraen y confirman igual que en texto.
- [ ] Un audio fuera de contexto no genera un gasto.
- [ ] Un error de STT responde al usuario y no deja el flujo colgado.

## 10. Publicación y export

- En n8n 2.x, `Test workflow` usa el **draft**; el bot activo usa la **versión
  publicada**. Después de crear/cambiar WF-02, publicarlo.
- Si `Execute Workflow` responde “Workflow is not active and cannot be executed”,
  revisar que WF-02 esté publicado y que exista el mapeo de versión publicado.
- Al terminar, exportar el workflow a `n8n/workflows/`:

```powershell
.\scripts\export-workflows.ps1
```

- No subir credenciales, tokens ni `.env` al repositorio.

## 11. IDs y credenciales

| Elemento | Valor |
|---|---|
| n8n | `2.42.6` en `http://localhost:5678` |
| WF-01 Router | `0af28059-7545-448c-9aa6-1dd7927e79a4` |
| WF-03 Extracción | `1232930e-38d8-4f18-b5a4-667760438170` |
| Credencial Telegram | `Telegram account` (`telegramApi`) |
| Credencial Gemini | `Google Gemini(PaLM) Api account` (`googlePalmApi`) |
| Credencial Postgres | `Postgres account` (`postgres`) |

No incluir tokens ni claves en este documento ni en el repositorio.

## 12. Entregable

- Workflow `[MYRA] 02 · Voz a Texto` creado y publicado.
- ID de WF-02 informado para conectarlo desde WF-01.
- Cambio de `Crear registro` en WF-03 aplicado (o coordinado con su dueño).
- Pruebas 1 a 4 ejecutadas.
- JSON exportado a `n8n/workflows/`.
