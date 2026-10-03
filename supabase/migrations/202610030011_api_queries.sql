-- Institution search is replaced here with a single-pass implementation.
-- Program, course, provider, policy, recommendation, equivalency, and evaluation functions follow.

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
        case
          when v_q is not null and exists (
            select 1
            from catalog.institution_identifiers n
            where n.institution_id = i.id
              and n.superseded_at is null
              and lower(n.identifier_value) = lower(coalesce(q, ''))
          ) then 1
          else 0
        end
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
    (select count(*)::integer from filtered),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'official_name', page.official_name,
        'institution_type', page.institution_type,
        'country_code', page.country_code,
        'control', page.control,
        'current_status', page.current_status,
        'website_url', page.website_url,
        'match_score', round(page.score::numeric, 3)
      ))
      from (
        select *
        from filtered
        order by case when v_q is null then 0 else score end desc, official_name
        limit v_limit offset v_offset
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

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

create or replace function api.fact_row(
  fact policy.policy_facts,
  version policy.policy_versions,
  parent policy.policies,
  as_of date
)
returns jsonb
language plpgsql
stable
set search_path = api, policy, alternative, academic, pg_temp
as $$
declare
  v_program_name text;
begin
  if parent.program_id is not null then
    select official_program_family_name into v_program_name
    from academic.programs
    where id = parent.program_id;
  end if;

  return jsonb_build_object(
    'policy_id', parent.id,
    'policy_version_id', version.id,
    'policy_fact_id', fact.id,
    'policy_kind', parent.policy_kind,
    'title', parent.title,
    'program_id', parent.program_id,
    'program_name', v_program_name,
    'fact_kind', fact.fact_kind,
    'statement', fact.statement,
    'source_category', fact.source_category,
    'method_labels', to_jsonb(fact.method_labels),
    'scope_degree_type', fact.scope_degree_type,
    'scope_modality', fact.scope_modality,
    'scope_career', fact.scope_career,
    'scope_requirement_area', fact.scope_requirement_area,
    'comparison', fact.comparison,
    'limit_value', fact.limit_value,
    'limit_unit', fact.limit_unit,
    'limit_is_percentage', fact.limit_is_percentage,
    'context_value', fact.context_value,
    'context_label', fact.context_label,
    'grade_threshold', fact.grade_threshold,
    'course_age_value', fact.course_age_value,
    'course_age_unit', fact.course_age_unit,
    'acceptance_status', fact.acceptance_status,
    'acceptance_strength', fact.acceptance_strength,
    'establishes_course_acceptance', fact.establishes_course_acceptance,
    'verification_status', fact.verification_status,
    'confidence', fact.confidence,
    'provider_links', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'provider_id', pr.id,
        'provider_name', pr.official_name,
        'relationship', fp.relationship
      ) order by pr.official_name), '[]'::jsonb)
      from policy.policy_fact_providers fp
      join alternative.providers pr on pr.id = fp.provider_id
      where fp.policy_fact_id = fact.id
    ),
    'temporal', api.temporal_object(
      version.valid_from, version.valid_to, version.from_precision, version.to_precision,
      as_of, version.recorded_at, version.superseded_at
    ),
    'source_document_id', fact.source_document_id
  );
end;
$$;

create or replace function api.get_transfer_policy(
  institution_id uuid,
  as_of date default null,
  program_id uuid default null,
  include_provenance boolean default false
)
returns jsonb
language plpgsql
stable
set search_path = api, policy, catalog, pg_temp
as $$
declare
  v_applied jsonb := '[]'::jsonb;
  v_withheld jsonb := '[]'::jsonb;
  r record;
  v_coverage text;
  v_row jsonb;
