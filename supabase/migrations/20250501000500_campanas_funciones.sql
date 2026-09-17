-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Funciones RPC (unica via de escritura)
-- ------------------------------------------------------------
-- Toda ESCRITURA de Campanas pasa por estas RPC, espejo de las de Inventario
-- (inv_crear_producto / inv_editar_producto) y Finanzas (guardar_asiento). Las
-- tablas de Campanas NO tienen policy de INSERT/UPDATE/DELETE (ver
-- 20250501000400): el cliente nunca escribe directo.
--
-- Todas son:
--   - language plpgsql, security definer, set search_path = public fijo.
--   - Validan tiene_acceso_marketing() al entrar, de modo que el candado de
--     acceso se respeta aunque la funcion salte RLS por ser definer.
--
-- REGLAS DURAS: precio_venta en bigint (pesos enteros); NADA se borra
-- (despublicar / baja logica); las etiquetas de un producto se REEMPLAZAN en
-- bloque (delete + insert de la tabla puente dentro de la RPC, no DELETE de
-- catalogo).
--
-- AVISO DE URGENCIA (criterio del dueno): es un interruptor MANUAL y HONESTO.
-- Se activa en el momento adecuado (por ejemplo, cuando de verdad quedan 3
-- unidades), nada de escasez fabricada. Por eso, si aviso_urgencia_activo=true,
-- la RPC EXIGE que aviso_urgencia_cantidad sea no nulo y > 0: no se puede
-- prender el aviso sin decir cuantas unidades quedan.
--
-- FIRMAS EXACTAS (para el frontend, FEAT-002/003):
--   cm_crear_campana(p_nombre, p_categoria_codigo, p_detalle_presentacion,
--     p_hook_corto, p_imagen_banner_path, p_caracteristica_adicional,
--     p_precio_venta bigint, p_hook_largo, p_por_que_magandhi,
--     p_sobre_este_producto, p_ficha_tecnica jsonb, p_imagenes jsonb,
--     p_sello_elegido, p_estrella, p_stock_disponible, p_aviso_urgencia_activo,
--     p_aviso_urgencia_cantidad, p_etiquetas text[]) -> jsonb {id}
--   cm_editar_campana(p_id uuid, ...mismos campos...) -> uuid
--   cm_publicar_campana(p_id uuid, p_publicado boolean) -> uuid
--
-- IDEMPOTENTE: create or replace (re-ejecutar solo actualiza la logica).
-- REQUISITO: correr DESPUES de 20250501000000..000200 y 20250301000600.
-- ============================================================

-- ------------------------------------------------------------
-- cm_crear_campana: alta de un producto vestido. Inserta la fila y asigna sus
-- etiquetas de segmentacion (tabla puente). Devuelve jsonb {id}.
-- ------------------------------------------------------------
create or replace function cm_crear_campana(
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_hook_corto              text default null,
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
  p_etiquetas               text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_tag text;
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
  -- Aviso de urgencia MANUAL y HONESTO: si esta activo, exige un numero > 0.
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;

  insert into campana_producto (
    nombre, categoria_codigo, detalle_presentacion, hook_corto, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_hook_corto, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false), p_aviso_urgencia_cantidad
  )
  returning id into v_id;

  -- Asignar etiquetas de segmentacion (si vinieron). Ignora nulos/vacios.
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

comment on function cm_crear_campana(text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[]) is 'CAMPANAS · alta de un producto vestido y asignacion de sus etiquetas de segmentacion (tabla puente). Valida tiene_acceso_marketing(), nombre obligatorio, precio_venta >= 0 y, si aviso_urgencia_activo=true, cantidad > 0 (aviso REAL y manual). precio_venta en bigint. Devuelve jsonb {id}.';

-- ------------------------------------------------------------
-- cm_editar_campana: edita la ficha del producto. NUNCA borra. Marca
-- actualizado=now(). REEMPLAZA en bloque las etiquetas del producto por
-- p_etiquetas (borra las del puente para ESE producto y vuelve a insertar; no
-- toca el catalogo de etiquetas). No cambia publicado (eso es cm_publicar_campana)
-- ni activo (baja logica futura por otra via). Devuelve el id editado.
-- ------------------------------------------------------------
create or replace function cm_editar_campana(
  p_id                      uuid,
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_hook_corto              text default null,
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
  p_etiquetas               text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existe uuid;
  v_tag    text;
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

  select id into v_existe from campana_producto where id = p_id;
  if v_existe is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  -- Edita SOLO la ficha. No toca publicado (cm_publicar_campana) ni activo.
  update campana_producto
     set nombre                   = p_nombre,
         categoria_codigo         = p_categoria_codigo,
         detalle_presentacion     = p_detalle_presentacion,
         hook_corto               = p_hook_corto,
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
         actualizado              = now()
   where id = p_id;

  -- Reemplazar en bloque las etiquetas de ESTE producto (no toca el catalogo).
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[]) is 'CAMPANAS · edita la ficha del producto vestido y REEMPLAZA en bloque sus etiquetas de segmentacion (no toca el catalogo de etiquetas). Marca actualizado=now(). NUNCA borra el producto. No cambia publicado (eso es cm_publicar_campana). Mismas validaciones que cm_crear_campana (nombre, precio >= 0, aviso con cantidad > 0). Devuelve el id.';

-- ------------------------------------------------------------
-- cm_publicar_campana: interruptor publicar/despublicar. Despublicar NO borra,
-- solo pone publicado=false (sale de catalogo_publico). Devuelve el id.
-- ------------------------------------------------------------
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
  v_existe uuid;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select id into v_existe from campana_producto where id = p_id;
  if v_existe is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  update campana_producto
     set publicado   = coalesce(p_publicado, false),
         actualizado = now()
   where id = p_id;

  return p_id;
end;
$$;

comment on function cm_publicar_campana(uuid, boolean) is 'CAMPANAS · interruptor publicar/despublicar de un producto. Despublicar (false) NO borra: solo lo saca de la vista catalogo_publico. Valida tiene_acceso_marketing(). Marca actualizado=now(). Devuelve el id.';
