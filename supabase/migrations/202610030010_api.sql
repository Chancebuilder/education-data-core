-- Stable V1 contract. Clients and the HTTP service should call api.* rather than base tables.
-- as_of is valid time with inclusive dates. It is not knowledge time.
-- Undated assertions (both bounds null) are current-only. They are not applied to a historical as-of date.

create or replace function api.temporal_coverage(
  valid_from date,
  valid_to date,
  from_precision text,
  to_precision text,
  as_of date
)
returns text
language plpgsql
immutable
set search_path = api, public, pg_temp
as $$
declare
  start_state text;
  end_state text;
  bound_year integer;
begin
  if as_of is null then
    return 'current_view';
  end if;

  if valid_from is null and valid_to is null then
    return 'undated';
  end if;

  if valid_from is null then
    start_state := 'open';
  elsif from_precision = 'year' then
    bound_year := extract(year from valid_from)::integer;
    if as_of < make_date(bound_year, 1, 1) then
      start_state := 'before';
    elsif as_of > make_date(bound_year, 12, 31) then
      start_state := 'after';
    else
      start_state := 'ambiguous';
    end if;
  elsif from_precision = 'month' then
    if as_of < date_trunc('month', valid_from)::date then
      start_state := 'before';
    elsif as_of >= (date_trunc('month', valid_from)::date + interval '1 month')::date then
      start_state := 'after';
    else
      start_state := 'ambiguous';
    end if;
  else
    if as_of < valid_from then
      start_state := 'before';
    else
      start_state := 'after';
    end if;
  end if;

  if start_state = 'before' then
    return 'out';
  end if;

  if valid_to is null then
    end_state := 'open';
  elsif to_precision = 'year' then
    bound_year := extract(year from valid_to)::integer;
    if as_of < make_date(bound_year, 1, 1) then
      end_state := 'inside';
    elsif as_of > make_date(bound_year, 12, 31) then
      end_state := 'after';
    else
      end_state := 'ambiguous';
    end if;
  elsif to_precision = 'month' then
    if as_of < date_trunc('month', valid_to)::date then
      end_state := 'inside';
    elsif as_of >= (date_trunc('month', valid_to)::date + interval '1 month')::date then
      end_state := 'after';
    else
      end_state := 'ambiguous';
    end if;
  else
    if as_of > valid_to then
      end_state := 'after';
    else
      end_state := 'inside';
    end if;
  end if;

  if end_state = 'after' then
    return 'out';
  end if;
  if start_state = 'ambiguous' or end_state = 'ambiguous' then
    return 'ambiguous';
  end if;
  return 'match';
end;
$$;

comment on function api.temporal_coverage(date, date, text, text, date) is
  'Returns match, ambiguous, out, undated, or current_view. Year precision is ambiguous for every day inside that year. Both bounds null is undated and must not be treated as true on an earlier as-of date.';

create or replace function api.format_temporal(value date, date_precision text)
returns text
language sql
immutable
as $$
  select case
    when value is null or date_precision = 'unknown' then null
    when date_precision = 'year' then extract(year from value)::text
    when date_precision = 'month' then to_char(value, 'YYYY-MM')
    else to_char(value, 'YYYY-MM-DD')
  end;
$$;

create or replace function api.temporal_object(
  valid_from date,
  valid_to date,
  from_precision text,
  to_precision text,
  as_of date,
  recorded_at timestamptz,
  superseded_at timestamptz
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'valid_from', valid_from,
    'valid_to', valid_to,
    'from_precision', from_precision,
    'to_precision', to_precision,
    'valid_from_display', api.format_temporal(valid_from, from_precision),
    'valid_to_display', api.format_temporal(valid_to, to_precision),
    'coverage', case
      when as_of is null then 'current_view'
      else api.temporal_coverage(valid_from, valid_to, from_precision, to_precision, as_of)
    end,
    'recorded_at', recorded_at,
    'superseded_at', superseded_at,
    'as_of_interpretation', 'valid_time_inclusive'
  );
$$;

