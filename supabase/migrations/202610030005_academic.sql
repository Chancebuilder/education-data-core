-- Programs and courses. Identity is stable; catalog content lives on versions.
-- Requirement nodes exist so a later solver can attach trees without new identity keys.
-- V1 seed does not invent requirement trees.

create table academic.program_categories (
  code text primary key,
  label text not null
);

insert into academic.program_categories (code, label) values
  ('health_sciences', 'Health sciences'),
  ('business', 'Business'),
  ('general', 'General or undeclared'),
  ('other', 'Other'),
  ('unknown', 'Category not established');

create table academic.programs (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id),
  official_program_family_name text not null,
  normalized_name text not null,
  program_category text not null references academic.program_categories (code),
  degree_type text not null references vocab.degree_type (code),
  cip_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index programs_natural_uidx
  on academic.programs (institution_id, normalized_name, degree_type);
create index programs_institution_idx on academic.programs (institution_id);
create index programs_name_trgm
  on academic.programs using gin (official_program_family_name gin_trgm_ops);

comment on table academic.programs is
  'A continuing program family. Requirements change on program_versions, not by overwriting this row.';
comment on column academic.programs.cip_code is
  'CIP code when a source establishes it. V1 leaves it null rather than guessing.';

create table academic.program_versions (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references academic.programs (id) on delete cascade,
  version_label text,
  academic_catalog_year text,
  official_program_name text not null,
  total_credits numeric(7, 2),
  credit_unit text references vocab.credit_unit (code),
  delivery_modality text references vocab.delivery_modality (code),
  status text not null default 'unknown' references vocab.institution_status (code),
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
  constraint program_versions_credits_chk check (
    total_credits is null or total_credits >= 0
  ),
  constraint program_versions_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index program_versions_asof_idx
  on academic.program_versions (program_id, valid_from, valid_to);
create index program_versions_name_trgm
  on academic.program_versions using gin (official_program_name gin_trgm_ops);

comment on table academic.program_versions is
  'One catalog incarnation of a program. total_credits and credit_unit stay null when the extract did not state them. Semester and quarter credits are never implied.';
comment on column academic.program_versions.status is
  'Reuses institution status codes only for active, closed, and unknown. V1 program pages are not assumed active merely because a transfer example mentioned them.';

create table academic.institution_courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references catalog.institutions (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index institution_courses_institution_idx
  on academic.institution_courses (institution_id);

comment on table academic.institution_courses is
  'Stable identity of a destination course across code and title changes. V1 has no invented catalog courses.';

create table academic.course_versions (
  id uuid primary key default gen_random_uuid(),
  institution_course_id uuid not null references academic.institution_courses (id) on delete cascade,
  course_code text not null,
  normalized_course_code text not null,
  official_title text not null,
  credits numeric(7, 2),
  credit_unit text references vocab.credit_unit (code),
  academic_level text references vocab.academic_level (code),
  subject text,
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
  constraint course_versions_credits_chk check (credits is null or credits >= 0),
  constraint course_versions_range_chk check (
    valid_to is null or valid_from is null or valid_to >= valid_from
  )
);

create index course_versions_code_idx
  on academic.course_versions (institution_course_id, normalized_course_code);
create index course_versions_title_trgm
  on academic.course_versions using gin (official_title gin_trgm_ops);
create index course_versions_code_trgm
  on academic.course_versions using gin (normalized_course_code gin_trgm_ops);

create table academic.requirement_nodes (
  id uuid primary key default gen_random_uuid(),
  program_version_id uuid not null references academic.program_versions (id) on delete cascade,
  parent_id uuid references academic.requirement_nodes (id) on delete cascade,
  node_type text not null,
  label text,
  min_credits numeric(7, 2),
  min_courses integer,
  sort_order integer not null default 0,
  source_document_id uuid references provenance.source_documents (id),
  verification_status text not null default 'unreviewed' references vocab.verification_status (code),
  notes text,
  created_at timestamptz not null default now(),
  constraint requirement_nodes_type_chk check (
    node_type in (
      'ALL', 'ANY', 'MIN_CREDITS', 'MIN_COURSES', 'COURSE',
      'CATEGORY', 'ATTRIBUTE', 'RESIDENCY', 'GPA'
    )
  ),
  constraint requirement_nodes_credits_chk check (
    min_credits is null or min_credits >= 0
  ),
  constraint requirement_nodes_courses_chk check (
    min_courses is null or min_courses >= 0
  )
);

create index requirement_nodes_program_idx
  on academic.requirement_nodes (program_version_id);
create index requirement_nodes_parent_idx
  on academic.requirement_nodes (parent_id);

comment on table academic.requirement_nodes is
  'BUILD NEXT compatibility. Empty in V1. Practical maximum transfer is a future solver output, not a stored institutional attribute.';

create table academic.requirement_bindings (
  id uuid primary key default gen_random_uuid(),
  requirement_node_id uuid not null references academic.requirement_nodes (id) on delete cascade,
  target_kind text not null,
  course_version_id uuid references academic.course_versions (id),
  category_code text,
  attribute_code text,
  credits numeric(7, 2),
  created_at timestamptz not null default now(),
  constraint requirement_bindings_kind_chk check (
    target_kind in ('course_version', 'category', 'attribute', 'residency')
  ),
  constraint requirement_bindings_target_chk check (
    (target_kind = 'course_version' and course_version_id is not null)
    or (target_kind = 'category' and category_code is not null)
    or (target_kind = 'attribute' and attribute_code is not null)
    or (target_kind = 'residency')
  )
);

create index requirement_bindings_node_idx
  on academic.requirement_bindings (requirement_node_id);
create index requirement_bindings_course_idx
  on academic.requirement_bindings (course_version_id);

comment on table academic.requirement_bindings is
  'BUILD NEXT. A binding is an authoritative mapping target. It is still not a learner-specific degree-audit result.';

alter table catalog.institution_accreditations
  add constraint institution_accreditations_program_fk
  foreign key (program_id) references academic.programs (id);
