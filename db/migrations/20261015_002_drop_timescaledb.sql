-- TimescaleDB is no longer used: drop the extension (FunderMaps 5.0, loose end L5).
--
-- Its only hypertable, application.product_tracker, became a plain table on 2026-10-15 01:24 Amsterdam (online
-- switch, scripts/ops/product-tracker-plain; 20261015_001 records the end state) and the tool's cleanup dropped the
-- old hypertable at 08:37 the same morning. True on prod when this was written (2026-10-15 09:20): timescaledb
-- 2.28.2 with 0 hypertables, nothing outside the extension's own schemas depends on it (pg_depend), and no code
-- calls a TimescaleDB function.
--
-- The extension is owned by `postgres`, but DigitalOcean's extension whitelist (extwlist) lets doadmin drop it:
-- a test on prod (BEGIN; DROP EXTENSION timescaledb; ROLLBACK, 2026-10-15 09:17) ran in 52 ms. Rehearsed on
-- TimescaleDB 2.28.2 / PostgreSQL 18 under traffic that opened a new connection per transaction: the committed
-- drop took ~0.4 s and nothing waited on it (slowest transaction 54 ms). The lock_timeout makes it fail instead of
-- queueing if anything holds one of the extension's catalog tables; rerun it then.
--
-- The library stays in DigitalOcean's shared_preload_libraries; without the extension it does nothing in this
-- database. Fresh and CI databases never had the extension (scripts/init_db.sh strips it from schema.sql), so
-- there this file is a no-op.

DO $$
DECLARE
    n int;
BEGIN
    IF EXISTS (SELECT FROM pg_extension WHERE extname = 'timescaledb') THEN
        EXECUTE 'SELECT count(*) FROM _timescaledb_catalog.hypertable' INTO n;
        IF n > 0 THEN
            RAISE EXCEPTION 'TimescaleDB still has % hypertable(s); convert them first', n;
        END IF;
    END IF;
END $$;

SET LOCAL lock_timeout = '2s';

DROP EXTENSION IF EXISTS timescaledb;
