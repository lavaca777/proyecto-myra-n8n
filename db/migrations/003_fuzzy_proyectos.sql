-- =====================================================================
-- Busqueda difusa de proyectos (Riesgo 5 del charter)
-- "la obra de Penuelas" debe encontrar "Obra Penuelas" aunque el STT
-- escriba distinto. pg_trgm permite similitud por trigramas.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- Permite comparar "Penuelas" con "Peñuelas".
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE INDEX IF NOT EXISTS idx_proyectos_nombre_trgm
    ON proyectos USING gin (nombre gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_proyecto_alias_trgm
    ON proyecto_alias USING gin (lower(alias) gin_trgm_ops);

-- ---------------------------------------------------------------------
-- Registro de esta migracion
-- ---------------------------------------------------------------------
INSERT INTO schema_migrations (filename)
VALUES ('003_fuzzy_proyectos.sql')
ON CONFLICT (filename) DO NOTHING;
