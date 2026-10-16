-- ============================================================================
-- MAGANDHI · C2 · PREFLIGHT DE PRODUCCION (ESTRICTAMENTE SOLO LECTURA)
-- ----------------------------------------------------------------------------
-- Ejecutar completo en SQL Editor antes de desplegar/abrir C2. Solo devuelve
-- conteos y booleanos: nunca correos, UID, customer_id, nombres ni direcciones.
-- La transaccion READ ONLY hace fallar cualquier escritura accidental.
-- ============================================================================

begin transaction read only;

with
senales as (
  select distinct c.id as customer_id, n.correo_norm
    from clientes c
    cross join lateral (
      values (ventas_norm_correo(c.correo_norm)),
             (ventas_norm_correo(c.correo))
    ) as n(correo_norm)
   where n.correo_norm is not null
),
por_correo as (
  select correo_norm, count(distinct customer_id) as clientes
    from senales
   group by correo_norm
),
ambiguos as (
  select correo_norm, clientes
    from por_correo
   where clientes > 1
),
auth_confirmados as (
  select ventas_norm_correo(u.email) as correo_norm
    from auth.users u
   where u.email_confirmed_at is not null
),
medidas(orden, comprobacion, valor, esperado) as (
  select 1, 'Migracion C1 presente',
         (to_regclass('public.cuentas_cliente') is not null)::text,
         'true'
  union all
  select 2, 'Migracion C2 presente',
         (to_regprocedure('public.cc_inicializar_cuenta()') is not null
          and to_regclass('public.cc_conflictos_revision') is not null)::text,
         'true despues de aplicar 20261101000000'
  union all
  select 3, 'Clientes cuyo correo_norm no refleja el correo crudo',
         count(*)::text,
         'informativo; C2 consulta ambas fuentes sin modificarlas'
    from clientes c
   where ventas_norm_correo(c.correo) is distinct from ventas_norm_correo(c.correo_norm)
  union all
  select 4, 'Claves de correo que apuntan a mas de un cliente',
         count(*)::text,
         '0 ideal; C2 no vincula y abre revision si es mayor'
    from ambiguos
  union all
  select 5, 'Filas de cliente incluidas en claves ambiguas',
         coalesce(sum(clientes), 0)::text,
         '0 ideal; solo conteo agregado'
    from ambiguos
  union all
  select 6, 'Usuarios confirmados afectados por una clave ambigua',
         count(*)::text,
         '0 ideal; solo conteo agregado'
    from auth_confirmados a
    join ambiguos x using (correo_norm)
  union all
  select 7, 'Customer IDs ya vinculados mas de una vez',
         count(*)::text,
         '0 (ademas protegido por UNIQUE)'
    from (
      select customer_id
        from cuentas_cliente
       where customer_id is not null
       group by customer_id
      having count(*) > 1
    ) repetidos
)
select orden as "#", comprobacion, valor, esperado
  from medidas
 order by orden;

rollback;
