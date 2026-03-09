import { env } from "../config.ts";

export interface Email {
  to: string[];
  subject: string;
  text: string;
  from?: string;
}

export async function sendEmail(email: Email): Promise<void> {
  if (!env.FUNDERMAPS_MAIL_API_KEY) {
    throw new Error("Mail API key not configured");
  }

  const from =
    email.from ??
    `${env.FUNDERMAPS_MAIL_SENDER_NAME} <${env.FUNDERMAPS_MAIL_SENDER_ADDRESS}>`;

  const body = new URLSearchParams({
    from,
    to: email.to.join(", "),
    subject: email.subject,
    text: email.text,
  });

  const url = `${env.FUNDERMAPS_MAIL_BASE_URL}/${env.FUNDERMAPS_MAIL_DOMAIN}/messages`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`api:${env.FUNDERMAPS_MAIL_API_KEY}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Mailgun API error ${response.status}: ${text}`);
  }
}
