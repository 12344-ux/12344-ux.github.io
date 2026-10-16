-- MAGANDHI · COMERCIAL C3 · CHECKOUT MULTIPRODUCTO
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261103000000. No modifica migraciones históricas.
-- Convierte pagos_intencion en una cabecera compatible: v0/v1 conservan su
-- snapshot escalar y v2 congela sus líneas en pagos_intencion_items.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Cabecera compatible y trazabilidad del carrito autenticado.
-- ----------------------------------------------------------------------------
alter table pagos_intencion
  drop constraint if exists pagos_intencion_version_checkout_valida;

alter table pagos_intencion
  alter column cantidad drop not null,
  alter column precio_unitario drop not null,
  add column if not exists auth_user_id uuid,
  add column if not exists carrito_id uuid,
  add column if not exists carrito_version bigint;

alter table pagos_intencion
  add constraint pagos_intencion_version_checkout_valida
  check (version_checkout in (0, 1, 2));

alter table pagos_intencion
  add constraint pagos_intencion_forma_checkout_valida
  check (
    (
      version_checkout in (0, 1)
      and cantidad is not null
      and precio_unitario is not null
      and auth_user_id is null
      and carrito_id is null
      and carrito_version is null
    )
    or
    (
      version_checkout = 2
      and campana_id is null
      and product_id is null
      and slug is null
      and nombre is null
      and cantidad is null
      and precio_unitario is null
      and auth_user_id is not null
      and carrito_id is not null
      and carrito_version is not null
      and carrito_version >= 0
    )
  );

comment on column pagos_intencion.version_checkout is
  'Versión del checkout: 0=F2/F3 histórico; 1=C1 escalar; 2=C3 carrito multiproducto con líneas congeladas.';
comment on column pagos_intencion.auth_user_id is
  'C3 · UID Auth derivado y validado por la Edge Function. Es trazabilidad privada, no customer_id ni autoridad comercial.';
comment on column pagos_intencion.carrito_id is
  'C3 · id del carrito activo revalidado al congelar la intención. Se conserva como snapshot y no consume ni cierra el carrito.';
comment on column pagos_intencion.carrito_version is
  'C3 · versión exacta del carrito que originó el snapshot multiproducto.';

-- Una versión concreta de un carrito autenticado solo puede tener una intención
-- v2, aunque dos invocaciones Edge lleguen con referencias aleatorias distintas.
create unique index pagos_intencion_carrito_version_v2_uidx
  on pagos_intencion (auth_user_id, carrito_id, carrito_version)
  where version_checkout = 2;

-- C3 distingue discordancias de datos firmados (moneda, entorno o líneas) de
-- una discordancia estrictamente monetaria para que la auditoría sea precisa.
alter table pagos_eventos
  drop constraint if exists pagos_eventos_resultado_check;
alter table pagos_eventos
  add constraint pagos_eventos_resultado_check
  check (resultado in ('procesado','repetido','rechazado','sin_intencion',
                       'sin_stock','monto_no_coincide','datos_no_coinciden',
                       'ignorado','ya_procesada'));

-- ----------------------------------------------------------------------------
-- (B) Líneas privadas congeladas. Los importes están en pesos enteros; solo la
--     cabecera guarda el total Wompi en centavos.
-- ----------------------------------------------------------------------------
create table pagos_intencion_items (
  referencia      text not null references pagos_intencion(referencia) on delete restrict,
  ordinal         smallint not null check (ordinal between 1 and 20),
  campana_id      uuid not null references campana_producto(id) on delete restrict,
  product_id      uuid not null references productos(id) on delete restrict,
  slug            text not null check (length(btrim(slug)) between 1 and 200),
  nombre          text not null check (length(btrim(nombre)) between 1 and 300),
  cantidad        integer not null check (cantidad between 1 and 20),
  precio_unitario bigint not null check (precio_unitario > 0),
  subtotal        bigint not null check (subtotal > 0),
  primary key (referencia, ordinal),
  constraint pagos_intencion_items_campana_unica unique (referencia, campana_id),
  constraint pagos_intencion_items_subtotal_exacto
    check (subtotal = precio_unitario * cantidad::bigint)
);

create index pagos_intencion_items_producto_idx
  on pagos_intencion_items (product_id);

comment on table pagos_intencion_items is
  'PRIVADA · líneas autoritativas congeladas del checkout C3. Precio y subtotal son pesos enteros; no se exponen ni se escriben desde navegador.';
