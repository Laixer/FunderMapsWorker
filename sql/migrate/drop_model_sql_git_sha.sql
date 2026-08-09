-- Drop model_version.sql_git_sha.
--
-- It named the last commit touching sql/model/, which was a tile fix rather
-- than a model change; sql/model/ holds tile builders, statistics and boundary
-- layers that move it without touching a risk calculation; and it described the
-- repository rather than the database. data.model_definition_sha256() already
-- identifies a version from what is actually deployed, so the git pointer
-- carried no information anyone could act on.
--
--   psql "$DB_URL" -f sql/migrate/drop_model_sql_git_sha.sql

BEGIN;

ALTER TABLE data.model_version DROP COLUMN sql_git_sha;

COMMIT;