create or replace function api.envelope_meta(as_of date)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'api_version', 'v1',
    'policy_as_of', as_of,
    'as_of_interpretation', case
      when as_of is null then 'current_non_superseded_records'
      else 'valid_time_inclusive'
    end,
    'data_snapshot_at', now(),
    'credit_units_note', 'Semester and quarter credits are never converted. Unspecified means the source did not name the unit.'
  );
$$;

create or replace function api.credits_are_comparable(left_unit text, right_unit text)
returns boolean
language sql
immutable
as $$
  select left_unit is not null
    and right_unit is not null
    and left_unit = right_unit
    and left_unit in (
      'semester', 'quarter', 'clock_hour',
      'semester_credit', 'quarter_credit'
    );
$$;

comment on function api.credits_are_comparable(text, text) is
  'True only when both units are the same named unit. unspecified, unknown, semester versus quarter, and semester versus semester_credit are not comparable. This function does not convert.';

create or replace function api.provenance_for(
  fact_schema text,
  fact_table text,
  fact_id uuid
)
returns jsonb
language sql
stable
set search_path = api, provenance, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'evidence_id', e.id,
    'link_role', l.link_role,
    'evidence_summary', e.evidence_summary,
    'evidence_excerpt', e.evidence_excerpt,
    'section_locator', e.section_locator,
    'page_number', e.page_number,
    'verification_status', e.verification_status,
    'confidence', e.confidence,
    'extraction_method', e.extraction_method,
    'source_document_id', s.id,
    'source_title', s.source_title,
    'source_url', s.source_url,
    'source_type', s.source_type,
    'publisher', s.publisher,
    'authority_scope', s.authority_scope,
    'published_at', s.published_at,
    'retrieved_at', s.retrieved_at,
    'archive_url', s.archive_url
  ) order by s.source_title), '[]'::jsonb)
  from provenance.fact_evidence_links l
  join provenance.evidence e on e.id = l.evidence_id
  join provenance.source_documents s on s.id = e.source_document_id
  where l.fact_schema = provenance_for.fact_schema
    and l.fact_table = provenance_for.fact_table
    and l.fact_id = provenance_for.fact_id;
$$;

create or replace function api.health()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'ok', true,
    'api_version', 'v1',
    'service', 'education-data-core'
  );
$$;

create or replace function api.rebuild_search_documents()
returns integer
language plpgsql
volatile
set search_path = api, catalog, academic, alternative, pg_temp
as $$
declare
  v_count integer;
begin
  delete from catalog.search_documents;
  insert into catalog.search_documents (entity_schema, entity_table, entity_id, search_text)
  select 'catalog', 'institutions', i.id,
         concat_ws(' ', i.official_name, i.normalized_name, i.current_status)
  from catalog.institutions i
  union all
  select 'catalog', 'institution_aliases', a.id, a.alias
  from catalog.institution_aliases a
  where a.superseded_at is null
  union all
  select 'academic', 'programs', p.id,
         concat_ws(' ', p.official_program_family_name, p.degree_type, p.program_category)
  from academic.programs p
  union all
  select 'academic', 'course_versions', c.id,
         concat_ws(' ', c.course_code, c.official_title, c.subject)
  from academic.course_versions c
  where c.superseded_at is null
  union all
  select 'alternative', 'providers', p.id, p.official_name
  from alternative.providers p
  union all
  select 'alternative', 'learning_experiences', le.id,
         concat_ws(' ', le.canonical_title, le.provider_course_identifier)
  from alternative.learning_experiences le;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function api.rebuild_search_documents() is
  'Rebuilds lexical search documents. Embeddings are intentionally absent so pgvector can be added later on catalog.search_documents.';

