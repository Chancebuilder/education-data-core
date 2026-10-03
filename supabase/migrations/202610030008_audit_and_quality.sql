-- Knowledge-time bookkeeping, import logs, and structural data-quality checks.

create or replace function internal.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function internal.log_change()
returns trigger
language plpgsql
security definer
set search_path = internal, pg_temp
as $$
declare
  v_id uuid;
  v_row jsonb;
begin
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;
  begin
    v_id := (v_row ->> 'id')::uuid;
  exception
    when others then
      v_id := null;
  end;
  insert into internal.change_log (schema_name, table_name, row_id, operation, row_snapshot)
  values (tg_table_schema, tg_table_name, v_id, tg_op, v_row);
  return coalesce(new, old);
end;
$$;

create table raw.source_payloads (
  id uuid primary key default gen_random_uuid(),
  source_family text not null,
  payload jsonb not null,
  payload_sha256 text not null,
  retrieved_at timestamptz,
  loaded_at timestamptz not null default now(),
  unique (source_family, payload_sha256)
);

comment on table raw.source_payloads is
  'Source-faithful JSON snapshots. Public API roles cannot read this schema.';

create table internal.import_batches (
  id uuid primary key default gen_random_uuid(),
  source_family text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null,
  records_read integer,
  records_upserted integer,
  notes text,
  payload_sha256 text,
  constraint import_batches_status_chk check (
    status in ('running', 'succeeded', 'failed')
  )
);

create table internal.change_log (
  id bigint generated always as identity primary key,
  schema_name text not null,
  table_name text not null,
  row_id uuid,
  operation text not null,
  changed_at timestamptz not null default now(),
  row_snapshot jsonb
);

create index change_log_row_idx
  on internal.change_log (schema_name, table_name, row_id, changed_at desc);

comment on table internal.change_log is
  'Append-only record of canonical writes. Not a substitute for valid time. Public roles cannot read it.';

do $$
declare
  r record;
begin
  for r in
    select table_schema, table_name
    from information_schema.columns
    where column_name = 'updated_at'
      and table_schema in (
        'catalog', 'academic', 'alternative', 'policy', 'provenance', 'transfer'
      )
  loop
    execute format(
      'drop trigger if exists %I on %I.%I',
      r.table_name || '_set_updated_at',
      r.table_schema,
      r.table_name
    );
    execute format(
      'create trigger %I before update on %I.%I for each row execute function internal.set_updated_at()',
      r.table_name || '_set_updated_at',
      r.table_schema,
      r.table_name
    );
  end loop;

  for r in
    select c.table_schema, c.table_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema
     and t.table_name = c.table_name
    where c.column_name = 'id'
      and c.data_type = 'uuid'
      and t.table_type = 'BASE TABLE'
      and c.table_schema in (
        'catalog', 'academic', 'alternative', 'policy', 'provenance', 'transfer'
      )
  loop
    execute format(
      'drop trigger if exists %I on %I.%I',
      r.table_name || '_log_change',
      r.table_schema,
      r.table_name
    );
    execute format(
      'create trigger %I after insert or update or delete on %I.%I for each row execute function internal.log_change()',
      r.table_name || '_log_change',
      r.table_schema,
      r.table_name
    );
  end loop;
end $$;

create or replace function internal.run_data_quality_checks()
returns table (
  check_code text,
  severity text,
  object_ref text,
  detail text
)
language sql
stable
set search_path = internal, catalog, academic, alternative, policy, transfer, provenance, public, pg_temp
as $$
  select
    'inferred_fact'::text,
    'error'::text,
    format('%s.%s:%s', schema_name, table_name, row_id),
    'Inferred verification is present. V1 does not treat inference as fact.'
  from (
    select 'alternative' as schema_name, 'credit_recommendations' as table_name, id::text as row_id
    from alternative.credit_recommendations
    where verification_status = 'inferred'
    union all
    select 'policy', 'policy_facts', id::text
    from policy.policy_facts
    where verification_status = 'inferred'
    union all
    select 'policy', 'policy_versions', id::text
    from policy.policy_versions
    where verification_status = 'inferred'
    union all
    select 'transfer', 'course_equivalencies', id::text
    from transfer.course_equivalencies
    where verification_status = 'inferred'
    union all
    select 'catalog', 'institution_accreditations', id::text
    from catalog.institution_accreditations
    where verification_status = 'inferred'
  ) inferred
  union all
  select
    'established_acceptance_without_provider_link',
    'error',
    f.id::text,
    'establishes_course_acceptance is true without a provider or course-strength link.'
  from policy.policy_facts f
  where f.establishes_course_acceptance
    and f.acceptance_strength = 'provider'
    and not exists (
      select 1
      from policy.policy_fact_providers fp
      where fp.policy_fact_id = f.id
        and fp.relationship in ('accepts', 'eligible_method')
    )
  union all
  select
    'direct_equivalency_missing_course',
    'error',
    e.id::text,
    'direct_course equivalency is missing a destination course version.'
  from transfer.course_equivalencies e
  where e.equivalency_type = 'direct_course'
    and e.destination_course_version_id is null
  union all
  select
    'equivalency_missing_source',
    'error',
    e.id::text,
    'Equivalency has no source document.'
  from transfer.course_equivalencies e
  where e.source_document_id is null
  union all
  select
    'policy_missing_source',
    'error',
    v.id::text,
    'Policy version has no source document.'
  from policy.policy_versions v
  where v.source_document_id is null
  union all
  select
    'recommendation_missing_source',
    'error',
    c.id::text,
    'Credit recommendation has no source document.'
  from alternative.credit_recommendations c
  where c.source_document_id is null
  union all
  select
    'accreditation_missing_source',
    'error',
    a.id::text,
    'Accreditation row has no source document.'
  from catalog.institution_accreditations a
  where a.source_document_id is null
  union all
  select
    'impossible_alias_dates',
    'error',
    a.id::text,
    'Alias valid_to is earlier than valid_from.'
  from catalog.institution_aliases a
  where a.valid_from is not null
    and a.valid_to is not null
    and a.valid_to < a.valid_from
  union all
  select
    'negative_recommendation_credits',
    'error',
    c.id::text,
    'Recommended credits are negative.'
  from alternative.credit_recommendations c
  where c.recommended_credits < 0
  union all
  select
    'regional_label_present',
    'warning',
    a.id::text,
    'historical_classification_label contains regional. Confirm the source used that word and that it was not rewritten into a current quality rank.'
  from catalog.institution_accreditations a
  where a.historical_classification_label ilike '%regional%'
  union all
  select
    'similar_institution_names',
    'warning',
    i1.id::text || ',' || i2.id::text,
    i1.official_name || ' / ' || i2.official_name
  from catalog.institutions i1
  join catalog.institutions i2
    on i1.id < i2.id
   and similarity(i1.normalized_name, i2.normalized_name) > 0.72
  union all
  select
    'provider_without_learning_experiences',
    'info',
    p.id::text,
    p.official_name || ' has provider identity only. Course-level records were not ingested.'
  from alternative.providers p
  where not exists (
    select 1 from alternative.learning_experiences le where le.provider_id = p.id
  );
$$;

comment on function internal.run_data_quality_checks() is
  'Structural checks. error fails validation. warning needs a person. info describes expected V1 gaps such as providers that do not yet have course rows.';
