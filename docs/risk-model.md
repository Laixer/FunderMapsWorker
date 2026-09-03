# FunderMaps Risk Model — Technical Reference

**Audience:** AI agents and human data scientists who need to understand, query, or modify the risk model in SQL.
**Scope:** Everything from raw inputs to the materialized view consumed by the webservice and the map tiles.
**Authoritative sources:** the files this doc cites in `sql/model/*.sql` and the dump in `schema.sql`.
**Last regenerated:** schema dump 2026-05-03; pipeline as deployed by Phases A1–A7.

> If you change SQL after reading this doc, update both this file and the relevant `sql/model/*.sql` source, then regenerate `schema.sql` (`pg_dump --schema-only`) so the dump matches what is deployed.

---

## 1. What the model produces

For every active "house"-type BAG building in the Netherlands (≈ 11.2M rows), the model produces a row in `data.model_risk_static` with:

- A **foundation type** prediction (`report.foundation_type` enum, 18 values).
- Three **damage-mode risks** — `drystand_risk`, `dewatering_depth_risk`, `bio_infection_risk` — each on the `data.foundation_risk_indication` ENUM `('a','b','c','d','e')` where `a` = safe and `e` = critical.
- A catch-all `unclassified_risk`.
- For each risk and the foundation type, a **reliability tier** (`data.reliability` ENUM: `indicative` < `cluster` < `supercluster` < `established`). Since Issue #1005, the `supercluster` tier applies **only to `foundation_type`** (a structural characteristic); all risk values and other inquiry-derived signal inherit at most from the `cluster` tier.
- Numeric features used to derive the risks (`drystand`, `dewatering_depth`, `velocity`, `ground_water_level`, `ground_level`, `height`, `surface_area`).
- A **restoration cost estimate** (€).
- The "best" inquiry referenced (`inquiry_id`, `inquiry_type`, `document_date`-derived `enforcement_term` years remaining, `damage_cause`, `overall_quality`).
- The most recent recovery type, if any.

The matview is consumed by:
- The TS API (`fundermaps_webapp` role) and C# Webservice (`fundermaps_webservice` role) — both have `SELECT` granted.
- 12 `data.statistics_*` matviews aggregating per neighborhood / municipality / postal code.
- `maplayer.analysis_full`, a thin projection view used as the GPKG dataset-archive export source. (Four sibling `analysis_*` tile views were dropped 2026-07-24 after the Martin tileserver cutover — analysis map layers now render from `maplayer.building_tiles` directly.)

---

## 2. Pipeline shape

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  RAW INPUTS (refreshed independently)                                        │
│                                                                              │
│   geocoder.building_active        ← BAG (PDOK, quarterly)                    │
│   geocoder.address                ← BAG                                      │
│   data.building_elevation         ← 3DBAG (data.3dbag.nl, ~yearly)           │
│   data.building_subsidence        ← InSAR P95 velocity (vendor GPKG)         │
│   data.building_groundwater_level ← Vendor                                   │
│   data.building_geographic_region ← Soil code (PDOK)                         │
│   data.building_pleistocene       ← Pleistocene depth                        │
│   data.building_ownership         ← Kadaster                                 │
│   data.building_cluster           ← ST_ClusterDBSCAN over BAG geom           │
│   data.supercluster               ← coarser cluster of clusters              │
│   data.cluster_recovery_sample    ← derived                                  │
│   report.inquiry / inquiry_sample ← Customer-uploaded F3O reports            │
│   report.recovery_sample          ← Customer-uploaded recovery records      │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  STAGE 1 — Per-BAG-reload (manual, ~quarterly)                               │
│                                                                              │
│   CALL data.refresh_building_precomputed();                                  │
│   → TRUNCATEs and reloads data.building_precomputed                          │
│     (≈ 11.2M house rows; PK building_id text = BAG external_id)              │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  STAGE 2 — Daily (Windmill flow f/fundermaps/data/refresh_data_model,       │
│             scheduled 18:00 UTC)                                             │
│                                                                              │
│   ├─ REFRESH MATERIALIZED VIEW CONCURRENTLY data.building_sample     ┐       │
│   ├─ REFRESH MATERIALIZED VIEW CONCURRENTLY data.cluster_sample      ├ par.  │
│   ├─ REFRESH MATERIALIZED VIEW CONCURRENTLY data.supercluster_sample ┘       │
│   ├─ REFRESH MATERIALIZED VIEW CONCURRENTLY data.model_risk_static           │
│   │      ← reads data.model_risk_dynamic_all (large view)                    │
│   ├─ REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_* (12, parallel) │
│   └─ sub-flow f/fundermaps/mapset/process_mapset                             │
│         → enqueues worker_jobs row; TS worker regenerates vector tiles       │
└──────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  STAGE 3 — Read paths                                                        │
│                                                                              │
│   data.model_risk_static                                                     │
│     ├─ data.building_geo_hierarchy (joins to geocoder.{neighborhood,         │
│     │                                          district,municipality})       │
│     │   └─ maplayer.analysis_full (GPKG archive export)                      │
│     ├─ maplayer.building_tiles (Martin tileserver source)                    │
│     ├─ maplayer.building_cluster_tiles (Martin, from data.building_cluster)  │
│     └─ data.statistics_*                                                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

The two stages exist because `building_precomputed` only changes on a BAG reload (quarterly), whereas the rest of the pipeline can change daily as customers upload new inquiries/recoveries. Splitting them avoids re-doing expensive `ST_Area(geom::geography, true)` and address-count work every day.

---

## 3. Type system

### 3.1 ENUMs

All listed values are taken verbatim from `schema.sql`.

