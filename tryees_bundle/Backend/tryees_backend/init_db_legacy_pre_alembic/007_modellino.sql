-- Nodi ESP32 del modellino/miniparco fisico
-- Nodo 1: Sensori Parco (temp/umidità/PM2.5/umidità suolo)
-- Nodo 2: Varchi & Accessi (conteggio ingressi/uscite)
-- Nodo 3: Smart Bin (riempimento + MPU6050 anti-vandalismo + LED)
-- Nodo 4: Display & HMI (schermo TFT/OLED + LED di segnalazione)
ALTER TYPE type_device ADD VALUE IF NOT EXISTS 'mini_ambiente';
ALTER TYPE type_device ADD VALUE IF NOT EXISTS 'mini_varchi';
ALTER TYPE type_device ADD VALUE IF NOT EXISTS 'mini_bin';
ALTER TYPE type_device ADD VALUE IF NOT EXISTS 'mini_display';

ALTER TYPE type_event ADD VALUE IF NOT EXISTS 'ingresso';
ALTER TYPE type_event ADD VALUE IF NOT EXISTS 'uscita';

-- Buzzer: quando/se un dispositivo deve far suonare l'allarme
ALTER TABLE device ADD COLUMN IF NOT EXISTS buzzer_active BOOLEAN DEFAULT FALSE;
ALTER TABLE device ADD COLUMN IF NOT EXISTS buzzer_triggered_at TIMESTAMPTZ;

-- Fix: colonne già create in 005 ma mai dichiarate negli ORM
-- (idempotenti, non fanno danno se già presenti)
ALTER TABLE event_camera     ADD COLUMN IF NOT EXISTS temperature_c FLOAT;
ALTER TABLE event_camera     ADD COLUMN IF NOT EXISTS humidity_pct FLOAT;
ALTER TABLE event_microphone ADD COLUMN IF NOT EXISTS noise_db FLOAT;
ALTER TABLE event_basket     ADD COLUMN IF NOT EXISTS fill_cm FLOAT;
ALTER TABLE event_basket     ADD COLUMN IF NOT EXISTS tilt_angle FLOAT;
ALTER TABLE event_light      ADD COLUMN IF NOT EXISTS lux_ldr FLOAT;
ALTER TABLE event_soil       ADD COLUMN IF NOT EXISTS pm25 FLOAT;
ALTER TABLE event_soil       ADD COLUMN IF NOT EXISTS pm10 FLOAT;
ALTER TABLE event_soil       ADD COLUMN IF NOT EXISTS noise_db FLOAT;

-- Seed: 4 nodi del modellino (MAC placeholder, da aggiornare quando
--    l'hardware reale sarà pronto — zone='Modellino' li distingue dal
--    parco vero, la dashboard filtra su questo prefisso)
INSERT INTO device (mac_address, zone, type, lat, lon, status) VALUES
  ('mini:01:amb:01:01:01', 'Modellino - Nodo 1 Sensori Ambiente', 'mini_ambiente', NULL, NULL, 'ok'),
  ('mini:02:var:02:02:02', 'Modellino - Nodo 2 Varchi & Accessi', 'mini_varchi',   NULL, NULL, 'ok'),
  ('mini:03:bin:03:03:03', 'Modellino - Nodo 3 Smart Bin',        'mini_bin',      NULL, NULL, 'ok'),
  ('mini:04:dsp:04:04:04', 'Modellino - Nodo 4 Display & HMI',    'mini_display',  NULL, NULL, 'ok')
ON CONFLICT (mac_address) DO NOTHING;
