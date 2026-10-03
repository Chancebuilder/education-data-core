# Cursor handoff

This repository is the Degree Agency Education Data Core V1. It is a PostgreSQL catalog and HTTP API seeded from the October 3, 2026 research extract. It is locally validated. It is not deployed to Supabase or production.

## What was built

- Schemas `vocab`, `provenance`, `catalog`, `academic`, `alternative`, `policy`, `transfer`, `raw`, `internal`, `api`, and an empty `learner` schema.
- Ordered SQL migrations in `supabase/migrations`.
- Idempotent ingest of `data/raw/v1_research_extract.json`.
- RLS for anonymous, application, editor, ingest, and admin roles.
- `api` functions for search, profiles, accreditation, programs, policies, recommendations, equivalencies, and transfer evaluation.
- Hono HTTP service in `src/server` and a catalog page in `src/web/index.html`.
- Tests in `tests/education-data-core.test.ts` and `scripts/validate/validate.ts`.
- Types in `src/types`. Docs in `docs`.

## Repository structure

```text
supabase/migrations     executable SQL, filename order
supabase/config.toml    Supabase marker; exposes only api
data/raw                v1_research_extract.json
scripts/db              migrate and reset
scripts/ingest          seed loader
scripts/validate        quality and secret scan
scripts/dev             local role setup
src/server              HTTP API
src/web/index.html      catalog browser
src/types               database and API types
docs                    architecture through deployment
tests                   node:test suite
```

## Schema architecture

Read `docs/architecture.md` and `docs/data-model.md` before editing tables.

Canonical ids are UUIDs. Ingest uses UUID v5, namespace `8c1d1a4e-5b2f-4c3a-9e7d-6f0a1b2c3d4e`, name `kind:key` (`scripts/ingest/ingest.ts`). External identifiers are a separate table and are empty.

Valid time is inclusive `valid_from` / `valid_to`. Year precision is ambiguous for every day in that year. Both bounds null is undated and must not be applied to a historical `as_of`. `current_status` is a cache. Knowledge time is `recorded_at` / `superseded_at`.

Do not collapse recommendation, acceptance, equivalency, and degree applicability. `establishes_course_acceptance` is false unless strength is `provider` or `course`. `addresses` is not `accepts`. `api.evaluate_transfer` keeps `degree_requirement_satisfied` at `not_documented`. Do not convert semester and quarter credits. Do not store a derived remainder in place of a sourced `context_value`.

## Migrations

Apply with `npm run db:migrate`. Files:

1. `202610030001_extensions_schemas_roles.sql`
2. `202610030002_vocabularies.sql`
3. `202610030003_provenance.sql`
4. `202610030004_catalog.sql`
5. `202610030005_academic.sql`
6. `202610030006_alternative_credit.sql`
7. `202610030007_policy_and_transfer.sql`
8. `202610030008_audit_and_quality.sql`
9. `202610030009_rls.sql`
10. `202610030010_api.sql`
11. `202610030011_api_queries.sql`
12. `202610030012_evaluate_and_grants.sql`

Do not edit an applied migration in a shared database. Add the next numbered file. `npm run db:reset` drops these schemas and is only for local rebuilds.

## Important tables

- `catalog.institutions`, `institution_aliases`, `institution_identifiers`, `institution_status_versions`
- `catalog.accreditors`, `accreditor_recognition_history`, `institution_accreditations`
- `academic.programs`, `program_versions`, `institution_courses`, `course_versions`
- `academic.requirement_nodes`, `requirement_bindings` (empty, BUILD NEXT)
- `alternative.recommendation_bodies`, `providers`, `learning_experiences`, `learning_experience_versions`, `credit_recommendations`
- `policy.policies`, `policy_versions`, `policy_facts`, `policy_fact_providers`
- `policy.policy_rules` and children (empty, BUILD NEXT)
- `transfer.course_equivalencies` (empty seed), `articulation_agreements` (empty)
- `provenance.source_documents`, `evidence`, `fact_evidence_links`, `research_gaps` (staff only)
- `raw.source_payloads`, `internal.import_batches`, `internal.change_log`
- `catalog.search_documents` (rebuilt on each ingest; no vector column)

## Important functions

Public: `api.search_institutions`, `get_institution_profile`, `get_institution_history`, `get_institution_accreditation`, `get_programs_by_institution`, `search_programs`, `get_program_requirements`, `get_transfer_policy`, `get_policy_history`, `get_alternative_credit_rules`, `search_courses`, `search_providers`, `get_provider`, `get_provider_courses`, `get_credit_recommendations`, `get_known_equivalencies`, `evaluate_transfer`, `get_record_provenance`, `get_source`, `health`, `temporal_coverage`, `credits_are_comparable`.

