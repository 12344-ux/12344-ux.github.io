-- ============================================================================
-- MAGANDHI · COMERCIAL C1 · CANTIDAD EN COMPRA INMEDIATA
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261101000000. No modifica migraciones históricas.
--
-- Cierra en el servidor las tres carreras de una compra con cantidad:
--   1. Campañas define un máximo obligatorio de 1..20 por producto y pedido.
--   2. La intención relee campaña, precio y disponibilidad antes de firmar.
--   3. El webhook vuelve a validar campaña, máximo y stock bajo los candados
--      de crear_pedido antes de materializar el pedido.
--
-- La superficie pública agrega únicamente max_comprable (0..20). Nunca expone
-- stock, reservas, piso, origen ni ids del proveedor.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Máximo comercial por campaña. Las campañas históricas nacen en 1.
-- ----------------------------------------------------------------------------
alter table campana_producto
  add column if not exists max_unidades_pedido integer not null default 1;

do $mig$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_producto_max_unidades_pedido_rango'
       and conrelid = 'campana_producto'::regclass
  ) then
    alter table campana_producto
      add constraint campana_producto_max_unidades_pedido_rango
      check (max_unidades_pedido between 1 and 20);
  end if;
end $mig$;

comment on column campana_producto.max_unidades_pedido is
  'C1 comercial · máximo de unidades de este producto permitido por pedido (1..20). No es stock ni reutiliza tope_escaparate. Las campañas históricas nacen en 1.';

-- Marcador explícito de contrato: las filas que ya existían son F2/F3 (0).
-- Solo pw_registrar_intencion C1 escribe 1. campana_id no sirve como proxy,
-- porque las intenciones históricas normales ya lo guardaban.
alter table pagos_intencion
  add column if not exists version_checkout smallint not null default 0;

do $mig$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'pagos_intencion_version_checkout_valida'
       and conrelid = 'pagos_intencion'::regclass
  ) then
    alter table pagos_intencion
      add constraint pagos_intencion_version_checkout_valida
      check (version_checkout in (0, 1));
  end if;
end $mig$;

comment on column pagos_intencion.version_checkout is
  'Versión del contrato de checkout: 0=F2/F3 histórico sin validación comercial final por campaña; 1=C1 con cantidad, campaña y máximo revalidados. Nunca se infiere desde campana_id.';

-- ----------------------------------------------------------------------------
-- (B) Alta y edición de Campañas. Se retiran las firmas D2b anteriores: dejar
--     una sobrecarga sin el parámetro nuevo permitiría omitir el candado.
-- ----------------------------------------------------------------------------
drop function if exists cm_crear_campana(
  text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean
);

-- Defensa ante drift: estas RPC son puertas únicas, no familias de overloads.
-- Antes de crear las firmas C1 se retira cualquier variante histórica restante.
do $drop_overloads$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('cm_crear_campana', 'cm_editar_campana')
  loop
    execute format('drop function %s', r.firma);
  end loop;
end $drop_overloads$;

create function cm_crear_campana(
  p_nombre                   text,
  p_categoria_codigo         text default null,
  p_detalle_presentacion     text default null,
  p_imagen_banner_path       text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta             bigint default null,
  p_hook_largo               text default null,
  p_por_que_magandhi         text default null,
  p_sobre_este_producto      text default null,
  p_ficha_tecnica            jsonb default '[]'::jsonb,
  p_imagenes                 jsonb default '[]'::jsonb,
  p_sello_elegido            boolean default false,
  p_estrella                 boolean default false,
  p_stock_disponible         integer default 0,
  p_aviso_urgencia_activo    boolean default false,
  p_aviso_urgencia_cantidad  integer default null,
  p_etiquetas                text[] default '{}',
  p_product_id_ref           uuid default null,
  p_slug                     text default null,
  p_tope_escaparate          integer default null,
  p_producto_probado         boolean default false,
  p_max_unidades_pedido      integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_tag  text;
  v_slug text;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;
  if p_precio_venta is not null and p_precio_venta < 0 then
    raise exception 'El precio de venta no puede ser negativo.';
  end if;
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
  end if;
  if p_max_unidades_pedido is null or p_max_unidades_pedido not between 1 and 20 then
    raise exception 'CM_MAX_UNIDADES_INVALIDO: el máximo de unidades por pedido debe ser un entero entre 1 y 20.';
  end if;
  if coalesce(p_producto_probado, false) and p_product_id_ref is null then
    raise exception 'CM_PRUEBA_SIN_PRODUCTO: liga un producto antes de marcarlo como probado por MAGANDHI.';
  end if;
  if coalesce(p_sello_elegido, false)
     and not coalesce(p_producto_probado, false) then
    raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de usar Elegido por MAGANDHI.';
  end if;

  v_slug := cm_normalizar_slug(p_slug);

  insert into campana_producto (
    nombre, categoria_codigo, detalle_presentacion, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad,
    product_id_ref, slug, tope_escaparate, probado_por_magandhi,
    max_unidades_pedido
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb),
    coalesce(p_imagenes, '[]'::jsonb), coalesce(p_sello_elegido, false),
    coalesce(p_estrella, false), coalesce(p_stock_disponible, 0),
    coalesce(p_aviso_urgencia_activo, false), p_aviso_urgencia_cantidad,
    p_product_id_ref, v_slug, p_tope_escaparate,
    coalesce(p_producto_probado, false), p_max_unidades_pedido
  )
  returning id into v_id;

  if p_etiquetas is not null then
    foreach v_tag in array p_etiquetas loop
      if v_tag is not null and length(trim(v_tag)) > 0 then
        insert into campana_producto_etiqueta (campana_producto_id, etiqueta_codigo)
        values (v_id, v_tag)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;

