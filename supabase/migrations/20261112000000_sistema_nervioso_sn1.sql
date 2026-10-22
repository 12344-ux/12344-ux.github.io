-- ============================================================================
-- MAGANDHI · SISTEMA NERVIOSO SN1
-- Backend común para búsqueda, recomendación, composición y assets.
-- ----------------------------------------------------------------------------
-- FORWARD posterior a 20261111000000_campanas_categorias_oficiales.sql.
-- No modifica migraciones históricas ni requiere extensiones nuevas.
--
-- INVARIANTE ABSOLUTA
--   La frontera pública siempre empieza en catalogo_publico y cada superficie
--   vuelve a exigir: campaña publicada + activa + no placeholder, agotado=false,
--   max_comprable>0 y ventana SN vigente. Una relación, prioridad, evento o
--   asset jamás puede reintroducir una campaña que falle esa frontera. Esta
--   invariante gobierna superficies SQL/tienda: retirar una fila impide que se
--   enumere o devuelva, pero no revoca un objeto de bucket público cuya URL ya
--   hubiera sido conocida.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

select pg_advisory_xact_lock(hashtextextended('magandhi-sistema-nervioso-sn1-v1', 0));

do $baseline$
declare
  v_columnas text[];
begin
  if to_regclass('public.campana_producto') is null
     or to_regclass('public.campana_producto_categoria') is null
     or to_regclass('public.campana_producto_etiqueta') is null
     or to_regclass('public.campana_etiqueta') is null
     or to_regclass('public.catalogo_publico') is null
     or to_regclass('public.pedidos') is null
     or to_regclass('public.pedido_items') is null
     or to_regclass('public.carritos') is null
     or to_regclass('public.carrito_items') is null
     or to_regclass('public.opiniones') is null
     or to_regclass('public.producto_rating_publico') is null
     or to_regclass('public.cuentas_cliente') is null
     or to_regclass('public.perfiles') is null
     or to_regclass('public.tienda_eventos') is null
     or to_regclass('public.tienda_eventos_limite') is null
     or to_regclass('public.em_config') is null
     or to_regprocedure('public.tiene_acceso_marketing()') is null
     or to_regprocedure('public.mt_registrar_eventos(text,text,jsonb,text)') is null then
    raise exception using errcode = 'P0001', message = 'SN1_REQUIERE_BASELINE_20261111000000_COMPLETO';
  end if;

  select array_agg(c.column_name::text order by c.ordinal_position)
    into v_columnas
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = 'catalogo_publico';

  if v_columnas is distinct from array[
    'id', 'nombre', 'slug', 'categoria_codigo', 'categoria_nombre',
    'color_fuerte', 'color_claro', 'color_sombra',
    'detalle_presentacion', 'imagen_banner_path', 'caracteristica_adicional',
    'precio_venta', 'hook_largo', 'por_que_magandhi', 'sobre_este_producto',
    'ficha_tecnica', 'imagenes', 'sello_elegido', 'estrella', 'agotado',
    'aviso_urgencia_activo', 'aviso_urgencia_cantidad', 'orden',
    'max_comprable', 'categoria_codigos', 'categorias'
  ]::text[] then
    raise exception using errcode = 'P0001', message = 'SN1_CATALOGO_PUBLICO_CONTRATO_INVALIDO';
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pedido_items'
       and column_name = 'campana_id'
  ) then
    raise exception using errcode = 'P0001', message = 'SN1_REQUIERE_PEDIDO_ITEMS_CAMPANA_ID';
  end if;

  if to_regclass('public.sn_config') is not null
     or to_regclass('public.sn_config_bitacora') is not null
     or to_regclass('public.sn_producto_config') is not null
     or to_regclass('public.sn_producto_relacion') is not null
     or to_regclass('public.sn_asset') is not null
     or to_regclass('public.sn_layout') is not null
     or to_regclass('public.sn_catalogo_seguro_v1') is not null
     or to_regclass('public.sn_assets_publicos_v1') is not null then
    raise exception using errcode = 'P0001', message = 'SN1_REQUIERE_AUSENCIA_LIMPIA';
  end if;
end;
$baseline$;

-- La forward instala un trigger sobre campañas y amplía telemetría. Los locks
-- bloquean escrituras incompatibles, no las lecturas públicas.
lock table public.campana_producto in share row exclusive mode;
lock table public.tienda_eventos in share row exclusive mode;

-- ----------------------------------------------------------------------------
-- (A) Helpers cerrados: normalización, privacidad y listas canónicas.
-- ----------------------------------------------------------------------------
create function public.sn__normalizar_texto(p_texto text)
returns text
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $fn$
declare
  v_texto text;
begin
  if p_texto is null then
    return null;
  end if;

  -- NFKD real y retiro de todos los bloques de marcas combinantes usados por
  -- PostgreSQL 15. No depende de unaccent.
  v_texto := lower(normalize(p_texto, NFKD));
  v_texto := regexp_replace(
    v_texto,
    U&'[\0300-\036F\1AB0-\1AFF\1DC0-\1DFF\20D0-\20FF\FE20-\FE2F]',
    '',
    'g'
  );
  v_texto := replace(v_texto, 'æ', 'ae');
  v_texto := replace(v_texto, 'œ', 'oe');
  v_texto := replace(v_texto, 'ß', 'ss');
  v_texto := translate(v_texto, 'łđðþøı', 'lddtoi');
  v_texto := regexp_replace(v_texto, '[^a-z0-9]+', ' ', 'g');
  v_texto := regexp_replace(btrim(v_texto), '[[:space:]]+', ' ', 'g');
  return nullif(v_texto, '');
end;
$fn$;

create function public.sn__contiene_pii(p_texto text)
returns boolean
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $fn$
declare
  v_crudo text := lower(coalesce(p_texto, ''));
  v_digitos text;
begin
  if p_texto is null then
    return false;
  end if;
  v_digitos := regexp_replace(v_crudo, '[^0-9]', '', 'g');
  return
    v_crudo ~ '[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}'
    or v_crudo ~ '(^|[^a-z0-9])@[a-z0-9._-]{2,}'
    or v_crudo ~* '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    or length(v_digitos) >= 7;
end;
$fn$;

-- El alt se publica junto con el asset: además de PII, nunca admite señales
-- comerciales que puedan filtrar precio, inventario u origen de suministro.
create function public.sn__alt_seguro(p_alt text)
returns boolean
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $fn$
declare
  v_crudo text := lower(coalesce(p_alt, ''));
  v_normalizado text;
begin
  if p_alt is null
     or p_alt is distinct from btrim(p_alt)
     or length(p_alt) not between 3 and 240
     or p_alt ~ E'[\n\r]'
     or public.sn__contiene_pii(p_alt) then
    return false;
  end if;

  v_normalizado := coalesce(public.sn__normalizar_texto(p_alt), '');
  return not (
    v_normalizado = ''
    or v_crudo ~ '[$€£¥¢₹₽₿]'
    or v_normalizado ~ '(^| )(precio|precios|costo|costos|coste|costes|stock|existencia|existencias|inventario|proveedor|proveedores|proveedora|proveedoras|supplier|suppliers|price|prices)( |$)'
    or v_normalizado ~ '(^| )(cop|usd|eur|gbp|cad|aud|mxn|ars|clp|pen|brl|dolar|dolares|peso|pesos|euro|euros)( |$)'
    or v_crudo ~ '(^|[^0-9])[0-9]{1,3}([.,][0-9]{3})+([.,][0-9]{2})?([^0-9]|$)'
    or v_crudo ~ '(^|[^0-9])[0-9]+[.,][0-9]{2}([^0-9]|$)'
  );
end;
$fn$;

create function public.sn__intenciones_validas(p_intenciones text[])
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $fn$
  select coalesce(
    cardinality(p_intenciones) between 0 and 12
    and not exists (
      select 1
        from unnest(p_intenciones) as i(valor)
       where i.valor is null
          or length(i.valor) not between 2 and 80
          or i.valor is distinct from lower(btrim(i.valor))
          or i.valor is distinct from regexp_replace(i.valor, '[[:space:]]+', ' ', 'g')
          or i.valor ~ E'[\n\r]'
          or public.sn__contiene_pii(i.valor)
          or public.sn__normalizar_texto(i.valor) is null
    )
    and cardinality(p_intenciones) = (
      select count(distinct public.sn__normalizar_texto(i.valor))::integer
        from unnest(p_intenciones) as i(valor)
    ),
    false
  );
$fn$;

create function public.sn__roles_validos(p_roles text[])
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $fn$
  select coalesce(
    cardinality(p_roles) between 1 and 5
    and array_position(p_roles, null) is null
    and p_roles <@ array['cuadrado','vertical','horizontal','panoramico','recorte']::text[]
    and cardinality(p_roles) = (
      select count(distinct x)::integer from unnest(p_roles) as u(x)
    ),
    false
  );
$fn$;

create function public.sn__asset_dimensiones_validas(
  p_rol text,
  p_ancho integer,
  p_alto integer
)
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $fn$
  select coalesce(
    p_ancho between 600 and 8192
    and p_alto between 600 and 8192
    and p_ancho::bigint * p_alto::bigint <= 40000000
    and case p_rol
      when 'cuadrado' then
        p_ancho >= 1600 and p_alto >= 1600
        and abs(p_ancho::numeric / p_alto - 1::numeric) <= 0.03
      when 'vertical' then
        p_ancho >= 1600 and p_alto >= 2000
        and abs(p_ancho::numeric / p_alto - (4::numeric / 5))
              <= (4::numeric / 5) * 0.03
      when 'horizontal' then
        p_ancho >= 1920 and p_alto >= 1080
        and abs(p_ancho::numeric / p_alto - (16::numeric / 9))
              <= (16::numeric / 9) * 0.03
      when 'panoramico' then
        p_ancho >= 2000 and p_alto >= 1000
        and abs(p_ancho::numeric / p_alto - 2::numeric) <= 2::numeric * 0.03
      when 'recorte' then
        p_ancho >= 2000 and p_alto >= 2000
        and abs(p_ancho::numeric / p_alto - 1::numeric) <= 0.03
      else false
    end,
    false
  );
$fn$;

-- La versión es identidad interna de base. El objeto maestro usa exactamente
-- una key inmutable de la consola; la variante -sm nunca se registra aquí.
create function public.sn__asset_path_valido(
  p_campana_id uuid,
  p_rol text,
  p_storage_path text
)
returns boolean
language sql
immutable
security definer
set search_path = pg_catalog
as $fn$
  select coalesce(
    p_campana_id is not null
    and p_rol in ('cuadrado','vertical','horizontal','panoramico','recorte')
    and p_storage_path = btrim(p_storage_path)
    and length(p_storage_path) between 62 and 500
    and p_storage_path like 'sistema-nervioso/' || p_campana_id::text || '/%'
    and p_storage_path !~ '//'
    and p_storage_path !~ '(^|/)\.\.?(/|$)'
    and p_storage_path ~ (
      '^sistema-nervioso/' || p_campana_id::text || '/' || p_rol
      || '-[0-9]{17}-[a-z0-9]+\.(jpg|jpeg|png|webp|avif)$'
    )
    and p_storage_path !~ '-sm\.(jpg|jpeg|png|webp|avif)$',
    false
  );
$fn$;

revoke all on function public.sn__normalizar_texto(text)
  from public, anon, authenticated, service_role;
revoke all on function public.sn__contiene_pii(text)
  from public, anon, authenticated, service_role;
revoke all on function public.sn__alt_seguro(text)
  from public, anon, authenticated, service_role;
revoke all on function public.sn__intenciones_validas(text[])
  from public, anon, authenticated, service_role;
revoke all on function public.sn__roles_validos(text[])
  from public, anon, authenticated, service_role;