begin
  if not exists (select 1 from catalog.institutions i where i.id = institution_id) then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  for r in
    select f as fact_row, v as version_row, p as policy_row
    from policy.policy_facts f
    join policy.policy_versions v on v.id = f.policy_version_id
    join policy.policies p on p.id = v.policy_id
    where p.institution_id = get_transfer_policy.institution_id
      and f.superseded_at is null
      and v.superseded_at is null
      and (get_transfer_policy.program_id is null or p.program_id is null or p.program_id = get_transfer_policy.program_id)
    order by p.title, f.fact_kind
  loop
    v_coverage := case
      when as_of is null then 'current_view'
      else api.temporal_coverage(
        (r.version_row).valid_from,
        (r.version_row).valid_to,
        (r.version_row).from_precision,
        (r.version_row).to_precision,
        as_of
      )
    end;
    v_row := api.fact_row(r.fact_row, r.version_row, r.policy_row, as_of);
    if include_provenance then
      v_row := v_row || jsonb_build_object(
        'provenance', api.provenance_for('policy', 'policy_facts', (r.fact_row).id)
      );
    end if;
    if as_of is null or v_coverage in ('match', 'ambiguous') then
      v_applied := v_applied || jsonb_build_array(v_row);
    elsif v_coverage = 'undated' then
      v_withheld := v_withheld || jsonb_build_array(v_row);
    end if;
  end loop;

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', jsonb_build_object(
      'institution_id', institution_id,
      'program_id', program_id,
      'applied', v_applied,
      'not_applied_to_as_of', v_withheld,
      'reading_note', 'A transfer maximum, residency rule, or category illustration does not by itself accept a named course, create an equivalency, or satisfy a degree requirement.'
    )
  );
end;
$$;

create or replace function api.get_policy_history(
  institution_id uuid,
  policy_kind text default null
)
returns jsonb
language plpgsql
stable
set search_path = api, policy, catalog, pg_temp
as $$
begin
  if not exists (select 1 from catalog.institutions i where i.id = institution_id) then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'policy_id', p.id,
        'policy_kind', p.policy_kind,
        'title', p.title,
        'program_id', p.program_id,
        'version_id', v.id,
        'version_label', v.version_label,
        'academic_catalog_year', v.academic_catalog_year,
        'verification_status', v.verification_status,
        'confidence', v.confidence,
        'superseded_at', v.superseded_at,
        'temporal', api.temporal_object(
          v.valid_from, v.valid_to, v.from_precision, v.to_precision,
          null, v.recorded_at, v.superseded_at
        ),
        'facts', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'policy_fact_id', f.id,
            'fact_kind', f.fact_kind,
            'statement', f.statement,
            'limit_value', f.limit_value,
            'limit_unit', f.limit_unit,
            'comparison', f.comparison,
            'establishes_course_acceptance', f.establishes_course_acceptance,
            'superseded_at', f.superseded_at
          ) order by f.created_at), '[]'::jsonb)
          from policy.policy_facts f
          where f.policy_version_id = v.id
        )
      ) order by v.valid_from nulls first, p.title), '[]'::jsonb)
      from policy.policy_versions v
      join policy.policies p on p.id = v.policy_id
      where p.institution_id = get_policy_history.institution_id
        and (get_policy_history.policy_kind is null or p.policy_kind = get_policy_history.policy_kind)
    )
  );
end;
$$;

create or replace function api.get_alternative_credit_rules(
  institution_id uuid,
  as_of date default null,
  provider_id uuid default null
)
returns jsonb
language sql
stable
set search_path = api, policy, pg_temp
as $$
  select jsonb_build_object(
    'meta', (api.get_transfer_policy(institution_id, as_of, null, true) -> 'meta'),
    'data', jsonb_build_object(
      'institution_id', institution_id,
      'provider_id', provider_id,
      'rules', (
        select coalesce(jsonb_agg(item), '[]'::jsonb)
        from (
          select item
          from jsonb_array_elements(
            (api.get_transfer_policy(institution_id, as_of, null, true) -> 'data' -> 'applied')
            || (api.get_transfer_policy(institution_id, as_of, null, true) -> 'data' -> 'not_applied_to_as_of')
          ) item
          where item ->> 'fact_kind' in (
            'alternative_credit_limit',
            'acceptance_condition',
            'source_distinction',
            'transcript_routing',
            'program_restriction'
          )
          or item ->> 'policy_kind' in ('alternative_credit', 'prior_learning', 'transcript_routing')
          or (
            provider_id is not null
            and exists (
              select 1
              from jsonb_array_elements(coalesce(item -> 'provider_links', '[]'::jsonb)) link
              where link ->> 'provider_id' = provider_id::text
            )
          )
        ) matched
      ),
      'acceptance_note', 'A provider link of addresses, or a category illustration, does not establish that the institution accepts a course.'
    )
  );
