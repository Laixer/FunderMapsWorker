import { env } from "../config.ts";

/**
 * The model calls the Data Ops lanes make, and nothing else.
 *
 * Three operations, deliberately separate, because they answer different
 * questions at different prices:
 *
 *   classifyPage   what IS this page          ~$0.0009/page, runs on everything
 *   readDrawing    infer a foundation type    vision lane, scans
 *   extractFields  lift stated values         text lane, bureau reports
 *
 * Classification first is most of the accuracy in this pipeline. A quarter of
 * what arrives as "archive evidence" is a photograph of the house, where the
 * benchmark scored 2% against 73-89% on real archive material. Spending a tenth
 * of a cent to route those to a human beats any prompt.
 */

const OPENROUTER = "https://openrouter.ai/api/v1/chat/completions";

/** Out of credits, bad key, unknown model: none improve by waiting. */
const FATAL = new Set([401, 402, 403, 404]);

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const backoff = (a: number) =>
  Math.min(2000 * 2 ** (a - 1), 45_000) * (0.7 + Math.random() * 0.6);

async function ask(body: unknown, attempts = 6): Promise<any> {
  let last = "";
  for (let a = 1; a <= attempts; a++) {
    try {
      const r = await fetch(OPENROUTER, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      if (r.ok) {
        const j = await r.json();
        if (!(j as any)?.error) return j;
        last = `provider: ${JSON.stringify((j as any).error).slice(0, 160)}`;
      } else {
        last = `HTTP ${r.status}: ${(await r.text()).slice(0, 160)}`;
        if (FATAL.has(r.status)) throw new Error(last);
        const ra = Number(r.headers.get("retry-after"));
        if (ra > 0 && a < attempts) { await sleep(Math.min(ra * 1000, 60_000)); continue; }
      }
    } catch (e) {
      last = String(e).slice(0, 200);
      if ([...FATAL].some((c) => last.includes(`HTTP ${c}`))) throw e;
    }
    if (a < attempts) await sleep(backoff(a));
  }
  throw new Error(`model call failed after ${attempts} attempts — ${last}`);
}

/**
 * Parse the JSON object out of a reply, salvaging one that was cut off.
 *
 * Reasoning tokens eat the completion budget before the JSON closes, and a
 * truncated reply still carries every field emitted before the cut. Throwing
 * those away cost 17% of a benchmark run once; it is not worth repeating.
 */
function parseJson(text: string, keys: string[]): Record<string, unknown> | null {
  const m = text.match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* fall through */ } }
  const out: Record<string, unknown> = {};
  for (const k of keys) {
    const s = text.match(new RegExp(`"${k}"\\s*:\\s*"([^"]*)"`));
    const n = text.match(new RegExp(`"${k}"\\s*:\\s*(-?[\\d.]+|true|false)`));
    if (s) out[k] = s[1];
    else if (n) out[k] = n[1] === "true" ? true : n[1] === "false" ? false : Number(n[1]);
  }
  return Object.keys(out).length ? out : null;
}


/**
 * Confidence, coerced to 0..1.
 *
 * The prompts ask for a number between 0 and 1 and usually get one, but a model
 * will now and then answer 95 where it meant 0.95. Both confidence columns are
 * numeric(4,3), so that raises "numeric field overflow" and loses the whole
 * document -- six of 500 in the first full pilot, and silently, because the
 * failure lands in a log rather than in the table.
 */
function norm01(v: unknown): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  const x = v > 1 && v <= 100 ? v / 100 : v;
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

const asImage = (b64: string) => ({
  type: "image_url",
  image_url: { url: `data:image/jpeg;base64,${b64}` },
});

// ---------------------------------------------------------------------------
// 1 — what is this page
// ---------------------------------------------------------------------------

export type Material =
  | "drawing" | "archive_document" | "report" | "photo" | "map" | "blank" | "other";

export interface PageVerdict {
  material: Material | null;
  confidence: number | null;
  /** true if a caption still gives the answer away; null if we could not tell */
  leaks: boolean | null;
}

