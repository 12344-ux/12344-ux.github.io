-- ============================================================================
-- MAGANDHI · COMERCIAL C2 · CARRITO PERSISTENTE
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261102000000. No modifica migraciones históricas.
--
-- El carrito pertenece al UID de Auth, no a clientes.id. Una cuenta activa sin
-- customer_id puede usarlo. C2 no reserva stock, no congela precio, no consume
-- el carrito y no cambia compra inmediata, compra invitada, Wompi ni pedidos.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Interruptor privado y techo de líneas distintas.
-- ----------------------------------------------------------------------------
create table if not exists comercial_config (
  id                   smallint primary key default 1,
  carrito_habilitado   boolean not null default false,
  max_lineas_carrito   integer not null default 20,
  actualizado          timestamptz not null default now(),
  constraint comercial_config_singleton check (id = 1),
  constraint comercial_config_max_lineas_rango check (max_lineas_carrito between 1 and 20)
);

insert into comercial_config (id, carrito_habilitado, max_lineas_carrito)
values (1, false, 20)
on conflict (id) do nothing;

comment on table comercial_config is
  'PRIVADA · configuración singleton de Comercial C2. El carrito nace apagado y admite como máximo 1..20 líneas distintas. No se expone al navegador.';
comment on column comercial_config.carrito_habilitado is
  'Interruptor operativo del carrito autenticado. false rechaza todas las RPC C2 sin afectar compra inmediata o invitada.';
comment on column comercial_config.max_lineas_carrito is
  'Máximo configurable de campañas distintas por carrito; nunca puede superar el techo técnico de 20.';

alter table comercial_config enable row level security;
revoke all on table comercial_config from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- (B) Cabecera por UID y líneas mínimas. No se persiste precio, cliente,
--     producto, stock ni disponibilidad.
-- ----------------------------------------------------------------------------
create table if not exists carritos (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references cuentas_cliente(auth_user_id) on delete cascade,
  estado       text not null default 'activa'
                 check (estado in ('activa', 'cerrada')),
  version      bigint not null default 0 check (version >= 0),
  creado       timestamptz not null default now(),
  actualizado  timestamptz not null default now()
);

create unique index if not exists carritos_una_activa_por_uid
  on carritos (auth_user_id)
  where estado = 'activa';

create index if not exists carritos_auth_user_id_idx
  on carritos (auth_user_id);

comment on table carritos is
  'Comercial C2 · cabecera persistente por UID de Auth. Solo puede existir una activa por cuenta; cerrarla conserva historia.';
comment on column carritos.auth_user_id is
  'Propietario Auth del carrito. Referencia cuentas_cliente, nunca clientes.id.';
comment on column carritos.version is
  'Versión monotónica para concurrencia optimista. Cada mutación efectiva de una línea la incrementa exactamente una vez.';

create table if not exists carrito_items (
  carrito_id uuid not null references carritos(id) on delete cascade,
  campana_id uuid not null references campana_producto(id) on delete restrict,
  cantidad   integer not null check (cantidad between 1 and 20),
  creado     timestamptz not null default now(),
  actualizado timestamptz not null default now(),
  primary key (carrito_id, campana_id)
);

comment on table carrito_items is
  'Comercial C2 · selección mínima de campaña y cantidad. Precio, customer_id, product_id, stock y máximos siempre se releen; no se reservan ni persisten aquí.';
comment on column carrito_items.cantidad is
  'Cantidad explícita solicitada (1..20). Nunca se reduce ni elimina automáticamente cuando cambia la disponibilidad.';

-- El reloj de concurrencia nunca retrocede, incluso ante una actualización
-- privilegiada fuera de las RPC. Repetir el valor no es una mutación efectiva.
create or replace function co__proteger_version_monotona()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.version < old.version then
    raise exception using errcode = 'P0001', message = 'CO_VERSION_DESACTUALIZADA';
  end if;
  return new;
end;
$$;

revoke execute on function co__proteger_version_monotona() from public, anon, authenticated;
grant execute on function co__proteger_version_monotona() to service_role;

drop trigger if exists trg_co_proteger_version_monotona on carritos;
create trigger trg_co_proteger_version_monotona
  before update of version on carritos
  for each row execute function co__proteger_version_monotona();

