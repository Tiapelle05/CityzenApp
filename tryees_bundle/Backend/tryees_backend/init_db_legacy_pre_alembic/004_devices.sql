ALTER TABLE device ADD COLUMN IF NOT EXISTS status VARCHAR DEFAULT 'ok';
ALTER TABLE device ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE device ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP WITH TIME ZONE;

CREATE TABLE IF NOT EXISTS maintenance_log (
    id          SERIAL PRIMARY KEY,
    mac_address VARCHAR NOT NULL REFERENCES device(mac_address) ON DELETE CASCADE,
    actor       VARCHAR NOT NULL,
    action      VARCHAR NOT NULL,
    notes       TEXT,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_maint_mac ON maintenance_log(mac_address);
CREATE INDEX IF NOT EXISTS ix_maint_ts  ON maintenance_log(created_at DESC);
