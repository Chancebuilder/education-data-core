# API

Call `api` functions in SQL, or the HTTP routes below. The HTTP service returns the function's JSON unchanged. Dates are `YYYY-MM-DD`. UUIDs are canonical ids, not UNITIDs.

`as_of` is valid time. Omit it for the current non-superseded view. Undated facts are included in that current view and withheld from a historical date, where they appear in `not_applied_to_as_of` or `undated_policy_context`.

`include_provenance=true` adds evidence links (URL, retrieval time, excerpt, extraction method) on profiles and policies. Provenance is omitted by default so list calls stay small.

Null and the string `not_documented` both mean the extract did not establish the fact. The service does not guess.

## Errors

| HTTP | PostgreSQL | When |
| --- | --- | --- |
| 404 | `P0002` | Institution, program version, learning experience, or source id is unknown. |
| 422 | `22023`, `22P02`, `22007`, `22008` | A required argument is missing, or a UUID or date is malformed. |
| 403 | `42501` | The role cannot read the research-gap queue or an internal schema. |
| 500 | other | Unexpected. The message is generic and does not echo the database error. |

## Health

`GET /v1/health` → `api.health()`

```json
{ "ok": true, "api_version": "v1", "service": "education-data-core" }
```

## Institutions

`GET /v1/institutions?q=&status=&country=&limit=&offset=`

`api.search_institutions(q, status, country, limit, offset)`

Matches the official name, normalized name, and aliases. `tesu`, `excelsior college`, `brandman`, and `presque isle` resolve to the current institution. An empty `q` lists institutions. `control` is null in V1.

`GET /v1/institutions/{id}?as_of=&include_provenance=`

`api.get_institution_profile(id, as_of, include_provenance)`

Returns the display name for that date, aliases, identifiers (empty array, with `external_identifiers_status = not_documented`), status, and embedded accreditation. Excelsior on `2020-06-01` displays Excelsior College. On `2022-08-01` it displays Excelsior University. UMass Global during 2021 is `alias_ambiguous` because both the Brandman end and the UMass start are year precision.

`GET /v1/institutions/{id}/history` returns alias, status, and accreditation history without applying one `as_of`.

`GET /v1/institutions/{id}/accreditation?as_of=&include_history=`

Current TESU accreditation is MSCHE, undated, so a 2014 query returns `applied: []` and lists MSCHE under `not_applied_to_as_of`. ITT returns no accreditation. UMPI's scope is `university_system_participation`.

## Programs

`GET /v1/institutions/{id}/programs?degree_type=&as_of=&modality=`

`GET /v1/programs?q=&institution_id=&degree_type=&limit=&offset=`

`GET /v1/program-versions/{id}/requirements`

The Health Sciences version returns `total_credits: null`, `requirement_status: not_documented`, and `practical_max_transfer_status: not_calculated`. Related policy facts can include the sourced "up to 113" statement. That number is `credits_unspecified` and does not satisfy the program.

## Policies

`GET /v1/institutions/{id}/policies?as_of=&program_id=&include_provenance=`

`api.get_transfer_policy`. TESU on `2020-06-01` does not apply the 90-credit rule (`valid_from` 2021-01-01). On `2024-01-01` that fact is applied, `limit_unit` is `credits_unspecified`, and `establishes_course_acceptance` is false. The undated ACE/NCCRS transcript-routing policy is a separate fact and is withheld from a dated query.

`GET /v1/institutions/{id}/policy-history?policy_kind=` returns versions, including those outside one date.

`GET /v1/institutions/{id}/alternative-credit-rules?as_of=&provider_id=` returns alternative-credit facts and provider links. `relationship: addresses` is not acceptance.

## Courses, providers, recommendations

`GET /v1/courses` searches destination course versions. V1 has none, so the total is 0.

`GET /v1/providers?q=` finds Study.com, Sophia Learning, StraighterLine, and Coopersmith. `straighter` matches StraighterLine.

`GET /v1/providers/{id}` and `GET /v1/providers/{id}/courses?q=&as_of=`

`GET /v1/recommendations?authority_identifier=&provider_id=&learning_experience_id=&as_of=`

`api.get_credit_recommendations`. Each row sets `institution_accepts` to `not_derived`. Recommended credits for `SDCM-0160` are null. The recommendation period is inclusive.

## Equivalencies

`GET /v1/equivalencies?destination_institution_id=&source_experience_version_id=&program_version_id=&as_of=`

`api.get_known_equivalencies`. An empty `data` array means no destination-authoritative equivalency is loaded. It is not an elective and it is not a rejection. Every returned row, when one exists, still has `degree_requirement_satisfied: not_documented`.

## Evaluate

`POST /v1/transfer/evaluate`

```json
{
  "destination_institution_id": "6456926d-1b81-5dd4-a63d-7eae886ecb96",
  "completed_on": "2024-06-01",
  "authority_identifier": "SDCM-0160"
}
```

`learning_experience_version_id` may be sent instead of `authority_identifier`. `program_version_id`, `grade`, and `policy_as_of` are optional. `grade_check` stays `not_documented` because no seeded threshold is a number the evaluator can apply.

Response `data.distinctions` for TESU and SDCM-0160 on 2024-06-01:

```json
{
  "credit_recommended": true,
  "institution_accepts": "not_documented",
  "acceptance_established": false,
  "equivalency_documented": false,
  "equivalency_type": null,
  "degree_requirement_satisfied": "not_documented"
}
```

`credit_recommended` is `false` before 2023-11-01 and after 2027-03-31, and `true` on both endpoints. The same call at Charter Oak stays `institution_accepts: not_documented` even though the partner policy addresses Study.com.

Acceptance becomes `conditional` or `accepted` only when a policy fact has `establishes_course_acceptance`, strength `provider` or `course`, a covering valid time, and a provider link of `accepts` or `eligible_method` (or course strength). The seed has no such fact. A rolled-back test inserts one and still receives `degree_requirement_satisfied: not_documented` after a direct equivalency is added.

## Provenance and gaps

`GET /v1/provenance?fact_schema=&fact_table=&fact_id=`

`GET /v1/sources/{id}`

`GET /v1/research-gaps` calls `api.list_research_gaps` and returns 403 for `edu_app`. Editors query the table directly.

## SQL examples

```sql
select api.search_institutions('tesu', null, null, 5, 0);
select api.get_institution_profile(:id, date '2020-06-01', true);
select api.evaluate_transfer(:id, date '2024-06-01', null, 'SDCM-0160', null, null, null);
select * from api.v_recommendation_acceptance_boundary;
```

`api.v_institutions_current` is the identity cache only. Accreditation and policy stay on their functions.
