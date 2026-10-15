-- MAGANDHI · C1 cuentas de cliente: identidad separada y RLS
begin;

create temp table cc_resultados (ok boolean, prueba text);
create or replace function pg_temp.chk(cond boolean, nombre text) returns void language plpgsql as $$
begin insert into cc_resultados values (coalesce(cond, false), nombre); end $$;

create or replace function pg_temp.valor_como(uid uuid, q text) returns text language plpgsql as $$
declare v text;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into v;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return 'ERROR:' || sqlerrm;
end $$;

create or replace function pg_temp.error_como(uid uuid, q text) returns text language plpgsql as $$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q;
  execute 'reset role';
  return 'SIN ERROR';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;

create or replace function pg_temp.error_postgres(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then return sqlerrm; end $$;

do $$
declare
  u_cliente constant uuid := '7ec10000-0000-4000-8000-000000000001';
  u_otro    constant uuid := '7ec10000-0000-4000-8000-000000000002';
  u_personal constant uuid := '7ec10000-0000-4000-8000-000000000003';
  u_cascada constant uuid := '7ec10000-0000-4000-8000-000000000004';
  c_cliente uuid;
  c_cascada uuid;
  p_cascada uuid;
begin
  insert into auth.users (id, email) values
    (u_cliente, 'cliente-c1@local.invalid'),
    (u_otro, 'otro-c1@local.invalid'),
    (u_personal, 'personal-c1@local.invalid'),
    (u_cascada, 'cascada-c1@local.invalid');
  insert into perfiles (id, rol, modulos) values (u_personal, 'prueba', '{ventas}');

  insert into clientes (nombre, correo) values ('Cliente C1', 'cliente-c1@local.invalid') returning id into c_cliente;
  insert into clientes (nombre, correo) values ('Cliente cascada C1', 'cascada-c1@local.invalid') returning id into c_cascada;
  insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en)
    values (u_cliente, c_cliente, now()), (u_cascada, c_cascada, now());
  insert into pedidos (customer_id, total)
    values (c_cascada, 12345) returning id into p_cascada;

  perform pg_temp.chk((select relrowsecurity from pg_class where oid = 'cuentas_cliente'::regclass), 'cuentas_cliente tiene RLS');
  perform pg_temp.chk(has_table_privilege('authenticated', 'cuentas_cliente', 'select'), 'authenticated alcanza SELECT con RLS');
  perform pg_temp.chk(not has_table_privilege('authenticated', 'cuentas_cliente', 'insert,update,delete'), 'authenticated no escribe el puente');
  perform pg_temp.chk(not has_table_privilege('anon', 'cuentas_cliente', 'select'), 'anon no lee cuentas');
  perform pg_temp.chk(has_function_privilege('authenticated', 'mi_cliente_id()', 'execute') and not has_function_privilege('anon', 'mi_cliente_id()', 'execute'), 'mi_cliente_id solo para sesion');

  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select count(*)::text from cuentas_cliente') = '1', 'cliente lee solo su puente');
  perform pg_temp.chk(pg_temp.valor_como(u_otro, 'select count(*)::text from cuentas_cliente') = '0', 'otra cuenta no lee puentes ajenos');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select mi_cliente_id()::text') = c_cliente::text, 'customer_id se deriva en servidor');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select es_cuenta_cliente()::text') = 'true', 'cliente activo se reconoce como cliente');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select es_personal_interno()::text') = 'false', 'cliente nunca es personal');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, $q$select tiene_modulo('ventas')::text$q$) = 'false', 'cliente no hereda modulos internos');
  perform pg_temp.chk(pg_temp.valor_como(u_personal, 'select es_personal_interno()::text') = 'true', 'personal conserva su identidad interna');
  perform pg_temp.chk(pg_temp.valor_como(u_personal, 'select es_cuenta_cliente()::text') = 'false', 'personal no se vuelve cliente');
  perform pg_temp.chk(pg_temp.valor_como(u_personal, 'select count(*)::text from cuentas_cliente') = '0', 'personal no enumera cuentas cliente');

  update cuentas_cliente set estado = 'bloqueada', actualizado = now() where auth_user_id = u_cliente;
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select es_cuenta_cliente()::text') = 'false', 'cuenta bloqueada no habilita superficie cliente');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, $q$select coalesce(mi_cliente_id()::text, 'NULO')$q$) = 'NULO', 'cuenta bloqueada no deriva customer_id');
  update cuentas_cliente set estado = 'cerrada', actualizado = now() where auth_user_id = u_cliente;
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select es_cuenta_cliente()::text') = 'false', 'cuenta cerrada no habilita superficie cliente');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, $q$select coalesce(mi_cliente_id()::text, 'NULO')$q$) = 'NULO', 'cuenta cerrada no deriva customer_id');
  update cuentas_cliente set estado = 'activa', actualizado = now() where auth_user_id = u_cliente;

  perform pg_temp.chk(pg_temp.error_como(u_cliente, $q$insert into cuentas_cliente(auth_user_id) values ('7ec10000-0000-4000-8000-000000000002')$q$) like 'permission denied%', 'cliente no crea puentes');
  perform pg_temp.chk(pg_temp.error_como(u_cliente, $q$update cuentas_cliente set estado='cerrada' where auth_user_id='7ec10000-0000-4000-8000-000000000001'$q$) like 'permission denied%', 'cliente no altera su estado');
  perform pg_temp.chk(pg_temp.error_como(u_cliente, $q$delete from cuentas_cliente where auth_user_id='7ec10000-0000-4000-8000-000000000001'$q$) like 'permission denied%', 'cliente no borra su puente');
  perform pg_temp.chk(pg_temp.valor_como(u_cliente, 'select count(*)::text from clientes') = '0', 'cliente no lee la tabla interna clientes');
  perform pg_temp.chk(pg_temp.error_como(u_cliente, $q$select crear_pedido(p_nombre=>'x', p_items=>'[]'::jsonb)$q$) like 'Acceso denegado%', 'cliente no llama crear_pedido interno');

  perform pg_temp.chk(pg_temp.error_postgres(format('insert into perfiles(id,rol,modulos) values (%L,%L,%L)', u_cliente, 'prueba', '{}')) = 'CC_IDENTIDAD_ES_CLIENTE', 'un cliente no puede recibir perfil interno');
  perform pg_temp.chk(pg_temp.error_postgres(format('insert into cuentas_cliente(auth_user_id) values (%L)', u_personal)) = 'CC_IDENTIDAD_ES_PERSONAL', 'personal no puede ser cuenta cliente con el mismo UID');

  delete from auth.users where id = u_cascada;
  perform pg_temp.chk(not exists(select 1 from cuentas_cliente where auth_user_id = u_cascada), 'borrar Auth elimina solo el puente');
  perform pg_temp.chk(exists(select 1 from clientes where id = c_cascada), 'cerrar acceso conserva el cliente comercial');
  perform pg_temp.chk(exists(select 1 from pedidos where id = p_cascada and customer_id = c_cascada), 'cerrar acceso conserva pedido y customer_id historicos');
end $$;

select 'RESUMEN' as tipo, count(*) || ' comprobaciones' as prueba,
       count(*) filter (where not ok) || ' fallan' as resultado
  from cc_resultados
union all
select case when ok then 'pasa' else 'FALLA' end, prueba, case when ok then 'ok' else 'FALLA' end
  from cc_resultados
order by 1, 2;

do $$ begin
  if exists (select 1 from cc_resultados where not ok) then
    raise exception 'FALLA C1 cuentas cliente';
  end if;
end $$;

rollback;
