import { basename } from "node:path";

/**
 * Is this document allowed to establish a foundation type?
 *
 * Some documents state a funderingstype that they did not determine. A QuickScan
 * (Fase 0) and an NWWI funderingsrisicorapport both display FunderMaps data --
 * so reading one and writing the answer back into FunderMaps is not extraction,
 * it is a loop. The value looks well-evidenced, the citation is accurate, and
 * the number it produces is our own.
 *
 * This is not hypothetical. Don reviewed 83 auto-accepted foundation types on
 * 2026-08-21 and rejected 26. Every single rejection was this: 22 QuickScans and
 * 4 NWWI risk reports. Not one was a misreading -- the model quoted all 26
 * correctly, and the documents were quoting us. Excluding them, he found no
 * reading errors at all.
 *
 * The same contamination is already in the historical data: ~126,000 quickscan
 * samples carry a foundation type that is probably our own output, which is why
 * data.model_evaluation_sample v2 excludes them (sql/migrate/…_v2.sql).
 * This stops the pipeline adding to the pile.
 *
 * Detection leans on the fact that these documents declare their own provenance
 * near the top -- Don's words: "zie in kop: Wijze van vaststelling - Bewijs
 * (archief of Fundermaps)".
 *
 * Measured on those 83 documents: 26/26 caught, 2 false positives. The error
 * costs are not symmetric. A false positive sends a document to a human who
 * would have seen it anyway; a false negative writes a circular value into
 * production. Tuned accordingly.
 */

/** Phrases that only appear when a document is repeating someone else's finding. */
const DECLARED_PROVENANCE: RegExp[] = [
  /wijze\s+van\s+vaststelling/i,      // the QuickScan header field itself
  /vermoeden\s+inspecteur/i,          // "established by: inspector's assumption"
  /funderingsrisico\s?rapport/i,      // the NWWI attachment title
  /risico\s+op\s+droogstandsproblematiek/i, // our own risk model's wording
  /\bfunder\s?maps\b/i,               // named as the source
  /funderingsattest/i,                // the attest re-states BAG year + our risk class
];

/** Only trusted in a filename, where it names the document rather than mentions it. */
const NAMES_ITSELF = /quick\s?scan|fase[\s._-]?0|funderingsrisico|funderingsattest/i;

/**
 * Look only at the opening of the document. These reports declare their source
 * in the header; a genuine funderingsonderzoek may well *discuss* QuickScans
 * further down, and one in this sample does exactly that.
 */
const HEADER_CHARS = 1500;

export interface Admissibility {
  ok: boolean;
  /** why it was refused, in Dutch, for a reviewer to read */
  reason?: string;
}

/**
 * Attachment categories as the public intake form records them
 * (files[*].category). When the submitter has labelled the document, that beats
 * any inference we can make from its text -- and it is the only signal that
 * works on a scan, where there is no text to match against.
 */
const CATEGORY_MAY_ESTABLISH: Record<string, boolean> = {
  quickscan: false,          // QuickScan / Fase 0 -- states our own data
  foundationresearch: true,  // Fase 1 / Fase 2 -- real fieldwork
  archieveresearch: true,    // bouwtekening / archiefstuk
  herstelbewijs: true,       // factuur, oplevering
  foto: true,                // nothing to establish, but not disqualified
  overig: true,
};

export function mayEstablishFoundationType(
  documentText: string,
  filePath: string,
  declaredCategory?: string
): Admissibility {
  // The submitter's own label is the strongest signal we get, and the only one
  // available for a scanned document.
  if (declaredCategory && CATEGORY_MAY_ESTABLISH[declaredCategory] === false) {
    return {
      ok: false,
      reason:
        `bron niet toelaatbaar: de indiener heeft dit bestand ` +
        `gelabeld als "${declaredCategory}". Het funderingstype in een QuickScan ` +
        `is FunderMaps-data die naar ons terugkomt.`,
    };
  }

  const head = documentText.slice(0, HEADER_CHARS).replace(/\s+/g, " ");

  for (const rx of DECLARED_PROVENANCE) {
    const m = head.match(rx);
    if (m) {
      return {
        ok: false,
        reason:
          `bron niet toelaatbaar: het document noemt zijn eigen ` +
          `herkomst ("${m[0]}") in de kop. QuickScans (Fase 0) en NWWI-risicorapporten ` +
          `tonen FunderMaps-data; het funderingstype daarin is onze eigen uitkomst.`,
      };
    }
  }

  const name = basename(filePath);
  if (NAMES_ITSELF.test(name)) {
    return {
      ok: false,
      reason:
        `bron niet toelaatbaar: de bestandsnaam ("${name}") ` +
        `duidt op een QuickScan of funderingsrisicorapport. Het funderingstype ` +
        `daarin is FunderMaps-data die naar ons terugkomt.`,
    };
  }

  return { ok: true };
}

/**
 * Every field the text lane extracts. This used to be the foundation type
 * alone, on the theory that a QuickScan's own measurements were genuine work
 * by someone on site. Don's verdicts on 2026-08-28/29 said otherwise: of 20
 * rejections, 16 were values quoted back from our own output, and they were
 * the bouwjaar (BAG, via us), the grondwaterstand (our model's) and the
 * herstel advice as often as the type. A document that declares FunderMaps as
 * its source establishes nothing; it goes to the reviewer with every value
 * marked, and the reviewer can still take one over by hand.
 */
export const FIELDS_REQUIRING_ADMISSIBLE_SOURCE = new Set([
  "funderingstype", "bouwjaar", "funderingskwaliteit",
  "herstel_geadviseerd", "handhavingstermijn", "grondwaterstand",
]);
