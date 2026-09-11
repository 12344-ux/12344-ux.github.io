-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Libro Mayor (vistas derivadas)
-- El Libro Mayor y los SALDOS NUNCA se escriben a mano: se DERIVAN de las
-- lineas del Libro Diario (asiento_lineas) que pertenezcan a asientos con
-- estado='activo'. El dueno solo alimenta el diario; el mayor se calcula.
-- Asi no hay dato duplicado ni riesgo de que el mayor se "desincronice".
--
-- ENLACE INTERNO (lo que pidio el dueno): registro en el diario -> todo
-- llega solo al lugar correcto. Estas vistas son ese "lugar correcto".
--
-- PREPARADO PARA EL TRAMO 2: el balance de comprobacion y los estados
-- financieros se derivaran de estas MISMAS vistas (total_debe, total_haber,
-- saldo por naturaleza) sin rehacer el modelo.
--
-- SEGURIDAD: las vistas heredan la RLS de sus tablas base (asientos,
-- asiento_lineas, puc_cuentas), todas protegidas por tiene_modulo('finanzas').
-- Al no usar security_definer, quien no tenga acceso al modulo no ve filas.
-- ============================================================

-- ------------------------------------------------------------
-- movimientos_mayor: una fila por cada linea de asiento ACTIVO, con el
-- contexto de la cuenta y del asiento. Es el detalle del Libro Mayor
-- (y sirve tambien como Libro Diario detallado ordenado por cuenta).
-- ------------------------------------------------------------
create or replace view movimientos_mayor as
select
  l.id            as linea_id,
  a.id            as asiento_id,
  a.fecha         as fecha,
  a.descripcion   as descripcion,
  l.cuenta_codigo as cuenta_codigo,
  c.nombre        as cuenta_nombre,
  c.naturaleza    as naturaleza,
  l.detalle       as detalle,
  l.debe          as debe,
  l.haber         as haber
from asiento_lineas l
  join asientos a     on a.id = l.asiento_id
  join puc_cuentas c  on c.codigo = l.cuenta_codigo
where a.estado = 'activo';

comment on view movimientos_mayor is 'Detalle del Libro Mayor: una fila por linea de asiento ACTIVO, con fecha, descripcion, cuenta y naturaleza. Derivado del diario; nunca se escribe a mano.';

-- ------------------------------------------------------------
-- saldos_cuenta: agrega por cuenta el total al debe, al haber y el SALDO
-- CON SIGNO segun la naturaleza de la cuenta:
--   naturaleza='debito'  -> saldo = total_debe - total_haber
--   naturaleza='credito' -> saldo = total_haber - total_debe
-- Un saldo positivo significa "saldo del lado de su naturaleza" (lo normal);
-- uno negativo, saldo contrario (util para detectar anomalias). Solo cuenta
-- asientos activos. De aqui salen el mayor por cuenta y, en TRAMO 2, el
-- balance de comprobacion y los estados financieros.
-- ------------------------------------------------------------
create or replace view saldos_cuenta as
select
  c.codigo                          as cuenta_codigo,
  c.nombre                          as cuenta_nombre,
  c.naturaleza                      as naturaleza,
  coalesce(sum(l.debe),  0)::bigint as total_debe,
  coalesce(sum(l.haber), 0)::bigint as total_haber,
  case
    when c.naturaleza = 'debito'
      then coalesce(sum(l.debe), 0) - coalesce(sum(l.haber), 0)
    else coalesce(sum(l.haber), 0) - coalesce(sum(l.debe), 0)
  end::bigint                       as saldo
from puc_cuentas c
  join asiento_lineas l on l.cuenta_codigo = c.codigo
  join asientos a       on a.id = l.asiento_id and a.estado = 'activo'
group by c.codigo, c.nombre, c.naturaleza;

comment on view saldos_cuenta is 'Saldo por cuenta derivado de los asientos ACTIVOS. saldo con signo segun naturaleza (debito: debe-haber; credito: haber-debe). Base del Libro Mayor y, en TRAMO 2, del balance de comprobacion y los estados financieros. Montos bigint (pesos enteros).';
