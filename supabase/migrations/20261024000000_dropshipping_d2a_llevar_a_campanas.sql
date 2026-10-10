-- ============================================================================
-- MAGANDHI · Dropshipping D2a · «Llevar a Campañas»
-- ----------------------------------------------------------------------------
-- Corte: 10 de octubre de 2026. Migración FORWARD sobre 20261023000000 (D1).
--
-- ESTE TRAMO SI HACE
--   1. ds_llevar_a_campanas(): en UNA transacción crea el producto interno
--      (origen='proveedor'), su ficha producto_proveedor y un BORRADOR de
--      campaña ligado, y marca el candidato como llevado. Si algo falla, no
--      queda nada a medias. Es idempotente por (Dropi producto + variante):
--      repetir el clic devuelve lo ya creado, nunca duplica.
--   2. Las fotos llegan YA convertidas a grande + '-sm' en el bucket propio
--      `campanas` (las convierte el panel con el mismo código del editor de
--      Campañas). La RPC solo acepta keys que EXISTEN en ese bucket: nunca una
--      URL remota de Dropi.
--   3. Candado del vínculo: una campaña de proveedor queda ligada a su ficha y
--      un producto proveedor solo entra a Campañas por esta importación. Vive
--      en un gatillo de la tabla, así que cubre el editor, la API y cualquier
--      RPC futura.
--   4. Un candidato ya llevado a Campañas no se descarta ni se restaura desde
--      la bandeja (su historia apunta a productos reales).
--
-- ESTE TRAMO NO HACE (a propósito)
--   - no publica: cm_publicar_campana y catalogo_publico siguen bloqueando
--     proveedor hasta D2c (stock vivo, fallo cerrado y pedido proveedor);
--   - no consulta stock en el checkout ni cambia crear_pedido/anular_pedido;
--   - no pone costo en productos.costo_unitario: ese campo alimenta el asiento
--     de inventario propio (143505). El costo del proveedor queda en
--     producto_proveedor.costo_reportado hasta que el contador defina sus
--     cuentas (D2c). Así, si algo se vendiera por error, el asiento quedaría
--     pendiente en vez de acreditar una bodega que nunca se cargó;
--   - no llama orders/ ni comparte datos de clientes con Dropi.
--
-- STOCK AL IMPORTAR: se guarda la lectura, pero con stock_vence_en = leído.
-- Es decir, nace VENCIDA: una lectura de curaduría no es una promesa de venta.
-- D2c la refrescará desde el servidor antes de permitir publicar.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Trazabilidad mínima de la importación
-- ----------------------------------------------------------------------------
alter table producto_proveedor
  add column if not exists candidato_id uuid references dropshipping_candidatos(id) on delete restrict;
alter table producto_proveedor
  add column if not exists variacion_nombre text;

alter table producto_proveedor
  drop constraint if exists producto_proveedor_variacion_nombre_largo;
alter table producto_proveedor
  add constraint producto_proveedor_variacion_nombre_largo
  check (variacion_nombre is null or length(variacion_nombre) <= 160);

comment on column producto_proveedor.candidato_id is
  'D2a · candidato de la bandeja desde el que se llevó a Campañas. Un candidato puede originar varias fichas: una por variante.';
comment on column producto_proveedor.variacion_nombre is
  'D2a · nombre legible de la variante Dropi (p. ej. «Color: Negro»), solo para el panel interno. Nunca sale a la tienda.';

create index if not exists producto_proveedor_candidato_idx
  on producto_proveedor (candidato_id);

-- ----------------------------------------------------------------------------
-- (B) Candado del vínculo campaña ↔ producto proveedor
-- ----------------------------------------------------------------------------
-- cm_crear_campana y cm_editar_campana asignan product_id_ref sin mirar el
-- origen. Sin este gatillo, el editor podría re-ligar una campaña proveedor a
-- un producto propio (y viceversa) y la ficha de proveedor quedaría huérfana.
-- La importación abre la compuerta impulse.ds_importando solo dentro de su
-- propia transacción (set_config local), igual que impulse.pago_servidor en F2.
create or replace function ds__campana_vinculo_proveedor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_origen_nuevo text;
  v_origen_viejo text;
