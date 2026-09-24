/**
 * Registration numbers of a QuickScan, for recognising a duplicate (#219).
 *
 * A QuickScan submitted via melden.fundermaps.com is often one FunderConsult
 * already delivered. Don (2026-09-24): a duplicate is recognised by its
 * registration number, and there are two numbering systems:
 *
 *   nafo           the NAFO / VastgoedNED registration on a Funderingsattest,
 *                  printed as "Registratienummer 105901"; the attest's file
 *                  name usually starts with it ("105895-Funderingsattest...").
 *                  Stored on our inquiry as "NAFO 105901" in the note.
 *   funderconsult  the REG number on a FunderConsult QuickScan certificate,
 *                  "REG-0002392". Stored as document_name "QS-FS-REG-0002392"
 *                  and "FunderScan REG-0002392" in the note.
 *
 * The attest also prints a "NAFO-ID" like 466353453-25-016. That is the
 * inspector's id, not the report's -- melders type it in as the registration
 * number. It never counts.
 *
 * Numbers compare without leading zeros, so REG-0002392 equals REG-2392.
 */

export type RegistrationSystem = "nafo" | "funderconsult";

export interface Registration {
  system: RegistrationSystem;
  number: string;
  /** Where it was read: the text around it, or the file name. */
  evidence: string;
}

const key = (r: { system: RegistrationSystem; number: string }) =>
  `${r.system}:${r.number.replace(/^0+/, "")}`;

/** The inspector's NAFO-ID (9 digits, 2, 3). Never a report's registration. */
const INSPECTOR_ID = /\b\d{9}-\d{2}-\d{3}\b/g;

/**
 * Every registration number a submitted document shows. `text` is the
 * pdftotext output (layout mode puts a label's value on the next line, under
 * it); `filename` is the name the melder uploaded.
 */
export function readRegistrations(text: string, filename: string | null): Registration[] {
  const found = new Map<string, Registration>();
  const add = (r: Registration) => { if (!found.has(key(r))) found.set(key(r), r); };
  const clean = text.replace(INSPECTOR_ID, " ");

  for (const m of clean.matchAll(/\bREG[-\s]?(\d{4,8})\b/gi)) {
    add({ system: "funderconsult", number: m[1]!, evidence: m[0] });
  }

  // "Registratienummer" and, within the next two lines, the first 5-7 digit
  // number on its own. In the attest the value sits under the label.
  for (const m of clean.matchAll(/Registratienummer/gi)) {
    const after = clean.slice(m.index! + m[0].length).split("\n").slice(0, 3).join("\n");
    const n = after.match(/(?<![\d-])(\d{5,7})(?![\d-])/);
    if (n) add({ system: "nafo", number: n[1]!, evidence: `Registratienummer ${n[1]}` });
  }

  const f = filename?.match(/^(\d{5,7})[-_ ]/);
  if (f && /attest/i.test(filename ?? "")) add({ system: "nafo", number: f[1]!, evidence: `bestandsnaam ${filename}` });

  return [...found.values()];
}

/** The registration numbers an existing inquiry carries in its document name and note. */
export function inquiryRegistrations(documentName: string | null, note: string | null): Registration[] {
  const text = `${documentName ?? ""}\n${note ?? ""}`;
  const found = new Map<string, Registration>();
  for (const m of text.matchAll(/\bNAFO\s+(\d{5,7})\b/g)) {
    const r: Registration = { system: "nafo", number: m[1]!, evidence: m[0] };
    found.set(key(r), r);
  }
  for (const m of text.matchAll(/\bREG-(\d{4,8})\b/g)) {
    const r: Registration = { system: "funderconsult", number: m[1]!, evidence: m[0] };
    found.set(key(r), r);
  }
  return [...found.values()];
}

/** The first registration both sides share, or null. */
export function sharedRegistration(submitted: Registration[], existing: Registration[]): Registration | null {
  const have = new Set(existing.map(key));
  return submitted.find((r) => have.has(key(r))) ?? null;
}
