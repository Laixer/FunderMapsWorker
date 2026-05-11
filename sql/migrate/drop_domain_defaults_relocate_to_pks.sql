-- Drop autogen defaults from three domain types and pin them
-- to the PK columns that actually need autogen.
--
-- Landmine (see project_landmines.md): the domains
--   application.user_id           default gen_random_uuid()
--   application.organization_id   default gen_random_uuid()
--   geocoder.geocoder_id          default geocoder.geocoder_generate_id()
-- bleed their defaults onto every column that uses the domain — including
-- FK columns. The result: INSERTs that forget to supply an FK silently
-- get a phantom autogen UUID/GFM id instead of failing. That's how the
-- `application.application` seeding produced rows with bogus user_ids.
--
-- Fix: drop the defaults from the domains, then ALTER COLUMN ... SET
-- DEFAULT explicitly on the PK columns that need autogen. After this,
-- any INSERT into an FK column that omits the FK value will fail loudly
-- (NOT NULL violation or FK reference error) rather than silently
-- inserting a phantom id.
--
-- PK columns receiving explicit defaults:
--   application.user.id           → gen_random_uuid()
--   application.organization.id   → gen_random_uuid()
--   geocoder.country.id           → geocoder.geocoder_generate_id()
--   geocoder.state.id             → geocoder.geocoder_generate_id()
--   geocoder.municipality.id      → geocoder.geocoder_generate_id()
--   geocoder.district.id          → geocoder.geocoder_generate_id()
--   geocoder.neighborhood.id      → geocoder.geocoder_generate_id()
--   geocoder.address.id           → geocoder.geocoder_generate_id()
--   geocoder.building.id          → geocoder.geocoder_generate_id()
--
-- Worker load scripts (load_address.sql, load_building.sql) insert without
-- supplying id and continue to work — the column-level default fires.
-- Admin user creation (Drizzle insert in management/user.ts without `id`)
-- continues to work for the same reason.

BEGIN;

ALTER DOMAIN application.user_id DROP DEFAULT;
ALTER DOMAIN application.organization_id DROP DEFAULT;
ALTER DOMAIN geocoder.geocoder_id DROP DEFAULT;

ALTER TABLE application.user
    ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE application.organization
    ALTER COLUMN id SET DEFAULT gen_random_uuid();

ALTER TABLE geocoder.country
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.state
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.municipality
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.district
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.neighborhood
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.address
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();
ALTER TABLE geocoder.building
    ALTER COLUMN id SET DEFAULT geocoder.geocoder_generate_id();

COMMIT;
