-- migrate: no-transaction
--
-- An index for the duplicate check on every billing insert (Laixer/FunderMapsWebservice#16).
--
-- The Webservice and the API insert a row into application.product_tracker unless the same
-- organisation, product and pand already have one from the last 24 hours. No index fits that. As a
-- prepared statement it gets a BitmapAnd of the index on building_id and the one on (organization_id,
-- product, create_date), and the second reads all of that organisation's rows of the last 24 hours, on
-- every insert. A large batch gets slower as it runs. The caller waits for this insert.
--
-- True on prod 2026-11-05: the heaviest statement on the database by a factor of 12, 99 ms on average and
-- about 3,000 blocks per call.
--
-- One statement, because the runner sends a no-transaction file as one query. CONCURRENTLY keeps inserts
-- going during the build, but it waits for older transactions, so don't apply this during the model
-- refresh. A failed build leaves an INVALID index that IF NOT EXISTS then passes over: the next migration
-- checks for that and refuses.
CREATE INDEX CONCURRENTLY IF NOT EXISTS product_tracker_org_prod_building_date_idx
    ON application.product_tracker (organization_id, product, building_id, create_date);
