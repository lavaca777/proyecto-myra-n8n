-- =====================================================================
-- Control de migraciones
-- Se ejecuta primero (orden alfabetico) en una base nueva.
-- El script scripts/db-migrate.ps1 usa esta tabla para no repetir archivos.
-- =====================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    filename   TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_migrations (filename)
VALUES ('000_migrations.sql')
ON CONFLICT (filename) DO NOTHING;
