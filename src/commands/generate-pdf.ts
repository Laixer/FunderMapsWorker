import { log, ACCENT, RESET, formatDuration } from "../lib/log.ts";
import { generatePdf } from "../providers/pdf.ts";
import * as s3 from "../providers/s3.ts";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

export async function generatePdfCommand(payload: {
  url: string;
  output_name?: string;
}): Promise<boolean> {
  const { url } = payload;
  if (!url) {
    throw new Error("Missing required field 'url'");
  }

  try {
    new URL(url);
  } catch {
    log.error(`Invalid URL: ${url}`);
    return false;
  }

  const outputName =
    payload.output_name ??
    new URL(url).pathname.replace(/\//g, "_").replace(/^_/, "");

  const start = performance.now();
  log.step(`Generating PDF from ${ACCENT.muted}${url}${RESET}`);

  try {
    const result = await generatePdf(url, outputName);

    if (!result.url) {
      log.error("PDF generation returned no URL");
      return false;
    }

    const pdfDir = "./pdfs";
    await mkdir(pdfDir, { recursive: true });
    const pdfPath = join(pdfDir, `${outputName}.pdf`);

    log.step("Downloading generated PDF");
    const response = await fetch(result.url);
    if (!response.ok) {
      throw new Error(`Failed to download PDF: HTTP ${response.status}`);
    }
    await Bun.write(pdfPath, response);

    log.step("Uploading to S3");
    const s3Path = `artifacts/report-pdf/${outputName}.pdf`;
    await s3.uploadFile(pdfPath, s3Path, "fundermaps");

    const elapsed = performance.now() - start;
    log.info(
      `${ACCENT.ok}✓${RESET} PDF generated in ${ACCENT.time}${formatDuration(elapsed)}${RESET}`
    );
    return true;
  } catch (e) {
    log.error("PDF generation failed", { error: String(e) });
    return false;
  }
}
