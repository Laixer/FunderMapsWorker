/**
 * Bring the documents of a FunderConsult loket export into Data Ops.
 *
 * The loket is where terugmeldingen arrived before melden.fundermaps.com. Its
 * export (ClientApp #340) is an Excel sheet plus one private copy per attachment
 * in `fundermaps-data`. This command reads the manifest that
 * scripts/loket_manifest.py distils from the sheet -- identifiers, state, the
 * reported BAG id and the attachment list, never the melder -- and does the
 * intake half of the pipeline for every melding in it:
 *
 *   one dossier per melding      channel bulk_drop, external_ref loket:<id>,
 *                                the reported address as bag_id + building_id
 *   one artifact per new file    copied to intake/loket/<sha256>.<ext> in the
 *                                pipeline bucket, declared_category from the
 *                                loket's own label
 *   nothing for a known file     the same bytes already sit in a dossier: that
 *                                artifact is reused, and when its dossier has
 *                                no address yet it gets this melding's
 *
 * Reading is not done here. The hourly Windmill sweep (or `ingest-dossier
 * --dossier <id>`) reads every artifact without an extraction, and the
 * resolver in there uses dossier.building_id to break ties -- which is why the
 * address is written first.
 *
 * Identity is content. Neither the export's object names nor our filenames say
 * which document is which (0 of 4,386 matched by name, 817 by bytes), so every
 * source object is hashed, and so is every stored artifact of a matching size.
 * Re-running is safe: dossiers are found by external_ref, artifacts by storage
 * key, and a file that is already there is never copied or registered twice.
 *
 *   bun run src/commands/load-loket-export.ts --manifest manifest.tsv
 *        [--source-bucket fundermaps-data] [--exceptions exceptions.tsv]
 *        [--hash-cache hashes.json] [--limit N] [--dry-run]
 */

import { log, ACCENT, RESET } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as s3 from "../providers/s3.ts";
import { env } from "../config.ts";

const STORAGE_PREFIX = "intake/loket";
const CHANNEL = "bulk_drop";
const REF_PREFIX = "loket:";

/** The loket's category labels, mapped onto the form vocabulary artifact.declared_category uses. */
const CATEGORY: Record<string, string> = {
  archieveresearch: "archieveresearch",
  archieftekeningen: "archieveresearch",
  foundationresearch: "foundationresearch",
  funderingsonderzoek: "foundationresearch",
  quickscan: "quickscan",
  herstelbewijs: "herstelbewijs",
  foto: "foto",
};

const EXTENSION: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/tiff": "tif",
  "image/heic": "heic",
  "image/heif": "heif",
  "image/webp": "webp",
};

interface Row {
  melding_nr: string;
  melding_id: string;
  submitted: string;
  status: string;
  fase: string;
  bag_id: string;
  topic: string;
  request_category: string;
  file_key: string;
  file_name: string;
  size: string;
  mime: string;
  category: string;
}

interface Known {
  artifact_id: number;
  dossier_id: number;
  building_id: string | null;
  external_ref: string | null;
}

interface Exception {
  melding_nr: string;
  sha: string;
  reason: string;
}

/** Dossiers this run already gave an address, so a second file of the same dossier does not write twice. */
const adopted = new Set<number>();

const counts = {
  meldingen: 0,
  dossiers_created: 0,
  dossiers_existing: 0,
  address_set: 0,
  files: 0,
  files_new: 0,
  files_known: 0,
  dossiers_adopted: 0,
  files_skipped_existing: 0,
  bytes_copied: 0,
  exceptions: 0,
};

function parseManifest(text: string): Row[] {
  const [head, ...lines] = text.trim().split("\n");
  const cols = head!.split("\t");
  return lines.map((l) => {
    const v = l.split("\t");
    return Object.fromEntries(cols.map((c, i) => [c, v[i] ?? ""])) as unknown as Row;
  });
}

function sha256(bytes: Uint8Array): string {
  return new Bun.CryptoHasher("sha256").update(bytes).digest("hex");
}

/**
 * Content hashes of every artifact we hold whose size matches a manifest file.
 * Same bytes means same size, so this is the whole candidate set; hashing a
 * few thousand objects is a minute, and the cache makes the second run free.
 */
