-- ============================================================================
-- MAGANDHI · Dropshipping D2c.1 · STOCK VIVO (cimiento de la venta proveedor)
-- ----------------------------------------------------------------------------
-- Migracion FORWARD. No reescribe ni reejecuta ninguna historica.
--
-- QUE HACE
--   1. `dropshipping_config`: las perillas del dueño en un solo lugar
--      (vigencia, piso de vitrina, vara de entrada, tanda de refresco).
--   2. `producto_proveedor` gana el piso por producto, el interruptor de
--      refresco y el rastro del ultimo intento/error.
--   3. `ds_productos_por_refrescar()`: la COLA del refresco rodante. Devuelve
--      los N productos con la lectura mas vieja. Solo service_role.
--   4. `ds_registrar_lectura_stock()`: donde la Edge Function escribe lo que
--      leyo de Dropi. Solo service_role.
--   5. `ds_estado_stock()`: lo que el panel muestra al dueño (frescura, piso,
--      por que un producto esta fuera de vitrina). Solo con modulo.
--   6. `catalogo_publico` aprende a FALLAR CERRADO con producto proveedor.
--
-- QUE NO HACE (a proposito)
--   - NO levanta DS_PUBLICACION_PENDIENTE: un producto proveedor sigue sin
--     poder publicarse, asi que NADA se puede vender todavia. Eso es D2c.2.
--   - no toca crear_pedido ni anular_pedido;
--   - no registra asientos ni cuentas contables;
--   - no llama a Dropi (eso vive en la Edge Function `dropi-refrescar-stock`);
--   - no crea el job de pg_cron: las extensiones se habilitan a mano desde el
--     dashboard y el agendamiento va en el runbook. Asi esta migracion corre
--     igual en el banco local, donde pg_cron no existe.
--
-- DECISIONES DEL DUEÑO (10-oct-2026, discutidas y cerradas)
--   · Piso de vitrina = 20 unidades. MEDIDO: en 8 lecturas reales el stock fue
--     1277, 459, 300, 300, 230, 0, 0, 0 — NADA entre 1 y 229. El stock de Dropi
--     es bimodal (muerto o profundo), asi que un piso de 20 no excluye ningun
--     producto que tenga existencias: es proteccion practicamente gratis.
--   · Vara de entrada = 100 unidades al importar, para no nacer al borde.
--   · Vigencia = 120 minutos. Es una perilla COMERCIAL, no de seguridad: lo que
--     evita vender humo es la consulta en vivo antes de pagar (D2c.2). Si la
--     vigencia se queda corta se pierde una venta; si se pasa, el cliente choca
--     al pagar. Ninguno de los dos vende lo que no existe.
--   · Refresco RODANTE de 3 productos por minuto, no un lote cada 15 min.
--     MEDIDO: Dropi responde 429 alrededor de la peticion 12-16 en rafaga, y
--     refrescar un producto cuesta 1 peticion. Una tanda de 3 por minuto jamas
--     se acerca al techo, y aun asi 15 productos quedan frescos cada 5 minutos.
--   · El copy publico NO cambia: se reutiliza `agotado`. Un texto distinto para
--     proveedor seria una ETIQUETA QUE DELATA el dropshipping, y la tienda
--     nunca debe oler a eso.
--
-- POR QUE EL STOCK PROVEEDOR NO PUEDE SALIR DEL LIBRO DE INVENTARIO
--   Un producto proveedor no tiene movimientos (lo impide el gatillo de D1) y
--   no esta en `stock_actual`. Su unica fuente de verdad es Dropi, y lo que
--   tenemos es una FOTOGRAFIA con hora. De ahi todo el diseño: la foto vence.
--
-- MEDIDO el 10-oct-2026 y por eso esto falla cerrado:
--   Dos productos pasaron de 300 unidades en 3 bodegas a 0 SIN NINGUNA bodega
--   en 24 horas, confirmado leyendo las dos rutas en el mismo instante. No
--   bajaron de a poco: se evaporaron. Y seguian con `active: true`. Por tanto
--   ni el piso ni `active` protegen de un derrumbe: solo la frescura.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Las perillas, en un solo lugar
-- ----------------------------------------------------------------------------
-- Mismo molde que `inventario_config`, `contabilidad_config` y `pagos_config`:
-- una sola fila, editada por el dueño, leida por todo lo demas. Cambiar un
-- numero NO debe exigir una migracion nueva.
create table if not exists dropshipping_config (
  id                  integer primary key default 1,
  -- Cuanto tiempo se trata una lectura de stock como si fuera el presente.
  vigencia_minutos    integer not null default 120
                        check (vigencia_minutos between 5 and 1440),
  -- Por debajo de esto, el producto sale de la vitrina aunque la lectura este
  -- fresca. Protege del DESGASTE (la carrera por la ultima unidad), que es lo
  -- unico que no tiene arreglo tecnico entre el pago y el despacho manual.
  piso_vitrina        integer not null default 20
                        check (piso_vitrina between 0 and 10000),
  -- Vara de ENTRADA: no se importa un producto con menos de esto.
  vara_entrada        integer not null default 100
                        check (vara_entrada between 0 and 100000),
  -- Cuantos productos refresca cada vuelta del reloj. Techo bajo a proposito.
  refresco_por_tanda  integer not null default 3
                        check (refresco_por_tanda between 1 and 8),
  -- Avisar en el panel cuando el saldo de Dropi baje de aqui (en pesos). Si el
  -- saldo llega a cero la operacion se rompe EN SILENCIO: se vende y no se
  -- puede despachar.
  saldo_minimo_aviso  bigint  not null default 0
                        check (saldo_minimo_aviso >= 0),
  -- EL INTERRUPTOR DE D2c.1. En false (por defecto) ningun producto proveedor
  -- puede asomarse a catalogo_publico, pase lo que pase con su stock.
  --
  -- POR QUE EXISTE: hasta D1 la vista excluia proveedor con un `origen =
  -- propio` duro. D2c.1 necesita calcular el `agotado` de proveedor para
  -- poder probarlo, pero si solo se cambiara esa condicion por la logica de
  -- stock, una campaña proveedor con publicado=true puesto por DML directo
  -- (service_role, un bug futuro, una mano torcida) apareceria en la tienda.
  -- Se veria agotada y no se podria comprar, pero se veria. D2c.1 tiene que
  -- ser INERTE, asi que el candado duro se conserva como un interruptor
  -- explicito que D2c.2 abre cuando el resto este listo y medido.
  venta_proveedor_habilitada boolean not null default false,
  creado              timestamptz not null default now(),
  actualizado         timestamptz,
  constraint dropshipping_config_fila_unica check (id = 1)
);

