# WF-02 · Voz → Texto

Documento de referencia del flujo de notas de voz de Telegram.

## 1. Objetivo

Recibir una nota de voz, validarla, transcribirla con Groq Whisper y devolver el texto
a WF-01. WF-01 decide el destino:

- WF-03 si es un gasto normal.
- WF-07A si el administrador está en modo maestras.

WF-02 **no crea gastos ni registros** en `registros_entrada`. Solo transforma audio en
texto. WF-03 es el dueño de la creación del registro y de la lógica de estado.

## 2. Estado actual

- Implementado con Groq `whisper-large-v3`.
- WF-01 normaliza los mensajes de voz y los marca como `tipo = 'voz'`.
- El Router de WF-01 envía la voz a `[MYRA] 02 · Voz a Texto`.
- La salida de WF-02 vuelve a WF-01; `Voz como texto` decide si va a WF-03 o a las
  maestras.
- La tabla `registros_entrada` soporta `tipo = 'voz'`, `telegram_file_id` y
  `duracion_ms` (duración del audio). El tiempo total de registro sigue pendiente.

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

## 4. Contrato de salida

WF-02 devuelve el mismo ítem, agregando:

```json
{
  "tipo": "voz",
  "texto_transcrito": "Anota doce mil quinientos en Copec, pagué con débito...",
  "transcripcion_ok": true,
  "stt_no_speech_prob": 0.02,
  "stt_avg_logprob": -0.18,
  "duracion_ms": 12000
}
```

- `texto_transcrito` es la transcripción aceptada.
- WF-01 lo copia a `texto` antes de llamar a WF-03 o a las maestras.
- `tipo` sigue siendo `voz`; `file_id` y `duracion_seg` se conservan.
- WF-03 usa `texto`, `tipo`, `telegram_message_id`, `telegram_file_id` y `duracion_ms`.

## 5. Nodos actuales

| Nodo | Tipo | Detalle |
|---|---|---|
| `When Executed by Another Workflow` | Execute Workflow Trigger | Recibe el ítem de WF-01 |
| `Descargar audio` | Telegram | `getFile` con **Download = true** |
| `Preparar audio` | Code | Valida el binario y el tamaño; fuerza OGG/Opus |
| `¿Audio válido?` | Switch | Válido → Groq; inválido → mensaje |
| `Transcribir con Groq` | HTTP Request | `whisper-large-v3`, `language=es`, `verbose_json` |
| `Extraer transcripcion` | Code | Calcula `transcripcion_ok` y las probabilidades |
| `Transcripcion OK?` | Switch | OK → devolver; error → mensaje |
| `Responder error audio` | Telegram | Aviso y luego error explícito |
| `Lanzar error STT` | Code | Corta el flujo para que no llegue a WF-03 |
| `Responder audio invalido` | Telegram | Aviso de archivo inválido |
| `Devolver transcripcion` | Code | Devuelve el ítem a WF-01 |

## 6. Validaciones

- El binario debe existir y ser descargable.
- Tamaño máximo: **20 MB**.
- MIME permitido: `audio/*`, `application/octet-stream`, `video/ogg` o vacío.
- Se rechaza si `texto_transcrito` está vacío, `no_speech_prob >= 0.5` o
  `avg_logprob <= -0.8`.
- Telegram entrega notas de voz OGG/Opus; Groq las acepta directamente.

## 7. Persistencia

WF-03 crea el registro y guarda:

```sql
INSERT INTO registros_entrada (
  usuario_id, tipo, telegram_message_id, telegram_file_id,
  transcripcion, duracion_ms, estado
)
VALUES ($1, $2, $3, $4, $5, $6, 'procesando')
RETURNING id;
```

Para texto, `tipo = 'texto'`, `file_id = NULL` y `duracion_ms = NULL`.

## 8. Errores

- Si falla la descarga: responder "No pude descargar el audio..." y no llamar a
  WF-03.
- Si la transcripción viene vacía o Groq falla: responder "No pude escuchar bien..." y
  cortar el flujo.
- No guardar nada en `gastos` desde WF-02.
- El workflow de errores centralizado (`WF-08`) todavía está pendiente; por ahora el
  error se registra en la ejecución de n8n.

## 9. Pruebas

1. **Voz completa:** "Anota 12.500 en Copec, pagué con débito, obra Peñuelas, cargué
   bencina." → extracción de los 5 campos y confirmación.
2. **Voz sin proyecto:** pregunta por el proyecto; la respuesta por texto continúa el
   mismo registro.
3. **Voz con ruido:** transcripción aceptable o mensaje para repetir.
4. **Voz fuera de contexto:** no crea gasto.
5. **Audio de más de 20 MB:** mensaje claro, sin llamar a Groq.
6. **Audio en modo maestras:** el texto llega a 07A y muestra el resumen de la
   operación.
7. **Verificación en base:** `tipo='voz'`, `telegram_file_id` no nulo y
   `duracion_ms` aproximado a la duración real.
