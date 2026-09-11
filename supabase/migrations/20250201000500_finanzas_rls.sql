-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · RLS (el candado real)
-- Row Level Security en TODAS las tablas financieras, apoyada en la
-- funcion central tiene_modulo('finanzas') (definida en
-- 20250101000000_crear_perfiles_y_roles.sql). Se REUTILIZA esa funcion;
-- no se reimplementa la logica de acceso: admin ve todo; otros solo si
-- 'finanzas' esta en su lista de modulos.
--
-- El candado real esta AQUI (en los datos), no en el HTML. Ocultar una
-- pagina en el navegador es comodidad de UX, nunca seguridad.
--
-- Resumen de politicas:
--   puc_cuentas ...... SELECT si tiene_modulo('finanzas'). SIN UPDATE
--                      directo: el contador "usos" se incrementa via la
--                      funcion security definer incrementar_uso_cuenta()
--                      (ver 20250201000600_finanzas_funciones.sql), para
--                      no abrir UPDATE general del catalogo normativo.
--   asientos ......... SELECT/INSERT/UPDATE si tiene_modulo('finanzas').
--                      SIN DELETE: las correcciones son estado='anulado'
--                      + bitacora, nunca borrado fisico.
--   asiento_lineas ... SELECT/INSERT/UPDATE si tiene_modulo('finanzas').
--                      SIN DELETE directo (el on delete cascade solo
--                      aplicaria si se borrara el asiento, cosa que RLS
--                      impide al no dar DELETE de asientos).
--   asiento_bitacora . SELECT/INSERT si tiene_modulo('finanzas').
--                      SIN UPDATE ni DELETE: el historial es de solo anadir.
-- ============================================================

-- ------------------------------------------------------------
-- puc_cuentas
-- ------------------------------------------------------------
alter table puc_cuentas enable row level security;

drop policy if exists "puc_cuentas_select_modulo" on puc_cuentas;
create policy "puc_cuentas_select_modulo" on puc_cuentas
  for select
  to authenticated
  using (tiene_modulo('finanzas'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el catalogo es
-- normativo (lo carga el dueno con service_role) y el contador "usos" se
-- toca solo via incrementar_uso_cuenta() (security definer). Asi nadie
-- desde el cliente puede alterar codigos/nombres/naturaleza del PUC.

-- ------------------------------------------------------------
-- asientos
-- ------------------------------------------------------------
alter table asientos enable row level security;

drop policy if exists "asientos_select_modulo" on asientos;
create policy "asientos_select_modulo" on asientos
  for select
  to authenticated
  using (tiene_modulo('finanzas'));

drop policy if exists "asientos_insert_modulo" on asientos;
create policy "asientos_insert_modulo" on asientos
  for insert
  to authenticated
  with check (tiene_modulo('finanzas'));

drop policy if exists "asientos_update_modulo" on asientos;
create policy "asientos_update_modulo" on asientos
  for update
  to authenticated
  using (tiene_modulo('finanzas'))
  with check (tiene_modulo('finanzas'));
-- Sin policy de DELETE: no hay borrado fisico de asientos. Corregir =
-- estado='anulado' (queda en asiento_bitacora).

-- ------------------------------------------------------------
-- asiento_lineas
-- ------------------------------------------------------------
alter table asiento_lineas enable row level security;

drop policy if exists "asiento_lineas_select_modulo" on asiento_lineas;
create policy "asiento_lineas_select_modulo" on asiento_lineas
  for select
  to authenticated
  using (tiene_modulo('finanzas'));

drop policy if exists "asiento_lineas_insert_modulo" on asiento_lineas;
create policy "asiento_lineas_insert_modulo" on asiento_lineas
  for insert
  to authenticated
  with check (tiene_modulo('finanzas'));

drop policy if exists "asiento_lineas_update_modulo" on asiento_lineas;
create policy "asiento_lineas_update_modulo" on asiento_lineas
  for update
  to authenticated
  using (tiene_modulo('finanzas'))
  with check (tiene_modulo('finanzas'));
-- Sin policy de DELETE directo: coherente con no borrar asientos.

-- ------------------------------------------------------------
-- asiento_bitacora (solo anadir + leer; nunca editar ni borrar)
-- ------------------------------------------------------------
alter table asiento_bitacora enable row level security;

drop policy if exists "asiento_bitacora_select_modulo" on asiento_bitacora;
create policy "asiento_bitacora_select_modulo" on asiento_bitacora
  for select
  to authenticated
  using (tiene_modulo('finanzas'));

drop policy if exists "asiento_bitacora_insert_modulo" on asiento_bitacora;
create policy "asiento_bitacora_insert_modulo" on asiento_bitacora
  for insert
  to authenticated
  with check (tiene_modulo('finanzas'));
-- Sin policy de UPDATE ni DELETE: la bitacora es de solo anadir
-- (append-only) para authenticated. El trigger que la alimenta es
-- security definer, asi que escribe aunque el flujo venga acotado.
