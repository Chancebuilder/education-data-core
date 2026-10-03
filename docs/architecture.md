# Architecture

The Education Data Core is a PostgreSQL 16 database plus a thin HTTP façade. Canonical facts live in dated, sourced tables. Clients call the `api` schema. They do not read `raw` or `internal`.

## Layers

| Schema | Role |
| --- | --- |
| `vocab` | Controlled codes. Application code does not invent status strings. |
| `provenance` | Source documents, evidence excerpts, fact links, and the internal research-gap queue. |
| `catalog` | Institutions, aliases, external identifiers, status history, accreditors, accreditation, lexical search documents. |
| `academic` | Programs, program versions, destination courses, and empty requirement trees reserved for a later audit. |
| `alternative` | Recommendation bodies, providers, learning experiences, and credit recommendations. |
| `policy` | Institution policies, versions, typed facts, and empty generic rule tables. |
| `transfer` | Course equivalencies. Articulation agreements exist and are empty. |
| `raw` | The original JSON payload, keyed by family and SHA-256. |
| `internal` | Import batches, change log, and data-quality checks. |
| `api` | Stable functions and two views. This is the contract. |
| `learner` | Reserved and empty. No learner wallet in V1. |

`scripts/ingest/ingest.ts` is the staging step. It reads `data/raw/v1_research_extract.json`, upserts canonical rows, and stores the payload in `raw.source_payloads`.

## Identity

Every canonical row uses a UUID primary key. Ingestion assigns UUID v5 values from the namespace `8c1d1a4e-5b2f-4c3a-9e7d-6f0a1b2c3d4e` and the name `kind:key`. A second load of the same extract hits `ON CONFLICT (id) DO UPDATE` only when a column actually changed.

External identifiers (UNITID, OPEID, DAPIP, and similar) belong on `catalog.institution_identifiers`. The October 3, 2026 extract did not establish any of them, so that table is empty. The API reports `external_identifiers_status = not_documented`. Those identifiers are not invented.

## Time

`valid_from` and `valid_to` are inclusive valid time. `recorded_at` and `superseded_at` are knowledge time. API `as_of` is valid time.

`api.temporal_coverage` returns:

- `current_view` when `as_of` is null. Non-superseded rows are returned.
- `undated` when both bounds are null. Undated facts are withheld from a historical `as_of`.
- `ambiguous` when a year-precision bound covers the asked year. The stored month and day are a convention and are not a calendar day.
- `match` when the date is inside a day-precision interval.
- `out` when the date is outside the interval. Out-of-range rows are omitted from the applied set. Use `get_policy_history` or `get_institution_history` to see them.

`catalog.institutions.current_status` is a cache for the current view. Historical status comes from `institution_status_versions`. A closed institution with no earlier operating row returns `not_documented` for a date before the closure fact.

## Distinctions the model will not collapse

These are different facts, stored in different tables, and returned as different fields:

1. Credit recommendation (`alternative.credit_recommendations`). ACE and NCCRS have `awards_credit = false` and `binds_destination_institutions = false`.
2. Institutional acceptance (`policy.policy_facts.establishes_course_acceptance`, plus `policy_fact_providers.relationship`).
3. Course equivalency (`transfer.course_equivalencies`). V1 seed has none.
4. Degree applicability. `api.evaluate_transfer` always returns `degree_requirement_satisfied = not_documented`, including when a fixture inserts an equivalency.

`acceptance_strength = category_illustrative` cannot set `establishes_course_acceptance`. A provider link of `addresses` means the policy mentions the provider. It is not acceptance.

`api.credits_are_comparable` is true only when both sides name the same unit. Semester credits, quarter credits, and `credits_unspecified` are not converted. A second number stored beside a cap, such as SNHU's 120, is `context_value`. It is not a derived remainder.

## Provenance

`provenance.source_documents` holds the document once. `provenance.evidence` holds the excerpt or summary. `provenance.fact_evidence_links` points a fact row at that evidence. Profile and policy calls accept `include_provenance=true`. `api.get_record_provenance` refuses `raw`, `internal`, `learner`, and the research-gap queue.

Seeded facts use `verification_status = source_confirmed`. Nothing in the extract is marked `verified` or `inferred`. An inferred recommendation cannot be stored at high confidence.

## Search

Institution, program, course, and provider search use normalized names, aliases, and `pg_trgm`. `catalog.search_documents` is a lexical index rebuilt on each ingest. It has no embedding column. `pgvector` can be added later without changing institution or recommendation identity.

## Security

`edu_anon` and `edu_app` can read public catalog, academic, alternative, policy, transfer, vocab, and provenance tables except `research_gaps`. They can execute `api` functions except `rebuild_search_documents` and `list_research_gaps`.

`edu_editor`, `edu_ingest`, and `edu_admin` can read the gap queue, raw payloads, and the change log, and can write canonical tables.

The HTTP process logs in as `edu_api` (`NOBYPASSRLS`, not a superuser) and runs `SET ROLE edu_app`. It refuses to start if the login role is a superuser or bypasses row level security. Row level security is forced, so a table owner does not skip policies unless the role is superuser.

On Supabase, grant `edu_anon` to `anon` and `edu_app` to `authenticated`, and expose only the `api` schema. The service role bypasses RLS and must stay off clients.

## What V1 deliberately leaves empty

`academic.requirement_nodes`, `academic.requirement_bindings`, `policy.policy_rules`, `policy.rule_conditions`, `policy.rule_effects`, `transfer.articulation_agreements`, and `learner` are present so later work does not have to rename institutions, programs, or recommendations. They are not populated from the extract, and the evaluator does not treat their emptiness as "no requirements" or "credit applies."
