-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Producto vestido (identidad)
-- ------------------------------------------------------------
-- QUE ES CAMPANAS: el software que "viste" un producto para publicarlo en la
-- tienda publica (magandhi.com). Cada campana tiene DOS secciones que el dueno
-- llena desde el panel: (1) BANNER HOOK (lo que engancha en el grid del home:
-- nombre, categoria con su color, presentacion, hook corto, imagen) y (2)
-- PRODUCTO (la pagina real: caracteristica, precio, descripcion larga, por que
-- esta en MAGANDHI, sobre este producto, ficha tecnica y galeria). Ademas trae
-- INTERRUPTORES por producto (sello, estrella, aviso de urgencia manual, stock
-- manual, publicar/despublicar).
--
-- ISLA (decision de arquitectura cerrada): CAMPANAS NO se cruza HOY con la
-- tabla `productos` de Inventario. NO lee stock real, NO usa su product_id.
-- campana_producto tiene IDENTIDAD PROPIA (su propio id uuid). Para conectar
-- Inventario despues SIN cirugia, se deja `product_id_ref` uuid NULL SIN FK
-- ("enchufe apagado", mismo patron que customer_id en movimientos_inventario
-- antes de que existiera Ventas). Hoy ese enchufe NO se conecta.
--
-- REGLAS DURAS DEL ECOSISTEMA (igual que Inventario/Ventas/Finanzas):
--   - Montos SIEMPRE bigint: precio_venta en pesos colombianos ENTEROS, nunca
--     float (evita errores de redondeo del punto flotante).
--   - NADA se borra: un producto se despublica (publicado=false) o se da de
--     baja logica (activo=false). Nunca DELETE.
--   - El candado real vive en los DATOS (RLS + RPC security definer), no en el
--     HTML. Toda ESCRITURA pasa por las RPC cm_* (ver 20250501000500). Esta
--     tabla NO tiene policy de INSERT/UPDATE/DELETE para el cliente.
--
-- AVISO DE URGENCIA (enfasis del dueno): es un INTERRUPTOR MANUAL por producto
-- (aviso_urgencia_activo) mas un NUMERO que el dueno define
-- (aviso_urgencia_cantidad, para el mensaje "Solo X disponibles"). Es REAL y
-- honesto: el dueno lo activa en el momento adecuado (por ejemplo cuando de
-- verdad quedan 3 unidades), nada de escasez fabricada. Aunque conceptualmente
-- el aviso tiene sentido conectado a Inventario, HOY es manual porque Campanas
-- es isla. La RPC exige cantidad > 0 cuando el switch esta activo.
--
-- IDEMPOTENTE: create table if not exists / create index if not exists. Se
-- puede re-ejecutar el archivo sin romper nada.
-- REQUISITO: correr DESPUES de 20250101000000_crear_perfiles_y_roles.sql (de
-- alli sale tiene_modulo) y de 20250301000600_inventario_marketing_lectura.sql
-- (de alli sale tiene_acceso_marketing, que usan la RLS y las RPC). La FK a
-- campana_categoria la enciende 20250501000100 (archivo siguiente).
-- ============================================================

-- gen_random_uuid() lo trae Supabase de fabrica (pgcrypto). Defensivo por si se
-- aplica en un Postgres limpio; en Supabase es idempotente y no molesta.
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- campana_producto: la identidad del producto VESTIDO para la tienda.
--   - id (uuid) = identidad PROPIA de la campana (no es el product_id de
--     Inventario). Autogenerada, nunca la escribe el dueno.
--   - product_id_ref (uuid NULL, SIN FK) = ENCHUFE APAGADO para conectar
--     Inventario despues sin cirugia. Hoy queda NULL. Igual patron que
--     customer_id en movimientos_inventario antes de que existiera Ventas.
-- Los campos se agrupan por las DOS secciones del panel + los interruptores +
-- auditoria. Comentarios por columna explican cada decision.
-- ------------------------------------------------------------
create table if not exists campana_producto (
  id                      uuid primary key default gen_random_uuid(),

  -- ---- SECCION 1 · BANNER HOOK (lo que se ve en el grid del home) ----
  nombre                  text not null,
  categoria_codigo        text,                 -- FK a campana_categoria (la enciende 20250501000100)
  detalle_presentacion    text,                 -- ej. 'Con extracto de curcuma . 400 mL' (la meta del grid)
  hook_corto              text,                  -- frase gancho corta del grid
  imagen_banner_path      text,                  -- path de la imagen principal del banner/grid

  -- ---- SECCION 2 · PRODUCTO (la pagina real del producto) ----
  caracteristica_adicional text,                 -- subtitulo de la ficha, ej. 'Con extracto de curcuma . 400 mL . Marca Grisi'
  precio_venta            bigint,                -- pesos COP ENTEROS, NUNCA float
  hook_largo              text,                  -- descripcion larga (parrafo bajo el precio)
  por_que_magandhi        text,                  -- bloque de curaduria 'Por que esta en MAGANDHI'
  sobre_este_producto     text,                  -- bloque 'Sobre este producto' (uno o dos parrafos)
  ficha_tecnica           jsonb default '[]'::jsonb,  -- arreglo de pares {clave, valor} para la tabla de ficha
  imagenes                jsonb default '[]'::jsonb,  -- arreglo de paths de la galeria (sin limite fijo)

  -- ---- INTERRUPTORES / CONTROLES por producto ----
  sello_elegido           boolean not null default false, -- sello 'Elegido por MAGANDHI'
  estrella                boolean not null default false, -- estrella (va DENTRO del sello) para producto destacado
  stock_disponible        integer default 0,     -- stock MANUAL (la isla no lee Inventario hoy; puede ser 0)
  aviso_urgencia_activo   boolean not null default false, -- interruptor MANUAL del aviso 'Solo X disponibles'
  aviso_urgencia_cantidad integer,               -- numero que el dueno define para el aviso (manual, honesto)
  publicado               boolean not null default false, -- visible en la tienda publica (via catalogo_publico)

  -- ---- ENCHUFE APAGADO (conexion futura a Inventario, SIN FK hoy) ----
  product_id_ref          uuid,                  -- uuid NULL SIN FK: enchufe para conectar Inventario despues

  -- ---- AUDITORIA / ORDEN ----
  activo                  boolean not null default true, -- baja logica: un producto NUNCA se borra
  orden                   integer default 0,     -- orden en el grid (menor primero)
  creado                  timestamptz default now(),
  creado_por              uuid default auth.uid(),
  actualizado             timestamptz
);

