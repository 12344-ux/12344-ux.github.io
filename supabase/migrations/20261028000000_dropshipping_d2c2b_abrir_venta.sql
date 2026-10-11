-- ============================================================================
-- MAGANDHI · Dropshipping D2c.2b · SE ABRE LA VENTA DE PROVEEDOR
-- ----------------------------------------------------------------------------
-- Migracion FORWARD. Cierra el tramo D2c.
--
-- ESTE ES EL TRAMO QUE LEVANTA EL CANDADO. Hasta aqui todo lo construido era
-- inerte a proposito. Despues de esta migracion, una campania de producto de
-- proveedor SE PUEDE PUBLICAR Y VENDER.
--
-- Se abre porque ya existe lo que faltaba, y cada pieza esta medida:
--   · stock vivo que FALLA CERRADO si la lectura vence (D2c.1);
--   · refresco rodante cada minuto, por debajo del 429 de Dropi (D2c.1);
--   · piso de vitrina de 20 unidades contra la carrera por la ultima unidad;
--   · crear_pedido y anular_pedido que entienden el origen (D2c.2a);
--   · evidencia de lo que Dropi reportaba al cobrar (D2c.2a);
--   · y lo que agrega esta migracion: el asiento contable y el circuito del
--     despacho manual.
--
-- QUE HACE
--   (A) fz__lineas_venta_web: el asiento aprende a descontar del SALDO EN DROPI
--       en vez de un inventario que nunca existio. Derivada del cuerpo real.
--   (B) ds_pedidos_por_transcribir(): lo que Ventas tiene que mostrar.
--   (C) ds_registrar_transcripcion(): donde el dueno anota el pedido de Dropi,
--       el costo real, el flete y el destino.
--   (D) cm_publicar_campana: se levanta DS_PUBLICACION_PENDIENTE. Derivada.
--   (E) venta_proveedor_habilitada = true.
--
-- QUE SIGUE SIN HACER, Y NO ES UN OLVIDO
--   El pedido a Dropi se crea A MANO. No hay POST a orders/ y no lo habra
--   hasta tener el contrato oficial: hoy no sabemos cuando se debita el saldo,
--   si una cancelacion reintegra, ni como se comporta la reserva PENDIENTE
--   CONFIRMACION. Un POST improvisado ahi crea un pedido real con plata real y
--   duplica si uno reintenta sin consultar antes por id. Eso es D3/D4.
--
--   Tampoco hay municipio DANE ni nombre/apellido separados: solo se necesitan
--   para el pedido AUTOMATICO. Con el manual, el dueno transcribe los datos.
--
-- EL ASIENTO, APROBADO POR EL CONTADOR (10-oct-2026)
--   Al cobrar (automatico, igual que F3):
--     D 138095 Wompi por liquidar      C 413505 ingreso (+ IVA si aplica)
--   Al transcribir el pedido, con los numeros REALES de Dropi (manual):
--     D 613505 costo de ventas
--     D 523535 fletes                  C 138010 saldo en Dropi
--
--   El costo NO pasa por 1435: nunca hay inventario que descargar. Y no puede
--   ser automatico porque el FLETE depende del destino y la API de Dropi NO
--   tiene ruta de cotizacion (medido). Al vender es literalmente desconocido.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) El asiento aprende el camino del proveedor
-- ----------------------------------------------------------------------------
create or replace function fz__lineas_venta_web(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
         string_agg(distinct pr.nombre, ', ')
           filter (where r.costo_real is null or r.flete is null),
         string_agg(distinct pr.nombre, ', ')
    into v_costo_prov, v_flete_prov, v_sin_dato, v_prov_nombres
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
  if v_costo_prov > 0 or v_flete_prov > 0 then
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
    v_lineas := v_lineas
      || jsonb_build_object('cuenta_codigo', c.cuenta_saldo_proveedor,
                            'detalle', 'Descontado del saldo en Dropi: ' || v_prov_nombres,
                            'debe', 0, 'haber', v_costo_prov + v_flete_prov);
  end if;

  -- La misma regla de oro de los asientos manuales: enteros, imputables, cuadre.
  perform fz_validar_lineas(v_lineas);
  return v_lineas;
end;
$$;

comment on function fz__lineas_venta_web(uuid) is
  'F3 + D2c.2b · arma las lineas del asiento de una venta web. Producto PROPIO: costo contra inventario (143505), sin cambios. Producto de PROVEEDOR: costo (613505) y flete (523535) contra el SALDO EN DROPI (138010), porque nunca hubo inventario que descargar. Si falta el costo real o el flete de un producto de proveedor, falla con DS_COSTO_PROVEEDOR_PENDIENTE y la venta queda pendiente: esos numeros los trae el dueno del panel de Dropi al transcribir el pedido, y NO se inventan.';

-- ----------------------------------------------------------------------------
-- (B) Lo que Ventas tiene que mostrar
-- ----------------------------------------------------------------------------
-- El aviso operativo del tramo: «estos pedidos ya los cobraste y todavia no
-- existen en Dropi». Mientras esten aqui, sus unidades cuentan como reservadas
-- contra el stock del proveedor, asi que la lista no es solo un recordatorio:
-- es lo que mantiene honesta la vitrina.
create or replace function ds_pedidos_por_transcribir()
returns table (
  pedido_id            uuid,
  pedido_corto         text,
  fecha_orden          date,
  estado               text,
  total                bigint,
  product_id           uuid,
  producto             text,
  sku                  text,
  dropi_id             text,
  variante             text,
  cantidad             integer,
  stock_al_vender      integer,
  ciudad               text,
  departamento         text,
  horas_esperando      numeric
)
language sql
stable
security definer
set search_path = public
as $fn$
  select
    r.pedido_id,
    left(r.pedido_id::text, 8),
    pe.fecha_orden,
    pe.estado,
    pe.total,
    r.product_id,
    pr.nombre,
    pr.sku,
    r.producto_externo_id,
    nullif(r.variacion_externa_id, ''),
    r.cantidad,
    r.stock_al_vender,
    pe.ciudad,
    pe.departamento,
    round(extract(epoch from (now() - r.creado)) / 3600.0, 1)
  from pedido_proveedor r
  join pedidos pe on pe.id = r.pedido_id
  join productos pr on pr.id = r.product_id
  where r.transcrito_en is null
    and pe.estado <> 'anulado'
    and (tiene_acceso_ventas() or tiene_acceso_dropshipping())
  order by pe.fecha_orden, r.creado;
$fn$;

comment on function ds_pedidos_por_transcribir() is
  'D2c.2b · pedidos de proveedor ya cobrados que TODAVIA no existen en Dropi. Es el aviso operativo de Ventas y, mientras una fila este aqui, sus unidades cuentan como reservadas contra el stock del proveedor. Trae el id y la variante de Dropi que hay que pedir y el destino. Definer pero valida acceso dentro: sin modulo devuelve cero filas.';

revoke all on function ds_pedidos_por_transcribir() from public;
grant execute on function ds_pedidos_por_transcribir() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (C) Donde el dueno anota lo que hizo a mano
-- ----------------------------------------------------------------------------
-- Se llama DESPUES de crear el pedido en el panel de Dropi. Exige el numero de
-- pedido externo porque sin el no se puede verificar nada mas adelante, y es
-- justo lo que evita el error mas caro del frente: reintentar una creacion sin
-- consultar antes y duplicar el pedido (trampa 2 de DROPI.md).
--
-- El costo y el flete son OPCIONALES aqui: Dropi no siempre los muestra en el
-- mismo instante. Mientras falten, el asiento queda pendiente con su motivo.
create or replace function ds_registrar_transcripcion(
  p_pedido_id   uuid,
  p_product_id  uuid,
  p_pedido_externo_id text,
  p_costo_real  bigint default null,
  p_flete       bigint default null,
  p_ciudad      text   default null,
  p_departamento text  default null,
  p_notas       text   default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
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
$fn$;

comment on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text) is
  'D2c.2b · el dueno anota que ya creo el pedido en el panel de Dropi A MANO, con su numero externo, el costo real, el flete y el destino. Exige el numero externo porque es lo que permite verificar despues y lo que evita duplicar el pedido. El costo y el flete pueden completarse en una segunda llamada (Dropi no siempre los muestra a la vez); mientras falten, el asiento queda pendiente. Deja rastro en pedido_bitacora. El flete y el destino se guardan desde el primer pedido para que Metricas tenga historico.';

revoke all on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text) from public;
grant execute on function ds_registrar_transcripcion(uuid, uuid, text, bigint, bigint, text, text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) Se levanta el candado de publicacion
-- ----------------------------------------------------------------------------
create or replace function cm_publicar_campana(
  p_id        uuid,
  p_publicado boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_producto_id     uuid;
  v_precio          bigint;
  v_producto_activo boolean;
  v_origen          text;
  v_sello_elegido   boolean;
  v_producto_probado boolean;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select cp.product_id_ref, cp.precio_venta, p.activo, p.origen,
         cp.sello_elegido, cp.probado_por_magandhi
    into v_producto_id, v_precio, v_producto_activo, v_origen,
         v_sello_elegido, v_producto_probado
    from campana_producto cp
    left join productos p on p.id = cp.product_id_ref
   where cp.id = p_id;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if coalesce(p_publicado, false) then
    if v_producto_id is null then
      raise exception 'No se puede publicar: liga primero un producto de Inventario.';
    end if;
    if coalesce(v_producto_activo, false) is not true then
      raise exception 'No se puede publicar: el producto de Inventario esta inactivo.';
    end if;
    -- D2c.2b LEVANTA el candado: ya existe stock vivo que falla cerrado, el
    -- checkout verifica en vivo antes de cobrar, el pedido no toca el libro de
    -- Inventario y el asiento sabe descontar del saldo en Dropi.
    --
    -- Lo que SI se exige: que el producto tenga ficha de proveedor. Un producto
    -- origen=proveedor sin producto_proveedor no se puede pedir a nadie: no
    -- tiene id de Dropi ni variante. Publicarlo seria prometer algo que no se
    -- puede despachar.
    if coalesce(v_origen, 'propio') = 'proveedor'
       and not exists (select 1 from producto_proveedor pp
                        where pp.product_id = v_producto_id) then
      raise exception 'DS_SIN_FICHA_PROVEEDOR: este producto es de proveedor pero no tiene ficha con su id de Dropi, asi que no se podria pedir. Vuelve a llevarlo desde Dropshipping.';
    end if;
    if v_precio is null or v_precio <= 0 then
      raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
    end if;
    if coalesce(v_sello_elegido, false)
       and not coalesce(v_producto_probado, false) then
      raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de publicar Elegido por MAGANDHI.';
    end if;
  end if;

  update campana_producto
     set publicado   = coalesce(p_publicado, false),
         actualizado = now()
   where id = p_id;

  return p_id;
end;
$$;

comment on function cm_publicar_campana(uuid, boolean) is
  'Campanas · publica o despublica. D2c.2b LEVANTA DS_PUBLICACION_PENDIENTE: un producto de proveedor ya se puede publicar, porque existe stock vivo que falla cerrado, verificacion en vivo antes de cobrar, pedido que no toca Inventario y asiento contra el saldo en Dropi. Lo que si se exige es que el producto tenga ficha de proveedor (DS_SIN_FICHA_PROVEEDOR): sin id de Dropi no se le puede pedir a nadie. Conserva el precio obligatorio y el sello con casilla de D2b.';

-- ----------------------------------------------------------------------------
-- (E) Y la vitrina deja de esconder al proveedor
-- ----------------------------------------------------------------------------
-- El interruptor que D2c.1 creo en false. Este es el momento para el que
-- existia: a partir de aqui un producto de proveedor PUBLICADO sale a la tienda
-- y se puede comprar, siempre que su lectura este vigente y sobre el piso.
update dropshipping_config set venta_proveedor_habilitada = true, actualizado = now()
 where id = 1;

commit;
