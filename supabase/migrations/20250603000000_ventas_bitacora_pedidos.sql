-- ============================================================
-- Magandhi Corporation · Area de Ventas · Bitacora de pedidos (D2.1) +
-- direccion de entrega estampada en el pedido (D2.2)
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO (TRAMO D2 del ANDAMIOS):
--
-- D2.1 · TRAZABILIDAD REAL DEL PEDIDO. Hoy el tablero de seguimiento FABRICA la
--   linea de tiempo mapeando un arreglo fijo de estados (FLUJO.indexOf(estado)):
--   dice que un pedido "paso por preparando" solo porque su estado actual es
--   posterior, aunque nunca se registro ese paso. Eso es una suposicion, no un
--   hecho. D2.1 crea la bitacora append-only pedido_bitacora -ESPEJO EXACTO de
--   asiento_bitacora de Finanzas (ver 20250201000400_finanzas_trazabilidad.sql)-
--   donde cada crear / cambio de estado / anular deja un RASTRO REAL con el
--   estado anterior, el nuevo, quien lo hizo y cuando. Nada se borra en silencio
--   (append-only: sin policy de UPDATE/DELETE, el historial no se puede borrar
--   desde el cliente). El frontend (FEAT-002) leera esta historia real en vez de
--   inventarla.
--
-- D2.2 · DIRECCION DE ENTREGA COMO SNAPSHOT DEL PEDIDO. Hoy la direccion vive
--   SOLO en la ficha del cliente (clientes.direccion/ciudad/departamento/pais).
--   crear_pedido YA RECIBE p_direccion/p_ciudad/p_departamento/p_pais, pero solo
--   los usa para crear/actualizar al cliente, no los guarda en el pedido. Si
--   luego se edita la direccion del cliente, se REESCRIBE historicamente a donde
--   se envio un pedido viejo: la orden apunta a una direccion que en su momento
--   no existia. D2.2 agrega a pedidos las columnas direccion/ciudad/departamento
--   /pais como SNAPSHOT INMUTABLE de a donde se envio ESTA orden, independiente
--   de ediciones posteriores del cliente. crear_pedido las estampa al crear.
--
-- DECISION DE CRITERIO · ¿TRIGGER O RPC PARA ALIMENTAR LA BITACORA?
--   Se ELIGE alimentar pedido_bitacora DIRECTAMENTE DENTRO de las tres RPC
--   (crear_pedido -> 'crear'; avanzar_estado_pedido -> 'cambio_estado';
--   anular_pedido -> 'anular'), NO con un trigger sobre pedidos. Razon: en
--   Ventas TODA ruta que cambia el estado de un pedido YA es una RPC security
--   definer (pedidos es SELECT-only bajo RLS, no hay UPDATE directo posible desde
--   el cliente, ver 20250401000300_ventas_rls.sql). No existe un UPDATE externo
--   que un trigger deba atrapar, y cada RPC conoce el estado ANTERIOR (lo lee
--   antes del UPDATE) y el NUEVO, asi que puede escribir el evento con precision
--   y SIN riesgo de duplicar. Esto es el MISMO espiritu que asiento_bitacora,
--   donde el evento 'editar' lo escribe la RPC como fuente unica para no
--   duplicar la traza. (Alli el trigger cubre crear/anular porque los asientos
--   SI admiten UPDATE directo; aqui no, por eso todo va por las RPC.)
--
-- COMO SE MODIFICAN LAS RPC (sin cambiar firmas): las tres se redefinen con
--   create or replace copiando su cuerpo VERBATIM de
--   20250401000400_ventas_funciones.sql, insertando UNICAMENTE el INSERT en la
--   bitacora (y, en crear_pedido, el estampado de la direccion). Las LISTAS DE
--   PARAMETROS quedan BYTE-IDENTICAS: no hay drop, no cambia la firma, el
--   frontend actual sigue llamandolas igual.
--
-- ACTOR NULLABLE (importante): actor default auth.uid(), NULLABLE a proposito.
--   Cuando el DUENO corre seeds o el backfill desde el SQL Editor, auth.uid() es
--   NULL (no hay sesion de usuario). Un actor NOT NULL haria fallar esas
--   operaciones de administracion. Se documenta en INSTRUCCIONES.md (seccion D2).
--
-- IDEMPOTENTE EN TODO: create table if not exists, create index if not exists,
--   create or replace function, do-block guard para el ALTER ... ADD COLUMN,
--   insert ... select ... where not exists para el backfill del evento 'crear',
--   y UPDATE con guardas NULL para el backfill de la direccion (solo toca filas
--   aun sin snapshot). Se puede re-ejecutar entero sin duplicar nada.
-- REQUISITO: correr DESPUES de 20250401000000..20250401000500 (las tablas
--   clientes/pedidos/pedido_items, la funcion tiene_acceso_ventas() y las tres
--   RPC de Ventas ya deben existir).
-- ============================================================