begin
  if new.product_id_ref is not null then
    select origen into v_origen_nuevo from productos where id = new.product_id_ref;
  end if;

  if tg_op = 'UPDATE' and old.product_id_ref is distinct from new.product_id_ref then
    if old.product_id_ref is not null then
      select origen into v_origen_viejo from productos where id = old.product_id_ref;
    end if;
    if v_origen_viejo = 'proveedor' then
      raise exception 'DS_VINCULO_PROVEEDOR_FIJO: esta campaña de proveedor queda ligada a su ficha. Para otra variante, llévala desde Dropshipping.';
    end if;
    if v_origen_nuevo = 'proveedor' then
      raise exception 'DS_VINCULO_SOLO_IMPORTACION: un producto de proveedor solo entra a Campañas desde Dropshipping («Llevar a Campañas»).';
    end if;
  end if;

  if tg_op = 'INSERT' and v_origen_nuevo = 'proveedor'
     and coalesce(current_setting('impulse.ds_importando', true), '') <> 'on' then
    raise exception 'DS_VINCULO_SOLO_IMPORTACION: un producto de proveedor solo entra a Campañas desde Dropshipping («Llevar a Campañas»).';
  end if;

  return new;
end;
$$;

comment on function ds__campana_vinculo_proveedor() is
  'D2a Dropshipping · gatillo interno: una campaña proveedor no cambia de producto y un producto proveedor solo se liga mediante ds_llevar_a_campanas. Cubre editor, API y RPC futuras.';

revoke all on function ds__campana_vinculo_proveedor() from public, anon, authenticated;
grant execute on function ds__campana_vinculo_proveedor() to service_role;

drop trigger if exists ds_campana_vinculo_proveedor on campana_producto;
create trigger ds_campana_vinculo_proveedor
before insert or update of product_id_ref on campana_producto
for each row execute function ds__campana_vinculo_proveedor();

