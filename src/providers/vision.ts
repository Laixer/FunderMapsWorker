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
    confidence: typeof a?.["zekerheid"] === "number" ? (a["zekerheid"] as number) : null,
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

Regels voor het bewijs:
- Citeer letterlijk uit het document. Het bewijs moet de waarde zelf bevatten of
  die onmiskenbaar benoemen.
- Komt de waarde uit een TABEL of een tekstblok met labels, neem dan de kolomkop
  of het label mee in het citaat, niet alleen de waarde.
- Staat de waarde er niet letterlijk maar leid je die af uit wat je ziet, begin
  het bewijs dan met "afgeleid: " en beschrijf waaruit. Afleiden mag -- op een
  oude tekening is dat vaak de enige manier -- het verzwijgen niet.

Antwoord met alleen JSON:
{"funderingstype": "...", "zekerheid": 0.0, "bewijs": "wat je op de tekening ziet waaruit dit blijkt", "pagina": 1}`;

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
    "funderingstype", "zekerheid", "bewijs", "pagina",
  ]);
  const ft = (a?.["funderingstype"] as string) ?? null;
  return {
    foundationType: ft && ft !== "onbekend" ? ft : null,
    confidence: typeof a?.["zekerheid"] === "number" ? (a["zekerheid"] as number) : null,
    evidence: (a?.["bewijs"] as string) ?? null,
    page: typeof a?.["pagina"] === "number" ? (a["pagina"] as number) : null,
  };
}

// ---------------------------------------------------------------------------
// 3 — the text lane: lift what the bureau already wrote down
// ---------------------------------------------------------------------------

const EXTRACT_PROMPT = `Hieronder staat de tekst van een Nederlands funderingsonderzoek,
opgesteld door een ingenieursbureau. Haal de volgende gegevens eruit. Staat een veld er
niet in, geef dan null. Verzin niets.

  funderingstype       een van (gebruik exact deze codes):
${FOUNDATION_VOCABULARY}
  bouwjaar             bouwjaar van het pand, als jaartal
  funderingskwaliteit  een van: slecht, matig, redelijk, goed, matig_tot_goed, matig_tot_slecht
  herstel_geadviseerd  true als het rapport funderingsherstel adviseert, false als
                       expliciet geen herstel nodig is
  handhavingstermijn   resterende levensduur in jaren, als getal of bereik "5-10"
  grondwaterstand      gemeten grondwaterstand in meters t.o.v. NAP, als getal

Geef bij elk veld dat je invult het citaat uit het rapport waar het vandaan komt.

Regels voor het bewijs:
- Citeer letterlijk uit het document. Het bewijs moet de waarde zelf bevatten of
  die onmiskenbaar benoemen.
- Komt de waarde uit een TABEL, neem dan de kolomkop of de rijlabel mee in het
  citaat, niet alleen de cel. "Gouvernestraat 273-277 | Slecht | 10" toont niet
  welke kolom de 10 is; zonder kop is het citaat waardeloos.
- Staat de waarde er niet letterlijk maar leid je die af, begin het bewijs dan
  met "afgeleid: " en beschrijf waaruit. Afleiden mag -- het verzwijgen niet.

Antwoord met alleen JSON:
{"funderingstype": null, "bouwjaar": null, "funderingskwaliteit": null,
 "herstel_geadviseerd": null, "handhavingstermijn": null, "grondwaterstand": null,
 "bewijs": {"funderingstype": "", "bouwjaar": ""}, "zekerheid": 0.0}`;

export const EXTRACT_FIELDS = [
  "funderingstype", "bouwjaar", "funderingskwaliteit",
  "herstel_geadviseerd", "handhavingstermijn", "grondwaterstand",
] as const;

export interface FieldRead {
  field: string;
  value: string;
  evidence: string | null;
  confidence: number | null;
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
  const ev = (a["bewijs"] ?? {}) as Record<string, string>;
  const conf = typeof a["zekerheid"] === "number" ? (a["zekerheid"] as number) : null;

  return EXTRACT_FIELDS.flatMap((f) => {
    const v = a[f];
    if (v === null || v === undefined || v === "" || v === "onbekend") return [];
    return [{ field: f, value: String(v), evidence: ev[f] ?? null, confidence: conf }];
  });
}
