-- MAGANDHI · C2 cuentas de cliente: confirmacion, vinculo e idempotencia
begin;

create temp table cc2_resultados (ok boolean, prueba text);
create or replace function pg_temp.chk(cond boolean, nombre text) returns void language plpgsql as $$
begin insert into cc2_resultados values (coalesce(cond, false), nombre); end $$;

create or replace function pg_temp.rpc_como(uid uuid) returns text language plpgsql as $$
declare v text;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select cc_inicializar_cuenta()::text into v;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return 'ERROR:' || sqlerrm;
end $$;

do $$
declare
  u_no_confirmado constant uuid := '7ec20000-0000-4000-8000-000000000001';
  u_cero          constant uuid := '7ec20000-0000-4000-8000-000000000002';
  u_crudo         constant uuid := '7ec20000-0000-4000-8000-000000000003';
  u_norm          constant uuid := '7ec20000-0000-4000-8000-000000000004';
  u_ambiguo       constant uuid := '7ec20000-0000-4000-8000-000000000005';
  u_dueno         constant uuid := '7ec20000-0000-4000-8000-000000000006';
  u_ya_vinculado  constant uuid := '7ec20000-0000-4000-8000-000000000007';
  u_personal      constant uuid := '7ec20000-0000-4000-8000-000000000008';
  u_bloqueada     constant uuid := '7ec20000-0000-4000-8000-000000000009';
  u_cerrada       constant uuid := '7ec20000-0000-4000-8000-000000000010';
  c_crudo uuid := '7ec21000-0000-4000-8000-000000000001';
  c_norm uuid := '7ec21000-0000-4000-8000-000000000002';
  c_amb_1 uuid := '7ec21000-0000-4000-8000-000000000003';
  c_amb_2 uuid := '7ec21000-0000-4000-8000-000000000004';
  c_vinculado uuid := '7ec21000-0000-4000-8000-000000000005';
  v_crudo text;
  v_norm text;
  v_cero text;
  v_ambiguo text;
  v_vinculado text;
  v_proc record;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (u_no_confirmado, 'no-confirmado-c2@local.invalid', null),
    (u_cero, 'sin-historia-c2@local.invalid', now()),
    (u_crudo, '  HISTORICO-CRUDO-C2@LOCAL.INVALID  ', now()),
    (u_norm, 'historico-norm-c2@local.invalid', now()),
    (u_ambiguo, 'ambiguo-c2@local.invalid', now()),
    (u_dueno, 'dueno-c2@local.invalid', now()),
    (u_ya_vinculado, 'vinculado-c2@local.invalid', now()),
    (u_personal, 'personal-c2@local.invalid', now()),
    (u_bloqueada, 'bloqueada-c2@local.invalid', now()),
    (u_cerrada, 'cerrada-c2@local.invalid', now());

  insert into clientes (id, nombre, correo, correo_norm) values
    (c_crudo, 'Historico por crudo', ' Historico-Crudo-C2@Local.Invalid ', null),
    (c_norm, 'Historico por norm', 'correo-anterior@local.invalid', ' HISTORICO-NORM-C2@LOCAL.INVALID '),
    (c_amb_1, 'Ambiguo norm', 'otro-amb-1@local.invalid', 'ambiguo-c2@local.invalid'),
    (c_amb_2, 'Ambiguo crudo', ' AMBIGUO-C2@LOCAL.INVALID ', 'otro-amb-2@local.invalid'),
    (c_vinculado, 'Ya vinculado', 'vinculado-c2@local.invalid', 'vinculado-c2@local.invalid');

  insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en)
    values (u_dueno, c_vinculado, now());
  insert into cuentas_cliente (auth_user_id, estado)
    values (u_bloqueada, 'bloqueada'), (u_cerrada, 'cerrada');
  insert into perfiles (id, rol, modulos) values (u_personal, 'prueba', '{}');

  select proc.prosecdef, proc.pronargs, proc.proconfig
    into v_proc
    from pg_proc proc join pg_namespace n on n.oid = proc.pronamespace
   where n.nspname = 'public' and proc.proname = 'cc_inicializar_cuenta';
  perform pg_temp.chk(v_proc.prosecdef and v_proc.pronargs = 0 and v_proc.proconfig @> array['search_path=public'], 'RPC sin parametros, SECURITY DEFINER y search_path fijo');
  perform pg_temp.chk(has_function_privilege('authenticated', 'cc_inicializar_cuenta()', 'execute'), 'authenticated ejecuta la unica puerta C2');
  perform pg_temp.chk(not has_function_privilege('anon', 'cc_inicializar_cuenta()', 'execute'), 'anon no ejecuta la puerta C2');
  perform pg_temp.chk(not has_table_privilege('authenticated', 'cc_conflictos_revision', 'select,insert,update,delete'), 'authenticated no accede a revision privada');
  perform pg_temp.chk(not has_table_privilege('anon', 'cc_conflictos_revision', 'select'), 'anon no accede a revision privada');
  perform pg_temp.chk(not has_table_privilege('service_role', 'cc_conflictos_revision', 'select,insert,update,delete'), 'service_role tampoco accede directamente a revision privada');

  perform pg_temp.chk(pg_temp.rpc_como(u_no_confirmado) = 'ERROR:CC_CORREO_NO_CONFIRMADO', 'correo sin confirmar no crea cuenta');
  perform pg_temp.chk(not exists(select 1 from cuentas_cliente where auth_user_id = u_no_confirmado), 'rechazo sin confirmar no deja puente');
  perform pg_temp.chk(pg_temp.rpc_como(u_personal) = 'ERROR:CC_IDENTIDAD_ES_PERSONAL', 'un perfil interno no abre cuenta cliente');

  v_cero := pg_temp.rpc_como(u_cero);
  perform pg_temp.chk(v_cero not like 'ERROR:%' and exists(select 1 from cuentas_cliente where auth_user_id=u_cero and customer_id is null), 'cero coincidencias crea cuenta sin customer_id');
  perform pg_temp.chk(not exists(select 1 from cc_conflictos_revision where auth_user_id=u_cero), 'cero coincidencias no inventa conflicto');

  v_crudo := pg_temp.rpc_como(u_crudo);
  perform pg_temp.chk(exists(select 1 from cuentas_cliente where auth_user_id=u_crudo and customer_id=c_crudo and vinculado_en is not null), 'vincula coincidencia unica usando ventas_norm_correo(correo crudo)');
  perform pg_temp.chk(pg_temp.rpc_como(u_crudo) = v_crudo and (select count(*) from cuentas_cliente where auth_user_id=u_crudo)=1, 'doble llamada es idempotente');

  v_norm := pg_temp.rpc_como(u_norm);
  perform pg_temp.chk(exists(select 1 from cuentas_cliente where auth_user_id=u_norm and customer_id=c_norm), 'vincula coincidencia unica usando ventas_norm_correo(correo_norm)');

  v_ambiguo := pg_temp.rpc_como(u_ambiguo);
  perform pg_temp.chk(exists(select 1 from cuentas_cliente where auth_user_id=u_ambiguo and customer_id is null), 'dos clientes por correo crean cuenta sin customer_id');
  perform pg_temp.chk(exists(select 1 from cc_conflictos_revision where auth_user_id=u_ambiguo and motivo='correo_ambiguo' and coincidencias=2 and customer_id_candidato is null and estado='pendiente'), 'ambiguedad queda en revision privada sin correo');

  v_vinculado := pg_temp.rpc_como(u_ya_vinculado);
  perform pg_temp.chk(exists(select 1 from cuentas_cliente where auth_user_id=u_ya_vinculado and customer_id is null), 'cliente ya vinculado no se roba y la cuenta queda sin customer_id');
  perform pg_temp.chk(exists(select 1 from cuentas_cliente where auth_user_id=u_dueno and customer_id=c_vinculado), 'el vinculo historico previo queda intacto');
  perform pg_temp.chk(exists(select 1 from cc_conflictos_revision where auth_user_id=u_ya_vinculado and motivo='cliente_ya_vinculado' and customer_id_candidato=c_vinculado), 'cliente ya vinculado queda en revision privada');

  perform pg_temp.chk(pg_temp.rpc_como(u_bloqueada) = 'ERROR:CC_CUENTA_NO_DISPONIBLE' and (select estado from cuentas_cliente where auth_user_id=u_bloqueada)='bloqueada', 'una cuenta bloqueada conserva historia pero no abre sesion publica');
  perform pg_temp.chk(pg_temp.rpc_como(u_cerrada) = 'ERROR:CC_CUENTA_NO_DISPONIBLE' and (select estado from cuentas_cliente where auth_user_id=u_cerrada)='cerrada', 'una cuenta cerrada conserva historia pero no abre sesion publica');

  perform pg_temp.chk(
    (v_cero::jsonb = v_crudo::jsonb and v_crudo::jsonb = v_norm::jsonb and v_norm::jsonb = v_ambiguo::jsonb and v_ambiguo::jsonb = v_vinculado::jsonb)
    and v_cero::jsonb = '{"ok":true,"estado":"lista"}'::jsonb,
    'respuesta opaca identica para cero, unico, ambiguo y ya vinculado');
  perform pg_temp.chk(
    v_crudo !~* '7ec|@|customer|correo|coincid|conflicto|vinculad',
    'respuesta no contiene UUID, correo ni senales de historia');
end $$;

select 'RESUMEN' as tipo, count(*) || ' comprobaciones' as prueba,
       count(*) filter (where not ok) || ' fallan' as resultado
  from cc2_resultados
union all
select case when ok then 'pasa' else 'FALLA' end, prueba, case when ok then 'ok' else 'FALLA' end
  from cc2_resultados
order by 1, 2;

do $$ begin
  if exists (select 1 from cc2_resultados where not ok) then
    raise exception 'FALLA C2 cuentas cliente';
  end if;
end $$;

rollback;
