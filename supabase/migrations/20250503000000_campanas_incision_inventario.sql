-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Tanda 2: LA INCISION
-- Conectar Campanas con Inventario (el enchufe se enciende de verdad)
-- ------------------------------------------------------------
-- QUE ES ESTA MIGRACION (Campanas fase 1, Tanda 2, CONECTANDO Inventario):
-- hasta hoy Campanas era una ISLA (ver 20250501000000 y 20250502000000):
-- product_id_ref era uuid NULL SIN FK ("enchufe apagado") y la tienda usaba el
-- numero MANUAL stock_disponible. Ahora que el Area de Campanas esta aprobada,
-- se hace la INCISION: se conectan las tuberias que estaban debajo del tapete.
--
-- LA FILOSOFIA (cita a ciegas del ecosistema Impulse): el candado real vive en
-- los DATOS (RLS + RPC security definer + vista segura), no en el HTML; nada se
-- borra (baja logica); montos en bigint; el stock NUNCA es un dato guardado, se
-- DERIVA del libro de movimientos (vista stock_actual). La tienda solo ve campos
-- publicos: JAMAS costo, proveedor, stock exacto, product_id_ref ni es_placeholder.
--
-- QUE HACE, EN ORDEN:
--
--   (a) FLAG INTERNO productos.es_placeholder (boolean not null default false).
--       Espejo del es_placeholder de campana_producto (20250502000000): marca
--       los productos FICTICIOS de ejemplo sembrados desde Campanas para poder
--       distinguirlos y RETIRARLOS luego sin manchar Inventario. NUNCA se expone
--       al publico (no entra en catalogo_publico ni en ninguna vista publica).
--       Se llama IGUAL que en campana_producto por coherencia del ecosistema:
--       un mismo concepto ("ficticio, no lo herede el sistema") con un mismo
--       nombre en las dos tablas que lo necesitan.
--
--   (b) SIEMBRA de los 5 productos de Campanas en `productos` (Inventario) con
--       stock 0 y CERO movimientos. Se usa inv_crear_producto con
--       p_cantidad_inicial => 0, que NO inserta fila en movimientos_inventario
--       (ver 20250301000400): asi el producto EXISTE en Inventario pero NO hay
--       unidades ni compra registrada -> Contabilidad no se toca. Es
--       exactamente lo que pidio el dueno: "que existan en la tienda mas NO que
--       hay unidades o que compramos". Cuando el dueno cargue unidades reales
--       (una 'entrada' por inv_registrar_movimiento) el stock subira solo y el
--       booleano `agotado` de la vista se apagara solo.
--
--   (c) ENCENDER la FK real campana_producto.product_id_ref -> productos(id) con
--       guard idempotente sobre pg_constraint (patron EXACTO de
--       20250401000300_ventas_rls.sql, la FK de movimientos_inventario.customer_id).
--       Hoy esa columna esta NULL en produccion (enchufe apagado), asi que ligar
--       es barato: no exige migrar ni reconciliar datos viejos.
--
--   (d) LIGAR los 5 seeds de Campanas (ids ...0c0001..0c0005) a sus 5 productos
--       de Inventario recien creados, guardando el id devuelto por
--       inv_crear_producto en campana_producto.product_id_ref.
--
--   (e) REDEFINIR la vista `catalogo_publico`: se QUITA stock_disponible (numero
--       manual) de la lista blanca y se AGREGA un booleano derivado `agotado`
--       leido del stock REAL (stock_actual.existencias <= 0 via product_id_ref),
--       SIN exponer nunca el numero exacto. DROP VIEW + CREATE VIEW + re-grant a
--       anon,authenticated (NUNCA create or replace: Postgres 42P16 al reordenar
--       columnas; ver 20250502000000). DECISION de criterio: si product_id_ref
--       es null (producto de campana AUN no ligado a Inventario) agotado = false
--       (no marcar agotado a algo sin inventario conectado, para no romper el
--       catalogo del dueno mientras migra).
--
--   (f) EXTENDER las RPC cm_crear_campana / cm_editar_campana con el parametro
--       nuevo p_product_id_ref uuid default null AL FINAL de la firma (para no
--       romper el orden de los parametros existentes). Como agregar un parametro
--       cambia la LISTA DE TIPOS y create or replace crearia una SOBRECARGA (dos
--       funciones con el mismo nombre), se hace drop function if exists de la
--       firma VIEJA + create con la firma NUEVA. NO se edita 20250501000500: las
--       dos RPC se recrean aqui, asi el orden de aplicacion es lineal y el dueno
--       solo corre este archivo nuevo.
--
-- IDEMPOTENTE en TODO: add column if not exists, siembra con guard (salta si el
-- campana_producto ya tiene product_id_ref no nulo), guard sobre pg_constraint
-- para la FK, drop view if exists + create view, drop function if exists +
-- create function. Se puede re-ejecutar el archivo entero sin duplicar nada.
--
-- REQUISITO: correr DESPUES de TODAS las migraciones 202503* (Inventario:
-- productos, movimientos, stock_actual, inv_crear_producto), 202505* (Campanas:
-- tablas, RPC y seed) y de 20250502000000 (es_placeholder/slug + vista con slug).
-- NOTA sobre inv_crear_producto: exige tiene_acceso_inventario(). El dueno la
-- corre desde el SQL Editor (service_role salta RLS pero la validacion interna
-- de la RPC se satisface porque tiene_modulo resuelve admin); ver INSTRUCCIONES.
-- ============================================================

