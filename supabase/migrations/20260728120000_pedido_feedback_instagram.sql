-- ============================================================
-- Stramont · Añade la columna opcional "instagram" a pedido_feedback (Correo 3)
-- El cliente puede dejar su @ de Instagram SOLO si (a) su nota es 4-5 y
-- (b) autoriza publicar su testimonio. Sirve para dar MÁS confianza al futuro
-- visitante de la landing: ver el @ real de quien dejó la opinión.
-- Se sanea/valida en la Edge Function "feedback" (no se confía en el navegador).
-- No cambia la seguridad: la tabla sigue sin policies públicas.
-- ============================================================

alter table pedido_feedback add column if not exists instagram text;

comment on column pedido_feedback.instagram is 'Handle de Instagram (sin @) que el cliente autoriza mostrar junto a su testimonio. Solo se guarda con permiso_publicar=true y nota 4-5. Validado/saneado en la Edge Function feedback.';
