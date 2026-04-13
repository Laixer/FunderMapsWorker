export interface SpawnResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/**
 * Executes a command and captures output.
 * Optimized for long-running GIS tools with large output potential.
 */
export async function spawn(
  cmd: string[],
  options?: { timeout?: number }
): Promise<SpawnResult> {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
  });

  let timer: ReturnType<typeof setTimeout> | undefined;
  if (options?.timeout) {
    timer = setTimeout(() => {
      // Attempt to kill the process group (using negative PID)
      try {
        process.kill(-proc.pid, "SIGKILL");
      } catch {
        proc.kill();
      }
    }, options.timeout);
  }

  // Stream logs to keep memory usage low even if tools are verbose.
  // We keep the last 1MB of logs for error reporting.
  const MAX_LOG_SIZE = 1024 * 1024;
  let stdout = "";
  let stderr = "";

  const readStream = async (stream: ReadableStream, append: (chunk: string) => void) => {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = decoder.decode(value);
        append(chunk);
      }
    } finally {
      reader.releaseLock();
    }
  };

  const capture = (type: "out" | "err") => (chunk: string) => {
    if (type === "out") {
      stdout += chunk;
      if (stdout.length > MAX_LOG_SIZE) stdout = stdout.slice(-MAX_LOG_SIZE);
    } else {
      stderr += chunk;
      if (stderr.length > MAX_LOG_SIZE) stderr = stderr.slice(-MAX_LOG_SIZE);
    }
  };

  await Promise.all([
    readStream(proc.stdout, capture("out")),
    readStream(proc.stderr, capture("err")),
  ]);

  const exitCode = await proc.exited;
  if (timer) clearTimeout(timer);

  return {
    exitCode,
    stdout: stdout.trim(),
    stderr: stderr.trim(),
  };
}
