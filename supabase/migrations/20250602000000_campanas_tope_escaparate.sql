-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · TOPE DE ESCAPARATE
-- La "llave tras cortina": cuantas unidades se muestran como disponibles.
-- ------------------------------------------------------------
-- QUE ES ESTA MIGRACION (Campanas fase 1, tramo TOPE DE ESCAPARATE):
-- una capa nueva sobre la incision de Inventario (20250503000000: FK
-- product_id_ref + vista catalogo_publico con el booleano derivado `agotado`
-- leido del stock REAL) y sobre C1 (20250504000000: cm_crear_campana /
-- cm_editar_campana con p_slug al final). Agrega el TOPE DE ESCAPARATE: un
-- numero que el dueno decide TRAS CORTINA para cada campana ligada a Inventario.
--
-- QUE ES EL TOPE DE ESCAPARATE:
--   Es el maximo de unidades que la tienda esta dispuesta a EXHIBIR como
--   disponibles, aunque en Inventario haya mas. Sirve para reservar stock
--   (dejar unidades fuera de la vitrina) sin mostrarle numeros a la web.
--
-- LA REGLA CENTRAL (sellada por el dueno, OPCION A):
--     lo ofrecido = min(existencias_reales, tope)
--   El tope solo puede RESTAR exhibicion, NUNCA inventar unidades: si el tope
--   es mayor que las existencias reales, manda el inventario real (no se puede
--   ofrecer lo que no hay). "ofrecidas" es un valor INTERMEDIO de calculo que
--   NUNCA se expone al publico.
--
-- OPCION A (que gobierna hoy el tope, y que NO):
--   El tope SOLO afecta el booleano `agotado` de catalogo_publico. La web NO ve
--   numeros: ni existencias, ni el tope, ni lo ofrecido. Solo el booleano
--   `agotado`, manteniendo EXACTAMENTE la misma lista de columnas publicas que
--   ya expone la vista hoy.
--
-- CASOS (con la regla lo ofrecido = min(existencias, tope)):
--   - existencias 25 + tope 25 (o mayor) -> ofrecidas >= 1 -> agotado = false.
--   - existencias 0                       -> ofrecidas 0    -> agotado = true
--     (igual que hoy: sin stock real, agotado).
--   - tope null/vacio -> ofrecer TODO el stock real (comportamiento actual:
--     agotado = existencias <= 0).
--   - tope 0 -> ofrecidas 0 -> agotado = true AUNQUE haya stock real (el dueno
--     decide no exhibir ninguna unidad).
--   - product_id_ref null (campana aun no ligada a Inventario) -> agotado =
--     false (criterio actual: no agotar algo sin inventario conectado).
--
-- MATIZ HONESTO (importante, para no venderse una capacidad que hoy no existe):
--   Hoy la venta fase 1 es MANUAL: NO hay checkout ni carrito en la web. Por
--   eso, HOY el tope gobierna UNICAMENTE el ESCAPARATE: lo que la tienda muestra
--   como disponible o agotado. El candado REAL de venta -"que no se venda la
--   unidad 26"- llegara cuando se conecte la pasarela de pago (Wompi) en la
--   Fase F, donde el checkout consultara lo ofrecido antes de cobrar. Aqui NO
--   se implementa ningun bloqueo de venta porque NO existe todavia un checkout
--   que bloquear; se prepara el dato (el tope) y su efecto visible (el agotado).
--
-- LO QUE ESTA MIGRACION NO TOCA (a proposito):
--   - El aviso "Solo X disponibles" (aviso_urgencia_cantidad) sigue siendo un
--     numero MANUAL, HONESTO e INDEPENDIENTE del tope. No se toca su logica ni
--     su columna.
--   - precio_venta: no se borra ni se cambia.
--   - Las migraciones 20250503000000 y 20250504000000: NO se editan. Todo lo
--     nuevo vive en este archivo.
--
-- QUE HACE, EN ORDEN:
--   (a) COLUMNA campana_producto.tope_escaparate integer NULL, con check
--       idempotente (>= 0 cuando no es null) via guard sobre pg_constraint.
--   (b) REDEFINIR catalogo_publico (DROP VIEW + CREATE VIEW + re-grant) para que
--       `agotado` use least(existencias, tope) cuando el tope no es null,
--       manteniendo EXACTAMENTE la misma lista de columnas publicas de hoy.
--   (c) EXTENDER cm_crear_campana / cm_editar_campana con p_tope_escaparate
--       integer default null AL FINAL de la firma (drop de la firma VIVA de C1
--       + create), persistiendolo en el INSERT/UPDATE y validando null o >= 0.
--
-- IDEMPOTENTE en TODO: add column if not exists, guard sobre pg_constraint para
-- el check, drop view if exists + create view, drop function if exists + create
-- function. Se puede re-ejecutar el archivo entero sin duplicar nada.
-- REQUISITO: correr DESPUES de 20250504000000_campanas_slug_retirar_placeholder.sql
-- (de alli sale la firma VIVA de cm_crear_campana / cm_editar_campana -que
-- termina en ..., text[], uuid, text- que este archivo reemplaza) y, por
-- transitividad, DESPUES de 20250503000000 (vista catalogo_publico viva).
-- NOTA: las RPC validan tiene_acceso_marketing()/auth.uid(); en el SQL Editor
-- auth.uid() es NULL, asi que NO las llames como seed desde el editor. Definir
-- las funciones aqui NO las ejecuta, asi que aplicar la migracion es seguro.
-- ============================================================

