-- =====================================================================
-- Seed de demostración "realista" para MYRA
--
-- Solo para pruebas y demos. No usar como datos productivos.
-- Es idempotente: se puede ejecutar más de una vez sin duplicar los
-- clientes, proyectos, usuarios, proveedores ni los gastos de ejemplo.
--
-- Los gastos usan fechas relativas a CURRENT_DATE para que los filtros
-- de "últimos 30 días" y "toda la tabla" muestren resultados distintos.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------
INSERT INTO clientes (nombre) VALUES
    ('Constructora MYRA'),
    ('Inmobiliaria Andes'),
    ('Constructora del Norte')
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- Proyectos
-- ---------------------------------------------------------------------
INSERT INTO proyectos (cliente_id, nombre)
SELECT c.id, p.nombre
FROM (VALUES
    ('Constructora MYRA', 'Obra Peñuelas'),
    ('Constructora MYRA', 'Obra La Rinconada'),
    ('Constructora MYRA', 'Obra Cerro Colorado'),
    ('Inmobiliaria Andes', 'Edificio Costanera'),
    ('Inmobiliaria Andes', 'Edificio Plaza Norte'),
    ('Constructora del Norte', 'Condominio Los Aromos')
) AS p(cliente, nombre)
JOIN clientes c ON c.nombre = p.cliente
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- Alias usados en faena
-- ---------------------------------------------------------------------
INSERT INTO proyecto_alias (proyecto_id, alias)
SELECT p.id, a.alias
FROM (VALUES
    ('Obra Peñuelas', 'la obra de Peñuelas'),
    ('Obra Peñuelas', 'Peñuelas'),
    ('Obra Peñuelas', 'Peñuela'),
    ('Obra La Rinconada', 'la Rinconada'),
    ('Obra La Rinconada', 'Rinconada'),
    ('Obra Cerro Colorado', 'Cerro Colorado'),
    ('Obra Cerro Colorado', 'el cerro'),
    ('Edificio Costanera', 'Costanera'),
    ('Edificio Costanera', 'la costanera'),
    ('Edificio Plaza Norte', 'Plaza Norte'),
    ('Edificio Plaza Norte', 'plaza'),
    ('Condominio Los Aromos', 'Los Aromos'),
    ('Condominio Los Aromos', 'los aromos')
) AS a(proyecto, alias)
JOIN proyectos p ON p.nombre = a.proyecto
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Usuarios de demostración
-- Los chat_id son ficticios: solo sirven para poblar reportes.
-- Para probar el bot con tu cuenta, usa el usuario real que ya tienes.
-- ---------------------------------------------------------------------
INSERT INTO usuarios (telegram_chat_id, nombre, rol, activo) VALUES
    (1000000001, 'Carlos Tapia', 'jefe_obra', TRUE),
    (1000000002, 'María José Rojas', 'administrador', TRUE),
    (1000000003, 'Pedro Silva', 'gerencia', TRUE),
    (1000000004, 'Luis González', 'jefe_obra', TRUE),
    (1000000005, 'Ana Morales', 'administrador', TRUE)
