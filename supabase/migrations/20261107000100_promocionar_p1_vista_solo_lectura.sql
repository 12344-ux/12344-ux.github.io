-- ============================================================================
-- MAGANDHI · PROMOCIONAR P1 · VISTA DE ALIASES ESTRICTAMENTE SOLO LECTURA
-- ----------------------------------------------------------------------------
-- Corrección forward después de 20261107000000.
--
-- Producción confirmó que sus default privileges concedieron a anon,
-- authenticated y service_role MAINTAIN, REFERENCES, TRIGGER y TRUNCATE además
-- de SELECT sobre la vista. La vista no es una tabla de datos editable, pero el
-- contrato público exige una ACL nominal exacta: únicamente SELECT.
--
-- No cambia filas, slugs, aliases, triggers, catálogo, pagos o carrito.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '15s';
set local lock_timeout = '3s';

do $$
begin
  if to_regclass('public.campana_slug_alias_publico') is null
     or to_regclass('public.campana_slug_historial') is null then
    raise exception using
      errcode = 'P0001',
      message = 'P1_VISTA_O_HISTORIAL_AUSENTE';
  end if;
end;
$$;

-- REVOKE ALL cubre también privilegios que dependen de la versión de Postgres,
-- incluido MAINTAIN. Después se reconstruye la lista blanca mínima.
revoke all on table campana_slug_alias_publico
  from public, anon, authenticated, service_role;

grant select on table campana_slug_alias_publico
  to anon, authenticated, service_role;

-- Falla la transacción completa si queda cualquier privilegio distinto de
-- SELECT para roles API o si PUBLIC recibe alguno.
do $$
begin
  if not has_table_privilege('anon', 'campana_slug_alias_publico', 'SELECT')
     or not has_table_privilege('authenticated', 'campana_slug_alias_publico', 'SELECT')
     or not has_table_privilege('service_role', 'campana_slug_alias_publico', 'SELECT') then
    raise exception using
      errcode = 'P0001',
      message = 'P1_SELECT_FALTANTE';
  end if;

  if exists (
    select 1
      from pg_class c
      cross join lateral aclexplode(
        coalesce(c.relacl, acldefault('r', c.relowner))
      ) a
      left join pg_roles r on r.oid = a.grantee
     where c.oid = 'public.campana_slug_alias_publico'::regclass
       and (
         a.grantee = 0
         or r.rolname in ('anon', 'authenticated', 'service_role')
       )
       and (
         a.grantee = 0
         or a.privilege_type <> 'SELECT'
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'P1_VISTA_CON_PRIVILEGIOS_EXTRA';
  end if;
end;
$$;

commit;
