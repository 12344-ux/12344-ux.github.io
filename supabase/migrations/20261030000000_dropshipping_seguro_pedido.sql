-- ============================================================================
-- Dropshipping · D2c.3 · el SEGURO del pedido de proveedor
-- ----------------------------------------------------------------------------
-- POR QUE
--   El 14-oct-2026 el saldo del panel de Dropi no coincidia con los libros. La
--   causa: al crear el pedido, Dropi ofrece «Asegurar pedido» y el dueno lo
--   activo por 754 pesos, pero pedido_proveedor solo tiene costo_real y flete.
--   NO HABIA DONDE ANOTARLO, asi que el asiento nacia incompleto y el descuadre
--   se repetiria con cada pedido asegurado. Se cuadro a mano
--   (supabase/operacion/cuadre-contable-2026-10-14.sql) y esta migracion cierra
--   la causa.
--
-- EL SEGURO ES OPCIONAL, y eso manda el diseno
--   En Dropi se decide al comprar: se puede asegurar o no. Por eso la columna
--   es NULLABLE y `null` o `0` significan «no se aseguro», NO «falta el dato».
--   Consecuencia deliberada: el seguro NUNCA bloquea el asiento contable. Un
--   despacho se registra y se cierra perfectamente sin seguro.
--   Es la diferencia con costo_real y flete, que si lo bloquean (con
--   DS_COSTO_PROVEEDOR_PENDIENTE) porque esos SIEMPRE existen y no inventarlos
--   es lo que mantiene el asiento honesto.
--
-- LA CUENTA
--   523095 SEGUROS · OTROS, bajo 5230 SEGUROS (gasto operacional de ventas).
--   Verificado contra el PUC (Decreto 2650) antes de elegirla:
--     · 5245 es «Mantenimiento y reparaciones», asi que 524555 NO es una cuenta
--       de seguros;
--     · dentro de 5230 no existe subcuenta de «transporte de mercancias»: las
--       de transporte (523040 a 523055) son para asegurar flota PROPIA. Para el
--       seguro de un envio que despacha un tercero queda 523095 «Otros».
--   Va en contabilidad_config, como el resto: cambiarla no exige migracion.
--
-- COMO SE HIZO (regla del proyecto: derivar, no retipear)
--   Los cuerpos de fz__lineas_venta_web y ds_registrar_transcripcion se tomaron
--   con pg_get_functiondef del esquema real y se les aplicaron 10 cambios
--   puntuales por script, cada uno con anclaje unico y verificado uno por uno
--   contra el diff. fz__lineas_venta_web decide el asiento de TODAS las ventas
--   web, incluidas las de producto propio, que ya funcionan y mueven dinero:
--   retipearla a mano es la forma de romperlas.
--
-- NO TOCA
--   El stock, la vitrina, los pedidos, ni el asiento de producto propio. Un
--   despacho sin seguro se comporta exactamente igual que antes.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) La cuenta del seguro en el catalogo
-- ----------------------------------------------------------------------------
-- 5230 no venia en la carga inicial del PUC. En produccion las dos cuentas ya
-- existen (las creo el script de cuadre del 14-oct con agregar_cuenta_puc);
-- esto es para que una base nueva y el banco de pruebas queden iguales.
-- El validador de asientos rechaza una cuenta que no exista.
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  ('5230',   'SEGUROS',                   3, 'debito', false, '52'),
  ('523095', 'OTROS (SEGUROS DE VENTAS)', 4, 'debito', true,  '5230')
on conflict (codigo) do nothing;

alter table contabilidad_config
  add column if not exists cuenta_seguro text not null default '523095';

update contabilidad_config set cuenta_seguro = '523095'
  where id = 1 and coalesce(cuenta_seguro, '') = '';

