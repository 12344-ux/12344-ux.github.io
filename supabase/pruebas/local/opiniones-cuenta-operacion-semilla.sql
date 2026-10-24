-- ============================================================================
-- Semilla CI · SQL operativos de opiniones con cuenta
-- Reproduce el caso de producción: una opinión con código sobre Grisi
-- Manzanilla Gold, en un pedido entregado de un cliente ligado a una cuenta de
-- Google. Se confirma (commit) porque los SQL operativos corren en sesiones
-- aparte; pg.sh recrea la base en cada corrida.
-- ============================================================================
begin;
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('0e100000-0000-4000-8000-000000000001', 'dueno-op@local.invalid', now(),
   '{"full_name":"Dueño Prueba","name":"Dueño Prueba","given_name":"Dueño","family_name":"Prueba"}');
insert into clientes (id, nombre, correo) values
  ('0e200000-0000-4000-8000-000000000001', 'Dueño', 'dueno-op@local.invalid');
insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en) values
  ('0e100000-0000-4000-8000-000000000001', '0e200000-0000-4000-8000-000000000001', now());
insert into pedidos (id, customer_id, total, estado) values
  ('0e500000-0000-4000-8000-000000000001', '0e200000-0000-4000-8000-000000000001', 69900, 'entregado');
insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
select '0e500000-0000-4000-8000-000000000001', cp.product_id_ref, 1, 69900, 69900
  from campana_producto cp
 where cp.slug = 'grisi-manzanilla-gold';
select public.op_registrar_opinion(
  (select codigo_resena from pedidos where id = '0e500000-0000-4000-8000-000000000001'),
  'grisi-manzanilla-gold', 5, 'Opinión del modelo anterior', 'Dueño', false
);
commit;
select 'semilla de la operación de opiniones lista' as estado;
