-- ============================================================
-- MAGANDHI · PAGOS WEB · WOMPI F2 (intencion persistida + webhook idempotente)
-- ------------------------------------------------------------
-- Diseno: docs/PLANO-PAGOS.md
--
-- LA PROMESA DE ESTE TRAMO: un pago aprobado se convierte en un pedido
-- trazable EXACTAMENTE UNA VEZ, sin vender existencias que no hay y sin dejar
-- dinero huerfano.
--
-- PIEZAS:
--   pagos_intencion  una fila por intento de pago. Guarda el MONTO FIRMADO
--                    (para compararlo despues), la foto del producto y del
--                    comprador (lo que escribio en la TIENDA: Wompi solo
--                    confirma el pago) y el utm_campaign / mg_vid de la visita.
--   pagos_eventos    libro de avisos de Wompi. Wompi NO envia un id de evento
--                    unico, asi que la idempotencia se construye con la llave
--                    unica (transaccion_id, estado_wompi): un reintento choca
--                    y no reprocesa; un cambio legitimo de estado si entra.
--   pw_registrar_intencion()  la llama crear-intencion-pago ANTES de firmar.
--   pw_procesar_pago()        la llama wompi-webhook con el evento YA VERIFICADO
--                             (el checksum se valida en la Edge Function, que es
--                             donde vive el secreto de eventos). Hace todo en
--                             UNA transaccion.
--   pw_revisiones() / pw_resolver_revision()  el aviso rojo del panel.
--
-- DECISIONES DEL DUENO (8-oct-2026):
--   (1) Pago aprobado SIN STOCK -> NO se crea el pedido. La intencion queda en
--       requiere_revision y salta como aviso rojo para resolver a mano. Un
--       pedido imposible ensuciaria Ventas; plata recibida sin producto debe
--       verse, no esconderse.
--   (2) Los datos del comprador son los de la TIENDA. De Wompi se guarda lo
--       util (transaccion, metodo de pago, correo del pagador) como respaldo.
--
-- Montos: bigint. monto_centavos es lo que se firma (pesos * cantidad * 100).
-- Forward e idempotente. REQUISITO: despues de 20261018000000.
-- ============================================================

-- ------------------------------------------------------------
-- Acceso: Ventas (o admin) ve y resuelve los pagos que requieren revision.
-- ------------------------------------------------------------
create or replace function tiene_acceso_pagos()
returns boolean language sql stable security definer set search_path = public as $$
  select tiene_modulo('ventas');
$$;
comment on function tiene_acceso_pagos() is 'Pagos web: admin o modulo ventas (un pago que requiere revision lo resuelve quien atiende pedidos).';
revoke execute on function tiene_acceso_pagos() from public, anon;
grant execute on function tiene_acceso_pagos() to authenticated, service_role;

-- ------------------------------------------------------------
-- pagos_intencion
-- ------------------------------------------------------------
create table if not exists pagos_intencion (
  referencia        text primary key check (referencia ~ '^[A-Za-z0-9_-]{6,64}$'),
  -- que se vende (foto al momento de firmar)
  campana_id        uuid references campana_producto(id),
  product_id        uuid references productos(id),
  slug              text,
  nombre            text,
  cantidad          integer not null default 1 check (cantidad > 0),
  precio_unitario   bigint  not null check (precio_unitario > 0),
  monto_centavos    bigint  not null check (monto_centavos > 0),
  moneda            text    not null default 'COP',
  entorno           text    not null check (entorno in ('sandbox','prod')),
  -- quien compra: LO QUE ESCRIBIO EN LA TIENDA
  comprador_nombre      text,
  comprador_correo      text,
  comprador_telefono    text,
  comprador_direccion   text,
  comprador_ciudad      text,
  comprador_departamento text,
  comprador_pais        text,
  -- de donde viene (enchufes de Email marketing y Metricas)
  utm_campaign      text,
  mg_vid            text,
  -- resultado
  estado            text not null default 'creada'
                      check (estado in ('creada','procesada','rechazada','requiere_revision')),
  pedido_id         uuid references pedidos(id),
  transaccion_id    text,
  estado_wompi      text,
  metodo_pago       text,
  correo_pagador    text,
  revision_motivo   text,
  resuelta_en       timestamptz,
  resuelta_por      uuid references auth.users(id),
  resuelta_nota     text,
  creado            timestamptz not null default now(),
  actualizado       timestamptz not null default now(),
  procesada_en      timestamptz
);

