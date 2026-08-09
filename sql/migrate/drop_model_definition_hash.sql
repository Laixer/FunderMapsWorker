-- Remove hashing from the model registry entirely.
--
-- Drops model_version.definition_sha256 (and the CHECK that required it) and
-- data.model_definition_sha256(). No hashes or checksums are kept.
--
-- A version is therefore identified by its slug, described by its notes, and
-- pinned to its data by `inputs`. Nothing records the logic itself.
--
-- Supersedes add_model_definition_hash.sql and drop_model_sql_git_sha.sql; all
-- three are kept in the migration history because they were applied to prod.
--
--   psql "$DB_URL" -f sql/migrate/drop_model_definition_hash.sql

BEGIN;

-- The CHECK references the column and is dropped with it.
ALTER TABLE data.model_version DROP COLUMN definition_sha256;

DROP FUNCTION IF EXISTS data.model_definition_sha256();

COMMIT;
