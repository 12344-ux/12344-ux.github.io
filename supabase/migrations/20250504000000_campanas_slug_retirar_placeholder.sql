-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · C1: slug editable +
-- retirar producto de ejemplo (placeholder) desde la UI, sin SQL manual.
-- ------------------------------------------------------------
-- QUE ES ESTA MIGRACION (Campanas · tramo C1 del plan maestro ANDAMIOS):
-- una capa nueva sobre el cimiento (20250501*), la Tanda 1 (20250502000000:
-- es_placeholder + slug + indice unico parcial) y la incision de Inventario
-- (20250503000000: FK product_id_ref + RPC con p_product_id_ref al final). NO
-- recrea ninguna columna existente: la columna `slug` y su indice unico parcial
-- YA existen (20250502000000) y el flag `es_placeholder` YA existe en
-- campana_producto (20250502000000) y en productos (20250503000000). Aqui solo:
--
--   (1) EXTENDER cm_crear_campana / cm_editar_campana con el parametro nuevo
--       p_slug text default null AL FINAL de la firma (despues de
--       p_product_id_ref, que anadio la incision), para no romper el orden de
--       los parametros existentes. Se persiste el slug en el INSERT/UPDATE. Se
--       normaliza en el servidor (minusculas, sin acentos/enie, espacios ->
--       guion, quitar simbolos) para respetar el indice unico parcial y que la
--       URL publica quede limpia; un slug vacio despues de normalizar se guarda
--       como NULL (opcional, no choca con el unico parcial).
--
--       Como agregar un parametro cambia la LISTA DE TIPOS de argumentos y un
--       `create or replace` crearia una SOBRECARGA nueva (dos funciones con el
--       mismo nombre y distinto numero de argumentos), se hace `drop function
--       if exists` de la firma VIVA ACTUAL (la de 20250503000000, con
--       p_product_id_ref uuid al final) + `create` con la firma NUEVA. El drop
--       usa la lista de tipos VIEJA EXACTA; el create/comment, la NUEVA
--       (con text de p_slug al final). Se mantienen TODAS las validaciones
--       actuales (tiene_acceso_marketing, nombre obligatorio, precio >= 0, aviso
--       con cantidad > 0) y la logica de etiquetas y product_id_ref intactas.
--
--   (2) RPC nueva cm_retirar_placeholder(p_id uuid): RETIRA de la tienda un
--       producto de EJEMPLO (ficticio) sin SQL manual y sin borrado fisico. La
--       Decision de Oro del dueno: un producto ficticio NO se edita para
--       volverlo real (seria "cambiarle el nombre dejandole la cedula/UUID de
--       otro"); lo correcto es RETIRAR el placeholder y crear uno nuevo. Retirar
--       = baja LOGICA coherente con el resto del ecosistema (nada se borra en
--       silencio): pone publicado=false (sale de catalogo_publico, como
--       cm_publicar_campana) y activo=false (baja logica), marca actualizado.
--       Ademas, si la campana esta ligada a un producto de Inventario que TAMBIEN
--       es placeholder (es_placeholder=true en productos), lo da de baja logica
--       (activo=false) para que el ejemplo no quede colgando en el desplegable de
--       Inventario; si el producto ligado es REAL (es_placeholder=false) NO se
--       toca (podria ser un producto de verdad que alguien reutilice). SOLO opera
--       sobre campanas con es_placeholder=true: retirar algo que NO es ejemplo
--       es un error explicito (proteccion contra retirar un producto real por
--       accidente). security definer + tiene_acceso_marketing(), como el resto de
--       las cm_*.
--
-- IDEMPOTENTE: drop function if exists + create; la RPC de retiro es segura de
-- re-ejecutar (poner publicado/activo=false sobre algo ya retirado no rompe
-- nada). Se puede re-ejecutar el archivo entero.
-- REQUISITO: correr DESPUES de 20250503000000_campanas_incision_inventario.sql
-- (de alli sale la firma VIVA con p_product_id_ref que este archivo reemplaza).
-- NOTA: la RPC valida tiene_acceso_marketing()/auth.uid(); en el SQL Editor
-- auth.uid() es NULL, asi que NO la llames como seed desde el editor (solo se
-- ejecuta bien desde el panel, con la sesion del usuario). Definir la funcion
-- aqui NO la ejecuta, asi que aplicar la migracion es seguro.
-- ============================================================

-- ------------------------------------------------------------
-- (0) cm_normalizar_slug: helper de normalizacion de slug (mismo criterio que
-- la autosugerencia del panel). minusculas + trim -> quitar acentos/enie ->
-- reemplazar lo no [a-z0-9] por guion -> colapsar guiones -> recortar de los
-- extremos. Devuelve NULL si queda vacio (para no chocar con el indice unico
-- parcial campana_producto_slug_key, que solo cuenta filas con slug NOT NULL).
-- Se define ANTES de que crear/editar la llamen.
-- ------------------------------------------------------------
create or replace function cm_normalizar_slug(p_texto text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text;
begin
  v := lower(trim(coalesce(p_texto, '')));
  v := translate(v,
                 'áàäâãéèëêíìïîóòöôõúùüûñç',
                 'aaaaaeeeeiiiiooooouuuunc');
  v := regexp_replace(v, '[^a-z0-9]+', '-', 'g');
  v := regexp_replace(v, '-+', '-', 'g');
  v := trim(both '-' from v);
  if v is null or length(v) = 0 then
    return null;
  end if;
  return v;
end;
$$;

comment on function cm_normalizar_slug(text) is 'CAMPANAS · normaliza un texto a un slug de URL estable: minusculas, sin acentos/enie, lo no [a-z0-9] -> guion, colapsa y recorta guiones. Devuelve NULL si queda vacio (para no chocar con el indice unico parcial de campana_producto.slug). La usan cm_crear_campana / cm_editar_campana para limpiar p_slug en el servidor (espejo de la autosugerencia del panel).';

-- ------------------------------------------------------------
-- (1) EXTENDER las RPC de Campanas con p_slug (al final de la firma).
--
-- DROP de la firma VIVA ACTUAL (la de 20250503000000, con p_product_id_ref uuid
-- al final) + CREATE con la firma NUEVA (con p_slug text al final). if exists:
-- idempotente. Las listas de tipos del drop son EXACTAS a la firma viva.
-- ------------------------------------------------------------
drop function if exists cm_crear_campana(
  text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid
);

-- ------------------------------------------------------------
-- cm_crear_campana (firma NUEVA): igual que la incision + p_slug text al final.
-- Persiste slug (normalizado; vacio -> NULL) en el INSERT.
-- ------------------------------------------------------------
create function cm_crear_campana(
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
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,  -- enlace a productos(id) (incision)
  p_slug                    text default null   -- NUEVO: direccion web legible (URL)
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
  -- Aviso de urgencia MANUAL y HONESTO: si esta activo, exige un numero > 0.
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;

  -- Normaliza el slug (minusculas, sin acentos/enie, espacios -> guion, quitar
  -- simbolos, colapsar/recortar guiones). Vacio despues de normalizar -> NULL
  -- (opcional; NULL no choca con el indice unico parcial campana_producto_slug_key).
  v_slug := cm_normalizar_slug(p_slug);

  insert into campana_producto (
    nombre, categoria_codigo, detalle_presentacion, hook_corto, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref, slug
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_hook_corto, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false),
    p_aviso_urgencia_cantidad, p_product_id_ref, v_slug
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

comment on function cm_crear_campana(text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text) is 'CAMPANAS · alta de un producto vestido y asignacion de sus etiquetas de segmentacion (tabla puente). Tanda 2 (incision): acepta p_product_id_ref (uuid, default null) para LIGAR la campana a un producto de Inventario. C1: acepta p_slug (text, ULTIMO parametro, default null) = direccion web legible para la URL de la tienda; se NORMALIZA en el servidor (minusculas, sin acentos/enie, espacios->guion, sin simbolos) y un slug vacio despues de normalizar se guarda como NULL (no choca con el indice unico parcial). Valida tiene_acceso_marketing(), nombre obligatorio, precio_venta >= 0 (bigint) y, si aviso_urgencia_activo=true, cantidad > 0. Devuelve jsonb {id}.';

-- ------------------------------------------------------------
-- cm_editar_campana (firma NUEVA): igual que la incision + p_slug text al final.
-- Persiste slug (normalizado; vacio -> NULL) en el UPDATE.
-- ------------------------------------------------------------
create function cm_editar_campana(
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
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,  -- enlace a productos(id) (incision)
  p_slug                    text default null   -- NUEVO: direccion web legible (URL)
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

  select id into v_existe from campana_producto where id = p_id;
  if v_existe is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  v_slug := cm_normalizar_slug(p_slug);

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
         product_id_ref           = p_product_id_ref,
         slug                     = v_slug,
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text) is 'CAMPANAS · edita la ficha del producto vestido y REEMPLAZA en bloque sus etiquetas de segmentacion (no toca el catalogo de etiquetas). Tanda 2 (incision): acepta p_product_id_ref (uuid, default null) para re-ligar o cambiar el producto de Inventario. C1: acepta p_slug (text, ULTIMO parametro, default null) = direccion web legible; se NORMALIZA en el servidor y vacio->NULL (no choca con el indice unico parcial). Marca actualizado=now(). NUNCA borra el producto. No cambia publicado (eso es cm_publicar_campana). Mismas validaciones que cm_crear_campana (nombre, precio >= 0, aviso con cantidad > 0). Devuelve el id.';

-- ------------------------------------------------------------
-- (2) cm_retirar_placeholder: RETIRA de la tienda un producto de EJEMPLO
--     (es_placeholder=true) sin borrado fisico. Baja logica: publicado=false
--     (sale de catalogo_publico) + activo=false. Si esta ligado a un producto
--     de Inventario que TAMBIEN es placeholder, ese producto se da de baja
--     logica tambien; si el ligado es REAL, NO se toca. SOLO opera sobre
--     campanas con es_placeholder=true (retirar algo real es un error explicito).
-- ------------------------------------------------------------
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
  v_product_id     uuid;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select es_placeholder, product_id_ref
    into v_es_placeholder, v_product_id
    from campana_producto
   where id = p_id;

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

  -- Si el producto de Inventario ligado TAMBIEN es un ejemplo, se da de baja
  -- logica (para que no quede colgando en el desplegable). Un producto REAL
  -- ligado NO se toca (podria reutilizarse).
  if v_product_id is not null then
    update productos
       set activo = false
     where id = v_product_id
       and es_placeholder = true;
  end if;

  return p_id;
end;
$$;

comment on function cm_retirar_placeholder(uuid) is 'CAMPANAS · RETIRA un producto de EJEMPLO (es_placeholder=true) desde el panel, sin SQL manual y sin borrado fisico (Decision de Oro del dueno: un ficticio NO se edita para volverlo real; se RETIRA y se crea uno nuevo). Baja LOGICA: pone publicado=false (sale de catalogo_publico) y activo=false; marca actualizado. Si el producto de Inventario ligado (product_id_ref) TAMBIEN es placeholder, lo da de baja logica (activo=false); si es REAL, NO lo toca. SOLO opera sobre campanas con es_placeholder=true (retirar un producto real es un error explicito). Valida tiene_acceso_marketing(). NUNCA delete. Devuelve el id.';