revoke all on function public.sn__asset_dimensiones_validas(text, integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.sn__asset_path_valido(uuid, text, text)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (B) Gate global, configuración editorial, relaciones, assets y layouts.
-- ----------------------------------------------------------------------------
create table public.sn_config (
  id                       smallint primary key default 1,
  activo                   boolean not null default true,
  personalizacion_cuenta   boolean not null default true,
  modelo_version           text not null default 'sn1-reglas-1',
  exploracion_pct          integer not null default 12,
  actualizado_en           timestamptz not null default statement_timestamp(),
  actualizado_por          uuid,
  actualizado_razon        text not null,
  actualizado_rol          text not null,
  constraint sn_config_singleton_chk check (id = 1),
  constraint sn_config_modelo_chk check (
    modelo_version = btrim(modelo_version)
    and modelo_version ~ '^[a-z0-9][a-z0-9._-]{0,59}$'
  ),
  constraint sn_config_exploracion_chk check (exploracion_pct between 0 and 100),
  constraint sn_config_razon_chk check (
    actualizado_razon = btrim(actualizado_razon)
    and length(actualizado_razon) between 3 and 500
  ),
  constraint sn_config_rol_chk check (
    actualizado_rol = btrim(actualizado_rol)
    and length(actualizado_rol) between 1 and 120
  )
);

create table public.sn_config_bitacora (
  id                                bigint generated always as identity primary key,
  registrado_en                     timestamptz not null default statement_timestamp(),
  actor_uid                         uuid,
  actor_rol                         text not null,
  razon                             text not null,
  antes_activo                      boolean,
  despues_activo                    boolean not null,
  antes_personalizacion_cuenta      boolean,
  despues_personalizacion_cuenta    boolean not null,
  antes_modelo_version              text,
  despues_modelo_version            text not null,
  antes_exploracion_pct             integer,
  despues_exploracion_pct           integer not null,
  constraint sn_config_bitacora_actor_rol_chk check (
    actor_rol = btrim(actor_rol) and length(actor_rol) between 1 and 120
  ),
  constraint sn_config_bitacora_razon_chk check (
    razon = btrim(razon) and length(razon) between 3 and 500
  )
);

create table public.sn_producto_config (
  campana_producto_id uuid primary key
    references public.campana_producto(id) on delete restrict,
  prioridad           integer not null default 0,
  intenciones         text[] not null default '{}'::text[],
  disponible_desde    timestamptz,
  disponible_hasta    timestamptz,
  creado_en            timestamptz not null default statement_timestamp(),
  creado_por           uuid,
  actualizado_en       timestamptz not null default statement_timestamp(),
  actualizado_por      uuid,
  constraint sn_producto_config_prioridad_chk check (prioridad between -20 and 20),
  constraint sn_producto_config_intenciones_chk check (
    public.sn__intenciones_validas(intenciones)
  ),
  constraint sn_producto_config_ventana_chk check (
    disponible_desde is null
    or disponible_hasta is null
    or disponible_hasta > disponible_desde
  )
);

create table public.sn_producto_relacion (
  id                         uuid primary key default gen_random_uuid(),
  campana_origen_id          uuid not null
    references public.campana_producto(id) on delete restrict,
  campana_destino_id         uuid not null
    references public.campana_producto(id) on delete restrict,
  tipo                       text not null,
  peso                       integer not null,
  activo                     boolean not null default true,
  creado_en                  timestamptz not null default statement_timestamp(),
  creado_por                 uuid,
  retirado_en                timestamptz,
  retirado_por               uuid,
  retirado_razon             text,
  constraint sn_producto_relacion_sin_auto_chk check (
    campana_origen_id <> campana_destino_id
  ),
  constraint sn_producto_relacion_tipo_chk check (
    tipo in ('complementa','sustituye','continua','rutina','descubrimiento','excluir')
  ),
  constraint sn_producto_relacion_peso_chk check (peso between 1 and 100),
  constraint sn_producto_relacion_baja_chk check (
    (activo and retirado_en is null and retirado_por is null and retirado_razon is null)
    or
    (not activo and retirado_en is not null and retirado_razon is not null
      and retirado_razon = btrim(retirado_razon)
      and length(retirado_razon) between 3 and 120)
  )
);

create unique index sn_producto_relacion_activa_unica_idx
  on public.sn_producto_relacion (campana_origen_id, campana_destino_id, tipo)
  where activo;
create index sn_producto_relacion_origen_idx
  on public.sn_producto_relacion (campana_origen_id, activo, tipo);
create index sn_producto_relacion_destino_idx
  on public.sn_producto_relacion (campana_destino_id, activo);

create table public.sn_asset (
  id                         uuid primary key default gen_random_uuid(),
  campana_producto_id        uuid not null
    references public.campana_producto(id) on delete restrict,
  rol                        text not null,
  storage_path               text not null unique,
  mime                       text not null,
  ancho                      integer not null,
  alto                       integer not null,
  foco_x                     numeric(5,4) not null default 0.5,
  foco_y                     numeric(5,4) not null default 0.5,
  alt                        text not null,
  version                    integer not null,
  activo                     boolean not null default true,
  creado_en                  timestamptz not null default statement_timestamp(),
  creado_por                 uuid,
  retirado_en                timestamptz,
  retirado_por               uuid,
  retirado_razon             text,
  constraint sn_asset_rol_chk check (
    rol in ('cuadrado','vertical','horizontal','panoramico','recorte')
  ),
  constraint sn_asset_mime_chk check (
    mime in ('image/jpeg','image/png','image/webp','image/avif')
  ),
  constraint sn_asset_version_chk check (version between 1 and 1000000),
  constraint sn_asset_dimensiones_chk check (
    public.sn__asset_dimensiones_validas(rol, ancho, alto)
  ),
  constraint sn_asset_foco_chk check (
    foco_x between 0 and 1 and foco_y between 0 and 1
  ),
  constraint sn_asset_alt_chk check (
    public.sn__alt_seguro(alt)
  ),
  constraint sn_asset_path_chk check (
    public.sn__asset_path_valido(campana_producto_id, rol, storage_path)
  ),
  constraint sn_asset_extension_mime_chk check (
    (mime = 'image/jpeg' and storage_path ~ '\.(jpg|jpeg)$')
    or (mime = 'image/png' and storage_path ~ '\.png$')
    or (mime = 'image/webp' and storage_path ~ '\.webp$')
    or (mime = 'image/avif' and storage_path ~ '\.avif$')
  ),
  constraint sn_asset_baja_chk check (
    (activo and retirado_en is null and retirado_por is null and retirado_razon is null)
    or
    (not activo and retirado_en is not null and retirado_razon is not null
      and retirado_razon = btrim(retirado_razon)
      and length(retirado_razon) between 3 and 120)
  ),
  constraint sn_asset_version_unica unique (campana_producto_id, rol, version)
);

create unique index sn_asset_variante_activa_unica_idx
  on public.sn_asset (campana_producto_id, rol)
  where activo;
create index sn_asset_campana_historia_idx
  on public.sn_asset (campana_producto_id, rol, version desc);

create table public.sn_layout (
  id                  uuid primary key default gen_random_uuid(),
  codigo              text not null,
  version             integer not null,
  superficie          text not null,
  orden               integer not null,
  tipo                text not null,
  titulo              text not null,
  subtitulo           text,
  peso                integer not null,
  roles_requeridos    text[] not null,
  activo              boolean not null default true,
  creado_en           timestamptz not null default statement_timestamp(),
  creado_por          uuid,
  constraint sn_layout_codigo_chk check (
    codigo ~ '^[a-z0-9][a-z0-9_-]{2,79}$'
  ),
  constraint sn_layout_version_chk check (version between 1 and 1000000),
  constraint sn_layout_superficie_chk check (
    superficie in (
      'home_principal','home_descubrimiento','categoria',
      'producto_final','carrito','busqueda'
    )
  ),
  constraint sn_layout_orden_chk check (orden between 1 and 3),
  constraint sn_layout_tipo_chk check (
    tipo in (
      'mosaico','carril_derecha','carril_izquierda',
      'destacado_horizontal','duo_vertical','cuadricula'
    )
  ),
  constraint sn_layout_titulo_chk check (
    titulo = btrim(titulo)
    and length(titulo) between 2 and 80
    and titulo in (
      'Elegidos para ti', 'Una selección para descubrir',
      'También puede gustarte', 'Más por descubrir',
      'Descubre algo nuevo', 'Dos buenas ideas', 'Sigue explorando',
      'Destacados de la categoría', 'Más opciones', 'También explora',
      'Completa tu elección', 'Puede ir bien contigo', 'Otra idea',
      'Antes de terminar', 'También podrías llevar', 'Últimos descubrimientos',
      'Resultados destacados', 'Más resultados', 'También descubre'
    )
    and (
      titulo <> 'Elegidos para ti'
      or (superficie = 'home_principal' and orden = 1)
    )
  ),
  constraint sn_layout_subtitulo_chk check (
    subtitulo is null
    or (subtitulo = btrim(subtitulo) and length(subtitulo) between 2 and 160)
  ),
  constraint sn_layout_peso_chk check (peso between 1 and 100),
  constraint sn_layout_roles_chk check (
    public.sn__roles_validos(roles_requeridos)
  ),
  constraint sn_layout_codigo_version_unica unique (codigo, version),
  constraint sn_layout_superficie_version_orden_unica unique (superficie, version, orden)
);

create unique index sn_layout_activo_por_slot_idx
  on public.sn_layout (superficie, orden)
  where activo;

insert into public.sn_config (
  id, activo, personalizacion_cuenta, modelo_version, exploracion_pct,
  actualizado_por, actualizado_razon, actualizado_rol
) values (
  1, true, true, 'sn1-reglas-1', 12,
  auth.uid(), 'instalacion_inicial_decision_dueno', 'sistema'
);

insert into public.sn_config_bitacora (
  actor_uid, actor_rol, razon,
  antes_activo, despues_activo,
  antes_personalizacion_cuenta, despues_personalizacion_cuenta,
  antes_modelo_version, despues_modelo_version,
  antes_exploracion_pct, despues_exploracion_pct
)
select auth.uid(), 'sistema', 'instalacion_inicial_decision_dueno',
       null, c.activo, null, c.personalizacion_cuenta,
       null, c.modelo_version, null, c.exploracion_pct
  from public.sn_config c
 where c.id = 1;

-- Tres módulos versionados por superficie. La versión queda en datos y cada
-- slot activo es único; un cambio futuro crea nueva versión y retira la previa.
insert into public.sn_layout (
  codigo, version, superficie, orden, tipo, titulo, subtitulo,
  peso, roles_requeridos, creado_por
) values
  ('home_principal_01',       1, 'home_principal',       1, 'mosaico',               'Elegidos para ti',       'Una selección clara para empezar.',                 100, array['cuadrado','vertical','horizontal'], auth.uid()),
  ('home_principal_02',       1, 'home_principal',       2, 'carril_derecha',        'También puede gustarte', 'Alternativas útiles sin perder variedad.',             80, array['vertical','cuadrado'],              auth.uid()),
  ('home_principal_03',       1, 'home_principal',       3, 'cuadricula',            'Más por descubrir',      'Novedades y hallazgos del catálogo.',                  60, array['cuadrado','recorte'],                auth.uid()),
  ('home_descubrimiento_01',  1, 'home_descubrimiento',  1, 'carril_izquierda',      'Descubre algo nuevo',    'Productos distintos para explorar.',                  100, array['vertical','cuadrado'],              auth.uid()),
  ('home_descubrimiento_02',  1, 'home_descubrimiento',  2, 'duo_vertical',          'Dos buenas ideas',       'Opciones que funcionan bien juntas.',                  80, array['vertical','recorte'],                auth.uid()),
  ('home_descubrimiento_03',  1, 'home_descubrimiento',  3, 'cuadricula',            'Sigue explorando',       'Una mezcla diversa del catálogo.',                     60, array['cuadrado','recorte'],                auth.uid()),
  ('categoria_01',            1, 'categoria',            1, 'destacado_horizontal',  'Destacados de la categoría','Una entrada rápida a lo más relevante.',             100, array['horizontal','panoramico'],          auth.uid()),
  ('categoria_02',            1, 'categoria',            2, 'cuadricula',            'Más opciones',           'Compara alternativas de esta selección.',              80, array['cuadrado','recorte'],                auth.uid()),
  ('categoria_03',            1, 'categoria',            3, 'carril_derecha',        'También explora',        'Ideas cercanas para ampliar la búsqueda.',              60, array['vertical','cuadrado'],               auth.uid()),
  ('producto_final_01',       1, 'producto_final',       1, 'carril_derecha',        'Completa tu elección',   'Productos relacionados con lo que estás viendo.',      100, array['vertical','cuadrado'],              auth.uid()),
  ('producto_final_02',       1, 'producto_final',       2, 'duo_vertical',          'Puede ir bien contigo',  'Complementos y alternativas relevantes.',               80, array['vertical','recorte'],                auth.uid()),
  ('producto_final_03',       1, 'producto_final',       3, 'destacado_horizontal',  'Otra idea',              'Un hallazgo para seguir descubriendo.',                  60, array['horizontal','panoramico'],           auth.uid()),
  ('carrito_01',              1, 'carrito',              1, 'carril_izquierda',      'Antes de terminar',      'Complementos útiles para tu selección.',                100, array['cuadrado','vertical'],              auth.uid()),
  ('carrito_02',              1, 'carrito',              2, 'duo_vertical',          'También podrías llevar', 'Opciones relacionadas sin repetir tu carrito.',          80, array['vertical','recorte'],                auth.uid()),
  ('carrito_03',              1, 'carrito',              3, 'cuadricula',            'Últimos descubrimientos','Más alternativas disponibles ahora.',                    60, array['cuadrado','recorte'],                auth.uid()),
  ('busqueda_01',             1, 'busqueda',             1, 'destacado_horizontal',  'Resultados destacados', 'Primero, las coincidencias más claras.',                100, array['horizontal','cuadrado'],            auth.uid()),
  ('busqueda_02',             1, 'busqueda',             2, 'cuadricula',            'Más resultados',         'Opciones relacionadas con tu búsqueda.',                80, array['cuadrado','recorte'],                auth.uid()),
  ('busqueda_03',             1, 'busqueda',             3, 'carril_derecha',        'También descubre',       'Una selección diversa para continuar.',                  60, array['vertical','cuadrado'],               auth.uid());

comment on table public.sn_config is
  'SN1 · singleton privado. activo es el único gate de emergencia del motor; no existe gate por producto. Nace activo=true por decisión del dueño.';
comment on table public.sn_config_bitacora is
  'SN1 · historial append-only del gate, personalización y exploración; sin consultas, perfiles ni datos de cliente.';
comment on table public.sn_producto_config is
  'SN1 · configuración editorial opcional por campaña. Admite 0..12 intenciones libres, canónicas, sin PII y únicas por texto normalizado; ausencia equivale a prioridad 0, intenciones vacías y ventana abierta.';
comment on table public.sn_producto_relacion is
  'SN1 · relación dirigida y versionada por baja lógica. Reemplazar relaciones retira las activas e inserta nuevas filas; nunca borra historia.';
comment on table public.sn_asset is
  'SN1 · assets multiformato privados e inmutables. La versión es interna de base y no forma parte de la key; solo se registra el maestro, nunca -sm. Retiro lógico y una sola variante activa por campaña y rol.';
comment on table public.sn_layout is
  'SN1 · recetas de composición versionadas por superficie, con tipo, peso, títulos de allowlist y roles fotográficos requeridos.';

-- Auditoría obligatoria del único gate global.
create function public.sn__auditar_config()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_actor_rol text;
begin
  if old.id <> 1 or new.id <> 1 then
    raise exception using errcode = 'P0001', message = 'SN_CONFIG_SINGLETON';
  end if;

  select p.rol into v_actor_rol
    from public.perfiles p
   where p.id = auth.uid();
  v_actor_rol := coalesce(v_actor_rol, 'sistema');

  new.actualizado_en := statement_timestamp();
  new.actualizado_por := auth.uid();
  new.actualizado_rol := v_actor_rol;

  insert into public.sn_config_bitacora (
    actor_uid, actor_rol, razon,
    antes_activo, despues_activo,
    antes_personalizacion_cuenta, despues_personalizacion_cuenta,
    antes_modelo_version, despues_modelo_version,
    antes_exploracion_pct, despues_exploracion_pct
  ) values (
    auth.uid(), v_actor_rol, new.actualizado_razon,
    old.activo, new.activo,
    old.personalizacion_cuenta, new.personalizacion_cuenta,
    old.modelo_version, new.modelo_version,
    old.exploracion_pct, new.exploracion_pct
  );
  return new;
end;
$fn$;

create trigger trg_sn_config_auditoria
  before update on public.sn_config
  for each row execute function public.sn__auditar_config();

-- Una publicación entra automáticamente en SN con defaults. Despublicar o dar
-- de baja no elimina la configuración ni crea un interruptor por producto.
create function public.sn__asegurar_config_publicada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
begin
  if new.publicado then
    insert into public.sn_producto_config (
      campana_producto_id, prioridad, intenciones,
      creado_por, actualizado_por
    ) values (
      new.id, 0, '{}'::text[], auth.uid(), auth.uid()
    )
    on conflict (campana_producto_id) do nothing;
  end if;
  return new;
end;
$fn$;

create trigger trg_sn_config_al_publicar
  after insert or update of publicado on public.campana_producto
  for each row
  when (new.publicado)
  execute function public.sn__asegurar_config_publicada();

insert into public.sn_producto_config (
  campana_producto_id, prioridad, intenciones, creado_por, actualizado_por
)
select cp.id, 0, '{}'::text[], auth.uid(), auth.uid()
  from public.campana_producto cp
 where cp.publicado
on conflict (campana_producto_id) do nothing;

-- Aunque la escritura pública está cerrada, este trigger protege la historia
-- frente a una operación privilegiada accidental.
create function public.sn__proteger_asset_inmutable()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
begin
  if new.id is distinct from old.id
     or new.campana_producto_id is distinct from old.campana_producto_id
     or new.rol is distinct from old.rol
     or new.storage_path is distinct from old.storage_path
     or new.mime is distinct from old.mime
     or new.ancho is distinct from old.ancho
     or new.alto is distinct from old.alto
     or new.foco_x is distinct from old.foco_x
     or new.foco_y is distinct from old.foco_y
     or new.alt is distinct from old.alt
     or new.version is distinct from old.version
     or new.creado_en is distinct from old.creado_en
     or new.creado_por is distinct from old.creado_por then
    raise exception using errcode = 'P0001', message = 'SN_ASSET_INMUTABLE';
  end if;
  if not old.activo and new.activo then
    raise exception using errcode = 'P0001', message = 'SN_ASSET_NO_REACTIVABLE';
  end if;
  return new;
end;
$fn$;

create trigger trg_sn_asset_inmutable
  before update on public.sn_asset
  for each row execute function public.sn__proteger_asset_inmutable();

revoke all on function public.sn__auditar_config()
  from public, anon, authenticated, service_role;
revoke all on function public.sn__asegurar_config_publicada()
  from public, anon, authenticated, service_role;
revoke all on function public.sn__proteger_asset_inmutable()
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (C) RLS: tablas privadas; lectura nominal de Marketing; cero DML directo.
-- ----------------------------------------------------------------------------
alter table public.sn_config enable row level security;
alter table public.sn_config_bitacora enable row level security;
alter table public.sn_producto_config enable row level security;
alter table public.sn_producto_relacion enable row level security;
alter table public.sn_asset enable row level security;
alter table public.sn_layout enable row level security;

revoke all on table public.sn_config
  from public, anon, authenticated, service_role;
revoke all on table public.sn_config_bitacora
  from public, anon, authenticated, service_role;
revoke all on table public.sn_producto_config
  from public, anon, authenticated, service_role;
revoke all on table public.sn_producto_relacion
  from public, anon, authenticated, service_role;
revoke all on table public.sn_asset
  from public, anon, authenticated, service_role;
revoke all on table public.sn_layout
  from public, anon, authenticated, service_role;
revoke all on sequence public.sn_config_bitacora_id_seq
  from public, anon, authenticated, service_role;

grant select on table public.sn_config,
  public.sn_config_bitacora,
  public.sn_producto_config,
  public.sn_producto_relacion,
  public.sn_asset,
  public.sn_layout
  to authenticated;

create policy sn_config_select_marketing on public.sn_config
  for select to authenticated using (public.tiene_acceso_marketing());
create policy sn_config_bitacora_select_marketing on public.sn_config_bitacora
  for select to authenticated using (public.tiene_acceso_marketing());
create policy sn_producto_config_select_marketing on public.sn_producto_config
  for select to authenticated using (public.tiene_acceso_marketing());
create policy sn_producto_relacion_select_marketing on public.sn_producto_relacion
  for select to authenticated using (public.tiene_acceso_marketing());
create policy sn_asset_select_marketing on public.sn_asset
  for select to authenticated using (public.tiene_acceso_marketing());
create policy sn_layout_select_marketing on public.sn_layout
  for select to authenticated using (public.tiene_acceso_marketing());

-- ----------------------------------------------------------------------------
-- (D) Catálogo de respaldo seguro. No depende del gate del algoritmo porque su
-- propósito es mantener la tienda operativa durante una caída o apagado de SN;
-- sí conserva todos los filtros duros, incluida la ventana editorial.
-- ----------------------------------------------------------------------------
create view public.sn_catalogo_seguro_v1
with (security_barrier = true)
as
select catalogo.*
from public.catalogo_publico catalogo
join public.campana_producto cp
  on cp.id = catalogo.id
 and cp.publicado
 and cp.activo
 and not cp.es_placeholder
left join public.sn_producto_config pc
  on pc.campana_producto_id = catalogo.id
where catalogo.agotado = false
  and catalogo.max_comprable > 0
  and (pc.disponible_desde is null
       or pc.disponible_desde at time zone 'America/Bogota'
          <= statement_timestamp() at time zone 'America/Bogota')
  and (pc.disponible_hasta is null
       or pc.disponible_hasta at time zone 'America/Bogota'
          > statement_timestamp() at time zone 'America/Bogota');

comment on view public.sn_catalogo_seguro_v1 is
  'SN1 · respaldo público de catálogo para fallos/apagado del ranker. Conserva publicación, actividad, no-placeholder, max_comprable>0 y ventana editorial; no personaliza ni expone campos adicionales.';

revoke all on table public.sn_catalogo_seguro_v1
  from public, anon, authenticated, service_role;
grant select on table public.sn_catalogo_seguro_v1
  to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D.2) Única superficie pública de assets. La vista no confía solo en el asset:
