-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Estado de resultados (POR PERIODO)
-- ------------------------------------------------------------------------
-- QUE ES: el Estado de resultados es la "pelicula" del ejercicio ENTRE DOS
-- FECHAS (p_inicio y p_fin, ambas inclusive). A diferencia del Balance de
-- comprobacion (que es una FOTO acumulada a una fecha de corte), este informe
-- mira SOLO el movimiento del periodo de las cuentas de RESULTADO (clases 4,
-- 5, 6 y 7) para calcular la utilidad o perdida del ejercicio. Es el paso 2a
-- del Tramo 2 (informes) y se deriva de las MISMAS tablas base que alimentan
-- el Libro Mayor (asientos, asiento_lineas, puc_cuentas): no reinventa el
-- calculo, lo acota a un rango de fechas y a las cuentas de resultado.
--
-- DIFERENCIA vs BALANCE DE COMPROBACION: el balance filtra a.fecha <= corte
-- (foto acumulada) e incluye TODAS las clases imputables. Aqui se filtra
--   a.fecha >= p_inicio AND a.fecha <= p_fin   (pelicula entre dos fechas)
-- y solo las clases de RESULTADO 4, 5, 6 y 7 (se excluyen a proposito las
-- clases de balance 1 activo, 2 pasivo y 3 patrimonio, que no forman parte del
-- estado de resultados).
--
-- MODELO CONTABLE (por naturaleza de cada clase). Cada clase se presenta en su
-- LADO NATURAL en positivo, tomando solo el movimiento del periodo:
--   * INGRESOS (clase 4, natural credito):        monto_periodo = sum(haber) - sum(debe)
--   * GASTOS (clase 5, natural debito):           monto_periodo = sum(debe)  - sum(haber)
--   * COSTO DE VENTAS (clase 6, natural debito):  monto_periodo = sum(debe)  - sum(haber)
--   * COSTOS DE PRODUCCION (clase 7, natural debito): monto_periodo = sum(debe) - sum(haber)
-- Asi una linea de ingreso normal sale POSITIVA y una de gasto/costo normal
-- tambien sale POSITIVA (cada una en su columna). NO se voltea ninguna cuenta
-- que corra contra-natura: se aplica la formula del lado natural de la clase,
-- de modo que una anomalia (p.ej. una devolucion en ventas que arrastra la
-- clase 4 hacia el debe) aparece en NEGATIVO y queda visible para revisarla.
--
-- UTILIDAD (o PERDIDA) DEL EJERCICIO:
--   utilidad = Ingresos(clase 4) - Costos(clase 6 + clase 7) - Gastos(clase 5)
-- Si el resultado es positivo hay UTILIDAD; si es negativo, PERDIDA. La misma
-- formula equivale a sumar cada fila con su contribucion con signo (ingresos
-- suman, costos y gastos restan), porque monto_periodo ya viene en el lado
-- natural de cada clase.
--
-- POR QUE ES CORRECTO / POR QUE IMPORTA: como cada clase se presenta en su
-- lado natural en positivo y la utilidad reutiliza EXACTAMENTE esos mismos
-- montos enteros, el resultado es exacto (no hay redondeos). Esta utilidad del
-- ejercicio alimentara despues el PATRIMONIO del Balance General (paso 2b), por
-- eso debe ser exacta: cualquier diferencia de un peso se arrastraria al
-- balance.
--
-- MONTOS: todo en bigint (pesos colombianos enteros, sin centavos). NUNCA
-- float/numeric: se mantiene la decision de montos del modulo (ver
-- 20250201000200_finanzas_asientos.sql). Los sum() se castean a ::bigint.
--
-- CLASE DERIVADA: puc_cuentas NO tiene columna `clase`; la clase se deriva del
-- primer digito del codigo con left(c.codigo, 1) (igual criterio que el resto
-- del modulo). Solo cuentas IMPUTABLES (de detalle) entran al informe.
--
-- CORTE POR FECHA / EXCLUYE ANULADOS: solo cuenta lineas de asientos con
-- estado='activo' (los anulados nunca cuentan para el mayor ni los informes) y
-- con a.fecha entre p_inicio y p_fin (ambas inclusive).
--
-- SEGURIDAD: la funcion se define STABLE (solo lee) y SECURITY INVOKER (por
-- defecto), igual que balance_comprobacion y que las vistas movimientos_mayor
-- / saldos_cuenta que NO son security definer. Asi hereda la RLS de las tablas
-- base: se ejecuta con los privilegios del usuario `authenticated`, de modo que
-- el candado tiene_modulo('finanzas') sobre asientos/asiento_lineas/puc_cuentas
-- se aplica al llamarla. Quien no tenga el modulo no obtiene filas. NO abre
-- ninguna escritura (INSERT/UPDATE/DELETE), NO toca RLS y NO usa
-- secretos/service_role.
--
-- IDEMPOTENTE: `create or replace function` y `grant` son idempotentes; este
-- archivo se puede re-ejecutar sin duplicar nada. Si se ajusta la logica,
-- basta con volver a ejecutar SOLO este archivo.
-- ============================================================

