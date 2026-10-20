# Promocionar P1 · despliegue coordinado

**Estado:** `20261107000000` y `20261107000100` aplicadas; P1 cerrado.
**Escritura:** ambas migraciones se ejecutaron una sola vez; no repetir.
**Dinero:** no abre Wompi ni requiere pago real.

## Objetivo

Reservar slugs históricos en Supabase y publicar después los shells estáticos de
`magandhi.com` sin congelar precio, stock o disponibilidad.

## Orden

1. Confirmar backup/PITR y ventana del dueño.
2. Ejecutar `promocionar-p1-preflight.sql` en SQL Editor. Es solo lectura y debe
   devolver `listo_para_aplicar=true` con contadores en cero.
3. Ejecutar una sola vez la migración
   `20261107000000_promocionar_p1_slug_historial.sql`.
4. Ejecutar `promocionar-p1-postflight.sql`. Si todo es `true` y
   `faltantes_actuales=0`, continuar. Si únicamente `vista_solo_lectura=false`
   por defaults de Supabase, aplicar una sola vez la forward
   `20261107000100_promocionar_p1_vista_solo_lectura.sql` y repetir exactamente
   el mismo postflight.
5. En la tienda, ejecutar
   `node scripts/generar-productos.mjs --sync` y revisar el diff. Ahora debe leer
   también `campana_slug_alias_publico`.
6. Fusionar/publicar la tienda. Esperar Pages y medir por HTTP cada shell,
   `sitemap.xml` y `robots.txt`.
7. Verificar una ficha con JavaScript y otra sin JavaScript. Precio, stock,
   máximo y compra deben continuar naciendo únicamente del catálogo vivo.

## Rollback y fallos

- Si el preflight no da `true`, detenerse y medir; no corregir datos a mano.
- No ejecutar una migración ya confirmada con `COMMIT` ni editarla después.
- Si un intento falla, verificar primero con el preflight que la transacción
  revirtió completa (`listo_para_aplicar=true`). Solo en ese caso puede
  reintentarse intacto el mismo archivo; si hubo commit o estado parcial
  inesperado, detenerse y preparar una corrección forward.
- No ejecutar postflight hasta confirmar que la migración terminó con `COMMIT`.
- Si falla la tienda, volver a desplegar el commit anterior; no tocar Supabase.
- Una corrección de base es otra migración forward.
- Los shells permanecen `noindex,follow` hasta publicar políticas y cerrar el
  gate editorial; P1 no autoriza retirar `noindex`.

## Resultado esperado

- Toda campaña actual tiene su slug reservado.
- Un slug histórico nunca pertenece después a otra campaña.
- `campana_slug_alias_publico` expone únicamente alias → slug actual de campañas
  públicas.
- Las rutas query y UUID siguen compatibles.
- P2–P5 no cambian.
