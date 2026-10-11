-- ============================================================================
-- MAGANDHI · Dropshipping D2c.2c · VERIFICACION EN VIVO ANTES DE COBRAR
-- ----------------------------------------------------------------------------
-- Migracion FORWARD. Ultima pieza de D2c.
--
-- QUE HACE
--   Una sola funcion, `ds_verificacion_checkout()`, que le da a
--   `crear-intencion-pago` lo que necesita para preguntarle a Dropi EN VIVO
--   justo antes de abrir Wompi: el origen del producto, su id y variante en
--   Dropi, el piso efectivo, lo que ya esta reservado y la EDAD de la ultima
--   lectura.
--
-- POR QUE UNA RPC Y NO LEER LA VISTA
--   `catalogo_publico` no expone —a proposito— el origen, el product_id_ref ni
--   el id externo: es una lista blanca para `anon`. La Edge Function corre con
--   service_role y podria leer las tablas directo, pero entonces la regla de
--   «que necesita el checkout» quedaria escrita dentro de un TypeScript, lejos
--   de la base que la define. Esta funcion la mantiene en un solo lugar.
--
-- SOLO service_role: devuelve existencias exactas e ids de proveedor.
--
-- LA DECISION DIFICIL, DOCUMENTADA: QUE HACER SI DROPI NO RESPONDE
--   La funcion no decide: entrega `minutos_desde_lectura` para que la Edge
--   Function decida, y el criterio elegido es este:
--     · Dropi dice que NO hay  -> se rechaza. Fallo cerrado, sin discusion.
--     · Dropi no responde Y la lectura en cache es FRESCA -> se permite. La
--       lectura ya paso la vigencia y el piso, y es la mejor informacion que
--       tenemos. Bloquear aqui convertiria cualquier hipo de Dropi en una
--       tienda caida, que es peor que el riesgo que evita.
--     · Dropi no responde Y la lectura ya tiene tiempo -> se rechaza. Si no
--       hay forma de confirmar y la evidencia ya envejecio, no se cobra.
--   El umbral vive en configuracion (`frescura_checkout_min`), no en el codigo.
-- ============================================================================

begin;

alter table dropshipping_config
  add column if not exists frescura_checkout_min integer not null default 10;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'dropshipping_config_frescura_rango') then
    alter table dropshipping_config
      add constraint dropshipping_config_frescura_rango
      check (frescura_checkout_min between 1 and 120);
  end if;
end $$;

comment on column dropshipping_config.frescura_checkout_min is
  'D2c.2c · minutos que una lectura de stock se considera lo bastante fresca para COBRAR cuando Dropi no responde. Dentro de la ventana se permite la compra (la lectura ya paso vigencia y piso, y bloquear convertiria un hipo de Dropi en tienda caida); fuera de ella se rechaza. Distinto de vigencia_minutos, que gobierna la VITRINA: cobrar exige mas frescura que mostrar.';

-- ----------------------------------------------------------------------------
-- Lo que el checkout necesita saber de un producto antes de cobrar
-- ----------------------------------------------------------------------------
create or replace function ds_verificacion_checkout(p_campana_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  select jsonb_build_object(
    'origen', coalesce(p.origen, 'propio'),
    -- Null en producto propio: la Edge Function no tiene nada que preguntarle
    -- a Dropi y sigue de largo.
    'dropi_id', pp.producto_externo_id,
    'variante', nullif(pp.variacion_externa_id, ''),
    'piso', coalesce(pp.piso_vitrina, cfg.piso_vitrina, 20),
    -- Unidades ya cobradas y todavia no transcritas a Dropi: se restan de lo
    -- que Dropi reporte en vivo, igual que hace la vitrina.
    'reservadas', coalesce((
      select sum(r.cantidad)
        from pedido_proveedor r
        join pedidos pe on pe.id = r.pedido_id
       where r.product_id = p.id
         and r.transcrito_en is null
         and pe.estado <> 'anulado'
    ), 0),
    'minutos_desde_lectura',
      case when pp.stock_leido_en is null then null
           else floor(extract(epoch from (now() - pp.stock_leido_en)) / 60.0)
      end,
    'frescura_max_min', coalesce(cfg.frescura_checkout_min, 10),
    -- Lo que la base ya sabe, para no depender solo de la respuesta externa.
    'disponible_local', coalesce(ventas_disponible_para_venta(p.id), 0)
  )
  from campana_producto cp
  join productos p on p.id = cp.product_id_ref
  left join producto_proveedor pp on pp.product_id = p.id
  left join (select piso_vitrina, frescura_checkout_min
               from dropshipping_config where id = 1) cfg on true
  where cp.id = p_campana_id;
$fn$;

comment on function ds_verificacion_checkout(uuid) is
  'D2c.2c · le entrega a crear-intencion-pago lo que necesita para verificar EN VIVO contra Dropi antes de cobrar: origen, id y variante externos, piso efectivo, unidades ya reservadas por pedidos sin transcribir, y la EDAD de la ultima lectura. No decide: la Edge Function aplica el criterio (Dropi dice que no -> rechazar; Dropi no responde pero la lectura es fresca -> permitir; no responde y la lectura envejecio -> rechazar). SOLO service_role: devuelve existencias exactas e ids de proveedor, que la lista blanca publica nunca expone.';

revoke all on function ds_verificacion_checkout(uuid) from public, anon, authenticated;
grant execute on function ds_verificacion_checkout(uuid) to service_role;

commit;
