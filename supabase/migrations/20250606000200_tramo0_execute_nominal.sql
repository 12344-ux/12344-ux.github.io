-- ============================================================
-- Impulse · TRAMO 0 (auditoria) · EXECUTE nominal: menor privilegio en funciones
-- ------------------------------------------------------------
-- EL HALLAZGO: PostgreSQL otorga EXECUTE a PUBLIC sobre toda funcion nueva y,
-- ademas, Supabase concede EXECUTE por defecto a anon y authenticated en el
-- esquema public. Ninguna migracion del repo lo revocaba (salvo
-- pagos_config_para_intencion). Resultado medido en una base local identica:
-- 32 de 32 funciones de public eran ejecutables por anon (el visitante sin
-- sesion de la tienda). Las RPC de escritura se defienden porque validan el
-- modulo por dentro, asi que no habia una explotacion directa; pero la
-- superficie era innecesariamente grande (helpers internos, informes,
-- normalizadores, la funcion de trigger...).
--
-- LA CORRECCION (menor privilegio, nominal):
--   (1) Se REVOCA EXECUTE de PUBLIC, anon y authenticated en TODAS las
--       funciones propias de public (se excluyen las de extensiones).
--   (2) Se OTORGA EXECUTE a authenticated SOLO en la lista blanca de abajo:
--       las 21 RPC que el back-office llama + los 4 guardias que usan las
--       policies RLS y de Storage + pagos_config_para_intencion.
--   (3) service_role (solo servidor: Edge Functions / dashboard) conserva
--       EXECUTE en todas.
--   (4) anon NO ejecuta ninguna funcion. La tienda solo lee la vista
--       catalogo_publico y llama la Edge Function (que usa service_role).
--   (5) DEFAULT PRIVILEGES: desde aqui, toda funcion NUEVA nace CERRADA para
--       PUBLIC, anon y authenticated. REGLA PARA EL FUTURO: cada migracion que
--       cree una funcion que el frontend llame DEBE incluir su
--       `grant execute ... to authenticated` (mismo espiritu del cambio de
--       Supabase del 30-oct-2026 para tablas nuevas). Si se olvida, falla de
--       forma RUIDOSA (permission denied for function), nunca silenciosa.
--
-- FUNCIONES QUE QUEDAN SOLO INTERNAS (sin authenticated, a proposito):
--   fz_validar_lineas, registrar_bitacora_asiento (trigger),
--   ventas_norm_correo, ventas_norm_telefono, ventas_norm_nombre,
--   cm_normalizar_slug. Todas se invocan unicamente desde RPC security
--   definer (corren como su dueno) o como trigger, asi que no necesitan
--   permiso del usuario.
--
-- POR QUE LOS GUARDIAS SI VAN A authenticated: las policies RLS
--   (tiene_modulo, tiene_acceso_*) se evaluan con los permisos de QUIEN
--   CONSULTA. Sin EXECUTE, toda lectura del back-office fallaria.
--
-- POR QUE UN BLOQUE DINAMICO: se otorga por NOMBRE recorriendo pg_proc, asi
--   cubre las firmas reales (cm_crear_campana/cm_editar_campana cambiaron de
--   firma varias veces) sin escribir listas de tipos fragiles. Si un nombre de
--   la lista blanca no existe, la migracion ABORTA (protege contra erratas).
--
-- IDEMPOTENTE: revoke/grant/alter default privileges son idempotentes.
-- REQUISITO: correr DESPUES de 20250606000100_tramo0_anulacion_sin_carreras.sql
--   (y en general al final: actua sobre todas las funciones existentes).
-- ============================================================

begin;

do $$
declare
  -- Lista blanca de funciones que authenticated puede ejecutar.
  v_autenticado text[] := array[
    -- Guardias usados por policies RLS y de Storage
    'tiene_modulo', 'tiene_acceso_inventario', 'tiene_acceso_marketing', 'tiene_acceso_ventas',
    -- Finanzas
    'guardar_asiento', 'editar_asiento', 'anular_asiento', 'incrementar_uso_cuenta',
    'agregar_cuenta_puc', 'balance_comprobacion', 'estado_resultados', 'balance_general',
    -- Inventario
    'inv_crear_producto', 'inv_registrar_movimiento', 'inv_editar_producto',
    -- Ventas
    'buscar_candidatos_cliente', 'crear_pedido', 'anular_pedido', 'avanzar_estado_pedido',
    -- Campanas
    'cm_crear_campana', 'cm_editar_campana', 'cm_publicar_campana',
    'cm_crear_etiqueta', 'cm_editar_etiqueta', 'cm_retirar_placeholder',
    -- Pagos (lee solo entorno + llave publica)
    'pagos_config_para_intencion'
  ];
  v_nombre text;
  r record;
begin
  -- Proteccion contra erratas: cada nombre de la lista debe existir.
  foreach v_nombre in array v_autenticado loop
    if not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_nombre
    ) then
      raise exception 'Tramo 0: la funcion % de la lista blanca no existe. No se aplico ningun cambio.', v_nombre;
    end if;
  end loop;

  -- (1) + (3) Todas las funciones propias de public (sin las de extensiones).
  for r in
    select p.oid::regprocedure as firma, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       and not exists (
         select 1 from pg_depend d
          where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
       )
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.firma);
    execute format('grant execute on function %s to service_role', r.firma);

    -- (2) Lista blanca para authenticated.
    if r.proname = any (v_autenticado) then
      execute format('grant execute on function %s to authenticated', r.firma);
    end if;
  end loop;
end;
$$;

-- (5) Funciones FUTURAS creadas por postgres nacen cerradas.
--   * PUBLIC es un default GLOBAL de PostgreSQL: se revoca sin "in schema".
--   * anon/authenticated son defaults de Supabase EN el esquema public.
--   * service_role mantiene su default (solo servidor).
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges in schema public grant execute on functions to service_role;

commit;

-- ------------------------------------------------------------
-- VERIFICACION (opcional, solo lectura). Debe devolver anon=0 y authenticated=26.
-- ------------------------------------------------------------
-- select
--   count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))          as anon,
--   count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute')) as authenticated,
--   count(*) filter (where has_function_privilege('service_role', p.oid, 'execute'))  as service_role,
--   count(*) as total
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');
