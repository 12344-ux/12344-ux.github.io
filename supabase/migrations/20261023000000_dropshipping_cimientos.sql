-- ============================================================================
-- MAGANDHI · Dropshipping D1 · cimientos internos, sin venta ni pedido externo
-- ----------------------------------------------------------------------------
-- Corte: 10 de octubre de 2026.
--
-- ESTE TRAMO SI HACE
--   1. Nombra el origen de TODO producto: propio | proveedor.
--   2. Crea una bandeja interna de candidatos de Dropi (solo metadatos y URLs
--      remotas de vista previa; NO descarga imagenes ni crea productos).
--   3. Deja lista la ficha 1:1 de proveedor para el momento en que un candidato
--      llegue a Campanas (D2), sin usarla todavia.
--   4. Impide, EN BASE DE DATOS, que un producto proveedor entre al libro de
--      Inventario; tampoco aparece en stock_actual ni en Metricas de inventario.
--   5. Agrega el area/modulo Dropshipping y RPCs para organizar la bandeja.
--   6. Cierra la vitrina publica: hasta D2 un producto proveedor no puede
--      publicarse ni aparecer en catalogo_publico, aunque alguien intente
--      saltarse el boton del editor.
--
-- ESTE TRAMO NO HACE (a proposito)
--   - no crea un producto proveedor desde la bandeja;
--   - no descarga, transforma ni sube imagenes a Storage;
--   - no publica una campana proveedor;
--   - no consulta stock durante checkout;
--   - no llama orders/, no crea reservas, no confirma despachos, no cobra ni
--     envía datos de un cliente a Dropi.
--
-- Es el cimiento seguro: primero se separan con firmeza los dos tipos de
-- mercancia; luego se construye importacion, stock vivo y despacho.
--
-- DECISIONES DEL DUEÑO (10-oct-2026)
--   · La tienda nunca debe «oler» a dropshipping: no se replica el catalogo.
--   · Cliente, pedido, correos, opiniones y metricas siguen siendo MAGANDHI.
--   · Una variante Dropi sera un producto/campana distinta cuando llegue D2.
--   · Las fotos remotas viven solo como vista previa interna; se descargan y se
--     convierten a grande/-sm SOLAMENTE al «Llevar a Campanas» futuro.
--   · Precio comercial manual; costo proveedor interno.
--   · El sello MAGANDHI exigira prueba aprobada en D2, no un checkbox libre.
--
-- REGLAS DE SEGURIDAD
--   - Ningun token, proveedor, costo, id externo o URL remota sale a anon.
--   - Las tablas nuevas tienen RLS; authenticated no escribe directo.
--   - Las RPCs validan tiene_acceso_dropshipping() aunque sean definer.
--   - El trigger del libro tambien protege service_role/RPCs futuras: esconder
--     un boton NO es la seguridad.
--   - Toda lectura a Dropi sigue en dropi-sonda, que es estrictamente read-only.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) El origen es parte de la identidad, no una etiqueta de interfaz
-- ----------------------------------------------------------------------------
-- Todos los productos historicos nacen como propios por el DEFAULT. La columna
-- no reemplaza `proveedor` (texto libre historico): ese texto no es una
-- integracion ni una llave externa.
alter table productos
  add column if not exists origen text not null default 'propio';

alter table productos
  drop constraint if exists productos_origen_valido;
alter table productos
  add constraint productos_origen_valido
  check (origen in ('propio', 'proveedor'));

comment on column productos.origen is
  'D1 Dropshipping · propio = mercancia de MAGANDHI, existe en el libro de Inventario; proveedor = se despacha desde una plataforma/proveedor externo y JAMAS genera movimientos_inventario. Se decide al crear el producto y es inmutable para no reinterpretar historia.';

create index if not exists productos_origen_activo_idx
  on productos (origen, activo);

-- No se cambia el origen de una ficha ya creada. Hacerlo despues de que haya
-- pedidos o movimientos reinterpretaria la historia: una venta de mercancia
-- propia pasaria a verse como proveedor, o al reves. D2 crea proveedor ya con
-- origen='proveedor'; Inventario crea propio por su DEFAULT.
create or replace function ds__origen_producto_inmutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.origen is distinct from old.origen then
    raise exception 'DS_ORIGEN_INMUTABLE: el origen se define al crear el producto y no se cambia despues.';
  end if;
  return new;
