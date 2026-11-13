-- Bug in 000_init.sql: device.lat/lon create come TEXT. 002_practices.sql
-- prova a "correggerle" con ADD COLUMN IF NOT EXISTS DOUBLE PRECISION, ma
-- essendo le colonne già esistenti (come text) quella riga non fa nulla.
-- Su un DB creato da zero (tutte le migration in sequenza) restano text
-- per sempre, causando "Unknown PG numeric type: 25" alla prima query.
ALTER TABLE device ALTER COLUMN lat TYPE DOUBLE PRECISION USING NULLIF(lat, '')::double precision;
ALTER TABLE device ALTER COLUMN lon TYPE DOUBLE PRECISION USING NULLIF(lon, '')::double precision;
