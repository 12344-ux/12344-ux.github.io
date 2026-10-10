-- ============================================================================
-- MAGANDHI · Dropshipping D2b · sello «Elegido por MAGANDHI»
-- ----------------------------------------------------------------------------
-- Forward sobre 20261024000000 (D2a).
--
-- DECISIÓN DEL DUEÑO · 10-oct-2026
--   D2b no abre un expediente ni una bitácora de pruebas. En el editor de
--   Campañas hay una única casilla: «Este producto fue probado por MAGANDHI».
--   Solo cuando está marcada se habilita Elegido por MAGANDHI.
--
-- La casilla pertenece a la presentación comercial (campana_producto), porque
-- gobierna exclusivamente este distintivo editorial. Si más adelante se necesita
-- auditar muestras, responsables, fechas o reevaluaciones, se crea un tramo
-- nuevo; este D2b no finge evidencia que el equipo no registró.
--
-- SEGURIDAD
--   La UI guía, pero la base impide sello_elegido=true sin la casilla en:
--   cm_crear_campana, cm_editar_campana, cm_publicar_campana y un trigger ante
--   DML privilegiado. D2b NO habilita publicación ni venta de proveedor: D1/D2a
--   siguen devolviendo DS_PUBLICACION_PENDIENTE hasta D2c.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Estado simple de curaduría por presentación comercial
-- ----------------------------------------------------------------------------
alter table campana_producto
  add column if not exists probado_por_magandhi boolean not null default false;

comment on column campana_producto.probado_por_magandhi is
  'D2b · confirmación simple del operador: el producto de esta campaña fue probado por el equipo MAGANDHI. Solo habilita sello_elegido; no es una bitácora, no publica proveedor y no sustituye futuros registros de muestras si se necesitan.';

-- ----------------------------------------------------------------------------
-- (B) Defensa en profundidad sobre la tabla de campañas
-- ----------------------------------------------------------------------------
create or replace function cm__campana_sello_exige_producto_probado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.probado_por_magandhi, false)
     and new.product_id_ref is null then
    raise exception 'CM_PRUEBA_SIN_PRODUCTO: liga un producto antes de marcarlo como probado por MAGANDHI.';
  end if;
  if coalesce(new.sello_elegido, false)
     and not coalesce(new.probado_por_magandhi, false) then
    raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de usar Elegido por MAGANDHI.';
  end if;
  return new;
end;
$$;

comment on function cm__campana_sello_exige_producto_probado() is
  'D2b · gatillo interno: exige producto ligado para probado_por_magandhi e impide sello_elegido sin esa confirmación incluso por DML privilegiado. No altera el bloqueo D1 de proveedor.';

revoke all on function cm__campana_sello_exige_producto_probado() from public, anon, authenticated;
grant execute on function cm__campana_sello_exige_producto_probado() to service_role;

drop trigger if exists cm_campana_sello_exige_producto_probado on campana_producto;
create trigger cm_campana_sello_exige_producto_probado
before insert or update of sello_elegido, probado_por_magandhi, product_id_ref on campana_producto
for each row execute function cm__campana_sello_exige_producto_probado();

-- ----------------------------------------------------------------------------
-- (C) RPC de alta y edición: la casilla viaja junto a la campaña
-- ----------------------------------------------------------------------------
-- Agregar un parámetro crea otra firma; se retiran las firmas vivas para que no
-- quede una vía antigua sin el candado. Sus ACL se restauran nominalmente abajo.
drop function if exists cm_crear_campana(
  text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
);

create function cm_crear_campana(
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_imagen_banner_path      text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta            bigint default null,
  p_hook_largo              text default null,
  p_por_que_magandhi        text default null,
  p_sobre_este_producto     text default null,
  p_ficha_tecnica           jsonb default '[]'::jsonb,
  p_imagenes                jsonb default '[]'::jsonb,
  p_sello_elegido           boolean default false,
  p_estrella                boolean default false,
  p_stock_disponible        integer default 0,
  p_aviso_urgencia_activo   boolean default false,
  p_aviso_urgencia_cantidad integer default null,
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,
  p_slug                    text default null,
  p_tope_escaparate         integer default null,
  p_producto_probado        boolean default false
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
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref, slug,
    tope_escaparate, probado_por_magandhi
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false),
    p_aviso_urgencia_cantidad, p_product_id_ref, v_slug,
    p_tope_escaparate, coalesce(p_producto_probado, false)
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