end;
$$;

comment on function ds__origen_producto_inmutable() is
  'D1 Dropshipping · gatillo interno: impide reclasificar un producto propio/proveedor despues del alta. La historia de pedidos, costos y movimientos no se reinterpreta.';

revoke all on function ds__origen_producto_inmutable() from public, anon, authenticated;
grant execute on function ds__origen_producto_inmutable() to service_role;

drop trigger if exists ds_origen_producto_inmutable on productos;
create trigger ds_origen_producto_inmutable
before update of origen on productos
for each row execute function ds__origen_producto_inmutable();

-- ----------------------------------------------------------------------------
-- (B) Ficha 1:1 de proveedor: lista para D2, sin alta automatica aun
-- ----------------------------------------------------------------------------
-- producto_id sigue siendo la llave interna que une Campanas, Pedido Items y
-- Finanzas. Los ids Dropi quedan aqui, privados. `variacion_externa_id = ''`
-- significa "el producto no tiene variante"; no se usa NULL porque el UNIQUE
-- de PostgreSQL considera NULL distinto y permitiria duplicados silenciosos.
create table if not exists producto_proveedor (
  product_id             uuid primary key references productos(id) on delete restrict,
  plataforma             text not null default 'dropi'
                           check (plataforma in ('dropi')),
  producto_externo_id    text not null check (producto_externo_id ~ '^[0-9]{1,12}$'),
  variacion_externa_id   text not null default ''
                           check (variacion_externa_id ~ '^[A-Za-z0-9_-]{0,80}$'),
  proveedor_externo_id   text,
  proveedor_nombre       text,
  costo_reportado        bigint check (costo_reportado is null or costo_reportado >= 0),
  moneda                 text not null default 'COP' check (moneda = 'COP'),
  stock_reportado        integer check (stock_reportado is null or stock_reportado >= 0),
  stock_leido_en         timestamptz,
  stock_vence_en         timestamptz,
  importado_en           timestamptz not null default now(),
  importado_por          uuid references auth.users(id) default auth.uid(),
  actualizado            timestamptz,
  constraint producto_proveedor_stock_fechas_coherentes check (
    (stock_reportado is null and stock_leido_en is null and stock_vence_en is null)
    or
    (stock_reportado is not null and stock_leido_en is not null and stock_vence_en is not null
     and stock_vence_en >= stock_leido_en)
  ),
  constraint producto_proveedor_externo_unico unique
    (plataforma, producto_externo_id, variacion_externa_id)
);

comment on table producto_proveedor is
  'D1 Dropshipping · ficha interna 1:1 de un producto proveedor. Guarda la identidad externa (Dropi producto + variante), proveedor, costo y ultima lectura de stock. NO se expone a anon, no alimenta movimientos_inventario y D1 aun no crea filas aqui: D2 la llenara atomica al Llevar a Campanas.';
comment on column producto_proveedor.product_id is
  'FK al producto interno MAGANDHI, siempre con productos.origen=proveedor. Mantiene el contrato unico de Campanas y Pedido Items.';
comment on column producto_proveedor.variacion_externa_id is
  'Id exacto de variante en Dropi. Cadena vacia solo para productos sin variantes; una variante sera un producto/campana MAGANDHI distinta.';
comment on column producto_proveedor.stock_vence_en is
  'Instante despues del cual el stock cacheado deja de ser confiable. D2 falla cerrado si vence o Dropi no responde.';

-- La ficha externa no puede colgar de un producto propio. El FK garantiza que
-- existe; este gatillo garantiza que su origen corresponde. Corre incluso si
-- alguien usa una RPC futura o service_role.
create or replace function ds__producto_proveedor_exige_origen()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_origen text;
begin
  select origen into v_origen
    from productos
   where id = new.product_id
   for key share;

  if not found then
    raise exception 'DS_PRODUCTO_PROVEEDOR_INEXISTENTE: no existe el producto interno %.', new.product_id;
  end if;
  if v_origen <> 'proveedor' then
    raise exception 'DS_PRODUCTO_PROVEEDOR_ORIGEN: producto_proveedor exige productos.origen=proveedor.';
  end if;
  return new;
end;
$$;

comment on function ds__producto_proveedor_exige_origen() is
  'D1 Dropshipping · gatillo interno: una ficha externa solo puede pertenecer a un producto marcado proveedor.';

