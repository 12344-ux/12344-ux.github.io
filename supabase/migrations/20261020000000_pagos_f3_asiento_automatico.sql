-- ============================================================
-- MAGANDHI · PAGOS WEB · F3 · ASIENTO CONTABLE AUTOMATICO
--                            + CORREO «RECIBIDO» AUTOMATICO
-- ------------------------------------------------------------
-- Diseno: docs/PLANO-PAGOS.md §10. Runbook: supabase/INSTRUCCIONES.md «Pagos F3».
--
-- LA PROMESA DE ESTE TRAMO: cada venta web pagada DE VERDAD queda en los libros
-- EXACTAMENTE UNA VEZ, cuadrada al peso, sin que nadie la escriba a mano. Si el
-- pedido se anula, el contraasiento la deja en cero. Y el cliente recibe solo el
-- correo de «Recibido» de su pedido.
--
-- DECISIONES DEL DUENO (8 y 9-oct-2026):
--   (1) Wompi NO consigna el dia de la venta: lo hace dias despues y YA SIN su
--       comision. Por eso la venta se registra contra una cuenta puente,
--       138095 «Otros» (deudores varios: plata en Wompi por liquidar), y se
--       salda A MANO cuando llega la consignacion: banco por el neto + 530515
--       por la comision contra 138095 por el bruto. Si 138095 no queda en cero,
--       falta una consignacion: la cuenta se autoconcilia.
--   (2) Comision de Wompi -> 530515 COMISIONES. No se automatiza: el evento de
--       Wompi no la informa (verificado en su documentacion).
--   (3) Las cuentas configuradas eran de grupo (1110, 4135, 5305, 6135, 1435:
--       no imputables): se bajan a subcuenta. Se agregan al PUC las cuentas que
--       usa el ciclo de venta y que faltaban.
--   (4) La venta NUNCA falla por contabilidad: si el asiento no se puede crear,
--       el pedido se crea igual y la venta sale en el aviso «ventas web sin
--       asiento» de Finanzas, con el motivo y un boton para generarlo.
--   (5) Validacion al CONFIGURAR: una cuenta inexistente o de grupo se rechaza
--       cuando se escribe en contabilidad_config, no tres ventas despues.
--   (6) El correo «Recibido» de un pedido web sale solo. El texto sigue en
--       correo_plantillas: se cambia sin tocar codigo.
-- DECISIONES DE DISENO (agente, 9-oct-2026):
--   (7) Un pago de PRUEBA (sandbox) crea pedido (F2) pero NO se contabiliza: no
--       movio dinero. Impulse no registra hechos que no ocurrieron.
--   (8) El IVA de las ventas NO se supone: contabilidad_config.iva_ventas_pct
--       nace VACIO y, mientras lo este, la venta queda pendiente con ese motivo.
--       0 = no responsable de IVA (el ingreso va completo a 413505). 5 o 19 =
--       precio con IVA incluido (el IVA se separa en 240805). Lo confirma el
--       contador.
--   (9) Un asiento automatico no se edita ni se anula desde Finanzas: se
--       corrige anulando el pedido (contraasiento). Asi Ventas, Inventario y
--       Finanzas nunca se contradicen.
--  (10) H4 · Fechas de Colombia: el pedido web y su asiento toman la fecha de
--       America/Bogota (la base corre en UTC: una compra despues de las 7 p. m.
--       quedaba con fecha del dia siguiente y podia saltar de mes o de ano).
--
-- QUE CAMBIA:
--   (A) PUC: 138095 (nueva) y 135518 con su nombre oficial.
--   (B) contabilidad_config: subcuentas, cuenta puente, IVA y validacion.
--   (C) asientos: origen + origen_ref + un solo asiento por pedido y tipo.
--   (D) Constructores internos: fz__asiento_venta_web / fz__reverso_venta_web.
--   (E) pw_procesar_pago: fecha de Colombia + asiento automatico.
--   (F) anular_pedido: contraasiento automatico.
--   (G) editar_asiento / anular_asiento: protegen los asientos automaticos.
--   (H) Panel de Finanzas: aviso de pendientes y boton «Generar asiento».
--   (I) Correo «Recibido» automatico: dos puertas solo para el servidor.
--
-- QUE NO CAMBIA: crear_pedido, el candado de stock, la idempotencia de F2, los
-- informes de Finanzas (ya leen solo asientos activos e imputables), los
-- asientos manuales y sus pantallas.
--
-- Forward e idempotente. REQUISITO: despues de 20261019000000 (F2).
-- ============================================================

-- ============================================================
-- (A) PUC · cuentas del ciclo de venta
-- ------------------------------------------------------------
-- 138095 OTROS (deudores varios). Codigo OFICIAL del PUC (Decreto 2650): la
-- plata que Wompi recaudo y todavia no consigna. Si el dueno ya la creo a mano
-- con otro nombre, se respeta (do nothing).
-- ============================================================
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre)
values ('138095', 'OTROS (PASARELA WOMPI POR LIQUIDAR)', 4, 'debito', true, '1380')
on conflict (codigo) do nothing;

