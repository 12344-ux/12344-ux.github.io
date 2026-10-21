-- ============================================================================
-- MAGANDHI · Promocionar P3 · banco semántico SQL local
-- ----------------------------------------------------------------------------
-- SOLO LOCAL. Prueba resolución, agregados, cuota y retención dentro de una
-- única transacción. ROLLBACK elimina fixtures, conteos y bitácora de gates.
-- ============================================================================
\set ON_ERROR_STOP on
set client_min_messages = warning;
set search_path = public, extensions, pg_temp;

create temp table p3_resultado (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p_ok boolean, p_que text)
returns void language sql as $$
  insert into pg_temp.p3_resultado(ok, que)
  values (coalesce(p_ok, false), p_que)
$$;

begin;

-- Identidad y dos campañas públicas controladas. No hay datos reales ni PII.
insert into auth.users (id, email) values
  ('73a00000-0000-4000-8000-000000000001', 'p3-banco@local.invalid');
insert into campana_producto (id, nombre, slug, publicado, activo) values
  ('73b00000-0000-4000-8000-000000000001', 'P3 producto local', 'p3-producto-local', true, true),
  ('73b00000-0000-4000-8000-000000000002', 'P3 home local', 'p3-home-local', true, true);

-- Los gates se encienden únicamente dentro de esta transacción reversible.
update promocionar_p3_config
   set activacion_habilitada = true,
       redirect_habilitado = true,
       conteo_habilitado = true,
       routing_verificado = true,
       actualizado_en = greatest(clock_timestamp(), actualizado_en + interval '1 microsecond'),
       actualizado_por = auth.uid(),
       actualizado_razon = 'banco_local_p3_habilitar',
       actualizado_rol = current_user
 where id = 1;

-- El trigger exige alta como borrador y transición posterior a activo.
insert into atribucion_enlaces (
  id, campana_producto_id, canal_promocion, source, medium,
  campaign_base, campaign, content, tipo_destino,
  clave_idempotencia, idempotencia_payload_hash, creado_por, actualizado_por
) values
  (
    '73c00000-0000-4000-8000-000000000001',
    '73b00000-0000-4000-8000-000000000001',
    'instagram', 'instagram', 'social',
    'p3-producto', 'p3-producto-261108-abcd', 'historia-uno', 'producto_v1',
    '73d00000-0000-4000-8000-000000000001', repeat('a', 64),
    '73a00000-0000-4000-8000-000000000001',
    '73a00000-0000-4000-8000-000000000001'
  ),
  (
    '73c00000-0000-4000-8000-000000000002',
    '73b00000-0000-4000-8000-000000000002',
    'email', 'email', 'email',
    'p3-home', 'p3-home-261108-efgh', null, 'home_v1',
    '73d00000-0000-4000-8000-000000000002', repeat('b', 64),
    '73a00000-0000-4000-8000-000000000001',
    '73a00000-0000-4000-8000-000000000001'
  );

update atribucion_enlaces
   set estado_enlace = 'activo',
       codigo = case id
         when '73c00000-0000-4000-8000-000000000001'::uuid then '0123456789abcdef'
         else 'fedcba9876543210'
       end,
       activado_en = greatest(clock_timestamp(), creado_en),
       activado_por = '73a00000-0000-4000-8000-000000000001',
       actualizado_en = greatest(clock_timestamp(), actualizado_en + interval '1 microsecond'),
       actualizado_por = '73a00000-0000-4000-8000-000000000001'
 where id in (
   '73c00000-0000-4000-8000-000000000001',
   '73c00000-0000-4000-8000-000000000002'
 );

-- ----------------------------------------------------------------------------
-- Resolución de lista blanca: destinos exactos derivados, nunca URL libre.
-- ----------------------------------------------------------------------------
create temp table p3_resoluciones as
select promocionar_p3_resolver('0123456789abcdef') as producto,
       promocionar_p3_resolver('fedcba9876543210') as home;

