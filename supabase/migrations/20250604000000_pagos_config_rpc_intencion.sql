-- ============================================================
-- Magandhi Corporation · Wompi (F1 · fix) · RPC pagos_config_para_intencion
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTA RPC (bug diagnosticado con evidencia directa):
--   La Edge Function crear-intencion-pago daba HTTP 500 con
--   {"error":"No se pudo leer la configuracion de pagos."} al leer la tabla
--   pagos_config por PostgREST, AUNQUE:
--     - el grant `grant select on public.pagos_config to service_role;` ya
--       estaba puesto por el dueno, y
--     - como service_role REAL la fila SI se lee (confirmado en el SQL Editor
--       con `begin; set local role service_role; select ... rollback;`).
--
--   CAUSA RAIZ: aunque la funcion crea el cliente con la SERVICE_ROLE_KEY y le
--   pasa el header Authorization=Bearer <service_role>, la peticion del
--   navegador tambien lleva el header apikey=publishable/anon (supabase-js lo
--   adjunta). PostgREST, al ver esa apikey anon, resuelve el ROL EFECTIVO como
--   anon/authenticated en lugar de service_role. Como pagos_config tiene RLS
--   (SELECT solo a authenticated con tiene_modulo('finanzas')), la lectura
--   directa de la TABLA queda bloqueada para ese rol degradado. Por eso la
--   funcion si podia leer catalogo_publico (una VISTA con grant a anon) pero NO
--   pagos_config (tabla con RLS).
--
--   FIX (patron coherente con TODO el proyecto: la lectura/escritura sensible
--   SIEMPRE va por RPC security definer, como en finanzas/inventario/ventas/
--   campanas): la Edge Function ya NO lee la tabla pagos_config directo por
--   PostgREST; la lee a traves de esta RPC SECURITY DEFINER, que corre con los
--   privilegios de su dueno y NO depende de como PostgREST resuelva el rol de la
--   peticion. Ademas la RPC solo devuelve DATOS PUBLICOS (entorno + llave
--   publica del entorno activo), nunca la fila completa.
--
-- ============================================================================
-- LINEA ROJA (orden permanente del dueno · NO negociable):
--   Esta RPC devuelve UNICAMENTE el entorno ('sandbox'|'prod') y la LLAVE
--   PUBLICA (publishable key) del entorno activo. JAMAS toda la fila. Las llaves
--   publicas NO son secretas (viajan al navegador de todas formas). Los SECRETOS
--   de Wompi (integridad, eventos) NO estan en pagos_config ni aqui: viven solo
--   como secrets de la Edge Function en Deno.env.
--
-- NO MODIFICAR 20250601000100_pagos_config.sql (la tabla y su RLS quedan igual).
--   Esta es una migracion NUEVA, idempotente (create or replace + grant).
-- ============================================================

-- ------------------------------------------------------------
-- pagos_config_para_intencion(): sin argumentos. Lee pagos_config (id=1) y
-- devuelve el entorno activo y la llave publica CORRESPONDIENTE a ese entorno
-- (llave_publica_sandbox si entorno='sandbox', llave_publica_prod si 'prod').
-- SECURITY DEFINER + STABLE + search_path fijo. La usa la Edge Function
-- crear-intencion-pago via supabase.rpc('pagos_config_para_intencion').
-- ------------------------------------------------------------
create or replace function pagos_config_para_intencion()
returns table (
  entorno       text,
  llave_publica text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    pc.entorno,
    case
      when pc.entorno = 'prod' then pc.llave_publica_prod
      else pc.llave_publica_sandbox
    end as llave_publica
  from pagos_config pc
  where pc.id = 1;
$$;

comment on function pagos_config_para_intencion() is 'Devuelve SOLO el entorno activo (sandbox|prod) y la LLAVE PUBLICA de ese entorno de pagos_config (id=1). SECURITY DEFINER: existe porque la Edge Function crear-intencion-pago no puede leer la tabla pagos_config directo por PostgREST (la apikey anon del navegador degrada el rol efectivo a anon/authenticated y la RLS de la tabla bloquea la lectura); esta RPC corre con los privilegios de su dueno, sortea ese problema y expone UNICAMENTE datos publicos (nunca la fila completa, nunca secretos). Las llaves publicas no son secretas (van al navegador). Los secretos de Wompi viven solo como secrets de la Edge Function.';

-- ------------------------------------------------------------
-- GRANT EXECUTE a service_role Y a authenticated. En Postgres las funciones
-- otorgan EXECUTE a PUBLIC por defecto al crearse, asi que hoy es tecnicamente
-- redundante; se deja EXPLICITO por claridad y como defensa a futuro (por si un
-- dia se hace `revoke execute ... from public`). La Edge Function la invoca con
-- el cliente service_role; authenticated tambien puede ejecutarla (solo lee
-- datos publicos). Idempotente. No abre escritura ni toca la RLS de la tabla.
-- ------------------------------------------------------------
grant execute on function pagos_config_para_intencion() to service_role;
grant execute on function pagos_config_para_intencion() to authenticated;