create extension if not exists pgcrypto; -- gen_random_uuid (idempotente)

-- ------------------------------------------------------------
-- (A) pedido_bitacora: la bitacora append-only del pedido. ESPEJO de
-- asiento_bitacora (20250201000400_finanzas_trazabilidad.sql). Registra cada
-- crear / cambio de estado / anular con el estado ANTERIOR y el NUEVO (columnas
-- propias, faciles de leer en el timeline), un jsonb de detalle libre, el actor
-- y el momento. Sin on delete en la FK: los pedidos NUNCA se borran (se anulan),
-- asi que conservamos el historial aunque el pedido cambie.
-- ------------------------------------------------------------
create table if not exists pedido_bitacora (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid references pedidos(id), -- sin on delete: no hay DELETE de pedidos; conservar aunque cambie
  accion          text not null check (accion in ('crear','cambio_estado','anular')),
  estado_anterior text,                         -- estado del pedido ANTES del evento (null en 'crear')
  estado_nuevo    text,                         -- estado del pedido DESPUES del evento
  detalle_cambio  jsonb,                        -- detalle libre del evento (motivo, snapshot, etc.)
  actor           uuid references auth.users(id) default auth.uid(), -- NULLABLE: null cuando el dueno corre seeds/backfill desde el SQL Editor
  cuando          timestamptz not null default now()
);

comment on table pedido_bitacora is 'Bitacora append-only del pedido (D2.1, espejo de asiento_bitacora): registra crear/cambio_estado/anular de cada pedido con el estado anterior, el nuevo, un detalle jsonb, el actor y el momento. Nada se borra en silencio. Sin policy de UPDATE/DELETE: el historial no se puede borrar desde el cliente. La alimentan las RPC de Ventas (crear_pedido / avanzar_estado_pedido / anular_pedido) como fuente unica, sin trigger, porque toda ruta de escritura ya es una RPC security definer.';
comment on column pedido_bitacora.accion is 'crear | cambio_estado | anular.';
comment on column pedido_bitacora.estado_anterior is 'Estado del pedido ANTES del evento. null en el evento crear (no habia estado previo).';
comment on column pedido_bitacora.estado_nuevo is 'Estado del pedido DESPUES del evento: recibido al crear, el estado destino en cambio_estado, anulado en anular.';
comment on column pedido_bitacora.detalle_cambio is 'jsonb con detalle libre del evento (p.ej. motivo de anulacion, snapshot de creacion). Permite reconstruir el contexto sin acoplar columnas.';
comment on column pedido_bitacora.actor is 'Quien hizo el cambio (auth.uid()). NULLABLE a proposito: es NULL cuando el dueno corre seeds o el backfill desde el SQL Editor (no hay sesion). Un actor NOT NULL romperia esas operaciones de administracion.';

create index if not exists idx_pedido_bitacora_pedido on pedido_bitacora (pedido_id);
create index if not exists idx_pedido_bitacora_cuando on pedido_bitacora (cuando desc);

