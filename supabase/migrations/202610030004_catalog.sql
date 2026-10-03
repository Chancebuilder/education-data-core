-- Institution identity is a stable UUID. External identifiers and names are separate, dated facts.

create or replace function catalog.normalize_name(input text)
returns text
language sql
immutable
parallel safe
set search_path = public, pg_temp
as $$
  select trim(both from regexp_replace(
    lower(public.unaccent(coalesce(input, ''))),
    '[^a-z0-9]+',
    ' ',
    'g'
  ));
$$;

comment on function catalog.normalize_name(text) is
  'Lowercase, accent-folded name key for exact and fuzzy lookup. Not a unique identity by itself.';

create table catalog.institutions (
  id uuid primary key default gen_random_uuid(),
  official_name text not null,
  normalized_name text not null,
  institution_type text not null references vocab.institution_type (code),
  country_code char(2) not null default 'US',
  control text references vocab.institution_control (code),
  current_status text not null references vocab.institution_status (code),
  website_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint institutions_country_chk check (country_code ~ '^[A-Z]{2}$'),
  constraint institutions_website_chk check (
    website_url is null or website_url ~ '^https?://'
  ),
  constraint institutions_name_chk check (length(btrim(official_name)) > 0)
);

comment on table catalog.institutions is
  'Stable institutional identity. current_status is a cache of the latest known operating status, not a substitute for institution_status_versions.';
comment on column catalog.institutions.control is
  'Public/private/for-profit control. Null when the V1 extract did not establish it. Do not infer control from reputation.';
comment on column catalog.institutions.current_status is
  'Cache for current-view queries. Historical questions must use institution_status_versions and as-of coverage.';

create unique index institutions_normalized_name_uidx
  on catalog.institutions (normalized_name);
create index institutions_official_name_trgm
  on catalog.institutions using gin (official_name gin_trgm_ops);
create index institutions_normalized_name_trgm
  on catalog.institutions using gin (normalized_name gin_trgm_ops);
create index institutions_status_idx
  on catalog.institutions (current_status);

create table catalog.institution_aliases (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id) on delete cascade,
  alias text not null,
  normalized_alias text not null,
  alias_type text not null references vocab.alias_type (code),
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
  updated_at timestamptz not null default now(),
  constraint institution_aliases_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  ),
  constraint institution_aliases_knowledge_chk check (
    superseded_at is null or superseded_at >= recorded_at
  )
);

create unique index institution_aliases_natural_uidx
  on catalog.institution_aliases (
    institution_id,
    alias_type,
    normalized_alias,
    coalesce(valid_from, date '0001-01-01')
  );
create index institution_aliases_alias_trgm
  on catalog.institution_aliases using gin (alias gin_trgm_ops);
create index institution_aliases_normalized_trgm
  on catalog.institution_aliases using gin (normalized_alias gin_trgm_ops);
create index institution_aliases_institution_idx
  on catalog.institution_aliases (institution_id, valid_from, valid_to);

comment on table catalog.institution_aliases is
  'Names are dated. valid_from and valid_to are inclusive. Year precision means only the year of the stored date is meaningful.';

create table catalog.institution_identifiers (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id) on delete cascade,
  identifier_type text not null references vocab.identifier_type (code),
  identifier_value text not null,
  issuer text not null,
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
  updated_at timestamptz not null default now(),
  constraint institution_identifiers_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  ),
  constraint institution_identifiers_value_chk check (length(btrim(identifier_value)) > 0)
);

create unique index institution_identifiers_natural_uidx
  on catalog.institution_identifiers (
    identifier_type,
    issuer,
    identifier_value,
    coalesce(valid_from, date '0001-01-01')
  );
create index institution_identifiers_institution_idx
  on catalog.institution_identifiers (institution_id);
create index institution_identifiers_value_idx
  on catalog.institution_identifiers (identifier_type, identifier_value);

comment on table catalog.institution_identifiers is
  'External identifiers are not primary keys. V1 does not invent UNITID, OPEID, or DAPIP values that were absent from the extract.';

