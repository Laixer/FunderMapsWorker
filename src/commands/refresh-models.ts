import { sql } from "../db.ts";
import { log, ACCENT, RESET } from "../lib/log.ts";

const RISK_VIEWS = [
  "data.building_sample",
  "data.cluster_sample",
  "data.supercluster_sample",
  "data.model_risk_static",
];

const STATISTICS_VIEWS = [
  "data.statistics_product_inquiries",
  "data.statistics_product_inquiry_municipality",
  "data.statistics_product_incidents",
  "data.statistics_product_incident_municipality",
  "data.statistics_product_foundation_type",
  "data.statistics_product_foundation_risk",
  "data.statistics_product_data_collected",
  "data.statistics_product_construction_years",
  "data.statistics_product_buildings_restored",
  "data.statistics_postal_code_foundation_type",
  "data.statistics_postal_code_foundation_risk",
  "data.statistics_postal_code_data_collected",
];

async function refreshView(view: string): Promise<void> {
  const start = performance.now();
  log.step(`Refreshing ${ACCENT.type}${view}${RESET}`);
  await sql.unsafe(
    `REFRESH MATERIALIZED VIEW CONCURRENTLY ${view}`
  );
  const elapsed = performance.now() - start;
  log.step(`${ACCENT.ok}✓${RESET} ${ACCENT.type}${view}${RESET}`, elapsed);
}

export async function refreshModels(payload: {
  skip_risk?: boolean;
  skip_statistics?: boolean;
  view?: string;
}): Promise<boolean> {
  if (payload.view) {
    if (!STATISTICS_VIEWS.includes(payload.view)) {
      log.warn(`View ${payload.view} not in known statistics views`);
      return false;
    }
    await refreshView(payload.view);
    return true;
  }

  let success = true;

  if (!payload.skip_risk) {
    log.info("Step 1: Risk metrics");
    for (const view of RISK_VIEWS) {
      try {
        await refreshView(view);
      } catch (e) {
        log.error(`Risk calculation failed on ${view}`, { error: String(e) });
        success = false;
      }
    }
  }

  if (!payload.skip_statistics) {
    log.info("Step 2: Statistics");
    for (const view of STATISTICS_VIEWS) {
      try {
        await refreshView(view);
      } catch (e) {
        log.error(`Statistics refresh failed on ${view}`, { error: String(e) });
        success = false;
      }
    }
  }

  return success;
}