-- 135518 se cargo con un nombre que no es el oficial («IVA descontable»). En el
-- PUC, 135518 es IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO: justo la que hace
-- falta para la reteICA (0,2 %) que Wompi practica en los pagos con tarjeta
-- cuando liquida. Solo se corrige si nadie la ha usado: si tiene movimientos,
-- se deja como esta y se avisa (un cambio de nombre no puede cambiar el
-- significado de asientos ya escritos).
do $$
begin
  if exists (select 1 from puc_cuentas
              where codigo = '135518'
                and nombre = 'IMPUESTO SOBRE LAS VENTAS DESCONTABLE (IVA DESCONTABLE)') then
    if exists (select 1 from asiento_lineas where cuenta_codigo = '135518') then
      raise notice 'F3: la cuenta 135518 tiene movimientos con el nombre anterior (IVA descontable). No se renombra: revisalo con el contador.';
    else
      update puc_cuentas
         set nombre = 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO'
       where codigo = '135518';
    end if;
  end if;
end $$;

-- ============================================================
-- (B) contabilidad_config · subcuentas, cuenta puente, IVA, validacion
-- ============================================================
alter table contabilidad_config add column if not exists cuenta_pasarela     text not null default '138095';
alter table contabilidad_config add column if not exists cuenta_iva_generado text not null default '240805';
alter table contabilidad_config add column if not exists iva_ventas_pct      smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'contabilidad_config_iva_valido') then
    alter table contabilidad_config
      add constraint contabilidad_config_iva_valido
      check (iva_ventas_pct is null or iva_ventas_pct in (0, 5, 19));
  end if;
end $$;

-- Defaults clonables (otra organizacion Impulse nace con subcuentas validas).
alter table contabilidad_config alter column cuenta_banco      set default '111005';
alter table contabilidad_config alter column cuenta_ingreso    set default '413505';
alter table contabilidad_config alter column cuenta_comision   set default '530515';
alter table contabilidad_config alter column cuenta_costo      set default '613505';
alter table contabilidad_config alter column cuenta_inventario set default '143505';

-- La fila unica, por si no existiera (nace con los defaults de arriba).
insert into contabilidad_config (id) values (1) on conflict (id) do nothing;

-- H1 · bajar de grupo a subcuenta, SOLO donde siga el valor viejo: si el dueno
-- ya ajusto una cuenta a mano, no se pisa.
update contabilidad_config set cuenta_banco      = '111005' where id = 1 and cuenta_banco      = '1110';
update contabilidad_config set cuenta_ingreso    = '413505' where id = 1 and cuenta_ingreso    = '4135';
update contabilidad_config set cuenta_comision   = '530515' where id = 1 and cuenta_comision   = '5305';
update contabilidad_config set cuenta_costo      = '613505' where id = 1 and cuenta_costo      = '6135';
update contabilidad_config set cuenta_inventario = '143505' where id = 1 and cuenta_inventario = '1435';

comment on column contabilidad_config.cuenta_banco      is 'Banco donde Wompi consigna (default 111005 MONEDA NACIONAL). La usa el asiento MANUAL de liquidacion de Wompi; el asiento de la venta no va al banco (va a cuenta_pasarela).';
comment on column contabilidad_config.cuenta_ingreso    is 'Ingreso por venta (default 413505 VENTA DE MERCANCIAS). Lo LEE el asiento automatico de la venta web.';
comment on column contabilidad_config.cuenta_comision   is 'Comision de la pasarela (default 530515 COMISIONES, decision del dueno 9-oct-2026). La usa el asiento MANUAL de liquidacion: el evento de Wompi no informa la comision.';
comment on column contabilidad_config.cuenta_costo      is 'Costo de ventas (default 613505). Lo LEE el asiento automatico con el costo_unitario del producto.';
comment on column contabilidad_config.cuenta_inventario is 'Inventario que sale con la venta (default 143505). Lo LEE el asiento automatico.';
comment on column contabilidad_config.cuenta_pasarela   is 'Cuenta PUENTE: plata recaudada por Wompi y aun no consignada (default 138095 OTROS, deudores varios). La venta web la DEBITA; la liquidacion manual de Wompi la ACREDITA. Saldo distinto de cero = consignaciones pendientes.';
comment on column contabilidad_config.cuenta_iva_generado is 'IVA generado en ventas (default 240805). Solo se usa si iva_ventas_pct > 0.';
comment on column contabilidad_config.iva_ventas_pct    is 'IVA incluido en el precio web: 0 (no responsable de IVA: todo el precio es ingreso), 5 o 19. NULL = sin definir: la venta web se crea pero su asiento queda pendiente hasta que el dueno lo defina (no se supone). Lo confirma el contador.';

-- Validacion AL CONFIGURAR: cada cuenta debe existir y ser imputable.
create or replace function fz__validar_contabilidad_config()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r     record;
  v_imp boolean;
begin
  for r in
    select * from (values
      (new.cuenta_banco,        'banco'),
      (new.cuenta_ingreso,      'ingreso por ventas'),
      (new.cuenta_comision,     'comision de la pasarela'),
      (new.cuenta_costo,        'costo de ventas'),
      (new.cuenta_inventario,   'inventario de mercancias'),
      (new.cuenta_pasarela,     'plata en la pasarela por liquidar'),
      (new.cuenta_iva_generado, 'IVA generado')
    ) as t(codigo, rol)
  loop
    select imputable into v_imp from puc_cuentas where codigo = r.codigo;
    if v_imp is null then
      raise exception 'La cuenta % (%) no existe en el catalogo PUC. Agregala primero o elige otra.', r.codigo, r.rol;
    elsif not v_imp then
      raise exception 'La cuenta % (%) es de grupo, no imputable: en el PUC no se registra en un grupo. Usa una de sus subcuentas de 6 digitos.', r.codigo, r.rol;
    end if;
  end loop;
  return new;
end;
$$;

comment on function fz__validar_contabilidad_config() is 'F3 · trigger de contabilidad_config: rechaza AL CONFIGURAR una cuenta que no exista en el PUC o que sea de grupo (no imputable), con un mensaje claro. Asi el error se ve cuando se comete, no tres ventas despues.';

