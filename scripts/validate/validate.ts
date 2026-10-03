import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import pg from "pg";
import { loadEnvFile } from "../../src/server/env.ts";

loadEnvFile();

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const failures: string[] = [];

function fail(message: string) {
  failures.push(message);
  console.error(`FAIL ${message}`);
}

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  const quality = await client.query<{ severity: string; n: number }>(
    "select severity, count(*)::int as n from internal.run_data_quality_checks() group by severity",
  );
  for (const row of quality.rows) {
    console.log(`quality ${row.severity}: ${row.n}`);
    if (row.severity === "error" && row.n > 0) fail(`${row.n} data-quality errors`);
  }

  const counts = await client.query<{ name: string; n: string }>(`
    select 'equivalencies' as name, count(*)::text as n from transfer.course_equivalencies
    union all select 'identifiers', count(*)::text from catalog.institution_identifiers
    union all select 'inferred_recommendations', count(*)::text
      from alternative.credit_recommendations where verification_status = 'inferred'
    union all select 'inferred_facts', count(*)::text
      from policy.policy_facts where verification_status = 'inferred'
    union all select 'regional_labels', count(*)::text
      from catalog.institution_accreditations
      where historical_classification_label ilike '%regional%'
    union all select 'established_acceptance', count(*)::text
      from policy.policy_facts where establishes_course_acceptance
  `);
  for (const row of counts.rows) {
    console.log(`${row.name}: ${row.n}`);
    if (Number(row.n) !== 0) fail(`${row.name} expected 0, found ${row.n}`);
  }
} finally {
  await client.end();
}

const skipDirs = new Set(["node_modules", ".git", "uploads", "dist", "coverage"]);
const secretPatterns: { name: string; pattern: RegExp }[] = [
  { name: "service role assignment", pattern: /SUPABASE_SERVICE_ROLE_KEY\s*=\s*\S+/ },
  { name: "live secret key", pattern: /sk_live_[0-9A-Za-z]+/ },
  { name: "aws access key", pattern: /AKIA[0-9A-Z]{16}/ },
  { name: "private key block", pattern: /BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY/ },
];

async function walk(dir: string): Promise<void> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (skipDirs.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(full);
      continue;
    }
    if (entry.name === ".env" || entry.name.endsWith(".json") && full.includes(`${path.sep}data${path.sep}processed${path.sep}`)) {
      continue;
    }
    if (!/\.(ts|sql|md|yml|yaml|json|toml|html|example|sh)$/.test(entry.name) && entry.name !== ".env.example") {
      continue;
    }
    const text = await readFile(full, "utf8");
    for (const rule of secretPatterns) {
      if (rule.pattern.test(text)) fail(`${rule.name} in ${path.relative(process.cwd(), full)}`);
    }
  }
}

await walk(process.cwd());

if (failures.length) {
  console.error(`${failures.length} validation failure(s).`);
  process.exit(1);
}
console.log("validation passed");
