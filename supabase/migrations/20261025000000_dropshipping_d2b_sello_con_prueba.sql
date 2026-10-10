-- ============================================================================
-- MAGANDHI · Dropshipping D2b · sello «Elegido por MAGANDHI» con prueba
-- ----------------------------------------------------------------------------
-- Forward sobre 20261024000000 (D2a).
--
-- REGLA DE MARCA
--   Un producto solo puede llevar sello_elegido=true cuando su prueba de
--   curaduría MÁS RECIENTE tiene el veredicto entra_con_sello. La prueba es un
--   hecho append-only: una reevaluación nunca altera ni borra la anterior; se
--   registra como una fila nueva y pasa a ser la que gobierna el sello.
--
-- ALCANCE
--   - crea producto_pruebas para productos propios Y de proveedor;
--   - registra evidencia únicamente por cm_registrar_producto_prueba();
--   - protege el sello en cm_crear_campana, cm_editar_campana,
--     cm_publicar_campana y también por trigger ante DML privilegiado;
--   - conserva los candados D1/D2a: una prueba NO publica ni vende proveedor.
--
-- EVIDENCIA HISTÓRICA
--   No se inventa una prueba para campañas históricas ya selladas. Al aplicar
--   esta migración, esas campañas conservan su fila actual, pero su siguiente
--   guardado/publicación con sello exigirá registrar evidencia real desde el
--   editor. GRISI se registra con fecha/notas reales decididas por el dueño.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Libro append-only de pruebas de curaduría
-- ----------------------------------------------------------------------------
create table if not exists producto_pruebas (
  id             uuid primary key default gen_random_uuid(),
  product_id     uuid not null references productos(id) on delete restrict,
  probado_por    text not null check (length(btrim(probado_por)) between 1 and 160),
  probado_en     date not null,
  notas          text not null check (length(btrim(notas)) between 1 and 4000),
  veredicto      text not null check (veredicto in ('entra_con_sello', 'entra_sin_sello', 'no_entra')),
  registrado_en  timestamptz not null default now(),
  registrado_por uuid references auth.users(id) default auth.uid()
);

comment on table producto_pruebas is
  'D2b · libro append-only de pruebas de curaduría MAGANDHI. Una fila registra quién probó un producto, cuándo, notas y veredicto. La prueba más reciente por fecha de prueba y registro gobierna la posibilidad de usar sello_elegido. Aplica igual a productos propios y proveedor; no se expone a anon ni a la tienda.';
comment on column producto_pruebas.probado_por is
  'Persona o equipo que realizó la prueba real de curaduría; distinto del usuario que la registró en el panel.';
comment on column producto_pruebas.veredicto is
  'entra_con_sello = la prueba vigente permite Elegido por MAGANDHI; entra_sin_sello = puede venderse sin sello; no_entra = no debe llevar sello. Una nueva prueba reemplaza la decisión vigente sin borrar la historia.';

create index if not exists producto_pruebas_producto_fecha_idx
  on producto_pruebas (product_id, probado_en desc, registrado_en desc, id desc);

alter table producto_pruebas enable row level security;

drop policy if exists "producto_pruebas_select_marketing" on producto_pruebas;
create policy "producto_pruebas_select_marketing" on producto_pruebas
  for select
  to authenticated
  using (tiene_acceso_marketing());

-- Auto-expose está apagado: el panel necesita SELECT para su historial, pero
-- nunca INSERT/UPDATE/DELETE directos. La única escritura es la RPC de abajo.
grant select on table producto_pruebas to authenticated;

-- La ausencia de policy DML protege al cliente; este gatillo protege además
-- cualquier ruta privilegiada futura para que el libro siga siendo append-only.
create or replace function cm__prueba_inmutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'CM_PRUEBA_INMUTABLE: una prueba de curaduría no se edita ni se borra; registra una nueva prueba para dejar la reevaluación.';
end;
$$;

comment on function cm__prueba_inmutable() is
  'D2b · gatillo interno append-only de producto_pruebas. Una corrección se registra como nuevo hecho; nunca se reescribe evidencia previa.';

revoke all on function cm__prueba_inmutable() from public, anon, authenticated;
grant execute on function cm__prueba_inmutable() to service_role;

drop trigger if exists cm_prueba_inmutable on producto_pruebas;
create trigger cm_prueba_inmutable
before update or delete on producto_pruebas
for each row execute function cm__prueba_inmutable();

