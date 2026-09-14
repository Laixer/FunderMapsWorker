/**
 * Where in the document a citation sits.
 *
 * The model answers a fixed JSON schema, so the order it returns values in is
 * our schema's order, not the report's. The review screen wants the report's
 * order ("in dezelfde volgorde als waarin ze in de tekst voorkomen" -- Don,
 * ClientApp #333 point 2). The one locator every proposal already carries is
 * its citation, and for the text and document lanes we hold the pdftotext
 * output the citation was lifted from. So: find the quote in the text, keep
 * the character offset and the page, sort on those.
 *
 * Citations come in a few shapes (measured on six real extractions,
 * 2026-09-10): the bare passage; "pagina 6, paragraaf 1.1: 'passage'"; and
 * "15-25 jaar -- Tabel 19: passage". Matching is forgiving on whitespace and
 * case, because `-layout` output pads columns with runs of spaces and the
 * model normalises them away, tries the quoted or trailing segment when the
 * whole does not match, and falls back to a prefix when the model trimmed or
 * paraphrased the tail. When the passage cannot be found but the citation
 * names a page, the page is kept and the offset is that page's start. It
 * never guesses beyond that: no match is null, and null sorts last.
 */

export interface EvidenceLocation {
  /** 1-based page, from `pdf.documentText`'s `--- pagina N ---` markers or the citation's own "pagina N"; null when unknown. */
  page: number | null;
  /** Character offset into the original text. Order key. */
  offset: number;
}

const PAGE_MARK = /\n--- pagina (\d+) ---\n/g;

/** Shortest prefix of a quote we are willing to call a match. */
const MIN_PREFIX = 12;
const PREFIXES = [80, 48, 24, MIN_PREFIX];

/**
 * Lower-case and collapse whitespace, keeping a map from folded index back to
 * the original index so the offset we store points into the real text.
 */
function fold(text: string): { folded: string; back: number[] } {
  let folded = "";
  const back: number[] = [];
  let pendingSpace = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!;
    if (/\s/.test(ch)) {
      pendingSpace = folded.length > 0;
      continue;
    }
    if (pendingSpace) {
      folded += " ";
      back.push(i);
      pendingSpace = false;
    }
    folded += ch.toLowerCase();
    back.push(i);
  }
  return { folded, back };
}

const trimQuotes = (s: string) => s.replace(/^[\s"'“”‘’«»]+|[\s"'“”‘’«»]+$/g, "");

/**
 * The passages worth looking for, most specific first: the whole citation
 * (minus the pipeline's own "afgeleid:" prefix), any quoted segment inside
 * it, what follows a " -- " or the last ": " (the model's locator prefix),
 * each at least `MIN_PREFIX` characters.
 */
export function candidatePassages(evidence: string): string[] {
  const whole = trimQuotes(evidence.replace(/^\s*afgeleid\s*:/i, ""));
  const out = [whole];
  for (const m of whole.matchAll(/["“«']([^"”»']{12,})["”»']/g)) out.push(trimQuotes(m[1]!));
  const dash = whole.split(/\s+--\s+/);
  if (dash.length > 1) out.push(trimQuotes(dash.slice(1).join(" -- ")));
  const colon = whole.lastIndexOf(": ");
  if (colon > 0) out.push(trimQuotes(whole.slice(colon + 2)));
  return [...new Set(out.filter((s) => s.length >= MIN_PREFIX))];
}

export function pageAt(text: string, offset: number): number | null {
  let page: number | null = null;
  PAGE_MARK.lastIndex = 0;
  for (let m = PAGE_MARK.exec(text); m && m.index < offset; m = PAGE_MARK.exec(text)) {
    page = Number(m[1]);
  }
  return page;
}

/** Offset of the marker that opens `page`, or null when the text has no such marker. */
function pageStart(text: string, page: number): number | null {
  PAGE_MARK.lastIndex = 0;
  for (let m = PAGE_MARK.exec(text); m; m = PAGE_MARK.exec(text)) {
    if (Number(m[1]) === page) return m.index;
  }
  return null;
}

/**
 * Find `evidence` in `text`: each candidate passage exactly (folded), then
 * the longest prefix that still matches. A candidate shorter than
 * `MIN_PREFIX` folded characters is too generic to trust ("1910" appears on
 * every page). Failing all that, a "pagina N" the citation names pins the
 * page and sorts the value at that page's start.
 */
export function locateEvidence(evidence: string | null | undefined, text: string): EvidenceLocation | null {
  if (!evidence || !text) return null;
  const { folded, back } = fold(text);

  for (const passage of candidatePassages(evidence)) {
    const quote = fold(passage).folded;
    if (quote.length < MIN_PREFIX) continue;
    const tries = [quote, ...PREFIXES.filter((n) => n < quote.length).map((n) => quote.slice(0, n).trimEnd())];
    for (const c of tries) {
      if (c.length < MIN_PREFIX) continue;
      const at = folded.indexOf(c);
      if (at < 0) continue;
      const offset = back[at]!;
      return { page: pageAt(text, offset), offset };
    }
  }

  const named = /\bpagina\s+(\d{1,4})\b/i.exec(evidence);
  if (named) {
    const page = Number(named[1]);
    const offset = pageStart(text, page);
    if (offset != null) return { page, offset };
  }
  return null;
}
