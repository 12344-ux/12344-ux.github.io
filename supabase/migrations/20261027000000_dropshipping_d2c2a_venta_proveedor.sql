-- ============================================================================
-- MAGANDHI · Dropshipping D2c.2a · LA VENTA DE PROVEEDOR (nucleo en la base)
-- ----------------------------------------------------------------------------
-- Migracion FORWARD. No reescribe ni reejecuta ninguna historica.
--
-- Este es el tramo que hace POSIBLE vender un producto de proveedor. Hasta hoy
-- era imposible por dos razones medidas, no teoricas:
--   · crear_pedido lo RECHAZABA con STOCK_INSUFICIENTE, porque un producto de
--     proveedor no tiene fila en stock_actual (no tiene libro de inventario);
--   · anular_pedido habria FALLADO al intentar devolver stock, porque el
--     gatillo de D1 bloquea cualquier movimiento de inventario de proveedor.
--
-- QUE HACE
--   (A) contabilidad_config: las dos cuentas que aprobo el contador.
--   (B) pedido_proveedor: que hay que despachar, con que flete y a donde.
--   (C) ventas_disponible_para_venta(): UNA puerta para «cuantas unidades
--       puedo vender», que sabe de donde leer segun el origen.
--   (D) crear_pedido: ramifica por origen. Derivada del cuerpo real.
--   (E) anular_pedido: solo compensa inventario propio. Derivada del real.
--   (F) catalogo_publico: resta los pedidos pagados aun sin transcribir.
--   (G) vara de entrada: deja de ser un numero decorativo y se impone.
--
-- QUE NO HACE (sigue siendo INERTE)
--   - NO levanta DS_PUBLICACION_PENDIENTE ni venta_proveedor_habilitada: una
--     campania de proveedor sigue sin poder publicarse, asi que nada de esto
--     se puede ejecutar todavia desde la tienda. Lo abre D2c.2b;
--   - no cambia el asiento contable (D2c.2b);
--   - no toca la pantalla de Ventas (D2c.2b);
--   - no llama a orders/ de Dropi. El pedido se transcribe A MANO. El POST
--     automatico es D3/D4 y no se improvisa: sin contrato oficial no se sabe
--     cuando se debita el saldo, si una cancelacion reintegra, ni como se
--     comporta la reserva PENDIENTE CONFIRMACION.
--
-- POR QUE LAS DOS FUNCIONES NUCLEO SE DERIVAN Y NO SE RETIPEAN
-- crear_pedido y anular_pedido son el corazon de TODAS las ventas, propias
-- incluidas. Sus cuerpos se tomaron del archivo de la migracion vigente y se
-- les aplicaron cambios puntuales verificados uno por uno. Retipear 300 lineas
-- a mano es la forma de introducir un bug en la venta de productos propios, que
-- hoy funciona.
--
-- CUENTAS (aprobadas por el contador, 10-oct-2026)
--   · 138010 saldo en Dropi, bajo 1380 Deudores varios. NO es un anticipo: no
--     esta asignado a ningun proveedor (son muchos y cambian) y nadie ha
--     facturado nada. Misma naturaleza que 138095 «Wompi por liquidar».
--   · 523535 Transporte, fletes y acarreos. El envio va incluido en el precio,
--     asi que no es costo de la mercancia: es gasto de VENDER.
--   · 613505 el costo, directo, sin pasar por 1435. Nunca hay inventario que
--     descargar: no tener la mercancia fisicamente no es lo mismo que no
--     haberla comprado. MAGANDHI es el vendedor, factura y responde garantia.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Las dos cuentas nuevas
-- ----------------------------------------------------------------------------
-- PRIMERO hay que CREARLAS en el catalogo: ninguna de las dos venia en la carga
-- inicial del PUC, y el validador de asientos rechaza una cuenta que no existe
-- («La cuenta 523535 no existe en el catalogo PUC»). Mismo precedente que F3,
-- que creo 138095 en su propia migracion.
--
-- 1380 DEUDORES VARIOS y 5235 SERVICIOS ya existen como encabezado, asi que
-- solo faltan las subcuentas de detalle (nivel 4, imputables).
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  ('138010', 'SALDO A FAVOR EN PLATAFORMA DE PROVEEDOR', 4, 'debito', true, '1380'),
  ('523535', 'TRANSPORTE, FLETES Y ACARREOS',             4, 'debito', true, '5235')