select pg_temp.chk(
  (select producto->>'destino_url' =
    'https://magandhi.com/producto/p3-producto-local/?utm_source=instagram&utm_medium=social&utm_campaign=p3-producto-261108-abcd&utm_content=historia-uno'
   from p3_resoluciones),
  'resolver: producto exacto dentro de la lista blanca'
);
select pg_temp.chk(
  (select home->>'destino_url' =
    'https://magandhi.com/?utm_source=email&utm_medium=email&utm_campaign=p3-home-261108-efgh'
   from p3_resoluciones),
  'resolver: home exacto dentro de la lista blanca'
);
select pg_temp.chk(
  (select bool_and(
     (x->>'destino_url') ~ '^https://magandhi[.]com/(producto/[a-z0-9-]+/)?[?]utm_source='
     and (x->>'destino_url') !~ 'redirect|next=|url='
   ) from p3_resoluciones r
     cross join lateral unnest(array[r.producto, r.home]) x),
  'resolver: ningún destino permite origen o parámetro arbitrario'
);
select pg_temp.chk(
  promocionar_p3_resolver('codigo-invalido') is null
  and promocionar_p3_resolver('aaaaaaaaaaaaaaaa') is null,
  'resolver: código inválido o desconocido no resuelve'
);

-- ----------------------------------------------------------------------------
-- Dos conteos producen una fila diaria y una sola ventana global.
-- ----------------------------------------------------------------------------
create temp table p3_conteo_1 as
select promocionar_p3_contar(
  '73c00000-0000-4000-8000-000000000001', repeat('1', 64)
) as salida;
create temp table p3_conteo_2 as
select promocionar_p3_contar(
  '73c00000-0000-4000-8000-000000000001', repeat('1', 64)
) as salida;

select pg_temp.chk(
  (select (salida->>'contado')::boolean
          and salida->>'total_dia' = '1'
          and salida->>'conteo_ventana' = '1'
     from p3_conteo_1)
  and (select (salida->>'contado')::boolean
              and salida->>'total_dia' = '2'
              and salida->>'conteo_ventana' = '2'
         from p3_conteo_2),
  'conteo: dos llamadas aceptadas llegan a total diario y ventana 2'
);
select pg_temp.chk(
  (select count(*) = 1 and min(total) = 2 and max(total) = 2
     from atribucion_clics_dia
    where enlace_id = '73c00000-0000-4000-8000-000000000001'
      and fecha_colombia = (statement_timestamp() at time zone 'America/Bogota')::date),
  'conteo: un único agregado por enlace y fecha Colombia'
);
select pg_temp.chk(
  (select count(*) = 1 and min(conteo) = 2 and max(conteo) = 2
     from atribucion_limite_temporal
    where hash_ip_dia = repeat('1', 64)
      and ventana_hora = date_trunc('hour', statement_timestamp() at time zone 'UTC')),
  'conteo: una única ventana por hash y hora UTC'
);

-- Completa 600 usando ambos enlaces: la cuota no se multiplica por enlace.
create temp table p3_hasta_600 as
select g,
       promocionar_p3_contar(
         case when g % 2 = 0
           then '73c00000-0000-4000-8000-000000000002'::uuid
           else '73c00000-0000-4000-8000-000000000001'::uuid
         end,
         repeat('1', 64)
       ) as salida
  from generate_series(1, 598) g;
create temp table p3_llamada_601 as
select promocionar_p3_contar(
  '73c00000-0000-4000-8000-000000000002', repeat('1', 64)
) as salida;

select pg_temp.chk(
  (select count(*) = 598
          and bool_and((salida->>'contado')::boolean)
          and max((salida->>'conteo_ventana')::integer) = 600
     from p3_hasta_600)
  and (select conteo = 600 from atribucion_limite_temporal
        where hash_ip_dia = repeat('1', 64)),
  'cuota: las primeras 600 llamadas del hash/hora se aceptan globalmente'
);
select pg_temp.chk(
  (select salida = '{"contado": false, "motivo": "cuota_hora_superada"}'::jsonb
     from p3_llamada_601)
  and (select sum(total) = 600 from atribucion_clics_dia
        where enlace_id in (
          '73c00000-0000-4000-8000-000000000001',
          '73c00000-0000-4000-8000-000000000002'
        )),
  'cuota: la llamada 601 se rechaza sin incrementar agregados'
);
select pg_temp.chk(
  (select total = 301 from atribucion_clics_dia
    where enlace_id = '73c00000-0000-4000-8000-000000000001'
      and fecha_colombia = (statement_timestamp() at time zone 'America/Bogota')::date)
  and
  (select total = 299 from atribucion_clics_dia
    where enlace_id = '73c00000-0000-4000-8000-000000000002'
      and fecha_colombia = (statement_timestamp() at time zone 'America/Bogota')::date),
  'conteo: cada enlace mantiene su agregado aunque la cuota sea compartida'
);