ON CONFLICT (telegram_chat_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Proveedores
-- ---------------------------------------------------------------------
INSERT INTO proveedores (nombre, nombre_normalizado) VALUES
    ('Copec', 'copec'),
    ('Shell', 'shell'),
    ('Sodimac', 'sodimac'),
    ('Ferretería El Tornillo', 'ferreteria el tornillo'),
    ('Construplast', 'construplast'),
    ('Distribuidora Andes', 'distribuidora andes'),
    ('Seguridad Industrial', 'seguridad industrial'),
    ('Maquinarias del Sur', 'maquinarias del sur'),
    ('Transportes Rápido', 'transportes rapido'),
    ('Cementos Bío Bío', 'cementos bio bio')
ON CONFLICT (nombre_normalizado) DO NOTHING;

-- ---------------------------------------------------------------------
-- Gastos de ejemplo
-- ---------------------------------------------------------------------
INSERT INTO gastos (
    proyecto_id,
    usuario_id,
    proveedor_id,
    medio_pago_id,
    categoria_id,
    descripcion,
    monto_total,
    fecha_gasto,
    origen
)
SELECT
    p.id,
    u.id,
    pr.id,
    mp.id,
    cat.id,
    v.descripcion,
    v.monto,
    v.fecha,
    v.origen
FROM (VALUES
    ('Obra Peñuelas', 'Carlos Tapia', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 45000, CURRENT_DATE - 2, 'voz'),
    ('Obra Peñuelas', 'Carlos Tapia', 'Sodimac', 'Tarjeta de crédito', 'Materiales', 'cemento y arena', 320000, CURRENT_DATE - 4, 'voz'),
    ('Obra Peñuelas', 'Luis González', 'Seguridad Industrial', 'Transferencia', 'EPP', 'guantes y mascarillas', 125000, CURRENT_DATE - 7, 'texto'),
    ('Obra Peñuelas', 'Carlos Tapia', 'Ferretería El Tornillo', 'Efectivo', 'Herramientas', 'tornillos y silicona', 15990, CURRENT_DATE - 9, 'voz'),
    ('Obra Peñuelas', 'Luis González', 'Transportes Rápido', 'Transferencia', 'Servicios', 'flete de materiales', 48000, CURRENT_DATE - 12, 'texto'),
    ('Obra Peñuelas', 'Carlos Tapia', 'Shell', 'Tarjeta de débito', 'Combustible', 'bencina camión', 38500, CURRENT_DATE - 15, 'voz'),
    ('Obra Peñuelas', 'María José Rojas', 'Sodimac', 'Tarjeta de crédito', 'Materiales', 'madera para moldaje', 265000, CURRENT_DATE - 19, 'foto'),
    ('Obra Peñuelas', 'Carlos Tapia', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 42000, CURRENT_DATE - 24, 'voz'),
    ('Obra Peñuelas', 'Luis González', 'Maquinarias del Sur', 'Transferencia', 'Herramientas', 'arriendo de taladro', 76000, CURRENT_DATE - 28, 'texto'),

    ('Obra La Rinconada', 'Luis González', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 35000, CURRENT_DATE - 3, 'voz'),
    ('Obra La Rinconada', 'Luis González', 'Ferretería El Tornillo', 'Efectivo', 'Materiales', 'fierro de construcción', 540000, CURRENT_DATE - 6, 'voz'),
    ('Obra La Rinconada', 'Carlos Tapia', 'Seguridad Industrial', 'Transferencia', 'EPP', 'cascos y chalecos', 198000, CURRENT_DATE - 10, 'texto'),
    ('Obra La Rinconada', 'Luis González', 'Transportes Rápido', 'Transferencia', 'Servicios', 'flete de fierro', 62000, CURRENT_DATE - 14, 'voz'),
    ('Obra La Rinconada', 'Luis González', 'Sodimac', 'Tarjeta de crédito', 'Materiales', 'planchas de yeso', 187000, CURRENT_DATE - 22, 'foto'),
    ('Obra La Rinconada', 'Carlos Tapia', 'Shell', 'Tarjeta de débito', 'Combustible', 'bencina camión', 41000, CURRENT_DATE - 29, 'voz'),

    ('Obra Cerro Colorado', 'Carlos Tapia', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 39500, CURRENT_DATE - 5, 'voz'),
    ('Obra Cerro Colorado', 'Ana Morales', 'Construplast', 'Transferencia', 'Materiales', 'tuberías y fittings', 430000, CURRENT_DATE - 11, 'texto'),
    ('Obra Cerro Colorado', 'Carlos Tapia', 'Maquinarias del Sur', 'Transferencia', 'Servicios', 'arriendo de andamio', 210000, CURRENT_DATE - 18, 'voz'),
    ('Obra Cerro Colorado', 'Luis González', 'Distribuidora Andes', 'Tarjeta de crédito', 'Materiales', 'perfiles de acero', 615000, CURRENT_DATE - 26, 'foto'),
    ('Obra Cerro Colorado', 'Carlos Tapia', 'Seguridad Industrial', 'Efectivo', 'EPP', 'protectores auditivos', 85000, CURRENT_DATE - 34, 'texto'),

    ('Edificio Costanera', 'María José Rojas', 'Sodimac', 'Tarjeta de crédito', 'Materiales', 'cerámicas y adhesivo', 478000, CURRENT_DATE - 8, 'voz'),
    ('Edificio Costanera', 'Carlos Tapia', 'Shell', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 44000, CURRENT_DATE - 13, 'voz'),
    ('Edificio Costanera', 'María José Rojas', 'Distribuidora Andes', 'Transferencia', 'Materiales', 'ventanas de aluminio', 1250000, CURRENT_DATE - 21, 'foto'),
    ('Edificio Costanera', 'Luis González', 'Transportes Rápido', 'Transferencia', 'Servicios', 'flete de cerámicas', 75000, CURRENT_DATE - 27, 'texto'),
    ('Edificio Costanera', 'María José Rojas', 'Cementos Bío Bío', 'Crédito en proveedor', 'Materiales', 'sacos de cemento', 890000, CURRENT_DATE - 41, 'voz'),
    ('Edificio Costanera', 'Carlos Tapia', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camión', 40500, CURRENT_DATE - 55, 'voz'),

    ('Edificio Plaza Norte', 'Ana Morales', 'Construplast', 'Transferencia', 'Materiales', 'molduras y perfiles', 356000, CURRENT_DATE - 16, 'texto'),
    ('Edificio Plaza Norte', 'Carlos Tapia', 'Seguridad Industrial', 'Tarjeta de crédito', 'EPP', 'guantes dieléctricos', 95000, CURRENT_DATE - 23, 'voz'),
    ('Edificio Plaza Norte', 'Ana Morales', 'Sodimac', 'Tarjeta de crédito', 'Herramientas', 'escaleras y cajas de herramienta', 289000, CURRENT_DATE - 45, 'foto'),
    ('Edificio Plaza Norte', 'Luis González', 'Transportes Rápido', 'Transferencia', 'Servicios', 'flete de perfiles', 68000, CURRENT_DATE - 62, 'texto'),
    ('Edificio Plaza Norte', 'Carlos Tapia', 'Shell', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 39000, CURRENT_DATE - 75, 'voz'),

    ('Condominio Los Aromos', 'Luis González', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 37000, CURRENT_DATE - 17, 'voz'),
    ('Condominio Los Aromos', 'Luis González', 'Ferretería El Tornillo', 'Efectivo', 'Materiales', 'alambre y clavos', 54000, CURRENT_DATE - 25, 'voz'),
    ('Condominio Los Aromos', 'Carlos Tapia', 'Maquinarias del Sur', 'Transferencia', 'Servicios', 'arriendo de retroexcavadora', 850000, CURRENT_DATE - 38, 'texto'),
    ('Condominio Los Aromos', 'Ana Morales', 'Distribuidora Andes', 'Transferencia', 'Materiales', 'tableros OSB', 398000, CURRENT_DATE - 48, 'foto'),
    ('Condominio Los Aromos', 'Luis González', 'Seguridad Industrial', 'Tarjeta de crédito', 'EPP', 'arneses de seguridad', 176000, CURRENT_DATE - 70, 'voz'),
    ('Condominio Los Aromos', 'Luis González', 'Copec', 'Tarjeta de débito', 'Combustible', 'bencina camioneta', 41500, CURRENT_DATE - 95, 'voz')
) AS v(proyecto, usuario, proveedor, medio, categoria, descripcion, monto, fecha, origen)
JOIN proyectos p ON p.nombre = v.proyecto
JOIN usuarios u ON u.nombre = v.usuario
JOIN proveedores pr ON pr.nombre = v.proveedor
JOIN medios_pago mp ON mp.nombre = v.medio
JOIN categorias cat ON cat.nombre = v.categoria
WHERE NOT EXISTS (
    SELECT 1
    FROM gastos g
    WHERE g.proyecto_id = p.id
      AND g.usuario_id = u.id
      AND g.proveedor_id = pr.id
      AND g.fecha_gasto = v.fecha
      AND g.monto_total = v.monto
      AND g.descripcion = v.descripcion
);

COMMIT;

-- Verificación rápida:
-- SELECT count(*) AS gastos_demo FROM gastos;
-- SELECT * FROM v_gastos_detalle ORDER BY fecha_gasto DESC LIMIT 10;