on conflict (codigo) do nothing;

-- Van en configuracion, como el resto: cambiarlas no exige una migracion.
alter table contabilidad_config
  add column if not exists cuenta_saldo_proveedor text not null default '138010',
  add column if not exists cuenta_flete           text not null default '523535';

update contabilidad_config set cuenta_saldo_proveedor = '138010'
  where id = 1 and coalesce(cuenta_saldo_proveedor, '') = '';
update contabilidad_config set cuenta_flete = '523535'
  where id = 1 and coalesce(cuenta_flete, '') = '';

comment on column contabilidad_config.cuenta_saldo_proveedor is
  'Saldo a favor en la plataforma del proveedor (default 138010, bajo 1380 Deudores varios). Plata nuestra en custodia de un tercero, de la que Dropi descuenta costo y flete por cada pedido. Aprobada por el contador el 10-oct-2026. La ACREDITA el asiento del costo proveedor; la DEBITA la recarga manual contra el banco.';
comment on column contabilidad_config.cuenta_flete is
  'Flete que el proveedor descuenta (default 523535 Transporte, fletes y acarreos). Es gasto de VENTAS, no costo de la mercancia, porque el envio va incluido en el precio y no se cobra aparte. Aprobada por el contador el 10-oct-2026.';

-- ----------------------------------------------------------------------------
-- (B) Que hay que despachar, con que flete y a donde
-- ----------------------------------------------------------------------------
-- Una fila por producto de proveedor dentro de un pedido. Nace al vender, con
-- la EVIDENCIA de lo que Dropi reportaba en ese momento, y se completa cuando
-- el dueno transcribe el pedido a mano en el panel de Dropi.
--
-- POR QUE GUARDAR EL FLETE Y EL DESTINO DESDE EL PRIMER PEDIDO (decision del
-- dueno): sin esto, Metricas no tendria NADA que analizar en tres meses y el
-- historico se perderia para siempre. Es lo que despues permitira decidir con
-- datos que destinos conviene centralizar.
create table if not exists pedido_proveedor (
  pedido_id            uuid    not null references pedidos(id) on delete restrict,
  product_id           uuid    not null references productos(id) on delete restrict,
  -- Snapshot de la identidad externa: si manana cambia producto_proveedor, este
  -- pedido conserva a que id y variante de Dropi correspondia.
  producto_externo_id  text    not null,
  variacion_externa_id text    not null default '',
  cantidad             integer not null check (cantidad > 0),
  -- EVIDENCIA al vender: cuanto reportaba Dropi y cuando se leyo.
  stock_al_vender      integer,
  stock_leido_en       timestamptz,
  -- Lo que el dueno completa al transcribir el pedido en Dropi.
  transcrito_en        timestamptz,
  transcrito_por       uuid references auth.users(id),
  pedido_externo_id    text    check (pedido_externo_id is null or length(pedido_externo_id) <= 60),
  costo_real           bigint  check (costo_real is null or costo_real >= 0),
  flete                bigint  check (flete is null or flete >= 0),
  destino_ciudad       text    check (destino_ciudad is null or length(destino_ciudad) <= 120),
  destino_departamento text    check (destino_departamento is null or length(destino_departamento) <= 120),
  notas                text    check (notas is null or length(notas) <= 500),
  creado               timestamptz not null default now(),
  actualizado          timestamptz,
  primary key (pedido_id, product_id),
  -- Transcrito es todo o nada en lo esencial: si se marco, tiene que haber
  -- numero de pedido en Dropi. El flete y el costo pueden llegar despues (Dropi
  -- no siempre los muestra en el mismo momento).
  constraint pedido_proveedor_transcrito_coherente check (
    (transcrito_en is null and pedido_externo_id is null)
    or (transcrito_en is not null and pedido_externo_id is not null)
  )
);