-- El redirect sigue resolviendo cuando el contador está apagado.
update promocionar_p3_config
   set conteo_habilitado = false,
       actualizado_en = greatest(clock_timestamp(), actualizado_en + interval '1 microsecond'),
       actualizado_por = auth.uid(),
       actualizado_razon = 'banco_local_p3_apagar_conteo',
       actualizado_rol = current_user
 where id = 1;
create temp table p3_conteo_apagado as
select promocionar_p3_resolver('fedcba9876543210') as resolucion,
       promocionar_p3_contar(
         '73c00000-0000-4000-8000-000000000002', repeat('2', 64)
       ) as conteo;
select pg_temp.chk(
  (select resolucion is not null
          and conteo = '{"contado": false, "motivo": "conteo_deshabilitado"}'::jsonb
     from p3_conteo_apagado)
  and not exists (
    select 1 from atribucion_limite_temporal where hash_ip_dia = repeat('2', 64)
  ),
  'independencia: redirect disponible y conteo apagado falla sin persistir'
);

-- ----------------------------------------------------------------------------
-- Mantenimiento: compacta solo antes de 13 meses y purga solo límites vencidos.
-- ----------------------------------------------------------------------------
insert into atribucion_clics_dia (enlace_id, fecha_colombia, total) values
  (
    '73c00000-0000-4000-8000-000000000001',
    ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date - 1,
    7
  ),
  (
    '73c00000-0000-4000-8000-000000000002',
    ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date - 2,
    11
  ),
  (
    '73c00000-0000-4000-8000-000000000001',
    ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date,
    13
  );
insert into atribucion_limite_temporal (
  hash_ip_dia, ventana_hora, conteo, creado_en, expira_en
) values (
  repeat('3', 64),
  date_trunc('hour', statement_timestamp() at time zone 'UTC') - interval '3 hours',
  1,
  statement_timestamp() - interval '2 hours',
  statement_timestamp() - interval '1 hour'
);

create temp table p3_mantenimiento_1 as
select promocionar_p3_mantenimiento() as salida;
create temp table p3_mantenimiento_2 as
select promocionar_p3_mantenimiento() as salida;

select pg_temp.chk(
  (select salida->>'filas_detalle_compactadas' = '2'
          and salida->>'enlaces_actualizados' = '2'
          and salida->>'total_compactado' = '18'
          and salida->>'limites_vencidos_purgados' = '1'
     from p3_mantenimiento_1),
  'mantenimiento: compacta dos filas antiguas y purga el límite vencido'
);
select pg_temp.chk(
  (select total_aproximado_historico = 7 from atribucion_enlaces
    where id = '73c00000-0000-4000-8000-000000000001')
  and
  (select total_aproximado_historico = 11 from atribucion_enlaces
    where id = '73c00000-0000-4000-8000-000000000002')
  and exists (
    select 1 from atribucion_clics_dia
     where enlace_id = '73c00000-0000-4000-8000-000000000001'
       and fecha_colombia =
         ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date
       and total = 13
  ),
  'retención: suma histórico por enlace y conserva exactamente el día de corte'
);
select pg_temp.chk(
  (select salida->>'filas_detalle_compactadas' = '0'
          and salida->>'enlaces_actualizados' = '0'
          and salida->>'total_compactado' = '0'
          and salida->>'limites_vencidos_purgados' = '0'
     from p3_mantenimiento_2),
  'mantenimiento: la segunda ejecución es idempotente'
);
select pg_temp.chk(
  not exists (
    select 1 from atribucion_clics_dia
     where fecha_colombia <
       ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date
  )
  and not exists (
    select 1 from atribucion_limite_temporal where expira_en <= statement_timestamp()
  ),
  'retención: no quedan detalle antiguo ni límites vencidos'
);

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que
  from pg_temp.p3_resultado order by n;
select 'RESUMEN P3 SQL | ' || count(*) || ' comprobaciones · '
       || count(*) filter (where not ok) || ' fallan'
  from pg_temp.p3_resultado;

do $$
begin
  if exists (select 1 from pg_temp.p3_resultado where not ok) then
    raise exception using errcode = 'P0001', message = 'P3_BANCO_SQL_FALLA';
  end if;
end;
$$;

rollback;
