-- load-loket-export (#137) passed JSON.stringify(...) to postgres-js for jsonb
-- columns; the driver JSON-encodes jsonb parameters itself, so the 2,396 loket
-- dossiers got a jsonb STRING holding the object ("{\"source\":...}") instead
-- of the object. payload->>'topic' is null, and `payload || jsonb` would fail.
-- Same for the 'received' entries' body. Unwrap once; idempotent.
--
--   psql "$DB_URL" -f sql/migrate/repair_loket_payload.sql

BEGIN;

UPDATE dataops.dossier
   SET payload = (payload #>> '{}')::jsonb
 WHERE jsonb_typeof(payload) = 'string';

-- The adoption path did `'{}'::jsonb || '"{...}"'::jsonb`, which PostgreSQL
-- turns into an ARRAY [{}, "{...}"] rather than failing. 968 bulk-drop
-- dossiers. Take the string element and parse it.
UPDATE dataops.dossier
   SET payload = (payload ->> 1)::jsonb
 WHERE jsonb_typeof(payload) = 'array'
   AND jsonb_array_length(payload) = 2
   AND jsonb_typeof(payload -> 1) = 'string'
   AND (payload ->> 1) LIKE '{%';

UPDATE dataops.dossier_entry
   SET body = (body #>> '{}')::jsonb
 WHERE jsonb_typeof(body) = 'string';

SELECT (SELECT count(*) FROM dataops.dossier WHERE jsonb_typeof(payload) = 'string') AS dossiers_left,
       (SELECT count(*) FROM dataops.dossier_entry WHERE jsonb_typeof(body) = 'string') AS entries_left;

COMMIT;
