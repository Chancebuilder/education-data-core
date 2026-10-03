-- Policies are versioned. V1 stores typed facts for the rule classes the extract actually supports.
-- Generic rule tables exist so those facts can move later without changing institution or program identity.

create table policy.policies (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id),
  program_id uuid references academic.programs (id),
  policy_kind text not null references vocab.policy_kind (code),
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index policies_institution_kind_idx
  on policy.policies (institution_id, policy_kind);
create index policies_program_idx on policy.policies (program_id);

comment on table policy.policies is
  'Policy identity scoped to an institution and, when the source is program-specific, one program. There is no per-school column such as tesu_max_ace_credit.';

create table policy.policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references policy.policies (id) on delete cascade,
  version_label text,
  academic_catalog_year text,
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  published_at date,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  notes text,
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint policy_versions_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index policy_versions_asof_idx
  on policy.policy_versions (policy_id, valid_from, valid_to);

comment on table policy.policy_versions is
  'Valid time is inclusive. recorded_at and superseded_at are knowledge time. as_of on the API is valid time unless a function says otherwise.';

create table policy.policy_facts (
  id uuid primary key default gen_random_uuid(),
  policy_version_id uuid not null references policy.policy_versions (id) on delete cascade,
  fact_kind text not null references vocab.policy_fact_kind (code),
  scope_degree_type text references vocab.degree_type (code),
  scope_modality text references vocab.delivery_modality (code),
  scope_career text,
  scope_requirement_area text references vocab.requirement_area (code),
  source_category text references vocab.source_category (code),
  method_labels text[],
  comparison text references vocab.comparison_operator (code),
  limit_value numeric(7, 2),
  limit_unit text references vocab.limit_unit (code),
  limit_is_percentage boolean not null default false,
  context_value numeric(7, 2),
  context_label text,
  grade_threshold text,
  course_age_value integer,
  course_age_unit text,
  acceptance_status text references vocab.acceptance_status (code),
  acceptance_strength text not null default 'none' references vocab.acceptance_strength (code),
  establishes_course_acceptance boolean not null default false,
  statement text not null,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint policy_facts_limit_chk check (limit_value is null or limit_value >= 0),
  constraint policy_facts_context_chk check (context_value is null or context_value >= 0),
  constraint policy_facts_percentage_chk check (
    limit_is_percentage = false or limit_unit = 'percent'
  ),
  constraint policy_facts_age_chk check (
    course_age_value is null or course_age_value >= 0
  ),
  constraint policy_facts_age_unit_chk check (
    course_age_unit is null or course_age_unit in ('day', 'month', 'year')
  ),
  constraint policy_facts_acceptance_flag_chk check (
    establishes_course_acceptance = false
    or acceptance_strength in ('course', 'provider')
  ),
  constraint policy_facts_statement_chk check (length(btrim(statement)) > 0)
);

create index policy_facts_version_idx
  on policy.policy_facts (policy_version_id);
create index policy_facts_kind_idx
  on policy.policy_facts (fact_kind, source_category);

comment on table policy.policy_facts is
  'Typed policy facts for V1. Null numeric fields mean the source did not establish the number. establishes_course_acceptance is false unless the source names the provider or course. Category illustrations never set that flag.';
comment on column policy.policy_facts.context_value is
  'A second sourced number in the same statement, such as a published degree total beside a transfer cap. It is not a derived remainder.';
comment on column policy.policy_facts.establishes_course_acceptance is
  'True only when this fact is enough to say the institution accepts a named provider or course. Default false. A credit recommendation cannot set it.';

create table policy.policy_fact_providers (
  policy_fact_id uuid not null references policy.policy_facts (id) on delete cascade,
  provider_id uuid not null references alternative.providers (id),
  relationship text not null references vocab.provider_link_relationship (code),
  primary key (policy_fact_id, provider_id)
);

create index policy_fact_providers_provider_idx
  on policy.policy_fact_providers (provider_id);

comment on table policy.policy_fact_providers is
  'relationship = addresses means the policy mentions the provider. It does not mean the provider is accepted.';

create table policy.policy_rules (
  id uuid primary key default gen_random_uuid(),
  policy_version_id uuid not null references policy.policy_versions (id) on delete cascade,
  rule_kind text not null,
  priority integer not null default 100,
  review_flag boolean not null default false,
  description text,
  created_at timestamptz not null default now()
);

