-- ============================================================
-- Magandhi Corporation · Modulo Inventario · Funciones RPC (la unica via de escritura)
-- Toda escritura del modulo pasa por estas RPC security definer, espejo de las
-- de Finanzas (guardar_asiento, editar_asiento). Ninguna tabla del modulo
-- tiene policy de INSERT/UPDATE/DELETE para authenticated (ver
-- 20250301000300_inventario_rls.sql): el cliente no escribe directo.
--
-- Todas son:
--   - security definer con set search_path = public fijo.
--   - Validan tiene_acceso_inventario() al entrar, de modo que el candado de
--     acceso se respeta aunque la funcion salte RLS por ser definer. Esa
--     funcion (definida en 20250301000300_inventario_rls.sql) acepta las tres
--     claves equivalentes del modulo (inventario / produccion / inventarios),
--     asi el candado de escritura habla la MISMA convencion que el panel, los
--     cores y la RLS.
--
-- FIRMAS EXACTAS (para el frontend, FEAT-003/004):
--   inv_crear_producto(p_nombre text, p_descripcion text, p_marca text,
--     p_categoria text, p_unidad_medida text, p_contenido text,
--     p_costo_unitario bigint, p_precio_venta bigint, p_stock_minimo integer,
--     p_proveedor text, p_ubicacion text, p_imagen_path text,
--     p_cantidad_inicial integer) -> jsonb {id, sku}
--   inv_registrar_movimiento(p_product_id uuid, p_tipo text,
--     p_cantidad integer, p_motivo text, p_referencia text,
--     p_costo_unitario_mov bigint, p_fecha date) -> jsonb {id, existencias}
--   inv_editar_producto(p_id uuid, p_nombre text, p_descripcion text,
--     p_marca text, p_categoria text, p_unidad_medida text, p_contenido text,
--     p_costo_unitario bigint, p_precio_venta bigint, p_stock_minimo integer,
--     p_proveedor text, p_ubicacion text, p_imagen_path text,
--     p_activo boolean, p_publicado boolean) -> uuid
--
-- IDEMPOTENTE: create or replace (re-ejecutar solo actualiza la logica).
-- ============================================================

