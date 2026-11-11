# Arquitectura

## 1. Contexto

Constructora MYRA registra compras de obra en cuatro grupos de WhatsApp. Los
comprobantes no traen centro de costo y la rendición se posterga, por lo que los
costos directos terminan acumulados en gastos generales. La solución reemplaza la
captura informal por un asistente de Telegram **audio-first** que estructura el gasto
en el punto de compra y lo imputa a un proyecto antes de persistirlo.

## 2. Vista de componentes

```text
┌──────────────┐   HTTPS (webhook)   ┌─────────────────────────────┐
│   Telegram   │ ──────────────────► │         n8n Cloud           │
│  (jefe obra) │ ◄────────────────── │  orquestador de flujos      │
└──────────────┘   mensajes/botones   └──────────┬──────────────────┘
                                                 │
                                     ┌───────────┴───────────┐
                                     │                       │
                                     ▼                       ▼
                            ┌─────────────────┐     ┌─────────────────┐
                            │ Gemini / Groq   │     │    Supabase     │
                            │  NLU + STT      │     │  PostgreSQL     │
                            └─────────────────┘     └─────────────────┘
```

| Componente | Tecnología | Rol |
|---|---|---|
| Interfaz | Telegram Bot API | Canal de voz, texto, fotos y botones inline |
| Orquestador | n8n Cloud (administrado) | Router, estado, validaciones, persistencia |
| STT + NLU | Groq Whisper + Google Gemini | Transcripción y extracción de campos |
| Datos | Supabase (PostgreSQL administrado) | Modelo relacional y auditoría |
| Exposición | HTTPS de n8n Cloud | Webhook estable de Telegram |
| Disponibilidad | Workflow `[MYRA] 08 · Heartbeat` | Evita la pausa por inactividad de Supabase |
| Contenedores | Docker Compose solo en desarrollo local | Reproducibilidad del entorno de pruebas |

## 3. Decisiones de diseño

### 3.1 El LLM extrae; los nodos deciden

El agente **no** tiene permitido escribir en la base. Su única salida es un JSON con
los campos extraídos y un nivel de confianza. La validación, el fuzzy matching y el
`INSERT` se hacen con nodos deterministas.

Motivos:

- El criterio de aceptación exige **imposibilidad de guardar sin proyecto**.
- Un agente con un `postgresTool` puede insertar en cualquier tabla o inventar IDs.
- La auditoría necesita saber qué dijo el usuario y qué entendió la IA
  (`registros_entrada.transcripcion` y `json_extraido`).
- Facilita medir la precisión (>80%) comparando lo extraído con lo confirmado.

### 3.2 El estado de la conversación vive en PostgreSQL

No se usa la memoria del AI Agent ni variables en memoria del proceso. Cada mensaje
relevante crea o actualiza una fila en `registros_entrada`:

```text
procesando ──► falta_dato ──► pendiente_confirmacion ──► confirmado
     │              │                    │
     └──────────────┴────────────────────┴──► cancelado / error
```

Campos que gobiernan la conversación:

- `estado`: en qué punto va el registro.
- `campo_pendiente`: qué dato falta o se está corrigiendo (`proyecto`, `monto`, ...).
- `json_extraido`: último JSON entendido por la IA.
- `transcripcion`: texto del audio o mensaje.
- `duracion_ms`: para medir la meta de < 60 segundos.

Ventajas: sobrevive a reinicios de n8n, permite retomar una conversación y deja
trazabilidad para la tesis.

### 3.3 Confirmación con botones inline

El mensaje de resumen incluye:

```text
Proyecto: Obra Peñuelas
Monto:    $45.990
Fecha:    17-10-2026
Proveedor: Sodimac
Pago:     Tarjeta de débito

[ ✅ Confirmar ]  [ ✏️ Corregir ]  [ ❌ Cancelar ]
```

Los botones envían `callback_query` con `callback_data`:

- `confirm:<registro_id>`
- `edit:<registro_id>`
- `cancel:<registro_id>`

El Telegram Trigger debe escuchar **`message` y `callback_query`**.

### 3.4 Idempotencia

- `gastos.registro_entrada_id` es `UNIQUE`: un registro no puede generar dos gastos.
- Antes de confirmar se verifica que el `registro_entrada` siga en
  `pendiente_confirmacion`.