revoke all on function ds__producto_proveedor_exige_origen() from public, anon, authenticated;
grant execute on function ds__producto_proveedor_exige_origen() to service_role;

drop trigger if exists ds_producto_proveedor_exige_origen on producto_proveedor;
create trigger ds_producto_proveedor_exige_origen
before insert or update of product_id on producto_proveedor
for each row execute function ds__producto_proveedor_exige_origen();

-- ----------------------------------------------------------------------------
-- (C) Bandeja de candidatos: fuente temporal, no catalogo copiado
-- ----------------------------------------------------------------------------
-- Un candidato NO es aun un producto MAGANDHI ni una campaña. Guarda el mínimo
-- que eligió el operador desde la lectura actual de Dropi para poder curarlo
-- después: identidad externa, texto/valores de referencia, stock sellado y URLs
-- HTTPS de PREVIEW. Esas URLs no se publican ni se descargan en D1; en D2 se
-- releerá la ficha desde Dropi por id antes de bajar cualquier byte a Storage.
create table if not exists dropshipping_candidatos (
  id                    uuid primary key default gen_random_uuid(),
  plataforma            text not null default 'dropi'
                          check (plataforma in ('dropi')),
  producto_externo_id   text not null check (producto_externo_id ~ '^[0-9]{1,12}$'),
  variacion_externa_id  text not null default ''
                          check (variacion_externa_id ~ '^[A-Za-z0-9_-]{0,80}$'),
  proveedor_externo_id  text,
  nombre_externo        text not null check (length(btrim(nombre_externo)) between 1 and 200),
  categoria_externa     text,
  precio_proveedor      bigint check (precio_proveedor is null or precio_proveedor >= 0),
  precio_sugerido       bigint check (precio_sugerido is null or precio_sugerido >= 0),
  stock_reportado       integer check (stock_reportado is null or stock_reportado >= 0),
  stock_leido_en        timestamptz,
  fotos_remotas         jsonb not null default '[]'::jsonb
                          check (jsonb_typeof(fotos_remotas) = 'array'),
  estado                text not null default 'bandeja'
                          check (estado in ('bandeja', 'descartado', 'llevado_a_campanas')),
  creado                timestamptz not null default now(),
  creado_por            uuid references auth.users(id) default auth.uid(),
  actualizado           timestamptz not null default now(),
  actualizado_por       uuid references auth.users(id) default auth.uid(),
  constraint dropshipping_candidato_externo_unico unique
    (plataforma, producto_externo_id, variacion_externa_id)
);

comment on table dropshipping_candidatos is
  'D1 Dropshipping · bandeja privada de candidatos seleccionados por MAGANDHI desde una lectura de Dropi. NO es un espejo del catalogo, NO crea producto/campaña, NO publica, NO descarga fotos y NO llama orders/. Las URLs de fotos son preview temporal HTTPS; D2 vuelve a leer Dropi antes de importarlas a Storage.';
comment on column dropshipping_candidatos.estado is
  'bandeja = candidato bajo curaduria; descartado = se conserva el rastro pero no se trabaja; llevado_a_campanas = reservado para D2, que crea producto proveedor + borrador atomico.';

create index if not exists dropshipping_candidatos_estado_actualizado_idx
  on dropshipping_candidatos (estado, actualizado desc);

-- ----------------------------------------------------------------------------
-- (D) Acceso, RLS y RPC de bandeja
-- ----------------------------------------------------------------------------
create or replace function tiene_acceso_dropshipping()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('dropshipping')
      or tiene_modulo('proveedores')
      or tiene_modulo('despachos');
$$;

comment on function tiene_acceso_dropshipping() is
  'D1 Dropshipping · acceso al area: admin o modulo dropshipping/proveedores/despachos. En D1 la lectura externa Dropi sigue exigiendo admin dentro de la Edge Function; esta guardia protege datos internos y la bandeja.';

-- Las tablas son privadas. El frontend autenticado puede LEER solo si tiene el
-- módulo; toda escritura pasa por RPC definer con validación doble.
alter table producto_proveedor enable row level security;
alter table dropshipping_candidatos enable row level security;

drop policy if exists "producto_proveedor_select_dropshipping" on producto_proveedor;
create policy "producto_proveedor_select_dropshipping" on producto_proveedor
  for select to authenticated using (tiene_acceso_dropshipping());

