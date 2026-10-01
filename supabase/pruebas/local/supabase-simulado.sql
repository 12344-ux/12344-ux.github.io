-- ============================================================
-- Impulse · Entorno LOCAL que imita lo minimo de Supabase para probar
-- las migraciones de este repo SIN tocar el proyecto real.
-- ------------------------------------------------------------
-- NO se ejecuta en Supabase. Lo usa supabase/pruebas/local/correr-local.sh
-- sobre un PostgreSQL local vacio, antes de aplicar las migraciones.
--
-- Que imita (lo que las migraciones y las pruebas necesitan):
--   * Roles anon / authenticated / service_role (service_role con BYPASSRLS,
--     igual que en Supabase) y su membresia para que postgres haga SET ROLE.
--   * Esquema auth con auth.users minima y auth.uid() / auth.role() leyendo
--     request.jwt.claims, exactamente como lo hace Supabase.
--   * Privilegios por defecto de Supabase sobre FUNCIONES (EXECUTE a anon,
--     authenticated y service_role). Es el peor caso realista: por eso el
--     Tramo 0 revoca y otorga nominalmente.
--   * Tablas SIN grant por defecto (el proyecto real tiene
--     "auto-expose new tables" en OFF).
--   * El usuario administrador real (mismo UID) para que la semilla de
--     perfiles no falle por la FK a auth.users.
-- ============================================================

-- Los roles son globales del servidor: se crean solo si no existen (permite
-- recrear la base de pruebas varias veces en el mismo servidor).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;
grant anon, authenticated, service_role to postgres;

grant usage on schema public to anon, authenticated, service_role;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id    uuid primary key,
  email text
);

create function auth.uid() returns uuid
language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')
    ), ''
  )::uuid
$$;

create function auth.role() returns text
language sql stable as $$
  select coalesce(
    current_setting('request.jwt.claim.role', true),
    (current_setting('request.jwt.claims', true)::jsonb ->> 'role')
  )
$$;

grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;

-- Default privileges de Supabase para funciones nuevas en public.
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

-- Administrador real (la migracion 20250101000000 lo siembra en perfiles).
insert into auth.users (id, email)
values ('89e5028d-8c17-4deb-89c3-59acbd0ee2f2', 'admin@local.invalid');