drop trigger if exists trg_contabilidad_config_validar on contabilidad_config;
create trigger trg_contabilidad_config_validar
  before insert or update on contabilidad_config
  for each row execute function fz__validar_contabilidad_config();

-- ============================================================
-- (C) asientos · origen
-- ------------------------------------------------------------
-- manual            lo escribe una persona en Finanzas (todos los de hoy).
-- venta_web         lo genera el sistema al confirmarse un pago web real.
-- reverso_venta_web lo genera el sistema al anular ese pedido.
-- origen_ref = pedido_id (sin FK dura, como el resto de cruces entre modulos).
-- El indice unico garantiza UN asiento de venta y UN reverso por pedido.
-- ============================================================
alter table asientos add column if not exists origen     text not null default 'manual';
alter table asientos add column if not exists origen_ref uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'asientos_origen_valido') then
    alter table asientos add constraint asientos_origen_valido
      check (origen in ('manual', 'venta_web', 'reverso_venta_web'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'asientos_origen_ref_coherente') then
    alter table asientos add constraint asientos_origen_ref_coherente
      check ((origen = 'manual') = (origen_ref is null));
  end if;
end $$;

create unique index if not exists asientos_un_automatico_uidx
  on asientos (origen, origen_ref) where origen <> 'manual';

comment on column asientos.origen     is 'manual (lo escribe una persona) | venta_web (lo genera el sistema al confirmarse un pago web real) | reverso_venta_web (contraasiento al anular ese pedido). Los automaticos no se editan ni se anulan desde Finanzas.';
comment on column asientos.origen_ref is 'pedido_id del asiento automatico (null en los manuales). Sin FK dura entre modulos; un solo asiento por (origen, origen_ref).';

-- ============================================================
-- (D) Constructores internos (solo los llaman funciones security definer)
-- ============================================================

-- Fecha de Colombia (H4). El parametro permite probar el cambio de dia.
create or replace function fz__fecha_colombia(p_momento timestamptz default now())
returns date
language sql
stable
set search_path = public
as $$
  select (p_momento at time zone 'America/Bogota')::date;
$$;

comment on function fz__fecha_colombia(timestamptz) is 'F3 · fecha calendario de Colombia (America/Bogota) de un momento. La base corre en UTC: sin esto una compra despues de las 7 p. m. quedaba con la fecha del dia siguiente.';

-- Lineas del asiento de una venta web. NO escribe nada: arma, valida con la
-- regla de oro (fz_validar_lineas) y devuelve el jsonb. Si falta un dato lanza
-- el motivo en lenguaje claro (es lo que ve el dueno en el aviso de Finanzas).
create or replace function fz__lineas_venta_web(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c           contabilidad_config;
  v_total     bigint;
  v_base      bigint;
  v_iva       bigint := 0;
  v_costo     bigint := 0;
  v_sin_costo text;
  v_productos text;
  v_lineas    jsonb;
begin
  select * into c from contabilidad_config where id = 1;
  if not found then
    raise exception 'Falta la configuracion contable (contabilidad_config): sin ella no se sabe a que cuentas va la venta.';
  end if;
  if c.iva_ventas_pct is null then
    raise exception 'Falta definir el IVA de las ventas web: 0 si MAGANDHI no es responsable de IVA, 5 o 19 si lo es (precio con IVA incluido). Se define una sola vez en contabilidad_config.iva_ventas_pct; lo confirma el contador.';
  end if;

  select total into v_total from pedidos where id = p_pedido_id;
  if v_total is null then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_total <= 0 then
    raise exception 'El pedido no tiene un total positivo: no hay venta que registrar.';
  end if;

  -- Costo de venta = costo_unitario ACTUAL del producto x cantidad (no hay costo
  -- por lote). null = costo desconocido: NO se inventa, la venta queda pendiente.
  select string_agg(distinct pr.nombre, ', ') filter (where pr.costo_unitario is null),
         coalesce(sum(pi.cantidad::bigint * pr.costo_unitario), 0),
         string_agg(pr.nombre || ' x ' || pi.cantidad, ', ' order by pr.nombre)
    into v_sin_costo, v_costo, v_productos
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
   where pi.pedido_id = p_pedido_id;

  if v_productos is null then
    raise exception 'El pedido no tiene productos: no hay venta que registrar.';
  end if;
  if v_sin_costo is not null then
    raise exception 'Falta el costo unitario de «%» en Inventario. Registralo en la ficha del producto y vuelve a generar el asiento (no se inventa un costo).', v_sin_costo;
  end if;

  -- IVA incluido en el precio: base = total / (1 + t), redondeada al peso; el
  -- IVA es la diferencia, asi el asiento SIEMPRE cuadra.
  if c.iva_ventas_pct > 0 then
    v_base := round(v_total::numeric * 100 / (100 + c.iva_ventas_pct))::bigint;
    v_iva  := v_total - v_base;
  else
    v_base := v_total;
  end if;

  -- La referencia de Wompi va en la DESCRIPCION del asiento (la que muestra el
  -- Libro Mayor): con ella se concilia cada venta contra la consignacion.
  v_lineas := jsonb_build_array(
    jsonb_build_object('cuenta_codigo', c.cuenta_pasarela,
                       'detalle', 'Wompi por liquidar',
                       'debe', v_total, 'haber', 0),
    jsonb_build_object('cuenta_codigo', c.cuenta_ingreso,
                       'detalle', 'Venta web: ' || v_productos,
                       'debe', 0, 'haber', v_base));
  if v_iva > 0 then
    v_lineas := v_lineas || jsonb_build_object('cuenta_codigo', c.cuenta_iva_generado,
                       'detalle', 'IVA generado ' || c.iva_ventas_pct || ' % (incluido en el precio)',
                       'debe', 0, 'haber', v_iva);
  end if;
  if v_costo > 0 then
    v_lineas := v_lineas
      || jsonb_build_object('cuenta_codigo', c.cuenta_costo,
                            'detalle', 'Costo de venta: ' || v_productos,
                            'debe', v_costo, 'haber', 0)
      || jsonb_build_object('cuenta_codigo', c.cuenta_inventario,
                            'detalle', 'Salida de inventario: ' || v_productos,
                            'debe', 0, 'haber', v_costo);
  end if;

  -- La misma regla de oro de los asientos manuales: enteros, imputables, cuadre.
  perform fz_validar_lineas(v_lineas);
  return v_lineas;
end;
$$;

comment on function fz__lineas_venta_web(uuid) is 'F3 · arma y VALIDA (fz_validar_lineas) las lineas del asiento de una venta web, sin escribir nada: Debito cuenta_pasarela por el total; Credito ingreso por la base (y IVA generado si iva_ventas_pct > 0); Debito costo / Credito inventario por cantidad x costo_unitario. Lanza el motivo en lenguaje claro si falta configuracion, IVA o costo. Uso interno.';

-- Lineas del contraasiento: las del asiento original con debe y haber
-- invertidos (mismas cuentas). Validadas con la regla de oro.
create or replace function fz__lineas_reverso(p_asiento_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lineas jsonb;
begin
  select jsonb_agg(jsonb_build_object(
           'cuenta_codigo', cuenta_codigo,
           'detalle', 'Reverso · ' || coalesce(detalle, ''),
           'debe', haber,
           'haber', debe) order by orden)
    into v_lineas
    from asiento_lineas
   where asiento_id = p_asiento_id;

  perform fz_validar_lineas(v_lineas);
  return v_lineas;
end;
$$;

comment on function fz__lineas_reverso(uuid) is 'F3 · lineas del contraasiento: las del asiento original con debe y haber invertidos, mismas cuentas, validadas con la regla de oro. Uso interno.';

-- Asiento de la venta web. Idempotente (un pedido, un asiento). Lanza el
-- motivo si no se puede: el que llama decide (el webhook NUNCA tumba la venta).
create or replace function fz__asiento_venta_web(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ped    record;
  v_int    record;
  v_id     uuid;
  v_lineas jsonb;
  v_linea  jsonb;
  v_orden  int := 0;
begin
  -- Bloqueo del pedido: serializa con anular_pedido y con un doble clic en
  -- «Generar asiento».
  select id, canal, anulado, fecha_orden into v_ped
    from pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  -- Idempotencia primero.
  select id into v_id from asientos where origen = 'venta_web' and origen_ref = p_pedido_id;
  if found then
    return jsonb_build_object('resultado', 'ya_existia', 'asiento_id', v_id);
  end if;

  if v_ped.canal is distinct from 'web' then
    raise exception 'Solo las ventas web se contabilizan solas; este pedido es de canal %.', coalesce(v_ped.canal, 'desconocido');
  end if;

  select referencia, entorno into v_int
    from pagos_intencion
   where pedido_id = p_pedido_id and estado = 'procesada'
   order by procesada_en desc nulls last
   limit 1;
  if not found then
    raise exception 'El pedido web no tiene un pago aprobado asociado: no hay venta que contabilizar.';
  end if;

  -- Un pago de prueba no movio dinero: no es un hecho contable.
  if v_int.entorno is distinct from 'prod' then
    return jsonb_build_object('resultado', 'omitido',
      'motivo', 'Pago de prueba (sandbox): no movio dinero real y no se contabiliza.');
  end if;

  if v_ped.anulado then
    raise exception 'El pedido esta anulado: ya no requiere asiento de venta.';
  end if;

  v_lineas := fz__lineas_venta_web(p_pedido_id);

  -- creado_por = null: lo escribio el sistema. La bitacora igual registra a la
  -- persona si fue ella quien pulso «Generar asiento» (auth.uid()).
  insert into asientos (fecha, descripcion, estado, creado_por, origen, origen_ref)
  values (v_ped.fecha_orden,
          'Venta web · pedido ' || correo_ref_pedido(p_pedido_id) || ' · Wompi ' || v_int.referencia,
          'activo', null, 'venta_web', p_pedido_id)
  returning id into v_id;

  for v_linea in select * from jsonb_array_elements(v_lineas) loop
    v_orden := v_orden + 1;
    insert into asiento_lineas (asiento_id, cuenta_codigo, detalle, debe, haber, orden)
    values (v_id, v_linea->>'cuenta_codigo', v_linea->>'detalle',
            coalesce((v_linea->>'debe')::bigint, 0),
            coalesce((v_linea->>'haber')::bigint, 0),
            v_orden);
  end loop;

  return jsonb_build_object('resultado', 'creado', 'asiento_id', v_id);
end;
$$;

comment on function fz__asiento_venta_web(uuid) is 'F3 · crea el asiento de una venta web PAGADA DE VERDAD (entorno prod), con fecha = fecha del pedido (Colombia), origen venta_web y origen_ref = pedido. Idempotente (devuelve ya_existia). Un pago sandbox devuelve omitido. Lanza el motivo si falta configuracion, IVA o costo, o si el pedido esta anulado. Uso interno: pw_procesar_pago y fz_generar_asiento_automatico.';

-- Contraasiento al anular. Idempotente. Si la venta nunca llego a los libros,
-- no hay nada que reversar (sin_asiento).
create or replace function fz__reverso_venta_web(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado boolean;
  v_orig    record;
  v_id      uuid;
  v_lineas  jsonb;
  v_linea   jsonb;
  v_orden   int := 0;
begin
  select anulado into v_anulado from pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  select id into v_id from asientos where origen = 'reverso_venta_web' and origen_ref = p_pedido_id;
  if found then
    return jsonb_build_object('resultado', 'ya_existia', 'asiento_id', v_id);
  end if;

  select id, descripcion into v_orig
    from asientos
   where origen = 'venta_web' and origen_ref = p_pedido_id and estado = 'activo';
  if not found then
    return jsonb_build_object('resultado', 'sin_asiento');
  end if;

  if not v_anulado then
    raise exception 'El pedido no esta anulado: el contraasiento solo se registra al anularlo en Ventas.';
  end if;

  v_lineas := fz__lineas_reverso(v_orig.id);

  -- Fecha del HECHO (la anulacion), en hora de Colombia. El asiento original no
  -- se toca: queda la venta y su reverso, y el neto es cero.
  insert into asientos (fecha, descripcion, estado, creado_por, origen, origen_ref)
  values (fz__fecha_colombia(),
          'Reverso por anulacion · ' || v_orig.descripcion,
          'activo', null, 'reverso_venta_web', p_pedido_id)
  returning id into v_id;

  for v_linea in select * from jsonb_array_elements(v_lineas) loop
    v_orden := v_orden + 1;
    insert into asiento_lineas (asiento_id, cuenta_codigo, detalle, debe, haber, orden)
    values (v_id, v_linea->>'cuenta_codigo', v_linea->>'detalle',
            coalesce((v_linea->>'debe')::bigint, 0),
            coalesce((v_linea->>'haber')::bigint, 0),
            v_orden);
  end loop;

  return jsonb_build_object('resultado', 'creado', 'asiento_id', v_id);
end;
$$;

comment on function fz__reverso_venta_web(uuid) is 'F3 · contraasiento de una venta web anulada: mismas cuentas con debe y haber invertidos, fecha de la anulacion (Colombia), origen reverso_venta_web. Idempotente. Si la venta no tenia asiento devuelve sin_asiento. Uso interno: anular_pedido y fz_generar_asiento_automatico.';

-- ============================================================
-- (E) pw_procesar_pago · MISMA firma y MISMO cuerpo que en 20261019000000,
--     con dos cambios: (1) el pedido toma la fecha de Colombia (H4) y
--     (2) al final, el asiento automatico (paso 8), que nunca tumba la venta.
-- ============================================================
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
  v_asiento    jsonb;
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
      -- F3 · H4: fecha calendario de COLOMBIA (la base esta en UTC).
      p_fecha_orden   => fz__fecha_colombia(),
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

  -- (8) F3 · ASIENTO CONTABLE AUTOMATICO. Va al final porque lee la intencion
  --     ya procesada. NUNCA tumba la venta: la plata entro y el producto salio
  --     (eso es un hecho); si el asiento falla, el pedido queda y la venta sale
  --     en «ventas web sin asiento» de Finanzas con el motivo.
  begin
    v_asiento := fz__asiento_venta_web(v_pedido_id);
  exception when others then
    v_asiento := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object('resultado', 'procesado', 'pedido_id', v_pedido_id,
                            'asiento', v_asiento);
end;
$$;

comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is 'PAGOS WEB · corazon de F2 (+F3): convierte un pago aprobado en pedido EXACTAMENTE UNA VEZ, en una sola transaccion. Orden: (1) registra el evento (idempotencia por transaccion_id+estado; un reintento devuelve repetido), (2) bloquea la intencion for update, (3) si ya estaba procesada devuelve el mismo pedido, (4) DECLINED/VOIDED/ERROR la cierran como rechazada, (5) compara el monto contra el FIRMADO, (6) crea el pedido canal=web con la fecha de Colombia reutilizando el candado de stock de crear_pedido y, si falla, deja requiere_revision con el motivo, (7) copia el utm_campaign al pedido, (8) F3: crea el asiento contable (venta real) sin tumbar nunca la venta; devuelve asiento {resultado, asiento_id | motivo}. El precio no se relee: se respeta lo firmado. Solo service_role.';

-- ============================================================
-- (F) anular_pedido · MISMA firma y MISMO cuerpo que en 20250606000100 (Tramo
--     0: FOR UPDATE), con un paso nuevo al final: el contraasiento de la venta
--     web, que nunca impide la anulacion.
-- ============================================================
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
  v_estado_ant  text;
  v_revertidos  integer := 0;
  v_item        record;
  v_reverso     jsonb;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;

  -- TRAMO 0: FOR UPDATE bloquea la fila del pedido hasta el fin de la
  -- transaccion. Una anulacion concurrente espera aqui y luego lee el valor
  -- ya actualizado (anulado=true), por lo que no revierte dos veces.
  select anulado, customer_id, fecha_orden, estado
    into v_anulado, v_customer_id, v_fecha, v_estado_ant
    from pedidos
   where id = p_pedido_id
     for update;

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
  -- No se exige producto activo: anular una venta de un producto dado de baja
  -- debe poder devolver el stock (ver 20250603000000).
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

  insert into pedido_bitacora (pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor)
  values (
    p_pedido_id, 'anular', v_estado_ant, 'anulado',
    jsonb_build_object('motivo', p_motivo, 'revertidos', v_revertidos),
    auth.uid()
  );

  -- F3 · CONTRAASIENTO de la venta web (si estaba en libros). Nunca impide la
  -- anulacion: si falla, queda en el aviso de Finanzas con su motivo.
  begin
    v_reverso := fz__reverso_venta_web(p_pedido_id);
  exception when others then
    v_reverso := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object('pedido_id', p_pedido_id, 'revertidos', v_revertidos,
                            'asiento_reverso', v_reverso);
end;
$$;

comment on function anular_pedido(uuid, text) is 'Anula un pedido de forma logica, transaccional y SIN CARRERAS (Tramo 0: FOR UPDATE). Marca anulado=true + estado=anulado + motivo (nunca DELETE), registra una ENTRADA compensatoria por cada pedido_item y un evento anular en pedido_bitacora. F3: si era una venta web con asiento, registra el contraasiento (fecha de la anulacion en Colombia) sin impedir nunca la anulacion. Si ya estaba anulado es un no-op. Devuelve jsonb {pedido_id, revertidos, asiento_reverso}. Exige tiene_acceso_ventas().';

-- ============================================================
-- (G) editar_asiento / anular_asiento · MISMAS firmas y MISMOS cuerpos que en
--     20250201000600, con UNA comprobacion nueva: un asiento automatico no se
--     toca desde Finanzas.
-- ============================================================
create or replace function editar_asiento(p_asiento_id uuid, p_fecha date, p_descripcion text, p_lineas jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_linea         jsonb;
  v_orden         int := 0;
  v_estado        text;
  v_fecha_ant     date;
  v_desc_ant      text;
  v_lineas_ant    jsonb;
  v_lineas_nuevas jsonb;
  v_cambio_cab    boolean;
  v_cambio_lin    boolean;
  v_origen        text;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  select estado, fecha, descripcion, origen
    into v_estado, v_fecha_ant, v_desc_ant, v_origen
    from asientos where id = p_asiento_id;
  if v_estado is null then
    raise exception 'El asiento % no existe.', p_asiento_id;
  end if;
  -- F3: los asientos automaticos se corrigen desde Ventas (anulando el pedido).
  if v_origen <> 'manual' then
    raise exception 'Este asiento lo genero el sistema (venta web) y no se edita a mano: asi Finanzas, Ventas e Inventario no se contradicen. Si la venta no procede, anula el pedido en Ventas y el sistema registra el contraasiento.';
  end if;
  if v_estado = 'anulado' then
    raise exception 'No se puede editar un asiento anulado. Cree uno nuevo.';
  end if;
  if p_descripcion is null or length(trim(p_descripcion)) = 0 then
    raise exception 'La descripcion del asiento es obligatoria.';
  end if;

  perform fz_validar_lineas(p_lineas);

  -- Snapshot de las lineas ANTERIORES (jsonb) para la bitacora: sin esto una
  -- edicion de importes no dejaria rastro del valor anterior de las lineas, lo
  -- que contradice "nada se borra en silencio". Modelo append-only intacto.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'cuenta_codigo', cuenta_codigo,
             'detalle', detalle,
             'debe', debe,
             'haber', haber,
             'orden', orden
           ) order by orden
         ), '[]'::jsonb)
    into v_lineas_ant
    from asiento_lineas
   where asiento_id = p_asiento_id;

  -- Normaliza las lineas NUEVAS al mismo shape para poder comparar y decidir
  -- si de verdad cambio algo (evita ensuciar la bitacora con ediciones vacias).
  v_orden := 0;
  select coalesce(jsonb_agg(elem order by ord), '[]'::jsonb)
    into v_lineas_nuevas
    from (
      select jsonb_build_object(
               'cuenta_codigo', ln->>'cuenta_codigo',
               'detalle', ln->>'detalle',
               'debe', coalesce((ln->>'debe')::bigint, 0),
               'haber', coalesce((ln->>'haber')::bigint, 0),
               'orden', row_number() over ()
             ) as elem,
             row_number() over () as ord
        from jsonb_array_elements(p_lineas) as ln
    ) t;

  v_cambio_cab := (v_fecha_ant is distinct from p_fecha)
               or (v_desc_ant  is distinct from p_descripcion);
  v_cambio_lin := (v_lineas_ant is distinct from v_lineas_nuevas);

  -- Si no cambia NADA (ni cabecera ni lineas), no tocar nada: no dispares el
  -- trigger ni registres un evento 'editar' sin contenido real.
  if not v_cambio_cab and not v_cambio_lin then
    return p_asiento_id;
  end if;

  -- Traza append-only del valor ANTERIOR: UN SOLO evento 'editar' que reune
  -- la cabecera anterior (fecha/descripcion) y, cuando cambian, las lineas
  -- anteriores (detalle_cambio.lineas). Se registra ANTES del delete/update,
  -- de modo que un asiento que no valida nunca llega a dejar traza. El trigger
  -- de bitacora NO registra ediciones (ver 20250201000400): esta RPC es la
  -- fuente unica del evento 'editar', asi el timeline no lo muestra duplicado.
  insert into asiento_bitacora (asiento_id, accion, detalle_cambio, actor)
  values (
    p_asiento_id,
    'editar',
    jsonb_build_object(
      'fecha', v_fecha_ant,
      'descripcion', v_desc_ant,
      'lineas', v_lineas_ant
    ),
    auth.uid()
  );

  -- Actualiza cabecera. El trigger de bitacora ya NO registra 'editar' por este
  -- UPDATE (solo cubre crear/anular), de modo que no se duplica el evento.
  update asientos
     set fecha = p_fecha,
         descripcion = p_descripcion,
         actualizado = now()
   where id = p_asiento_id;

  -- Reemplaza las lineas: borra las viejas y crea las nuevas. El borrado
  -- de lineas hijas es interno de la edicion (no es borrado de asientos);
  -- la cabecera y su historia se conservan intactas en asiento_bitacora.
  delete from asiento_lineas where asiento_id = p_asiento_id;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    v_orden := v_orden + 1;
    insert into asiento_lineas (asiento_id, cuenta_codigo, detalle, debe, haber, orden)
    values (
      p_asiento_id,
      v_linea->>'cuenta_codigo',
      v_linea->>'detalle',
      coalesce((v_linea->>'debe')::bigint, 0),
      coalesce((v_linea->>'haber')::bigint, 0),
      v_orden
    );
  end loop;

  return p_asiento_id;
end;
$$;

comment on function editar_asiento(uuid, date, text, jsonb) is 'Edita un asiento activo MANUAL: reemplaza cabecera y lineas tras revalidar la regla de oro. Registra UN SOLO evento editar en asiento_bitacora con el valor ANTERIOR de cabecera (fecha/descripcion) y lineas (detalle_cambio.lineas) antes de tocar nada. Si no cambia nada es un no-op. No permite editar asientos anulados. F3: rechaza los asientos automaticos (origen distinto de manual): se corrigen anulando el pedido en Ventas.';

create or replace function anular_asiento(p_asiento_id uuid, p_motivo text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
  v_origen text;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  select estado, origen into v_estado, v_origen from asientos where id = p_asiento_id;
  if v_estado is null then
    raise exception 'El asiento % no existe.', p_asiento_id;
  end if;
  -- F3: los asientos automaticos se corrigen desde Ventas (anulando el pedido).
  if v_origen <> 'manual' then
    raise exception 'Este asiento lo genero el sistema (venta web) y no se anula a mano: asi Finanzas, Ventas e Inventario no se contradicen. Si la venta no procede, anula el pedido en Ventas y el sistema registra el contraasiento.';
  end if;
  if v_estado = 'anulado' then
    raise exception 'El asiento ya estaba anulado.';
  end if;

  update asientos
     set estado = 'anulado',
         actualizado = now(),
         descripcion = case
           when p_motivo is not null and length(trim(p_motivo)) > 0
             then descripcion || ' [ANULADO: ' || p_motivo || ']'
           else descripcion
         end
   where id = p_asiento_id;

  return p_asiento_id;
end;
$$;

comment on function anular_asiento(uuid, text) is 'Anula un asiento MANUAL (estado=anulado). El trigger de bitacora registra la anulacion con el valor anterior. Es la via de correccion; nunca se borra fisicamente. F3: rechaza los asientos automaticos (origen distinto de manual): se corrigen anulando el pedido en Ventas.';

-- ============================================================
-- (H) Panel de Finanzas · ventas web sin asiento y «Generar asiento»
-- ============================================================

-- La lista se DERIVA de los datos (no de una bandera que se pueda desfasar):
--   venta   = pedido web pagado DE VERDAD (prod), vigente, sin asiento de venta.
--   reverso = pedido anulado cuya venta estaba en libros y no tiene contraasiento.
-- El motivo es el ACTUAL: se arma el asiento en seco (sin escribir). Si ya no
-- falta nada, motivo = null («listo para registrar»).
create or replace function fz_asientos_automaticos_pendientes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r        record;
  v_lista  jsonb := '[]'::jsonb;
  v_motivo text;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  for r in
    select p.id, p.fecha_orden, p.total, p.creado, i.referencia
      from pedidos p
      join pagos_intencion i
        on i.pedido_id = p.id and i.estado = 'procesada' and i.entorno = 'prod'
     where p.canal = 'web'
       and not p.anulado
       and not exists (select 1 from asientos a
                        where a.origen = 'venta_web' and a.origen_ref = p.id)
     order by p.creado
  loop
    begin
      perform fz__lineas_venta_web(r.id);
      v_motivo := null;
    exception when others then
      v_motivo := sqlerrm;
    end;
    v_lista := v_lista || jsonb_build_object(
      'tipo', 'venta', 'pedido_id', r.id, 'pedido', correo_ref_pedido(r.id),
      'fecha', r.fecha_orden, 'total', r.total, 'referencia', r.referencia,
      'motivo', v_motivo);
  end loop;

  for r in
    select p.id, p.fecha_orden, p.total, a.id as asiento_id
      from pedidos p
      join asientos a
        on a.origen = 'venta_web' and a.origen_ref = p.id and a.estado = 'activo'
     where p.anulado
       and not exists (select 1 from asientos b
                        where b.origen = 'reverso_venta_web' and b.origen_ref = p.id)
     order by p.actualizado nulls last
  loop
    begin
      perform fz__lineas_reverso(r.asiento_id);
      v_motivo := null;
    exception when others then
      v_motivo := sqlerrm;
    end;
    v_lista := v_lista || jsonb_build_object(
      'tipo', 'reverso', 'pedido_id', r.id, 'pedido', correo_ref_pedido(r.id),
      'fecha', r.fecha_orden, 'total', r.total, 'referencia', null,
      'motivo', v_motivo);
  end loop;

  return jsonb_build_object('pendientes', jsonb_array_length(v_lista), 'lista', v_lista);
end;
$$;

comment on function fz_asientos_automaticos_pendientes() is 'F3 · aviso de Finanzas: ventas web reales (prod) vigentes SIN asiento y pedidos anulados con venta en libros SIN contraasiento. Derivado de los datos, con el motivo ACTUAL (arma el asiento en seco; null = listo para registrar). Sin datos personales. Exige tiene_modulo(finanzas).';

create or replace function fz_generar_asiento_automatico(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado boolean;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  select anulado into v_anulado from pedidos where id = p_pedido_id;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;

  if v_anulado then
    return fz__reverso_venta_web(p_pedido_id);
  end if;
  return fz__asiento_venta_web(p_pedido_id);
end;
$$;

comment on function fz_generar_asiento_automatico(uuid) is 'F3 · boton «Generar asiento» del aviso de Finanzas: registra el asiento de una venta web pendiente (o el contraasiento si el pedido se anulo). Idempotente: si ya existe devuelve ya_existia. Si todavia falta algo, lanza el motivo. Exige tiene_modulo(finanzas).';

-- ============================================================
-- (I) Correo «Recibido» automatico del pedido web
-- ------------------------------------------------------------
-- Hoy el envio es manual y esta guardado por tiene_acceso_ventas() (con la
-- sesion de una persona). El servidor necesita su PROPIA puerta, igual que se
-- resolvio crear_pedido en F2: dos funciones ejecutables SOLO por service_role
-- (la Edge Function enviar-correo-pedido en modo automatico, que dispara
-- wompi-webhook). Reutilizan correo_pedido_preparar (mismas validaciones, mismo
-- destinatario sacado de la base, misma idempotencia: un solo «Recibido» por
-- pedido) abriendo la compuerta de contexto de F2 durante esa sola llamada.
-- Limites: solo pedidos web y solo la etapa «recibido».
-- ============================================================
create or replace function correo_auto_recibido_preparar(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_canal text;
  v       jsonb;
begin
  select canal into v_canal from pedidos where id = p_pedido_id;
  if not found then
    raise exception 'CORREO_PEDIDO_NO_EXISTE';
  end if;
  if v_canal is distinct from 'web' then
    raise exception 'CORREO_SOLO_WEB';
  end if;

  perform set_config('impulse.pago_servidor', 'on', true);
  begin
    v := correo_pedido_preparar(p_pedido_id, 'recibido', false);
  exception when others then
    perform set_config('impulse.pago_servidor', 'off', true);
    raise;
  end;
  perform set_config('impulse.pago_servidor', 'off', true);

  return v || jsonb_build_object('automatico', true);
end;
$$;

comment on function correo_auto_recibido_preparar(uuid) is 'F3 · reserva el correo «Recibido» de un pedido WEB para el envio automatico (lo llama enviar-correo-pedido en modo automatico, disparado por wompi-webhook). Reutiliza correo_pedido_preparar con la compuerta de contexto de servidor abierta solo durante esa llamada: mismas validaciones, destinatario de la base e idempotencia (CORREO_YA_ENVIADO / CORREO_EN_CURSO). Rechaza pedidos que no son web (CORREO_SOLO_WEB). Solo service_role.';

create or replace function correo_auto_resultado(
  p_envio_id     uuid,
  p_ok           boolean,
  p_proveedor_id text default null,
  p_error        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
begin
  -- Solo cierra envios que reservo el SERVIDOR (creado_por nulo), reales y de
  -- la etapa recibido. No reescribe historia: solo desde 'pendiente'.
  update correo_envios
     set estado       = case when p_ok then 'enviado' else 'fallido' end,
         proveedor_id = left(p_proveedor_id, 200),
         error        = case when p_ok then null else left(coalesce(p_error, 'Error desconocido'), 500) end,
         resuelto     = now()
   where id = p_envio_id
     and estado = 'pendiente'
     and creado_por is null
     and not es_prueba
     and etapa = 'recibido'
  returning estado into v_estado;

  if v_estado is null then
    raise exception 'CORREO_ENVIO_NO_PENDIENTE';
  end if;
  return jsonb_build_object('envio_id', p_envio_id, 'estado', v_estado);
end;
$$;

comment on function correo_auto_resultado(uuid, boolean, text, text) is 'F3 · cierra como enviado/fallido un correo «Recibido» que reservo el servidor (creado_por nulo). Solo transiciona desde pendiente. Solo service_role.';

comment on function pw__contexto_servidor() is 'PAGOS WEB · true solo dentro de funciones que unicamente ejecuta service_role y que la abren y la cierran en la misma transaccion: pw_procesar_pago (F2, crear el pedido web) y correo_auto_recibido_preparar (F3, reservar el correo Recibido). Usa el prefijo impulse.* porque PostgREST solo puede rellenar variables request.* desde cabeceras del cliente: un navegador no puede falsificar esta.';

-- ============================================================
-- Grants (Tramo 0: nominales; las funciones nuevas nacen cerradas)
-- ============================================================
do $$
declare f text;
begin
  -- Internas y del servidor: nadie desde el navegador.
  foreach f in array array[
    'fz__validar_contabilidad_config()',
    'fz__fecha_colombia(timestamptz)',
    'fz__lineas_venta_web(uuid)',
    'fz__lineas_reverso(uuid)',
    'fz__asiento_venta_web(uuid)',
    'fz__reverso_venta_web(uuid)',
    'correo_auto_recibido_preparar(uuid)',
    'correo_auto_resultado(uuid, boolean, text, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- Panel de Finanzas (cada una con su guardia tiene_modulo('finanzas')).
  foreach f in array array[
    'fz_asientos_automaticos_pendientes()',
    'fz_generar_asiento_automatico(uuid)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
