/**
 * Data Ops — risk follow-up after the model refresh (API #143 option B).
 *
 * Last step of f/fundermaps/data/refresh_data_model, after the run is logged:
 * asks the API to compare every closed melding's risk snapshot with the
 * freshly refreshed model and mail the melder once when it changed. The logic
 * lives in the API (mail templates, send log, timeline); this is the trigger.
 *
 * @param intake_token  the intake lane's shared secret ($var:f/fundermaps/intake_token)
 * @param api_url       https://api.fundermaps.com
 * @param dry_run       count only, send nothing
 */
export async function main(intake_token: string, api_url: string = "https://api.fundermaps.com", dry_run: boolean = false) {
  const res = await fetch(`${api_url}/api/intake/risk-followup`, {
    method: "POST",
    headers: { authorization: `Bearer ${intake_token}`, "content-type": "application/json" },
    body: JSON.stringify({ dry_run }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`risk-followup ${res.status}: ${text.slice(0, 300)}`);
  const result = JSON.parse(text);
  console.log(JSON.stringify(result));
  return result;
}
