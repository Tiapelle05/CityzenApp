-- event_alarm: storico sirena + LED polizia del modellino
CREATE TABLE IF NOT EXISTS event_alarm (
    id                 SERIAL PRIMARY KEY,
    device_id          VARCHAR NOT NULL REFERENCES device(mac_address) ON DELETE CASCADE,
    alarm_type         VARCHAR NOT NULL,           -- 'VANDALISMO', 'AFFOLLAMENTO'
    sirena_active      BOOLEAN DEFAULT FALSE,
    led_police_active  BOOLEAN DEFAULT FALSE,
    timestamp          TIMESTAMPTZ DEFAULT NOW(),
    resolved           BOOLEAN DEFAULT FALSE,
    resolved_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_event_alarm_device    ON event_alarm(device_id);
CREATE INDEX IF NOT EXISTS ix_event_alarm_resolved  ON event_alarm(resolved);

-- mini_video_log: video mock collegati agli allarmi del modellino
-- (tabella distinta da 'event_video', già usata per le clip reali della
--  telecamera con schema id_event/video_url)
CREATE TABLE IF NOT EXISTS mini_video_log (
    id            SERIAL PRIMARY KEY,
    device_id     VARCHAR NOT NULL REFERENCES device(mac_address) ON DELETE CASCADE,
    video_path    VARCHAR NOT NULL,
    trigger_event VARCHAR,
    timestamp     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_mini_video_log_device ON mini_video_log(device_id);