async function indexKnown(sizes: Set<number>, cachePath: string | undefined): Promise<Map<string, Known[]>> {
  const cache: Record<string, string> = cachePath && (await Bun.file(cachePath).exists())
    ? await Bun.file(cachePath).json()
    : {};
  const rows = await sql<{ id: number; storage_key: string; size_bytes: number; dossier_id: number; building_id: string | null; external_ref: string | null }[]>`
    SELECT a.id, a.storage_key, a.size_bytes, a.dossier_id, d.building_id, d.external_ref
      FROM dataops.artifact a JOIN dataops.dossier d ON d.id = a.dossier_id
     WHERE a.size_bytes = ANY(${[...sizes]})`;
  log.step(`${rows.length} stored artifacts share a size with a manifest file; hashing the uncached ones`);
  const known = new Map<string, Known[]>();
  let hashed = 0;
  for (const r of rows) {
    let sha = cache[r.storage_key];
    if (!sha) {
      sha = sha256(await s3.downloadBytes(r.storage_key));
      cache[r.storage_key] = sha;
      hashed++;
    }
    const list = known.get(sha) ?? [];
    list.push({ artifact_id: r.id, dossier_id: r.dossier_id, building_id: r.building_id, external_ref: r.external_ref });
    known.set(sha, list);
  }
  if (cachePath) await Bun.write(cachePath, JSON.stringify(cache));
  log.step(`${hashed} hashed, ${rows.length - hashed} from cache, ${known.size} distinct documents`);
  return known;
}

/** BAG nummeraanduiding -> geocoder building, the way the intake form resolves it. */
async function resolveBuilding(bag: string): Promise<{ bag_id: string; building_id: string | null; status: "resolved" | "stale_bag" | "absent" }> {
  if (!bag) return { bag_id: "", building_id: null, status: "absent" };
  const external = `NL.IMBAG.NUMMERAANDUIDING.${bag}`;
  const [a] = await sql<{ building_id: string | null }[]>`
    SELECT building_id FROM geocoder.address WHERE external_id = ${external} LIMIT 1`;
  return { bag_id: external, building_id: a?.building_id ?? null, status: a?.building_id ? "resolved" : "stale_bag" };
}

async function findOrCreateDossier(m: Row, dry_run: boolean): Promise<{ id: number | null; building_id: string | null }> {
  const ref = REF_PREFIX + m.melding_id;
  const [existing] = await sql<{ id: number; building_id: string | null }[]>`
    SELECT id, building_id FROM dataops.dossier WHERE external_ref = ${ref} LIMIT 1`;
  if (existing) {
    counts.dossiers_existing++;
    return existing;
  }
  const addr = await resolveBuilding(m.bag_id);
  const subject = `${m.melding_nr} · ${m.submitted.slice(0, 10).replaceAll("-", "/")} · ${m.topic || "loket"}`;
  const payload = {
    source: "funderconsult-loket-export",
    melding_nr: m.melding_nr,
    status: m.status,
    fase: m.fase,
    topic: m.topic || null,
    request_category: m.request_category || null,
  };
  counts.dossiers_created++;
  if (addr.building_id) counts.address_set++;
  if (dry_run) return { id: null, building_id: addr.building_id };
  const [d] = await sql<{ id: number }[]>`
    INSERT INTO dataops.dossier
      (channel, subject, external_ref, received_at, bag_id, building_id, resolution_status, payload)
    VALUES (${CHANNEL}, ${subject}, ${ref}, ${m.submitted}, ${addr.bag_id || null}, ${addr.building_id},
            ${addr.status}, ${JSON.stringify(payload)})
    RETURNING id`;
  await sql`
    INSERT INTO dataops.dossier_entry
      (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
    VALUES (${d!.id}, 'received', 'system', 'loket-export',
            ${`Terugmelding ${m.melding_nr} overgenomen uit de loket-export`},
            ${JSON.stringify({ source: payload.source, status: m.status, fase: m.fase })}, false)`;
  return { id: d!.id, building_id: addr.building_id };
}

/**
 * The same bytes already sit in a dossier. Reuse that artifact; when its dossier
 * has no address and every file in it belongs to this melding, give it this
 * melding's. Anything less clear-cut is an exception for a person.
 */