create table catalog.institution_status_versions (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id) on delete cascade,
  status text not null references vocab.institution_status (code),
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  notes text,
  source_document_id uuid references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint institution_status_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index institution_status_asof_idx
  on catalog.institution_status_versions (institution_id, valid_from, valid_to);

create table catalog.institution_relationships (
  id uuid primary key default gen_random_uuid(),
  from_institution_id uuid not null references catalog.institutions (id),
  to_institution_id uuid not null references catalog.institutions (id),
  relationship_type text not null references vocab.relationship_type (code),
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  notes text,
  source_document_id uuid references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint institution_relationships_distinct_chk check (from_institution_id <> to_institution_id),
  constraint institution_relationships_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index institution_relationships_from_idx
  on catalog.institution_relationships (from_institution_id);
create index institution_relationships_to_idx
  on catalog.institution_relationships (to_institution_id);

comment on table catalog.institution_relationships is
  'Cross-institution succession and system membership. Former names of the same continuing institution stay in institution_aliases.';

create table catalog.accreditors (
  id uuid primary key default gen_random_uuid(),
  official_name text not null,
  acronym text,
  normalized_name text not null unique,
  accreditor_scope text not null references vocab.accreditation_scope (code),
  website_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accreditors_website_chk check (
    website_url is null or website_url ~ '^https?://'
  )
);

create index accreditors_acronym_idx on catalog.accreditors (acronym);
create index accreditors_name_trgm
  on catalog.accreditors using gin (official_name gin_trgm_ops);

create table catalog.accreditor_recognition_history (
  id uuid primary key default gen_random_uuid(),
  accreditor_id uuid not null references catalog.accreditors (id),
  recognition_authority text not null,
  status text not null references vocab.recognition_status (code),
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  notes text,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint accreditor_recognition_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index accreditor_recognition_asof_idx
  on catalog.accreditor_recognition_history (accreditor_id, valid_from, valid_to);

comment on table catalog.accreditor_recognition_history is
  'Whether an accreditor itself was recognized. This is separate from whether an institution held that accreditor''s accreditation.';

create table catalog.institution_accreditations (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id),
  accreditor_id uuid not null references catalog.accreditors (id),
  program_id uuid,
  accreditation_status text not null references vocab.accreditation_status (code),
  accreditation_scope text not null references vocab.accreditation_scope (code),
  historical_classification_label text,
  valid_from date,
  valid_to date,
  from_precision text not null default 'unknown' references vocab.date_precision (code),
  to_precision text not null default 'unknown' references vocab.date_precision (code),
  notes text,
  source_document_id uuid not null references provenance.source_documents (id),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  recorded_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint institution_accreditations_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index institution_accreditations_inst_idx
  on catalog.institution_accreditations (institution_id, valid_from, valid_to);
create index institution_accreditations_accreditor_idx
  on catalog.institution_accreditations (accreditor_id, valid_from, valid_to);
create index institution_accreditations_program_idx
  on catalog.institution_accreditations (program_id);

comment on table catalog.institution_accreditations is
  'Dated accreditation grants. A null validity interval means the extract established a current grant and did not establish its start. Historical as-of queries must not treat that undated row as if it were true in an earlier year.';
comment on column catalog.institution_accreditations.historical_classification_label is
  'Source language such as a historical regional label, stored only when the source used it. V1 does not write regional onto current accreditors.';
comment on column catalog.institution_accreditations.program_id is
  'Set only for programmatic accreditation. Foreign key is added after academic.programs exists.';

create table catalog.search_documents (
  id uuid primary key default gen_random_uuid(),
  entity_schema text not null,
  entity_table text not null,
  entity_id uuid not null,
  search_text text not null,
  updated_at timestamptz not null default now(),
  unique (entity_schema, entity_table, entity_id)
);

create index search_documents_text_trgm
  on catalog.search_documents using gin (search_text gin_trgm_ops);

comment on table catalog.search_documents is
  'Lexical search text for institutions, programs, courses, providers, and learning experiences. V1 does not store embeddings. A later migration can add a pgvector column on this table without changing canonical keys.';
