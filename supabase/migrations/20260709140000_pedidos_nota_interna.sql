-- ============================================================
-- Stramont · Columna "nota_interna" en "pedidos"
-- Nota que el DUEÑO escribe en el tablero para la IA que construye la guía
-- (ej: "enfócale PESTEL", "tiene examen el viernes"). Viaja pegada al
-- pedido, para no repetirla por chat.
--
-- Es interna (nunca se muestra al cliente ni sale en correos). Columna
-- aditiva y nullable. La lee/escribe la Edge Function con service_role.
-- ============================================================

alter table pedidos add column if not exists nota_interna text;

comment on column pedidos.nota_interna is 'Nota interna del dueno para la IA que arma la guia (ej: enfasis, contexto). Nunca se muestra al cliente.';
