# Education Data Core

Provenance-preserving catalog of institutions, accreditation, transfer policy, and credit recommendations for Degree Agency. The October 3, 2026 research extract is the V1 seed. Missing facts stay null or `not_documented`.

A credit recommendation does not mean an institution accepts the credit. Acceptance does not create a course equivalency. An equivalency does not satisfy a degree requirement.

## Run locally

PostgreSQL 16 and Node.js 22.

```bash
bash scripts/dev/setup_local_postgres.sh
cp .env.example .env
npm install
npm run db:setup
npm test
npm run validate
npm run dev
```

Open [the API and catalog browser](http://127.0.0.1:43123).

`npm run db:setup` resets the application schemas, applies migrations, and loads `data/raw/v1_research_extract.json`. Running the seed again does not duplicate institutions or recommendations.

## Layout

| Path | Contents |
| --- | --- |
| `supabase/migrations` | Ordered SQL |
| `data/raw/v1_research_extract.json` | Seed extract |
| `scripts/ingest` | Idempotent load |
| `scripts/validate` | Quality and secret checks |
| `src/server` | HTTP API |
| `src/web` | Catalog browser |
| `src/types` | TypeScript shapes |
| `docs` | Architecture, model, dictionary, API, deployment |
| `tests` | Database and HTTP tests |

Read `CURSOR_HANDOFF.md` before changing the schema.
