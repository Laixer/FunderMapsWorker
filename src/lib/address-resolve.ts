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

// ---------------------------------------------------------------------------
// Ranges and lists of house numbers (#186).
//
// A report often covers a block: "Olympiaweg 20-92", "Driedijk 32 t/m 38",
// "Harddraverstraat 46 t/m 52A, 52C en 54C". Read as one address, such a text
// either resolved to nothing (387 values on 2026-09-20) or, worse, to one
// front door the document never names (dossier 2494: 9 values on 54B). The
// rules, taken from those cases:
//
//   * "a t/m b" is always a range; "a-b" only when b > a, both have the
//     same parity and b > 4 ("25-1", "37-2" and often "2-4" are a number
//     with a toevoeging, #195);
//   * a range whose ends share a parity steps by two (85-87 is 85 and 87,
//     never 86); mixed ends ("35 t/m 38") take every number;
//   * a number without a letter means the whole number: bare and every
//     lettered unit (Olympiaweg 20-92 is 22H ... 92H in the BAG);
//   * a lettered end bounds its own number: "46B t/m 50" starts at 46B,
//   * "t/m 52A" stops at 52A (52 and 52A, not 52C);
//   * a single lettered number is exactly that unit ("52C");
//   * a range may cross pand boundaries; nothing assumes one building.
// ---------------------------------------------------------------------------

export interface NumberSpan {
  from: number;
  /** Letter the span starts at on `from`, "" for the whole number. */
  fromSuffix: string;
  to: number;
  /** Letter the span stops at on `to`, "" for the whole number. */
  toSuffix: string;
  /** Every other number (same parity at both ends) or every number. */
  step: 1 | 2;
}

export interface AddressList {
  street: string;
  spans: NumberSpan[];
}

/** Numbers a range may span before we refuse to guess ("Dorpsstraat 1-999"). */
export const MAX_SPAN_NUMBERS = 150;

const NUM = String.raw`(\d+)([A-Za-z](?![A-Za-z]))?`;
const RANGE_WORD = String.raw`\s*(?:t\s*\/\s*m|tot\s+en\s+met|-)\s*`;
const SEPARATOR = String.raw`\s*(?:,|&|\+|\ben\b)\s*`;

/**
 * "Harddraverstraat 46 t/m 52A, 52C en 54C" -> street + spans, or null when
 * the text names one plain address (the single-address resolver's job) or
 * something we will not guess at.
 */
export function parseAddressList(text: string): AddressList | null {
  const head = text.trim().match(/^(.+?)\s+(?=\d)/);
  if (!head) return null;
  const street = head[1]!.trim();
  let rest = text.trim().slice(head[0].length);

  const spans: NumberSpan[] = [];
  let sawList = false;
  const item = new RegExp(String.raw`^${NUM}(?:(${RANGE_WORD})${NUM})?`, "i");
  for (;;) {
    const m = rest.match(item);
    if (!m) break;
    const from = Number(m[1]);
    const fromSuffix = (m[2] ?? "").toUpperCase();
    if (m[3] !== undefined) {
      const to = Number(m[4]);
      const toSuffix = (m[5] ?? "").toUpperCase();
      const dash = m[3].trim() === "-";
      if (to < from || (to === from && !toSuffix)) return null;
      if (dash && (to === from || (to - from) % 2 !== 0)) return null;
      // "2-4" in Amsterdam is number 2, fourth floor as often as 2 and 4.
      if (dash && to <= 4) return null;
      if (to - from + 1 > MAX_SPAN_NUMBERS) return null;
      spans.push({ from, fromSuffix, to, toSuffix, step: (to - from) % 2 === 0 ? 2 : 1 });
      sawList = true;
    } else {
      spans.push({ from, fromSuffix, to: from, toSuffix: fromSuffix, step: 1 });
    }
    rest = rest.slice(m[0].length);
    // "1234 AB Amsterdam" after the numbers is a postcode, not a unit.
    if (/^\s+\d{4}\s?[A-Za-z]{2}\b/.test(rest)) break;
    const sep = rest.match(new RegExp(String.raw`^${SEPARATOR}(?=\d)(?!\d{4}\s?[A-Za-z]{2}\b)`, "i"));
    if (!sep) break;
    rest = rest.slice(sep[0].length);
    sawList = true;
  }
  if (!spans.length || !sawList) return null;
  // A trailing hyphenated number the loop did not take ("25-1") means the
  // text is a toevoeging, not a list: leave it to the single resolver.
  if (/^\s*-\s*\d/.test(rest)) return null;
  return { street, spans };
}

/**
 * The spans a BAG building_number falls in: "93", "22H", or with the
 * toevoeging our geocoder writes after a hyphen ("259-H", "261-2", the
 * Amsterdam units). A toevoeging belongs to its number; only the house letter
 * is bounded by a lettered range end.
 */
export function inSpans(buildingNumber: string, spans: NumberSpan[]): boolean {
  const m = buildingNumber.trim().match(/^(\d+)([A-Za-z]?)(?:-[A-Za-z0-9]+)?$/);
  if (!m) return false;
  const n = Number(m[1]);
  const s = (m[2] ?? "").toUpperCase();
  return spans.some((sp) => {
    if (n < sp.from || n > sp.to) return false;
    if (sp.step === 2 && (n - sp.from) % 2 !== 0) return false;
    if (sp.from === sp.to) return sp.fromSuffix ? s === sp.fromSuffix : true;
    if (n === sp.from && sp.fromSuffix && s < sp.fromSuffix) return false;
    if (n === sp.to && sp.toSuffix && s > sp.toSuffix) return false;
    return true;
  });
}

export interface ListedAddress extends Candidate {
  buildingNumber: string;
  street: string;
}

/**
 * Of every address on the street, the ones the list names -- in one city.
 * The street may exist in several places; the dossier's city decides, then
 * its postcode area, else a street found in one city only. No city we can
 * stand behind means no expansion (an empty list), never a guess.
 */
export function selectListedAddresses(list: AddressList, rows: ListedAddress[], ctx: DossierContext): ListedAddress[] {
  const hits = rows.filter((r) => inSpans(r.buildingNumber, list.spans));
  const cities = new Map<string, ListedAddress[]>();
  for (const h of hits) {
    const k = (h.city ?? "").toLowerCase();
    cities.set(k, [...(cities.get(k) ?? []), h]);
  }
  if (cities.size === 0) return [];
  if (ctx.city && cities.has(ctx.city.toLowerCase())) return cities.get(ctx.city.toLowerCase())!;
  const area = postalArea(ctx.postalCode);
  if (area) {
    const inArea = [...cities.values()].filter((list) => list.some((h) => postalArea(h.postalCode) === area));
    if (inArea.length === 1) return inArea[0]!;
  }
  if (ctx.knownAddressIds.size) {
    const known = [...cities.values()].filter((list) => list.some((h) => ctx.knownAddressIds.has(h.id)));
    if (known.length === 1) return known[0]!;
  }
  return cities.size === 1 ? [...cities.values()][0]! : [];
}
