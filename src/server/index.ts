import { serve } from "@hono/node-server";
import pg from "pg";
import { createApp } from "./app.ts";
import { loadEnvFile } from "./env.ts";

loadEnvFile();

const connectionString = process.env.API_DATABASE_URL;
if (!connectionString) {
  console.error("API_DATABASE_URL is required. The API role must not bypass row level security.");
  process.exit(1);
}

const pool = new pg.Pool({ connectionString });

pool.on("connect", (client) => {
  client.query("set role edu_app").catch((error: unknown) => {
    console.error("Could not assume edu_app. Refusing to serve with the login role.", error);
    process.exit(1);
  });
});

const check = await pool.connect();
try {
  const identity = await check.query<{
    session_user: string;
    current_user: string;
    rolsuper: boolean;
    rolbypassrls: boolean;
  }>(`
    select session_user,
           current_user,
           r.rolsuper,
           r.rolbypassrls
    from pg_roles r
    where r.rolname = session_user
  `);
  const row = identity.rows[0];
  if (!row || row.rolsuper || row.rolbypassrls) {
    console.error("API_DATABASE_URL logs in as a superuser or a role that bypasses row level security.");
    process.exit(1);
  }
  await check.query("set role edu_app");
  const assumed = await check.query("select current_user");
  if (assumed.rows[0].current_user !== "edu_app") {
    console.error("The API login role could not assume edu_app.");
    process.exit(1);
  }
} finally {
  check.release();
}

const app = createApp(pool);
const port = Number(process.env.PORT ?? 43123);
serve({ fetch: app.fetch, port, hostname: "0.0.0.0" }, (info) => {
  console.log(`Education Data Core API listening on http://127.0.0.1:${info.port}`);
});