comment on table pagos_intencion is 'PAGOS WEB · una fila por intento de pago, persistida ANTES de firmar (F2). Guarda el monto firmado para compararlo con el que informe Wompi, la foto del producto y los datos que el comprador escribio en la TIENDA (Wompi solo confirma el pago), y el utm_campaign / mg_vid de la visita. Estados: creada -> procesada | rechazada | requiere_revision. Nada se borra ni se edita a mano: cambia de estado y queda el libro pagos_eventos.';
comment on column pagos_intencion.monto_centavos is 'Monto EXACTO que se firmo (precio releido server-side * cantidad * 100). El webhook lo compara con amount_in_cents del evento; si no coincide NO crea pedido.';
comment on column pagos_intencion.estado is 'creada = se abrio el checkout (no prueba nada). procesada = pago aprobado y pedido creado (terminal). rechazada = DECLINED/VOIDED/ERROR (terminal). requiere_revision = pago aprobado que NO se pudo convertir en pedido (sin stock o monto que no coincide); sale como aviso rojo en el panel.';
comment on column pagos_intencion.mg_vid is 'Id aleatorio del visitante de la analitica propia (EM7). Es el enchufe que Metricas esperaba para medir el embudo real hasta la compra. Sin nombre ni correo.';

create index if not exists pagos_intencion_estado_idx on pagos_intencion (estado, creado desc);
create index if not exists pagos_intencion_transaccion_idx on pagos_intencion (transaccion_id) where transaccion_id is not null;
create index if not exists pagos_intencion_pedido_idx on pagos_intencion (pedido_id) where pedido_id is not null;

-- ------------------------------------------------------------
-- pagos_eventos · idempotencia por (transaccion_id, estado_wompi)
-- ------------------------------------------------------------
create table if not exists pagos_eventos (
  id             bigint generated always as identity primary key,
  transaccion_id text not null,
  estado_wompi   text not null,
  referencia     text,
  evento         text,
  checksum       text,
  cuerpo         jsonb,
  resultado      text not null
                   check (resultado in ('procesado','repetido','rechazado','sin_intencion',
                                        'sin_stock','monto_no_coincide','ignorado','ya_procesada')),
  recibido       timestamptz not null default now(),
  constraint pagos_eventos_unico unique (transaccion_id, estado_wompi)
);

comment on table pagos_eventos is 'PAGOS WEB · libro de avisos (webhooks) de Wompi. Wompi NO envia un id de evento unico y reintenta hasta 3 veces en 24 h si no recibe 200, por eso la idempotencia se construye con la llave unica (transaccion_id, estado_wompi): un reintento del mismo aviso choca y no reprocesa; un cambio legitimo de estado (PENDING -> APPROVED) si entra. Guarda el cuerpo completo y el resultado para auditar sin adivinar.';

alter table pagos_intencion enable row level security;
alter table pagos_eventos  enable row level security;

-- Lectura solo para quien atiende Ventas. Escritura: SOLO por las RPC
-- security definer (no hay policy de insert/update/delete a proposito).
drop policy if exists "pagos_intencion_select_ventas" on pagos_intencion;
create policy "pagos_intencion_select_ventas" on pagos_intencion
  for select to authenticated using (tiene_acceso_pagos());
drop policy if exists "pagos_eventos_select_ventas" on pagos_eventos;
create policy "pagos_eventos_select_ventas" on pagos_eventos
  for select to authenticated using (tiene_acceso_pagos());

grant select on pagos_intencion to authenticated;
grant select on pagos_eventos  to authenticated;
-- service_role: la Edge Function no lee estas tablas directo, usa las RPC.

