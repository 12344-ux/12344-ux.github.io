-- ============================================================
-- Magandhi Corporation · Modulo Inventario · Catalogo de productos
-- Segundo software del back-office interno (montaguth.institute), hermano
-- del modulo Finanzas ya terminado. Mismo estandar de calidad y misma
-- filosofia: nada se borra en silencio, cantidades enteras (unidades),
-- montos bigint (pesos enteros, nunca float), y el candado real vive en los
-- DATOS (RLS + RPC security definer), no en el HTML.
--
-- Este archivo crea LA IDENTIDAD del producto (el "que" vendemos), no el
-- "cuanto" hay: el stock NO se guarda como un numero editable, se DERIVA del
-- libro de movimientos (ver 20250301000100_inventario_movimientos.sql y la
-- vista 20250301000200_inventario_stock_vista.sql). Mismo principio que el
-- Libro Mayor de Finanzas: el diario se escribe, el saldo se deriva.
--
-- CLONABLE (MAGANDHI es el piloto del ecosistema Impulse): el prefijo del SKU
-- NO va escrito a fuego en el codigo. Vive en la tabla de configuracion
-- inventario_config (una fila), para que otra organizacion lo cambie en un
-- solo lugar sin tocar la logica.
--
-- IDEMPOTENTE: create table if not exists / create sequence if not exists, de
-- modo que el dueno puede re-ejecutar el archivo sin romper nada.
-- ============================================================

-- ------------------------------------------------------------
-- inventario_config: configuracion del modulo, una sola fila.
-- Hoy solo guarda el prefijo del SKU (MAG para Magandhi). Se deja como tabla
-- (y no como constante en la RPC) justamente para que el modulo sea clonable:
-- otra organizacion Impulse solo cambia esta fila. La RPC inv_crear_producto
-- (ver 20250301000400) lee de aqui el prefijo al generar el SKU.
-- ------------------------------------------------------------
create table if not exists inventario_config (
  id            integer primary key default 1,
  prefijo       text not null default 'MAG',
  creado        timestamptz default now(),
  -- Candado: garantiza que solo pueda existir UNA fila de configuracion.
  constraint inventario_config_fila_unica check (id = 1)
);

comment on table inventario_config is 'Configuracion del modulo Inventario (una sola fila, id=1). Guarda el prefijo del SKU (default MAG). Vive en tabla y no en la RPC para que el modulo sea clonable: otra organizacion Impulse cambia el prefijo aqui, en un solo lugar. La RPC inv_crear_producto lo lee al generar el SKU.';

-- Semilla de la unica fila de configuracion. Idempotente: si ya existe, no la
-- pisa (do nothing) para no revertir un prefijo que el dueno haya cambiado.
insert into inventario_config (id, prefijo)
values (1, 'MAG')
  on conflict (id) do nothing;

-- ------------------------------------------------------------
-- inventario_sku_seq: secuencia del consecutivo del SKU.
-- Se usa una SECUENCIA (nextval) y NO un conteo de filas, porque contar filas
-- se rompe en cuanto un producto se marca inactivo (no se borra nunca) o si
-- dos altas ocurren a la vez. La secuencia es segura ante concurrencia y da
-- un consecutivo estable de por vida. inv_crear_producto la rellena a 4
-- digitos (ej. 0001). Compartida por todas las categorias: el SKU es
-- <prefijo>-<CAT>-<consecutivo global>, no un consecutivo por categoria.
-- ------------------------------------------------------------
create sequence if not exists inventario_sku_seq
  start with 1
  increment by 1
  no maxvalue
  no cycle;

comment on sequence inventario_sku_seq is 'Consecutivo global del SKU legible de productos (concurrencia-segura). inv_crear_producto usa nextval() y lo rellena a 4 digitos. No se cuenta por filas (un producto inactivo no se borra, romperia el conteo).';

-- ------------------------------------------------------------
-- productos: catalogo / ficha del producto. El "que", no el "cuanto".
--   - id (uuid) = el product_id interno, autogenerado. La llave que conecta
--     con el libro, con Pedidos y con Marketing. NUNCA lo escribe el dueno.
--   - sku (text unique) = el codigo legible (ej. MAG-CUI-0001). Lo genera la
--     RPC inv_crear_producto server-side (unico de verdad) y es INMUTABLE:
--     inv_editar_producto nunca lo toca.
--   - costo_unitario / precio_venta = bigint (pesos enteros), regla dura de
--     Finanzas: nunca float.
--   - stock_minimo = integer (umbral de reorden; no dispara nada automatico).
--   - activo = un producto NUNCA se borra (romperia el historial del libro y
--     de Marketing): se marca activo=false. Mismo espiritu que "anular".
--   - publicado = si la futura tienda publica puede mostrarlo (existe en
--     inventario != visible al cliente). Superficie publica no se construye
--     esta vuelta; la columna queda lista.
-- NO existe columna de stock/existencias: eso se deriva del libro (vista).
-- ------------------------------------------------------------
create table if not exists productos (
  id             uuid primary key default gen_random_uuid(),
  sku            text unique not null,
  nombre         text not null,
  descripcion    text,
  marca          text,
  categoria      text,
  unidad_medida  text not null default 'unidad',
  contenido      text,
  costo_unitario bigint,
  precio_venta   bigint,
  stock_minimo   integer default 0,
  proveedor      text,
  ubicacion      text,
  imagen_path    text,
  activo         boolean not null default true,
  publicado      boolean not null default false,
  creado         timestamptz default now(),
  creado_por     uuid default auth.uid(),
  actualizado    timestamptz
);

comment on table productos is 'Catalogo de productos (identidad y ficha): el "que" se vende, no el "cuanto". El stock NO vive aqui: se deriva del libro de movimientos (vista stock_actual). id (uuid) = product_id interno autogenerado; sku legible unico e INMUTABLE generado por inv_crear_producto. costo_unitario y precio_venta en bigint (pesos enteros, nunca float). Un producto no se borra: activo=false. Toda escritura va por RPC security definer.';
comment on column productos.id is 'product_id interno (uuid autogenerado). Llave que conecta con el libro, Pedidos y Marketing. Nunca lo escribe el dueno.';
comment on column productos.sku is 'Codigo legible unico (ej. MAG-CUI-0001). Generado server-side por inv_crear_producto e INMUTABLE: inv_editar_producto nunca lo toca.';
comment on column productos.activo is 'Producto activo/inactivo. Nunca se borra un producto (rompe historial del libro/Marketing): se marca activo=false.';
comment on column productos.publicado is 'Si la futura tienda publica puede mostrarlo. Separa "existe en inventario" de "visible al cliente". La superficie publica no se construye esta vuelta.';

-- Indices utiles para "Ver inventario" (filtra activos, agrupa por categoria).
create index if not exists productos_categoria_idx on productos (categoria);
create index if not exists productos_activo_idx     on productos (activo);