comment on table pedido_proveedor is
  'D2c.2a Dropshipping · una fila por producto de proveedor dentro de un pedido. Nace al vender con la EVIDENCIA de lo que Dropi reportaba (stock_al_vender, stock_leido_en) y se completa cuando el dueno transcribe el pedido A MANO en el panel de Dropi: numero externo, costo real, flete y destino. El flete y el destino se guardan desde el primer pedido porque sin ellos Metricas no tendria historico que analizar. NO se expone a anon.';
comment on column pedido_proveedor.stock_al_vender is
  'Cuantas unidades reportaba Dropi cuando se cobro. Es la prueba de que al vender SI habia: si el pedido falla despues por falta de stock, queda claro que no fue una venta a ciegas.';
comment on column pedido_proveedor.transcrito_en is
  'Cuando el dueno creo el pedido en el panel de Dropi, a mano. Mientras sea null, el pedido cuenta como RESERVADO contra el stock del proveedor en catalogo_publico: ya nos llevamos esas unidades aunque Dropi todavia no lo sepa.';
comment on column pedido_proveedor.flete is
  'Lo que Dropi descuento por el envio, en pesos enteros. Solo se conoce al transcribir: depende del destino y la API NO tiene ruta de cotizacion (medido el 10-oct-2026).';

create index if not exists pedido_proveedor_sin_transcribir_idx
  on pedido_proveedor (product_id) where transcrito_en is null;

alter table pedido_proveedor enable row level security;

drop policy if exists "pedido_proveedor_select_areas" on pedido_proveedor;
create policy "pedido_proveedor_select_areas" on pedido_proveedor
  for select to authenticated
  using (tiene_acceso_dropshipping() or tiene_acceso_ventas());

-- Auto-expose apagado: sin el grant, PostgREST responde 403 antes de RLS.
-- NO se concede INSERT/UPDATE/DELETE: solo las RPC escriben aqui.
grant select on table pedido_proveedor to authenticated;

