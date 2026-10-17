-- =====================================================================
-- Catalogos iniciales de MYRA (medios de pago y categorias)
-- Idempotente: se puede ejecutar varias veces sin duplicar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- DATOS INICIALES (confirmar con MYRA)
-- ---------------------------------------------------------------------
INSERT INTO medios_pago (nombre) VALUES
    ('Efectivo'), ('Tarjeta de débito'), ('Tarjeta de crédito'),
    ('Transferencia'), ('Crédito en proveedor')
ON CONFLICT (nombre) DO NOTHING;

-- usa_bot = TRUE para las categorías típicas de compras en obra (supuesto a validar)
INSERT INTO categorias (nombre, usa_bot) VALUES
    ('Combustible', TRUE),  ('EPP', TRUE),           ('GG', TRUE),
    ('Herramientas', TRUE), ('Materiales', TRUE),    ('Servicios', TRUE),
    ('Vehículos', TRUE),
    ('Honorarios Contador', FALSE), ('Imposiciones', FALSE), ('Impuesto 2da', FALSE),
    ('IVA', FALSE), ('Marketing', FALSE), ('PPM', FALSE), ('Renta', FALSE), ('Sueldo', FALSE)
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- Registro de esta migracion
-- ---------------------------------------------------------------------
INSERT INTO schema_migrations (filename)
VALUES ('002_seed_catalogos.sql')
ON CONFLICT (filename) DO NOTHING;
