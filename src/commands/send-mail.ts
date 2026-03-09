import { log, ACCENT, RESET } from "../lib/log.ts";
import { sendEmail } from "../providers/mail.ts";

export async function sendMail(payload: {
  to: string;
  subject: string;
  text: string;
}): Promise<boolean> {
  if (!payload.to || !payload.subject || !payload.text) {
    throw new Error("Missing required fields: to, subject, text");
  }

  await sendEmail({
    to: [payload.to],
    subject: payload.subject,
    text: payload.text,
  });

  log.info(`${ACCENT.ok}✓${RESET} Email sent to ${ACCENT.muted}${payload.to}${RESET}`);
  return true;
}