-- ----------------------------------------------------------------------------
-- (C) UNA sola puerta para «cuantas unidades puedo vender»
-- ----------------------------------------------------------------------------
-- Antes de D2c.2 habia una sola fuente posible (stock_actual) y por eso estaba
-- escrita a mano dentro de crear_pedido. Ahora hay dos, y la decision no puede
-- quedar duplicada en cada consumidor: si manana cambia la regla del proveedor,
-- tiene que cambiar en UN lugar.
--
-- Para proveedor la disponibilidad es:
--   lectura vigente y sobre el piso  ->  stock reportado - pedidos sin transcribir
--   lectura vencida, ausente o bajo el piso  ->  0
--
-- La resta de los pedidos sin transcribir es la parte CONOCIDA del hueco entre
-- el cobro y el despacho: no sabemos si otro vendedor se llevo una unidad, pero
-- si sabemos cuantas nos llevamos nosotros y todavia no le dijimos a Dropi.
create or replace function ventas_disponible_para_venta(p_product_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $fn$
  select case
    when coalesce(p.origen, 'propio') = 'propio'
      then coalesce((select s.existencias from stock_actual s where s.product_id = p.id), 0)
    when pp.product_id is null
      or pp.stock_reportado is null
      or pp.stock_vence_en is null
      or pp.stock_vence_en <= now()
      or pp.stock_reportado < coalesce(pp.piso_vitrina, cfg.piso_vitrina, 20)
      then 0
    else greatest(
      pp.stock_reportado - coalesce((
        select sum(r.cantidad)
          from pedido_proveedor r
          join pedidos pe on pe.id = r.pedido_id
         where r.product_id = p.id
           and r.transcrito_en is null
           and pe.estado <> 'anulado'
      ), 0),
      0)::integer
  end
  from productos p
  left join producto_proveedor pp on pp.product_id = p.id
  left join (select piso_vitrina from dropshipping_config where id = 1) cfg on true
  where p.id = p_product_id;
$fn$;

comment on function ventas_disponible_para_venta(uuid) is
  'D2c.2a · unidades que se pueden vender de UN producto, sin importar su origen. Propio: el libro de Inventario. Proveedor: la lectura de Dropi si esta vigente y sobre el piso, MENOS los pedidos pagados que aun no se han transcrito a Dropi; 0 si la lectura vencio, falta o esta bajo el piso. Una sola puerta a proposito: la regla no puede quedar duplicada en cada consumidor.';

revoke all on function ventas_disponible_para_venta(uuid) from public;
grant execute on function ventas_disponible_para_venta(uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) crear_pedido: ramifica por origen
-- ----------------------------------------------------------------------------
create or replace function crear_pedido(
  p_customer_id    uuid    default null,
  p_nombre         text    default null,
  p_correo         text    default null,
  p_telefono       text    default null,
  p_direccion      text    default null,
  p_ciudad         text    default null,
  p_departamento   text    default null,
  p_pais           text    default null,
  p_notas_cliente  text    default null,
  p_canal          text    default 'manual',
  p_fecha_orden    date    default current_date,
  p_notas_pedido   text    default null,
  p_items          jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id   uuid := p_customer_id;
  v_correo_norm   text := ventas_norm_correo(p_correo);
  v_telefono_norm text := ventas_norm_telefono(p_telefono);
  v_canal         text := coalesce(nullif(trim(p_canal), ''), 'manual');
  v_fecha         date := coalesce(p_fecha_orden, current_date);
  v_pedido_id     uuid;
  v_total         bigint := 0;
  v_item          jsonb;
  v_product_id    uuid;
  v_cantidad      integer;
  v_precio        bigint;
  v_subtotal      bigint;
  v_activo        boolean;
  v_req           record;
  v_nom_prod      text;
  v_disponible    integer;
  v_origen        text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  if v_canal not in ('manual','web') then
    raise exception 'Canal invalido: %. Use manual o web.', v_canal;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe tener al menos un item.';
  end if;

  -- (0) BLOQUEO FIRME DE STOCK (decision del dueno, 2026-10-08) ------------
  -- No se registra un pedido que pida mas unidades de las que hay en el libro
  -- de Inventario. Se agrupa por producto (dos lineas del mismo producto suman)
  -- y se BLOQUEA LA FILA del producto (for update) en orden de id: dos pedidos
  -- simultaneos por la ultima unidad se serializan y solo el primero pasa. Vale
  -- para las dos puertas (manual hoy, web/Wompi F2 manana): el candado vive en
  -- el servidor, no en la pantalla. Todo es atomico: si falla, no se crea nada.
  for v_req in
    select (e->>'product_id')::uuid as product_id,
           sum((e->>'cantidad')::integer) as cantidad
      from jsonb_array_elements(p_items) e
     group by 1
     order by 1
  loop
    if v_req.product_id is null then
      raise exception 'Cada item requiere product_id.';
    end if;
    -- cantidad invalida: la valida el bucle de lineas de abajo con su mensaje.
    continue when v_req.cantidad is null or v_req.cantidad <= 0;

    select nombre into v_nom_prod from productos where id = v_req.product_id for update;
    if not found then
      raise exception 'El producto % no existe.', v_req.product_id;
    end if;

    -- D2c.2: la fuente del stock depende del ORIGEN del producto.
    --   propio    -> el libro de Inventario (identico a 2026-10-08)
    --   proveedor -> la ultima lectura de Dropi, que vale 0 si vencio
    -- Un producto de proveedor NO tiene fila en stock_actual, asi que con el
    -- codigo anterior toda venta de proveedor moria con STOCK_INSUFICIENTE.
    select coalesce(p.origen, 'propio') into v_origen
      from productos p where p.id = v_req.product_id;
    v_disponible := coalesce(ventas_disponible_para_venta(v_req.product_id), 0);

    if v_disponible < v_req.cantidad then
      if v_origen = 'proveedor' then
        raise exception 'STOCK_INSUFICIENTE: «%» reporta % unidad(es) disponible(s) en el proveedor y el pedido pide %. La lectura pudo vencer, caer bajo el piso de vitrina, o haber pedidos sin transcribir.',
          v_nom_prod, greatest(v_disponible, 0), v_req.cantidad;
      else
        raise exception 'STOCK_INSUFICIENTE: «%» tiene % unidad(es) disponible(s) y el pedido pide %. Registra primero la entrada en Inventario.',
          v_nom_prod, greatest(v_disponible, 0), v_req.cantidad;
      end if;
    end if;
  end loop;

  -- (1) RESOLVER CLIENTE ---------------------------------------------------
  if v_customer_id is null then
    -- Ante colision del UNIQUE parcial NO se cae ni se duplica (§4.5, el UNIQUE
    -- manda): se resuelve al cliente existente que ya tiene ese contacto.
    -- Precedencia: correo, luego telefono.
    if v_correo_norm is not null then
      select id into v_customer_id from clientes where correo_norm = v_correo_norm limit 1;
    end if;
    if v_customer_id is null and v_telefono_norm is not null then
      select id into v_customer_id from clientes where telefono_norm = v_telefono_norm limit 1;
    end if;

    -- Si sigue sin resolverse, es cliente nuevo: se crea con la normalizacion.
    if v_customer_id is null then
      if p_nombre is null or length(trim(p_nombre)) = 0 then
        raise exception 'Para un cliente nuevo el nombre es obligatorio.';
      end if;
      insert into clientes (
        nombre, correo, correo_norm, telefono, telefono_norm,
        direccion, ciudad, departamento, pais, notas
      ) values (
        trim(p_nombre), p_correo, v_correo_norm, p_telefono, v_telefono_norm,
        p_direccion, p_ciudad, p_departamento,
        coalesce(nullif(trim(p_pais), ''), 'Colombia'), p_notas_cliente
      )
      returning id into v_customer_id;
    end if;
  else
    -- Se paso un customer_id explicito: validar que exista.
    perform 1 from clientes where id = v_customer_id;
    if not found then
      raise exception 'El cliente % no existe.', v_customer_id;
    end if;
  end if;

  -- (2) CREAR LA ORDEN -----------------------------------------------------
  -- D2.2: se estampa la direccion de entrega como SNAPSHOT del pedido, ademas de
  -- usarse arriba para el cliente. Editar despues la ficha del cliente NO
  -- reescribe estas columnas: son a donde se envio ESTA orden.
  insert into pedidos (
    customer_id, fecha_orden, estado, canal, total, notas,
    direccion, ciudad, departamento, pais
  )
  values (
    v_customer_id, v_fecha, 'recibido', v_canal, 0, p_notas_pedido,
    p_direccion, p_ciudad, p_departamento,
    coalesce(nullif(trim(p_pais), ''), 'Colombia')
  )
  returning id into v_pedido_id;

  -- (3) LINEAS + TOTAL, y (4) BAJA DE STOCK por cada item ------------------
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_cantidad   := (v_item->>'cantidad')::integer;
    v_precio     := (v_item->>'precio_unitario')::bigint;

    if v_product_id is null then
      raise exception 'Cada item requiere product_id.';
    end if;
    if v_cantidad is null or v_cantidad <= 0 then
      raise exception 'La cantidad de cada item debe ser un entero positivo.';
    end if;
    if v_precio is null or v_precio < 0 then
      raise exception 'El precio_unitario de cada item debe ser un bigint no negativo.';
    end if;

    -- VALIDACION DE PRODUCTO (mismo chequeo que inv_registrar_movimiento): el
    -- producto debe existir Y estar activo antes de tocar el libro. La FK de
    -- pedido_items.product_id atrapa el inexistente, pero NO el inactivo; sin
    -- este chequeo un producto dado de baja (activo=false) pasaria. El picker
    -- manual ya filtra activo=true, pero la puerta web futura invoca el mismo
    -- nucleo y no necesariamente filtra igual: cerramos la divergencia
    -- server-side para no depender del cliente.
    select activo, coalesce(origen, 'propio') into v_activo, v_origen
      from productos where id = v_product_id;
    if v_activo is null then
      raise exception 'El producto % no existe.', v_product_id;
    end if;
    if not v_activo then
      raise exception 'El producto % esta inactivo; no admite movimientos.', v_product_id;
    end if;

    v_subtotal := v_cantidad::bigint * v_precio;
    v_total := v_total + v_subtotal;

    insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
    values (v_pedido_id, v_product_id, v_cantidad, v_precio, v_subtotal);

    -- BAJA DE STOCK: insert directo de la 'salida' en el libro (ver DECISION DE
    -- CRITERIO en la cabecera). Mismo conjunto de columnas y logica de signo que
    -- inv_registrar_movimiento; estampa customer_id y referencia=pedido_id. Una
    -- salida sin stock NO se bloquea (contrato del libro, §2).
    -- D2c.2: SOLO el producto propio toca el libro. Un producto de proveedor
    -- no tiene inventario nuestro que descargar, y el gatillo de D1 lo
    -- impediria incluso por encima de RLS. En su lugar queda la ficha del
    -- despacho pendiente, con EVIDENCIA de lo que Dropi reportaba al vender:
    -- si manana el pedido falla por falta de stock, queda demostrado que al
    -- cobrar si habia.
    if v_origen = 'proveedor' then
      insert into pedido_proveedor (
        pedido_id, product_id, producto_externo_id, variacion_externa_id,
        cantidad, stock_al_vender, stock_leido_en
      )
      select v_pedido_id, v_product_id, pp.producto_externo_id, pp.variacion_externa_id,
             v_cantidad, pp.stock_reportado, pp.stock_leido_en
        from producto_proveedor pp
       where pp.product_id = v_product_id
      on conflict (pedido_id, product_id) do update
        set cantidad = pedido_proveedor.cantidad + excluded.cantidad;
    else
      insert into movimientos_inventario (
        product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
      ) values (
        v_product_id, 'salida', v_cantidad, 'Venta', v_pedido_id::text, v_customer_id, v_fecha
      );
    end if;
  end loop;

  -- Total definitivo del pedido (bigint).
  update pedidos set total = v_total, actualizado = now() where id = v_pedido_id;

  -- D2.1: evento 'crear' en la bitacora. Estado inicial 'recibido' (sin estado
  -- anterior). Es la fuente unica del evento de creacion (no hay trigger).
  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    v_pedido_id, 'crear', null, 'recibido',
    jsonb_build_object('canal', v_canal, 'total', v_total, 'customer_id', v_customer_id),
    auth.uid()
  );

  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'customer_id', v_customer_id,
    'total', v_total
  );
