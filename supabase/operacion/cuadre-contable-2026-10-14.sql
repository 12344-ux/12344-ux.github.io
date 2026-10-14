-- ============================================================================
-- MAGANDHI · CUADRE CONTABLE · 14 de octubre de 2026
-- ----------------------------------------------------------------------------
-- QUE ARREGLA
--   El saldo del panel de Dropi no coincidia con los libros. Al medir salieron
--   CUATRO cosas sin contabilizar, no una:
--     1. el SEGURO del pedido en Dropi («Asegurar pedido»), que se activo y
--        nunca se registro. Detras hay un hueco de diseno: pedido_proveedor
--        solo tiene costo_real y flete, asi que la pantalla de Despachos NO
--        TIENE DONDE anotar un seguro (se corrige en un PR aparte);
--     2. los DOS SHAMPOOS, que entraron a la bodega sin asiento de apertura:
--        el inventario existia en Produccion pero no en libros;
--     3. la RECARGA de 50.000 al saldo de Dropi;
--     4. la LIQUIDACION de Wompi de las dos ventas, ya consignada al banco.
--
-- COMO SE EJECUTA
--   Supabase -> SQL Editor -> pegar COMPLETO -> Run. UNA sola vez.
--   Es UN SOLO bloque y por tanto UNA SOLA TRANSACCION: si cualquier
--   comprobacion final falla, NO QUEDA NADA ESCRITO. Se puede volver a correr
--   sin miedo a duplicar: cada asiento se registra solo si no existe ya.
--
-- POR QUE FIJA LAS CLAIMS DEL ADMIN
--   guardar_asiento y agregar_cuenta_puc exigen tiene_modulo('finanzas') y
--   rol admin, que se resuelven con auth.uid(). En el SQL Editor no hay sesion,
--   asi que auth.uid() es null y las dos funciones fallarian. El bloque busca
--   el perfil admin y fija request.jwt.claims SOLO dentro de esta transaccion
--   (set_config con is_local = true). No abre nada ni deja estado.
--   Se hace asi, y no con INSERT directo, para que los asientos pasen por el
--   VALIDADOR server-side (fz_validar_lineas) y por la bitacora, igual que si
--   se hubieran escrito desde la pantalla de Finanzas.
--
-- CUENTAS NUEVAS (verificadas contra el PUC, Decreto 2650)
--   3130 / 313005  CAPITAL DE PERSONAS NATURALES. MAGANDHI es persona natural.
--                  OJO: 3120 es «Capital asignado», de sucursales de sociedades
--                  EXTRANJERAS; la de personas naturales es la 3130.
--   5230 / 523095  SEGUROS · OTROS, gasto operacional de ventas.
--                  OJO: 5245 es «Mantenimiento y reparaciones», asi que 524555
--                  no es una cuenta de seguros. La cuenta de seguros de ventas
--                  es la 5230, y dentro de ella no existe ninguna subcuenta de
--                  «transporte de mercancias» (las de transporte son para la
--                  flota PROPIA), por lo que el seguro de un envio de un tercero
--                  va en 523095 «Otros».
-- ============================================================================

do $$
declare
  -- ====================== LOS NUMEROS, todos aqui ===========================
  -- Si alguno no es exacto, se cambia SOLO aqui y se vuelve a correr.
  v_costo_cubo    bigint := 7200;     -- lo que Dropi cobro por la mercancia
  v_flete_cubo    bigint := 14910;    -- el envio, sin el seguro
  v_seguro        bigint := 755;      -- «Asegurar pedido»
  v_capital_merc  bigint := 95410;    -- 2 shampoos x 47.705, aporte en especie
  v_capital_efec  bigint := 50000;    -- recarga del saldo de Dropi, aporte
  v_costo_sham    bigint := 47705;    -- costo del shampoo vendido
  v_comision      bigint := 4818;     -- Wompi: 2,65% + 700 + IVA, 2 transacciones
  v_neto_banco    bigint := 95082;    -- lo que Wompi consigno
  v_bruto_ventas  bigint := 99900;    -- 69.900 shampoo + 30.000 cubo

  v_fecha_cap_merc date := '2026-10-01';  -- cuando entro la mercancia
  v_fecha_cap_efec date := '2026-10-10';  -- cuando se recargo Dropi
  v_fecha_seguro   date := '2026-10-10';  -- el pedido en Dropi
  v_fecha_liq      date := '2026-10-13';  -- el abono de Wompi al banco
  -- ==========================================================================

  v_admin   uuid;
  v_esperado_dropi bigint;
  n_138010 bigint; n_138095 bigint; n_143505 bigint;
  n_111005 bigint; n_413505 bigint; n_3130 bigint;
  v_debe bigint; v_haber bigint;
  v_activo bigint; v_pasivo bigint; v_patrim bigint; v_ing bigint; v_cg bigint;
