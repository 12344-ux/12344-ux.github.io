-- ============================================================
-- Magandhi Corporation · Area de Ventas · Tablas pedidos y pedido_items (la orden)
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO: el pedido es el HECHO que se escribe; las
-- metricas del Portafolio se DERIVAN de el (vista, ver 20250401000200). Misma
-- filosofia de Inventario y Finanzas: el hecho se escribe, el agregado se
-- deriva (PLANO-VENTAS §1.1, §1.8).
--
-- QUE HACE: crea pedidos (la orden: cliente, fecha, estado, canal, total) y
-- pedido_items (una linea por producto vendido, con el PRECIO REAL de la venta).
-- El id del pedido es el valor que va en movimientos_inventario.referencia al
-- bajar stock (§2), atando cada salida del libro a su pedido.
--
-- ESTADOS DEL PEDIDO (§5.1 + DECISIONES FINALES DEL DUENO): el ciclo de vida es
--   recibido -> preparando -> en_camino -> entregado
-- mas 'anulado' como terminal aparte (con bitacora, nunca se borra). OJO: el
-- estado 'en_camino' lo anadio el dueno en la sesion de aprobacion (es la etapa
-- que el cliente mas quiere saber) y PREVALECE sobre el DDL de ejemplo de la
-- §1.5, que no lo listaba. El check incluye los 5 estados.
--
-- PRECIO REAL EN LA LINEA (§1.6): pedido_items.precio_unitario guarda el precio
-- al MOMENTO de la venta, no el precio_venta actual del producto. Asi el Ranking
-- de Marketing deja de estimar (hoy usa precio_venta actual, marcado como
-- CONEXION FUTURA en ranking-productos.html) y pasa a ingreso exacto sin rehacer
-- nada. subtotal = cantidad * precio_unitario (redundante pero auditable).
--
-- MONTOS Y CANTIDADES (regla del ecosistema): montos siempre bigint (pesos
-- enteros, nunca float): total, precio_unitario, subtotal. Cantidades integer
-- (unidades enteras), igual que el libro de Inventario.
--
-- SIN DELETE: un pedido no se borra; se anula (anulado=true + motivo_anulacion,
-- §5.3). La escritura va SOLO por RPC security definer (ver 20250401000400).
--
-- IDEMPOTENTE: create table if not exists / create index if not exists.
-- REQUISITO: correr DESPUES de 20250401000000_ventas_clientes.sql (FK a
-- clientes) y con productos ya existente (FK a productos, del modulo Inventario).
-- ============================================================

-- ------------------------------------------------------------
-- pedidos: la orden. customer_id es FK REAL a clientes(id) (dentro de Ventas si
-- hay FK; la del libro de Inventario se enciende en 20250401000300). El check de
-- estado incluye los 5 estados (con 'en_camino', decision final del dueno).
-- ------------------------------------------------------------
create table if not exists pedidos (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references clientes(id),
  fecha_orden      date not null default current_date,
  estado           text not null default 'recibido'
                     check (estado in ('recibido','preparando','en_camino','entregado','anulado')),
  canal            text not null default 'manual'
                     check (canal in ('manual','web')),
  total            bigint not null default 0,
  notas            text,
  anulado          boolean not null default false,
  motivo_anulacion text,
  creado           timestamptz default now(),
  creado_por       uuid default auth.uid(),
  actualizado      timestamptz
);

comment on table pedidos is 'La orden de venta. Su id va en movimientos_inventario.referencia al bajar stock (§2). El hecho se escribe aqui; las metricas del Portafolio se derivan (vista portafolio_metricas). Nunca se borra: anulado=true + motivo_anulacion. Escritura solo por RPC security definer.';
comment on column pedidos.estado is 'Ciclo de vida (§5.1 + decision final del dueno): recibido -> preparando -> en_camino -> entregado, mas anulado (terminal). en_camino lo anadio el dueno (etapa que el cliente mas quiere saber) y prevalece sobre el DDL de ejemplo del plano.';
comment on column pedidos.canal is 'Por que puerta entro el pedido. Hoy siempre manual; web queda listo como enchufe para el checkout futuro (Wompi), que invocara el MISMO nucleo crear_pedido con canal=web (§3).';
comment on column pedidos.total is 'Total del pedido en pesos enteros (bigint, nunca float). Se calcula desde los pedido_items.';
comment on column pedidos.anulado is 'Anulacion logica. Nada se borra (§5.3): se marca anulado=true, se guarda motivo_anulacion y se registra una ENTRADA compensatoria por cada item en el libro de Inventario.';

create index if not exists pedidos_customer_idx on pedidos (customer_id);
create index if not exists pedidos_fecha_idx    on pedidos (fecha_orden);

-- ------------------------------------------------------------
-- pedido_items: las lineas del pedido. precio_unitario = PRECIO REAL de la venta
-- (bigint), subtotal = cantidad * precio_unitario. product_id es FK al catalogo
-- de Inventario (productos), que ya existe.
-- ------------------------------------------------------------
create table if not exists pedido_items (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null references pedidos(id),
  product_id      uuid not null references productos(id),
  cantidad        integer not null check (cantidad > 0),
  precio_unitario bigint not null,   -- PRECIO REAL de la venta (bigint, pesos)
  subtotal        bigint not null
);

comment on table pedido_items is 'Lineas del pedido: una por producto vendido. precio_unitario guarda el PRECIO REAL al momento de la venta (no el precio_venta actual del producto): asi el Ranking de Marketing deja de estimar (§1.6). subtotal = cantidad * precio_unitario, pesos enteros.';
comment on column pedido_items.precio_unitario is 'PRECIO REAL de esta venta en pesos enteros (bigint). Enciende el ingreso real del Ranking de Marketing, que hoy estima con productos.precio_venta actual (marcador CONEXION FUTURA en ranking-productos.html).';
comment on column pedido_items.cantidad is 'Unidades vendidas (integer, check > 0). Es la cantidad que baja del libro de Inventario como salida al crear el pedido.';

create index if not exists pedido_items_pedido_idx  on pedido_items (pedido_id);
create index if not exists pedido_items_product_idx on pedido_items (product_id);