const CLASSIFY_PROMPT = `Dit is een pagina uit een Nederlands bouwdossier. De pagina is
al bewerkt: getypte tekst die er later door een medewerker aan toegevoegd is, is wit
overgeschilderd. Lege witte vlakken zijn dus normaal.

1. Is er nog steeds moderne, getypte of gedrukte tekst zichtbaar die het FUNDERINGSTYPE
   of het BOUWJAAR benoemt? Tekst die deel uitmaakt van de originele oude tekening of
   het archiefstuk telt NIET mee -- alleen tekst die er later aan toegevoegd lijkt.

2. Wat voor materiaal is dit? Kies een van: drawing (bouwkundige tekening, plattegrond,
   doorsnede, palenplan), archive_document (brief, vergunning, bestek, formulier),
   report (modern getypt rapport), photo (foto van een gebouw of situatie),
   map (kadastrale kaart, situatietekening, luchtfoto), blank (vrijwel niets te zien),
   other.

Antwoord met alleen JSON:
{"verklapt": true, "materiaal": "...", "zekerheid": 0.0}`;

export async function classifyPage(jpegBase64: string): Promise<PageVerdict> {
  const j = await ask({
    model: env.DATAOPS_CLASSIFY_MODEL,
    temperature: 0,
    max_tokens: 900,
    messages: [{ role: "user", content: [{ type: "text", text: CLASSIFY_PROMPT }, asImage(jpegBase64)] }],
  });
  const a = parseJson(j.choices?.[0]?.message?.content ?? "", ["verklapt", "materiaal", "zekerheid"]);
  return {
    material: (a?.["materiaal"] as Material) ?? null,
    confidence: norm01(a?.["zekerheid"]),
    // Fail closed. A verdict we could not read is not evidence of a clean page.
    leaks: typeof a?.["verklapt"] === "boolean" ? (a["verklapt"] as boolean) : null,
  };
}

// ---------------------------------------------------------------------------
// 2 — the vision lane: infer a foundation type from a drawing
// ---------------------------------------------------------------------------

/**
 * Yorick's ruling, 2026-08-21: answer with the most specific subtype the
 * document supports, and fall back to plain `wood` when it does not say which.
 */
export const FOUNDATION_VOCABULARY = `  wood                      Hout
  wood_amsterdam            Hout: Amsterdam fundering
  wood_rotterdam            Hout: Rotterdam fundering
  wood_rotterdam_amsterdam  Hout: gecombineerde Rotterdam/Amsterdam fundering
  wood_amsterdam_arch       Hout: Amsterdam fundering met bogen
  wood_rotterdam_arch       Hout: Rotterdam fundering met bogen
  wood_charger              Hout met oplanger
  concrete                  Beton
  steel_pile                Stalen buispalen
  weighted_pile             Verzwaardepuntpaal
  combined                  Gecombineerd
  no_pile                   Niet onderheid
  no_pile_masonry           Niet onderheid: gemetseld
  no_pile_strips            Niet onderheid: stroken fundering
  no_pile_bearing_floor     Niet onderheid: fundering met dragende vloer
  no_pile_concrete_floor    Niet onderheid: dragende betonvloer
  no_pile_slit              Niet onderheid: slieten
  other                     Overig

Regel voor de keuze -- let op, die verschilt per groep:

HOUTEN PALEN: Amsterdam en Rotterdam zijn BENAMINGEN van een constructiewijze.
- Gebruik wood_amsterdam, wood_rotterdam of een gecombineerde variant ALLEEN als
  het document die benaming zelf gebruikt. Leid ze nooit af uit een tekening.
- Staat er alleen dat de fundering op houten palen staat, kies dan wood. Dat is
  geen slechter antwoord -- het is het juiste antwoord.

NIET ONDERHEID: dit zijn BESCHRIJVINGEN van wat het gebouw draagt.
- Beschrijft het document de constructie -- gemetselde voet of poeren, betonnen
  stroken, slieten, een dragende betonvloer -- kies dan de bijbehorende code.
  De beschrijving is het bewijs; er hoeft geen benaming te staan.
- Kies no_pile alleen als vaststaat dat er geen palen zijn maar het document
  niet zegt waar het gebouw dan op rust.`;

