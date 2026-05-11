-- Drop 'service' from application.role enum.
--
-- The value was a holdover from an early plan to provision service
-- accounts via the user table. It was never used — `application.role` is
-- ('administrator', 'user', 'service') and 0 rows have role = 'service'.
--
-- Postgres can't drop enum values directly, so the type is recreated
-- with the same OID-stable trick: rename old, create new, ALTER COLUMN
-- USING the cast, drop old.
--
-- C# Webservice safety: Npgsql's `MapEnum<ApplicationRole>` is lazy and
-- only validates per-row, so dropping the DB value while the C# enum
-- still has Service = 2 is safe (no rows ever hit that value). The
-- matching enum entry is also being removed in the FunderMaps repo
-- (chore/drop-role-service-enum-value) for cleanliness.

BEGIN;

ALTER TYPE application.role RENAME TO role_old;

CREATE TYPE application.role AS ENUM ('administrator', 'user');

ALTER TABLE application.user
    ALTER COLUMN role DROP DEFAULT,
    ALTER COLUMN role TYPE application.role
        USING role::text::application.role,
    ALTER COLUMN role SET DEFAULT 'user'::application.role;

DROP TYPE application.role_old;

COMMIT;
