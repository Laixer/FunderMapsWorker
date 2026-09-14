/**
 * Turning "Adamshofstraat 93A" into a geocoder.address row, with what the
 * dossier already knows (ClientApp #333 part D, points 12-14).
 *
 * The database side (the candidate query, the dossier context) stays in
 * ingest-dossier.ts; this module is the pure part so the ranking can be
 * tested without a database. The rule, in order:
 *
 *   1. one candidate -- take it;
 *   2. a candidate the dossier already links (a nalezing's own sample
 *      addresses, point 12; the addresses of the pand the melding was filed
 *      under, point 13) -- take it;
 *   3. one candidate in the dossier's city -- take it (the old tie-break);
 *   4. one candidate in the dossier's postcode area (4 digits) -- take it;
 *   5. else nothing. A wrong address on a sample is worse than none, and the
 *      reviewer sees the raw text and can link it by hand (part C).
 */

export interface ParsedAddress {
  street: string;
  /** Digits only. */
  number: string;
  /** Upper-cased letter suffix, "" when none. */
  suffix: string;
}

export interface Candidate {
  id: string;
  buildingId: string | null;
  city: string | null;
  postalCode: string | null;
}

/** What the dossier already knows about where it is. */
export interface DossierContext {
  /** `NL.IMBAG.PAND.*` the dossier was filed under; null on most bulk drops. */
  buildingId: string | null;
  /** City and postcode of that pand's first address. */
  city: string | null;
  postalCode: string | null;
  /**
   * Addresses the dossier is already linked to: the pand's own addresses and,
   * on a nalezing, the rapportage's sample addresses. A candidate in this set
   * wins any tie.
   */
  knownAddressIds: Set<string>;
  /**
   * On a nalezing of a rapportage with exactly one sample: that address.
   * Text the resolver cannot place lands there, so an old drawing keeps the
   * link it already had (point 12) instead of turning up as unresolved.
   */
  fallbackAddressId: string | null;
}

export const EMPTY_CONTEXT: DossierContext = {
  buildingId: null,
  city: null,
  postalCode: null,
  knownAddressIds: new Set(),
  fallbackAddressId: null,
};

/** "Adamshofstraat 93A" / "Molenwal 15 te Oudewater" -> street + number, or null. */
export function parseAddress(text: string): ParsedAddress | null {
  const m = text.trim().match(/^(.+?)\s+(\d+)\s*([a-zA-Z]?)\b/);
  if (!m) return null;
  return { street: m[1]!.trim(), number: m[2]!, suffix: (m[3] ?? "").toUpperCase() };
}

/** The first four digits of a Dutch postcode, or null. */
export function postalArea(postalCode: string | null | undefined): string | null {
  const m = (postalCode ?? "").trim().match(/^(\d{4})/);
  return m ? m[1]! : null;
}

/**
 * Pick one of the candidates the street+number query returned, or null.
 * `candidates` is what the database found for the text; the context breaks
 * the tie the way a person at the desk would.
 */
export function pickCandidate(candidates: Candidate[], ctx: DossierContext): string | null {
  if (candidates.length === 0) return null;
  if (candidates.length === 1) return candidates[0]!.id;

  const known = candidates.filter((c) => ctx.knownAddressIds.has(c.id));
  if (known.length === 1) return known[0]!.id;
  if (known.length > 1) return null;

  const onPand = ctx.buildingId ? candidates.filter((c) => c.buildingId === ctx.buildingId) : [];
  if (onPand.length === 1) return onPand[0]!.id;

  if (ctx.city) {
    const inCity = candidates.filter((c) => c.city && c.city.toLowerCase() === ctx.city!.toLowerCase());
    if (inCity.length === 1) return inCity[0]!.id;
    if (inCity.length > 1) {
      const area = postalArea(ctx.postalCode);
      const inArea = area ? inCity.filter((c) => postalArea(c.postalCode) === area) : [];
      if (inArea.length === 1) return inArea[0]!.id;
    }
  }
  return null;
}

/**
 * The addresses a document names that are not on the pand the dossier was
 * filed under (point 14): what a person should be told about, and what goes
 * into dataops.dossier_address as pipeline rows for the review screen.
 * Returns one entry per resolved address, the first text it was written as.
 */
export function extraAddresses(
  resolved: Map<string, string | null>,
  byId: Map<string, Candidate>,
  ctx: DossierContext,
): { addressId: string; addressText: string }[] {
  const seen = new Set<string>();
  const out: { addressId: string; addressText: string }[] = [];
  for (const [text, id] of resolved) {
    if (!id || seen.has(id)) continue;
    const c = byId.get(id);
    if (ctx.buildingId && c?.buildingId === ctx.buildingId) continue;
    seen.add(id);
    out.push({ addressId: id, addressText: text });
  }
  return out;
}
