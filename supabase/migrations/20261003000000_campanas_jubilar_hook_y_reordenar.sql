-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS
-- JUBILAR hook_corto (A) + REORDENAR por arrastrar y soltar (B)
-- Fecha: 2026-10-03
-- ------------------------------------------------------------
-- QUE HACE ESTA MIGRACION (una sola, para no redefinir las mismas
-- funciones y la misma vista dos veces en el mismo ledger):
--
--   A) JUBILAR hook_corto del circuito de Campanas, SIN borrar nada en la
--      base. El campo "HOOK CORTO" deja de pedirse al crear/editar un
--      producto y deja de exponerse en la vitrina publica, para no generar
--      confusion. Concretamente:
--        - cm_crear_campana / cm_editar_campana se re-crean SIN el parametro
--          p_hook_corto (fuera del INSERT y del UPDATE).
--        - catalogo_publico se re-crea SIN la columna cp.hook_corto.
--      La columna campana_producto.hook_corto NO se borra (no hay drop
--      column): solo se deja de escribir y de exponer. Los datos viejos
--      quedan intactos por si algun dia se quieren consultar.
--
--   B) ORDEN editable desde el back-office por arrastrar y soltar. Se crea la
--      RPC atomica cm_reordenar_campanas(p_ids uuid[]) que reasigna
--      orden = 1..N en el ORDEN exacto del arreglo recibido (sin huecos). El
--      navegador nunca escribe la columna orden directamente: esta RPC es la
--      UNICA via de escritura del orden. La columna campana_producto.orden, su
--      indice y su exposicion en catalogo_publico YA EXISTEN y estan en
--      produccion; esta migracion NO los toca (no hay alter table ... orden).
--
-- POR QUE DROP + CREATE DE LAS RPC (NO create or replace):
--   quitar un parametro cambia la lista de tipos de la firma. Un
--   create or replace sobre una firma distinta crearia una SOBRECARGA nueva
--   dejando viva la vieja (con p_hook_corto); por eso se hace drop de la firma
--   VIVA EXACTA + create de la firma nueva. Las listas de tipos del drop son
--   EXACTAS a la firma viva (la de 20250602000000, terminada en
--   ..., text[], uuid, text, integer) o el drop no encontraria la funcion.
--
-- POR QUE DROP VIEW + CREATE VIEW + RE-GRANT DE LA VISTA (NO create or replace):
--   quitar la columna hook_corto cambia la lista/orden de columnas de la
--   vista; un create or replace en ese caso da error 42P16. Por eso se hace
--   drop view if exists + create view, copiando el cuerpo VIVO de
--   20261002000000 IDENTICO salvo la linea cp.hook_corto. El DROP VIEW se
--   lleva TODOS los grants de la vista, asi que al final se re-otorga
--   grant select a anon, authenticated, service_role (service_role es
--   obligatorio: la Edge Function crear-intencion-pago lee catalogo_publico
--   como service_role; ver 20250605000000, omitirlo rompe con 42501).
--
-- IDEMPOTENTE de punta a punta: drop function if exists + create function,
-- drop view if exists + create view. Se puede re-ejecutar el archivo entero
-- sin duplicar nada.
--
-- REQUISITO: correr DESPUES de 20261002000000_puesta_al_dia_seguridad_operativa.sql
-- (de alli sale el cuerpo VIVO de catalogo_publico que esta archivo preserva) y,
-- por transitividad, DESPUES de 20250602000000 (de alli salen las firmas VIVAS
-- de cm_crear_campana / cm_editar_campana que este archivo reemplaza).
--
-- NOTA: las RPC validan tiene_acceso_marketing(); en el SQL Editor auth.uid()
-- es NULL, asi que NO llames las funciones como seed desde el editor. Definir
-- las funciones aqui NO las ejecuta, asi que aplicar la migracion es seguro.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- (A.1) DROP de las firmas VIVAS EXACTAS de las dos RPC de Campanas.
-- Son las firmas de 20250602000000 (terminan en ..., text[], uuid, text,
-- integer). Las listas de tipos deben coincidir EXACTO o el drop no encuentra
-- la funcion.
-- ------------------------------------------------------------
drop function if exists cm_crear_campana(
  text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
);

