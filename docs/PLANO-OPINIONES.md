# PLANO · Software de Opiniones (reseñas de clientes)

**Área nueva del back-office:** "Gestión de opiniones".
**Corte:** 7 de octubre de 2026.
**Estado:** base (backend) escrita; pendiente de desplegar y de construir panel + tienda.

Este documento es la memoria de diseño del módulo, igual que `PLANO-INVENTARIO.md` y `PLANO-VENTAS.md`. Describe el porqué de cada decisión; el DDL vive en `supabase/migrations/20261007000000_opiniones_modulo.sql`.

---

## 1. Por qué existe

La curaduría y la **confianza** son el moat de MAGANDHI. Una opinión anónima que cualquiera deja no vale nada y se huele a trucada; una opinión **verificada** (de quien sí compró, sí recibió, sí usó el producto) es prueba social real — lo opuesto a los marketplaces masivos. Este módulo convierte cada opinión en prueba verificada y le da seguimiento interno (responder, moderar) sin romper la honestidad de marca.

## 2. El candado (sin login): código de reseña por pedido

La tienda no tiene login. Si la tabla de opiniones aceptara escritura pública directa, cualquiera inyectaría reseñas falsas. Solución (idea del dueño, patrón ya validado en el proyecto anterior):

1. Cada **pedido** lleva un **código de reseña único e imposible de adivinar** (`pedidos.codigo_resena`, ej. `MG-A3F09B7C21`), generado por trigger al crear el pedido (manual hoy; web con Wompi F2 mañana, sin tocar `crear_pedido`).
2. El cliente opina en la tienda **con ese código**.
3. Una Edge Function server-side (`enviar-opinion`) llama al RPC `op_registrar_opinion` (SECURITY DEFINER), que valida: código existe → pedido **entregado** → el producto pertenecía a ese pedido → no hay opinión previa para ese producto-pedido. Inserta una sola opinión por producto-pedido.

La autorización para opinar es la **posesión del código**, no un login. Por eso `op_registrar_opinion` no pide `tiene_modulo`. El código es secreto por pedido: viaja al cliente por correo (fase siguiente) y **nunca** se expone a anon.

## 3. Entrega del código al cliente (FASE SIGUIENTE, no incluida aquí)

El código ya existe en cada pedido desde que se crea. Hacerlo **llegar** al cliente —en el último correo de seguimiento/entrega, cuando ya recibió el producto— es la fase que sigue, y depende de montar el envío de correos de MAGANDHI (hoy inexistente; proveedor por decidir, p. ej. Resend + verificación de dominio). **Hasta montar eso no entran opiniones reales.** El motor queda listo y probable desde hoy (el dueño puede tomar un código del back-office y probar el flujo end-to-end).

## 4. Coherencia del promedio (decisión del dueño, 7-oct-2026)

El número grande que ve el cliente es el **promedio real** (`avg` de estrellas) redondeado a 1 decimal, **siempre** acompañado del total (N). Si hay 1 opinión de 5★, arriba dice **"5.0 · 1 opinión"**: no mentimos, el N avisa que es una sola. **No se usa media bayesiana ni suavizado** — rompería la coherencia con las tarjetas visibles y, a futuro, la del propio algoritmo. La tienda muestra **estado vacío** hasta `total >= 1`.

## 5. Moderación con control de marca

Las opiniones verificadas se publican **automáticamente** (incluidas las negativas reales: esconderlas sería un truco de tienda y choca con la marca; se responden, no se ocultan). El panel puede "borrar" una opinión, pero —coherente con todo el proyecto, donde nada se borra en silencio— **"borrar" = ocultar con bitácora** (`oculta=true` + quién/cuándo/por qué), reversible. Da control de marca sin perder integridad ni dejar al negocio sin defensa ante una disputa. Una opinión oculta sale de la web y del promedio pero no se destruye. El uso legítimo es **abuso/spam/falso**, no silenciar críticas reales.

## 6. Modelo de datos

- `pedidos.codigo_resena text` (unique parcial) + trigger `trg_pedidos_codigo_resena` + backfill.
- `opiniones`: `pedido_id`, `product_id`, `estrellas` (1..5), `comentario` (≤1000), `autor_nombre` (≤40, "cómo quieres aparecer"), `respuesta`/`respuesta_en`/`respuesta_por` (respuesta pública de la marca), `oculta`/`oculta_en`/`oculta_por`/`oculta_motivo` (bitácora), `es_prueba` (excluye de agregados), `creado` (**la fecha**). Unique `(pedido_id, product_id)`.

### Superficies públicas (lee la tienda por slug, sin login)
- `opiniones_publicas` (vista): opiniones individuales no ocultas, no de prueba, de campañas publicadas+activas. Solo columnas públicas; jamás `pedido_id`, `product_id`, `id`, `creado_por`, `es_prueba` ni bitácora.
- `producto_rating_publico` (vista): por slug, `total`, `promedio` (real, 1 decimal) y distribución por estrella (5→1).

### RPC de panel (back-office autenticado con módulo `opiniones`)
- `op_resumen_productos()` → productos con opiniones **ordenados por reseña más reciente primero**; promedio/total visibles + conteos `sin_responder`, `ocultas`, `pruebas`.
- `op_opiniones_producto(uuid)` → todas las opiniones de un producto **de más antigua a más reciente** (incluye ocultas/pruebas, para moderar).
- `op_responder_opinion(uuid, text)` → respuesta pública (vacío la quita).
- `op_ocultar_opinion(uuid, boolean, text)` → "borrar"/restaurar con bitácora.

Todas guardadas por `tiene_acceso_opiniones()` (= `tiene_modulo('opiniones')`).

## 7. Seguridad (resumen)

- `opiniones`: RLS; `select` solo a autenticado con módulo; **cero** policies de escritura → todo por RPC definer. anon: nada.
- Escritura pública solo por `op_registrar_opinion` (execute a `service_role`), vía Edge Function.
- Vistas públicas son SECURITY DEFINER (como `catalogo_publico`): anon recibe solo columnas públicas. **No** se recrea `catalogo_publico` (no se tocan sus grants).
- El código de reseña nunca sale a anon; no se loguea en la Edge Function.

## 8. Pendientes (orden de trabajo)

1. **Desplegar** la migración `20261007000000` en SQL Editor y verificar (ver `INSTRUCCIONES.md`).
2. **Desplegar** la Edge Function `enviar-opinion`.
3. **Panel** "Gestión de opiniones" (`opiniones/` en el back-office): lista por recencia, detalle por producto, responder y ocultar/restaurar. Mostrar el `codigo_resena` del pedido en el detalle de Ventas.
4. **Tienda**: botón "Dejar una reseña" + render real reusando el diseño aprobado (promedio grande + grid 2col + "ver todas"), leyendo `producto_rating_publico` y `opiniones_publicas` por slug.
5. **Fase siguiente**: envío del código en el último correo de entrega (requiere montar correos de MAGANDHI).