-- vuelve a cruzar catalogo_publico y los candados físicos de campaña.
-- ----------------------------------------------------------------------------
create view public.sn_assets_publicos_v1
with (security_barrier = true)
as
select
  a.id as asset_id,
  a.campana_producto_id as campana_id,
  a.rol,
  a.storage_path as path,
  a.mime,
  a.ancho,
  a.alto,
  a.foco_x,
  a.foco_y,
  a.alt,
  a.version
from public.sn_asset a
join public.sn_config global_cfg
  on global_cfg.id = 1
 and global_cfg.activo
join public.catalogo_publico catalogo
  on catalogo.id = a.campana_producto_id
 and catalogo.agotado = false
 and catalogo.max_comprable > 0
join public.campana_producto cp
  on cp.id = catalogo.id
 and cp.publicado
 and cp.activo
 and not cp.es_placeholder
left join public.sn_producto_config pc
  on pc.campana_producto_id = catalogo.id
where a.activo
  and (pc.disponible_desde is null
       or pc.disponible_desde at time zone 'America/Bogota'
          <= statement_timestamp() at time zone 'America/Bogota')
  and (pc.disponible_hasta is null
       or pc.disponible_hasta at time zone 'America/Bogota'
          > statement_timestamp() at time zone 'America/Bogota');

comment on view public.sn_assets_publicos_v1 is
  'SN1 · allowlist pública de assets activos con alt validado como metadata segura. Solo campañas presentes ahora mismo en catalogo_publico, publicadas, activas, no placeholder, disponibles por ventana Bogotá, no agotadas y con max_comprable>0. No expone auditoría ni datos internos; retirar evita enumeración/retorno, no revoca una URL ya conocida del bucket público.';

revoke all on table public.sn_assets_publicos_v1
  from public, anon, authenticated, service_role;
grant select on table public.sn_assets_publicos_v1
  to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) RPC internas de Marketing. Toda mutación es SECURITY DEFINER.
-- ----------------------------------------------------------------------------
create function public.sn_campana_detalle_v1(p_campana_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_nombre text;
  v_publicado boolean;
  v_activo boolean;
  v_es_placeholder boolean;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'SN_SIN_ACCESO';
  end if;
  if p_campana_id is null then
    raise exception using errcode = '22023', message = 'SN_CAMPANA_INVALIDA';
  end if;

  select cp.nombre, cp.publicado, cp.activo, cp.es_placeholder
    into v_nombre, v_publicado, v_activo, v_es_placeholder
    from public.campana_producto cp
   where cp.id = p_campana_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'SN_CAMPANA_NO_EXISTE';
  end if;

  return jsonb_build_object(
    'ok', true,
    'campana_id', p_campana_id,
    'nombre', v_nombre,
    'campana', jsonb_build_object(
      'id', p_campana_id,
      'nombre', v_nombre,
      'publicado', v_publicado,
      'activo', v_activo,
      'es_placeholder', v_es_placeholder
    ),
    'config', coalesce(
      (
        select jsonb_build_object(
          'predeterminada', false,
          'prioridad', pc.prioridad,
          'intenciones', pc.intenciones,
          'disponible_desde', pc.disponible_desde,
          'disponible_hasta', pc.disponible_hasta,
          'actualizado_en', pc.actualizado_en
        )
          from public.sn_producto_config pc
         where pc.campana_producto_id = p_campana_id
      ),
      jsonb_build_object(
        'predeterminada', true,
        'prioridad', 0,
        'intenciones', '[]'::jsonb,
        'disponible_desde', null,
        'disponible_hasta', null,
        'actualizado_en', null
      )
    ),
    'assets', jsonb_build_object(
      'activos', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', a.id, 'rol', a.rol, 'path', a.storage_path,
            'mime', a.mime, 'ancho', a.ancho, 'alto', a.alto,
            'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt,
            'version', a.version, 'creado_en', a.creado_en
          ) order by a.rol, a.version desc
        ), '[]'::jsonb)
          from public.sn_asset a
         where a.campana_producto_id = p_campana_id and a.activo
      ),
      'historicos', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', a.id, 'rol', a.rol, 'path', a.storage_path,
            'mime', a.mime, 'ancho', a.ancho, 'alto', a.alto,
            'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt,
            'version', a.version, 'creado_en', a.creado_en,
            'retirado_en', a.retirado_en, 'retirado_razon', a.retirado_razon
          ) order by a.rol, a.version desc
        ), '[]'::jsonb)
          from public.sn_asset a
         where a.campana_producto_id = p_campana_id and not a.activo
      )
    ),
    'relaciones', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'destino_id', r.campana_destino_id,
          'destino_nombre', destino.nombre,
          'tipo', r.tipo,
          'peso', r.peso,
          'activo', r.activo,
          'creado_en', r.creado_en,
          'retirado_en', r.retirado_en,
          'retirado_razon', r.retirado_razon
        ) order by r.activo desc, r.creado_en desc, r.id
      ), '[]'::jsonb)
        from public.sn_producto_relacion r
        join public.campana_producto destino on destino.id = r.campana_destino_id
       where r.campana_origen_id = p_campana_id
    )
  );
end;
$fn$;

