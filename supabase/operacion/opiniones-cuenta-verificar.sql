-- ============================================================================
-- MAGANDHI · Opiniones con cuenta · verificación (SOLO LECTURA)
-- ----------------------------------------------------------------------------
-- Correr en el SQL Editor DESPUÉS de aplicar
-- 20261117000000_opiniones_cuenta.sql. No escribe nada.
--
-- Si responde «function ... does not exist» o «column ... does not exist», la
-- migración no está aplicada.
--
-- Devuelve UNA fila. Esperado antes de retirar la opinión vieja de Grisi:
--   migracion_aplicada = true
--   opiniones_con_codigo = 1
--   opiniones_con_cuenta = 0
--   pedido_entregado = true
--   pedido_de_una_cuenta = true
--   nombre_publico = tu nombre e inicial (por ejemplo «Maicol R.»)
--   listo_para_retirar = true
-- ============================================================================
with producto as (
  select cp.product_id_ref as product_id
    from public.campana_producto cp
   where cp.slug = 'grisi-manzanilla-gold'
     and cp.product_id_ref is not null
   order by cp.publicado desc, cp.id
   limit 1
),
con_codigo as (
  select o.id, o.pedido_id, o.creado
    from public.opiniones o
    join producto pr on pr.product_id = o.product_id
   where o.origen = 'codigo'
),
detalle as (
  select c.id, c.creado, p.estado, p.anulado, cc.auth_user_id
    from con_codigo c
    join public.pedidos p on p.id = c.pedido_id
    left join public.cuentas_cliente cc
      on cc.customer_id = p.customer_id
     and cc.estado = 'activa'
)
select
  to_regclass('public.opiniones_historial') is not null
    and to_regprocedure('public.op_cuenta_opiniones()') is not null
    and to_regprocedure('public.op_cuenta_opinar(uuid,integer,text)') is not null
    and to_regprocedure('public.op_cuenta_retirar_opinion(uuid)') is not null
    as migracion_aplicada,
  (select count(*) from producto) = 1 as producto_encontrado,
  (select count(*) from con_codigo)::integer as opiniones_con_codigo,
  (select count(*)
     from public.opiniones o
     join producto pr on pr.product_id = o.product_id
    where o.origen = 'cuenta')::integer as opiniones_con_cuenta,
  coalesce((select bool_and(d.estado = 'entregado' and not d.anulado) from detalle d), false)
    as pedido_entregado,
  coalesce((select bool_and(d.auth_user_id is not null) from detalle d), false)
    as pedido_de_una_cuenta,
  (select public.op__nombre_publico_cuenta(d.auth_user_id)
     from detalle d
    where d.auth_user_id is not null
    limit 1) as nombre_publico,
  (select to_char(d.creado at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI')
     from detalle d
    limit 1) as opinion_vieja_creada_colombia,
  (select count(*) from con_codigo) = 1
    and coalesce((select bool_and(d.estado = 'entregado' and not d.anulado and d.auth_user_id is not null) from detalle d), false)
    as listo_para_retirar;
