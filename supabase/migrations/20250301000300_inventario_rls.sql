-- ============================================================
-- Magandhi Corporation · Modulo Inventario · RLS (el candado real)
-- Row Level Security en TODAS las tablas del modulo, apoyada en la funcion
-- central tiene_modulo('inventario') (definida en
-- 20250101000000_crear_perfiles_y_roles.sql). Se REUTILIZA esa funcion; no se
-- reimplementa la logica de acceso: admin ve todo; otros solo si 'inventario'
-- esta en su lista de modulos. La funcion NO se redefine aqui.
--
-- El candado real esta AQUI (en los datos), no en el HTML. Ocultar una pagina
-- o una tarjeta en el navegador es comodidad de UX, nunca seguridad.
--
-- Resumen de politicas (mismo criterio que Finanzas):
--   inventario_config ...... SELECT si tiene_modulo('inventario'). La escribe
--                            el dueno con service_role (semilla del prefijo);
--                            sin INSERT/UPDATE/DELETE para authenticated.
--   productos .............. SELECT si tiene_modulo('inventario'). SIN
--                            INSERT/UPDATE/DELETE directo: toda escritura va
--                            por RPC security definer (inv_crear_producto /
--                            inv_editar_producto). Un producto no se borra:
--                            activo=false.
--   movimientos_inventario . SELECT si tiene_modulo('inventario'). SIN
--                            INSERT/UPDATE/DELETE directo: el libro se escribe
--                            por inv_registrar_movimiento (append-only). Nada
--                            se borra; un error se compensa con un ajuste.
--   stock_actual (vista) ... NO necesita policy: hereda la RLS de sus tablas
--                            base (SECURITY INVOKER).
--
-- SIN DELETE en ninguna tabla. Toda escritura pasa por RPC security definer
-- que valida tiene_modulo('inventario') al entrar.
--
-- IDEMPOTENTE: drop policy if exists + create policy.
-- ============================================================

-- ------------------------------------------------------------
-- inventario_config
-- ------------------------------------------------------------
alter table inventario_config enable row level security;

drop policy if exists "inventario_config_select_modulo" on inventario_config;
create policy "inventario_config_select_modulo" on inventario_config
  for select
  to authenticated
  using (tiene_modulo('inventario'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el prefijo del SKU es
-- configuracion, la siembra el dueno con service_role desde el dashboard. Asi
-- nadie desde el cliente cambia el prefijo del SKU.

-- ------------------------------------------------------------
-- productos
-- ------------------------------------------------------------
alter table productos enable row level security;

drop policy if exists "productos_select_modulo" on productos;
create policy "productos_select_modulo" on productos
  for select
  to authenticated
  using (tiene_modulo('inventario'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el alta y la edicion
-- de la ficha van por inv_crear_producto / inv_editar_producto (security
-- definer). Sin DELETE: un producto no se borra, se marca activo=false.

-- ------------------------------------------------------------
-- movimientos_inventario (el libro: solo anadir + leer)
-- ------------------------------------------------------------
alter table movimientos_inventario enable row level security;

drop policy if exists "movimientos_inventario_select_modulo" on movimientos_inventario;
create policy "movimientos_inventario_select_modulo" on movimientos_inventario
  for select
  to authenticated
  using (tiene_modulo('inventario'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el libro se escribe
-- SOLO via inv_registrar_movimiento (security definer). Append-only: nada se
-- edita ni se borra; un error se compensa con un ajuste que deja el rastro.