-- La fila de configuración se bloquea primero y la cabecera después: es el
-- mismo orden que siguen las RPC. Esto serializa altas del mismo carrito,
-- protege el conteo incluso ante escritura privilegiada y evita un lock global.
create or replace function co__limitar_lineas_carrito()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_lineas integer;
  v_lineas     integer;
begin
  if tg_op = 'UPDATE' then
    if new.carrito_id is distinct from old.carrito_id then
      -- Mover una línea eludiría el conteo de INSERT. Se rechaza con el mismo
      -- error estable del límite; un escritor debe borrar e insertar.
      raise exception using errcode = 'P0001', message = 'CO_MAX_LINEAS';
    end if;
    return new;
  end if;

  select least(max_lineas_carrito, 20)
    into v_max_lineas
    from comercial_config
   where id = 1
   for share;

  perform 1
    from carritos c
   where c.id = new.carrito_id
   for update;

  v_max_lineas := coalesce(v_max_lineas, 20);

  select count(*)::integer
    into v_lineas
    from carrito_items ci
   where ci.carrito_id = new.carrito_id;

  if v_lineas >= v_max_lineas or v_lineas >= 20 then
    raise exception using errcode = 'P0001', message = 'CO_MAX_LINEAS';
  end if;

  return new;
end;
$$;

revoke execute on function co__limitar_lineas_carrito() from public, anon, authenticated;
grant execute on function co__limitar_lineas_carrito() to service_role;

drop trigger if exists trg_co_limitar_lineas_carrito on carrito_items;
create trigger trg_co_limitar_lineas_carrito
  before insert or update of carrito_id on carrito_items
  for each row execute function co__limitar_lineas_carrito();

-- Una reducción del máximo ya posee el lock de la fila singleton. Las altas
-- toman esa misma fila FOR SHARE antes de contar, de modo que el nuevo techo
-- nunca entra en vigor sobre una inserción todavía abierta.
create or replace function co__validar_max_lineas_config()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
      from carrito_items ci
     group by ci.carrito_id
    having count(*) > least(new.max_lineas_carrito, 20)
  ) then
    raise exception using errcode = 'P0001', message = 'CO_MAX_LINEAS';
  end if;

  return new;
end;
$$;

revoke execute on function co__validar_max_lineas_config() from public, anon, authenticated;
grant execute on function co__validar_max_lineas_config() to service_role;

drop trigger if exists trg_co_validar_max_lineas_config on comercial_config;
create trigger trg_co_validar_max_lineas_config
  before update of max_lineas_carrito on comercial_config
  for each row execute function co__validar_max_lineas_config();

-- ----------------------------------------------------------------------------
-- (C) RLS de propietario. El navegador solo lee; toda escritura pasa por RPC.
-- ----------------------------------------------------------------------------
alter table carritos enable row level security;
alter table carrito_items enable row level security;

revoke all on table carritos from public, anon, authenticated;
revoke all on table carrito_items from public, anon, authenticated;
grant select on table carritos to authenticated;
grant select on table carrito_items to authenticated;

drop policy if exists carritos_lectura_propia on carritos;
create policy carritos_lectura_propia on carritos
  for select
  to authenticated
  using (
    (select auth.uid()) = auth_user_id
    and es_cuenta_cliente()
  );

drop policy if exists carrito_items_lectura_propia on carrito_items;
create policy carrito_items_lectura_propia on carrito_items
  for select
  to authenticated
  using (
    es_cuenta_cliente()
    and exists (
      select 1
        from carritos c
       where c.id = carrito_items.carrito_id
         and c.auth_user_id = (select auth.uid())
    )
  );

-- ----------------------------------------------------------------------------
-- (D) Snapshot canónico. Solo consume la lista blanca catalogo_publico.
--     Si una campaña salió del catálogo, conserva exclusivamente id/cantidad;
--     los demás datos públicos quedan null y nunca se consulta la ficha base.
-- ----------------------------------------------------------------------------
create or replace function co__carrito_snapshot()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_habilitado boolean := false;
  v_carrito_id uuid;
  v_version    bigint;
  v_lineas     bigint := 0;
  v_unidades   bigint := 0;
  v_items      jsonb := '[]'::jsonb;
