-- Providers, learning experiences, and credit recommendations.
-- A recommendation does not accept, equate, or apply credit at a destination.

create table alternative.recommendation_bodies (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  official_name text not null,
  awards_credit boolean not null default false,
  binds_destination_institutions boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table alternative.recommendation_bodies is
  'ACE and NCCRS recommend credit. awards_credit and binds_destination_institutions stay false for those bodies: they do not award the destination institution''s credit and do not bind its decision.';

create table alternative.providers (
  id uuid primary key default gen_random_uuid(),
  official_name text not null,
  normalized_name text not null unique,
  provider_type text not null references vocab.provider_type (code),
  website_url text,
  notes text,
  source_document_id uuid references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint providers_website_chk check (
    website_url is null or website_url ~ '^https?://'
  )
);

create index providers_name_trgm
  on alternative.providers using gin (official_name gin_trgm_ops);

create table alternative.learning_experiences (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references alternative.providers (id),
  provider_course_identifier text,
  identifier_status text not null default 'published',
  canonical_title text not null,
  normalized_title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint learning_experiences_identifier_status_chk check (
    identifier_status in ('published', 'not_captured')
  )
);

create unique index learning_experiences_provider_code_uidx
  on alternative.learning_experiences (provider_id, provider_course_identifier)
  where provider_course_identifier is not null;
create unique index learning_experiences_provider_title_uidx
  on alternative.learning_experiences (provider_id, normalized_title);
create index learning_experiences_provider_idx
  on alternative.learning_experiences (provider_id);
create index learning_experiences_title_trgm
  on alternative.learning_experiences using gin (canonical_title gin_trgm_ops);

comment on table alternative.learning_experiences is
  'Stable identity of an external course or exam. identifier_status = not_captured means the provider code was absent from the extract, not that the code is empty on purpose.';

create table alternative.learning_experience_versions (
  id uuid primary key default gen_random_uuid(),
  learning_experience_id uuid not null references alternative.learning_experiences (id) on delete cascade,
  official_title text not null,
  description text,
  subject text,
  passing_threshold text,
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  source_document_id uuid references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint learning_experience_versions_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index learning_experience_versions_experience_idx
  on alternative.learning_experience_versions (learning_experience_id, valid_from, valid_to);

comment on column alternative.learning_experience_versions.subject is
  'Subject only when the recommendation body or provider source stated it. A word in the course title is not stored as an ACE subject area.';
comment on column alternative.learning_experience_versions.passing_threshold is
  'Passing score or grade only when published. Null means not captured.';

create table alternative.credit_recommendations (
  id uuid primary key default gen_random_uuid(),
  learning_experience_version_id uuid not null
    references alternative.learning_experience_versions (id),
  recommendation_body_id uuid not null
    references alternative.recommendation_bodies (id),
  authority_identifier text,
  recommendation_version text,
  recommended_credits numeric(7, 2),
  credit_unit text references vocab.credit_unit (code),
  recommended_level text references vocab.academic_level (code),
  recommended_subject text,
  recommendation_start date not null,
  recommendation_end date,
  start_precision text not null default 'day' references vocab.date_precision (code),
  end_precision text not null default 'day' references vocab.date_precision (code),
  recommendation_notes text,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint credit_recommendations_credits_chk check (
    recommended_credits is null or recommended_credits >= 0
  ),
  constraint credit_recommendations_range_chk check (
    recommendation_end is null or recommendation_end >= recommendation_start
  ),
  constraint credit_recommendations_not_inferred_as_verified_chk check (
    verification_status <> 'verified' or verification_status <> 'inferred'
  )
);

create unique index credit_recommendations_natural_uidx
  on alternative.credit_recommendations (
    learning_experience_version_id,
    recommendation_body_id,
    recommendation_start,
    coalesce(authority_identifier, '')
  );
create index credit_recommendations_period_idx
  on alternative.credit_recommendations (
    learning_experience_version_id,
    recommendation_start,
    recommendation_end
  );
create index credit_recommendations_authority_idx
  on alternative.credit_recommendations (authority_identifier);

comment on table alternative.credit_recommendations is
  'A recommendation period is inclusive. recommended_credits, level, and subject are null when the extract did not state them. This table never implies destination acceptance.';

-- The check above is tautological and was a placeholder. Replace it with a real rule:
alter table alternative.credit_recommendations
  drop constraint credit_recommendations_not_inferred_as_verified_chk;

alter table alternative.credit_recommendations
  add constraint credit_recommendations_inferred_not_verified_chk
  check (verification_status <> 'inferred' or confidence <> 'high');

comment on constraint credit_recommendations_inferred_not_verified_chk
  on alternative.credit_recommendations is
  'An inferred recommendation cannot be stored at high confidence. Inference is not used in the V1 extract.';
