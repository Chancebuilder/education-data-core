-- Conservative transfer evaluation.
-- credit_recommended, institution_accepts, equivalency_documented, and
-- degree_requirement_satisfied are independent. None is copied from another.

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
  v_withheld jsonb;
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
            in ('match', 'ambiguous')
        )
    )
  ) order by p.official_program_family_name), '[]'::jsonb)
  into v_rows
  from academic.programs p
  where p.institution_id = get_programs_by_institution.institution_id
    and (get_programs_by_institution.degree_type is null or p.degree_type = get_programs_by_institution.degree_type);

  select coalesce(jsonb_agg(jsonb_build_object(
    'program_version_id', v.id,
    'official_program_name', v.official_program_name,
    'reason', 'undated_version_not_applied_to_historical_as_of'
  )), '[]'::jsonb)
  into v_withheld
  from academic.program_versions v
  join academic.programs p on p.id = v.program_id
  where p.institution_id = get_programs_by_institution.institution_id
    and v.superseded_at is null
    and as_of is not null
    and api.temporal_coverage(v.valid_from, v.valid_to, v.from_precision, v.to_precision, as_of) = 'undated';

  return jsonb_build_object(
    'meta', api.envelope_meta(as_of),
    'data', v_rows,
    'not_applied_to_as_of', v_withheld
  );
end;
$$;

create or replace function api.evaluate_transfer(
  destination_institution_id uuid,
  completed_on date,
  learning_experience_version_id uuid default null,
  authority_identifier text default null,
  grade text default null,
  program_version_id uuid default null,
  policy_as_of date default null
)
returns jsonb
language plpgsql
stable
set search_path = api, catalog, academic, alternative, policy, transfer, pg_temp
as $$
#variable_conflict use_variable
declare
  v_as_of date := coalesce(policy_as_of, completed_on);
  v_version_id uuid;
  v_provider_id uuid;
  v_match_count integer := 0;
  v_row_count integer := 0;
  v_ambiguous_count integer := 0;
  v_credit jsonb;
  v_recommendations jsonb;
  v_body jsonb;
  v_policy jsonb;
  v_equivalencies jsonb;
  v_equiv_count integer := 0;
  v_equiv_type text;
  v_acceptance text := 'not_documented';
  v_acceptance_established boolean := false;
  v_binding_count integer := 0;
  v_program_id uuid;
