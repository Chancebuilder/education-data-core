import pg from "pg";
import { createApp } from "../src/server/app.ts";

const connectionString = process.env.API_DATABASE_URL;
if (!connectionString) throw new Error("API_DATABASE_URL is required.");

const pool = new pg.Pool({
  connectionString,
  max: 5,
  ssl: { rejectUnauthorized: false },
});

pool.on("connect", (client) => {
  void client.query("set role edu_app");
});

export default createApp(pool);
