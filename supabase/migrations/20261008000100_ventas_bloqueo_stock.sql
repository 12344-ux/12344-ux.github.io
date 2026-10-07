-- ============================================================
-- MAGANDHI · Ventas · BLOQUEO FIRME DE STOCK al crear pedidos
-- ------------------------------------------------------------
-- POR QUE: hasta hoy una venta sin stock NO se bloqueaba (contrato original de
-- PLANO-INVENTARIO: "la salida en negativo se registra y la existencia negativa
-- es la senal"). Ademas, la pantalla de Registrar pedido nunca mostraba el
-- stock, asi que tampoco avisaba. DECISION DEL DUENO (8-oct-2026): bloqueo
-- firme. Inventario ya es la fuente de verdad (la tienda muestra "Agotado" con
-- ese dato) y vender lo que no hay rompe la promesa de MAGANDHI. Si la
-- mercancia llego y no esta cargada, el orden correcto es: entrada en
-- Inventario -> pedido.
--
-- QUE CAMBIA:
--   (A) crear_pedido: MISMA FIRMA (byte-identica) y MISMO CUERPO que en
--       20250603000000, con UN bloque nuevo (0) al inicio que rechaza con
--       STOCK_INSUFICIENTE si algun producto pide mas de lo disponible. Bloquea
--       la fila del producto (for update) para que dos pedidos simultaneos no
--       vendan la misma ultima unidad. Aplica a canal manual y web.
--   (B) ventas_stock_disponible(): lectura de existencias de productos activos
--       para que el formulario muestre "Disponibles: N", guardada por
--       tiene_acceso_ventas() (un usuario solo de Ventas no lee el libro de
--       Inventario directamente).
--
-- QUE NO CAMBIA: anular_pedido (sigue devolviendo stock), avanzar_estado_pedido,
-- y los movimientos manuales de Inventario (inv_registrar_movimiento conserva su
-- contrato; ajustes de conteo fisico siguen siendo posibles).
--
-- Migracion forward, idempotente (create or replace). EXECUTE: crear_pedido
-- conserva sus grants (create or replace no los toca); la funcion nueva se
-- otorga nominalmente (default privileges del tramo 0).
-- REQUISITO: despues de 20261008000000_correos_pedido.sql.
-- ============================================================

-- (A) crear_pedido con bloqueo firme de stock
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

    select coalesce(s.existencias, 0) into v_disponible
      from stock_actual s where s.product_id = v_req.product_id;
    v_disponible := coalesce(v_disponible, 0);

    if v_disponible < v_req.cantidad then
      raise exception 'STOCK_INSUFICIENTE: «%» tiene % unidad(es) disponible(s) y el pedido pide %. Registra primero la entrada en Inventario.',
        v_nom_prod, greatest(v_disponible, 0), v_req.cantidad;
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
    select activo into v_activo from productos where id = v_product_id;
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
    insert into movimientos_inventario (
      product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
    ) values (
      v_product_id, 'salida', v_cantidad, 'Venta', v_pedido_id::text, v_customer_id, v_fecha
    );
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


comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is 'NUCLEO UNICO de creacion de pedido (manual hoy, web futura via canal). BLOQUEO FIRME DE STOCK (8-oct-2026): rechaza con STOCK_INSUFICIENTE si algun producto pide mas unidades que las existencias del libro, bloqueando la fila del producto para serializar ventas simultaneas. Transaccional: resuelve/crea cliente, inserta pedidos + pedido_items, calcula total bigint, baja stock con una salida (motivo=Venta, referencia=pedido_id), estampa la direccion como snapshot y registra crear en pedido_bitacora. Devuelve jsonb {pedido_id, customer_id, total}. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- (B) ventas_stock_disponible
-- ------------------------------------------------------------
create or replace function ventas_stock_disponible()
returns table (product_id uuid, existencias integer)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;
  return query
    select p.id, coalesce(s.existencias, 0)::integer
      from productos p
      left join stock_actual s on s.product_id = p.id
     where p.activo = true;
end;
$fn$;

comment on function ventas_stock_disponible() is 'Existencias actuales de los productos activos, para mostrar "Disponibles: N" en Registrar pedido. Guardada por tiene_acceso_ventas(). Solo lectura; el bloqueo real esta en crear_pedido.';

revoke execute on function ventas_stock_disponible() from public;
grant  execute on function ventas_stock_disponible() to authenticated, service_role;
