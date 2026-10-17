-- =====================================================================
-- Sistema de registro de gastos por voz - Constructora MYRA
-- Esquema de base de datos (PostgreSQL)  |  versión 2.0
-- Convenciones:
--   * Montos en pesos chilenos como BIGINT (CLP no usa decimales)
--   * Borrado lógico (activo / estado) en vez de borrar filas
--   * El cliente NO se registra en el gasto: se infiere por el proyecto
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. USUARIOS: quién puede usar el bot (whitelist por chat de Telegram)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    telegram_chat_id  BIGINT      NOT NULL UNIQUE,
    nombre            TEXT        NOT NULL,
    rol               TEXT        NOT NULL DEFAULT 'jefe_obra'
                      CHECK (rol IN ('jefe_obra', 'administrador', 'gerencia')),
    activo            BOOLEAN     NOT NULL DEFAULT TRUE,
    creado_en         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. CLIENTES: un cliente puede tener varios proyectos
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     TEXT        NOT NULL UNIQUE,
    activo     BOOLEAN     NOT NULL DEFAULT TRUE,
    creado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3. PROYECTOS: obras activas. Los crea el administrador manualmente.
--    Cada proyecto pertenece a un único cliente.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proyectos (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id INTEGER     NOT NULL REFERENCES clientes(id),
    nombre     TEXT        NOT NULL UNIQUE,
    activo     BOOLEAN     NOT NULL DEFAULT TRUE,
    creado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Alias de cada proyecto: cómo lo nombran realmente los jefes de obra.
-- Sirve para el fuzzy matching del NLU ("la obra de Peñuelas").
CREATE TABLE IF NOT EXISTS proyecto_alias (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proyecto_id  INTEGER NOT NULL REFERENCES proyectos(id) ON DELETE CASCADE,
    alias        TEXT    NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_proyecto_alias ON proyecto_alias (lower(alias));

-- ---------------------------------------------------------------------
-- 4. CATEGORÍAS de gasto (listado que ya usa MYRA en su Excel)
--    usa_bot = TRUE: el bot puede sugerirla al interpretar un audio de obra.
--    Las de tipo administrativo/tributario se registran de otra forma.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categorias (
    id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre   TEXT    NOT NULL UNIQUE,
    usa_bot  BOOLEAN NOT NULL DEFAULT TRUE,
    activo   BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 5. MEDIOS DE PAGO
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS medios_pago (
    id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  TEXT    NOT NULL UNIQUE,
    activo  BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 6. PROVEEDORES: lugar o empresa donde se compra (en el Excel: "Empresa").
--    Se crean automáticamente la primera vez que se mencionan.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proveedores (
    id                 INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre             TEXT NOT NULL,
    -- minúsculas y sin tildes, para evitar duplicados ("Sodimac" / "sodimac")
    nombre_normalizado TEXT NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 7. REGISTROS_ENTRADA: bitácora de cada audio/foto/texto recibido.
--    a) borrador mientras el usuario confirma (estado de la conversación)
--    b) auditoría: qué dijo el usuario y qué entendió la IA
--    c) medir la precisión (>80%) comparando lo extraído vs lo confirmado
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS registros_entrada (
    id                  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id          INTEGER     NOT NULL REFERENCES usuarios(id),
    tipo                TEXT        NOT NULL DEFAULT 'voz'
                        CHECK (tipo IN ('voz', 'foto', 'texto')),
    telegram_message_id BIGINT,
    telegram_file_id    TEXT,
    transcripcion       TEXT,
    json_extraido       JSONB,           -- campos según la IA
    modelo_ia           TEXT,            -- para comparar Gemini vs API de bajo costo
    duracion_ms         INTEGER,         -- meta: < 60 s
    estado              TEXT        NOT NULL DEFAULT 'procesando'
                        CHECK (estado IN ('procesando', 'falta_dato',
                                          'pendiente_confirmacion', 'confirmado',
                                          'cancelado', 'error')),
    campo_pendiente     TEXT,            -- ej. 'proyecto' cuando el bot pregunta por él
    error_detalle       TEXT,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION set_actualizado_en() RETURNS trigger AS $$
BEGIN
    NEW.actualizado_en = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_registros_actualizado ON registros_entrada;
CREATE TRIGGER trg_registros_actualizado
    BEFORE UPDATE ON registros_entrada
    FOR EACH ROW EXECUTE FUNCTION set_actualizado_en();

-- ---------------------------------------------------------------------
-- 8. GASTOS: registro final y confirmado.
--    5 campos críticos: Proyecto, Monto, Fecha, Proveedor, Medio de pago.
--    Categoría y descripción son complementarias (la IA las infiere).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gastos (
    id                  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proyecto_id         INTEGER     NOT NULL REFERENCES proyectos(id),   -- objetivo: 100% con proyecto
    usuario_id          INTEGER     NOT NULL REFERENCES usuarios(id),
    proveedor_id        INTEGER     REFERENCES proveedores(id),
    medio_pago_id       INTEGER     REFERENCES medios_pago(id),
    categoria_id        INTEGER     REFERENCES categorias(id),
    descripcion         TEXT,                                             -- "qué se compró"
    monto_total         BIGINT      NOT NULL CHECK (monto_total > 0),     -- CLP
    fecha_gasto         DATE        NOT NULL,
    origen              TEXT        NOT NULL DEFAULT 'voz'
                        CHECK (origen IN ('voz', 'foto', 'texto')),
    estado              TEXT        NOT NULL DEFAULT 'confirmado'
                        CHECK (estado IN ('confirmado', 'anulado')),
    registro_entrada_id INTEGER     UNIQUE REFERENCES registros_entrada(id),
    registrado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 9. COMPROBANTES: documento que respalda el gasto (factura, boleta u otro).
--    Una factura da derecho a crédito fiscal de IVA y una boleta no,
--    por eso se distingue el tipo.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS comprobantes (
    id               INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gasto_id         INTEGER     NOT NULL REFERENCES gastos(id) ON DELETE CASCADE,
    tipo_documento   TEXT        NOT NULL DEFAULT 'factura'
                     CHECK (tipo_documento IN ('factura', 'boleta', 'otro')),
    numero_documento TEXT,
    telegram_file_id TEXT,
    texto_ocr        TEXT,
    subido_en        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- ÍNDICES para consultas frecuentes (resúmenes, filtros y exportaciones)
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_proyectos_cliente     ON proyectos (cliente_id);
CREATE INDEX IF NOT EXISTS idx_gastos_proyecto_fecha ON gastos (proyecto_id, fecha_gasto);
CREATE INDEX IF NOT EXISTS idx_gastos_categoria      ON gastos (categoria_id);
CREATE INDEX IF NOT EXISTS idx_gastos_fecha          ON gastos (fecha_gasto);
CREATE INDEX IF NOT EXISTS idx_registros_usuario_est ON registros_entrada (usuario_id, estado);

-- ---------------------------------------------------------------------
-- VISTA: gastos con nombres legibles. El cliente sale del proyecto.
-- Sirve para /resumen, filtros por cliente/categoría y exportar CSV/Excel.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_gastos_detalle AS
SELECT g.id,
       g.fecha_gasto,
       c.nombre   AS cliente,
       p.nombre   AS proyecto,
       cat.nombre AS categoria,
       pr.nombre  AS proveedor,
       g.descripcion,
       mp.nombre  AS medio_pago,
       g.monto_total,
       u.nombre   AS registrado_por,
       g.origen,
       g.registrado_en
FROM gastos g
JOIN proyectos p           ON p.id   = g.proyecto_id
JOIN clientes c            ON c.id   = p.cliente_id
JOIN usuarios u            ON u.id   = g.usuario_id
LEFT JOIN categorias cat   ON cat.id = g.categoria_id
LEFT JOIN proveedores pr   ON pr.id  = g.proveedor_id
LEFT JOIN medios_pago mp   ON mp.id  = g.medio_pago_id
WHERE g.estado = 'confirmado';

-- ---------------------------------------------------------------------
-- Registro de esta migracion
-- ---------------------------------------------------------------------
INSERT INTO schema_migrations (filename)
VALUES ('001_schema_inicial.sql')
ON CONFLICT (filename) DO NOTHING;
