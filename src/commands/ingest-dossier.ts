import { log, ACCENT, RESET } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as pdf from "../providers/pdf.ts";
import * as vision from "../providers/vision.ts";
import { mayEstablishFoundationType, FIELDS_REQUIRING_ADMISSIBLE_SOURCE } from "../providers/admissibility.ts";
import * as s3 from "../providers/s3.ts";
import { env } from "../config.ts";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";

/**
 * Walk one document through the Data Ops front door.
 *
 *   sniff -> redact -> classify every page -> pick a lane -> read -> propose
 *
 * Nothing here decides anything. Every value lands in dataops.extraction_field
 * as 'pending' for a person to confirm, or as 'auto_accepted' when it clears
 * the confidence gate AND carries the passage it came from. The gate without
 * the evidence requirement would be worth little: in the extraction benchmark
 * one groundwater level in 39 was fabricated, at ordinary confidence, and was
 * indistinguishable from the real ones until someone opened the report.
 *
 * Two ways in, and they differ only at the front:
 *
 *   --file      a document we are bringing in ourselves. Upload it, open a
 *               dossier (or attach to one), then read it.
 *   --dossier   a submission that already exists. The public form has already
 *               written the dossier and its artifacts and put the bytes in
 *               Spaces, so there is nothing to upload and nothing to insert --
 *               only the reading half is left.
 *
 * The second exists because the review queue joins through `extraction`. A
 * dossier nobody has read has no extraction, so it never appears, and a
 * submission can sit correctly stored and completely invisible.
 *
 *   bun run src/commands/ingest-dossier.ts --file <path|s3://key> [--dry-run]
 *   bun run src/commands/ingest-dossier.ts --dossier <id> [--dry-run]
 *   bun run src/commands/ingest-dossier.ts --reference FM2026-000042 [--dry-run]
 */

export interface IngestResult {
  dossierId: number | null;
  artifactId: number | null;
  lane: "vision" | "text" | "none";
  pages: number;
  redactedPages: number;
  fields: number;
  autoAccepted: number;
}

/**
 * Everything the pipeline stores lives under this prefix, and nothing it stores
 * lives anywhere else.
 *
 * `inquiry-report/` holds the documents behind report.inquiry -- 30,814 files
 * that customers, the risk model and seven years of survey work depend on. The
 * pipeline reads from it and must never write to it: a machine that can add,
 * replace or overwrite objects there can corrupt the record it is supposed to
 * be reading. Keeping the two prefixes disjoint means a mistake in this command
 * can cost at worst a re-ingest, never a lost survey.
 *
 * On acceptance a document is COPIED into inquiry-report/ through the ordinary
 * inquiry path, with its own key. It is never referenced across the boundary.
 */
const DATAOPS_PREFIX = "dataops/";

/** Material classes that carry no foundation information worth paying to read. */
const BARREN = new Set(["photo", "blank", "map"]);

