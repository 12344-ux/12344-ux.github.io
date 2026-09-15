-- ============================================================
-- Magandhi Corporation · Modulo Inventario · Stock derivado (vista)
-- El stock NUNCA es un dato guardado: se DERIVA sumando el libro de
-- movimientos por producto. Mismo patron que saldos_cuenta en Finanzas: si el
-- libro cambia, el stock cambia solo. Imposible desincronizar.
--
-- SEGURIDAD: la vista NO usa security definer. Hereda la RLS de sus tablas
-- base (productos, movimientos_inventario), ambas protegidas por
-- tiene_modulo('inventario'). Al ser SECURITY INVOKER, quien no tenga el
-- modulo no ve filas, igual que las vistas del Libro Mayor de Finanzas.
--
-- SIGNO POR TIPO: entrada/ajuste_entrada suman; salida/ajuste_salida restan.
-- cantidad es siempre positiva (lo garantiza el check de la tabla), asi que
-- la vista solo aplica el signo segun el tipo, sin logica de cantidades
-- negativas. left join para que un producto sin movimientos exista con
-- existencias = 0 (coalesce).
--
-- IDEMPOTENTE: create or replace view.
-- ============================================================

create or replace view stock_actual as
select
  p.id    as product_id,
  p.sku   as sku,
  p.nombre as nombre,
  coalesce(sum(
    case m.tipo
      when 'entrada'        then  m.cantidad
      when 'ajuste_entrada' then  m.cantidad
      when 'salida'         then -m.cantidad
      when 'ajuste_salida'  then -m.cantidad
    end
  ), 0)::integer as existencias
from productos p
  left join movimientos_inventario m on m.product_id = p.id
group by p.id, p.sku, p.nombre;

comment on view stock_actual is 'Existencias por producto DERIVADAS del libro de movimientos (nunca un dato guardado). entrada/ajuste_entrada suman; salida/ajuste_salida restan; cantidad siempre positiva. SECURITY INVOKER: hereda la RLS de productos/movimientos_inventario (tiene_modulo(inventario)). Un producto sin movimientos aparece con existencias 0. Las existencias pueden ser negativas si se registro una salida sin stock (senal honesta de reconciliacion, no se bloquea).';
