-- ============================================================
-- Magandhi Corporation · Modulo Inventario · RLS (el candado real)
-- Row Level Security en TODAS las tablas del modulo, apoyada en la funcion
-- de acceso del modulo tiene_acceso_inventario() (definida mas abajo, envuelve
-- la funcion central tiene_modulo() de
-- 20250101000000_crear_perfiles_y_roles.sql). Se REUTILIZA esa funcion; no se
-- reimplementa la logica de acceso: admin ve todo; otros solo si su lista de
-- modulos incluye una de las claves de este modulo.
--
-- CONVENCION DE CLAVES (una sola historia panel <-> core <-> datos):
--   El panel y los cores razonan con claves de AREA/SUB-AREA ('produccion',
--   'inventarios'). La clave canonica del DATO es 'inventario'. Para que la
--   receta intuitiva del dueno (dar '{produccion}' a un trabajador de bodega,
--   ver INSTRUCCIONES I4) funcione de punta a punta, el candado de datos acepta
--   CUALQUIERA de las tres claves equivalentes de este modulo:
--       'inventario'  (clave canonica del dato)
--       'produccion'  (clave del area contenedora)
--       'inventarios' (clave de la sub-area)
--   Asi la visibilidad de la UI y el candado de datos cuentan lo MISMO: quien
--   ve la carpeta tambien puede leer/operar los datos. El candado real sigue
--   estando AQUI (en los datos), no en el HTML. Ocultar una pagina o una
--   tarjeta en el navegador es comodidad de UX, nunca seguridad.
--
-- Resumen de politicas (mismo criterio que Finanzas):
--   inventario_config ...... SELECT si tiene_acceso_inventario(). La escribe
--                            el dueno con service_role (semilla del prefijo);
--                            sin INSERT/UPDATE/DELETE para authenticated.
--   productos .............. SELECT si tiene_acceso_inventario(). SIN
--                            INSERT/UPDATE/DELETE directo: toda escritura va
--                            por RPC security definer (inv_crear_producto /
--                            inv_editar_producto). Un producto no se borra:
--                            activo=false.
--   movimientos_inventario . SELECT si tiene_acceso_inventario(). SIN
--                            INSERT/UPDATE/DELETE directo: el libro se escribe
--                            por inv_registrar_movimiento (append-only). Nada
--                            se borra; un error se compensa con un ajuste.
--   stock_actual (vista) ... NO necesita policy: hereda la RLS de sus tablas
--                            base (SECURITY INVOKER).
--
-- SIN DELETE en ninguna tabla. Toda escritura pasa por RPC security definer
-- que valida tiene_acceso_inventario() al entrar.
--
-- IDEMPOTENTE: drop policy if exists + create policy + create or replace fn.
-- ============================================================

-- ------------------------------------------------------------
-- tiene_acceso_inventario(): clave de acceso del modulo Inventario.
-- Envuelve tiene_modulo() y acepta las tres claves equivalentes del modulo
-- (canonica del dato + area + sub-area) para que el candado de datos hable el
-- MISMO idioma que el panel y los cores. admin ve todo (lo resuelve
-- tiene_modulo). Clonable: un modulo nuevo copia esta funcion con sus claves.
-- ------------------------------------------------------------
create or replace function tiene_acceso_inventario()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('inventario')
      or tiene_modulo('produccion')
      or tiene_modulo('inventarios');
$$;

comment on function tiene_acceso_inventario() is 'Acceso al modulo Inventario: true si el usuario tiene la clave canonica del dato (inventario) o la del area (produccion) o la de la sub-area (inventarios), o si es admin. Envuelve tiene_modulo() para que el candado de datos, el panel y los cores hablen la misma convencion de claves.';

-- ------------------------------------------------------------
-- inventario_config
-- ------------------------------------------------------------
alter table inventario_config enable row level security;

drop policy if exists "inventario_config_select_modulo" on inventario_config;
create policy "inventario_config_select_modulo" on inventario_config
  for select
  to authenticated
  using (tiene_acceso_inventario());
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
  using (tiene_acceso_inventario());
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
  using (tiene_acceso_inventario());
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el libro se escribe
-- SOLO via inv_registrar_movimiento (security definer). Append-only: nada se
-- edita ni se borra; un error se compensa con un ajuste que deja el rastro.
