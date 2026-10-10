-- ============================================================
-- Impulse · Los dias se cuentan en Colombia, no en UTC
-- ------------------------------------------------------------
-- La base corre en UTC. Entre las 7 p. m. y la medianoche de Colombia ya es
-- "manana" para la base, asi que cualquier resta que mezcle `current_date`
-- (UTC) con una fecha en hora de Colombia da un dia de mas. El bug vivio en
-- EM2 y EM5.1 hasta el 10-oct-2026 y solo se delataba en esas cinco horas.
--
-- Estas comprobaciones NO dependen de la hora a la que se corran: son el
-- guardian para que la clase entera de bug no vuelva a entrar.
-- SOLO LOCAL; no escribe nada que sobreviva.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

begin;

-- ------------------------------------------------------------------
-- 1. EL GUARDIAN: ninguna funcion puede mezclar las dos zonas
-- ------------------------------------------------------------------
-- Si una funcion menciona `current_date` Y ademas `America/Bogota`, casi con
-- seguridad esta restando una fecha UTC de una fecha de Colombia. Es el patron
-- exacto que tenian em__perfil_base y em__perfil_email.
select pg_temp.chk(
  not exists (
    select 1
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and not exists (select 1 from pg_depend d
                        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
       and p.prosrc like '%current_date%'
       and p.prosrc like '%America/Bogota%'
  ),
  'GUARDIAN: ninguna funcion de public mezcla current_date (UTC) con America/Bogota');

-- Y si alguna lo hiciera, que se vea cual:
select pg_temp.chk(true, 'funciones que mezclan: ' || coalesce((
  select string_agg(p.proname, ', ' order by p.proname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc like '%current_date%' and p.prosrc like '%America/Bogota%'), 'ninguna'));

-- ------------------------------------------------------------------
-- 2. Las tres funciones corregidas, una por una
-- ------------------------------------------------------------------
select pg_temp.chk(
  pg_get_functiondef('em__perfil_base(date,date)'::regprocedure) not like '%current_date%',
  'em__perfil_base ya no usa current_date (dias_desde_ultima_compra)');
select pg_temp.chk(
  pg_get_functiondef('em__perfil_email()'::regprocedure) not like '%current_date%',
  'em__perfil_email ya no usa current_date (dias_desde_ultimo_clic)');
select pg_temp.chk(
  pg_get_functiondef('em__segmento_where(jsonb)'::regprocedure) not like '%current_date%',
  'em__segmento_where ya no usa current_date (dias_en_lista)');

-- Las tres SI cuentan en Colombia.
select pg_temp.chk(
  pg_get_functiondef('em__perfil_base(date,date)'::regprocedure) like '%America/Bogota%'
  and pg_get_functiondef('em__perfil_email()'::regprocedure) like '%America/Bogota%'
  and pg_get_functiondef('em__segmento_where(jsonb)'::regprocedure) like '%America/Bogota%',
  'las tres cuentan el dia en America/Bogota');

-- ------------------------------------------------------------------
-- 3. dias_en_lista: la expresion que se inyecta en el WHERE
-- ------------------------------------------------------------------
-- em__segmento_where arma el WHERE como TEXTO, asi que se puede leer sin
-- ejecutar nada. Los DOS lados de la resta deben ir en hora de Colombia.
select pg_temp.chk(
  em__segmento_where('{"modo":"y","reglas":[{"campo":"dias_en_lista","op":"gte","valor":"0"}]}'::jsonb)
    not like '%current_date%',
  'dias_en_lista: el WHERE generado no trae current_date');
select pg_temp.chk(
  (select count(*) from regexp_matches(
     em__segmento_where('{"modo":"y","reglas":[{"campo":"dias_en_lista","op":"gte","valor":"0"}]}'::jsonb),
     'America/Bogota', 'g')) = 2,
  'dias_en_lista: los DOS lados de la resta van en Colombia');

-- ------------------------------------------------------------------
-- 4. La aritmetica del bug, con momentos fijos (no depende de la hora)
-- ------------------------------------------------------------------
-- Momento: 10-oct 01:00 UTC = 9-oct 20:00 en Colombia.
-- Clic:    10-oct 00:00 UTC = 9-oct 19:00 en Colombia, o sea HOY, hace 1 hora.
select pg_temp.chk(
  ('2026-10-10 01:00+00'::timestamptz at time zone 'UTC')::date
    - ('2026-10-10 00:00+00'::timestamptz at time zone 'America/Bogota')::date = 1,
  'asi se calculaba antes: un clic de hace 1 hora daba «hace 1 dia»');
select pg_temp.chk(
  ('2026-10-10 01:00+00'::timestamptz at time zone 'America/Bogota')::date
    - ('2026-10-10 00:00+00'::timestamptz at time zone 'America/Bogota')::date = 0,
  'asi se calcula ahora: el mismo clic da 0 dias');

-- A mediodia de Colombia las dos formas coincidian: por eso el bug se escondia.
select pg_temp.chk(
  ('2026-10-09 17:00+00'::timestamptz at time zone 'UTC')::date
    = ('2026-10-09 17:00+00'::timestamptz at time zone 'America/Bogota')::date,
  'a mediodia de Colombia ambas formas coinciden (por eso pasaba inadvertido)');

-- El caso que mas dolería: 31 de diciembre a las 8 p. m. en Colombia.
select pg_temp.chk(
  ('2027-01-01 01:00+00'::timestamptz at time zone 'UTC')::date
    <> ('2027-01-01 01:00+00'::timestamptz at time zone 'America/Bogota')::date,
  'el 31-dic a las 8 p. m. de Colombia, UTC ya cambio de ANO');

-- ------------------------------------------------------------------
-- 5. Sin regresion: lo que ya estaba bien sigue bien
-- ------------------------------------------------------------------
select pg_temp.chk(
  (select fz__fecha_colombia('2026-10-10 01:00+00'::timestamptz)) = '2026-10-09'::date,
  'sin regresion: fz__fecha_colombia (F3) sigue dando el dia de Colombia');
select pg_temp.chk(
  not has_function_privilege('authenticated', 'em__perfil_base(date,date)'::regprocedure, 'execute')
  and not has_function_privilege('anon', 'em__perfil_email()'::regprocedure, 'execute')
  and not has_function_privilege('authenticated', 'em__segmento_where(jsonb)'::regprocedure, 'execute'),
  'sin regresion: las tres siguen siendo nucleo interno (sin grant)');
-- mk_perfiles_clientes (el clúster) consume las dos funciones corregidas. No se
-- ejecuta aqui porque exige acceso de Marketing (eso ya lo cubre
-- em5-1-respuesta-email.sql); se comprueba que el enganche siga en pie.
select pg_temp.chk(
  pg_get_functiondef('mk_perfiles_clientes(date,date)'::regprocedure) like '%em__perfil_base%'
  and pg_get_functiondef('mk_perfiles_clientes(date,date)'::regprocedure) like '%em__perfil_email%',
  'sin regresion: el clúster sigue consumiendo las dos funciones corregidas');

-- Metricas ya lo hacia bien desde M1: que siga asi.
select pg_temp.chk(
  pg_get_functiondef('mt_en_vivo()'::regprocedure) not like '%current_date%',
  'sin regresion: Metricas En vivo sigue sin current_date');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
