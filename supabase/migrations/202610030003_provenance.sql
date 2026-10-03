-- Sources and evidence. Research gaps that reference institutions are created after catalog.

create table provenance.source_documents (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  source_url text,
  source_title text not null,
  source_type text not null references vocab.source_type (code),
  publisher text,
  authority_scope text references vocab.authority_scope (code),
  published_at date,
  retrieved_at timestamptz not null,
  effective_from date,
  effective_to date,
  academic_year text,
  archive_url text,
  content_sha256 text,
  extraction_method text not null references vocab.extraction_method (code),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint source_documents_url_chk check (
    source_url is null or source_url ~ '^https?://'
  ),
  constraint source_documents_archive_url_chk check (
    archive_url is null or archive_url ~ '^https?://'
  ),
  constraint source_documents_effective_chk check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);

comment on table provenance.source_documents is
  'One row per cited source. Large document bodies are not copied here. A null URL means the research extract did not retain a primary locator.';
comment on column provenance.source_documents.retrieved_at is
  'When the fact was retrieved. For the V1 extract this is the research verification timestamp, not a later live refetch.';

create table provenance.evidence (
  id uuid primary key default gen_random_uuid(),
  source_document_id uuid not null references provenance.source_documents (id),
  page_number integer,
  section_locator text,
  evidence_summary text not null,
  evidence_excerpt text,
  evidence_role text not null references vocab.evidence_role (code),
  extraction_method text not null references vocab.extraction_method (code),
  verification_status text not null references vocab.verification_status (code),
  confidence text not null references vocab.confidence_level (code),
  manually_verified boolean not null default false,
  verified_at timestamptz,
  reviewer_label text,
  created_at timestamptz not null default now(),
  constraint evidence_page_chk check (page_number is null or page_number > 0)
);

comment on table provenance.evidence is
  'A located summary or excerpt inside a source document. Excerpts from the V1 extract are research paraphrases unless the notes say they are verbatim.';

create table provenance.fact_evidence_links (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references provenance.evidence (id) on delete cascade,
  fact_schema text not null,
  fact_table text not null,
  fact_id uuid not null,
  link_role text not null references vocab.evidence_role (code),
  created_at timestamptz not null default now(),
  unique (evidence_id, fact_schema, fact_table, fact_id, link_role)
);

create index fact_evidence_links_fact_idx
  on provenance.fact_evidence_links (fact_schema, fact_table, fact_id);

comment on table provenance.fact_evidence_links is
  'Many facts can share one source, and one fact can have supporting and contradicting evidence.';

create index source_documents_type_idx on provenance.source_documents (source_type);
create index source_documents_retrieved_idx on provenance.source_documents (retrieved_at);
create index evidence_source_idx on provenance.evidence (source_document_id);
