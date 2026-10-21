-- Promocionar P4 · reversa segura. No altera P3, pagos ni historia atribuida.
begin;
update promocionar_p4_config
   set atribucion_habilitada = false,
       actualizado_razon = 'reversa_operativa_p4'
 where id = 1 and atribucion_habilitada;
commit;

select atribucion_habilitada, actualizado_en, actualizado_razon
  from promocionar_p4_config where id = 1;
