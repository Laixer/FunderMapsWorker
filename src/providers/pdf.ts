import { env } from "../config.ts";

// Gotenberg's Chromium module renders a URL to PDF and returns the bytes
// inline (no async job, no CDN hop). Replaces the prior pdf.co provider.
//
// `waitForExpression` blocks Chromium until the report front-end signals it's
// done rendering — pairs with FunderMapsReport setting
// `<html data-pdf-ready="true">` after Highcharts/Leaflet etc. settle. Without
// it, chart-heavy reports rasterize while still skeleton-painted.
export async function generatePdf(
  url: string,
  orientation: "Portrait" | "Landscape" = "Portrait",
  margins = "10mm"
): Promise<Uint8Array> {
  if (!env.FUNDERMAPS_GOTENBERG_URL) {
    throw new Error("Gotenberg URL not configured (FUNDERMAPS_GOTENBERG_URL)");
  }

  const form = new FormData();
  form.append("url", url.trim());
  form.append("paperWidth", "8.27");
  form.append("paperHeight", "11.69");
  form.append("landscape", orientation === "Landscape" ? "true" : "false");
  form.append("marginTop", margins);
  form.append("marginBottom", margins);
  form.append("marginLeft", margins);
  form.append("marginRight", margins);
  form.append(
    "waitForExpression",
    "document.documentElement.getAttribute('data-pdf-ready') === 'true'"
  );

  const response = await fetch(
    `${env.FUNDERMAPS_GOTENBERG_URL}/forms/chromium/convert/url`,
    { method: "POST", body: form }
  );

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`Gotenberg error: HTTP ${response.status} ${detail}`);
  }

  return new Uint8Array(await response.arrayBuffer());
}
