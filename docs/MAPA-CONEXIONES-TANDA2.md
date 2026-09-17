# MAPA DE CONEXIONES · Tanda 2 (la incisión: Campañas ↔ Inventario)

> **Qué es esto:** el mapa de todos los "tapetes" del ecosistema Impulse tras la
> incisión de la Tanda 2. Explica qué quedó **encendido**, qué es **terreno
> preparado (no implementado)**, qué sigue **desconectado a propósito** y cuál es
> la **línea roja de seguridad** que nunca se cruza.
>
> Tono: socio honesto. Donde hay un riesgo o una decisión con costo, se dice sin
> humo. Este documento NO reemplaza a `supabase/INSTRUCCIONES.md`: el SQL y su
> verificación viven allí (subsección **C4. Tanda 2**); aquí se enlaza, no se
> duplica.
>
> **Estado:** Tanda 2 **aplicada en código**, pendiente de que el dueño corra el
> SQL `20250503000000_campanas_incision_inventario.sql` en el SQL Editor de
> Supabase y lo verifique (ver INSTRUCCIONES.md · C4.2).

---

## Contexto: por qué ahora sí

El Área de Campañas nació como una **isla** a propósito: mientras no estaba
aprobada, no leía Inventario y el stock/Agotado eran manuales, para no arrastrar
a nadie. Ahora que Campañas está **aprobada**, se hace la **incisión**: se
conectan las tuberías que ya estaban dibujadas debajo del tapete, **sin forzar
acoplamientos** y respetando la "cita a ciegas" (bajo acoplamiento entre áreas
que el dueño definió como arquitectura).

Regla que gobierna todo el mapa: **primero el producto entra a Inventario**, y
solo entonces aparece en el desplegable del panel de Campañas para poder
elegirlo por su `id`. El stock y el estado Agotado se toman **automáticamente**
de Inventario; nadie los escribe a mano en Campañas.

---

## (a) Lo que se ENCENDIÓ

Tras aplicar `20250503000000_campanas_incision_inventario.sql`:

1. **FK real `campana_producto.product_id_ref → productos(id)`.** El enchufe
   que estaba apagado (columna presente pero NULL, sin FK) se enciende con un
   guard idempotente sobre `pg_constraint` (mismo patrón que la FK de Ventas en
   `20250401000300`). Ligar es barato y ya queda validado por la base.

2. **Siembra de los 5 productos de Campañas en Inventario con stock 0 y CERO
   movimientos.** Los 5 productos de los seeds de Campañas (Grisi + 4 ejemplos)
   se crean en la tabla `productos` vía `inv_crear_producto(..., p_cantidad_inicial => 0)`,
   que **no** inserta ninguna fila en `movimientos_inventario`. Es decir:
   **existen en la lista de Inventario para que la página los pueda mostrar,
   pero NO hay unidades y NO se registró ninguna compra.** Se marcan con el flag
   interno `productos.es_placeholder` (true en los 4 ejemplos, false en Grisi)
   para poder distinguirlos/retirarlos sin manchar Inventario. Ese flag NUNCA se
   expone al público.

3. **Los 5 seeds de Campañas quedan ligados** a sus 5 productos de Inventario por
   `product_id_ref` (id capturado de la RPC al sembrar). Idempotente: si el
   `campana_producto` ya tiene `product_id_ref` no nulo, no se vuelve a sembrar.

4. **La vista pública `catalogo_publico` expone el booleano derivado `agotado`.**
   En lugar del antiguo número manual `stock_disponible`, la vista calcula
   `agotado` desde el stock REAL de Inventario:
   `case when cp.product_id_ref is null then false else coalesce(sa.existencias,0) <= 0 end`.
   Es decir: si el producto de Campañas todavía **no** está ligado a Inventario,
   `agotado = false` (no marcamos agotado a algo sin inventario conectado, para
   no romper el catálogo mientras el dueño migra); si está ligado, `agotado` es
   `true` cuando las existencias reales llegan a 0.

5. **Desplegable de producto de Inventario en el panel de Campañas.**
   `marketing/campanas/agregar.html` y `editar.html` tienen un
   `<select id="cm-producto">` que lista los productos de Inventario (por SKU +
   nombre) y guarda `product_id_ref` a través de las RPC `cm_crear_campana` /
   `cm_editar_campana` (parámetro `p_product_id_ref`). Flujo del operador:
   registra el producto en Inventario → aparece en el desplegable → lo elige al
   crear/editar la campaña → llena la presentación.

6. **La tienda muestra Agotado y deshabilita la compra por sí sola.** El home
   (`magandhi/index.html`), la página de producto (`magandhi/producto/index.html`)
   y la página legacy de Grisi (`magandhi/producto/grisi-manzanilla-gold/index.html`)
   leen `fila.agotado` (booleano) de `catalogo_publico`: cuando es `true` pintan
   el sello **Agotado** y **deshabilitan el botón de compra**. Cuando el dueño
   agregue unidades reales en Inventario, `existencias` sube, `agotado` pasa a
   `false` y la compra se habilita sola. Cuando el stock vuelva a 0, se pone en
   Agotado automáticamente.

