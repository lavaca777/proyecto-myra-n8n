# Seeds (datos de ejemplo)

Estos archivos **no** se ejecutan automáticamente. Son datos de prueba para
desarrollo; no deben usarse en producción.

## Cargar un seed

```powershell
docker compose cp .\db\seeds\dev_demo.sql postgres:/tmp/dev_demo.sql
docker compose exec -T postgres psql -U myra -d myra -v ON_ERROR_STOP=1 -f /tmp/dev_demo.sql
docker compose exec -T postgres rm -f /tmp/dev_demo.sql
```

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
