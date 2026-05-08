#!/usr/bin/env bun
/**
 * Generate sql/seed.sql.gz — a single-municipality data subset of the
 * FunderMaps prod DB suitable for loading into a fresh test VM after
 * scripts/init_db.sh has run.
 *
 * Sections of the produced seed.sql:
 *   1. Geocoder hierarchy (municipality + district + neighborhood, nationwide).
 *   2. Buildings + addresses + residences for the chosen municipality only.
 *   3. data.* per-building tables (elevation, ownership, subsidence, etc.).
 *   4. Synthetic application data (org, users, contractor, attribution,
 *      auth_key, mapset, geolock).
 *   5. Synthetic inquiries + samples on random subset buildings — varied
 *      enum values so data.refresh_all() produces non-trivial model rows.
 *   6. Sequence resets.
 *   7. CALL data.refresh_all() to populate matviews.
 *
 * Skipped on purpose:
 *   - data.building_subsidence_history (timeseries, ~30M rows for Rotterdam).
 *     The per-building summary table is dumped; history is for UI testing.
 *   - report.recovery / recovery_sample / incident — recovery is a parked
 *     feature (memory: project_recovery_feature_parked).
 *   - All auth_* token tables, sessions, verification, worker_jobs — start
 *     empty; the running stack populates them.
 *
 * Usage:
 *   DATABASE_URL=postgres://user:pass@host:port/fundermaps \
 *     bun scripts/build_seed.ts
 *
 * Optional env:
 *   MUNICIPALITY        external_id of target (default '0599' = Rotterdam)
 *   OUTPUT              output path (default 'sql/seed.sql.gz')
 *   SYNTHETIC_INQUIRIES count of synthetic inquiries (default 100)
 *   SEED                PRNG seed for synthetic data (default 1)
 */

