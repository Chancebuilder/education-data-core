# Deployment

V1 is validated against local PostgreSQL 16. It has not been deployed to Supabase or any other hosted environment.

## Local

PostgreSQL 16 with `postgresql-contrib` (`pgcrypto`, `pg_trgm`, `unaccent`). Node.js 22.

```bash
sudo pg_ctlcluster 16 main start
bash scripts/dev/setup_local_postgres.sh
cp .env.example .env
npm install
npm run db:setup
npm test
npm run validate
npm run dev
```

`db:setup` drops the application schemas, applies `supabase/migrations` in filename order, and loads `data/raw/v1_research_extract.json`.

The API listens on `0.0.0.0` and `PORT` (43123 in `.env.example`):

```text
http://127.0.0.1:43123
```

`DATABASE_URL` is the migrator, a local superuser used only for migrations, ingestion, and tests. `API_DATABASE_URL` is `edu_api`, which is not a superuser and cannot bypass row level security. The server sets the role to `edu_app` and exits if the login role is too privileged.

Local passwords in `.env.example` are development defaults. Do not reuse them outside this machine. Do not commit `.env`.

## Configuration

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | for migrate, seed, test, validate | `edu_migrator` |
| `API_DATABASE_URL` | for `npm run dev` | `edu_api` |
| `PORT` | no | Defaults to 43123 |

No Supabase keys are required to run locally. If you later host the database, put `SUPABASE_URL` and the anon key in the environment of the client that should be public. Never put `SUPABASE_SERVICE_ROLE_KEY` in this repository, in the browser, or in the page at `/`.

## Supabase, when you choose to deploy

1. Create a project on PostgreSQL 15 or 16.
2. Apply `supabase/migrations/*.sql` in order with the Supabase SQL editor or CLI. Do not run `db:reset` against a database you need to keep.
3. Run the ingest with `DATABASE_URL` pointing at a role that can write and that is not the service role embedded in a client.
4. In `supabase/config.toml`, `schemas = ["api"]` is already set. Do not add `raw`, `internal`, or `learner` to the exposed API.
5. Grant the mapping roles if they exist: `anon` inherits `edu_anon`, `authenticated` inherits `edu_app`. The first migration does this when those roles are present.
6. Confirm `edu_anon` can `select` an institution and cannot `select provenance.research_gaps`.
7. Point this HTTP service at `API_DATABASE_URL` for a role equivalent to `edu_api`, or call `api.*` through Supabase RPC as `anon` / `authenticated`.

`supabase/config.toml` does not start a local Supabase stack by itself.

## What to re-check after a deploy

```sql
select count(*) from catalog.institutions;                  -- 10
select count(*) from transfer.course_equivalencies;         -- 0
select count(*) from catalog.institution_identifiers;       -- 0
select severity, count(*) from internal.run_data_quality_checks() group by severity;
```

Then call `GET /v1/health` and `POST /v1/transfer/evaluate` for TESU and `SDCM-0160`. `institution_accepts` must remain `not_documented`.
