# Relevo de sesión · Promocionar P1 preparado · 20 de octubre de 2026

**Estado:** implementación preparada en backend y tienda; no desplegada ni
medida en producción. Leer `docs/PLANO-PROMOCIONAR-P1.md` y
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

- Shells y plantilla permanecen `noindex,follow`.
- La consulta del catálogo usada al construir fue pública y de solo lectura.
- No se aplicó la migración P1.
- No se cambió Supabase, DNS, Wompi, flags o políticas.
- No se abrió un pago real.
- El estado productivo remoto sigue gobernado por el relevo C5 hasta medir P1.

## Para continuar

1. Esperar ambos PR y sus bancos verdes.
2. Pedir confirmación del dueño para la ventana P1.
3. Ejecutar preflight; exigir `listo_para_aplicar=true`.
4. Aplicar una sola vez `20261107000000_promocionar_p1_slug_historial.sql`.
5. Ejecutar postflight; booleanos `true`, `faltantes_actuales=0`.
6. Sincronizar otra vez la tienda para leer aliases server-side.
7. Fusionar/publicar tienda, esperar Pages y medir HTTP/sin JavaScript.
8. Mantener `noindex` hasta que las políticas reales estén publicadas.

P2 no comienza hasta cerrar o aceptar expresamente el límite productivo de P1.
P3–P5 siguen fuera de alcance.
