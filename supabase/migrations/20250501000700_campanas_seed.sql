-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · SEED de los 5 productos del home
-- ------------------------------------------------------------
-- QUE HACE: siembra los 5 productos que HOY estan en el home de la tienda
-- (magandhi/index.html) para que Campanas arranque con datos reales y la tienda
-- pueda leerlos EN VIVO desde catalogo_publico (FEAT-004) sin perder su diseno.
--
-- ORIGEN DE LOS TEXTOS (tal como estan en la tienda):
--   (1) Shampoo Manzanilla GRISI Gold  -> unico con pagina real; textos EXACTOS
--       de magandhi/producto/grisi-manzanilla-gold/index.html (sello + estrella,
--       precio 24900, por que MAGANDHI, sobre este producto, ficha).
--   (2..5) Serum Rosa Mosqueta, Balsamo de Barba, Jabon de Coco, Miel de Cafe
--       -> productos de EJEMPLO del home (el dueno los ajustara desde el panel).
-- Los NOMBRES y PRECIOS se conservan EXACTOS. Los textos de contenido conservan
-- su acentuacion (es contenido de la tienda, no un mensaje de commit).
--
-- IDEMPOTENTE: se usan IDS FIJOS por producto + on conflict (id) do update, de
-- modo que re-ejecutar refresca el contenido sin duplicar filas. Las etiquetas
-- de segmentacion se reasignan borrando primero las de estos 5 ids.
--
-- POR DEFECTO: publicado=true (los 5 salen a la tienda), aviso_urgencia_activo=
-- false (el dueno lo prende cuando de verdad quede poco stock), stock_disponible
-- razonable (>0). El estado "Agotado" queda preparado en el modelo pero no se
-- dispara solo (no hay stock real hoy: Campanas es isla).
--
-- REQUISITO: correr DESPUES de 20250501000000..000200 (tablas, categorias sembradas,
-- etiquetas sembradas). Las categorias 'cabello'..'alimentos' ya existen.
-- ============================================================