comment on column contabilidad_config.cuenta_seguro is
  'Seguro del envio que cobra el proveedor (default 523095 SEGUROS · OTROS, bajo 5230 Seguros de ventas). Es gasto de VENDER, igual que el flete. Se eligio 523095 porque 5245 es Mantenimiento y reparaciones (no seguros) y dentro de 5230 no hay subcuenta de transporte de mercancias: las de transporte son para flota propia. Cambiarla no exige migracion.';

-- ----------------------------------------------------------------------------
-- (B) Donde se guarda
-- ----------------------------------------------------------------------------
alter table pedido_proveedor
  add column if not exists seguro bigint;

-- add constraint no admite IF NOT EXISTS: se guarda para poder reaplicar.
do $mig$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'pedido_proveedor_seguro_no_negativo') then
    alter table pedido_proveedor
      add constraint pedido_proveedor_seguro_no_negativo
      check (seguro is null or seguro >= 0);
  end if;
end $mig$;

comment on column pedido_proveedor.seguro is
  'Lo que Dropi cobro por «Asegurar pedido», en pesos enteros. OPCIONAL: en Dropi se decide al comprar, asi que null o 0 significan «no se aseguro», NO «falta el dato». Por eso NUNCA bloquea el asiento, al contrario que costo_real y flete. Va a 523095 (contabilidad_config.cuenta_seguro) contra el saldo en Dropi, igual que el flete.';

