/**
 * Data Ops — the review-queue dispatcher (FunderMapsApi #277).
 *
 * Work is pushed to people instead of everyone filtering one shared queue:
 * new meldingen get an assignee on the run after they arrive, older research
 * (nalezingen, the archive drop) is topped up to a day's worth per person, and
 * what sat untouched for five of someone's working days goes back to the pool.
 * Who takes how much is dataops.staff_capacity (Beheer › Werkverdeling). The
 * rules live in the API (lib/dispatch.ts); this script only calls
 * POST /api/dataops/dispatch as the Fundie user, the way close_qs_duplicates
 * closes dossiers through the API instead of with grants of its own.
 *
 * Two schedules: mode "new" hourly at :25 (after ingest_pending at :03 and the
 * QuickScan duplicate sweep at :20, so a duplicate is closed before anyone gets
 * it), mode "drip" every morning at 07:30. dry_run = report the plan, change
 * nothing.
 */

const API_URL = "https://api.fundermaps.com";

type Mode = "new" | "drip" | "all";
type Change = { dossierId: number; person: string; bucket?: string; idleWorkingDays?: number };

/**
 * @param api_key  fmsk key of the Fundie user ($var:f/fundermaps/dataops/qs_sweeper_api_key).
 * @param mode     new = hand out new meldingen; drip = top up research; all = both. Every mode releases stale work.
 * @param dry_run  true = show the plan, change nothing.
 */
export async function main(api_key: string, mode: Mode = "new", dry_run: boolean = true) {
  if (!api_key) throw new Error("api_key is empty (variable f/fundermaps/dataops/qs_sweeper_api_key)");
  const res = await fetch(`${API_URL}/api/dataops/dispatch`, {
    method: "POST",
    headers: { Authorization: `Bearer ${api_key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ mode, dryRun: dry_run }),
  });
  const body = (await res.json().catch(() => null)) as {
    assign: Change[]; release: Change[]; unplaced: { new: number; research: number }; skipped: number;
  } | null;
  if (!res.ok || !body) throw new Error(`dispatch answered ${res.status}: ${JSON.stringify(body).slice(0, 500)}`);

  console.log(
    `${dry_run ? "dry run" : "applied"} (${mode}): ${body.assign.length} assigned, ${body.release.length} released, ` +
    `new meldingen nobody could take ${body.unplaced.new}, research left in the pool ${body.unplaced.research}, skipped ${body.skipped}`,
  );
  return {
    mode,
    dryRun: dry_run,
    assigned: body.assign.map((a) => ({ dossier: a.dossierId, to: a.person, bucket: a.bucket })),
    released: body.release.map((r) => ({ dossier: r.dossierId, from: r.person, idleWorkingDays: r.idleWorkingDays })),
    unplaced: body.unplaced,
    skipped: body.skipped,
  };
}
