import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import pg from "pg";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const migrationsDir = path.resolve("supabase/migrations");
const client = new pg.Client({ connectionString: databaseUrl });

await client.connect();
try {
  await client.query("create schema if not exists internal");
  await client.query(`
    create table if not exists internal.schema_migrations (
      filename text primary key,
      applied_at timestamptz not null default now()
    )
  `);

  const files = (await readdir(migrationsDir))
    .filter((name) => name.endsWith(".sql"))
    .sort();

  for (const filename of files) {
    const existing = await client.query(
      "select 1 from internal.schema_migrations where filename = $1",
      [filename],
    );
    if (existing.rowCount) {
      console.log(`skip ${filename}`);
      continue;
    }
    const sql = await readFile(path.join(migrationsDir, filename), "utf8");
    console.log(`apply ${filename}`);
    await client.query("begin");
    try {
      await client.query(sql);
      await client.query(
        "insert into internal.schema_migrations (filename) values ($1)",
        [filename],
      );
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      console.error(`failed on ${filename}`);
      throw error;
    }
  }
  console.log("migrations complete");
} finally {
  await client.end();
}
