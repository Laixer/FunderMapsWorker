export interface SpawnResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

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
      // Kill the entire process group so child processes (ogr2ogr workers) die too
      try {
        process.kill(-proc.pid, "SIGKILL");
      } catch {
        proc.kill();
      }
    }, options.timeout);
  }

  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);

  const exitCode = await proc.exited;
  if (timer) clearTimeout(timer);

  return { exitCode, stdout: stdout.trim(), stderr: stderr.trim() };
}
