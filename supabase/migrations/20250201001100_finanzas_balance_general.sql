-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Balance General / Estado de Situacion Financiera (A FECHA DE CORTE)
-- ------------------------------------------------------------------------
-- QUE ES: el Balance General (o Estado de Situacion Financiera) es la "foto"
-- de lo que la empresa TIENE y DEBE a una fecha de corte. Se organiza en dos
-- bloques que deben cuadrar:
--     ACTIVO  =  PASIVO  +  PATRIMONIO
-- Es el paso 2b del Tramo 2 (informes) y, como el Balance de comprobacion, es
-- una FOTO ACUMULADA a una fecha de corte (no la "pelicula" entre dos fechas
-- del Estado de resultados). Se deriva de las MISMAS tablas base que el Libro
-- Mayor (asientos, asiento_lineas, puc_cuentas): no reinventa el calculo, lo
-- acota a las clases de balance y le suma el resultado del ejercicio.
--
-- QUE CLASES ENTRAN Y CON QUE FORMULA (por naturaleza de cada clase, foto
-- acumulada con a.fecha <= p_fecha_corte). Cada clase se presenta en su LADO
-- NATURAL en positivo:
--   * ACTIVO (clase 1, natural debito):      monto = sum(debe)  - sum(haber)
--   * PASIVO (clase 2, natural credito):     monto = sum(haber) - sum(debe)
--   * PATRIMONIO (clase 3, natural credito): monto = sum(haber) - sum(debe)
-- Solo cuentas IMPUTABLES (de detalle) con movimiento; la clase se deriva del
-- primer digito del codigo con left(c.codigo, 1) (puc_cuentas NO tiene columna
-- `clase`, igual criterio que el resto del modulo).
--
-- CLASES 8 Y 9 (CUENTAS DE ORDEN) FUERA DE ALCANCE A PROPOSITO: el termino de
-- balance filtra clases 1/2/3 y el termino de resultado cubre 4/5/6/7, de modo
-- que las clases 8 (deudoras de orden) y 9 (acreedoras de orden) quedan EXCLUIDAS
-- deliberadamente del Balance General. Son cuentas de MEMORANDO/orden: se
-- registran por-contra (en pares que se netean a cero dentro de su clase) y NO
-- forman parte del Activo/Pasivo/Patrimonio ni del resultado del ejercicio, por
-- lo que no afectan el cuadre ACTIVO = PASIVO + PATRIMONIO + RESULTADO. El alcance
-- 1/2/3 + 4/5/6/7 es intencional, no una omision.
--
-- RESULTADO DEL EJERCICIO (por que va en el Balance): el resultado del periodo
-- (utilidad o perdida) forma parte del PATRIMONIO. En este software NO se ha
-- implementado todavia el asiento de CIERRE ANUAL que traslada el resultado a
-- una cuenta de patrimonio (clase 3); por eso el resultado NO esta guardado en
-- ninguna cuenta clase 3 y se CALCULA y se PRESENTA como una linea aparte
-- dentro del bloque de Patrimonio. Se computa con EXACTAMENTE el mismo criterio
-- del Estado de resultados (paso 2a) para el periodo:
--     p_inicio = 1 de ENERO del ano del corte  ..  p_fin = p_fecha_corte
-- (ambas inclusive; ano fiscal = ano calendario). Los meses sin movimiento
-- suman cero: el inicio es SIEMPRE el 1-ene del ano del corte, nunca se
-- "detecta la primera operacion". Para GARANTIZAR que el numero coincide al
-- peso con el informe 2a, esta funcion LLAMA a estado_resultados(p_inicio,
-- p_fecha_corte) y agrega su monto_periodo por clase:
--     utilidad = Ingresos(clase 4) - Costos(clase 6 + clase 7) - Gastos(clase 5)
-- (estado_resultados ya entrega monto_periodo en el lado natural: clase 4 =
-- haber-debe; clases 5/6/7 = debe-haber, de modo que ingresos suman y costos y
-- gastos restan). Positivo -> utilidad; negativo -> perdida. Se emite SIEMPRE
-- una sola fila de resultado (seccion='resultado'), aunque su monto sea 0, para
-- que el frontend siempre la pueda mostrar.
--
-- POR QUE CUADRA (ACTIVO = PASIVO + PATRIMONIO + RESULTADO): en un libro de
-- partida doble cuadrado, sobre TODAS las clases se cumple sum(debe)=sum(haber),
-- luego:
--     (activo:   debe-haber)
--   - (pasivo:   haber-debe)
--   - (patrim.3: haber-debe)
--   - (ingresos4 - gastos5 - costos6/7)
--   = sum(debe) - sum(haber)  sobre todas las clases  = 0
-- es decir ACTIVO = PASIVO + PATRIMONIO(clase 3) + RESULTADO. El frontend usa
-- esa igualdad como indicador de cuadre.
--
-- CAVEAT HONESTO (cierre anual no implementado): la igualdad de arriba asume
-- que TODO el movimiento de las cuentas de resultado (clases 4/5/6/7) del libro
-- pertenece al ano del corte. Como este software AUN NO hace el asiento de
-- cierre anual (que salda las clases 4/5/6/7 contra el patrimonio al terminar
-- cada ano), si existieran movimientos de resultado de un ANO ANTERIOR al del
-- corte y sin cerrar, la ecuacion simple podria no cuadrar exactamente (ese
-- resultado viejo no estaria ni en el patrimonio clase 3 ni dentro del periodo
-- 1-ene-ano..corte que aqui se calcula). Para el uso actual de MAGANDHI
-- (empieza este ano, sin ejercicios anteriores) cuadra perfecto. El cierre
-- anual queda como funcion futura; aqui NO se implementa ningun ajuste, solo se
-- deja esta nota honesta.
--
-- MONTOS: todo en bigint (pesos colombianos enteros, sin centavos). NUNCA
-- float/numeric: se mantiene la decision de montos del modulo (ver
-- 20250201000200_finanzas_asientos.sql). Los sum() se castean a ::bigint.
--
-- CORTE POR FECHA / EXCLUYE ANULADOS: solo cuenta lineas de asientos con
-- estado='activo' (los anulados nunca cuentan para el mayor ni los informes) y
-- con a.fecha <= p_fecha_corte para las clases de balance (foto acumulada). El
-- termino de resultado hereda ese mismo filtro de estado a traves de
-- estado_resultados, acotado al periodo del ano corriente.
--
-- SEGURIDAD: la funcion se define STABLE (solo lee) y SECURITY INVOKER (por
-- defecto), igual que balance_comprobacion / estado_resultados y que las vistas
-- movimientos_mayor / saldos_cuenta que NO son security definer. Asi hereda la
-- RLS de las tablas base: se ejecuta con los privilegios del usuario
-- `authenticated`, de modo que el candado tiene_modulo('finanzas') sobre
-- asientos/asiento_lineas/puc_cuentas se aplica al llamarla (tambien a traves
-- de estado_resultados, que es igualmente SECURITY INVOKER). Quien no tenga el
-- modulo no obtiene filas. NO abre ninguna escritura (INSERT/UPDATE/DELETE), NO
-- toca RLS y NO usa secretos/service_role.
--
-- IDEMPOTENTE: `create or replace function` y `grant` son idempotentes; este
-- archivo se puede re-ejecutar sin duplicar nada. Si se ajusta la logica,
-- basta con volver a ejecutar SOLO este archivo. Requiere que ya exista la
-- funcion estado_resultados (archivo 11, 20250201001000).
-- ============================================================