begin
  -- ---------- (0) Actuar como el administrador, solo en esta transaccion ----
  select id into v_admin from perfiles where rol = 'admin' order by creado limit 1;
  if v_admin is null then
    raise exception 'No hay ningun perfil con rol admin: no se puede registrar nada.';
  end if;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
                     true);

  -- ---------- (1) Las cuentas que faltan en el catalogo --------------------
  if not exists (select 1 from puc_cuentas where codigo = '3130') then
    perform agregar_cuenta_puc('3130', 'CAPITAL DE PERSONAS NATURALES', 'credito', false);
  end if;
  if not exists (select 1 from puc_cuentas where codigo = '313005') then
    perform agregar_cuenta_puc('313005', 'CAPITAL DE PERSONAS NATURALES', 'credito', true);
  end if;
  if not exists (select 1 from puc_cuentas where codigo = '5230') then
    perform agregar_cuenta_puc('5230', 'SEGUROS', 'debito', false);
  end if;
  if not exists (select 1 from puc_cuentas where codigo = '523095') then
    perform agregar_cuenta_puc('523095', 'OTROS (SEGUROS DE VENTAS)', 'debito', true);
  end if;

  -- ---------- (2) Aporte de capital en MERCANCIA: los dos shampoos ---------
  -- Entraron a la bodega sin asiento. El dueno los aporto como capital por
  -- exactamente lo que valieron: 2 x 47.705, el mismo costo unitario que ya
  -- estaba en los libros por la venta del 9-oct.
  if not exists (select 1 from asientos
                  where descripcion = 'Cuadre 14-oct-2026 · aporte de capital en mercancia (2 shampoos)'
                    and estado = 'activo') then
    perform guardar_asiento(
      v_fecha_cap_merc,
      'Cuadre 14-oct-2026 · aporte de capital en mercancia (2 shampoos)',
      format('[{"cuenta_codigo":"143505","detalle":"2 shampoos a 47.705 c/u","debe":%s,"haber":0},
               {"cuenta_codigo":"313005","detalle":"aporte del dueno en especie","debe":0,"haber":%s}]',
             v_capital_merc, v_capital_merc)::jsonb);
  end if;

  -- ---------- (3) Aporte de capital en EFECTIVO: la recarga de Dropi -------
  if not exists (select 1 from asientos
                  where descripcion = 'Cuadre 14-oct-2026 · aporte de capital para recargar el saldo en Dropi'
                    and estado = 'activo') then
    perform guardar_asiento(
      v_fecha_cap_efec,
      'Cuadre 14-oct-2026 · aporte de capital para recargar el saldo en Dropi',
      format('[{"cuenta_codigo":"138010","detalle":"recarga del saldo en el panel de Dropi","debe":%s,"haber":0},
               {"cuenta_codigo":"313005","detalle":"aporte del dueno en efectivo","debe":0,"haber":%s}]',
             v_capital_efec, v_capital_efec)::jsonb);
  end if;

  -- ---------- (4) El SEGURO del pedido en Dropi ----------------------------
  -- Se pago del saldo de Dropi, igual que el costo y el flete.
  if not exists (select 1 from asientos
                  where descripcion = 'Cuadre 14-oct-2026 · seguro del pedido en Dropi (Asegurar pedido)'
                    and estado = 'activo') then
    perform guardar_asiento(
      v_fecha_seguro,
      'Cuadre 14-oct-2026 · seguro del pedido en Dropi (Asegurar pedido)',
      format('[{"cuenta_codigo":"523095","detalle":"seguro del envio del pedido de proveedor","debe":%s,"haber":0},
               {"cuenta_codigo":"138010","detalle":"descontado del saldo en Dropi","debe":0,"haber":%s}]',
             v_seguro, v_seguro)::jsonb);
  end if;

  -- ---------- (5) La LIQUIDACION de Wompi ----------------------------------
  -- Wompi consigno el neto de las dos ventas y se queda la comision. No hubo
  -- retenciones: si las hubiera, 99.900 - 4.818 no daria exactamente 95.082.
  if not exists (select 1 from asientos
                  where descripcion = 'Cuadre 14-oct-2026 · liquidacion Wompi de las dos ventas'
                    and estado = 'activo') then
    perform guardar_asiento(
      v_fecha_liq,
      'Cuadre 14-oct-2026 · liquidacion Wompi de las dos ventas',
      format('[{"cuenta_codigo":"111005","detalle":"consignado por Wompi el 13-oct 4:08 p.m.","debe":%s,"haber":0},
               {"cuenta_codigo":"530515","detalle":"comision 2,65%% + 700 + IVA por transaccion","debe":%s,"haber":0},
               {"cuenta_codigo":"138095","detalle":"se cierra la cuenta puente de las dos ventas","debe":0,"haber":%s}]',
             v_neto_banco, v_comision, v_bruto_ventas)::jsonb);
  end if;

  -- ======================= COMPROBACION FINAL ==============================
  -- Si algo de esto falla, la transaccion entera se deshace y no queda nada.
  v_esperado_dropi := v_capital_efec - v_costo_cubo - v_flete_cubo - v_seguro;

  select coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo = '138010'), 0),
         coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo = '138095'), 0),
         coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo = '143505'), 0),
         coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo = '111005'), 0),
         coalesce(sum(l.haber - l.debe) filter (where l.cuenta_codigo = '413505'), 0),
         coalesce(sum(l.haber - l.debe) filter (where l.cuenta_codigo like '3130%'), 0),
         coalesce(sum(l.debe), 0),
         coalesce(sum(l.haber), 0)
    into n_138010, n_138095, n_143505, n_111005, n_413505, n_3130, v_debe, v_haber
    from asiento_lineas l join asientos a on a.id = l.asiento_id
   where a.estado = 'activo';

  if v_debe <> v_haber then
    raise exception 'El libro no cuadra: debe % vs haber %. No se escribio nada.', v_debe, v_haber;
  end if;

  if n_138095 <> 0 then
    raise exception 'Wompi por liquidar (138095) quedo en % y deberia ser 0. '
      'Lo mas probable: falta el asiento AUTOMATICO de una de las dos ventas, o el bruto '
      'de las ventas no es %. No se escribio nada.', n_138095, v_bruto_ventas;
  end if;

  if n_138010 <> v_esperado_dropi then
    raise exception 'El saldo en Dropi (138010) quedo en % y deberia ser % '
      '(= % de recarga - % de costo - % de flete - % de seguro). Lo mas probable: todavia no '
      'se ha registrado el asiento del COSTO del pedido de proveedor desde Finanzas, o el costo '
      'o el flete son otros. No se escribio nada.',
      n_138010, v_esperado_dropi, v_capital_efec, v_costo_cubo, v_flete_cubo, v_seguro;
  end if;

  if n_143505 <> v_capital_merc - v_costo_sham then
    raise exception 'El inventario (143505) quedo en % y deberia ser % (1 shampoo). No se escribio nada.',
      n_143505, v_capital_merc - v_costo_sham;
  end if;

  if n_111005 <> v_neto_banco then
    raise exception 'El banco (111005) quedo en % y deberia ser %. No se escribio nada.',
      n_111005, v_neto_banco;
  end if;

  if n_413505 <> v_bruto_ventas then
    raise exception 'Los ingresos (413505) quedaron en % y deberian ser %. No se escribio nada.',
      n_413505, v_bruto_ventas;
  end if;

  -- Cuadre del balance por los dos lados.
  select coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo like '1%'), 0),
         coalesce(sum(l.haber - l.debe) filter (where l.cuenta_codigo like '2%'), 0),
         coalesce(sum(l.haber - l.debe) filter (where l.cuenta_codigo like '3%'), 0),
         coalesce(sum(l.haber - l.debe) filter (where l.cuenta_codigo like '4%'), 0),
         coalesce(sum(l.debe - l.haber) filter (where l.cuenta_codigo similar to '(5|6|7)%'), 0)
    into v_activo, v_pasivo, v_patrim, v_ing, v_cg
    from asiento_lineas l join asientos a on a.id = l.asiento_id
   where a.estado = 'activo';

  if v_activo <> v_pasivo + v_patrim + (v_ing - v_cg) then
    raise exception 'El balance no cuadra: activo % vs pasivo+patrimonio+resultado %. No se escribio nada.',
      v_activo, v_pasivo + v_patrim + (v_ing - v_cg);
  end if;

  -- ---------------------------- EL RESUMEN ---------------------------------
  raise notice '';
  raise notice '================ CUADRE APLICADO ================';
  raise notice 'PLATA de MAGANDHI ............. $%', to_char(n_111005 + n_138095 + n_138010, 'FM999G999G999');
  raise notice '   banco (111005) ............. $%', to_char(n_111005, 'FM999G999G999');
  raise notice '   saldo en Dropi (138010) .... $%', to_char(n_138010, 'FM999G999G999');
  raise notice '   Wompi por liquidar (138095)  $%', to_char(n_138095, 'FM999G999G999');
  raise notice 'Inventario (143505) ........... $%', to_char(n_143505, 'FM999G999G999');
  raise notice '-------------------------------------------------';
  raise notice 'Capital aportado (3130) ....... $%', to_char(n_3130, 'FM999G999G999');
  raise notice 'Utilidad del ejercicio ........ $%', to_char(v_ing - v_cg, 'FM999G999G999');
  raise notice 'ACTIVO = PAS + PAT + RESULTADO  $% = $%',
    to_char(v_activo, 'FM999G999G999'),
    to_char(v_pasivo + v_patrim + (v_ing - v_cg), 'FM999G999G999');
  raise notice '=================================================';
end $$;