-- ------------------------------------------------------------
-- (a) FLAG INTERNO es_placeholder en productos (Inventario).
-- ------------------------------------------------------------
alter table productos
  add column if not exists es_placeholder boolean not null default false;

comment on column productos.es_placeholder is 'Flag INTERNO (NUNCA se expone en catalogo_publico ni en ninguna vista publica): marca los productos FICTICIOS sembrados desde Campanas para arrancar la tienda. Espejo del es_placeholder de campana_producto (coherencia del ecosistema). true = ficticio (el dueno lo RETIRA y crea productos reales, para no heredar su identidad/UUID); false = real (el Grisi). Uso interno del panel de Inventario/Campanas para distinguir y limpiar los ejemplos sin manchar el sistema.';

-- ------------------------------------------------------------
-- (c) ENCENDER LA FK DEL ENCHUFE: campana_producto.product_id_ref -> productos(id).
-- La columna existe desde 20250501000000 como uuid NULL SIN FK ("enchufe
-- apagado"). Se le agrega la FK ahora. Guard idempotente: solo se agrega si no
-- existe ya en pg_constraint, para no fallar al re-ejecutar (patron EXACTO de
-- movimientos_inventario_customer_id_fkey en 20250401000300_ventas_rls.sql).
-- La columna esta NULL en produccion (Campanas era isla), asi que la FK no
-- exige migrar datos y su costo es minimo. Se enciende ANTES de ligar (paso d)
-- para que los updates de enlace ya viajen validados por la FK.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_producto_product_id_ref_fkey'
       and conrelid = 'campana_producto'::regclass
  ) then
    alter table campana_producto
      add constraint campana_producto_product_id_ref_fkey
      foreign key (product_id_ref) references productos(id);
  end if;
end
$$;

