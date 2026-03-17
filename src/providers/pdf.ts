import { env } from "../config.ts";

const BASE_URL = "https://api.pdf.co/v1";

export interface PdfResult {
  url: string;
  error: boolean;
  message?: string;
}

export async function generatePdf(
  url: string,
  name: string,
  paperSize = "A4",
  orientation = "Portrait",
  margins = "10mm"
): Promise<PdfResult> {
  if (!env.FUNDERMAPS_PDF_API_KEY) {
    throw new Error("PDF.co API key not configured");
  }

  const body = new URLSearchParams({
    url: url.trim(),
    name: name.trim(),
    paperSize,
    orientation,
    margins,
    async: "false",
  });

  const response = await fetch(`${BASE_URL}/pdf/convert/from/url`, {
    method: "POST",
    headers: {
      "x-api-key": env.FUNDERMAPS_PDF_API_KEY,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    throw new Error(`PDF.co API error: HTTP ${response.status}`);
  }

  const result = (await response.json()) as PdfResult;
  if (result.error) {
    throw new Error(`PDF.co API error: ${result.message}`);
  }

  return result;
}
