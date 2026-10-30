-- Drop public.resource_status, the last FunderMaps object in schema public (Yorick 2026-10-30: "drop the enum").
--
-- The enum (uploaded, processing, active, archived; owner fundermaps) is a leftover: application.file_resource.status
-- is a plain text column, and the only thing using the type was that column's default, 'uploaded'::resource_status.
-- No code names it; Drizzle declares the column as text().default("uploaded"). The default becomes the same value as
-- plain text, then the type goes. Everything else in public belongs to PostGIS, pgcrypto and pg_stat_statements
-- (prod, 2026-10-30, read-only).

SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF (SELECT format_type(atttypid, atttypmod) FROM pg_attribute
         WHERE attrelid = 'application.file_resource'::regclass AND attname = 'status') <> 'text' THEN
        RAISE EXCEPTION 'application.file_resource.status is no longer text; stopping';
    END IF;
END
$$;

ALTER TABLE application.file_resource ALTER COLUMN status SET DEFAULT 'uploaded';

DROP TYPE public.resource_status;
