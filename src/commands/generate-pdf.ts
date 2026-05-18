import { log, ACCENT, RESET, formatDuration } from "../lib/log.ts";
import { generatePdf } from "../providers/pdf.ts";
import * as s3 from "../providers/s3.ts";

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
    const bytes = await generatePdf(url);

    log.step("Uploading to S3");
    const s3Key = `artifacts/report-pdf/${outputName}.pdf`;
    await s3.uploadBytes(bytes, s3Key, "fundermaps", {
      ContentType: "application/pdf",
    });

    const elapsed = performance.now() - start;
    log.info(
      `${ACCENT.ok}✓${RESET} PDF generated in ${ACCENT.time}${formatDuration(elapsed)}${RESET} (${bytes.byteLength} bytes)`
    );
    return true;
  } catch (e) {
    log.error("PDF generation failed", { error: String(e) });
    return false;
  }
}