```sql
CREATE TYPE data.foundation_risk_indication AS ENUM ('a','b','c','d','e');
-- 'a' = safe (or recovered), 'b' = low, 'c' = moderate,
-- 'd' = concerning, 'e' = urgent / critical.

CREATE TYPE data.reliability AS ENUM (
    'indicative',     -- derived purely from BAG + soil + height (no inquiry data)
    'established',    -- there is an inquiry sample on this exact building
    'cluster',        -- inquiry exists on a building in the same DBSCAN cluster
    'supercluster'    -- inquiry exists in a coarser cluster-of-clusters
);
-- Note: precedence is established > cluster > supercluster > indicative
-- (despite the order in which the enum was declared).
-- Issue #1005: 'supercluster' can only appear on foundation_type_reliability;
-- risk values never inherit past the cluster tier anymore.

CREATE TYPE report.foundation_type AS ENUM (
    'wood','concrete','no_pile','wood_charger','weighted_pile','combined',
    'steel_pile','other',
    'no_pile_masonry','no_pile_strips','no_pile_concrete_floor',
    'no_pile_slit','no_pile_bearing_floor',
    'wood_amsterdam','wood_rotterdam','wood_rotterdam_amsterdam',
    'wood_rotterdam_arch','wood_amsterdam_arch'
);
-- Wood-family (incl. charger) and no-pile-family are tested via the helper
-- functions data.is_wood_family / data.is_wood_pile / data.is_no_pile_family.
-- 'concrete' and 'weighted_pile' are considered SAFE (data.is_safe_foundation).

CREATE TYPE report.foundation_damage_cause AS ENUM (
    'drainage','construction_flaw','drystand','overcharge',
    'overcharge_negative_cling','negative_cling','bio_infection',
    'fungus_infection','bio_fungus_infection','foundation_flaw',
    'construction_heave','subsidence','vegetation','gas','vibrations',
    'partial_foundation_recovery','japanese_knotweed',
    'groundwater_level_reduction'
);

CREATE TYPE report.foundation_quality AS ENUM (
    'bad','mediocre','tolerable','good','mediocre_good','mediocre_bad'
);

CREATE TYPE report.enforcement_term AS ENUM (
    -- Legacy "interval" enum (still present in old data):
    'term05',     -- 0–5  years
    'term510',    -- 5–10 years
    'term1020',   -- 10–20 years
    -- Modern point-estimate enum:
    'term5','term10','term15','term20','term25','term30','term40'
);
-- Mapped to a fixed `interval` by data.enforcement_term_years().

CREATE TYPE report.inquiry_type AS ENUM (
    'monitoring','note','quickscan','unknown','demolition_research',
    'second_opinion','archive_research','architectural_research',
    'foundation_advice','inspectionpit','foundation_research',
    'additional_research','ground_water_level_research','soil_investigation',
    'facade_scan'
);
```

### 3.2 The `data.foundation_risk_indication` letter scale

| Letter | Meaning            | When emitted (typical)                                             |
| :---:  | ------------------ | ------------------------------------------------------------------ |
| `a`    | Safe / recovered   | Recovery exists on the building (established tier), or foundation type is `concrete`/`weighted_pile`. |
| `b`    | Low                | Long enforcement term (`term25/30/40`) or `good`/`mediocre_good`. |
| `c`    | Moderate           | Mid-term (`term1020/15/20`) or `mediocre`/`tolerable`.            |
| `d`    | Concerning         | Mid-short term (`term510/10`) or `mediocre_bad`.                  |
| `e`    | Urgent / critical  | Short term (`term05/5`), `recovery_advised=true`, or `bad`.       |

The same enum is used for indicative (no-inquiry) risk via threshold-based functions described in §6.

---

## 4. Source tables

All cited columns come from `schema.sql` definitions.

### 4.1 Building geometry & geography

- **`geocoder.building_active`** — actively-occupied BAG buildings. Filtered to `building_type = 'house'` by `refresh_building_precomputed`. Provides `external_id text` (BAG ID, the universal join key throughout the model), `neighborhood_id`, `geom` (PostGIS), `built_year` (date), `building_type`.
- **`geocoder.address`** — BAG addresses; one building can have many. Counted to populate `building_precomputed.address_count`.
- **`geocoder.{neighborhood,district,municipality}`** — administrative hierarchy joined by `building_geo_hierarchy`.

### 4.2 Building features (one row per building)

| Table                              | Columns used                          | What it represents                                 |
| ---------------------------------- | ------------------------------------- | -------------------------------------------------- |
| `data.building_elevation`          | `building_id text PK, ground real, roof real, height real GENERATED ALWAYS AS (roof - ground) STORED` | 3DBAG-derived ground & roof heights. |
| `data.building_height` (VIEW)      | wraps `building_elevation`, exposes `height = roof - ground` where both NOT NULL | Used only by the legacy/facade scan path; the model reads `building_precomputed.height` instead. |
| `data.building_groundwater_level`  | `building_id text PK, level double precision NOT NULL` | Ground water level (m). Lower = drier. |
| `data.building_geographic_region`  | `building_id text PK, code text NOT NULL` | Soil code. Sandy codes treated specially: `'hz', 'ni-hz', 'ni-du'`. |
| `data.building_subsidence`         | `building_id text PK, velocity double precision NOT NULL` | InSAR P95 settlement velocity (mm/year, negative = sinking). |
| `data.building_pleistocene`        | `building_id text PK, depth double precision` | Depth to Pleistocene sand layer (m below ground surface). |
| `data.building_ownership`          | `building_id text PK, owner text NOT NULL` | Kadaster ownership category, surfaced for tile colouring. |

### 4.3 Clustering tables

- **`data.building_cluster (building_id text NOT NULL, cluster_id uuid NOT NULL)`** — DBSCAN-cluster membership over building geometry. Used to "borrow" inquiry signal from neighbours.
- **`data.supercluster (cluster_id uuid NOT NULL, supercluster_id uuid NOT NULL)`** — coarser cluster-of-clusters used as a third fallback.
- **`data.cluster_recovery_sample (cluster_id uuid NOT NULL, type report.recovery_type)`** — flag indicating any recovery in the cluster; used by `compute_unclassified_risk` at the cluster tier.

### 4.4 Inquiry & recovery tables (customer reports)

- **`report.inquiry`** — `id integer PK, type report.inquiry_type, document_date date, audit_status` etc. One row per uploaded F3O report.
- **`report.inquiry_sample`** — `id integer PK, inquiry_id integer FK, building_id geocoder_id, foundation_type, enforcement_term, damage_cause, overall_quality, recovery_advised, built_year, groundwater_level_temp, wood_level, foundation_depth`, and many facade/crack columns (only used by `maplayer.facade_scan`). One row per inspected building under an inquiry.
- **`report.recovery_sample`** — `id integer PK, recovery_id, building_id, type report.recovery_type, create_date`. The model picks the most recent per building (`DISTINCT ON (building_id) ORDER BY create_date DESC`).

---

## 5. Stage 1 — `data.building_precomputed`

**Source:** `sql/model/create_building_precomputed.sql`. **Procedure:** `data.refresh_building_precomputed()`.

