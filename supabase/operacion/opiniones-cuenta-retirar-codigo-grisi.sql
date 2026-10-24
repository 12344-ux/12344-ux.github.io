-- ============================================================================
-- MAGANDHI · Opiniones con cuenta · retirar la opinión vieja de Grisi (ESCRIBE)
-- ----------------------------------------------------------------------------
-- Decisión del dueño (24-oct-2026): la opinión de Grisi Manzanilla Gold se
-- escribió con el código de reseña (modelo anterior). Se retira para que el
-- dueño opine con su cuenta y pruebe el flujo nuevo con una compra real.
--
-- No borra en silencio: copia la fila completa a opiniones_historial con el
-- motivo y la quita de opiniones. Sale de la tienda y del promedio, y la cuenta
-- dueña del pedido vuelve a poder opinar.
--
-- Se detiene SIN CAMBIAR NADA si no encuentra exactamente una opinión con
-- código de ese producto, o si su pedido no está entregado o no pertenece a
-- una cuenta activa. Correrlo dos veces no hace nada la segunda vez: falla con
-- OP_RETIRO_ESPERABA_UNA_OPINION_CON_CODIGO.
--
-- Devuelve UNA fila. Esperado:
--   retirada = true · quedan_con_codigo = 0 · cuenta_puede_opinar = true
--   nombre_publico = tu nombre e inicial (por ejemplo «Maicol R.»)
-- ============================================================================
begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

do $$
declare
  v_producto uuid;
  v_ids uuid[];
  v_estado text;
  v_anulado boolean;
  v_cuenta uuid;
begin
  if to_regprocedure('public.op__retirar_opinion(uuid,uuid,text)') is null then
    raise exception using errcode = 'P0001', message = 'OP_RETIRO_MIGRACION_NO_APLICADA';
  end if;

  select cp.product_id_ref
    into v_producto
    from public.campana_producto cp
   where cp.slug = 'grisi-manzanilla-gold'
     and cp.product_id_ref is not null
   order by cp.publicado desc, cp.id
   limit 1;
  if v_producto is null then
    raise exception using errcode = 'P0001', message = 'OP_RETIRO_PRODUCTO_NO_ENCONTRADO';
  end if;

  select array_agg(o.id order by o.creado)
    into v_ids
    from public.opiniones o
   where o.product_id = v_producto
     and o.origen = 'codigo';
  if coalesce(array_length(v_ids, 1), 0) <> 1 then
    raise exception using errcode = 'P0001',
      message = 'OP_RETIRO_ESPERABA_UNA_OPINION_CON_CODIGO',
      detail = format('Encontradas: %s', coalesce(array_length(v_ids, 1), 0));
  end if;

  select p.estado, p.anulado, cc.auth_user_id
    into v_estado, v_anulado, v_cuenta
    from public.opiniones o
    join public.pedidos p on p.id = o.pedido_id
    left join public.cuentas_cliente cc
      on cc.customer_id = p.customer_id
     and cc.estado = 'activa'
   where o.id = v_ids[1];
  if v_estado is distinct from 'entregado' or v_anulado then
    raise exception using errcode = 'P0001', message = 'OP_RETIRO_PEDIDO_NO_ENTREGADO';
  end if;
  if v_cuenta is null then
    raise exception using errcode = 'P0001', message = 'OP_RETIRO_PEDIDO_SIN_CUENTA';
  end if;

  perform public.op__retirar_opinion(
    v_ids[1], null,
    'operacion: opinion con codigo reemplazada por opinion con cuenta (decision del dueno 24-oct-2026)'
  );
end;
$$;

commit;

with retiro as (
  select h.opinion_id, (h.datos->>'pedido_id')::uuid as pedido_id,
         (h.datos->>'product_id')::uuid as product_id, h.creado
    from public.opiniones_historial h
   where h.evento = 'retiro'
     and h.motivo like 'operacion: opinion con codigo reemplazada%'
   order by h.creado desc
   limit 1
),
cuenta as (
  select cc.auth_user_id, p.customer_id, r.product_id
    from retiro r
    join public.pedidos p on p.id = r.pedido_id
    join public.cuentas_cliente cc
      on cc.customer_id = p.customer_id
     and cc.estado = 'activa'
)
select
  exists (select 1 from retiro) as retirada,
  (select count(*)
     from public.opiniones o
     join retiro r on r.product_id = o.product_id
    where o.origen = 'codigo')::integer as quedan_con_codigo,
  coalesce((
    select not exists (
             select 1
               from public.opiniones o
               join public.pedidos p on p.id = o.pedido_id
              where p.customer_id = c.customer_id
                and o.product_id = c.product_id
           )
       and exists (
             select 1
               from public.pedidos p
               join public.pedido_items pi on pi.pedido_id = p.id
              where p.customer_id = c.customer_id
                and pi.product_id = c.product_id
                and p.estado = 'entregado'
                and not p.anulado
           )
      from cuenta c
     limit 1
  ), false) as cuenta_puede_opinar,
  (select public.op__nombre_publico_cuenta(c.auth_user_id) from cuenta c limit 1) as nombre_publico,
  (select to_char(r.creado at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI') from retiro r) as retirada_colombia;