-- ----------------------------------------------------------------------------
-- (C) La importación atómica
-- ----------------------------------------------------------------------------
-- La llama el panel Dropshipping (sesión autenticada) DESPUÉS de releer la
-- ficha en Dropi por id (dropi-sonda) y de subir las fotos elegidas. Exige los
-- dos módulos porque crea a la vez ficha de proveedor y campaña.
create or replace function ds_llevar_a_campanas(
  p_candidato_id         uuid,
  p_variacion_externa_id text default '',
  p_variacion_nombre     text default null,
  p_nombre               text default null,
  p_costo_reportado      bigint default null,
  p_stock_reportado      integer default null,
  p_stock_leido_en       timestamptz default null,
  p_imagenes             jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cand        dropshipping_candidatos%rowtype;
  v_variacion   text := btrim(coalesce(p_variacion_externa_id, ''));
  v_var_nombre  text := nullif(btrim(coalesce(p_variacion_nombre, '')), '');
  v_nombre      text;
  v_imagenes    jsonb := '[]'::jsonb;
  v_key         text;
  v_prefijo     text;
  v_sku         text;
  v_producto_id uuid;
  v_campana_id  uuid;
  v_leido       timestamptz;
begin
  if not (tiene_acceso_dropshipping() and tiene_acceso_marketing()) then
    raise exception 'DS_SIN_ACCESO: llevar a Campañas exige los módulos Dropshipping y Marketing.';
  end if;

  select * into v_cand from dropshipping_candidatos where id = p_candidato_id for update;
  if not found then
    raise exception 'DS_CANDIDATO_NO_ENCONTRADO: el candidato no existe.';
  end if;
  if v_cand.estado = 'descartado' then
    raise exception 'DS_CANDIDATO_DESCARTADO: restaura el candidato antes de llevarlo a Campañas.';
  end if;
  if v_variacion !~ '^[A-Za-z0-9_-]{0,80}$' then
    raise exception 'DS_CANDIDATO_VARIACION_INVALIDA: la variante Dropi no es válida.';
  end if;

  -- Idempotencia: la misma variante del mismo producto Dropi ya es un producto
  -- MAGANDHI. Se devuelve lo existente; el panel limpia las fotos que acaba de
  -- subir para este segundo intento.
  select pp.product_id, cp.id
    into v_producto_id, v_campana_id
    from producto_proveedor pp
    left join campana_producto cp on cp.product_id_ref = pp.product_id
   where pp.plataforma = v_cand.plataforma
     and pp.producto_externo_id = v_cand.producto_externo_id
     and pp.variacion_externa_id = v_variacion
   order by cp.creado nulls last
   limit 1;
  if v_producto_id is not null then
    update dropshipping_candidatos
       set estado = 'llevado_a_campanas', actualizado = now(), actualizado_por = auth.uid()
     where id = v_cand.id and estado <> 'llevado_a_campanas';
    return jsonb_build_object('ya_existia', true, 'producto_id', v_producto_id, 'campana_id', v_campana_id);
  end if;

  if p_costo_reportado is not null and p_costo_reportado < 0 then
    raise exception 'DS_COSTO_INVALIDO: el costo reportado no puede ser negativo.';
  end if;
  if p_stock_reportado is not null and p_stock_reportado < 0 then
    raise exception 'DS_STOCK_INVALIDO: el stock reportado no puede ser negativo.';
  end if;
  if v_var_nombre is not null and length(v_var_nombre) > 160 then
    raise exception 'DS_CANDIDATO_VARIACION_INVALIDA: el nombre de la variante supera 160 caracteres.';
  end if;

  -- Fotos: solo keys GRANDES ya subidas al bucket propio, en el formato que usa
  -- el editor (raíz del bucket, sin carpetas). Nunca una URL ni una '-sm'.
  if p_imagenes is null then p_imagenes := '[]'::jsonb; end if;
  if jsonb_typeof(p_imagenes) <> 'array' then
    raise exception 'DS_IMAGEN_INVALIDA: las imágenes deben ser una lista.';
  end if;
  if jsonb_array_length(p_imagenes) > 12 then
    raise exception 'DS_IMAGEN_INVALIDA: máximo 12 imágenes.';
  end if;
  for v_key in select value from jsonb_array_elements_text(p_imagenes) loop
    if v_key !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,100}\.(webp|jpg|jpeg|png)$'
       or v_key ~ '-sm\.[a-z]+$' then
      raise exception 'DS_IMAGEN_INVALIDA: «%» no es una imagen propia de Campañas.', left(v_key, 60);
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'campanas' and o.name = v_key) then
      raise exception 'DS_IMAGEN_NO_SUBIDA: la imagen «%» no está en el bucket campanas.', left(v_key, 60);
    end if;
    if not (v_imagenes @> jsonb_build_array(v_key)) then
      v_imagenes := v_imagenes || jsonb_build_array(v_key);
    end if;
  end loop;

  v_nombre := left(coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), v_cand.nombre_externo), 160);

  -- SKU propio y reconocible a simple vista: MAG-DROP-0042. Misma secuencia que
  -- Inventario, así nunca choca con un SKU propio.
  select prefijo into v_prefijo from inventario_config where id = 1;
  v_prefijo := coalesce(nullif(trim(v_prefijo), ''), 'MAG');
  v_sku := v_prefijo || '-DROP-' || lpad(nextval('inventario_sku_seq')::text, 4, '0');

  insert into productos (sku, nombre, categoria, unidad_medida, costo_unitario, origen, activo)
  values (v_sku, v_nombre, v_cand.categoria_externa, 'unidad', null, 'proveedor', true)
  returning id into v_producto_id;

  -- La lectura de stock nace VENCIDA (vence = leído): sirve para curar, no para
  -- vender. D2c la refresca desde el servidor antes de publicar.
  v_leido := case when p_stock_reportado is null then null else coalesce(p_stock_leido_en, now()) end;
  insert into producto_proveedor (
    product_id, plataforma, producto_externo_id, variacion_externa_id,
    proveedor_externo_id, costo_reportado, stock_reportado, stock_leido_en, stock_vence_en,
    candidato_id, variacion_nombre, actualizado
  ) values (
    v_producto_id, v_cand.plataforma, v_cand.producto_externo_id, v_variacion,
    v_cand.proveedor_externo_id, coalesce(p_costo_reportado, v_cand.precio_proveedor),
    p_stock_reportado, v_leido, v_leido,
    v_cand.id, v_var_nombre, now()
  );

  -- Borrador: nunca publicado, sin sello, sin aviso, sin precio. El precio
  -- comercial se pone a mano en el editor.
  perform set_config('impulse.ds_importando', 'on', true);
  insert into campana_producto (
    nombre, product_id_ref, imagenes, ficha_tecnica,
    publicado, activo, sello_elegido, estrella, aviso_urgencia_activo, actualizado
  ) values (
    v_nombre, v_producto_id, v_imagenes, '[]'::jsonb,
    false, true, false, false, false, now()
  )
  returning id into v_campana_id;
  perform set_config('impulse.ds_importando', 'off', true);

  update dropshipping_candidatos
     set estado = 'llevado_a_campanas', actualizado = now(), actualizado_por = auth.uid()
   where id = v_cand.id;

  return jsonb_build_object(
    'ya_existia', false,
    'producto_id', v_producto_id,
    'sku', v_sku,
    'campana_id', v_campana_id
  );
