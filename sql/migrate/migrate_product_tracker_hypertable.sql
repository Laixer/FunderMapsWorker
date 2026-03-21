-- migrate_product_tracker_hypertable.sql
-- Converts application.product_tracker from yearly range partitions to a TimescaleDB monthly hypertable.
--
-- Prerequisites:
--   - application.product_tracker_new already exists as an empty hypertable (done)
--   - product_tracker_count_idx already dropped (done)
--   - Run via direct connection (port 25060), NOT PgBouncer
--
-- Usage:
--   source .env.local
--   PGPASSWORD=$FUNDERMAPS_DB_PASSWORD psql -h $FUNDERMAPS_DB_HOST -p $FUNDERMAPS_DB_PORT \
--     -U $FUNDERMAPS_DB_USER -d $FUNDERMAPS_DB_NAME --set=sslmode=require -f sql/migrate_product_tracker_hypertable.sql

\timing on

-- Step 1: Bulk data migration (~10-20 min for 19M rows)
\echo '=== Step 1: Migrating data ==='
INSERT INTO application.product_tracker_new
  SELECT * FROM application.product_tracker;

-- Step 2: Create index on new table
\echo '=== Step 2: Creating index ==='
CREATE INDEX product_tracker_new_org_prod_id_date_idx
  ON application.product_tracker_new
  USING btree (organization_id, product, identifier, create_date);

-- Step 3: Catch-up rows inserted during migration + atomic swap
\echo '=== Step 3: Atomic swap ==='
BEGIN;

-- Lock both tables to prevent writes during swap
LOCK TABLE application.product_tracker IN ACCESS EXCLUSIVE MODE;
LOCK TABLE application.product_tracker_new IN ACCESS EXCLUSIVE MODE;

-- Insert any rows that arrived during the bulk migration
INSERT INTO application.product_tracker_new
  SELECT * FROM application.product_tracker pt
  WHERE NOT EXISTS (
    SELECT 1 FROM application.product_tracker_new ptn
    WHERE ptn.organization_id = pt.organization_id
      AND ptn.product = pt.product
      AND ptn.building_id = pt.building_id
      AND ptn.create_date = pt.create_date
      AND ptn.identifier = pt.identifier
  );

-- Swap
ALTER TABLE application.product_tracker RENAME TO product_tracker_old;
ALTER TABLE application.product_tracker_new RENAME TO product_tracker;

-- Rename index to match
ALTER INDEX application.product_tracker_new_org_prod_id_date_idx
  RENAME TO product_tracker_org_prod_id_date_idx;

-- Rename constraints to match
ALTER TABLE application.product_tracker
  RENAME CONSTRAINT product_tracker_new_building_id_fkey TO product_tracker_building_id_fkey;
ALTER TABLE application.product_tracker
  RENAME CONSTRAINT product_tracker_new_organization_id_fkey TO product_tracker_organization_id_fkey;

COMMIT;

-- Step 4: Verify
\echo '=== Step 4: Verification ==='
SELECT 'old' AS table, count(*) FROM application.product_tracker_old
UNION ALL
SELECT 'new', count(*) FROM application.product_tracker;

SELECT chunk_name, range_start, range_end, pg_size_pretty(total_bytes) AS size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'product_tracker'
ORDER BY range_start;

\echo '=== Migration complete ==='
\echo 'Verify the app works, then drop the old table:'
\echo '  DROP TABLE application.product_tracker_old;'
