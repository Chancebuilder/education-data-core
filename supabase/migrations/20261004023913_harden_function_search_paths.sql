-- Production hardening synchronized from hosted Supabase.
-- Fixes Supabase lint 0011_function_search_path_mutable without changing function behavior.

alter function internal.set_updated_at() set search_path = '';
alter function api.format_temporal(date,text) set search_path = '';
alter function api.envelope_meta(date) set search_path = '';
alter function api.credits_are_comparable(text,text) set search_path = '';
alter function api.health() set search_path = '';
alter function api.get_record_provenance(text,text,uuid) set search_path = 'pg_catalog','api','provenance';
alter function api.temporal_object(date,date,text,text,date,timestamptz,timestamptz) set search_path = 'pg_catalog','api';
