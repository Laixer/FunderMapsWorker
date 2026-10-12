import { z } from "zod/v4";

const envSchema = z.object({
  // Database
  FUNDERMAPS_DATABASE_HOST: z.string(),
  FUNDERMAPS_DATABASE_PORT: z.coerce.number().default(25060),
  FUNDERMAPS_DATABASE_NAME: z.string().default("fundermaps"),
  FUNDERMAPS_DATABASE_USER: z.string().default("fundermaps"),
  FUNDERMAPS_DATABASE_PASSWORD: z.string(),

  // S3
  FUNDERMAPS_S3_ENDPOINT: z.string(),
  FUNDERMAPS_S3_REGION: z.string().default("ams3"),
  // `fundermaps` is where both prefixes live and what the API signs against
  // (S3_BUCKET on fundermaps-api-prod). It used to default to
  // fundermaps-development, which meant a misconfigured worker wrote documents
  // into one bucket while the API looked for them in another -- 891 artifact
  // rows pointing at objects that were never created.
  //
  // It stayed a default rather than a required variable because the queue
  // worker ran on a droplet whose config could not be checked from here; that
  // worker is gone since 2026-10-12 (#147), so this could become required.
  // Writes are fenced to the dataops/ prefix (see commands/ingest-dossier.ts),
  // which is the protection that actually matters.
  FUNDERMAPS_S3_BUCKET: z.string().default("fundermaps"),
  FUNDERMAPS_S3_ACCESS_KEY: z.string(),
  FUNDERMAPS_S3_SECRET_KEY: z.string(),

  // Data Ops — document lanes.
  // Models are configurable because the benchmark showed the choice matters far
  // more than the prompt: on 1,192 archive documents gemini-3.7-flash reached
  // 92% when it committed, gemini-3.1-pro 86% at 7.7x the price, and
  // qwen3-vl-235b sat at chance. Pinning a winner in code would age badly.
  OPENROUTER_API_KEY: z.string().optional(),
  DATAOPS_CLASSIFY_MODEL: z.string().default("google/gemini-3.7-flash"),
  DATAOPS_VISION_MODEL: z.string().default("google/gemini-3.7-flash"),
  DATAOPS_TEXT_MODEL: z.string().default("google/gemini-3.7-flash"),
});

export const env = envSchema.parse(process.env);
export type Env = z.infer<typeof envSchema>;
