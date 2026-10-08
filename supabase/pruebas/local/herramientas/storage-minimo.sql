create schema if not exists storage;
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create table if not exists storage.buckets (id text primary key, name text, public boolean default false);
grant usage on schema storage to anon, authenticated, service_role;