-- ------------------------------------------------------------
-- (B) SNAPSHOT DE DIRECCION EN EL PEDIDO (D2.2). Se agregan a pedidos las
-- columnas de direccion de entrega como SNAPSHOT INMUTABLE de a donde se envio
-- ESTA orden. Guard idempotente sobre information_schema.columns: solo se agrega
-- la columna si no existe, para no fallar al re-ejecutar.
--
-- POR QUE UN SNAPSHOT Y NO LEER SIEMPRE del cliente: si un pedido leyera la
-- direccion viva del cliente, editar la ficha del cliente REESCRIBIRIA a donde
-- se envio un pedido pasado (falseando el historial). El snapshot congela la
-- direccion al momento de la orden; editar el cliente despues NO debe alterarla.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_name = 'pedidos' and column_name = 'direccion'
  ) then
    alter table pedidos add column direccion text;
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_name = 'pedidos' and column_name = 'ciudad'
  ) then
    alter table pedidos add column ciudad text;
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_name = 'pedidos' and column_name = 'departamento'
  ) then
    alter table pedidos add column departamento text;
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_name = 'pedidos' and column_name = 'pais'
  ) then
    alter table pedidos add column pais text;
  end if;
end
$$;

comment on column pedidos.direccion is 'SNAPSHOT INMUTABLE de la direccion de entrega de ESTA orden (D2.2). Se estampa al crear el pedido desde p_direccion. Editar despues la ficha del cliente NO reescribe este valor: es a donde se envio esta orden en su momento.';
comment on column pedidos.ciudad is 'SNAPSHOT INMUTABLE de la ciudad de entrega de ESTA orden (D2.2). Independiente de ediciones posteriores del cliente.';
comment on column pedidos.departamento is 'SNAPSHOT INMUTABLE del departamento de entrega de ESTA orden (D2.2). Independiente de ediciones posteriores del cliente.';
comment on column pedidos.pais is 'SNAPSHOT INMUTABLE del pais de entrega de ESTA orden (D2.2). Independiente de ediciones posteriores del cliente.';

-- ============================================================
-- (C) RPC alimentando la bitacora (create or replace, FIRMAS BYTE-IDENTICAS).
-- Se copian los cuerpos VERBATIM de 20250401000400_ventas_funciones.sql y se
-- inserta UNICAMENTE el evento en pedido_bitacora (y, en crear_pedido, el
-- estampado de la direccion). Ninguna lista de parametros cambia.
-- ============================================================

-- ------------------------------------------------------------
-- crear_pedido: identico a 20250401000400, con DOS anadidos D2:
--   (D2.2) al insertar el pedido, estampa direccion/ciudad/departamento/pais
--          desde p_direccion/p_ciudad/p_departamento/p_pais (snapshot); y
--   (D2.1) al final registra un evento 'crear' en pedido_bitacora con
--          estado_nuevo='recibido'.
-- La lista de parametros NO cambia.
-- ------------------------------------------------------------
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

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is 'NUCLEO UNICO de creacion de pedido (dos puertas: manual hoy, web futura via canal). Transaccional: resuelve/crea cliente (ante colision del UNIQUE parcial resuelve al existente, no falla ni duplica, §4.5), inserta pedidos + pedido_items con precio real, calcula total bigint y baja stock con un INSERT directo de salida (motivo=Venta, referencia=pedido_id, customer_id estampado) en el libro -- NO llama inv_registrar_movimiento (no acopla areas ni exige permiso de inventario; salida sin stock no se bloquea). Valida por item que el producto exista Y este activo (mismo chequeo que inv_registrar_movimiento) antes de tocar el libro. D2.2: estampa la direccion de entrega como snapshot en el pedido. D2.1: registra un evento crear en pedido_bitacora (estado_nuevo=recibido). Devuelve jsonb {pedido_id, customer_id, total}. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- anular_pedido: identico a 20250401000400, con UN anadido D2.1: registra un
-- evento 'anular' en pedido_bitacora con el estado ANTERIOR (leido antes del
-- UPDATE) y estado_nuevo='anulado'. Si el pedido ya estaba anulado no se
-- registra evento (igual que no se revierte stock: es no-op idempotente). La
-- lista de parametros NO cambia.
-- ------------------------------------------------------------
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

  select anulado, customer_id, fecha_orden, estado
    into v_anulado, v_customer_id, v_fecha, v_estado_ant
    from pedidos
   where id = p_pedido_id;

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
  -- DECISION DE CRITERIO: a diferencia de crear_pedido, aqui NO se exige que el
  -- producto siga activo. Un producto puede darse de baja (activo=false) DESPUES
  -- de una venta, y anular esa venta debe poder devolver el stock que la salida
  -- original resto: registrar una ENTRADA que reintegra existencias es una
  -- operacion segura (nunca deja stock negativo ni vende algo dado de baja).
  -- Bloquearla por inactividad dejaria el libro descuadrado (salida sin su
  -- entrada compensatoria). La FK product_id -> productos(id) sigue garantizando
  -- que el producto exista.
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

  -- D2.1: evento 'anular' en la bitacora, con el estado ANTERIOR (leido arriba,
  -- antes del UPDATE) y estado_nuevo='anulado'. Se registra solo cuando la
  -- anulacion ocurre de verdad (no en el no-op de un pedido ya anulado).
  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    p_pedido_id, 'anular', v_estado_ant, 'anulado',
    jsonb_build_object('motivo', p_motivo, 'revertidos', v_revertidos),
    auth.uid()
  );

  return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', v_revertidos);
