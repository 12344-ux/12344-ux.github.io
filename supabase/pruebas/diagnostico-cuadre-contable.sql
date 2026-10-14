-- ============================================================
-- MAGANDHI / Impulse · DIAGNÓSTICO DEL CUADRE CONTABLE (solo lectura)
-- ------------------------------------------------------------
-- Dice QUÉ HAY DE VERDAD en los libros antes de registrar los asientos de
-- cuadre del 14-oct-2026: el seguro de Dropi (755), el capital de los dos
-- shampoos (95.410), la recarga de Dropi (50.000) y la liquidación de Wompi.
--
-- Solo SELECT: no crea, no cambia ni borra nada.
-- Uso: Supabase → SQL Editor → pegar COMPLETO → Run → copiar la tabla.
-- ============================================================
with
-- Saldo por cuenta, solo asientos ACTIVOS (los anulados no cuentan).
sal as (
  select l.cuenta_codigo,
         sum(l.debe)::bigint                   as debe,
         sum(l.haber)::bigint                  as haber,
         (sum(l.debe) - sum(l.haber))::bigint  as neto
    from asiento_lineas l
    join asientos a on a.id = l.asiento_id
   where a.estado = 'activo'
   group by l.cuenta_codigo
),
-- Clases para el cuadre del balance.
clase as (
  select
    coalesce(sum(neto)              filter (where cuenta_codigo like '1%'), 0) as activo,
    coalesce(sum(-neto)             filter (where cuenta_codigo like '2%'), 0) as pasivo,
    coalesce(sum(-neto)             filter (where cuenta_codigo like '3%'), 0) as patrimonio,
    coalesce(sum(-neto)             filter (where cuenta_codigo like '4%'), 0) as ingresos,
    coalesce(sum(neto)              filter (where cuenta_codigo similar to '(5|6|7)%'), 0) as costos_gastos,
    coalesce(sum(debe), 0)  as total_debe,
    coalesce(sum(haber), 0) as total_haber
  from sal
),
-- Plata líquida: banco + caja + lo que tienen terceros por nosotros.
plata as (
  select
    coalesce((select neto from sal where cuenta_codigo = '111005'), 0) as banco,
    coalesce((select sum(neto) from sal where cuenta_codigo like '1105%'), 0) as caja,
    coalesce((select neto from sal where cuenta_codigo = '138095'), 0) as wompi_por_liquidar,
    coalesce((select neto from sal where cuenta_codigo = '138010'), 0) as saldo_dropi
),
d(n, seccion, concepto, valor, nota) as (

  -- ---------------- A · Configuración ----------------
  select 1, 'A · Config', 'Entorno de pagos',
         coalesce((select entorno from pagos_config where id = 1), 'sin fila'),
         'prod = cobra dinero real'
  union all
  select 2, 'A · Config', 'IVA de ventas configurado',
         coalesce((select iva_ventas_pct::text from contabilidad_config where id = 1), 'sin fila'),
         '0 = no responsable de IVA'
  union all
  select 3, 'A · Config', 'Cuentas del asiento automático',
         coalesce((select 'banco ' || c.cuenta_banco || ' · ingreso ' || c.cuenta_ingreso ||
                          ' · costo ' || c.cuenta_costo || ' · inv ' || c.cuenta_inventario ||
                          ' · pasarela ' || c.cuenta_pasarela || ' · comisión ' || c.cuenta_comision ||
                          ' · Dropi ' || c.cuenta_saldo_proveedor || ' · flete ' || c.cuenta_flete
                     from contabilidad_config c where c.id = 1), 'sin fila'),
         'informativo'

  -- ---------------- B · Saldos de las cuentas clave ----------------
  union all
  select 10 + r.ord, 'B · Saldos en libros',
         r.cod || ' ' || coalesce(pc.nombre, '«NO EXISTE EN EL PUC»'),
         case when s.cuenta_codigo is null then 'sin movimiento'
              else '$' || to_char(s.neto, 'FM999G999G999') ||
                   '   (D ' || to_char(s.debe, 'FM999G999G999') ||
                   ' / H ' || to_char(s.haber, 'FM999G999G999') || ')' end,
         r.que
    from (values
      (1, '111005', 'banco · lo que llegó de Wompi'),
      (2, '110505', 'caja general'),
      (3, '138095', 'Wompi por liquidar · 0 = todo conciliado'),
      (4, '138010', 'saldo en Dropi · debe igual al del panel'),
      (5, '143505', 'inventario en libros'),
      (6, '310505', 'capital · aportes del dueño'),
      (7, '311505', 'capital · cuotas o partes de interés social'),
      (8, '413505', 'ingresos por venta'),
      (9, '613505', 'costo de la mercancía vendida'),
      (10, '523535', 'fletes'),
      (11, '530515', 'comisiones de la pasarela'),
      (12, '529595', 'otros gastos diversos de ventas')
    ) as r(ord, cod, que)
    left join sal s on s.cuenta_codigo = r.cod
    left join puc_cuentas pc on pc.codigo = r.cod

  -- ---------------- C · Cuadre del libro ----------------
  union all
  select 30, 'C · Cuadre', 'Partida doble: total debe vs total haber',
         (select '$' || to_char(total_debe, 'FM999G999G999') || ' vs $' ||
                 to_char(total_haber, 'FM999G999G999') ||
                 case when total_debe = total_haber then '  ✓ cuadra' else '  ✗ DESCUADRADO' end
            from clase),
         'iguales siempre'
  union all
  select 31, 'C · Cuadre', 'Activo vs Pasivo + Patrimonio + Resultado',
         (select '$' || to_char(activo, 'FM999G999G999') || ' vs $' ||
                 to_char(pasivo + patrimonio + (ingresos - costos_gastos), 'FM999G999G999') ||
                 case when activo = pasivo + patrimonio + (ingresos - costos_gastos)
                      then '  ✓ cuadra' else '  ✗ DESCUADRADO' end
            from clase),
         'iguales en un libro sano'
  union all
  select 32, 'C · Cuadre', 'Resultado del ejercicio (ingresos − costos − gastos)',
         (select '$' || to_char(ingresos - costos_gastos, 'FM999G999G999') ||
                 '   (ingresos $' || to_char(ingresos, 'FM999G999G999') ||
                 ' − costos/gastos $' || to_char(costos_gastos, 'FM999G999G999') || ')'
            from clase),
         'informativo'
  union all
  select 33, 'C · Cuadre', 'PLATA que los libros dicen que MAGANDHI tiene',
         (select '$' || to_char(banco + caja + wompi_por_liquidar + saldo_dropi, 'FM999G999G999') ||
                 '   (banco ' || to_char(banco, 'FM999G999G999') ||
                 ' + caja ' || to_char(caja, 'FM999G999G999') ||
                 ' + Wompi ' || to_char(wompi_por_liquidar, 'FM999G999G999') ||
                 ' + Dropi ' || to_char(saldo_dropi, 'FM999G999G999') || ')'
            from plata),
         'comparar con el banco y el panel de Dropi'

  -- ---------------- D · Libro Diario completo ----------------
  union all
  select 100 + row_number() over (order by a.fecha, a.creado, l.orden, l.cuenta_codigo),
         'D · Libro Diario',
         to_char(a.fecha, 'YYYY-MM-DD') || ' · ' || a.descripcion ||
           case when a.estado <> 'activo' then '  [' || upper(a.estado) || ']' else '' end ||
           case when coalesce(a.origen, '') <> '' then '  («' || a.origen || '»)' else '' end,
         l.cuenta_codigo ||
           case when l.debe > 0 then '   DEBE  $' || to_char(l.debe, 'FM999G999G999')
                else '   HABER $' || to_char(l.haber, 'FM999G999G999') end,
         coalesce(l.detalle, '')
    from asientos a
    join asiento_lineas l on l.asiento_id = a.id

  -- ---------------- E · Pedidos ----------------
  union all
  select 500 + row_number() over (order by p.fecha_orden, p.creado),
         'E · Pedidos',
         to_char(p.fecha_orden, 'YYYY-MM-DD') || ' · ' || p.canal ||
           ' · ' || p.estado || case when p.anulado then '  [ANULADO]' else '' end,
         '$' || to_char(p.total, 'FM999G999G999') || '   ' ||
           coalesce((select string_agg(pr.nombre || ' ×' || i.cantidad || ' (' || pr.origen || ')', ' + ')
                       from pedido_items i join productos pr on pr.id = i.product_id
                      where i.pedido_id = p.id), 'sin items'),
         case when exists (select 1 from asientos a
                            where a.estado = 'activo' and a.origen = 'venta_web'
                              and a.origen_ref = p.id)
              then 'con asiento automático' else 'SIN asiento' end
    from pedidos p

  -- ---------------- F · Despachos de proveedor ----------------
  union all
  select 700 + row_number() over (order by r.creado),
         'F · Proveedor (Dropi)',
         'pedido Dropi ' || coalesce(r.pedido_externo_id, '«sin transcribir»') ||
           ' · ' || coalesce(r.destino_ciudad, '?') || ', ' || coalesce(r.destino_departamento, '?'),
         'costo $' || coalesce(to_char(r.costo_real, 'FM999G999G999'), 'FALTA') ||
           ' · flete $' || coalesce(to_char(r.flete, 'FM999G999G999'), 'FALTA') ||
           ' · cantidad ' || r.cantidad,
         'la tabla NO tiene columna para el SEGURO: ' || coalesce(r.notas, 'sin notas')
    from pedido_proveedor r

  -- ---------------- G · Inventario ----------------
  union all
  select 900, 'G · Inventario', 'En libros (1435) vs en bodega (stock × costo)',
         'libros $' || to_char(coalesce((select sum(neto) from sal where cuenta_codigo like '1435%'), 0), 'FM999G999G999') ||
         '  vs bodega $' || to_char(coalesce((select sum(greatest(s.existencias, 0)::bigint * p.costo_unitario)
                                               from productos p join stock_actual s on s.product_id = p.id
                                              where p.activo and p.costo_unitario is not null), 0), 'FM999G999G999'),
         'iguales si el inventario ya está en libros'
  union all
  select 901 + row_number() over (order by p.sku),
         'G · Inventario',
         p.sku || ' · ' || p.nombre || ' (' || p.origen || ')',
         'stock ' || coalesce(s.existencias::text, '0') ||
           ' · costo unit. ' || coalesce('$' || to_char(p.costo_unitario, 'FM999G999G999'), 'SIN COSTO') ||
           ' · valor $' || to_char(coalesce(greatest(s.existencias, 0)::bigint * coalesce(p.costo_unitario, 0), 0), 'FM999G999G999'),
         'informativo'
    from productos p
    left join stock_actual s on s.product_id = p.id
   where p.activo and not coalesce(p.es_placeholder, false)
)
select n, seccion, concepto, valor, nota from d order by n;
