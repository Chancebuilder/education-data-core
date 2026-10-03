import pg from "pg";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("DATABASE_URL is required.");
  process.exit(1);
}

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  await client.query(`
    drop schema if exists api cascade;
    drop schema if exists transfer cascade;
    drop schema if exists policy cascade;
    drop schema if exists alternative cascade;
    drop schema if exists academic cascade;
    drop schema if exists catalog cascade;
    drop schema if exists provenance cascade;
    drop schema if exists vocab cascade;
    drop schema if exists raw cascade;
    drop schema if exists internal cascade;
    drop schema if exists learner cascade;
  `);
  console.log("schemas dropped");
} finally {
  await client.end();
}
