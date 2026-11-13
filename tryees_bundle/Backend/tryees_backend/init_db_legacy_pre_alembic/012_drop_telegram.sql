-- Notifiche Telegram rimosse dal sistema.
ALTER TABLE practice DROP COLUMN IF EXISTS last_telegram_at;