comment on column pagos_intencion_items.ordinal is
  'Orden estable 1..20 del snapshot de carrito.';
comment on column pagos_intencion_items.subtotal is
  'Subtotal exacto en pesos: precio_unitario * cantidad.';

alter table pagos_intencion_items enable row level security;
revoke all on table pagos_intencion_items from public, anon, authenticated;
grant select, insert, update, delete on table pagos_intencion_items to service_role;

-- ----------------------------------------------------------------------------
-- (C) Tope monetario operativo explícito. Default: COP 10.000.000 expresados
--     como 1.000.000.000 centavos. El rango evita configuraciones negativas o
--     desproporcionadas y deja margen operativo sin acercarse a bigint.
-- ----------------------------------------------------------------------------
alter table comercial_config
  add column if not exists max_monto_checkout_centavos bigint not null
    default 1000000000;

alter table comercial_config
  add constraint comercial_config_max_monto_checkout_rango
  check (max_monto_checkout_centavos between 100 and 1000000000000);

comment on column comercial_config.max_monto_checkout_centavos is
  'C3 · máximo total por checkout, en centavos COP. Default 1.000.000.000 = COP 10.000.000; rango seguro COP 1..10.000.000.000.';

-- La misma firma histórica sigue siendo exclusivamente service_role. C3 añade
-- product_id al retorno privado para que Edge agrupe campañas del mismo
-- producto sin exponer ese identificador en ninguna respuesta al navegador.
create or replace function ds_verificacion_checkout(p_campana_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object(
    'product_id', p.id,
    'origen', coalesce(p.origen, 'propio'),
    'dropi_id', pp.producto_externo_id,
    'variante', nullif(pp.variacion_externa_id, ''),
    'piso', coalesce(pp.piso_vitrina, cfg.piso_vitrina, 20),
    'reservadas', coalesce((
      select sum(r.cantidad)
        from pedido_proveedor r
        join pedidos pe on pe.id = r.pedido_id
       where r.product_id = p.id
         and r.transcrito_en is null
         and pe.estado <> 'anulado'
    ), 0),
    'minutos_desde_lectura',
      case when pp.stock_leido_en is null then null
           else floor(extract(epoch from (now() - pp.stock_leido_en)) / 60.0)
      end,
    'frescura_max_min', coalesce(cfg.frescura_checkout_min, 10),
    'disponible_local', coalesce(ventas_disponible_para_venta(p.id), 0)
  )
  from campana_producto cp
  join productos p on p.id = cp.product_id_ref
  left join producto_proveedor pp on pp.product_id = p.id
  left join (select piso_vitrina, frescura_checkout_min
               from dropshipping_config where id = 1) cfg on true
  where cp.id = p_campana_id;
$fn$;

comment on function ds_verificacion_checkout(uuid) is
  'D2c.2c + C3 · retorno interno service_role para verificación viva y agregación por producto. Incluye product_id, ids de proveedor, reservas, piso, edad y disponibilidad; nada se expone al navegador.';
revoke all on function ds_verificacion_checkout(uuid) from public, anon, authenticated;
grant execute on function ds_verificacion_checkout(uuid) to service_role;

-- ----------------------------------------------------------------------------
-- (D) Registrar intención de carrito. Solo recibe identidad derivada por Edge,
--     nunca items, precios, monto ni customer_id del navegador.
-- ----------------------------------------------------------------------------
drop function if exists pw_registrar_intencion_carrito(
  text, uuid, uuid, bigint, text, jsonb, text, text, text
);

create function pw_registrar_intencion_carrito(
  p_referencia      text,
  p_auth_user_id    uuid,
  p_carrito_id      uuid,
  p_version_esperada bigint,
  p_entorno         text,
  p_comprador       jsonb default '{}'::jsonb,
  p_utm_campaign    text default null,
  p_mg_vid          text default null,
  p_moneda          text default 'COP'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existente       pagos_intencion;
  v_estado_cuenta   text;
  v_carrito_version bigint;
  v_carrito_estado  text;
  v_carrito_uid     uuid;
  v_habilitado      boolean;
  v_max_lineas      integer;
  v_max_monto       bigint;
  v_lineas          integer;
  v_unidades        bigint;
  v_max_comprable   integer;
  v_disponible      integer;
  v_req             record;
  v_items_actuales  jsonb := '[]'::jsonb;
  v_items_guardados jsonb := '[]'::jsonb;
  v_vinculos_pre    jsonb := '{}'::jsonb;
  v_total_pesos     numeric := 0;
  v_total_centavos_n numeric;
  v_total_centavos  bigint;
  v_moneda          text := coalesce(nullif(p_moneda, ''), 'COP');
  v_nombre          text := nullif(btrim(p_comprador->>'nombre'), '');
  v_correo          text := nullif(btrim(p_comprador->>'correo'), '');
  v_telefono        text := nullif(btrim(p_comprador->>'telefono'), '');
  v_direccion       text := nullif(btrim(p_comprador->>'direccion'), '');
  v_ciudad          text := nullif(btrim(p_comprador->>'ciudad'), '');
  v_departamento    text := nullif(btrim(p_comprador->>'departamento'), '');
  v_pais            text := nullif(btrim(p_comprador->>'pais'), '');
  v_utm             text := nullif(p_utm_campaign, '');
  v_vid             text := nullif(p_mg_vid, '');
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    raise exception using errcode = 'P0001', message = 'PW_REFERENCIA_INVALIDA';
  end if;
  if p_auth_user_id is null or p_carrito_id is null then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_INVALIDO';
  end if;
  if p_version_esperada is null or p_version_esperada < 0 then
    raise exception using errcode = 'P0001', message = 'PW_VERSION_DESACTUALIZADA';
  end if;
  if coalesce(p_entorno, '') not in ('sandbox', 'prod') then
    raise exception using errcode = 'P0001', message = 'PW_ENTORNO_INVALIDO';
  end if;
  if v_moneda <> 'COP' then
    raise exception using errcode = 'P0001', message = 'PW_MONEDA_INVALIDA';
  end if;
  if p_comprador is not null and jsonb_typeof(p_comprador) <> 'object' then
    raise exception using errcode = 'P0001', message = 'PW_COMPRADOR_INVALIDO';
  end if;

  -- La idempotencia comercial por carrito se resuelve después de adquirir el
  -- lock del carrito. La referencia aleatoria solo identifica una creación
  -- realmente nueva; nunca decide qué intención reutilizar.

  -- Mismo prefijo de locks de C2: configuración -> cuenta -> carrito. Después,
  -- la parte comercial usa estrictamente producto -> campaña.
  select cfg.carrito_habilitado,
         least(cfg.max_lineas_carrito, 20),
         cfg.max_monto_checkout_centavos
    into v_habilitado, v_max_lineas, v_max_monto
    from comercial_config cfg
   where cfg.id = 1
   for share;

  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_DESHABILITADO';
  end if;

  select cc.estado into v_estado_cuenta
    from cuentas_cliente cc
   where cc.auth_user_id = p_auth_user_id
   for update;
  if not found or v_estado_cuenta <> 'activa' then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_INVALIDO';
  end if;

  select c.auth_user_id, c.estado, c.version
    into v_carrito_uid, v_carrito_estado, v_carrito_version
    from carritos c
   where c.id = p_carrito_id
   for update;

  if not found
     or v_carrito_uid is distinct from p_auth_user_id
     or v_carrito_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_INVALIDO';
  end if;
  if v_carrito_version is distinct from p_version_esperada then
    raise exception using errcode = 'P0001', message = 'PW_VERSION_DESACTUALIZADA';
  end if;

  -- El lock del carrito serializa dos solicitudes de la misma versión. La
  -- segunda observa la intención que confirmó la primera y reutiliza su
  -- referencia, sin depender de ON CONFLICT para decidir la idempotencia.
  select * into v_existente
    from pagos_intencion pi
   where pi.version_checkout = 2
     and pi.auth_user_id = p_auth_user_id
     and pi.carrito_id = p_carrito_id
     and pi.carrito_version = p_version_esperada
   for update;

  if found then
    if v_existente.estado in ('procesada', 'requiere_revision') then
      raise exception using errcode = 'P0001', message = 'PW_CARRITO_YA_PROCESADO';
    end if;
    if v_existente.estado not in ('creada', 'rechazada') then
      raise exception using errcode = 'P0001', message = 'PW_CARRITO_YA_PROCESADO';
    end if;

    select count(*)::integer, coalesce(sum(i.cantidad), 0)::bigint,
           coalesce(jsonb_agg(
             jsonb_build_object(
               'ordinal', i.ordinal,
               'campana_id', i.campana_id,
               'product_id', i.product_id,
               'slug', i.slug,
               'nombre', i.nombre,
               'cantidad', i.cantidad,
               'precio_unitario', i.precio_unitario::text,
               'subtotal', i.subtotal::text
             ) order by i.ordinal
           ), '[]'::jsonb)
      into v_lineas, v_unidades, v_items_guardados
      from pagos_intencion_items i
     where i.referencia = v_existente.referencia;

    if v_lineas not between 1 and 20
       or (select coalesce(sum(i.subtotal::numeric * 100), 0)
             from pagos_intencion_items i
            where i.referencia = v_existente.referencia)
          <> v_existente.monto_centavos::numeric then
      raise exception using errcode = 'XX000', message = 'PW_SNAPSHOT_V2_INCONSISTENTE';
    end if;

    return jsonb_build_object(
      'referencia', v_existente.referencia,
      'version_checkout', 2,
      'carrito_id', v_existente.carrito_id,
      'carrito_version', v_existente.carrito_version,
      'estado', v_existente.estado,
      'entorno', v_existente.entorno,
      'monto_centavos', v_existente.monto_centavos::text,
      'moneda', v_existente.moneda,
      'cantidad_lineas', v_lineas,
      'cantidad_unidades', v_unidades,
      'items', v_items_guardados
    );
  end if;

  -- Una referencia que ya pertenezca a cualquier otra intención es una colisión
  -- independiente del carrito; se rechaza antes de hacer trabajo comercial.
  perform 1 from pagos_intencion pi
   where pi.referencia = p_referencia
   for update;
  if found then
    raise exception using errcode = 'P0001', message = 'PW_REFERENCIA_REUTILIZADA';
  end if;

  -- Congela las filas del carrito mientras se resuelven todos sus productos.
  perform ci.campana_id
    from carrito_items ci
   where ci.carrito_id = p_carrito_id
   order by ci.campana_id
   for update;

  select count(*)::integer, coalesce(sum(ci.cantidad), 0)::bigint
    into v_lineas, v_unidades
    from carrito_items ci
   where ci.carrito_id = p_carrito_id;

  if v_lineas < 1 then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_VACIO';
  end if;
  if v_lineas > least(coalesce(v_max_lineas, 20), 20) then
    raise exception using errcode = 'P0001', message = 'PW_MAX_LINEAS';
  end if;
  if exists (
    select 1 from carrito_items ci
     where ci.carrito_id = p_carrito_id
       and ci.cantidad not between 1 and 20
  ) then
    raise exception using errcode = 'P0001', message = 'PW_CANTIDAD_INVALIDA';
  end if;
  if exists (
    select 1
      from carrito_items ci
      left join campana_producto cp on cp.id = ci.campana_id
     where ci.carrito_id = p_carrito_id
       and cp.product_id_ref is null
  ) then
    raise exception using errcode = 'P0001', message = 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  -- Conserva el vínculo observado antes de bloquear productos. Tras adquirir
  -- campañas se exige que ninguno haya cambiado de producto mientras esperaba.
  select coalesce(
           jsonb_object_agg(cp.id::text, cp.product_id_ref::text),
           '{}'::jsonb
         )
    into v_vinculos_pre
    from carrito_items ci
    join campana_producto cp on cp.id = ci.campana_id
   where ci.carrito_id = p_carrito_id;

  -- Candados deterministas sobre cada producto distinto.
  perform p.id
    from productos p
    join (
      select distinct cp.product_id_ref as product_id
        from carrito_items ci
        join campana_producto cp on cp.id = ci.campana_id
       where ci.carrito_id = p_carrito_id
    ) x on x.product_id = p.id
   order by p.id
   for update of p;

  if (
    select count(distinct cp.product_id_ref)
      from carrito_items ci
      join campana_producto cp on cp.id = ci.campana_id
     where ci.carrito_id = p_carrito_id
  ) <> (
    select count(distinct p.id)
      from productos p
      join campana_producto cp on cp.product_id_ref = p.id
      join carrito_items ci on ci.campana_id = cp.id
     where ci.carrito_id = p_carrito_id
  ) then
    raise exception using errcode = 'P0001', message = 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  -- Solo después de todos los productos se bloquean todas las campañas.
  perform cp.id
    from campana_producto cp
    join carrito_items ci on ci.campana_id = cp.id
   where ci.carrito_id = p_carrito_id
   order by cp.id
   for update of cp;

  if exists (
    select 1
      from carrito_items ci
      join campana_producto cp on cp.id = ci.campana_id
     where ci.carrito_id = p_carrito_id
       and (v_vinculos_pre->>cp.id::text) is distinct from cp.product_id_ref::text
  ) then
    raise exception using errcode = 'P0001', message = 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  -- Revalidación autoritativa de cada campaña y construcción del snapshot.
  for v_req in
    select row_number() over (order by ci.creado, ci.campana_id)::smallint as ordinal,
           cp.id as campana_id,
           cp.product_id_ref as product_id,
           cp.slug,
           cp.nombre,
           ci.cantidad,
           cp.precio_venta,
           cp.publicado,
           cp.activo as campana_activa,
           cp.max_unidades_pedido,
           p.activo as producto_activo
      from carrito_items ci
      join campana_producto cp on cp.id = ci.campana_id
      join productos p on p.id = cp.product_id_ref
     where ci.carrito_id = p_carrito_id
     order by ci.creado, ci.campana_id
  loop
    if coalesce(v_req.publicado, false) is not true
       or coalesce(v_req.campana_activa, false) is not true
       or coalesce(v_req.producto_activo, false) is not true
       or v_req.slug is null or btrim(v_req.slug) = ''
       or v_req.nombre is null or btrim(v_req.nombre) = ''
       or v_req.precio_venta is null or v_req.precio_venta <= 0 then
      raise exception using errcode = 'P0001', message = 'PW_CAMPANA_NO_COMPRABLE';
    end if;

    v_max_comprable := ventas_max_comprable_campana(v_req.campana_id);
    if v_req.cantidad > coalesce(v_req.max_unidades_pedido, 0)
       or v_req.cantidad > v_max_comprable then
      raise exception using
        errcode = 'P0001',
        message = format('PW_MAX_COMPRABLE:%s', greatest(v_max_comprable, 0));
    end if;

    v_total_pesos := v_total_pesos
      + (v_req.precio_venta::numeric * v_req.cantidad::numeric);

    v_items_actuales := v_items_actuales || jsonb_build_array(
      jsonb_build_object(
        'ordinal', v_req.ordinal,
        'campana_id', v_req.campana_id,
        'product_id', v_req.product_id,
        'slug', v_req.slug,
        'nombre', v_req.nombre,
        'cantidad', v_req.cantidad,
        'precio_unitario', v_req.precio_venta::text,
        'subtotal', (v_req.precio_venta::numeric * v_req.cantidad::numeric)::text
      )
    );
  end loop;

  -- Varias campañas no pueden evadir la disponibilidad del mismo producto.
  for v_req in
    select cp.product_id_ref as product_id,
           sum(ci.cantidad)::integer as cantidad
      from carrito_items ci
      join campana_producto cp on cp.id = ci.campana_id
     where ci.carrito_id = p_carrito_id
     group by cp.product_id_ref
     order by cp.product_id_ref
  loop
    if v_req.cantidad > 20 then
      raise exception using errcode = 'P0001', message = 'PW_MAX_COMPRABLE:20';
    end if;
    v_disponible := coalesce(ventas_disponible_para_venta(v_req.product_id), 0);
    if v_req.cantidad > v_disponible then
      raise exception using errcode = 'P0001', message = 'PW_MAX_COMPRABLE:0';
    end if;
  end loop;

  v_total_centavos_n := v_total_pesos * 100;
  if v_total_centavos_n <= 0
     or v_total_centavos_n > coalesce(v_max_monto, 1000000000) then
    raise exception using
      errcode = 'P0001',
      message = format('PW_MONTO_MAXIMO:%s', coalesce(v_max_monto, 1000000000));
  end if;
  if v_total_centavos_n > 9223372036854775807::numeric then
    raise exception using errcode = 'P0001', message = 'PW_MONTO_MAXIMO';
  end if;
  v_total_centavos := v_total_centavos_n::bigint;

  insert into pagos_intencion (
    referencia, campana_id, product_id, slug, nombre, cantidad, precio_unitario,
    monto_centavos, moneda, entorno, version_checkout,
    auth_user_id, carrito_id, carrito_version,
    comprador_nombre, comprador_correo, comprador_telefono, comprador_direccion,
    comprador_ciudad, comprador_departamento, comprador_pais,
    utm_campaign, mg_vid
  ) values (
    p_referencia, null, null, null, null, null, null,
    v_total_centavos, v_moneda, p_entorno, 2,
    p_auth_user_id, p_carrito_id, p_version_esperada,
    v_nombre, v_correo, v_telefono, v_direccion,
    v_ciudad, v_departamento, v_pais, v_utm, v_vid
  );

  insert into pagos_intencion_items (
    referencia, ordinal, campana_id, product_id, slug, nombre,
    cantidad, precio_unitario, subtotal
  )
  select p_referencia,
         (e->>'ordinal')::smallint,
         (e->>'campana_id')::uuid,
         (e->>'product_id')::uuid,
         e->>'slug', e->>'nombre',
         (e->>'cantidad')::integer,
         (e->>'precio_unitario')::bigint,
         (e->>'subtotal')::bigint
    from jsonb_array_elements(v_items_actuales) e;

  select * into strict v_existente
    from pagos_intencion
   where referencia = p_referencia;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'ordinal', i.ordinal,
             'campana_id', i.campana_id,
             'product_id', i.product_id,
             'slug', i.slug,
             'nombre', i.nombre,
             'cantidad', i.cantidad,
             'precio_unitario', i.precio_unitario::text,
             'subtotal', i.subtotal::text
           ) order by i.ordinal
         ), '[]'::jsonb)
    into v_items_guardados
    from pagos_intencion_items i
   where i.referencia = p_referencia;

  return jsonb_build_object(
    'referencia', v_existente.referencia,
    'version_checkout', 2,
    'carrito_id', v_existente.carrito_id,
    'carrito_version', v_existente.carrito_version,
    'estado', v_existente.estado,
    'entorno', v_existente.entorno,
    'monto_centavos', v_existente.monto_centavos::text,
    'moneda', v_existente.moneda,
    'cantidad_lineas', v_lineas,
    'cantidad_unidades', v_unidades,
    'items', v_items_guardados
  );
