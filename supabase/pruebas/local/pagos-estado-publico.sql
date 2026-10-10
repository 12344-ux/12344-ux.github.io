-- ============================================================
-- Impulse · Pruebas de pw_estado_publico (D0 · vuelta del pago)
-- Mide lo que la tienda puede saber de un pago por su referencia, y sobre todo
-- lo que NO puede saber. SOLO LOCAL; todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

-- Llama como service_role, que es el unico rol que puede: asi se prueba el
-- camino real de la Edge Function 'estado-pago' y no un atajo de superusuario.
create or replace function pg_temp.est(ref text)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute 'set local role service_role';
  select to_jsonb(t) into v from pw_estado_publico(ref) t;
  execute 'reset role';
  return v;  -- null cuando la funcion devuelve cero filas
end $$;

-- Crea una intencion con el estado interno que se quiera probar.
create or replace function pg_temp.sembrar(ref text, est text) returns void language sql as $$
  insert into pagos_intencion
    (referencia, nombre, slug, precio_unitario, monto_centavos, entorno, estado)
  values (ref, 'Shampoo de prueba', 'shampoo-prueba', 69900, 6990000, 'sandbox', est)
$$;

begin;

-- ------------------------------------------------------------------
-- 1. Traduccion de estados: el vocabulario interno NO sale a la tienda
-- ------------------------------------------------------------------
select pg_temp.sembrar('MAG-t1-creada', 'creada');
select pg_temp.sembrar('MAG-t2-procesada', 'procesada');
select pg_temp.sembrar('MAG-t3-rechazada', 'rechazada');
select pg_temp.sembrar('MAG-t4-revision', 'requiere_revision');

select pg_temp.chk(pg_temp.est('MAG-t1-creada')->>'estado' = 'pendiente',
  'traduce: creada -> pendiente (el webhook aun no llega)');
select pg_temp.chk(pg_temp.est('MAG-t2-procesada')->>'estado' = 'aprobado',
  'traduce: procesada -> aprobado (hay pedido)');
select pg_temp.chk(pg_temp.est('MAG-t3-rechazada')->>'estado' = 'rechazado',
  'traduce: rechazada -> rechazado (no hubo cobro)');
select pg_temp.chk(pg_temp.est('MAG-t4-revision')->>'estado' = 'revision',
  'traduce: requiere_revision -> revision (el pago entro, el pedido no)');

-- 'revision' NO se disfraza de aprobado: prometeria un pedido que no existe.
select pg_temp.chk(pg_temp.est('MAG-t4-revision')->>'estado' <> 'aprobado',
  'honestidad: un pago en revision nunca se reporta como aprobado');
-- ...ni de rechazado: el dinero SI entro.
select pg_temp.chk(pg_temp.est('MAG-t4-revision')->>'estado' <> 'rechazado',
  'honestidad: un pago en revision nunca se reporta como rechazado');

-- ------------------------------------------------------------------
-- 2. Lo que devuelve: el minimo, y nada mas
-- ------------------------------------------------------------------
select pg_temp.chk(pg_temp.est('MAG-t1-creada')->>'nombre_producto' = 'Shampoo de prueba',
  'devuelve el nombre del producto (para el aviso de la tienda)');
select pg_temp.chk(pg_temp.est('MAG-t1-creada')->>'slug' = 'shampoo-prueba',
  'devuelve el slug');
select pg_temp.chk(
  (select count(*) from jsonb_object_keys(pg_temp.est('MAG-t1-creada'))) = 3,
  'devuelve EXACTAMENTE 3 campos (estado, nombre_producto, slug)');

-- La prueba que de verdad importa: ningun dato del comprador ni del dinero.
select pg_temp.chk(
  pg_get_function_result('pw_estado_publico(text)'::regprocedure)
    !~* '(monto|precio|centavos|correo|telefono|direccion|ciudad|departamento|comprador|pedido_id|transaccion|metodo|entorno|revision_motivo|utm|mg_vid)',
  'no filtra: la firma no expone monto, datos del comprador, pedido ni transaccion');