---

## (b) El triángulo Campaña ↔ Producto ↔ Venta (cerrado)

La columna vertebral del ecosistema es `productos.id` (= `product_id`). Con la
incisión, el triángulo queda **cerrado**:

```
        Campaña (campana_producto)
              │  product_id_ref  ──────────► productos.id
              │                                   ▲
              │                                   │  product_id
              ▼                                   │
      catalogo_publico.agotado            pedido_items.product_id
      (derivado de stock_actual              (ya existía; Ventas)
       vía product_id_ref)
```

- **Campaña → Producto:** `campana_producto.product_id_ref → productos.id`
  (encendido en esta Tanda 2).
- **Venta → Producto:** `pedido_items.product_id → productos.id` **ya existía**
  (lo dejó el Área de Ventas). No se toca aquí.
- **Producto → stock real:** la vista `stock_actual` deriva `existencias` del
  libro `movimientos_inventario`; `catalogo_publico.agotado` la lee por
  `product_id_ref`.

Por qué queda cerrado: los tres vértices apuntan al **mismo** `productos.id`. Una
campaña sabe qué producto viste; una venta sabe qué producto salió; el stock real
de ese producto alimenta el Agotado que ve la tienda. Ningún vértice escribe en
el otro: cada área deposita su dato y los demás lo leen (bajo acoplamiento).

### Marketing / Ranking de productos — CONEXIÓN con Ventas (estado REAL)

En `marketing/marketing-project/ranking-productos.html` (alrededor de la línea
180, bloque **"INGRESO REAL POR PRODUCTO"**) el marcador que antes decía
"CONEXIÓN FUTURA" a Ventas **ya está actualizado y activo en el código actual**:
la función `leerIngresoRealPorProducto` lee `pedido_items`
(`precio_unitario × cantidad` de pedidos NO anulados, acotados por
`pedidos.fecha_orden`) para calcular el **ingreso REAL** por producto, y solo cae
al **fallback** de `precio_venta` actual para las salidas del libro que no
nacieron de un pedido (ventas viejas o ajustes manuales). O sea: la conexión con
Ventas **ya no es futura, es real**. El comentario del código refleja esto
correctamente ("antes marcada como CONEXIÓN FUTURA"); **no se reabrió ni se
cambió la lógica** en la Tanda 2. Se documenta aquí su estado real para que nadie
lo confunda con un pendiente.

> Nota de coherencia: `CONTEXTO-MAGANDHI.md` aún describe el Ranking con "ingreso
> ESTIMADO" y una "conexión futura marcada en el código". Ese texto es del estado
> previo; la implementación real ya usa el ingreso real de `pedido_items` con
> fallback a estimado por unidad. La corrección amplia de ese índice se hace en
> su propia línea de trabajo; aquí solo se deja constancia del estado real.

---

## (c) Terreno PREPARADO (NO implementado en esta Tanda)

Estas conexiones están dibujadas debajo del tapete pero **no** se encienden aquí.
Se dejan listas para cuando haya datos y el dueño lo pida:

- **Clúster de etiquetas de Campañas × ventas por cliente.** Las etiquetas de
  segmentación de Campañas (`campana_producto_etiqueta`) y el historial de compras
  por cliente (Ventas: `pedidos`/`pedido_items` + `customer_id`) podrían cruzarse
  para agrupar clientes y calcular la "salud" del portafolio. **No se implementa:**
  requiere que Ventas acumule datos reales primero, y el Análisis Clúster de
  Marketing es quien haría esa lectura cruzada (no Campañas). Campañas NO lee ese
  cruce hoy.
- **Cualquier otra lectura cruzada futura** (Email Marketing por clúster,
  Mapas/Rutas por dirección) queda igual: terreno preparado, sin encender.

Regla: no se fuerza ningún acoplamiento. Se enciende solo lo que la aprobación de
Campañas justifica (el ligado a Inventario y el Agotado real).

---

## (d) DESCONECTADO a propósito: Finanzas / Contabilidad

**Finanzas NO se engancha.** La siembra de los 5 productos usa
`inv_crear_producto` con `p_cantidad_inicial = 0`, que **no** inserta ninguna fila
en `movimientos_inventario`. Consecuencia directa:

- **No se generan asientos contables** (no hubo compra, no hubo entrada de
  inventario, no hay movimiento del libro que registrar).
- **No se toca el stock real** (existencias siguen en 0 hasta que el dueño cargue
  unidades de verdad).

Por qué esto protege a Contabilidad: si la siembra hubiera creado movimientos,
habría fabricado un costo/entrada de inventario ficticio que un humano tendría que
"desaparecer" de la contabilidad, ensuciando el libro. Al sembrar con cantidad 0,
los productos **existen en la lista** (para que la página los muestre) pero
**no afectan Contabilidad ni ningún otro software**. Esto respeta la "cita a
ciegas": Inventario y Contabilidad no se hablan; un error de un lado no envenena
al otro. Cuando el dueño registre entradas reales, ahí sí el libro se moverá y la
contabilidad se hará **manual, con criterio humano**, como siempre.