- Si el usuario pulsa dos veces "Confirmar", la segunda responde "ya registrado".

### 3.5 Usuarios autorizados

La tabla `usuarios` es una whitelist por `telegram_chat_id`. Todo update de un chat
no registrado o inactivo se rechaza antes de tocar la IA o la base. El rol
(`jefe_obra`, `administrador`, `gerencia`) habilita comandos distintos:

- `jefe_obra`: registrar gastos y consultar sus últimos registros.
- `administrador`: maestras, exportaciones.
- `gerencia`: resúmenes consolidados.

### 3.6 Fuzzy matching de proyectos

El audio puede decir "la obra de Peñuelas" y el catálogo decir "Obra Peñuelas".
La migración `003_fuzzy_proyectos.sql` habilita `pg_trgm` e índices GIN. La búsqueda
combina:

1. Coincidencia exacta normalizada (minúsculas, sin tildes).
2. Alias declarados en `proyecto_alias`.
3. Similitud por trigramas (`similarity()`) con umbral configurable.
4. Si nada supera el umbral: `falta_dato = 'proyecto'` y se pregunta.

Nunca se asigna un proyecto "parecido" sin confirmación cuando la confianza es baja.

### 3.7 Errores

- Un workflow `[MYRA] 07 · Errores` con **Error Trigger** centraliza los fallos.
- El error se registra con el `execution.id` de n8n y se avisa al chat administrador.
- El usuario recibe un mensaje genérico ("No pude procesar el audio, intenta de nuevo")
  sin exponer detalles técnicos.
- Los errores de STT se pueden reintentar una vez antes de pedir texto.

## 4. Flujo principal (voz)

```text
1. Usuario envía nota de voz
2. WF-01 identifica chat_id y valida whitelist
3. WF-02 descarga el audio y lo transcribe
4. WF-03 carga maestras, arma el prompt y llama a Gemini
5. Gemini devuelve JSON con los 5 campos + confianza
6. WF-03 normaliza monto/fecha y hace fuzzy match del proyecto
7. Si falta un campo -> estado falta_dato y pregunta puntual
8. Si están los 5 -> estado pendiente_confirmacion + resumen con botones
9. Usuario confirma
10. WF-04 inserta proveedor (si es nuevo), gasto y comprobante
11. Respuesta final con ID y resumen
```

## 5. Despliegue

### Desarrollo local (PC)

- Docker Compose: `myra-postgres` + `myra-n8n`.
- n8n en `http://localhost:5678`.
- Cloudflare quick tunnel para probar el webhook de Telegram desde internet.
- Este entorno es solo para desarrollo y pruebas; no es producción.

### Producción (n8n Cloud + Supabase)

- n8n Cloud con URL HTTPS fija; sin servidor propio ni túnel de Cloudflare.
- Supabase como PostgreSQL administrado, con conexión SSL.
- Workflow `[MYRA] 08 · Heartbeat` cada 3 días para evitar la pausa por inactividad
  del plan gratuito de Supabase.
- Respaldos periódicos de Supabase y exportación de workflows a git.
- Sin servidor UCN, sin VPS, sin Nginx/Caddy y sin Docker Compose en producción.
- Ver [`04-despliegue-cloud.md`](04-despliegue-cloud.md).

## 6. Riesgos técnicos y mitigación

| Riesgo | Mitigación |
|---|---|
| Ruido en faena afecta el STT | `no_speech_prob` + mensaje de reintento + confirmación |
| El proveedor de STT no acepta OGG/Opus de Telegram | Groq Whisper para STT; Gemini solo para extracción |
| URL del quick tunnel cambia | Solo afecta desarrollo; en producción n8n Cloud da URL fija |
| Reinicio de n8n pierde contexto | Estado en PostgreSQL, no en memoria |
| Proyecto mal asignado | Fuzzy match + confirmación obligatoria si la confianza es baja |
| Supabase free se pausa por inactividad | Workflow `[MYRA] 08 · Heartbeat` cada 3 días |
| Límite de ejecuciones de n8n Cloud | Medir volumen mensual y elegir plan; los sub-workflows no consumen el límite |
| Credenciales/IDs locales no sirven en Cloud | Recrear credenciales y remapear nodos al importar |
| Pérdida de workflows o datos | Export de workflows a git + respaldos de Supabase |
