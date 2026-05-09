import { env } from "../config.ts";

// Experimental: HTML→PDF via self-hosted Gotenberg, candidate replacement
// for PDF.co. Not wired into the generate-pdf job yet — call directly to
// evaluate. Returns the PDF bytes; the caller is responsible for storing
// (e.g. uploading to S3).
//
// Requires FUNDERMAPS_GOTENBERG_URL pointing at a Gotenberg instance — in
// production this is the DO App Platform internal port.

const A4_INCHES_WIDTH = 8.27;
const A4_INCHES_HEIGHT = 11.69;

export async function generatePdfViaGotenberg(
  url: string,
  paperWidth = A4_INCHES_WIDTH,
  paperHeight = A4_INCHES_HEIGHT,
): Promise<Uint8Array> {
  if (!env.FUNDERMAPS_GOTENBERG_URL) {
    throw new Error("FUNDERMAPS_GOTENBERG_URL not configured");
  }

  const form = new FormData();
  form.append("url", url);
  form.append("paperWidth", String(paperWidth));
  form.append("paperHeight", String(paperHeight));
  // Equivalent to PDF.co's WaitFor selector — block rendering until the
  // report sets data-pdf-ready on <html> after charts and async data finish.
  form.append(
    "waitForExpression",
    "document.documentElement.getAttribute('data-pdf-ready') === 'true'",
  );

  const response = await fetch(
    `${env.FUNDERMAPS_GOTENBERG_URL}/forms/chromium/convert/url`,
    { method: "POST", body: form },
  );

  if (!response.ok) {
    throw new Error(`Gotenberg HTTP ${response.status}`);
  }

  return new Uint8Array(await response.arrayBuffer());
}
