import { log, ACCENT, RESET } from "../lib/log.ts";
import { sql } from "../db.ts";
import * as pdf from "../providers/pdf.ts";
import * as vision from "../providers/vision.ts";
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
 *   bun run src/commands/ingest-dossier.ts --file <path|s3://key> [--dry-run]
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
      storageKey = file.replace("s3://", "");
      log.step("Downloading from S3");
      await s3.downloadFile(localPath, storageKey);
    } else {
      await Bun.write(localPath, Bun.file(file));
      storageKey = `dataops/${basename(file)}`;
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
      const [a] = await sql<{ id: number }[]>`
        INSERT INTO dataops.artifact
          (dossier_id, storage_key, original_filename, mime_type, size_bytes, page_count, lane)
        VALUES (${result.dossierId}, ${storageKey}, ${basename(file)},
                ${kind === "pdf" ? "application/pdf" : "image/jpeg"},
                ${size}, ${pages}, ${result.lane})
        RETURNING id`;
      result.artifactId = a!.id;
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

    result.fields = fields.length;

    // Decide the gate here, not inside the write path: a --dry-run has to
    // report exactly what a real run would do, or it is not a rehearsal.
    // Inference is allowed and often right, but it is not the same as reading a
    // value off the page, and the two were previously indistinguishable at the
    // gate. The prompt now makes the model mark an inferred value with
    // "afgeleid:"; anything so marked goes to a human whatever it scores.
    const inferred = (f: vision.FieldRead) => /^\s*afgeleid\s*:/i.test(f.evidence ?? "");
    const cleared = (f: vision.FieldRead) =>
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
        await sql`
          INSERT INTO dataops.extraction_field
            (extraction_id, field, value, confidence, evidence, state)
          VALUES (${ex!.id}, ${f.field}, ${f.value}, ${f.confidence},
                  ${f.evidence}, ${auto ? "auto_accepted" : "pending"})`;
      }
    }

    for (const f of fields) {
      const gate = cleared(f)
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

if (import.meta.main) {
  const argv = process.argv.slice(2);
  const arg = (k: string) => {
    const i = argv.indexOf(`--${k}`);
    return i > -1 ? argv[i + 1] : undefined;
  };

  const file = arg("file");
  if (!file) {
    console.error(
      "usage: ingest-dossier --file <path|s3://key> [--dossier <id>] [--channel upload] [--subject ...] [--ref ...] [--dry-run]\n" +
        "       --dossier attaches the file to an existing submission instead of opening a new one"
    );
    process.exit(1);
  }

  log.banner("Data Ops — ingest dossier");
  try {
    const r = await ingestDossier({
      file,
      channel: (arg("channel") as any) ?? "upload",
      subject: arg("subject"),
      external_ref: arg("ref"),
      dossier_id: arg("dossier") ? Number(arg("dossier")) : undefined,
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