$$;

create or replace function api.get_programs_by_institution(
  institution_id uuid,
  degree_type text default null,
  as_of date default null,
  modality text default null
)
returns jsonb
language plpgsql
stable
set search_path = api, academic, catalog, pg_temp
as $$
declare
  v_rows jsonb;
begin
  if not exists (select 1 from catalog.institutions i where i.id = institution_id) then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'program_id', p.id,
    'official_program_family_name', p.official_program_family_name,
    'program_category', p.program_category,
    'degree_type', p.degree_type,
    'cip_code', p.cip_code,
    'versions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'program_version_id', v.id,
        'version_label', v.version_label,
        'academic_catalog_year', v.academic_catalog_year,
        'official_program_name', v.official_program_name,
        'total_credits', v.total_credits,
        'credit_unit', v.credit_unit,
        'delivery_modality', v.delivery_modality,
        'status', v.status,
        'verification_status', v.verification_status,
        'confidence', v.confidence,
        'temporal', api.temporal_object(
          v.valid_from, v.valid_to, v.from_precision, v.to_precision,
          as_of, v.recorded_at, v.superseded_at
        )
      ) order by v.official_program_name), '[]'::jsonb)
      from academic.program_versions v
      where v.program_id = p.id
        and v.superseded_at is null
        and (modality is null or v.delivery_modality = modality or v.delivery_modality is null)
        and (
          as_of is null
          or api.temporal_coverage(v.valid_from, v.valid_to, v.from_precision, v.to_precision, as_of)
            in ('match', 'ambiguous', 'undated', 'current_view')
        )
    )
  ) order by p.official_program_family_name), '[]'::jsonb)
  into v_rows
  from academic.programs p
  where p.institution_id = get_programs_by_institution.institution_id
    and (get_programs_by_institution.degree_type is null or p.degree_type = get_programs_by_institution.degree_type);

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', v_rows
  );
end;
$$;

create or replace function api.search_programs(
  q text default null,
  institution_id uuid default null,
  degree_type text default null,
  result_limit integer default 20,
  result_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = api, academic, catalog, public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(result_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(result_offset, 0), 0);
  v_q text := nullif(catalog.normalize_name(coalesce(q, '')), '');
  v_rows jsonb;
  v_total integer;
begin
  with matched as (
    select
      p.id,
      p.official_program_family_name,
      p.degree_type,
      p.program_category,
      p.institution_id,
      i.official_name as institution_name,
      greatest(
        case
          when v_q is null then 0
          when p.normalized_name = v_q then 1
          when p.normalized_name like '%' || v_q || '%' then 0.9
          else similarity(p.normalized_name, v_q)
        end
      ) as score
    from academic.programs p
    join catalog.institutions i on i.id = p.institution_id
    where (search_programs.institution_id is null or p.institution_id = search_programs.institution_id)
      and (search_programs.degree_type is null or p.degree_type = search_programs.degree_type)
      and (
        v_q is null
        or p.normalized_name like '%' || v_q || '%'
        or similarity(p.normalized_name, v_q) >= 0.28
      )
  )
  select
    (select count(*)::integer from matched),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'program_id', page.id,
        'official_program_family_name', page.official_program_family_name,
        'degree_type', page.degree_type,
        'program_category', page.program_category,
        'institution_id', page.institution_id,
        'institution_name', page.institution_name,
        'match_score', round(page.score::numeric, 3)
      ))
      from (
        select * from matched
        order by score desc, official_program_family_name
        limit v_limit offset v_offset
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', v_rows,
    'page', jsonb_build_object('limit', v_limit, 'offset', v_offset, 'total', v_total)
  );