Verificación de que NO hubo movimientos (en INSTRUCCIONES.md · C4.2):
`select count(*) from movimientos_inventario m join campana_producto cp on cp.product_id_ref = m.product_id;` debe dar **0**.

---

## (e) LÍNEA ROJA de seguridad (lo que NUNCA se expone)

La vista `catalogo_publico` es la **única** superficie que lee la tienda pública
(`magandhi.com`) sin login, con la publishable key (rol `anon`). Su lista blanca
de columnas es sagrada:

- **SÍ expone:** el booleano derivado **`agotado`** (y los campos públicos de
  siempre: nombre, slug, categoría + colores, presentación, hooks, precio_venta,
  textos, ficha, imágenes, sello, estrella, aviso de urgencia).
- **NUNCA expone:** el **número exacto de existencias**, el **costo**, el
  **proveedor**, `product_id_ref`, `es_placeholder`, ni las etiquetas de
  segmentación. Tampoco `stock_disponible` (se retiró de la vista en la Tanda 2).

El candado es doble: (1) las tablas base no tienen grant/policy para `anon`, y
(2) la vista solo trae filas `publicado = true and activo = true` y solo columnas
públicas. El `left join` a `stock_actual` se resuelve con los privilegios del
**dueño de la vista** (`catalogo_publico` es security definer por defecto), así
que `anon` obtiene **solo el booleano** `agotado` y jamás puede leer
`stock_actual` directo.

**El aviso "Solo X disponibles" sigue siendo MANUAL** (`aviso_urgencia_activo` +
`aviso_urgencia_cantidad`, definidos por el dueño) y es **independiente** del
Agotado real: el Agotado sale del stock de Inventario; el aviso de urgencia es una
decisión honesta del dueño (por ejemplo, cuando de verdad quedan 3 unidades). Si un
producto está agotado, en la tienda manda el sello **Agotado** y el aviso de
urgencia se oculta para no contradecirlo.

### Tabla base vs vista pública (para no confundir `stock_disponible`)

Tras la incisión, `stock_disponible` **sigue existiendo** como columna de la
**tabla base** `campana_producto`, y el panel autenticado (`editar.html`) aún la
lee y la escribe vía RPC. **Eso es válido:** es una lectura/escritura autenticada
directa sobre la tabla base, no sobre la vista pública. Lo que se retiró de la
**vista pública** `catalogo_publico` es esa columna: la tienda ya **no** depende de
`stock_disponible` para nada (ver grep abajo). No confundir ambas cosas:

| Concepto            | `campana_producto.stock_disponible` (tabla base) | `catalogo_publico.agotado` (vista pública) |
|---------------------|--------------------------------------------------|--------------------------------------------|
| Naturaleza          | Número manual, dato de compatibilidad            | Booleano derivado del stock real           |
| Quién lo lee        | Panel autenticado (marketing), directo           | La tienda pública (`anon`)                 |
| Alimenta el Agotado | **No** (histórico/manual)                         | **Sí** (existencias ≤ 0 vía product_id_ref)|
| Se expone al público| **No**                                           | **Sí** (solo el booleano)                  |

---

## Verificación de coherencia realizada en esta Tanda

- **`grep -rn stock_disponible` en `magandhi/` (la tienda):** **0 resultados**.
  La tienda NO depende de `stock_disponible` del catálogo público tras la Tanda 2
  (FEAT-004 ya migró la lógica de agotado a `fila.agotado`). No quedó ninguna
  dependencia huérfana que rompa la tienda.
- **`grep -rn stock_disponible` en `12344-ux.github.io/marketing/`:** aparece solo
  en el panel de Campañas (`agregar.html` línea ~821 al escribir vía RPC,
  `editar.html` líneas ~765/~795/~919 al leer y escribir). Todas son operaciones
  autenticadas sobre la **tabla base** `campana_producto`, válidas (ver distinción
  arriba).
- **Comentarios del panel actualizados:** las notas de arquitectura en el `<head>`
  de `agregar.html` y `editar.html` decían "Campañas NO lee Inventario hoy" y que
  el Agotado "no se dispara solo": quedaron **desactualizadas** tras la incisión.
  Se corrigió **solo el texto de los comentarios** (sin cambiar comportamiento)
  para reflejar que Campañas ya se liga a Inventario por `product_id_ref` y que el
  Agotado se deriva del stock real en la tienda.
- **`ranking-productos.html`:** el marcador de conexión con Ventas ya estaba
  actualizado (usa `pedido_items` para el precio real). No se reabrió ni se cambió.

---

## Enlaces

- **SQL y verificación:** `supabase/INSTRUCCIONES.md` → subsección **C4. Tanda 2 ·
  La incisión: conectar Campañas con Inventario** (orden exacto de ejecución en
  C4.1, consultas de verificación en C4.2).
- **Migración:** `supabase/migrations/20250503000000_campanas_incision_inventario.sql`.
- **Índice de estado del proyecto:** `CONTEXTO-MAGANDHI.md`.

> _Aplica el SQL el dueño, a mano, en el SQL Editor de Supabase. Escribir SQL en
> el repo NO lo despliega._