-- ------------------------------------------------------------
-- (a) COLUMNA: campana_producto.tope_escaparate integer NULL + check >= 0.
--
-- integer (unidades enteras; los montos son bigint, pero el tope es un conteo
-- de unidades como stock_disponible). NULL = sin tope = ofrecer todo el stock
-- real. El check (via guard idempotente sobre pg_constraint, patron EXACTO del
-- guard de la FK en 20250503000000 seccion (c)) prohibe topes negativos pero
-- permite 0 (0 = no exhibir ninguna unidad, caso valido) y NULL (sin tope).
-- ------------------------------------------------------------
alter table campana_producto
  add column if not exists tope_escaparate integer null;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_producto_tope_escaparate_chk'
       and conrelid = 'campana_producto'::regclass
  ) then
    alter table campana_producto
      add constraint campana_producto_tope_escaparate_chk
      check (tope_escaparate is null or tope_escaparate >= 0);
  end if;
end
$$;

comment on column campana_producto.tope_escaparate is 'CAMPANAS · tope de exhibicion (unidades) que el dueno decide TRAS CORTINA. null = ofrecer todo el stock real; 0 = no exhibir ninguna unidad (agotado aunque haya stock). Regla: lo ofrecido = min(existencias_reales, tope); el tope solo puede RESTAR exhibicion, nunca inventar unidades (la vista usa least sobre el stock real). HOY solo gobierna el booleano agotado del escaparate (fase 1 sin checkout); el candado de venta real -que no se venda la unidad 26- llega con la pasarela Wompi (Fase F). NUNCA se expone en catalogo_publico.';