end;
$$;

create or replace function api.get_program_requirements(program_version_id uuid)
returns jsonb
language plpgsql
stable
set search_path = api, academic, policy, pg_temp
as $$
declare
  v_version academic.program_versions%rowtype;
  v_program academic.programs%rowtype;
  v_nodes integer;
begin
  select * into v_version from academic.program_versions v where v.id = program_version_id;
  if not found then
    raise exception 'program version not found' using errcode = 'P0002';
  end if;
  select * into v_program from academic.programs p where p.id = v_version.program_id;
  select count(*)::integer into v_nodes
  from academic.requirement_nodes n
  where n.program_version_id = get_program_requirements.program_version_id;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', jsonb_build_object(
      'program_id', v_program.id,
      'program_version_id', v_version.id,
      'institution_id', v_program.institution_id,
      'official_program_name', v_version.official_program_name,
      'degree_type', v_program.degree_type,
      'total_credits', v_version.total_credits,
      'credit_unit', v_version.credit_unit,
      'academic_catalog_year', v_version.academic_catalog_year,
      'requirement_tree', case when v_nodes = 0 then null else 'present' end,
      'requirement_node_count', v_nodes,
      'requirement_status', case when v_nodes = 0 then 'not_documented' else 'nodes_present_audit_deferred' end,
      'practical_max_transfer', null,
      'practical_max_transfer_status', 'not_calculated',
      'related_policy_facts', (
        api.get_transfer_policy(v_program.institution_id, null, v_program.id, false) -> 'data' -> 'applied'
      ),
      'note', 'V1 does not calculate whether credit satisfies this program. An empty requirement tree means the requirements were not documented, not that the program has no requirements.'
    )
  );
end;
$$;

create or replace function api.search_courses(
  q text default null,
  institution_id uuid default null,
  result_limit integer default 20,
  result_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = api, academic, catalog, public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(result_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(result_offset, 0), 0);
  v_q text := nullif(catalog.normalize_name(coalesce(q, '')), '');
  v_rows jsonb;
  v_total integer;
begin
  with matched as (
    select
      cv.id,
      cv.course_code,
      cv.official_title,
      cv.credits,
      cv.credit_unit,
      cv.academic_level,
      ic.institution_id,
      i.official_name as institution_name,
      greatest(
        case
          when v_q is null then 0
          when cv.normalized_course_code = v_q then 1
          when catalog.normalize_name(cv.official_title) like '%' || v_q || '%' then 0.9
          else similarity(catalog.normalize_name(cv.official_title), v_q)
        end
      ) as score
    from academic.course_versions cv
    join academic.institution_courses ic on ic.id = cv.institution_course_id
    join catalog.institutions i on i.id = ic.institution_id
    where cv.superseded_at is null
      and (search_courses.institution_id is null or ic.institution_id = search_courses.institution_id)
      and (
        v_q is null
        or cv.normalized_course_code = v_q
        or catalog.normalize_name(cv.official_title) like '%' || v_q || '%'
        or similarity(catalog.normalize_name(cv.official_title), v_q) >= 0.28
      )
  )
  select
    (select count(*)::integer from matched),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'course_version_id', page.id,
        'course_code', page.course_code,
        'official_title', page.official_title,
        'credits', page.credits,
        'credit_unit', page.credit_unit,
        'academic_level', page.academic_level,
        'institution_id', page.institution_id,
        'institution_name', page.institution_name,
        'match_score', round(page.score::numeric, 3)
      ))
      from (
        select * from matched
        order by score desc, official_title
        limit v_limit offset v_offset
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', v_rows,
    'page', jsonb_build_object(
      'limit', v_limit,
      'offset', v_offset,
      'total', v_total,
      'empty_means', 'No course versions are loaded. V1 did not invent destination catalog courses.'
    )
  );