export async function ingestDossier(payload: {
  file: string;
  /**
   * Attach to an existing dossier instead of opening a new one.
   *
   * A dossier is one SUBMISSION, not one file. Don's batch for Oeverlaan 43 is
   * nine files -- a 1991 drawing, a municipal archive file, a 102-page
   * funderingsonderzoek, records of the works -- all describing the same
   * building. Processed as nine dossiers that connection is lost, and the
   * reviewer sees nine unrelated proposals instead of one property with a
   * paper trail.
   */
  dossier_id?: number;
  /**
   * Read an artifact row that already exists rather than creating one.
   *
   * Set for anything the public form delivered: the API wrote the row and the
   * browser put the bytes in `intake/` before this command ever runs. Creating
   * a second row would give the reviewer the same document twice and leave the
   * first copy forever unread.
   */
  artifact_id?: number;
  /**
   * What the sender said the document is. Bounds what may be concluded from it
   * -- a `quickscan` cannot establish a foundation type, because the type in a
   * QuickScan is our own data coming back. Never overrides classification.
   */
  declared_category?: string;
  /** The sender's filename, when `file` is a uuid key that says nothing. */
  display_name?: string;
  channel?: "email" | "upload" | "bulk_drop" | "api" | "invoer_app";
  subject?: string;
  external_ref?: string;
  dry_run?: boolean;
  tmp_dir?: string;
}): Promise<IngestResult> {
  const { file, channel = "upload", dry_run = false } = payload;
  if (!file) throw new Error("Missing required field 'file'");
  if (!env.OPENROUTER_API_KEY) throw new Error("OPENROUTER_API_KEY is not set");

  const workDir = payload.tmp_dir ?? (await mkdtemp(join(tmpdir(), "fm-dossier-")));
  const localPath = join(workDir, basename(file));
  const result: IngestResult = {
    dossierId: null, artifactId: null, lane: "none",
    pages: 0, redactedPages: 0, fields: 0, autoAccepted: 0,
  };

  try {
    // -- fetch ---------------------------------------------------------------
    let storageKey = file;
    if (file.startsWith("s3://")) {
      // Reading from inquiry-report/ is normal -- that is where the historical
      // corpus lives. The row then points at the original object and no copy is
      // made, so nothing in that prefix is touched.
      storageKey = file.replace("s3://", "");
      log.step("Downloading from S3");
      await s3.downloadFile(localPath, storageKey);
    } else if (payload.artifact_id) {
      // Should not be reachable: an existing artifact always carries an s3 key.
      throw new Error("--dossier mode expects artifacts with an s3 storage_key");
    } else {
      await Bun.write(localPath, Bun.file(file));

      // Upload it. A dossier whose storage_key points at nothing is worse than
      // no dossier: the review screen mints a signed URL, the reviewer gets a
      // 404, and there is no way to check a citation against the page it came
      // from. An earlier version computed the key without ever putting the file
      // there, and every one of 891 artifacts pointed into the void.
      //
      // Keyed by uuid like inquiry-report/, with the original name kept on the
      // artifact row: two people send "Funderingsrapport.pdf" in the same week.
      const ext = (file.split(".").pop() ?? "bin").toLowerCase();
      storageKey = `${DATAOPS_PREFIX}${crypto.randomUUID()}.${ext}`;
      // Belt and braces. The key is built above and cannot currently escape the
      // prefix, but this command will be edited by someone who does not know
      // what inquiry-report/ costs to lose.
      if (!storageKey.startsWith(DATAOPS_PREFIX)) {
        throw new Error(
          `refusing to write outside ${DATAOPS_PREFIX}: ${storageKey}. ` +
            `inquiry-report/ is the survey record and the pipeline never writes there.`,
        );
      }
      log.step(`Uploading to ${storageKey}`);
      const mime = (await pdf.fileKind(localPath)) === "pdf"
        ? "application/pdf"
        : `image/${ext === "jpg" ? "jpeg" : ext}`;
      await s3.uploadFile(localPath, storageKey, undefined, { ContentType: mime });
    }

    const kind = await pdf.fileKind(localPath);
    if (kind === "other") throw new Error(`unsupported file type: ${basename(file)}`);

    // -- sniff ---------------------------------------------------------------
    // Never trust the extension. The type on report.inquiry is no better a
    // guide: 42 of 160 `foundation_research` files turned out to be scans.
    const size = Bun.file(localPath).size;
    const pages = kind === "pdf" ? await pdf.pageCount(localPath) : 1;
    result.pages = pages;
    log.step(
      kind === "pdf"
        ? `pdf, ${pages} pages, ${(size / 1024 / 1024).toFixed(1)} MB, producer "${await pdf.producer(localPath)}"`
        : `image, ${(size / 1024 / 1024).toFixed(1)} MB`
    );

    const pageChars: number[] = [];
    if (kind === "pdf") {
      for (let p = 1; p <= pages; p++) {
        pageChars.push((await pdf.pageText(localPath, p, false)).replace(/\s/g, "").length);
      }
    }
    const totalChars = pageChars.reduce((a, b) => a + b, 0);
    const scanned = kind === "image" ? 1 : pageChars.filter(pdf.looksScanned).length;

    // Route on CHARACTERS, not on how many pages happen to be scans.
    //
    // The first version of this rule also required `scanned < pages / 2`, and a
    // 102-page funderingsonderzoek with 70,470 characters of text failed it:
    // 54 of its pages were scanned appendices and photographs, so a document
    // that is unambiguously a typed report was sent down the vision lane,
    // truncated to 8 pages, and produced nothing. Worse, redaction painted out
    // the report's own text on the way -- the exact damage the lane split
    // exists to prevent.
    //
    // A scan's added caption runs to ~60 characters and a preparer's cover
    // sheet to ~300, so 2,000 separates the two cases without needing to count
    // pages at all. Mixed documents ultimately want both lanes and a merge;
    // until then, text wins, because that is where the evidence is.
    // An image has no text layer, so the text lane is not available to it.
    const textLane = kind === "pdf" && totalChars >= 2000;
    result.lane = textLane ? "text" : "vision";
    log.step(`lane: ${ACCENT.type}${result.lane}${RESET} (${totalChars} text chars, ${scanned}/${pages} pages look scanned)`);

    // -- rows ----------------------------------------------------------------
    if (!dry_run) {
      if (payload.dossier_id) {
        result.dossierId = payload.dossier_id;
        log.step(`attaching to existing dossier #${payload.dossier_id}`);
      } else {
        const [d] = await sql<{ id: number }[]>`
          INSERT INTO dataops.dossier (channel, subject, external_ref)
          VALUES (${channel}, ${payload.subject ?? null}, ${payload.external_ref ?? null})
          RETURNING id`;
        result.dossierId = d!.id;
        log.step(`opened dossier #${d!.id}`);
      }
    }

    if (!dry_run) {
      if (payload.artifact_id) {
        // The row is the form's; only what reading it taught us is ours to
        // write. Filename, size and mime stay as the sender sent them.
        result.artifactId = payload.artifact_id;
        await sql`
          UPDATE dataops.artifact
             SET lane = ${result.lane}, page_count = ${pages}
           WHERE id = ${payload.artifact_id}`;
        log.step(`reading existing artifact #${payload.artifact_id}`);
      } else {
        const [a] = await sql<{ id: number }[]>`
          INSERT INTO dataops.artifact
            (dossier_id, storage_key, original_filename, mime_type, size_bytes, page_count, lane)
          VALUES (${result.dossierId}, ${storageKey}, ${basename(file)},
                  ${kind === "pdf" ? "application/pdf" : "image/jpeg"},
                  ${size}, ${pages}, ${result.lane})
          RETURNING id`;
        result.artifactId = a!.id;
      }
    }

    // -- redact + classify ---------------------------------------------------
    // The vision lane needs images with every preparer annotation painted out.
    // The text lane keeps its text, so only the cover page is dropped -- and
    // the cover is recognised by the same signal: a short, typed page in a file
    // that is otherwise a report.
    const annotations: string[] = [];
    const annotationPages: number[] = [];
    const cleanPages: { page: number; b64: string; material: string | null }[] = [];

    if (result.lane === "vision") {
      const cap = Math.min(pages, 8);
      for (let p = 1; p <= cap; p++) {
        const r =
          kind === "image"
            ? await pdf.prepareImage(localPath, workDir)
            : await pdf.redactPage(localPath, p, workDir);
        if (r.redacted > 0) {
          result.redactedPages++;
          annotations.push(r.annotation);
          annotationPages.push(p);
        }
        const b64 = (await readFile(r.path)).toString("base64");
        const verdict = await vision.classifyPage(b64);

        // Fail closed: a page the classifier could not vouch for, or one that
        // still shows the answer, does not go to the reader.
        const usable = verdict.leaks === false && !BARREN.has(verdict.material ?? "other");
        if (usable) cleanPages.push({ page: p, b64, material: verdict.material });

        // Persist the triage. It decides the routing, it explains after the
        // fact why a page was dropped, and without it a reviewer looking at a
        // thin result has no way to see that six of eight pages were blanks.
        if (!dry_run) {
          await sql`
            INSERT INTO dataops.artifact_page
              (artifact_id, page_no, material, material_conf, is_clean, redacted_boxes, text_chars)
            VALUES (${result.artifactId}, ${p},
                    ${(verdict.material ?? null) as string | null},
                    ${verdict.confidence}, ${usable}, ${r.redacted},
                    ${pageChars[p - 1] ?? 0})
            ON CONFLICT (artifact_id, page_no) DO NOTHING`;
        }
        log.step(
          `  page ${p}: ${verdict.material ?? "?"}` +
            (verdict.leaks === false ? "" : verdict.leaks ? "  LEAKS -> dropped" : "  unreadable -> dropped") +
            (BARREN.has(verdict.material ?? "") ? "  (no evidence -> human)" : "")
        );
      }
    } else {
      // Text lane: find the preparer's summary by its template, on ANY page.
      // Size heuristics do not work here -- see pdf.looksLikeCoverSheet.
      for (let p = 1; p <= pages; p++) {
        if ((pageChars[p - 1] ?? 0) === 0) continue;
        const t = await pdf.pageText(localPath, p);
        if (!pdf.looksLikeCoverSheet(t)) continue;
        annotations.push(t.trim());
        annotationPages.push(p);
        result.redactedPages++;
      }
      if (!dry_run) {
        for (let p = 1; p <= pages; p++) {
          await sql`
            INSERT INTO dataops.artifact_page
              (artifact_id, page_no, material, material_conf, is_clean, redacted_boxes, text_chars)
            VALUES (${result.artifactId}, ${p},
                    ${annotationPages.includes(p) ? "other" : "report"}, NULL,
                    ${!annotationPages.includes(p)}, 0, ${pageChars[p - 1] ?? 0})
            ON CONFLICT (artifact_id, page_no) DO NOTHING`;
        }
      }
    }

    // What the preparer added is only known once every page has been through
    // redaction, so it lands as an update rather than at insert time.
    if (!dry_run && annotationPages.length > 0) {
      await sql`
        UPDATE dataops.artifact
           SET annotation_text  = ${annotations.join("\n---\n") || null},
               annotation_pages = ${annotationPages}
         WHERE id = ${result.artifactId}`;
    }

    // -- read ----------------------------------------------------------------
    const started = Date.now();
    let fields: vision.FieldRead[] = [];

    if (result.lane === "text") {
      fields = await vision.extractFields(
        await pdf.documentText(localPath, 1, annotationPages)
      );
    } else if (cleanPages.length > 0) {
      const read = await vision.readDrawing(cleanPages.map((p) => p.b64));
      if (read.foundationType) {
        fields = [{
          field: "funderingstype",
          value: read.foundationType,
          evidence: read.evidence,
          confidence: read.confidence,
        }];
      }
    } else {
      log.warn("no page carries usable evidence — routed to a human, no model call made");
    }

    // Can this document establish a foundation type at all? A QuickScan or an
    // NWWI risk report states one, but it is FunderMaps data coming back to us.
    // Reading it is not extraction; it is a loop. See providers/admissibility.ts.
    const sourceText =
      result.lane === "text"
        ? await pdf.documentText(localPath, 1, annotationPages)
        : annotations.join(" ");
    // The sender's own label is the strongest signal available for a scan, and
    // the only one on a document whose filename is a uuid. Passing `file` alone
    // here would silently disarm the QuickScan check for everything the public
    // form delivers.
    const adm = mayEstablishFoundationType(
      sourceText,
      payload.display_name ?? file,
      payload.declared_category,
    );
    if (!adm.ok) {
      log.warn(`bron niet toelaatbaar voor funderingstype`, { reden: adm.reason?.slice(0, 90) });
      fields = fields.map(f =>
        FIELDS_REQUIRING_ADMISSIBLE_SOURCE.has(f.field)
          ? { ...f, rejected: adm.reason }
          : f
      );
    }

    result.fields = fields.length;

    // Decide the gate here, not inside the write path: a --dry-run has to
    // report exactly what a real run would do, or it is not a rehearsal.
    // Inference is allowed and often right, but it is not the same as reading a
    // value off the page, and the two were previously indistinguishable at the
    // gate. The prompt now makes the model mark an inferred value with
    // "afgeleid:"; anything so marked goes to a human whatever it scores.
    const inferred = (f: vision.FieldRead) => /^\s*afgeleid\s*:/i.test(f.evidence ?? "");
    const cleared = (f: vision.FieldRead) =>
      !f.rejected &&
      (f.confidence ?? 0) >= env.DATAOPS_AUTO_ACCEPT &&
      !!f.evidence?.trim() &&
      !inferred(f);
    result.autoAccepted = fields.filter(cleared).length;

    if (!dry_run && result.artifactId !== null) {
      const [ex] = await sql<{ id: number }[]>`
        INSERT INTO dataops.extraction
          (artifact_id, model, prompt_version, lane, pages_sent, finished_at)
        VALUES (${result.artifactId},
                ${result.lane === "text" ? env.DATAOPS_TEXT_MODEL : env.DATAOPS_VISION_MODEL},
                'dataops-2026.1', ${result.lane},
                ${result.lane === "text" ? pages : cleanPages.length}, now())
        RETURNING id`;

      for (const f of fields) {
        // Auto-accept needs BOTH a high score and a passage to point at.
        const auto = cleared(f);
        // A value from an inadmissible source is kept, not discarded: the
        // reviewer should see what the document said and why we will not take
        // it. 'rejected' plus the reason in the evidence makes that legible.
        await sql`
          INSERT INTO dataops.extraction_field
            (extraction_id, field, value, confidence, evidence, state)
          VALUES (${ex!.id}, ${f.field}, ${f.value}, ${f.confidence},
                  ${f.rejected ? `${f.rejected}\n\nCitaat uit het document: ${f.evidence ?? ""}` : f.evidence},
                  ${f.rejected ? "rejected" : auto ? "auto_accepted" : "pending"})`;
      }
    }

    for (const f of fields) {
      const gate = f.rejected
        ? `${ACCENT.fail}geweigerd${RESET}`
        : cleared(f)
        ? `${ACCENT.ok}auto${RESET}`
        : inferred(f)
          ? `${ACCENT.muted}human(afgeleid)${RESET}`
          : `${ACCENT.muted}human${RESET}`;
      log.step(
        `  ${f.field} = ${ACCENT.type}${f.value}${RESET} ` +
          `(${f.confidence ?? "?"}) ${gate}  ${ACCENT.muted}${(f.evidence ?? "no evidence").slice(0, 70)}${RESET}`
      );
    }
    log.step(
      `${result.fields} field(s) proposed, ${result.autoAccepted} cleared the gate`,
      Date.now() - started
    );
    return result;
  } finally {
    if (!payload.tmp_dir) await rm(workDir, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Read a submission that already exists.
 *
 * The public form writes the dossier, the artifact rows and the bytes before
 * this command ever runs, so there is nothing to acquire — only the reading
 * half of the pipeline is left to do.
 *
 * Only artifacts with no extraction are touched, which makes the command safe
 * to re-run: a submission that failed halfway resumes, and one already read is
 * a no-op rather than a second set of proposals for the same document.
 */
export async function readSubmission(payload: {
  dossier_id?: number;
  reference?: string;
  /** Read artifacts that already have an extraction as well. Off by default. */
  again?: boolean;
  dry_run?: boolean;
}): Promise<IngestResult[]> {
  const [d] = await sql<{ id: number; reference: string | null; subject: string | null }[]>`
    SELECT id, reference, subject FROM dataops.dossier
     WHERE ${payload.dossier_id ? sql`id = ${payload.dossier_id}` : sql`reference = ${payload.reference ?? null}`}
     LIMIT 1`;
  if (!d) throw new Error(`no dossier for ${payload.dossier_id ?? payload.reference}`);

  const artifacts = await sql<
    { id: number; storage_key: string; original_filename: string | null; declared_category: string | null }[]
  >`
    SELECT a.id, a.storage_key, a.original_filename, a.declared_category
      FROM dataops.artifact a
     WHERE a.dossier_id = ${d.id}
       ${payload.again ? sql`` : sql`AND NOT EXISTS (SELECT 1 FROM dataops.extraction e WHERE e.artifact_id = a.id)`}
     ORDER BY a.id`;

  log.info(`dossier #${d.id}${d.reference ? ` (${d.reference})` : ""}`, {
    onderwerp: d.subject ?? "-",
    "te lezen": artifacts.length,
  });
  if (artifacts.length === 0) {
    log.warn("nothing to read — every artifact already has an extraction");
    return [];
  }

  const results: IngestResult[] = [];
  for (const [i, a] of artifacts.entries()) {
    log.step(`${ACCENT.type}[${i + 1}/${artifacts.length}]${RESET} ${a.original_filename ?? a.storage_key}` +
      (a.declared_category ? ` ${ACCENT.muted}(sender: ${a.declared_category})${RESET}` : ""));
    try {
      results.push(
        await ingestDossier({
          file: `s3://${a.storage_key}`,
          dossier_id: d.id,
          artifact_id: a.id,
          declared_category: a.declared_category ?? undefined,
          display_name: a.original_filename ?? undefined,
          dry_run: payload.dry_run,
        }),
      );
    } catch (e) {
      // One unreadable file must not strand the rest of a submission. The
      // artifact keeps no extraction, so a later run picks it up again.
      log.error(`  ${a.original_filename ?? a.storage_key}: ${String(e)}`);
    }
  }
  return results;
}

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };

  const file = arg("file");
  const dossierArg = arg("dossier");
  const reference = arg("reference");

  if (!file && !dossierArg && !reference) {
    console.error(
      "usage:\n" +
        "  bring a document in:\n" +
        "    ingest-dossier --file <path|s3://key> [--dossier <id>] [--channel upload]\n" +
        "                   [--subject ...] [--ref ...] [--dry-run]\n" +
        "    --dossier attaches the file to an existing submission instead of opening a new one\n" +
        "\n" +
        "  read a submission that already exists (the public form writes these):\n" +
        "    ingest-dossier --dossier <id> [--again] [--dry-run]\n" +
        "    ingest-dossier --reference FM2026-000042 [--again] [--dry-run]\n" +
        "    reads only artifacts with no extraction, so it is safe to re-run"
    );
    process.exit(1);
  }

  log.banner("Data Ops — ingest dossier");
  try {
    if (!file) {
      const rs = await readSubmission({
        dossier_id: dossierArg ? Number(dossierArg) : undefined,
        reference,
        again: argv.includes("--again"),
        dry_run: argv.includes("--dry-run"),
      });
      log.info("done", {
        documenten: rs.length,
        velden: rs.reduce((n, r) => n + r.fields, 0),
        auto: rs.reduce((n, r) => n + r.autoAccepted, 0),
      });
      process.exit(0);
    }

    const r = await ingestDossier({
      file,
      channel: (arg("channel") as any) ?? "upload",
      subject: arg("subject"),
      external_ref: arg("ref"),
      dossier_id: dossierArg ? Number(dossierArg) : undefined,
      dry_run: argv.includes("--dry-run"),
    });
    log.info("done", { ...r });
    process.exit(0);
  } catch (e) {
    log.error(String(e));
    process.exit(1);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
}
