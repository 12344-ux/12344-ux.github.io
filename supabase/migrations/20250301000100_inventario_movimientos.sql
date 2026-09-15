-- ============================================================
-- Magandhi Corporation · Modulo Inventario · EL LIBRO (append-only)
-- movimientos_inventario es el corazon del modulo: un libro append-only
-- donde cada fila es un HECHO (entro stock, salio stock). El stock NUNCA se
-- edita directamente; se deriva sumando este libro (vista stock_actual). Es
-- la misma filosofia del Libro Diario de Finanzas: el diario se escribe, el
-- saldo se deriva; nada se borra en silencio.
--
-- POR QUE EL LIBRO Y NO UN NUMERO: Marketing (Proyeccion de la demanda)
-- necesita el HISTORIAL de ventas por periodo para proyectar. Si guardaramos
-- solo "quedan 12", manana no tendriamos con que alimentar Marketing y habria
-- que rehacer Inventario entero. El libro es la semilla que hace posible
-- Marketing sin rehacer nada: leera este libro filtrando tipo='salida' y
-- agrupando por periodo / product_id.
--
-- SIGNO POR TIPO (no por cantidad): cantidad es SIEMPRE positiva
-- (check cantidad > 0). El tipo, no el signo, decide si suma o resta al
-- derivar el stock (ver la vista). Cuatro tipos explicitos:
--   entrada        -> suma (llega mercancia del proveedor)
--   salida         -> resta (venta, merma, devolucion a proveedor)
--   ajuste_entrada -> suma  (conteo fisico real MAYOR que el libro)
--   ajuste_salida  -> resta (conteo fisico real MENOR que el libro)
-- Un movimiento equivocado NO se edita ni se borra: se compensa con un ajuste
-- que deja el rastro, igual que "anular" en Finanzas.
--
-- IDEMPOTENTE: create table if not exists / create index if not exists.
-- ============================================================

-- ------------------------------------------------------------
-- movimientos_inventario: el libro de movimientos.
--   - product_id -> productos(id): que producto se movio.
--   - tipo: naturaleza del movimiento (check con los 4 tipos permitidos).
--   - cantidad: integer, SIEMPRE positiva (check > 0). Unidades enteras.
--   - customer_id: uuid nullable ANTICIPADO, "enchufe apagado". Se llenara
--     cuando exista el software de Clientes. HOY NO tiene FK a ninguna tabla
--     (no se crea una tabla clientes a medias): la FK se agregara sin migrar
--     datos cuando Clientes exista.
--   - costo_unitario_mov: bigint nullable, costo al que entro ese lote
--     puntual (referencia historica que el futuro orquestador de ventas usara
--     para el costo de venta, sin rehacer nada).
--   - fecha (date): fecha contable del movimiento, la que importa para
--     Marketing por periodo. Distinta de creado (momento real del registro).
-- APPEND-ONLY: RLS no da UPDATE ni DELETE (ver 20250301000300); la escritura
-- va por la RPC security definer inv_registrar_movimiento.
-- ------------------------------------------------------------
create table if not exists movimientos_inventario (
  id                 uuid primary key default gen_random_uuid(),
  product_id         uuid not null references productos(id),
  tipo               text not null check (tipo in ('entrada','salida','ajuste_entrada','ajuste_salida')),
  cantidad           integer not null check (cantidad > 0),
  motivo             text,
  referencia         text,
  customer_id        uuid,
  costo_unitario_mov bigint,
  fecha              date not null default current_date,
  creado             timestamptz default now(),
  creado_por         uuid default auth.uid()
);

comment on table movimientos_inventario is 'EL LIBRO append-only del modulo Inventario. Cada fila es un hecho (entrada/salida). El stock NO se edita: se deriva sumando este libro (vista stock_actual). Marketing lee este libro (tipo=salida por periodo). cantidad SIEMPRE positiva; el tipo decide sumar/restar. Nada se borra: un error se compensa con un ajuste. Escritura solo por RPC security definer.';
comment on column movimientos_inventario.tipo is 'Naturaleza del movimiento: entrada/ajuste_entrada suman stock; salida/ajuste_salida restan. El signo lo pone el tipo, no la cantidad.';
comment on column movimientos_inventario.cantidad is 'Cantidad SIEMPRE positiva (check > 0), unidades enteras. El tipo decide si suma o resta al derivar el stock.';
comment on column movimientos_inventario.customer_id is 'ANTICIPADO ("enchufe apagado"): columna preparada para cuando exista el software de Clientes. HOY sin FK a ninguna tabla (no se crea una tabla clientes a medias). Permitira a Marketing cruzar "que compro quien" sin tocar Inventario.';
comment on column movimientos_inventario.costo_unitario_mov is 'Costo al que entro ese lote puntual (bigint, pesos enteros). Referencia historica para el futuro orquestador de ventas (costo de venta), disponible sin rehacer nada.';
comment on column movimientos_inventario.fecha is 'Fecha contable del movimiento (la que importa para Marketing por periodo). Distinta de creado (momento real del registro, auditoria).';

-- Indices: por producto (stock de un producto) y por (product_id, fecha)
-- para el agrupamiento por periodo que hara Marketing.
create index if not exists movimientos_inventario_product_idx       on movimientos_inventario (product_id);
create index if not exists movimientos_inventario_product_fecha_idx on movimientos_inventario (product_id, fecha);
