import { readFile } from "node:fs/promises";
import { basename } from "node:path";
import { env } from "../config.ts";
import {
  EXTRACT_PROMPT, ADDRESS_PROMPT, EXTRACT_FIELDS, ADDRESS_FIELDS, enforcementTermCode,
  type FieldRead,
} from "../providers/vision.ts";

/**
 * EXPERIMENT (2026-09-01, Yorick: "why do we even route?"). Bench-only, never
 * on the production path.
 *
 * One lane: the PDF goes to the model as a document, in one call, with one
 * prompt asking for everything the two production prompts ask for. No text
 * layer, no lane rule, no page cap, no tiling. bench-extract scores it with
 * exactly the same truth and matching as the production text lane, so the
 * two tables are comparable line by line. The question is the numbers in
 * tables: the text lane reads "-2,47" verbatim; a document read may not.
 */

const OPENROUTER = "https://openrouter.ai/api/v1/chat/completions";
const MAX_PDF_BYTES = 28 * 1024 * 1024;

const QUALITY = new Set(["bad", "mediocre", "tolerable", "good", "mediocre_good", "mediocre_bad"]);
const QUALITY_NL: Record<string, string> = { slecht: "bad", matig: "mediocre", redelijk: "tolerable", goed: "good", matig_tot_goed: "mediocre_good", matig_tot_slecht: "mediocre_bad" };
const ENUMS: Record<string, Set<string>> = {
  wood_type: new Set(["pine", "spruce"]),
  wood_encroachment: new Set(["fungus_infection", "bio_fungus_infection", "bio_infection"]),
  damage_cause: new Set(["drainage", "construction_flaw", "drystand", "overcharge", "overcharge_negative_cling", "negative_cling", "bio_infection", "fungus_infection", "bio_fungus_infection", "foundation_flaw", "construction_heave", "subsidence", "vegetation", "gas", "vibrations", "partial_foundation_recovery", "japanese_knotweed", "groundwater_level_reduction"]),
  damage_characteristics: new Set(["jamming_door_window", "crack", "skewed", "crawlspace_flooding", "threshold_above_subsurface", "threshold_below_subsurface", "crooked_floor_wall"]),
};
const CRACKS = new Set(["none", "nil", "small", "mediocre", "big"]);
const NUMERIC = new Set([
  "built_year", "groundwater_level", "wood_level", "pile_head_level", "pile_tip_level", "concrete_charger_length",
  "pile_diameter_top", "pile_diameter_bottom", "pile_distance_length", "wood_penetration_depth", "foundation_depth",
  "groundlevel", "skewed_parallel", "skewed_perpendicular", "threshold_front_level", "threshold_back_level", "settlement_speed",
]);

function lastNumber(raw: string): string | null {
  const t = raw.trim().replace(/,(\d)/g, ".$1");
  if (/^-?\d+(\.\d+)?$/.test(t)) return t;
  const ns = t.match(/-?\d+(?:\.\d+)?/g);
  return ns?.length ? ns[ns.length - 1]! : null;
}
function skewMid(value: string, citation: string | undefined): string {
  const ns = [...(citation ?? "").matchAll(/1\s*:\s*(\d+(?:[.,]\d+)?)/g)].map((m) => parseFloat(m[1]!.replace(",", ".")));
  if (ns.length >= 2) return String((ns[0]! + ns[1]!) / 2);
  if (ns.length === 1) return String(ns[0]);
  return value;
}
function normalise(field: string, raw: unknown, citation: string | undefined): string[] {
  if (raw === null || raw === undefined || raw === "" || raw === "onbekend") return [];
  if (Array.isArray(raw)) {
    // Candidate lists are only meant for the damage fields; the model also
    // hands back lists for scalar fields (one entry per address). Take the
    // distinct values, and for a scalar field only the first.
    const allowed = ENUMS[field];
    const vals = raw.flatMap((x) => normalise(field, x, citation)).filter((x, i, a) => a.indexOf(x) === i);
    if (field === "damage_cause" || field === "damage_characteristics") return vals.filter((x) => !allowed || allowed.has(x)).slice(0, 3);
    return vals.slice(0, 1);
  }
  let v = String(raw).trim();
  if (field === "foundation_quality") { const c = QUALITY.has(v.toLowerCase()) ? v.toLowerCase() : QUALITY_NL[v.toLowerCase().replace(/\s+/g, "_")]; return c ? [c] : []; }
  if (field === "recovery_advised") { const b = v.toLowerCase(); return b === "true" || b === "false" ? [b] : []; }
  if (field === "enforcement_term") { const c = enforcementTermCode(v); return c ? [c] : []; }
  if (field.startsWith("crack_")) return CRACKS.has(v.toLowerCase()) ? [v.toLowerCase()] : [];
  if (ENUMS[field]) return ENUMS[field]!.has(v.toLowerCase()) ? [v.toLowerCase()] : [];
  if (NUMERIC.has(field)) { const n = lastNumber(v); if (!n) return []; v = n; }
  if (field === "skewed_parallel" || field === "skewed_perpendicular") v = skewMid(v, citation);
  return [v];
}

