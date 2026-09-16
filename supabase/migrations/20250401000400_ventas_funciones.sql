-- ============================================================
-- Magandhi Corporation · Area de Ventas · Funciones RPC (la unica via de escritura)
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO: toda la escritura de Ventas pasa por estas RPC
-- security definer, espejo del patron de Inventario (inv_registrar_movimiento) y
-- Finanzas (guardar_asiento). Ninguna tabla de Ventas tiene policy de INSERT/
-- UPDATE/DELETE para authenticated (ver 20250401000300_ventas_rls.sql): el
-- cliente no escribe directo (PLANO-VENTAS §6).
--
-- Todas son:
--   - security definer con set search_path = public fijo.
--   - Validan tiene_acceso_ventas() al entrar, de modo que el candado de acceso
--     se respeta aunque la funcion salte RLS por ser definer.
--
-- FIRMAS EXACTAS (para el frontend, features siguientes):
--   buscar_candidatos_cliente(p_correo text, p_telefono text, p_nombre text)
--     -> jsonb (array de candidatos). SOLO LECTURA.
--   crear_pedido(p_customer_id uuid, p_nombre text, p_correo text,
--     p_telefono text, p_direccion text, p_ciudad text, p_departamento text,
--     p_pais text, p_notas_cliente text, p_canal text, p_fecha_orden date,
--     p_notas_pedido text, p_items jsonb) -> jsonb {pedido_id, customer_id, total}
--   anular_pedido(p_pedido_id uuid, p_motivo text) -> jsonb {pedido_id, revertidos}
--
-- DECISION DE CRITERIO SOBRE LA BAJA DE STOCK (documentada aqui por diseno):
--   crear_pedido y anular_pedido NO llaman inv_registrar_movimiento. Esa RPC de
--   Inventario (1) exige tiene_acceso_inventario() al entrar -> rechazaria a un
--   usuario SOLO de ventas, y (2) no acepta un parametro customer_id -> no
--   podria estampar quien compro. En su lugar, estas RPC (siendo security
--   definer) INSERTAN DIRECTAMENTE la fila en movimientos_inventario (el libro
--   es append-only; usamos el MISMO conjunto de columnas y la MISMA logica de
--   signo por tipo que inv_registrar_movimiento):
--     - al crear:  tipo='salida',  motivo='Venta',
--     - al anular: tipo='entrada', motivo='Anulacion de venta',
--   ambas con referencia = pedido_id::text, customer_id estampado y
--   fecha = fecha_orden del pedido. Se ELIGE esta via frente a modificar la
--   firma de Inventario porque: no acopla las dos areas por codigo (mantiene la
--   "cita a ciegas"), no obliga al usuario de ventas a tener tambien permiso de
--   inventario, y respeta el contrato existente del libro: una SALIDA SIN STOCK
--   NO SE BLOQUEA (§2, §5.2, §11) -- es una senal de reconciliacion, no un error.
--
-- MONTOS bigint (total, precio_unitario, subtotal), cantidades integer.
--
-- IDEMPOTENTE: create or replace (re-ejecutar solo actualiza la logica).
-- REQUISITO: correr DESPUES de 20250401000000..20250401000300.
-- ============================================================

-- ------------------------------------------------------------
-- ventas_norm_correo / ventas_norm_telefono: normalizacion SERVER-SIDE, reglas
-- deterministas y explicables (§1.4). Se centralizan aqui para que el algoritmo
-- de coincidencia y crear_pedido normalicen EXACTAMENTE igual (si difirieran, el
-- indice UNIQUE parcial no protegeria nada). Devuelven null si el resultado
-- queda vacio, para que la unicidad parcial (where ... is not null) no choque.
--   correo   -> trim + minusculas.
--   telefono -> quitar todo lo que no sea digito y el prefijo de pais 57 / +57.
-- ------------------------------------------------------------
create or replace function ventas_norm_correo(p_correo text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(coalesce(p_correo, ''))), '');
$$;

comment on function ventas_norm_correo(text) is 'Normaliza un correo a su forma canonica (trim + minusculas, §1.4). Devuelve null si queda vacio. Se usa igual en buscar_candidatos_cliente y crear_pedido para que el indice UNIQUE parcial de clientes.correo_norm sea consistente.';

