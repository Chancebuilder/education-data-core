import { readFileSync } from "node:fs";
import path from "node:path";
import { Hono } from "hono";
import type { Pool } from "pg";

type PgError = { code?: string; message?: string };

function queryValue(value: string | undefined): string | null {
  if (value == null || value.trim() === "") return null;
  return value;
}

function queryBool(value: string | undefined): boolean {
  return value === "true" || value === "1";
}

function queryInt(value: string | undefined, fallback: number): number {
  if (value == null || value.trim() === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

async function callJson(pool: Pool, sql: string, params: unknown[]) {
  const result = await pool.query(sql, params);
  return result.rows[0]?.body ?? null;
}

function statusFor(error: PgError): number {
  if (error.code === "P0002") return 404;
  if (error.code === "22023" || error.code === "22P02" || error.code === "22007" || error.code === "22008") {
    return 422;
  }
  if (error.code === "42501") return 403;
  return 500;
}

export function createApp(pool: Pool) {
  const app = new Hono();
  const webRoot = path.resolve("src/web/index.html");
  let openApi = "";
  try {
    openApi = readFileSync(path.resolve("docs/openapi.yaml"), "utf8");
  } catch {
    openApi = "openapi: 3.1.0\ninfo:\n  title: Degree Agency Education Data API\n  version: 1.0.0\npaths: {}\n";
  }

  app.onError((error, c) => {
    const pgError = error as PgError;
    const status = statusFor(pgError);
    return c.json(
      {
        error: {
          code: pgError.code ?? "error",
          message: status === 500 ? "The request could not be completed." : pgError.message,
        },
      },
      status,
    );
  });

  app.get("/v1/health", async (c) => {
    const body = await callJson(pool, "select api.health() as body", []);
    return c.json(body);
  });

  app.get("/v1/institutions", async (c) => {
    const body = await callJson(
      pool,
      "select api.search_institutions($1, $2, $3, $4, $5) as body",
      [
        queryValue(c.req.query("q")),
        queryValue(c.req.query("status")),
        queryValue(c.req.query("country")),
        queryInt(c.req.query("limit"), 20),
        queryInt(c.req.query("offset"), 0),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_institution_profile($1::uuid, $2::date, $3) as body",
      [c.req.param("id"), queryValue(c.req.query("as_of")), queryBool(c.req.query("include_provenance"))],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/history", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_institution_history($1::uuid) as body",
      [c.req.param("id")],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/accreditation", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_institution_accreditation($1::uuid, $2::date, $3) as body",
      [c.req.param("id"), queryValue(c.req.query("as_of")), queryBool(c.req.query("include_history"))],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/programs", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_programs_by_institution($1::uuid, $2, $3::date, $4) as body",
      [
        c.req.param("id"),
        queryValue(c.req.query("degree_type")),
        queryValue(c.req.query("as_of")),
        queryValue(c.req.query("modality")),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/policies", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_transfer_policy($1::uuid, $2::date, $3::uuid, $4) as body",
      [
        c.req.param("id"),
        queryValue(c.req.query("as_of")),
        queryValue(c.req.query("program_id")),
        queryBool(c.req.query("include_provenance")),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/alternative-credit-rules", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_alternative_credit_rules($1::uuid, $2::date, $3::uuid) as body",
      [c.req.param("id"), queryValue(c.req.query("as_of")), queryValue(c.req.query("provider_id"))],
    );
    return c.json(body);
  });

  app.get("/v1/institutions/:id/policy-history", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_policy_history($1::uuid, $2) as body",
      [c.req.param("id"), queryValue(c.req.query("policy_kind"))],
    );
    return c.json(body);
  });

  app.get("/v1/program-versions/:id/requirements", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_program_requirements($1::uuid) as body",
      [c.req.param("id")],
    );
    return c.json(body);
  });

  app.get("/v1/programs", async (c) => {
    const body = await callJson(
      pool,
      "select api.search_programs($1, $2::uuid, $3, $4, $5) as body",
      [
        queryValue(c.req.query("q")),
        queryValue(c.req.query("institution_id")),
        queryValue(c.req.query("degree_type")),
        queryInt(c.req.query("limit"), 20),
        queryInt(c.req.query("offset"), 0),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/courses", async (c) => {
    const body = await callJson(
      pool,
      "select api.search_courses($1, $2::uuid, $3, $4) as body",
      [
        queryValue(c.req.query("q")),
        queryValue(c.req.query("institution_id")),
        queryInt(c.req.query("limit"), 20),
        queryInt(c.req.query("offset"), 0),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/providers", async (c) => {
    const body = await callJson(
      pool,
      "select api.search_providers($1, $2, $3) as body",
      [queryValue(c.req.query("q")), queryInt(c.req.query("limit"), 20), queryInt(c.req.query("offset"), 0)],
    );
    return c.json(body);
  });

  app.get("/v1/providers/:id", async (c) => {
    const body = await callJson(pool, "select api.get_provider($1::uuid) as body", [c.req.param("id")]);
    return c.json(body);
  });

  app.get("/v1/providers/:id/courses", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_provider_courses($1::uuid, $2, $3::date) as body",
      [c.req.param("id"), queryValue(c.req.query("q")), queryValue(c.req.query("as_of"))],
    );
    return c.json(body);
  });

  app.get("/v1/recommendations", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_credit_recommendations($1, $2::uuid, $3::uuid, $4::date) as body",
      [
        queryValue(c.req.query("authority_identifier")),
        queryValue(c.req.query("provider_id")),
        queryValue(c.req.query("learning_experience_id")),
        queryValue(c.req.query("as_of")),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/equivalencies", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_known_equivalencies($1::uuid, $2::uuid, $3::uuid, $4::date) as body",
      [
        queryValue(c.req.query("destination_institution_id")),
        queryValue(c.req.query("source_experience_version_id")),
        queryValue(c.req.query("program_version_id")),
        queryValue(c.req.query("as_of")),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/provenance", async (c) => {
    const body = await callJson(
      pool,
      "select api.get_record_provenance($1, $2, $3::uuid) as body",
      [
        queryValue(c.req.query("fact_schema")),
        queryValue(c.req.query("fact_table")),
        queryValue(c.req.query("fact_id")),
      ],
    );
    return c.json(body);
  });

  app.get("/v1/sources/:id", async (c) => {
    const body = await callJson(pool, "select api.get_source($1::uuid) as body", [c.req.param("id")]);
    return c.json(body);
  });

  app.get("/v1/research-gaps", async (c) => {
    const body = await callJson(
      pool,
      "select api.list_research_gaps($1, $2) as body",
      [queryValue(c.req.query("status")), queryValue(c.req.query("topic"))],
    );
    return c.json(body);
  });

  app.post("/v1/transfer/evaluate", async (c) => {
    const input = await c.req.json();
    const body = await callJson(
      pool,
      "select api.evaluate_transfer($1::uuid, $2::date, $3::uuid, $4, $5, $6::uuid, $7::date) as body",
      [
        input.destination_institution_id ?? null,
        input.completed_on ?? null,
        input.learning_experience_version_id ?? null,
        input.authority_identifier ?? null,
        input.grade ?? null,
        input.program_version_id ?? null,
        input.policy_as_of ?? null,
      ],
    );
    return c.json(body);
  });

  app.get("/openapi.yaml", (c) => c.text(openApi, 200, { "content-type": "application/yaml" }));

  app.get("/", (c) => c.html(readFileSync(webRoot, "utf8")));

  return app;
}