create function public.sn_guardar_campana_v1(
  p_campana_id uuid,
  p_prioridad integer,
  p_intenciones text[],
  p_disponible_desde timestamptz,
  p_disponible_hasta timestamptz,
  p_relaciones jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_intenciones text[] := coalesce(p_intenciones, '{}'::text[]);
  v_relaciones jsonb := coalesce(p_relaciones, '[]'::jsonb);
  v_rel jsonb;
  v_destino uuid;
  v_tipo text;
  v_peso integer;
  v_clave text;
  v_claves text[] := '{}'::text[];
  v_destinos uuid[] := '{}'::uuid[];
  v_todos uuid[];
  v_bloqueado uuid;
  v_bloqueados integer := 0;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'SN_SIN_ACCESO';
  end if;
  if p_campana_id is null then
    raise exception using errcode = '22023', message = 'SN_CAMPANA_INVALIDA';
  end if;
  if p_prioridad is null or p_prioridad not between -20 and 20 then
    raise exception using errcode = '22023', message = 'SN_PRIORIDAD_INVALIDA';
  end if;
  if not public.sn__intenciones_validas(v_intenciones) then
    raise exception using errcode = '22023', message = 'SN_INTENCIONES_INVALIDAS';
  end if;
  if p_disponible_desde is not null
     and p_disponible_hasta is not null
     and p_disponible_hasta <= p_disponible_desde then
    raise exception using errcode = '22023', message = 'SN_VENTANA_INVALIDA';
  end if;
  if jsonb_typeof(v_relaciones) <> 'array' then
    raise exception using errcode = '22023', message = 'SN_RELACIONES_INVALIDAS';
  end if;
  if jsonb_array_length(v_relaciones) > 100 then
    raise exception using errcode = '22023', message = 'SN_RELACIONES_INVALIDAS';
  end if;

  -- Se valida el lote completo antes de bloquear o cambiar una sola fila.
  for v_rel in select value from jsonb_array_elements(v_relaciones) as e(value)
  loop
    if jsonb_typeof(v_rel) <> 'object' then
      raise exception using errcode = '22023', message = 'SN_RELACION_FORMA_INVALIDA';
    end if;
    if exists (
         select 1
           from jsonb_object_keys(v_rel) as k(clave)
          where k.clave not in ('destino_id','tipo','peso')
       )
       or not (v_rel ? 'destino_id' and v_rel ? 'tipo' and v_rel ? 'peso')
       or jsonb_typeof(v_rel->'destino_id') <> 'string'
       or jsonb_typeof(v_rel->'tipo') <> 'string'
       or jsonb_typeof(v_rel->'peso') <> 'number'
       or (v_rel->>'destino_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (v_rel->>'peso') !~ '^[0-9]{1,3}$' then
      raise exception using errcode = '22023', message = 'SN_RELACION_FORMA_INVALIDA';
    end if;

    v_destino := (v_rel->>'destino_id')::uuid;
    v_tipo := v_rel->>'tipo';
    v_peso := (v_rel->>'peso')::integer;

    if v_destino = p_campana_id then
      raise exception using errcode = '22023', message = 'SN_RELACION_AUTORREFERENCIA';
    end if;
    if v_tipo not in ('complementa','sustituye','continua','rutina','descubrimiento','excluir')
       or v_tipo is distinct from lower(btrim(v_tipo)) then
      raise exception using errcode = '22023', message = 'SN_RELACION_TIPO_INVALIDO';
    end if;
    if v_peso not between 1 and 100 then
      raise exception using errcode = '22023', message = 'SN_RELACION_PESO_INVALIDO';
    end if;

    v_clave := v_destino::text || '|' || v_tipo;
    if v_clave = any(v_claves) then
      raise exception using errcode = '22023', message = 'SN_RELACION_DUPLICADA';
    end if;
    v_claves := array_append(v_claves, v_clave);
    if not (v_destino = any(v_destinos)) then
      v_destinos := array_append(v_destinos, v_destino);
    end if;
  end loop;

  -- Origen y destinos se bloquean siempre en orden UUID. Esto evita el ciclo
  -- A→B / B→A entre dos guardados concurrentes y fija las FK del lote.
  v_todos := array_append(v_destinos, p_campana_id);
  for v_bloqueado in
    select cp.id
      from public.campana_producto cp
     where cp.id = any(v_todos)
     order by cp.id
     for update
  loop
    v_bloqueados := v_bloqueados + 1;
  end loop;

  if v_bloqueados <> cardinality(v_todos) then
    if not exists (
      select 1 from public.campana_producto cp where cp.id = p_campana_id
    ) then
      raise exception using errcode = 'P0002', message = 'SN_CAMPANA_NO_EXISTE';
    end if;
    raise exception using errcode = 'P0002', message = 'SN_RELACION_DESTINO_NO_EXISTE';
  end if;

  -- Los estados se comprueban después de adquirir todos los locks. Editar un
  -- borrador real no exige publicación ni stock, pero un registro inactivo o
  -- placeholder nunca puede ser origen ni destino editorial.
  if exists (
    select 1
      from public.campana_producto cp
     where cp.id = p_campana_id
       and (not cp.activo or cp.es_placeholder)
  ) then
    raise exception using errcode = 'P0001', message = 'SN_CAMPANA_NO_EDITABLE';
  end if;
  if exists (
    select 1
      from public.campana_producto cp
     where cp.id = any(v_destinos)
       and (not cp.activo or cp.es_placeholder)
  ) then
    raise exception using errcode = 'P0001', message = 'SN_RELACION_DESTINO_NO_EDITABLE';
  end if;

  insert into public.sn_producto_config (
    campana_producto_id, prioridad, intenciones,
    disponible_desde, disponible_hasta,
    creado_por, actualizado_por
  ) values (
    p_campana_id, p_prioridad, v_intenciones,
    p_disponible_desde, p_disponible_hasta,
    auth.uid(), auth.uid()
  )
  on conflict (campana_producto_id) do update
    set prioridad = excluded.prioridad,
        intenciones = excluded.intenciones,
        disponible_desde = excluded.disponible_desde,
        disponible_hasta = excluded.disponible_hasta,
        actualizado_en = statement_timestamp(),
        actualizado_por = auth.uid();

  update public.sn_producto_relacion
     set activo = false,
         retirado_en = statement_timestamp(),
         retirado_por = auth.uid(),
         retirado_razon = 'reemplazo_atomico'
   where campana_origen_id = p_campana_id
     and activo;

  for v_rel in select value from jsonb_array_elements(v_relaciones) as e(value)
  loop
    insert into public.sn_producto_relacion (
      campana_origen_id, campana_destino_id, tipo, peso, creado_por
    ) values (
      p_campana_id,
      (v_rel->>'destino_id')::uuid,
      v_rel->>'tipo',
      (v_rel->>'peso')::integer,
      auth.uid()
    );
  end loop;

  return public.sn_campana_detalle_v1(p_campana_id);
end;
$fn$;

create function public.sn_registrar_asset_v1(
  p_campana_id uuid,
  p_rol text,
  p_storage_path text,
  p_mime text,
  p_ancho integer,
  p_alto integer,
  p_foco_x numeric,
  p_foco_y numeric,
  p_alt text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_rol text := lower(btrim(coalesce(p_rol, '')));
  v_path text := btrim(coalesce(p_storage_path, ''));
  v_mime text := lower(btrim(coalesce(p_mime, '')));
  v_alt text := btrim(coalesce(p_alt, ''));
  v_foco_x numeric(5,4);
  v_foco_y numeric(5,4);
  v_campana_activa boolean;
  v_campana_placeholder boolean;
  v_existente public.sn_asset%rowtype;
  v_version integer;
  v_id uuid;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'SN_SIN_ACCESO';
  end if;
  if p_campana_id is null then
    raise exception using errcode = '22023', message = 'SN_CAMPANA_INVALIDA';
  end if;

  select cp.activo, cp.es_placeholder
    into v_campana_activa, v_campana_placeholder
    from public.campana_producto cp
   where cp.id = p_campana_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SN_CAMPANA_NO_EXISTE';
  end if;
  if not v_campana_activa or v_campana_placeholder then
    raise exception using errcode = 'P0001', message = 'SN_CAMPANA_NO_EDITABLE';
  end if;

  if v_rol not in ('cuadrado','vertical','horizontal','panoramico','recorte') then
    raise exception using errcode = '22023', message = 'SN_ASSET_ROL_INVALIDO';
  end if;
  if v_mime not in ('image/jpeg','image/png','image/webp','image/avif') then
    raise exception using errcode = '22023', message = 'SN_ASSET_MIME_INVALIDO';
  end if;
  if not public.sn__asset_dimensiones_validas(v_rol, p_ancho, p_alto) then
    raise exception using errcode = '22023', message = 'SN_ASSET_DIMENSIONES_INVALIDAS';
  end if;
  if p_foco_x is null or p_foco_y is null
     or p_foco_x not between 0 and 1 or p_foco_y not between 0 and 1 then
    raise exception using errcode = '22023', message = 'SN_ASSET_FOCO_INVALIDO';
  end if;
  v_foco_x := p_foco_x;
  v_foco_y := p_foco_y;
  if not public.sn__alt_seguro(v_alt) then
    raise exception using errcode = '22023', message = 'SN_ASSET_ALT_INVALIDO';
  end if;
  if not public.sn__asset_path_valido(p_campana_id, v_rol, v_path) then
    raise exception using errcode = '22023', message = 'SN_ASSET_PATH_INVALIDO';
  end if;
  if not (
    (v_mime = 'image/jpeg' and v_path ~ '\.(jpg|jpeg)$')
    or (v_mime = 'image/png' and v_path ~ '\.png$')
    or (v_mime = 'image/webp' and v_path ~ '\.webp$')
    or (v_mime = 'image/avif' and v_path ~ '\.avif$')
  ) then
    raise exception using errcode = '22023', message = 'SN_ASSET_EXTENSION_MIME_INVALIDA';
  end if;

  -- Un retry posterior a una respuesta perdida encuentra la key inmutable bajo
  -- el mismo lock de campaña. Solo la misma fila activa y la misma metadata se
  -- consideran éxito; historia y colisiones nunca se reactivan ni se corrigen.
  select * into v_existente
    from public.sn_asset a
   where a.storage_path = v_path
   for update;
  if found then
    if not v_existente.activo then
      raise exception using errcode = 'P0001', message = 'SN_ASSET_PATH_HISTORICO';
    end if;
    if v_existente.campana_producto_id is distinct from p_campana_id
       or v_existente.rol is distinct from v_rol
       or v_existente.storage_path is distinct from v_path
       or v_existente.mime is distinct from v_mime
       or v_existente.ancho is distinct from p_ancho
       or v_existente.alto is distinct from p_alto
       or v_existente.foco_x is distinct from v_foco_x
       or v_existente.foco_y is distinct from v_foco_y
       or v_existente.alt is distinct from v_alt then
      raise exception using errcode = 'P0001', message = 'SN_ASSET_PATH_DIVERGENTE';
    end if;

    return jsonb_build_object(
      'ok', true,
      'asset', jsonb_build_object(
        'id', v_existente.id,
        'campana_id', v_existente.campana_producto_id,
        'rol', v_existente.rol,
        'path', v_existente.storage_path,
        'mime', v_existente.mime,
        'ancho', v_existente.ancho,
        'alto', v_existente.alto,
        'foco_x', v_existente.foco_x,
        'foco_y', v_existente.foco_y,
        'alt', v_existente.alt,
        'version', v_existente.version,
        'activo', true
      )
    );
  end if;

  select coalesce(max(a.version), 0) + 1
    into v_version
    from public.sn_asset a
   where a.campana_producto_id = p_campana_id
     and a.rol = v_rol;

  update public.sn_asset
     set activo = false,
         retirado_en = statement_timestamp(),
         retirado_por = auth.uid(),
         retirado_razon = 'reemplazo_version'
   where campana_producto_id = p_campana_id
     and rol = v_rol
     and activo;

  insert into public.sn_asset (
    campana_producto_id, rol, storage_path, mime,
    ancho, alto, foco_x, foco_y, alt, version, creado_por
  ) values (
    p_campana_id, v_rol, v_path, v_mime,
    p_ancho, p_alto, v_foco_x, v_foco_y, v_alt, v_version, auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'asset', jsonb_build_object(
      'id', v_id, 'campana_id', p_campana_id, 'rol', v_rol,
      'path', v_path, 'mime', v_mime, 'ancho', p_ancho, 'alto', p_alto,
      'foco_x', v_foco_x, 'foco_y', v_foco_y, 'alt', v_alt,
      'version', v_version, 'activo', true
    )
  );
exception when unique_violation then
  raise exception using errcode = '23505', message = 'SN_ASSET_PATH_O_VERSION_DUPLICADA';
end;
$fn$;

create function public.sn_retirar_asset_v1(p_asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_asset public.sn_asset%rowtype;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'SN_SIN_ACCESO';
  end if;
  if p_asset_id is null then
    raise exception using errcode = '22023', message = 'SN_ASSET_INVALIDO';
  end if;

  select * into v_asset
    from public.sn_asset a
   where a.id = p_asset_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SN_ASSET_NO_EXISTE';
  end if;

  if v_asset.activo then
    update public.sn_asset
       set activo = false,
           retirado_en = statement_timestamp(),
           retirado_por = auth.uid(),
           retirado_razon = 'retiro_manual'
     where id = p_asset_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'asset_id', p_asset_id,
    'activo', false,
    'ya_estaba_retirado', not v_asset.activo
  );
end;
$fn$;

create function public.sn_configurar_v1(
  p_activo boolean,
  p_personalizacion_cuenta boolean,
  p_exploracion_pct integer,
  p_razon text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_razon text := btrim(coalesce(p_razon, ''));
  v_salida jsonb;
begin
  if not exists (
    select 1 from public.perfiles p
     where p.id = auth.uid() and p.rol = 'admin'
  ) then
    raise exception using errcode = '42501', message = 'SN_REQUIERE_ADMIN';
  end if;
  if p_activo is null or p_personalizacion_cuenta is null then
    raise exception using errcode = '22023', message = 'SN_CONFIG_BOOLEANO_INVALIDO';
  end if;
  if p_exploracion_pct is null or p_exploracion_pct not between 0 and 100 then
    raise exception using errcode = '22023', message = 'SN_EXPLORACION_INVALIDA';
  end if;
  if length(v_razon) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'SN_RAZON_INVALIDA';
  end if;

  update public.sn_config
     set activo = p_activo,
         personalizacion_cuenta = p_personalizacion_cuenta,
         exploracion_pct = p_exploracion_pct,
         actualizado_razon = v_razon
   where id = 1
  returning jsonb_build_object(
    'ok', true,
    'activo', activo,
    'personalizacion_cuenta', personalizacion_cuenta,
    'modelo_version', modelo_version,
    'exploracion_pct', exploracion_pct,
    'actualizado_en', actualizado_en
  ) into v_salida;

  if v_salida is null then
    raise exception using errcode = 'P0001', message = 'SN_CONFIG_AUSENTE';
  end if;
  return v_salida;
end;
$fn$;

-- ----------------------------------------------------------------------------
-- (F) Búsqueda pública. La consulta jamás se persiste y una señal con forma de
-- PII se rechaza sin repetirla en respuesta ni excepción.
-- ----------------------------------------------------------------------------
create function public.sn_buscar_v1(
  p_consulta text default null,
  p_categoria text default null,
  p_semilla text default null,
  p_limite integer default 24,
  p_desde integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_cfg public.sn_config%rowtype;
  v_cruda text := btrim(coalesce(p_consulta, ''));
  v_consulta text;
  v_categoria text := nullif(lower(btrim(coalesce(p_categoria, ''))), '');
  v_semilla text := nullif(btrim(coalesce(p_semilla, '')), '');
  v_limite integer := coalesce(p_limite, 24);
  v_desde integer := coalesce(p_desde, 0);
  v_modo text;
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_personaliza boolean := false;
begin
  select * into v_cfg from public.sn_config c where c.id = 1;
  if not found or not v_cfg.activo then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_APAGADO',
      'modelo_version', coalesce(v_cfg.modelo_version, 'sn1-reglas-1'),
      'modo', 'apagado', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  if length(v_cruda) > 120 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONSULTA_MUY_LARGA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if public.sn__contiene_pii(v_cruda) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONSULTA_SENSIBLE',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  v_consulta := public.sn__normalizar_texto(v_cruda);
  if v_categoria is not null
     and (length(v_categoria) > 64 or v_categoria !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CATEGORIA_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if v_semilla is not null
     and (length(v_semilla) > 80 or v_semilla !~ '^[A-Za-z0-9_-]+$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SEMILLA_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if v_limite not between 1 and 60 or v_desde not between 0 and 10000 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_PAGINACION_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  v_modo := case
    when v_consulta is not null then 'busqueda'
    when v_categoria is not null then 'categoria'
    else 'exploracion'
  end;
  v_semilla := coalesce(
    v_semilla,
    concat_ws('|', v_modo, coalesce(v_consulta, ''), coalesce(v_categoria, ''),
                    (statement_timestamp() at time zone 'America/Bogota')::date::text)
  );

  if v_cfg.personalizacion_cuenta and v_uid is not null then
    select cc.customer_id into v_customer_id
      from public.cuentas_cliente cc
     where cc.auth_user_id = v_uid and cc.estado = 'activa';
    v_personaliza := found and v_customer_id is not null;
  end if;

  return (
    with ventas_popularidad_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id,
             pi.cantidad
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where not p.anulado
         and p.estado <> 'anulado'
         and p.fecha_orden between
             (statement_timestamp() at time zone 'America/Bogota')::date - 364
             and (statement_timestamp() at time zone 'America/Bogota')::date
    ),
    ventas as (
      select vl.campana_id, sum(vl.cantidad)::bigint as unidades
        from ventas_popularidad_lineas vl
       where vl.campana_id is not null
       group by vl.campana_id
    ),
    compras_cuenta_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where v_personaliza
         and v_customer_id is not null
         and p.customer_id = v_customer_id
         and not p.anulado
         and p.estado <> 'anulado'
    ),
    mis_campanas as (
      select distinct vl.campana_id
        from compras_cuenta_lineas vl
       where vl.campana_id is not null
    ),
    perfil as (
      select
        array(
          select distinct x.codigo from (
            select pcc.categoria_codigo as codigo
              from mis_campanas mc
              join public.campana_producto_categoria pcc
                on pcc.campana_producto_id = mc.campana_id
            union
            select cp2.categoria_codigo
              from mis_campanas mc
              join public.campana_producto cp2 on cp2.id = mc.campana_id
             where cp2.categoria_codigo is not null
          ) x where x.codigo is not null
        )::text[] as categorias
    ),
    elegibles as (
      select
        c.*,
        cp.creado,
        coalesce(pc.prioridad, 0) as prioridad,
        coalesce(v.unidades, 0) as popularidad,
        coalesce(r.promedio, 0) as rating_promedio,
        coalesce(r.total, 0) as rating_total,
        public.sn__normalizar_texto(c.nombre) as nombre_n,
        -- Documento observable: solo columnas de catalogo_publico. Ninguna
        -- etiqueta, intención ni hook interno puede incluir u ordenar resultados.
        public.sn__normalizar_texto(concat_ws(' ',
          c.nombre, c.slug,
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' '),
          c.categorias::text,
          c.detalle_presentacion, c.caracteristica_adicional, c.hook_largo,
          c.por_que_magandhi, c.sobre_este_producto, c.ficha_tecnica::text
        )) as documento_n,
        public.sn__normalizar_texto(concat_ws(' ',
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' '),
          c.categorias::text
        )) as categorias_n
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id
       and cp.publicado
       and cp.activo
       and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
      left join ventas v on v.campana_id = c.id
      left join public.producto_rating_publico r on r.slug = c.slug
      where c.agotado = false
        and c.max_comprable > 0
        and (pc.disponible_desde is null
             or pc.disponible_desde at time zone 'America/Bogota'
                <= statement_timestamp() at time zone 'America/Bogota')
        and (pc.disponible_hasta is null
             or pc.disponible_hasta at time zone 'America/Bogota'
                > statement_timestamp() at time zone 'America/Bogota')
        and (v_categoria is null or v_categoria = any(c.categoria_codigos))
    ),
    puntuados as (
      select e.*,
        case when v_consulta is null then 0 else
          case
            when e.nombre_n = v_consulta then 100000
            when e.nombre_n like v_consulta || '%' then 80000
            when position(v_consulta in e.nombre_n) > 0 then 60000
            else 0
          end
          + case when position(v_consulta in e.categorias_n) > 0 then 20000 else 0 end
          + coalesce((
              select sum(
                case when position(t.token in e.nombre_n) > 0 then 5000 else 0 end
                + case when position(t.token in e.categorias_n) > 0 then 2500 else 0 end
                + case when position(t.token in e.documento_n) > 0 then 1000 else 0 end
              )::integer
                from regexp_split_to_table(v_consulta, ' +') as t(token)
            ), 0)
        end as relevancia_textual,
        case when v_personaliza then
          case when e.categoria_codigos && perfil.categorias then 2 else 0 end
        else 0 end as afinidad_cuenta
      from elegibles e
      cross join perfil
    ),
    filtrados as (
      select * from puntuados p
       where v_consulta is null or p.relevancia_textual > 0
    ),
    ordenados as (
      select f.*,
             row_number() over (
               order by f.relevancia_textual desc,
                        f.afinidad_cuenta desc,
                        f.prioridad desc,
                        f.popularidad desc,
                        f.rating_promedio desc,
                        f.rating_total desc,
                        f.creado desc nulls last,
                        md5(v_semilla || '|' || f.id::text)
             ) as posicion
        from filtrados f
    ),
    pagina as (
      select * from ordenados
       order by posicion
       offset v_desde limit v_limite
    )
    select jsonb_build_object(
      'ok', true,
      'modelo_version', v_cfg.modelo_version,
      'modo', v_modo,
      'consulta', coalesce(v_consulta, ''),
      'total', (select count(*) from filtrados),
      'productos', coalesce((
        select jsonb_agg(x.producto order by x.posicion)
          from (
            select p.posicion,
              jsonb_build_object(
                'id', p.id,
                'nombre', p.nombre,
                'slug', p.slug,
                'categoria_codigo', p.categoria_codigo,
                'categoria_nombre', p.categoria_nombre,
                'categoria_codigos', p.categoria_codigos,
                'detalle_presentacion', p.detalle_presentacion,
                'precio_venta', p.precio_venta,
                'imagen_banner_path', p.imagen_banner_path,
                'imagenes', p.imagenes,
                'sello_elegido', p.sello_elegido,
                'aviso_urgencia_activo', p.aviso_urgencia_activo,
                'aviso_urgencia_cantidad', p.aviso_urgencia_cantidad,
                'max_comprable', p.max_comprable,
                'asset', case when a.asset_id is null then null else jsonb_build_object(
                  'rol', a.rol, 'path', a.path, 'ancho', a.ancho, 'alto', a.alto,
                  'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt
                ) end,
                'razon', case
                  when v_consulta is not null and position(v_consulta in p.nombre_n) > 0
                    then 'coincidencia_nombre'
                  when v_consulta is not null and position(v_consulta in p.categorias_n) > 0
                    then 'coincidencia_categoria'
                  when v_consulta is not null then 'coincidencia_contenido'
                  when p.afinidad_cuenta > 0 then 'afinidad_cuenta'
                  when p.popularidad > 0 then 'popular'
                  when p.creado >= statement_timestamp() - interval '45 days' then 'novedad'
                  else 'exploracion'
                end
              ) as producto
            from pagina p
            left join lateral (
              select av.*
                from public.sn_assets_publicos_v1 av
               where av.campana_id = p.id
               order by array_position(
                 array['cuadrado','horizontal','vertical','recorte','panoramico']::text[],
                 av.rol
               ), av.version desc
               limit 1
            ) a on true
          ) x
      ), '[]'::jsonb)
    )
  );
end;
$fn$;

-- ----------------------------------------------------------------------------
-- (G) Recomendación y composición pública.
-- ----------------------------------------------------------------------------
create function public.sn_recomendar_v1(
  p_superficie text,
  p_contexto jsonb default '{}'::jsonb,
  p_semilla text default null,
  p_limite integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_cfg public.sn_config%rowtype;
  v_superficie text := lower(btrim(coalesce(p_superficie, '')));
  v_contexto jsonb := coalesce(p_contexto, '{}'::jsonb);
  v_semilla text := nullif(btrim(coalesce(p_semilla, '')), '');
  v_limite integer := coalesce(p_limite, 12);
  v_modulos integer;
  v_request_id uuid := gen_random_uuid();
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_es_cuenta boolean := false;
  v_personaliza boolean := false;
  v_slug text;
  v_categoria text;
  v_consulta_cruda text;
  v_consulta text;
  v_contexto_id uuid;
  v_excluir text[] := '{}'::text[];
  v_item jsonb;
  v_excluir_slug text;
begin
  select * into v_cfg from public.sn_config c where c.id = 1;
  if not found or not v_cfg.activo then
    return jsonb_build_object(
      'ok', false,
      'codigo', 'SN_APAGADO',
      'request_id', v_request_id,
      'modelo_version', coalesce(v_cfg.modelo_version, 'sn1-reglas-1'),
      'modo', 'contextual',
      'superficie', v_superficie,
      'modulos', '[]'::jsonb
    );
  end if;

  if v_superficie not in (
    'home_principal','home_descubrimiento','categoria',
    'producto_final','carrito','busqueda'
  ) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SUPERFICIE_INVALIDA',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if v_limite not between 1 and 36 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_LIMITE_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if v_semilla is not null
     and (length(v_semilla) > 80 or v_semilla !~ '^[A-Za-z0-9_-]+$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SEMILLA_INVALIDA',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if jsonb_typeof(v_contexto) <> 'object' then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if exists (
       select 1 from jsonb_object_keys(v_contexto) as k(clave)
        where k.clave not in ('slug','categoria','consulta','excluir')
     ) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;

  if v_contexto ? 'slug' then
    if jsonb_typeof(v_contexto->'slug') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_slug := lower(btrim(v_contexto->>'slug'));
    if length(v_slug) not between 1 and 180
       or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
  end if;

  if v_contexto ? 'categoria' then
    if jsonb_typeof(v_contexto->'categoria') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_categoria := lower(btrim(v_contexto->>'categoria'));
    if length(v_categoria) not between 1 and 64
       or v_categoria !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
  end if;

  if v_contexto ? 'consulta' then
    if jsonb_typeof(v_contexto->'consulta') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_consulta_cruda := btrim(v_contexto->>'consulta');
    if length(v_consulta_cruda) > 120
       or public.sn__contiene_pii(v_consulta_cruda) then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_SENSIBLE',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_consulta := public.sn__normalizar_texto(v_consulta_cruda);
  end if;

  if v_contexto ? 'excluir' then
    if jsonb_typeof(v_contexto->'excluir') <> 'array' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    if jsonb_array_length(v_contexto->'excluir') > 100 then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    for v_item in select value from jsonb_array_elements(v_contexto->'excluir') as e(value)
    loop
      if jsonb_typeof(v_item) <> 'string' then
        return jsonb_build_object(
          'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
          'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
          'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
        );
      end if;
      v_excluir_slug := lower(btrim(v_item #>> '{}'));
      if length(v_excluir_slug) not between 1 and 180
         or v_excluir_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
         or v_excluir_slug = any(v_excluir) then
        return jsonb_build_object(
          'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
          'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
          'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
        );
      end if;
      v_excluir := array_append(v_excluir, v_excluir_slug);
    end loop;
  end if;

  -- Una campaña contextual se resuelve únicamente dentro de la frontera
  -- pública disponible; un slug retirado no se convierte en señal interna.
  if v_slug is not null then
    select c.id into v_contexto_id
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id and cp.publicado and cp.activo and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
     where c.slug = v_slug
       and c.agotado = false
       and c.max_comprable > 0
       and (pc.disponible_desde is null
            or pc.disponible_desde at time zone 'America/Bogota'
               <= statement_timestamp() at time zone 'America/Bogota')
       and (pc.disponible_hasta is null
            or pc.disponible_hasta at time zone 'America/Bogota'
               > statement_timestamp() at time zone 'America/Bogota')
     limit 1;
  end if;

  if v_cfg.personalizacion_cuenta and v_uid is not null then
    select true, cc.customer_id into v_es_cuenta, v_customer_id
      from public.cuentas_cliente cc
     where cc.auth_user_id = v_uid and cc.estado = 'activa';
    v_es_cuenta := coalesce(v_es_cuenta, false);
  end if;
  v_personaliza := v_cfg.personalizacion_cuenta and v_es_cuenta;
  v_modulos := case when v_limite <= 4 then 1 when v_limite <= 8 then 2 else 3 end;
  v_semilla := coalesce(
    v_semilla,
    concat_ws('|', v_superficie, coalesce(v_slug, ''), coalesce(v_categoria, ''),
                    coalesce(v_consulta, ''),
                    (statement_timestamp() at time zone 'America/Bogota')::date::text,
                    case when v_personaliza then v_uid::text else 'anon' end)
  );

  return (
    with ventas_popularidad_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id,
             pi.cantidad
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where not p.anulado
         and p.estado <> 'anulado'
         and p.fecha_orden between
             (statement_timestamp() at time zone 'America/Bogota')::date - 364
             and (statement_timestamp() at time zone 'America/Bogota')::date
    ),
    popularidad as (
      select vl.campana_id, sum(vl.cantidad)::bigint as unidades
        from ventas_popularidad_lineas vl
       where vl.campana_id is not null
       group by vl.campana_id
    ),
    compras_cuenta as (
      select distinct coalesce(pi.campana_id, mapa.campana_id) as campana_id
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where v_personaliza
         and v_customer_id is not null
         and p.customer_id = v_customer_id
         and not p.anulado
         and p.estado <> 'anulado'
    ),
    fuentes_cuenta as (
      select vl.campana_id
        from compras_cuenta vl
       where vl.campana_id is not null
      union
      select ci.campana_id
        from public.carritos ca
        join public.carrito_items ci on ci.carrito_id = ca.id
       where v_personaliza
         and ca.auth_user_id = v_uid
         and ca.estado = 'activa'
    ),
    carrito_actual as (
      select ci.campana_id
        from public.carritos ca
        join public.carrito_items ci on ci.carrito_id = ca.id
       where v_personaliza
         and ca.auth_user_id = v_uid
         and ca.estado = 'activa'
    ),
    fuentes_relacion as (
      select v_contexto_id as campana_id where v_contexto_id is not null
      union
      select ca.campana_id from carrito_actual ca
       where v_superficie = 'carrito'
    ),
    perfil_contexto as (
      select
        array(
          select distinct codigo from (
            select pcc.categoria_codigo as codigo
              from public.campana_producto_categoria pcc
             where pcc.campana_producto_id = v_contexto_id
            union
            select cp2.categoria_codigo
              from public.campana_producto cp2
             where cp2.id = v_contexto_id and cp2.categoria_codigo is not null
          ) x where codigo is not null
        )::text[] as categorias,
        array(
          select distinct pe.etiqueta_codigo
            from public.campana_producto_etiqueta pe
            join public.campana_etiqueta et
              on et.codigo = pe.etiqueta_codigo and et.activo
           where pe.campana_producto_id = v_contexto_id
        )::text[] as etiquetas
    ),
    perfil_cuenta as (
      select
        array(
          select distinct codigo from (
            select pcc.categoria_codigo as codigo
              from fuentes_cuenta fc
              join public.campana_producto_categoria pcc
                on pcc.campana_producto_id = fc.campana_id
            union
            select cp2.categoria_codigo
              from fuentes_cuenta fc
              join public.campana_producto cp2 on cp2.id = fc.campana_id
             where cp2.categoria_codigo is not null
          ) x where codigo is not null
        )::text[] as categorias,
        array(
          select distinct pe.etiqueta_codigo
            from fuentes_cuenta fc
            join public.campana_producto_etiqueta pe
              on pe.campana_producto_id = fc.campana_id
            join public.campana_etiqueta et
              on et.codigo = pe.etiqueta_codigo and et.activo
        )::text[] as etiquetas
    ),
    elegibles as (
      select
        c.*,
        cp.creado,
        coalesce(pc.prioridad, 0) as prioridad,
        coalesce(pop.unidades, 0) as popularidad,
        coalesce(rt.promedio, 0) as rating_promedio,
        coalesce(rt.total, 0) as rating_total,
        coalesce(tags.codigos, '{}'::text[]) as etiquetas_codigos,
        -- La consulta contextual usa el mismo documento público de búsqueda.
        -- Las etiquetas internas quedan solo como afinidad no textual.
        public.sn__normalizar_texto(concat_ws(' ',
          c.nombre, c.slug,
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' '),
          c.categorias::text,
          c.detalle_presentacion, c.caracteristica_adicional, c.hook_largo,
          c.por_que_magandhi, c.sobre_este_producto, c.ficha_tecnica::text
        )) as documento_n
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id
       and cp.publicado
       and cp.activo
       and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
      left join popularidad pop on pop.campana_id = c.id
      left join public.producto_rating_publico rt on rt.slug = c.slug
      left join lateral (
        select array_agg(pe.etiqueta_codigo order by pe.etiqueta_codigo) as codigos
          from public.campana_producto_etiqueta pe
          join public.campana_etiqueta et
            on et.codigo = pe.etiqueta_codigo and et.activo
         where pe.campana_producto_id = c.id
      ) tags on true
      where c.agotado = false
        and c.max_comprable > 0
        and (pc.disponible_desde is null
             or pc.disponible_desde at time zone 'America/Bogota'
                <= statement_timestamp() at time zone 'America/Bogota')
        and (pc.disponible_hasta is null
             or pc.disponible_hasta at time zone 'America/Bogota'
                > statement_timestamp() at time zone 'America/Bogota')
        and not (c.slug = any(v_excluir))
        and (v_slug is null or c.slug <> v_slug)
        and not (
          v_superficie = 'carrito'
          and exists (select 1 from carrito_actual ca where ca.campana_id = c.id)
        )
        and not exists (
          select 1
            from public.sn_producto_relacion rx
            join fuentes_relacion fr on fr.campana_id = rx.campana_origen_id
           where rx.campana_destino_id = c.id
             and rx.activo
             and rx.tipo = 'excluir'
        )
    ),
    senales as (
      select e.*,
        rel.tipo as relacion_tipo,
        coalesce(rel.peso, 0) as relacion_peso,
        case when v_consulta is null then 0 else
          case when position(v_consulta in e.documento_n) > 0 then 5000 else 0 end
          + coalesce((
              select sum(
                case when position(t.token in e.documento_n) > 0 then 1000 else 0 end
              )::integer
                from regexp_split_to_table(v_consulta, ' +') as t(token)
            ), 0)
        end as relevancia_textual,
        (case when v_categoria is not null and v_categoria = any(e.categoria_codigos) then 3 else 0 end)
          + (case when e.categoria_codigos && pcx.categorias then 2 else 0 end)
          + (case when e.etiquetas_codigos && pcx.etiquetas then 1 else 0 end)
          as afinidad_contexto,
        case when v_personaliza then
          (case when e.categoria_codigos && pcu.categorias then 2 else 0 end)
          + (case when e.etiquetas_codigos && pcu.etiquetas then 1 else 0 end)
        else 0 end as afinidad_cuenta,
        (mod((hashtextextended(v_semilla || '|' || e.id::text, 0) & 2147483647), 100)
          < v_cfg.exploracion_pct) as explora
      from elegibles e
      cross join perfil_contexto pcx
      cross join perfil_cuenta pcu
      left join lateral (
        select r.tipo, r.peso
          from public.sn_producto_relacion r
          join fuentes_relacion fr on fr.campana_id = r.campana_origen_id
         where r.campana_destino_id = e.id
           and r.activo
           and r.tipo <> 'excluir'
         order by r.peso desc,
                  array_position(
                    array['complementa','continua','rutina','sustituye','descubrimiento']::text[],
                    r.tipo
                  ),
                  r.id
         limit 1
      ) rel on true
    ),
    puntuados as (
      select s.*,
        (s.relevancia_textual::bigint * 10000)
        + case when s.relacion_peso > 0
            then 100000 + (s.relacion_peso::bigint * 1000)
            else 0
          end
        + (s.afinidad_contexto::bigint * 500)
        + (s.afinidad_cuenta::bigint * 350)
        + ((s.prioridad + 20)::bigint * 25)
        + least(s.popularidad, 500)
        + (s.rating_promedio * 20)::bigint
        + least(s.rating_total, 100)::bigint
        + case when s.creado >= statement_timestamp() - interval '45 days' then 80 else 0 end
        + case when s.explora then greatest(0::bigint, 120 - least(s.popularidad, 120)) else 0 end
        as puntuacion,
        case
          when s.relevancia_textual > 0 then 'coincidencia_busqueda'
          when s.relacion_tipo = 'complementa' then 'complemento'
          when s.relacion_tipo = 'sustituye' then 'alternativa'
          when s.relacion_tipo = 'continua' then 'continuacion'
          when s.relacion_tipo = 'rutina' then 'rutina'
          when s.relacion_tipo = 'descubrimiento' then 'descubrimiento'
          when s.afinidad_cuenta > 0 then 'afinidad_cuenta'
          when s.afinidad_contexto > 0 then 'misma_categoria'
          when s.popularidad > 0 or s.rating_total > 0 then 'popular'
          when s.creado >= statement_timestamp() - interval '45 days' then 'novedad'
          when s.explora then 'exploracion'
          else 'descubrimiento'
        end as razon
      from senales s
    ),
    diversidad as (
      select p.*,
             row_number() over (
               partition by coalesce(p.categoria_codigo, p.id::text)
               order by p.puntuacion desc, md5(v_semilla || '|categoria|' || p.id::text)
             ) as turno_categoria
        from puntuados p
    ),
    ordenados as (
      select d.*,
             row_number() over (
               order by d.turno_categoria,
                        d.puntuacion desc,
                        md5(v_semilla || '|final|' || d.id::text)
             ) as posicion
        from diversidad d
    ),
    seleccionados as (
      select * from ordenados order by posicion limit v_limite
    ),
    layouts as (
      select
        l.*,
        case
          when l.titulo = 'Elegidos para ti'
               and v_personaliza
               and l.superficie = 'home_principal'
               and l.orden = 1 then 'Elegidos para ti'
          when l.titulo = 'Elegidos para ti' then 'Una selección para descubrir'
          when l.titulo in (
            'Una selección para descubrir',
            'También puede gustarte', 'Más por descubrir',
            'Descubre algo nuevo', 'Dos buenas ideas', 'Sigue explorando',
            'Destacados de la categoría', 'Más opciones', 'También explora',
            'Completa tu elección', 'Puede ir bien contigo', 'Otra idea',
            'Antes de terminar', 'También podrías llevar', 'Últimos descubrimientos',
            'Resultados destacados', 'Más resultados', 'También descubre'
          ) then l.titulo
          else case l.superficie
            when 'home_principal' then 'Una selección para descubrir'
            when 'home_descubrimiento' then 'Descubre algo nuevo'
            when 'categoria' then 'Destacados de la categoría'
            when 'producto_final' then 'Completa tu elección'
            when 'carrito' then 'Antes de terminar'
            when 'busqueda' then 'Resultados destacados'
          end
        end as titulo_salida
        from public.sn_layout l
       where l.superficie = v_superficie and l.activo
       order by l.peso desc, l.orden
       limit v_modulos
    )
    select jsonb_build_object(
      'ok', true,
      'request_id', v_request_id,
      'modelo_version', v_cfg.modelo_version,
      'modo', case when v_personaliza then 'personalizado' else 'contextual' end,
      'superficie', v_superficie,
      'modulos', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', l.codigo,
            'tipo', l.tipo,
            'titulo', l.titulo_salida,
            'subtitulo', l.subtitulo,
            'productos', coalesce((
              select jsonb_agg(x.producto order by x.posicion)
                from (
                  select s.posicion,
                    jsonb_build_object(
                      'id', s.id,
                      'nombre', s.nombre,
                      'slug', s.slug,
                      'categoria_codigo', s.categoria_codigo,
                      'categoria_nombre', s.categoria_nombre,
                      'categoria_codigos', s.categoria_codigos,
                      'detalle_presentacion', s.detalle_presentacion,
                      'precio_venta', s.precio_venta,
                      'imagen_banner_path', s.imagen_banner_path,
                      'imagenes', s.imagenes,
                      'sello_elegido', s.sello_elegido,
                      'aviso_urgencia_activo', s.aviso_urgencia_activo,
                      'aviso_urgencia_cantidad', s.aviso_urgencia_cantidad,
                      'max_comprable', s.max_comprable,
                      'asset', case when a.asset_id is null then null else jsonb_build_object(
                        'rol', a.rol, 'path', a.path, 'ancho', a.ancho, 'alto', a.alto,
                        'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt
                      ) end,
                      'razon', s.razon
                    ) as producto
                  from seleccionados s
                  left join lateral (
                    select av.*
                      from public.sn_assets_publicos_v1 av
                     where av.campana_id = s.id
                       and av.rol = any(l.roles_requeridos)
                     order by array_position(l.roles_requeridos, av.rol), av.version desc
                     limit 1
                  ) a on true
                 where ((s.posicion - 1) % v_modulos) + 1 = l.orden
                ) x
            ), '[]'::jsonb)
          ) order by l.orden
        ) from layouts l
      ), '[]'::jsonb)
    )
  );
end;
$fn$;

-- ----------------------------------------------------------------------------
-- (H) Resumen agregado interno. Nunca devuelve visitante, sesión, request_id,
-- consulta_hash ni slug individual.
-- ----------------------------------------------------------------------------
create function public.sn_resumen_v1(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_impresiones bigint;
  v_clics bigint;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'SN_SIN_ACCESO';
  end if;
  if p_desde is null or p_hasta is null
     or p_hasta < p_desde or p_hasta - p_desde > 730 then
    raise exception using errcode = '22023', message = 'SN_PERIODO_INVALIDO';
  end if;

  select
    count(*) filter (where te.tipo = 'recomendacion_impresion'),
    count(*) filter (where te.tipo = 'recomendacion_click')
    into v_impresiones, v_clics
    from public.tienda_eventos te
   where (te.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta;

  return jsonb_build_object(
    'ok', true,
    'desde', p_desde,
    'hasta', p_hasta,
    'impresiones', v_impresiones,
    'clics', v_clics,
    'ctr_pct', case when v_impresiones = 0 then 0
                    else round(v_clics::numeric * 100 / v_impresiones, 2) end,
    'busquedas', (
      select count(*)
        from public.tienda_eventos te
       where te.tipo = 'busqueda_resultados'
         and (te.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta
    ),
    'resultados_promedio', (
      select coalesce(round(avg(te.cantidad_resultados)::numeric, 2), 0)
        from public.tienda_eventos te
       where te.tipo = 'busqueda_resultados'
         and (te.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta
    ),
    'por_superficie', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'superficie', x.superficie,
        'impresiones', x.impresiones,
        'clics', x.clics,
        'ctr_pct', case when x.impresiones = 0 then 0
                        else round(x.clics::numeric * 100 / x.impresiones, 2) end
      ) order by x.superficie), '[]'::jsonb)
        from (
          select te.superficie,
                 count(*) filter (where te.tipo = 'recomendacion_impresion') as impresiones,
                 count(*) filter (where te.tipo = 'recomendacion_click') as clics
            from public.tienda_eventos te
           where te.tipo in ('recomendacion_impresion','recomendacion_click')
             and (te.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta
           group by te.superficie
        ) x
    ),
    'por_modelo', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'modelo_version', x.modelo_version,
        'impresiones', x.impresiones,
        'clics', x.clics,
        'busquedas', x.busquedas
      ) order by x.modelo_version), '[]'::jsonb)
        from (
          select te.modelo_version,
                 count(*) filter (where te.tipo = 'recomendacion_impresion') as impresiones,
                 count(*) filter (where te.tipo = 'recomendacion_click') as clics,
                 count(*) filter (where te.tipo = 'busqueda_resultados') as busquedas
            from public.tienda_eventos te
           where te.tipo in (
             'recomendacion_impresion','recomendacion_click','busqueda_resultados'
           )
             and (te.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta
           group by te.modelo_version
        ) x
    )
  );