begin
  if destination_institution_id is null or completed_on is null then
    raise exception 'destination_institution_id and completed_on are required'
      using errcode = '22023';
  end if;
  if learning_experience_version_id is null and nullif(btrim(coalesce(authority_identifier, '')), '') is null then
    raise exception 'learning_experience_version_id or authority_identifier is required'
      using errcode = '22023';
  end if;
  if not exists (select 1 from catalog.institutions i where i.id = destination_institution_id) then
    raise exception 'institution not found' using errcode = 'P0002';
  end if;

  if program_version_id is not null then
    select program_id into v_program_id
    from academic.program_versions
    where id = program_version_id;
    if v_program_id is null then
      raise exception 'program version not found' using errcode = 'P0002';
    end if;
  end if;

  if learning_experience_version_id is not null then
    v_version_id := learning_experience_version_id;
    if not exists (
      select 1 from alternative.learning_experience_versions lev where lev.id = v_version_id
    ) then
      raise exception 'learning experience version not found' using errcode = 'P0002';
    end if;
  else
    select lev.id
    into v_version_id
    from alternative.learning_experience_versions lev
    join alternative.learning_experiences le on le.id = lev.learning_experience_id
    left join alternative.credit_recommendations cr
      on cr.learning_experience_version_id = lev.id
     and cr.superseded_at is null
    where lev.superseded_at is null
      and (
        le.provider_course_identifier = authority_identifier
        or cr.authority_identifier = authority_identifier
      )
    order by
      case
        when api.temporal_coverage(
          cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision, completed_on
        ) = 'match' then 0
        else 1
      end,
      lev.created_at
    limit 1;
    if v_version_id is null then
      raise exception 'learning experience not found for authority identifier' using errcode = 'P0002';
    end if;
  end if;

  select le.provider_id into v_provider_id
  from alternative.learning_experience_versions lev
  join alternative.learning_experiences le on le.id = lev.learning_experience_id
  where lev.id = v_version_id;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'credit_recommendation_id', cr.id,
      'authority_identifier', cr.authority_identifier,
      'recommended_credits', cr.recommended_credits,
      'credit_unit', cr.credit_unit,
      'recommended_level', cr.recommended_level,
      'recommended_subject', cr.recommended_subject,
      'recommendation_body', rb.code,
      'awards_credit', rb.awards_credit,
      'binds_destination_institutions', rb.binds_destination_institutions,
      'verification_status', cr.verification_status,
      'confidence', cr.confidence,
      'coverage', api.temporal_coverage(
        cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision, completed_on
      ),
      'temporal', api.temporal_object(
        cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision,
        completed_on, cr.recorded_at, cr.superseded_at
      ),
      'provenance', api.provenance_for('alternative', 'credit_recommendations', cr.id)
    ) order by cr.recommendation_start), '[]'::jsonb),
    count(*)::integer,
    count(*) filter (
      where api.temporal_coverage(
        cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision, completed_on
      ) = 'match'
    )::integer,
    count(*) filter (
      where api.temporal_coverage(
        cr.recommendation_start, cr.recommendation_end, cr.start_precision, cr.end_precision, completed_on
      ) = 'ambiguous'
    )::integer
  into v_recommendations, v_row_count, v_match_count, v_ambiguous_count
  from alternative.credit_recommendations cr
  join alternative.recommendation_bodies rb on rb.id = cr.recommendation_body_id
  where cr.learning_experience_version_id = v_version_id
    and cr.superseded_at is null;

  if v_row_count = 0 then
    v_credit := to_jsonb('not_documented'::text);
  elsif v_match_count > 0 then
    v_credit := to_jsonb(true);
  elsif v_ambiguous_count > 0 then
    v_credit := to_jsonb('ambiguous'::text);
  else
    v_credit := to_jsonb(false);
  end if;

  select jsonb_build_object(
    'code', rb.code,
    'official_name', rb.official_name,
    'awards_credit', rb.awards_credit,
    'binds_destination_institutions', rb.binds_destination_institutions
  )
  into v_body
  from alternative.credit_recommendations cr
  join alternative.recommendation_bodies rb on rb.id = cr.recommendation_body_id
  where cr.learning_experience_version_id = v_version_id
    and cr.superseded_at is null
  order by cr.recommendation_start
  limit 1;

  v_policy := api.get_transfer_policy(destination_institution_id, v_as_of, v_program_id, true);

  select f.acceptance_status
  into v_acceptance
  from policy.policy_facts f
  join policy.policy_versions v on v.id = f.policy_version_id
  join policy.policies p on p.id = v.policy_id
  where p.institution_id = destination_institution_id
    and f.superseded_at is null
    and v.superseded_at is null
    and f.establishes_course_acceptance
    and f.acceptance_strength in ('course', 'provider')
    and (v_program_id is null or p.program_id is null or p.program_id = v_program_id)
    and api.temporal_coverage(v.valid_from, v.valid_to, v.from_precision, v.to_precision, v_as_of)
      in ('match', 'ambiguous')
    and (
      f.acceptance_strength = 'course'
      or exists (
        select 1
        from policy.policy_fact_providers fp
        where fp.policy_fact_id = f.id
          and fp.provider_id = v_provider_id
          and fp.relationship in ('accepts', 'eligible_method')
      )
    )
  order by case f.acceptance_status
    when 'rejected' then 0
    when 'accepted' then 1
    when 'conditional' then 2
    else 3
  end
  limit 1;

  if v_acceptance is not null and v_acceptance <> 'not_documented' then
    v_acceptance_established := true;
  else
    v_acceptance := 'not_documented';
    v_acceptance_established := false;
  end if;

  v_equivalencies := api.get_known_equivalencies(
    destination_institution_id,
    v_version_id,
    program_version_id,
    v_as_of
  );
  v_equiv_count := jsonb_array_length(coalesce(v_equivalencies -> 'data', '[]'::jsonb));
  if v_equiv_count > 0 then
    v_equiv_type := v_equivalencies -> 'data' -> 0 ->> 'equivalency_type';
  end if;

  select count(*)::integer
  into v_binding_count
  from academic.requirement_bindings b
  join academic.requirement_nodes n on n.id = b.requirement_node_id
  where program_version_id is not null
    and n.program_version_id = evaluate_transfer.program_version_id
    and b.course_version_id is not null
    and b.course_version_id in (
      select (item ->> 'destination_course_version_id')::uuid
      from jsonb_array_elements(coalesce(v_equivalencies -> 'data', '[]'::jsonb)) item
      where item ->> 'destination_course_version_id' is not null
    );

  return jsonb_build_object(
    'meta', api.envelope_meta(v_as_of),
    'data', jsonb_build_object(
      'destination_institution_id', destination_institution_id,
      'completed_on', completed_on,
      'policy_as_of', v_as_of,
      'grade_supplied', grade,
      'grade_check', 'not_documented',
      'learning_experience_version_id', v_version_id,
      'provider_id', v_provider_id,
      'program_version_id', program_version_id,
      'distinctions', jsonb_build_object(
        'credit_recommended', v_credit,
        'institution_accepts', v_acceptance,
        'acceptance_established', v_acceptance_established,
        'equivalency_documented', v_equiv_count > 0,
        'equivalency_type', v_equiv_type,
        'degree_requirement_satisfied', 'not_documented',
        'degree_applicability', jsonb_build_object(
          'general_education', 'not_documented',
          'elective', 'not_documented',
          'major', 'not_documented',
          'concentration', 'not_documented',
          'residency', 'not_documented',
          'upper_division', 'not_documented',
          'total_degree_credits', 'not_documented'
        )
      ),
      'recommendation_body', v_body,
      'recommendations', v_recommendations,
      'policy_context', v_policy -> 'data' -> 'applied',
      'undated_policy_context', v_policy -> 'data' -> 'not_applied_to_as_of',
      'equivalencies', v_equivalencies -> 'data',
      'requirement_bindings_touched', v_binding_count,
      'requirement_binding_note', 'A requirement binding counts a published target. V1 still does not mark a learner requirement satisfied.',
      'warnings', jsonb_build_array(
        'A credit recommendation does not establish institutional acceptance.',
        'Institutional acceptance does not establish a course equivalency.',
        'A course equivalency does not establish that a degree requirement is satisfied.',
        'Semester and quarter credits are not converted.',
        'Null recommendation fields were not filled in from the course title or from a default credit value.'
      )
    )
  );
