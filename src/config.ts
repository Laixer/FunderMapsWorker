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
  FUNDERMAPS_S3_BUCKET: z.string().default("fundermaps-development"),
  FUNDERMAPS_S3_ACCESS_KEY: z.string(),
  FUNDERMAPS_S3_SECRET_KEY: z.string(),

  // Worker
  POLL_INTERVAL: z.coerce.number().default(30),
  MAX_CONCURRENT: z.coerce.number().default(3),
  MAX_TILESET_WORKERS: z.coerce.number().optional(),
  JOB_TIMEOUT: z.coerce.number().default(14400),
});

export const env = envSchema.parse(process.env);
export type Env = z.infer<typeof envSchema>;
