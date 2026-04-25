-- Add missing index on geocoder.residence.address_id.
-- Table is 1.7 GB heap; without this index every JOIN on
-- residence ON address_id = address.id is a seq scan.
--
-- CONCURRENTLY: no BEGIN/COMMIT (psql top-level statement),
-- doesn't take a write lock during creation.

CREATE INDEX CONCURRENTLY IF NOT EXISTS residence_address_id_idx
    ON geocoder.residence USING btree (address_id);