-- ------------------------------------------------------------
-- (A.2) cm_crear_campana (firma NUEVA): identica a la viva pero SIN
-- p_hook_corto. hook_corto queda jubilado: fuera de la firma, fuera del
-- INSERT y fuera del VALUES. El resto del cuerpo (validaciones de nombre,
-- precio, aviso, tope; cm_normalizar_slug; etiquetas; product_id_ref) se copia
-- tal cual.
-- ------------------------------------------------------------
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
  p_product_id_ref          uuid default null,  -- enlace a productos(id) (incision)
  p_slug                    text default null,  -- direccion web legible (URL) (C1)
  p_tope_escaparate         integer default null -- tope de escaparate (opcion A)
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
    nombre, categoria_codigo, detalle_presentacion, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref, slug,
    tope_escaparate
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_imagen_banner_path,
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

comment on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is 'CAMPANAS · alta de un producto vestido y asignacion de sus etiquetas de segmentacion (tabla puente). JUBILAR hook_corto: esta firma ya NO acepta p_hook_corto (el campo "HOOK CORTO" quedo jubilado; la columna campana_producto.hook_corto NO se borra, solo se deja de escribir). Acepta p_product_id_ref (uuid, default null) para LIGAR la campana a un producto de Inventario, p_slug (text, default null) = direccion web legible normalizada en el servidor (vacio -> NULL), y p_tope_escaparate (integer, ULTIMO parametro, default null) = tope de exhibicion (opcion A): null = ofrecer todo el stock real, 0 = no exhibir; SOLO afecta el booleano agotado de catalogo_publico. Valida tiene_acceso_marketing(), nombre obligatorio, precio_venta >= 0 (bigint), aviso con cantidad > 0 y tope null o >= 0. Devuelve jsonb {id}.';

-- ------------------------------------------------------------
-- (A.3) cm_editar_campana (firma NUEVA): identica a la viva pero SIN
-- p_hook_corto. hook_corto queda jubilado: fuera de la firma y fuera del
-- UPDATE. El resto del cuerpo se copia tal cual.
-- ------------------------------------------------------------
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
  p_product_id_ref          uuid default null,  -- enlace a productos(id) (incision)
  p_slug                    text default null,  -- direccion web legible (URL) (C1)
  p_tope_escaparate         integer default null -- tope de escaparate (opcion A)
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is 'CAMPANAS · edita la ficha del producto vestido y REEMPLAZA en bloque sus etiquetas de segmentacion (no toca el catalogo de etiquetas). JUBILAR hook_corto: esta firma ya NO acepta p_hook_corto y el UPDATE ya no escribe hook_corto (el campo quedo jubilado; la columna campana_producto.hook_corto NO se borra). Acepta p_product_id_ref (uuid, default null) para re-ligar o cambiar el producto de Inventario, p_slug (text, default null) = direccion web legible normalizada (vacio -> NULL), y p_tope_escaparate (integer, ULTIMO parametro, default null) = tope de exhibicion (opcion A). Marca actualizado=now(). NUNCA borra el producto. No cambia publicado (eso es cm_publicar_campana). Mismas validaciones que cm_crear_campana (nombre, precio >= 0, aviso con cantidad > 0, tope null o >= 0). Devuelve el id.';

-- ------------------------------------------------------------
-- (A.4) VISTA catalogo_publico: redefinir SIN la columna hook_corto.
--
-- Se copia el cuerpo VIVO de 20261002000000 IDENTICO (misma subconsulta a
-- movimientos_inventario para 'existencias', mismo CASE del agotado con
-- product_id_ref/tope_escaparate, mismo WHERE publicado=true and activo=true,
-- mismo orden del resto de columnas), QUITANDO unicamente la linea
-- cp.hook_corto. Como la lista de columnas cambia, se usa drop view if exists +
-- create view (NO create or replace: daria 42P16).
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
  case
    when cp.product_id_ref is null then true
    when cp.tope_escaparate is not null
      then least(coalesce(ex.existencias, 0), cp.tope_escaparate) <= 0
    else coalesce(ex.existencias, 0) <= 0
  end as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
