ALTER TABLE device ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE device ADD COLUMN IF NOT EXISTS lon DOUBLE PRECISION;
DO $$ BEGIN CREATE TYPE practice_status AS ENUM ('open','in_progress','resolved','closed'); EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE TABLE IF NOT EXISTS practice (
    id SERIAL PRIMARY KEY, title VARCHAR NOT NULL,
    status practice_status NOT NULL DEFAULT 'open',
    severity DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    lat DOUBLE PRECISION, lon DOUBLE PRECISION, zone VARCHAR,
    created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ, last_telegram_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS practice_event (
    practice_id INTEGER NOT NULL REFERENCES practice(id) ON DELETE CASCADE,
    event_id INTEGER NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    linked_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (practice_id, event_id)
);