create table policy.rule_conditions (
  id uuid primary key default gen_random_uuid(),
  policy_rule_id uuid not null references policy.policy_rules (id) on delete cascade,
  field_name text not null,
  operator text not null,
  operand_text text,
  operand_numeric numeric,
  operand_bool boolean,
  operand_date date,
  created_at timestamptz not null default now(),
  constraint rule_conditions_operand_chk check (
    operand_text is not null
    or operand_numeric is not null
    or operand_bool is not null
    or operand_date is not null
  )
);

create table policy.rule_effects (
  id uuid primary key default gen_random_uuid(),
  policy_rule_id uuid not null references policy.policy_rules (id) on delete cascade,
  effect_type text not null,
  value_text text,
  value_numeric numeric,
  value_uuid uuid,
  created_at timestamptz not null default now(),
  constraint rule_effects_value_chk check (
    value_text is not null or value_numeric is not null or value_uuid is not null
  )
);

comment on table policy.policy_rules is
  'BUILD NEXT. Empty in V1. Typed facts in policy_facts are the operational representation and can migrate here without changing policy or institution identity.';
comment on table policy.rule_conditions is 'BUILD NEXT. Empty in V1.';
comment on table policy.rule_effects is 'BUILD NEXT. Empty in V1.';

create table transfer.course_equivalencies (
  id uuid primary key default gen_random_uuid(),
  source_experience_version_id uuid
    references alternative.learning_experience_versions (id),
  source_course_version_id uuid references academic.course_versions (id),
  destination_institution_id uuid not null references catalog.institutions (id),
  destination_course_version_id uuid references academic.course_versions (id),
  program_version_id uuid references academic.program_versions (id),
  equivalency_type text not null references vocab.equivalency_type (code),
  destination_credits numeric(7, 2),
  credit_unit text references vocab.credit_unit (code),
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  catalog_year text,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  verified_at timestamptz,
  notes text,
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint course_equivalencies_source_chk check (
    source_experience_version_id is not null or source_course_version_id is not null
  ),
  constraint course_equivalencies_direct_chk check (
    equivalency_type <> 'direct_course' or destination_course_version_id is not null
  ),
  constraint course_equivalencies_credits_chk check (
    destination_credits is null or destination_credits >= 0
  ),
  constraint course_equivalencies_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index equivalencies_destination_source_idx
  on transfer.course_equivalencies (
    destination_institution_id,
    source_experience_version_id,
    valid_from
  );
create index equivalencies_destination_course_idx
  on transfer.course_equivalencies (destination_course_version_id);
create index equivalencies_program_idx
  on transfer.course_equivalencies (program_version_id);

comment on table transfer.course_equivalencies is
  'Only destination-authoritative equivalencies belong here. V1 seed contains none. An equivalency does not mean a degree requirement is satisfied, and a credit recommendation must not create a row here.';

create table transfer.articulation_agreements (
  id uuid primary key default gen_random_uuid(),
  source_institution_id uuid references catalog.institutions (id),
  destination_institution_id uuid not null references catalog.institutions (id),
  title text not null,
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  notes text,
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint articulation_agreements_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index articulation_agreements_destination_idx
  on transfer.articulation_agreements (destination_institution_id, valid_from);

comment on table transfer.articulation_agreements is
  'BUILD NEXT home for agreements. Empty in V1. Agreements are not stored as boolean equivalencies.';

create table provenance.research_gaps (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid references catalog.institutions (id),
  entity_type text,
  entity_id uuid,
  topic text not null,
  unresolved_question text not null,
  conflicting_evidence text,
  current_best_evidence text,
  confidence text references vocab.confidence_level (code),
  recommended_action text,
  status text not null default 'open' references vocab.research_gap_status (code),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint research_gaps_resolved_chk check (
    (status = 'resolved' and resolved_at is not null)
    or (status <> 'resolved' and resolved_at is null)
  )
);

create index research_gaps_open_idx
  on provenance.research_gaps (status, institution_id);
create index research_gaps_topic_idx
  on provenance.research_gaps (topic);

comment on table provenance.research_gaps is
  'Internal register of what the extract did not establish. Public API responses say not_documented instead of exposing this queue. Do not fill a gap by guessing.';