-- ------------------------------------------------------------
-- 5 productos. ficha_tecnica = arreglo jsonb de pares {clave, valor}.
-- ------------------------------------------------------------
insert into campana_producto (
  id, nombre, categoria_codigo, detalle_presentacion, hook_corto, imagen_banner_path,
  caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
  sobre_este_producto, ficha_tecnica, imagenes,
  sello_elegido, estrella, stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad,
  publicado, orden
) values
  -- (1) PRODUCTO ESTRELLA · Grisi Manzanilla Gold · cabello · sello + estrella
  (
    '00000000-0000-0000-0000-0000000c0001',
    'Shampoo Manzanilla GRISI Gold',
    'cabello',
    'Con extracto de cúrcuma · 400 mL',
    'Un clásico del cuidado con manzanilla. Lo revisamos uno a uno: original, en fecha y en buen estado. Si no cumple, no entra.',
    'productos/grisi-manzanilla-gold.png',
    'Con extracto de cúrcuma · 400 mL · Marca Grisi',
    24900,
    'Shampoo de manzanilla con extracto de cúrcuma de la marca Grisi, presentación de 400 mL. Pensado para quienes buscan un shampoo de uso diario con ingredientes de origen botánico.',
    'El equipo revisó este producto antes de ofrecerlo: verificamos que sea original, que esté dentro de su fecha y que la presentación llegue en buen estado. Si algo no cumple, no entra.',
    'La manzanilla es un ingrediente tradicional en el cuidado del cabello. Este shampoo de la línea Gold de Grisi combina manzanilla con extracto de cúrcuma en una presentación de 400 mL para uso diario. MAGANDHI describe el producto tal como es: te contamos qué contiene y para qué tipo de uso está pensado, sin prometer resultados que no podamos sostener. La información de ingredientes y modo de uso viene del fabricante y está impresa en el envase.',
    '[{"clave":"Marca","valor":"Grisi"},{"clave":"Línea","valor":"Manzanilla Gold"},{"clave":"Contenido","valor":"400 mL"},{"clave":"Tipo","valor":"Shampoo de uso diario"},{"clave":"Ingrediente destacado","valor":"Manzanilla + cúrcuma"},{"clave":"Disponibilidad","valor":"Entrega local"}]'::jsonb,
    '["productos/grisi-manzanilla-gold.png"]'::jsonb,
    true, true, 25, false, null,
    true, 1
  ),
  -- (2) EJEMPLO · Serum Facial de Rosa Mosqueta · belleza_fem · sello, sin estrella
  (
    '00000000-0000-0000-0000-0000000c0002',
    'Sérum Facial de Rosa Mosqueta',
    'belleza_fem',
    'Aceite botánico · 30 mL',
    'Aceite de rosa mosqueta para rutina facial nocturna. Te contamos qué contiene, sin promesas de milagros.',
    null,
    'Aceite botánico · 30 mL',
    32900,
    'Aceite de rosa mosqueta para rutina facial nocturna. Te contamos qué contiene, sin promesas de milagros.',
    'El equipo revisó este producto antes de ofrecerlo: verificamos que sea original, que esté dentro de su fecha y que la presentación llegue en buen estado. Si algo no cumple, no entra.',
    'Producto de ejemplo del home: el dueño lo ajustará desde el panel de Campañas con los textos y la ficha definitivos.',
    '[{"clave":"Contenido","valor":"30 mL"},{"clave":"Tipo","valor":"Aceite facial"},{"clave":"Disponibilidad","valor":"Entrega local"}]'::jsonb,
    '[]'::jsonb,
    true, false, 15, false, null,
    true, 2
  ),
  -- (3) EJEMPLO · Balsamo para Barba de Cedro · belleza_masc
  (
    '00000000-0000-0000-0000-0000000c0003',
    'Bálsamo para Barba de Cedro',
    'belleza_masc',
    'Con aceite de argán · 60 mL',
    'Bálsamo para dar forma y suavidad a la barba. Aroma de cedro; lo revisamos antes de ofrecerlo.',
    null,
    'Con aceite de argán · 60 mL',
    28500,
    'Bálsamo para dar forma y suavidad a la barba. Aroma de cedro; lo revisamos antes de ofrecerlo.',
    'El equipo revisó este producto antes de ofrecerlo: verificamos que sea original, que esté dentro de su fecha y que la presentación llegue en buen estado. Si algo no cumple, no entra.',
    'Producto de ejemplo del home: el dueño lo ajustará desde el panel de Campañas con los textos y la ficha definitivos.',
    '[{"clave":"Contenido","valor":"60 mL"},{"clave":"Tipo","valor":"Bálsamo para barba"},{"clave":"Disponibilidad","valor":"Entrega local"}]'::jsonb,
    '[]'::jsonb,
    true, false, 15, false, null,
    true, 3
  ),
  -- (4) EJEMPLO · Jabon de Coco para el Hogar · hogar
  (
    '00000000-0000-0000-0000-0000000c0004',
    'Jabón de Coco para el Hogar',
    'hogar',
    'Multiusos concentrado · 500 g',
    'Jabón de coco para lavado y limpieza del hogar. Rinde y huele a limpio; nada de promesas de más.',
    null,
    'Multiusos concentrado · 500 g',
    15900,
    'Jabón de coco para lavado y limpieza del hogar. Rinde y huele a limpio; nada de promesas de más.',
    'El equipo revisó este producto antes de ofrecerlo: verificamos que sea original, que esté dentro de su fecha y que la presentación llegue en buen estado. Si algo no cumple, no entra.',
    'Producto de ejemplo del home: el dueño lo ajustará desde el panel de Campañas con los textos y la ficha definitivos.',
    '[{"clave":"Contenido","valor":"500 g"},{"clave":"Tipo","valor":"Jabón multiusos"},{"clave":"Disponibilidad","valor":"Entrega local"}]'::jsonb,
    '[]'::jsonb,
    true, false, 20, false, null,
    true, 4
  ),
  -- (5) EJEMPLO · Miel de Cafe Artesanal · alimentos
  (
    '00000000-0000-0000-0000-0000000c0005',
    'Miel de Café Artesanal',
    'alimentos',
    'Origen colombiano · 250 g',
    'Miel con notas de café de finca colombiana. Producto natural, envasado tal como se cosecha.',
    null,
    'Origen colombiano · 250 g',
    21000,
    'Miel con notas de café de finca colombiana. Producto natural, envasado tal como se cosecha.',
    'El equipo revisó este producto antes de ofrecerlo: verificamos que sea original, que esté dentro de su fecha y que la presentación llegue en buen estado. Si algo no cumple, no entra.',
    'Producto de ejemplo del home: el dueño lo ajustará desde el panel de Campañas con los textos y la ficha definitivos.',
    '[{"clave":"Contenido","valor":"250 g"},{"clave":"Origen","valor":"Colombia"},{"clave":"Disponibilidad","valor":"Entrega local"}]'::jsonb,
    '[]'::jsonb,
    true, false, 30, false, null,
    true, 5
  )