const READ_PROMPT = `Je bekijkt pagina's uit een Nederlands bouwdossier of archiefstuk.
Het kan gaan om oude bouwtekeningen (soms van rond 1900), handgeschreven aantekeningen,
bestekken of vergunningen. De kwaliteit van de scan kan slecht zijn.

Bepaal het FUNDERINGSTYPE van het gebouw. Kies exact een van deze codes:

${FOUNDATION_VOCABULARY}

Is het funderingstype niet af te leiden, antwoord dan "onbekend".

Let op de herkomst van het funderingstype. Sommige documenten -- een QuickScan of
Fase 0-rapport, een funderingsrisicorapport, een taxatiebijlage -- vermelden een
funderingstype dat zij NIET zelf hebben vastgesteld, maar hebben overgenomen uit
een database (vaak FunderMaps) of uit een eerder rapport. Herken dat aan zinnen
als "wijze van vaststelling", "vermoeden inspecteur", "bron: archief of
FunderMaps", of aan een risicoklasse die zonder eigen onderzoek wordt getoond.

Is dat het geval, antwoord dan "onbekend" -- ook al staat het type er duidelijk.
Wij zouden dan onze eigen gegevens terugkrijgen. Alleen wat in dit document zelf
is waargenomen of vastgelegd telt.


Regels voor het bewijs:
- Citeer letterlijk uit het document. Het bewijs moet de waarde zelf bevatten of
  die onmiskenbaar benoemen.
- Komt de waarde uit een TABEL of een tekstblok met labels, neem dan de kolomkop
  of het label mee in het citaat, niet alleen de waarde.
- Staat de waarde er niet letterlijk maar leid je die af uit wat je ziet, begin
  het bewijs dan met "afgeleid: " en beschrijf waaruit. Afleiden mag -- op een
  oude tekening is dat vaak de enige manier -- het verzwijgen niet.

Antwoord met alleen JSON:
{"foundation_type": "...", "confidence": 0.0, "evidence": "wat je op de tekening ziet waaruit dit blijkt", "page": 1}`;

export interface DrawingRead {
  foundationType: string | null;
  confidence: number | null;
  evidence: string | null;
  page: number | null;
}

export async function readDrawing(pages: string[]): Promise<DrawingRead> {
  const j = await ask({
    model: env.DATAOPS_VISION_MODEL,
    temperature: 0,
    max_tokens: 1500,
    messages: [{ role: "user", content: [{ type: "text", text: READ_PROMPT }, ...pages.map(asImage)] }],
  });
  const a = parseJson(j.choices?.[0]?.message?.content ?? "", [
    "foundation_type", "confidence", "evidence", "page",
  ]);
  const ft = (a?.["foundation_type"] as string) ?? null;
  return {
    foundationType: ft && ft !== "onbekend" ? ft : null,
    confidence: norm01(a?.["confidence"]),
    evidence: (a?.["evidence"] as string) ?? null,
    page: typeof a?.["page"] === "number" ? (a["page"] as number) : null,
  };
}

// ---------------------------------------------------------------------------
// 3 — the text lane: lift what the bureau already wrote down
// ---------------------------------------------------------------------------

