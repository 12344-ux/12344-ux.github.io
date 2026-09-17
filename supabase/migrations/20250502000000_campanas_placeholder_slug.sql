-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Tanda 1: es_placeholder + slug,
-- vista publica con slug y RPC de etiquetas (cm_crear_etiqueta / cm_editar_etiqueta)
-- ------------------------------------------------------------
-- QUE ES ESTA MIGRACION (Campanas fase 1, Tanda 1, SIN conectar Inventario):
-- una capa nueva sobre el cimiento de Campanas (20250501000000..000700) que:
--
--   (1) FLAG INTERNO es_placeholder en campana_producto. Los 4 productos de
--       EJEMPLO que sembramos para arrancar el home (Serum de Rosa Mosqueta,
--       Balsamo de Barba de Cedro, Jabon de Coco para el Hogar, Miel de Cafe
--       Artesanal, ids ...0c0002..0c0005) NO son productos reales. La decision
--       del dueno es NO editarlos para volverlos reales: se RETIRAN y se crean
--       productos NUEVOS cuando lleguen los reales, para no heredar su
--       identidad/UUID. Este flag los marca como "ficticios" para que no
--       manchen el sistema (el panel podra distinguirlos y ocultarlos). El
--       Grisi (id ...0c0001) es REAL, queda es_placeholder=false. El flag es
--       INTERNO: NUNCA se expone en la tienda (no entra en catalogo_publico).
--
--   (2) SLUG PUBLICO en campana_producto. Clave publica legible para la URL de
--       la tienda (magandhi.com/producto/?slug=...), alternativa amable al id
--       uuid. Es opcional (text NULL) y unico cuando no es null (indice unico
--       parcial). A diferencia de es_placeholder, el slug SI es publico y SI
--       entra en la vista (la tienda lo necesita para armar la URL).
--
--   (3) Redefine la vista SEGURA catalogo_publico agregando SOLO la columna
--       slug a la lista blanca (justo despues de nombre). La LINEA ROJA sigue
--       intacta: NO se agrega es_placeholder ni ninguna otra columna interna;
--       se conserva EXACTO el WHERE publicado=true AND activo=true y el resto
--       de columnas publicas.
--
--   (4) RPC security definer cm_crear_etiqueta / cm_editar_etiqueta para que el
--       dueno AMPLIE y mantenga el catalogo de etiquetas de segmentacion
--       (campana_etiqueta) desde el panel, como amplia el PUC con
--       agregar_cuenta_puc. Patron identico: validan tiene_acceso_marketing()
--       al entrar, security definer, set search_path=public. Nada se borra: una
--       etiqueta se DESACTIVA (activo=false), nunca se elimina, para no romper
--       asignaciones historicas del puente campana_producto_etiqueta.
--
-- SOBRE GRANT / EXECUTE (decision, no hace falta tocar 20250501000600):
--   - No se agregan columnas nuevas de tabla que requieran GRANT: campana_producto
--     ya tiene `grant select ... to authenticated`, y ese grant cubre las
--     columnas nuevas es_placeholder/slug (el grant es a nivel de tabla).
--   - La vista catalogo_publico se REDEFINE con create or replace view; su grant
--     `select to anon, authenticated` (20250501000600) se conserva.
--   - Las funciones nuevas otorgan EXECUTE a PUBLIC por defecto al crearse y
--     ninguna migracion del repo hace revoke, asi que `authenticated` ya puede
--     ejecutarlas (mismo criterio que agregar_cuenta_puc y las cm_* existentes).
--     Por tanto NO se necesita ningun GRANT nuevo.
--
-- NO SE CONECTA INVENTARIO (Tanda 2 futura): product_id_ref sigue NULL SIN FK.
-- Esta migracion no crea ninguna FK a la tabla `productos` de Inventario.
--
-- IDEMPOTENTE: add column if not exists, create unique index if not exists,
-- UPDATE acotados por id (o slug is null), create or replace view, create or
-- replace function. Se puede re-ejecutar el archivo entero sin romper nada.
-- REQUISITO: correr DESPUES de 20250501000000..000700 (tablas, vista, RPC y
-- seed de Campanas ya aplicados).
-- ============================================================

-- ------------------------------------------------------------
-- (1) FLAG INTERNO es_placeholder en campana_producto.
-- ------------------------------------------------------------
alter table campana_producto
  add column if not exists es_placeholder boolean not null default false;

comment on column campana_producto.es_placeholder is 'Flag INTERNO (NUNCA se expone en catalogo_publico): marca los productos FICTICIOS de ejemplo sembrados para arrancar el home. El dueno NO los edita para volverlos reales; los RETIRA y crea productos NUEVOS (para no heredar su identidad/UUID). true = ficticio (no debe manchar el sistema); false = real (Grisi). Uso interno del panel para distinguirlos/ocultarlos.';

-- ------------------------------------------------------------
-- (2) SLUG PUBLICO en campana_producto + indice unico parcial (solo cuando el
--     slug no es null: permite muchas filas con slug null sin chocar).
-- ------------------------------------------------------------
alter table campana_producto
  add column if not exists slug text;