left join (
  select
    m.product_id,
    sum(
      case m.tipo
        when 'entrada'        then  m.cantidad
        when 'ajuste_entrada' then  m.cantidad
        when 'salida'         then -m.cantidad
        when 'ajuste_salida'  then -m.cantidad
      end
    )::integer as existencias
  from movimientos_inventario m
  group by m.product_id
) ex on ex.product_id = cp.product_id_ref
where cp.publicado = true
  and cp.activo = true;

comment on view catalogo_publico is 'CAMPANAS · superficie publica de lista blanca para magandhi.com. Solo filas publicado=true y activo=true. JUBILAR hook_corto: esta vista ya NO expone la columna hook_corto (el campo quedo jubilado; la columna base NO se borra). agotado se deriva del libro movimientos_inventario; una campana sin product_id_ref se considera agotada/no comprable. Nunca expone existencias, tope, product_id_ref, placeholders, costos, proveedor ni etiquetas.';

-- ------------------------------------------------------------
-- (A.5) RE-OTORGAR el grant: el DROP VIEW de arriba se lleva TODOS los grants
-- de la vista. service_role es OBLIGATORIO: la Edge Function
-- crear-intencion-pago lee catalogo_publico como service_role (ver
-- 20250605000000); omitirlo la rompe con 42501. anon = tienda publica,
-- authenticated = back-office.
-- ------------------------------------------------------------
grant select on catalogo_publico to anon, authenticated, service_role;

-- ------------------------------------------------------------
-- (B.1) RPC nueva cm_reordenar_campanas(p_ids uuid[]): reasigna orden = 1..N
-- en el ORDEN del arreglo recibido (sin huecos). Es la UNICA via de escritura
-- de la columna orden; el navegador nunca hace update directo. Atomica: todo
-- ocurre dentro de la misma transaccion de la funcion, asi que un fallo deja el
-- orden intacto. Garantiza posiciones validas 1..N: la posicion de cada id es
-- su indice en el arreglo, no un numero libre tecleado por el usuario.
-- ------------------------------------------------------------
create or replace function cm_reordenar_campanas(
  p_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  i integer;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_ids is null then
    raise exception 'La lista de ids a reordenar es obligatoria.';
  end if;

  -- Reasigna secuencialmente orden = 1..N siguiendo el orden del arreglo. Al
  -- recorrer por indice no quedan huecos ni se puede saltar a un numero fuera
  -- de rango (la "posicion 50" con 7 productos es imposible: solo hay indices
  -- 1..array_length).
  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update campana_producto
       set orden       = i,
           actualizado = now()
     where id = p_ids[i];
  end loop;
end;
$$;

comment on function cm_reordenar_campanas(uuid[]) is 'CAMPANAS · reasigna de forma ATOMICA el orden del grid del home (campana_producto.orden) a 1..N siguiendo el ORDEN exacto del arreglo p_ids (sin huecos). Es la UNICA via de escritura del orden: el navegador NUNCA hace update directo de la columna orden, solo llama esta RPC (herramienta de arrastrar y soltar del back-office). El numero NO se muestra en la web; solo controla el orden de aparicion (el home ordena con order(orden, asc)). Valida tiene_acceso_marketing(). (B.2) NO se otorga grant execute explicito: en este proyecto las funciones conceden EXECUTE a PUBLIC por defecto y ninguna migracion de Campanas lo revoca (ver 20250501000600_campanas_grants.sql), igual que las demas cm_*. El candado real es tiene_acceso_marketing() dentro de la funcion.';

commit;
