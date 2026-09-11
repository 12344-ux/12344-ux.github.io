-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Balance de comprobacion (A FECHA DE CORTE)
-- ------------------------------------------------------------------------
-- QUE ES: el Balance de comprobacion es la "foto" del Libro Mayor a una
-- fecha de corte. Para cada cuenta IMPUTABLE con movimiento acumula el
-- total al DEBE, el total al HABER y presenta el saldo repartido en dos
-- columnas: saldo_deudor y saldo_acreedor. Es el primer paso del Tramo 2
-- (informes) y se deriva de las MISMAS tablas base que alimentan la vista
-- saldos_cuenta (asientos, asiento_lineas, puc_cuentas): no reinventa el
-- calculo, lo extiende con un corte por fecha.
--
-- POR QUE FUNCION Y NO VISTA: una vista no acepta parametros, y este
-- informe NECESITA un parametro de fecha de corte (p_fecha_corte) para
-- producir la foto acumulada "hasta esa fecha". saldos_cuenta hace el mismo
-- calculo de saldo por naturaleza pero SIN corte (toma todo el historico
-- activo); aqui se agrega el filtro a.fecha <= p_fecha_corte. Por eso se
-- modela como funcion de tabla y no como otra vista.
--
-- CORTE POR FECHA / EXCLUYE ANULADOS: solo cuenta lineas de asientos con
-- estado='activo' (los anulados nunca cuentan para el mayor ni los saldos)
-- y con a.fecha <= p_fecha_corte (foto acumulada hasta el corte, inclusive).
--
-- MONTOS: todo en bigint (pesos colombianos enteros, sin centavos). NUNCA
-- float/numeric: se mantiene la decision de montos del modulo (ver
-- 20250201000200_finanzas_asientos.sql). Los sum() se castean a ::bigint.
--
-- REPARTO DEUDOR / ACREEDOR (por que es contablemente correcto): se calcula
-- el neto neto_debe_haber = sum(debe) - sum(haber) de la cuenta y se reparte:
--   * si neto_debe_haber >= 0  ->  saldo_deudor  = neto_debe_haber, saldo_acreedor = 0
--   * si neto_debe_haber <  0  ->  saldo_acreedor = -neto_debe_haber, saldo_deudor  = 0
-- Es el mismo criterio de saldo por naturaleza de saldos_cuenta, presentado
-- en dos columnas: una cuenta de naturaleza 'debito' con movimiento normal
-- tendra neto>0 y por tanto saldo_deudor (su lado natural); una de naturaleza
-- 'credito' tendra neto<0 y por tanto saldo_acreedor (su lado natural). Se
-- expone tambien la columna naturaleza para que el frontend pueda mostrarla y
-- resaltar anomalias (p.ej. una cuenta debito que cae en saldo_acreedor).
-- CUADRE POR CONSTRUCCION: como cada linea entra en el DEBE o en el HABER y el
-- reparto solo redistribuye el mismo neto sin crear ni perder pesos, se cumple
--   sum(saldo_deudor) - sum(saldo_acreedor) = sum(debe) - sum(haber)
-- y en un libro cuadrado (partida doble: sum(debe)=sum(haber)) el lado derecho
-- es 0, luego sum(saldo_deudor) = sum(saldo_acreedor) y sum(total_debe) =
-- sum(total_haber). Esa es exactamente la comprobacion de cuadre del balance.
--
-- SEGURIDAD: la funcion se define STABLE (solo lee) y SECURITY INVOKER (por
-- defecto), igual que las vistas movimientos_mayor / saldos_cuenta que NO son
-- security definer. Asi hereda la RLS de las tablas base: se ejecuta con los
-- privilegios del usuario `authenticated`, de modo que el candado
-- tiene_modulo('finanzas') sobre asientos/asiento_lineas/puc_cuentas se aplica
-- al llamarla. Quien no tenga el modulo no obtiene filas. NO abre ninguna
-- escritura (INSERT/UPDATE/DELETE), NO toca RLS y NO usa secretos/service_role.
--
-- IDEMPOTENTE: `create or replace function` y `grant` son idempotentes; este
-- archivo se puede re-ejecutar sin duplicar nada. Si se ajusta la logica,
-- basta con volver a ejecutar SOLO este archivo.
-- ============================================================

create or replace function balance_comprobacion(p_fecha_corte date)
returns table (
  cuenta_codigo  text,
  cuenta_nombre  text,
  naturaleza     text,
  total_debe     bigint,
  total_haber    bigint,
  saldo_deudor   bigint,
  saldo_acreedor bigint
)
language sql
stable
as $$
  select
    c.codigo                            as cuenta_codigo,
    c.nombre                            as cuenta_nombre,
    c.naturaleza                        as naturaleza,
    coalesce(sum(l.debe),  0)::bigint   as total_debe,
    coalesce(sum(l.haber), 0)::bigint   as total_haber,
    -- neto = debe - haber. Si es >= 0 el saldo es deudor; si es < 0, acreedor.
    case
      when coalesce(sum(l.debe), 0) - coalesce(sum(l.haber), 0) >= 0
        then coalesce(sum(l.debe), 0) - coalesce(sum(l.haber), 0)
      else 0
    end::bigint                         as saldo_deudor,
    case
      when coalesce(sum(l.debe), 0) - coalesce(sum(l.haber), 0) < 0
        then coalesce(sum(l.haber), 0) - coalesce(sum(l.debe), 0)
      else 0
    end::bigint                         as saldo_acreedor
  from puc_cuentas c
    join asiento_lineas l on l.cuenta_codigo = c.codigo
    join asientos a       on a.id = l.asiento_id
                         and a.estado = 'activo'
                         and a.fecha <= p_fecha_corte
  where c.imputable = true
  group by c.codigo, c.nombre, c.naturaleza
  order by c.codigo;
$$;

comment on function balance_comprobacion(date) is 'Balance de comprobacion a fecha de corte: por cada cuenta IMPUTABLE con movimiento (asientos activos con fecha <= corte) devuelve total_debe, total_haber y el saldo repartido en saldo_deudor/saldo_acreedor segun el neto debe-haber. Deriva de las mismas tablas que saldos_cuenta; en un libro cuadrado sum(saldo_deudor)=sum(saldo_acreedor) y sum(total_debe)=sum(total_haber). STABLE + SECURITY INVOKER: hereda RLS tiene_modulo(finanzas). Montos bigint (pesos enteros).';

-- GRANT EXECUTE explicito a `authenticated`. Coherencia con la nota de
-- 20250201000700_finanzas_grants.sql: las funciones otorgan EXECUTE a PUBLIC
-- por defecto, asi que hoy este grant es tecnicamente redundante. Se deja
-- EXPLICITO por claridad (el frontend lo invoca via RPC como usuario
-- authenticated) y como defensa a futuro: si algun dia se hace
-- `revoke execute ... from public`, este grant deja intacto el acceso del
-- modulo. Idempotente. No abre escritura ni toca RLS.
grant execute on function balance_comprobacion(date) to authenticated;