on conflict (id) do update
  set nombre                   = excluded.nombre,
      categoria_codigo         = excluded.categoria_codigo,
      detalle_presentacion     = excluded.detalle_presentacion,
      hook_corto               = excluded.hook_corto,
      imagen_banner_path       = excluded.imagen_banner_path,
      caracteristica_adicional = excluded.caracteristica_adicional,
      precio_venta             = excluded.precio_venta,
      hook_largo               = excluded.hook_largo,
      por_que_magandhi         = excluded.por_que_magandhi,
      sobre_este_producto      = excluded.sobre_este_producto,
      ficha_tecnica            = excluded.ficha_tecnica,
      imagenes                 = excluded.imagenes,
      sello_elegido            = excluded.sello_elegido,
      estrella                 = excluded.estrella,
      stock_disponible         = excluded.stock_disponible,
      aviso_urgencia_activo    = excluded.aviso_urgencia_activo,
      aviso_urgencia_cantidad  = excluded.aviso_urgencia_cantidad,
      publicado                = excluded.publicado,
      orden                    = excluded.orden,
      actualizado              = now();

-- ------------------------------------------------------------
-- Etiquetas de segmentacion coherentes por producto (tabla puente). Se
-- reasignan borrando primero las de estos 5 ids (idempotente).
-- ------------------------------------------------------------
delete from campana_producto_etiqueta
 where campana_producto_id in (
   '00000000-0000-0000-0000-0000000c0001',
   '00000000-0000-0000-0000-0000000c0002',
   '00000000-0000-0000-0000-0000000c0003',
   '00000000-0000-0000-0000-0000000c0004',
   '00000000-0000-0000-0000-0000000c0005'
 );

insert into campana_producto_etiqueta (campana_producto_id, etiqueta_codigo) values
  ('00000000-0000-0000-0000-0000000c0001', 'uso_diario'),
  ('00000000-0000-0000-0000-0000000c0001', 'cuidado_capilar'),
  ('00000000-0000-0000-0000-0000000c0002', 'cuidado_facial'),
  ('00000000-0000-0000-0000-0000000c0002', 'origen_natural'),
  ('00000000-0000-0000-0000-0000000c0002', 'gama_alta'),
  ('00000000-0000-0000-0000-0000000c0003', 'barba'),
  ('00000000-0000-0000-0000-0000000c0003', 'regalo'),
  ('00000000-0000-0000-0000-0000000c0004', 'hogar'),
  ('00000000-0000-0000-0000-0000000c0004', 'economico'),
  ('00000000-0000-0000-0000-0000000c0005', 'origen_natural'),
  ('00000000-0000-0000-0000-0000000c0005', 'regalo')
on conflict do nothing;