create or replace function api.search_institutions(
  q text default null,
  status_filter text default null,
  country text default null,
  result_limit integer default 20,
  result_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = api, catalog, public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(result_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(result_offset, 0), 0);
  v_q text := nullif(catalog.normalize_name(coalesce(q, '')), '');
  v_rows jsonb;
  v_total integer;
begin
  with scored as (
    select
      i.id,
      i.official_name,
      i.institution_type,
      i.country_code,
      i.control,
      i.current_status,
      i.website_url,
      greatest(
        case
          when v_q is null then 0
          when i.normalized_name = v_q then 1
          when i.normalized_name like '%' || v_q || '%' then 0.9
          else similarity(i.normalized_name, v_q)
        end,
        coalesce((
          select max(
            case
              when a.normalized_alias = v_q then 1
              when a.normalized_alias like '%' || v_q || '%' then 0.93
              else similarity(a.normalized_alias, v_q)
            end
          )
          from catalog.institution_aliases a
          where a.institution_id = i.id
            and a.superseded_at is null
        ), 0),
        coalesce((
          select max(1.0)
          from catalog.institution_identifiers n
          where n.institution_id = i.id
            and n.superseded_at is null
            and lower(n.identifier_value) = lower(coalesce(q, ''))
        ), 0)
      ) as score
    from catalog.institutions i
    where (status_filter is null or i.current_status = status_filter)
      and (country is null or i.country_code = country)
  ),
  filtered as (
    select * from scored
    where v_q is null or score >= 0.28
  )
  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id,
      'official_name', page.official_name,
      'institution_type', page.institution_type,
      'country_code', page.country_code,
      'control', page.control,
      'current_status', page.current_status,
      'website_url', page.website_url,
      'match_score', round(page.score::numeric, 3)
    )), '[]'::jsonb)
  into v_total, v_rows
  from (
    select *
    from filtered
    order by
      case when v_q is null then 0 else score end desc,
      official_name
    limit v_limit offset v_offset
  ) page
  right join (select 1) keep on true
  left join filtered page_count_guard on false;

  -- The join above is a bad way to get both count and page. Compute them separately.
  select count(*)::integer into v_total from (
    select 1
    from catalog.institutions i
    where (status_filter is null or i.current_status = status_filter)
      and (country is null or i.country_code = country)
      and (
        v_q is null
        or i.normalized_name = v_q
        or i.normalized_name like '%' || v_q || '%'
        or similarity(i.normalized_name, v_q) >= 0.28
        or exists (
          select 1 from catalog.institution_aliases a
          where a.institution_id = i.id
            and a.superseded_at is null
            and (
              a.normalized_alias = v_q
              or a.normalized_alias like '%' || v_q || '%'
              or similarity(a.normalized_alias, v_q) >= 0.28
            )
        )
        or exists (
          select 1 from catalog.institution_identifiers n
          where n.institution_id = i.id
            and n.superseded_at is null
            and lower(n.identifier_value) = lower(coalesce(q, ''))
        )
      )
  ) matched;

  with scored as (
    select
      i.id,
      i.official_name,
      i.institution_type,
      i.country_code,
      i.control,
      i.current_status,
      i.website_url,
      greatest(
        case
          when v_q is null then 0
          when i.normalized_name = v_q then 1
          when i.normalized_name like '%' || v_q || '%' then 0.9
          else similarity(i.normalized_name, v_q)
        end,
        coalesce((
          select max(
            case
              when a.normalized_alias = v_q then 1
              when a.normalized_alias like '%' || v_q || '%' then 0.93
              else similarity(a.normalized_alias, v_q)
            end
          )
          from catalog.institution_aliases a
          where a.institution_id = i.id and a.superseded_at is null
        ), 0),
        case when exists (
          select 1 from catalog.institution_identifiers n
          where n.institution_id = i.id
            and n.superseded_at is null
            and lower(n.identifier_value) = lower(coalesce(q, ''))
        ) then 1 else 0 end
      ) as score
    from catalog.institutions i
    where (status_filter is null or i.current_status = status_filter)
      and (country is null or i.country_code = country)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'official_name', s.official_name,
    'institution_type', s.institution_type,
    'country_code', s.country_code,
    'control', s.control,
    'current_status', s.current_status,
    'website_url', s.website_url,
    'match_score', round(s.score::numeric, 3)
  )), '[]'::jsonb)
  into v_rows
  from (
    select *
    from scored
    where v_q is null or score >= 0.28
    order by case when v_q is null then 0 else score end desc, official_name
    limit v_limit offset v_offset
  ) s;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', v_rows,
    'page', jsonb_build_object(
      'limit', v_limit,
      'offset', v_offset,
      'total', v_total,
      'next_offset', case when v_offset + v_limit < v_total then v_offset + v_limit else null end
    )
  );