comment on column campana_producto.slug is 'Clave PUBLICA legible para la URL de la tienda (magandhi.com/producto/?slug=...), alternativa amable al id uuid. Opcional (NULL permitido) y UNICA cuando no es null (indice unico parcial). A diferencia de es_placeholder, el slug SI es publico y SI entra en catalogo_publico.';

create unique index if not exists campana_producto_slug_key
  on campana_producto (slug)
  where slug is not null;

-- ------------------------------------------------------------
-- (3) MARCAR los placeholders (ficticios) y el real. Acotado por los ids fijos
--     del seed 20250501000700 (idempotente: fija el valor cada vez que corre).
-- ------------------------------------------------------------
update campana_producto
   set es_placeholder = true
 where id in (
   '00000000-0000-0000-0000-0000000c0002',   -- Serum Facial de Rosa Mosqueta (ejemplo)
   '00000000-0000-0000-0000-0000000c0003',   -- Balsamo para Barba de Cedro (ejemplo)
   '00000000-0000-0000-0000-0000000c0004',   -- Jabon de Coco para el Hogar (ejemplo)
   '00000000-0000-0000-0000-0000000c0005'    -- Miel de Cafe Artesanal (ejemplo)
 );

update campana_producto
   set es_placeholder = false
 where id = '00000000-0000-0000-0000-0000000c0001';   -- Shampoo Manzanilla GRISI Gold (real)

-- ------------------------------------------------------------
-- (4) ASIGNAR slug legible a los 5 seeds SOLO si aun no tienen slug (para no
--     pisar un slug ya elegido por el dueno si re-corre la migracion).
-- ------------------------------------------------------------
update campana_producto set slug = 'grisi-manzanilla-gold'
 where id = '00000000-0000-0000-0000-0000000c0001' and slug is null;
update campana_producto set slug = 'serum-facial-rosa-mosqueta'
 where id = '00000000-0000-0000-0000-0000000c0002' and slug is null;
update campana_producto set slug = 'balsamo-barba-cedro'
 where id = '00000000-0000-0000-0000-0000000c0003' and slug is null;
update campana_producto set slug = 'jabon-coco-hogar'
 where id = '00000000-0000-0000-0000-0000000c0004' and slug is null;
update campana_producto set slug = 'miel-cafe-artesanal'
 where id = '00000000-0000-0000-0000-0000000c0005' and slug is null;

-- ------------------------------------------------------------
-- (5) REDEFINIR la vista publica agregando SOLO slug a la lista blanca (justo
--     despues de nombre). Resto de columnas y el WHERE quedan EXACTO. NO se
--     agrega es_placeholder ni ninguna otra columna interna: LINEA ROJA.
-- ------------------------------------------------------------
-- NOTA: se usa DROP + CREATE (no create or replace) porque Postgres no permite
-- insertar una columna nueva (slug) EN MEDIO de una vista existente con
-- 'create or replace view' (solo deja agregar columnas AL FINAL o mantener el
-- mismo orden). Recrear la vista es seguro: es una ventana sin datos y el
-- drop+create corren en el mismo lote. El grant a anon/authenticated se re-otorga
-- abajo porque el drop se lo lleva.
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
  cp.stock_disponible,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
where cp.publicado = true
  and cp.activo = true;

comment on view catalogo_publico is 'CAMPANAS · vista publica SEGURA que lee la tienda (magandhi.com) sin login. SOLO expone productos con publicado=true y activo=true, y SOLO campos publicos (nombre, slug para la URL, categoria + colores, presentacion, hooks, precio_venta, textos, ficha, imagenes, sello, estrella, stock, aviso de urgencia). Ahora tambien expone slug (publico, para la URL legible). JAMAS expone es_placeholder ni ninguna columna interna: costo/proveedor/stock interno, product_id_ref, creado_por, ni las etiquetas de segmentacion. El candado es doble: tablas base sin grant/policy para anon + la vista solo trae filas publicadas y columnas publicas. Grant select a anon: ver 20250501000600_campanas_grants.sql.';

-- RE-OTORGAR el grant: el DROP VIEW de arriba se lleva el grant que 20250501000600
-- le habia dado a la vista, asi que hay que volver a concederlo o la tienda
-- (rol anon) y el panel (authenticated) perderian el acceso de lectura.
grant select on catalogo_publico to anon, authenticated;

