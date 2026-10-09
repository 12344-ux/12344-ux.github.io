-- ============================================================
-- MAGANDHI / Impulse · DIAGNÓSTICO DE PRODUCCIÓN (solo lectura)
-- ------------------------------------------------------------
-- Dice DÓNDE ESTAMOS DE VERDAD en la base, sin fiarse de la documentación.
-- Solo SELECT: no crea, no cambia ni borra nada.
-- Funciona aunque F2 todavía no esté aplicada (lo informa en vez de fallar).
--
-- Uso: Supabase → SQL Editor → pegar COMPLETO → Run → copiar la tabla.
-- ============================================================
with
f2 as (
  select to_regclass('public.pagos_intencion') is not null as hay_intencion,
         to_regclass('public.pagos_eventos')  is not null as hay_eventos
),
d(n, area, comprobacion, valor, esperado) as (

  -- ---------------- 0 · Base ----------------
  select 1, '0 · Base', 'Zona horaria de la base',
         current_setting('TimeZone'),
         'informativo (los pedidos web toman la fecha de aquí)'
  union all
  select 2, '0 · Base', 'Hora actual en Colombia',
         to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'),
         'informativo'

  -- ---------------- A · Puesta al día 20261018 ----------------
  union all
  select 3, 'A · Puesta al día 20261018', 'Publicar exige producto ligado y precio',
         coalesce((select bool_or(strpos(pg_get_functiondef(p.oid), 'product_id_ref') > 0)
                     from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                    where s.nspname = 'public' and p.proname = 'cm_publicar_campana')::text, 'no existe'),
         'true'
  union all
  select 4, 'A · Puesta al día 20261018', 'Puertas latentes de escritura directa en Finanzas',
         (select count(*) from pg_policies
           where schemaname = 'public'
             and policyname in ('asientos_insert_modulo', 'asientos_update_modulo',
                                'asiento_lineas_insert_modulo', 'asiento_lineas_update_modulo',
                                'asiento_bitacora_insert_modulo'))::text,
         '0'
  union all
  select 5, 'A · Puesta al día 20261018', 'Marketing puede borrar imágenes huérfanas del bucket',
         (exists (select 1 from pg_policies
                   where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'campanas_delete_marketing'))::text,
         'true'
  union all
  select 6, 'A · Puesta al día 20261018', 'La vista catalogo_publico es la del 3-oct (no tocar)',
         coalesce((strpos(obj_description(to_regclass('public.catalogo_publico'), 'pg_class'),
                          'JUBILAR hook_corto') > 0)::text, 'sin comentario'),
         'true'

  -- ---------------- B · F2 en la base (20261019) ----------------
  union all
  select 7, 'B · F2 en la base (20261019)', 'Tablas pagos_intencion y pagos_eventos',
         (select (hay_intencion and hay_eventos)::text from f2),
         'true'
  union all
  select 8, 'B · F2 en la base (20261019)', 'Funciones de F2 presentes (de 4)',
         (select count(distinct p.proname)
            from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public'
             and p.proname in ('pw_registrar_intencion', 'pw_procesar_pago',
                               'pw_revisiones', 'pw_resolver_revision'))::text,
         '4'
  union all
  select 9, 'B · F2 en la base (20261019)', 'Ventas acepta el pedido que crea el webhook',
         coalesce((select bool_or(strpos(pg_get_functiondef(p.oid), 'pw__contexto_servidor') > 0)
                     from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                    where s.nspname = 'public' and p.proname = 'tiene_acceso_ventas')::text, 'no existe'),
         'true'
  union all
  select 10, 'B · F2 en la base (20261019)', 'Procesar pagos cerrado a anon y authenticated',
         coalesce((
           not has_function_privilege('anon',
                 to_regprocedure('public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)')::oid, 'EXECUTE')
           and not has_function_privilege('authenticated',
                 to_regprocedure('public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)')::oid, 'EXECUTE')
         )::text, 'no existe'),
         'true'

  -- ---------------- C · Configuración de pagos ----------------
  union all
  select 11, 'C · Pagos', 'Entorno activo',
         coalesce((select entorno from pagos_config where id = 1), 'sin fila'),
         'sandbox'
  union all
  select 12, 'C · Pagos', 'Llave pública de sandbox',
         coalesce((select case when left(llave_publica_sandbox, 9) = 'pub_test_' then 'cargada (pub_test_…)'
                               when coalesce(llave_publica_sandbox, '') = '' then 'VACÍA'
                               else 'formato inesperado' end
                     from pagos_config where id = 1), 'sin fila'),
         'cargada (pub_test_…)'
  union all
  select 13, 'C · Pagos', 'Llave pública de producción',
         coalesce((select case when left(llave_publica_prod, 9) = 'pub_prod_' then 'cargada (pub_prod_…)'
                               when coalesce(llave_publica_prod, '') = '' then 'vacía'
                               else 'formato inesperado' end
                     from pagos_config where id = 1), 'sin fila'),
         'vacía hasta F4'

  -- ---------------- D · Rastro real de las Edge Functions ----------------
  union all
  select 14, 'D · Rastro de las Edge Functions', 'Intenciones de pago (crear-intencion-pago versión F2)',
         case when (select hay_intencion from f2) then
           (xpath('/row/v/text()', query_to_xml($q$
              select count(*) || ' en total · ' ||
                     coalesce((select string_agg(estado || '=' || n, ', ' order by estado)
                                 from (select estado, count(*) as n
                                         from public.pagos_intencion group by estado) x), 'sin estados') ||
                     ' · última ' ||
                     coalesce(to_char(max(creado) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'), '-') as v
                from public.pagos_intencion $q$, false, true, '')))[1]::text
         else 'la tabla no existe (F2 sin aplicar)' end,
         '> 0 si ya se intentó comprar con F2 desplegada'
  union all
  select 15, 'D · Rastro de las Edge Functions', 'Avisos de Wompi recibidos (wompi-webhook)',
         case when (select hay_eventos from f2) then
           (xpath('/row/v/text()', query_to_xml($q$
              select count(*) || ' en total · ' ||
                     coalesce((select string_agg(resultado || '=' || n, ', ' order by resultado)
                                 from (select resultado, count(*) as n
                                         from public.pagos_eventos group by resultado) x), 'sin avisos') ||
                     ' · último ' ||
                     coalesce(to_char(max(recibido) at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI'), '-') as v
                from public.pagos_eventos $q$, false, true, '')))[1]::text
         else 'la tabla no existe (F2 sin aplicar)' end,
         '> 0 si ya se pagó en sandbox con el webhook conectado'
  union all
  select 16, 'D · Rastro de las Edge Functions', 'Pedidos por canal',
         coalesce((select string_agg(canal || '=' || n, ', ' order by canal)
                     from (select canal, count(*) as n from pedidos group by canal) x), 'sin pedidos'),
         'web > 0 después de una compra aprobada'
  union all
  select 17, 'D · Rastro de las Edge Functions', 'Pagos aprobados sin pedido (aviso rojo)',
         case when (select hay_intencion from f2) then
           (xpath('/row/v/text()', query_to_xml($q$
              select count(*) as v from public.pagos_intencion
               where estado = 'requiere_revision' and resuelta_en is null $q$, false, true, '')))[1]::text
         else '-' end,
         '0'
  union all
  select 18, 'D · Rastro de las Edge Functions', 'Pedidos web con fecha distinta a la de Colombia',
         (select count(*) from pedidos
           where canal = 'web' and fecha_orden <> (creado at time zone 'America/Bogota')::date)::text,
         '0'

  -- ---------------- E · Listo para una compra de prueba ----------------
  union all
  select 19, 'E · Compra de prueba', 'Productos comprables hoy en la tienda',
         coalesce((select string_agg(coalesce(slug, id::text) || ' ($' || coalesce(precio_venta::text, 'sin precio') || ')',
                                     ' · ' order by orden, slug)
                     from catalogo_publico where not agotado), 'NINGUNO'),
         'al menos 1'
  union all
  select 20, 'E · Compra de prueba', 'Campañas publicadas → producto, stock y costo',
         coalesce((select string_agg(
                     coalesce(cp.slug, cp.nombre) || ' → ' ||
                     case when p.id is null then 'SIN PRODUCTO LIGADO'
                          else p.sku || ' · stock ' || coalesce(s.existencias, 0) ||
                               ' · costo ' || coalesce(p.costo_unitario::text, 'SIN COSTO') end,
                     ' | ' order by cp.orden, cp.slug)
                     from campana_producto cp
                     left join productos p on p.id = cp.product_id_ref
                     left join stock_actual s on s.product_id = p.id
                    where cp.publicado and cp.activo), 'ninguna publicada'),
         'producto ligado, stock > 0 y costo'

  -- ---------------- F · Finanzas (línea base para F3) ----------------
  union all
  select 21, 'F · Finanzas', 'Cuentas que leería el asiento automático',
         coalesce((select string_agg(r.rol || ' ' || r.cod || ' → ' ||
                                     case when pc.codigo is null then 'NO EXISTE'
                                          when pc.imputable then 'ok'
                                          else 'NO IMPUTABLE' end,
                                     ' · ' order by r.ord)
                     from contabilidad_config c
                     cross join lateral (values (1, 'banco', c.cuenta_banco),
                                                (2, 'ingreso', c.cuenta_ingreso),
                                                (3, 'comisión', c.cuenta_comision),
                                                (4, 'costo', c.cuenta_costo),
                                                (5, 'inventario', c.cuenta_inventario)) as r(ord, rol, cod)
                     left join puc_cuentas pc on pc.codigo = r.cod
                    where c.id = 1), 'sin fila'),
         'todas ok'
  union all
  select 22, 'F · Finanzas', 'Asientos registrados',
         (select (count(*) filter (where estado = 'activo'))::text || ' activos · ' ||
                 (count(*) filter (where estado = 'anulado'))::text || ' anulados · último ' ||
                 coalesce(max(fecha)::text, '-')
            from asientos),
         'informativo'
  union all
  select 23, 'F · Finanzas', 'Inventario: en libros (1435) vs en bodega (stock × costo)',
         'libros $' ||
         coalesce((select sum(l.debe - l.haber)
                     from asiento_lineas l join asientos a on a.id = l.asiento_id
                    where a.estado = 'activo' and l.cuenta_codigo like '1435%'), 0) ||
         ' · bodega $' ||
         coalesce((select sum(greatest(s.existencias, 0)::bigint * p.costo_unitario)
                     from productos p join stock_actual s on s.product_id = p.id
                    where p.activo and p.costo_unitario is not null), 0) ||
         ' · productos con stock y SIN costo: ' ||
         (select count(*) from productos p join stock_actual s on s.product_id = p.id
           where p.activo and s.existencias > 0 and p.costo_unitario is null),
         'iguales si el inventario ya está en libros'
  union all
  select 24, 'F · Finanzas', 'Bancos (1110) en libros',
         '$' || coalesce((select sum(l.debe - l.haber)
                            from asiento_lineas l join asientos a on a.id = l.asiento_id
                           where a.estado = 'activo' and l.cuenta_codigo like '1110%'), 0),
         'informativo'
)
select n as "#", area, comprobacion, valor, esperado
  from d
 order by n;