create or replace function balance_general(p_fecha_corte date)
returns table (
  seccion        text,
  cuenta_codigo  text,
  cuenta_nombre  text,
  naturaleza     text,
  monto          bigint
)
language sql
stable
as $$
  -- ACTIVO / PASIVO / PATRIMONIO: foto acumulada de las clases de balance
  -- (1, 2, 3) por cuenta imputable con movimiento, hasta la fecha de corte.
  -- Cada clase en su lado natural en positivo.
  select
    case left(c.codigo, 1)
      when '1' then 'activo'
      when '2' then 'pasivo'
      else          'patrimonio'
    end                                 as seccion,
    c.codigo                            as cuenta_codigo,
    c.nombre                            as cuenta_nombre,
    c.naturaleza                        as naturaleza,
    case left(c.codigo, 1)
      when '1' then coalesce(sum(l.debe),  0) - coalesce(sum(l.haber), 0)
      else          coalesce(sum(l.haber), 0) - coalesce(sum(l.debe),  0)
    end::bigint                         as monto
  from puc_cuentas c
    join asiento_lineas l on l.cuenta_codigo = c.codigo
    join asientos a       on a.id = l.asiento_id
                         and a.estado = 'activo'
                         and a.fecha <= p_fecha_corte
  where c.imputable = true
    and left(c.codigo, 1) in ('1', '2', '3')
  group by left(c.codigo, 1), c.codigo, c.nombre, c.naturaleza

  union all

  -- RESULTADO DEL EJERCICIO: una sola fila sintetica dentro del patrimonio.
  -- Se calcula con EXACTAMENTE el criterio del Estado de resultados (2a) para
  -- el periodo [1-ene-ano del corte .. corte], llamando a estado_resultados
  -- para garantizar que coincide al peso con el informe 2a. Los meses sin
  -- movimiento suman cero (el inicio es siempre el 1-ene del ano del corte).
  -- La fila se emite SIEMPRE, aunque el monto sea 0.
  select
    'resultado'                         as seccion,
    ''                                  as cuenta_codigo,
    'Resultado del ejercicio'           as cuenta_nombre,
    ''                                  as naturaleza,
    coalesce((
      select
          coalesce(sum(er.monto_periodo) filter (where left(er.cuenta_codigo, 1) = '4'), 0)
        - coalesce(sum(er.monto_periodo) filter (where left(er.cuenta_codigo, 1) in ('6', '7')), 0)
        - coalesce(sum(er.monto_periodo) filter (where left(er.cuenta_codigo, 1) = '5'), 0)
      from estado_resultados(
             make_date(extract(year from p_fecha_corte)::int, 1, 1),
             p_fecha_corte
           ) er
    ), 0)::bigint                       as monto;
