-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Vista publica SEGURA (catalogo_publico)
-- ------------------------------------------------------------
-- QUE ES: la UNICA superficie que la tienda publica (magandhi.com) lee EN VIVO,
-- SIN login (rol anon). Es una vista que expone SOLO productos publicados y SOLO
-- campos publicos. Es la LINEA ROJA de seguridad del dueno: la tienda jamas debe
-- poder ver informacion interna del negocio.
--
-- QUE FILTRA (solo lo que puede salir a la calle):
--   WHERE publicado = true AND activo = true  -> solo productos vivos y publicados.
--
-- QUE EXPONE (campos PUBLICOS, los que el diseno de la tienda necesita):
--   id, nombre, categoria + su terna de color (join a campana_categoria),
--   detalle_presentacion, hook_corto, imagen_banner_path, caracteristica_adicional,
--   precio_venta, hook_largo, por_que_magandhi, sobre_este_producto, ficha_tecnica,
--   imagenes, sello_elegido, estrella, stock_disponible, aviso_urgencia_activo,
--   aviso_urgencia_cantidad, orden.
--
-- QUE JAMAS EXPONE (por que cada uno queda FUERA):
--   - product_id_ref  -> es el enchufe interno a Inventario; la tienda no debe
--                        conocer la identidad interna del producto.
--   - creado_por      -> es el uuid del usuario del back-office (dato interno).
--   - etiquetas de segmentacion (campana_etiqueta / campana_producto_etiqueta)
--                     -> son inteligencia interna del negocio; la vista NO hace
--                        join a esas tablas.
--   - costo / proveedor / stock interno de Inventario -> NO existen en Campanas
--                        (es isla) y NO se traen de ningun lado: la vista solo
--                        mira campana_producto y campana_categoria.
--
-- ESTRATEGIA DE ACCESO (documentada, la mas simple y segura):
--   catalogo_publico es una vista NORMAL (no materializada). El candado real es
--   DOBLE: (a) las tablas base NO tienen grant ni policy para anon (ver
--   20250501000400 y 20250501000600), asi que anon no puede leerlas directo; y
--   (b) la vista ya trae el WHERE publicado=true y solo columnas publicas, y es
--   la UNICA que recibe grant select a anon. Por defecto una vista en Postgres
--   corre con los privilegios de su DUENO (security_invoker OFF), de modo que
--   anon puede leer la vista aunque no tenga acceso directo a las tablas base:
--   justo lo que queremos (leer solo lo publicado, nada mas).
--
-- IDEMPOTENTE: create or replace view. Re-ejecutar solo actualiza la definicion.
-- REQUISITO: correr DESPUES de 20250501000000_campanas_producto.sql y
-- 20250501000100_campanas_categorias.sql.
-- ============================================================

create or replace view catalogo_publico as
select
  cp.id,
  cp.nombre,
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

comment on view catalogo_publico is 'CAMPANAS · vista publica SEGURA que lee la tienda (magandhi.com) sin login. SOLO expone productos con publicado=true y activo=true, y SOLO campos publicos (nombre, categoria + colores, presentacion, hooks, precio_venta, textos, ficha, imagenes, sello, estrella, stock, aviso de urgencia). JAMAS expone costo/proveedor/stock interno, product_id_ref, creado_por, ni las etiquetas de segmentacion (internas). El candado es doble: tablas base sin grant/policy para anon + la vista solo trae filas publicadas y columnas publicas. Grant select a anon: ver 20250501000600_campanas_grants.sql.';
