-- =====================================================================
-- Estado pendiente de administración de maestras
-- Permite que WF-07 recuerde en qué paso va un administrador cuando
-- responde con texto después de tocar un botón.
-- =====================================================================

CREATE TABLE IF NOT EXISTS admin_pending (
    id              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id      INTEGER NOT NULL UNIQUE REFERENCES usuarios(id) ON DELETE CASCADE,
    accion          TEXT    NOT NULL
                    CHECK (accion IN ('crear', 'editar', 'desactivar', 'reactivar')),
    paso            TEXT    NOT NULL,
    entidad_id      INTEGER REFERENCES proyectos(id) ON DELETE SET NULL,
    payload         JSONB   NOT NULL DEFAULT '{}'::jsonb,
    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_migrations (filename)
VALUES ('004_admin_pending.sql')
ON CONFLICT (filename) DO NOTHING;
