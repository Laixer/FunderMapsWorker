import { z } from "zod/v4";
import { sql } from "./db.ts";
import { env } from "./config.ts";
import { log, ACCENT, RESET } from "./lib/log.ts";
import { concurrentMap } from "./lib/queue.ts";
import { processMapset } from "./commands/process-mapset.ts";
import { exportProduct } from "./commands/export-product.ts";
import { loadDataset } from "./commands/load-dataset.ts";
import { generatePdfCommand } from "./commands/generate-pdf.ts";
import { cleanupStorage } from "./commands/cleanup-storage.ts";
import { sendMail } from "./commands/send-mail.ts";
import { exportSamples } from "./commands/export-samples.ts";

// -- Job types ----------------------------------------------------------------

interface Job {
  id: number;
  job_type: string;
  payload: Record<string, unknown> | null;
  priority: number;
  retry_count: number;
  max_retries: number;
}

// -- Payload schemas ----------------------------------------------------------

const payloadSchemas = {
  process_mapset: z.object({
    tileset: z.union([z.string(), z.array(z.string())]).optional(),
    max_workers: z.number().optional(),
  }),
  export_product: z.object({
    date: z.string().optional(),
  }),
  load_dataset: z.object({
    dataset_input: z.string(),
    layer: z.array(z.string()).optional(),
    delete_after: z.boolean().optional(),
    tmp_dir: z.string().optional(),
  }),
  generate_pdf: z.object({
    url: z.string(),
    output_name: z.string().optional(),
  }),
  cleanup_storage: z.object({}).passthrough(),
  send_mail: z.object({
    to: z.string(),
    subject: z.string(),
    text: z.string(),
  }),
  export_samples: z.object({
    date: z.string().optional(),
  }),
} as const;

type JobType = keyof typeof payloadSchemas;

const handlers: Record<JobType, (payload: unknown) => Promise<boolean>> = {
  process_mapset: (p) => processMapset(p as z.infer<typeof payloadSchemas.process_mapset>),
  export_product: (p) => exportProduct(p as z.infer<typeof payloadSchemas.export_product>),
  load_dataset: (p) => loadDataset(p as z.infer<typeof payloadSchemas.load_dataset>),
  generate_pdf: (p) => generatePdfCommand(p as z.infer<typeof payloadSchemas.generate_pdf>),
  cleanup_storage: () => cleanupStorage(),
  send_mail: (p) => sendMail(p as z.infer<typeof payloadSchemas.send_mail>),
  export_samples: (p) => exportSamples(p as z.infer<typeof payloadSchemas.export_samples>),
};

// -- DB helpers ---------------------------------------------------------------

async function getPendingJobs(): Promise<Job[]> {
  return sql<Job[]>`
    SELECT id, job_type, payload, priority, retry_count, max_retries
    FROM application.worker_jobs
    WHERE status = 'pending'
      AND (process_after IS NULL OR process_after <= NOW())
      AND (max_retries = 0 OR retry_count < max_retries)
    ORDER BY priority DESC, created_at ASC
  `;
}

async function markInProgress(jobId: number): Promise<boolean> {
  const result = await sql`
    UPDATE application.worker_jobs
    SET status = 'processing', updated_at = NOW()
    WHERE id = ${jobId} AND status = 'pending'
    RETURNING id
  `;
  return result.length > 0;
}

async function markComplete(jobId: number): Promise<void> {
  await sql`
    UPDATE application.worker_jobs
    SET status = 'completed', updated_at = NOW()
    WHERE id = ${jobId}
  `;
}

async function markFailed(
  jobId: number,
  error: string,
  retry = true
): Promise<void> {
  const [job] = await sql<{ retry_count: number; max_retries: number }[]>`
    SELECT retry_count, max_retries
    FROM application.worker_jobs
    WHERE id = ${jobId}
  `;

  if (!job) {
    log.error(`Job ${jobId} not found`);
    return;
  }

  const newRetryCount = job.retry_count + 1;
  const canRetry =
    retry && (job.max_retries === 0 || newRetryCount < job.max_retries);
  const newStatus = canRetry ? "pending" : "failed";

  if (canRetry) {
    const backoffSeconds = 30 * Math.pow(2, newRetryCount - 1);
    log.warn(
      `${ACCENT.job}#${jobId}${RESET} scheduling retry in ${ACCENT.time}${backoffSeconds}s${RESET}`,
      { attempt: `${newRetryCount}/${job.max_retries || "∞"}` }
    );

    await sql`
      UPDATE application.worker_jobs
      SET
        status = ${newStatus},
        retry_count = ${newRetryCount},
        last_error = ${error},
        process_after = NOW() + ${`${backoffSeconds} seconds`}::interval,
        updated_at = NOW()
      WHERE id = ${jobId}
    `;
  } else {
    await sql`
      UPDATE application.worker_jobs
      SET
        status = ${newStatus},
        retry_count = ${newRetryCount},
        last_error = ${error},
        process_after = NULL,
        updated_at = NOW()
      WHERE id = ${jobId}
    `;
  }
}

/** Wraps a DB status update with a fallback if the connection is broken. */
async function safeDbUpdate(
  jobId: number,
  fn: () => Promise<void>,
  fallbackError: string
): Promise<void> {
  try {
    await fn();
  } catch (e) {
    log.error(`Failed to update job #${jobId}, forcing failed`, { error: String(e) });
    try {
      await sql`
        UPDATE application.worker_jobs
        SET status = 'failed', last_error = ${fallbackError}, updated_at = NOW()
        WHERE id = ${jobId}
      `;
    } catch {
      log.error(`Job #${jobId} stuck in 'processing' — DB unreachable`);
    }
  }
}

