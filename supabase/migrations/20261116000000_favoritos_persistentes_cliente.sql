-- ============================================================================
-- MAGANDHI · Cuenta cliente · favoritos persistentes
-- ----------------------------------------------------------------------------
-- Mantiene la identidad del favorito aunque una campaña salga del catálogo.
-- La única lectura y escritura cliente ocurre mediante RPC owner-safe.
-- ============================================================================

begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

create table public.favoritos_cliente (
  auth_user_id uuid        not null,
  campana_id   uuid        not null,
  creado       timestamptz not null default now(),
  constraint favoritos_cliente_pkey
    primary key (auth_user_id, campana_id),
  constraint favoritos_cliente_auth_user_id_fkey
    foreign key (auth_user_id)
    references public.cuentas_cliente(auth_user_id)
    on delete cascade,
  constraint favoritos_cliente_campana_id_fkey
    foreign key (campana_id)
    references public.campana_producto(id)
    on delete restrict
);

comment on table public.favoritos_cliente is
  'Favoritos persistentes de cuentas cliente. Conserva la referencia si una campaña deja de estar publicada; toda operación del navegador pasa por fv_*.';
comment on column public.favoritos_cliente.auth_user_id is
  'Cuenta propietaria derivada exclusivamente de auth.uid(); nunca llega como argumento RPC.';
comment on column public.favoritos_cliente.campana_id is
  'Campaña marcada como favorita. La baja física se restringe para conservar la preferencia.';
comment on column public.favoritos_cliente.creado is
  'Instante de la primera marcación. Repetir el alta no lo modifica.';

alter table public.favoritos_cliente enable row level security;

-- Sin políticas ni privilegios directos: las funciones SECURITY DEFINER son la
-- única superficie, incluso para service_role en esta tabla.
revoke all on table public.favoritos_cliente
  from public, anon, authenticated, service_role;

-- Retira cualquier firma anterior para que PostgREST exponga una sola RPC por
-- nombre y ninguna variante pueda aceptar identidad desde el navegador.
do $drop_overloads$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as firma, p.prokind
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fv_favoritos_listar', 'fv_favorito_establecer')
       and p.prokind in ('f', 'p')
  loop
    execute format(
      'drop %s %s',
      case when r.prokind = 'p' then 'procedure' else 'function' end,
      r.firma
    );
  end loop;
end
$drop_overloads$;

-- Devuelve todos los favoritos de la cuenta, más recientes primero.
-- catalogo_publico es la única fuente de presentación; una retirada queda
-- identificable y no filtra ningún dato de campana_producto.
create function public.fv_favoritos_listar()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_estado text;
  v_favoritos jsonb;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'FV_SESION_REQUERIDA';
  end if;

  select cc.estado
    into v_estado
    from public.cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for share;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'FV_CUENTA_NO_DISPONIBLE';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'campana_id', fv.campana_id,
               'creado', fv.creado,
               'nombre', case when cp.id is not null then cp.nombre else null end,
               'slug', case when cp.id is not null then cp.slug else null end,
               'precio_venta', case when cp.id is not null then cp.precio_venta else null end,
               'imagenes', case when cp.id is not null then cp.imagenes else null end,
               'imagen_banner_path', case when cp.id is not null then cp.imagen_banner_path else null end,
               'max_comprable', case when cp.id is not null then cp.max_comprable else 0 end,
               'disponible', (
                 cp.id is not null
                 and coalesce(cp.precio_venta, 0) > 0
                 and coalesce(cp.max_comprable, 0) > 0
               )
             )
             order by fv.creado desc, fv.campana_id desc
           ),
           '[]'::jsonb
         )
    into v_favoritos
    from public.favoritos_cliente fv
    left join public.catalogo_publico cp on cp.id = fv.campana_id
   where fv.auth_user_id = v_uid;

  return jsonb_build_object('favoritos', v_favoritos);
end;
$fn$;

comment on function public.fv_favoritos_listar() is
  'Cuenta cliente · snapshot owner-safe de todos sus favoritos. Enriquece solo con catalogo_publico y conserva retirados con presentación nula/no disponible.';