-- ------------------------------------------------------------
-- CONTEXTO DE SERVIDOR · por que existe y por que es seguro
-- ------------------------------------------------------------
-- F2 NO reimplementa la creacion del pedido ni el candado de stock: reutiliza
-- crear_pedido, que es la unica puerta que serializa ventas simultaneas y
-- bloquea existencias. Pero crear_pedido exige tiene_acceso_ventas(), y el
-- servidor (service_role, la Edge Function del webhook) NO tiene perfil ni
-- auth.uid(): el guardia lo rechazaria.
--
-- Copiar crear_pedido aqui seria peor (dos implementaciones del candado de
-- stock que se desincronizan). Y detectar el rol desde dentro de una funcion
-- security definer NO es fiable: current_user devuelve el dueno de la funcion
-- y current_setting('role') devuelve 'none' (comprobado).
--
-- Solucion: una COMPUERTA DE CONTEXTO explicita y de alcance minimo.
--   · La abre SOLO pw_procesar_pago, que solo puede ejecutar service_role
--     (EXECUTE revocado a anon y authenticated).
--   · Es local a la transaccion (set_config con is_local = true): al terminar
--     desaparece sola.
--   · Se cierra a mano inmediatamente despues de crear el pedido.
--   · PREFIJO 'impulse.' A PROPOSITO: PostgREST solo rellena variables con
--     prefijo 'request.*' a partir de las cabeceras del cliente. Un navegador
--     NO puede inyectar una variable 'impulse.*'. Si se hubiera llamado
--     'request.pago_servidor', un cliente podria falsificarla con una cabecera.
--     Esa eleccion de nombre ES el candado.
-- ------------------------------------------------------------
create or replace function pw__contexto_servidor()
returns boolean language sql stable set search_path = public as $$
  select coalesce(current_setting('impulse.pago_servidor', true), '') = 'on';
$$;
comment on function pw__contexto_servidor() is 'PAGOS WEB · true solo dentro de la transaccion de pw_procesar_pago (que solo ejecuta service_role). Usa el prefijo impulse.* porque PostgREST solo puede rellenar variables request.* desde cabeceras del cliente: un navegador no puede falsificar esta. Local a la transaccion.';

-- Se re-emite el helper de Ventas para que acepte el contexto de servidor.
-- NO amplia el acceso de ninguna persona: la compuerta solo esta abierta
-- dentro de la transaccion del webhook de pagos.
create or replace function tiene_acceso_ventas()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('ventas')        -- clave del area
      or tiene_modulo('pedidos')       -- sub-area seguimiento de pedidos
      or tiene_modulo('clientes')      -- sub-area portafolio
      or tiene_modulo('portafolio')    -- alias de la sub-area portafolio
      or pw__contexto_servidor();      -- F2: el webhook de pagos crea el pedido web
$$;

comment on function tiene_acceso_ventas() is 'Acceso al Area de Ventas: true si el usuario tiene la clave del area (ventas), la de la sub-area de pedidos (pedidos) o la del portafolio (clientes / portafolio), o si es admin. Desde F2 tambien es true dentro de la transaccion de pw_procesar_pago (contexto de servidor, variable impulse.* no falsificable por el cliente), para que el webhook de Wompi pueda crear el pedido web reutilizando crear_pedido y su candado de stock.';

