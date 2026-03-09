import { spawn } from "../lib/subprocess.ts";
import { which } from "bun";

export async function tippecanoe(
  input: string,
  output: string,
  layer?: string,
  maxZoom = 15,
  minZoom = 10
): Promise<void> {
  if (!which("tippecanoe")) {
    throw new Error("tippecanoe not found in PATH");
  }

  const cmd = [
    "tippecanoe",
    "--force",
    "--read-parallel",
    "--drop-densest-as-needed",
    "--quiet",
    "--no-tile-compression",
    "-z",
    String(maxZoom),
    "-Z",
    String(minZoom),
    "--output-to-directory",
    output,
  ];

  if (layer) {
    cmd.push("-l", layer);
  }

  cmd.push(String(input));

  const result = await spawn(cmd, { timeout: 600_000 });
  if (result.exitCode !== 0) {
    throw new Error(`tippecanoe failed: ${result.stderr}`);
  }
}