-- ------------------------------------------------------------
-- (b) VISTA: redefinir catalogo_publico para que `agotado` considere el tope.
--
-- DROP VIEW + CREATE VIEW + re-grant (NUNCA create or replace: Postgres 42P16 si
-- cambia la lista/orden de columnas; ver 20250502000000 / 20250503000000). La
-- LISTA DE COLUMNAS PUBLICAS ES IDENTICA a la definicion viva de 20250503000000
-- seccion (e), en el MISMO ORDEN. UNICO cambio: la expresion del booleano
-- `agotado`.
--
-- Nueva expresion de `agotado` (aplica la regla lo ofrecido = min(existencias,
-- tope)):
--   - product_id_ref null                 -> false (no agotar algo sin ligar).
--   - tope_escaparate NO null             -> least(coalesce(existencias,0),
--                                            tope_escaparate) <= 0.
--   - tope_escaparate null                -> coalesce(existencias,0) <= 0
--                                            (comportamiento actual, sin tope).
-- Aqui least(coalesce(sa.existencias,0), cp.tope_escaparate) es "ofrecidas":
-- un valor INTERMEDIO de calculo que se compara con 0 y que NUNCA se expone como
-- columna (LINEA ROJA). Casos: exist 25 + tope 25 -> least=25 -> false; exist 0
-- -> least=0 -> true; tope 0 -> least=0 -> true aunque haya stock; tope null ->
-- rama sin tope -> existencias<=0.
--
-- LINEA ROJA: la vista NO agrega `existencias`, `tope_escaparate` ni `ofrecidas`
-- a su lista de columnas; el tope solo vive DENTRO de la expresion CASE del
-- agotado. Se mantiene el modelo de seguridad del join a stock_actual identico
-- al actual (catalogo_publico es SECURITY DEFINER: el join a stock_actual se
-- resuelve con los privilegios del dueno de la vista, no con los de anon).
-- El grant a anon/authenticated se re-otorga abajo (el DROP se lo lleva).
-- ------------------------------------------------------------
drop view if exists catalogo_publico;
create view catalogo_publico as
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
  cp.hook_corto,
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
  -- Booleano derivado del stock REAL, ahora acotado por el tope de escaparate.
  -- Regla: lo ofrecido = min(existencias_reales, tope). least(...) es ese valor
  -- "ofrecidas" INTERMEDIO -> NUNCA se expone como columna (LINEA ROJA).
  --   - sin inventario ligado (product_id_ref null) -> false.
  --   - con tope (no null) -> least(existencias, tope) <= 0 (tope 0 -> agotado
  --     aunque haya stock; el tope solo RESTA exhibicion, nunca inventa unidades).
  --   - sin tope (null) -> existencias <= 0 (comportamiento actual).
  case
    when cp.product_id_ref is null then false
    when cp.tope_escaparate is not null
      then least(coalesce(sa.existencias, 0), cp.tope_escaparate) <= 0
    else coalesce(sa.existencias, 0) <= 0
  end as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
left join stock_actual sa on sa.product_id = cp.product_id_ref
where cp.publicado = true
  and cp.activo = true;

comment on view catalogo_publico is 'CAMPANAS · vista publica SEGURA que lee la tienda (magandhi.com) sin login. SOLO expone productos con publicado=true y activo=true, y SOLO campos publicos (nombre, slug para la URL, categoria + colores, presentacion, hooks, precio_venta, textos, ficha, imagenes, sello, estrella, aviso de urgencia). Expone el booleano derivado `agotado`, leido del stock REAL de Inventario (stock_actual via product_id_ref). TOPE DE ESCAPARATE (opcion A): `agotado` ahora tambien considera el tope -regla lo ofrecido = min(existencias, tope)-: con tope no null, agotado = least(existencias, tope) <= 0 (tope 0 => agotado aunque haya stock); con tope null, agotado = existencias <= 0 (como antes); sin product_id_ref, agotado = false. El numero de existencias, el tope y lo ofrecido siguen SIN exponerse: solo el booleano agotado. JAMAS expone existencias, tope_escaparate, ofrecidas, product_id_ref, es_placeholder, stock_disponible, costo/proveedor/creado_por, ni las etiquetas. El candado es doble: tablas base sin grant/policy para anon + la vista solo trae filas publicadas y columnas publicas; el join a stock_actual se resuelve con los privilegios del dueno de la vista (security definer). Grant select a anon: se re-otorga tras el DROP.';

-- RE-OTORGAR el grant: el DROP VIEW de arriba se lleva el grant que le habian
-- dado a la vista, asi que hay que volver a concederlo o la tienda (anon) y el
-- panel (authenticated) perderian la lectura.
grant select on catalogo_publico to anon, authenticated;

-- ------------------------------------------------------------
-- (c) EXTENDER las RPC de Campanas con p_tope_escaparate (al final de la firma).
--
-- DROP de la firma VIVA ACTUAL (la de C1 / 20250504000000, que termina en
-- ..., p_etiquetas text[], p_product_id_ref uuid, p_slug text) + CREATE con la
-- firma NUEVA (con p_tope_escaparate integer al final). No create or replace:
-- agregar un parametro cambia la lista de tipos y crearia una SOBRECARGA. Las
-- listas de tipos del drop son EXACTAS a la firma viva. Se copia el cuerpo
-- COMPLETO y ACTUAL de ambas funciones (validaciones, cm_normalizar_slug,
-- etiquetas, product_id_ref) SIN cambiarlo, y solo se agrega: la validacion del
-- tope (null o >= 0) y su persistencia en el INSERT/UPDATE.
-- ------------------------------------------------------------
drop function if exists cm_crear_campana(
  text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text
);