insert into dropshipping_config (id) values (1) on conflict (id) do nothing;

comment on table dropshipping_config is
  'D2c.1 Dropshipping · perillas del stock proveedor en una sola fila (id=1), molde de inventario_config/contabilidad_config. Decisiones del dueño del 10-oct-2026: vigencia 120 min, piso de vitrina 20, vara de entrada 100, tanda de refresco 3. Se cambian AQUI, sin migracion nueva. La edita el dueño (service_role); authenticated con modulo dropshipping solo la LEE.';
comment on column dropshipping_config.vigencia_minutos is
  'Minutos que una lectura de stock se considera vigente. Al vencer, el producto sale de la vitrina (agotado=true) aunque hubiera existencias: FALLA CERRADO. Es una perilla comercial, no de seguridad; la seguridad real es la consulta en vivo antes de pagar.';
comment on column dropshipping_config.piso_vitrina is
  'Unidades minimas para mostrar el producto como disponible. MEDIDO: el stock de Dropi es bimodal (0 o 230+), asi que 20 no excluye nada con existencias. Protege de la carrera por la ultima unidad entre el pago y la transcripcion manual del pedido.';
comment on column dropshipping_config.refresco_por_tanda is
  'Productos por vuelta del reloj. Refresco RODANTE: 3 por minuto nunca se acerca al 429 de Dropi (medido entre la peticion 12 y 16 en rafaga) y aun asi mantiene un catalogo pequeño mas fresco que un lote cada 15 minutos.';
comment on column dropshipping_config.venta_proveedor_habilitada is
  'CANDADO DURO de D2c.1. En false, catalogo_publico no muestra NINGUN producto proveedor aunque su campaña estuviera publicada por DML directo. Conserva la proteccion que D1 tenia con «origen = propio» mientras D2c.1 construye y prueba la logica de agotado. Lo abre D2c.2, junto con el checkout seguro y el pedido; no antes.';

