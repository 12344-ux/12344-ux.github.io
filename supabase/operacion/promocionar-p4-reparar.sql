-- Promocionar P4 · reparación manual idempotente de incidencias fail-open.
-- Ejecutar desde SQL Editor y revisar después promocionar-p4-estado.sql.
begin;
select promocionar_p4_reparar_incidencias() as reparacion;
commit;

select count(*) as incidencias_pendientes
  from promocionar_p4_incidencias where resuelta_en is null;
select count(*) as divergencias
  from pagos_intencion i join pedidos p on p.id = i.pedido_id
 where i.atribucion_enlace_id is distinct from p.atribucion_enlace_id;
