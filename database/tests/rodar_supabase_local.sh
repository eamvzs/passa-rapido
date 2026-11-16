#!/usr/bin/env bash
# Recria o banco local que imita o Supabase (papéis, auth, privilégios padrão) e instala os scripts.
set -euo pipefail
DB="${1:-pr_supa14}"; shift || true
cd "$(dirname "$0")/.."
psql -U postgres -q -c "drop database if exists $DB" -c "create database $DB"
psql -U postgres -q -d $DB <<'SQL'
do $$ begin if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if; end $$;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
create publication supabase_realtime;
SQL
for f in "$@"; do
  psql -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f $f 2>&1 | grep -E "ERROR" || true
done
