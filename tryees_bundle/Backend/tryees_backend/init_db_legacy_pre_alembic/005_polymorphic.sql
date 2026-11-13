-- practice.category
ALTER TABLE practice ADD COLUMN IF NOT EXISTS category VARCHAR DEFAULT 'security';
CREATE INDEX IF NOT EXISTS ix_practice_category ON practice(category);

-- event_camera
CREATE TABLE IF NOT EXISTS event_camera (
    event_id        INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    person_count    INTEGER,
    confidence      FLOAT,
    bbox_json       TEXT,
    frame_url       TEXT,
    alert_type      VARCHAR   -- 'motion', 'person', 'fight', 'scream'
);

-- event_microphone
CREATE TABLE IF NOT EXISTS event_microphone (
    event_id        INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    decibel         FLOAT,
    frequency_hz    FLOAT,
    audio_url       TEXT,
    alert_type      VARCHAR   -- 'scream', 'help', 'noise'
);

-- event_basket
CREATE TABLE IF NOT EXISTS event_basket (
    event_id        INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    fill_level_pct  FLOAT,    -- 0-100
    weight_kg       FLOAT,
    battery_pct     FLOAT,
    last_emptied    TIMESTAMP WITH TIME ZONE
);

-- event_light
CREATE TABLE IF NOT EXISTS event_light (
    event_id        INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    lux_value       FLOAT,
    is_on           BOOLEAN,
    fault_code      VARCHAR
);

-- event_soil
CREATE TABLE IF NOT EXISTS event_soil (
    event_id        INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    humidity_pct    FLOAT,
    temperature_c   FLOAT,
    ph              FLOAT
);

-- Index
CREATE INDEX IF NOT EXISTS ix_ev_camera_event  ON event_camera(event_id);
CREATE INDEX IF NOT EXISTS ix_ev_basket_event  ON event_basket(event_id);
CREATE INDEX IF NOT EXISTS ix_ev_light_event   ON event_light(event_id);

ALTER TABLE event_microphone ADD COLUMN IF NOT EXISTS noise_db FLOAT;
ALTER TABLE event_basket     ADD COLUMN IF NOT EXISTS fill_cm FLOAT;
ALTER TABLE event_basket     ADD COLUMN IF NOT EXISTS tilt_angle FLOAT;
ALTER TABLE event_light      ADD COLUMN IF NOT EXISTS lux_ldr FLOAT;
ALTER TABLE event_camera     ADD COLUMN IF NOT EXISTS temperature_c FLOAT;
ALTER TABLE event_camera     ADD COLUMN IF NOT EXISTS humidity_pct FLOAT;
ALTER TABLE event_soil       ADD COLUMN IF NOT EXISTS pm25 FLOAT;
ALTER TABLE event_soil       ADD COLUMN IF NOT EXISTS pm10 FLOAT;

CREATE TABLE IF NOT EXISTS event_environment (
    event_id      INTEGER PRIMARY KEY REFERENCES event(id) ON DELETE CASCADE,
    temperature_c FLOAT, humidity_pct FLOAT, pm25 FLOAT, pm10 FLOAT,
    noise_db FLOAT, lux FLOAT, co2_ppm FLOAT
);
