# Prompt · Extracción de gasto v1

**Uso:** WF-03 · Extracción
**Modelo sugerido:** Gemini 2.0 Flash (capa gratuita)
**Salida:** JSON estricto (`response_mime_type: application/json`)

> El prompt se versiona acá y se copia al nodo `Armar prompt`. Si cambia, crear
> `extraccion_gasto_v2.md` y registrar la versión en `registros_entrada.modelo_ia`
> o en el campo `meta` del workflow.

---

## System prompt

```text
Eres el módulo de extracción de datos de compras de Constructora MYRA.
Recibes la transcripción de una nota de voz o un mensaje de texto de un jefe de obra
chileno. Tu única tarea es extraer los datos del gasto y devolver un JSON válido.

REGLAS OBLIGATORIAS
1. No inventes datos. Si un campo no aparece, usa null.
2. No escribas explicaciones, markdown ni texto fuera del JSON.
3. Los montos son pesos chilenos (CLP), enteros y sin puntos ni decimales.
   - "45 mil" -> 45000
   - "45.990" -> 45990
   - "cuarenta y cinco mil novecientos noventa" -> 45990
   - "mil quinientos" -> 1500
4. La fecha debe ser ISO 8601 (YYYY-MM-DD).
   - "hoy" y "ayer" ya vienen resueltos en el campo fecha_actual.
   - Si dice "el viernes" o "la semana pasada", usa la fecha más probable cercana a
     fecha_actual y baja la confianza.
5. El proyecto debe ser uno de los que aparecen en PROYECTOS. Puedes devolver el
   nombre oficial o el alias tal como lo dijo el usuario; el sistema hará el match.
   Si no se menciona ningún proyecto, usa null.
6. El medio de pago debe ser uno de MEDIOS_PAGO. Si no coincide, usa null.
7. La categoría debe ser una de CATEGORIAS. Si no estás seguro, usa null.
8. La descripción es breve: qué se compró (ej. "tornillos y silicona").
9. La confianza es un número entre 0 y 1 por cada campo extraído.
10. Si el audio es ininteligible o no describe una compra, devuelve todos los campos
    en null y confianza 0.

FORMATO DE SALIDA
{
  "proyecto": string | null,
  "monto_total": integer | null,
  "fecha": "YYYY-MM-DD" | null,
  "proveedor": string | null,
  "medio_pago": string | null,
  "categoria": string | null,
  "descripcion": string | null,
  "confianza": {
    "proyecto": number,
    "monto_total": number,
    "fecha": number,
    "proveedor": number,
    "medio_pago": number
  }
}
```

## User prompt (plantilla)

```text
FECHA_ACTUAL: {{ $now.setZone('America/Santiago').toISODate() }}
DÍA_DE_LA_SEMANA: {{ $now.setZone('America/Santiago').toFormat('cccc') }}

PROYECTOS (nombre oficial | alias):
{{ $json.proyectos.map(p => `- ${p.nombre} | ${p.alias.join(', ')}`).join('\n') }}

MEDIOS_PAGO:
{{ $json.medios_pago.map(m => `- ${m.nombre}`).join('\n') }}

CATEGORIAS:
{{ $json.categorias.map(c => `- ${c.nombre}`).join('\n') }}

TEXTO DEL USUARIO:
"""
{{ $json.texto }}
"""

Devuelve solo el JSON.
```

> En n8n, `$now` es un DateTime de Luxon. Si la expresión no funciona en el nodo,
> calcular la fecha en un Code node y pasarla como `fecha_actual`.

---

## JSON Schema (para `response_schema` de Gemini)

