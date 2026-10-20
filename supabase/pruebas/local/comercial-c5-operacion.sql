-- Valida que los cuatro scripts operativos C5 completos sean ejecutables sobre
-- PostgreSQL 15 después de aplicar todo el historial de migraciones.
\set ON_ERROR_STOP on

\ir ../../operacion/comercial-c5-postflight.sql
\ir ../../operacion/comercial-c5-estado.sql
\ir ../../operacion/comercial-c5-activar.sql
\ir ../../operacion/comercial-c5-desactivar.sql

select case
  when (select count(*) = 1 and bool_and(id = 1 and carrito_habilitado is false)
          from public.comercial_config)
  then 'TODO PASA · operación C5 ejecutable y flag final OFF'
  else 'FALLA · operación C5 no dejó el flag final OFF'
end as resultado;