end;
$$;

comment on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text) is
  'C3 · service_role registra una intención v2 desde UID derivado por Edge y carrito activo/versionado. Relee 1..20 líneas, bloquea producto->campaña, revalida y congela importes exactos; retries idénticos devuelven el mismo snapshot.';

revoke all on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (E) Webhook: firma exacta histórica. v0/v1 conservan literalmente su camino;
--     v2 valida monto, COP, entorno verificado y líneas antes de crear un único
--     pedido multiproducto. El carrito no se consume ni se cierra.
-- ----------------------------------------------------------------------------
create or replace function pw_procesar_pago(
  p_transaccion_id text,
  p_estado_wompi   text,
  p_referencia     text,
  p_monto_centavos bigint,
  p_moneda         text default null,
  p_evento         text default null,
  p_checksum       text default null,
  p_cuerpo         jsonb default null,
  p_metodo_pago    text default null,
  p_correo_pagador text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ins        bigint;
  v_i          pagos_intencion;
  v_pedido     jsonb;
  v_pedido_id  uuid;
  v_motivo     text;
  v_aprobado   boolean;
  v_asiento    jsonb;
  v_items      jsonb;
  v_lineas     integer;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_total_lineas numeric;
  v_entorno_evento text;
begin
  if coalesce(btrim(p_transaccion_id), '') = ''
     or coalesce(btrim(p_estado_wompi), '') = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  insert into pagos_eventos (
    transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado
  ) values (
    p_transaccion_id, upper(btrim(p_estado_wompi)), nullif(p_referencia, ''),
    p_evento, p_checksum, p_cuerpo, 'ignorado'
  )
  on conflict (transaccion_id, estado_wompi) do nothing
  returning id into v_ins;

  if v_ins is null then
    return jsonb_build_object(
      'resultado', 'repetido',
      'pedido_id', (select pedido_id from pagos_intencion
                     where referencia = p_referencia)
    );
  end if;

  v_aprobado := upper(btrim(p_estado_wompi)) = 'APPROVED';

  select * into v_i from pagos_intencion
   where referencia = p_referencia for update;

  if not found then
    update pagos_eventos set resultado = 'sin_intencion' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_intencion');
  end if;

  if v_i.estado = 'procesada' then
    update pagos_eventos set resultado = 'ya_procesada' where id = v_ins;
    return jsonb_build_object('resultado', 'ya_procesada',
                              'pedido_id', v_i.pedido_id);
  end if;

  if not v_aprobado then
    update pagos_intencion
       set estado = case
                      when upper(btrim(p_estado_wompi)) in ('DECLINED','VOIDED','ERROR')
                        then 'rechazada'
                      else estado
                    end,
           transaccion_id = p_transaccion_id,
           estado_wompi = upper(btrim(p_estado_wompi)),
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'rechazado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado',
                              'estado', upper(btrim(p_estado_wompi)));
  end if;

  if p_monto_centavos is null or p_monto_centavos <> v_i.monto_centavos then
    v_motivo := format(
      'El monto informado (%s) no coincide con el firmado (%s).',
      coalesce(p_monto_centavos::text, 'nulo'), v_i.monto_centavos
    );
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'monto_no_coincide' where id = v_ins;
    return jsonb_build_object('resultado', 'monto_no_coincide',
                              'motivo', v_motivo);
  end if;

  -- El webhook moderno siempre informa moneda y entorno. Las llamadas SQL
  -- históricas v0/v1 que no enviaban cuerpo conservan compatibilidad: solo se
  -- validan esos campos cuando están presentes. En v2 ambos son obligatorios.
  v_entorno_evento := case lower(coalesce(p_cuerpo->>'environment', ''))
    when 'test' then 'sandbox'
    when 'sandbox' then 'sandbox'
    when 'prod' then 'prod'
    when 'production' then 'prod'
    else null
  end;

  if (v_i.version_checkout = 2 or p_moneda is not null)
     and upper(nullif(btrim(p_moneda), ''))
         is distinct from upper(nullif(btrim(v_i.moneda), '')) then
    v_motivo := format(
      'La moneda informada (%s) no coincide con la intención (%s).',
      coalesce(nullif(btrim(p_moneda), ''), 'nula'), v_i.moneda
    );
  elsif (v_i.version_checkout = 2 or coalesce(p_cuerpo ? 'environment', false))
     and (v_entorno_evento is null
          or v_entorno_evento is distinct from v_i.entorno) then
    v_motivo := format(
      'El entorno informado (%s) no coincide con la intención (%s).',
      coalesce(nullif(p_cuerpo->>'environment', ''), 'nulo'), v_i.entorno
    );
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden',
                              'motivo', v_motivo);
  end if;

  if v_i.version_checkout = 2 then
    select count(*)::integer, min(i.ordinal)::integer, max(i.ordinal)::integer,
           coalesce(sum(i.subtotal::numeric * 100), 0),
           coalesce(jsonb_agg(
             jsonb_build_object(
               'campana_id', i.campana_id,
               'product_id', i.product_id,
               'cantidad', i.cantidad,
               'precio_unitario', i.precio_unitario
             ) order by i.ordinal
           ), '[]'::jsonb)
      into v_lineas, v_min_ordinal, v_max_ordinal, v_total_lineas, v_items
      from pagos_intencion_items i
     where i.referencia = v_i.referencia;

    if v_lineas not between 1 and 20
       or v_min_ordinal <> 1
       or v_max_ordinal <> v_lineas
       or v_total_lineas <> v_i.monto_centavos::numeric then
      v_motivo := 'Las líneas congeladas no coinciden con la intención firmada.';
      update pagos_intencion
         set estado = 'requiere_revision', revision_motivo = v_motivo,
             transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
             metodo_pago = coalesce(p_metodo_pago, metodo_pago),
             correo_pagador = coalesce(p_correo_pagador, correo_pagador),
             actualizado = now()
       where referencia = p_referencia;
      update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
      return jsonb_build_object('resultado', 'datos_no_coinciden',
                                'motivo', v_motivo);
    end if;
  else
    if v_i.product_id is null then
      v_motivo := 'La campana no tiene producto de Inventario ligado.';
      update pagos_intencion
         set estado = 'requiere_revision', revision_motivo = v_motivo,
             transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
             actualizado = now()
       where referencia = p_referencia;
      update pagos_eventos set resultado = 'sin_stock' where id = v_ins;
      return jsonb_build_object('resultado', 'sin_stock', 'motivo', v_motivo);
    end if;

    v_items := jsonb_build_array(
      jsonb_build_object(
        'product_id', v_i.product_id,
        'cantidad', v_i.cantidad,
        'precio_unitario', v_i.precio_unitario
      ) || case
             when v_i.version_checkout = 0 then '{}'::jsonb
             else jsonb_build_object('campana_id', v_i.campana_id)
           end
    );
  end if;

  begin
    perform set_config('impulse.pago_servidor', 'on', true);
    perform set_config(
      'impulse.checkout_legacy',
      case when v_i.version_checkout = 0 then 'on' else 'off' end,
      true
    );
    v_pedido := crear_pedido(
      p_nombre        => coalesce(v_i.comprador_nombre, 'Comprador web'),
      p_correo        => coalesce(v_i.comprador_correo, p_correo_pagador),
      p_telefono      => v_i.comprador_telefono,
      p_direccion     => v_i.comprador_direccion,
      p_ciudad        => v_i.comprador_ciudad,
      p_departamento  => v_i.comprador_departamento,
      p_pais          => v_i.comprador_pais,
      p_canal         => 'web',
      p_fecha_orden   => fz__fecha_colombia(),
      p_notas_pedido  => 'Pago web Wompi · referencia ' || v_i.referencia,
      p_items         => v_items
    );
    v_pedido_id := (v_pedido->>'pedido_id')::uuid;
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
  exception when raise_exception then
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
    v_motivo := sqlerrm;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'sin_stock' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_stock', 'motivo', v_motivo);
  end;

  if v_i.utm_campaign is not null then
    update pedidos set utm_campaign = v_i.utm_campaign
     where id = v_pedido_id;
  end if;

  update pagos_intencion
     set estado = 'procesada', pedido_id = v_pedido_id,
         transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
         metodo_pago = coalesce(p_metodo_pago, metodo_pago),
         correo_pagador = coalesce(p_correo_pagador, correo_pagador),
         revision_motivo = null, procesada_en = now(), actualizado = now()
   where referencia = p_referencia;
  update pagos_eventos set resultado = 'procesado' where id = v_ins;

  begin
    v_asiento := fz__asiento_venta_web(v_pedido_id);
  exception when others then
    v_asiento := jsonb_build_object('resultado', 'pendiente',
                                    'motivo', sqlerrm);
  end;

  return jsonb_build_object('resultado', 'procesado',
                            'pedido_id', v_pedido_id,
                            'asiento', v_asiento);