end;
$$;

comment on function api.evaluate_transfer(uuid, date, uuid, text, text, uuid, date) is
  'Explains recommendation, acceptance, equivalency, and degree applicability separately. Category-level policy illustrations do not flip institution_accepts. Degree applicability stays not_documented until a future audit engine has authoritative requirement results.';

create or replace view api.v_institutions_current
with (security_invoker = true) as
select
  id,
  official_name,
  normalized_name,
  institution_type,
  country_code,
  control,
  current_status,
  website_url
from catalog.institutions;

comment on view api.v_institutions_current is
  'Current institution identity cache. Aliases, identifiers, and accreditation stay on their own functions.';

create or replace view api.v_recommendation_acceptance_boundary
with (security_invoker = true) as
select
  cr.id as credit_recommendation_id,
  le.canonical_title,
  cr.authority_identifier,
  cr.recommended_credits,
  cr.credit_unit,
  rb.code as recommendation_body,
  rb.awards_credit,
  rb.binds_destination_institutions,
  'not_derived'::text as institution_accepts,
  false as equivalency_documented,
  'not_documented'::text as degree_requirement_satisfied
from alternative.credit_recommendations cr
join alternative.recommendation_bodies rb on rb.id = cr.recommendation_body_id
join alternative.learning_experience_versions lev on lev.id = cr.learning_experience_version_id
join alternative.learning_experiences le on le.id = lev.learning_experience_id
where cr.superseded_at is null;

comment on view api.v_recommendation_acceptance_boundary is
  'Makes the V1 boundary explicit: a recommendation row does not carry acceptance, equivalency, or degree applicability.';

grant select on api.v_institutions_current, api.v_recommendation_acceptance_boundary
  to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;

revoke all on all functions in schema api from public;
grant execute on all functions in schema api to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
revoke execute on function api.rebuild_search_documents() from edu_anon, edu_app;
revoke execute on function api.list_research_gaps(text, text) from edu_anon, edu_app;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'edu_api') then
    grant edu_app to edu_api;
  end if;
end $$;
