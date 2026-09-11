-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Trazabilidad (punto medio)
-- Modelo de correccion "punto medio": los asientos se pueden EDITAR y
-- ANULAR, PERO nada se borra en silencio. Cada crear/editar/anular deja
-- rastro en asiento_bitacora con el VALOR ANTERIOR, quien lo hizo y cuando.
--
-- Esto es control interno / operacional (saber que paso), NO todavia
-- inmutabilidad contable formal para la DIAN. Deja la puerta abierta a
-- formalizar inmutabilidad en el futuro (p.ej. prohibir editar asientos de
-- periodos cerrados) SIN rehacer el modelo: la bitacora ya existe.
--
-- SEGURIDAD: RLS de asiento_bitacora en 20250201000500_finanzas_rls.sql
-- (SELECT/INSERT con tiene_modulo('finanzas'), sin DELETE). El trigger
-- corre como el usuario, y como no hay policy de DELETE, el historial no
-- se puede borrar desde el cliente.
-- ============================================================

create extension if not exists pgcrypto; -- gen_random_uuid (idempotente)

create table if not exists asiento_bitacora (
  id             uuid primary key default gen_random_uuid(),
  asiento_id     uuid references asientos(id), -- sin on delete: no hay DELETE de asientos; conservar aunque cambie
  accion         text not null check (accion in ('crear','editar','anular')),
  detalle_cambio jsonb,                         -- valor anterior / que se modifico
  actor          uuid references auth.users(id) default auth.uid(),
  cuando         timestamptz not null default now()
);

comment on table asiento_bitacora is 'Bitacora de correcciones (modelo punto medio): registra crear/editar/anular de cada asiento con el valor anterior en detalle_cambio (jsonb), el actor y el momento. Nada se borra en silencio. Sin policy de DELETE: el historial no se puede borrar desde el cliente.';
comment on column asiento_bitacora.accion is 'crear | editar | anular.';
comment on column asiento_bitacora.detalle_cambio is 'jsonb con el estado ANTERIOR del asiento (row_to_json de OLD) o los datos de creacion (row_to_json de NEW). Permite reconstruir que cambio.';

create index if not exists idx_asiento_bitacora_asiento on asiento_bitacora (asiento_id);
create index if not exists idx_asiento_bitacora_cuando on asiento_bitacora (cuando desc);

-- ------------------------------------------------------------
-- Trigger que alimenta la bitacora automaticamente en INSERT/UPDATE de
-- asientos. security definer para poder escribir la bitacora aunque las
-- policies de INSERT esten acotadas; search_path fijo por seguridad.
--   * INSERT  -> accion 'crear',  detalle_cambio = fila nueva.
--   * UPDATE con cambio estado activo->anulado -> accion 'anular'.
--   * Otro UPDATE -> accion 'editar', detalle_cambio = fila ANTERIOR (OLD).
-- ------------------------------------------------------------
create or replace function registrar_bitacora_asiento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    insert into asiento_bitacora (asiento_id, accion, detalle_cambio, actor)
    values (new.id, 'crear', to_jsonb(new), coalesce(new.creado_por, auth.uid()));
    return new;

  elsif (tg_op = 'UPDATE') then
    if (old.estado = 'activo' and new.estado = 'anulado') then
      insert into asiento_bitacora (asiento_id, accion, detalle_cambio, actor)
      values (new.id, 'anular', to_jsonb(old), auth.uid());
    else
      insert into asiento_bitacora (asiento_id, accion, detalle_cambio, actor)
      values (new.id, 'editar', to_jsonb(old), auth.uid());
    end if;
    return new;
  end if;

  return null;
end;
$$;

comment on function registrar_bitacora_asiento() is 'Trigger que alimenta asiento_bitacora en INSERT (crear) y UPDATE (anular si activo->anulado; editar en otro caso), guardando el valor anterior (OLD) o nuevo (INSERT) en detalle_cambio.';

drop trigger if exists trg_bitacora_asiento on asientos;
create trigger trg_bitacora_asiento
  after insert or update on asientos
  for each row execute function registrar_bitacora_asiento();
