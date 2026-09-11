-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Funciones RPC (regla de oro)
-- Refuerzo SERVER-SIDE de la partida doble y utilidades del modulo.
-- Se eligio la VIA RPC (en lugar de un trigger constraint deferrable)
-- porque:
--   1) Permite validar cuadre + montos enteros + cuenta imputable ANTES
--      de escribir nada, dentro de UNA transaccion (cabecera + lineas),
--      devolviendo un error claro al cliente.
--   2) Es mas robusta que un trigger deferrable (que es fragil ante
--      inserciones parciales) y mas facil de razonar/mantener.
--   3) FEAT-002 la llama directamente con supabase.rpc('guardar_asiento', ...).
--
-- Todas son security definer con search_path=public fijo. Validan
-- tiene_modulo('finanzas') al entrar, de modo que el candado de acceso se
-- respeta aunque la funcion salte RLS por ser definer.
--
-- FIRMAS EXACTAS (para FEAT-002):
--   guardar_asiento(p_fecha date, p_descripcion text, p_lineas jsonb) -> uuid
--   editar_asiento(p_asiento_id uuid, p_fecha date, p_descripcion text, p_lineas jsonb) -> uuid
--   anular_asiento(p_asiento_id uuid, p_motivo text default null) -> uuid
--   incrementar_uso_cuenta(p_codigo text) -> void
--
-- Formato de p_lineas (jsonb array). Cada elemento:
--   { "cuenta_codigo": "110505", "detalle": "texto opcional",
--     "debe": 120000, "haber": 0 }
-- debe/haber son ENTEROS de pesos COP (bigint). En cada linea exactamente
-- uno es > 0 (el otro 0). Se valida cuadre (sum debe = sum haber) y >= 2 lineas.
-- ============================================================

