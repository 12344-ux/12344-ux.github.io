-- ============================================================
-- Magandhi Corporation · Cimiento para Wompi (B3.2) · pagos_config
-- Tabla de configuracion de pagos, UNA sola fila (mismo molde que
-- inventario_config / contabilidad_config: id integer primary key default 1 +
-- candado de fila unica + seed idempotente de id=1).
--
-- QUE ES: el "interruptor" sandbox <-> prod de la pasarela de pagos (Wompi).
--   Cambiar de pruebas a real es EDITAR UNA FILA, no reconstruir ni redeploy:
--   la Edge Function del asiento web (fase F, futura) leera 'entorno' de aqui
--   para decidir contra que ambiente de Wompi opera y que llave publica usar.
--
-- ============================================================================
-- ⚠️  LINEA ROJA DE SEGURIDAD (orden permanente del dueno · NO negociable):
--   Los SECRETOS de Wompi (secreto de INTEGRIDAD y secreto de EVENTOS/webhook)
--   NO van en esta tabla, ni en texto plano ni cifrados. Van como *secrets* de
--   la Edge Function en el dashboard de Supabase (los pone el dueno alli). Esta
--   tabla SOLO guarda "que entorno" + datos PUBLICOS.
--
--   Por que las llaves PUBLICAS si pueden vivir aqui: las llaves publicas de
--   Wompi (publishable keys) NO son secretas por diseno; viajan al navegador
--   del comprador de todas formas para inicializar el widget. Guardarlas en una
--   tabla de solo-lectura no las expone mas de lo que ya lo estan.
--
--   Este es el CORAZON de por que B3 se hace asi: separar el "que entorno + lo
--   publico" (esta tabla, versionable, auditable, clonable) de "los secretos"
--   (fuera del repo y fuera de la base, solo en el runtime de la funcion).
-- ============================================================================
--
-- RLS Y GRANT (mismo criterio que Finanzas, incluidos en este archivo): SELECT
--   solo para authenticated con el guardia central tiene_modulo('finanzas')
--   (definido en 20250101000000_crear_perfiles_y_roles.sql). SIN
--   INSERT/UPDATE/DELETE para authenticated: el dueno cambia el interruptor a
--   mano (service_role / SQL Editor). anon no recibe ningun grant. Aunque las
--   llaves publicas no son secretas, la tabla vive tras login: la superficie
--   publica de la tienda no se construye en B3.
--
-- IDEMPOTENTE: create table if not exists + seed on conflict do nothing +
--   drop policy if exists / create policy + grant. Re-ejecutable sin romper ni
--   pisar la fila (no revierte un entorno='prod' que el dueno haya activado).
-- ============================================================

-- ------------------------------------------------------------
-- pagos_config: una sola fila (id=1). Entorno + llaves PUBLICAS por entorno.
-- ------------------------------------------------------------
create table if not exists pagos_config (
  id                     integer primary key default 1,
  entorno                text not null default 'sandbox',
  llave_publica_sandbox  text not null default '',
  llave_publica_prod     text not null default '',
  creado                 timestamptz default now(),
  -- Candado: solo puede existir UNA fila de configuracion.
  constraint pagos_config_fila_unica check (id = 1),
  -- El interruptor solo acepta los dos ambientes reales de Wompi.
  constraint pagos_config_entorno_valido check (entorno in ('sandbox', 'prod'))
);

comment on table pagos_config is 'Configuracion de la pasarela de pagos (Wompi), una sola fila (id=1). Es el interruptor sandbox<->prod: cambiar de pruebas a real es editar la columna entorno, no reconstruir. Guarda SOLO el entorno actual y las llaves PUBLICAS por entorno (publishable keys, NO secretas: viajan al navegador de todas formas). LINEA ROJA: los SECRETOS de Wompi (integridad, eventos/webhook) NO van aqui; van como secrets de la Edge Function en el dashboard de Supabase. La fila la siembra/edita el dueno a mano; authenticated con el modulo finanzas solo la LEE.';
comment on column pagos_config.entorno               is 'Interruptor sandbox<->prod. Valores validos: sandbox | prod (check). La Edge Function del asiento web lo lee para decidir contra que ambiente de Wompi opera y que llave publica usar.';
comment on column pagos_config.llave_publica_sandbox is 'Llave PUBLICA (publishable key) de Wompi para el ambiente sandbox. NO es secreta (va al navegador). Puede quedar vacia hasta que el dueno la ponga.';
comment on column pagos_config.llave_publica_prod    is 'Llave PUBLICA (publishable key) de Wompi para produccion. NO es secreta (va al navegador). Puede quedar vacia hasta que el dueno la ponga. Los SECRETOS de Wompi NO van aqui: van como secrets de la Edge Function.';

-- Semilla de la unica fila: arranca en sandbox y con las llaves publicas
-- vacias (el dueno las pega despues). Idempotente: si ya existe, no la pisa
-- (do nothing) para no revertir un entorno='prod' ya activado por el dueno.
insert into pagos_config (id, entorno, llave_publica_sandbox, llave_publica_prod)
values (1, 'sandbox', '', '')
  on conflict (id) do nothing;

-- ------------------------------------------------------------
-- RLS: solo lectura para authenticated con el guardia del modulo finanzas.
-- ------------------------------------------------------------
alter table pagos_config enable row level security;

drop policy if exists "pagos_config_select_modulo" on pagos_config;
create policy "pagos_config_select_modulo" on pagos_config
  for select
  to authenticated
  using (tiene_modulo('finanzas'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: el interruptor lo
-- mueve el dueno a mano (service_role / SQL Editor). Nadie desde el cliente
-- cambia el entorno de pagos ni las llaves.

-- ------------------------------------------------------------
-- GRANT de tabla (capa 1) para authenticated. Solo SELECT. Nada para anon.
-- ------------------------------------------------------------
grant select on table pagos_config to authenticated;