comment on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) is
  'Campañas · alta de ficha comercial. C1 agrega p_max_unidades_pedido (1..20, default 1) al final y conserva la semántica D2b de precio, aviso, tope, etiquetas, slug, vínculo y curaduría.';

create function cm_editar_campana(
  p_id                       uuid,
  p_nombre                   text,
  p_categoria_codigo         text default null,
  p_detalle_presentacion     text default null,
  p_imagen_banner_path       text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta             bigint default null,
  p_hook_largo               text default null,
  p_por_que_magandhi         text default null,
  p_sobre_este_producto      text default null,
  p_ficha_tecnica            jsonb default '[]'::jsonb,
  p_imagenes                 jsonb default '[]'::jsonb,
  p_sello_elegido            boolean default false,
  p_estrella                 boolean default false,
  p_stock_disponible         integer default 0,
  p_aviso_urgencia_activo    boolean default false,
  p_aviso_urgencia_cantidad  integer default null,
  p_etiquetas                text[] default '{}',
  p_product_id_ref           uuid default null,
  p_slug                     text default null,
  p_tope_escaparate          integer default null,
  p_producto_probado         boolean default false,
  p_max_unidades_pedido      integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existe uuid;
  v_tag    text;
  v_slug   text;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;
  if p_precio_venta is not null and p_precio_venta < 0 then
    raise exception 'El precio de venta no puede ser negativo.';
  end if;
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
  end if;
  if p_max_unidades_pedido is null or p_max_unidades_pedido not between 1 and 20 then
    raise exception 'CM_MAX_UNIDADES_INVALIDO: el máximo de unidades por pedido debe ser un entero entre 1 y 20.';
  end if;

  -- Si la edición liga un producto, se bloquea antes que la campaña. Además de
  -- hacer explícito el orden producto -> campaña, evita que el chequeo de la FK
  -- adquiera implícitamente esos candados en el orden inverso.
  if p_product_id_ref is not null then
    perform 1
      from productos
     where id = p_product_id_ref
     for update;
  end if;

  select id into v_existe
    from campana_producto
   where id = p_id
   for update;
  if v_existe is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if coalesce(p_producto_probado, false) and p_product_id_ref is null then
    raise exception 'CM_PRUEBA_SIN_PRODUCTO: liga un producto antes de marcarlo como probado por MAGANDHI.';
  end if;
  if coalesce(p_sello_elegido, false)
     and not coalesce(p_producto_probado, false) then
    raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de usar Elegido por MAGANDHI.';
  end if;

  v_slug := cm_normalizar_slug(p_slug);

  update campana_producto
     set nombre                   = p_nombre,
         categoria_codigo         = p_categoria_codigo,
         detalle_presentacion     = p_detalle_presentacion,
         imagen_banner_path       = p_imagen_banner_path,
         caracteristica_adicional = p_caracteristica_adicional,
         precio_venta             = p_precio_venta,
         hook_largo               = p_hook_largo,
         por_que_magandhi         = p_por_que_magandhi,
         sobre_este_producto      = p_sobre_este_producto,
         ficha_tecnica            = coalesce(p_ficha_tecnica, '[]'::jsonb),
         imagenes                 = coalesce(p_imagenes, '[]'::jsonb),
         sello_elegido            = coalesce(p_sello_elegido, false),
         estrella                 = coalesce(p_estrella, false),
         stock_disponible         = coalesce(p_stock_disponible, 0),
         aviso_urgencia_activo    = coalesce(p_aviso_urgencia_activo, false),
         aviso_urgencia_cantidad  = p_aviso_urgencia_cantidad,
         product_id_ref           = p_product_id_ref,
         slug                     = v_slug,
         tope_escaparate          = p_tope_escaparate,
         probado_por_magandhi     = coalesce(p_producto_probado, false),
         max_unidades_pedido      = p_max_unidades_pedido,
         actualizado              = now()
   where id = p_id;

  delete from campana_producto_etiqueta where campana_producto_id = p_id;
  if p_etiquetas is not null then
    foreach v_tag in array p_etiquetas loop
      if v_tag is not null and length(trim(v_tag)) > 0 then
        insert into campana_producto_etiqueta (campana_producto_id, etiqueta_codigo)
        values (p_id, v_tag)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  return p_id;
end;
$$;

comment on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) is
  'Campañas · edición de ficha comercial. C1 agrega p_max_unidades_pedido (1..20, default 1), conserva la semántica D2b restante y, al ligar un producto, bloquea en orden producto -> campaña para no invertir el orden de crear_pedido.';

revoke execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) from public, anon, authenticated;
grant execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) to authenticated, service_role;
revoke execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) from public, anon, authenticated;
grant execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (B.1) Escritores concurrentes que participan en decisiones C1.
--       El orden común es producto -> campaña; nunca campaña -> producto.
--       CREATE OR REPLACE conserva los grants nominales de cada firma vigente.
-- ----------------------------------------------------------------------------

