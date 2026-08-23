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
  // No default. A worker that writes production documents into whichever
  // bucket happened to be compiled in is how 891 artifact rows came to point at
  // objects that were never created: the record looked fine, the API signed a
  // URL against `fundermaps`, and every reviewer got a 404. Fail loudly on a
  // missing bucket instead of writing somewhere plausible.
  FUNDERMAPS_S3_BUCKET: z.string(),
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
  // Nothing is auto-accepted below this, and nothing without an evidence quote.
  // At >=0.95 the archive benchmark cleared 46% of the queue at 97.3%.
  DATAOPS_AUTO_ACCEPT: z.coerce.number().default(0.95),

  // Worker
  POLL_INTERVAL: z.coerce.number().default(30),
  MAX_CONCURRENT: z.coerce.number().default(3),
  MAX_TILESET_WORKERS: z.coerce.number().optional(),
  JOB_TIMEOUT: z.coerce.number().default(14400),
});

export const env = envSchema.parse(process.env);
export type Env = z.infer<typeof envSchema>;
