# Base de datos

Motor: **PostgreSQL 16**. Modelo relacional orientado a la trazabilidad del gasto y a
la conversación del bot. Diagrama: [`modelo-relacional.png`](db/modelo-relacional.png).

## 1. Tablas

| Tabla | Propósito | Notas |
|---|---|---|
| `usuarios` | Whitelist de Telegram | `telegram_chat_id` único; rol y `activo` |
| `clientes` | Dueños de los proyectos | Un cliente tiene varios proyectos |
| `proyectos` | Obras activas | `nombre` único; `activo` para borrado lógico |
| `proyecto_alias` | Cómo nombra la gente a la obra | Índice único sobre `lower(alias)` |
| `categorias` | Categorías de gasto | `usa_bot = TRUE` para las que sugiere la IA |
| `medios_pago` | Efectivo, débito, crédito, etc. | Catálogo simple |
| `proveedores` | Ferreterías y empresas | `nombre_normalizado` único evita duplicados |
| `registros_entrada` | Bitácora y estado de la conversación | Una fila por audio/texto/foto |
| `gastos` | Gasto confirmado | 5 campos críticos + `registro_entrada_id` único |
| `comprobantes` | Boleta/factura asociada | Uno o varios por gasto |
| `v_gastos_detalle` | Vista legible para reportes | Une proyecto, cliente, categoría, etc. |

## 2. Los 5 campos críticos

| Campo del charter | Columna | Regla |
|---|---|---|
| Proyecto | `gastos.proyecto_id` | **NOT NULL**; debe existir en `proyectos` |
| Monto total | `gastos.monto_total` | `BIGINT > 0`, pesos chilenos sin decimales |
| Fecha | `gastos.fecha_gasto` | `DATE`; se interpreta en `America/Santiago` |
| Proveedor | `gastos.proveedor_id` | Se crea si no existe (normalizado) |
| Medio de pago | `gastos.medio_pago_id` | Debe existir en `medios_pago` |

La categoría y la descripción son complementarias: la IA las infiere, pero no son
obligatorias para persistir.

## 3. Estado de la conversación

`registros_entrada.estado`:

```text
procesando → falta_dato → pendiente_confirmacion → confirmado
     │            │                 │
     └────────────┴─────────────────┴→ cancelado / error
```

- `campo_pendiente`: `proyecto`, `monto_total`, `fecha`, `proveedor` o `medio_pago`.
- `json_extraido` (`JSONB`): lo que entendió la IA, para auditoría y para medir precisión.
- `transcripcion`: texto del audio o mensaje.
- `modelo_ia`: `gemini-2.0-flash`, etc.
- `duracion_ms`: para verificar la meta de < 60 s.
- `telegram_message_id` y `telegram_file_id`: trazabilidad con Telegram.

El trigger `trg_registros_actualizado` mantiene `actualizado_en`.

## 4. Integridad

- `gastos.registro_entrada_id` es **UNIQUE**: un registro no puede generar dos gastos.
- `gastos.proyecto_id` es **NOT NULL**: no existen gastos huérfanos.
- `gastos.monto_total > 0`.
- Borrado lógico con `activo` / `estado`, no `DELETE`.
- `proveedores.nombre_normalizado` único: "Sodimac" y "sodimac" son el mismo.
- `proyecto_alias` único por `lower(alias)`: evita dos alias iguales en proyectos distintos.

## 5. Migraciones

Los archivos viven en `db/migrations/` y se ejecutan en orden alfabético:

| Archivo | Contenido |
|---|---|
| `000_migrations.sql` | Crea `schema_migrations` |
| `001_schema_inicial.sql` | Tablas, índices, trigger y vista |
| `002_seed_catalogos.sql` | Medios de pago y categorías |
| `003_fuzzy_proyectos.sql` | `pg_trgm`, `unaccent` e índices |

### Base nueva

Docker ejecuta automáticamente todo `db/migrations/` cuando el volumen de PostgreSQL
está vacío. No hay que hacer nada más.

### Base existente

```powershell
.\scripts\db-migrate.ps1
```

El script aplica solo los archivos que no están registrados en `schema_migrations`.
Las migraciones actuales son idempotentes (`IF NOT EXISTS`, `ON CONFLICT`), así que
también se pueden reejecutar sin romper nada.

### Crear una migración nueva

1. Crea `db/migrations/004_descripcion.sql`.
2. Usa `IF NOT EXISTS` / `ON CONFLICT` cuando sea posible.
3. Termina con:

```sql
INSERT INTO schema_migrations (filename)
VALUES ('004_descripcion.sql')
ON CONFLICT (filename) DO NOTHING;
```

4. Ejecuta `.\scripts\db-migrate.ps1`.
5. Commit del archivo.

## 6. Maestras

Antes de probar el bot deben existir:

- Al menos un `cliente`.
- Al menos un `proyecto` activo y sus alias.
- Los `medios_pago` y `categorias` (los carga `002_seed_catalogos.sql`).
- El `usuario` de prueba con su `telegram_chat_id` real.

Ejemplo:

```sql
INSERT INTO clientes (nombre) VALUES ('Cliente Demo')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO proyectos (cliente_id, nombre)
SELECT id, 'Obra Peñuelas' FROM clientes WHERE nombre = 'Cliente Demo'
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO proyecto_alias (proyecto_id, alias)
SELECT id, 'la obra de Peñuelas' FROM proyectos WHERE nombre = 'Obra Peñuelas'
ON CONFLICT DO NOTHING;

INSERT INTO usuarios (telegram_chat_id, nombre, rol)
VALUES (123456789, 'Carlos Tapia', 'jefe_obra')
ON CONFLICT (telegram_chat_id) DO NOTHING;
```

Para desarrollo hay un archivo de ejemplo en `db/seeds/dev_demo.sql`. **No** se ejecuta
automáticamente.

## 7. Fuzzy matching

`003_fuzzy_proyectos.sql` habilita:

- `pg_trgm`: similitud por trigramas.
- `unaccent`: "Peñuelas" ≈ "Penuelas".
- Índices GIN sobre nombres y alias.

La consulta de WF-00 devuelve hasta 3 candidatos con `score`. Reglas:

- `score >= 0.55` y sin empate cercano → asignar.
- `score < 0.55` o dos candidatos con diferencia < 0.10 → preguntar.
- Sin candidatos → `falta_dato = 'proyecto'`.

## 8. Consultas útiles

### Gasto del mes por proyecto

```sql
SELECT proyecto,
       COUNT(*) AS compras,
       SUM(monto_total) AS total
FROM v_gastos_detalle
WHERE fecha_gasto >= date_trunc('month', current_date)
GROUP BY proyecto
ORDER BY total DESC;
```

### Gastos por cliente y categoría

```sql
SELECT cliente, categoria, SUM(monto_total) AS total
FROM v_gastos_detalle
WHERE fecha_gasto BETWEEN $1 AND $2
GROUP BY cliente, categoria
ORDER BY total DESC;
```

### Export para Excel/CSV

```sql
COPY (
  SELECT *
  FROM v_gastos_detalle
  ORDER BY fecha_gasto DESC
) TO STDOUT WITH (FORMAT csv, HEADER true);
```

n8n puede usar `Postgres → Execute Query` y luego `Spreadsheet File → Convert to CSV`.

### Registros con error

```sql
SELECT id, usuario_id, tipo, estado, error_detalle, creado_en
FROM registros_entrada
WHERE estado = 'error'
ORDER BY creado_en DESC;
```

## 9. Respaldos

```powershell
.\scripts\backup.ps1
```

Genera `db/backups/myra_YYYYMMDD_HHmmss.dump` con `pg_dump -Fc`.

Restaurar en una base limpia:

```powershell
# Detener n8n para que no escriba durante la restauración
docker compose stop n8n

# Restaurar
docker compose exec -T postgres dropdb -U myra --if-exists myra
docker compose exec -T postgres createdb -U myra myra
docker compose cp .\db\backups\myra_AAAAAMMDD_HHMMSS.dump postgres:/tmp/restore.dump
docker compose exec -T postgres pg_restore -U myra -d myra --clean --if-exists /tmp/restore.dump

docker compose start n8n
```

> El `--clean` con `dropdb/createdb` es para una base vacía. En producción, validar
> siempre el respaldo antes de restaurar.

## 10. Decisiones y pendientes

- **Montos en CLP como `BIGINT`**: no se usan decimales. Si más adelante se requiere
  UF o moneda extranjera, agregar una tabla de monedas y tipo de cambio.
- **Zona horaria**: `America/Santiago` en contenedores y en la interpretación de
  fechas relativas.
- **Comprobantes**: el OCR es "Could"; la tabla ya está lista.
- **Auditoría**: `registros_entrada` conserva lo que dijo el usuario y lo que entendió
  la IA. No borrar esos registros.
- **Pendiente con MYRA**: catálogo real de proyectos, alias usados en faena y
  categorías que deben estar disponibles en el bot.