end;
$$;

create or replace function api.search_providers(
  q text default null,
  result_limit integer default 20,
  result_offset integer default 0
)
returns jsonb
language plpgsql
stable
set search_path = api, alternative, catalog, public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(result_limit, 20), 1), 100);
  v_offset integer := greatest(coalesce(result_offset, 0), 0);
  v_q text := nullif(catalog.normalize_name(coalesce(q, '')), '');
  v_rows jsonb;
  v_total integer;
begin
  with matched as (
    select
      p.id,
      p.official_name,
      p.provider_type,
      p.website_url,
      p.verification_status,
      case
        when v_q is null then 0
        when p.normalized_name = v_q then 1
        when p.normalized_name like '%' || v_q || '%' then 0.9
        else similarity(p.normalized_name, v_q)
      end as score
    from alternative.providers p
    where v_q is null
      or p.normalized_name like '%' || v_q || '%'
      or similarity(p.normalized_name, v_q) >= 0.28
  )
  select
    (select count(*)::integer from matched),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'official_name', page.official_name,
        'provider_type', page.provider_type,
        'website_url', page.website_url,
        'verification_status', page.verification_status,
        'match_score', round(page.score::numeric, 3)
      ))
      from (
        select * from matched
        order by score desc, official_name
        limit v_limit offset v_offset
      ) page
    ), '[]'::jsonb)
  into v_total, v_rows;

  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', v_rows,
    'page', jsonb_build_object('limit', v_limit, 'offset', v_offset, 'total', v_total)
  );
end;
$$;

create or replace function api.get_provider(provider_id uuid)
returns jsonb
language plpgsql
stable
set search_path = api, alternative, pg_temp
as $$
declare
  v_row alternative.providers%rowtype;
begin
  select * into v_row from alternative.providers p where p.id = provider_id;
  if not found then
    raise exception 'provider not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', jsonb_build_object(
      'id', v_row.id,
      'official_name', v_row.official_name,
      'provider_type', v_row.provider_type,
      'website_url', v_row.website_url,
      'notes', v_row.notes,
      'verification_status', v_row.verification_status,
      'confidence', v_row.confidence,
      'provenance', api.provenance_for('alternative', 'providers', v_row.id)
    )
  );
end;
$$;

create or replace function api.get_provider_courses(
  provider_id uuid,
  q text default null,
  as_of date default null
)
returns jsonb
language plpgsql
stable
set search_path = api, alternative, catalog, public, pg_temp
as $$
declare
  v_q text := nullif(catalog.normalize_name(coalesce(q, '')), '');
  v_rows jsonb;
begin
  if not exists (select 1 from alternative.providers p where p.id = provider_id) then
    raise exception 'provider not found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'learning_experience_id', le.id,
    'provider_course_identifier', le.provider_course_identifier,
    'identifier_status', le.identifier_status,
    'canonical_title', le.canonical_title,
    'versions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'learning_experience_version_id', v.id,
        'official_title', v.official_title,
        'subject', v.subject,
        'passing_threshold', v.passing_threshold,
        'description', v.description,
        'temporal', api.temporal_object(
          v.valid_from, v.valid_to, v.from_precision, v.to_precision,
          as_of, v.recorded_at, v.superseded_at
        )
      )), '[]'::jsonb)
      from alternative.learning_experience_versions v
      where v.learning_experience_id = le.id
        and v.superseded_at is null
    )
  ) order by le.canonical_title), '[]'::jsonb)
  into v_rows
  from alternative.learning_experiences le
  where le.provider_id = get_provider_courses.provider_id
    and (
      v_q is null
      or le.normalized_title like '%' || v_q || '%'
      or coalesce(lower(le.provider_course_identifier), '') = lower(coalesce(q, ''))
    );

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', v_rows
  );
end;
$$;

create or replace function api.get_credit_recommendations(
  authority_identifier text default null,
  provider_id uuid default null,
  learning_experience_id uuid default null,
  as_of date default null
)
returns jsonb
language plpgsql
stable
set search_path = api, alternative, pg_temp
as $$
declare
  v_rows jsonb;