-- ------------------------------------------------------------
-- (6) RPC cm_crear_etiqueta: agrega una etiqueta al catalogo campana_etiqueta
--     desde el panel (patron agregar_cuenta_puc / cm_crear_campana). Normaliza
--     el codigo a un identificador estable (minusculas, sin acentos, no-alfa ->
--     guion_bajo, colapsando/recortando guiones bajos). Rechaza duplicados
--     (no upsert silencioso: el dueno debe enterarse de que ya existia).
--     Devuelve jsonb {codigo} con el codigo normalizado.
-- ------------------------------------------------------------
create or replace function cm_crear_etiqueta(
  p_codigo      text,
  p_nombre      text,
  p_descripcion text default null,
  p_orden       integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := trim(p_nombre);
  v_codigo text;
begin
  -- 1) CANDADO server-side: se exige acceso al modulo marketing (primero de
  --    todo, aunque la funcion salte RLS por ser definer).
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  -- 2) NOMBRE no vacio.
  if v_nombre is null or length(v_nombre) = 0 then
    raise exception 'El nombre de la etiqueta es obligatorio.';
  end if;

  -- 3) NORMALIZAR el codigo a un identificador estable:
  --    minusculas + trim -> quitar acentos (vocales y n con tilde) ->
  --    reemplazar todo lo que no sea [a-z0-9] por guion_bajo -> colapsar
  --    guiones_bajos repetidos -> recortar los de los extremos.
  v_codigo := lower(trim(coalesce(p_codigo, '')));
  v_codigo := translate(v_codigo,
                        'áàäâãéèëêíìïîóòöôõúùüûñç',
                        'aaaaaeeeeiiiiooooouuuunc');
  v_codigo := regexp_replace(v_codigo, '[^a-z0-9]+', '_', 'g');
  v_codigo := regexp_replace(v_codigo, '_+', '_', 'g');
  v_codigo := trim(both '_' from v_codigo);

  -- 4) CODIGO normalizado no vacio (ej. si venia solo con simbolos/acentos raros).
  if v_codigo is null or length(v_codigo) = 0 then
    raise exception 'El codigo de la etiqueta quedo vacio despues de normalizar. Use letras o numeros.';
  end if;

  -- 5) DUPLICADO: si el codigo ya existe, se rechaza (no upsert silencioso).
  if exists (select 1 from campana_etiqueta where codigo = v_codigo) then
    raise exception 'La etiqueta % ya existe en el catalogo.', v_codigo;
  end if;

  -- 6) INSERT final. activo=true (alta viva); orden por defecto 0 si viene null.
  insert into campana_etiqueta (codigo, nombre, descripcion, orden, activo)
  values (v_codigo, v_nombre, nullif(trim(coalesce(p_descripcion, '')), ''),
          coalesce(p_orden, 0), true);

  return jsonb_build_object('codigo', v_codigo);
end;
$$;

comment on function cm_crear_etiqueta(text, text, text, integer) is 'CAMPANAS · agrega una etiqueta de segmentacion INTERNA al catalogo campana_etiqueta desde el panel (patron agregar_cuenta_puc). Valida tiene_acceso_marketing() y nombre no vacio. NORMALIZA el codigo (minusculas, sin acentos, no-alfanumerico -> guion_bajo, colapsa y recorta guiones bajos), rechaza codigo vacio y duplicados (no upsert). Inserta con activo=true. Devuelve jsonb {codigo} con el codigo normalizado.';

-- ------------------------------------------------------------
-- (7) RPC cm_editar_etiqueta: edita nombre/descripcion/orden y permite
--     DESACTIVAR (activo=false: baja logica, NUNCA delete). NO cambia el codigo
--     (es la PK y clave estable; cambiarlo romperia asignaciones historicas del
--     puente). Devuelve el codigo.
-- ------------------------------------------------------------
create or replace function cm_editar_etiqueta(
  p_codigo      text,
  p_nombre      text,
  p_descripcion text default null,
  p_orden       integer default 0,
  p_activo      boolean default true
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := trim(p_nombre);
  v_codigo text := trim(coalesce(p_codigo, ''));
begin
  -- 1) CANDADO server-side.
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  -- 2) NOMBRE no vacio (aun al desactivar se conserva un nombre legible).
  if v_nombre is null or length(v_nombre) = 0 then
    raise exception 'El nombre de la etiqueta es obligatorio.';
  end if;

  -- 3) EXISTENCIA: el codigo es la PK estable; NO se cambia. Si no existe, error.
  if not exists (select 1 from campana_etiqueta where codigo = v_codigo) then
    raise exception 'La etiqueta % no existe.', v_codigo;
  end if;

  -- 4) ACTUALIZAR nombre/descripcion/orden/activo. activo=false = baja logica
  --    (desactivar), NUNCA delete: desactivar una etiqueta NO rompe asignaciones
  --    historicas del puente campana_producto_etiqueta.
  update campana_etiqueta
     set nombre      = v_nombre,
         descripcion = nullif(trim(coalesce(p_descripcion, '')), ''),
         orden       = coalesce(p_orden, 0),
         activo      = coalesce(p_activo, true)
   where codigo = v_codigo;

  return v_codigo;
end;
$$;

comment on function cm_editar_etiqueta(text, text, text, integer, boolean) is 'CAMPANAS · edita una etiqueta del catalogo campana_etiqueta (nombre, descripcion, orden) y permite DESACTIVARLA (activo=false: baja logica, NUNCA delete). Valida tiene_acceso_marketing() y que la etiqueta exista. NO cambia el codigo (PK y clave estable). Desactivar NO rompe asignaciones historicas del puente campana_producto_etiqueta. Devuelve el codigo.';
