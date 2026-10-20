-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · ENLACES PROPIOS Y CLICS APROXIMADOS
-- ----------------------------------------------------------------------------
-- Capa PostgreSQL privada para:
--   · borradores y enlaces cortos inmutables;
--   · resolución de destinos MAGANDHI de lista blanca;
--   · conteo diario agregado con cuota temporal global;
--   · compactación transaccional de detalle mayor a 13 meses.
--
-- No agrega UI, atribución a pedidos (P4), resultados (P5) ni URL libre.
-- Todos los gates nacen OFF. Forward de una sola aplicación.
-- REQUISITO: Promocionar P1 completo hasta 20261107000100.
-- ============================================================================

begin;
set local search_path = public, extensions, pg_temp;
set local statement_timeout = '90s';
set local lock_timeout = '5s';

-- Mantener el orden P1: lock de relación antes del advisory lock.
lock table campana_producto in share row exclusive mode;
select pg_advisory_xact_lock(hashtextextended('promocionar-p3-instalacion-v1', 0));

-- Baseline medido por objetos, no por un ledger que producción no tiene.
do $baseline$
begin
  if to_regclass('public.campana_producto') is null
     or to_regclass('public.campana_slug_historial') is null
     or to_regclass('public.campana_slug_alias_publico') is null
     or to_regprocedure('public.cm__asignar_slug_automatico()') is null
     or to_regprocedure('public.cm__validar_slug_no_reasignado()') is null
     or to_regprocedure('public.cm__registrar_slug_historial()') is null
     or to_regprocedure('public.tiene_acceso_marketing()') is null
     or not exists (
       select 1
         from pg_extension e
         join pg_namespace n on n.oid = e.extnamespace
        where e.extname = 'pgcrypto'
          and n.nspname in ('public', 'extensions')
          and to_regprocedure(format('%I.gen_random_bytes(integer)', n.nspname)) is not null
          and to_regprocedure(format('%I.digest(text,text)', n.nspname)) is not null
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'P3_REQUIERE_BASELINE_P1_COMPLETO';
  end if;

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public' and table_name = 'campana_producto'
       and column_name = 'slug' and is_nullable = 'NO'
  ) or not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public' and table_name = 'campana_producto'
       and column_name = 'es_placeholder' and is_nullable = 'NO'
  ) or exists (
    select 1
      from campana_producto cp
      left join campana_slug_historial h
        on h.slug = cp.slug and h.campana_producto_id = cp.id
     where cp.slug is null
        or cp.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
        or length(cp.slug) > 180
        or h.slug is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'P3_BASELINE_P1_INCONSISTENTE';
  end if;

  if exists (
    select 1
      from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
       and (
         has_schema_privilege(r.rolname, 'public', 'CREATE')
         or case when to_regnamespace('extensions') is null then false
                 else has_schema_privilege(r.rolname, 'extensions', 'CREATE') end
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'P3_ROL_API_PUEDE_CREAR_EN_SCHEMA_DEFINER';
  end if;

  if to_regclass('public.promocionar_p3_config') is not null
     or to_regclass('public.promocionar_p3_config_bitacora') is not null
     or to_regclass('public.atribucion_enlaces') is not null
     or to_regclass('public.atribucion_clics_dia') is not null
     or to_regclass('public.atribucion_limite_temporal') is not null
     or to_regprocedure('public.promocionar_p3_config()') is not null
     or to_regprocedure('public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)') is not null
     or to_regprocedure('public.promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)') is not null
     or to_regprocedure('public.promocionar_p3_resolver(text)') is not null then
    raise exception using
      errcode = 'P0001',
      message = 'P3_REQUIERE_AUSENCIA_LIMPIA';
  end if;
end;
$baseline$;

-- ----------------------------------------------------------------------------
-- Configuración singleton. URL y cuota inicial son decisiones cerradas; una
-- modificación requiere otra migración/decisión, no un UPDATE silencioso.
-- ----------------------------------------------------------------------------
create table promocionar_p3_config (
  id                       smallint primary key default 1,
  activacion_habilitada    boolean not null default false,
  redirect_habilitado      boolean not null default false,
  conteo_habilitado        boolean not null default false,
  politica_publicada       boolean not null default false,
  routing_verificado       boolean not null default false,
  politica_version         text,
  url_corta_base           text not null default 'https://go.magandhi.com',
  cuota_hora               integer not null default 600,
  actualizado_en           timestamptz not null default statement_timestamp(),
  actualizado_por          uuid references auth.users(id) on delete restrict,
  actualizado_razon        text not null,
  actualizado_rol          text not null,
  constraint promocionar_p3_config_singleton check (id = 1),
  constraint promocionar_p3_config_url_fija
    check (url_corta_base = 'https://go.magandhi.com'),
  constraint promocionar_p3_config_cuota_fija check (cuota_hora = 600),
  constraint promocionar_p3_config_razon_valida check (
    actualizado_razon = btrim(actualizado_razon)
    and length(actualizado_razon) between 1 and 500
  ),
  constraint promocionar_p3_config_rol_valido check (
    actualizado_rol = btrim(actualizado_rol)
    and length(actualizado_rol) between 1 and 120
  ),
  constraint promocionar_p3_config_version_valida check (
    politica_version is null
    or (
      politica_version = btrim(politica_version)
      and length(politica_version) between 1 and 120
    )
  ),
  constraint promocionar_p3_config_gates_coherentes check (
    (not politica_publicada or politica_version is not null)
    and (
      not (activacion_habilitada or redirect_habilitado or conteo_habilitado)
      or routing_verificado
    )
    and (not activacion_habilitada or redirect_habilitado)
    and (not conteo_habilitado or redirect_habilitado)
  )
);

insert into promocionar_p3_config (
  id, activacion_habilitada, redirect_habilitado, conteo_habilitado,
  politica_publicada, routing_verificado, politica_version,
  url_corta_base, cuota_hora, actualizado_por, actualizado_razon, actualizado_rol
) values (
  1, false, false, false, false, false, null,
  'https://go.magandhi.com', 600, auth.uid(), 'instalacion_inicial', current_user
);

comment on table promocionar_p3_config is
  'Promocionar P3 · singleton privado. Los tres gates nacen OFF y requieren routing medido; la política es informativa y no bloquea P3.';
comment on column promocionar_p3_config.politica_publicada is
  'Referencia informativa para la política general; no condiciona activación, redirect ni conteo P3.';
comment on column promocionar_p3_config.politica_version is
  'Versión informativa opcional; P3 puede operar mientras permanece NULL.';
comment on column promocionar_p3_config.activacion_habilitada is
  'Gate para que Marketing active borradores; solo puede encenderse con redirect habilitado.';
comment on column promocionar_p3_config.redirect_habilitado is
  'Gate público de resolución; la RPC config lo expone también como activo.';
comment on column promocionar_p3_config.conteo_habilitado is
  'Gate de conteo aproximado; puede apagarse sin apagar el redirect.';
comment on column promocionar_p3_config.url_corta_base is
  'Decisión cerrada P3: exactamente https://go.magandhi.com, sin slash final.';
comment on column promocionar_p3_config.cuota_hora is
  'Cuota temporal global inicial: 600 incrementos aceptados por hash diario y hora.';
comment on column promocionar_p3_config.actualizado_razon is
  'Razón operativa obligatoria y nueva para cada cambio de gates o evidencia.';
comment on column promocionar_p3_config.actualizado_rol is
  'current_user capturado explícitamente por la operación que cambió la configuración.';

-- Historial privado e inmutable de gates y evidencia. No contiene códigos,
-- hashes, destinos ni datos de clientes.
create table promocionar_p3_config_bitacora (
  id                                bigint generated always as identity primary key,
  registrado_en                     timestamptz not null default statement_timestamp(),
  actor_uid                         uuid,
  actor_rol                         text not null,
  razon                             text not null,
  antes_activacion_habilitada       boolean,
  despues_activacion_habilitada     boolean not null,
  antes_redirect_habilitado         boolean,
  despues_redirect_habilitado       boolean not null,
  antes_conteo_habilitado           boolean,
  despues_conteo_habilitado         boolean not null,
  antes_politica_publicada          boolean,
  despues_politica_publicada        boolean not null,
  antes_routing_verificado          boolean,
  despues_routing_verificado        boolean not null,
  antes_politica_version            text,
  despues_politica_version          text,
  constraint promocionar_p3_config_bitacora_razon_valida check (
    razon = btrim(razon) and length(razon) between 1 and 500
  ),
  constraint promocionar_p3_config_bitacora_rol_valido check (
    actor_rol = btrim(actor_rol) and length(actor_rol) between 1 and 120
  ),
  constraint promocionar_p3_config_bitacora_antes_completo check (
    (
      antes_activacion_habilitada is null
      and antes_redirect_habilitado is null
      and antes_conteo_habilitado is null
      and antes_politica_publicada is null
      and antes_routing_verificado is null
      and antes_politica_version is null
    )
    or (
      antes_activacion_habilitada is not null
      and antes_redirect_habilitado is not null
      and antes_conteo_habilitado is not null
      and antes_politica_publicada is not null
      and antes_routing_verificado is not null
    )
  )
);

insert into promocionar_p3_config_bitacora (
  actor_uid, actor_rol, razon,
  antes_activacion_habilitada, despues_activacion_habilitada,
  antes_redirect_habilitado, despues_redirect_habilitado,
  antes_conteo_habilitado, despues_conteo_habilitado,
  antes_politica_publicada, despues_politica_publicada,
  antes_routing_verificado, despues_routing_verificado,
  antes_politica_version, despues_politica_version
)
select auth.uid(), current_user, 'instalacion_inicial',
       null, c.activacion_habilitada,
       null, c.redirect_habilitado,
       null, c.conteo_habilitado,
       null, c.politica_publicada,
       null, c.routing_verificado,
       null, c.politica_version
  from promocionar_p3_config c
 where c.id = 1;

comment on table promocionar_p3_config_bitacora is
  'Promocionar P3 · historial privado append-only de gates y evidencia; sin datos de enlaces ni actores expuestos por API.';
comment on column promocionar_p3_config_bitacora.actor_uid is
  'auth.uid() al cambiar configuración; puede ser NULL para operación SQL/cron.';
comment on column promocionar_p3_config_bitacora.actor_rol is
  'current_user capturado por la operación y conservado solo en la tabla privada.';

-- ----------------------------------------------------------------------------
-- Registro autoritativo del enlace. No existe columna URL: el destino se deriva
-- exclusivamente de tipo_destino + campana_producto_id.
-- ----------------------------------------------------------------------------
create table atribucion_enlaces (
  id                            uuid primary key default gen_random_uuid(),
  codigo                        text,
  campana_producto_id           uuid not null references campana_producto(id) on delete restrict,
  canal_promocion               text not null,
  source                        text not null,
  medium                        text not null,
  campaign_base                 text not null,
  campaign                      text not null,
  content                       text,
  tipo_destino                  text not null,
  estado_enlace                 text not null default 'borrador',
  clave_idempotencia            uuid not null,
  idempotencia_payload_hash     text not null,
  reemplaza_enlace_id           uuid references atribucion_enlaces(id) on delete restrict,
  total_aproximado_historico    bigint not null default 0,
  creado_en                     timestamptz not null default statement_timestamp(),
  creado_por                    uuid not null references auth.users(id) on delete restrict,
  actualizado_en                timestamptz not null default statement_timestamp(),
  actualizado_por               uuid references auth.users(id) on delete restrict,
  activado_en                   timestamptz,
  activado_por                  uuid references auth.users(id) on delete restrict,
  desactivado_en                timestamptz,
  desactivado_por               uuid references auth.users(id) on delete restrict,
  mantenimiento_en              timestamptz,

  constraint atribucion_enlaces_codigo_unico unique (codigo),
  constraint atribucion_enlaces_campaign_unico unique (campaign),
  constraint atribucion_enlaces_idempotencia_unica
    unique (clave_idempotencia, creado_por),
  constraint atribucion_enlaces_idempotencia_hash_formato
    check (idempotencia_payload_hash ~ '^[0-9a-f]{64}$'),
  constraint atribucion_enlaces_codigo_estado_enlace check (
    (estado_enlace = 'borrador' and codigo is null)
    or (
      estado_enlace in ('activo', 'desactivado')
      and codigo ~ '^[0-9a-hjkmnp-tv-z]{16}$'
    )
  ),
  constraint atribucion_enlaces_estado_enlace_valido
    check (estado_enlace in ('borrador', 'activo', 'desactivado')),
  constraint atribucion_enlaces_destino_tipado
    check (tipo_destino in ('producto_v1', 'home_v1')),
  constraint atribucion_enlaces_canal_utm check (
    (canal_promocion = 'whatsapp' and source = 'whatsapp' and medium = 'mensajeria')
    or (canal_promocion = 'instagram' and source = 'instagram' and medium = 'social')
    or (canal_promocion = 'facebook' and source = 'facebook' and medium = 'social')
    or (canal_promocion = 'email' and source = 'email' and medium = 'email')
    or (canal_promocion = 'qr' and source = 'qr' and medium = 'offline')
    or (canal_promocion = 'anuncio_manual' and source = 'anuncio-manual' and medium = 'paid-manual')
    or (canal_promocion = 'otro_controlado' and source = 'otro-controlado' and medium = 'referral')
  ),
  constraint atribucion_enlaces_campaign_base_formato check (
    campaign_base ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    and length(campaign_base) between 1 and 48
  ),
  constraint atribucion_enlaces_campaign_formato check (
    campaign ~ '^[a-z0-9]+(-[a-z0-9]+)*-[0-9]{6}-[0-9a-hjkmnp-tv-z]{4}$'
    and length(campaign) <= 60
    and length(campaign) = length(campaign_base) + 12
    and left(campaign, length(campaign_base) + 1) = campaign_base || '-'
  ),
  constraint atribucion_enlaces_content_formato check (
    content is null
    or (
      content ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      and length(content) between 1 and 60
    )
  ),
  constraint atribucion_enlaces_no_autorreemplazo
    check (reemplaza_enlace_id is null or reemplaza_enlace_id <> id),
  constraint atribucion_enlaces_total_no_negativo
    check (total_aproximado_historico >= 0),
  constraint atribucion_enlaces_auditoria_estado_enlace check (
    (estado_enlace = 'borrador'
      and activado_en is null and activado_por is null
      and desactivado_en is null and desactivado_por is null)
    or
    (estado_enlace = 'activo'
      and activado_en is not null and activado_por is not null
      and desactivado_en is null and desactivado_por is null
      and activado_en >= creado_en)
    or
    (estado_enlace = 'desactivado'
      and activado_en is not null and activado_por is not null
      and desactivado_en is not null and desactivado_por is not null
      and activado_en >= creado_en and desactivado_en >= activado_en)
  )
);

create index atribucion_enlaces_campana_creado_idx
  on atribucion_enlaces (campana_producto_id, creado_en desc);
create index atribucion_enlaces_estado_enlace_idx
  on atribucion_enlaces (estado_enlace, creado_en desc);
create unique index atribucion_enlaces_reemplaza_unico_idx
  on atribucion_enlaces (reemplaza_enlace_id)
  where reemplaza_enlace_id is not null;

comment on table atribucion_enlaces is
  'Promocionar P3 · registro privado autoritativo de enlaces propios; sin URL arbitraria, PII ni atribución de pedidos.';
comment on column atribucion_enlaces.codigo is
  'Código público opaco: NULL solo en borrador; 16 caracteres Crockford/80 bits al activar; reservado para siempre.';
comment on column atribucion_enlaces.campana_producto_id is
  'Campaña de origen obligatoria para todo enlace, incluso cuando tipo_destino es home_v1.';
comment on column atribucion_enlaces.estado_enlace is
  'Ciclo contractual del enlace: borrador, activo o desactivado terminal.';
comment on column atribucion_enlaces.campaign_base is
  'Base normalizada server-side (máximo 48); no identifica personas.';
comment on column atribucion_enlaces.campaign is
  'UTM final única: base-aammdd-xxxx, generada server-side y congelada al activar.';
comment on column atribucion_enlaces.content is
  'Pieza o colocación normalizada opcional; nunca persona, audiencia, correo, teléfono o identificador.';
comment on column atribucion_enlaces.idempotencia_payload_hash is
  'SHA-256 del payload canónico original; liga la clave sin persistir una segunda copia del contenido y no cambia al editar.';
comment on column atribucion_enlaces.total_aproximado_historico is
  'Rollup no fechado del detalle diario que superó 13 meses; no representa personas únicas.';

-- Una fila agregada por enlace y fecha civil de Colombia.
create table atribucion_clics_dia (
  enlace_id         uuid not null references atribucion_enlaces(id) on delete restrict,
  fecha_colombia    date not null,
  total             bigint not null,
  constraint atribucion_clics_dia_pkey primary key (enlace_id, fecha_colombia),
  constraint atribucion_clics_dia_total_positivo check (total > 0)
);

create index atribucion_clics_dia_fecha_idx
  on atribucion_clics_dia (fecha_colombia, enlace_id);

comment on table atribucion_clics_dia is
  'Promocionar P3 · clics aproximados agregados por enlace y fecha America/Bogota; nunca eventos individuales.';

-- Cuota global: deliberadamente NO contiene enlace_id ni cualquier identidad.
create table atribucion_limite_temporal (
  hash_ip_dia     text not null,
  ventana_hora    timestamp without time zone not null,
  conteo          integer not null,
  creado_en       timestamptz not null default statement_timestamp(),
  expira_en       timestamptz not null,
  constraint atribucion_limite_temporal_pkey
    primary key (hash_ip_dia, ventana_hora),
  constraint atribucion_limite_temporal_hash_formato
    check (hash_ip_dia ~ '^[0-9a-f]{64}$'),
  constraint atribucion_limite_temporal_ventana_hora check (
    ventana_hora = date_trunc('hour', ventana_hora)
  ),
  constraint atribucion_limite_temporal_conteo check (
    conteo between 1 and 600
  ),
  constraint atribucion_limite_temporal_expiracion check (
    expira_en > creado_en
    and expira_en < creado_en + interval '48 hours'
  )
);

create index atribucion_limite_temporal_expira_idx
  on atribucion_limite_temporal (expira_en);

comment on table atribucion_limite_temporal is
  'Promocionar P3 · cuota global efímera: el hash HMAC rota por fecha Colombia y ventana_hora representa la hora técnica UTC; sin enlace, IP cruda, sesión, cuenta o cliente; expira antes de 48h.';

-- Todas las relaciones son privadas. RLS queda habilitada sin policies y la API
-- no recibe siquiera privilegios de tabla: solo atraviesa RPC nominales.
alter table promocionar_p3_config enable row level security;
alter table promocionar_p3_config_bitacora enable row level security;
alter table atribucion_enlaces enable row level security;
alter table atribucion_clics_dia enable row level security;
alter table atribucion_limite_temporal enable row level security;

revoke all on table promocionar_p3_config
  from public, anon, authenticated, service_role;
revoke all on table promocionar_p3_config_bitacora
  from public, anon, authenticated, service_role;
revoke all on sequence promocionar_p3_config_bitacora_id_seq
  from public, anon, authenticated, service_role;
revoke all on table atribucion_enlaces
  from public, anon, authenticated, service_role;
revoke all on table atribucion_clics_dia
  from public, anon, authenticated, service_role;
revoke all on table atribucion_limite_temporal
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Helpers privados
-- ----------------------------------------------------------------------------

-- NFKD real, retiro de marcas combinantes, minúsculas y slug ASCII. Los rangos
-- cubren los bloques Unicode de marcas combinantes vigentes en PostgreSQL 15.
create function promocionar_p3__normalizar(p_texto text, p_maximo integer)
returns text
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_texto text;
begin
  if p_texto is null then
    return null;
  end if;
  if p_maximo is null or p_maximo < 1 or p_maximo > 512 then
    raise exception using errcode = '22023', message = 'P3_MAXIMO_NORMALIZACION_INVALIDO';
  end if;

  v_texto := lower(normalize(p_texto, NFKD));
  v_texto := regexp_replace(
    v_texto,
    U&'[\0300-\036F\1AB0-\1AFF\1DC0-\1DFF\20D0-\20FF\FE20-\FE2F]',
    '',
    'g'
  );
  -- Letras latinas que no siempre se expanden en una sola base bajo NFKD.
  v_texto := replace(v_texto, 'æ', 'ae');
  v_texto := replace(v_texto, 'œ', 'oe');
  v_texto := replace(v_texto, 'ß', 'ss');
  v_texto := translate(v_texto, 'łđðþøı', 'lddtoi');
  v_texto := regexp_replace(btrim(v_texto), '[^a-z0-9]+', '-', 'g');
  v_texto := trim(both '-' from v_texto);

  if v_texto = '' then
    return null;
  end if;

  v_texto := left(v_texto, p_maximo);
  v_texto := regexp_replace(v_texto, '-+$', '');
  return nullif(v_texto, '');
end;
$fn$;

comment on function promocionar_p3__normalizar(text, integer) is
  'Promocionar P3 · helper privado de normalización interoperable NFKD a [a-z0-9-], con truncado sin guion final.';
revoke all on function promocionar_p3__normalizar(text, integer)
  from public, anon, authenticated, service_role;

-- Detección prudente: bloquea señales evidentes antes de destruir separadores
-- mediante normalización. No pretende clasificar nombres propios por heurística.
create function promocionar_p3__contiene_pii(p_texto text)
returns boolean
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_crudo text := lower(coalesce(p_texto, ''));
  v_digitos text;
  v_normalizado text;
begin
  if p_texto is null then
    return false;
  end if;

  v_digitos := regexp_replace(v_crudo, '[^0-9]', '', 'g');
  v_normalizado := promocionar_p3__normalizar(left(v_crudo, 512), 512);

  return
    v_crudo ~ '[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}'
    or v_crudo ~ '(^|[^a-z0-9])@[a-z0-9._-]{2,}'
    or v_crudo ~ '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    or length(v_digitos) >= 7
    or coalesce(v_normalizado, '') ~ '(^|-)(audiencia|cliente|customer|persona|usuario|user|suscriptor|contacto|correo|email|telefono|celular|documento|cedula|identificacion)(-|$)';
end;
$fn$;

comment on function promocionar_p3__contiene_pii(text) is
  'Promocionar P3 · helper privado prudente para señales evidentes de correo, teléfono, UUID, handle o etiquetas de identidad/audiencia.';
revoke all on function promocionar_p3__contiene_pii(text)
  from public, anon, authenticated, service_role;

create function promocionar_p3__canal_utm(p_canal text)
returns jsonb
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_canal text := lower(btrim(coalesce(p_canal, '')));
begin
  if v_canal = 'whatsapp' then
    return jsonb_build_object('canal', 'whatsapp', 'source', 'whatsapp', 'medium', 'mensajeria');
  elsif v_canal = 'instagram' then
    return jsonb_build_object('canal', 'instagram', 'source', 'instagram', 'medium', 'social');
  elsif v_canal = 'facebook' then
    return jsonb_build_object('canal', 'facebook', 'source', 'facebook', 'medium', 'social');
  elsif v_canal = 'email' then
    return jsonb_build_object('canal', 'email', 'source', 'email', 'medium', 'email');
  elsif v_canal = 'qr' then
    return jsonb_build_object('canal', 'qr', 'source', 'qr', 'medium', 'offline');
  elsif v_canal = 'anuncio_manual' then
    return jsonb_build_object('canal', 'anuncio_manual', 'source', 'anuncio-manual', 'medium', 'paid-manual');
  elsif v_canal = 'otro_controlado' then
    return jsonb_build_object('canal', 'otro_controlado', 'source', 'otro-controlado', 'medium', 'referral');
  end if;
  raise exception using errcode = '22023', message = 'P3_CANAL_INVALIDO';
end;
$fn$;

comment on function promocionar_p3__canal_utm(text) is
  'Promocionar P3 · helper privado: única tabla de verdad para los siete pares canal/source/medium.';
revoke all on function promocionar_p3__canal_utm(text)
  from public, anon, authenticated, service_role;

-- Cada carácter toma exactamente cinco bits de gen_random_bytes. Para 4 se usan
-- 20 bits de 3 bytes; para 16, los 80 bits completos. No hay módulo ni sesgo.
create function promocionar_p3__crockford(p_longitud integer)
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $fn$
declare
  v_alfabeto constant text := '0123456789abcdefghjkmnpqrstvwxyz';
  v_bytes bytea;
  v_salida text := '';
  v_i integer;
  v_j integer;
  v_valor integer;
begin
  if p_longitud not in (4, 16) then
    raise exception using errcode = '22023', message = 'P3_LONGITUD_CROCKFORD_INVALIDA';
  end if;

  v_bytes := gen_random_bytes(((p_longitud * 5) + 7) / 8);
  for v_i in 0..(p_longitud - 1) loop
    v_valor := 0;
    for v_j in 0..4 loop
      v_valor := (v_valor * 2) + get_bit(v_bytes, (v_i * 5) + v_j);
    end loop;
    v_salida := v_salida || substr(v_alfabeto, v_valor + 1, 1);
  end loop;
  return v_salida;
end;
$fn$;

comment on function promocionar_p3__crockford(integer) is
  'Promocionar P3 · helper criptográfico uniforme: Crockford minúsculo de 4/20 bits o 16/80 bits mediante gen_random_bytes.';
revoke all on function promocionar_p3__crockford(integer)
  from public, anon, authenticated, service_role;

create function promocionar_p3__campaign_candidato(p_base text)
returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_base text := promocionar_p3__normalizar(p_base, 48);
begin
  if v_base is null or v_base is distinct from p_base then
    raise exception using errcode = '22023', message = 'P3_CAMPAIGN_BASE_NO_CANONICA';
  end if;
  return v_base || '-'
    || to_char(statement_timestamp() at time zone 'America/Bogota', 'YYMMDD')
    || '-' || promocionar_p3__crockford(4);
end;
$fn$;

comment on function promocionar_p3__campaign_candidato(text) is
  'Promocionar P3 · helper privado: base normalizada + fecha Colombia aammdd + 20 bits Crockford.';
revoke all on function promocionar_p3__campaign_candidato(text)
  from public, anon, authenticated, service_role;

-- JSON de lista blanca para administración. Omite claves de idempotencia,
-- actores y cualquier campo interno de cuota. `resoluble` refleja la salida
-- autoritativa vigente para que listar permita revalidar antes de distribuir.
create function promocionar_p3__enlace_json(p_enlace atribucion_enlaces)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_detalle bigint;
  v_total bigint;
  v_resoluble boolean;
begin
  select coalesce(sum(d.total), 0)::bigint
    into v_detalle
    from atribucion_clics_dia d
   where d.enlace_id = p_enlace.id;
  v_total := p_enlace.total_aproximado_historico + v_detalle;

  select exists (
    select 1
      from promocionar_p3_config c
     where c.id = 1
       and p_enlace.estado_enlace = 'activo'
       and c.redirect_habilitado
       and c.routing_verificado
       and (
         p_enlace.tipo_destino = 'home_v1'
         or (
           p_enlace.tipo_destino = 'producto_v1'
           and exists (
             select 1
               from campana_producto cp
              where cp.id = p_enlace.campana_producto_id
                and cp.activo and cp.publicado and not cp.es_placeholder
                and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
                and length(cp.slug) between 1 and 180
           )
         )
       )
  ) into v_resoluble;

  return jsonb_build_object(
    'id', p_enlace.id,
    'codigo', p_enlace.codigo,
    'url_corta', case when p_enlace.codigo is null then null
                      else 'https://go.magandhi.com/' || p_enlace.codigo end,
    'campana_producto_id', p_enlace.campana_producto_id,
    'canal_promocion', p_enlace.canal_promocion,
    'source', p_enlace.source,
    'medium', p_enlace.medium,
    'campaign_base', p_enlace.campaign_base,
    'campaign', p_enlace.campaign,
    'content', p_enlace.content,
    'tipo_destino', p_enlace.tipo_destino,
    'estado_enlace', p_enlace.estado_enlace,
    'resoluble', v_resoluble,
    'reemplaza_enlace_id', p_enlace.reemplaza_enlace_id,
    'total_aproximado_historico', p_enlace.total_aproximado_historico,
    'total_aproximado', v_total,
    'creado_en', p_enlace.creado_en,
    'actualizado_en', p_enlace.actualizado_en,
    'activado_en', p_enlace.activado_en,
    'desactivado_en', p_enlace.desactivado_en
  );
end;
$fn$;

comment on function promocionar_p3__enlace_json(atribucion_enlaces) is
  'Promocionar P3 · helper privado de JSON administrativo seguro con resolubilidad vigente, sin actores ni clave de idempotencia.';
revoke all on function promocionar_p3__enlace_json(atribucion_enlaces)
  from public, anon, authenticated, service_role;

-- El singleton no puede borrarse ni perder coherencia aunque una escritura de
-- mantenimiento evite los scripts operativos. Todo cambio de gates/evidencia
-- debe adelantar la versión y aportar una razón nueva.
create function promocionar_p3__proteger_config()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_cambio_relevante boolean;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_NO_ELIMINABLE';
  end if;
  if new.id <> 1 or (tg_op = 'UPDATE' and new.id is distinct from old.id) then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_SINGLETON_INVALIDO';
  end if;
  if new.url_corta_base <> 'https://go.magandhi.com' or new.cuota_hora <> 600 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_DECISION_CERRADA';
  end if;
  if (
       (new.activacion_habilitada or new.redirect_habilitado or new.conteo_habilitado)
       and not new.routing_verificado
     )
     or (new.activacion_habilitada and not new.redirect_habilitado)
     or (new.conteo_habilitado and not new.redirect_habilitado) then
    raise exception using errcode = 'P0001', message = 'P3_GATES_INCOMPLETOS';
  end if;

  if new.actualizado_razon is null
     or new.actualizado_razon <> btrim(new.actualizado_razon)
     or length(new.actualizado_razon) not between 1 and 500
     or new.actualizado_rol is null
     or new.actualizado_rol <> btrim(new.actualizado_rol)
     or length(new.actualizado_rol) not between 1 and 120 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_AUDITORIA_INVALIDA';
  end if;

  if tg_op = 'UPDATE' then
    v_cambio_relevante := row(
      new.activacion_habilitada, new.redirect_habilitado, new.conteo_habilitado,
      new.politica_publicada, new.routing_verificado, new.politica_version
    ) is distinct from row(
      old.activacion_habilitada, old.redirect_habilitado, old.conteo_habilitado,
      old.politica_publicada, old.routing_verificado, old.politica_version
    );

    if not v_cambio_relevante then
      raise exception using errcode = 'P0001', message = 'P3_CONFIG_SIN_CAMBIO_RELEVANTE';
    end if;
    if new.actualizado_en <= old.actualizado_en
       or new.actualizado_razon is not distinct from old.actualizado_razon
       or new.actualizado_por is distinct from auth.uid() then
      raise exception using errcode = 'P0001', message = 'P3_CONFIG_RAZON_O_ACTOR_REQUERIDO';
    end if;
  end if;
  return new;
end;
$fn$;

comment on function promocionar_p3__proteger_config() is
  'Promocionar P3 · trigger privado: singleton/gates coherentes y razón/actor obligatorios por cambio relevante.';
revoke all on function promocionar_p3__proteger_config()
  from public, anon, authenticated, service_role;

create trigger trg_promocionar_p3_proteger_config
before insert or update or delete on promocionar_p3_config
for each row execute function promocionar_p3__proteger_config();

create function promocionar_p3__auditar_config()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  insert into public.promocionar_p3_config_bitacora (
    registrado_en, actor_uid, actor_rol, razon,
    antes_activacion_habilitada, despues_activacion_habilitada,
    antes_redirect_habilitado, despues_redirect_habilitado,
    antes_conteo_habilitado, despues_conteo_habilitado,
    antes_politica_publicada, despues_politica_publicada,
    antes_routing_verificado, despues_routing_verificado,
    antes_politica_version, despues_politica_version
  ) values (
    statement_timestamp(), auth.uid(), new.actualizado_rol, new.actualizado_razon,
    old.activacion_habilitada, new.activacion_habilitada,
    old.redirect_habilitado, new.redirect_habilitado,
    old.conteo_habilitado, new.conteo_habilitado,
    old.politica_publicada, new.politica_publicada,
    old.routing_verificado, new.routing_verificado,
    old.politica_version, new.politica_version
  );
  return new;
end;
$fn$;

comment on function promocionar_p3__auditar_config() is
  'Promocionar P3 · AFTER UPDATE append-only con before/after de gates y evidencia.';
revoke all on function promocionar_p3__auditar_config()
  from public, anon, authenticated, service_role;

create trigger trg_promocionar_p3_auditar_config
after update on promocionar_p3_config
for each row execute function promocionar_p3__auditar_config();

create function promocionar_p3__proteger_config_bitacora()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  raise exception using errcode = 'P0001', message = 'P3_CONFIG_BITACORA_APPEND_ONLY';
end;
$fn$;

comment on function promocionar_p3__proteger_config_bitacora() is
  'Promocionar P3 · bloquea UPDATE, DELETE y TRUNCATE del historial de configuración.';
revoke all on function promocionar_p3__proteger_config_bitacora()
  from public, anon, authenticated, service_role;

create trigger trg_promocionar_p3_proteger_config_bitacora
before update or delete or truncate on promocionar_p3_config_bitacora
for each statement execute function promocionar_p3__proteger_config_bitacora();

-- Defensa de última línea para estados, normalización, reemplazos, auditoría e
-- inmutabilidad. Las RPC no son la única autoridad: el trigger también cierra
-- escrituras privilegiadas accidentales.
create function promocionar_p3__validar_enlace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_utm jsonb;
  v_reemplazado atribucion_enlaces%rowtype;
begin
  if tg_op = 'DELETE' then
    if old.estado_enlace <> 'borrador' or old.codigo is not null then
      raise exception using errcode = 'P0001', message = 'P3_SOLO_BORRADOR_SE_ELIMINA';
    end if;
    return old;
  end if;

  v_utm := promocionar_p3__canal_utm(new.canal_promocion);
  if new.canal_promocion is distinct from (v_utm ->> 'canal')
     or new.source is distinct from (v_utm ->> 'source')
     or new.medium is distinct from (v_utm ->> 'medium') then
    raise exception using errcode = 'P0001', message = 'P3_PAR_CANAL_UTM_INVALIDO';
  end if;

  if new.campaign_base is distinct from promocionar_p3__normalizar(new.campaign_base, 48)
     or promocionar_p3__contiene_pii(new.campaign_base) then
    raise exception using errcode = 'P0001', message = 'P3_CAMPAIGN_BASE_INVALIDA';
  end if;
  if new.content is not null and (
       new.content is distinct from promocionar_p3__normalizar(new.content, 60)
       or promocionar_p3__contiene_pii(new.content)
     ) then
    raise exception using errcode = 'P0001', message = 'P3_CONTENT_INVALIDO';
  end if;
  if new.campaign !~ '^[a-z0-9]+(-[a-z0-9]+)*-[0-9]{6}-[0-9a-hjkmnp-tv-z]{4}$'
     or length(new.campaign) <> length(new.campaign_base) + 12
     or left(new.campaign, length(new.campaign_base) + 1) <> new.campaign_base || '-' then
    raise exception using errcode = 'P0001', message = 'P3_CAMPAIGN_FINAL_INVALIDA';
  end if;

  if new.tipo_destino not in ('producto_v1', 'home_v1') then
    raise exception using errcode = 'P0001', message = 'P3_TIPO_DESTINO_INVALIDO';
  end if;
  if new.campana_producto_id is null
     or not exists (
       select 1 from public.campana_producto cp
        where cp.id = new.campana_producto_id
     ) then
    raise exception using errcode = '23503', message = 'P3_CAMPANA_ORIGEN_INEXISTENTE';
  end if;

  if new.reemplaza_enlace_id is not null then
    if new.reemplaza_enlace_id = new.id then
      raise exception using errcode = 'P0001', message = 'P3_AUTORREEMPLAZO_INVALIDO';
    end if;
    select * into v_reemplazado
      from public.atribucion_enlaces
     where id = new.reemplaza_enlace_id;
    if not found
       or v_reemplazado.estado_enlace <> 'desactivado'
       or v_reemplazado.campana_producto_id is distinct from new.campana_producto_id then
      raise exception using errcode = 'P0001', message = 'P3_REEMPLAZO_INVALIDO';
    end if;
  end if;

  if new.total_aproximado_historico < 0
     or new.idempotencia_payload_hash !~ '^[0-9a-f]{64}$'
     or new.creado_por is null
     or new.creado_en is null
     or new.actualizado_en is null
     or new.actualizado_en < new.creado_en then
    raise exception using errcode = 'P0001', message = 'P3_AUDITORIA_INVALIDA';
  end if;

  if tg_op = 'INSERT' then
    if new.estado_enlace <> 'borrador'
       or new.codigo is not null
       or new.total_aproximado_historico <> 0
       or new.activado_en is not null or new.activado_por is not null
       or new.desactivado_en is not null or new.desactivado_por is not null then
      raise exception using errcode = 'P0001', message = 'P3_ALTA_DEBE_SER_BORRADOR';
    end if;
    return new;
  end if;

  -- Identidad, idempotencia y creación jamás cambian.
  if row(new.id, new.clave_idempotencia, new.idempotencia_payload_hash,
         new.creado_en, new.creado_por)
       is distinct from
     row(old.id, old.clave_idempotencia, old.idempotencia_payload_hash,
         old.creado_en, old.creado_por) then
    raise exception using errcode = 'P0001', message = 'P3_IDENTIDAD_INMUTABLE';
  end if;
  if new.actualizado_en < old.actualizado_en
     or new.total_aproximado_historico < old.total_aproximado_historico then
    raise exception using errcode = 'P0001', message = 'P3_AUDITORIA_O_TOTAL_REGRESIVO';
  end if;

  if old.estado_enlace = 'borrador' then
    if new.estado_enlace = 'desactivado' then
      raise exception using errcode = 'P0001', message = 'P3_TRANSICION_INVALIDA';
    elsif new.estado_enlace = 'borrador' then
      if new.campana_producto_id is distinct from old.campana_producto_id then
        raise exception using errcode = 'P0001', message = 'P3_CAMPANA_ORIGEN_INMUTABLE';
      end if;
      if new.reemplaza_enlace_id is distinct from old.reemplaza_enlace_id then
        raise exception using errcode = 'P0001', message = 'P3_GENEALOGIA_INMUTABLE';
      end if;
      if new.codigo is not null
         or new.total_aproximado_historico <> 0
         or new.activado_en is not null or new.activado_por is not null
         or new.desactivado_en is not null or new.desactivado_por is not null then
        raise exception using errcode = 'P0001', message = 'P3_BORRADOR_INVALIDO';
      end if;
    elsif new.estado_enlace = 'activo' then
      if row(new.campana_producto_id, new.canal_promocion, new.source,
             new.medium, new.campaign_base, new.campaign, new.content,
             new.tipo_destino, new.reemplaza_enlace_id)
           is distinct from
         row(old.campana_producto_id, old.canal_promocion, old.source,
             old.medium, old.campaign_base, old.campaign, old.content,
             old.tipo_destino, old.reemplaza_enlace_id) then
        raise exception using errcode = 'P0001', message = 'P3_ACTIVACION_NO_EDITA_BORRADOR';
      end if;
      if new.codigo is null or new.codigo !~ '^[0-9a-hjkmnp-tv-z]{16}$'
         or new.activado_en is null or new.activado_por is null
         or new.desactivado_en is not null or new.desactivado_por is not null
         or not exists (
           select 1 from promocionar_p3_config c
            where c.id = 1 and c.activacion_habilitada
              and c.redirect_habilitado and c.routing_verificado
         ) then
        raise exception using errcode = 'P0001', message = 'P3_ACTIVACION_SIN_GATES_O_CODIGO';
      end if;
      if new.tipo_destino = 'producto_v1' and not exists (
        select 1
          from campana_producto cp
         where cp.id = new.campana_producto_id
           and cp.activo and cp.publicado and not cp.es_placeholder
           and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
           and length(cp.slug) between 1 and 180
      ) then
        raise exception using errcode = 'P0001', message = 'P3_CAMPANA_NO_PUBLICABLE';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'P3_ESTADO_INVALIDO';
    end if;

  elsif old.estado_enlace = 'activo' then
    -- Campos de negocio y activación quedan congelados. Solo se admite el
    -- rollup técnico o la transición terminal a desactivado.
    if row(new.id, new.codigo, new.campana_producto_id, new.canal_promocion,
           new.source, new.medium, new.campaign_base, new.campaign, new.content,
           new.tipo_destino, new.clave_idempotencia, new.reemplaza_enlace_id,
           new.creado_en, new.creado_por, new.activado_en, new.activado_por)
         is distinct from
       row(old.id, old.codigo, old.campana_producto_id, old.canal_promocion,
           old.source, old.medium, old.campaign_base, old.campaign, old.content,
           old.tipo_destino, old.clave_idempotencia, old.reemplaza_enlace_id,
           old.creado_en, old.creado_por, old.activado_en, old.activado_por) then
      raise exception using errcode = 'P0001', message = 'P3_ENLACE_ACTIVO_INMUTABLE';
    end if;
    if new.estado_enlace = 'activo' then
      if new.desactivado_en is not null or new.desactivado_por is not null then
        raise exception using errcode = 'P0001', message = 'P3_DESACTIVACION_INCOMPLETA';
      end if;
    elsif new.estado_enlace = 'desactivado' then
      if new.desactivado_en is null or new.desactivado_por is null
         or new.desactivado_en < new.activado_en then
        raise exception using errcode = 'P0001', message = 'P3_DESACTIVACION_INVALIDA';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'P3_NO_REACTIVABLE';
    end if;

  elsif old.estado_enlace = 'desactivado' then
    if new.estado_enlace <> 'desactivado'
       or row(new.id, new.codigo, new.campana_producto_id, new.canal_promocion,
              new.source, new.medium, new.campaign_base, new.campaign, new.content,
              new.tipo_destino, new.clave_idempotencia, new.reemplaza_enlace_id,
              new.creado_en, new.creado_por, new.activado_en, new.activado_por,
              new.desactivado_en, new.desactivado_por)
            is distinct from
          row(old.id, old.codigo, old.campana_producto_id, old.canal_promocion,
              old.source, old.medium, old.campaign_base, old.campaign, old.content,
              old.tipo_destino, old.clave_idempotencia, old.reemplaza_enlace_id,
              old.creado_en, old.creado_por, old.activado_en, old.activado_por,
              old.desactivado_en, old.desactivado_por) then
      raise exception using errcode = 'P0001', message = 'P3_DESACTIVADO_TERMINAL';
    end if;
  else
    raise exception using errcode = 'P0001', message = 'P3_ESTADO_HISTORICO_INVALIDO';
  end if;

  return new;
end;
$fn$;

comment on function promocionar_p3__validar_enlace() is
  'Promocionar P3 · trigger privado: normalización, destino/reemplazo, ciclo terminal, inmutabilidad, no borrado y auditoría.';
revoke all on function promocionar_p3__validar_enlace()
  from public, anon, authenticated, service_role;

create trigger trg_promocionar_p3_validar_enlace
before insert or update or delete on atribucion_enlaces
for each row execute function promocionar_p3__validar_enlace();

-- ----------------------------------------------------------------------------
-- RPC autenticadas de Marketing
-- ----------------------------------------------------------------------------
create function promocionar_p3_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_salida jsonb;
begin
  if not tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  select jsonb_build_object(
    'construido', true,
    'activo', c.redirect_habilitado,
    'activacion_habilitada', c.activacion_habilitada,
    'redirect_habilitado', c.redirect_habilitado,
    'conteo_habilitado', c.conteo_habilitado,
    'politica_publicada', c.politica_publicada,
    'routing_verificado', c.routing_verificado,
    'politica_version', c.politica_version,
    'url_corta_base', c.url_corta_base,
    'cuota_hora', c.cuota_hora,
    'razon_bloqueo', case
      when not c.routing_verificado then 'ROUTING_NO_VERIFICADO'
      when not c.redirect_habilitado then 'REDIRECT_APAGADO'
      when not c.activacion_habilitada then 'ACTIVACION_APAGADA'
      when not c.conteo_habilitado then 'CONTEO_APAGADO'
      else null
    end,
    'actualizado_en', c.actualizado_en
  ) into v_salida
  from promocionar_p3_config c where c.id = 1;
  if v_salida is null then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_AUSENTE';
  end if;
  return v_salida;
end;
$fn$;

revoke all on function promocionar_p3_config()
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_config() to authenticated;

create function promocionar_p3_listar(p_campana_producto_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_salida jsonb;
begin
  if not tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  select coalesce(
    jsonb_agg(promocionar_p3__enlace_json(e) order by e.creado_en desc, e.id),
    '[]'::jsonb
  ) into v_salida
  from atribucion_enlaces e
  where p_campana_producto_id is null
     or e.campana_producto_id = p_campana_producto_id;
  return v_salida;
end;
$fn$;

revoke all on function promocionar_p3_listar(uuid)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_listar(uuid) to authenticated;

create function promocionar_p3_crear_borrador(
  p_campana_producto_id uuid,
  p_tipo_destino text,
  p_canal_promocion text,
  p_campaign_base text,
  p_content text,
  p_clave_idempotencia uuid,
  p_reemplaza_enlace_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $fn$
declare
  v_actor uuid;
  v_utm jsonb;
  v_canal text;
  v_source text;
  v_medium text;
  v_base text;
  v_content text;
  v_tipo text;
  v_payload_hash text;
  v_campaign text;
  v_enlace public.atribucion_enlaces%rowtype;
  v_restriccion text;
  v_intento integer;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  v_actor := auth.uid();
  if v_actor is null then
    raise exception using errcode = '42501', message = 'P3_IDENTIDAD_AUTENTICADA_REQUERIDA';
  end if;
  if p_campana_producto_id is null then
    raise exception using errcode = '22023', message = 'P3_CAMPANA_ORIGEN_REQUERIDA';
  end if;
  if p_tipo_destino is null
     or p_tipo_destino <> btrim(p_tipo_destino)
     or p_tipo_destino not in ('producto_v1', 'home_v1') then
    raise exception using errcode = '22023', message = 'P3_TIPO_DESTINO_INVALIDO';
  end if;
  if p_clave_idempotencia is null then
    raise exception using errcode = '22023', message = 'P3_CLAVE_IDEMPOTENCIA_REQUERIDA';
  end if;
  if length(coalesce(p_campaign_base, '')) > 512
     or length(coalesce(p_content, '')) > 512
     or public.promocionar_p3__contiene_pii(p_campaign_base)
     or public.promocionar_p3__contiene_pii(p_content) then
    raise exception using errcode = '22023', message = 'P3_TEXTO_CON_PII_O_EXCESIVO';
  end if;
  if not exists (
    select 1 from public.campana_producto cp
     where cp.id = p_campana_producto_id
  ) then
    raise exception using errcode = '23503', message = 'P3_CAMPANA_ORIGEN_INEXISTENTE';
  end if;

  v_tipo := p_tipo_destino;
  v_utm := public.promocionar_p3__canal_utm(p_canal_promocion);
  v_canal := v_utm ->> 'canal';
  v_source := v_utm ->> 'source';
  v_medium := v_utm ->> 'medium';
  v_base := public.promocionar_p3__normalizar(p_campaign_base, 48);
  if v_base is null then
    raise exception using errcode = '22023', message = 'P3_CAMPAIGN_BASE_REQUERIDA';
  end if;

  if p_content is null or btrim(p_content) = '' then
    v_content := null;
  else
    v_content := public.promocionar_p3__normalizar(p_content, 60);
    if v_content is null then
      raise exception using errcode = '22023', message = 'P3_CONTENT_VACIO_TRAS_NORMALIZAR';
    end if;
  end if;

  v_payload_hash := encode(digest(jsonb_build_object(
    'campana_producto_id', p_campana_producto_id,
    'tipo_destino', v_tipo,
    'canal_promocion', v_canal,
    'campaign_base', v_base,
    'content', v_content,
    'reemplaza_enlace_id', p_reemplaza_enlace_id
  )::text, 'sha256'), 'hex');

  -- Serializa la misma clave aun antes del INSERT; la UNIQUE sigue siendo la
  -- autoridad final frente a cualquier escritor fuera de esta RPC.
  perform pg_advisory_xact_lock(hashtextextended(
    'promocionar-p3-idem:' || v_actor::text || ':' || p_clave_idempotencia::text,
    0
  ));

  select * into v_enlace
    from public.atribucion_enlaces e
   where e.clave_idempotencia = p_clave_idempotencia
     and e.creado_por = v_actor;
  if found then
    if v_enlace.idempotencia_payload_hash is distinct from v_payload_hash then
      raise exception using errcode = '22023', message = 'P3_IDEMPOTENCIA_PAYLOAD_DIFERENTE';
    end if;
    return public.promocionar_p3__enlace_json(v_enlace);
  end if;

  -- La fecha y los 20 bits nacen en servidor. Una colisión del UNIQUE de
  -- campaign reintenta sin alterar la base; 64 intentos es un límite defensivo.
  for v_intento in 1..64 loop
    v_campaign := public.promocionar_p3__campaign_candidato(v_base);
    begin
      insert into public.atribucion_enlaces (
        campana_producto_id, canal_promocion, source, medium,
        campaign_base, campaign, content, tipo_destino, estado_enlace,
        clave_idempotencia, idempotencia_payload_hash, reemplaza_enlace_id,
        creado_por, actualizado_por
      ) values (
        p_campana_producto_id, v_canal, v_source, v_medium,
        v_base, v_campaign, v_content, v_tipo, 'borrador',
        p_clave_idempotencia, v_payload_hash, p_reemplaza_enlace_id,
        v_actor, v_actor
      ) returning * into v_enlace;
      return public.promocionar_p3__enlace_json(v_enlace);
    exception when unique_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      if v_restriccion = 'atribucion_enlaces_campaign_unico' then
        null; -- regenerar xxxx
      elsif v_restriccion = 'atribucion_enlaces_idempotencia_unica' then
        select * into v_enlace
          from public.atribucion_enlaces e
         where e.clave_idempotencia = p_clave_idempotencia
           and e.creado_por = v_actor;
        if found
           and v_enlace.idempotencia_payload_hash is not distinct from v_payload_hash then
          return public.promocionar_p3__enlace_json(v_enlace);
        end if;
        raise exception using errcode = '22023', message = 'P3_IDEMPOTENCIA_PAYLOAD_DIFERENTE';
      else
        raise;
      end if;
    end;
  end loop;
  raise exception using errcode = 'P0001', message = 'P3_CAMPAIGN_COLISIONES_AGOTADAS';
end;
$fn$;

revoke all on function promocionar_p3_crear_borrador(uuid, text, text, text, text, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_crear_borrador(uuid, text, text, text, text, uuid, uuid)
  to authenticated;

create function promocionar_p3_editar_borrador(
  p_enlace_id uuid,
  p_actualizado_en_esperado timestamptz,
  p_tipo_destino text,
  p_canal_promocion text,
  p_campaign_base text,
  p_content text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_actor uuid;
  v_utm jsonb;
  v_base text;
  v_content text;
  v_campaign text;
  v_nuevo_actualizado_en timestamptz;
  v_enlace public.atribucion_enlaces%rowtype;
  v_restriccion text;
  v_intento integer;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  v_actor := auth.uid();
  if v_actor is null then
    raise exception using errcode = '42501', message = 'P3_IDENTIDAD_AUTENTICADA_REQUERIDA';
  end if;
  if p_enlace_id is null
     or p_actualizado_en_esperado is null
     or p_tipo_destino is null
     or p_tipo_destino <> btrim(p_tipo_destino)
     or p_tipo_destino not in ('producto_v1', 'home_v1')
     or length(coalesce(p_campaign_base, '')) > 512
     or length(coalesce(p_content, '')) > 512
     or public.promocionar_p3__contiene_pii(p_campaign_base)
     or public.promocionar_p3__contiene_pii(p_content) then
    raise exception using errcode = '22023', message = 'P3_EDICION_INVALIDA';
  end if;

  v_utm := public.promocionar_p3__canal_utm(p_canal_promocion);
  v_base := public.promocionar_p3__normalizar(p_campaign_base, 48);
  if v_base is null then
    raise exception using errcode = '22023', message = 'P3_CAMPAIGN_BASE_REQUERIDA';
  end if;
  if p_content is null or btrim(p_content) = '' then
    v_content := null;
  else
    v_content := public.promocionar_p3__normalizar(p_content, 60);
    if v_content is null then
      raise exception using errcode = '22023', message = 'P3_CONTENT_VACIO_TRAS_NORMALIZAR';
    end if;
  end if;

  select * into v_enlace
    from public.atribucion_enlaces e
   where e.id = p_enlace_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'P3_ENLACE_NO_ENCONTRADO';
  end if;
  if v_enlace.estado_enlace <> 'borrador' then
    raise exception using errcode = 'P0001', message = 'P3_SOLO_BORRADOR_EDITABLE';
  end if;
  if v_enlace.actualizado_en is distinct from p_actualizado_en_esperado then
    raise exception using errcode = 'P0001', message = 'P3_BORRADOR_VERSION_CONFLICTO';
  end if;

  v_nuevo_actualizado_en := greatest(
    clock_timestamp(), p_actualizado_en_esperado + interval '1 microsecond'
  );

  if v_enlace.campaign_base = v_base then
    update public.atribucion_enlaces
       set tipo_destino = p_tipo_destino,
           canal_promocion = v_utm ->> 'canal',
           source = v_utm ->> 'source',
           medium = v_utm ->> 'medium',
           content = v_content,
           actualizado_en = v_nuevo_actualizado_en,
           actualizado_por = v_actor
     where id = p_enlace_id
       and estado_enlace = 'borrador'
       and actualizado_en = p_actualizado_en_esperado
     returning * into v_enlace;
    if not found then
      raise exception using errcode = 'P0001', message = 'P3_BORRADOR_VERSION_CONFLICTO';
    end if;
    return public.promocionar_p3__enlace_json(v_enlace);
  end if;

  for v_intento in 1..64 loop
    v_campaign := public.promocionar_p3__campaign_candidato(v_base);
    begin
      update public.atribucion_enlaces
         set tipo_destino = p_tipo_destino,
             canal_promocion = v_utm ->> 'canal',
             source = v_utm ->> 'source',
             medium = v_utm ->> 'medium',
             campaign_base = v_base,
             campaign = v_campaign,
             content = v_content,
             actualizado_en = v_nuevo_actualizado_en,
             actualizado_por = v_actor
       where id = p_enlace_id
         and estado_enlace = 'borrador'
         and actualizado_en = p_actualizado_en_esperado
       returning * into v_enlace;
      if not found then
        raise exception using errcode = 'P0001', message = 'P3_BORRADOR_VERSION_CONFLICTO';
      end if;
      return public.promocionar_p3__enlace_json(v_enlace);
    exception when unique_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      if v_restriccion <> 'atribucion_enlaces_campaign_unico' then
        raise;
      end if;
    end;
  end loop;
  raise exception using errcode = 'P0001', message = 'P3_CAMPAIGN_COLISIONES_AGOTADAS';
end;
$fn$;

revoke all on function promocionar_p3_editar_borrador(uuid, timestamptz, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_editar_borrador(uuid, timestamptz, text, text, text, text)
  to authenticated;

create function promocionar_p3_activar(p_enlace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_actor uuid;
  v_enlace atribucion_enlaces%rowtype;
  v_codigo text;
  v_restriccion text;
  v_intento integer;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  v_actor := auth.uid();
  if v_actor is null then
    raise exception using errcode = '42501', message = 'P3_IDENTIDAD_AUTENTICADA_REQUERIDA';
  end if;

  -- Primero bloquea el enlace: repetir sobre un activo devuelve exactamente su
  -- JSON actual aun si los gates se apagaron después. Desactivado es terminal.
  select * into v_enlace
    from public.atribucion_enlaces e
   where e.id = p_enlace_id
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'P3_ENLACE_NO_ENCONTRADO';
  end if;
  if v_enlace.estado_enlace = 'activo' then
    return public.promocionar_p3__enlace_json(v_enlace);
  elsif v_enlace.estado_enlace = 'desactivado' then
    raise exception using errcode = 'P0001', message = 'P3_ENLACE_DESACTIVADO_NO_REACTIVABLE';
  elsif v_enlace.estado_enlace <> 'borrador' then
    raise exception using errcode = 'P0001', message = 'P3_ESTADO_ENLACE_INVALIDO';
  end if;

  -- FOR SHARE serializa la primera activación con el apagado operacional.
  perform 1
    from public.promocionar_p3_config c
   where c.id = 1 and c.activacion_habilitada and c.redirect_habilitado
     and c.routing_verificado
   for share;
  if not found then
    raise exception using errcode = 'P0001', message = 'P3_GATES_NO_AUTORIZAN_ACTIVAR';
  end if;

  if v_enlace.tipo_destino = 'producto_v1' then
    perform 1
      from campana_producto cp
     where cp.id = v_enlace.campana_producto_id
       and cp.activo and cp.publicado and not cp.es_placeholder
       and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       and length(cp.slug) between 1 and 180
     for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'P3_CAMPANA_NO_PUBLICABLE';
    end if;
  end if;

  -- El UNIQUE es la reserva final. Una colisión de los 80 bits regenera el
  -- código en una subtransacción; ninguna otra columna queda parcialmente mutada.
  for v_intento in 1..64 loop
    v_codigo := promocionar_p3__crockford(16);
    begin
      update public.atribucion_enlaces
         set codigo = v_codigo,
             estado_enlace = 'activo',
             activado_en = statement_timestamp(),
             activado_por = v_actor,
             actualizado_en = greatest(
               clock_timestamp(), v_enlace.actualizado_en + interval '1 microsecond'
             ),
             actualizado_por = v_actor
       where id = p_enlace_id
         and estado_enlace = 'borrador'
       returning * into v_enlace;
      return public.promocionar_p3__enlace_json(v_enlace);
    exception when unique_violation then
      get stacked diagnostics v_restriccion = constraint_name;
      if v_restriccion <> 'atribucion_enlaces_codigo_unico' then
        raise;
      end if;
    end;
  end loop;
  raise exception using errcode = 'P0001', message = 'P3_CODIGO_COLISIONES_AGOTADAS';
end;
$fn$;

revoke all on function promocionar_p3_activar(uuid)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_activar(uuid) to authenticated;

create function promocionar_p3_desactivar(p_enlace_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_actor uuid;
  v_enlace atribucion_enlaces%rowtype;
begin
  if not tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  v_actor := auth.uid();
  if v_actor is null then
    raise exception using errcode = '42501', message = 'P3_IDENTIDAD_AUTENTICADA_REQUERIDA';
  end if;

  select * into v_enlace from atribucion_enlaces where id = p_enlace_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'P3_ENLACE_NO_ENCONTRADO';
  end if;
  if v_enlace.estado_enlace = 'borrador' then
    raise exception using errcode = 'P0001', message = 'P3_BORRADOR_NO_SE_DESACTIVA';
  elsif v_enlace.estado_enlace = 'desactivado' then
    return promocionar_p3__enlace_json(v_enlace);
  end if;

  update public.atribucion_enlaces
     set estado_enlace = 'desactivado',
         desactivado_en = greatest(clock_timestamp(), v_enlace.activado_en),
         desactivado_por = v_actor,
         actualizado_en = greatest(
           clock_timestamp(), v_enlace.actualizado_en + interval '1 microsecond'
         ),
         actualizado_por = v_actor
   where id = p_enlace_id and estado_enlace = 'activo'
   returning * into v_enlace;
  return public.promocionar_p3__enlace_json(v_enlace);
end;
$fn$;

revoke all on function promocionar_p3_desactivar(uuid)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_desactivar(uuid) to authenticated;

create function promocionar_p3_eliminar_borrador(p_enlace_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_enlace atribucion_enlaces%rowtype;
  v_eliminado uuid;
begin
  if not tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P3_ACCESO_MARKETING_REQUERIDO';
  end if;
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'P3_IDENTIDAD_AUTENTICADA_REQUERIDA';
  end if;

  select * into v_enlace from atribucion_enlaces where id = p_enlace_id for update;
  if not found then
    return false;
  end if;
  if v_enlace.estado_enlace <> 'borrador' or v_enlace.codigo is not null then
    raise exception using errcode = 'P0001', message = 'P3_SOLO_BORRADOR_SE_ELIMINA';
  end if;

  delete from atribucion_enlaces where id = p_enlace_id returning id into v_eliminado;
  return v_eliminado is not null;
end;
$fn$;

revoke all on function promocionar_p3_eliminar_borrador(uuid)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_eliminar_borrador(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- RPC exclusivas de service_role. Resolver y contar son llamadas separadas:
-- cualquier error/timeout del contador no puede deshacer una resolución previa.
-- ----------------------------------------------------------------------------
create function promocionar_p3_resolver(p_codigo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_enlace atribucion_enlaces%rowtype;
  v_slug text;
  v_destino text;
begin
  if p_codigo is null or p_codigo !~ '^[0-9a-hjkmnp-tv-z]{16}$' then
    return null;
  end if;
  if not exists (
    select 1 from promocionar_p3_config c
     where c.id = 1 and c.redirect_habilitado
       and c.routing_verificado
  ) then
    return null;
  end if;

  select * into v_enlace
    from atribucion_enlaces e
   where e.codigo = p_codigo and e.estado_enlace = 'activo';
  if not found then
    return null;
  end if;

  if v_enlace.tipo_destino = 'home_v1' then
    v_destino := 'https://magandhi.com/';
  elsif v_enlace.tipo_destino = 'producto_v1' then
    select cp.slug into v_slug
      from campana_producto cp
     where cp.id = v_enlace.campana_producto_id
       and cp.activo and cp.publicado and not cp.es_placeholder
       and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       and length(cp.slug) between 1 and 180;
    if v_slug is null then
      return null;
    end if;
    v_destino := 'https://magandhi.com/producto/' || v_slug || '/';
  else
    return null;
  end if;

  -- Solo caracteres normalizados; no se incorpora nada del request salvo el
  -- código usado para localizar esta fila.
  v_destino := v_destino
    || '?utm_source=' || v_enlace.source
    || '&utm_medium=' || v_enlace.medium
    || '&utm_campaign=' || v_enlace.campaign;
  if v_enlace.content is not null then
    v_destino := v_destino || '&utm_content=' || v_enlace.content;
  end if;

  return jsonb_build_object('enlace_id', v_enlace.id, 'destino_url', v_destino);
end;
$fn$;

revoke all on function promocionar_p3_resolver(text)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_resolver(text) to service_role;

create function promocionar_p3_contar(p_enlace_id uuid, p_ip_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_ahora timestamptz := statement_timestamp();
  v_fecha date := (statement_timestamp() at time zone 'America/Bogota')::date;
  v_ventana timestamp without time zone := date_trunc(
    'hour', statement_timestamp() at time zone 'UTC'
  );
  v_cuota integer;
  v_tipo text;
  v_campana uuid;
  v_conteo integer;
  v_total bigint;
begin
  if p_enlace_id is null or p_ip_hash is null
     or p_ip_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'P3_HASH_O_ENLACE_INVALIDO';
  end if;

  select c.cuota_hora into v_cuota
    from public.promocionar_p3_config c
   where c.id = 1 and c.conteo_habilitado and c.redirect_habilitado
     and c.routing_verificado
   for share;
  if v_cuota is null then
    return jsonb_build_object('contado', false, 'motivo', 'conteo_deshabilitado');
  end if;

  select e.tipo_destino, e.campana_producto_id
    into v_tipo, v_campana
    from atribucion_enlaces e
   where e.id = p_enlace_id and e.estado_enlace = 'activo';
  if not found then
    return jsonb_build_object('contado', false, 'motivo', 'enlace_no_disponible');
  end if;
  if v_tipo = 'producto_v1' and not exists (
    select 1 from campana_producto cp
     where cp.id = v_campana
       and cp.activo and cp.publicado and not cp.es_placeholder
       and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       and length(cp.slug) between 1 and 180
  ) then
    return jsonb_build_object('contado', false, 'motivo', 'destino_no_disponible');
  end if;

  -- Defensa adicional al cron: una solicitud aceptada retira primero ventanas
  -- ya vencidas. El cron horario sigue siendo obligatorio para garantizar la
  -- limpieza incluso cuando no llega tráfico.
  delete from public.atribucion_limite_temporal
   where expira_en <= v_ahora;

  -- UPSERT atómico global por hash/hora. No se renueva expira_en: una llamada
  -- repetida jamás alarga la retención. 47h + cron horario deja margen <48h.
  insert into atribucion_limite_temporal (
    hash_ip_dia, ventana_hora, conteo, creado_en, expira_en
  ) values (
    p_ip_hash, v_ventana, 1, v_ahora, v_ahora + interval '47 hours'
  )
  on conflict (hash_ip_dia, ventana_hora) do update
     set conteo = atribucion_limite_temporal.conteo + 1
   where atribucion_limite_temporal.conteo < v_cuota
  returning conteo into v_conteo;

  if v_conteo is null then
    return jsonb_build_object('contado', false, 'motivo', 'cuota_hora_superada');
  end if;

  insert into atribucion_clics_dia (enlace_id, fecha_colombia, total)
  values (p_enlace_id, v_fecha, 1)
  on conflict (enlace_id, fecha_colombia) do update
     set total = atribucion_clics_dia.total + 1
  returning total into v_total;

  return jsonb_build_object(
    'contado', true,
    'fecha_colombia', v_fecha,
    'total_dia', v_total,
    'conteo_ventana', v_conteo
  );
end;
$fn$;

revoke all on function promocionar_p3_contar(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_contar(uuid, text) to service_role;

-- Solo cron/postgres. Compacta y elimina en una misma transacción de función;
-- si el UPDATE falla, el DELETE del detalle también revierte, evitando doble suma.
create function promocionar_p3_mantenimiento()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_corte date := (
    (statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months'
  )::date;
  v_filas_detalle bigint := 0;
  v_enlaces bigint := 0;
  v_total bigint := 0;
  v_limites bigint := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended('promocionar-p3-mantenimiento-v1', 0));

  with retirados as (
    delete from atribucion_clics_dia d
     where d.fecha_colombia < v_corte
     returning d.enlace_id, d.total
  ), sumas as (
    select enlace_id, count(*)::bigint as filas, sum(total)::bigint as total
      from retirados
     group by enlace_id
  ), actualizados as (
    update atribucion_enlaces e
       set total_aproximado_historico = e.total_aproximado_historico + s.total,
           actualizado_en = greatest(
             clock_timestamp(), e.actualizado_en + interval '1 microsecond'
           ),
           actualizado_por = null,
           mantenimiento_en = clock_timestamp()
      from sumas s
     where e.id = s.enlace_id
     returning s.filas, s.total
  )
  select coalesce(sum(a.filas), 0)::bigint,
         count(*)::bigint,
         coalesce(sum(a.total), 0)::bigint
    into v_filas_detalle, v_enlaces, v_total
    from actualizados a;

  delete from atribucion_limite_temporal
   where expira_en <= statement_timestamp();
  get diagnostics v_limites = row_count;

  return jsonb_build_object(
    'corte_exclusivo', v_corte,
    'filas_detalle_compactadas', v_filas_detalle,
    'enlaces_actualizados', v_enlaces,
    'total_compactado', v_total,
    'limites_vencidos_purgados', v_limites
  );
end;
$fn$;

revoke all on function promocionar_p3_mantenimiento()
  from public, anon, authenticated, service_role;
-- El owner postgres ya conserva EXECUTE; el grant nominal documenta al único
-- ejecutor previsto para pg_cron sin abrirlo a roles API.
grant execute on function promocionar_p3_mantenimiento() to postgres;

-- ----------------------------------------------------------------------------
-- Invariantes de instalación. Cualquier desviación revierte todo el archivo.
-- ----------------------------------------------------------------------------
do $invariantes$
declare
  v_rel text;
  v_f record;
  v_oid regprocedure;
  v_definer boolean;
  v_path_ok boolean;
begin
  if (select count(*) from public.promocionar_p3_config) <> 1
     or not exists (
       select 1 from public.promocionar_p3_config
        where id = 1
          and activacion_habilitada is false
          and redirect_habilitado is false
          and conteo_habilitado is false
          and politica_publicada is false
          and routing_verificado is false
          and politica_version is null
          and url_corta_base = 'https://go.magandhi.com'
          and cuota_hora = 600
          and actualizado_razon = 'instalacion_inicial'
          and actualizado_rol <> ''
     ) then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_INICIAL_INVALIDA';
  end if;

  if exists (
    select 1
      from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
       and (
         has_schema_privilege(r.rolname, 'public', 'CREATE')
         or case when to_regnamespace('extensions') is null then false
                 else has_schema_privilege(r.rolname, 'extensions', 'CREATE') end
       )
  ) then
    raise exception using errcode = 'P0001', message = 'P3_SCHEMA_DEFINER_ESCRIBIBLE_POR_API';
  end if;

  if (
    select count(*)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in (
         'promocionar_p3_config', 'promocionar_p3_config_bitacora',
         'atribucion_enlaces', 'atribucion_clics_dia',
         'atribucion_limite_temporal'
       )
       and c.relkind in ('r', 'p')
  ) <> 5 then
    raise exception using errcode = 'P0001', message = 'P3_CINCO_TABLAS_REQUERIDAS';
  end if;

  foreach v_rel in array array[
    'promocionar_p3_config', 'promocionar_p3_config_bitacora',
    'atribucion_enlaces', 'atribucion_clics_dia',
    'atribucion_limite_temporal'
  ] loop
    if not (select c.relrowsecurity from pg_class c
             where c.oid = ('public.' || v_rel)::regclass)
       or exists (select 1 from pg_policy p
                   where p.polrelid = ('public.' || v_rel)::regclass)
       or exists (
         select 1
           from pg_class c
           cross join lateral aclexplode(
             coalesce(c.relacl, acldefault('r', c.relowner))
           ) a
           left join pg_roles r on r.oid = a.grantee
          where c.oid = ('public.' || v_rel)::regclass
            and (a.grantee = 0 or r.rolname in ('anon', 'authenticated', 'service_role'))
       ) then
      raise exception using errcode = 'P0001', message = 'P3_TABLA_EXPUESTA_' || upper(v_rel);
    end if;
  end loop;

  if exists (
    select 1
      from pg_class c
      cross join lateral aclexplode(coalesce(c.relacl, acldefault('S', c.relowner))) a
      left join pg_roles r on r.oid = a.grantee
     where c.oid = 'public.promocionar_p3_config_bitacora_id_seq'::regclass
       and (a.grantee = 0 or r.rolname in ('anon', 'authenticated', 'service_role'))
  ) then
    raise exception using errcode = 'P0001', message = 'P3_SECUENCIA_BITACORA_EXPUESTA';
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'atribucion_enlaces'
       and column_name = 'campana_producto_id' and is_nullable = 'NO'
  ) or not exists (
    select 1 from pg_constraint
     where conrelid = 'public.atribucion_enlaces'::regclass
       and conname = 'atribucion_enlaces_destino_tipado'
       and convalidated
       and pg_get_constraintdef(oid, true) like '%producto_v1%'
       and pg_get_constraintdef(oid, true) like '%home_v1%'
  ) or not exists (
    select 1
      from pg_index i
      join pg_class x on x.oid = i.indexrelid
     where i.indrelid = 'public.atribucion_enlaces'::regclass
       and x.relname = 'atribucion_enlaces_reemplaza_unico_idx'
       and i.indisunique and i.indpred is not null
  ) then
    raise exception using errcode = 'P0001', message = 'P3_DESTINO_O_GENEALOGIA_INVALIDA';
  end if;

  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'atribucion_limite_temporal'
       and column_name in (
         'enlace_id', 'ip', 'ip_cruda', 'mg_vid', 'sesion_id',
         'cuenta_id', 'cliente_id', 'customer_id', 'user_agent', 'referrer'
       )
  ) then
    raise exception using errcode = 'P0001', message = 'P3_LIMITE_TEMPORAL_VINCULABLE';
  end if;

  if (select count(*) from public.promocionar_p3_config_bitacora) <> 1
     or not exists (
       select 1 from public.promocionar_p3_config_bitacora
        where razon = 'instalacion_inicial'
          and antes_activacion_habilitada is null
          and antes_redirect_habilitado is null
          and antes_conteo_habilitado is null
          and antes_politica_publicada is null
          and antes_routing_verificado is null
          and antes_politica_version is null
          and despues_activacion_habilitada is false
          and despues_redirect_habilitado is false
          and despues_conteo_habilitado is false
          and despues_politica_publicada is false
          and despues_routing_verificado is false
          and despues_politica_version is null
     ) then
    raise exception using errcode = 'P0001', message = 'P3_BITACORA_INICIAL_INVALIDA';
  end if;

  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.atribucion_enlaces'::regclass
       and t.tgname = 'trg_promocionar_p3_validar_enlace'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31
       and t.tgfoid = 'public.promocionar_p3__validar_enlace()'::regprocedure
  ) or not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.promocionar_p3_config'::regclass
       and t.tgname = 'trg_promocionar_p3_proteger_config'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31
       and t.tgfoid = 'public.promocionar_p3__proteger_config()'::regprocedure
  ) or not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.promocionar_p3_config'::regclass
       and t.tgname = 'trg_promocionar_p3_auditar_config'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 17
       and t.tgfoid = 'public.promocionar_p3__auditar_config()'::regprocedure
  ) or not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.promocionar_p3_config_bitacora'::regclass
       and t.tgname = 'trg_promocionar_p3_proteger_config_bitacora'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 58
       and t.tgfoid = 'public.promocionar_p3__proteger_config_bitacora()'::regprocedure
  ) then
    raise exception using errcode = 'P0001', message = 'P3_TRIGGER_DEFENSIVO_AUSENTE';
  end if;

  if not coalesce((
    select p.proargnames = array[
      'p_campana_producto_id', 'p_tipo_destino', 'p_canal_promocion',
      'p_campaign_base', 'p_content', 'p_clave_idempotencia',
      'p_reemplaza_enlace_id'
    ]::text[]
      from pg_proc p
     where p.oid = to_regprocedure(
       'public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)'
     )
  ), false) or not coalesce((
    select p.proargnames = array[
      'p_enlace_id', 'p_actualizado_en_esperado', 'p_tipo_destino',
      'p_canal_promocion', 'p_campaign_base', 'p_content'
    ]::text[]
      from pg_proc p
     where p.oid = to_regprocedure(
       'public.promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)'
     )
  ), false) then
    raise exception using errcode = 'P0001', message = 'P3_FIRMA_RPC_INCORRECTA';
  end if;

  -- Matriz nominal exacta: siete RPC Marketing, dos service-only y cero helper/
  -- mantenimiento para los tres roles API.
  for v_f in
    select * from (values
      ('public.promocionar_p3__normalizar(text,integer)', false, false),
      ('public.promocionar_p3__contiene_pii(text)', false, false),
      ('public.promocionar_p3__canal_utm(text)', false, false),
      ('public.promocionar_p3__crockford(integer)', false, false),
      ('public.promocionar_p3__campaign_candidato(text)', false, false),
      ('public.promocionar_p3__enlace_json(atribucion_enlaces)', false, false),
      ('public.promocionar_p3__proteger_config()', false, false),
      ('public.promocionar_p3__auditar_config()', false, false),
      ('public.promocionar_p3__proteger_config_bitacora()', false, false),
      ('public.promocionar_p3__validar_enlace()', false, false),
      ('public.promocionar_p3_config()', true, false),
      ('public.promocionar_p3_listar(uuid)', true, false),
      ('public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)', true, false),
      ('public.promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)', true, false),
      ('public.promocionar_p3_activar(uuid)', true, false),
      ('public.promocionar_p3_desactivar(uuid)', true, false),
      ('public.promocionar_p3_eliminar_borrador(uuid)', true, false),
      ('public.promocionar_p3_resolver(text)', false, true),
      ('public.promocionar_p3_contar(uuid,text)', false, true),
      ('public.promocionar_p3_mantenimiento()', false, false)
    ) as e(firma, authenticated_e, service_e)
  loop
    v_oid := to_regprocedure(v_f.firma);
    if v_oid is null then
      raise exception using errcode = 'P0001', message = 'P3_FUNCION_AUSENTE_' || v_f.firma;
    end if;
    select p.prosecdef,
           coalesce(p.proconfig = array[
             'search_path=' || case
               when v_f.firma in (
                 'public.promocionar_p3__crockford(integer)',
                 'public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)'
               ) then 'public, extensions, pg_temp'
               else 'public, pg_temp'
             end
           ], false)
      into v_definer, v_path_ok
      from pg_proc p where p.oid = v_oid;
    if not v_definer or not v_path_ok
       or has_function_privilege('anon', v_oid, 'execute')
       or has_function_privilege('authenticated', v_oid, 'execute') is distinct from v_f.authenticated_e
       or has_function_privilege('service_role', v_oid, 'execute') is distinct from v_f.service_e then
      raise exception using errcode = 'P0001', message = 'P3_FUNCION_O_ACL_INVALIDA_' || v_f.firma;
    end if;
  end loop;

  if not has_function_privilege('postgres', 'public.promocionar_p3_mantenimiento()', 'execute')
     or exists (select 1 from public.atribucion_enlaces)
     or exists (select 1 from public.atribucion_clics_dia)
     or exists (select 1 from public.atribucion_limite_temporal) then
    raise exception using errcode = 'P0001', message = 'P3_INSTALACION_INICIAL_INVALIDA';
  end if;
end;
$invariantes$;

commit;
