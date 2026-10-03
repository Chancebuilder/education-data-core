# Data dictionary

Null means the source did not establish the value. Codes come from `vocab.*`. Dates are inclusive. `recorded_at` / `superseded_at` are knowledge time and are not the API `as_of`.

Seeded factual rows use `verification_status = source_confirmed` and a confidence of `high` or `medium`. `inferred` is a legal status and is unused in the seed. A check rejects an inferred recommendation at high confidence.

## catalog.institutions

Stable identity. `current_status` is a cache, not a history.

| Field | Type | Null | Notes |
| --- | --- | --- | --- |
| id | uuid | no | Canonical id. Not an external identifier. |
| official_name | text | no | Current official name. |
| normalized_name | text | no | Unique. Output of `catalog.normalize_name`. |
| institution_type | text | no | `vocab.institution_type`. |
| country_code | char(2) | no | Default `US`. |
| control | text | yes | Public, private, or for-profit. Null in the V1 extract. Do not infer it. |
| current_status | text | no | Cache only. |
| website_url | text | yes | Must be http(s) when present. |

## catalog.institution_aliases

| Field | Type | Null | Notes |
| --- | --- | --- | --- |
| alias_type | text | no | `official_name`, `former_name`, `abbreviation`, `trade_name`, and other vocab codes. |
| valid_from, valid_to | date | yes | Inclusive. Both null means the alias is not a dated historical name. |
| from_precision, to_precision | text | no | `day`, `month`, `year`, or `unknown`. Year precision makes every day in that year `ambiguous`. |

Excelsior College `valid_to` is 2022-07-31 at day precision. Brandman and Kaplan end years are year precision.

## catalog.institution_identifiers

Crosswalk for UNITID, OPEID, DAPIP, and other issued identifiers. Empty in V1. Unique on type, issuer, value, and the coalesced start date.

## catalog.institution_status_versions

Dated operating status. ITT is `closed` from 2016-09-06. There is no row before that announcement, so 2015 is not documented rather than "open."

## catalog.accreditors and recognition

`catalog.accreditors` is the agency. `catalog.accreditor_recognition_history.status` is whether a recognition authority recognized the agency. That history does not create `catalog.institution_accreditations` rows.

Institution accreditation fields that matter:

| Field | Meaning |
| --- | --- |
| accreditation_status | `accredited`, `participating`, or another vocab code. Not a synonym for "recognized by ED." |
| accreditation_scope | `institutional` or `university_system_participation` in the seed. |
| historical_classification_label | Only when the source used a classification word. No "regional" label is stored. |
| valid_from, valid_to | Both null on the seeded grants. Those rows apply to the current view and are withheld from a historical `as_of`. |
| program_id | Null unless the grant is program-specific. |

## academic.programs and program_versions

| Field | Null in seed | Notes |
| --- | --- | --- |
| degree_type | no | Vocab code such as `bachelor`. |
| cip_code | yes | Not captured. |
| total_credits | yes | Not stated for BS Health Sciences. |
| credit_unit | yes | Not stated. Not defaulted to semester. |
| academic_catalog_year | yes | Not stated. |
| status | no | `unknown`. A mentioned program is not marked active. |
| delivery_modality | yes | Not stated. |

## alternative.credit_recommendations

| Field | Nullability | Temporal behavior | Provenance |
| --- | --- | --- | --- |
| authority_identifier | yes | Stable label such as `SDCM-0160`. | Required `source_document_id`. |
| recommended_credits | yes | Null when the guide excerpt did not state a number. | Not filled from the title. |
| credit_unit | yes | `vocab.credit_unit` when stated. | Never converted. |
| recommended_level, recommended_subject | yes | Null unless the recommendation body stated them. | A word in the title is not a subject. |
| recommendation_start, recommendation_end | start required | Inclusive. SDCM-0160 is 2023-11-01 through 2027-03-31. | Linked evidence excerpt. |

`alternative.recommendation_bodies.awards_credit` and `binds_destination_institutions` stay false for ACE and NCCRS.

## policy.policy_facts

| Field | Meaning |
| --- | --- |
| fact_kind | Controlled kind: transfer maximum, residency, grade, course age, alternative-credit limit, and the other vocab codes. |
| statement | The sourced sentence. Required. |
| limit_value, limit_unit | The sourced cap. Unit `credits_unspecified` means the page did not name semester or quarter. |
| context_value, context_label | A second sourced number, such as SNHU's published 120. Not a calculated remainder. |
| grade_threshold | Null when the page says a threshold exists but does not state it. |
| acceptance_strength | `none`, `category_illustrative`, `category_explicit`, `provider`, or `course`. |
| establishes_course_acceptance | True only for `provider` or `course` strength. False on every seeded fact. |
| source_document_id | Required. A policy without a source cannot be inserted. |

`policy.policy_fact_providers.relationship = addresses` is not acceptance.

## transfer.course_equivalencies

Destination-authoritative mappings only. `source_document_id` is required. `direct_course` requires `destination_course_version_id`. The seed has zero rows. An equivalency does not set degree applicability.

## provenance.source_documents

| Field | Notes |
| --- | --- |
| source_url | Nullable. Must be http(s) when present. |
| source_type | Vocab: registrar policy, accreditor directory, ACE guide, and others. |
| authority_scope | How far the publisher can speak. `discovery_only` for the research report. |
| retrieved_at | 2026-10-03 for the V1 extract. |
| extraction_method | `deep_research_report` for this load. |
| published_at | Null when the page did not show a publication date. |

## provenance.research_gaps

Internal queue. `resolved_at` is set only when status is resolved. Public API roles cannot select this table or call `api.list_research_gaps`.

## Derived values

`catalog.search_documents.search_text` is rebuilt from names and titles. `api.evaluate_transfer` distinctions are computed at read time and are not stored. `practical_max_transfer` is always null in V1.
