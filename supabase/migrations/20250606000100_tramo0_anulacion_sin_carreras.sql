-- ============================================================
-- Impulse · TRAMO 0 (auditoria) · Ventas: anulacion y cambio de estado sin carreras
-- ------------------------------------------------------------
-- EL HALLAZGO: anular_pedido y avanzar_estado_pedido leian el pedido con un
-- SELECT simple, decidian, y despues hacian el UPDATE. Entre la lectura y la
-- escritura otra transaccion podia colarse:
--   (a) DOBLE ANULACION: dos anulaciones simultaneas leen anulado=false, las
--       dos pasan el filtro y las dos registran la ENTRADA compensatoria ->
--       el stock vuelve DOS veces (el libro queda inflado) y la bitacora
--       registra dos anulaciones.
--   (b) AVANZAR UN PEDIDO YA ANULADO: avanzar lee anulado=false, en ese
--       instante otra persona lo anula, y avanzar lo pasa a 'entregado' ->
--       un pedido anulado (con stock ya devuelto) termina marcado entregado.
-- Hoy con un solo operador es improbable; con varias personas o con el
-- webhook de Wompi (reintentos) es real. Por eso va ANTES de F2.
--
-- LA CORRECCION: leer el pedido con SELECT ... FOR UPDATE. La fila queda
-- bloqueada hasta el fin de la transaccion; la segunda operacion ESPERA y,
-- al continuar, PostgreSQL le entrega la version YA ACTUALIZADA de la fila
-- (READ COMMITTED re-evalua la fila bloqueada). Resultado: la segunda
-- anulacion ve anulado=true y es un no-op; el avance ve anulado=true y
-- rechaza. Cero entradas duplicadas.
--
-- QUE NO CAMBIA: firmas, parametros, valores de retorno, mensajes y logica
-- de negocio son IDENTICOS a 20250603000000_ventas_bitacora_pedidos.sql. El
-- UNICO cambio es `for update` en la lectura inicial. create or replace
-- conserva los permisos EXECUTE de la funcion.
--
-- IDEMPOTENTE: create or replace function.
-- REQUISITO: correr DESPUES de 20250603000000_ventas_bitacora_pedidos.sql.
-- ============================================================

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
    select product_id, cantidad from pedido_items where pedido_id = p_pedido_id
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

  return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', v_revertidos);
end;
$$;

comment on function anular_pedido(uuid, text) is 'Anula un pedido de forma logica, transaccional y SIN CARRERAS (Tramo 0: lee el pedido con FOR UPDATE, asi dos anulaciones simultaneas nunca devuelven el stock dos veces). Marca anulado=true + estado=anulado + motivo (nunca DELETE), registra una ENTRADA compensatoria por cada pedido_item y un evento anular en pedido_bitacora. Si ya estaba anulado es un no-op. Devuelve jsonb {pedido_id, revertidos}. Exige tiene_acceso_ventas().';

create or replace function avanzar_estado_pedido(
  p_pedido_id    uuid,
  p_nuevo_estado text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado    boolean;
  v_estado_ant text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  if p_nuevo_estado is null or p_nuevo_estado not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'Estado invalido: %. Use recibido, preparando, en_camino o entregado (para anular use anular_pedido).', p_nuevo_estado;
  end if;

  -- TRAMO 0: FOR UPDATE. Si una anulacion esta en curso, este avance espera y
  -- despues ve anulado=true, de modo que nunca marca como entregado un pedido
  -- ya anulado. Tambien deja el estado_anterior de la bitacora exacto.
  select anulado, estado into v_anulado, v_estado_ant
    from pedidos
   where id = p_pedido_id
     for update;

  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  if v_anulado then
    raise exception 'El pedido % esta anulado y no admite avance de estado.', p_pedido_id;
  end if;

  update pedidos
     set estado = p_nuevo_estado,
         actualizado = now()
   where id = p_pedido_id;

  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    p_pedido_id, 'cambio_estado', v_estado_ant, p_nuevo_estado, null, auth.uid()
  );

  return jsonb_build_object('pedido_id', p_pedido_id, 'estado', p_nuevo_estado);
end;
$$;

comment on function avanzar_estado_pedido(uuid, text) is 'Avanza el estado operativo de un pedido (recibido/preparando/en_camino/entregado) via RPC security definer. Tramo 0: lee el pedido con FOR UPDATE, asi nunca avanza un pedido que otra transaccion acaba de anular y el estado_anterior de la bitacora es exacto. NO acepta anulado como destino (eso es anular_pedido). Registra cambio_estado en pedido_bitacora. Devuelve jsonb {pedido_id, estado}.';