// -- Job dispatch -------------------------------------------------------------

async function processJob(job: Job): Promise<boolean> {
  // Canonical form is underscore (e.g. `process_mapset`) — that's what
  // data.refresh_all and schema.sql emit. The command files and docs use
  // dashes, so accept dashes too rather than silently failing.
  const jobType = job.job_type.replace(/-/g, "_") as JobType;
  const handler = handlers[jobType];
  const schema = payloadSchemas[jobType];

  if (!handler || !schema) {
    log.error(`Unknown job type: ${job.job_type}`, { job: job.id });
    await safeDbUpdate(job.id, () => markFailed(job.id, `Unknown job type: ${job.job_type}`, false), `Unknown job type: ${job.job_type}`);
    return false;
  }

  // Validate payload
  const parsed = schema.safeParse(job.payload ?? {});
  if (!parsed.success) {
    const msg = `Invalid payload: ${z.prettifyError(parsed.error)}`;
    log.error(msg, { job: job.id });
    await safeDbUpdate(job.id, () => markFailed(job.id, msg, false), msg);
    return false;
  }

  if (!(await markInProgress(job.id))) {
    log.warn(`${ACCENT.job}#${job.id}${RESET} could not be claimed, skipping`);
    return false;
  }

  log.job("started", job.id, job.job_type);
  const start = performance.now();

  const ac = new AbortController();
  const timeoutMs = env.JOB_TIMEOUT * 1000;
  const timer = setTimeout(() => ac.abort(), timeoutMs);

  try {
    const result = await Promise.race([
      handler(parsed.data),
      new Promise<never>((_, reject) => {
        ac.signal.addEventListener("abort", () =>
          reject(new Error(`Job timed out after ${env.JOB_TIMEOUT}s`))
        );
      }),
    ]);

    clearTimeout(timer);
    const elapsed = performance.now() - start;

    if (result) {
      await safeDbUpdate(job.id, () => markComplete(job.id), "DB error during mark-complete");
      log.jobOk(job.id, job.job_type, elapsed);
      return true;
    } else {
      await safeDbUpdate(job.id, () => markFailed(job.id, "Job processing returned failure"), "Job processing returned failure");
      log.jobFail(job.id, job.job_type, "returned failure");
      return false;
    }
  } catch (e) {
    clearTimeout(timer);
    const message = e instanceof Error ? e.message : String(e);
    log.jobFail(job.id, job.job_type, message);
    await safeDbUpdate(job.id, () => markFailed(job.id, message), message);
    return false;
  }
}

// -- Stale job recovery -------------------------------------------------------

const STALE_THRESHOLD_HOURS = 2;

async function recoverStaleJobs(): Promise<void> {
  const errorMsg = `Reset: stuck in processing for >${STALE_THRESHOLD_HOURS}h (likely OOM or crash)`;
  const stale = await sql<{ id: number; job_type: string }[]>`
    UPDATE application.worker_jobs
    SET status = 'pending', updated_at = NOW(), last_error = ${errorMsg}
    WHERE status = 'processing'
      AND updated_at < NOW() - ${`${STALE_THRESHOLD_HOURS} hours`}::interval
    RETURNING id, job_type
  `;

  for (const job of stale) {
    log.warn(
      `Recovered stale job ${ACCENT.job}#${job.id}${RESET} (${job.job_type})`
    );
  }
}

// -- Main loop ----------------------------------------------------------------

let shuttingDown = false;

async function processJobs(): Promise<void> {
  // Health check: Ensure DB is reachable before polling
  try {
    await sql`SELECT 1`;
  } catch (e) {
    log.error("Database health check failed", { error: String(e) });
    return;
  }

  await recoverStaleJobs();

  const jobs = await getPendingJobs();
  if (jobs.length === 0) return;

  log.info(`Found ${ACCENT.job}${jobs.length}${RESET} pending job(s)`);
  try {
    await concurrentMap(jobs, env.MAX_CONCURRENT, processJob);
  } catch (e) {
    log.error("Queue execution crashed", { error: String(e) });
  }
}

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  log.warn(`Received ${signal}, shutting down gracefully...`);

  // Force exit after 10s if graceful shutdown hangs
  setTimeout(() => {
    log.error("Graceful shutdown timed out, forcing exit");
    process.exit(1);
  }, 10000).unref();

  // Give in-flight jobs a few seconds to finish their current DB writes
  await Bun.sleep(2000);

  // Close the postgres connection pool
  try {
    await sql.end({ timeout: 5 });
  } catch (e) {
    log.error("Error closing database pool", { error: String(e) });
  }
  log.info("Shutdown complete");
  process.exit(0);
}

// -- Safety nets --------------------------------------------------------------

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

process.on("unhandledRejection", (reason) => {
  log.error("CRITICAL: Unhandled promise rejection", {
    error: reason instanceof Error ? reason.message : String(reason),
    stack: reason instanceof Error ? reason.stack : undefined,
  });
});

// -- Start --------------------------------------------------------------------

log.banner("FunderMaps Worker");
log.info("Starting worker", {
  poll: `${env.POLL_INTERVAL}s`,
  concurrency: env.MAX_CONCURRENT,
  timeout: `${env.JOB_TIMEOUT}s`,
});

while (!shuttingDown) {
  try {
    const start = performance.now();
    await processJobs();
    const elapsed = (performance.now() - start) / 1000;

    const sleepTime = Math.max(0.1, env.POLL_INTERVAL - elapsed);
    await Bun.sleep(sleepTime * 1000);
  } catch (e) {
    log.error("Error in processing cycle", { error: String(e) });
    await Bun.sleep(env.POLL_INTERVAL * 1000);
  }
}