end;
$$;

create or replace function api.get_institution_accreditation(
  institution_id uuid,
  as_of date default null,
  include_history boolean default false
)
returns jsonb
language plpgsql
stable
set search_path = api, catalog, pg_temp
as $$
declare
  v_applied jsonb := '[]'::jsonb;
  v_withheld jsonb := '[]'::jsonb;
  v_history jsonb := '[]'::jsonb;
  r record;
  v_coverage text;
begin
  if not exists (select 1 from catalog.institutions i where i.id = institution_id) then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  for r in
    select
      a.id,
      a.accreditation_status,
      a.accreditation_scope,
      a.historical_classification_label,
      a.notes,
      a.valid_from,
      a.valid_to,
      a.from_precision,
      a.to_precision,
      a.recorded_at,
      a.superseded_at,
      a.verification_status,
      a.confidence,
      a.program_id,
      c.official_name as accreditor_name,
      c.acronym as accreditor_acronym,
      c.id as accreditor_id
    from catalog.institution_accreditations a
    join catalog.accreditors c on c.id = a.accreditor_id
    where a.institution_id = get_institution_accreditation.institution_id
      and a.superseded_at is null
    order by c.official_name, a.valid_from nulls last
  loop
    v_coverage := case
      when as_of is null then 'current_view'
      else api.temporal_coverage(r.valid_from, r.valid_to, r.from_precision, r.to_precision, as_of)
    end;
    v_history := v_history || jsonb_build_array(jsonb_build_object(
      'id', r.id,
      'accreditor_id', r.accreditor_id,
      'accreditor_name', r.accreditor_name,
      'accreditor_acronym', r.accreditor_acronym,
      'accreditation_status', r.accreditation_status,
      'accreditation_scope', r.accreditation_scope,
      'historical_classification_label', r.historical_classification_label,
      'program_id', r.program_id,
      'notes', r.notes,
      'verification_status', r.verification_status,
      'confidence', r.confidence,
      'temporal', api.temporal_object(
        r.valid_from, r.valid_to, r.from_precision, r.to_precision,
        as_of, r.recorded_at, r.superseded_at
      )
    ));
    if as_of is null or v_coverage in ('match', 'ambiguous') then
      v_applied := v_applied || jsonb_build_array(v_history -> -1);
    elsif v_coverage = 'undated' then
      v_withheld := v_withheld || jsonb_build_array(v_history -> -1);
    end if;
  end loop;

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', jsonb_build_object(
      'institution_id', institution_id,
      'applied', v_applied,
      'not_applied_to_as_of', v_withheld,
      'history', case when include_history then v_history else null end,
      'history_included', include_history
    )
  );
end;
$$;

create or replace function api.get_institution_profile(
  institution_id uuid,
  as_of date default null,
  include_provenance boolean default false
)
returns jsonb
language plpgsql
stable
set search_path = api, catalog, academic, provenance, pg_temp
as $$
declare
  v_inst catalog.institutions%rowtype;
  v_display text;
  v_basis text;
  v_also jsonb;
  v_aliases jsonb;
  v_identifiers jsonb;
  v_identifier_status text;
  v_status jsonb;
  v_accreditation jsonb;
  v_program_count integer;
  v_unknowns text[] := array[]::text[];
  v_provenance jsonb;