$$;

comment on function balance_general(date) is 'Balance General / Estado de Situacion Financiera a fecha de corte (Tramo 2, paso 2b): foto acumulada de las clases de balance por cuenta imputable con movimiento (asientos activos con fecha <= corte). Devuelve seccion (activo|pasivo|patrimonio|resultado), cuenta_codigo, cuenta_nombre, naturaleza y monto (bigint), en el lado natural de cada clase: activo (1) = debe-haber; pasivo (2) y patrimonio (3) = haber-debe. Agrega una unica fila seccion=resultado (Resultado del ejercicio), que NO esta guardada en clase 3 porque aun no hay cierre anual, calculada con el mismo criterio de estado_resultados para 1-ene-ano-del-corte..corte (Ingresos 4 - Costos 6+7 - Gastos 5), coincidente al peso con el informe 2a. Cuadre: ACTIVO = PASIVO + PATRIMONIO(3) + RESULTADO (en libro cuadrado del ano corriente; el cierre anual queda como funcion futura). STABLE + SECURITY INVOKER: hereda RLS tiene_modulo(finanzas). Montos bigint (pesos enteros).';

-- GRANT EXECUTE explicito a `authenticated` (misma razon que en
-- balance_comprobacion / estado_resultados, ver 20250201000900 y 20250201001000).
-- Las funciones otorgan EXECUTE a PUBLIC por defecto, asi que hoy es
-- tecnicamente redundante; se deja EXPLICITO por claridad (el frontend lo
-- invoca via RPC como usuario authenticated) y como defensa a futuro.
-- Idempotente. No abre escritura ni toca RLS.
grant execute on function balance_general(date) to authenticated;
