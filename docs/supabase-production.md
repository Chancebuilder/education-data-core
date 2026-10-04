# Hosted API deployment

The production API gateway is a Supabase Edge Function named `education-data-core`.

Base path: `/functions/v1/education-data-core/v1`.

The Edge Function forwards the stable HTTP contract to PostgreSQL functions in the `api` schema using the project's anonymous role. Database RLS and grants remain the authorization boundary. Never use a service-role key in this function.

## Production data boundary

The public API exposes the approved `api` contract. `raw`, `internal`, and `learner` are not application-facing API schemas. `provenance.research_gaps` remains staff-only.

## Required verification

After deployment verify health, institution/provider search, recommendation lookup for `SDCM-0160`, and transfer evaluation against Thomas Edison State University on 2024-06-01.

The transfer test must preserve the evidence boundary: an ACE recommendation may be documented while institution acceptance and degree applicability remain `not_documented`, and no equivalency may be inferred.
