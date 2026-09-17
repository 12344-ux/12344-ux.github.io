-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · RLS (el candado real)
-- ------------------------------------------------------------
-- POR QUE EXISTE: pone Row Level Security sobre TODAS las tablas base de
-- Campanas. El candado de verdad esta en los DATOS, no en el HTML: ocultar una
-- pantalla en el navegador es comodidad de UX, nunca seguridad.
--
-- REGLA UNICA POR TABLA: cada tabla base recibe UNA policy FOR SELECT to
-- authenticated using (tiene_acceso_marketing()). La funcion tiene_acceso_
-- marketing() YA existe (20250301000600_inventario_marketing_lectura.sql) y
-- acepta las claves 'marketing' y 'marketing-project'; admin ve todo.
--
-- SIN ESCRITURA DIRECTA: NINGUNA policy de INSERT/UPDATE/DELETE. Toda la
-- escritura pasa SOLO por las RPC security definer cm_* (ver 20250501000500),
-- que corren con privilegios del dueno y por eso no necesitan policy de
-- escritura sobre estas tablas.
--
-- CERO ANON SOBRE TABLAS BASE (linea roja): estas tablas contienen campos
-- internos (product_id_ref, creado_por, etiquetas de segmentacion). El rol anon
-- (tienda publica) NO recibe policy NI grant sobre ellas. La UNICA superficie
-- publica es la vista catalogo_publico, cuyo SELECT se concede a anon en el
-- archivo de grants (20250501000600). El candado publico es DOBLE:
--   (a) tablas base sin grant/policy para anon -> anon no las puede leer directo.
--   (b) la vista solo expone filas publicadas y columnas publicas.
-- catalogo_publico es una vista normal (security_invoker OFF por defecto): corre
-- con privilegios de su dueno, asi anon lee solo lo publicado a traves de ella
-- sin tocar las tablas base. Por eso la vista NO necesita policy propia.
--
-- IDEMPOTENTE: alter table enable rls (se re-asegura) + drop policy if exists +
-- create policy. Se puede re-ejecutar sin duplicar.
-- REQUISITO: correr DESPUES de 20250501000000..000200 (las tablas ya existen) y
-- de 20250301000600 (de alli sale tiene_acceso_marketing).
-- ============================================================

-- ------------------------------------------------------------
-- campana_producto: SELECT si tiene_acceso_marketing(). Sin escritura directa.
-- Cero policy para anon (campos internos como product_id_ref / creado_por).
-- ------------------------------------------------------------
alter table campana_producto enable row level security;

drop policy if exists "campana_producto_select_marketing" on campana_producto;
create policy "campana_producto_select_marketing" on campana_producto
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- ------------------------------------------------------------
-- campana_categoria: SELECT si tiene_acceso_marketing(). El panel lee el
-- catalogo de categorias (colores) para vestir el producto. Sin escritura
-- directa (la siembra la migracion / el dueno con service_role).
-- ------------------------------------------------------------
alter table campana_categoria enable row level security;

drop policy if exists "campana_categoria_select_marketing" on campana_categoria;
create policy "campana_categoria_select_marketing" on campana_categoria
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- ------------------------------------------------------------
-- campana_etiqueta: SELECT si tiene_acceso_marketing(). Catalogo INTERNO de
-- segmentacion. Cero policy para anon (nunca sale a la tienda).
-- ------------------------------------------------------------
alter table campana_etiqueta enable row level security;

drop policy if exists "campana_etiqueta_select_marketing" on campana_etiqueta;
create policy "campana_etiqueta_select_marketing" on campana_etiqueta
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- ------------------------------------------------------------
-- campana_producto_etiqueta: SELECT si tiene_acceso_marketing(). Puente INTERNO.
-- Cero policy para anon. La escritura (reemplazo de etiquetas) va por las RPC.
-- ------------------------------------------------------------
alter table campana_producto_etiqueta enable row level security;

drop policy if exists "campana_producto_etiqueta_select_marketing" on campana_producto_etiqueta;
create policy "campana_producto_etiqueta_select_marketing" on campana_producto_etiqueta
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- Sin policies de INSERT/UPDATE/DELETE en ninguna tabla: la escritura pasa SOLO
-- por las RPC security definer de 20250501000500. Cero policy para anon sobre
-- las tablas base: la unica superficie publica es la vista catalogo_publico
-- (grant a anon en 20250501000600), que ya filtra filas y columnas.
