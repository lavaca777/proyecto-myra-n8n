# Seeds (datos de ejemplo)

Estos archivos **no** se ejecutan automáticamente. Son datos de prueba para
desarrollo; no deben usarse en producción.

## Cargar un seed

### Supabase (producción)

Copiar el contenido de `dev_demo.sql` en el **SQL Editor** de Supabase y ejecutarlo,
después de reemplazar el `telegram_chat_id` de ejemplo por el real.

### Desarrollo local

```powershell
docker compose cp .\db\seeds\dev_demo.sql postgres:/tmp/dev_demo.sql
docker compose exec -T postgres psql -U myra -d myra -v ON_ERROR_STOP=1 -f /tmp/dev_demo.sql
docker compose exec -T postgres rm -f /tmp/dev_demo.sql
```

## Seed realista para demos

`demo_realista.sql` carga clientes, 6 proyectos, alias, usuarios ficticios,
proveedores y 37 gastos con fechas variadas. Sirve para probar `/resumen`,
`/ultimos` y las exportaciones con filtros de 30 días y tabla completa.

Es idempotente: se puede ejecutar varias veces sin duplicar los gastos.
No usar como datos productivos.

## Antes de probar el bot

1. Reemplaza `123456789` en `dev_demo.sql` por tu `telegram_chat_id` real.
2. Verifica que el proyecto exista y esté activo:

```sql
SELECT p.id, p.nombre, p.activo, c.nombre AS cliente
FROM proyectos p
JOIN clientes c ON c.id = p.cliente_id;
```

3. Verifica los alias:

```sql
SELECT p.nombre AS proyecto, pa.alias
FROM proyecto_alias pa
JOIN proyectos p ON p.id = pa.proyecto_id;
```

## Datos que sí deben existir en producción

- Clientes y proyectos reales de MYRA.
- Alias que usa el personal de faena.
- Usuarios autorizados (whitelist por `telegram_chat_id`).
- Medios de pago y categorías (los carga `002_seed_catalogos.sql`, pero deben
  validarse con la empresa).
