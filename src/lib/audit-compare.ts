/**
 * The nalezing's comparison: does what the model read off the document agree
 * with what the database already holds for that sample?
 *
 * Pure: rows in, verdicts out, so it can be tested without a database and
 * reasoned about without a model. The mapping from extraction_field.field to
 * inquiry_sample column mirrors FunderMapsApi's dataops-commit `applyField`;
 * the two must agree or a value would be judged against the wrong column.
 */

/** extraction_field.field -> report.inquiry_sample column. */
export const SAMPLE_COLUMN: Record<string, string> = {
  foundation_type: "foundation_type",
  built_year: "built_year",
  foundation_quality: "overall_quality",
  recovery_advised: "recovery_advised",
  enforcement_term: "enforcement_term",
  groundwater_level: "groundwater_level_temp",
  wood_level: "wood_level",
  pile_head_level: "pile_head_level",
  pile_tip_level: "pile_tip_level",
  concrete_charger_length: "concrete_charger_length",
  pile_diameter_top: "pile_diameter_top",
  pile_diameter_bottom: "pile_diameter_bottom",
  pile_distance_length: "pile_distance_length",
  wood_type: "wood_type",
  wood_penetration_depth: "wood_penetration_depth",
  wood_encroachment: "wood_encroachment",
  foundation_depth: "foundation_depth",
  groundlevel: "groundlevel",
  damage_cause: "damage_cause",
  damage_characteristics: "damage_characteristics",
  crack_facade_front_type: "crack_facade_front_type",
  crack_facade_back_type: "crack_facade_back_type",
  crack_indoor_type: "crack_indoor_type",
};

/** report.inquiry columns for the document-level fields. */
export const INQUIRY_COLUMN: Record<string, string> = {
  document_date: "document_date",
  inquiry_type: "type",
  contractor: "contractor",
};

/**
 * Not compared, by decision:
 *  - the two skew fields until Don rules on the unit (the model writes 300
 *    for "< 1:300", and so do 8,633 human-entered rows labelled mm/m;
 *    comparing would raise thousands of false discrepancies);
 *  - free-text advice, which has no column and no equality;
 *  - the rest have no column the invoer app fills.
 */
export const NOT_COMPARED = new Set([
  "skewed_parallel", "skewed_perpendicular",
  "recovery_note", "follow_up_note",
  "threshold_front_level", "threshold_back_level", "settlement_speed", "cpt", "mason_level",
]);

/** Tolerance for a level or length: 5 mm on metres, half a millimetre on millimetres. */
const TOLERANCE_M = 0.005;
const MM_FIELDS = new Set(["pile_diameter_top", "pile_diameter_bottom", "wood_penetration_depth"]);
const NUMERIC = new Set([
  "groundwater_level", "wood_level", "pile_head_level", "pile_tip_level", "concrete_charger_length",
  "pile_diameter_top", "pile_diameter_bottom", "pile_distance_length", "wood_penetration_depth",
  "foundation_depth", "groundlevel",
]);

export type Comparison = "agrees" | "differs" | "missing";

/** One database value as text, the way the reviewer will see it next to the proposal. */
export function currentValueText(field: string, dbValue: unknown): string | null {
  if (dbValue === null || dbValue === undefined || dbValue === "") return null;
  if (field === "built_year") {
    const d = dbValue instanceof Date ? dbValue : new Date(String(dbValue));
    return Number.isNaN(d.getTime()) ? String(dbValue) : String(d.getUTCFullYear());
  }
  if (field === "document_date") {
    const d = dbValue instanceof Date ? dbValue : new Date(String(dbValue));
    return Number.isNaN(d.getTime()) ? String(dbValue) : d.toISOString().slice(0, 10);
  }
  return String(dbValue);
}

/** Lower-case, no legal form, no punctuation -- the same as the API's contractor-match. */
export function normaliseName(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, " en ")
    .replace(/\b(b\.?\s?v\.?|n\.?\s?v\.?|v\.?o\.?f\.?|c\.?v\.?|bv|nv|vof|holding|groep|group)\b/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

/** Values that say "nothing": an empty database cell agrees with them. */
const NOTHING = new Set(["false", "none", "nil", "no", "0"]);

/**
 * Compare one proposal with the database's value for the same field.
 *
 * `proposals` is every value the model gave for this field on this sample --
 * the damage fields come as up to three candidates, and the database agrees
 * with the field if it agrees with any of them.
 */
export function compare(field: string, proposals: string[], dbValue: unknown): Comparison {
  const current = currentValueText(field, dbValue);
  if (current === null) {
    const nothing = (field === "recovery_advised" || field.startsWith("crack_")) &&
      proposals.length > 0 && proposals.every((p) => NOTHING.has(p.trim().toLowerCase()));
    return nothing ? "agrees" : "missing";
  }
  const c = current.trim().toLowerCase();
  for (const p of proposals) {
    const v = p.trim().toLowerCase();
    if (field === "built_year") {
      if (/^\d{4}/.test(v) && v.slice(0, 4) === c.slice(0, 4)) return "agrees";
      continue;
    }
    if (field === "contractor") {
      const a = normaliseName(v), b = normaliseName(c);
      if (a && b && (a === b || (a.length >= 4 && b.startsWith(`${a} `)) || (b.length >= 4 && a.startsWith(`${b} `)))) return "agrees";
      continue;
    }
    if (field === "recovery_advised") {
      const truthy = (x: string) => x === "true" || x === "t" || x === "1" || x === "ja";
      if (truthy(v) === truthy(c)) return "agrees";
      continue;
    }
    if (NUMERIC.has(field)) {
      const a = parseFloat(v), b = parseFloat(c);
      if (Number.isFinite(a) && Number.isFinite(b)) {
        const tol = MM_FIELDS.has(field) ? 0.5 : TOLERANCE_M;
        if (Math.abs(a - b) <= tol) return "agrees";
      }
      continue;
    }
    if (v === c) return "agrees";
  }
  return "differs";
}
