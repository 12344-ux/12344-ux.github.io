# Relevo de sesión · Cierre estructural de Promocionar P1 · 20 de octubre de 2026

**Punto de arranque vigente.** Leer primero este archivo; después
`docs/PLANO-PROMOCIONAR-P1.md`, `docs/PLANO-PROMOCIONAR-P0.md` y
`docs/PLANO-FASE-COMERCIAL.md` §4. El relevo Comercial C5 sigue gobernando
carrito, Wompi y su cierre monetario pendiente.

## 1. Respuesta corta

- **Promocionar P0 y P1 están cerrados.** P0 como contrato; P1 desplegado y
  cerrado estructuralmente en producción.
- Backend PR #295 y corrección ACL #296 fusionados. Migraciones
  `20261107000000` y `20261107000100` aplicadas una vez cada una.
- Tienda PR #116 fusionada. GitHub Pages run `39384518735` terminó `success`.
- Seis productos tienen shell canónico compartible con metadata inicial; precio,
  stock y compra continúan vivos desde `catalogo_publico`.
- Los shells permanecen `noindex,follow` y el sitemap solo publica la home hasta
  publicar políticas. Es un gate editorial deliberado, no un fallo de P1.
- **Siguiente tramo: P2 · Estudio Promocionar.** P3–P5 siguen pendientes.

## 2. Estado productivo medido

| Pieza | Estado |
|---|---|
| Migraciones Supabase | Aplicadas manualmente hasta `20261107000100`; sin ledger, nunca `db push` |
| Historial de slugs | Instalado; cada slug queda reservado para su campaña original |
| Vista de aliases | HTTP 200, 0 filas en este corte; solo SELECT para `anon`, `authenticated`, `service_role` |
| Tienda | PR #116 / merge `a54911d`; Pages `39384518735` correcto |
| Shells | 6/6 responden HTTP 200 |
| Metadata | title, description, canonical, OG, Twitter y JSON-LD `Product` |
| Datos estáticos prohibidos | Sin `Offer`, `brand` inventada, precio, stock o disponibilidad |
| Sitemap | HTTP 200; solo home mientras políticas=`borrador` |
| Robots | HTTP 200 y referencia al sitemap |
| Compatibilidad | `/producto/?slug=` y `?id=` responden HTTP 200 |
| Pantalla | Grisi verificado en PC 1280×900 y móvil 390×844 |
| Indexación | `noindex,follow` intencional hasta políticas |

Rutas medidas:

- `/producto/cubo-rubik-4x4-qiyi/`
- `/producto/grisi-manzanilla-gold/`
- `/producto/serum-facial-rosa-mosqueta/`
- `/producto/balsamo-barba-cedro/`
- `/producto/jabon-coco-hogar/`
- `/producto/miel-cafe-artesanal/`

En las seis se comprobó: HTTP 200, title del producto, canonical y OG URL
idénticos, `noindex,follow`, dataset UUID/slug, compra inicialmente deshabilitada
y ausencia de Offer/precio/stock/brand en JSON-LD.

## 3. Ventana ejecutada

1. Backend #295 fusionado; banco PostgreSQL 15 verde.
2. Preflight productivo: trigger correcto, objetos P1 ausentes, cero slugs nulos,
   inválidos o repetidos; `listo_para_aplicar=true`.
3. Migración `20261107000000` aplicada una vez.
4. Primer postflight: todo correcto salvo `vista_solo_lectura=false`.
5. Diagnóstico ACL: los defaults reales de Supabase concedieron `MAINTAIN`,
   `REFERENCES`, `TRIGGER` y `TRUNCATE` además de SELECT a los tres roles API.
6. Corrección forward #296 / `20261107000100`: `REVOKE ALL` y concesión nominal
   únicamente de SELECT. No cambió filas o slugs.
7. Postflight final específico confirmado por el dueño: SELECT para los tres
   roles, cero privilegios extra y `vista_solo_lectura=true`.
8. Sincronización tienda contra `catalogo_publico` y vista de aliases: 6
   productos, 0 aliases, 0 artefactos por cambiar; `--check` correcto.
9. Tienda #116 fusionada; Pages correcto.
10. Sondas HTTP, metadata, sitemap, robots, query/UUID y capturas PC/móvil
    correctas. No se abrió Wompi ni se pagó dinero.

## 4. Defecto encontrado y aprendizaje

La migración inicial concedió SELECT sobre la vista sin hacer antes `REVOKE ALL`.
El banco local simulaba default privileges de funciones, pero no los defaults
reales de producción para vistas; por eso la diferencia apareció en postflight.

Impacto medido:

- no hubo pérdida o modificación conocida;
- la vista exponía solo campaña, slug anterior y slug actual;
- la tabla histórica permaneció privada;
- tienda P1 aún no estaba publicada cuando se detectó;
- no involucró PII, precio, stock, pagos o Wompi.

Regla permanente: toda vista pública nueva empieza con `REVOKE ALL` para PUBLIC
y roles API, y después recibe grants nominales. CI no sustituye el postflight
contra defaults reales de Supabase.

## 5. Operación desde ahora

Cuando Campañas cree, publique, despublique o cambie contenido/slug de un
producto:

```bash
node scripts/generar-productos.mjs --sync
node scripts/generar-productos.mjs --check
```

Después revisar el diff, fusionar la tienda, esperar Pages y medir el shell. El
manifiesto conserva aliases por UUID; el backend impide reasignarlos.

No aplicar nuevamente ninguna migración P1. Una corrección futura es forward.

## 6. Límites abiertos

1. Políticas públicas siguen en `borrador-0`; por eso `noindex` y sitemap-home
   permanecen. Al publicar políticas, cambiar el gate versionado y regenerar:
   shells pasan a `index,follow` y entran al sitemap juntos.
2. No existen aliases históricos todavía (vista 0 filas); el mecanismo está
   instalado para el primer cambio real.
3. P1 no implementa estudio, textos, QR o piezas (P2).
4. P1 no implementa enlaces cortos/clics (P3), atribución exacta (P4) o lectura
   comercial (P5).
5. C5 continúa sin cierre monetario por carrito; dinero solo con autorización.

## 7. Siguiente etapa · P2

P2 construye una pantalla propia «Promocionar» desde Campañas con:

- enlace oficial canónico;
- presets por los siete canales P0;
- generador UTM descriptivo;
- copiar y Web Share;
- preview interna y textos editables basados en contenido aprobado;
- QR generado localmente;
- piezas 1080×1080, 1080×1920 y horizontal;
- exportación local;
- sin publicación automática, Meta Ads, Pixel o gasto.

No mezclar P2 con registro/clicks P3, pagos/atribución P4 o métricas P5.

## 8. Prompt para el próximo chat

> Retomamos MAGANDHI después del **cierre estructural productivo de Promocionar
> P1**. Lee `docs/RELEVO-PROMOCIONAR-P1-2026-10-20.md`, después
> `docs/PLANO-PROMOCIONAR-P1.md`, `docs/PLANO-PROMOCIONAR-P0.md` y
> `docs/PLANO-FASE-COMERCIAL.md` §4. Producción Supabase llega manualmente hasta
> `20261107000100`, sin ledger y nunca con `db push`. P1 tiene historial
> inmutable de slugs, vista pública de aliases solo-SELECT y seis shells
> canónicos publicados; Pages run `39384518735` correcto. Shells siguen
> `noindex,follow` y sitemap solo home hasta políticas. No reaplicar migraciones
> P1. Siguiente etapa: **P2 · Estudio Promocionar**; confirma el tramo antes de
> construir. No adelantar P3–P5 ni tocar dinero/Wompi.
