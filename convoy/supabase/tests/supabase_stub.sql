-- Minimal stand-in for the parts of a Supabase project the migrations touch,
-- so the schema and its rules can be tested on plain Postgres in CI.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema auth;
create table auth.users (
  id uuid primary key,
  phone_confirmed_at timestamptz,
  raw_user_meta_data jsonb default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create schema realtime;
create table realtime.messages (id bigserial primary key, topic text, payload jsonb);
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic', true)
$$;
create publication supabase_realtime;
grant usage on schema public, auth, realtime to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated;
grant select, insert on realtime.messages to authenticated;
alter table realtime.messages enable row level security;
grant usage on all sequences in schema realtime to authenticated;