const EXTRACT_PROMPT = `Hieronder staat de tekst van een Nederlands funderingsonderzoek,
opgesteld door een ingenieursbureau. Haal de volgende gegevens eruit. Staat een veld er
niet in, geef dan null. Verzin niets.


Let op de herkomst van het funderingstype. Sommige documenten -- een QuickScan of
Fase 0-rapport, een funderingsrisicorapport, een taxatiebijlage -- vermelden een
funderingstype dat zij NIET zelf hebben vastgesteld, maar hebben overgenomen uit
een database (vaak FunderMaps) of uit een eerder rapport. Herken dat aan zinnen
als "wijze van vaststelling", "vermoeden inspecteur", "bron: archief of
FunderMaps", of aan een risicoklasse die zonder eigen onderzoek wordt getoond.

Is dat het geval, antwoord dan "onbekend" -- ook al staat het type er duidelijk.
Wij zouden dan onze eigen gegevens terugkrijgen. Alleen wat in dit document zelf
is waargenomen of vastgelegd telt.

  foundation_type          een van (gebruik exact deze codes):
${FOUNDATION_VOCABULARY}
  built_year               bouwjaar van het pand, als jaartal. ALLEEN als het rapport
                           dat zelf vaststelt; een bouwjaar dat uit de BAG of uit
                           FunderMaps is overgenomen telt niet -- geef dan null.
  foundation_quality       een van (gebruik exact deze codes):
                             bad            slecht
                             mediocre       matig
                             tolerable      redelijk
                             good           goed
                             mediocre_good  matig tot goed
                             mediocre_bad   matig tot slecht
  recovery_advised         true als het rapport funderingsherstel adviseert, false als
                           expliciet geen herstel nodig is
  recovery_note            het advies letterlijk, in een zin, als het genuanceerder is
                           dan ja/nee ("direct herstel niet nodig, maar monitoren")
  enforcement_term         resterende handhavingstermijn / levensduur in jaren, als
                           getal of bereik "15-25"
  groundwater_level        gemeten grondwaterstand in meters t.o.v. NAP, als getal
                           (bijv. -2.32)
  wood_level               bovenkant houten paalfundering / langshout in meters
                           t.o.v. NAP, als getal
  pile_head_level          bovenkant paal in meters t.o.v. NAP, als getal
  pile_tip_level           punt van de paal (paalpuntniveau) in meters t.o.v. NAP
  concrete_charger_length  lengte van de betonnen oplanger in meters, als getal
  pile_diameter_top        paaldiameter aan de kop in MILLIMETERS, als geheel getal
  pile_diameter_bottom     paaldiameter aan de punt in millimeters, als geheel getal
  pile_distance_length     hart-op-hart paalafstand in meters, als getal
  wood_type                houtsoort van de palen: pine (grenen) of spruce (vuren)
  wood_penetration_depth   indringingsdiepte / aantasting van het hout in millimeters
                           (bijv. uit een priktest), als getal
  wood_encroachment        aantasting van het hout, een van: fungus_infection
                           (schimmel), bio_infection (bacterieel), bio_fungus_infection
  mason_level              onderkant metselwerk in meters t.o.v. NAP, als getal
  foundation_depth         aanlegniveau / onderkant fundering in meters t.o.v. NAP
  groundlevel              maaiveldhoogte in meters t.o.v. NAP, als getal
  damage_cause             oorzaak van de schade, een van: drainage, construction_flaw,
                           drystand (droogstand), overcharge (overbelasting),
                           negative_cling (negatieve kleef), overcharge_negative_cling,
                           bio_infection, fungus_infection, bio_fungus_infection,
                           foundation_flaw, construction_heave, subsidence (zetting),
                           vegetation, gas, vibrations, partial_foundation_recovery,
                           japanese_knotweed, groundwater_level_reduction
  damage_characteristics   waargenomen schadebeeld, een van: jamming_door_window
                           (klemmende deuren/ramen), crack (scheuren), skewed
                           (scheefstand), crawlspace_flooding, threshold_above_subsurface,
                           threshold_below_subsurface, crooked_floor_wall

Geef bij elk veld dat je invult het citaat uit het rapport waar het vandaan komt.

Regels voor het bewijs:
- Citeer letterlijk uit het document. Het bewijs moet de waarde zelf bevatten of
  die onmiskenbaar benoemen.
- Komt de waarde uit een TABEL, neem dan de kolomkop of de rijlabel mee in het
  citaat, niet alleen de cel. "Gouvernestraat 273-277 | Slecht | 10" toont niet
  welke kolom de 10 is; zonder kop is het citaat waardeloos.
- Staat de waarde er niet letterlijk maar leid je die af, begin het bewijs dan
  met "afgeleid: " en beschrijf waaruit. Afleiden mag -- het verzwijgen niet.

Voorbeelden van goed bewijs, uit echte rapporten (waarde <- citaat):
- foundation_type = wood_rotterdam <- "De fundering van de panden in de bouweenheid
  Adamshofstraat 81 t/m 105 is opgebouwd uit een houten paalfundering met langshout,
  een Rotterdamse fundering"
- built_year = 1911 <- "Tabel 4.1: bouweenheid en bouwjaar | Adamshofstraat 81 t/m 105 | 1911"
- wood_level = -2.47 <- "Tabel 9.3: inmeetgegevens fundering | Adamshofstraat 93 |
  achtergevel 93/91 | 14-9-2022 | -1,25 | -2,43 | -2,47" (kolom bovenkant hout)
- groundwater_level = -2.94 <- "Tabel 15: ... | West Sidelinge 88 | Grondwater (m t.o.v. NAP): -2,94"
- enforcement_term = "1-5" <- "indicatieve funderingstechnische handhavingstermijn van 1 tot 5 jaar"
Een tabelcitaat draagt altijd de kop of het rijlabel mee; een getal zonder context is
geen bewijs.

Een rapport beschrijft vaak meerdere adressen. Geef dan de waarde voor het adres dat
het rapport als hoofdadres of eerste adres noemt, en zet het adres in het citaat.

De WAARDE van een veld is alleen het getal, de code, true/false of het jaartal --
nooit het citaat. Het citaat hoort uitsluitend onder "evidence", met dezelfde
sleutel. Dus: "built_year": 1910 en "evidence": {"built_year": "Tabel 3: bouwjaar |
Wilhelminakade 59 | 1910"}.

Antwoord met alleen JSON, met exact deze sleutels:
{"foundation_type": null, "built_year": null, "foundation_quality": null,
 "recovery_advised": null, "recovery_note": null, "enforcement_term": null,
 "groundwater_level": null, "wood_level": null, "pile_head_level": null,
 "pile_tip_level": null, "concrete_charger_length": null,
 "pile_diameter_top": null, "pile_diameter_bottom": null, "pile_distance_length": null,
 "wood_type": null, "wood_penetration_depth": null, "wood_encroachment": null,
 "mason_level": null, "foundation_depth": null, "groundlevel": null,
 "damage_cause": null, "damage_characteristics": null,
 "evidence": {"foundation_type": "", "built_year": ""}, "confidence": 0.0}`;