drop policy if exists "dropshipping_candidatos_select_dropshipping" on dropshipping_candidatos;
create policy "dropshipping_candidatos_select_dropshipping" on dropshipping_candidatos
  for select to authenticated using (tiene_acceso_dropshipping());

-- Auto-expose de tablas esta apagado: sin estos grants PostgREST responde 403
-- antes de evaluar RLS. No se concede INSERT/UPDATE/DELETE directo.
grant select on table producto_proveedor, dropshipping_candidatos to authenticated;

-- Guarda/actualiza un candidato desde la lectura de Dropi. La UI nunca inserta
-- directo. No acepta URL HTTP, javascript:, credenciales ni arreglos enormes;
-- aun asi estas URLs JAMAS se descargan en D1, solo se pintan como preview.
create or replace function ds_guardar_candidato(
  p_producto_externo_id  text,
  p_variacion_externa_id text default '',
  p_proveedor_externo_id text default null,
  p_nombre_externo       text default null,
  p_categoria_externa    text default null,
  p_precio_proveedor     bigint default null,
  p_precio_sugerido      bigint default null,
  p_stock_reportado      integer default null,
  p_stock_leido_en       timestamptz default null,
  p_fotos_remotas        jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_producto  text := btrim(coalesce(p_producto_externo_id, ''));
  v_variacion text := btrim(coalesce(p_variacion_externa_id, ''));
  v_nombre    text := btrim(coalesce(p_nombre_externo, ''));
  v_fotos     jsonb := '[]'::jsonb;
  v_url       text;
  v_id        uuid;
begin
  if not tiene_acceso_dropshipping() then
    raise exception 'DS_SIN_ACCESO: se requiere el modulo dropshipping.';
  end if;
  if v_producto !~ '^[0-9]{1,12}$' then
    raise exception 'DS_CANDIDATO_PRODUCTO_INVALIDO: el id de producto Dropi debe ser numerico.';
  end if;
  if v_variacion !~ '^[A-Za-z0-9_-]{0,80}$' then
    raise exception 'DS_CANDIDATO_VARIACION_INVALIDA: la variante Dropi no es valida.';
  end if;
  if length(v_nombre) = 0 or length(v_nombre) > 200 then
    raise exception 'DS_CANDIDATO_NOMBRE_INVALIDO: el nombre es obligatorio y no puede superar 200 caracteres.';
  end if;
  if p_precio_proveedor is not null and p_precio_proveedor < 0 then
    raise exception 'DS_CANDIDATO_PRECIO_INVALIDO: el precio proveedor no puede ser negativo.';
  end if;
  if p_precio_sugerido is not null and p_precio_sugerido < 0 then
    raise exception 'DS_CANDIDATO_PRECIO_INVALIDO: el precio sugerido no puede ser negativo.';
  end if;
  if p_stock_reportado is not null and p_stock_reportado < 0 then
    raise exception 'DS_CANDIDATO_STOCK_INVALIDO: el stock no puede ser negativo.';
  end if;
  if p_fotos_remotas is null then p_fotos_remotas := '[]'::jsonb; end if;
  if jsonb_typeof(p_fotos_remotas) <> 'array' then
    raise exception 'DS_CANDIDATO_FOTOS_INVALIDAS: las fotos deben ser una lista.';
  end if;
  if jsonb_array_length(p_fotos_remotas) > 12 then
    raise exception 'DS_CANDIDATO_FOTOS_INVALIDAS: maximo 12 fotos de vista previa.';
  end if;

  for v_url in select value from jsonb_array_elements_text(p_fotos_remotas) loop
    if length(v_url) > 500 or v_url !~ '^https://[^[:space:]]+$' then
      raise exception 'DS_CANDIDATO_FOTO_INVALIDA: solo se aceptan URLs HTTPS sin espacios.';
    end if;
    v_fotos := v_fotos || jsonb_build_array(v_url);
  end loop;

  insert into dropshipping_candidatos (
    plataforma, producto_externo_id, variacion_externa_id, proveedor_externo_id,
    nombre_externo, categoria_externa, precio_proveedor, precio_sugerido,
    stock_reportado, stock_leido_en, fotos_remotas, estado, actualizado, actualizado_por
  ) values (
    'dropi', v_producto, v_variacion, nullif(btrim(p_proveedor_externo_id), ''),
    v_nombre, nullif(btrim(p_categoria_externa), ''), p_precio_proveedor, p_precio_sugerido,
    p_stock_reportado, case when p_stock_reportado is null then null else coalesce(p_stock_leido_en, now()) end,
    v_fotos, 'bandeja', now(), auth.uid()
  )
  on conflict (plataforma, producto_externo_id, variacion_externa_id) do update
    set proveedor_externo_id = excluded.proveedor_externo_id,
        nombre_externo       = excluded.nombre_externo,
        categoria_externa    = excluded.categoria_externa,
        precio_proveedor     = excluded.precio_proveedor,
        precio_sugerido      = excluded.precio_sugerido,
        stock_reportado      = excluded.stock_reportado,
        stock_leido_en       = excluded.stock_leido_en,
        fotos_remotas        = excluded.fotos_remotas,
        -- Guardar otra vez un candidato descartado significa volver a ponerlo
        -- bajo curaduria; un candidato ya llevado a Campañas queda sellado para
        -- que una relectura futura no deshaga el vínculo D2 por accidente.
        estado               = case
                                  when dropshipping_candidatos.estado = 'llevado_a_campanas' then 'llevado_a_campanas'
                                  else 'bandeja'
                                end,
        actualizado          = now(),
        actualizado_por      = auth.uid()
  returning id into v_id;

  return v_id;
end;
$$;

comment on function ds_guardar_candidato(text, text, text, text, text, bigint, bigint, integer, timestamptz, jsonb) is
  'D1 Dropshipping · guarda o refresca un candidato Dropi en la bandeja privada. Solo modulo Dropshipping; valida ids, montos, stock y hasta 12 URLs HTTPS de preview. NO crea producto, campaña, imagen local, movimiento, pedido ni llamada externa.';

create or replace function ds_actualizar_estado_candidato(
  p_id     uuid,
  p_estado text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text := btrim(coalesce(p_estado, ''));
  v_id uuid;
begin
  if not tiene_acceso_dropshipping() then
    raise exception 'DS_SIN_ACCESO: se requiere el modulo dropshipping.';
  end if;
  if v_estado not in ('bandeja', 'descartado') then
    raise exception 'DS_ESTADO_INVALIDO: D1 solo permite bandeja o descartado.';
  end if;

  update dropshipping_candidatos
     set estado = v_estado,
         actualizado = now(),
         actualizado_por = auth.uid()
   where id = p_id
   returning id into v_id;

  if v_id is null then
    raise exception 'DS_CANDIDATO_NO_ENCONTRADO: el candidato no existe.';
  end if;
  return v_id;
end;
$$;

comment on function ds_actualizar_estado_candidato(uuid, text) is
  'D1 Dropshipping · mueve un candidato entre bandeja y descartado. No permite llevar a Campañas: esa transicion queda reservada para la RPC atomica de D2.';

-- Default privileges estan cerrados desde Tramo 0. Se declara cada ACL de
-- forma nominal: anon nunca ejecuta; authenticated solo las puertas del panel;
-- service_role conserva acceso a todas las funciones internas.
revoke all on function tiene_acceso_dropshipping() from public, anon;
revoke all on function ds_guardar_candidato(text, text, text, text, text, bigint, bigint, integer, timestamptz, jsonb) from public, anon;
revoke all on function ds_actualizar_estado_candidato(uuid, text) from public, anon;
grant execute on function tiene_acceso_dropshipping() to authenticated, service_role;
grant execute on function ds_guardar_candidato(text, text, text, text, text, bigint, bigint, integer, timestamptz, jsonb) to authenticated, service_role;
grant execute on function ds_actualizar_estado_candidato(uuid, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) El libro de Inventario queda fisicamente cerrado a proveedor
-- ----------------------------------------------------------------------------
-- `crear_pedido` y `anular_pedido` escriben hoy movimientos directamente, no
-- solo inv_registrar_movimiento. Por eso se necesita un gatillo sobre la TABLA:
-- cubre toda ruta presente o futura, incluso service_role. D2 ramificara esos
-- dos RPCs para permitir pedido proveedor sin insertar en este libro.
create or replace function ds__bloquear_movimiento_proveedor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_origen text;
begin
  select origen into v_origen from productos where id = new.product_id;
  if v_origen = 'proveedor' then
    raise exception 'DS_PRODUCTO_PROVEEDOR_SIN_INVENTARIO: un producto proveedor no admite movimientos de Inventario.';
  end if;
  return new;
end;
$$;

comment on function ds__bloquear_movimiento_proveedor() is
  'D1 Dropshipping · gatillo interno sobre movimientos_inventario. Rechaza cualquier entrada/salida/ajuste de producto proveedor, incluso desde SECURITY DEFINER o service_role.';

revoke all on function ds__bloquear_movimiento_proveedor() from public, anon, authenticated;
grant execute on function ds__bloquear_movimiento_proveedor() to service_role;

drop trigger if exists ds_bloquear_movimiento_proveedor on movimientos_inventario;
create trigger ds_bloquear_movimiento_proveedor
before insert or update of product_id on movimientos_inventario
for each row execute function ds__bloquear_movimiento_proveedor();

-- Mensaje claro para el operador de Inventario; el trigger de arriba mantiene
-- el candado incluso si otra funcion omite este chequeo.
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
  v_origen      text;
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

  select activo, origen into v_activo, v_origen from productos where id = p_product_id;
  if v_activo is null then
    raise exception 'El producto % no existe.', p_product_id;
  end if;
  if v_origen = 'proveedor' then
    raise exception 'DS_PRODUCTO_PROVEEDOR_SIN_INVENTARIO: este producto se controla desde Dropshipping, no desde el libro de Inventario.';
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

comment on function inv_registrar_movimiento(uuid, text, integer, text, text, bigint, date) is
  'Inventario · escribe un movimiento append-only de producto propio. D1: rechaza de forma clara productos.origen=proveedor; el gatillo de la tabla replica el candado para toda otra ruta. Una salida propia puede quedar negativa como contrato historico del modulo.';

-- stock_actual es una vista de INVENTARIO PROPIO, no un listado general de
-- productos. Esto protege vitrina, movimientos y cualquier futuro consumidor
-- que parta de ella. security_invoker se reafirma porque catalogo_publico no la
-- usa y el Tramo 0 exige RLS real para las vistas internas.
create or replace view stock_actual as
select
  p.id     as product_id,
  p.sku    as sku,
  p.nombre as nombre,
  coalesce(sum(
    case m.tipo
      when 'entrada'        then  m.cantidad
      when 'ajuste_entrada' then  m.cantidad
      when 'salida'         then -m.cantidad
      when 'ajuste_salida'  then -m.cantidad
    end
  ), 0)::integer as existencias
from productos p
left join movimientos_inventario m on m.product_id = p.id
where p.origen = 'propio'
group by p.id, p.sku, p.nombre;

alter view stock_actual set (security_invoker = true);

comment on view stock_actual is
  'D1 Dropshipping · existencias derivadas EXCLUSIVAMENTE de productos.origen=propio y su libro movimientos_inventario. Producto proveedor no aparece: Dropi sera su fuente de stock en D2. SECURITY INVOKER, hereda RLS de Inventario.';

-- ----------------------------------------------------------------------------
-- (F) Metricas de Inventario: solo mercancia propia
-- ----------------------------------------------------------------------------
create or replace function mt_inventario()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if not tiene_acceso_datos_metricas() then raise exception 'MT_SIN_ACCESO'; end if;
  return (
    with stock as (
      select p.id, p.sku, p.nombre, p.categoria, coalesce(p.stock_minimo, 0) as stock_minimo,
             p.activo, coalesce(p.costo_unitario, 0) as costo_unitario,
             coalesce(sum(case m.tipo
                            when 'entrada'        then  m.cantidad
                            when 'ajuste_entrada' then  m.cantidad
                            when 'salida'         then -m.cantidad
                            when 'ajuste_salida'  then -m.cantidad end), 0)::int as existencias
        from productos p
        left join movimientos_inventario m on m.product_id = p.id
       where p.origen = 'propio'
       group by p.id
    ),
    venta30 as (
      -- Unidades propias vendidas en 30 dias. Las ventas proveedor SI son
      -- ventas MAGANDHI, pero no son rotacion de mercancia propia y por eso no
      -- alimentan dias de inventario ni alertas de bodega.
      select pi.product_id, sum(pi.cantidad) as u
        from pedido_items pi
        join pedidos pe on pe.id = pi.pedido_id
        join productos p on p.id = pi.product_id
       where not pe.anulado
         and pe.fecha_orden >= v_hoy - 29
         and p.origen = 'propio'
       group by pi.product_id
    )
    select jsonb_build_object(
      'hoy', v_hoy,
      'totales', jsonb_build_object(
        'productos_activos', (select count(*) from stock where activo),
        'unidades_total',    (select coalesce(sum(existencias), 0) from stock where activo),
        'valor_costo',       (select coalesce(sum(existencias::bigint * costo_unitario), 0) from stock where activo),
        'bajo_stock',        (select count(*) from stock where activo and existencias <= stock_minimo),
        'agotados',          (select count(*) from stock where activo and existencias <= 0)),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object(
            'nombre', s.nombre, 'sku', s.sku, 'existencias', s.existencias, 'stock_minimo', s.stock_minimo,
            'vendidas_30d', coalesce(v.u, 0),
            'dias_inventario', case when coalesce(v.u, 0) > 0 then round(s.existencias / (v.u / 30.0)) end,
            'bajo', s.existencias <= s.stock_minimo, 'agotado', s.existencias <= 0
          ) order by (s.existencias <= 0) desc, (s.existencias <= s.stock_minimo) desc, s.nombre), '[]')
        from stock s left join venta30 v on v.product_id = s.id where s.activo),
      'por_semana', (select coalesce(jsonb_agg(jsonb_build_object('semana', g::date,
            'unidades', (select coalesce(sum(pi.cantidad), 0)
                            from pedido_items pi
                            join pedidos pe on pe.id = pi.pedido_id
                            join productos p on p.id = pi.product_id
                           where not pe.anulado
                             and p.origen = 'propio'
                             and pe.fecha_orden >= g::date
                             and pe.fecha_orden < g::date + 7)) order by g), '[]')
        from generate_series(date_trunc('week', v_hoy::timestamp) - interval '11 weeks', date_trunc('week', v_hoy::timestamp), interval '1 week') g),
      'alertas', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'existencias', existencias,
            'stock_minimo', stock_minimo, 'agotado', existencias <= 0) order by existencias), '[]')
        from stock where activo and existencias <= stock_minimo)
    )
  );
