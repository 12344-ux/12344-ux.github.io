-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · PUENTE DE ESTADO C3 → C4
-- ----------------------------------------------------------------------------
-- Ejecutar COMPLETO después del preflight C3 y ANTES de desplegar la Edge
-- estado-pago C4. Luego se despliega la Edge nueva y solo entonces se aplica
-- 20261105000000_comercial_c4_cuenta_ciclo_carrito.sql.
--
-- Motivo: la Edge C4 necesita pw_estado_checkout_publico, mientras la Edge C3
-- todavía usa pw_estado_publico. Este puente añade la puerta nueva sobre el
-- esquema C3 sin retirar la antigua; así no existe una ventana de retorno roto.
-- La migración C4 la reemplaza atómicamente con su versión autoritativa, que
-- además libera expiraciones. El puente es solo lectura y no expira intenciones.
--
-- Es idempotente ANTES de C4. Falla cerrado si el carrito no está OFF o si C4
-- ya fue aplicada, para impedir que una ejecución tardía degrade su contrato.
-- ============================================================================

begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

select id
  from public.comercial_config
 where id = 1
 for share;

do $$
begin
  if (select count(*)
        from public.comercial_config
       where id = 1
         and carrito_habilitado is false) <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'C4_PUENTE_REQUIERE_CARRITO_OFF';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'pagos_intencion'
       and column_name = 'ciclo_carrito_version'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'C4_PUENTE_NO_APLICAR_DESPUES_DE_C4';
  end if;
end;
$$;

create or replace function public.pw_estado_checkout_publico(
  p_referencia text,
  p_auth_user_id uuid default null
)
returns table (
  estado text,
  nombre_producto text,
  slug text,
  checkout jsonb
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_i public.pagos_intencion%rowtype;
begin
  if p_referencia is null
     or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    return;
  end if;

  select pi.*
    into v_i
    from public.pagos_intencion pi
   where pi.referencia = p_referencia;

  if not found then
    return;
  end if;

  -- v0/v1 conservan autorización histórica por posesión. v2 requiere el UID
  -- congelado ya disponible en C3; no se expone si falta o pertenece a otro.
  if v_i.version_checkout = 2
     and p_auth_user_id is distinct from v_i.auth_user_id then
    return;
  end if;

  return query
  select case v_i.estado
           when 'creada' then 'pendiente'
           when 'procesada' then 'aprobado'
           when 'rechazada' then 'rechazado'
           when 'requiere_revision' then 'revision'
           else 'pendiente'
         end,
         coalesce(v_i.nombre, ''),
         coalesce(v_i.slug, ''),
         case
           when v_i.version_checkout = 2 then
             jsonb_build_object(
               'tipo', 'carrito',
               'id', v_i.carrito_id,
               'version', v_i.carrito_version,
               'recargar', true
             )
           else null
         end;
end;
$$;

comment on function public.pw_estado_checkout_publico(text, uuid) is
  'Puente de despliegue C3→C4 · estado mínimo; v2 exige UID y añade descriptor de carrito. La migración C4 reemplaza esta versión estable por la autoritativa con expiración.';

revoke all on function public.pw_estado_checkout_publico(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.pw_estado_checkout_publico(text, uuid)
  to service_role;

commit;

-- Verificación durable posterior al COMMIT: todos deben ser true.
select to_regprocedure(
         'public.pw_estado_checkout_publico(text,uuid)'
       ) is not null as puente_presente,
       has_function_privilege(
         'service_role',
         'public.pw_estado_checkout_publico(text,uuid)',
         'execute'
       ) as service_role_puede_ejecutar,
       not has_function_privilege(
         'anon',
         'public.pw_estado_checkout_publico(text,uuid)',
         'execute'
       ) as anon_no_puede_ejecutar,
       not has_function_privilege(
         'authenticated',
         'public.pw_estado_checkout_publico(text,uuid)',
         'execute'
       ) as authenticated_no_puede_ejecutar;