end;
$$;

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is
  'NUCLEO UNICO de creacion de pedido (manual y web). D2c.2a: ramifica por productos.origen. PROPIO se comporta igual que antes (bloqueo de stock contra el libro y salida de inventario). PROVEEDOR lee la disponibilidad de ventas_disponible_para_venta (lectura de Dropi vigente, sobre el piso y menos los pedidos sin transcribir) y NO toca el libro: deja una fila en pedido_proveedor con la evidencia de lo que Dropi reportaba al cobrar. Conserva el bloqueo de fila que serializa ventas simultaneas, la resolucion de cliente, el snapshot de direccion y la bitacora. Exige tiene_acceso_ventas().';

-- ----------------------------------------------------------------------------
-- (E) anular_pedido: solo compensa inventario propio
-- ----------------------------------------------------------------------------
create or replace function anular_pedido(
  p_pedido_id uuid,
  p_motivo    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado     boolean;
  v_customer_id uuid;
  v_fecha       date;
  v_estado_ant  text;
  v_revertidos  integer := 0;
  v_item        record;
  v_reverso     jsonb;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  -- TRAMO 0: FOR UPDATE bloquea la fila del pedido hasta el fin de la
  -- transaccion. Una anulacion concurrente espera aqui y luego lee el valor
  -- ya actualizado (anulado=true), por lo que no revierte dos veces.
  select anulado, customer_id, fecha_orden, estado
    into v_anulado, v_customer_id, v_fecha, v_estado_ant
    from pedidos
   where id = p_pedido_id
     for update;

  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  -- Si ya estaba anulado, no se revierte otra vez (evita entradas duplicadas).
  if v_anulado then
    return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', 0);
  end if;

  -- Marca la anulacion logica (nunca DELETE).
  update pedidos
     set anulado = true,
         estado = 'anulado',
         motivo_anulacion = p_motivo,
         actualizado = now()
   where id = p_pedido_id;

  -- Entrada compensatoria por cada linea (devuelve al inventario lo restado).
  -- No se exige producto activo: anular una venta de un producto dado de baja
  -- debe poder devolver el stock (ver 20250603000000).
  for v_item in
    -- D2c.2: solo se compensa INVENTARIO PROPIO. Un producto de proveedor no
    -- bajo stock al vender, asi que no hay nada que devolver; y el gatillo de
    -- D1 rechazaria el movimiento, haciendo fallar la anulacion entera.
    select pi.product_id, pi.cantidad
      from pedido_items pi
      join productos p on p.id = pi.product_id
     where pi.pedido_id = p_pedido_id
       and coalesce(p.origen, 'propio') = 'propio'
  loop
    insert into movimientos_inventario (
      product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
    ) values (
      v_item.product_id, 'entrada', v_item.cantidad, 'Anulacion de venta',
      p_pedido_id::text, v_customer_id, coalesce(v_fecha, current_date)
    );
    v_revertidos := v_revertidos + 1;
  end loop;

  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    p_pedido_id, 'anular', v_estado_ant, 'anulado',
    jsonb_build_object('motivo', p_motivo, 'revertidos', v_revertidos),
    auth.uid()
  );

  -- F3 · CONTRAASIENTO de la venta web (si estaba en libros). Nunca impide la
  -- anulacion: si falla, queda en el aviso de Finanzas con su motivo.
  begin
    v_reverso := fz__reverso_venta_web(p_pedido_id);
  exception when others then
    v_reverso := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', v_revertidos,
                            'asiento_reverso', v_reverso);
