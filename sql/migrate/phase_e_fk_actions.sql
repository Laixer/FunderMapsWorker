-- Phase E: explicit FK actions on the 16 FKs that were left at the
-- Postgres default of NO ACTION/NO ACTION. Categorisation:
--
--   A. derived-from-building data        → ON DELETE CASCADE  (9)
--   B. parent-child geographic hierarchy → ON DELETE CASCADE  (4)
--   C. nullable, parent can disappear    → ON DELETE SET NULL (2)
--   D. customer data — fail loudly       → ON DELETE RESTRICT (1)
--
-- All 16 also get ON UPDATE CASCADE (matches existing pattern on FKs
-- that already had explicit actions).
--
-- Pattern: DROP + ADD CONSTRAINT NOT VALID under one transaction,
-- then VALIDATE CONSTRAINT in separate statements.
--   - DROP+ADD NOT VALID is metadata-only (fast, AccessExclusiveLock
--     held only briefly per table)
--   - VALIDATE only needs ShareUpdateExclusiveLock (concurrent
--     reads/writes proceed); essential for data.subsidence_history
--     (10 GB / 132M rows) which would otherwise lock for minutes.
--
-- Existing data is already valid against these parents — the prior
-- FKs with NO ACTION still enforced referential integrity at
-- INSERT/UPDATE time. So all 16 VALIDATEs should succeed.
--
-- Run as: fundermaps (owner)

BEGIN;

-- =============================================================================
-- Category A — derived-from-building → ON DELETE CASCADE
-- =============================================================================

ALTER TABLE data.building_cluster DROP CONSTRAINT building_cluster_building_id_fkey;
ALTER TABLE data.building_cluster ADD CONSTRAINT building_cluster_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_elevation DROP CONSTRAINT building_elevation_building_id_fkey;
ALTER TABLE data.building_elevation ADD CONSTRAINT building_elevation_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_geographic_region DROP CONSTRAINT building_geographic_region_building_id_fkey;
ALTER TABLE data.building_geographic_region ADD CONSTRAINT building_geographic_region_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_groundwater_level DROP CONSTRAINT building_groundwater_level_building_id_fkey;
ALTER TABLE data.building_groundwater_level ADD CONSTRAINT building_groundwater_level_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_ownership DROP CONSTRAINT building_ownership_building_id_fkey;
ALTER TABLE data.building_ownership ADD CONSTRAINT building_ownership_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_pleistocene DROP CONSTRAINT building_pleistocene_building_id_fkey;
ALTER TABLE data.building_pleistocene ADD CONSTRAINT building_pleistocene_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.building_subsidence DROP CONSTRAINT building_subsidence_building_id_fkey;
ALTER TABLE data.building_subsidence ADD CONSTRAINT building_subsidence_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE data.subsidence_history DROP CONSTRAINT subsidence_history_building_id_fkey;
ALTER TABLE data.subsidence_history ADD CONSTRAINT subsidence_history_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE geocoder.residence DROP CONSTRAINT residence_building_id_fkey;
ALTER TABLE geocoder.residence ADD CONSTRAINT residence_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

-- =============================================================================
-- Category B — geographic hierarchy → ON DELETE CASCADE
-- =============================================================================

ALTER TABLE geocoder.district DROP CONSTRAINT district_municipality_id_fkey;
ALTER TABLE geocoder.district ADD CONSTRAINT district_municipality_id_fkey
    FOREIGN KEY (municipality_id) REFERENCES geocoder.municipality(id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE geocoder.neighborhood DROP CONSTRAINT neighborhood_district_id_fkey;
ALTER TABLE geocoder.neighborhood ADD CONSTRAINT neighborhood_district_id_fkey
    FOREIGN KEY (district_id) REFERENCES geocoder.district(id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE geocoder.state DROP CONSTRAINT state_country_id_fkey;
ALTER TABLE geocoder.state ADD CONSTRAINT state_country_id_fkey
    FOREIGN KEY (country_id) REFERENCES geocoder.country(id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

ALTER TABLE geocoder.residence DROP CONSTRAINT residence_address_id_fkey;
ALTER TABLE geocoder.residence ADD CONSTRAINT residence_address_id_fkey
    FOREIGN KEY (address_id) REFERENCES geocoder.address(external_id)
    ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;

-- =============================================================================
-- Category C — nullable, parent loss is recoverable → ON DELETE SET NULL
-- =============================================================================

ALTER TABLE geocoder.address DROP CONSTRAINT address_building_id_fkey;
ALTER TABLE geocoder.address ADD CONSTRAINT address_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE SET NULL NOT VALID;

ALTER TABLE geocoder.building DROP CONSTRAINT building_neighborhood_id_fkey;
ALTER TABLE geocoder.building ADD CONSTRAINT building_neighborhood_id_fkey
    FOREIGN KEY (neighborhood_id) REFERENCES geocoder.neighborhood(id)
    ON UPDATE CASCADE ON DELETE SET NULL NOT VALID;

-- =============================================================================
-- Category D — customer data → ON DELETE RESTRICT (fail loudly)
-- =============================================================================

ALTER TABLE report.recovery_sample DROP CONSTRAINT recovery_sample_building_id_fkey;
ALTER TABLE report.recovery_sample ADD CONSTRAINT recovery_sample_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID;

COMMIT;

-- =============================================================================
-- VALIDATE phase — separate statements (no transaction wrapper) so each
-- runs under ShareUpdateExclusiveLock instead of holding AccessExclusiveLock.
-- Order: small tables first (cheap warm-up), then big ones.
-- =============================================================================

ALTER TABLE geocoder.state                   VALIDATE CONSTRAINT state_country_id_fkey;
ALTER TABLE geocoder.district                VALIDATE CONSTRAINT district_municipality_id_fkey;
ALTER TABLE geocoder.neighborhood            VALIDATE CONSTRAINT neighborhood_district_id_fkey;
ALTER TABLE report.recovery_sample           VALIDATE CONSTRAINT recovery_sample_building_id_fkey;
ALTER TABLE data.building_ownership          VALIDATE CONSTRAINT building_ownership_building_id_fkey;
ALTER TABLE data.building_subsidence         VALIDATE CONSTRAINT building_subsidence_building_id_fkey;
ALTER TABLE geocoder.residence               VALIDATE CONSTRAINT residence_building_id_fkey;
ALTER TABLE geocoder.residence               VALIDATE CONSTRAINT residence_address_id_fkey;
ALTER TABLE data.building_cluster            VALIDATE CONSTRAINT building_cluster_building_id_fkey;
ALTER TABLE data.building_pleistocene        VALIDATE CONSTRAINT building_pleistocene_building_id_fkey;
ALTER TABLE data.building_geographic_region  VALIDATE CONSTRAINT building_geographic_region_building_id_fkey;
ALTER TABLE data.building_groundwater_level  VALIDATE CONSTRAINT building_groundwater_level_building_id_fkey;
ALTER TABLE data.building_elevation          VALIDATE CONSTRAINT building_elevation_building_id_fkey;
ALTER TABLE geocoder.address                 VALIDATE CONSTRAINT address_building_id_fkey;
ALTER TABLE geocoder.building                VALIDATE CONSTRAINT building_neighborhood_id_fkey;
ALTER TABLE data.subsidence_history          VALIDATE CONSTRAINT subsidence_history_building_id_fkey;