end;
$$;

comment on function ds_llevar_a_campanas(uuid, text, text, text, bigint, integer, timestamptz, jsonb) is
  'D2a Dropshipping · lleva un candidato (una variante) a Campañas en una sola transacción: producto origen=proveedor + producto_proveedor + borrador de campaña ligado + candidato llevado. Idempotente por producto/variante Dropi. Solo acepta imágenes ya subidas al bucket campanas. Exige Dropshipping y Marketing. NO publica, NO toca Inventario, NO pone costo de inventario y NO llama orders/.';

revoke all on function ds_llevar_a_campanas(uuid, text, text, text, bigint, integer, timestamptz, jsonb) from public, anon;
grant execute on function ds_llevar_a_campanas(uuid, text, text, text, bigint, integer, timestamptz, jsonb) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) La bandeja ya no mueve un candidato llevado a Campañas
-- ----------------------------------------------------------------------------
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
  v_actual text;
begin
  if not tiene_acceso_dropshipping() then
    raise exception 'DS_SIN_ACCESO: se requiere el modulo dropshipping.';
  end if;
  if v_estado not in ('bandeja', 'descartado') then
    raise exception 'DS_ESTADO_INVALIDO: la bandeja solo permite bandeja o descartado.';
  end if;

  select estado into v_actual from dropshipping_candidatos where id = p_id for update;
  if not found then
    raise exception 'DS_CANDIDATO_NO_ENCONTRADO: el candidato no existe.';
  end if;
  if v_actual = 'llevado_a_campanas' then
    raise exception 'DS_CANDIDATO_YA_LLEVADO: este candidato ya tiene productos en Campañas; se gestionan desde el editor.';
  end if;

  update dropshipping_candidatos
     set estado = v_estado,
         actualizado = now(),
         actualizado_por = auth.uid()
   where id = p_id;

  return p_id;
end;
$$;

comment on function ds_actualizar_estado_candidato(uuid, text) is
  'Dropshipping · mueve un candidato entre bandeja y descartado. D2a: un candidato llevado a Campañas queda sellado (su historia apunta a productos reales).';

revoke all on function ds_actualizar_estado_candidato(uuid, text) from public, anon;
grant execute on function ds_actualizar_estado_candidato(uuid, text) to authenticated, service_role;

commit;
