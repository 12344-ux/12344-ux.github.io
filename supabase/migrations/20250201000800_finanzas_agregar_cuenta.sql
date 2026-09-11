-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · RPC agregar_cuenta_puc
-- Autonomia del dueno para AGREGAR una cuenta nueva al catalogo PUC
-- DESDE DENTRO del back-office (opcion B: pantalla en el software), sin
-- abrir SQL a mano ni depender del agente. FEAT-002 construye la pantalla
-- que llama a esta funcion con supabase.rpc('agregar_cuenta_puc', {...}).
--
-- POR QUE UNA RPC SECURITY DEFINER (y no un GRANT de INSERT):
--   El catalogo puc_cuentas NO tiene policy RLS de INSERT/UPDATE/DELETE
--   (ver 20250201000500_finanzas_rls.sql: solo SELECT con tiene_modulo).
--   Abrir INSERT directo al rol authenticated dejaria que cualquier
--   usuario con el modulo finanzas escribiera cuentas arbitrarias, sin
--   validar jerarquia ni rol. En su lugar, TODA la escritura del catalogo
--   pasa por esta funcion, que corre con privilegios del dueno (definer),
--   valida server-side y es la UNICA via de escritura. Mismo patron que
--   guardar_asiento / incrementar_uso_cuenta en 20250201000600.
--
-- CANDADO REAL = SERVER-SIDE (no negociable):
--   Solo un ADMIN puede agregar cuentas. La UI de FEAT-002 ocultara la
--   opcion a no-admin por comodidad, pero eso es UX, no seguridad: esta
--   funcion RECHAZA la operacion si auth.uid() no es un perfil con
--   rol='admin'. Se consulta la tabla perfiles DIRECTAMENTE porque en el
--   repo NO existe un helper es_admin (verificado). Se usa a proposito
--   rol='admin' y NO tiene_modulo('finanzas'): un trabajador con el modulo
--   finanzas puede registrar asientos, pero NO debe poder alterar el
--   catalogo de cuentas.
--
-- PROTECCION DE LA INTEGRIDAD DEL LIBRO (jerarquia PUC):
--   Antes de insertar se valida formato del codigo, que no exista ya, y
--   que su cuenta PADRE exista. Asi no se crean cuentas huerfanas que
--   romperian el Libro Mayor (las vistas movimientos_mayor / saldos_cuenta
--   dependen de la jerarquia). Si el padre falta, se rechaza nombrandolo.
--
-- IDEMPOTENCIA: la definicion usa `create or replace function`, de modo
--   que este archivo se puede re-ejecutar cuantas veces haga falta sin
--   duplicar ni fallar. La funcion en si NO es un upsert: si la cuenta ya
--   existe, lanza excepcion (el dueno debe enterarse de que ya estaba, no
--   sobreescribirla en silencio).
--
-- GRANT EXECUTE: NO hace falta (decision consistente con la nota de
--   20250201000700_finanzas_grants.sql). En Postgres las funciones otorgan
--   EXECUTE a PUBLIC por defecto al crearse y ninguna migracion del repo
--   hace `revoke ... from public`, asi que `authenticated` ya puede
--   ejecutar esta RPC. Anadir GRANT EXECUTE seria redundante. Tampoco se
--   abre INSERT/UPDATE/DELETE por RLS ni GRANT de tabla sobre puc_cuentas:
--   la escritura sigue siendo exclusiva de esta funcion definer.
--
-- FIRMA EXACTA (para FEAT-002):
--   agregar_cuenta_puc(p_codigo text, p_nombre text, p_naturaleza text,
--                      p_imputable boolean) -> text  (devuelve el codigo insertado)
--
-- MAPEO longitud de codigo -> nivel (la columna nivel es 1/2/3/4, NO la
--   longitud): 1 dig -> nivel 1 (clase), 2 dig -> nivel 2 (grupo),
--   4 dig -> nivel 3 (cuenta), 6 dig -> nivel 4 (subcuenta).
--
-- PADRE segun longitud: 6 dig -> prefijo de 4; 4 dig -> prefijo de 2;
--   2 dig -> prefijo de 1 (la clase); 1 dig (clase) -> sin padre (null).
-- ============================================================

