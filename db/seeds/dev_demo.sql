-- =====================================================================
-- Datos de ejemplo SOLO para desarrollo.
-- No se ejecuta automaticamente. Ejecutar a mano:
--   .\scripts\psql.ps1 -Query "..."   o   Get-Content .\db\seeds\dev_demo.sql | ...
--
-- Antes de usar el bot, reemplaza el telegram_chat_id por el real.
-- =====================================================================

INSERT INTO clientes (nombre)
VALUES ('Cliente Demo')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO proyectos (cliente_id, nombre)
SELECT id, 'Obra Peñuelas'
FROM clientes
WHERE nombre = 'Cliente Demo'
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO proyectos (cliente_id, nombre)
SELECT id, 'Obra La Rinconada'
FROM clientes
WHERE nombre = 'Cliente Demo'
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO proyecto_alias (proyecto_id, alias)
SELECT id, 'la obra de Peñuelas'
FROM proyectos
WHERE nombre = 'Obra Peñuelas'
ON CONFLICT DO NOTHING;

INSERT INTO proyecto_alias (proyecto_id, alias)
SELECT id, 'Peñuelas'
FROM proyectos
WHERE nombre = 'Obra Peñuelas'
ON CONFLICT DO NOTHING;

INSERT INTO proyecto_alias (proyecto_id, alias)
SELECT id, 'la Rinconada'
FROM proyectos
WHERE nombre = 'Obra La Rinconada'
ON CONFLICT DO NOTHING;

-- Reemplaza 123456789 por tu chat_id real de Telegram.
-- Puedes obtenerlo escribiendo al bot y mirando el update en n8n.
INSERT INTO usuarios (telegram_chat_id, nombre, rol)
VALUES (123456789, 'Usuario Demo', 'jefe_obra')
ON CONFLICT (telegram_chat_id) DO NOTHING;