-- ------------------------------------------------------------
-- pw_registrar_intencion · la llama crear-intencion-pago ANTES de firmar
-- ------------------------------------------------------------
create or replace function pw_registrar_intencion(
  p_referencia      text,
  p_campana_id      uuid,
  p_slug            text,
  p_nombre          text,
  p_cantidad        integer,
  p_precio_unitario bigint,
  p_monto_centavos  bigint,
  p_entorno         text,
  p_comprador       jsonb default '{}'::jsonb,
  p_utm_campaign    text default null,
  p_mg_vid          text default null,
  p_moneda          text default 'COP'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product_id uuid;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    raise exception 'PW_REFERENCIA_INVALIDA';
  end if;
  if coalesce(p_cantidad, 0) <= 0 or coalesce(p_precio_unitario, 0) <= 0 or coalesce(p_monto_centavos, 0) <= 0 then
    raise exception 'PW_MONTO_INVALIDO';
  end if;
  if coalesce(p_entorno, '') not in ('sandbox','prod') then raise exception 'PW_ENTORNO_INVALIDO'; end if;

  -- El producto de Inventario se resuelve AQUI (la Edge Function no conoce
  -- product_id_ref: el catalogo publico no lo expone, y asi debe seguir).
  select cp.product_id_ref into v_product_id from campana_producto cp where cp.id = p_campana_id;

  insert into pagos_intencion (
    referencia, campana_id, product_id, slug, nombre, cantidad, precio_unitario,
    monto_centavos, moneda, entorno,
    comprador_nombre, comprador_correo, comprador_telefono, comprador_direccion,
    comprador_ciudad, comprador_departamento, comprador_pais,
    utm_campaign, mg_vid
  ) values (
    p_referencia, p_campana_id, v_product_id, nullif(p_slug, ''), nullif(p_nombre, ''),
    p_cantidad, p_precio_unitario, p_monto_centavos, coalesce(nullif(p_moneda, ''), 'COP'), p_entorno,
    nullif(btrim(p_comprador->>'nombre'), ''), nullif(btrim(p_comprador->>'correo'), ''),
    nullif(btrim(p_comprador->>'telefono'), ''), nullif(btrim(p_comprador->>'direccion'), ''),
    nullif(btrim(p_comprador->>'ciudad'), ''), nullif(btrim(p_comprador->>'departamento'), ''),
    nullif(btrim(p_comprador->>'pais'), ''),
    nullif(p_utm_campaign, ''), nullif(p_mg_vid, '')
  )
  on conflict (referencia) do nothing;

  return jsonb_build_object('referencia', p_referencia, 'product_id', v_product_id,
                            'ligado', v_product_id is not null);
end;
$$;

comment on function pw_registrar_intencion(text, uuid, text, text, integer, bigint, bigint, text, jsonb, text, text, text) is 'PAGOS WEB · persiste la intencion ANTES de firmar (F2). Resuelve el product_id de Inventario desde la campana (el catalogo publico NO expone product_id_ref y asi debe seguir). Idempotente por referencia. Solo service_role.';

-- ------------------------------------------------------------
-- pw_procesar_pago · el corazon de F2. UNA transaccion, idempotente.
-- La Edge Function ya verifico el checksum (el secreto de eventos vive alla).
-- ------------------------------------------------------------
create or replace function pw_procesar_pago(
  p_transaccion_id text,
  p_estado_wompi   text,
  p_referencia     text,
  p_monto_centavos bigint,
  p_moneda         text default null,
  p_evento         text default null,
  p_checksum       text default null,
  p_cuerpo         jsonb default null,
  p_metodo_pago    text default null,
  p_correo_pagador text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ins        bigint;
  v_i          pagos_intencion;
  v_resultado  text;
  v_pedido     jsonb;
  v_pedido_id  uuid;
  v_motivo     text;
  v_aprobado   boolean;
begin
  if coalesce(btrim(p_transaccion_id), '') = '' or coalesce(btrim(p_estado_wompi), '') = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  -- (1) IDEMPOTENCIA PRIMERO. Si esta pareja ya se vio, no se vuelve a procesar.
  insert into pagos_eventos (transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado)
  values (p_transaccion_id, upper(btrim(p_estado_wompi)), nullif(p_referencia, ''), p_evento, p_checksum, p_cuerpo, 'ignorado')
  on conflict (transaccion_id, estado_wompi) do nothing
  returning id into v_ins;

  if v_ins is null then
    return jsonb_build_object('resultado', 'repetido',
      'pedido_id', (select pedido_id from pagos_intencion where referencia = p_referencia));
  end if;

  v_aprobado := upper(btrim(p_estado_wompi)) = 'APPROVED';

  -- (2) Bloquear la intencion para serializar avisos simultaneos.
  select * into v_i from pagos_intencion where referencia = p_referencia for update;

  if not found then
    -- Pago sin intencion nuestra: NO se inventa un pedido. Queda el evento.
    update pagos_eventos set resultado = 'sin_intencion' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_intencion');
  end if;

  -- (3) Si ya se proceso, devolver el mismo pedido (nunca crear otro).
  if v_i.estado = 'procesada' then
    update pagos_eventos set resultado = 'ya_procesada' where id = v_ins;
    return jsonb_build_object('resultado', 'ya_procesada', 'pedido_id', v_i.pedido_id);
  end if;

  -- (4) Estado final que no es aprobado: se cierra sin crear nada.
  if not v_aprobado then
    update pagos_intencion
       set estado = case when upper(btrim(p_estado_wompi)) in ('DECLINED','VOIDED','ERROR')
                         then 'rechazada' else estado end,
           transaccion_id = p_transaccion_id, estado_wompi = upper(btrim(p_estado_wompi)),
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'rechazado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado', 'estado', upper(btrim(p_estado_wompi)));
  end if;

  -- (5) APROBADO · el monto debe coincidir con lo FIRMADO. Nunca se confia en
  --     el monto que llega: si difiere, no se crea pedido.
  if p_monto_centavos is null or p_monto_centavos <> v_i.monto_centavos then
    v_motivo := format('El monto informado (%s) no coincide con el firmado (%s).',
                       coalesce(p_monto_centavos::text, 'nulo'), v_i.monto_centavos);
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'monto_no_coincide' where id = v_ins;
    return jsonb_build_object('resultado', 'monto_no_coincide', 'motivo', v_motivo);
  end if;

  -- (6) APROBADO y monto correcto: crear el pedido web.
  --     El stock lo bloquea crear_pedido (candado firme ya existente, que
  --     serializa ventas simultaneas). F2 NO reimplementa esa logica.
  --     El precio NO se relee: quedo congelado al firmar; se respeta lo pagado.
  if v_i.product_id is null then
    v_motivo := 'La campana no tiene producto de Inventario ligado.';
    update pagos_intencion set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED', actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'sin_stock' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_stock', 'motivo', v_motivo);
  end if;

  begin
    -- Compuerta de contexto: se abre justo aqui y se cierra enseguida.
    perform set_config('impulse.pago_servidor', 'on', true);
    v_pedido := crear_pedido(
      p_nombre        => coalesce(v_i.comprador_nombre, 'Comprador web'),
      p_correo        => coalesce(v_i.comprador_correo, p_correo_pagador),
      p_telefono      => v_i.comprador_telefono,
      p_direccion     => v_i.comprador_direccion,
      p_ciudad        => v_i.comprador_ciudad,
      p_departamento  => v_i.comprador_departamento,
      p_pais          => v_i.comprador_pais,
      p_canal         => 'web',
      p_notas_pedido  => 'Pago web Wompi · referencia ' || v_i.referencia,
      p_items         => jsonb_build_array(jsonb_build_object(
                            'product_id', v_i.product_id,
                            'cantidad', v_i.cantidad,
                            'precio_unitario', v_i.precio_unitario))
    );
    -- crear_pedido devuelve jsonb {pedido_id, customer_id, total}
    v_pedido_id := (v_pedido->>'pedido_id')::uuid;
    perform set_config('impulse.pago_servidor', 'off', true);  -- cerrar enseguida
  exception when others then
    perform set_config('impulse.pago_servidor', 'off', true);  -- cerrar tambien al fallar
    -- Tipicamente stock insuficiente (la ultima unidad se vendio por otro lado).
    -- Decision del dueno: NO se crea el pedido; queda aviso rojo para resolver.
    v_motivo := sqlerrm;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'sin_stock' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_stock', 'motivo', v_motivo);
  end;

  -- (7) Enchufe de atribucion EXACTA: el pedido web se queda con el
  --     utm_campaign de la visita (asi Email marketing deja de aproximar).
  if v_i.utm_campaign is not null then
    update pedidos set utm_campaign = v_i.utm_campaign where id = v_pedido_id;
  end if;

  update pagos_intencion
     set estado = 'procesada', pedido_id = v_pedido_id,
         transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
         metodo_pago = coalesce(p_metodo_pago, metodo_pago),
         correo_pagador = coalesce(p_correo_pagador, correo_pagador),
         revision_motivo = null, procesada_en = now(), actualizado = now()
   where referencia = p_referencia;
  update pagos_eventos set resultado = 'procesado' where id = v_ins;

  return jsonb_build_object('resultado', 'procesado', 'pedido_id', v_pedido_id);