-- ------------------------------------------------------------
-- cm_crear_campana (firma NUEVA): igual que C1 + p_tope_escaparate integer al
-- final. Persiste tope_escaparate en el INSERT.
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
  p_slug                    text default null,  -- direccion web legible (URL) (C1)
  p_tope_escaparate         integer default null -- NUEVO: tope de escaparate (opcion A)
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
  -- Tope de escaparate: null (sin tope) o un entero >= 0 (0 = no exhibir).
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
  end if;

  -- Normaliza el slug (minusculas, sin acentos/enie, espacios -> guion, quitar
  -- simbolos, colapsar/recortar guiones). Vacio despues de normalizar -> NULL
  -- (opcional; NULL no choca con el indice unico parcial campana_producto_slug_key).
  v_slug := cm_normalizar_slug(p_slug);

  insert into campana_producto (
    nombre, categoria_codigo, detalle_presentacion, hook_corto, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref, slug,
    tope_escaparate
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_hook_corto, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false),
    p_aviso_urgencia_cantidad, p_product_id_ref, v_slug,
    p_tope_escaparate
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

comment on function cm_crear_campana(text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is 'CAMPANAS · alta de un producto vestido y asignacion de sus etiquetas de segmentacion (tabla puente). Tanda 2 (incision): acepta p_product_id_ref (uuid, default null) para LIGAR la campana a un producto de Inventario. C1: acepta p_slug (text, default null) = direccion web legible normalizada en el servidor (vacio -> NULL). TOPE DE ESCAPARATE: acepta p_tope_escaparate (integer, ULTIMO parametro, default null) = tope de exhibicion (opcion A): null = ofrecer todo el stock real, 0 = no exhibir. SOLO afecta el booleano agotado de catalogo_publico (regla lo ofrecido = min(existencias, tope)); el candado de venta real llega con Wompi (Fase F). Valida tiene_acceso_marketing(), nombre obligatorio, precio_venta >= 0 (bigint), aviso con cantidad > 0 y tope null o >= 0. Devuelve jsonb {id}.';

-- ------------------------------------------------------------
-- cm_editar_campana (firma NUEVA): igual que C1 + p_tope_escaparate integer al
-- final. Persiste tope_escaparate en el UPDATE.
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
  p_slug                    text default null,  -- direccion web legible (URL) (C1)
  p_tope_escaparate         integer default null -- NUEVO: tope de escaparate (opcion A)
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
  -- Tope de escaparate: null (sin tope) o un entero >= 0 (0 = no exhibir).
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
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
         tope_escaparate          = p_tope_escaparate,
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is 'CAMPANAS · edita la ficha del producto vestido y REEMPLAZA en bloque sus etiquetas de segmentacion (no toca el catalogo de etiquetas). Tanda 2 (incision): acepta p_product_id_ref (uuid, default null) para re-ligar o cambiar el producto de Inventario. C1: acepta p_slug (text, default null) = direccion web legible normalizada (vacio -> NULL). TOPE DE ESCAPARATE: acepta p_tope_escaparate (integer, ULTIMO parametro, default null) = tope de exhibicion (opcion A): null = ofrecer todo el stock real, 0 = no exhibir; SOLO afecta el booleano agotado de catalogo_publico (regla lo ofrecido = min(existencias, tope)); el candado de venta real llega con Wompi (Fase F). Lo persiste en el UPDATE. Marca actualizado=now(). NUNCA borra el producto. No cambia publicado (eso es cm_publicar_campana). Mismas validaciones que cm_crear_campana (nombre, precio >= 0, aviso con cantidad > 0, tope null o >= 0). Devuelve el id.';