end;
$fn$;

-- ----------------------------------------------------------------------------
-- (I) Telemetría consentida: evolución aditiva de M1, misma firma nominal.
-- ----------------------------------------------------------------------------
alter table public.tienda_eventos
  add column request_id uuid,
  add column superficie text,
  add column slot text,
  add column posicion integer,
  add column layout_codigo text,
  add column modelo_version text,
  add column razon text,
  add column cantidad_resultados integer,
  add column consulta_hash text;

alter table public.tienda_eventos
  drop constraint if exists tienda_eventos_tipo_check,
  drop constraint if exists tienda_eventos_slug_check;

alter table public.tienda_eventos
  add constraint tienda_eventos_tipo_check check (
    tipo in (
      'pagina_vista','producto_visto','clic_comprar','checkout_iniciado',
      'compra','llegada_campana','recomendacion_impresion',
      'recomendacion_click','busqueda_resultados'
    )
  ),
  add constraint tienda_eventos_slug_check check (
    slug is null or slug ~ '^[a-z0-9-]{1,180}$'
  ),
  add constraint tienda_eventos_superficie_sn_chk check (
    superficie is null or superficie in (
      'home_principal','home_descubrimiento','categoria',
      'producto_final','carrito','busqueda'
    )
  ),
  add constraint tienda_eventos_slot_sn_chk check (
    slot is null or slot ~ '^[a-z0-9][a-z0-9_-]{0,79}$'
  ),
  add constraint tienda_eventos_posicion_sn_chk check (
    posicion is null or posicion between 1 and 100
  ),
  add constraint tienda_eventos_layout_sn_chk check (
    layout_codigo is null or layout_codigo ~ '^[a-z0-9][a-z0-9_-]{2,79}$'
  ),
  add constraint tienda_eventos_modelo_sn_chk check (
    modelo_version is null
    or modelo_version ~ '^[a-z0-9][a-z0-9._-]{0,59}$'
  ),
  add constraint tienda_eventos_razon_sn_chk check (
    razon is null or razon in (
      'coincidencia_nombre','coincidencia_categoria','coincidencia_contenido',
      'coincidencia_busqueda','afinidad_cuenta','misma_categoria','complemento',
      'alternativa','continuacion','rutina','popular','novedad',
      'descubrimiento','exploracion'
    )
  ),
  add constraint tienda_eventos_cantidad_resultados_sn_chk check (
    cantidad_resultados is null or cantidad_resultados between 0 and 10000
  ),
  add constraint tienda_eventos_consulta_hash_sn_chk check (
    consulta_hash is null or consulta_hash ~ '^[0-9a-f]{64}$'
  ),
  add constraint tienda_eventos_request_separado_sn_chk check (
    request_id is null
    or (
      lower(request_id::text) <> lower(visitante)
      and lower(request_id::text) <> lower(sesion)
    )
  ),
  add constraint tienda_eventos_forma_sn_chk check (
    (
      tipo in (
        'pagina_vista','producto_visto','clic_comprar',
        'checkout_iniciado','compra','llegada_campana'
      )
      and request_id is null and superficie is null and slot is null
      and posicion is null and layout_codigo is null and modelo_version is null
      and razon is null and cantidad_resultados is null and consulta_hash is null
    )
    or
    (
      tipo = 'busqueda_resultados'
      and request_id is not null
      and superficie = 'busqueda'
      and modelo_version is not null
      and cantidad_resultados is not null
      and slot is null and posicion is null and layout_codigo is null and razon is null
      and ruta is null and slug is null and origen is null
      and entrada = false and utm_campaign is null and dispositivo is null
    )
    or
    (
      tipo in ('recomendacion_impresion','recomendacion_click')
      and request_id is not null
      and superficie is not null
      and slot is not null
      and posicion is not null
      and layout_codigo is not null
      and modelo_version is not null
      and razon is not null
      and slug is not null
      and ruta is null and origen is null
      and entrada = false and utm_campaign is null and dispositivo is null
      and cantidad_resultados is null
      and consulta_hash is null
    )
  );