end;
$$;

comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is 'PAGOS WEB · corazon de F2: convierte un pago aprobado en pedido EXACTAMENTE UNA VEZ, en una sola transaccion. Orden: (1) registra el evento (idempotencia por transaccion_id+estado; un reintento devuelve repetido), (2) bloquea la intencion for update, (3) si ya estaba procesada devuelve el mismo pedido, (4) DECLINED/VOIDED/ERROR la cierran como rechazada, (5) compara el monto contra el FIRMADO, (6) crea el pedido canal=web reutilizando el candado de stock de crear_pedido y, si falla, deja requiere_revision con el motivo, (7) copia el utm_campaign al pedido para atribucion exacta. El precio no se relee: se respeta lo firmado. Solo service_role.';

-- ------------------------------------------------------------
-- Panel: el aviso rojo y su resolucion manual
-- ------------------------------------------------------------
create or replace function pw_revisiones()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_pagos() then raise exception 'PW_SIN_ACCESO'; end if;
  return jsonb_build_object(
    'pendientes', (select count(*) from pagos_intencion where estado = 'requiere_revision' and resuelta_en is null),
    'lista', (select coalesce(jsonb_agg(jsonb_build_object(
        'referencia', referencia, 'nombre', nombre, 'slug', slug,
        'cantidad', cantidad, 'monto_centavos', monto_centavos,
        'motivo', revision_motivo, 'transaccion_id', transaccion_id,
        'metodo_pago', metodo_pago, 'comprador', comprador_nombre,
        'correo', comprador_correo, 'telefono', comprador_telefono,
        'creado', creado, 'actualizado', actualizado) order by actualizado desc), '[]')
      from pagos_intencion where estado = 'requiere_revision' and resuelta_en is null),
    'resueltas_30d', (select count(*) from pagos_intencion
                       where resuelta_en is not null and resuelta_en >= now() - interval '30 days')
  );