-- ----------------------------------------------------------------------------
-- (C) El asiento: el seguro sale del saldo en Dropi, como el costo y el flete
-- ----------------------------------------------------------------------------
--   D 613505 costo de la mercancia
--   D 523535 flete
--   D 523095 seguro            (solo si se aseguro)   C 138010 saldo en Dropi
CREATE OR REPLACE FUNCTION public.fz__lineas_venta_web(p_pedido_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c           contabilidad_config;
  v_total     bigint;
  v_base      bigint;
  v_iva       bigint := 0;
  v_costo     bigint := 0;
  v_sin_costo text;
  v_productos text;
  v_lineas    jsonb;
  -- D2c.2b: el costo del producto de PROVEEDOR no sale de la ficha de
  -- Inventario (no la tiene). Sale de lo que Dropi descontó de verdad, que el
  -- dueño registra al transcribir el pedido a mano.
  v_costo_prov  bigint := 0;
  v_flete_prov  bigint := 0;
  -- El seguro es OPCIONAL: en Dropi se decide al comprar. null o 0 significa
  -- «no se aseguro», no «falta el dato», asi que NUNCA bloquea el asiento.
  v_seguro_prov bigint := 0;
  v_sin_dato    text;
  v_prov_nombres text;
begin
  select * into c from contabilidad_config where id = 1;
  if not found then
    raise exception 'Falta la configuracion contable (contabilidad_config): sin ella no se sabe a que cuentas va la venta.';
  end if;
  if c.iva_ventas_pct is null then
    raise exception 'Falta definir el IVA de las ventas web: 0 si MAGANDHI no es responsable de IVA, 5 o 19 si lo es (precio con IVA incluido). Se define una sola vez en contabilidad_config.iva_ventas_pct; lo confirma el contador.';
  end if;

  select total into v_total from pedidos where id = p_pedido_id;
  if v_total is null then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_total <= 0 then
    raise exception 'El pedido no tiene un total positivo: no hay venta que registrar.';
  end if;

  -- Costo de venta = costo_unitario ACTUAL del producto x cantidad (no hay costo
  -- por lote). null = costo desconocido: NO se inventa, la venta queda pendiente.
  -- D2c.2b: los productos PROPIOS conservan exactamente la regla de F3.
  select string_agg(distinct pr.nombre, ', ') filter (where pr.costo_unitario is null),
         coalesce(sum(pi.cantidad::bigint * pr.costo_unitario), 0)
    into v_sin_costo, v_costo
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
   where pi.pedido_id = p_pedido_id
     and coalesce(pr.origen, 'propio') = 'propio';

  -- Los de PROVEEDOR traen su costo y su flete de pedido_proveedor, con los
  -- numeros REALES que Dropi cobro. null = todavia no se transcribio el pedido:
  -- no se inventa nada, la venta queda pendiente con un motivo que dice que
  -- hacer.
  select coalesce(sum(r.costo_real), 0),
         coalesce(sum(r.flete), 0),
         coalesce(sum(coalesce(r.seguro, 0)), 0),
         string_agg(distinct pr.nombre, ', ')
           filter (where r.costo_real is null or r.flete is null),
         string_agg(distinct pr.nombre, ', ')
    into v_costo_prov, v_flete_prov, v_seguro_prov, v_sin_dato, v_prov_nombres
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
    left join pedido_proveedor r
           on r.pedido_id = pi.pedido_id and r.product_id = pi.product_id
   where pi.pedido_id = p_pedido_id
     and pr.origen = 'proveedor';

  -- La lista de productos para los detalles incluye a todos, como siempre.
  select string_agg(pr.nombre || ' x ' || pi.cantidad, ', ' order by pr.nombre)
    into v_productos
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
   where pi.pedido_id = p_pedido_id;

  if v_productos is null then
    raise exception 'El pedido no tiene productos: no hay venta que registrar.';
  end if;
  if v_sin_costo is not null then
    raise exception 'Falta el costo unitario de «%» en Inventario. Registralo en la ficha del producto y vuelve a generar el asiento (no se inventa un costo).', v_sin_costo;
  end if;
  -- Mensaje DISTINTO a proposito: para un producto de proveedor no hay ficha de
  -- Inventario que llenar. El dato llega del panel de Dropi cuando el dueno
  -- transcribe el pedido, y la accion correctiva esta en Ventas, no en
  -- Inventario. Decirle «registralo en Inventario» lo mandaria a un sitio donde
  -- no puede hacer nada.
  if v_sin_dato is not null then
    raise exception 'DS_COSTO_PROVEEDOR_PENDIENTE: falta el costo real y el flete que Dropi descontó por «%». Transcribe el pedido en Dropi y registra esos dos numeros en Ventas; recien entonces el asiento puede cuadrar (no se inventan).', v_sin_dato;
  end if;

  -- IVA incluido en el precio: base = total / (1 + t), redondeada al peso; el
  -- IVA es la diferencia, asi el asiento SIEMPRE cuadra.
  if c.iva_ventas_pct > 0 then
    v_base := round(v_total::numeric * 100 / (100 + c.iva_ventas_pct))::bigint;
    v_iva  := v_total - v_base;
  else
    v_base := v_total;
  end if;

  -- La referencia de Wompi va en la DESCRIPCION del asiento (la que muestra el
  -- Libro Mayor): con ella se concilia cada venta contra la consignacion.
  v_lineas := jsonb_build_array(
    jsonb_build_object('cuenta_codigo', c.cuenta_pasarela,
                       'detalle', 'Wompi por liquidar',
                       'debe', v_total, 'haber', 0),
    jsonb_build_object('cuenta_codigo', c.cuenta_ingreso,
                       'detalle', 'Venta web: ' || v_productos,
                       'debe', 0, 'haber', v_base));
  if v_iva > 0 then
    v_lineas := v_lineas || jsonb_build_object('cuenta_codigo', c.cuenta_iva_generado,
                       'detalle', 'IVA generado ' || c.iva_ventas_pct || ' % (incluido en el precio)',
                       'debe', 0, 'haber', v_iva);
  end if;
  -- Producto PROPIO: el costo sale del inventario. Identico a F3.
  if v_costo > 0 then
    v_lineas := v_lineas
      || jsonb_build_object('cuenta_codigo', c.cuenta_costo,
                            'detalle', 'Costo de venta: ' || v_productos,
                            'debe', v_costo, 'haber', 0)
      || jsonb_build_object('cuenta_codigo', c.cuenta_inventario,
                            'detalle', 'Salida de inventario: ' || v_productos,
                            'debe', 0, 'haber', v_costo);
  end if;

  -- Producto de PROVEEDOR: el costo y el flete salen del SALDO EN DROPI, no de
  -- un inventario que nunca existio. El contador lo aprobo asi el 10-oct-2026:
  --   D 613505 costo de ventas      (lo que costo la mercancia)
  --   D 523535 fletes               (gasto de VENDER: el envio va en el precio)
  --   C 138010 saldo en Dropi       (de ahi salio la plata)
  if v_costo_prov > 0 or v_flete_prov > 0 or v_seguro_prov > 0 then
    if v_costo_prov > 0 then
      v_lineas := v_lineas
        || jsonb_build_object('cuenta_codigo', c.cuenta_costo,
                              'detalle', 'Costo de venta (proveedor): ' || v_prov_nombres,
                              'debe', v_costo_prov, 'haber', 0);
    end if;
    if v_flete_prov > 0 then
      v_lineas := v_lineas
        || jsonb_build_object('cuenta_codigo', c.cuenta_flete,
                              'detalle', 'Flete del despacho: ' || v_prov_nombres,
                              'debe', v_flete_prov, 'haber', 0);
    end if;
    if v_seguro_prov > 0 then
      v_lineas := v_lineas
        || jsonb_build_object('cuenta_codigo', c.cuenta_seguro,
                              'detalle', 'Seguro del envio: ' || v_prov_nombres,
                              'debe', v_seguro_prov, 'haber', 0);
    end if;
    v_lineas := v_lineas
      || jsonb_build_object('cuenta_codigo', c.cuenta_saldo_proveedor,
                            'detalle', 'Descontado del saldo en Dropi: ' || v_prov_nombres,
                            'debe', 0, 'haber', v_costo_prov + v_flete_prov + v_seguro_prov);
  end if;

  -- La misma regla de oro de los asientos manuales: enteros, imputables, cuadre.
  perform fz_validar_lineas(v_lineas);
  return v_lineas;
end;
$function$
;

comment on function fz__lineas_venta_web(uuid) is
  'F3 + D2c.3 · arma las lineas del asiento de una venta web. Producto PROPIO: costo contra inventario (143505), sin cambios. Producto de PROVEEDOR: costo (613505), flete (523535) y, si se aseguro, seguro (523095) contra el SALDO EN DROPI (138010), porque nunca hubo inventario que descargar. El seguro es OPCIONAL y no bloquea: null o 0 es «no se aseguro». Si falta el costo real o el flete si falla, con DS_COSTO_PROVEEDOR_PENDIENTE, y la venta queda pendiente: esos numeros los trae el dueno del panel de Dropi al transcribir el pedido, y NO se inventan.';

-- ----------------------------------------------------------------------------
-- (D) Capturarlo al transcribir el pedido
-- ----------------------------------------------------------------------------
-- Se BORRA la version de 8 argumentos antes de crear la de 9. Si se dejaran las
-- dos, PostgREST tendria dos candidatas para la misma llamada por nombre y la
-- resolucion quedaria ambigua.
drop function if exists ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text);
CREATE OR REPLACE FUNCTION public.ds_registrar_transcripcion(p_pedido_id uuid, p_product_id uuid, p_pedido_externo_id text, p_costo_real bigint DEFAULT NULL::bigint, p_flete bigint DEFAULT NULL::bigint, p_ciudad text DEFAULT NULL::text, p_departamento text DEFAULT NULL::text, p_notas text DEFAULT NULL::text, p_seguro bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ext text := nullif(trim(coalesce(p_pedido_externo_id, '')), '');
  v_fila pedido_proveedor;
begin
  if not (tiene_acceso_ventas() or tiene_acceso_dropshipping()) then
    raise exception 'Acceso denegado: se requiere Ventas o Dropshipping.';
  end if;
  if v_ext is null then
    raise exception 'DS_FALTA_PEDIDO_EXTERNO: anota el numero de pedido que te dio Dropi. Sin el no se puede verificar despues si el pedido existe, y es lo que evita crearlo dos veces.';
  end if;
  if length(v_ext) > 60 then
    raise exception 'El numero de pedido de Dropi es demasiado largo.';
  end if;
  if p_costo_real is not null and p_costo_real < 0 then
    raise exception 'El costo real no puede ser negativo.';
  end if;
  if p_flete is not null and p_flete < 0 then
    raise exception 'El flete no puede ser negativo.';
  end if;
  if p_seguro is not null and p_seguro < 0 then
    raise exception 'El seguro no puede ser negativo.';
  end if;

  select * into v_fila from pedido_proveedor
   where pedido_id = p_pedido_id and product_id = p_product_id;
  if not found then
    raise exception 'Ese pedido no tiene un despacho de proveedor pendiente.';
  end if;
  if v_fila.transcrito_en is not null then
    -- Idempotente de hecho: no se re-transcribe, pero se pueden COMPLETAR el
    -- costo y el flete, que suelen llegar despues.
    update pedido_proveedor
       set costo_real = coalesce(p_costo_real, costo_real),
           flete      = coalesce(p_flete, flete),
           seguro     = coalesce(p_seguro, seguro),
           notas      = coalesce(nullif(trim(coalesce(p_notas,'')), ''), notas),
           actualizado = now()
     where pedido_id = p_pedido_id and product_id = p_product_id;
    return jsonb_build_object('ya_estaba', true, 'pedido_externo_id', v_fila.pedido_externo_id);
  end if;

  update pedido_proveedor
     set transcrito_en     = now(),
         transcrito_por    = auth.uid(),
         pedido_externo_id = v_ext,
         costo_real        = p_costo_real,
         flete             = p_flete,
         seguro            = p_seguro,
         destino_ciudad    = coalesce(nullif(trim(coalesce(p_ciudad,'')), ''),
                                      (select ciudad from pedidos where id = p_pedido_id)),
         destino_departamento = coalesce(nullif(trim(coalesce(p_departamento,'')), ''),
                                      (select departamento from pedidos where id = p_pedido_id)),
         notas             = nullif(trim(coalesce(p_notas,'')), ''),
         actualizado       = now()
   where pedido_id = p_pedido_id and product_id = p_product_id;

  -- NO se escribe en pedido_bitacora. Su `accion` es una lista cerrada
  -- (crear/cambio_estado/anular) y ninguna describe esto: forzar una de ellas
  -- seria registrar un hecho falso, y ampliar un CHECK historico por un dato
  -- redundante no se justifica. El rastro completo ya vive en esta misma fila:
  -- transcrito_en (cuando), transcrito_por (quien) y pedido_externo_id (que).
  --
  -- Lo que SI puede cambiar despues es el costo y el flete, porque Dropi no
  -- siempre los muestra a la vez. Si el asiento ya se registro, cambiarlos aqui
  -- NO lo reescribe: los asientos automaticos se marcan y no se editan (F3).

  return jsonb_build_object('ya_estaba', false, 'pedido_externo_id', v_ext);
end;
$function$
;

comment on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text, bigint) is
  'D2c.3 · el dueno anota que ya creo el pedido en el panel de Dropi A MANO, con su numero externo, el costo real, el flete, el SEGURO si lo contrato, y el destino. Exige el numero externo porque es lo que permite verificar despues y lo que evita duplicar el pedido. El costo, el flete y el seguro pueden completarse en una segunda llamada (Dropi no siempre los muestra a la vez); mientras falten el costo o el flete el asiento queda pendiente, pero el SEGURO no bloquea nunca porque es opcional. El flete y el destino se guardan desde el primer pedido para que Metricas tenga historico.';

revoke all on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text, bigint) from public;
grant execute on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text, bigint) to authenticated, service_role;

commit;