alter table dropshipping_config enable row level security;

drop policy if exists "dropshipping_config_select_dropshipping" on dropshipping_config;
create policy "dropshipping_config_select_dropshipping" on dropshipping_config
  for select to authenticated using (tiene_acceso_dropshipping());

-- Auto-expose apagado: sin el grant, PostgREST responde 403 antes de RLS.
-- NO se concede INSERT/UPDATE/DELETE: las perillas las mueve el dueño.
grant select on table dropshipping_config to authenticated;

-- ----------------------------------------------------------------------------
-- (B) La ficha del proveedor aprende a ser refrescada
-- ----------------------------------------------------------------------------
alter table producto_proveedor
  add column if not exists piso_vitrina   integer,
  add column if not exists refrescar      boolean not null default true,
  add column if not exists ultimo_intento timestamptz,
  add column if not exists ultimo_error   text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'producto_proveedor_piso_rango'
  ) then
    alter table producto_proveedor
      add constraint producto_proveedor_piso_rango
      check (piso_vitrina is null or piso_vitrina between 0 and 10000);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'producto_proveedor_error_corto'
  ) then
    alter table producto_proveedor
      add constraint producto_proveedor_error_corto
      check (ultimo_error is null or length(ultimo_error) <= 300);
  end if;
end $$;

comment on column producto_proveedor.piso_vitrina is
  'Piso propio de ESTE producto, en unidades. NULL = usa dropshipping_config.piso_vitrina. Existe porque un producto que vende 1 al mes no necesita colchon y uno que vende 10 al dia necesita mas de 20.';
comment on column producto_proveedor.refrescar is
  'false = sale de la cola del refresco (producto pausado). No lo vuelve disponible: sin lectura fresca, la vitrina lo da por agotado igual.';
comment on column producto_proveedor.ultimo_intento is
  'Cuando se intento leer por ultima vez, haya salido bien o mal. Separado de stock_leido_en (que solo avanza con una lectura BUENA) para que un producto que falla no monopolice la cola.';
comment on column producto_proveedor.ultimo_error is
  'Que respondio Dropi en el ultimo intento fallido (p. ej. «429» o «404»). Se limpia con la siguiente lectura buena. Nunca guarda token ni cuerpos completos.';

-- La cola ordena por intento mas viejo: con indice, para que no degrade cuando
-- haya decenas de productos.
create index if not exists producto_proveedor_cola_refresco_idx
  on producto_proveedor (ultimo_intento nulls first)
  where refrescar;

-- ----------------------------------------------------------------------------
-- (C) La cola del refresco rodante
-- ----------------------------------------------------------------------------
-- La llama la Edge Function `dropi-refrescar-stock` con service_role. Devuelve
-- los N productos con el intento mas viejo (los que nunca se leyeron, primero).
--
-- POR QUE ordena por `ultimo_intento` y no por `stock_leido_en`: si un producto
-- empieza a fallar, su `stock_leido_en` se queda congelado y volveria a salir
-- primero en cada vuelta, monopolizando la cola y dejando a los demas sin
-- refrescar. Con `ultimo_intento` el que falla cede el turno.
create or replace function ds_productos_por_refrescar(p_limite integer default null)
returns table (
  product_id           uuid,
  producto_externo_id  text,
  variacion_externa_id text,
  stock_leido_en       timestamptz
)
language sql
volatile
security definer
set search_path = public
as $$
  select pp.product_id, pp.producto_externo_id, pp.variacion_externa_id, pp.stock_leido_en
  from producto_proveedor pp
  join productos p on p.id = pp.product_id
  where pp.refrescar
    and p.origen = 'proveedor'
  order by pp.ultimo_intento asc nulls first, pp.product_id
  limit greatest(1, least(
    coalesce(p_limite, (select refresco_por_tanda from dropshipping_config where id = 1), 3),
    8
  ));
$$;

comment on function ds_productos_por_refrescar(integer) is
  'D2c.1 · cola del refresco rodante: los N productos proveedor con el intento mas viejo. La llama la Edge Function dropi-refrescar-stock (service_role). Ordena por ultimo_intento, no por stock_leido_en, para que un producto que falla ceda el turno en vez de monopolizar la cola. El limite esta topado a 8 aunque se pida mas: el techo de Dropi es ~12-16 peticiones en rafaga.';

