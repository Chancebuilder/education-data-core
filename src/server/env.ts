import { readFileSync } from "node:fs";

export function loadEnvFile(file = ".env"): void {
  try {
    const text = readFileSync(file, "utf8");
    for (const line of text.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eq = trimmed.indexOf("=");
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      const value = trimmed.slice(eq + 1).trim();
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    // The process environment is enough when the file is absent.
  }
}