end;
$$;

-- ----------------------------------------------------------------------------
-- (F) La vitrina resta lo que ya nos llevamos
-- ----------------------------------------------------------------------------
-- Cambia UNA cosa frente a D2c.1: el stock disponible de un producto de
-- proveedor ahora descuenta los pedidos pagados que todavia no se han
-- transcrito a Dropi. Sin esto, con 21 unidades y 4 pedidos sin transcribir la
-- vitrina seguiria diciendo «disponible» cuando en la practica quedan 17.
--
-- El candado duro de venta_proveedor_habilitada SE CONSERVA: D2c.2a sigue
-- siendo inerte.
create or replace view catalogo_publico as
select
  cp.id,
  cp.nombre,
  cp.slug,
  cp.categoria_codigo,
  cc.nombre        as categoria_nombre,
  cc.color_fuerte,
  cc.color_claro,
  cc.color_sombra,
  cp.detalle_presentacion,
  cp.imagen_banner_path,
  cp.caracteristica_adicional,
  cp.precio_venta,
  cp.hook_largo,
  cp.por_que_magandhi,
  cp.sobre_este_producto,
  cp.ficha_tecnica,
  cp.imagenes,
  cp.sello_elegido,
  cp.estrella,
  case
    when cp.product_id_ref is null then true
    -- Producto de proveedor: MISMA regla que ventas_disponible_para_venta, pero
    -- escrita aqui dentro, no llamando a la funcion.
    --
    -- POR QUE SE DUPLICA, aunque duplicar reglas sea malo: esta vista la lee
    -- `anon`. Llamar a la funcion exigiria darle EXECUTE, y esa funcion
    -- devuelve EXISTENCIAS EXACTAS — justo lo que la lista blanca publica no
    -- puede exponer jamas. Entre duplicar una condicion o abrirle a un
    -- anonimo una puerta que cuenta unidades, se duplica.
    --
    -- La deriva se controla con una prueba que exige que la vista y la funcion
    -- coincidan para todo producto (dropshipping-d2c2a.sql). Si alguien cambia
    -- una y olvida la otra, el banco lo caza.
    when p.origen = 'proveedor' then (
      pp.product_id is null
      or pp.stock_reportado is null
      or pp.stock_vence_en is null
      or pp.stock_vence_en <= now()
      or pp.stock_reportado < coalesce(pp.piso_vitrina, dcfg.piso_vitrina, 20)
      or (pp.stock_reportado - coalesce(res.reservadas, 0)) <= 0
    )
    when cp.tope_escaparate is not null
      then least(coalesce(ex.existencias, 0), cp.tope_escaparate) <= 0
    else coalesce(ex.existencias, 0) <= 0
  end as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