```sql
CREATE TABLE data.building_precomputed (
    building_id text PRIMARY KEY,                -- BAG external_id (NL.IMBAG.PAND.…)
    neighborhood_id text,                        -- copied from geocoder.building_active
    surface_area numeric(10,2),                  -- ST_Area(geom::geography, true) in m²
    address_count integer NOT NULL DEFAULT 0,    -- COUNT(*) from geocoder.address
    construction_year_bag integer,               -- date_part('year', built_year::date)
    height double precision,                     -- GREATEST(roof - ground, 0)
    ground_level numeric(5,2)                    -- building_elevation.ground rounded to 0.01 m
);
CREATE INDEX idx_bp_neighborhood ON data.building_precomputed (neighborhood_id);
```

`refresh_building_precomputed` is a **TRUNCATE + INSERT** procedure (`LANGUAGE sql`), not an upsert, because a full reload is faster than diffing 11M rows. It joins `geocoder.building_active` LEFT JOIN `building_elevation`, LEFT JOIN `building_height` (used here only for the `GREATEST(bh.height,0)` clamp), and a grouped subquery on `geocoder.address`. Filter: `WHERE ba.building_type = 'house'`.

**When to run:** after each BAG reload (see `runbook-load-bag.md`). Quarterly is sufficient unless 3DBAG is also refreshed (see `runbook-load-3dbag.md`) — heights or address counts changing should also trigger a rerun.

**Cost reasoning:** per-row `ST_Area(geom::geography, true)` is the single most expensive operation in the whole model. Computing it once per BAG cycle (instead of on every `model_risk_static` refresh) saves the daily refresh from O(11M × geography Area) work.

---

## 6. Helper functions

**Source:** `sql/model/create_helper_functions.sql`. All declared `LANGUAGE sql IMMUTABLE PARALLEL SAFE` so the planner can inline them in parallel scans of `building_precomputed`.

### 6.1 Foundation-type predicates

```sql
data.is_wood_family(ft)  -- wood + wood_charger + 5 city-specific wood variants
data.is_wood_pile(ft)    -- wood-family EXCLUDING wood_charger (different velocity/GWL thresholds)
data.is_no_pile_family(ft) -- no_pile + 5 no_pile_* variants (incl. no_pile_bearing_floor)
data.is_safe_foundation(ft) -- 'concrete' or 'weighted_pile'
```

### 6.2 `data.enforcement_term_years(term report.enforcement_term) → interval`

Maps every enum value to a fixed `interval`:

| Enum                  | Interval        |
| --------------------- | --------------- |
| `term05`, `term5`     | `5 years`       |
| `term510`, `term10`   | `10 years`      |
| `term15`              | `15 years`      |
| `term1020`, `term20`  | `20 years`      |
| `term25`              | `25 years`      |
| `term30`              | `30 years`      |
| `term40`              | `40 years`      |
| anything else / NULL  | `NULL`          |

This is used in `model_risk_dynamic_all` to compute `enforcement_term` (years remaining as a `double precision`):

```sql
date_part('years', age(
    (document_date + data.enforcement_term_years(enforcement_term))::timestamptz,
    CURRENT_TIMESTAMP
))
```

> ⚠️ **Landmine** — the result is **years remaining (can be negative)**, not the input enum. Both `enforcement_term` and `overall_quality` were stripped from the v3 webservice GET payload in 2026-04 because clients (and mapsets) had baked in an enum-shaped expectation. See [memory/project_enforcement_term_semantic.md](../.claude/projects/-home-eve-Projects-FunderMapsWorker/memory/project_enforcement_term_semantic.md).

### 6.3 `data.compute_restoration_costs(ft, surface_area) → integer`

```sql
CASE
    WHEN data.is_wood_family(ft)            THEN round(surface_area * 1950, -2)::integer
    WHEN ft IN ('no_pile','no_pile_masonry','no_pile_strips',
                'no_pile_concrete_floor','no_pile_slit')
                                             THEN round(surface_area * 350, -2)::integer
    ELSE NULL
END
```

Note: `no_pile_bearing_floor` is intentionally excluded — bearing floors are not restorable on a per-m² basis. `concrete`, `weighted_pile`, `combined`, `steel_pile`, `other` get `NULL`.

### 6.4 `data.indicative_foundation_type(construction_year, height, soil_code, address_count) → report.foundation_type`

This is the **decision tree used when no inquiry sample exists** (or for the indicative reliability tier). Inputs:

- `construction_year integer` — `COALESCE(established.built_year, building_precomputed.construction_year_bag)`.
- `height double precision` — `building_precomputed.height`.
- `soil_code text` — `building_geographic_region.code`. Sandy codes are `'hz'`, `'ni-hz'`, `'ni-du'`.
- `address_count integer` — `building_precomputed.address_count`.

Decision tree (in evaluation order — first match wins):

| Conditions                                                               | Foundation type |
| ------------------------------------------------------------------------ | --------------- |
| `1940 ≤ year < 1965` AND `address_count ≥ 8`                             | `concrete`      |
| `year ≥ 1965` AND `(height < 14 OR NULL)` AND sandy soil                 | `no_pile`       |
| `year ≥ 1965` AND `(height < 14 OR NULL)` AND non-sandy/unknown          | `concrete`      |
| `year ≥ 1965` AND `height ≥ 14`                                          | `concrete`      |
| `1700 ≤ year < 1800` AND `(height < 14 OR NULL)` AND sandy               | `no_pile`       |
| `1700 ≤ year < 1800` AND `height ≥ 14` AND sandy                         | `wood`          |
| `1700 ≤ year < 1800` AND `height < 8.5` AND non-sandy/unknown            | `no_pile`       |
| `1700 ≤ year < 1800` AND `(height ≥ 8.5 OR NULL)` AND non-sandy/unknown  | `wood`          |
| `1800 ≤ year < 1965` AND `(height < 14 OR NULL)` AND sandy               | `no_pile`       |
| `1800 ≤ year < 1965` AND `height ≥ 14` AND sandy                         | `wood`          |
| `1800 ≤ year < 1965` AND `height < 8.5` AND non-sandy¹                   | `no_pile`       |
| `1800 ≤ year < 1920` AND `(height ≥ 8.5 OR NULL)` AND non-sandy/unknown  | `wood`          |
| `1920 ≤ year < 1965` AND `(height ≥ 8.5 OR NULL)` AND non-sandy/unknown  | `wood_charger`  |
| `year < 1700`                                                            | `no_pile`       |
| Fallback (NULL year): `height ≥ 10.5`                                    | `wood`          |
| Fallback (NULL year): `height < 10.5`                                    | `no_pile`       |
| All else                                                                 | `'other'`       |

¹ The `1800–1965, height<8.5, non-sandy` branch has a slightly redundant predicate `soil_code <> 'ni-du' OR soil_code IS NULL` after the NOT IN — kept verbatim from the original logic.