/**
 * Field keys are the `report.inquiry_sample` column names (English, like all
 * identifiers -- Yorick 2026-08-28), except `recovery_note`, which has no
 * column and exists because a boolean lost the nuance Don kept finding
 * ("direct herstel niet nodig, maar ...").
 */
export const EXTRACT_FIELDS = [
  "foundation_type", "built_year", "foundation_quality",
  "recovery_advised", "recovery_note", "enforcement_term", "groundwater_level",
  "wood_level", "pile_head_level", "pile_tip_level", "concrete_charger_length",
  // Phase A, Don 2026-08-29: "uit de funderingsonderzoeken kan meer worden gehaald".
  // Document-level only; per-address values (cracks, skew) are phase B.
  "pile_diameter_top", "pile_diameter_bottom", "pile_distance_length",
  "wood_type", "wood_penetration_depth", "wood_encroachment",
  "mason_level", "foundation_depth", "groundlevel",
  "damage_cause", "damage_characteristics",
] as const;

/** Enum-typed fields: a value outside the PG enum is dropped, never stored. */
const ENUM_VALUES: Record<string, Set<string>> = {
  wood_type: new Set(["pine", "spruce"]),
  wood_encroachment: new Set(["fungus_infection", "bio_fungus_infection", "bio_infection"]),
  damage_cause: new Set([
    "drainage", "construction_flaw", "drystand", "overcharge", "overcharge_negative_cling",
    "negative_cling", "bio_infection", "fungus_infection", "bio_fungus_infection",
    "foundation_flaw", "construction_heave", "subsidence", "vegetation", "gas", "vibrations",
    "partial_foundation_recovery", "japanese_knotweed", "groundwater_level_reduction",
  ]),
  damage_characteristics: new Set([
    "jamming_door_window", "crack", "skewed", "crawlspace_flooding",
    "threshold_above_subsurface", "threshold_below_subsurface", "crooked_floor_wall",
  ]),
};

/** Map a term in years (a number or a "15-25" range) onto report.enforcement_term. */
export function enforcementTermCode(raw: string): string | null {
  const m = String(raw).match(/-?\d+(?:[.,]\d+)?/);
  if (!m) return null;
  const years = parseFloat(m[0].replace(",", "."));
  if (!Number.isFinite(years) || years < 0) return null;
  // The lower bound of a range: an enforcement term is a promise about the
  // earliest date something must happen, so "15-25" is a 15.
  for (const [cap, code] of [[5, "term5"], [10, "term10"], [15, "term15"], [20, "term20"], [25, "term25"], [30, "term30"]] as const) {
    if (years <= cap) return code;
  }
  return "term40";
}

