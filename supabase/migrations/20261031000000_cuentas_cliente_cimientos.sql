-- ============================================================================
-- MAGANDHI · CUENTAS DE CLIENTE C1 · IDENTIDAD Y FRONTERA INTERNA
-- ----------------------------------------------------------------------------
-- OBJETIVO
--   Preparar cuentas publicas SIN abrir todavia registro/login en la tienda y
--   SIN cambiar los UUID comerciales existentes:
--     auth.users.id  = identidad de acceso (sesion)
--     clientes.id    = identidad comercial (pedidos, compras, opiniones)
--     cuentas_cliente = puente 1:0..1 entre las dos
--
-- FRONTERA FIRME
--   perfiles sigue siendo EXCLUSIVO del personal de montaguth.institute.
--   cuentas_cliente es EXCLUSIVO de clientes de magandhi.com. Un mismo UID no
--   puede estar en ambas tablas: si una persona del equipo quiere comprar con
--   cuenta de cliente, usa otra identidad o compra como invitada.
--
-- ESTE TRAMO NO HACE
--   No crea usuarios, no vincula por correo, no abre pedidos a authenticated,
--   no cambia Wompi ni opiniones y no concede escritura desde el navegador.
--   C2 hara el alta solo despues de confirmar el correo.
-- ============================================================================

begin;

create table if not exists cuentas_cliente (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  customer_id  uuid unique references clientes(id) on delete restrict,
  estado       text not null default 'activa'
                 check (estado in ('activa', 'bloqueada', 'cerrada')),
  vinculado_en timestamptz,
  creado       timestamptz not null default now(),
  actualizado  timestamptz not null default now(),
  constraint cuentas_cliente_vinculo_coherente check (
    (customer_id is null and vinculado_en is null)
    or (customer_id is not null and vinculado_en is not null)
  )
);

comment on table cuentas_cliente is
  'CUENTAS PUBLICAS · puente entre Supabase Auth y clientes.id. No reemplaza customer_id ni crea acceso interno. Una cuenta puede existir sin compra/customer_id; C2 vinculara solo tras verificar el correo.';
comment on column cuentas_cliente.auth_user_id is
  'UID de Supabase Auth. Exclusivo de tienda: un trigger impide que el mismo UID exista en perfiles (personal interno).';
comment on column cuentas_cliente.customer_id is
  'Cliente comercial enlazado. Nullable hasta la primera compra o hasta vincular historial por correo VERIFICADO. UNIQUE: una cuenta por cliente y un cliente por cuenta.';
comment on column cuentas_cliente.estado is
  'Estado de acceso de la cuenta publica. Solo activa habilita mi_cliente_id(); no borra pedidos ni historia comercial.';

alter table cuentas_cliente enable row level security;

-- El navegador solo puede LEER su propio puente. Cero INSERT/UPDATE/DELETE:
-- C2 usara una puerta server-side que compruebe correo confirmado y colisiones.
revoke all on table cuentas_cliente from public, anon, authenticated;
grant select on table cuentas_cliente to authenticated;

drop policy if exists cuentas_cliente_lectura_propia on cuentas_cliente;
create policy cuentas_cliente_lectura_propia on cuentas_cliente
  for select
  to authenticated
  using ((select auth.uid()) = auth_user_id);

-- --------------------------------------------------------------------------
-- Separacion personal <-> cliente, impuesta en los dos sentidos.
-- --------------------------------------------------------------------------
create or replace function cc__impedir_personal_como_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Los dos triggers bloquean LA MISMA fila antes de mirar la tabla opuesta.
  -- Sin esto, dos altas simultaneas podrian ver ambas tablas vacias y confirmar
  -- el mismo UID como cliente y personal. El bloqueo dura la transaccion.
  perform 1 from auth.users where id = new.auth_user_id for update;
  if not found then raise exception 'CC_AUTH_NO_EXISTE'; end if;

  if exists (select 1 from perfiles where id = new.auth_user_id) then
    raise exception 'CC_IDENTIDAD_ES_PERSONAL';
  end if;
  return new;
end;
$$;

create or replace function cc__impedir_cliente_como_personal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Mismo bloqueo transaccional que usa cuentas_cliente (ver arriba).
  perform 1 from auth.users where id = new.id for update;
  if not found then raise exception 'CC_AUTH_NO_EXISTE'; end if;

  if exists (select 1 from cuentas_cliente where auth_user_id = new.id) then
    raise exception 'CC_IDENTIDAD_ES_CLIENTE';
  end if;
  return new;
end;
$$;

revoke execute on function cc__impedir_personal_como_cliente() from public, anon, authenticated;
revoke execute on function cc__impedir_cliente_como_personal() from public, anon, authenticated;
grant execute on function cc__impedir_personal_como_cliente() to service_role;
grant execute on function cc__impedir_cliente_como_personal() to service_role;

drop trigger if exists trg_cc_separar_de_personal on cuentas_cliente;
create trigger trg_cc_separar_de_personal
  before insert or update of auth_user_id on cuentas_cliente
  for each row execute function cc__impedir_personal_como_cliente();

drop trigger if exists trg_perfiles_separar_de_cliente on perfiles;
create trigger trg_perfiles_separar_de_cliente
  before insert or update of id on perfiles
  for each row execute function cc__impedir_cliente_como_personal();

-- --------------------------------------------------------------------------
-- Helpers de identidad. Son deliberadamente pequenos: no exponen correo, PII
-- ni auth.users. Las futuras superficies de Mi cuenta los usaran en RLS/RPC.
-- --------------------------------------------------------------------------
create or replace function es_personal_interno()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from perfiles where id = (select auth.uid()));
$$;

create or replace function es_cuenta_cliente()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from cuentas_cliente
     where auth_user_id = (select auth.uid())
       and estado = 'activa'
  );
$$;

create or replace function mi_cliente_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select customer_id
    from cuentas_cliente
   where auth_user_id = (select auth.uid())
     and estado = 'activa';
$$;

comment on function es_personal_interno() is
  'True solo si auth.uid() tiene perfil de PERSONAL. Una sesion Auth de cliente devuelve false.';
comment on function es_cuenta_cliente() is
  'True solo si auth.uid() tiene una cuenta publica activa. No concede acceso a pedidos por si sola.';
comment on function mi_cliente_id() is
  'Customer UUID comercial de la cuenta activa actual, o null si aun no tiene compra/vinculo. Nunca acepta IDs del navegador.';

revoke execute on function es_personal_interno() from public, anon;
revoke execute on function es_cuenta_cliente() from public, anon;
revoke execute on function mi_cliente_id() from public, anon;
grant execute on function es_personal_interno() to authenticated, service_role;
grant execute on function es_cuenta_cliente() to authenticated, service_role;
grant execute on function mi_cliente_id() to authenticated, service_role;

commit;