-- ------------------------------------------------------------
-- inv_crear_producto: alta de un producto.
-- Genera el SKU server-side (unico de verdad, no depende del navegador) como
-- <prefijo>-<CAT>-<consecutivo 4 digitos>:
--   - <prefijo> viene de inventario_config (clonable, no escrito a fuego).
--   - <CAT> = primeros 3-4 chars de la categoria en MAYUSCULAS y sin acentos.
--     Si no hay categoria, ese tramo se OMITE -> <prefijo>-<consecutivo>.
--   - <consecutivo> = nextval('inventario_sku_seq') a 4 digitos (concurrencia
--     segura; NO se cuentan filas).
-- Inserta el producto y, si p_cantidad_inicial > 0, registra la 'entrada'
-- inicial en el libro con esa cantidad. Devuelve jsonb {id, sku}. El SKU es
-- INMUTABLE: nunca se recalcula (inv_editar_producto no lo toca).
-- ------------------------------------------------------------
create or replace function inv_crear_producto(
  p_nombre           text,
  p_descripcion      text default null,
  p_marca            text default null,
  p_categoria        text default null,
  p_unidad_medida    text default 'unidad',
  p_contenido        text default null,
  p_costo_unitario   bigint default null,
  p_precio_venta     bigint default null,
  p_stock_minimo     integer default 0,
  p_proveedor        text default null,
  p_ubicacion        text default null,
  p_imagen_path      text default null,
  p_cantidad_inicial integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id          uuid;
  v_prefijo     text;
  v_cat         text;
  v_consecutivo text;
  v_sku         text;
begin
  if not tiene_acceso_inventario() then
    raise exception 'Acceso denegado: se requiere el modulo inventario.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;
  if p_cantidad_inicial is not null and p_cantidad_inicial < 0 then
    raise exception 'La cantidad inicial no puede ser negativa.';
  end if;

  -- Prefijo desde la configuracion (clonable). Fallback 'MAG' si faltara.
  select prefijo into v_prefijo from inventario_config where id = 1;
  v_prefijo := coalesce(nullif(trim(v_prefijo), ''), 'MAG');

  -- Abreviatura de categoria: mayusculas, sin acentos, solo A-Z0-9, 3-4 chars.
  -- unaccent no esta garantizado; se translitera a mano el set de acentos del
  -- espanol para no depender de una extension.
  if p_categoria is not null and length(trim(p_categoria)) > 0 then
    v_cat := upper(trim(p_categoria));
    v_cat := translate(v_cat, 'ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÑ', 'AEIOUAEIOUAEIOUAEIOUN');
    v_cat := regexp_replace(v_cat, '[^A-Z0-9]', '', 'g');
    v_cat := substring(v_cat from 1 for 4);
    if v_cat = '' then
      v_cat := null;
    end if;
  else
    v_cat := null;
  end if;

  -- Consecutivo concurrencia-seguro (secuencia, NO conteo de filas), 4 digitos.
  v_consecutivo := lpad(nextval('inventario_sku_seq')::text, 4, '0');

  -- Ensambla el SKU. Omite el tramo <CAT> si no hay categoria.
  if v_cat is null then
    v_sku := v_prefijo || '-' || v_consecutivo;
  else
    v_sku := v_prefijo || '-' || v_cat || '-' || v_consecutivo;
  end if;

  insert into productos (
    sku, nombre, descripcion, marca, categoria, unidad_medida, contenido,
    costo_unitario, precio_venta, stock_minimo, proveedor, ubicacion, imagen_path
  ) values (
    v_sku, p_nombre, p_descripcion, p_marca, p_categoria,
    coalesce(nullif(trim(p_unidad_medida), ''), 'unidad'),
    p_contenido, p_costo_unitario, p_precio_venta,
    coalesce(p_stock_minimo, 0), p_proveedor, p_ubicacion, p_imagen_path
  )
  returning id into v_id;

  -- Entrada inicial en el libro (si el dueno declaro una cantidad de arranque).
  if coalesce(p_cantidad_inicial, 0) > 0 then
    insert into movimientos_inventario (product_id, tipo, cantidad, motivo, costo_unitario_mov)
    values (v_id, 'entrada', p_cantidad_inicial, 'Alta de producto (cantidad inicial)', p_costo_unitario);
  end if;

  return jsonb_build_object('id', v_id, 'sku', v_sku);
end;
$$;

comment on function inv_crear_producto(text, text, text, text, text, text, bigint, bigint, integer, text, text, text, integer) is 'Alta de un producto. Genera el SKU server-side como <prefijo (inventario_config)>-<CAT (categoria en mayusculas, sin acentos, 3-4 chars; se omite si no hay categoria)>-<consecutivo 4 digitos via inventario_sku_seq>. Inserta el producto y, si p_cantidad_inicial > 0, registra la entrada inicial en el libro. Devuelve jsonb {id, sku}. El SKU es inmutable. Exige tiene_acceso_inventario() (claves inventario/produccion/inventarios).';

-- ------------------------------------------------------------
-- inv_registrar_movimiento: escribe una fila en el libro (append-only).
-- Valida modulo, que el producto exista y este activo, cantidad > 0 y tipo en
-- el conjunto permitido. CONTRATO DE VENTA SIN STOCK (PLANO §2.3, decision del
-- dueno): una 'salida' que dejaria el stock en negativo NO se bloquea; se
-- registra igual y se DEVUELVE el stock resultante para que la UI alerte en el
-- momento. Bloquear a nivel de datos daria falsa sensacion de control y podria
-- impedir registrar una venta que de verdad ocurrio. Devuelve jsonb
-- {id, existencias}.
-- ------------------------------------------------------------
create or replace function inv_registrar_movimiento(
  p_product_id         uuid,
  p_tipo               text,
  p_cantidad           integer,
  p_motivo             text default null,
  p_referencia         text default null,
  p_costo_unitario_mov bigint default null,
  p_fecha              date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id          uuid;
  v_activo      boolean;
  v_existencias integer;
begin
  if not tiene_acceso_inventario() then
    raise exception 'Acceso denegado: se requiere el modulo inventario.';
  end if;

  if p_tipo not in ('entrada','salida','ajuste_entrada','ajuste_salida') then
    raise exception 'Tipo de movimiento invalido: %. Use entrada, salida, ajuste_entrada o ajuste_salida.', p_tipo;
  end if;
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser un entero positivo.';
  end if;

  select activo into v_activo from productos where id = p_product_id;
  if v_activo is null then
    raise exception 'El producto % no existe.', p_product_id;
  end if;
  if not v_activo then
    raise exception 'El producto % esta inactivo; no admite movimientos.', p_product_id;
  end if;

  insert into movimientos_inventario (
    product_id, tipo, cantidad, motivo, referencia, costo_unitario_mov, fecha
  ) values (
    p_product_id, p_tipo, p_cantidad, p_motivo, p_referencia, p_costo_unitario_mov,
    coalesce(p_fecha, current_date)
  )
  returning id into v_id;

  -- Stock resultante derivado del libro (misma logica de signo que la vista).
  -- Una salida sin stock deja existencias negativas: se permite y se informa.
  select coalesce(sum(
           case tipo
             when 'entrada'        then  cantidad
             when 'ajuste_entrada' then  cantidad
             when 'salida'         then -cantidad
             when 'ajuste_salida'  then -cantidad
           end
         ), 0)::integer
    into v_existencias
    from movimientos_inventario
   where product_id = p_product_id;

  return jsonb_build_object('id', v_id, 'existencias', v_existencias);
end;
$$;

comment on function inv_registrar_movimiento(uuid, text, integer, text, text, bigint, date) is 'Escribe una fila en el libro de movimientos (append-only). Valida modulo, producto existente y activo, cantidad > 0 y tipo permitido. Una salida que dejaria el stock negativo NO se bloquea (PLANO §2.3): se registra y se devuelve el stock resultante para que la UI alerte. Devuelve jsonb {id, existencias}. Exige tiene_acceso_inventario() (claves inventario/produccion/inventarios).';

-- ------------------------------------------------------------
-- inv_editar_producto: edita SOLO la ficha del producto.
-- NUNCA toca el sku (inmutable) ni las existencias (solo se mueven por el
-- libro via inv_registrar_movimiento). Marca actualizado = now(). Permite
-- alternar activo (baja logica) y publicado. Devuelve el id editado.
-- ------------------------------------------------------------
create or replace function inv_editar_producto(
  p_id             uuid,
  p_nombre         text,
  p_descripcion    text default null,
  p_marca          text default null,
  p_categoria      text default null,
  p_unidad_medida  text default 'unidad',
  p_contenido      text default null,
  p_costo_unitario bigint default null,
  p_precio_venta   bigint default null,
  p_stock_minimo   integer default 0,
  p_proveedor      text default null,
  p_ubicacion      text default null,
  p_imagen_path    text default null,
  p_activo         boolean default true,
  p_publicado      boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existe uuid;
begin
  if not tiene_acceso_inventario() then
    raise exception 'Acceso denegado: se requiere el modulo inventario.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;

  select id into v_existe from productos where id = p_id;
  if v_existe is null then
    raise exception 'El producto % no existe.', p_id;
  end if;

  -- Edita SOLO la ficha. No aparece sku (inmutable) ni existencias (derivadas
  -- del libro): ni siquiera se listan en el UPDATE, para que sea imposible
  -- alterarlas por esta via.
  update productos
     set nombre        = p_nombre,
         descripcion   = p_descripcion,
         marca         = p_marca,
         categoria     = p_categoria,
         unidad_medida = coalesce(nullif(trim(p_unidad_medida), ''), 'unidad'),
         contenido     = p_contenido,
         costo_unitario = p_costo_unitario,
         precio_venta  = p_precio_venta,
         stock_minimo  = coalesce(p_stock_minimo, 0),
         proveedor     = p_proveedor,
         ubicacion     = p_ubicacion,
         imagen_path   = p_imagen_path,
         activo        = coalesce(p_activo, true),
         publicado     = coalesce(p_publicado, false),
         actualizado   = now()
   where id = p_id;

  return p_id;
end;
$$;

comment on function inv_editar_producto(uuid, text, text, text, text, text, text, bigint, bigint, integer, text, text, text, boolean, boolean) is 'Edita SOLO la ficha del producto (nombre, descripcion, marca, categoria, unidad_medida, contenido, costo_unitario, precio_venta, stock_minimo, proveedor, ubicacion, imagen_path, activo, publicado) y marca actualizado=now(). NUNCA toca el sku (inmutable) ni las existencias (solo se mueven por el libro). Exige tiene_acceso_inventario() (claves inventario/produccion/inventarios). Devuelve el id.';