const NUMERIC_FIELDS = new Set([
  "built_year", "groundwater_level", "wood_level", "pile_head_level", "pile_tip_level",
  "concrete_charger_length", "pile_diameter_top", "pile_diameter_bottom",
  "pile_distance_length", "wood_penetration_depth", "mason_level", "foundation_depth",
  "groundlevel",
]);

/**
 * The value slot sometimes carries the citation ("Tabel 3: bouwjaar | ... | 1910")
 * despite the prompt. A numeric field keeps only its number -- the LAST one in
 * the string, because a table citation ends in its cell -- and the rest of the
 * text is moved to the evidence so nothing is lost. Measured on the 2026-08-29
 * benchmark: 18 of ~700 values arrived this way.
 */
function normaliseNumeric(raw: string, evidence: string | null): { value: string; evidence: string | null } | null {
  const trimmed = raw.trim().replace(/,(\d)/g, ".$1");
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return { value: trimmed, evidence };
  const nums = trimmed.match(/-?\d+(?:\.\d+)?/g);
  if (!nums || nums.length === 0) return null;
  return { value: nums[nums.length - 1]!, evidence: evidence?.trim() ? evidence : raw };
}

const QUALITY_CODES = new Set(["bad", "mediocre", "tolerable", "good", "mediocre_good", "mediocre_bad"]);
/** The model was told the codes; a Dutch word slipping through is mapped, not stored. */
const QUALITY_FROM_DUTCH: Record<string, string> = {
  slecht: "bad", matig: "mediocre", redelijk: "tolerable", goed: "good",
  matig_tot_goed: "mediocre_good", matig_tot_slecht: "mediocre_bad",
};

export interface FieldRead {
  field: string;
  value: string;
  evidence: string | null;
  confidence: number | null;
  /**
   * Set when the document is not allowed to establish this field -- a QuickScan
   * or NWWI risk report stating a foundation type it read off FunderMaps.
   * The value is kept so a reviewer can see what was claimed and why we refuse
   * it; it never clears the gate. See providers/admissibility.ts.
   */
  rejected?: string;
}

export async function extractFields(reportText: string): Promise<FieldRead[]> {
  const j = await ask({
    model: env.DATAOPS_TEXT_MODEL,
    temperature: 0,
    max_tokens: 4000,
    messages: [{ role: "user", content: `${EXTRACT_PROMPT}\n\n=== RAPPORT ===\n${reportText}` }],
  });
  const a = parseJson(j.choices?.[0]?.message?.content ?? "", [...EXTRACT_FIELDS]);
  if (!a) return [];
  const ev = (a["evidence"] ?? {}) as Record<string, string>;
  const conf = norm01(a["confidence"]);

  return EXTRACT_FIELDS.flatMap((f): FieldRead[] => {
    let v = a[f];
    if (v === null || v === undefined || v === "" || v === "onbekend") return [];
    if (f === "foundation_quality") {
      const code = QUALITY_CODES.has(String(v)) ? String(v) : QUALITY_FROM_DUTCH[String(v).toLowerCase().replace(/\s+/g, "_")];
      if (!code) return [];
      v = code;
    }
    if (ENUM_VALUES[f] && !ENUM_VALUES[f]!.has(String(v).toLowerCase())) return [];
    if (f === "recovery_advised") {
      const b = String(v).trim().toLowerCase();
      if (b !== "true" && b !== "false") return [];
      v = b;
    }
    if (NUMERIC_FIELDS.has(f)) {
      const n = normaliseNumeric(String(v), ev[f] ?? null);
      if (!n) return [];
      return [{ field: f, value: n.value, evidence: n.evidence, confidence: conf }];
    }
    if (f === "enforcement_term") {
      const code = enforcementTermCode(String(v));
      if (!code) return [];
      // Keep what the document said next to the code: "term15" alone hides
      // that the report wrote "15-25".
      return [{ field: f, value: code, evidence: `${String(v)} jaar -- ${ev[f] ?? ""}`.trim(), confidence: conf }];
    }
    return [{ field: f, value: String(v), evidence: ev[f] ?? null, confidence: conf }];
  });
}