create or replace function estado_resultados(p_inicio date, p_fin date)
returns table (
  clase         text,
  cuenta_codigo text,
  cuenta_nombre text,
  naturaleza    text,
  total_debe    bigint,
  total_haber   bigint,
  monto_periodo bigint
)
language sql
stable
as $$
  select
    left(c.codigo, 1)                   as clase,
    c.codigo                            as cuenta_codigo,
    c.nombre                            as cuenta_nombre,
    c.naturaleza                        as naturaleza,
    coalesce(sum(l.debe),  0)::bigint   as total_debe,
    coalesce(sum(l.haber), 0)::bigint   as total_haber,
    -- monto del periodo en el LADO NATURAL de la clase:
    --   clase 4 (ingresos, credito): haber - debe
    --   clases 5, 6, 7 (gastos/costos, debito): debe - haber
    case left(c.codigo, 1)
      when '4' then coalesce(sum(l.haber), 0) - coalesce(sum(l.debe),  0)
      else          coalesce(sum(l.debe),  0) - coalesce(sum(l.haber), 0)
    end::bigint                         as monto_periodo
  from puc_cuentas c
    join asiento_lineas l on l.cuenta_codigo = c.codigo
    join asientos a       on a.id = l.asiento_id
                         and a.estado = 'activo'
                         and a.fecha >= p_inicio
                         and a.fecha <= p_fin
  where c.imputable = true
    and left(c.codigo, 1) in ('4', '5', '6', '7')
  group by left(c.codigo, 1), c.codigo, c.nombre, c.naturaleza
  order by c.codigo;
$$;

comment on function estado_resultados(date, date) is 'Estado de resultados POR PERIODO (Tramo 2, paso 2a): pelicula entre p_inicio y p_fin (inclusive) de las cuentas de resultado (clases 4/5/6/7). Por cada cuenta imputable con movimiento devuelve clase (left(codigo,1)), cuenta_codigo, cuenta_nombre, naturaleza, total_debe, total_haber y monto_periodo en el lado natural de la clase (ingresos 4 = haber-debe; gastos 5 y costos 6/7 = debe-haber). Utilidad del ejercicio = Ingresos(4) - Costos(6+7) - Gastos(5); positivo utilidad, negativo perdida. Esta utilidad alimenta luego el patrimonio del Balance General (paso 2b). STABLE + SECURITY INVOKER: hereda RLS tiene_modulo(finanzas). Montos bigint (pesos enteros).';

-- GRANT EXECUTE explicito a `authenticated` (misma razon que en
-- balance_comprobacion, ver 20250201000900). Las funciones otorgan EXECUTE a
-- PUBLIC por defecto, asi que hoy es tecnicamente redundante; se deja EXPLICITO
-- por claridad (el frontend lo invoca via RPC como usuario authenticated) y
-- como defensa a futuro. Idempotente. No abre escritura ni toca RLS.
grant execute on function estado_resultados(date, date) to authenticated;