/** The two production prompts, merged: document-level fields plus the per-address block. */
function combinedPrompt(): string {
  const addrKeys = ADDRESS_PROMPT.slice(ADDRESS_PROMPT.indexOf("Sleutels per adres"), ADDRESS_PROMPT.indexOf("Funderingstype-codes"));
  const docPart = EXTRACT_PROMPT.replace("Hieronder staat de tekst van een Nederlands funderingsonderzoek,\nopgesteld door een ingenieursbureau.", "Bijgevoegd is een Nederlands funderingsonderzoek (PDF, tekst en/of scans, met tabellen,\ntekeningen en foto's), opgesteld door een ingenieursbureau. Lees het hele document.")
    .replace(/Antwoord met alleen JSON, met exact deze sleutels:[\s\S]*$/, "");
  return `${docPart}
Geef DAARNAAST per adres dat het rapport onderzoekt een object in "addresses" met de
gegevens die het rapport voor DAT adres vastlegt (inmeettabellen, schade-opname).
${addrKeys}
Antwoord met alleen JSON, met exact deze sleutels:
{${[...EXTRACT_FIELDS].map((f) => `"${f}": null`).join(", ")},
 "evidence": {"foundation_type": "", "built_year": ""}, "confidence": 0.0,
 "addresses": [{"address": "...", ${ADDRESS_FIELDS.slice(0, 3).map((f) => `"${f}": null`).join(", ")}, "evidence": {}}]}`;
}

export async function extractSingleLane(pdfPath: string): Promise<FieldRead[]> {
  const bytes = await readFile(pdfPath);
  if (bytes.byteLength > MAX_PDF_BYTES) throw new Error(`pdf too large for one call: ${(bytes.byteLength / 1e6).toFixed(1)} MB`);
  const body = {
    model: env.DATAOPS_TEXT_MODEL,
    temperature: 0,
    max_tokens: 24000,
    messages: [{
      role: "user",
      content: [
        { type: "text", text: combinedPrompt() },
        { type: "file", file: { filename: basename(pdfPath), file_data: `data:application/pdf;base64,${bytes.toString("base64")}` } },
      ],
    }],
  };
  let text = "";
  for (let attempt = 1; attempt <= 4; attempt++) {
    const r = await fetch(OPENROUTER, { method: "POST", headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (r.ok) { const j = (await r.json()) as any; if (!j?.error) { text = j.choices?.[0]?.message?.content ?? ""; break; } text = ""; }
    if (attempt === 4) throw new Error(`model call failed: HTTP ${r.status}`);
    await new Promise((res) => setTimeout(res, 3000 * attempt));
  }
  const start = text.indexOf("{"), end = text.lastIndexOf("}");
  if (start < 0 || end < 0) return [];
  let a: Record<string, unknown>;
  try { a = JSON.parse(text.slice(start, end + 1)); } catch { return []; }
  const conf = typeof a["confidence"] === "number" ? Math.max(0, Math.min(1, a["confidence"] as number)) : null;
  const ev = (a["evidence"] ?? {}) as Record<string, string>;
  const out: FieldRead[] = [];
  for (const f of EXTRACT_FIELDS) for (const v of normalise(f, a[f], ev[f])) out.push({ field: f, value: v, evidence: ev[f] ?? null, confidence: conf });
  const addresses = Array.isArray(a["addresses"]) ? (a["addresses"] as Record<string, unknown>[]) : [];
  for (const row of addresses.slice(0, 60)) {
    const address = String(row?.["address"] ?? "").trim();
    if (!address) continue;
    const rev = (row["evidence"] ?? {}) as Record<string, string>;
    for (const f of ADDRESS_FIELDS) for (const v of normalise(f, row[f], rev[f])) out.push({ field: f, value: v, evidence: rev[f] ?? null, confidence: conf, address });
  }
  return out;
}