end;
$$;

comment on function mt_inventario() is
  'D1 Dropshipping · Metricas de Inventario propio: existencias del libro, rotacion, dias de inventario y alertas solo para productos.origen=propio. Las ventas proveedor siguen siendo ventas MAGANDHI en las otras capas, pero no se interpretan como bodega propia.';

revoke execute on function mt_inventario() from public, anon;
grant execute on function mt_inventario() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (G) Cinturon de publicacion: proveedor espera D2
-- ----------------------------------------------------------------------------
-- El editor de Campanas puede ligar una ficha proveedora en el futuro; hasta
-- que exista stock vivo/fallo cerrado/checkout proveedor, publicarla seria
-- vender aire. La RPC bloquea la via normal y catalogo_publico la oculta incluso
-- si una escritura privilegiada cambiara publicado=true por accidente.
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
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select cp.product_id_ref, cp.precio_venta, p.activo, p.origen
    into v_producto_id, v_precio, v_producto_activo, v_origen
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
    if coalesce(v_origen, 'propio') = 'proveedor' then
      raise exception 'DS_PUBLICACION_PENDIENTE: este producto proveedor espera D2 (stock vivo y checkout seguro) antes de publicarse.';
    end if;
    if v_precio is null or v_precio <= 0 then
      raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
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
  'CAMPANAS · publica/despublica sin borrar. D1 agrega: producto.origen=proveedor no se publica hasta D2, cuando haya stock Dropi vigente/fallo cerrado y checkout seguro. Despublicar siempre queda permitido.';

revoke execute on function cm_publicar_campana(uuid, boolean) from public, anon;
grant execute on function cm_publicar_campana(uuid, boolean) to authenticated, service_role;

-- Misma lista blanca publica de siempre. La columna origen NO sale. Un
-- proveedor queda fuera por ahora aunque alguien altere publicado con un rol
-- privilegiado; D2 redefinira este CASE para usar producto_proveedor.stock.
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
  and coalesce(p.origen, 'propio') = 'propio';

comment on view catalogo_publico is
  'D1 Dropshipping · superficie publica de lista blanca. Solo campañas activas/publicadas de productos propios; producto proveedor queda completamente fuera hasta D2. Nunca expone origen, proveedor, costo, ids externos ni existencias exactas.';

grant select on catalogo_publico to anon, authenticated, service_role;

commit;