create or replace function agregar_cuenta_puc(
  p_codigo     text,
  p_nombre     text,
  p_naturaleza text,
  p_imputable  boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo text := trim(p_codigo);
  v_nombre text := trim(p_nombre);
  v_len    int;
  v_nivel  smallint;
  v_padre  text;
begin
  -- 1) CANDADO DE ADMIN (server-side, primero de todo). Un trabajador con
  --    el modulo finanzas NO basta: se exige rol='admin'. Se consulta
  --    perfiles directamente porque no hay helper es_admin en el repo.
  if not exists (
    select 1 from perfiles where id = auth.uid() and rol = 'admin'
  ) then
    raise exception 'Solo un administrador puede agregar cuentas al catalogo PUC.';
  end if;

  -- 2) FORMATO DEL CODIGO: solo digitos y longitud PUC valida (1/2/4/6).
  if v_codigo is null or v_codigo !~ '^[0-9]+$' then
    raise exception 'El codigo PUC debe tener solo digitos y longitud 1, 2, 4 o 6.';
  end if;
  v_len := length(v_codigo);
  if v_len not in (1, 2, 4, 6) then
    raise exception 'El codigo PUC debe tener solo digitos y longitud 1, 2, 4 o 6.';
  end if;

  -- 2b) NOMBRE no vacio.
  if v_nombre is null or length(v_nombre) = 0 then
    raise exception 'El nombre de la cuenta es obligatorio.';
  end if;

  -- 2c) NATURALEZA: solo se valida que sea uno de los dos valores permitidos.
  --     NO se fuerza desde la clase: la sugerencia debito/credito por clase
  --     (clases 1/5/6/7/8 -> debito; 2/3/4/9 -> credito) se calcula en la UI,
  --     pero existen cuentas correctoras (ej. 1592, 4175) con naturaleza
  --     contraria a su clase, asi que aqui solo se persiste el valor
  --     confirmado por el usuario, exigiendo que sea 'debito' o 'credito'.
  if p_naturaleza is null or p_naturaleza not in ('debito', 'credito') then
    raise exception 'La naturaleza debe ser debito o credito.';
  end if;

  -- 3) DUPLICADO: si el codigo ya existe, se rechaza (no upsert silencioso).
  if exists (select 1 from puc_cuentas where codigo = v_codigo) then
    raise exception 'La cuenta % ya existe en el catalogo.', v_codigo;
  end if;

  -- 4) NIVEL derivado de la longitud (columna nivel es 1/2/3/4, no la longitud).
  v_nivel := case v_len
               when 1 then 1  -- clase
               when 2 then 2  -- grupo
               when 4 then 3  -- cuenta
               when 6 then 4  -- subcuenta (nivel de detalle)
             end;

  -- 5) PADRE segun la longitud y VALIDACION de jerarquia (protege el Libro
  --    Mayor: nada de cuentas huerfanas). Una clase de 1 digito no tiene padre.
  v_padre := case v_len
               when 6 then left(v_codigo, 4)
               when 4 then left(v_codigo, 2)
               when 2 then left(v_codigo, 1)
               else null
             end;
  if v_padre is not null
     and not exists (select 1 from puc_cuentas where codigo = v_padre) then
    raise exception 'Primero debe existir la cuenta padre %. No se pueden crear cuentas huerfanas.', v_padre;
  end if;

  -- 6) INSERT final. usos arranca en 0; imputable por defecto false si viene null.
  insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre, usos)
  values (v_codigo, v_nombre, v_nivel, p_naturaleza, coalesce(p_imputable, false), v_padre, 0);

  return v_codigo;
end;
$$;

comment on function agregar_cuenta_puc(text, text, text, boolean) is 'Agrega una cuenta al catalogo PUC desde el back-office. Candado server-side: SOLO admin (consulta perfiles.rol=admin directamente, no tiene_modulo). Valida formato (solo digitos, longitud 1/2/4/6), naturaleza in (debito,credito), nombre no vacio, no duplicado y existencia del PADRE segun la jerarquia (6->4->2->1) para no crear cuentas huerfanas que romperian el Libro Mayor. Deriva nivel desde la longitud (1->1,2->2,4->3,6->4). Es la UNICA via de escritura del catalogo (puc_cuentas no tiene policy RLS de INSERT). Devuelve el codigo insertado. FEAT-002 la llama con supabase.rpc.';
