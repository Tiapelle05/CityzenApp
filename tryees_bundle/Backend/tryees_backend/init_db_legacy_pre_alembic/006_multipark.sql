-- Parks
CREATE TABLE IF NOT EXISTS park (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR NOT NULL,
    city        VARCHAR NOT NULL DEFAULT 'Legnano',
    address     VARCHAR,
    lat         DOUBLE PRECISION,
    lon         DOUBLE PRECISION,
    active      BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO park (name, city, address, lat, lon)
VALUES ('Parco Robinson', 'Legnano', 'Via Espinasse, Legnano', 45.603215, 8.938087)
ON CONFLICT DO NOTHING;

-- User ↔ Park
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS park_id INTEGER REFERENCES park(id);
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS totp_secret VARCHAR;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS last_login TIMESTAMPTZ;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS failed_logins INTEGER DEFAULT 0;
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

-- Assign all existing users to park 1
UPDATE app_user SET park_id = 1 WHERE park_id IS NULL;

-- Device ↔ Park
ALTER TABLE device ADD COLUMN IF NOT EXISTS park_id INTEGER REFERENCES park(id) DEFAULT 1;
UPDATE device SET park_id = 1 WHERE park_id IS NULL;

-- Practice ↔ Park
ALTER TABLE practice ADD COLUMN IF NOT EXISTS park_id INTEGER REFERENCES park(id) DEFAULT 1;
UPDATE practice SET park_id = 1 WHERE park_id IS NULL;

-- API Keys (device onboarding)
CREATE TABLE IF NOT EXISTS api_key (
    id          SERIAL PRIMARY KEY,
    key         VARCHAR NOT NULL UNIQUE,
    device_mac  VARCHAR REFERENCES device(mac_address) ON DELETE CASCADE,
    park_id     INTEGER NOT NULL REFERENCES park(id),
    label       VARCHAR NOT NULL,
    created_by  INTEGER REFERENCES app_user(id),
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    last_used   TIMESTAMPTZ,
    active      BOOLEAN DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS ix_api_key_key ON api_key(key);

-- Access log
CREATE TABLE IF NOT EXISTS access_log (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER REFERENCES app_user(id),
    username    VARCHAR NOT NULL,
    action      VARCHAR NOT NULL,
    ip          VARCHAR,
    success     BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_access_log_user ON access_log(user_id);
CREATE INDEX IF NOT EXISTS ix_access_log_ts   ON access_log(created_at DESC);

-- Device health snapshots
CREATE TABLE IF NOT EXISTS device_health (
    id          SERIAL PRIMARY KEY,
    mac_address VARCHAR NOT NULL REFERENCES device(mac_address) ON DELETE CASCADE,
    park_id     INTEGER REFERENCES park(id),
    is_online   BOOLEAN NOT NULL,
    latency_ms  INTEGER,
    event_count INTEGER DEFAULT 0,
    checked_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_device_health_mac ON device_health(mac_address, checked_at DESC);