import postgres from "postgres";
import { createWriteStream } from "node:fs";
import { createGzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { PassThrough } from "node:stream";
import { createHash } from "node:crypto";

const SRC_URL = process.env.DATABASE_URL;
if (!SRC_URL) {
  console.error("error: DATABASE_URL is required (read access to prod)");
  process.exit(1);
}

const MUNICIPALITY = process.env.MUNICIPALITY ?? "0599";
const OUTPUT = process.env.OUTPUT ?? "sql/seed.sql.gz";
const SYNTHETIC_INQUIRIES = Number(process.env.SYNTHETIC_INQUIRIES ?? "100");
const SEED = Number(process.env.SEED ?? "1");

// --- Synthetic data constants -----------------------------------------------
// Stable IDs so re-running the seed against the same prod state produces
// identical bytes (modulo timestamps).
const SYNTH = {
  contractorId: 99001,
  attributionId: 99000,
  organizationId: "99999999-9999-9999-9999-999999999999",
  adminUserId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  reviewerUserId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  authKeyId: "cccccccc-cccc-cccc-cccc-cccccccccccc",
  authKeyPlaintext: "fmsk.test_dev_seed_key_a1b2c3d4e5f6",
  mapsetId: "test-rotterdam",
  inquiryIdStart: 90000,
  inquirySampleIdStart: 90000,
} as const;

const sql = postgres(SRC_URL, {
  ssl: "prefer",
  prepare: false,
  max: 1,
  connection: { application_name: "fundermaps-build-seed" },
});

// --- Streaming output -------------------------------------------------------
const passthrough = new PassThrough();
const gzip = createGzip({ level: 9 });
const fileOut = createWriteStream(OUTPUT);
const pipelinePromise = pipeline(passthrough, gzip, fileOut);

function write(s: string | Uint8Array) {
  if (!passthrough.write(s)) {
    return new Promise<void>((r) => passthrough.once("drain", r));
  }
}

async function flush() {
  passthrough.end();
  await pipelinePromise;
}

// --- COPY helpers -----------------------------------------------------------
/** Stream COPY (...) TO STDOUT from prod, wrap as a COPY ... FROM stdin block. */
async function dumpCopy(targetTable: string, srcQuery: string) {
  await write(`COPY ${targetTable} FROM stdin;\n`);
  const reader = await sql.unsafe(`COPY (${srcQuery}) TO STDOUT`).readable();
  for await (const chunk of reader) {
    await write(chunk);
  }
  await write("\\.\n\n");
}

// --- Quoting helpers for synthetic INSERT statements ------------------------
function q(s: string | null | undefined): string {
  if (s === null || s === undefined) return "NULL";
  return "'" + s.replace(/'/g, "''") + "'";
}
function qNum(n: number | null | undefined): string {
  return n === null || n === undefined ? "NULL" : String(n);
}

// --- Deterministic PRNG (mulberry32) ----------------------------------------
function makeRng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// --- Enum value pools (subset chosen to exercise the model) -----------------
const FOUNDATION_TYPES = [
  "wood",
  "concrete",
  "no_pile",
  "wood_charger",
  "wood_amsterdam",
  "wood_rotterdam",
  "no_pile_masonry",
  "combined",
] as const;
const FOUNDATION_QUALITIES = [
  "good",
  "tolerable",
  "mediocre",
  "mediocre_bad",
  "bad",
] as const;
const ENFORCEMENT_TERMS = [
  "term05",
  "term510",
  "term1020",
  "term15",
  "term20",
  "term30",
] as const;
const DAMAGE_CAUSES = [
  "drainage",
  "drystand",
  "negative_cling",
  "bio_infection",
  "subsidence",
  "vegetation",
  "construction_flaw",
] as const;
const INQUIRY_TYPES = [
  "foundation_research",
  "inspectionpit",
  "second_opinion",
  "additional_research",
  "archive_research",
  "quickscan",
] as const;

function pick<T>(rng: () => number, arr: readonly T[]): T {
  return arr[Math.floor(rng() * arr.length)]!;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log(`Source:       ${SRC_URL.replace(/:[^:@/]+@/, ":***@")}`);
  console.log(`Municipality: ${MUNICIPALITY}`);
  console.log(`Output:       ${OUTPUT}`);

  // Resolve municipality + buildings up-front. We use the building set both
  // to filter dependent tables and to seed synthetic inquiries.
  const muniRow = await sql<{ id: string; name: string }[]>`
    SELECT id, name FROM geocoder.municipality WHERE external_id = ${MUNICIPALITY}
  `;
  if (muniRow.length === 0) {
    throw new Error(`Municipality external_id=${MUNICIPALITY} not found`);
  }
  console.log(`Resolved:     ${muniRow[0]!.name} (id=${muniRow[0]!.id})`);

  const buildingRows = await sql<{ external_id: string; built_year: number | null }[]>`
    SELECT b.external_id, date_part('year', b.built_year::date)::int AS built_year
    FROM geocoder.building b
    JOIN geocoder.neighborhood n ON b.neighborhood_id = n.id
    JOIN geocoder.district d ON n.district_id = d.id
    WHERE d.municipality_id = ${muniRow[0]!.id}
  `;
  console.log(`Buildings:    ${buildingRows.length.toLocaleString()}`);
  if (buildingRows.length === 0) {
    throw new Error("No buildings found for municipality — aborting.");
  }

  // The filter clause used by every dependent table dump.
  const buildingFilter = `building_id IN (
    SELECT b.external_id FROM geocoder.building b
    JOIN geocoder.neighborhood n ON b.neighborhood_id = n.id
    JOIN geocoder.district d ON n.district_id = d.id
    WHERE d.municipality_id = '${muniRow[0]!.id.replace(/'/g, "''")}'
  )`;

  // ------------------------------------------------------------------------
  // Header
  // ------------------------------------------------------------------------
  await write(`-- FunderMaps test seed
-- Generated: ${new Date().toISOString()}
-- Source municipality: ${muniRow[0]!.name} (external_id=${MUNICIPALITY})
-- Building count: ${buildingRows.length}
-- Synthetic inquiries: ${SYNTHETIC_INQUIRIES}
--
-- Load with:  gunzip -c sql/seed.sql.gz | psql "$DATABASE_URL"
--
-- Assumes scripts/init_db.sh has already created the schema.

SET session_replication_role = 'replica';  -- defer FK checks within COPY blocks
BEGIN;

`);

  // ------------------------------------------------------------------------
  // 1. Geocoder hierarchy (full nationwide — small)
  // ------------------------------------------------------------------------
  console.log("Dumping geocoder hierarchy...");
  await dumpCopy("geocoder.municipality", "SELECT * FROM geocoder.municipality");
  await dumpCopy("geocoder.district",     "SELECT * FROM geocoder.district");
  await dumpCopy("geocoder.neighborhood", "SELECT * FROM geocoder.neighborhood");

  // ------------------------------------------------------------------------
  // 2. Building + address + residence (filtered to municipality)
  // ------------------------------------------------------------------------
  console.log("Dumping buildings, addresses, residences...");
  await dumpCopy(
    "geocoder.building",
    `SELECT b.* FROM geocoder.building b
     JOIN geocoder.neighborhood n ON b.neighborhood_id = n.id
     JOIN geocoder.district d ON n.district_id = d.id
     WHERE d.municipality_id = '${muniRow[0]!.id.replace(/'/g, "''")}'`
  );
  await dumpCopy(
    "geocoder.address",
    `SELECT a.* FROM geocoder.address a
     WHERE a.${buildingFilter}`
  );
  await dumpCopy(
    "geocoder.residence",
    `SELECT r.* FROM geocoder.residence r
     WHERE r.${buildingFilter}`
  );

  // ------------------------------------------------------------------------
  // 3. data.* per-building tables (filtered)
  // ------------------------------------------------------------------------
  const dataTables = [
    "data.building_cluster",
    "data.building_elevation",
    "data.building_geographic_region",
    "data.building_groundwater_level",
    "data.building_ownership",
    "data.building_pleistocene",
    "data.building_subsidence",
    "data.building_precomputed",
  ];
  for (const t of dataTables) {
    console.log(`Dumping ${t}...`);
    await dumpCopy(t, `SELECT * FROM ${t} WHERE ${buildingFilter}`);
  }

  // ------------------------------------------------------------------------
  // 4. Synthetic application data
  // ------------------------------------------------------------------------
  console.log("Emitting synthetic application data...");

  const keyHash = createHash("sha256")
    .update(SYNTH.authKeyPlaintext)
    .digest("hex");

  await write(`-- ============================================================
-- Synthetic application data (no real user/org/key carried over)
-- ============================================================
-- Plaintext API key (display once, never logged elsewhere):
--   ${SYNTH.authKeyPlaintext}
-- Admin login email: admin@test.local  (password_hash NULL — use API key
--   or run a Better Auth password-set flow once on first login)

INSERT INTO application.contractor (id, name) VALUES
  (${SYNTH.contractorId}, ${q("Test Contractor")})
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application.organization (id, name) VALUES
  (${q(SYNTH.organizationId)}, ${q("Test Organization")})
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application."user" (id, given_name, last_name, email, role, email_verified) VALUES
  (${q(SYNTH.adminUserId)},    ${q("Test")}, ${q("Admin")},    ${q("admin@test.local")},    'administrator', true),
  (${q(SYNTH.reviewerUserId)}, ${q("Test")}, ${q("Reviewer")}, ${q("reviewer@test.local")}, 'user',          true)
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application.organization_user (user_id, organization_id, role) VALUES
  (${q(SYNTH.adminUserId)},    ${q(SYNTH.organizationId)}, 'superuser'),
  (${q(SYNTH.reviewerUserId)}, ${q(SYNTH.organizationId)}, 'reader')
  ON CONFLICT DO NOTHING;

INSERT INTO application.attribution (id, reviewer_id, creator_id, owner_id, contractor_id) VALUES
  (${SYNTH.attributionId}, ${q(SYNTH.reviewerUserId)}, ${q(SYNTH.adminUserId)},
   ${q(SYNTH.organizationId)}, ${SYNTH.contractorId})
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application.auth_key (id, user_id, name, key_hash, created_at) VALUES
  (${q(SYNTH.authKeyId)}, ${q(SYNTH.adminUserId)}, ${q("seed-key")},
   ${q(keyHash)}, now())
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application.mapset (id, name, style, layers, public, "order") VALUES
  (${q(SYNTH.mapsetId)}, ${q("Rotterdam Test")},
   ${q("mapbox://styles/mapbox/streets-v12")},
   ARRAY[]::text[], false, 0)
  ON CONFLICT (id) DO NOTHING;

INSERT INTO application.organization_mapset (organization_id, mapset_id, metadata) VALUES
  (${q(SYNTH.organizationId)}, ${q(SYNTH.mapsetId)}, '{}'::jsonb)
  ON CONFLICT DO NOTHING;

INSERT INTO application.organization_geolock_municipality (organization_id, municipality_id) VALUES
  (${q(SYNTH.organizationId)}, ${q(MUNICIPALITY)})
  ON CONFLICT DO NOTHING;

`);

  // ------------------------------------------------------------------------
  // 5. Synthetic inquiries + samples
  // ------------------------------------------------------------------------
  console.log(`Emitting ${SYNTHETIC_INQUIRIES} synthetic inquiries...`);
  const rng = makeRng(SEED);

  // Pick distinct buildings deterministically.
  const shuffled = [...buildingRows];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [shuffled[i]!, shuffled[j]!] = [shuffled[j]!, shuffled[i]!];
  }
  const targets = shuffled.slice(0, Math.min(SYNTHETIC_INQUIRIES, shuffled.length));

  await write(`-- ============================================================
-- Synthetic report.inquiry + inquiry_sample (one sample per inquiry,
-- one inquiry per target building, varied enum values).
-- ============================================================

`);

  // Build INSERT batches to keep the .sql readable and fast to load.
  const inquiryRows: string[] = [];
  const sampleRows: string[] = [];
  for (let i = 0; i < targets.length; i++) {
    const inquiryId = SYNTH.inquiryIdStart + i;
    const sampleId = SYNTH.inquirySampleIdStart + i;
    const b = targets[i]!;
    const inquiryType = pick(rng, INQUIRY_TYPES);

    // document_date must be >= built_year - 5y for the matview to pick it.
    // Use today minus a small jitter; that's safely after any built_year.
    const docDate = new Date();
    docDate.setUTCDate(docDate.getUTCDate() - Math.floor(rng() * 365 * 3));
    const docDateStr = docDate.toISOString().slice(0, 10);

    inquiryRows.push(
      `  (${inquiryId}, ${q(`seed-inquiry-${inquiryId}`)}, ${q(`seed-inquiry-${inquiryId}.pdf`)}, ` +
      `${q(docDateStr)}, ${SYNTH.attributionId}, ${q(inquiryType)})`
    );

    const builtYear = b.built_year ?? 1950;
    const builtYearStr = `${builtYear}-01-01`;
    sampleRows.push(
      `  (${sampleId}, ${inquiryId}, ${q(b.external_id)}, ` +
      `${q(builtYearStr)}, ${q(pick(rng, FOUNDATION_TYPES))}, ` +
      `${q(pick(rng, FOUNDATION_QUALITIES))}, ${q(pick(rng, ENFORCEMENT_TERMS))}, ` +
      `${q(pick(rng, DAMAGE_CAUSES))}, ${rng() < 0.5 ? "true" : "false"}, ` +
      `${qNum(-1 - rng() * 3)}, ${qNum(-2 - rng() * 4)}, ${qNum(-1 - rng() * 2)})`
    );
  }

  // Chunk INSERTs at 500 rows each so a syntax error in one chunk doesn't
  // wedge the whole load.
  for (let i = 0; i < inquiryRows.length; i += 500) {
    const slice = inquiryRows.slice(i, i + 500);
    await write(
      `INSERT INTO report.inquiry (id, document_name, document_file, document_date, attribution_id, type) VALUES\n` +
      slice.join(",\n") +
      `\n  ON CONFLICT (id) DO NOTHING;\n\n`
    );
  }
  for (let i = 0; i < sampleRows.length; i += 500) {
    const slice = sampleRows.slice(i, i + 500);
    await write(
      `INSERT INTO report.inquiry_sample (id, inquiry_id, building_id, built_year, foundation_type, overall_quality, enforcement_term, damage_cause, recovery_advised, groundwater_level_temp, wood_level, foundation_depth) VALUES\n` +
      slice.join(",\n") +
      `\n  ON CONFLICT (id) DO NOTHING;\n\n`
    );
  }

  // ------------------------------------------------------------------------
  // 6. Sequence resets
  // ------------------------------------------------------------------------
  await write(`-- Bump sequences past synthetic IDs so future INSERTs don't collide.
SELECT setval('application.contractor_id_seq',  ${SYNTH.contractorId + 1}, false);
SELECT setval('application.attribution_id_seq', ${SYNTH.attributionId + 1}, false);
SELECT setval('report.inquiry_id_seq',          ${SYNTH.inquiryIdStart + SYNTHETIC_INQUIRIES + 1}, false);
SELECT setval('report.inquiry_sample_id_seq',   ${SYNTH.inquirySampleIdStart + SYNTHETIC_INQUIRIES + 1}, false);

COMMIT;
SET session_replication_role = 'origin';

-- Populate matviews. ~minutes on a small subset.
CALL data.refresh_all();
`);

  console.log("Closing output...");
  await flush();
  await sql.end({ timeout: 5 });
  console.log(`Wrote ${OUTPUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
