-- =====================================================================
-- Modo administración para WF-07
-- Permite que admin_pending guarde una sesión abierta de administración
-- además de las acciones concretas sobre proyectos.
-- =====================================================================

ALTER TABLE admin_pending
    DROP CONSTRAINT IF EXISTS admin_pending_accion_check;

ALTER TABLE admin_pending
    ADD CONSTRAINT admin_pending_accion_check
    CHECK (accion IN ('modo', 'crear', 'editar', 'desactivar', 'reactivar'));

INSERT INTO schema_migrations (filename)
VALUES ('005_admin_modo.sql')
ON CONFLICT (filename) DO NOTHING;