comment on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) is
  'CAMPANAS · alta de ficha comercial. D2b agrega p_producto_probado: solo con true puede guardar sello_elegido. Mantiene precio, aviso, tope, etiquetas, slug y el contrato D1/D2a.';

create function cm_editar_campana(
  p_id                      uuid,
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_imagen_banner_path      text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta            bigint default null,
  p_hook_largo              text default null,
  p_por_que_magandhi        text default null,
  p_sobre_este_producto     text default null,
  p_ficha_tecnica           jsonb default '[]'::jsonb,
  p_imagenes                jsonb default '[]'::jsonb,
  p_sello_elegido           boolean default false,
  p_estrella                boolean default false,
  p_stock_disponible        integer default 0,
  p_aviso_urgencia_activo   boolean default false,
  p_aviso_urgencia_cantidad integer default null,
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,
  p_slug                    text default null,
  p_tope_escaparate         integer default null,
  p_producto_probado        boolean default false
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

  select id into v_existe from campana_producto where id = p_id;
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) is
  'CAMPANAS · edición de ficha comercial. D2b agrega p_producto_probado: solo con true permite conservar o activar sello_elegido. No cambia el vínculo fijo de proveedor de D2a ni la regla de un solo distintivo.';

revoke execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) from public, anon;
grant execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) to authenticated, service_role;
revoke execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) from public, anon;
grant execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) Publicar: vuelve a validar la casilla antes de exponer la campaña
-- ----------------------------------------------------------------------------
create or replace function cm_publicar_campana(
  p_id        uuid,
  p_publicado boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_producto_id     uuid;
  v_precio          bigint;
  v_producto_activo boolean;
  v_origen          text;
  v_sello_elegido   boolean;
  v_producto_probado boolean;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select cp.product_id_ref, cp.precio_venta, p.activo, p.origen,
         cp.sello_elegido, cp.probado_por_magandhi
    into v_producto_id, v_precio, v_producto_activo, v_origen,
         v_sello_elegido, v_producto_probado
    from campana_producto cp
    left join productos p on p.id = cp.product_id_ref
   where cp.id = p_id;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if coalesce(p_publicado, false) then
    if v_producto_id is null then
      raise exception 'No se puede publicar: liga primero un producto de Inventario.';
    end if;
    if coalesce(v_producto_activo, false) is not true then
      raise exception 'No se puede publicar: el producto de Inventario esta inactivo.';
    end if;
    -- D2b NO abre D2c: proveedor sigue bloqueado antes de revisar el sello.
    if coalesce(v_origen, 'propio') = 'proveedor' then
      raise exception 'DS_PUBLICACION_PENDIENTE: este producto proveedor espera D2 (stock vivo y checkout seguro) antes de publicarse.';
    end if;
    if v_precio is null or v_precio <= 0 then
      raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
    end if;
    if coalesce(v_sello_elegido, false)
       and not coalesce(v_producto_probado, false) then
      raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de publicar Elegido por MAGANDHI.';
    end if;
  end if;

  update campana_producto
     set publicado   = coalesce(p_publicado, false),
         actualizado = now()
   where id = p_id;

  return p_id;
end;
$$;

comment on function cm_publicar_campana(uuid, boolean) is
  'CAMPANAS · publica/despublica sin borrar. D2b exige la casilla probado_por_magandhi cuando la campaña usa sello; D1 conserva proveedor bloqueado hasta D2c. Despublicar siempre queda permitido.';

revoke execute on function cm_publicar_campana(uuid, boolean) from public, anon;
grant execute on function cm_publicar_campana(uuid, boolean) to authenticated, service_role;

commit;
