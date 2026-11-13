CREATE TABLE IF NOT EXISTS practice_audit (
    id SERIAL PRIMARY KEY, practice_id INTEGER NOT NULL REFERENCES practice(id) ON DELETE CASCADE,
    actor VARCHAR NOT NULL, action VARCHAR NOT NULL, detail TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_audit_practice ON practice_audit(practice_id);