begin
  select * into v_inst from catalog.institutions i where i.id = institution_id;
  if not found then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  if v_inst.control is null then
    v_unknowns := array_append(v_unknowns, 'institutional_control');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'alias', a.alias,
    'alias_type', a.alias_type,
    'verification_status', a.verification_status,
    'confidence', a.confidence,
    'temporal', api.temporal_object(
      a.valid_from, a.valid_to, a.from_precision, a.to_precision,
      as_of, a.recorded_at, a.superseded_at
    )
  ) order by a.alias_type, a.alias), '[]'::jsonb)
  into v_aliases
  from catalog.institution_aliases a
  where a.institution_id = v_inst.id
    and a.superseded_at is null;

  if as_of is null then
    v_display := v_inst.official_name;
    v_basis := 'current_official_name';
    v_also := '[]'::jsonb;
  else
    select a.alias,
           'alias_' || api.temporal_coverage(a.valid_from, a.valid_to, a.from_precision, a.to_precision, as_of)
    into v_display, v_basis
    from catalog.institution_aliases a
    where a.institution_id = v_inst.id
      and a.superseded_at is null
      and a.alias_type in ('official_name', 'former_name')
      and api.temporal_coverage(a.valid_from, a.valid_to, a.from_precision, a.to_precision, as_of)
        in ('match', 'ambiguous')
    order by
      case api.temporal_coverage(a.valid_from, a.valid_to, a.from_precision, a.to_precision, as_of)
        when 'match' then 0 else 1 end,
      case a.alias_type when 'official_name' then 0 else 1 end,
      a.valid_from desc nulls last
    limit 1;

    select coalesce(jsonb_agg(a.alias order by a.alias), '[]'::jsonb)
    into v_also
    from catalog.institution_aliases a
    where a.institution_id = v_inst.id
      and a.superseded_at is null
      and a.alias_type in ('official_name', 'former_name')
      and a.alias is distinct from v_display
      and api.temporal_coverage(a.valid_from, a.valid_to, a.from_precision, a.to_precision, as_of)
        in ('match', 'ambiguous');

    if v_display is null then
      v_display := v_inst.official_name;
      v_basis := 'current_official_name_no_alias_covered_as_of';
      v_unknowns := array_append(v_unknowns, 'historical_name');
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'identifier_type', n.identifier_type,
    'identifier_value', n.identifier_value,
    'issuer', n.issuer,
    'verification_status', n.verification_status,
    'temporal', api.temporal_object(
      n.valid_from, n.valid_to, n.from_precision, n.to_precision,
      as_of, n.recorded_at, n.superseded_at
    )
  ) order by n.identifier_type, n.identifier_value), '[]'::jsonb)
  into v_identifiers
  from catalog.institution_identifiers n
  where n.institution_id = v_inst.id
    and n.superseded_at is null;

  if jsonb_array_length(v_identifiers) = 0 then
    v_identifier_status := 'not_documented';
    v_unknowns := array_append(v_unknowns, 'external_identifiers');
  else
    v_identifier_status := 'documented';
  end if;

  if as_of is null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'status', s.status,
      'notes', s.notes,
      'verification_status', s.verification_status,
      'basis', 'status_version',
      'temporal', api.temporal_object(
        s.valid_from, s.valid_to, s.from_precision, s.to_precision,
        null, s.recorded_at, s.superseded_at
      )
    )), '[]'::jsonb)
    into v_status
    from catalog.institution_status_versions s
    where s.institution_id = v_inst.id
      and s.superseded_at is null;

    if jsonb_array_length(v_status) = 0 then
      v_status := jsonb_build_array(jsonb_build_object(
        'status', v_inst.current_status,
        'notes', 'current_status is a cache of the status known when the extract was loaded. It is not a historical operating interval.',
        'basis', 'current_status_cache',
        'temporal', null
      ));
      v_unknowns := array_append(v_unknowns, 'operating_interval');
    end if;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'status', s.status,
      'notes', s.notes,
      'verification_status', s.verification_status,
      'basis', 'status_version',
      'temporal', api.temporal_object(
        s.valid_from, s.valid_to, s.from_precision, s.to_precision,
        as_of, s.recorded_at, s.superseded_at
      )
    )), '[]'::jsonb)
    into v_status
    from catalog.institution_status_versions s
    where s.institution_id = v_inst.id
      and s.superseded_at is null
      and api.temporal_coverage(s.valid_from, s.valid_to, s.from_precision, s.to_precision, as_of)
        in ('match', 'ambiguous');

    if jsonb_array_length(v_status) = 0 then
      v_status := jsonb_build_array(jsonb_build_object(
        'status', 'not_documented',
        'basis', 'no_status_interval_covers_as_of',
        'notes', 'The current_status cache was not projected backward onto this date.',
        'temporal', null
      ));
      v_unknowns := array_append(v_unknowns, 'operating_status_on_as_of');
    end if;
  end if;

  v_accreditation := api.get_institution_accreditation(v_inst.id, as_of, false);
  if jsonb_array_length(v_accreditation -> 'data' -> 'applied') = 0 then
    v_unknowns := array_append(v_unknowns, 'accreditation_on_requested_view');
  end if;

  select count(*)::integer into v_program_count
  from academic.programs p
  where p.institution_id = v_inst.id;

  if include_provenance then
    select coalesce(jsonb_agg(item), '[]'::jsonb)
    into v_provenance
    from (
      select jsonb_array_elements(api.provenance_for('catalog', 'institutions', v_inst.id)) as item
      union all
      select jsonb_array_elements(api.provenance_for('catalog', 'institution_aliases', a.id))
      from catalog.institution_aliases a
      where a.institution_id = v_inst.id
      union all
      select jsonb_array_elements(api.provenance_for('catalog', 'institution_accreditations', ac.id))
      from catalog.institution_accreditations ac
      where ac.institution_id = v_inst.id
      union all
      select jsonb_array_elements(api.provenance_for('catalog', 'institution_status_versions', st.id))
      from catalog.institution_status_versions st
      where st.institution_id = v_inst.id
    ) src;
  end if;

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', jsonb_build_object(
      'id', v_inst.id,
      'official_name', v_inst.official_name,
      'display_name', v_display,
      'display_name_basis', v_basis,
      'also_matching_names', coalesce(v_also, '[]'::jsonb),
      'institution_type', v_inst.institution_type,
      'country_code', v_inst.country_code,
      'control', v_inst.control,
      'current_status', v_inst.current_status,
      'current_status_meaning', 'Cache for the current view. Historical status comes from status_as_of.',
      'website_url', v_inst.website_url,
      'notes', v_inst.notes,
      'aliases', v_aliases,
      'identifiers', v_identifiers,
      'external_identifiers_status', v_identifier_status,
      'status_as_of', v_status,
      'accreditation', v_accreditation -> 'data',
      'program_count', v_program_count,
      'unknowns', to_jsonb(v_unknowns),
      'provenance', case when include_provenance then v_provenance else null end
    )
  );
