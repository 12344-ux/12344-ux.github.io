-- ============================================================
-- Impulse · CAMPANAS · UN SOLO DISTINTIVO DE TARJETA
-- Fecha: 2026-10-03
-- ------------------------------------------------------------
-- DECISION DE MARCA:
--   La tarjeta del escaparate puede llevar UNA sola señal editorial:
--     A) Elegido por MAGANDHI (representado por la estrella de la marca), o
--     B) Ultimas unidades (con una cantidad manual, real y comprobada).
--   Tambien puede no llevar ninguna. "Agotado" sigue derivandose de Inventario
--   y no forma parte de esta eleccion.
--
-- MODELO:
--   No se crea otra columna: sello_elegido y aviso_urgencia_activo ya expresan
--   los dos estados. Esta migracion sella en la tabla que ambos no pueden ser
--   verdaderos a la vez. Los formularios usan un grupo de radios que traduce
--   la eleccion a esos dos booleanos.
--
-- DATOS HISTORICOS:
--   El CHECK se agrega NOT VALID para no destruir ni modificar silenciosamente
--   una fila antigua que pudiera tener ambos flags. Aun sin validar, PostgreSQL
--   SI exige la regla a toda fila nueva o actualizada. Si no hay conflictos al
--   aplicar la migracion, se valida de inmediato; si los hay, queda pendiente
--   hasta que el operador abra esas campanas, elija una opcion y las guarde.
--
-- La columna estrella queda como dato historico por trazabilidad, pero deja de
-- controlar la marca: el simbolo de Elegido por MAGANDHI es siempre la estrella
-- y ya no existe un segundo interruptor de "destacado".
--
-- Esta migracion NO recrea RPC ni vistas y NO toca sus grants. Evita repetir el
-- incidente 42501 causado por recrear funciones sin devolver EXECUTE nominal.
-- IDEMPOTENTE: guard por pg_constraint; VALIDATE puede repetirse.
-- REQUISITO: ejecutar despues de 20261003000100_campanas_execute_nominal.sql.
-- ============================================================

begin;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_producto_un_distintivo_chk'
       and conrelid = 'public.campana_producto'::regclass
  ) then
    alter table public.campana_producto
      add constraint campana_producto_un_distintivo_chk
      check (not (sello_elegido and aviso_urgencia_activo))
      not valid;
  end if;
end
$$;

comment on constraint campana_producto_un_distintivo_chk
  on public.campana_producto is
  'CAMPANAS · una tarjeta puede mostrar Elegido por MAGANDHI O Ultimas unidades, nunca ambos. Agotado sigue derivado de Inventario.';

comment on column public.campana_producto.estrella is
  'DATO HISTORICO JUBILADO: ya no controla ninguna representacion publica ni tiene interruptor en Campanas. Elegido por MAGANDHI usa siempre la estrella como simbolo de marca.';

-- Validar de inmediato solo cuando los datos historicos ya cumplen. Si existe
-- algun conflicto, el constraint queda NOT VALID pero protege desde ahora toda
-- insercion/actualizacion; el formulario nuevo permite resolverlo al editar.
do $$
begin
  if not exists (
    select 1
      from public.campana_producto
     where sello_elegido = true
       and aviso_urgencia_activo = true
  ) then
    alter table public.campana_producto
      validate constraint campana_producto_un_distintivo_chk;
  end if;
end
$$;

commit;