end;
$$;
comment on function pw_revisiones() is 'PAGOS WEB · aviso rojo del panel: pagos APROBADOS que no se pudieron convertir en pedido (sin stock, monto que no coincide o campana sin producto ligado). Incluye los datos de contacto para resolver (reponer o devolver).';

create or replace function pw_resolver_revision(p_referencia text, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_pagos() then raise exception 'PW_SIN_ACCESO'; end if;
  if coalesce(btrim(p_nota), '') = '' then raise exception 'PW_NOTA_OBLIGATORIA'; end if;
  update pagos_intencion
     set resuelta_en = now(), resuelta_por = auth.uid(), resuelta_nota = btrim(p_nota), actualizado = now()
   where referencia = p_referencia and estado = 'requiere_revision' and resuelta_en is null;
  if not found then raise exception 'PW_REVISION_NO_ENCONTRADA'; end if;
  return jsonb_build_object('referencia', p_referencia, 'resuelta', true);
end;
$$;
comment on function pw_resolver_revision(text, text) is 'PAGOS WEB · marca una revision como atendida CON NOTA OBLIGATORIA (que se hizo: se repuso el stock, se devolvio el dinero...). No borra nada ni crea pedidos: deja constancia de quien y cuando.';

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
do $$
declare f text;
begin
  -- Solo la Edge Function (service_role) escribe pagos.
  foreach f in array array[
    'pw_registrar_intencion(text, uuid, text, text, integer, bigint, bigint, text, jsonb, text, text, text)',
    'pw_procesar_pago(text, text, text, bigint, text, text, jsonb, text, text)',
    'pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)'] loop
    begin
      execute format('revoke execute on function %s from public, anon, authenticated', f);
      execute format('grant execute on function %s to service_role', f);
    exception when undefined_function then null;
    end;
  end loop;
  -- El panel lee y resuelve.
  foreach f in array array['pw_revisiones()', 'pw_resolver_revision(text, text)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