```json
{
  "type": "object",
  "properties": {
    "proyecto": { "type": ["string", "null"] },
    "monto_total": { "type": ["integer", "null"] },
    "fecha": { "type": ["string", "null"], "format": "date" },
    "proveedor": { "type": ["string", "null"] },
    "medio_pago": { "type": ["string", "null"] },
    "categoria": { "type": ["string", "null"] },
    "descripcion": { "type": ["string", "null"] },
    "confianza": {
      "type": "object",
      "properties": {
        "proyecto": { "type": "number" },
        "monto_total": { "type": "number" },
        "fecha": { "type": "number" },
        "proveedor": { "type": "number" },
        "medio_pago": { "type": "number" }
      },
      "required": ["proyecto", "monto_total", "fecha", "proveedor", "medio_pago"]
    }
  },
  "required": [
    "proyecto", "monto_total", "fecha", "proveedor", "medio_pago",
    "categoria", "descripcion", "confianza"
  ]
}
```

---

## Ejemplos

### Ejemplo 1 · completo

**Entrada:**
> "Anota cuarenta y cinco mil novecientos noventa en Sodimac, pagué con débito, para
> la obra de Peñuelas, compré tornillos y silicona."

**Salida:**

```json
{
  "proyecto": "la obra de Peñuelas",
  "monto_total": 45990,
  "fecha": "2026-10-17",
  "proveedor": "Sodimac",
  "medio_pago": "Tarjeta de débito",
  "categoria": "Materiales",
  "descripcion": "tornillos y silicona",
  "confianza": {
    "proyecto": 0.95,
    "monto_total": 0.99,
    "fecha": 0.8,
    "proveedor": 0.99,
    "medio_pago": 0.95
  }
}
```

### Ejemplo 2 · falta proyecto

**Entrada:**
> "Gasté 12 lucas en combustible, pagué en efectivo."

**Salida:**

```json
{
  "proyecto": null,
  "monto_total": 12000,
  "fecha": "2026-10-17",
  "proveedor": null,
  "medio_pago": "Efectivo",
  "categoria": "Combustible",
  "descripcion": "combustible",
  "confianza": {
    "proyecto": 0,
    "monto_total": 0.9,
    "fecha": 0.6,
    "proveedor": 0,
    "medio_pago": 0.9
  }
}
```

### Ejemplo 3 · audio ininteligible

**Entrada:**
> "Eh... no, espera... [ruido]"

**Salida:**

```json
{
  "proyecto": null,
  "monto_total": null,
  "fecha": null,
  "proveedor": null,
  "medio_pago": null,
  "categoria": null,
  "descripcion": null,
  "confianza": {
    "proyecto": 0,
    "monto_total": 0,
    "fecha": 0,
    "proveedor": 0,
    "medio_pago": 0
  }
}
```

---

## Post-procesamiento obligatorio en n8n

El LLM no es confiable al 100%. Después de parsear el JSON:

1. **Monto**: si viene con puntos o como string, limpiar y convertir a entero.
   Rechazar `<= 0`.
2. **Fecha**: si es `null`, usar la fecha actual; si es futura, marcarla para revisión.
3. **Proyecto**: fuzzy match contra `proyectos` y `proyecto_alias`; aplicar umbrales.
4. **Medio de pago**: comparar contra el catálogo (normalizado); si no hay match, `null`.
5. **Proveedor**: normalizar (minúsculas, sin tildes, sin espacios extra) para el upsert.
6. **Confianza**: si `confianza.proyecto < 0.55`, no asignar automáticamente.
7. **Validación final**: si falta cualquiera de los 5 campos, `estado='falta_dato'` y
   preguntar solo por el primero faltante (prioridad: proyecto > monto > fecha >
   proveedor > medio de pago).

## Métricas

Guardar en `registros_entrada`:

- `modelo_ia`: nombre y versión del modelo.
- `json_extraido`: la salida cruda y la normalizada.
- `transcripcion`: el texto de entrada.
- `duracion_ms`: tiempo total del flujo.

Para medir la precisión (>80%), comparar `json_extraido` (lo que entendió la IA) con
los datos que finalmente se confirmaron en `gastos`. Esa comparación debe hacerse en
un script o consulta aparte, no en el flujo del usuario.