left join productos p on p.id = cp.product_id_ref
left join producto_proveedor pp on pp.product_id = cp.product_id_ref
left join (
  select piso_vitrina, venta_proveedor_habilitada
  from dropshipping_config where id = 1
) dcfg on true
-- Unidades que ya nos llevamos y que Dropi todavia no sabe: pedidos pagados
-- sin transcribir. Es la parte CONOCIDA del hueco entre el cobro y el despacho.
left join (
  select r.product_id, sum(r.cantidad)::integer as reservadas
    from pedido_proveedor r
    join pedidos pe on pe.id = r.pedido_id
   where r.transcrito_en is null
     and pe.estado <> 'anulado'
   group by r.product_id
) res on res.product_id = cp.product_id_ref
left join (
  select
    m.product_id,
    sum(
      case m.tipo
        when 'entrada'        then  m.cantidad
        when 'ajuste_entrada' then  m.cantidad
        when 'salida'         then -m.cantidad
        when 'ajuste_salida'  then -m.cantidad
      end
    )::integer as existencias
  from movimientos_inventario m
  group by m.product_id
) ex on ex.product_id = cp.product_id_ref
where cp.publicado = true
  and cp.activo = true
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view catalogo_publico is
  'D2c.2a Dropshipping · superficie publica de lista blanca. Producto propio: agotado sale del libro de inventario. Producto proveedor: agotado sale de ventas_disponible_para_venta, la MISMA puerta que usa crear_pedido (lectura de Dropi vigente y sobre el piso, menos los pedidos sin transcribir), asi la vitrina y el checkout no pueden discrepar. Falla cerrado. Reutiliza el booleano `agotado` a proposito: un copy distinto delataria cuales productos son de proveedor. Nunca expone origen, proveedor, costo, ids externos, piso ni existencias exactas.';