create index tienda_eventos_sn_resumen_idx
  on public.tienda_eventos (tipo, cuando, superficie)
  where tipo in ('recomendacion_impresion','recomendacion_click','busqueda_resultados');

-- Los IDs vienen de una fuente cliente no autoritativa; estos índices solo
-- hacen idempotentes los retries y acotan duplicados accidentales por sesión.
create unique index tienda_eventos_sn_recomendacion_unica_idx
  on public.tienda_eventos (
    visitante, sesion, request_id, slot, posicion, slug, tipo
  )
  where tipo in ('recomendacion_impresion','recomendacion_click');
create unique index tienda_eventos_sn_busqueda_unica_idx
  on public.tienda_eventos (visitante, sesion, request_id)
  where tipo = 'busqueda_resultados';

comment on column public.tienda_eventos.request_id is
  'SN1 · UUID aleatorio por respuesta para correlación efímera; nunca UID, customer_id, visitante ni sesión.';
comment on column public.tienda_eventos.consulta_hash is
  'SN1 · digest HMAC hexadecimal opcional de 64 caracteres; jamás consulta cruda. La Edge re-HMACea el digest cliente con SN_CONSULTA_SAL o lo omite.';
comment on column public.tienda_eventos.razon is
  'SN1 · código explicativo de lista blanca; nunca texto libre ni señal interna.';