-- ------------------------------------------------------------
-- (b) SIEMBRA de los 5 productos en `productos` con stock 0 y CERO movimientos,
--     y (d) LIGADO de los 5 seeds de Campanas a esos productos.
--
-- Un solo bloque DO/plpgsql que, para cada uno de los 5, si el campana_producto
-- correspondiente AUN no tiene product_id_ref (enchufe apagado), llama
-- inv_crear_producto con p_cantidad_inicial => 0 (NO toca el libro) y guarda el
-- id devuelto en campana_producto.product_id_ref. Si ya tiene product_id_ref
-- (re-ejecucion), SALTA la creacion: asi es idempotente y no crea productos
-- duplicados en Inventario cada vez que corre.
--
-- Nombres/precios EXACTOS del seed 20250501000700. Grisi es real
-- (es_placeholder=false); los otros 4 son ejemplos (es_placeholder=true). La
-- categoria que se pasa a inv_crear_producto es el codigo de categoria de
-- Campanas (cabello/belleza_fem/belleza_masc/hogar/alimentos); la RPC solo la
-- usa para el tramo <CAT> del SKU (mayusculas, sin acentos, 3-4 chars).
-- precio_venta en bigint (pesos enteros). NO se pasa costo ni cantidad: cero
-- movimiento, cero contabilidad.
-- ------------------------------------------------------------
do $$
declare
  v_res         jsonb;
  v_id_producto uuid;
begin
  -- (1) Shampoo Manzanilla GRISI Gold · cabello · 24900 · REAL (es_placeholder=false)
  if exists (
    select 1 from campana_producto
     where id = '00000000-0000-0000-0000-0000000c0001'
       and product_id_ref is null
  ) then
    v_res := inv_crear_producto(
      p_nombre           => 'Shampoo Manzanilla GRISI Gold',
      p_categoria        => 'cabello',
      p_precio_venta     => 24900::bigint,
      p_cantidad_inicial => 0            -- CERO: no inserta en movimientos_inventario
    );
    v_id_producto := (v_res->>'id')::uuid;
    update productos set es_placeholder = false where id = v_id_producto;  -- Grisi = real
    update campana_producto set product_id_ref = v_id_producto
     where id = '00000000-0000-0000-0000-0000000c0001';
  end if;

  -- (2) Serum Facial de Rosa Mosqueta · belleza_fem · 32900 · EJEMPLO (es_placeholder=true)
  if exists (
    select 1 from campana_producto
     where id = '00000000-0000-0000-0000-0000000c0002'
       and product_id_ref is null
  ) then
    v_res := inv_crear_producto(
      p_nombre           => 'Serum Facial de Rosa Mosqueta',
      p_categoria        => 'belleza_fem',
      p_precio_venta     => 32900::bigint,
      p_cantidad_inicial => 0
    );
    v_id_producto := (v_res->>'id')::uuid;
    update productos set es_placeholder = true where id = v_id_producto;   -- ejemplo = ficticio
    update campana_producto set product_id_ref = v_id_producto
     where id = '00000000-0000-0000-0000-0000000c0002';
  end if;

  -- (3) Balsamo para Barba de Cedro · belleza_masc · 28500 · EJEMPLO
  if exists (
    select 1 from campana_producto
     where id = '00000000-0000-0000-0000-0000000c0003'
       and product_id_ref is null
  ) then
    v_res := inv_crear_producto(
      p_nombre           => 'Balsamo para Barba de Cedro',
      p_categoria        => 'belleza_masc',
      p_precio_venta     => 28500::bigint,
      p_cantidad_inicial => 0
    );
    v_id_producto := (v_res->>'id')::uuid;
    update productos set es_placeholder = true where id = v_id_producto;
    update campana_producto set product_id_ref = v_id_producto
     where id = '00000000-0000-0000-0000-0000000c0003';
  end if;

  -- (4) Jabon de Coco para el Hogar · hogar · 15900 · EJEMPLO
  if exists (
    select 1 from campana_producto
     where id = '00000000-0000-0000-0000-0000000c0004'
       and product_id_ref is null
  ) then
    v_res := inv_crear_producto(
      p_nombre           => 'Jabon de Coco para el Hogar',
      p_categoria        => 'hogar',
      p_precio_venta     => 15900::bigint,
      p_cantidad_inicial => 0
    );
    v_id_producto := (v_res->>'id')::uuid;
    update productos set es_placeholder = true where id = v_id_producto;
    update campana_producto set product_id_ref = v_id_producto
     where id = '00000000-0000-0000-0000-0000000c0004';
  end if;

  -- (5) Miel de Cafe Artesanal · alimentos · 21000 · EJEMPLO
  if exists (
    select 1 from campana_producto
     where id = '00000000-0000-0000-0000-0000000c0005'
       and product_id_ref is null
  ) then
    v_res := inv_crear_producto(
      p_nombre           => 'Miel de Cafe Artesanal',
      p_categoria        => 'alimentos',
      p_precio_venta     => 21000::bigint,
      p_cantidad_inicial => 0
    );
    v_id_producto := (v_res->>'id')::uuid;
    update productos set es_placeholder = true where id = v_id_producto;
    update campana_producto set product_id_ref = v_id_producto
     where id = '00000000-0000-0000-0000-0000000c0005';
  end if;