-- Inventario manual conserva su contrato histórico: una salida o ajuste puede
-- dejar existencias negativas. El candado no agrega una validación de saldo;
-- solo serializa el movimiento con la decisión de stock de crear_pedido.
create or replace function inv_registrar_movimiento(
  p_product_id         uuid,
  p_tipo               text,
  p_cantidad           integer,
  p_motivo             text default null,
  p_referencia         text default null,
  p_costo_unitario_mov bigint default null,
  p_fecha              date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id          uuid;
  v_activo      boolean;
  v_origen      text;
  v_existencias integer;
begin
  if not tiene_acceso_inventario() then
    raise exception 'Acceso denegado: se requiere el modulo inventario.';
  end if;

  if p_tipo not in ('entrada','salida','ajuste_entrada','ajuste_salida') then
    raise exception 'Tipo de movimiento invalido: %. Use entrada, salida, ajuste_entrada o ajuste_salida.', p_tipo;
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser un entero positivo.';
  end if;

  select activo, origen into v_activo, v_origen
    from productos
   where id = p_product_id
   for update;
  if v_activo is null then
    raise exception 'El producto % no existe.', p_product_id;
  end if;
  if v_origen = 'proveedor' then
    raise exception 'DS_PRODUCTO_PROVEEDOR_SIN_INVENTARIO: este producto se controla desde Dropshipping, no desde el libro de Inventario.';
  end if;
  if not v_activo then
    raise exception 'El producto % esta inactivo; no admite movimientos.', p_product_id;
  end if;

  insert into movimientos_inventario (
    product_id, tipo, cantidad, motivo, referencia, costo_unitario_mov, fecha
  ) values (
    p_product_id, p_tipo, p_cantidad, p_motivo, p_referencia, p_costo_unitario_mov,
    coalesce(p_fecha, current_date)
  )
  returning id into v_id;

  select coalesce(sum(
           case tipo
             when 'entrada'        then  cantidad
             when 'ajuste_entrada' then  cantidad
             when 'salida'         then -cantidad
             when 'ajuste_salida'  then -cantidad
           end
         ), 0)::integer
    into v_existencias
    from movimientos_inventario
   where product_id = p_product_id;

  return jsonb_build_object('id', v_id, 'existencias', v_existencias);
end;
$$;

comment on function inv_registrar_movimiento(uuid, text, integer, text, text, bigint, date) is
  'Inventario · escribe un movimiento append-only de producto propio. D1: rechaza de forma clara productos.origen=proveedor; el gatillo de la tabla replica el candado para toda otra ruta. C1 bloquea primero el producto para serializar la decisión con crear_pedido. Una salida propia puede quedar negativa como contrato historico del modulo.';

-- La lectura externa de Dropi ocurre antes de entrar aquí. Tanto el resultado
-- bueno como el error toman el mismo candado de producto antes de validar o
-- actualizar producto_proveedor, y así se serializan con crear_pedido.
create or replace function ds_registrar_lectura_stock(
  p_product_id uuid,
  p_stock      integer default null,
  p_error      text    default null
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_minutos integer;
  v_ahora   timestamptz := now();
  v_vence   timestamptz;
  v_origen  text;
begin
  if p_product_id is null then
    raise exception 'DS_FALTA_PRODUCTO';
  end if;

  select origen into v_origen
    from productos
   where id = p_product_id
   for update;

  if not found or v_origen is distinct from 'proveedor' or not exists (
    select 1
      from producto_proveedor pp
     where pp.product_id = p_product_id
  ) then
    raise exception 'DS_PRODUCTO_NO_PROVEEDOR';
  end if;

  -- Lectura fallida (o sin dato): solo se anota el intento. El stock queda
  -- intacto y su vigencia sigue corriendo hacia el vencimiento.
  if p_error is not null or p_stock is null then
    update producto_proveedor
    set ultimo_intento = v_ahora,
        ultimo_error   = left(coalesce(p_error, 'sin dato de stock'), 300),
        actualizado    = v_ahora
    where product_id = p_product_id;
    return null;
  end if;

  if p_stock < 0 then
    raise exception 'DS_STOCK_NEGATIVO';
  end if;

  select vigencia_minutos into v_minutos from dropshipping_config where id = 1;
  v_vence := v_ahora + make_interval(mins => coalesce(v_minutos, 120));

  update producto_proveedor
  set stock_reportado = p_stock,
      stock_leido_en  = v_ahora,
      stock_vence_en  = v_vence,
      ultimo_intento  = v_ahora,
      ultimo_error    = null,
      actualizado     = v_ahora
  where product_id = p_product_id;

  return v_vence;
end;
$$;

comment on function ds_registrar_lectura_stock(uuid, integer, text) is
  'D2c.1 · la Edge Function dropi-refrescar-stock escribe aqui lo que leyo de Dropi (service_role). C1 bloquea primero productos para serializar tanto lecturas buenas como errores con crear_pedido. Una lectura buena mueve stock_reportado/leido_en/vence_en; una FALLIDA solo anota el intento y el error, sin tocar el stock ni la vigencia: fallar jamas puede alargarle la vida a un dato viejo. Devuelve la nueva fecha de vencimiento, o null si fue fallo.';

-- Retirar un placeholder puede tocar producto y campaña. La primera lectura no
-- bloquea y solo resuelve el producto; después el orden obligatorio es producto
-- -> campaña. Bajo el lock de campaña se revalidan placeholder y vínculo.
create or replace function cm_retirar_placeholder(
  p_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_es_placeholder boolean;
  v_product_id_pre  uuid;
  v_product_id      uuid;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  -- Lectura preliminar sin lock: únicamente resuelve qué producto bloquear.
  select product_id_ref
    into v_product_id_pre
    from campana_producto
   where id = p_id;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if v_product_id_pre is not null then
    perform 1
      from productos
     where id = v_product_id_pre
     for update;
  end if;

  -- Orden producto -> campaña. La relectura evita actuar si el vínculo cambió
  -- mientras se esperaba cualquiera de los candados.
  select es_placeholder, product_id_ref
    into v_es_placeholder, v_product_id
    from campana_producto
   where id = p_id
   for update;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;
  if v_product_id is distinct from v_product_id_pre then
    raise exception 'La campana % cambio de producto durante el retiro; reintente.', p_id;
  end if;

  if v_es_placeholder is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  -- PROTECCION: solo se retiran EJEMPLOS. Un producto real no se "retira" por
  -- esta via (se despublica/edita normal); evita sacar algo real por accidente.
  if not v_es_placeholder then
    raise exception 'La campana % no es un producto de ejemplo (es_placeholder=false): no se retira por esta via.', p_id;
  end if;

  -- Baja LOGICA de la campana ficticia: sale de la tienda (publicado=false) y
  -- deja de estar activa (activo=false). NUNCA delete: la ficha sigue viva.
  update campana_producto
     set publicado   = false,
         activo      = false,
         actualizado = now()
   where id = p_id;

  -- El producto ya fue bloqueado antes que la campaña. Solo se da de baja si
  -- también es placeholder; un producto REAL ligado nunca se toca.
  if v_product_id is not null then
    update productos
       set activo = false
     where id = v_product_id
       and es_placeholder = true;
  end if;

  return p_id;
end;
$$;

comment on function cm_retirar_placeholder(uuid) is
  'CAMPANAS · RETIRA un producto de EJEMPLO (es_placeholder=true) desde el panel, sin SQL manual y sin borrado fisico (Decision de Oro del dueno: un ficticio NO se edita para volverlo real; se RETIRA y se crea uno nuevo). Baja LOGICA: pone publicado=false (sale de catalogo_publico) y activo=false; marca actualizado. Si el producto de Inventario ligado (product_id_ref) TAMBIEN es placeholder, lo da de baja logica (activo=false); si es REAL, NO lo toca. SOLO opera sobre campanas con es_placeholder=true (retirar un producto real es un error explicito). C1 bloquea en orden producto -> campaña y revalida el vínculo bajo lock. Valida tiene_acceso_marketing(). NUNCA delete. Devuelve el id.';

-- ----------------------------------------------------------------------------
-- (C) Disponibilidad. La puerta exacta por producto sigue siendo privada.
--     Proveedor protege el piso también DESPUÉS de la compra.
-- ----------------------------------------------------------------------------
create or replace function ventas_disponible_para_venta(p_product_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
  select case
    when coalesce(p.origen, 'propio') = 'propio'
      then coalesce((select s.existencias from stock_actual s where s.product_id = p.id), 0)
    when pp.product_id is null
      or pp.stock_reportado is null
      or pp.stock_vence_en is null
      or pp.stock_vence_en <= now()
      then 0
    else greatest(
      pp.stock_reportado
      - coalesce((
          select sum(r.cantidad)
            from pedido_proveedor r
            join pedidos pe on pe.id = r.pedido_id
           where r.product_id = p.id
             and r.transcrito_en is null
             and pe.estado <> 'anulado'
        ), 0)
      - coalesce(pp.piso_vitrina, cfg.piso_vitrina, 20),
      0
    )::integer
  end
  from productos p
  left join producto_proveedor pp on pp.product_id = p.id
  left join (select piso_vitrina from dropshipping_config where id = 1) cfg on true
  where p.id = p_product_id;
$fn$;

comment on function ventas_disponible_para_venta(uuid) is
  'C1 comercial · disponibilidad exacta interna por producto. Propio: libro de Inventario. Proveedor: lectura Dropi vigente menos pedidos pagados sin transcribir menos el piso efectivo, nunca menor que cero. Helper privado: solo service_role.';

revoke all on function ventas_disponible_para_venta(uuid) from public, anon, authenticated;
grant execute on function ventas_disponible_para_venta(uuid) to service_role;

-- ÚNICA función que decide el máximo comprable de una campaña. Devuelve solo
-- el valor público acotado 0..20; no revela cuál candado lo redujo.
create or replace function ventas_max_comprable_campana(p_campana_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_max          integer;
  v_tope         integer;
  v_product_id   uuid;
  v_publicado    boolean;
  v_camp_activa  boolean;
  v_prod_activo  boolean;
  v_origen       text;
  v_prov_hab     boolean;
  v_disponible   integer;
begin
  select cp.max_unidades_pedido, cp.tope_escaparate, cp.product_id_ref,
         cp.publicado, cp.activo, p.activo, coalesce(p.origen, 'propio'),
         coalesce(cfg.venta_proveedor_habilitada, false)
    into v_max, v_tope, v_product_id, v_publicado, v_camp_activa,
         v_prod_activo, v_origen, v_prov_hab
    from campana_producto cp
    left join productos p on p.id = cp.product_id_ref
    left join (select venta_proveedor_habilitada
                 from dropshipping_config where id = 1) cfg on true
   where cp.id = p_campana_id;

  if not found
     or coalesce(v_publicado, false) is not true
     or coalesce(v_camp_activa, false) is not true
     or v_product_id is null
     or coalesce(v_prod_activo, false) is not true
     or (v_origen = 'proveedor' and not v_prov_hab)
     or v_tope = 0 then
    return 0;
  end if;

  v_disponible := coalesce(ventas_disponible_para_venta(v_product_id), 0);
  return greatest(0, least(coalesce(v_max, 1), v_disponible, 20))::integer;
end;
$$;

comment on function ventas_max_comprable_campana(uuid) is
  'C1 comercial · única regla del máximo comprable por campaña: 0 si no está publicable/comprable o tope_escaparate=0; si no, min(max_unidades_pedido, disponibilidad), acotado 0..20. Un tope_escaparate positivo NO limita este máximo. No revela stock, piso, reservas, origen ni proveedor.';

-- La vista pública del dueño puede invocarla, pero no se abre una RPC anónima.
revoke all on function ventas_max_comprable_campana(uuid) from public, anon, authenticated;
grant execute on function ventas_max_comprable_campana(uuid) to service_role;

-- ----------------------------------------------------------------------------
-- (D) Catálogo público: mismo shape y filtros; se agrega SOLO max_comprable al
--     final y agotado deriva exactamente de ese valor.
-- ----------------------------------------------------------------------------
create or replace view catalogo_publico as
select
  cp.id,
  cp.nombre,
  cp.slug,
  cp.categoria_codigo,
  cc.nombre        as categoria_nombre,
  cc.color_fuerte,
  cc.color_claro,
  cc.color_sombra,
  cp.detalle_presentacion,
  cp.imagen_banner_path,
  cp.caracteristica_adicional,
  cp.precio_venta,
  cp.hook_largo,
  cp.por_que_magandhi,
  cp.sobre_este_producto,
  cp.ficha_tecnica,
  cp.imagenes,
  cp.sello_elegido,
  cp.estrella,
  (mx.max_comprable = 0) as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden,
  mx.max_comprable
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
left join productos p on p.id = cp.product_id_ref
left join (select venta_proveedor_habilitada
             from dropshipping_config where id = 1) dcfg on true
cross join lateral (
  select ventas_max_comprable_campana(cp.id) as max_comprable
) mx
where cp.publicado = true
  and cp.activo = true
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view catalogo_publico is
  'C1 comercial · lista blanca pública. Conserva las columnas y filtros vigentes y agrega únicamente max_comprable (0..20), ya limitado por campaña y disponibilidad. agotado equivale a max_comprable=0. Nunca expone stock, máximo desnudo, piso, reservas, origen, proveedor ni ids internos/externos.';

grant select on catalogo_publico to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) Registrar intención: misma firma para Edge actual. Relee y bloquea datos
--     autoritativos, repite máximo/disponibilidad y exige que el snapshot que
--     llegó coincida antes de persistir lo que se firmará.
-- ----------------------------------------------------------------------------
create or replace function pw_registrar_intencion(
  p_referencia      text,
  p_campana_id      uuid,
  p_slug            text,
  p_nombre          text,
  p_cantidad        integer,
  p_precio_unitario bigint,
  p_monto_centavos  bigint,
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
  v_product_id_pre uuid;
  v_cp             campana_producto;
  v_producto       productos;
  v_max            integer;
  v_monto          bigint;
  v_existente      pagos_intencion;
  v_insertadas     integer;
  v_moneda         text := coalesce(nullif(p_moneda, ''), 'COP');
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    raise exception 'PW_REFERENCIA_INVALIDA';
  end if;
  if p_cantidad is null or p_cantidad not between 1 and 20 then
    raise exception 'PW_CANTIDAD_INVALIDA';
  end if;
  if coalesce(p_entorno, '') not in ('sandbox','prod') then
    raise exception 'PW_ENTORNO_INVALIDO';
  end if;
  if v_moneda <> 'COP' then
    raise exception 'PW_MONEDA_INVALIDA';
  end if;

  -- Retry idempotente: primero bloquea una intención ya existente. No relee la
  -- campaña actual ni toma sus candados, porque el snapshot ya fue firmado y
  -- podría haber cambiado después. Así también conserva el orden de locks del
  -- webhook (intención antes de producto) y evita una inversión innecesaria.
  select * into v_existente from pagos_intencion
   where referencia = p_referencia for update;
  if found then
    if v_existente.version_checkout is distinct from 1
       or v_existente.campana_id is distinct from p_campana_id
       or v_existente.slug is distinct from p_slug
       or v_existente.nombre is distinct from p_nombre
       or v_existente.cantidad is distinct from p_cantidad
       or v_existente.precio_unitario is distinct from p_precio_unitario
       or v_existente.monto_centavos is distinct from p_monto_centavos
       or v_existente.moneda is distinct from v_moneda
       or v_existente.entorno is distinct from p_entorno then
      raise exception 'PW_REFERENCIA_REUTILIZADA';
    end if;
    return jsonb_build_object(
      'referencia', v_existente.referencia,
      'product_id', v_existente.product_id,
      'ligado', v_existente.product_id is not null,
      'campana_id', v_existente.campana_id,
      'slug', v_existente.slug,
      'nombre', v_existente.nombre,
      'cantidad', v_existente.cantidad,
      'precio_unitario', v_existente.precio_unitario::text,
      'monto_centavos', v_existente.monto_centavos::text,
      'moneda', v_existente.moneda,
      'max_comprable', v_existente.cantidad
    );
  end if;

  -- Orden de candados igual al núcleo de pedidos: producto y luego campaña.
  -- La primera lectura solo resuelve qué producto bloquear; la campaña se
  -- relee bajo FOR UPDATE y se exige que el vínculo no haya cambiado.
  select cp.product_id_ref into v_product_id_pre
    from campana_producto cp where cp.id = p_campana_id;
  if not found or v_product_id_pre is null then
    raise exception 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  select * into v_producto from productos
   where id = v_product_id_pre for update;
  if not found then
    raise exception 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  select * into v_cp from campana_producto
   where id = p_campana_id for update;
  if not found
     or v_cp.product_id_ref is distinct from v_product_id_pre
     or coalesce(v_cp.publicado, false) is not true
     or coalesce(v_cp.activo, false) is not true
     or coalesce(v_producto.activo, false) is not true
     or v_cp.precio_venta is null
     or v_cp.precio_venta <= 0 then
    raise exception 'PW_CAMPANA_NO_COMPRABLE';
  end if;

  v_max := ventas_max_comprable_campana(v_cp.id);
  if p_cantidad > v_max then
    raise exception 'PW_MAX_COMPRABLE:%', v_max;
  end if;

  v_monto := v_cp.precio_venta * p_cantidad::bigint * 100::bigint;

  -- La firma se conserva para desplegar sin romper la Edge anterior, pero sus
  -- datos dejan de ser confiables: deben coincidir con la relectura autoritativa.
  if p_slug is distinct from v_cp.slug
     or p_nombre is distinct from v_cp.nombre
     or p_precio_unitario is distinct from v_cp.precio_venta
     or p_monto_centavos is distinct from v_monto then
    raise exception 'PW_DATOS_DESACTUALIZADOS';
  end if;

  insert into pagos_intencion (
    referencia, campana_id, product_id, slug, nombre, cantidad, precio_unitario,
    monto_centavos, moneda, entorno, version_checkout,
    comprador_nombre, comprador_correo, comprador_telefono, comprador_direccion,
    comprador_ciudad, comprador_departamento, comprador_pais,
    utm_campaign, mg_vid
  ) values (
    p_referencia, v_cp.id, v_producto.id, v_cp.slug, v_cp.nombre,
    p_cantidad, v_cp.precio_venta, v_monto, v_moneda, p_entorno, 1,
    nullif(btrim(p_comprador->>'nombre'), ''),
    nullif(btrim(p_comprador->>'correo'), ''),
    nullif(btrim(p_comprador->>'telefono'), ''),
    nullif(btrim(p_comprador->>'direccion'), ''),
    nullif(btrim(p_comprador->>'ciudad'), ''),
    nullif(btrim(p_comprador->>'departamento'), ''),
    nullif(btrim(p_comprador->>'pais'), ''),
    nullif(p_utm_campaign, ''), nullif(p_mg_vid, '')
  )
  on conflict (referencia) do nothing;
  get diagnostics v_insertadas = row_count;

  select * into v_existente from pagos_intencion
   where referencia = p_referencia for update;

  if v_insertadas = 0 and (
       v_existente.campana_id is distinct from v_cp.id
       or v_existente.product_id is distinct from v_producto.id
       or v_existente.slug is distinct from v_cp.slug
       or v_existente.nombre is distinct from v_cp.nombre
       or v_existente.cantidad is distinct from p_cantidad
       or v_existente.precio_unitario is distinct from v_cp.precio_venta
       or v_existente.monto_centavos is distinct from v_monto
       or v_existente.moneda is distinct from v_moneda
       or v_existente.entorno is distinct from p_entorno
       or v_existente.version_checkout is distinct from 1
     ) then
    raise exception 'PW_REFERENCIA_REUTILIZADA';
  end if;

  return jsonb_build_object(
    'referencia', v_existente.referencia,
    'product_id', v_existente.product_id,
    'ligado', v_existente.product_id is not null,
    'campana_id', v_existente.campana_id,
    'slug', v_existente.slug,
    'nombre', v_existente.nombre,
    'cantidad', v_existente.cantidad,
    'precio_unitario', v_existente.precio_unitario::text,
    'monto_centavos', v_existente.monto_centavos::text,
    'moneda', v_existente.moneda,
    'max_comprable', v_max
  );
end;
$$;

comment on function pw_registrar_intencion(text, uuid, text, text, integer, bigint, bigint, text, jsonb, text, text, text) is
  'C1 comercial · conserva la firma F2 para compatibilidad, pero bloquea/relee campaña y producto, valida cantidad 1..20 y max_comprable, recalcula precio/monto con bigint y exige consistencia antes de persistir el snapshot autoritativo. Devuelve precio_unitario y monto_centavos como texto exacto. Solo service_role.';

revoke execute on function pw_registrar_intencion(text, uuid, text, text, integer, bigint, bigint, text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function pw_registrar_intencion(text, uuid, text, text, integer, bigint, bigint, text, jsonb, text, text, text) to service_role;

-- ----------------------------------------------------------------------------
-- (F) crear_pedido: misma firma y semántica manual. Para items web que traen
--     campana_id, consolida por campaña/producto, bloquea la campaña y repite
--     vínculo, publicación, actividad, máximo y disponibilidad final.
--     versión 0 conservan el camino escalar F2/F3 mediante una compuerta local
--     que solo abre pw_procesar_pago.
-- ----------------------------------------------------------------------------
create or replace function crear_pedido(
  p_customer_id    uuid    default null,
  p_nombre         text    default null,
  p_correo         text    default null,
  p_telefono       text    default null,
  p_direccion      text    default null,
  p_ciudad         text    default null,
  p_departamento   text    default null,
  p_pais           text    default null,
  p_notas_cliente  text    default null,
  p_canal          text    default 'manual',
  p_fecha_orden    date    default current_date,
  p_notas_pedido   text    default null,
  p_items          jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id   uuid := p_customer_id;
  v_correo_norm   text := ventas_norm_correo(p_correo);
  v_telefono_norm text := ventas_norm_telefono(p_telefono);
  v_canal         text := coalesce(nullif(trim(p_canal), ''), 'manual');
  v_fecha         date := coalesce(p_fecha_orden, current_date);
  v_pedido_id     uuid;
  v_total         bigint := 0;
  v_item          jsonb;
  v_product_id    uuid;
  v_cantidad      integer;
  v_precio        bigint;
  v_subtotal      bigint;
  v_activo        boolean;
  v_req           record;
  v_nom_prod      text;
  v_disponible    integer;
  v_origen        text;
  v_campana       record;
  v_checkout_legacy boolean;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  if v_canal not in ('manual','web') then
    raise exception 'Canal invalido: %. Use manual o web.', v_canal;
  end if;

  -- Excepción estrecha para materializar intenciones F2/F3 históricas. Solo
  -- pw_procesar_pago puede abrir ambas variables impulse.* dentro de su
  -- transacción; una llamada normal web debe traer campana_id.
  v_checkout_legacy := v_canal = 'web'
    and pw__contexto_servidor()
    and coalesce(current_setting('impulse.checkout_legacy', true), '') = 'on';

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe tener al menos un item.';
  end if;

  -- Candado de stock por producto, consolidado y en orden estable.
  for v_req in
    select (e->>'product_id')::uuid as product_id,
           sum((e->>'cantidad')::integer) as cantidad
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    if v_req.product_id is null then
      raise exception 'Cada item requiere product_id.';
    end if;
    continue when v_req.cantidad is null or v_req.cantidad <= 0;
    if v_canal = 'web' and v_req.cantidad > 20 then
      raise exception 'CM_TECHO_TECNICO_EXCEDIDO: un pedido web admite máximo 20 unidades por producto.';
    end if;

    select nombre into v_nom_prod from productos
     where id = v_req.product_id for update;
    if not found then
      raise exception 'El producto % no existe.', v_req.product_id;
    end if;

    select coalesce(p.origen, 'propio') into v_origen
      from productos p where p.id = v_req.product_id;

    -- Compatibilidad estrictamente acotada a intenciones históricas versión 0.
    -- Bajo la compuerta servidor + checkout_legacy, proveedor conserva la regla
    -- con la que se firmó: lectura vigente, stock bruto >= piso y después
    -- stock menos pendientes, SIN volver a restar el piso. Ninguna llamada web
    -- ordinaria puede abrir esta rama; C1 y el camino manual usan la regla nueva.
    if v_checkout_legacy and v_origen = 'proveedor' then
      select case
        when pp.product_id is null
          or pp.stock_reportado is null
          or pp.stock_vence_en is null
          or pp.stock_vence_en <= now()
          or pp.stock_reportado < coalesce(pp.piso_vitrina, cfg.piso_vitrina, 20)
          then 0
        else greatest(
          pp.stock_reportado
          - coalesce((
              select sum(r.cantidad)
                from pedido_proveedor r
                join pedidos pe on pe.id = r.pedido_id
               where r.product_id = v_req.product_id
                 and r.transcrito_en is null
                 and pe.estado <> 'anulado'
            ), 0),
          0
        )::integer
      end
        into v_disponible
        from productos p
        left join producto_proveedor pp on pp.product_id = p.id
        left join (select piso_vitrina from dropshipping_config where id = 1) cfg on true
       where p.id = v_req.product_id;
    else
      v_disponible := coalesce(ventas_disponible_para_venta(v_req.product_id), 0);
    end if;

    if v_disponible < v_req.cantidad then
      if v_origen = 'proveedor' then
        raise exception 'STOCK_INSUFICIENTE: «%» reporta % unidad(es) vendible(s) conservando el piso del proveedor y el pedido pide %.',
          v_nom_prod, greatest(v_disponible, 0), v_req.cantidad;
      else
        raise exception 'STOCK_INSUFICIENTE: «%» tiene % unidad(es) disponible(s) y el pedido pide %. Registra primero la entrada en Inventario.',
          v_nom_prod, greatest(v_disponible, 0), v_req.cantidad;
      end if;
    end if;
  end loop;

  -- C1: para el canal web NUEVO, dos líneas no pueden evadir el máximo.
  -- Las intenciones versión 0 se toleran únicamente bajo la compuerta local
  -- abierta por pw_procesar_pago; el Edge C1 siempre incluye campana_id.
  if v_canal = 'web' then
    for v_req in
      select nullif(e->>'campana_id', '')::uuid as campana_id,
             (e->>'product_id')::uuid as product_id,
             sum((e->>'cantidad')::integer) as cantidad
        from jsonb_array_elements(p_items) e
       group by 1, 2
       order by 1 nulls last, 2
    loop
      if v_req.campana_id is null then
        if not v_checkout_legacy then
          raise exception 'CM_CAMPANA_REQUERIDA: cada item web C1 requiere campana_id.';
        end if;
        continue;
      end if;
      continue when v_req.cantidad is null or v_req.cantidad <= 0;

      select cp.id, cp.product_id_ref, cp.publicado, cp.activo,
             cp.max_unidades_pedido, p.activo as producto_activo
        into v_campana
        from campana_producto cp
        left join productos p on p.id = cp.product_id_ref
       where cp.id = v_req.campana_id
       for update of cp;

      if not found then
        raise exception 'CM_CAMPANA_NO_COMPRABLE: la campaña % no existe.', v_req.campana_id;
      end if;
      if v_campana.product_id_ref is distinct from v_req.product_id then
        raise exception 'CM_CAMPANA_PRODUCTO_INVALIDO: la campaña no corresponde al producto cobrado.';
      end if;
      if coalesce(v_campana.publicado, false) is not true
         or coalesce(v_campana.activo, false) is not true
         or coalesce(v_campana.producto_activo, false) is not true then
        raise exception 'CM_CAMPANA_NO_COMPRABLE: la campaña o el producto ya no están activos/publicados.';
      end if;
      if v_req.cantidad > v_campana.max_unidades_pedido then
        raise exception 'CM_MAX_UNIDADES_EXCEDIDO: el pedido solicita % y la campaña admite %.',
          v_req.cantidad, v_campana.max_unidades_pedido;
      end if;

      v_disponible := ventas_max_comprable_campana(v_req.campana_id);
      if v_req.cantidad > v_disponible then
        raise exception 'CM_MAX_COMPRABLE_CAMBIO: el pedido solicita % y ahora se pueden comprar %.',
          v_req.cantidad, v_disponible;
      end if;
    end loop;
  end if;

  -- Resolver o crear cliente (semántica vigente).
  if v_customer_id is null then
    if v_correo_norm is not null then
      select id into v_customer_id from clientes where correo_norm = v_correo_norm limit 1;
    end if;
    if v_customer_id is null and v_telefono_norm is not null then
      select id into v_customer_id from clientes where telefono_norm = v_telefono_norm limit 1;
    end if;

    if v_customer_id is null then
      if p_nombre is null or length(trim(p_nombre)) = 0 then
        raise exception 'Para un cliente nuevo el nombre es obligatorio.';
      end if;
      insert into clientes (
        nombre, correo, correo_norm, telefono, telefono_norm,
        direccion, ciudad, departamento, pais, notas
      ) values (
        trim(p_nombre), p_correo, v_correo_norm, p_telefono, v_telefono_norm,
        p_direccion, p_ciudad, p_departamento,
        coalesce(nullif(trim(p_pais), ''), 'Colombia'), p_notas_cliente
      )
      returning id into v_customer_id;
    end if;
  else
    perform 1 from clientes where id = v_customer_id;
    if not found then
      raise exception 'El cliente % no existe.', v_customer_id;
    end if;
  end if;

  insert into pedidos (
    customer_id, fecha_orden, estado, canal, total, notas,
    direccion, ciudad, departamento, pais
  ) values (
    v_customer_id, v_fecha, 'recibido', v_canal, 0, p_notas_pedido,
    p_direccion, p_ciudad, p_departamento,
    coalesce(nullif(trim(p_pais), ''), 'Colombia')
  )
  returning id into v_pedido_id;

  -- Líneas, total y salida/reserva. Conserva exactamente el camino vigente.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_cantidad   := (v_item->>'cantidad')::integer;
    v_precio     := (v_item->>'precio_unitario')::bigint;

    if v_product_id is null then
      raise exception 'Cada item requiere product_id.';
    end if;
    if v_cantidad is null or v_cantidad <= 0 then
      raise exception 'La cantidad de cada item debe ser un entero positivo.';
    end if;
    if v_precio is null or v_precio < 0 then
      raise exception 'El precio_unitario de cada item debe ser un bigint no negativo.';
    end if;

    select activo, coalesce(origen, 'propio') into v_activo, v_origen
      from productos where id = v_product_id;
    if v_activo is null then
      raise exception 'El producto % no existe.', v_product_id;
    end if;
    if not v_activo then
      raise exception 'El producto % esta inactivo; no admite movimientos.', v_product_id;
    end if;

    v_subtotal := v_cantidad::bigint * v_precio;
    v_total := v_total + v_subtotal;

    insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
    values (v_pedido_id, v_product_id, v_cantidad, v_precio, v_subtotal);

    if v_origen = 'proveedor' then
      insert into pedido_proveedor (
        pedido_id, product_id, producto_externo_id, variacion_externa_id,
        cantidad, stock_al_vender, stock_leido_en
      )
      select v_pedido_id, v_product_id, pp.producto_externo_id,
             pp.variacion_externa_id, v_cantidad, pp.stock_reportado,
             pp.stock_leido_en
        from producto_proveedor pp
       where pp.product_id = v_product_id
      on conflict (pedido_id, product_id) do update
        set cantidad = pedido_proveedor.cantidad + excluded.cantidad;
    else
      insert into movimientos_inventario (
        product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
      ) values (
        v_product_id, 'salida', v_cantidad, 'Venta',
        v_pedido_id::text, v_customer_id, v_fecha
      );
    end if;
  end loop;

  update pedidos set total = v_total, actualizado = now() where id = v_pedido_id;

  insert into pedido_bitacora (
    pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor
  ) values (
    v_pedido_id, 'crear', null, 'recibido',
    jsonb_build_object('canal', v_canal, 'total', v_total,
                       'customer_id', v_customer_id),
    auth.uid()
  );

  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'customer_id', v_customer_id,
    'total', v_total
  );
end;
$$;

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is
  'Núcleo único de pedidos manuales y web. C1 conserva firma y camino manual; stock se consolida/bloquea por producto y el canal web tiene techo técnico agregado de 20. Items web C1 requieren campana_id y se consolidan por campaña/producto para revalidar bajo lock vínculo, publicación, actividad, max_unidades_pedido y max_comprable final. Solo pw_procesar_pago puede habilitar temporalmente el camino histórico versión 0 sin campaña; para proveedor ese camino conserva lectura vigente, stock bruto >= piso y stock menos pendientes sin restar el piso.';

revoke execute on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) from public, anon;
grant execute on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (G) Webhook: misma firma y semántica F2/F3. Único cambio: la intención C1
--     pasa campana_id dentro del item para versión 1. Una intención histórica
--     versión 0 omite la clave bajo una compuerta transaccional no falsificable.
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
      p_items         => jsonb_build_array(
        jsonb_build_object(
          'product_id', v_i.product_id,
          'cantidad', v_i.cantidad,
          'precio_unitario', v_i.precio_unitario
        ) || case
               when v_i.version_checkout = 0 then '{}'::jsonb
               else jsonb_build_object('campana_id', v_i.campana_id)
             end
      )
    );
    v_pedido_id := (v_pedido->>'pedido_id')::uuid;
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
  exception when others then
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
  'Pagos web F2/F3 + C1 · conserva firma, idempotencia, revisión, fecha Colombia, atribución y asiento best-effort. C1 pasa campana_id al item de crear_pedido para versión_checkout=1; las intenciones históricas versión 0 usan una compuerta local no falsificable y conservan el camino F2/F3.';

-- Se elimina una firma F2 transitoria de 9 argumentos si sobreviviera en un
-- entorno con drift. La firma vigente de 10 argumentos permanece.
drop function if exists pw_procesar_pago(text, text, text, bigint, text, text, jsonb, text, text);

revoke execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) from public, anon, authenticated;
grant execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) to service_role;

commit;