end;
$$;

comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is
  'Pagos web F2/F3 + C1 + C3 · conserva firma y ramas v0/v1. v2 carga líneas congeladas, valida monto/COP/entorno y crea un único pedido multiproducto; cualquier falla comercial queda atómicamente en revisión. No consume ni cierra carrito.';

-- El panel conserva todas sus claves históricas. Para v2 completa nombre y
-- cantidad con un resumen del carrito e incluye solo datos saneados de líneas;
-- pagos_intencion_items continúa sin grants directos para authenticated.
create or replace function pw_revisiones()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_pagos() then raise exception 'PW_SIN_ACCESO'; end if;
  return jsonb_build_object(
    'pendientes', (select count(*) from pagos_intencion
                    where estado = 'requiere_revision' and resuelta_en is null),
    'lista', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'referencia', pi.referencia,
        'nombre', case when pi.version_checkout = 2
                       then detalle.nombre_resumen else pi.nombre end,
        'slug', pi.slug,
        'cantidad', case when pi.version_checkout = 2
                         then detalle.cantidad_unidades else pi.cantidad end,
        'monto_centavos', pi.monto_centavos,
        'motivo', pi.revision_motivo,
        'transaccion_id', pi.transaccion_id,
        'metodo_pago', pi.metodo_pago,
        'comprador', pi.comprador_nombre,
        'correo', pi.comprador_correo,
        'telefono', pi.comprador_telefono,
        'creado', pi.creado,
        'actualizado', pi.actualizado,
        'items', case when pi.version_checkout = 2
                      then detalle.items else null end
      ) order by pi.actualizado desc), '[]'::jsonb)
      from pagos_intencion pi
      left join lateral (
        select case when count(*) = 1 then max(i.nombre)
                    else count(*)::text || ' productos' end as nombre_resumen,
               coalesce(sum(i.cantidad), 0) as cantidad_unidades,
               coalesce(jsonb_agg(jsonb_build_object(
                 'ordinal', i.ordinal,
                 'nombre', i.nombre,
                 'cantidad', i.cantidad,
                 'subtotal', i.subtotal
               ) order by i.ordinal), '[]'::jsonb) as items
          from pagos_intencion_items i
         where i.referencia = pi.referencia
      ) detalle on pi.version_checkout = 2
     where pi.estado = 'requiere_revision' and pi.resuelta_en is null
    ),
    'resueltas_30d', (select count(*) from pagos_intencion
                       where resuelta_en is not null
                         and resuelta_en >= now() - interval '30 days')
  );
end;
$$;

comment on function pw_revisiones() is
  'PAGOS WEB · conserva el contrato histórico del panel y, para C3 v2, añade items saneados y resumen de nombre/cantidad sin otorgar acceso directo a pagos_intencion_items.';
revoke execute on function pw_revisiones() from public, anon;
grant execute on function pw_revisiones() to authenticated, service_role;

-- Grants históricos de la firma se conservan: solo service_role procesa pagos.
revoke execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  to service_role;

commit;