begin
  select coalesce(cfg.carrito_habilitado, false)
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1;

  select c.id, c.version
    into v_carrito_id, v_version
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa';

  if v_carrito_id is not null then
    select count(*)::bigint,
           coalesce(sum(ci.cantidad), 0)::bigint,
           coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'campana_id', ci.campana_id,
                 'nombre', case when cp.id is not null then cp.nombre else null end,
                 'slug', case when cp.id is not null then cp.slug else null end,
                 'precio_unitario_actual', case when cp.id is not null then cp.precio_venta else null end,
                 'cantidad', ci.cantidad,
                 'subtotal_actual', case
                   when cp.id is not null and cp.precio_venta is not null
                     then cp.precio_venta * ci.cantidad
                   else null
                 end,
                 'max_comprable', case when cp.id is not null then cp.max_comprable else 0 end,
                 'disponible', (
                   cp.id is not null
                   and coalesce(cp.precio_venta, 0) > 0
                   and coalesce(cp.max_comprable, 0) > 0
                 ),
                 'requiere_ajuste', (
                   cp.id is null
                   or coalesce(cp.precio_venta, 0) <= 0
                   or coalesce(cp.max_comprable, 0) <= 0
                   or ci.cantidad > coalesce(cp.max_comprable, 0)
                 )
               )
               order by ci.creado, ci.campana_id
             ),
             '[]'::jsonb
           )
      into v_lineas, v_unidades, v_items
      from carrito_items ci
      left join catalogo_publico cp on cp.id = ci.campana_id
     where ci.carrito_id = v_carrito_id;
  end if;

  return jsonb_build_object(
    'habilitado', coalesce(v_habilitado, false),
    'carrito_id', v_carrito_id,
    'version', coalesce(v_version, 0),
    'cantidad_lineas', coalesce(v_lineas, 0),
    'cantidad_unidades', coalesce(v_unidades, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

comment on function co__carrito_snapshot() is
  'Interna C2 · snapshot canónico del carrito activo de auth.uid(). Usa solo catalogo_publico; una campaña retirada conserva id/cantidad y no filtra su ficha interna.';

revoke execute on function co__carrito_snapshot() from public, anon, authenticated;
grant execute on function co__carrito_snapshot() to service_role;

-- Estas cuatro RPC son puertas únicas: se retira cualquier overload que pudiera
-- aceptar identidad, carrito, cliente, precio u otra autoridad del navegador.
do $drop_overloads$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'co_carrito_listar',
         'co_carrito_agregar',
         'co_carrito_cambiar',
         'co_carrito_quitar'
       )
  loop
    execute format('drop function %s', r.firma);
  end loop;
end $drop_overloads$;

-- ----------------------------------------------------------------------------
-- (E) Obtener/listar. La creación es perezosa y queda serializada por la fila
--     de cuentas_cliente; el índice parcial es el piso duro adicional.
-- ----------------------------------------------------------------------------
create function co_carrito_listar()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_habilitado  boolean;
  v_estado      text;
  v_carrito_id  uuid;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;

  select cfg.carrito_habilitado
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1
   for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;

  select cc.estado
    into v_estado
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;

  select c.id
    into v_carrito_id
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa'
   for update;

  if v_carrito_id is null then
    insert into carritos (auth_user_id)
    values (v_uid)
    returning id into v_carrito_id;
  end if;

  return co__carrito_snapshot();
end;
$$;

comment on function co_carrito_listar() is
  'Comercial C2 · obtiene o crea perezosamente la cesta activa de auth.uid() y devuelve su snapshot actual. Exige flag y cuenta activa; customer_id puede ser null.';

-- ----------------------------------------------------------------------------
-- (F) Agregar delta. Consolida una sola línea bajo el lock de cabecera.
-- ----------------------------------------------------------------------------
create function co_carrito_agregar(
  p_campana_id uuid,
  p_cantidad   integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_habilitado   boolean;
  v_max_lineas   integer;
  v_estado       text;
  v_carrito_id   uuid;
  v_actual       integer;
  v_nueva        integer;
  v_lineas       integer;
  v_precio       bigint;
  v_max_comprable integer;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;

  -- Cuenta -> cabecera -> campaña -> línea. La cabecera serializa las RPC del
  -- mismo UID; el trigger añade un lock por carrito para escrituras privilegiadas.
  select cfg.carrito_habilitado, cfg.max_lineas_carrito
    into v_habilitado, v_max_lineas
    from comercial_config cfg
   where cfg.id = 1
   for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;

  select cc.estado
    into v_estado
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;

  if p_cantidad is null or p_cantidad not between 1 and 20 then
    raise exception using errcode = 'P0001', message = 'CO_CANTIDAD_INVALIDA';
  end if;

  select c.id
    into v_carrito_id
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa'
   for update;

  if v_carrito_id is null then
    insert into carritos (auth_user_id)
    values (v_uid)
    returning id into v_carrito_id;
  end if;

  -- Ninguna ruta del carrito bloquea productos: no reserva ni materializa una
  -- compra. La campaña se estabiliza después de cuenta/cabecera y antes de
  -- releer la lista blanca; ningún escritor de C1 toma locks de carrito.
  perform 1
    from campana_producto cp
   where cp.id = p_campana_id
   for share;

  select cp.precio_venta, cp.max_comprable
    into v_precio, v_max_comprable
    from catalogo_publico cp
   where cp.id = p_campana_id;

  if not found
     or coalesce(v_precio, 0) <= 0
     or coalesce(v_max_comprable, 0) <= 0 then
    raise exception using errcode = 'P0001', message = 'CO_CAMPANA_NO_COMPRABLE';
  end if;

  select ci.cantidad
    into v_actual
    from carrito_items ci
   where ci.carrito_id = v_carrito_id
     and ci.campana_id = p_campana_id
   for update;

  v_nueva := coalesce(v_actual, 0) + p_cantidad;
  if v_nueva > v_max_comprable then
    raise exception using
      errcode = 'P0001',
      message = format('CO_MAX_COMPRABLE:%s', v_max_comprable);
  end if;

  if v_actual is null then
    select count(*)::integer
      into v_lineas
      from carrito_items ci
     where ci.carrito_id = v_carrito_id;

    if v_lineas >= least(coalesce(v_max_lineas, 20), 20) then
      raise exception using errcode = 'P0001', message = 'CO_MAX_LINEAS';
    end if;

    insert into carrito_items (carrito_id, campana_id, cantidad)
    values (v_carrito_id, p_campana_id, v_nueva);
  else
    update carrito_items
       set cantidad = v_nueva,
           actualizado = now()
     where carrito_id = v_carrito_id
       and campana_id = p_campana_id;
  end if;

  update carritos
     set version = version + 1,
         actualizado = now()
   where id = v_carrito_id;

  return co__carrito_snapshot();
end;
$$;

comment on function co_carrito_agregar(uuid, integer) is
  'Comercial C2 · suma un delta 1..20 a una campaña y consolida por PK. Crea la cesta activa si falta, relee catálogo/precio/máximo y aumenta la versión una vez.';

-- ----------------------------------------------------------------------------
-- (G) Cambiar cantidad absoluta con versión esperada.
-- ----------------------------------------------------------------------------
create function co_carrito_cambiar(
  p_campana_id       uuid,
  p_cantidad         integer,
  p_version_esperada bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := auth.uid();
  v_habilitado    boolean;
  v_estado        text;
  v_carrito_id    uuid;
  v_version       bigint;
  v_actual        integer;
  v_precio        bigint;
  v_max_comprable integer;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;

  select cfg.carrito_habilitado
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1
   for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;

  select cc.estado
    into v_estado
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;

  if p_cantidad is null or p_cantidad not between 1 and 20 then
    raise exception using errcode = 'P0001', message = 'CO_CANTIDAD_INVALIDA';
  end if;

  select c.id, c.version
    into v_carrito_id, v_version
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa'
   for update;

  if v_carrito_id is null then
    raise exception using errcode = 'P0001', message = 'CO_LINEA_NO_EXISTE';
  end if;
  if p_version_esperada is null or p_version_esperada <> v_version then
    raise exception using errcode = 'P0001', message = 'CO_VERSION_DESACTUALIZADA';
  end if;

  perform 1
    from campana_producto cp
   where cp.id = p_campana_id
   for share;

  select cp.precio_venta, cp.max_comprable
    into v_precio, v_max_comprable
    from catalogo_publico cp
   where cp.id = p_campana_id;

  if not found
     or coalesce(v_precio, 0) <= 0
     or coalesce(v_max_comprable, 0) <= 0 then
    raise exception using errcode = 'P0001', message = 'CO_CAMPANA_NO_COMPRABLE';
  end if;
  if p_cantidad > v_max_comprable then
    raise exception using
      errcode = 'P0001',
      message = format('CO_MAX_COMPRABLE:%s', v_max_comprable);
  end if;

  select ci.cantidad
    into v_actual
    from carrito_items ci
   where ci.carrito_id = v_carrito_id
     and ci.campana_id = p_campana_id
   for update;
  if v_actual is null then
    raise exception using errcode = 'P0001', message = 'CO_LINEA_NO_EXISTE';
  end if;

  if p_cantidad <> v_actual then
    update carrito_items
       set cantidad = p_cantidad,
           actualizado = now()
     where carrito_id = v_carrito_id
       and campana_id = p_campana_id;

    update carritos
       set version = version + 1,
           actualizado = now()
     where id = v_carrito_id;
  end if;

  return co__carrito_snapshot();
end;
$$;

comment on function co_carrito_cambiar(uuid, integer, bigint) is
  'Comercial C2 · fija cantidad absoluta bajo versión esperada. Revalida campaña pública, precio positivo y máximo actual; una operación sin cambio no incrementa versión.';

-- ----------------------------------------------------------------------------
-- (H) Quitar con versión esperada. No consulta campaña ni catálogo: una línea
--     retirada/despublicada siempre se puede eliminar.
-- ----------------------------------------------------------------------------
create function co_carrito_quitar(
  p_campana_id       uuid,
  p_version_esperada bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_habilitado  boolean;
  v_estado      text;
  v_carrito_id  uuid;
  v_version     bigint;
  v_existe      uuid;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;

  select cfg.carrito_habilitado
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1
   for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;

  select cc.estado
    into v_estado
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;

  select c.id, c.version
    into v_carrito_id, v_version
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa'
   for update;

  if v_carrito_id is null then
    raise exception using errcode = 'P0001', message = 'CO_LINEA_NO_EXISTE';
  end if;
  if p_version_esperada is null or p_version_esperada <> v_version then
    raise exception using errcode = 'P0001', message = 'CO_VERSION_DESACTUALIZADA';
  end if;

  select ci.campana_id
    into v_existe
    from carrito_items ci
   where ci.carrito_id = v_carrito_id
     and ci.campana_id = p_campana_id
   for update;
  if v_existe is null then
    raise exception using errcode = 'P0001', message = 'CO_LINEA_NO_EXISTE';
  end if;

  delete from carrito_items
   where carrito_id = v_carrito_id
     and campana_id = p_campana_id;

  update carritos
     set version = version + 1,
         actualizado = now()
   where id = v_carrito_id;

  return co__carrito_snapshot();
end;
$$;

comment on function co_carrito_quitar(uuid, bigint) is
  'Comercial C2 · elimina una línea bajo versión esperada aun si la campaña ya salió del catálogo. Incrementa la versión exactamente una vez.';

-- Superficie pública exacta: authenticated y service_role. anon/public no
-- ejecutan carrito; ninguna firma acepta UID, carrito, customer_id o precio.
revoke all on function co_carrito_listar() from public, anon, authenticated, service_role;
revoke all on function co_carrito_agregar(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function co_carrito_cambiar(uuid, integer, bigint) from public, anon, authenticated, service_role;
revoke all on function co_carrito_quitar(uuid, bigint) from public, anon, authenticated, service_role;

grant execute on function co_carrito_listar() to authenticated, service_role;
grant execute on function co_carrito_agregar(uuid, integer) to authenticated, service_role;
grant execute on function co_carrito_cambiar(uuid, integer, bigint) to authenticated, service_role;
grant execute on function co_carrito_quitar(uuid, bigint) to authenticated, service_role;

commit;