comment on table campana_producto is 'CAMPANAS · producto vestido para la tienda publica. ISLA: identidad PROPIA (id uuid), NO se cruza con productos de Inventario. Dos secciones (banner hook + producto) mas interruptores (sello, estrella, aviso urgencia manual, stock manual, publicar). Montos en bigint (pesos enteros). Nada se borra (baja logica/despublicar). Escritura solo por RPC security definer cm_* que validan tiene_acceso_marketing().';
comment on column campana_producto.id is 'Identidad PROPIA de la campana (uuid autogenerado). NO es el product_id de Inventario (Campanas es isla).';
comment on column campana_producto.categoria_codigo is 'Categoria del producto (FK a campana_categoria). Define el COLOR automatico del banner/tarjeta; el color no se guarda aqui, se deriva de la categoria.';
comment on column campana_producto.detalle_presentacion is 'Meta corta del grid (ej. "Con extracto de curcuma . 400 mL"). Seccion 1 (banner hook).';
comment on column campana_producto.precio_venta is 'Precio de venta en pesos COP ENTEROS (bigint). NUNCA float: regla dura del ecosistema.';
comment on column campana_producto.ficha_tecnica is 'Arreglo jsonb de pares {clave, valor} para la tabla "Ficha" de la pagina de producto.';
comment on column campana_producto.imagenes is 'Arreglo jsonb de paths de la galeria del producto (sin limite fijo).';
comment on column campana_producto.sello_elegido is 'Interruptor: muestra el sello "Elegido por MAGANDHI". Siempre visible en el diseno aprobado cuando esta activo.';
comment on column campana_producto.estrella is 'Interruptor: estrella DENTRO del sello, para producto destacado. Opcional (solo si el dueno la activa).';
comment on column campana_producto.stock_disponible is 'Stock MANUAL definido por el dueno. La isla NO lee Inventario hoy; puede quedar 0. El estado "Agotado" queda preparado en el modelo pero no se dispara solo (no hay stock real hoy).';
comment on column campana_producto.aviso_urgencia_activo is 'Interruptor MANUAL del aviso de urgencia ("Solo X disponibles"). El dueno lo activa en el momento adecuado (ej. cuando quedan 3 unidades). Aviso REAL y honesto, no escasez fabricada.';
comment on column campana_producto.aviso_urgencia_cantidad is 'Numero que el dueno define para el aviso ("Solo X disponibles"). Manual. La RPC exige que sea no nulo y > 0 cuando aviso_urgencia_activo = true.';
comment on column campana_producto.publicado is 'Interruptor publicar/despublicar. Solo los publicados (y activos) aparecen en la vista catalogo_publico que lee la tienda. Despublicar NO borra.';
comment on column campana_producto.product_id_ref is 'ENCHUFE APAGADO: uuid NULL SIN FK para conectar el producto de Inventario despues sin cirugia. Hoy queda NULL (Campanas es isla). Mismo patron que customer_id en movimientos_inventario antes de Ventas.';
comment on column campana_producto.activo is 'Baja logica. Un producto de campana NUNCA se borra (rompe historial): se marca activo=false.';
comment on column campana_producto.orden is 'Orden de aparicion en el grid de la tienda (menor primero).';

-- Indices utiles: el grid publico filtra publicados y ordena por orden; el
-- panel agrupa por categoria.
create index if not exists campana_producto_publicado_idx on campana_producto (publicado);
create index if not exists campana_producto_categoria_idx on campana_producto (categoria_codigo);
create index if not exists campana_producto_orden_idx      on campana_producto (orden);

-- RLS de esta tabla: ver 20250501000400_campanas_rls.sql (SELECT solo con
-- tiene_acceso_marketing(); sin escritura directa; nada para anon). Se habilita
-- alli para mantener toda la politica de acceso de Campanas en un unico archivo.