### 6.5 Damage-cause risk: `data.compute_damage_risk(...)`

Used at **established / cluster** tiers to map `(damage_cause, enforcement_term, overall_quality, recovery_advised)` to a letter. (Until Issue #1005 it was also applied at the supercluster tier; risk no longer propagates that far.)

```sql
SELECT CASE
    WHEN has_recovery THEN 'a'                                                    -- recovered → safe (established tier only)
    WHEN damage_cause = ANY(target_causes)
         AND (enforcement_term IN ('term05','term5')
              OR recovery_advised
              OR overall_quality = 'bad')                  THEN 'e'
    WHEN damage_cause = ANY(target_causes)
         AND (enforcement_term IN ('term510','term10')
              OR overall_quality = 'mediocre_bad')         THEN 'd'
    WHEN damage_cause = ANY(target_causes)
         AND (enforcement_term IN ('term1020','term15','term20')
              OR overall_quality IN ('mediocre','tolerable')) THEN 'c'
    WHEN damage_cause = ANY(target_causes)
         AND (enforcement_term IN ('term25','term30','term40')
              OR overall_quality IN ('good','mediocre_good')) THEN 'b'
    ELSE NULL
END;
```

`target_causes` is per damage mode:
- **drystand_risk:** `ARRAY['drystand','fungus_infection','bio_fungus_infection']`
- **bio_infection_risk:** `ARRAY['bio_infection']`
- **dewatering_depth_risk:** `ARRAY['drainage']`

If the sample's `damage_cause` is not in the array, the function returns NULL and `COALESCE` falls through to the next tier (or the indicative function).

### 6.6 `data.compute_unclassified_risk(...)`

Catch-all when `damage_cause` doesn't match any of the three specific causes. Tier-parameterised: **established** uses `recovery_risk='a', urgent_risk='e'`; **cluster** uses `'e','d'`.

```sql
SELECT CASE
    WHEN has_recovery                                  THEN recovery_risk
    WHEN enforcement_term IN ('term05','term5','term510','term10','term15','term1020','term20')
      OR recovery_advised
      OR overall_quality IN ('bad','mediocre_bad','mediocre')
      OR damage_cause IS NOT NULL                      THEN urgent_risk
    WHEN enforcement_term IN ('term25','term30','term40')
      OR overall_quality IN ('good','mediocre_good','tolerable') THEN 'b'
    ELSE NULL
END;
```

### 6.7 Indicative drystand risk: `data.compute_indicative_drystand_risk(ft, velocity, gwl, has_recovery)`

For wood pile and wood-charger foundations only. Thresholds differ:

| Foundation       | Velocity threshold | GWL threshold | Cells (vel × gwl)                       |
| ---------------- | -----------------: | ------------: | --------------------------------------- |
| `is_wood_pile`   |          `−2.0`    |       `1.5`   | (NULL, ≥1.5)=`c`, (NULL, <1.5)=`b`, (<−2, ≥1.5)=`e`, (≥−2, ≥1.5)=`d`, (<−2, <1.5)=`d`, (≥−2, <1.5)=`c` |
| `wood_charger`   |          `−1.0`    |       `2.5`   | (NULL, ≥2.5)=`c`, (NULL, <2.5)=`b`, (<−1, ≥2.5)=`e`, (<−1, <2.5)=`c`, (≥−1, ≥2.5)=`c`, (≥−1, <2.5)=`b` |
| `is_safe_foundation` (concrete, weighted_pile) | — | — | always `'a'` |
| `has_recovery=true` | — | — | always `'a'` |
| Anything else   | — | — | `NULL` |

Velocity is in mm/year; negative values mean the building is sinking. GWL in metres.

### 6.8 Indicative dewatering depth risk: `data.compute_indicative_dewatering_risk(ft, velocity, gwl, has_recovery)`

For no-pile family **excluding `no_pile_bearing_floor`** (matches current/legacy behaviour): velocity threshold `−1.0`, GWL threshold `0.6`. Risk cells follow the same shape as drystand: NULL velocity → `b`/`c`, fast subsidence + dry GWL → `e`, etc.

```sql
CASE
    WHEN has_recovery                              THEN 'a'
    WHEN data.is_safe_foundation(ft)               THEN 'a'
    WHEN ft IN ('no_pile','no_pile_masonry','no_pile_strips',
                'no_pile_concrete_floor','no_pile_slit')
        AND velocity IS NULL AND gwl < 0.6         THEN 'c'
    WHEN ... AND velocity IS NULL AND gwl >= 0.6   THEN 'b'
    WHEN ... AND velocity < -1.0 AND gwl < 0.6     THEN 'e'
    WHEN ... AND velocity < -1.0 AND gwl >= 0.6    THEN 'd'
    WHEN ... AND velocity >= -1.0 AND gwl < 0.6    THEN 'd'
    WHEN ... AND velocity >= -1.0 AND gwl >= 0.6   THEN 'c'
    ELSE NULL
END
```

### 6.9 Indicative bio infection risk: `data.compute_indicative_bio_risk(ft, pile_length, velocity, has_recovery)`

For wood-family (incl. charger). `pile_length` is computed as `building_precomputed.ground_level − building_pleistocene.depth`.

| Pile length (m) | Velocity            | Risk |
| --------------- | ------------------- | ---- |
| `≤ 12`          | `< −2.0`            | `e`  |
| `≤ 12`          | else / NULL         | `d`  |
| `12–15`         | `< −2.0`            | `e`  |
| `12–15`         | else / NULL         | `c`  |
| `> 15`          | `< −2.0`            | `d`  |
| `> 15`          | else / NULL         | `b`  |
| `has_recovery`  | —                   | `a`  |
| Non-wood        | —                   | `NULL` |

---

## 7. Sample matviews — how "established" / "cluster" / "supercluster" inquiry signal is selected

**Source:** `sql/model/recreate_sample_matviews.sql` (Phase A3 v2 swap, applied). **Live shape:** `schema.sql` lines 2262–2402.

All three matviews share an identical projection and tie-breaking logic, differing only in the join key:

```sql
CREATE MATERIALIZED VIEW data.building_sample AS
SELECT DISTINCT ON (b.external_id)
    b.external_id AS building_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    date_part('year', is2.built_year::date)::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type   AS inquiry_type,
    i.document_date,
    i.id
FROM report.inquiry_sample is2
JOIN report.inquiry        i  ON is2.inquiry_id = i.id
JOIN geocoder.building     b  ON b.external_id = is2.building_id::text
WHERE i.document_date >= b.built_year::date - interval '5 years'
ORDER BY b.external_id,
    CASE i.type
        WHEN 'foundation_research'  THEN 0
        WHEN 'inspectionpit'        THEN 1
        WHEN 'second_opinion'       THEN 2
        WHEN 'note'                 THEN 3
        WHEN 'additional_research'  THEN 4
        WHEN 'demolition_research'  THEN 5
        WHEN 'architectural_research' THEN 6
        WHEN 'archive_research'     THEN 7
        WHEN 'quickscan'            THEN 8
        ELSE 100
    END,
    i.document_date DESC
WITH NO DATA;
CREATE UNIQUE INDEX ON data.building_sample (building_id);
```

`data.cluster_sample` is the same query joined through `data.building_cluster` and grouped by `bc.cluster_id`; `data.supercluster_sample` is joined through `supercluster → building_cluster` grouped by `s.supercluster_id`.

**Why `DISTINCT ON` and not `array_agg`:** the original matviews used `array_agg(... ORDER BY ...)[1]`, but Postgres does not guarantee that `array_agg` preserves subquery `ORDER BY` through `GROUP BY`. The Phase A3 rewrite replaced it with `DISTINCT ON (...) ORDER BY ...` for deterministic selection.

**Tie-break order** (lower number wins, then most recent `document_date`):
0. `foundation_research` ← strongest signal
1. `inspectionpit`
2. `second_opinion`
3. `note`
4. `additional_research`
5. `demolition_research`
6. `architectural_research`
7. `archive_research`
8. `quickscan`
100. anything else (effectively last-resort)

**Recency filter:** only inquiries with `document_date ≥ built_year − 5y` are kept, so an inquiry pre-dating construction by more than 5 years is rejected.

> ⚠️ **Landmine — `archieve_research` typo.** The source file `recreate_sample_matviews.sql` and at least one frontend tile filter use the misspelling `archieve_research`. The deployed enum value (and the deployed matview, per `schema.sql:2289`) is the correct spelling `archive_research`. If you regenerate `recreate_sample_matviews.sql` from `schema.sql`, fix the typo at the same time. There is a tracked TODO to clean this up in WebFront after the next tileset regen.

---

## 8. Stage 2 — `data.model_risk_dynamic_all` (the calculation view)

**Source:** `sql/model/recreate_model_risk_dynamic_all.sql`. **Live shape:** `schema.sql` lines 2461–2546.

This is a regular (non-materialized) view. It joins `building_precomputed` with all building features and the three sample matviews, then derives every model output via `COALESCE(...)`-tier resolution and the helper functions.

### 8.1 FROM clause

```sql
FROM data.building_precomputed bp
LEFT JOIN data.building_geographic_region gr  ON gr.building_id  = bp.building_id
LEFT JOIN data.building_groundwater_level gwl ON gwl.building_id = bp.building_id
LEFT JOIN data.building_subsidence        bs  ON bs.building_id  = bp.building_id
LEFT JOIN data.building_ownership         bo  ON bo.building_id  = bp.building_id
LEFT JOIN data.building_pleistocene       bpl ON bpl.building_id = bp.building_id
LEFT JOIN data.building_cluster           bc  ON bc.building_id  = bp.building_id
LEFT JOIN data.supercluster               bsc ON bsc.cluster_id  = bc.cluster_id
LEFT JOIN data.building_sample            established  ON established.building_id   = bp.building_id
LEFT JOIN data.cluster_sample             cluster      ON cluster.cluster_id        = bc.cluster_id
LEFT JOIN data.supercluster_sample        supercluster ON supercluster.supercluster_id = bsc.supercluster_id
LEFT JOIN LATERAL (
    SELECT DISTINCT ON (rs.building_id) rs.building_id, rs.type
    FROM report.recovery_sample rs
    WHERE rs.building_id = bp.building_id
    ORDER BY rs.building_id, rs.create_date DESC
) recovery ON true
LEFT JOIN data.cluster_recovery_sample
       ON cluster_recovery_sample.cluster_id = bc.cluster_id,
LATERAL (SELECT round((bp.ground_level - bpl.depth)::numeric, 2))
    AS pile_length(pile_length),
LATERAL (SELECT COALESCE(
    established.foundation_type,
    cluster.foundation_type,
    supercluster.foundation_type,
    data.indicative_foundation_type(
        COALESCE(established.built_year, bp.construction_year_bag),
        bp.height, gr.code, bp.address_count)
)) AS foundation_type(ft);
```

The two `LATERAL` blocks are convenience aliases reused by every output column:

- `pile_length.pile_length` — `ground_level − pleistocene_depth`, used by `compute_indicative_bio_risk`.
- `foundation_type.ft` — the resolved foundation type with `established > cluster > supercluster > indicative` precedence.

The `recovery` LATERAL picks the most recent `recovery_sample` per building. `has_recovery` is then `recovery.type IS NOT NULL`.

### 8.2 SELECT list — output column reference

| Output column                       | Definition (paraphrased)                                                  | Tier resolution |
| ----------------------------------- | ------------------------------------------------------------------------- | --------------- |
| `building_id`                       | `bp.building_id`                                                          | — |
| `address_count`                     | `bp.address_count`                                                        | — |
| `neighborhood_id`                   | `bp.neighborhood_id`                                                      | — |
| `construction_year`                 | `COALESCE(established.built_year, bp.construction_year_bag)`              | established or BAG |
| `construction_year_reliability`     | `'established'` if `established.built_year IS NOT NULL` else `'indicative'` | — |
| `foundation_type`                   | `foundation_type.ft` (LATERAL)                                            | est > clu > sup > ind (only column still using the supercluster tier) |
| `foundation_type_reliability`       | first non-NULL `foundation_type` in {est, clu, sup}, else `'indicative'`  | — |
| `restoration_costs`                 | `data.compute_restoration_costs(foundation_type.ft, bp.surface_area)`     | — |
| `drystand`                          | see §8.3                                                                  | est > clu > indicative gwl |
| `drystand_risk`                     | `COALESCE(compute_damage_risk × 2 tiers, compute_indicative_drystand_risk)` | — |
| `drystand_risk_reliability`         | first tier with non-NULL inquiry id; `'indicative'` otherwise              | — |
| `bio_infection_risk` (+ reliability) | `COALESCE(compute_damage_risk × 2, compute_indicative_bio_risk)`           | — |
| `dewatering_depth`                  | see §8.3                                                                  | est > clu > indicative gwl |
| `dewatering_depth_risk` (+ reliability) | `COALESCE(compute_damage_risk × 2, compute_indicative_dewatering_risk)`  | — |
| `unclassified_risk`                 | see §8.4 (incl. construction-year fallback, #1002)                        | est > clu > year-fallback |
| `height`                            | `bp.height::numeric(10,2)`                                                 | — |
| `velocity`                          | `round(bs.velocity::numeric, 2)`                                          | — |
| `ground_water_level`                | `round(gwl.level::numeric, 2)`                                            | — |
| `ground_level`                      | `bp.ground_level`                                                         | — |
| `soil`                              | `gr.code`                                                                 | — |
| `surface_area`                      | `bp.surface_area`                                                         | — |
| `owner`                             | `bo.owner`                                                                | — |
| `inquiry_id`                        | `established.id` — **established only** (Issue #1005)                     | — |
| `inquiry_type`                      | `established.inquiry_type` — **established only** (Issue #1005)           | — |
| `damage_cause`                      | `COALESCE(established, cluster)` damage_cause                             | — |
| `enforcement_term`                  | `date_part('years', age((doc_date + enforcement_term_years(...))::tstz, CURRENT_TIMESTAMP))` — **years remaining (negative if elapsed)** | — |
| `overall_quality`                   | `COALESCE(established, cluster)` overall_quality                          | — |
| `recovery_type`                     | `recovery.type`                                                            | — |

### 8.3 Numeric outputs `drystand` and `dewatering_depth`

Both are physical metres, used both for display and as inputs to the indicative-risk functions.

```sql
-- drystand:    wood top - groundwater level. If unknown,
--              indicative estimate based on foundation type bias.
CASE
    WHEN established.wood_level IS NOT NULL AND established.groundwater_level IS NOT NULL
        THEN (established.wood_level - established.groundwater_level)::double precision
    WHEN cluster.wood_level    IS NOT NULL AND cluster.groundwater_level    IS NOT NULL
        THEN ...
    WHEN foundation_type.ft = 'wood_charger'    THEN gwl.level - 2.5
    WHEN data.is_wood_pile(foundation_type.ft)  THEN gwl.level - 1.5
    ELSE NULL
END

-- dewatering_depth:    foundation_depth - groundwater_level - 0.6
--                      (the 0.6 m offset is the minimum required dry zone)
CASE
    WHEN established.foundation_depth IS NOT NULL AND established.groundwater_level IS NOT NULL
        THEN (established.foundation_depth - established.groundwater_level - 0.6)::double precision
    WHEN cluster.foundation_depth    IS NOT NULL AND cluster.groundwater_level    IS NOT NULL
        THEN ...
    WHEN data.is_no_pile_family(foundation_type.ft) THEN gwl.level - 0.6
    ELSE NULL
END
```

> ⚠️ **Bug fixes baked into Phase A4** (already deployed; re-introduce if you rewrite the view):
> 1. `dewatering_depth` cluster branch checks `foundation_depth IS NOT NULL` (the legacy view incorrectly checked `wood_level`).
> 2. `wood_rotterdam_amsterdam` was previously listed in the no-pile branch of `dewatering_depth` and removed (it is wood, not no-pile).
> 3. A duplicate `wood_rotterdam_arch` line was removed from the drystand CASE.

### 8.4 `unclassified_risk`

Aggregates a final letter when the specific drystand / bio / drainage paths produced nothing, using `compute_unclassified_risk` per tier with different `recovery_risk` and `urgent_risk` parameters:

```sql
COALESCE(
    compute_unclassified_risk(
        recovery.type IS NOT NULL,    'a', 'e',  -- established: recovered → a, urgent → e
        established.enforcement_term, established.overall_quality,
        established.recovery_advised, established.damage_cause),
    compute_unclassified_risk(
        cluster_recovery_sample.type IS NOT NULL, 'e', 'd',  -- cluster: cluster_recovery → e, urgent → d
        cluster.enforcement_term, cluster.overall_quality,
        cluster.recovery_advised, cluster.damage_cause)
)
```

The asymmetric mapping (`a/e` for established, `e/d` for cluster) captures the fact that a recovery flag is only fully trustworthy at the building level; cluster recoveries indicate the area is being treated, not necessarily this building.

#### Construction-year fallback (Issue [Laixer/FunderMaps#1002](https://github.com/Laixer/FunderMaps/issues/1002))

Every building must carry at least one risk indication. When all three component risks **and** the report-derived `unclassified_risk` above are NULL (~45k buildings: missing groundwater model coverage — e.g. the Waddeneilanden — plus `other`/`combined` foundation types and `no_pile_bearing_floor`), `unclassified_risk` falls back to a construction-year heuristic:

| `construction_year` | fallback |
|---|---|
| `< 1970` | `'d'` |
| `>= 1970` | `'b'` |
| NULL | stays NULL (1 building nationally) |

The view wraps its base query in an outer `SELECT ... FROM (...) base` solely so this gate can reference the computed risk columns. The fallback is deliberately gated on the other risks being NULL — ungated it would stamp a class on every report-less building in the country and skew the neighborhood statistics. These rows are always `indicative` reliability (no sample joins matched). Domain rule by Don; consumed by the Webservice `/light` endpoint as a fourth `computeOverallRisk` component.

### 8.5 Reliability columns

There are four reliability columns: `construction_year_reliability`, `foundation_type_reliability`, `drystand_risk_reliability`, `bio_infection_risk_reliability`, `dewatering_depth_risk_reliability`. They are recomputed per output by checking which tier supplied a non-NULL `id` (or `built_year` / `foundation_type` for the corresponding fields). Since Issue #1005 the risk reliabilities can only be established/cluster/indicative; `supercluster` still occurs on `foundation_type_reliability` only. The `restoration_costs`, `drystand`, `dewatering_depth` numeric columns themselves do not carry an explicit reliability — they inherit from `foundation_type_reliability` via the foundation type they use.

---

## 9. Stage 2 — `data.model_risk_static` (the materialized output)

**Source:** `sql/model/recreate_model_risk_manifest.sql`. **Live shape:** `schema.sql` lines 2553–2598.

```sql
CREATE MATERIALIZED VIEW data.model_risk_static AS
SELECT
    building_id, address_count, neighborhood_id,
    construction_year, construction_year_reliability,
    foundation_type, foundation_type_reliability,
    restoration_costs,
    drystand, drystand_risk, drystand_risk_reliability,
    bio_infection_risk, bio_infection_risk_reliability,
    dewatering_depth, dewatering_depth_risk, dewatering_depth_risk_reliability,
    unclassified_risk,
    height, velocity, ground_water_level, ground_level,
    soil, surface_area, owner,
    inquiry_id, inquiry_type, damage_cause,
    enforcement_term, overall_quality, recovery_type
FROM data.model_risk_dynamic_all
WITH DATA;

CREATE UNIQUE INDEX model_risk_static_pkey
    ON data.model_risk_static USING btree (building_id);
CREATE INDEX idx_mrs_neighborhood
    ON data.model_risk_static USING btree (neighborhood_id);

GRANT SELECT ON data.model_risk_static TO fundermaps_webapp;
GRANT SELECT ON data.model_risk_static TO fundermaps_webservice;
```

**Why a matview, not a table:** historical predecessor `model_risk_manifest()` was an `INSERT ON CONFLICT DO UPDATE` procedure. Replacing it with a matview lets us use `REFRESH MATERIALIZED VIEW CONCURRENTLY` (no exclusive locks during refresh) and drop the manual UPSERT bookkeeping. The unique index on `building_id` is required by `CONCURRENTLY`.

**Stale-row policy:** the matview is **not pruned**. If a building drops out of `building_active` (e.g. demolition) it stays in `model_risk_static` until the next manual cleanup or a full `REFRESH … WITH NO DATA` then re-refresh. This is by design — see [memory/risk-model-review.md](../.claude/projects/-home-eve-Projects-FunderMapsWorker/memory/risk-model-review.md).

**NULL `built_year`:** kept as-is and falls into the indicative tree's height-only fallback (`height ≥ 10.5 → wood`, else `no_pile`).

---

## 10. The daily refresh — Windmill flow `f/fundermaps/data/refresh_data_model`

Scheduled in Windmill at 18:00 UTC daily. The flow runs one small SQL script
per matview (each a single `REFRESH MATERIALIZED VIEW CONCURRENTLY`), in this
order:

1. **Sample matviews** (parallel branch): `refresh_building_sample`,
   `refresh_cluster_sample`, `refresh_supercluster_sample`.
2. **Model**: `refresh_risk_model` → `data.model_risk_static`.
3. **Statistics** (parallel branch): the 12 `refresh_statistics_*` scripts.
4. **Tiles**: sub-flow `f/fundermaps/mapset/process_mapset` inserts a
   `process_mapset` row into `application.worker_jobs` and polls it; the
   FunderMaps Worker (`src/commands/process-mapset.ts`) picks it up and
   regenerates all vector tiles (`ogr2ogr → tippecanoe → S3 upload
   (fundermaps-tileset)`).

Each script is its own transaction, so locks release between steps, and
`CONCURRENTLY` keeps API/webservice SELECTs unblocked throughout.

**Operational notes**
- **History:** the refresh was originally the systemd timer
  `fundermaps-refresh-model.timer` on the worker droplet, then pg_cron Job 7
  (`defaultdb`) calling a `data.refresh_all()` procedure. Both are gone —
  the timer is disabled, the cron job unscheduled, and the procedure dropped
  (2026-07-21). Windmill is the only scheduler. Do not resurrect the others.
- Refresh duration is dominated by `model_risk_static` (~minutes on the
  11M-row dataset) and the larger statistics matviews.
- A fresh database restored from `schema.sql` has matviews `WITH NO DATA`;
  `CONCURRENTLY` fails on those. First population must use plain
  `REFRESH MATERIALIZED VIEW` — the seed generated by `scripts/build_seed.ts`
  ends with exactly that block.
- Stale job recovery in the worker resets any `processing` job stuck >2h back
  to `pending`, so a crashed `process_mapset` will re-fire on the next worker
  poll.
---

## 11. Downstream consumers

### 11.1 `data.building_geo_hierarchy` (base view)

**Source:** `sql/model/consolidate_analysis_views.sql`.

```sql
CREATE OR REPLACE VIEW data.building_geo_hierarchy AS
SELECT
    mrs.*,
    ba.geom,
    n.external_id AS ext_neighborhood_id,
    d.external_id AS ext_district_id,
    m.external_id AS ext_municipality_id
FROM data.model_risk_static mrs
JOIN geocoder.building_active ba ON ba.external_id = mrs.building_id
JOIN geocoder.neighborhood    n  ON n.id = ba.neighborhood_id
JOIN geocoder.district        d  ON d.id = n.district_id
JOIN geocoder.municipality    m  ON m.id = d.municipality_id
WHERE mrs.address_count > 0;
```

The `mrs.address_count > 0` filter excludes orphaned / unaddressed buildings (sheds, tiny annexes) from all map products.

### 11.2 `maplayer.analysis_full` (GPKG archive export)

A thin column projection exposing essentially every model output. It no longer re-does `DISTINCT ON` (`building_id` is unique in `model_risk_static` thanks to its PK).

Until the 2026-07-23 Martin tileserver cutover there were five such views feeding static tippecanoe tilesets; the other four (`analysis_building`, `analysis_foundation`, `analysis_report`, `analysis_risk`) plus `analysis_monitoring` were dropped on 2026-07-24 (`sql/migrate/drop_analysis_tile_views.sql`) — analysis map layers now render from `maplayer.building_tiles` via Martin. `analysis_full` survives because its `maplayer.bundle` row is GPKG-export-only, feeding the nightly dataset archive (raw material for model-run diffs). It remains the heaviest export (`MAX_TILESET_WORKERS=1` is set on the worker droplet because parallel exports OOM the 8 GB node).

### 11.3 `maplayer.facade_scan`

Does **not** read `model_risk_static`. It queries `report.inquiry_sample` directly to surface facade-crack data. (`maplayer.analysis_monitoring`, which did the same for joint-monitoring data, was dropped with the other tile views.)

### 11.4 Statistics matviews

12 matviews under `data.statistics_*` aggregate either over `model_risk_static` (foundation_type/foundation_risk/data_collected for postal_code and product) or directly over inquiry/incident/recovery tables (`statistics_product_inquiries`, `statistics_product_incidents`, `statistics_product_buildings_restored`). Bug fixes baked in by Phase A7 and reflected in `sql/model/fix_statistics.sql`:

- `statistics_product_buildings_restored`: rewritten as `LEFT JOIN + COALESCE` instead of `UNION + DISTINCT ON` (the latter could non-deterministically return the 0-count row).
- `statistics_product_incident_municipality`: now uses `geocoder.building_active` (was `geocoder.building`, which included inactive buildings).
- `statistics_product_inquiry_municipality`: now keys off `i.document_date` (was `is2.create_date`).

---

## 12. How to modify the model

### 12.1 Workflow

1. Edit the relevant file in `sql/model/`. All files are idempotent (`CREATE OR REPLACE` everywhere except `CREATE MATERIALIZED VIEW`, which uses a v2 → rename swap pattern; see `recreate_sample_matviews.sql`).
2. Apply against `defaultdb`/`fundermaps` as `doadmin` (the `fundermaps` role lacks CREATE on the database):
   ```bash
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/model/<file>.sql
   ```
3. For matview changes:
   - For a definition change you typically need `DROP MATERIALIZED VIEW` then `CREATE MATERIALIZED VIEW … WITH DATA` (or use the v2-swap pattern documented in `recreate_sample_matviews.sql` to avoid downtime).
   - **Always recreate the unique index** required by `REFRESH … CONCURRENTLY`.
   - **Always re-`GRANT SELECT … TO fundermaps_webapp, fundermaps_webservice`** — Postgres does NOT preserve privileges across DROP/CREATE.
4. Refresh the matviews you changed (`REFRESH MATERIALIZED VIEW CONCURRENTLY data.<matview>;`) or trigger the Windmill flow `f/fundermaps/data/refresh_data_model` for a full pass.
5. Spot-check downstream maplayer views (`SELECT count(*) FROM maplayer.analysis_full`).
6. Regenerate `schema.sql`:
   ```bash
   # pg_dump must be >= the server major (prod is PG 18: postgresql-client-18 from PGDG).
   # _timescaledb_internal holds only hypertable chunks and is excluded on purpose.
   pg_dump --schema-only --no-owner --no-acl --exclude-schema=_timescaledb_internal "$DATABASE_URL" > schema.sql
   ```
7. Update this doc — column lists, CASE branches, helper-function bodies, anything that changed.
8. Commit both `sql/model/*.sql` and `schema.sql` together so source and dump never drift.

### 12.2 Common modification patterns

- **New foundation type:** add the value to the `report.foundation_type` enum, update `data.is_wood_family` / `is_wood_pile` / `is_no_pile_family` / `is_safe_foundation` predicates if it falls into one of those families, decide cost coefficient in `compute_restoration_costs`, decide indicative-risk thresholds, and add a branch in `indicative_foundation_type` if the type can be inferred from BAG features.
- **New damage cause:** add to `report.foundation_damage_cause`, add the cause to the relevant `target_causes` array literal in `model_risk_dynamic_all` (drystand/bio/dewatering), or add a new `data.compute_*_risk` family.
- **Threshold tuning** (e.g. change wood-pile drystand velocity threshold from `−2.0` to `−1.8`): edit `compute_indicative_drystand_risk` only — no other downstream changes needed because the function is `IMMUTABLE PARALLEL SAFE` and inlined.
- **New output column:** add to `model_risk_dynamic_all` SELECT, then to `model_risk_static` SELECT, then to whichever `analysis_*` view should expose it, then update `pg_dump`.

### 12.3 Things to verify before deploying

- `EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM data.model_risk_dynamic_all WHERE building_id = '<some BAG id>';` — the row plan should still be parameterized index lookups, not seq-scans.
- Row count parity: `SELECT count(*) FROM data.model_risk_static;` should match the previous count ± expected delta.
- `SELECT foundation_type, count(*) FROM data.model_risk_static GROUP BY 1 ORDER BY 2 DESC;` should not radically reshape unless you intended to.
- A worked example for a known address (e.g. `yorick@laixer.com`'s testing flow against `ws.fundermaps.com /api/v3/product/analysis`) before letting the next nightly Windmill run fire.

---

## 13. Known landmines (consolidated)

1. **`enforcement_term` semantic** — the column on `model_risk_static` (and `analysis_full`) is **years remaining (double, can be negative)**, not the input enum. Both this and `overall_quality` are excluded from `ws.fundermaps.com /api/v3/product/...` payloads to avoid breaking mapsets that interpret the original enum shape. Don't add them back without a coordinated client migration. See [memory/project_enforcement_term_semantic.md](../.claude/projects/-home-eve-Projects-FunderMapsWorker/memory/project_enforcement_term_semantic.md).
2. **`archieve_research` typo** — `recreate_sample_matviews.sql` has the misspelling; the deployed enum and matview use `archive_research`. Don't blindly copy from the source file.
3. **`address_count > 0` in `building_geo_hierarchy`** — quietly hides any building without addresses from every analysis tile. Buildings *do* still appear in `model_risk_static`; they're just absent from the maplayer.
4. **`recreate_sample_matviews.sql` v2 swap is one-shot** — it creates `*_v2` matviews and documents (in comments) a `BEGIN; ALTER ... RENAME ...; COMMIT;` swap. Don't re-run it as-is on a live system; either edit the live matviews directly or re-introduce the v2 swap dance.
5. **Stale rows in `model_risk_static`** — by design. If you need the matview to mirror `building_active` exactly, schedule a periodic `REFRESH … WITH NO DATA` then full refresh, or add a `DELETE WHERE building_id NOT IN (SELECT external_id FROM building_active)` step.
6. **Privileges drop on `DROP MATERIALIZED VIEW`** — always re-`GRANT SELECT TO fundermaps_webapp, fundermaps_webservice`. Phase L of the schema cleanup hit this exact bug and is enshrined in the migration history.
7. **`process_mapset` enqueue in the Windmill `process_mapset` flow** — if you change the `application.worker_jobs` schema (column names, enum values), update the flow's `INSERT` too. The current shape is `(job_type='process_mapset', status='pending', max_retries=0)`.

---

## 14. Quick reference — file map

| Concern                         | File                                               |
| ------------------------------- | -------------------------------------------------- |
| Helper functions                | `sql/model/create_helper_functions.sql`            |
| `building_precomputed` table + procedure | `sql/model/create_building_precomputed.sql`  |
| Sample matviews (v2 swap)       | `sql/model/recreate_sample_matviews.sql`           |
| `model_risk_dynamic_all` view   | `sql/model/recreate_model_risk_dynamic_all.sql`    |
| `model_risk_static` matview     | `sql/model/recreate_model_risk_manifest.sql`       |
| Daily refresh                   | Windmill flow `f/fundermaps/data/refresh_data_model` |
| Analysis views & extra indexes  | `sql/model/consolidate_analysis_views.sql`         |
| Statistics matview fixes        | `sql/model/fix_statistics.sql`                     |
| Authoritative dump              | `schema.sql` (regenerate after any change)         |
| Operational memory (decisions)  | `~/.claude/projects/-home-eve-Projects-FunderMapsWorker/memory/{risk-model-review,model-performance,gfm-migration}.md` |