Views: `api.v_institutions_current`, `api.v_recommendation_acceptance_boundary`.

Staff only: `api.rebuild_search_documents`, `api.list_research_gaps`, `internal.run_data_quality_checks`.

HTTP routes mirror these functions. See `docs/api.md` and `docs/openapi.yaml`. The server reads `API_DATABASE_URL`, refuses a superuser, and `SET ROLE edu_app`.

## Environment variables

```text
DATABASE_URL=postgres://edu_migrator:edu_migrator@127.0.0.1:5432/education_data_core
API_DATABASE_URL=postgres://edu_api:edu_api@127.0.0.1:5432/education_data_core
PORT=43123
```

Copy `.env.example`. Never commit `.env` or a Supabase service-role key.

## Run locally

```bash
bash scripts/dev/setup_local_postgres.sh
cp .env.example .env
npm install
npm run db:setup
npm test
npm run validate
npm run dev
```

The page and API are at `http://127.0.0.1:43123`.

## Test

`npm test` uses Node's test runner, one file at a time. It checks seed counts, quality, search, Excelsior and Brandman names, ITT closure, undated TESU accreditation, the TESU 90-credit effective date, SDCM-0160 inclusive dates, Charter Oak "addresses" versus acceptance, empty requirements, constraints, RLS, idempotent ingest, and the HTTP evaluate response.

One test inserts a `SYNTHETIC FIXTURE` institution, a provider acceptance, and a direct equivalency, then rolls back. It proves degree applicability stays `not_documented`. Do not commit fixture rows.

`npm run validate` fails on quality errors, any equivalency, any identifier, any inferred fact, any "regional" classification label, any seeded acceptance flag, or secret-shaped strings in the tree.

## Deploy

Follow `docs/deployment.md`. Expose only the `api` schema. Map `anon` → `edu_anon` and `authenticated` → `edu_app`. Do not run `db:reset` against a database you need to keep.

## Seed counts from the extract

| Entity | Count |
| --- | --- |
| Institutions | 10 |
| Aliases | 12 |
| External identifiers | 0 |
| Accreditors | 6 |
| Institution accreditations | 8 |
| Providers | 4 |
| Learning experiences | 2 |
| Credit recommendations | 1 |
| Programs | 1 |
| Policy facts | 16 |
| Equivalencies | 0 |
| Research gaps | 35 |
| Source documents | 25 |

Quality after seed: no `error` rows. Two `info` rows because Sophia Learning and StraighterLine have no learning-experience rows. That is expected.

## Known gaps

Do not fill these by inference:

- No UNITID, OPEID, or DAPIP.
- No Excelsior accreditor, no ITT–ACICS grant, no DEAC recognition row.
- No course equivalencies and no requirement trees.
- Charter Oak numeric maxima and grade thresholds are null.
- SNHU course-age duration is null. The 120 beside the 90 is a published total, not a stored 30-credit residency.
- Capella quarter-credit discussion is not converted.
- TESU, and the other undated accreditation rows, must not be projected onto an earlier year.
- Excelsior College's start date is unknown. The 2022-07-31 end is an interpretation of the August 1, 2022 designation.
- Brandman/UMass and Kaplan/Purdue Global transitions are year precision, so the transition year is ambiguous.
- Coopersmith has no captured course code and no recommendation.
- SDCM-0160 recommended credits, level, and subject are null.
- 35 research gaps remain in `provenance.research_gaps` for editors. The public API answers `not_documented` instead of returning that queue.

## Next implementation priorities

1. Load authoritative external identifiers with their own sources, still in `institution_identifiers`.
2. Capture dated accreditation grants where the accreditor or institution publishes start and end.
3. Add destination courses and equivalencies only from institution publications, each with a source document.
4. Fill `requirement_nodes` for one program before any solver. Keep `practical_max_transfer` computed, not stored as an institutional attribute.
5. Move typed facts into `policy_rules` only when a fact needs conditions the typed columns cannot express.
6. Make `rebuild_search_documents` diff-based so a repeat ingest does not rewrite the lexical index.

## Deferred

Learner wallet, PESC/CLR, international evaluation, military credit, certifications, an articulation graph, vector search, a degree-path optimizer, partitioning, and event streaming. `search_documents` has no embedding column so `pgvector` can be added without a new identity model. `learner` stays empty.

## Rules that should survive the next edit

- Never invent a university, identifier, equivalency, grade threshold, or accreditation grant.
- Never set `establishes_course_acceptance` on a category illustration.
- Never mark a program version active because a transfer page mentioned it.
- Never let `credit_recommended` assign `institution_accepts`, or either of those assign `degree_requirement_satisfied`.
- Keep the API role off superuser and off `BYPASSRLS`.
