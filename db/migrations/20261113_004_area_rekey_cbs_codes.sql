-- gfm retirement (Worker #158, step 3, part 2b): the CBS code becomes the id of province, municipality, district and
-- neighbourhood, and geocoder.building points at its neighbourhood by that code.
--
-- Values only: no column, type, view, materialized view or function changes. geocoder.geocoder_id is text without a
-- check, and everything that joins the chain joins id to *_id, so it keeps joining. Afterwards id = external_id on the
-- four tables (BU / WK / GM / PV codes) and legacy_id holds what id was.
--
-- Prod 2026-11-13 (read-only): geocoder.building has 12,805,766 rows, 3,826 without a neighbourhood (they stay
-- without), heap 8.3 GB, three indexes 2.8 GB, no triggers. Every row with a neighbourhood is rewritten once.
--
-- data.building_precomputed (11.3M rows, 2.2 GB) goes along in the same transaction. It is the model's own copy of
-- that reference, and it is refilled only by hand after a BAG load (sql/load/refresh_precomputed.sql), not by the
-- twice-daily refresh: left alone, the 2026.3 model would keep reading the old ids from it.
--
-- One transaction: a reader sees the old ids until COMMIT and the new ones after, never a mix, and is not held up
-- (only row locks are taken; the foreign keys went in the migration before this one). Nothing else may write
-- geocoder.building or data.building_precomputed meanwhile: no BAG load.
--
-- Rehearsed 2026-11-13 on a full-size copy of both tables (a 4 vCPU / 8 GB machine that was busy with other work):
-- 54 minutes for this file, 29 GB of write-ahead log, about 2.6 million stand-in reads meanwhile with no error and no
-- wrong answer, and afterwards every building on the same neighbourhood, district, municipality and province as before.
--
-- Not touched here, because a materialized view cannot be updated: data.model_risk_static_2026_3 and the nine
-- data.statistics_product_* views hold the old ids until their next refresh; legacy_id resolves those.
-- data.model_risk_static_2024_1 is frozen (not refreshed since 2026-10-19) and keeps the old ids as they were.

DO $$
DECLARE
  linked bigint;
  rewritten bigint;
BEGIN
  -- before: this must be the first run, on tables as 20261113_002 left them
  IF EXISTS (SELECT 1 FROM geocoder.neighborhood WHERE legacy_id IS DISTINCT FROM id)
     OR EXISTS (SELECT 1 FROM geocoder.district WHERE legacy_id IS DISTINCT FROM id)
     OR EXISTS (SELECT 1 FROM geocoder.municipality WHERE legacy_id IS DISTINCT FROM id)
     OR EXISTS (SELECT 1 FROM geocoder.state WHERE legacy_id IS DISTINCT FROM id) THEN
    RAISE EXCEPTION 'legacy_id does not repeat id on every area row: 20261113_002 not applied, or the rekey already ran';
  END IF;

  SELECT count(*) INTO linked FROM geocoder.building WHERE neighborhood_id IS NOT NULL;

  -- the one large statement: every building takes the code of the neighbourhood it already points at
  UPDATE geocoder.building b SET neighborhood_id = n.external_id
    FROM geocoder.neighborhood n WHERE n.id = b.neighborhood_id;
  GET DIAGNOSTICS rewritten = ROW_COUNT;
  IF rewritten <> linked THEN
    RAISE EXCEPTION '% buildings have a neighbourhood but % were given its code', linked, rewritten;
  END IF;

  -- the model's copy of the same reference
  SELECT count(*) INTO linked FROM data.building_precomputed WHERE neighborhood_id IS NOT NULL;
  UPDATE data.building_precomputed bp SET neighborhood_id = n.external_id
    FROM geocoder.neighborhood n WHERE n.id = bp.neighborhood_id;
  GET DIAGNOSTICS rewritten = ROW_COUNT;
  IF rewritten <> linked THEN
    RAISE EXCEPTION '% precomputed buildings have a neighbourhood but % were given its code', linked, rewritten;
  END IF;

  -- the chain's own references, child before parent
  UPDATE geocoder.neighborhood n SET district_id = d.external_id FROM geocoder.district d WHERE d.id = n.district_id;
  GET DIAGNOSTICS rewritten = ROW_COUNT;
  IF rewritten <> (SELECT count(*) FROM geocoder.neighborhood) THEN RAISE EXCEPTION 'a neighbourhood without its district'; END IF;

  UPDATE geocoder.district d SET municipality_id = m.external_id FROM geocoder.municipality m WHERE m.id = d.municipality_id;
  GET DIAGNOSTICS rewritten = ROW_COUNT;
  IF rewritten <> (SELECT count(*) FROM geocoder.district) THEN RAISE EXCEPTION 'a district without its municipality'; END IF;

  UPDATE geocoder.municipality m SET state_id = s.external_id FROM geocoder.state s WHERE s.id = m.state_id;
  GET DIAGNOSTICS rewritten = ROW_COUNT;
  IF rewritten <> (SELECT count(*) FROM geocoder.municipality) THEN RAISE EXCEPTION 'a municipality without its province'; END IF;

  -- the ids themselves
  UPDATE geocoder.neighborhood SET id = external_id;
  UPDATE geocoder.district SET id = external_id;
  UPDATE geocoder.municipality SET id = external_id;
  UPDATE geocoder.state SET id = external_id;

  -- after: every reference resolves, and nothing of the old ids is left in the chain
  IF EXISTS (SELECT 1 FROM geocoder.building b WHERE b.neighborhood_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM geocoder.neighborhood n WHERE n.id = b.neighborhood_id)) THEN
    RAISE EXCEPTION 'a building points at a neighbourhood that does not exist';
  END IF;
  IF EXISTS (SELECT 1 FROM geocoder.neighborhood n WHERE NOT EXISTS (SELECT 1 FROM geocoder.district d WHERE d.id = n.district_id))
     OR EXISTS (SELECT 1 FROM geocoder.district d WHERE NOT EXISTS (SELECT 1 FROM geocoder.municipality m WHERE m.id = d.municipality_id))
     OR EXISTS (SELECT 1 FROM geocoder.municipality m WHERE NOT EXISTS (SELECT 1 FROM geocoder.state s WHERE s.id = m.state_id)) THEN
    RAISE EXCEPTION 'the area chain is broken';
  END IF;
  IF EXISTS (SELECT 1 FROM geocoder.neighborhood WHERE id LIKE 'gfm-%' OR district_id LIKE 'gfm-%' OR id <> external_id)
     OR EXISTS (SELECT 1 FROM geocoder.district WHERE id LIKE 'gfm-%' OR municipality_id LIKE 'gfm-%' OR id <> external_id)
     OR EXISTS (SELECT 1 FROM geocoder.municipality WHERE id LIKE 'gfm-%' OR state_id LIKE 'gfm-%' OR id <> external_id)
     OR EXISTS (SELECT 1 FROM geocoder.state WHERE id LIKE 'gfm-%' OR id <> external_id) THEN
    RAISE EXCEPTION 'an old id is left in the area chain';
  END IF;
END $$;