end;
$$;

comment on function anular_pedido(uuid, text) is 'Anula un pedido de forma logica y reversible, transaccional (§5.3): marca anulado=true + estado=anulado + motivo_anulacion (nunca DELETE) y registra una ENTRADA compensatoria por cada pedido_item en el libro (insert directo, motivo=Anulacion de venta, referencia=pedido_id, customer_id del pedido) -- NO llama inv_registrar_movimiento. Si el pedido ya estaba anulado no revierte de nuevo. D2.1: registra un evento anular en pedido_bitacora (estado_anterior real, estado_nuevo=anulado) cuando la anulacion ocurre. Devuelve jsonb {pedido_id, revertidos}. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- avanzar_estado_pedido: identico a 20250401000400, con UN anadido D2.1:
-- registra un evento 'cambio_estado' en pedido_bitacora con el estado ANTERIOR
-- (leido antes del UPDATE) y estado_nuevo=p_nuevo_estado. La lista de parametros
-- NO cambia.
-- ------------------------------------------------------------
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

  -- 'anulado' se excluye a proposito: la anulacion va por anular_pedido (revierte
  -- stock). Aqui solo se avanza el ciclo operativo.
  if p_nuevo_estado is null or p_nuevo_estado not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'Estado invalido: %. Use recibido, preparando, en_camino o entregado (para anular use anular_pedido).', p_nuevo_estado;
  end if;

  select anulado, estado into v_anulado, v_estado_ant from pedidos where id = p_pedido_id;

  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  -- Un pedido anulado es terminal: no se avanza (para reactivarlo habria que
  -- registrar uno nuevo; la anulacion ya devolvio el stock al libro).
  if v_anulado then
    raise exception 'El pedido % esta anulado y no admite avance de estado.', p_pedido_id;
  end if;

  update pedidos
     set estado = p_nuevo_estado,
         actualizado = now()
   where id = p_pedido_id;

  -- D2.1: evento 'cambio_estado' en la bitacora, con el estado ANTERIOR (leido
  -- arriba, antes del UPDATE) y estado_nuevo=p_nuevo_estado. Reaplicar el mismo
  -- estado deja traza igual (es un hecho real: alguien lo volvio a marcar); la
  -- RPC sigue siendo idempotente en el efecto sobre pedidos.
  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    p_pedido_id, 'cambio_estado', v_estado_ant, p_nuevo_estado, null, auth.uid()
  );

  return jsonb_build_object('pedido_id', p_pedido_id, 'estado', p_nuevo_estado);
end;
$$;

