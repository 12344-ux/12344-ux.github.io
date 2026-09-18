-- ============================================================
-- Magandhi Corporation · Cimiento para Wompi (B3.1) · contabilidad_config
-- Tabla de configuracion contable, UNA sola fila (mismo molde que
-- inventario_config en 20250301000000_inventario_productos.sql: id integer
-- primary key default 1 + candado de fila unica + seed idempotente de id=1).
--
-- QUE GUARDA Y POR QUE:
--   Los CODIGOS de cuenta del PUC que el asiento automatico de la venta web
--   (fase F, futura Edge Function de Wompi) usara para armar la partida doble.
--   Se guardan AQUI, en datos, y NO se escriben a fuego en el codigo, por dos
--   razones:
--     1) Clonabilidad Impulse (MAGANDHI es el piloto): otra organizacion del
--        ecosistema cambia estos 5 codigos en un solo lugar (esta fila) sin
--        tocar la logica del asiento, igual que el prefijo del SKU vive en
--        inventario_config y no en la RPC.
--     2) El asiento web LEE de aqui: si manana el dueno reclasifica una cuenta,
--        edita la fila y el asiento sigue cuadrando sin redeploy.
--
-- LOS 5 CODIGOS (rol contable -> codigo PUC -> naturaleza esperada). VERIFICADO
-- que las 5 cuentas existen en el catalogo cargado en
-- 20250201000100_finanzas_carga_puc.sql con la naturaleza correcta:
--   cuenta_banco     '1110' BANCOS ................................... debito
--   cuenta_ingreso   '4135' COMERCIO AL POR MAYOR Y AL POR MENOR ..... credito
--   cuenta_comision  '5305' FINANCIEROS (comision de la pasarela) .... debito
--   cuenta_costo     '6135' COSTO (venta de mercancias) ............... debito
--   cuenta_inventario'1435' MERCANCIAS NO FABRICADAS POR LA EMPRESA ... debito
--
-- RELACION LOGICA CON puc_cuentas (a proposito SIN FK dura):
--   Estos text apuntan a puc_cuentas(codigo), pero NO se pone FOREIGN KEY, en
--   linea con el resto del proyecto que evita acoplamientos duros entre modulos
--   (ver como Inventario/Marketing referencian sin FK cruzada). La FK ademas
--   arriesgaria el seed si el orden de carga del PUC cambiara. La relacion se
--   documenta aqui y se valida en el asiento web al leer los codigos; el
--   catalogo PUC sigue siendo la fuente normativa.
--
-- RLS Y GRANT (mismo criterio que Finanzas, incluidos en este archivo para que
--   la tabla nazca con su candado): SELECT solo para authenticated con el
--   guardia central del modulo tiene_modulo('finanzas') (definido en
--   20250101000000_crear_perfiles_y_roles.sql). SIN INSERT/UPDATE/DELETE para
--   authenticated: la fila la siembra/edita el DUENO a mano (service_role /
--   SQL Editor), no el cliente. anon no recibe ningun grant: esta tabla es
--   contable, vive tras login.
--
-- IDEMPOTENTE: create table if not exists + seed on conflict do nothing +
--   drop policy if exists / create policy + grant (idempotente por naturaleza).
--   El dueno puede re-ejecutar este archivo sin romper nada ni pisar la fila.
-- ============================================================

-- ------------------------------------------------------------
-- contabilidad_config: una sola fila (id=1), molde de inventario_config.
-- ------------------------------------------------------------
create table if not exists contabilidad_config (
  id                integer primary key default 1,
  cuenta_banco      text not null default '1110',
  cuenta_ingreso    text not null default '4135',
  cuenta_comision   text not null default '5305',
  cuenta_costo      text not null default '6135',
  cuenta_inventario text not null default '1435',
  creado            timestamptz default now(),
  -- Candado: garantiza que solo pueda existir UNA fila de configuracion.
  constraint contabilidad_config_fila_unica check (id = 1)
);

comment on table contabilidad_config is 'Configuracion contable del asiento automatico de la venta web (una sola fila, id=1). Guarda los CODIGOS de cuenta PUC que el asiento LEE, para no escribirlos a fuego en el codigo (clonable a otra organizacion Impulse: se cambian aqui, en un solo lugar). Los codigos apuntan logicamente a puc_cuentas(codigo); a proposito SIN FK dura, como el resto del proyecto que evita acoplamientos. La siembra/edita el dueno a mano (service_role); authenticated con el modulo finanzas solo la LEE.';
comment on column contabilidad_config.cuenta_banco      is 'Codigo PUC del banco / caja receptora del pago (default 1110 BANCOS, naturaleza debito). Lo LEE el asiento web; NO se hardcodea.';
comment on column contabilidad_config.cuenta_ingreso    is 'Codigo PUC del ingreso por venta (default 4135 COMERCIO AL POR MAYOR Y AL POR MENOR, naturaleza credito). Lo LEE el asiento web; NO se hardcodea.';
comment on column contabilidad_config.cuenta_comision   is 'Codigo PUC de la comision de la pasarela de pagos (default 5305 FINANCIEROS, naturaleza debito). Lo LEE el asiento web; NO se hardcodea.';
comment on column contabilidad_config.cuenta_costo      is 'Codigo PUC del costo de ventas (default 6135, naturaleza debito). Lo LEE el asiento web; NO se hardcodea.';
comment on column contabilidad_config.cuenta_inventario is 'Codigo PUC del inventario / mercancias que sale con la venta (default 1435 MERCANCIAS NO FABRICADAS POR LA EMPRESA, naturaleza debito). Lo LEE el asiento web; NO se hardcodea.';

-- Semilla de la unica fila con los codigos de MAGANDHI. Idempotente: si ya
-- existe, no la pisa (do nothing) para no revertir codigos que el dueno haya
-- ajustado para su organizacion.
insert into contabilidad_config
  (id, cuenta_banco, cuenta_ingreso, cuenta_comision, cuenta_costo, cuenta_inventario)
values
  (1, '1110', '4135', '5305', '6135', '1435')
  on conflict (id) do nothing;

-- ------------------------------------------------------------
-- RLS: solo lectura para authenticated con el guardia del modulo finanzas.
-- Mismo criterio que 20250201000500_finanzas_rls.sql. El candado real vive en
-- los datos, no en el HTML.
-- ------------------------------------------------------------
alter table contabilidad_config enable row level security;

drop policy if exists "contabilidad_config_select_modulo" on contabilidad_config;
create policy "contabilidad_config_select_modulo" on contabilidad_config
  for select
  to authenticated
  using (tiene_modulo('finanzas'));
-- Sin policy de INSERT/UPDATE/DELETE para authenticated: la fila la siembra /
-- edita el dueno a mano (service_role / SQL Editor). Asi nadie desde el cliente
-- cambia los codigos de cuenta que gobiernan el asiento contable.

-- ------------------------------------------------------------
-- GRANT de tabla (capa 1) para authenticated. Sin este grant, PostgREST
-- responderia 403 ANTES de evaluar RLS (auto-expose OFF, ver INSTRUCCIONES).
-- Solo SELECT: la escritura no pasa por el cliente. Nada para anon.
-- Misma leccion que 20250301000500_inventario_grants.sql.
-- ------------------------------------------------------------
grant select on table contabilidad_config to authenticated;