grant select on catalogo_publico to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (G) La vara de entrada: que el documento diga la verdad
-- ----------------------------------------------------------------------------
-- DEUDA DE D2c.1, PAGADA AQUI. Esa migracion guardo `vara_entrada` con un
-- comentario que afirmaba «no se importa un producto con menos de esto». Era
-- FALSO: nadie leia la columna. Un numero de configuracion que nadie respeta es
-- peor que no tenerlo, porque invita a confiar en una proteccion inexistente.
--
-- Se intento imponerlo con un gatillo sobre producto_proveedor y se descarto,
-- por dos razones:
--   1. Rompia flujos legitimos. El gatillo bloquea CUALQUIER inserccion, no
--      solo la importacion: fixtures, cargas administrativas y cualquier camino
--      futuro. La suite de D1 fallo en el acto, y tenia razon.
--   2. Y sobre todo: la vara NO es un invariante, es un JUICIO DE CURADURIA.
--      Nada se rompe si se importa un producto con 60 unidades de un proveedor
--      serio; simplemente se agota antes. Lo que si es invariante es el PISO DE
--      VITRINA, y ese si esta impuesto server-side (en la vista y en
--      crear_pedido). Prohibirle a un humano una decision comercial que el
--      sistema no necesita para estar correcto es obstruir, no proteger.
--
-- Por tanto la vara se queda como ADVERTENCIA en el momento de importar, con el
-- numero a la vista, y el documento lo dice tal cual.
comment on column dropshipping_config.vara_entrada is
  'Unidades minimas RECOMENDADAS para importar un producto de proveedor, para no nacer al borde del piso de vitrina. Es una ADVERTENCIA de curaduria que la pantalla de importacion muestra, NO un candado del servidor: el dueno puede importar por debajo si lo decide. El invariante real es piso_vitrina, impuesto en catalogo_publico y en crear_pedido. 0 oculta la advertencia.';

commit;