-- Establece el estado deseado, no una transición: repetir true o false produce
-- el mismo resultado. Solo el alta exige presencia actual en catalogo_publico.
create function public.fv_favorito_establecer(
  p_campana_id uuid,
  p_favorito boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_estado text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'FV_SESION_REQUERIDA';
  end if;

  select cc.estado
    into v_estado
    from public.cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'FV_CUENTA_NO_DISPONIBLE';
  end if;

  if p_campana_id is null or p_favorito is null then
    raise exception using errcode = 'P0001', message = 'FV_SOLICITUD_INVALIDA';
  end if;

  if p_favorito then
    -- Si ya estaba guardado, repetir true conserva el estado aunque la campaña
    -- se haya retirado después de la primera respuesta.
    perform 1
      from public.favoritos_cliente fv
     where fv.auth_user_id = v_uid
       and fv.campana_id = p_campana_id;

    if not found then
      -- Serializa el alta con publicación/despublicación antes de consultar la
      -- vista pública. No toma locks de Inventario ni altera esos flujos.
      perform 1
        from public.campana_producto cp
       where cp.id = p_campana_id
       for share;
      if not found then
        raise exception using errcode = 'P0001', message = 'FV_CAMPANA_NO_DISPONIBLE';
      end if;

      perform 1
        from public.catalogo_publico cp
       where cp.id = p_campana_id;
      if not found then
        raise exception using errcode = 'P0001', message = 'FV_CAMPANA_NO_DISPONIBLE';
      end if;

      insert into public.favoritos_cliente (auth_user_id, campana_id)
      values (v_uid, p_campana_id)
      on conflict (auth_user_id, campana_id) do nothing;
    end if;
  else
    delete from public.favoritos_cliente fv
     where fv.auth_user_id = v_uid
       and fv.campana_id = p_campana_id;
  end if;

  return public.fv_favoritos_listar();
end;
$fn$;

comment on function public.fv_favorito_establecer(uuid, boolean) is
  'Cuenta cliente · fija idempotentemente un favorito de auth.uid(). El alta exige catálogo público; la baja funciona aunque la campaña esté retirada y devuelve el snapshot completo.';

-- Superficie RPC exacta: sesión autenticada y service_role. Sin acceso anon ni
-- privilegio heredado de PUBLIC; ninguna firma recibe UID.
revoke all on function public.fv_favoritos_listar()
  from public, anon, authenticated, service_role;
revoke all on function public.fv_favorito_establecer(uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.fv_favoritos_listar()
  to authenticated, service_role;
grant execute on function public.fv_favorito_establecer(uuid, boolean)
  to authenticated, service_role;

-- Gates estructurales para que la forward falle completa ante una superficie
-- distinta de la acordada.
do $postflight$
declare
  v_listar oid := to_regprocedure('public.fv_favoritos_listar()');
  v_establecer oid := to_regprocedure('public.fv_favorito_establecer(uuid,boolean)');
begin
  if not (
    select c.relrowsecurity
      from pg_class c
     where c.oid = 'public.favoritos_cliente'::regclass
  ) then
    raise exception using errcode = 'P0001', message = 'FV_RLS_INVALIDO';
  end if;

  if exists (
    select 1
      from pg_policy p
     where p.polrelid = 'public.favoritos_cliente'::regclass
  ) then
    raise exception using errcode = 'P0001', message = 'FV_ACCESO_DIRECTO_INVALIDO';
  end if;

  if v_listar is null or v_establecer is null
     or exists (
       select 1
         from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('fv_favoritos_listar', 'fv_favorito_establecer')
          and p.oid not in (v_listar, v_establecer)
     ) then
    raise exception using errcode = 'P0001', message = 'FV_FIRMAS_INVALIDAS';
  end if;

  if exists (
    select 1
      from pg_proc p
     where p.oid in (v_listar, v_establecer)
       and (
         not p.prosecdef
         or p.prorettype <> 'jsonb'::regtype
         or coalesce(p.proconfig, '{}'::text[])
              <> array['search_path=pg_catalog, public']::text[]
       )
  ) then
    raise exception using errcode = 'P0001', message = 'FV_FUNCIONES_INVALIDAS';
  end if;

  if has_function_privilege('anon', v_listar, 'execute')
     or has_function_privilege('anon', v_establecer, 'execute')
     or not has_function_privilege('authenticated', v_listar, 'execute')
     or not has_function_privilege('authenticated', v_establecer, 'execute')
     or not has_function_privilege('service_role', v_listar, 'execute')
     or not has_function_privilege('service_role', v_establecer, 'execute') then
    raise exception using errcode = 'P0001', message = 'FV_RPC_ACL_INVALIDA';
  end if;
end;
$postflight$;

commit;
