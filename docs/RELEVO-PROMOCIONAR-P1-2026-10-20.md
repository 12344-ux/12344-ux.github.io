# Relevo de sesión · Promocionar P1 en despliegue · 20 de octubre de 2026

**Estado:** backend #295 fusionado; migración `20261107000000` aplicada. El
postflight dio todo correcto salvo `vista_solo_lectura=false`: producción añadió
`MAINTAIN`, `REFERENCES`, `TRIGGER` y `TRUNCATE` a los tres roles API mediante
sus defaults. La corrección forward `20261107000100` está preparada; tienda
#116 sigue abierta. Leer `docs/PLANO-PROMOCIONAR-P1.md` y
`supabase/operacion/PROMOCIONAR-P1-DESPLIEGUE.md`.

## Entregado en código

- Back-office/backend: PR #295, commit inicial `437edc8`.
- Tienda: PR #116, commit inicial `30e8707`.
- Historial inmutable de slugs y vista pública mínima de aliases.
- Preflight, migración, postflight y runbook manual.
- Plantilla única de producto compatible con query, UUID y ruta canónica.
- Generador/sincronizador de shells desde `catalogo_publico`.
- Seis shells correspondientes al catálogo público leído el 20-oct-2026.
- Open Graph, Twitter Card y JSON-LD `Product` sin precio, stock, Offer o marca
  inventada.
- Sitemap, robots y enlaces internos canónicos.
- Analítica compatible con slug en path, sin cambiar consentimiento.

## Estado seguro

- Shells y plantilla permanecen `noindex,follow` y tienda #116 no está fusionada.
- La consulta del catálogo usada al construir fue pública y de solo lectura.
- `20261107000000` se aplicó una sola vez: historial, triggers, restricciones e
  invariantes correctos según postflight.
- Hallazgo medido: la vista recibió privilegios extra para roles API; no hubo
  cambio de filas. `20261107000100` los retira y vuelve a conceder solo SELECT.
- No se cambió DNS, Wompi, flags o políticas y no se abrió un pago real.

## Para continuar

1. Fusionar la corrección forward de ACL.
2. Aplicar una sola vez `20261107000100_promocionar_p1_vista_solo_lectura.sql`.
3. Repetir `promocionar-p1-postflight.sql`; exigir todos los booleanos `true` y
   `faltantes_actuales=0`.
4. Sincronizar otra vez la tienda para leer aliases server-side.
5. Fusionar/publicar tienda #116, esperar Pages y medir HTTP/sin JavaScript.
6. Mantener `noindex` hasta que las políticas reales estén publicadas.

P2 no comienza hasta cerrar o aceptar expresamente el límite productivo de P1.
P3–P5 siguen fuera de alcance.