comment on function avanzar_estado_pedido(uuid, text) is 'Avanza el estado operativo de un pedido (recibido/preparando/en_camino/entregado, §5.1) via RPC security definer, porque pedidos es SELECT-only bajo RLS y un UPDATE directo lo rechaza Postgres. NO acepta anulado como destino: la anulacion va por anular_pedido (que ademas revierte stock). Valida tiene_acceso_ventas(), que el estado destino este en el flujo, que el pedido exista y que NO este anulado (terminal). Hace update de pedidos.estado + actualizado=now(). D2.1: registra un evento cambio_estado en pedido_bitacora (estado_anterior real, estado_nuevo=destino). Devuelve jsonb {pedido_id, estado}. Idempotente en el efecto.';

-- ============================================================
-- (D) BACKFILL IDEMPOTENTE (operacion de ADMINISTRACION que corre el dueno).
-- ============================================================

-- ------------------------------------------------------------
-- (D.1) Backfill del evento 'crear' para pedidos preexistentes. Por cada pedido
-- que NO tenga aun un evento 'crear' en la bitacora, se inserta UNO con
-- cuando = pedidos.creado, estado_nuevo = el estado inicial coherente
-- ('recibido'; para un pedido ya anulado su vida empezo igualmente en recibido),
-- y actor = pedidos.creado_por (o NULL). insert ... select ... where not exists
-- => idempotente (re-ejecutar no duplica).
--
-- NO SE FABRICAN transiciones intermedias: de los pedidos viejos solo consta el
-- evento de creacion (no hay registro real de por que estados pasaron). El
-- historial real empieza a acumularse desde ahora via las RPC.
-- ------------------------------------------------------------
insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor, cuando)
select
  p.id,
  'crear',
  null,
  'recibido',
  jsonb_build_object('backfill', true, 'estado_actual', p.estado),
  p.creado_por,
  coalesce(p.creado, now())
from pedidos p
where not exists (
  select 1 from pedido_bitacora b
   where b.pedido_id = p.id and b.accion = 'crear'
);

-- ------------------------------------------------------------
-- (D.2) Backfill del snapshot de direccion. Para pedidos cuyas cuatro columnas
-- de direccion siguen NULL, se copia la direccion ACTUAL del cliente ligado
-- (la mejor disponible). Es APROXIMADO para ordenes creadas antes de que la
-- columna existiera: no sabemos a donde se envio realmente, solo la direccion
-- vigente del cliente hoy. Idempotente: solo toca filas aun sin snapshot (guarda
-- NULL en las cuatro), asi que una vez estampadas no se sobreescriben.
-- ------------------------------------------------------------
update pedidos p
   set direccion    = c.direccion,
       ciudad       = c.ciudad,
       departamento = c.departamento,
       pais         = c.pais
  from clientes c
 where c.id = p.customer_id
   and p.direccion is null
   and p.ciudad is null
   and p.departamento is null
   and p.pais is null;

-- ============================================================
-- (E) RLS + GRANT de pedido_bitacora (candado real, capa 1 + capa 2).
-- Consistente con 20250401000300_ventas_rls.sql y 20250401000500_ventas_grants.
-- sql. Se incluye en ESTE mismo archivo para que la tabla nazca con su candado
-- (una sola corrida, un solo Run).
-- ------------------------------------------------------------
-- SELECT si tiene_acceso_ventas(); SIN policy de INSERT/UPDATE/DELETE: la
-- escritura solo ocurre dentro de las RPC security definer (que saltan RLS). Sin
-- policy de DELETE, el historial es append-only e imborrable desde el cliente.
-- CERO policy y CERO grant para anon (datos operativos tras login).
-- ============================================================
alter table pedido_bitacora enable row level security;

drop policy if exists "pedido_bitacora_select_ventas" on pedido_bitacora;
create policy "pedido_bitacora_select_ventas" on pedido_bitacora
  for select
  to authenticated
  using (tiene_acceso_ventas());

-- Capa 1 (GRANT de tabla): sin este grant Postgres rechaza con "permission
-- denied" ANTES de evaluar RLS, porque "auto-expose new tables" esta OFF. Solo
-- SELECT (el cliente nunca escribe directo; las RPC security definer no
-- requieren grant sobre las tablas que tocan por dentro). CERO grant a anon.
grant select on table pedido_bitacora to authenticated;
