-- application.product_tracker is a plain table, no longer a TimescaleDB hypertable (FunderMaps 5.0, loose end L5).
--
-- On prod the hypertable was converted ONLINE on 2026-10-15 01:24 Amsterdam with scripts/ops/product-tracker-plain (a mirror trigger, a copy
-- from one snapshot, then a rename swap of about a second; see its README). This file does not convert anything: one
-- transaction would hold the billing table for minutes. It refuses where the table is still a hypertable and
-- otherwise brings the database to the end state the online switch leaves behind.
--
-- schema.sql (and so every bootstrapped dev or CI database) already creates a plain table; there this file only
-- adds the index below. On prod it is a no-op once the switch has run (the switch builds the same index).
--
-- Why the extra index: the hypertable's monthly chunks kept the time-bounded queries small. On one plain table
-- the Webservice rate limit (organization, product, since the window start), the two dedups and the usage
-- queries need an index that ends in create_date. Rehearsal on a 12M-row copy (2026-10-14): rate limit 17.9 →
-- 2.8 ms, WS dedup 12.7 → 0.4 ms, no query shape slower. The three existing indexes stay unchanged.

DO $$
BEGIN
    -- chunks inherit from their hypertable, so pg_inherits answers without needing the extension's catalog
    IF EXISTS (SELECT FROM pg_inherits WHERE inhparent = 'application.product_tracker'::regclass) THEN
        RAISE EXCEPTION 'application.product_tracker is still a hypertable: convert it online with scripts/ops/product-tracker-plain first';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS product_tracker_org_prod_date_idx
    ON application.product_tracker USING btree (organization_id, product, create_date);
