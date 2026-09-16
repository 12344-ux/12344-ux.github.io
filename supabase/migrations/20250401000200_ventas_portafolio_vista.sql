-- ============================================================
-- Magandhi Corporation · Area de Ventas · Vista portafolio_metricas (metricas derivadas)
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO: las metricas del Portafolio de clientes (ultima
-- compra, numero de pedidos, total gastado) NO se guardan: se DERIVAN de pedidos
-- por cliente, igual que stock_actual deriva del libro de Inventario
-- (PLANO-VENTAS §1.8). Al ser derivada es IMPOSIBLE desincronizar: si se anula
-- un pedido, la metrica cambia sola, no hay un contador que actualizar.
--
-- QUE HACE: define la vista portafolio_metricas, una fila por cliente con:
--   - ultima_compra = max(fecha_orden) de sus pedidos NO anulados.
--   - num_pedidos   = conteo de sus pedidos NO anulados.
--   - total_gastado = coalesce(sum(total),0)::bigint de sus pedidos NO anulados.
-- El left join con filtro anulado=false en la condicion del join (no en un
-- where) conserva a los clientes SIN pedidos (o con todos anulados): salen con
-- ultima_compra NULL, num_pedidos 0 y total_gastado 0.
--
-- SOLO EL DATO OBJETIVO, NO LA SALUD (regla de identidad de Impulse): esta vista
-- entrega cifras crudas (frecuencia, recencia, gasto) y NO las interpreta. Decir
-- si un cliente esta "sano", "en riesgo" o "dormido" es trabajo del Analisis
-- Cluster futuro (en Marketing), que leera estas mismas tablas. Aqui no hay
-- etiquetas de opinion.
--
-- SEGURIDAD INVOKER: la vista se declara con (security_invoker = true) (Postgres
-- 15+), coherente con como Inventario dejo stock_actual. Asi HEREDA la RLS de
-- sus tablas base (clientes / pedidos): no evade el candado, ejecuta con los
-- permisos de quien consulta, no de quien creo la vista. La RLS de esas tablas
-- se define en 20250401000300_ventas_rls.sql (tiene_acceso_ventas()).
--
-- IDEMPOTENTE: create or replace view (re-ejecutar solo actualiza la definicion).
-- REQUISITO: correr DESPUES de 20250401000000_ventas_clientes.sql y
-- 20250401000100_ventas_pedidos.sql.
-- ============================================================

create or replace view portafolio_metricas
  with (security_invoker = true)
as
select
  c.id                              as customer_id,
  c.nombre                          as nombre,
  max(p.fecha_orden)                as ultima_compra,
  count(p.id)                       as num_pedidos,
  coalesce(sum(p.total), 0)::bigint as total_gastado
from clientes c
  left join pedidos p
    on p.customer_id = c.id
   and p.anulado = false
group by c.id, c.nombre;

comment on view portafolio_metricas is 'Metricas OBJETIVAS del Portafolio, una fila por cliente, DERIVADAS de pedidos no anulados (nunca se guardan; imposible desincronizar): ultima_compra=max(fecha_orden), num_pedidos=conteo, total_gastado=sum(total) bigint. Filtrable (ej. quien compro mas el ultimo mes). NO interpreta la salud del cliente (eso es el Cluster futuro). SECURITY INVOKER: hereda la RLS de clientes/pedidos.';