end
$$;

-- ------------------------------------------------------------
-- (e) REDEFINIR la vista publica: quitar stock_disponible (numero manual) y
--     agregar el booleano derivado `agotado` (del stock REAL de Inventario).
--
-- Se usa DROP + CREATE (no create or replace) porque cambiamos la LISTA de
-- columnas de la vista (Postgres 42P16 al reordenar/quitar columnas; ver
-- 20250502000000). El grant a anon/authenticated se re-otorga abajo (el DROP se
-- lo lleva).
--
-- `agotado` se calcula con un left join a stock_actual por
-- cp.product_id_ref = sa.product_id:
--   - Si product_id_ref es NULL (campana aun no ligada a Inventario): false.
--     DECISION de criterio (documentada): no marcar agotado a algo sin
--     inventario conectado; asi el catalogo del dueno no se rompe mientras migra.
--   - Si product_id_ref no es null: coalesce(sa.existencias, 0) <= 0 as agotado.
--     existencias es el stock REAL derivado del libro; cuando el dueno registre
--     una 'entrada' el numero sube y agotado pasa a false SOLO.
--
-- LINEA ROJA: la vista NUNCA expone sa.existencias (el numero exacto), ni
-- product_id_ref, ni es_placeholder, ni stock_disponible. Solo el booleano
-- derivado `agotado`. El aviso "Solo X disponibles" de la tienda sigue siendo
-- el numero MANUAL aviso_urgencia_cantidad, no el stock real.
--
-- SEGURIDAD del join a stock_actual: stock_actual es SECURITY INVOKER y hereda
-- la RLS de productos/movimientos_inventario (tiene_acceso_inventario). Pero
-- catalogo_publico es, por defecto, una vista SECURITY DEFINER (corre con los
-- privilegios de su DUENO), asi que el left join a stock_actual se resuelve con
-- los privilegios del dueno de la vista y NO con los del rol anon. Resultado:
-- anon obtiene solo el booleano derivado `agotado` y NUNCA puede leer
-- stock_actual directo ni el numero de existencias (ver verificacion (iv) en
-- INSTRUCCIONES). La lista blanca de columnas es el segundo candado.
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
  -- Booleano derivado del stock REAL. Reemplaza a stock_disponible (manual).
  -- Sin inventario ligado -> false (no agotamos algo que aun no se conecta).
  case
    when cp.product_id_ref is null then false
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

comment on view catalogo_publico is 'CAMPANAS · vista publica SEGURA que lee la tienda (magandhi.com) sin login. SOLO expone productos con publicado=true y activo=true, y SOLO campos publicos (nombre, slug para la URL, categoria + colores, presentacion, hooks, precio_venta, textos, ficha, imagenes, sello, estrella, aviso de urgencia). Tanda 2 (la incision): en lugar de stock_disponible (numero manual) expone el booleano derivado `agotado`, leido del stock REAL de Inventario (stock_actual.existencias <= 0 via product_id_ref). Si product_id_ref es null (aun no ligado a Inventario), agotado=false. JAMAS expone el numero exacto de existencias, ni product_id_ref, ni es_placeholder, ni stock_disponible, ni costo/proveedor/creado_por, ni las etiquetas de segmentacion. El candado es doble: tablas base sin grant/policy para anon + la vista solo trae filas publicadas y columnas publicas; el join a stock_actual se resuelve con los privilegios del dueno de la vista (security definer), asi anon obtiene solo el booleano y nunca el stock. Grant select a anon: se re-otorga tras el DROP.';