revoke all on function ds_productos_por_refrescar(integer) from public;
grant execute on function ds_productos_por_refrescar(integer) to service_role;

-- ----------------------------------------------------------------------------
-- (D) Donde se escribe lo que Dropi contesto
-- ----------------------------------------------------------------------------
-- Una lectura BUENA mueve stock_reportado, stock_leido_en y stock_vence_en.
-- Una lectura FALLIDA solo deja rastro: NO toca el stock ni la vigencia, asi
-- que la foto vieja sigue envejeciendo y vence sola. Fallar nunca puede
-- extender la vida de un dato.
create or replace function ds_registrar_lectura_stock(
  p_product_id uuid,
  p_stock      integer default null,
  p_error      text    default null
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_minutos integer;
  v_ahora   timestamptz := now();
  v_vence   timestamptz;
begin
  if p_product_id is null then
    raise exception 'DS_FALTA_PRODUCTO';
  end if;

  if not exists (
    select 1 from producto_proveedor pp
    join productos p on p.id = pp.product_id
    where pp.product_id = p_product_id and p.origen = 'proveedor'
  ) then
    raise exception 'DS_PRODUCTO_NO_PROVEEDOR';
  end if;

  -- Lectura fallida (o sin dato): solo se anota el intento. El stock queda
  -- intacto y su vigencia sigue corriendo hacia el vencimiento.
  if p_error is not null or p_stock is null then
    update producto_proveedor
    set ultimo_intento = v_ahora,
        ultimo_error   = left(coalesce(p_error, 'sin dato de stock'), 300),
        actualizado    = v_ahora
    where product_id = p_product_id;
    return null;
  end if;

  if p_stock < 0 then
    raise exception 'DS_STOCK_NEGATIVO';
  end if;

  select vigencia_minutos into v_minutos from dropshipping_config where id = 1;
  v_vence := v_ahora + make_interval(mins => coalesce(v_minutos, 120));

  update producto_proveedor
  set stock_reportado = p_stock,
      stock_leido_en  = v_ahora,
      stock_vence_en  = v_vence,
      ultimo_intento  = v_ahora,
      ultimo_error    = null,
      actualizado     = v_ahora
  where product_id = p_product_id;

  return v_vence;
end;
$$;

comment on function ds_registrar_lectura_stock(uuid, integer, text) is
  'D2c.1 · la Edge Function dropi-refrescar-stock escribe aqui lo que leyo de Dropi (service_role). Una lectura buena mueve stock_reportado/leido_en/vence_en; una FALLIDA solo anota el intento y el error, sin tocar el stock ni la vigencia: fallar jamas puede alargarle la vida a un dato viejo. Devuelve la nueva fecha de vencimiento, o null si fue fallo.';

revoke all on function ds_registrar_lectura_stock(uuid, integer, text) from public;
grant execute on function ds_registrar_lectura_stock(uuid, integer, text) to service_role;

-- ----------------------------------------------------------------------------
-- (E) Lo que el panel le muestra al dueño
-- ----------------------------------------------------------------------------
-- Responde la pregunta operativa: «¿por que este producto no esta en vitrina?».
-- Un motivo claro por producto, en orden de precedencia.
create or replace function ds_estado_stock()
returns table (
  product_id      uuid,
  sku             text,
  nombre          text,
  dropi_id        text,
  variante        text,
  stock           integer,
  piso_efectivo   integer,
  leido_en        timestamptz,
  vence_en        timestamptz,
  vigente         boolean,
  en_vitrina      boolean,
  motivo          text,
  ultimo_error    text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    pp.product_id,
    p.sku,
    p.nombre,
    pp.producto_externo_id,
    nullif(pp.variacion_externa_id, ''),
    pp.stock_reportado,
    coalesce(pp.piso_vitrina, cfg.piso_vitrina) as piso_efectivo,
    pp.stock_leido_en,
    pp.stock_vence_en,
    (pp.stock_vence_en is not null and pp.stock_vence_en > now()) as vigente,
    (
      pp.stock_reportado is not null
      and pp.stock_vence_en is not null
      and pp.stock_vence_en > now()
      and pp.stock_reportado >= coalesce(pp.piso_vitrina, cfg.piso_vitrina)
    ) as en_vitrina,
    case
      when pp.stock_leido_en is null then 'sin lectura todavia'
      when pp.stock_reportado is null then 'sin dato de stock'
      when pp.stock_vence_en <= now() then 'lectura vencida'
      when pp.stock_reportado < coalesce(pp.piso_vitrina, cfg.piso_vitrina)
        then 'por debajo del piso'
      when not pp.refrescar then 'en vitrina, pero el refresco esta pausado'
      else 'en vitrina'
    end as motivo,
    pp.ultimo_error
  from producto_proveedor pp
  join productos p on p.id = pp.product_id
  cross join (select piso_vitrina from dropshipping_config where id = 1) cfg
  where p.origen = 'proveedor'
    and tiene_acceso_dropshipping()
  order by p.nombre;
$$;

comment on function ds_estado_stock() is
  'D2c.1 · lo que el panel de Dropshipping muestra: frescura, piso efectivo y POR QUE cada producto proveedor esta o no en vitrina. Definer pero valida tiene_acceso_dropshipping() dentro: sin modulo devuelve cero filas. No expone costo ni proveedor.';

revoke all on function ds_estado_stock() from public;
grant execute on function ds_estado_stock() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (F) La vitrina publica aprende a fallar cerrado
-- ----------------------------------------------------------------------------
-- El copy NO cambia: se reutiliza el booleano `agotado` que la tienda ya sabe
-- leer («Agotado por ahora» + boton deshabilitado). Un estado nuevo con texto
-- distinto delataria cuales productos son de proveedor.
--
-- Para producto PROPIO: identico a D1, no se toca nada.
-- Para producto PROVEEDOR, `agotado` es true si CUALQUIERA de estas pasa:
--   · no hay ficha de proveedor;
--   · no hay lectura de stock;
--   · la lectura VENCIO (aqui esta el fallo cerrado);
--   · el stock esta por debajo del piso (propio del producto o el global).
--
-- Un producto proveedor solo puede aparecer aqui si su campaña esta publicada,
-- y D2c.1 NO levanta DS_PUBLICACION_PENDIENTE: hoy sigue siendo imposible.
-- Esta logica queda construida y probada para que D2c.2 solo tenga que abrir
-- la puerta.
--
-- PENDIENTE D2c.2: restar los pedidos ya pagados que todavia no se han
-- transcrito a mano en Dropi. Esa resta necesita el flujo de pedido proveedor,
-- que no existe aun; hoy no hay ninguno posible, asi que el resultado seria el
-- mismo. D2c.2 redefine esta vista para incluirla.
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
    -- Sin producto ligado no hay nada que vender.
    when cp.product_id_ref is null then true
    -- Producto de proveedor: manda la fotografia de Dropi y su vigencia.
    when p.origen = 'proveedor' then (
      pp.product_id is null
      or pp.stock_reportado is null
      or pp.stock_vence_en is null
      or pp.stock_vence_en <= now()
      or pp.stock_reportado < coalesce(pp.piso_vitrina, dcfg.piso_vitrina, 20)
    )
    -- Producto propio: el libro de inventario, igual que siempre.
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
left join producto_proveedor pp on pp.product_id = cp.product_id_ref
left join (
  select piso_vitrina, venta_proveedor_habilitada
  from dropshipping_config where id = 1
) dcfg on true
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
  -- CANDADO DURO: mientras el interruptor este en false, ningun producto
  -- proveedor sale a la tienda ni siquiera como tarjeta agotada. Es la
  -- proteccion que D1 tenia con «origen = propio», conservada a proposito
  -- para que D2c.1 sea INERTE. La abre D2c.2.
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view catalogo_publico is
  'D2c.1 Dropshipping · superficie publica de lista blanca. Producto propio: agotado sale del libro de inventario (sin cambios). Producto proveedor: agotado sale de la lectura de Dropi y FALLA CERRADO si la lectura vencio, falta o esta por debajo del piso. Reutiliza el mismo booleano `agotado` a proposito: un estado nuevo con copy distinto delataria cuales productos son de proveedor. Nunca expone origen, proveedor, costo, ids externos, el piso ni existencias exactas.';

grant select on catalogo_publico to anon, authenticated, service_role;

commit;