-- ----------------------------------------------------------------------------
-- (B) Puertas de registro y consulta interna de elegibilidad
-- ----------------------------------------------------------------------------
-- La última prueba por fecha real de prueba gobierna. Si dos hechos tienen la
-- misma fecha, gana el último registro; id solo desempata dos timestamps iguales.
create or replace function cm__producto_tiene_prueba_sello(
  p_product_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select pp.veredicto = 'entra_con_sello'
      from producto_pruebas pp
     where pp.product_id = p_product_id
     order by pp.probado_en desc, pp.registrado_en desc, pp.id desc
     limit 1
  ), false);
$$;

comment on function cm__producto_tiene_prueba_sello(uuid) is
  'D2b · helper interno: true solo si la prueba de curaduría vigente del producto tiene veredicto entra_con_sello. No es una puerta del panel.';

revoke all on function cm__producto_tiene_prueba_sello(uuid) from public, anon, authenticated;
grant execute on function cm__producto_tiene_prueba_sello(uuid) to service_role;

create or replace function cm_registrar_producto_prueba(
  p_product_id uuid,
  p_probado_por text,
  p_probado_en date,
  p_notas text,
  p_veredicto text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id        uuid;
  v_probador  text := btrim(coalesce(p_probado_por, ''));
  v_notas     text := btrim(coalesce(p_notas, ''));
  v_veredicto text := btrim(coalesce(p_veredicto, ''));
begin
  if not tiene_acceso_marketing() then
    raise exception 'CM_PRUEBA_SIN_ACCESO: se requiere el módulo Marketing.';
  end if;
  if p_product_id is null or not exists (select 1 from productos where id = p_product_id) then
    raise exception 'CM_PRUEBA_PRODUCTO_NO_ENCONTRADO: el producto ligado no existe.';
  end if;
  if length(v_probador) = 0 or length(v_probador) > 160 then
    raise exception 'CM_PRUEBA_PROBADOR_INVALIDO: indica quién realizó la prueba (máximo 160 caracteres).';
  end if;
  if p_probado_en is null then
    raise exception 'CM_PRUEBA_FECHA_OBLIGATORIA: indica la fecha real de la prueba.';
  end if;
  if p_probado_en > (now() at time zone 'America/Bogota')::date then
    raise exception 'CM_PRUEBA_FECHA_INVALIDA: la fecha de la prueba no puede estar en el futuro.';
  end if;
  if length(v_notas) = 0 or length(v_notas) > 4000 then
    raise exception 'CM_PRUEBA_NOTAS_INVALIDAS: registra notas de 1 a 4000 caracteres.';
  end if;
  if v_veredicto not in ('entra_con_sello', 'entra_sin_sello', 'no_entra') then
    raise exception 'CM_PRUEBA_VEREDICTO_INVALIDO: elige entra_con_sello, entra_sin_sello o no_entra.';
  end if;

  insert into producto_pruebas (
    product_id, probado_por, probado_en, notas, veredicto, registrado_por
  ) values (
    p_product_id, v_probador, p_probado_en, v_notas, v_veredicto, auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function cm_registrar_producto_prueba(uuid, text, date, text, text) is
  'D2b · registra una prueba de curaduría append-only para un producto propio o proveedor. Solo Marketing. La prueba más reciente determina si puede usar sello_elegido; nunca edita ni borra una anterior.';

revoke all on function cm_registrar_producto_prueba(uuid, text, date, text, text) from public, anon;
grant execute on function cm_registrar_producto_prueba(uuid, text, date, text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (C) Defensa en profundidad sobre la tabla de campañas
-- ----------------------------------------------------------------------------
-- Las RPC de abajo dan mensajes claros al operador. Este gatillo replica la
-- regla para escrituras privilegiadas o futuras: ocultar el botón nunca es el
-- control de seguridad. D2a inserta borradores con sello=false, sin cambio.
create or replace function cm__campana_sello_exige_prueba()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.sello_elegido, false) then
    if new.product_id_ref is null then
      raise exception 'CM_SELLO_SIN_PRODUCTO: liga primero un producto antes de usar el sello Elegido por MAGANDHI.';
    end if;
    if not cm__producto_tiene_prueba_sello(new.product_id_ref) then
      raise exception 'CM_SELLO_SIN_PRUEBA: registra una prueba vigente con veredicto «Entra con sello» antes de usar Elegido por MAGANDHI.';
    end if;
  end if;
  return new;
end;
$$;

comment on function cm__campana_sello_exige_prueba() is
  'D2b · gatillo interno que impide sello_elegido sin evidencia vigente, incluso por DML privilegiado. No modifica la prohibición D1 de publicar proveedor.';

revoke all on function cm__campana_sello_exige_prueba() from public, anon, authenticated;
grant execute on function cm__campana_sello_exige_prueba() to service_role;

drop trigger if exists cm_campana_sello_exige_prueba on campana_producto;
create trigger cm_campana_sello_exige_prueba
before insert or update of sello_elegido, product_id_ref on campana_producto
for each row execute function cm__campana_sello_exige_prueba();

-- ----------------------------------------------------------------------------
-- (D) RPC de creación y edición: misma firma, nueva validación autoritativa
-- ----------------------------------------------------------------------------
create or replace function cm_crear_campana(
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_imagen_banner_path      text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta            bigint default null,
  p_hook_largo              text default null,
  p_por_que_magandhi        text default null,
  p_sobre_este_producto     text default null,
  p_ficha_tecnica           jsonb default '[]'::jsonb,
  p_imagenes                jsonb default '[]'::jsonb,
  p_sello_elegido           boolean default false,
  p_estrella                boolean default false,
  p_stock_disponible        integer default 0,
  p_aviso_urgencia_activo   boolean default false,
  p_aviso_urgencia_cantidad integer default null,
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,
  p_slug                    text default null,
  p_tope_escaparate         integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_tag  text;
  v_slug text;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;
  if p_precio_venta is not null and p_precio_venta < 0 then
    raise exception 'El precio de venta no puede ser negativo.';
  end if;
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
  end if;
  if coalesce(p_sello_elegido, false) then
    if p_product_id_ref is null then
      raise exception 'CM_SELLO_SIN_PRODUCTO: liga primero un producto antes de usar el sello Elegido por MAGANDHI.';
    end if;
    if not cm__producto_tiene_prueba_sello(p_product_id_ref) then
      raise exception 'CM_SELLO_SIN_PRUEBA: registra una prueba vigente con veredicto «Entra con sello» antes de usar Elegido por MAGANDHI.';
    end if;
  end if;

  v_slug := cm_normalizar_slug(p_slug);

  insert into campana_producto (
    nombre, categoria_codigo, detalle_presentacion, imagen_banner_path,
    caracteristica_adicional, precio_venta, hook_largo, por_que_magandhi,
    sobre_este_producto, ficha_tecnica, imagenes, sello_elegido, estrella,
    stock_disponible, aviso_urgencia_activo, aviso_urgencia_cantidad, product_id_ref, slug,
    tope_escaparate
  ) values (
    p_nombre, p_categoria_codigo, p_detalle_presentacion, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo, p_por_que_magandhi,
    p_sobre_este_producto, coalesce(p_ficha_tecnica, '[]'::jsonb), coalesce(p_imagenes, '[]'::jsonb),
    coalesce(p_sello_elegido, false), coalesce(p_estrella, false),
    coalesce(p_stock_disponible, 0), coalesce(p_aviso_urgencia_activo, false),
    p_aviso_urgencia_cantidad, p_product_id_ref, v_slug,
    p_tope_escaparate
  )
  returning id into v_id;

  if p_etiquetas is not null then
    foreach v_tag in array p_etiquetas loop
      if v_tag is not null and length(trim(v_tag)) > 0 then
        insert into campana_producto_etiqueta (campana_producto_id, etiqueta_codigo)
        values (v_id, v_tag)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  return jsonb_build_object('id', v_id);
end;
$$;

comment on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is
  'CAMPANAS · alta de ficha comercial. D2b: sello_elegido exige producto ligado y prueba vigente entra_con_sello, además del trigger de defensa. Mantiene precio, aviso, tope, etiquetas, slug y el contrato existente de D2a.';

create or replace function cm_editar_campana(
  p_id                      uuid,
  p_nombre                  text,
  p_categoria_codigo        text default null,
  p_detalle_presentacion    text default null,
  p_imagen_banner_path      text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta            bigint default null,
  p_hook_largo              text default null,
  p_por_que_magandhi        text default null,
  p_sobre_este_producto     text default null,
  p_ficha_tecnica           jsonb default '[]'::jsonb,
  p_imagenes                jsonb default '[]'::jsonb,
  p_sello_elegido           boolean default false,
  p_estrella                boolean default false,
  p_stock_disponible        integer default 0,
  p_aviso_urgencia_activo   boolean default false,
  p_aviso_urgencia_cantidad integer default null,
  p_etiquetas               text[] default '{}',
  p_product_id_ref          uuid default null,
  p_slug                    text default null,
  p_tope_escaparate         integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existe uuid;
  v_tag    text;
  v_slug   text;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) = 0 then
    raise exception 'El nombre del producto es obligatorio.';
  end if;
  if p_precio_venta is not null and p_precio_venta < 0 then
    raise exception 'El precio de venta no puede ser negativo.';
  end if;
  if coalesce(p_aviso_urgencia_activo, false) then
    if p_aviso_urgencia_cantidad is null or p_aviso_urgencia_cantidad <= 0 then
      raise exception 'Con el aviso de urgencia activo debe indicar una cantidad mayor que cero (numero para "Solo X disponibles").';
    end if;
  end if;
  if p_tope_escaparate is not null and p_tope_escaparate < 0 then
    raise exception 'El tope de escaparate no puede ser negativo.';
  end if;

  select id into v_existe from campana_producto where id = p_id;
  if v_existe is null then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if coalesce(p_sello_elegido, false) then
    if p_product_id_ref is null then
      raise exception 'CM_SELLO_SIN_PRODUCTO: liga primero un producto antes de usar el sello Elegido por MAGANDHI.';
    end if;
    if not cm__producto_tiene_prueba_sello(p_product_id_ref) then
      raise exception 'CM_SELLO_SIN_PRUEBA: registra una prueba vigente con veredicto «Entra con sello» antes de usar Elegido por MAGANDHI.';
    end if;
  end if;

  v_slug := cm_normalizar_slug(p_slug);

  update campana_producto
     set nombre                   = p_nombre,
         categoria_codigo         = p_categoria_codigo,
         detalle_presentacion     = p_detalle_presentacion,
         imagen_banner_path       = p_imagen_banner_path,
         caracteristica_adicional = p_caracteristica_adicional,
         precio_venta             = p_precio_venta,
         hook_largo               = p_hook_largo,
         por_que_magandhi         = p_por_que_magandhi,
         sobre_este_producto      = p_sobre_este_producto,
         ficha_tecnica            = coalesce(p_ficha_tecnica, '[]'::jsonb),
         imagenes                 = coalesce(p_imagenes, '[]'::jsonb),
         sello_elegido            = coalesce(p_sello_elegido, false),
         estrella                 = coalesce(p_estrella, false),
         stock_disponible         = coalesce(p_stock_disponible, 0),
         aviso_urgencia_activo    = coalesce(p_aviso_urgencia_activo, false),
         aviso_urgencia_cantidad  = p_aviso_urgencia_cantidad,
         product_id_ref           = p_product_id_ref,
         slug                     = v_slug,
         tope_escaparate          = p_tope_escaparate,
         actualizado              = now()
   where id = p_id;

  delete from campana_producto_etiqueta where campana_producto_id = p_id;
  if p_etiquetas is not null then
    foreach v_tag in array p_etiquetas loop
      if v_tag is not null and length(trim(v_tag)) > 0 then
        insert into campana_producto_etiqueta (campana_producto_id, etiqueta_codigo)
        values (p_id, v_tag)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  return p_id;
end;
$$;

comment on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) is
  'CAMPANAS · edición de ficha comercial. D2b: conservar/activar sello_elegido exige que el producto de destino tenga prueba vigente entra_con_sello. No cambia el vínculo fijo de proveedor de D2a ni la regla de un solo distintivo.';

-- Las firmas no cambian, pero se reafirman sus ACL nominales para evitar el
-- incidente histórico de 42501 al redefinir funciones de Campañas.
revoke execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) from public, anon;
grant execute on function cm_crear_campana(text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) to authenticated, service_role;
revoke execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) from public, anon;
grant execute on function cm_editar_campana(uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) Publicar: vuelve a validar el sello antes de exponer la campaña
-- ----------------------------------------------------------------------------
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
  v_sello_elegido   boolean;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select cp.product_id_ref, cp.precio_venta, p.activo, p.origen, cp.sello_elegido
    into v_producto_id, v_precio, v_producto_activo, v_origen, v_sello_elegido
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
    -- D2b NO abre D2c: proveedor sigue bloqueado antes de revisar el sello.
    if coalesce(v_origen, 'propio') = 'proveedor' then
      raise exception 'DS_PUBLICACION_PENDIENTE: este producto proveedor espera D2 (stock vivo y checkout seguro) antes de publicarse.';
    end if;
    if v_precio is null or v_precio <= 0 then
      raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
    end if;
    if coalesce(v_sello_elegido, false)
       and not cm__producto_tiene_prueba_sello(v_producto_id) then
      raise exception 'CM_SELLO_SIN_PRUEBA: registra una prueba vigente con veredicto «Entra con sello» antes de publicar Elegido por MAGANDHI.';
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
  'CAMPANAS · publica/despublica sin borrar. D2b exige prueba vigente entra_con_sello cuando la campaña usa sello; D1 conserva proveedor bloqueado hasta D2c. Despublicar siempre queda permitido.';

revoke execute on function cm_publicar_campana(uuid, boolean) from public, anon;
grant execute on function cm_publicar_campana(uuid, boolean) to authenticated, service_role;

commit;
