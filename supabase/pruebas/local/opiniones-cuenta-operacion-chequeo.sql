-- ============================================================================
-- Chequeo CI · después de opiniones-cuenta-retirar-codigo-grisi.sql
-- Confirma que la opinión con código salió de la tienda, quedó en el
-- historial y que la cuenta dueña del pedido puede opinar con su nombre.
-- ============================================================================
begin;

create temp table op_oper_resultados (ok boolean, prueba text);
create or replace function pg_temp.chk(cond boolean, nombre text) returns void language plpgsql as $$
begin insert into op_oper_resultados values (coalesce(cond, false), nombre); end $$;

create or replace function pg_temp.json_como(uid uuid, q text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into v;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('error', sqlerrm);
end $$;

do $$
declare
  u_dueno constant uuid := '0e100000-0000-4000-8000-000000000001';
  v_campana uuid;
  v_producto uuid;
  snap jsonb;
begin
  select cp.id, cp.product_id_ref into v_campana, v_producto
    from campana_producto cp where cp.slug = 'grisi-manzanilla-gold';

  perform pg_temp.chk(not exists (select 1 from opiniones o where o.product_id = v_producto and o.origen = 'codigo'), 'la opinión con código ya no está en opiniones');
  perform pg_temp.chk((select count(*) from opiniones_historial h where h.evento = 'retiro' and h.actor is null and h.motivo like 'operacion: opinion con codigo reemplazada%' and (h.datos->>'product_id')::uuid = v_producto) = 1, 'el historial guarda la fila retirada con su motivo');
  perform pg_temp.chk((select count(*) from opiniones_publicas where slug = 'grisi-manzanilla-gold') = 0, 'la tienda ya no la muestra');

  snap := pg_temp.json_como(u_dueno, 'select public.op_cuenta_opiniones()');
  perform pg_temp.chk(snap->>'nombre_publico' = 'Dueño P.', 'la cuenta aparecerá como «Dueño P.»');
  perform pg_temp.chk((select x->>'estado' from jsonb_array_elements(snap->'productos') x where x->>'campana_id' = v_campana::text) = 'pendiente', 'la cuenta dueña del pedido puede volver a opinar');

  snap := pg_temp.json_como(u_dueno, format('select public.op_cuenta_opinar(%L, 5, %L)', v_campana, 'Ahora con mi cuenta'));
  perform pg_temp.chk((select count(*) from opiniones_publicas where slug = 'grisi-manzanilla-gold' and autor_nombre = 'Dueño P.') = 1, 'la nueva opinión con cuenta sale en la tienda');
end $$;

select 'RESUMEN' as tipo, count(*) || ' comprobaciones' as prueba,
       count(*) filter (where not ok) || ' fallan' as resultado
  from op_oper_resultados
union all
select case when ok then 'pasa' else 'FALLA' end, prueba, case when ok then 'ok' else 'FALLA' end
  from op_oper_resultados
order by 1, 2;

do $$ begin
  if exists (select 1 from op_oper_resultados where not ok) then
    raise exception 'FALLA operación de opiniones con cuenta';
  end if;
end $$;

rollback;
