-- Ejecutar solo después de marcar y medir validación pública + checkout.
-- La activación no despliega código y no debe anticiparse a los postflight.
begin;
update promocionar_p4_config
   set validacion_publica_verificada = true,
       checkout_verificado = true,
       atribucion_habilitada = true,
       actualizado_razon = 'activacion_controlada_p4'
 where id = 1
   and not atribucion_habilitada;
commit;

select atribucion_habilitada, validacion_publica_verificada,
       checkout_verificado, actualizado_en, actualizado_razon
  from promocionar_p4_config where id = 1;