begin
  if authority_identifier is null and provider_id is null and learning_experience_id is null then
    raise exception 'authority_identifier, provider_id, or learning_experience_id is required'
      using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'credit_recommendation_id', cr.id,
    'learning_experience_version_id', cr.learning_experience_version_id,
    'learning_experience_id', le.id,
    'provider_id', le.provider_id,
    'provider_name', pr.official_name,
    'canonical_title', le.canonical_title,
    'provider_course_identifier', le.provider_course_identifier,
    'authority_identifier', cr.authority_identifier,
    'recommendation_body', rb.code,
    'recommendation_body_name', rb.official_name,
    'awards_credit', rb.awards_credit,
    'binds_destination_institutions', rb.binds_destination_institutions,
    'recommended_credits', cr.recommended_credits,
    'credit_unit', cr.credit_unit,
    'recommended_level', cr.recommended_level,
    'recommended_subject', cr.recommended_subject,
    'recommendation_notes', cr.recommendation_notes,
    'verification_status', cr.verification_status,
    'confidence', cr.confidence,
    'temporal', api.temporal_object(
      cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision,
      as_of, cr.recorded_at, cr.superseded_at
    ),
    'institution_accepts', 'not_derived',
    'equivalency_documented', false,
    'degree_requirement_satisfied', 'not_documented'
  ) order by cr.recommendation_start), '[]'::jsonb)
  into v_rows
  from alternative.credit_recommendations cr
  join alternative.recommendation_bodies rb on rb.id = cr.recommendation_body_id
  join alternative.learning_experience_versions lev on lev.id = cr.learning_experience_version_id
  join alternative.learning_experiences le on le.id = lev.learning_experience_id
  join alternative.providers pr on pr.id = le.provider_id
  where cr.superseded_at is null
    and (
      get_credit_recommendations.authority_identifier is null
      or cr.authority_identifier = get_credit_recommendations.authority_identifier
      or le.provider_course_identifier = get_credit_recommendations.authority_identifier
    )
    and (get_credit_recommendations.provider_id is null or le.provider_id = get_credit_recommendations.provider_id)
    and (get_credit_recommendations.learning_experience_id is null or le.id = get_credit_recommendations.learning_experience_id)
    and (
      as_of is null
      or api.temporal_coverage(
        cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision, as_of
      ) in ('match', 'ambiguous')
    );

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', v_rows,
    'boundary', jsonb_build_object(
      'credit_recommendation_establishes_acceptance', false,
      'credit_recommendation_establishes_equivalency', false,
      'credit_recommendation_establishes_degree_applicability', false
    )
  );
end;
$$;

comment on function api.get_credit_recommendations(text, uuid, uuid, date) is
  'Returns recommendation-body facts only. institution_accepts is not_derived on every row so a client cannot read a recommendation as institutional acceptance.';