-- ------------------------------------------------------------
-- Validador interno reutilizable: recibe el jsonb de lineas y lanza
-- excepcion si algo viola la regla de oro; si todo bien, no hace nada.
-- No es una funcion publica; la usan guardar_asiento y editar_asiento.
-- ------------------------------------------------------------
create or replace function fz_validar_lineas(p_lineas jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_linea       jsonb;
  v_codigo      text;
  v_debe        bigint;
  v_haber       bigint;
  v_n           int := 0;
  v_suma_debe   bigint := 0;
  v_suma_haber  bigint := 0;
  v_imputable   boolean;
begin
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' then
    raise exception 'Las lineas del asiento deben ser un arreglo JSON.';
  end if;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    v_n := v_n + 1;
    v_codigo := v_linea->>'cuenta_codigo';

    -- Montos como ENTEROS. Si vienen con decimales, se rechaza (nada de float).
    if (v_linea->>'debe') ~ '\.' or (v_linea->>'haber') ~ '\.' then
      raise exception 'Los montos deben ser enteros de pesos (sin decimales). Linea %', v_n;
    end if;
    v_debe  := coalesce((v_linea->>'debe')::bigint, 0);
    v_haber := coalesce((v_linea->>'haber')::bigint, 0);

    if v_debe < 0 or v_haber < 0 then
      raise exception 'Los montos no pueden ser negativos. Linea %', v_n;
    end if;

    -- XOR: exactamente uno positivo (misma regla que el check de la tabla).
    if (v_debe > 0) = (v_haber > 0) then
      raise exception 'Cada linea debe ser DEBE o HABER (uno positivo, el otro cero). Linea %', v_n;
    end if;

    -- La cuenta debe existir y ser IMPUTABLE (solo nivel de detalle recibe asiento).
    select imputable into v_imputable from puc_cuentas where codigo = v_codigo;
    if v_imputable is null then
      raise exception 'La cuenta % no existe en el catalogo PUC. Linea %', v_codigo, v_n;
    end if;
    if not v_imputable then
      raise exception 'La cuenta % no es imputable (solo se registra en el nivel de detalle). Linea %', v_codigo, v_n;
    end if;

    v_suma_debe  := v_suma_debe  + v_debe;
    v_suma_haber := v_suma_haber + v_haber;
  end loop;

  -- Al menos 2 lineas.
  if v_n < 2 then
    raise exception 'Un asiento debe tener al menos 2 lineas (partida doble).';
  end if;

  -- REGLA DE ORO: cuadre. Debe = Haber.
  if v_suma_debe <> v_suma_haber then
    raise exception 'El asiento no cuadra: total DEBE (%) distinto de total HABER (%).', v_suma_debe, v_suma_haber;
  end if;
end;
$$;

comment on function fz_validar_lineas(jsonb) is 'Valida la regla de oro server-side: montos enteros >=0, cada linea DEBE o HABER exclusivo, cuenta existente e imputable, minimo 2 lineas y cuadre sum(debe)=sum(haber). Lanza excepcion si algo falla. Uso interno de guardar_asiento/editar_asiento.';

-- ------------------------------------------------------------
-- guardar_asiento: crea cabecera + lineas en UNA transaccion tras validar.
-- Devuelve el id del asiento creado. FEAT-002: supabase.rpc('guardar_asiento', {...}).
-- ------------------------------------------------------------
create or replace function guardar_asiento(p_fecha date, p_descripcion text, p_lineas jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asiento_id uuid;
  v_linea      jsonb;
  v_orden      int := 0;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;
  if p_descripcion is null or length(trim(p_descripcion)) = 0 then
    raise exception 'La descripcion del asiento es obligatoria.';
  end if;

  perform fz_validar_lineas(p_lineas);

  insert into asientos (fecha, descripcion, estado, creado_por)
  values (p_fecha, p_descripcion, 'activo', auth.uid())
  returning id into v_asiento_id;

  for v_linea in select * from jsonb_array_elements(p_lineas) loop
    v_orden := v_orden + 1;
    insert into asiento_lineas (asiento_id, cuenta_codigo, detalle, debe, haber, orden)
    values (
      v_asiento_id,
      v_linea->>'cuenta_codigo',
      v_linea->>'detalle',
      coalesce((v_linea->>'debe')::bigint, 0),
      coalesce((v_linea->>'haber')::bigint, 0),
      v_orden
    );
  end loop;

  return v_asiento_id;
end;
$$;

comment on function guardar_asiento(date, text, jsonb) is 'Crea un asiento (cabecera + lineas) en una transaccion tras validar la regla de oro (fz_validar_lineas). Exige tiene_modulo(finanzas). Devuelve el uuid del asiento. FEAT-002 lo llama con supabase.rpc.';

-- ------------------------------------------------------------
-- editar_asiento: reemplaza cabecera y lineas de un asiento existente
-- (modelo punto medio: se puede editar; el trigger de bitacora registra el
-- valor anterior). Valida de nuevo la regla de oro. Devuelve el id.
-- ------------------------------------------------------------
create or replace function editar_asiento(p_asiento_id uuid, p_fecha date, p_descripcion text, p_lineas jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_linea  jsonb;
  v_orden  int := 0;
  v_estado text;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  select estado into v_estado from asientos where id = p_asiento_id;
  if v_estado is null then
    raise exception 'El asiento % no existe.', p_asiento_id;
  end if;
  if v_estado = 'anulado' then
    raise exception 'No se puede editar un asiento anulado. Cree uno nuevo.';
  end if;
  if p_descripcion is null or length(trim(p_descripcion)) = 0 then
    raise exception 'La descripcion del asiento es obligatoria.';
  end if;

  perform fz_validar_lineas(p_lineas);

  -- Actualiza cabecera (dispara el trigger de bitacora: accion 'editar').
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

comment on function editar_asiento(uuid, date, text, jsonb) is 'Edita un asiento activo: reemplaza cabecera y lineas tras revalidar la regla de oro. El trigger de bitacora guarda el valor anterior. No permite editar asientos anulados. FEAT-002 lo llama con supabase.rpc.';

-- ------------------------------------------------------------
-- anular_asiento: marca estado='anulado' (correccion punto medio). El
-- trigger registra la anulacion en la bitacora. Devuelve el id.
-- ------------------------------------------------------------
create or replace function anular_asiento(p_asiento_id uuid, p_motivo text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;

  select estado into v_estado from asientos where id = p_asiento_id;
  if v_estado is null then
    raise exception 'El asiento % no existe.', p_asiento_id;
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

comment on function anular_asiento(uuid, text) is 'Anula un asiento (estado=anulado). El trigger de bitacora registra la anulacion con el valor anterior. Es la via de correccion; nunca se borra fisicamente. FEAT-002 lo llama con supabase.rpc.';

-- ------------------------------------------------------------
-- incrementar_uso_cuenta: suma 1 al contador "usos" de una cuenta, para
-- que el buscador priorice las mas usadas. security definer para no tener
-- que abrir UPDATE general del catalogo (RLS de puc_cuentas no da UPDATE).
-- FEAT-002 la llama tras guardar un asiento, una vez por cuenta usada.
-- ------------------------------------------------------------
create or replace function incrementar_uso_cuenta(p_codigo text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tiene_modulo('finanzas') then
    raise exception 'Acceso denegado: se requiere el modulo finanzas.';
  end if;
  update puc_cuentas set usos = usos + 1 where codigo = p_codigo;
end;
$$;

comment on function incrementar_uso_cuenta(text) is 'Suma 1 al contador usos de una cuenta del PUC para priorizar el buscador. security definer: evita abrir UPDATE general del catalogo. Exige tiene_modulo(finanzas). FEAT-002 lo llama por cada cuenta usada al guardar un asiento.';
