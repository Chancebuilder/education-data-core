-- Education Data Core V1
-- Extensions, schemas, and application roles.
-- Login passwords are created outside migrations so secrets stay out of SQL history.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;
create extension if not exists unaccent;

create schema if not exists vocab;
create schema if not exists provenance;
create schema if not exists catalog;
create schema if not exists academic;
create schema if not exists alternative;
create schema if not exists policy;
create schema if not exists transfer;
create schema if not exists raw;
create schema if not exists internal;
create schema if not exists api;
create schema if not exists learner;

comment on schema vocab is
  'Controlled vocabularies. Codes are stable; labels may be clarified without changing identity.';
comment on schema provenance is
  'Reusable sources, evidence excerpts, fact links, and the internal research-gap register.';
comment on schema catalog is
  'Institution identity, aliases, external identifiers, status history, and accreditation.';
comment on schema academic is
  'Programs, program versions, institutional courses, and the deferred requirement tree.';
comment on schema alternative is
  'Alternative-credit providers, learning experiences, and third-party credit recommendations.';
comment on schema policy is
  'Destination-institution policies. Typed V1 facts hang off policy versions; generic rules are reserved for a later release.';
comment on schema transfer is
  'Course equivalencies and the future home of articulation agreements. Equivalency is not degree applicability.';
comment on schema raw is
  'Source-faithful import payloads. Not exposed to the public API.';
comment on schema internal is
  'Import batches, change history, and data-quality results. Not exposed to the public API.';
comment on schema api is
  'Stable read contract: functions and views. Clients should use this schema rather than base tables.';
comment on schema learner is
  'Reserved for learner PII, transcripts, consent, and evaluations. Empty in V1. Do not expose it.';

revoke all on schema raw, internal, learner from public;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'edu_anon') then
    create role edu_anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'edu_app') then
    create role edu_app nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'edu_editor') then
    create role edu_editor nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'edu_ingest') then
    create role edu_ingest nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'edu_admin') then
    create role edu_admin nologin;
  end if;
end $$;

comment on role edu_anon is
  'Anonymous read of public educational reference data through the api schema and row level security.';
comment on role edu_app is
  'Authenticated application read of the same public reference data. Learner records are not in V1.';
comment on role edu_editor is
  'Internal editorial read and write, including the research-gap register.';
comment on role edu_ingest is
  'Ingestion service. Can write raw payloads, canonical facts, and import logs.';
comment on role edu_admin is
  'Administrative database role for the education catalog. Not a substitute for a Postgres superuser.';

-- Map Supabase built-in roles when this database is hosted on Supabase.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant edu_anon to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant edu_app to authenticated;
  end if;
end $$;