create or replace function ventas_norm_telefono(p_telefono text)
returns text
language sql
immutable
as $$
  -- 1) dejar solo digitos; 2) quitar prefijo de pais 57 cuando el resto queda
  -- con 10 digitos (celular colombiano). Reglas explicitas y legibles (§1.4).
  select nullif(
    case
      when length(regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g')) = 12
       and left(regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g'), 2) = '57'
        then substring(regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g') from 3)
      else regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g')
    end, '');
$$;

comment on function ventas_norm_telefono(text) is 'Normaliza un telefono a su forma canonica: solo digitos, quitando espacios/guiones/parentesis y el prefijo de pais 57/+57 cuando quedan 12 digitos (celular colombiano). Devuelve null si queda vacio. Se usa igual en buscar_candidatos_cliente y crear_pedido para que el indice UNIQUE parcial de clientes.telefono_norm sea consistente.';

-- ------------------------------------------------------------
-- ventas_norm_nombre: normaliza un nombre para comparacion de senal DEBIL:
-- minusculas, sin acentos (transliteracion a mano, no depende de unaccent),
-- trim y espacios colapsados. Solo para comparar; el nombre original se guarda
-- tal cual.
-- ------------------------------------------------------------
create or replace function ventas_norm_nombre(p_nombre text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      trim(
        lower(
          translate(coalesce(p_nombre, ''),
            'ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÑáéíóúàèìòùäëïöüâêîôûñ',
            'aeiouaeiouaeiouaeiounaeiouaeiouaeiouaeioun')
        )
      ),
      '\s+', ' ', 'g'
    ), '');
$$;

comment on function ventas_norm_nombre(text) is 'Normaliza un nombre para comparacion de senal debil (§4.1): minusculas, sin acentos (transliteracion a mano, sin depender de unaccent), trim y espacios colapsados. Solo para comparar; el nombre original se conserva.';

-- ------------------------------------------------------------
-- buscar_candidatos_cliente: SOLO LECTURA. El algoritmo de coincidencia (§4).
-- Corre security definer no para escribir sino para LEER de forma acotada
-- (§6.2): devuelve candidatos con score/porcentaje/senales/banda SIN abrir toda
-- la tabla clientes al navegador (son datos personales de terceros).
--
-- PUNTAJE POR SENALES (explicable, §4.1-§4.2). Pesos de ARRANQUE (afinables,
-- §4.2 y §10), documentados aqui:
--   correo_norm exacto   = 60  (senal FUERTE)
--   telefono_norm exacto = 60  (senal FUERTE)
--   nombre muy parecido  = hasta 30 (senal DEBIL; similitud sobre nombre norm.)
--   misma ciudad         = no se evalua aqui (apoyo futuro, §4.1)
-- El porcentaje es min(100, score). Bandas de arranque:
--   alta  >= 60  (una senal fuerte sola YA alcanza alta)
--   media >= 30  (varias debiles, o una debil marcada)
--   baja  < 30   (solo algo de nombre)
-- REGLA INNEGOCIABLE: una senal fuerte sola da banda ALTA; las senales debiles
-- SOLAS nunca alcanzan alta (el peso de nombre topa en 30 < 60). Sin pg_trgm:
-- la similitud de nombre se calcula en SQL puro con distancia de edicion
-- normalizada (levenshtein del modulo fuzzystrmatch si esta, con fallback a
-- comparacion por prefijo/igualdad). Aqui se usa una similitud simple y
-- explicable basada en levenshtein sobre el nombre normalizado si la funcion
-- existe; si no, cae a igualdad exacta del nombre normalizado.
--
-- NUNCA fusiona ni bloquea: solo propone. El humano decide (§4.4).
-- ------------------------------------------------------------
create or replace function buscar_candidatos_cliente(
  p_correo   text default null,
  p_telefono text default null,
  p_nombre   text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_correo_norm   text := ventas_norm_correo(p_correo);
  v_telefono_norm text := ventas_norm_telefono(p_telefono);
  v_nombre_norm   text := ventas_norm_nombre(p_nombre);
  v_tiene_lev     boolean;
  v_resultado     jsonb;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  -- Sin ningun dato de entrada no hay a quien parecerse: array vacio.
  if v_correo_norm is null and v_telefono_norm is null and v_nombre_norm is null then
    return '[]'::jsonb;
  end if;

  -- Deteccion de levenshtein (extension fuzzystrmatch). Si no esta, la
  -- similitud de nombre cae a igualdad exacta del nombre normalizado.
  select exists (
    select 1 from pg_proc where proname = 'levenshtein'
  ) into v_tiene_lev;

  with base as (
    select
      c.id,
      c.nombre,
      c.correo,
      c.telefono,
      -- Senal fuerte: correo exacto.
      (v_correo_norm is not null and c.correo_norm = v_correo_norm) as m_correo,
      -- Senal fuerte: telefono exacto.
      (v_telefono_norm is not null and c.telefono_norm = v_telefono_norm) as m_telefono,
      -- Senal debil: similitud de nombre 0..1 (0 = nada parecido, 1 = igual).
      case
        when v_nombre_norm is null then 0::numeric
        when v_tiene_lev then
          greatest(
            0::numeric,
            1 - (
              levenshtein(ventas_norm_nombre(c.nombre), v_nombre_norm)::numeric
              / greatest(length(v_nombre_norm), length(ventas_norm_nombre(c.nombre)), 1)
            )
          )
        when ventas_norm_nombre(c.nombre) = v_nombre_norm then 1::numeric
        else 0::numeric
      end as sim_nombre
    from clientes c
    where c.activo = true
      and (
        (v_correo_norm is not null and c.correo_norm = v_correo_norm)
        or (v_telefono_norm is not null and c.telefono_norm = v_telefono_norm)
        or (v_nombre_norm is not null and ventas_norm_nombre(c.nombre) is not null)
      )
  ),
  puntuado as (
    select
      id, nombre, correo, telefono, m_correo, m_telefono, sim_nombre,
      -- Score: fuerte = 60 (cada una); debil de nombre = hasta 30.
      (case when m_correo then 60 else 0 end)
      + (case when m_telefono then 60 else 0 end)
      + round(sim_nombre * 30)::int as score
    from base
  ),
  clasificado as (
    select
      id, nombre, correo, telefono, m_correo, m_telefono, sim_nombre, score,
      least(100, score) as porcentaje,
      case
        when score >= 60 then 'alta'
        when score >= 30 then 'media'
        else 'baja'
      end as banda,
      -- Senales legibles (el porque), en orden de fuerza.
      (
        case when m_correo then jsonb_build_array('mismo correo') else '[]'::jsonb end
        || case when m_telefono then jsonb_build_array('mismo telefono') else '[]'::jsonb end
        || case when sim_nombre >= 0.6 then jsonb_build_array('nombre muy parecido')
                when sim_nombre > 0 then jsonb_build_array('nombre algo parecido')
                else '[]'::jsonb end
      ) as senales
    from puntuado
    -- Un candidato entra si tiene alguna senal real (evita listar toda la tabla
    -- por el solo hecho de tener nombre). Un _norm identico SIEMPRE entra (§4.5).
    where m_correo or m_telefono or sim_nombre > 0
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'nombre', nombre,
        'correo', correo,
        'telefono', telefono,
        'score', score,
        'porcentaje', porcentaje,
        'senales', senales,
        'banda', banda
      )
      order by score desc, sim_nombre desc
    ),
    '[]'::jsonb
  )
  into v_resultado
  from clasificado;

  return v_resultado;
end;
$$;

comment on function buscar_candidatos_cliente(text, text, text) is 'SOLO LECTURA. Algoritmo de coincidencia de cliente (§4): normaliza server-side y devuelve un array jsonb de candidatos {id,nombre,correo,telefono,score,porcentaje,senales,banda}. Senal FUERTE=correo_norm o telefono_norm exacto (peso 60); senal DEBIL=nombre parecido (hasta 30). Una fuerte sola da banda alta; las debiles solas nunca alcanzan alta. Nunca fusiona ni bloquea: el humano decide. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- crear_pedido: el NUCLEO UNICO con dos puertas (manual hoy, web futura). Toda
-- la cadena en UNA TRANSACCION (el cuerpo de una funcion plpgsql es atomico):
--   (1) resolver cliente (usar p_customer_id, o crear en clientes; ante colision
--       del UNIQUE parcial NO falla ni duplica: resuelve al existente, §4.5).
--   (2) insertar el pedido (estado inicial 'recibido', canal, fecha_orden).
--   (3) por cada item: insertar pedido_items con precio real y subtotal, sumar
--       el total (bigint).
--   (4) bajar inventario: INSERT directo de una 'salida' en el libro por item
--       (ver DECISION DE CRITERIO en la cabecera; salida sin stock NO se bloquea).
-- Devuelve jsonb {pedido_id, customer_id, total}.
-- ------------------------------------------------------------
create or replace function crear_pedido(
  p_customer_id    uuid    default null,
  p_nombre         text    default null,
  p_correo         text    default null,
  p_telefono       text    default null,
  p_direccion      text    default null,
  p_ciudad         text    default null,
  p_departamento   text    default null,
  p_pais           text    default null,
  p_notas_cliente  text    default null,
  p_canal          text    default 'manual',
  p_fecha_orden    date    default current_date,
  p_notas_pedido   text    default null,
  p_items          jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id   uuid := p_customer_id;
  v_correo_norm   text := ventas_norm_correo(p_correo);
  v_telefono_norm text := ventas_norm_telefono(p_telefono);
  v_canal         text := coalesce(nullif(trim(p_canal), ''), 'manual');
  v_fecha         date := coalesce(p_fecha_orden, current_date);
  v_pedido_id     uuid;
  v_total         bigint := 0;
  v_item          jsonb;
  v_product_id    uuid;
  v_cantidad      integer;
  v_precio        bigint;
  v_subtotal      bigint;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  if v_canal not in ('manual','web') then
    raise exception 'Canal invalido: %. Use manual o web.', v_canal;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe tener al menos un item.';
  end if;

  -- (1) RESOLVER CLIENTE ---------------------------------------------------
  if v_customer_id is null then
    -- Ante colision del UNIQUE parcial NO se cae ni se duplica (§4.5, el UNIQUE
    -- manda): se resuelve al cliente existente que ya tiene ese contacto.
    -- Precedencia: correo, luego telefono.
    if v_correo_norm is not null then
      select id into v_customer_id from clientes where correo_norm = v_correo_norm limit 1;
    end if;
    if v_customer_id is null and v_telefono_norm is not null then
      select id into v_customer_id from clientes where telefono_norm = v_telefono_norm limit 1;
    end if;

    -- Si sigue sin resolverse, es cliente nuevo: se crea con la normalizacion.
    if v_customer_id is null then
      if p_nombre is null or length(trim(p_nombre)) = 0 then
        raise exception 'Para un cliente nuevo el nombre es obligatorio.';
      end if;
      insert into clientes (
        nombre, correo, correo_norm, telefono, telefono_norm,
        direccion, ciudad, departamento, pais, notas
      ) values (
        trim(p_nombre), p_correo, v_correo_norm, p_telefono, v_telefono_norm,
        p_direccion, p_ciudad, p_departamento,
        coalesce(nullif(trim(p_pais), ''), 'Colombia'), p_notas_cliente
      )
      returning id into v_customer_id;
    end if;
  else
    -- Se paso un customer_id explicito: validar que exista.
    perform 1 from clientes where id = v_customer_id;
    if not found then
      raise exception 'El cliente % no existe.', v_customer_id;
    end if;
  end if;

  -- (2) CREAR LA ORDEN -----------------------------------------------------
  insert into pedidos (customer_id, fecha_orden, estado, canal, total, notas)
  values (v_customer_id, v_fecha, 'recibido', v_canal, 0, p_notas_pedido)
  returning id into v_pedido_id;

  -- (3) LINEAS + TOTAL, y (4) BAJA DE STOCK por cada item ------------------
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_cantidad   := (v_item->>'cantidad')::integer;
    v_precio     := (v_item->>'precio_unitario')::bigint;

    if v_product_id is null then
      raise exception 'Cada item requiere product_id.';
    end if;
    if v_cantidad is null or v_cantidad <= 0 then
      raise exception 'La cantidad de cada item debe ser un entero positivo.';
    end if;
    if v_precio is null or v_precio < 0 then
      raise exception 'El precio_unitario de cada item debe ser un bigint no negativo.';
    end if;

    v_subtotal := v_cantidad::bigint * v_precio;
    v_total := v_total + v_subtotal;

    insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
    values (v_pedido_id, v_product_id, v_cantidad, v_precio, v_subtotal);

    -- BAJA DE STOCK: insert directo de la 'salida' en el libro (ver DECISION DE
    -- CRITERIO en la cabecera). Mismo conjunto de columnas y logica de signo que
    -- inv_registrar_movimiento; estampa customer_id y referencia=pedido_id. Una
    -- salida sin stock NO se bloquea (contrato del libro, §2).
    insert into movimientos_inventario (
      product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
    ) values (
      v_product_id, 'salida', v_cantidad, 'Venta', v_pedido_id::text, v_customer_id, v_fecha
    );
  end loop;

  -- Total definitivo del pedido (bigint).
  update pedidos set total = v_total, actualizado = now() where id = v_pedido_id;

  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'customer_id', v_customer_id,
    'total', v_total
  );
end;
$$;

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is 'NUCLEO UNICO de creacion de pedido (dos puertas: manual hoy, web futura via canal). Transaccional: resuelve/crea cliente (ante colision del UNIQUE parcial resuelve al existente, no falla ni duplica, §4.5), inserta pedidos + pedido_items con precio real, calcula total bigint y baja stock con un INSERT directo de salida (motivo=Venta, referencia=pedido_id, customer_id estampado) en el libro -- NO llama inv_registrar_movimiento (no acopla areas ni exige permiso de inventario; salida sin stock no se bloquea). Devuelve jsonb {pedido_id, customer_id, total}. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- anular_pedido: anulacion logica + reversion de stock, TRANSACCIONAL (§5.3).
-- Marca pedidos.anulado=true + motivo_anulacion + estado='anulado' y, por cada
-- pedido_item, registra una ENTRADA compensatoria en el libro (insert directo,
-- tipo='entrada', motivo='Anulacion de venta', referencia=pedido_id,
-- customer_id del pedido). NUNCA borra: el libro conserva la salida original y
-- la entrada compensatoria (auditable de punta a punta). Idempotente en efecto:
-- si el pedido ya esta anulado, no revierte de nuevo. Devuelve jsonb
-- {pedido_id, revertidos}.
-- ------------------------------------------------------------
create or replace function anular_pedido(
  p_pedido_id uuid,
  p_motivo    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado     boolean;
  v_customer_id uuid;
  v_fecha       date;
  v_revertidos  integer := 0;
  v_item        record;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  select anulado, customer_id, fecha_orden
    into v_anulado, v_customer_id, v_fecha
    from pedidos
   where id = p_pedido_id;

  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  -- Si ya estaba anulado, no se revierte otra vez (evita entradas duplicadas).
  if v_anulado then
    return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', 0);
  end if;

  -- Marca la anulacion logica (nunca DELETE).
  update pedidos
     set anulado = true,
         estado = 'anulado',
         motivo_anulacion = p_motivo,
         actualizado = now()
   where id = p_pedido_id;

  -- Entrada compensatoria por cada linea (devuelve al inventario lo restado).
  for v_item in
    select product_id, cantidad from pedido_items where pedido_id = p_pedido_id
  loop
    insert into movimientos_inventario (
      product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
    ) values (
      v_item.product_id, 'entrada', v_item.cantidad, 'Anulacion de venta',
      p_pedido_id::text, v_customer_id, coalesce(v_fecha, current_date)
    );
    v_revertidos := v_revertidos + 1;
  end loop;

  return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', v_revertidos);
end;
$$;

comment on function anular_pedido(uuid, text) is 'Anula un pedido de forma logica y reversible, transaccional (§5.3): marca anulado=true + estado=anulado + motivo_anulacion (nunca DELETE) y registra una ENTRADA compensatoria por cada pedido_item en el libro (insert directo, motivo=Anulacion de venta, referencia=pedido_id, customer_id del pedido) -- NO llama inv_registrar_movimiento. Si el pedido ya estaba anulado no revierte de nuevo. Devuelve jsonb {pedido_id, revertidos}. Exige tiene_acceso_ventas().';

-- ------------------------------------------------------------
-- avanzar_estado_pedido: mueve el estado del pedido a lo largo del ciclo de
-- vida operativo (recibido -> preparando -> en_camino -> entregado, §5.1).
--
-- POR QUE ES UNA RPC Y NO UN UPDATE DIRECTO: pedidos es SELECT-only bajo RLS
-- (ver 20250401000300_ventas_rls.sql); NO tiene policy de UPDATE, asi que un
-- UPDATE directo desde el navegador lo rechaza Postgres. Como el resto de la
-- escritura de Ventas, el avance de estado pasa por una RPC security definer
-- que salta RLS de forma controlada tras validar tiene_acceso_ventas().
--
-- ANULAR NO VA POR AQUI: 'anulado' NO es un estado destino valido de esta RPC.
-- La anulacion tiene su propia RPC (anular_pedido) porque ademas de cambiar el
-- estado REVIERTE el stock con una entrada compensatoria en el libro; hacerlo
-- por un simple cambio de estado dejaria el inventario descuadrado. Aqui solo
-- se avanza el ciclo operativo, sin tocar el libro.
--
-- REGLAS: (1) el estado destino debe estar en el flujo operativo
-- (recibido/preparando/en_camino/entregado); (2) el pedido debe existir; (3) un
-- pedido ya anulado NO se avanza (es terminal). No impone la direccion del
-- flujo (permite corregir un estado marcado por error); el tablero propone el
-- siguiente paso, pero la RPC acepta cualquier estado valido del flujo.
--
-- Hace update pedidos set estado=p_nuevo_estado, actualizado=now(). Devuelve
-- jsonb {pedido_id, estado}. IDEMPOTENTE (create or replace); reaplicar el mismo
-- estado no causa dano (queda igual, solo refresca actualizado).
-- ------------------------------------------------------------
create or replace function avanzar_estado_pedido(
  p_pedido_id    uuid,
  p_nuevo_estado text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado boolean;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  -- 'anulado' se excluye a proposito: la anulacion va por anular_pedido (revierte
  -- stock). Aqui solo se avanza el ciclo operativo.
  if p_nuevo_estado is null or p_nuevo_estado not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'Estado invalido: %. Use recibido, preparando, en_camino o entregado (para anular use anular_pedido).', p_nuevo_estado;
  end if;

  select anulado into v_anulado from pedidos where id = p_pedido_id;

  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  -- Un pedido anulado es terminal: no se avanza (para reactivarlo habria que
  -- registrar uno nuevo; la anulacion ya devolvio el stock al libro).
  if v_anulado then
    raise exception 'El pedido % esta anulado y no admite avance de estado.', p_pedido_id;
  end if;

  update pedidos
     set estado = p_nuevo_estado,
         actualizado = now()
   where id = p_pedido_id;

  return jsonb_build_object('pedido_id', p_pedido_id, 'estado', p_nuevo_estado);
end;
$$;

comment on function avanzar_estado_pedido(uuid, text) is 'Avanza el estado operativo de un pedido (recibido/preparando/en_camino/entregado, §5.1) via RPC security definer, porque pedidos es SELECT-only bajo RLS y un UPDATE directo lo rechaza Postgres. NO acepta anulado como destino: la anulacion va por anular_pedido (que ademas revierte stock). Valida tiene_acceso_ventas(), que el estado destino este en el flujo, que el pedido exista y que NO este anulado (terminal). Hace update de pedidos.estado + actualizado=now(). Devuelve jsonb {pedido_id, estado}. Idempotente.';
