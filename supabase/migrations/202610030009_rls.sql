-- Row level security.
-- Public reference data is readable by edu_anon and edu_app.
-- Research gaps, raw payloads, and audit logs are staff-only.
-- Table owners that are superusers still bypass RLS; the API role must not be a superuser.
-- FORCE ROW LEVEL SECURITY makes a non-superuser owner obey the policies too.

grant usage on schema
  vocab, catalog, academic, alternative, policy, transfer, provenance, api
  to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;

grant usage on schema raw, internal to edu_ingest, edu_admin, edu_editor;
grant usage on schema learner to edu_admin;

grant select on all tables in schema vocab to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
grant select on all tables in schema catalog to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
grant select on all tables in schema academic to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
grant select on all tables in schema alternative to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
grant select on all tables in schema policy to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;
grant select on all tables in schema transfer to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;

grant select on
  provenance.source_documents,
  provenance.evidence,
  provenance.fact_evidence_links
  to edu_anon, edu_app, edu_editor, edu_ingest, edu_admin;

grant select, insert, update, delete on provenance.research_gaps
  to edu_editor, edu_ingest, edu_admin;

grant select, insert, update, delete on all tables in schema catalog
  to edu_editor, edu_ingest, edu_admin;
grant select, insert, update, delete on all tables in schema academic
  to edu_editor, edu_ingest, edu_admin;
grant select, insert, update, delete on all tables in schema alternative
  to edu_editor, edu_ingest, edu_admin;
grant select, insert, update, delete on all tables in schema policy
  to edu_editor, edu_ingest, edu_admin;
grant select, insert, update, delete on all tables in schema transfer
  to edu_editor, edu_ingest, edu_admin;
grant select, insert, update, delete on
  provenance.source_documents,
  provenance.evidence,
  provenance.fact_evidence_links
  to edu_editor, edu_ingest, edu_admin;

grant select, insert, update, delete on all tables in schema raw to edu_ingest, edu_admin;
grant select, insert, update, delete on all tables in schema internal to edu_ingest, edu_admin;
grant select on internal.import_batches, internal.change_log to edu_editor;

grant execute on function internal.set_updated_at() to edu_editor, edu_ingest, edu_admin;
grant execute on function internal.log_change() to edu_editor, edu_ingest, edu_admin;
grant execute on function internal.run_data_quality_checks() to edu_editor, edu_ingest, edu_admin;

revoke all on function internal.set_updated_at() from public;
revoke all on function internal.log_change() from public;
revoke all on function internal.run_data_quality_checks() from public;

do $$
declare
  r record;
begin
  for r in
    select n.nspname as schemaname, c.relname as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and (
        n.nspname in ('catalog', 'academic', 'alternative', 'policy', 'transfer', 'vocab')
        or (n.nspname = 'provenance' and c.relname <> 'research_gaps')
      )
  loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
    execute format('alter table %I.%I force row level security', r.schemaname, r.tablename);
    execute format('drop policy if exists %I on %I.%I', r.tablename || '_public_read', r.schemaname, r.tablename);
    execute format(
      'create policy %I on %I.%I for select to edu_anon, edu_app using (true)',
      r.tablename || '_public_read',
      r.schemaname,
      r.tablename
    );
    execute format('drop policy if exists %I on %I.%I', r.tablename || '_staff_write', r.schemaname, r.tablename);
    execute format(
      'create policy %I on %I.%I for all to edu_editor, edu_ingest, edu_admin using (true) with check (true)',
      r.tablename || '_staff_write',
      r.schemaname,
      r.tablename
    );
  end loop;
end $$;

alter table provenance.research_gaps enable row level security;
alter table provenance.research_gaps force row level security;
create policy research_gaps_staff on provenance.research_gaps
  for all to edu_editor, edu_ingest, edu_admin
  using (true) with check (true);

alter table raw.source_payloads enable row level security;
alter table raw.source_payloads force row level security;
create policy source_payloads_ingest on raw.source_payloads
  for all to edu_ingest, edu_admin
  using (true) with check (true);

alter table internal.import_batches enable row level security;
alter table internal.import_batches force row level security;
create policy import_batches_staff on internal.import_batches
  for all to edu_ingest, edu_admin
  using (true) with check (true);
create policy import_batches_editor_read on internal.import_batches
  for select to edu_editor
  using (true);

alter table internal.change_log enable row level security;
alter table internal.change_log force row level security;
create policy change_log_staff on internal.change_log
  for all to edu_ingest, edu_admin
  using (true) with check (true);
create policy change_log_editor_read on internal.change_log
  for select to edu_editor
  using (true);

-- Supabase Data API roles, when present, inherit the matching education role.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant edu_anon to anon';
    execute 'grant usage on schema api to anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant edu_app to authenticated';
    execute 'grant usage on schema api to authenticated';
  end if;
end $$;

comment on policy research_gaps_staff on provenance.research_gaps is
  'The research queue is internal. Anonymous and application roles have no policy and no grant, so they see nothing.';