create or replace function api.get_known_equivalencies(
  destination_institution_id uuid default null,
  source_experience_version_id uuid default null,
  program_version_id uuid default null,
  as_of date default null
)
returns jsonb
language plpgsql
stable
set search_path = api, transfer, catalog, pg_temp
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'equivalency_id', e.id,
    'equivalency_type', e.equivalency_type,
    'destination_institution_id', e.destination_institution_id,
    'destination_course_version_id', e.destination_course_version_id,
    'source_experience_version_id', e.source_experience_version_id,
    'source_course_version_id', e.source_course_version_id,
    'program_version_id', e.program_version_id,
    'destination_credits', e.destination_credits,
    'credit_unit', e.credit_unit,
    'catalog_year', e.catalog_year,
    'verification_status', e.verification_status,
    'confidence', e.confidence,
    'notes', e.notes,
    'temporal', api.temporal_object(
      e.valid_from, e.valid_to, e.from_precision, e.to_precision,
      as_of, e.recorded_at, e.superseded_at
    ),
    'degree_requirement_satisfied', 'not_documented',
    'provenance', api.provenance_for('transfer', 'course_equivalencies', e.id)
  )), '[]'::jsonb)
  into v_rows
  from transfer.course_equivalencies e
  where e.superseded_at is null
    and (
      get_known_equivalencies.destination_institution_id is null
      or e.destination_institution_id = get_known_equivalencies.destination_institution_id
    )
    and (
      get_known_equivalencies.source_experience_version_id is null
      or e.source_experience_version_id = get_known_equivalencies.source_experience_version_id
    )
    and (get_known_equivalencies.program_version_id is null or e.program_version_id = get_known_equivalencies.program_version_id or e.program_version_id is null)
    and (
      as_of is null
      or api.temporal_coverage(e.valid_from, e.valid_to, e.from_precision, e.to_precision, as_of)
        in ('match', 'ambiguous')
    );

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', v_rows,
    'empty_means', 'No destination-authoritative equivalency is loaded for this query. Absence is not an invented elective and it is not a rejection.'
  );
end;
$$;

create or replace function api.get_record_provenance(
  fact_schema text,
  fact_table text,
  fact_id uuid
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_rows jsonb;
begin
  if fact_schema is null or fact_table is null or fact_id is null then
    raise exception 'fact_schema, fact_table, and fact_id are required' using errcode = '22023';
  end if;
  if fact_schema in ('internal', 'raw', 'learner') or fact_table in ('research_gaps', 'change_log', 'import_batches', 'source_payloads') then
    raise exception 'provenance for internal records is not available on the public contract' using errcode = '42501';
  end if;
  v_rows := api.provenance_for(fact_schema, fact_table, fact_id);
  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', jsonb_build_object(
      'fact_schema', fact_schema,
      'fact_table', fact_table,
      'fact_id', fact_id,
      'sources', v_rows,
      'provenance_status', case when jsonb_array_length(v_rows) = 0 then 'not_linked' else 'linked' end
    )
  );
end;
$$;

create or replace function api.get_source(source_id uuid)
returns jsonb
language plpgsql
stable
set search_path = api, provenance, pg_temp
as $$
declare
  v_row provenance.source_documents%rowtype;
begin
  select * into v_row from provenance.source_documents s where s.id = source_id;
  if not found then
    raise exception 'source not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', jsonb_build_object(
      'id', v_row.id,
      'source_title', v_row.source_title,
      'source_url', v_row.source_url,
      'source_type', v_row.source_type,
      'publisher', v_row.publisher,
      'authority_scope', v_row.authority_scope,
      'published_at', v_row.published_at,
      'retrieved_at', v_row.retrieved_at,
      'effective_from', v_row.effective_from,
      'effective_to', v_row.effective_to,
      'academic_year', v_row.academic_year,
      'archive_url', v_row.archive_url,
      'extraction_method', v_row.extraction_method,
      'notes', v_row.notes
    )
  );
end;
$$;

create or replace function api.list_research_gaps(
  status_filter text default null,
  topic_filter text default null
)
returns jsonb
language sql
stable
set search_path = api, provenance, pg_temp
as $$
  select jsonb_build_object(
    'meta', api.envelope_meta(null),
    'data', coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id,
      'institution_id', g.institution_id,
      'entity_type', g.entity_type,
      'entity_id', g.entity_id,
      'topic', g.topic,
      'unresolved_question', g.unresolved_question,
      'conflicting_evidence', g.conflicting_evidence,
      'current_best_evidence', g.current_best_evidence,
      'confidence', g.confidence,
      'recommended_action', g.recommended_action,
      'status', g.status
    ) order by g.topic), '[]'::jsonb)
  )
  from provenance.research_gaps g
  where (status_filter is null or g.status = status_filter)
    and (topic_filter is null or g.topic ilike '%' || topic_filter || '%');
$$;

comment on function api.list_research_gaps(text, text) is
  'Internal research queue. Execute is revoked from anonymous and application roles.';
