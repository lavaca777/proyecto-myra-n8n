-- =====================================================================
-- Idempotencia de mensajes de Telegram
-- Evita crear dos registros_entrada para el mismo mensaje si Telegram
-- reintenta el webhook. Usa telegram_message_id, que ya existe y se
-- llena para texto y voz.
-- =====================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_registros_usuario_mensaje
    ON registros_entrada (usuario_id, telegram_message_id)
    WHERE telegram_message_id IS NOT NULL;

INSERT INTO schema_migrations (filename)
VALUES ('006_idempotencia_telegram.sql')
ON CONFLICT (filename) DO NOTHING;
