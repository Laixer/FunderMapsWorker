# Test VM database bootstrap

How to bring up a working FunderMaps Postgres on a fresh test VM, with
schema + a Rotterdam data subset, in two steps.

## Prerequisites

- Postgres 17 with PostGIS available (`apt-get install postgresql-17-postgis-3` or similar).
- `bun` available locally if you need to (re)generate the seed file.
- An empty target database. Create it as a Postgres superuser first:

  ```bash
  createdb fundermaps
  ```

## Step 1 — Schema and roles

```bash
DATABASE_URL=postgres://OWNER:PW@HOST:PORT/fundermaps \
  ./scripts/init_db.sh
```

What it does:

- Refuses to run against the prod managed cluster (matched on the
  `do-user-871803` substring).
- Installs `postgis`.
- Creates four roles: `fundermaps`, `fundermaps_webapp`,
  `fundermaps_webservice`, `grafana`. If `PG_FM_PASS`, `PG_WEBAPP_PASS`,
  `PG_WS_PASS`, `PG_GRAFANA_PASS` are set, those are used; otherwise random
  passwords are generated and printed once at the end.
- Loads `schema.sql` (strips the pg_dump 18 `\restrict` directive that
  breaks psql ≤ 17).
- Applies `sql/init/grants.sql` so the four roles get prod-equivalent
  privileges.

Re-runs are idempotent: roles get `ALTER ROLE … PASSWORD …`, schema reload
fails fast on `ON_ERROR_STOP=1`, grants replay cleanly. Typical use is
once per VM, but rerun to refresh credentials.

What it does NOT do:

- Create the database.
- Install timescaledb. Prod's `application.product_tracker` hypertable is
  irrelevant for testing; vanilla tables work.
- Set up pg_cron jobs. Trigger refreshes manually (Step 3).
- Load any data — that's `seed.sql.gz`.

## Step 2 — Seed data

```bash
gunzip -c sql/seed.sql.gz | psql "$DATABASE_URL"
```

The seed contains:

- Full nationwide `geocoder.municipality` / `district` / `neighborhood`
  (a few thousand rows, ~MB-scale) so boundary lookups behave realistically
  even outside Rotterdam.
- All `geocoder.building`, `address`, `residence` for Rotterdam (~330k /
  ~700k / ~700k rows).
- All `data.*` per-building tables (elevation, ownership, subsidence
  summary, precomputed, etc.) for Rotterdam buildings.
- Synthetic application data: 1 organization, 2 users (admin + reviewer),
  1 contractor, 1 attribution, 1 mapset, 1 organization geolock, 1 API
  key. **No real users, orgs, or PII from prod.**
- ~100 synthetic inquiries + samples spread across random Rotterdam
  buildings, with varied foundation types, qualities, enforcement terms,
  and damage causes — enough for the model pipeline to produce
  non-trivial output.
- A trailing `CALL data.refresh_all();` that refreshes the 16 matviews
  (`building_sample`, `cluster_sample`, `supercluster_sample`,
  `model_risk_static`, etc.) against the seeded subset. Takes a few
  minutes on Rotterdam alone.

### Default credentials (synthetic)

| What            | Value                                                                  |
| --------------- | ---------------------------------------------------------------------- |
| Admin email     | `admin@test.local`                                                     |
| Admin user id   | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`                                 |
| Reviewer email  | `reviewer@test.local`                                                  |
| Organization id | `99999999-9999-9999-9999-999999999999`                                 |
| Mapset id       | `test-rotterdam`                                                       |
| API key         | `fmsk.test_dev_seed_key_a1b2c3d4e5f6` (SHA-256 stored, plaintext here) |

The admin row's `password_hash` is `NULL` — login by password requires
running a Better Auth password-set/reset flow once on first login. API
access via the API key works immediately.

## Step 3 — (Re)generating the seed

`sql/seed.sql.gz` is committed. Regenerate when prod data has shifted
(after a BAG reload, or to switch municipality):

```bash
DATABASE_URL=postgres://READONLY_USER:PW@PROD_HOST:PORT/fundermaps \
  bun scripts/build_seed.ts
```

Optional env:

- `MUNICIPALITY=0518` to switch (0518 = Den Haag, 0599 = Rotterdam,
  0344 = Utrecht; codes are CBS gemeente IDs and stored as
  `geocoder.municipality.external_id`).
- `OUTPUT=/tmp/seed.sql.gz` to write elsewhere.
- `SYNTHETIC_INQUIRIES=200` to change inquiry count.
- `SEED=42` to vary the synthetic random seed.

The script is read-only on the source — it only issues `SELECT` and
`COPY … TO STDOUT`. Run it from a workstation, not on prod.

## Notes / known limits

- **Subsidence history excluded.** `data.building_subsidence_history`
  is the per-month timeseries — ~30M rows just for Rotterdam. The
  per-building summary (`data.building_subsidence`) is included and is
  what the model reads. Add history later if you need to test
  history-rendering UI.
- **No recovery data.** `report.recovery` / `recovery_sample` are not
  seeded (recovery is a parked feature; see the project memory).
- **Sequence IDs 90000–99000 reserved** for synthetic data. If you load
  multiple seed iterations or hand-insert with low IDs you can collide;
  the script bumps sequences past the reserved range at the end.
