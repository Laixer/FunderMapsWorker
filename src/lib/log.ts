type Level = "debug" | "info" | "warn" | "error";

const LEVELS: Record<Level, number> = { debug: 0, info: 1, warn: 2, error: 3 };

// ANSI 256-color codes — these work in every terminal and podman logs
const RESET = "\x1b[0m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";

const COLORS: Record<Level, string> = {
  debug: "\x1b[38;5;245m", // gray
  info: "\x1b[38;5;39m", // blue
  warn: "\x1b[38;5;214m", // orange
  error: "\x1b[38;5;196m", // red
};

const LABELS: Record<Level, string> = {
  debug: "DBG",
  info: "INF",
  warn: "WRN",
  error: "ERR",
};

// Accent colors for structured data
const ACCENT = {
  job: "\x1b[38;5;183m", // lavender — job ids
  type: "\x1b[38;5;114m", // green — job types
  time: "\x1b[38;5;223m", // peach — durations
  ok: "\x1b[38;5;84m", // bright green — success
  fail: "\x1b[38;5;203m", // coral — failure
  muted: "\x1b[38;5;242m", // dark gray — secondary info
};

let minLevel: Level = (process.env["LOG_LEVEL"] as Level) ?? "info";

function timestamp(): string {
  const d = new Date();
  const h = String(d.getHours()).padStart(2, "0");
  const m = String(d.getMinutes()).padStart(2, "0");
  const s = String(d.getSeconds()).padStart(2, "0");
  const ms = String(d.getMilliseconds()).padStart(3, "0");
  return `${h}:${m}:${s}.${ms}`;
}

function format(level: Level, msg: string, ctx?: Record<string, unknown>): string {
  const c = COLORS[level];
  const ts = `${DIM}${timestamp()}${RESET}`;
  const label = `${c}${BOLD}${LABELS[level]}${RESET}`;
  let line = `${ts} ${label} ${msg}`;

  if (ctx && Object.keys(ctx).length > 0) {
    const pairs = Object.entries(ctx)
      .map(([k, v]) => `${DIM}${k}=${RESET}${String(v)}`)
      .join(" ");
    line += ` ${pairs}`;
  }

  return line;
}

function write(level: Level, msg: string, ctx?: Record<string, unknown>): void {
  if (LEVELS[level] < LEVELS[minLevel]) return;
  const line = format(level, msg, ctx);
  if (level === "error") {
    process.stderr.write(line + "\n");
  } else {
    process.stdout.write(line + "\n");
  }
}

export const log = {
  debug: (msg: string, ctx?: Record<string, unknown>) => write("debug", msg, ctx),
  info: (msg: string, ctx?: Record<string, unknown>) => write("info", msg, ctx),
  warn: (msg: string, ctx?: Record<string, unknown>) => write("warn", msg, ctx),
  error: (msg: string, ctx?: Record<string, unknown>) => write("error", msg, ctx),

  // Structured helpers for common patterns
  job(action: string, jobId: number, jobType?: string, extra?: Record<string, unknown>) {
    const parts = [`${ACCENT.job}#${jobId}${RESET}`];
    if (jobType) parts.push(`${ACCENT.type}${jobType}${RESET}`);
    parts.push(action);
    write("info", parts.join(" "), extra);
  },

  jobOk(jobId: number, jobType: string, durationMs: number) {
    const dur = formatDuration(durationMs);
    write(
      "info",
      `${ACCENT.ok}✓${RESET} ${ACCENT.job}#${jobId}${RESET} ${ACCENT.type}${jobType}${RESET} completed in ${ACCENT.time}${dur}${RESET}`
    );
  },

  jobFail(jobId: number, jobType: string, error: string) {
    write(
      "error",
      `${ACCENT.fail}✗${RESET} ${ACCENT.job}#${jobId}${RESET} ${ACCENT.type}${jobType}${RESET} failed: ${error}`
    );
  },

  step(label: string, durationMs?: number) {
    const dur = durationMs != null ? ` ${ACCENT.time}${formatDuration(durationMs)}${RESET}` : "";
    write("info", `  ${ACCENT.muted}→${RESET} ${label}${dur}`);
  },

  banner(text: string) {
    const line = `${BOLD}${COLORS.info}${"─".repeat(48)}${RESET}`;
    process.stdout.write(`${line}\n`);
    process.stdout.write(`${BOLD}${COLORS.info}  ${text}${RESET}\n`);
    process.stdout.write(`${line}\n`);
  },

  setLevel(level: Level) {
    minLevel = level;
  },
};

function formatDuration(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const rem = Math.round(s % 60);
  if (m < 60) return `${m}m${rem}s`;
  const h = Math.floor(m / 60);
  const remM = m % 60;
  return `${h}h${remM}m`;
}

export { ACCENT, RESET, BOLD, DIM, formatDuration };