async function adoptKnown(m: Row, hits: Known[], artifactMeldingen: Map<number, Set<string>>, dry_run: boolean, exceptions: Exception[], sha: string) {
  counts.files_known++;
  const dossiers = new Set(hits.map((h) => h.dossier_id));
  for (const dossierId of dossiers) {
    const hit = hits.find((h) => h.dossier_id === dossierId)!;
    if (hit.external_ref?.startsWith(REF_PREFIX)) continue; // one of ours from an earlier run
    if (hit.building_id || adopted.has(dossierId)) continue; // already placed; not ours to move
    // Every artifact of that dossier must be a file of this melding, or the
    // address would be a guess.
    const all = await sql<{ id: number }[]>`SELECT id FROM dataops.artifact WHERE dossier_id = ${dossierId}`;
    const foreign = all.some((a) => !artifactMeldingen.get(a.id)?.has(m.melding_id));
    if (foreign) {
      exceptions.push({ melding_nr: m.melding_nr, sha, reason: `known artifact #${hit.artifact_id} sits in dossier #${dossierId} with files of another melding; address not set` });
      continue;
    }
    const addr = await resolveBuilding(m.bag_id);
    if (!addr.building_id) {
      exceptions.push({ melding_nr: m.melding_nr, sha, reason: `known artifact #${hit.artifact_id} in dossier #${dossierId}; melding has no resolvable BAG id (${addr.status})` });
      continue;
    }
    counts.dossiers_adopted++;
    adopted.add(dossierId);
    if (dry_run) continue;
    await sql`
      UPDATE dataops.dossier
         SET bag_id = ${addr.bag_id}, building_id = ${addr.building_id}, resolution_status = 'resolved',
             payload = COALESCE(payload, '{}'::jsonb) || ${JSON.stringify({ loket_melding_nr: m.melding_nr, loket_melding_id: m.melding_id })}::jsonb,
             updated_at = now()
       WHERE id = ${dossierId} AND building_id IS NULL`;
    await sql`
      INSERT INTO dataops.dossier_entry (dossier_id, kind, actor_kind, actor, text, body, visible_to_melder)
      VALUES (${dossierId}, 'status', 'system', 'loket-export',
              ${`Adres overgenomen uit loket-terugmelding ${m.melding_nr}`},
              ${JSON.stringify({ bag_id: addr.bag_id })}, false)`;
  }
}

async function addFile(m: Row, dossierId: number | null, bytes: Uint8Array, sha: string, dry_run: boolean, exceptions: Exception[]) {
  const ext = EXTENSION[m.mime];
  if (!ext) {
    exceptions.push({ melding_nr: m.melding_nr, sha, reason: `unsupported type ${m.mime || "(unknown)"}; not loaded` });
    return;
  }
  const key = `${STORAGE_PREFIX}/${sha}.${ext}`;
  const [dup] = await sql<{ id: number }[]>`SELECT id FROM dataops.artifact WHERE storage_key = ${key} LIMIT 1`;
  if (dup) {
    counts.files_skipped_existing++;
    return;
  }
  counts.files_new++;
  counts.bytes_copied += bytes.byteLength;
  if (dry_run || dossierId === null) return;
  await s3.uploadBytes(bytes, key, undefined, { ContentType: m.mime });
  await sql`
    INSERT INTO dataops.artifact
      (dossier_id, storage_key, original_filename, mime_type, size_bytes, lane, declared_category)
    VALUES (${dossierId}, ${key}, ${m.file_name || null}, ${m.mime}, ${bytes.byteLength}, 'none',
            ${CATEGORY[m.category] ?? (m.category ? "overig" : null)})`;
}

