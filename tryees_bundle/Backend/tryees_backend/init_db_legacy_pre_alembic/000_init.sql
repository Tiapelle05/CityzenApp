-- Schema iniziale: Enum + tabelle core
-- (Senza campi di stato device: status, is_online, last_seen non sono previsti)

CREATE TYPE type_user AS ENUM ('op_eco', 'admin', 'ente');
CREATE TYPE type_device AS ENUM ('camera', 'microphone', 'light', 'basket', 'soil_sensor');
-- alert: segnale di allerta telecamera
-- eco: cestino pieno
-- assistance: segnale di assistenza
-- weight: peso del cestino
-- humidity: umidità
CREATE TYPE type_event AS ENUM ('alert', 'eco', 'assistance', 'weight', 'humidity', 'light', 'motion', 'light_on', 'is_dark', 'full', 'battery');

-- Utenti applicativi
CREATE TABLE IF NOT EXISTS app_user (
    id SERIAL PRIMARY KEY,
    username VARCHAR NOT NULL UNIQUE,
    password VARCHAR NOT NULL,
    type type_user NOT NULL
);

CREATE INDEX ix_app_user_id ON app_user(id);
CREATE INDEX ix_app_user_username ON app_user(username);

-- Dispositivi fisici nel parco
CREATE TABLE IF NOT EXISTS device (
    mac_address VARCHAR PRIMARY KEY,
    zone VARCHAR,
    type type_device NOT NULL,
    lat text,
    lon text
);


-- Eventi generati dai dispositivi
CREATE TABLE IF NOT EXISTS event (
    id SERIAL PRIMARY KEY,
    mac_address VARCHAR NOT NULL REFERENCES device(mac_address) ON DELETE CASCADE,
    type type_event NOT NULL,
    val_number DOUBLE PRECISION,
    sampling_time TIMESTAMP WITH TIME ZONE,
    transmission_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_event_id ON event(id);

-- Tabella associativa evento-utente (notifiche)
CREATE TABLE IF NOT EXISTS notify (
    id_event INTEGER REFERENCES event(id) ON DELETE CASCADE,
    id_user INTEGER REFERENCES app_user(id) ON DELETE CASCADE,
    PRIMARY KEY (id_event, id_user)
);

-- Tabella per i flussi video associati agli eventi
CREATE TABLE IF NOT EXISTS event_video (
    id SERIAL PRIMARY KEY,
    id_event INTEGER NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    video_url VARCHAR NOT NULL,
    thumbnail_url VARCHAR,
    duration_seconds INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_event_video_event_id ON event_video(id_event);
