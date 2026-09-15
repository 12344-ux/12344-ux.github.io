-- ============================================================
-- Magandhi Corporation · Puente de LECTURA Inventario -> Marketing
-- ------------------------------------------------------------
-- El Area de Marketing (Marketing Project -> Proyeccion de la demanda) LEE el
-- libro de inventario (movimientos_inventario, filas tipo='salida') y el
-- catalogo (productos) para proyectar la demanda EN EL CLIENTE. El calculo es
-- solo lectura: no crea ninguna RPC ni superficie de escritura nueva.
--
-- PROBLEMA QUE RESUELVE: las tablas del modulo Inventario tienen RLS de
-- inventario (ver 20250301000300_inventario_rls.sql). Un usuario SOLO de
-- marketing quedaria bloqueado al leer el libro. Este archivo ANADE una
-- politica SELECT extra que ADEMAS permite leer movimientos_inventario y
-- productos cuando el usuario tiene acceso al Area de Marketing. Es la opcion
-- mas simple y con mejor UX: no obliga a mezclar permisos de dos areas para una
-- tarea de solo lectura, y mantiene el candado real en los datos.
--
-- CONVENCION DE CLAVES (misma historia panel <-> core <-> datos): el panel y
-- marketing-core razonan con las claves del Area/Sub-area de Marketing
-- ('marketing', 'marketing-project'). Para que la receta del dueno de dar
-- '{marketing}' a un analista funcione de punta a punta, este puente acepta
-- CUALQUIERA de esas dos claves via tiene_acceso_marketing() (definida abajo).
-- Asi la visibilidad de la UI y el candado de lectura cuentan lo mismo.
--
-- ESTRICTAMENTE DE LECTURA: solo policies FOR SELECT. NO toca INSERT/UPDATE/
-- DELETE. El alta y la edicion del libro y del catalogo siguen pasando SOLO
-- por las RPC security definer de Inventario (inv_registrar_movimiento /
-- inv_crear_producto / inv_editar_producto). Marketing nunca escribe.
--
-- CITA A CIEGAS (filosofia del dueno): Inventario y Marketing se hablan por el
-- DATO (el libro), no por codigo. Este puente solo abre la puerta de LECTURA;
-- no acopla la logica de las dos areas.
--
-- IDEMPOTENTE: drop policy if exists + create policy + create or replace fn, y
-- las tablas ya tienen RLS habilitada por 20250301000300 (se re-asegura por si
-- se corre suelto).
-- REQUISITO: correr DESPUES de 20250301000000_inventario_productos.sql,
-- 20250301000100_inventario_movimientos.sql y 20250301000300_inventario_rls.sql.
-- ============================================================

-- ------------------------------------------------------------
-- tiene_acceso_marketing(): clave de acceso del Area de Marketing.
-- Envuelve tiene_modulo() y acepta las dos claves equivalentes del area
-- (area + sub-area) para que el puente de lectura hable el MISMO idioma que el
-- panel y marketing-core. admin ve todo (lo resuelve tiene_modulo). Clonable.
-- ------------------------------------------------------------
create or replace function tiene_acceso_marketing()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('marketing')
      or tiene_modulo('marketing-project');
$$;

comment on function tiene_acceso_marketing() is 'Acceso al Area de Marketing: true si el usuario tiene la clave del area (marketing) o la de la sub-area (marketing-project), o si es admin. Envuelve tiene_modulo() para que el puente de lectura, el panel y marketing-core hablen la misma convencion de claves.';

-- ------------------------------------------------------------
-- productos: SELECT adicional para el Area de Marketing.
-- Convive con productos_select_modulo (acceso de inventario): en RLS, basta con
-- que UNA politica permisiva de SELECT sea verdadera.
-- ------------------------------------------------------------
alter table productos enable row level security;

drop policy if exists "productos_select_marketing" on productos;
create policy "productos_select_marketing" on productos
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- ------------------------------------------------------------
-- movimientos_inventario: SELECT adicional para el modulo 'marketing'.
-- Marketing lee este libro (tipo='salida' por periodo) para proyectar la
-- demanda. Solo lectura; el libro es append-only via RPC (no se toca aqui).
-- ------------------------------------------------------------
alter table movimientos_inventario enable row level security;

drop policy if exists "movimientos_inventario_select_marketing" on movimientos_inventario;
create policy "movimientos_inventario_select_marketing" on movimientos_inventario
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- Sin politicas de INSERT/UPDATE/DELETE: este archivo NO concede escritura a
-- nadie. Marketing es un consumidor de solo lectura del libro de Inventario.