-- Mantenimiento explícito. El cron se configura y mide fuera de esta forward;
-- la purga probabilística de ingestión queda únicamente como respaldo.
create function public.sn_purgar_telemetria()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_eventos bigint := 0;
  v_limites bigint := 0;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('magandhi-sn-purgar-telemetria-v1', 0)
  );

  delete from public.tienda_eventos
   where cuando < statement_timestamp() - interval '13 months';
  get diagnostics v_eventos = row_count;

  delete from public.tienda_eventos_limite
   where hora < statement_timestamp() - interval '48 hours';
  get diagnostics v_limites = row_count;

  return jsonb_build_object(
    'eventos_purgados', v_eventos,
    'limites_purgados', v_limites
  );
end;
$fn$;

revoke all on function public.sn_purgar_telemetria()
  from public, anon, authenticated, service_role;
-- El owner postgres conserva EXECUTE; el grant nominal documenta al único
-- ejecutor previsto para el pg_cron configurado manualmente.
grant execute on function public.sn_purgar_telemetria() to postgres;
comment on function public.sn_purgar_telemetria() is
  'SN1 · mantenimiento de retención: borra eventos >13 meses y límites >48 h, devuelve conteos y solo lo ejecuta postgres. El pg_cron se configura manualmente fuera de la migración.';

create or replace function public.mt_registrar_eventos(
  p_visitante text,
  p_sesion text,
  p_eventos jsonb,
  p_ip_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  e jsonb;
  v_ok integer := 0;
  v_desc integer := 0;
  v_n integer;
  v_hora timestamptz := date_trunc('hour', statement_timestamp());
  v_cuando timestamptz;
begin
  if not (
    select ec.analitica_activa and ec.politica_publicada
      from public.em_config ec where ec.id
  ) then
    raise exception 'MT_ANALITICA_APAGADA';
  end if;
  if p_visitante is null or p_visitante !~ '^[A-Za-z0-9_-]{16,40}$'
     or p_sesion is null or p_sesion !~ '^[A-Za-z0-9_-]{8,40}$' then
    raise exception 'MT_VISITANTE_INVALIDO';
  end if;
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array'
     or jsonb_array_length(p_eventos) = 0
     or jsonb_array_length(p_eventos) > 30 then
    raise exception 'MT_EVENTOS_INVALIDOS';
  end if;

  if p_ip_hash is not null then
    insert into public.tienda_eventos_limite (ip_hash, hora, n)
    values (left(p_ip_hash, 64), v_hora, jsonb_array_length(p_eventos))
    on conflict (ip_hash, hora) do update
      set n = public.tienda_eventos_limite.n + excluded.n
    returning n into v_n;
    if v_n > 600 then
      raise exception 'MT_DEMASIADOS_EVENTOS';
    end if;
  end if;

  for e in select value from jsonb_array_elements(p_eventos) as j(value)
  loop
    begin
      v_cuando := coalesce(public.em__ts(e->>'cuando'), statement_timestamp());
      if v_cuando > statement_timestamp()
         or v_cuando < statement_timestamp() - interval '10 minutes' then
        v_cuando := statement_timestamp();
      end if;

      -- Un clic solo cuenta si esta misma sesión ya registró la impresión del
      -- mismo elemento de respuesta. La fuente sigue siendo cliente y, por
      -- tanto, esto limita incoherencias pero no prueba una interacción real.
      if e->>'tipo' = 'recomendacion_click'
         and not exists (
           select 1
             from public.tienda_eventos te
            where te.tipo = 'recomendacion_impresion'
              and te.visitante = p_visitante
              and te.sesion = p_sesion
              and te.request_id = nullif(e->>'request_id', '')::uuid
              and te.slot = nullif(e->>'slot', '')
              and te.posicion = nullif(e->>'posicion', '')::integer
              and te.slug = nullif(e->>'slug', '')
              and te.superficie = nullif(e->>'superficie', '')
              and te.layout_codigo = nullif(e->>'layout_codigo', '')
              and te.modelo_version = nullif(e->>'modelo_version', '')
              and te.razon = nullif(e->>'razon', '')
         ) then
        v_desc := v_desc + 1;
        continue;
      end if;

      insert into public.tienda_eventos (
        visitante, sesion, tipo, ruta, slug, origen, entrada,
        utm_campaign, dispositivo, cuando,
        request_id, superficie, slot, posicion, layout_codigo,
        modelo_version, razon, cantidad_resultados, consulta_hash
      ) values (
        p_visitante,
        p_sesion,
        e->>'tipo',
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(left(e->>'ruta', 120), '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar','checkout_iniciado',
          'compra','llegada_campana','recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'slug', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'origen', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then coalesce((e->>'entrada')::boolean, false) else false end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'utm_campaign', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'dispositivo', '') end,
        v_cuando,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'request_id', '')::uuid end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'superficie', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'slot', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'posicion', '')::integer end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'layout_codigo', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'modelo_version', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'razon', '') end,
        case when e->>'tipo' = 'busqueda_resultados'
          then nullif(e->>'cantidad_resultados', '')::integer end,
        case when e->>'tipo' = 'busqueda_resultados'
          then nullif(e->>'consulta_hash', '') end
      );
      v_ok := v_ok + 1;
    exception
      when check_violation
        or unique_violation
        or invalid_text_representation
        or numeric_value_out_of_range then
      v_desc := v_desc + 1;
    end;
  end loop;

  -- Respaldo best-effort si el trabajo operativo deja de correr. La garantía
  -- de retención depende del mantenimiento programado y medido fuera de aquí.
  if random() < 0.01 then
    perform public.sn_purgar_telemetria();
  end if;
  return jsonb_build_object('aceptados', v_ok, 'descartados', v_desc);