end;
$$;

create or replace function api.get_institution_history(institution_id uuid)
returns jsonb
language plpgsql
stable
set search_path = api, catalog, policy, pg_temp
as $$
declare
  v_name text;
begin
  select official_name into v_name from catalog.institutions i where i.id = institution_id;
  if v_name is null then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', jsonb_build_object(
      'institution_id', institution_id,
      'official_name', v_name,
      'aliases', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', a.id,
          'alias', a.alias,
          'alias_type', a.alias_type,
          'verification_status', a.verification_status,
          'temporal', api.temporal_object(a.valid_from, a.valid_to, a.from_precision, a.to_precision, null, a.recorded_at, a.superseded_at)
        ) order by a.valid_from nulls first, a.alias), '[]'::jsonb)
        from catalog.institution_aliases a
        where a.institution_id = get_institution_history.institution_id
      ),
      'status_versions', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id,
          'status', s.status,
          'notes', s.notes,
          'verification_status', s.verification_status,
          'temporal', api.temporal_object(s.valid_from, s.valid_to, s.from_precision, s.to_precision, null, s.recorded_at, s.superseded_at)
        )), '[]'::jsonb)
        from catalog.institution_status_versions s
        where s.institution_id = get_institution_history.institution_id
      ),
      'accreditations', (
        api.get_institution_accreditation(get_institution_history.institution_id, null, true) -> 'data' -> 'history'
      ),
      'accreditor_recognition_is_separate', true
    )
  );
end;
$$;