export async function loadLoketExport(opts: { manifest: string; source_bucket: string; exceptions?: string; hash_cache?: string; limit?: number; dry_run: boolean }) {
  const rows = parseManifest(await Bun.file(opts.manifest).text());
  const meldingen = new Map<string, Row[]>();
  for (const r of rows) meldingen.set(r.melding_id, [...(meldingen.get(r.melding_id) ?? []), r]);
  const files = rows.filter((r) => r.file_key);
  log.info("manifest", { meldingen: meldingen.size, files: files.length, bucket: opts.source_bucket, dry_run: opts.dry_run });

  // Hash the source side first: which distinct documents are we looking at, and
  // which melding(s) does each belong to.
  const sourceSha = new Map<string, string>();
  const bySha = new Map<string, Uint8Array>();
  const byMelding = new Map<string, Set<string>>();
  log.step(`hashing ${files.length} source objects`);
  let i = 0;
  for (const f of files) {
    if (!sourceSha.has(f.file_key)) {
      const bytes = await s3.downloadBytes(f.file_key, opts.source_bucket);
      const sha = sha256(bytes);
      sourceSha.set(f.file_key, sha);
      if (!bySha.has(sha)) bySha.set(sha, bytes);
    }
    const sha = sourceSha.get(f.file_key)!;
    byMelding.set(f.melding_id, (byMelding.get(f.melding_id) ?? new Set()).add(sha));
    if (++i % 500 === 0) log.step(`${i}/${files.length} hashed`);
  }
  log.step(`${bySha.size} distinct documents in ${files.length} references`);

  const known = await indexKnown(new Set(files.map((f) => Number(f.size))), opts.hash_cache);
  // Which melding(s) each stored artifact belongs to, by content.
  const artifactMeldingen = new Map<number, Set<string>>();
  for (const [meldingId, shas] of byMelding) {
    for (const sha of shas) {
      for (const k of known.get(sha) ?? []) {
        artifactMeldingen.set(k.artifact_id, (artifactMeldingen.get(k.artifact_id) ?? new Set()).add(meldingId));
      }
    }
  }
  const exceptions: Exception[] = [];
  const seenSha = new Set<string>();

  let n = 0;
  for (const list of meldingen.values()) {
    if (opts.limit && n++ >= opts.limit) break;
    const m = list[0]!;
    counts.meldingen++;
    if (!m.bag_id) exceptions.push({ melding_nr: m.melding_nr, sha: "", reason: "no BAG nummeraanduiding on the melding" });
    const dossier = await findOrCreateDossier(m, opts.dry_run);
    log.step(`${ACCENT.type}${m.melding_nr}${RESET} dossier #${dossier.id ?? "(dry)"} ${list.filter((r) => r.file_key).length} file(s)`);
    for (const f of list) {
      if (!f.file_key) continue;
      counts.files++;
      const sha = sourceSha.get(f.file_key)!;
      const hits = known.get(sha);
      if (hits?.length) {
        await adoptKnown(f, hits, artifactMeldingen, opts.dry_run, exceptions, sha);
        continue;
      }
      if (seenSha.has(sha)) {
        // Same bytes under a second melding in this very export: the first
        // melding's dossier holds it, this one gets the exception line.
        exceptions.push({ melding_nr: f.melding_nr, sha, reason: "same document also filed under another melding in this export; loaded once" });
        continue;
      }
      seenSha.add(sha);
      await addFile(f, dossier.id, bySha.get(sha)!, sha, opts.dry_run, exceptions);
    }
  }

  counts.exceptions = exceptions.length;
  if (opts.exceptions) {
    await Bun.write(opts.exceptions, "melding_nr\tsha256\treason\n" + exceptions.map((e) => `${e.melding_nr}\t${e.sha}\t${e.reason}`).join("\n") + "\n");
  }
  log.info(opts.dry_run ? "dry run — nothing written" : "done", { ...counts, bytes_copied: `${(counts.bytes_copied / 1e9).toFixed(2)} GB` });
  return counts;
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };
  const manifest = arg("manifest");
  if (!manifest) {
    console.error(
      "usage: load-loket-export --manifest <tsv from scripts/loket_manifest.py>\n" +
        "         [--source-bucket fundermaps-data] [--exceptions <tsv>] [--hash-cache <json>]\n" +
        "         [--limit N] [--dry-run]\n" +
        "  loads dossiers + artifacts only; reading is the hourly sweep's job (or ingest-dossier --dossier)"
    );
    process.exit(1);
  }
  log.banner("Data Ops — load loket export");
  try {
    await loadLoketExport({
      manifest,
      source_bucket: arg("source-bucket") ?? "fundermaps-data",
      exceptions: arg("exceptions"),
      hash_cache: arg("hash-cache"),
      limit: arg("limit") ? Number(arg("limit")) : undefined,
      dry_run: argv.includes("--dry-run"),
    });
    process.exit(0);
  } catch (e) {
    log.error(String(e));
    process.exit(1);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
    void env;
  }
}