-- RE-OTORGAR el grant: el DROP VIEW de arriba se lleva el grant que le habian
-- dado a la vista (20250501000600 / 20250502000000), asi que hay que volver a
-- concederlo o la tienda (anon) y el panel (authenticated) perderian la lectura.
grant select on catalogo_publico to anon, authenticated;

-- ------------------------------------------------------------
-- (f) EXTENDER las RPC de Campanas con p_product_id_ref (al final de la firma).
--
-- DROP de la firma VIEJA + CREATE con la firma NUEVA (no create or replace):
-- agregar un parametro cambia la lista de tipos de argumentos, asi que un
-- create or replace crearia una SOBRECARGA nueva y dejaria conviviendo la firma
-- vieja (dos funciones con el mismo nombre y distinto numero de argumentos).
-- El drop explicito de la firma vieja evita esa ambiguedad. Firmas viejas
-- tomadas EXACTAS de 20250501000500. Este archivo NO edita 20250501000500.
-- ------------------------------------------------------------

-- Quitar las firmas VIEJAS (sin p_product_id_ref). if exists: idempotente y no
-- falla si ya se recrearon en una corrida anterior.
drop function if exists cm_crear_campana(
  text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[]
);
drop function if exists cm_editar_campana(
  uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[]
);

-- ------------------------------------------------------------
-- cm_crear_campana (firma NUEVA): igual que antes + p_product_id_ref uuid al
-- final. Persiste product_id_ref en el INSERT. Asi, al crear una campana desde
-- el panel, el dueno elige del desplegable el producto de Inventario y queda
-- ligado de una vez (el stock real ya alimenta el `agotado` de la vista).
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
  p_product_id_ref          uuid default null   -- NUEVO: enlace a productos(id)
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
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_hook_corto, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false),
    p_aviso_urgencia_cantidad, p_product_id_ref
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

comment on function cm_crear_campana(text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid) is 'CAMPANAS · alta de un producto vestido y asignacion de sus etiquetas de segmentacion (tabla puente). Tanda 2: acepta p_product_id_ref (uuid, ultimo parametro, default null) para LIGAR la campana a un producto de Inventario (productos.id) y que su stock real alimente el booleano agotado de catalogo_publico. Valida tiene_acceso_marketing(), nombre obligatorio, precio_venta >= 0 (bigint) y, si aviso_urgencia_activo=true, cantidad > 0 (aviso REAL y manual). Devuelve jsonb {id}.';

-- ------------------------------------------------------------
-- cm_editar_campana (firma NUEVA): igual que antes + p_product_id_ref uuid al
-- final. Persiste product_id_ref en el UPDATE. Permite re-ligar o cambiar el
-- producto de Inventario asociado desde el panel de edicion.
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
  p_product_id_ref          uuid default null   -- NUEVO: enlace a productos(id)
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
         product_id_ref           = p_product_id_ref,
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

comment on function cm_editar_campana(uuid, text, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid) is 'CAMPANAS · edita la ficha del producto vestido y REEMPLAZA en bloque sus etiquetas de segmentacion (no toca el catalogo de etiquetas). Tanda 2: acepta p_product_id_ref (uuid, ultimo parametro, default null) y lo persiste en el UPDATE para re-ligar o cambiar el producto de Inventario asociado. Marca actualizado=now(). NUNCA borra el producto. No cambia publicado (eso es cm_publicar_campana). Mismas validaciones que cm_crear_campana (nombre, precio >= 0, aviso con cantidad > 0). Devuelve el id.';