end;
$fn$;

comment on function public.mt_registrar_eventos(text, text, jsonb, text) is
  'M1 + SN1 · conserva firma y seis eventos históricos. Admite tres eventos SN consentidos, aproximados y rate-limited con lista blanca; deduplica retries y descarta clic sin impresión correlacionada, pero la fuente cliente no es autoritativa. consulta_hash solo HMAC hexadecimal y nunca consulta cruda. Analítica activa + política, 30/lote, 600/h por hash temporal, retención operativa 13 meses con purga probabilística de respaldo. Solo service_role.';

-- ----------------------------------------------------------------------------
-- (J) EXECUTE nominal. Helpers/triggers cerrados; público solo buscar/recomendar.
-- ----------------------------------------------------------------------------
revoke all on function public.sn_campana_detalle_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_guardar_campana_v1(uuid, integer, text[], timestamptz, timestamptz, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_registrar_asset_v1(uuid, text, text, text, integer, integer, numeric, numeric, text)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_retirar_asset_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_configurar_v1(boolean, boolean, integer, text)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_buscar_v1(text, text, text, integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_recomendar_v1(text, jsonb, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_resumen_v1(date, date)
  from public, anon, authenticated, service_role;
revoke all on function public.mt_registrar_eventos(text, text, jsonb, text)
  from public, anon, authenticated, service_role;

grant execute on function public.sn_campana_detalle_v1(uuid)
  to authenticated;
grant execute on function public.sn_guardar_campana_v1(uuid, integer, text[], timestamptz, timestamptz, jsonb)
  to authenticated;
grant execute on function public.sn_registrar_asset_v1(uuid, text, text, text, integer, integer, numeric, numeric, text)
  to authenticated;
grant execute on function public.sn_retirar_asset_v1(uuid)
  to authenticated;
grant execute on function public.sn_configurar_v1(boolean, boolean, integer, text)
  to authenticated;
grant execute on function public.sn_resumen_v1(date, date)
  to authenticated;
grant execute on function public.sn_buscar_v1(text, text, text, integer, integer)
  to anon, authenticated, service_role;
grant execute on function public.sn_recomendar_v1(text, jsonb, text, integer)
  to anon, authenticated, service_role;
grant execute on function public.mt_registrar_eventos(text, text, jsonb, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (K) Gates de contrato antes de confirmar la transacción.
-- ----------------------------------------------------------------------------
do $gate$
declare
  v_columnas text[];
  v_acl record;
  v_campana_gate constant uuid := '11111111-2222-4333-8444-555555555555';
begin
  if not exists (
    select 1 from public.sn_config c
     where c.id = 1
       and c.activo
       and c.personalizacion_cuenta
       and c.modelo_version = 'sn1-reglas-1'
       and c.exploracion_pct = 12
  ) then
    raise exception using errcode = 'P0001', message = 'SN1_CONFIG_INICIAL_INVALIDA';
  end if;

  if exists (
    select 1 from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = 'sn_producto_config'
       and c.column_name in ('activo','habilitado','publicado')
  ) then
    raise exception using errcode = 'P0001', message = 'SN1_GATE_POR_PRODUCTO_PROHIBIDO';
  end if;

  if public.sn__intenciones_validas(null)
     or not public.sn__intenciones_validas('{}'::text[])
     or not public.sn__intenciones_validas(array(
       select 'caso editorial ' || chr(96 + n)
         from generate_series(1, 12) as g(n)
     ))
     or public.sn__intenciones_validas(array(
       select 'caso editorial ' || chr(96 + n)
         from generate_series(1, 13) as g(n)
     ))
     or public.sn__intenciones_validas(array['café diario','cafe diario'])
     or public.sn__intenciones_validas(array['texto  con espacios'])
     or public.sn__intenciones_validas(array['contactar ana@example.com']) then
    raise exception using errcode = 'P0001', message = 'SN1_INTENCIONES_CONTRATO_INVALIDO';
  end if;

  if not public.sn__alt_seguro('Botella roja sobre fondo claro')
     or public.sn__alt_seguro(' Botella roja sobre fondo claro')
     or public.sn__alt_seguro(E'Botella roja\ncon tapa')
     or public.sn__alt_seguro('Escribir a ana@example.com')
     or public.sn__alt_seguro('Llamar al 300 123 4567')
     or public.sn__alt_seguro('Asset 11111111-2222-4333-8444-555555555555')
     or public.sn__alt_seguro('Foto por @proveedor')
     or public.sn__alt_seguro('Precio especial del producto')
     or public.sn__alt_seguro('Producto por $25.000')
     or public.sn__alt_seguro('Stock disponible')
     or public.sn__alt_seguro('Foto entregada por proveedor')
     or public.sn__alt_seguro('Producto por 25.000') then
    raise exception using errcode = 'P0001', message = 'SN1_ASSET_ALT_CONTRATO_INVALIDO';
  end if;

  if not public.sn__asset_path_valido(
       v_campana_gate,
       'cuadrado',
       'sistema-nervioso/11111111-2222-4333-8444-555555555555/cuadrado-20261112000000000-a1b2c3d4e5f60708.webp'
     )
     or public.sn__asset_path_valido(
       v_campana_gate,
       'cuadrado',
       'sistema-nervioso/11111111-2222-4333-8444-555555555555/cuadrado-20261112000000000-a1b2c3d4e5f60708-sm.webp'
     )
     or public.sn__asset_path_valido(
       v_campana_gate,
       'cuadrado',
       'sistema-nervioso/11111111-2222-4333-8444-555555555555/subcarpeta/cuadrado-20261112000000000-a1b2c3d4e5f60708.webp'
     ) then
    raise exception using errcode = 'P0001', message = 'SN1_ASSET_PATH_CONTRATO_INVALIDO';
  end if;

  if not public.sn__asset_dimensiones_validas('cuadrado', 1600, 1600)
     or not public.sn__asset_dimensiones_validas('vertical', 1600, 2000)
     or not public.sn__asset_dimensiones_validas('horizontal', 1920, 1080)
     or not public.sn__asset_dimensiones_validas('panoramico', 2000, 1000)
     or not public.sn__asset_dimensiones_validas('recorte', 2000, 2000)
     or public.sn__asset_dimensiones_validas('cuadrado', 1599, 1600)
     or public.sn__asset_dimensiones_validas('panoramico', 2200, 1000) then
    raise exception using errcode = 'P0001', message = 'SN1_ASSET_DIMENSIONES_CONTRATO_INVALIDO';
  end if;

  if (select count(*) from public.sn_layout where activo) <> 18
     or exists (
       select superficie
         from public.sn_layout
        where activo
        group by superficie
       having count(*) <> 3
     )
     or exists (
       select 1
         from public.sn_layout l
        where l.activo
          and (
            l.titulo not in (
              'Elegidos para ti', 'Una selección para descubrir',
              'También puede gustarte', 'Más por descubrir',
              'Descubre algo nuevo', 'Dos buenas ideas', 'Sigue explorando',
              'Destacados de la categoría', 'Más opciones', 'También explora',
              'Completa tu elección', 'Puede ir bien contigo', 'Otra idea',
              'Antes de terminar', 'También podrías llevar', 'Últimos descubrimientos',
              'Resultados destacados', 'Más resultados', 'También descubre'
            )
            or (
              l.titulo = 'Elegidos para ti'
              and (l.superficie <> 'home_principal' or l.orden <> 1)
            )
          )
     ) then
    raise exception using errcode = 'P0001', message = 'SN1_LAYOUT_SEEDS_INVALIDOS';
  end if;

  select array_agg(c.column_name::text order by c.ordinal_position)
    into v_columnas
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = 'sn_assets_publicos_v1';
  if v_columnas is distinct from array[
    'asset_id','campana_id','rol','path','mime','ancho','alto',
    'foco_x','foco_y','alt','version'
  ]::text[] then
    raise exception using errcode = 'P0001', message = 'SN1_ASSETS_PUBLICOS_ALLOWLIST_INVALIDA';
  end if;

  if not has_table_privilege('anon', 'public.sn_catalogo_seguro_v1', 'select')
     or not has_table_privilege('authenticated', 'public.sn_catalogo_seguro_v1', 'select')
     or not has_table_privilege('service_role', 'public.sn_catalogo_seguro_v1', 'select') then
    raise exception using errcode = 'P0001', message = 'SN1_CATALOGO_SEGURO_ACL_INVALIDA';
  end if;

  if not has_table_privilege('anon', 'public.sn_assets_publicos_v1', 'select')
     or not has_table_privilege('authenticated', 'public.sn_assets_publicos_v1', 'select')
     or not has_table_privilege('service_role', 'public.sn_assets_publicos_v1', 'select') then
    raise exception using errcode = 'P0001', message = 'SN1_ASSETS_PUBLICOS_ACL_INVALIDA';
  end if;

  if has_table_privilege('anon', 'public.sn_config', 'select')
     or has_table_privilege('anon', 'public.sn_producto_config', 'select')
     or has_table_privilege('anon', 'public.sn_producto_relacion', 'select')
     or has_table_privilege('anon', 'public.sn_asset', 'select')
     or has_table_privilege('anon', 'public.sn_layout', 'select')
     or has_table_privilege('authenticated', 'public.sn_config', 'insert')
     or has_table_privilege('authenticated', 'public.sn_producto_config', 'update')
     or has_table_privilege('authenticated', 'public.sn_producto_relacion', 'delete')
     or has_table_privilege('authenticated', 'public.sn_asset', 'insert')
     or has_table_privilege('service_role', 'public.sn_asset', 'select') then
    raise exception using errcode = 'P0001', message = 'SN1_TABLAS_PRIVADAS_ACL_INVALIDA';
  end if;

  if not has_function_privilege('anon', 'public.sn_buscar_v1(text,text,text,integer,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.sn_buscar_v1(text,text,text,integer,integer)', 'execute')
     or not has_function_privilege('service_role', 'public.sn_buscar_v1(text,text,text,integer,integer)', 'execute')
     or not has_function_privilege('anon', 'public.sn_recomendar_v1(text,jsonb,text,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.sn_recomendar_v1(text,jsonb,text,integer)', 'execute')
     or not has_function_privilege('service_role', 'public.sn_recomendar_v1(text,jsonb,text,integer)', 'execute') then
    raise exception using errcode = 'P0001', message = 'SN1_RPC_PUBLICAS_ACL_INVALIDA';
  end if;

  if has_function_privilege('anon', 'public.sn_campana_detalle_v1(uuid)', 'execute')
     or has_function_privilege('anon', 'public.sn_guardar_campana_v1(uuid,integer,text[],timestamptz,timestamptz,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.sn_registrar_asset_v1(uuid,text,text,text,integer,integer,numeric,numeric,text)', 'execute')
     or has_function_privilege('anon', 'public.sn_resumen_v1(date,date)', 'execute')
     or has_function_privilege('service_role', 'public.sn_resumen_v1(date,date)', 'execute')
     or has_function_privilege('anon', 'public.mt_registrar_eventos(text,text,jsonb,text)', 'execute')
     or has_function_privilege('authenticated', 'public.mt_registrar_eventos(text,text,jsonb,text)', 'execute')
     or not has_function_privilege('service_role', 'public.mt_registrar_eventos(text,text,jsonb,text)', 'execute') then
    raise exception using errcode = 'P0001', message = 'SN1_RPC_PRIVADAS_ACL_INVALIDA';
  end if;

  -- Las ocho firmas SN son nominales: dos puertas públicas/service y seis de
  -- panel authenticated. La purga no pertenece a ningún rol API.
  for v_acl in
    select * from (values
      ('public.sn_campana_detalle_v1(uuid)', false, true, false),
      ('public.sn_guardar_campana_v1(uuid,integer,text[],timestamptz,timestamptz,jsonb)', false, true, false),
      ('public.sn_registrar_asset_v1(uuid,text,text,text,integer,integer,numeric,numeric,text)', false, true, false),
      ('public.sn_retirar_asset_v1(uuid)', false, true, false),
      ('public.sn_configurar_v1(boolean,boolean,integer,text)', false, true, false),
      ('public.sn_buscar_v1(text,text,text,integer,integer)', true, true, true),
      ('public.sn_recomendar_v1(text,jsonb,text,integer)', true, true, true),
      ('public.sn_resumen_v1(date,date)', false, true, false),
      ('public.sn_purgar_telemetria()', false, false, false)
    ) as x(firma, anon_e, authenticated_e, service_e)
  loop
    if to_regprocedure(v_acl.firma) is null
       or has_function_privilege(
            'anon', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.anon_e
       or has_function_privilege(
            'authenticated', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.authenticated_e
       or has_function_privilege(
            'service_role', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.service_e then
      raise exception using errcode = 'P0001', message = 'SN1_RPC_NOMINAL_ACL_INVALIDA';
    end if;
  end loop;

  if not has_function_privilege(
       'postgres', 'public.sn_purgar_telemetria()', 'execute'
     )
     or not (
       select p.prosecdef
         from pg_proc p
        where p.oid = 'public.sn_purgar_telemetria()'::regprocedure
     )
     or exists (
       select 1
         from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname like 'sn\_\_%' escape '\'
          and (
            has_function_privilege('anon', p.oid, 'execute')
            or has_function_privilege('authenticated', p.oid, 'execute')
            or has_function_privilege('service_role', p.oid, 'execute')
          )
     ) then
    raise exception using errcode = 'P0001', message = 'SN1_HELPERS_O_PURGA_ACL_INVALIDA';
  end if;
end;
$gate$;

commit;