-- ------------------------------------------------------------------
-- 3. Referencias que no deben decir nada
-- ------------------------------------------------------------------
select pg_temp.chk(pg_temp.est('MAG-no-existe-jamas') is null,
  'referencia inexistente: cero filas (la Edge Function responde 404)');
select pg_temp.chk(pg_temp.est('con espacios y * raros') is null,
  'referencia mal formada: cero filas, sin tocar la tabla');
select pg_temp.chk(pg_temp.est('abc') is null,
  'referencia demasiado corta: cero filas');
select pg_temp.chk(pg_temp.est(null) is null,
  'referencia null: cero filas');
select pg_temp.chk(pg_temp.est(repeat('A', 65)) is null,
  'referencia demasiado larga: cero filas');
-- Una referencia inexistente y una mal formada se ven IGUAL hacia afuera: la
-- funcion no sirve para averiguar si una referencia existe.
select pg_temp.chk(
  pg_temp.est('MAG-no-existe-jamas') is not distinct from pg_temp.est('con espacios y * raros'),
  'no confirma existencia: inexistente y mal formada responden lo mismo');

-- ------------------------------------------------------------------
-- 4. Un estado interno nuevo sin traducir cae en el lado prudente
-- ------------------------------------------------------------------
-- Se fuerza saltando el check de la tabla (escenario: alguien agrega un estado
-- a pagos_intencion y olvida traducirlo aqui). Nunca debe salir 'aprobado'.
alter table pagos_intencion drop constraint pagos_intencion_estado_check;
select pg_temp.sembrar('MAG-t5-futuro', 'estado_que_no_existe_aun');
select pg_temp.chk(pg_temp.est('MAG-t5-futuro')->>'estado' = 'pendiente',
  'estado desconocido: cae en pendiente, nunca en aprobado');

-- ------------------------------------------------------------------
-- 5. Permisos: la unica puerta es la Edge Function
-- ------------------------------------------------------------------
select pg_temp.chk(
  not has_function_privilege('anon', 'pw_estado_publico(text)'::regprocedure, 'execute'),
  'permisos: la tienda (anon) NO ejecuta pw_estado_publico');
select pg_temp.chk(
  not has_function_privilege('authenticated', 'pw_estado_publico(text)'::regprocedure, 'execute'),
  'permisos: un autenticado tampoco (el panel lee la tabla con su RLS)');
select pg_temp.chk(
  has_function_privilege('service_role', 'pw_estado_publico(text)'::regprocedure, 'execute'),
  'permisos: solo service_role, que es con quien corre la Edge Function');
select pg_temp.chk(
  not has_table_privilege('anon', 'pagos_intencion', 'select'),
  'sin regresion: pagos_intencion sigue cerrada para anon');

-- ------------------------------------------------------------------
-- 6. Forma de la funcion: definer, solo lectura, search_path fijo
-- ------------------------------------------------------------------
select pg_temp.chk(
  (select prosecdef from pg_proc where oid = 'pw_estado_publico(text)'::regprocedure),
  'forma: SECURITY DEFINER (pagos_intencion no es publica)');
select pg_temp.chk(
  (select provolatile from pg_proc where oid = 'pw_estado_publico(text)'::regprocedure) = 's',
  'forma: STABLE, solo lee (no escribe en ninguna tabla)');
select pg_temp.chk(
  (select proconfig::text from pg_proc where oid = 'pw_estado_publico(text)'::regprocedure)
    like '%search_path=public%',
  'forma: search_path fijo (ninguna funcion definer sin el)');

-- El reporte va DENTRO de la transaccion (los insert en la tabla temporal
-- tambien se deshacen con el rollback) y 'rollback' es la ultima linea: misma
-- convencion que el resto del banco. Nada de esto sobrevive a la prueba.
select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
