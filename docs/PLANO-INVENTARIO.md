# PLANO MAESTRO · Módulo Inventario (ecosistema Impulse · piloto MAGANDHI)

> **Estado: APROBADO POR EL DUEÑO — EN CONSTRUCCIÓN.** El dueño revisó el plano
> y dio luz verde. Este documento es la memoria fiel de las decisiones tomadas.
>
> Tono: socio honesto. Donde hay una decisión con costo o un riesgo, lo digo
> sin humo. Donde algo es "para después", lo marco para no caer en gold-plating.

---

## ⭐ DECISIONES FINALES DEL DUEÑO (sesión de aprobación)

Estas son las decisiones que cierran las preguntas abiertas de la §7 y ajustan
el alcance. Prevalecen sobre cualquier texto anterior del documento.

### Arquitectura del panel: ÁREAS jerárquicas (cambio importante)

El panel de admin deja de tener "módulos planos" y pasa a tener **3 grandes
áreas**, cada una un contenedor de **sub-áreas** (que a su vez tienen secciones):

```
PANEL ADMIN
├── FINANZAS    (área — ya existe, se queda igual)
│      └── Contabilidad PUC (asientos, diario, mayor, informes)
├── MARKETING   (área NUEVA — contenedor)
│      └── Marketing Project  (sub-área)
│             ├── Proyección de la demanda  ← se construye HOY
│             ├── Análisis de oportunidades de mercado   (futuro)
│             ├── Análisis clúster                        (futuro)
│             ├── Elasticidad de la demanda               (futuro)
│             └── "Cosas que podría estar ignorando"      (futuro)
│      └── (futuras herramientas de marketing)
└── PRODUCCIÓN  (área NUEVA — contenedor)
       └── Inventarios  (sub-área)  ← se construye HOY
              ├── Ver inventario
              └── Agregar a inventario
       └── (futuras sub-áreas de producción)
```

- **Marketing** y **Producción** son **carpetas de área** (como Finanzas), no
  herramientas planas. Clic en el área → aparecen sus sub-áreas → clic en la
  sub-área → aparecen sus secciones.
- Rutas: `produccion/index.html` → `produccion/inventarios/{index,ver,agregar}.html`;
  `marketing/index.html` → `marketing/marketing-project/{index, proyeccion-demanda}.html`.
- **Roles jerárquicos:** `modulos[]` debe permitir dar acceso a un **área
  completa** (ej. `produccion`) o a una **sub-área** (ej. `inventarios`). Se deja
  diseñado para delegar por área o por sub-área sin rehacer permisos.

### Alcance de HOY (las dos áreas funcionando y conectadas)

1. **Panel reorganizado** en las 3 áreas.
2. **PRODUCCIÓN → Inventarios** completo de punta a punta: Agregar (con
   **cantidad inicial** + descripción + **imagen auto-optimizada**), Ver (con
   fotos, stock derivado del libro), y el **libro de movimientos** guardando
   historia **completa, sin límite de tiempo, para siempre**.
3. **MARKETING → Marketing Project → Proyección de la demanda:** motor real con
   los **3 métodos** (promedio móvil, suavización exponencial, regresión lineal),
   **leyendo datos reales del libro de Inventario** desde el día uno. El dueño
   elige **periodo-base** (cuánto historial mira) y **horizonte** (cuántos días/
   semanas/meses proyecta). Resultado en 3 capas: número grande / gráfico
   (sólido = real, punteado = proyección) / tabla de detalle.

### Decisiones puntuales cerradas

- **SKU:** `MAG-<CAT>-0001` (con categoría). CONFIRMADO.
- **Color de área:** Inventario/Producción **hereda el azul marino** del
  back-office y se diferencia por **layout/jerarquía**. **Sin color nuevo.**
  (El verde ya es de Finanzas.) CONFIRMADO.
- **Imágenes en el inventario interno: SÍ**, con **optimización automática al
  subir** (redimensionar + comprimir antes de guardar; ~100–300 KB por foto).
  Razón del dueño: "así sabemos qué producto es realmente". La misma foto servirá
  luego a la tienda pública.
- **Lotes / vencimiento:** para después. CONFIRMADO (fuera del piloto).
- **Tabla `clientes`: NO se crea todavía.** Decisión del dueño: tiene pensado un
  software de Clientes más completo; crear una tabla a medias ahora arriesga
  chocar con ese diseño. Se deja `customer_id` en el libro como **"enchufe
  apagado"** (columna preparada, SIN FK todavía), que se conectará cuando exista
  el software de Clientes, sin tocar Inventario. (Esto **revierte** la §1.5 y la
  pregunta 4 de la §7: no hay tabla `clientes` en fase 1.)
- **Vitrina pública `hay_stock`:** **aún no.** Por ahora todo se queda a nivel
  interno; la superficie pública de la tienda (§2.4) NO se construye en esta
  vuelta. (El contrato de datos queda diseñado para el futuro.)
- **Cruce proyección ↔ stock** ("te faltarían ~220, considera reponer"): **NO en
  esta versión.** El dueño prefiere ver el número proyectado puro y **decidir la
  reposición manualmente** (aún no le da confianza plena a la proyección con poco
  historial). Se activa en una vuelta futura.
- **Aviso de datos insuficientes:** NO un aviso paternalista ni bloqueo. Igual
  que el Balance General: si no hay datos, un aviso **sobrio** de "aún no hay
  información" y ya. El software **nunca se limita ni se bloquea**.

### La relación Contabilidad ↔ Inventario ↔ Marketing (la "cita a ciegas")

Concepto aprobado por el dueño (bajo acoplamiento):

- **Inventario y Contabilidad NO se hablan directamente.** Cada uno hace su
  trabajo y **ambos depositan información en el punto común** (los datos reales)
  de donde **Marketing** los lee. Inventario confía en que lo registrado saliendo
  es lo vendido; Contabilidad confía en que lo registrado es la venta real.
- **Por qué así:** una venta real toca varias cuentas (Ingreso por ventas, Caja/
  Banco, Costo de ventas, salida de Inventario). Calcular el **costo de venta**
  requiere criterio contable → es **trabajo humano legítimo** (el dueño planea
  delegarlo a una persona). Acoplar Inventario→Contabilidad automáticamente
  contaminaría los libros ante cualquier error. Desacoplados, un error de un lado
  no envenena el otro (más robusto).
- **Reparto de la venta (hoy):** bajar inventario = automático (cuando haya
  checkout) / manual en el piloto; **ingreso de inventario = manual**; **costo de
  venta + registro contable = manual** (humano con criterio).
- **Ficha FUTURA "Ventas / Orquestador":** el módulo que, al concretarse una
  venta, orquestará a los demás (baja inventario, calcula costo, arma el paquete
  contable). Requiere pasarela/banco + Pedidos + Clientes, que hoy no existen. Se
  documenta como gema futura, NO se construye ahora.
- **Dato que se deja listo hoy en silencio:** cada movimiento guarda
  `costo_unitario_mov` y el producto guarda `precio_venta`, para que el día del
  orquestador el costo esté disponible sin rehacer nada.

---

## 0. Qué estamos construyendo y por qué así

El módulo **Inventario** es el segundo software del back-office interno
(`montaguth.institute`), hermano del módulo **Finanzas** ya terminado. Tiene
que quedar **impecable y clonable**: MAGANDHI es el piloto, pero el diseño no
puede quedar amarrado a MAGANDHI. Si funciona, Impulse lo replica a otras
organizaciones.

Dos pantallas, como pediste:

1. **Ver inventario**: todo lo que hay, cantidades y descripción detallada.
2. **Agregar a inventario**: alta manual: "me llegó este producto, en estas
   cantidades, con esta descripción, con esta imagen".

Y una decisión de arquitectura que ya conversamos y aprobaste: el stock **no**
se guarda como un número editable. Se guarda como la **suma de un libro de
movimientos** (entradas y salidas, con fecha y motivo). Lo que ves en pantalla
como "stock actual" es un cálculo en vivo de ese libro, nunca un dato suelto
que se pueda desincronizar. Misma filosofía de trazabilidad que Finanzas: nada
se borra en silencio.

**Por qué el libro de movimientos y no un número:** el Marketing Project (el
segundo software grande, que viene después) necesita el **historial de ventas
por periodo** para proyectar la demanda. Si hoy guardáramos solo "quedan 12
unidades", mañana no tendríamos con qué alimentar Marketing y habría que
rehacer Inventario entero. El libro de movimientos es la semilla que hace
posible Marketing sin rehacer nada.

**Lo que NO hace este módulo (para tener límites claros):**

- **No toca Contabilidad.** La contabilidad la registras tú a mano en Finanzas.
  No hay ningún enganche automático Inventario → Finanzas. (Tú lo pediste así.)
- **No construye Marketing.** Solo deja la arquitectura de datos preparada para
  que Marketing se conecte después sin rehacer nada.
- **No construye Pedidos/Clientes.** Pero deja anticipado el `customer_id` para
  cuando existan.

---

## 1. Modelo de datos

### 1.1. Las tres piezas y cómo encajan

```
  productos ──1─────────┐
   (catálogo,           │ product_id (UUID) = la llave que conecta todo
    identidad, ficha)   │
                        ▼
             movimientos_inventario  ← EL LIBRO (append-only)
              (cada entrada/salida,       ▲
               con fecha y motivo)        │ customer_id (anticipado, nullable)
                                          │
                                     clientes (FUTURO, tabla mínima anticipada)

  stock_actual (VISTA) = suma del libro por producto  → nunca se escribe a mano
```

El principio es el mismo que en Finanzas: **el diario se escribe, el saldo se
deriva.** Aquí: **el libro de movimientos se escribe, el stock se deriva.**

### 1.2. Tabla `productos` (identidad y ficha del producto)

Esta es la tabla de catálogo: **qué** vendemos, no **cuánto** hay. El "cuánto"
vive en el libro.

| Columna | Tipo | Fase | Para qué |
|---|---|---|---|
| `id` | `uuid` PK, `default gen_random_uuid()` | 1 | **El `product_id` interno.** UUID autogenerado al diligenciar el alta. Es la llave que conecta con la tienda, con Pedidos, con Marketing. Nunca lo escribe el dueño. |
| `sku` | `text` UNIQUE NOT NULL | 1 | **El código legible** que tú lees, dices y buscas. Autogenerado (ver §1.4). Ej. `MAG-SHAM-0001`. |
| `nombre` | `text` NOT NULL | 1 | Nombre comercial. Ej. "Shampoo Manzanilla GRISI Gold". |
| `descripcion` | `text` | 1 | Descripción detallada / ficha. |
| `marca` | `text` | 1 | Marca del fabricante (GRISI). Útil para agrupar y para Marketing (análisis por marca). |
| `categoria` | `text` | 1 | Categoría comercial ("Cuidado del cabello"). Base de análisis clúster en Marketing. |
| `unidad_medida` | `text` NOT NULL default `'unidad'` | 1 | Cómo se cuenta: unidad, mL, g, par... Evita el error clásico de sumar peras con manzanas. |
| `contenido` | `text` | 1 | Presentación legible ("400 mL"). Texto, no cálculo. |
| `costo_unitario` | `bigint` (pesos enteros) | 1 | Costo de reposición de referencia. **Entero de pesos**, misma regla que Finanzas (nunca float). Referencia interna; NO se contabiliza automático. |
| `precio_venta` | `bigint` (pesos enteros) | 1 | Precio de venta al público. Lo que la tienda mostrará. Entero de pesos. |
| `stock_minimo` | `integer` default `0` | 1 | Umbral de alerta ("punto de reorden"). Cuando el stock cae por debajo, la pantalla lo marca en la lista. No dispara nada automático (fase 1). |
| `proveedor` | `text` | 1 | Proveedor como **texto libre** (no FK todavía). Barato de incluir y alimenta el análisis por proveedor de Marketing. La tabla formal de proveedores queda para el futuro (Compras, si existe). **Confirmado dentro de fase 1.** |
| `ubicacion` | `text` | 1 (opcional de llenar) | Dónde está físicamente (bodega, estante). Barato de incluir; sirve cuando haya volumen. |
| `imagen_path` | `text` | 1 | **Ruta** dentro del bucket de Storage (no una URL con llave). Ver §4. |
| `activo` | `boolean` NOT NULL default `true` | 1 | Producto activo/inactivo. **Nunca se borra** un producto (rompería el historial del libro y de Marketing): se marca inactivo. Mismo espíritu que "anular" en Finanzas. |
| `publicado` | `boolean` NOT NULL default `false` | 1 | Si la **tienda pública** puede mostrarlo. Separa "existe en inventario" de "visible al cliente". Un producto puede existir sin estar publicado. |
| `creado` | `timestamptz` default `now()` | 1 | Auditoría. |
| `creado_por` | `uuid` ref `auth.users` default `auth.uid()` | 1 | Quién lo dio de alta. |
| `actualizado` | `timestamptz` | 1 | Última edición de la ficha. |

**Campos que investigué y DEJO PARA DESPUÉS (para no inflar la fase 1):**

- `codigo_barras` / EAN: útil si algún día se escanea en punto de venta. Hoy no
  hay escáner. Se agrega en una migración `alter table` cuando haga falta.
- `impuesto` / IVA por producto: la contabilidad es manual, no lo necesitamos
  para inventario. Cuando Pedidos calcule totales, se decide ahí.
- `proveedor_id` (tabla formal de proveedores): para el futuro. En fase 1 el
  proveedor va como **texto libre** en la columna `proveedor` (ya confirmada
  arriba en el DDL), que es barato y alimenta Marketing. La **tabla formal** de
  proveedores, con su FK, vendría con Compras si algún día existe. Es decir:
  `proveedor text` SÍ está en fase 1; `proveedor_id` como FK NO.
- `lote` / `fecha_vencimiento`: MAGANDHI vende producto de consumo con fecha.
  Esto **puede importar** (revisas que esté "en fecha", según el hero de la
  tienda). **Lo marco como decisión tuya:** ¿lo quieres en fase 1 a nivel de
  movimiento de entrada (cada lote que llega con su vencimiento) o lo dejamos
  para después? Mi recomendación honesta: **dejarlo para fase 2**, porque
  manejar lotes bien implica que el stock se descuenta por lote (FEFO) y eso es
  bastante más complejo. Para el piloto, un campo simple no aporta y un sistema
  de lotes completo es gold-plating. Lo dejo anotado, no construido.

### 1.3. Tabla `movimientos_inventario`, EL LIBRO (corazón del módulo)

Append-only. Cada fila es un hecho: entró stock, salió stock. **Nunca se
edita el stock directamente.** Esta es la tabla que Marketing va a leer.

| Columna | Tipo | Fase | Para qué |
|---|---|---|---|
| `id` | `uuid` PK `default gen_random_uuid()` | 1 | Identidad del movimiento. |
| `product_id` | `uuid` NOT NULL ref `productos(id)` | 1 | Qué producto se movió. |
| `tipo` | `text` NOT NULL check in (`'entrada'`,`'salida'`,`'ajuste_entrada'`,`'ajuste_salida'`) | 1 | Naturaleza del movimiento. Ver nota abajo. |
| `cantidad` | `integer` NOT NULL check (`cantidad > 0`) | 1 | **Siempre positiva.** El `tipo` (no el signo de `cantidad`) define si suma o resta al derivar el stock. Entero (unidades enteras). |
| `motivo` | `text` | 1 | Por qué. "Llegó pedido del proveedor", "Venta tienda", "Ajuste por conteo físico". |
| `referencia` | `text` | 1 | Enlace suave a un origen externo (ej. id de pedido de la tienda) sin acoplar tablas todavía. |
| `customer_id` | `uuid` ref `clientes(id)` NULL | 1 (columna) | **Anticipado.** Se llena cuando la salida es una venta y exista Clientes. Hoy queda NULL. Es lo que permitirá a Marketing cruzar "qué compró quién". |
| `costo_unitario_mov` | `bigint` NULL | 1 | Costo al que entró ese lote puntual (referencia histórica). Nullable. |
| `fecha` | `date` NOT NULL default `current_date` | 1 | Fecha contable del movimiento (la que importa para Marketing por periodo). |
| `creado` | `timestamptz` default `now()` | 1 | Momento real del registro (auditoría, distinto de `fecha`). |
| `creado_por` | `uuid` ref `auth.users` default `auth.uid()` | 1 | Quién lo registró. En ventas de la tienda, el usuario de servicio (ver §3). |

**Sobre `tipo` y el signo (DECIDIDO, ya no es pregunta abierta):**

El signo del movimiento es load-bearing: de él dependen el check de `cantidad` y
la expresión CASE de la vista `stock_actual`. Para que no quede ambiguo, lo
resuelvo con **tipos separados**, sin cantidades negativas:

- `entrada`: suma stock (llega mercancía del proveedor).
- `salida`: resta stock (venta concretada, merma, devolución a proveedor).
- `ajuste_entrada`: suma stock por corrección de conteo físico (el conteo real
  es mayor que el libro).
- `ajuste_salida`: resta stock por corrección de conteo físico (el conteo real
  es menor que el libro).

Así `cantidad` es **siempre positiva** (`check (cantidad > 0)`), el signo lo pone
el `tipo`, y la vista no necesita ninguna cantidad con signo. **Nunca editamos un
movimiento viejo;** si el conteo real no cuadra con el libro, se registra el
`ajuste_entrada` o `ajuste_salida` que corresponda, con su motivo. El libro sigue
siendo append-only y auditable, igual que "anular" en Finanzas en vez de borrar.

Descarté la alternativa de "una `cantidad` con signo solo para `ajuste`" porque
mezcla convenciones (unos tipos positivos, otro con signo) y complica tanto el
check como la lectura del libro. Dos tipos explícitos son más claros y auditables.

**Regla dura heredada de Finanzas:** cantidades **enteras** (unidades), montos
**bigint** (pesos enteros). Nada de float.

**Nada se borra.** No hay DELETE en RLS. Un movimiento equivocado se corrige
con un `ajuste` que lo compensa, dejando el rastro. (Si más adelante quieres un
"anular movimiento" explícito con bitácora como en Finanzas, se añade; para el
piloto, el ajuste compensatorio es suficiente y más simple.)

### 1.4. Generación del SKU legible (autogenerado, no lo escribes tú)

Quieres SKU legible + UUID, y que el `product_id` (UUID) se genere solo al
diligenciar. El UUID lo da Postgres (`gen_random_uuid()`), cero intervención.

El **SKU legible** lo genera la **RPC de alta** (server-side, para que sea
único de verdad y no dependa del navegador). Propuesta de formato:

```
MAG-<CAT>-<consecutivo 4 dígitos>     ej.  MAG-SHAM-0001
```

- `MAG` = prefijo de la organización. **Aquí está la clave de "clonable":** el
  prefijo NO va escrito a fuego en el código. Vive en una tabla de
  configuración (`inventario_config`, una fila) o como parámetro. Para otra
  organización de Impulse, se cambia el prefijo en un solo lugar.
- `<CAT>` = abreviatura derivada de la **categoría de texto libre** del producto
  (la columna `categoria`), NO de una tabla de categorías formal (no la hay en
  fase 1). La RPC toma la `categoria` en el momento del alta, la normaliza
  (mayúsculas, sin acentos) y usa sus primeros 3-4 caracteres. Si no hay
  categoría, ese tramo se omite (`MAG-0001`).
- `<consecutivo>` = número que la RPC calcula con una **secuencia** de Postgres
  (segura ante concurrencia), no contando filas (contar filas se rompe si algo
  se marca inactivo).

**SKU inmutable (implicación importante):** el SKU se **fija en el momento del
alta y no se recalcula nunca.** Aunque después edites la `categoria` de un
producto, su SKU **no cambia**. Esto es a propósito: el SKU es una etiqueta
estable que ya dijiste, escribiste o pegaste en algún lado (una caja, un pedido,
un mensaje), y un código que muta rompería trazabilidad y referencias externas.
La `categoria` puede evolucionar para el análisis de Marketing; el SKU se queda
como nació. Por eso `inv_editar_producto` **nunca** toca el `sku`.

**Decisión tuya:** ¿te sirve `MAG-SHAM-0001` o prefieres algo más corto tipo
`MAG-0001`? Lo dejo propuesto con categoría; es fácil de ajustar.

### 1.5. Tabla `clientes` (FUTURO · anticipada mínima)

No construimos Clientes ahora, pero para que `customer_id` sea una FK real y no
un texto suelto, propongo crear la tabla **mínima** ya:

| Columna | Tipo | Para qué |
|---|---|---|
| `id` | `uuid` PK `default gen_random_uuid()` | El `customer_id` que conecta todo. |
| `nombre` | `text` | Mínimo para que exista. |
| `creado` | `timestamptz` default `now()` | Auditoría. |

Así `movimientos_inventario.customer_id` apunta a una FK de verdad desde el día
uno, y cuando construyamos Clientes/Pedidos solo agregamos columnas, sin migrar
datos. **Alternativa honesta:** si prefieres no crear tablas "vacías", dejamos
`customer_id uuid` sin FK por ahora y la convertimos en FK cuando exista
Clientes. Mi recomendación: **crear la tabla mínima** (es baratísimo y evita
una migración de datos incómoda después).

### 1.6. El stock se deriva: vista `stock_actual`

Igual que `saldos_cuenta` en Finanzas. Una vista que suma el libro:

```sql
create or replace view stock_actual as
select
  p.id                as product_id,
  p.sku               as sku,
  p.nombre            as nombre,
  coalesce(sum(
    case m.tipo
      when 'entrada'        then  m.cantidad
      when 'ajuste_entrada' then  m.cantidad
      when 'salida'         then -m.cantidad
      when 'ajuste_salida'  then -m.cantidad
    end
  ), 0)::integer      as existencias
from productos p
left join movimientos_inventario m on m.product_id = p.id
group by p.id, p.sku, p.nombre;
```

- Hereda RLS de sus tablas base (SECURITY INVOKER, igual que el mayor de
  Finanzas). Quien no tenga el módulo, no ve filas.
- "Ver inventario" lee de aquí + de `productos` para la ficha.
- **Existencias nunca es un dato guardado.** Si el libro cambia, el stock
  cambia solo. Imposible desincronizar.
- Marketing leerá `movimientos_inventario` filtrando por `tipo='salida'` y
  agrupando por periodo/`product_id`/`customer_id`. Sin rehacer nada.

*(El signo del ajuste ya está resuelto, no es un detalle abierto: hay dos tipos,
`ajuste_entrada` y `ajuste_salida`, y `cantidad` es siempre positiva. La vista
solo tiene que sumar o restar según el `tipo`, sin lógica de signo. Ver §1.3.)*

---

## 2. Arquitectura de seguridad (el candado real está en los datos)

Reutilizamos **exactamente** el patrón de Finanzas. Nada nuevo que inventar.

### 2.1. Acceso por módulo: `tiene_modulo('inventario')`

- La función `tiene_modulo(text)` **ya existe** (migración de perfiles). La
  reutilizamos con el argumento `'inventario'`. No se toca.
- El admin (tú) ve todo. Un empleado futuro con `modulos = '{inventario}'`
  entra solo a Inventario. El candado real es RLS; ocultar la tarjeta en el
  panel es solo comodidad de UX.

### 2.2. RLS por tabla (interno)

| Tabla | authenticated puede | Por qué |
|---|---|---|
| `productos` | SELECT si `tiene_modulo('inventario')` | Lectura interna. Escritura solo por RPC. |
| `movimientos_inventario` | SELECT si `tiene_modulo('inventario')` | Igual. El libro se escribe por RPC. |
| `clientes` | SELECT si `tiene_modulo('inventario')` (o el módulo que corresponda a futuro) | Anticipado. |
| vista `stock_actual` | hereda de las tablas base | SECURITY INVOKER. |

- **Sin INSERT/UPDATE/DELETE directos** para el catálogo ni para el libro desde
  el cliente autenticado. Toda escritura pasa por **RPC security-definer** que
  valida `tiene_modulo('inventario')` al entrar (idéntico a `guardar_asiento`).
- **Sin DELETE en ninguna tabla.** Productos se marcan inactivos; movimientos se
  compensan con ajustes. Nada se borra en silencio.
- Recordar el **GRANT de capa 1**: con "auto-expose new tables" en OFF, hay que
  otorgar `SELECT` explícito al rol `authenticated` sobre las tablas y vistas
  que el cliente lee directo (lección aprendida en Finanzas, archivo de grants).

### 2.3. RPCs de escritura (security-definer, la única vía)

Espejo de las RPC de Finanzas:

- `inv_crear_producto(...)` → valida admin/módulo, genera SKU, inserta el
  producto, devuelve `{id, sku}`. (El UUID lo pone el default.)
- `inv_registrar_movimiento(product_id, tipo, cantidad, motivo, ...)` → valida
  módulo, valida que el producto exista y esté activo, valida `cantidad > 0`, e
  inserta en el libro. **Contrato de venta sin stock (DECIDIDO):** una `salida`
  que dejaría el stock en negativo **no se bloquea**; se registra igual y la
  vista muestra existencias negativas como señal honesta de que hay que
  reconciliar. El motivo: en el piloto la venta se confirma a mano, así que
  bloquear a nivel de datos daría una falsa sensación de control y podría impedir
  registrar una venta que de verdad ocurrió. La RPC devuelve el stock resultante
  para que la UI pueda alertar en el momento. (Si el dueño prefiere bloquear la
  salida en negativo, es un `if` de una línea en la RPC; ver §7.)
- `inv_editar_producto(...)` → edita SOLO la ficha (nombre, precio, etc.),
  **nunca** las existencias (esas solo se mueven por el libro).

Todas: `security definer`, `set search_path = public`, chequean
`tiene_modulo('inventario')` al entrar. Igual que Finanzas.

### 2.4. Lectura pública para la tienda (el punto delicado #1)

La tienda `magandhi.com` (otro repo, otro dominio, estático) debe **leer** el
producto para renderizar la página real (hoy 404). Reglas:

- **Nunca** exponer la secret/service_role. La tienda es pública: cualquiera ve
  su código.
- La tienda usaría la **publishable key** (pública por diseño) contra Supabase,
  **pero** las tablas internas están cerradas al rol `anon`. Necesitamos una
  **superficie de lectura pública mínima y controlada**, no abrir `productos`
  entero al público (eso filtraría costo, proveedor, ubicación, stock interno).

Dos caminos seguros, recomiendo el A:

- **A (recomendado): una VISTA pública `catalogo_publico`** que expone SOLO los
  campos que el cliente puede ver (`sku`, `nombre`, `descripcion`, `marca`,
  `precio_venta`, `imagen_path`, y opcionalmente `hay_stock` como booleano, no
  el número exacto), filtrada a `where publicado = true and activo = true`. Se
  otorga `SELECT` sobre esa vista al rol `anon`. **El costo, el stock exacto, el
  proveedor y la ubicación NUNCA salen.** Es el mínimo privilegio: el público ve
  una vitrina, no el inventario.
  - Riesgo controlado: exponer `hay_stock` como booleano evita que la
    competencia sepa cuántas unidades tienes. Si ni siquiera quieres revelar
    "disponible/agotado" a nivel de dato, se omite y la tienda asume disponible.
- **B (alternativa): una Edge Function pública de solo lectura** que devuelve el
  producto por SKU. Más control (puedes formatear, cachear, ocultar), pero más
  piezas que desplegar y mantener. Para solo-lectura de una vitrina, la vista
  (A) es más simple y igual de segura. **Recomiendo A y reservo Edge Functions
  para la ESCRITURA (§3), donde sí son imprescindibles.**

**Cómo la tienda enlaza al producto:** hoy el hero apunta a
`producto/grisi-manzanilla-gold/` (ruta que da 404). La página de producto real
leerá el SKU/slug de la URL y consultará `catalogo_publico`. El diseño de esa
página de tienda es un entregable aparte (repo `magandhi`), pero el plano deja
definida la superficie de datos que consumirá.

### 2.5. Baja de stock por venta

**Decisión de fase (importante, lee esto primero):** hoy la tienda **no tiene
checkout**; solo botones de contacto (correo, WhatsApp, Instagram) y un enlace de
producto que además da 404. No existe "venta concretada" automática que pueda
disparar nada. Por eso:

- **FASE 1 (el piloto), baja de stock MANUAL desde el back-office.** Cuando
  cierras una venta por WhatsApp/correo, tú (o un empleado con el módulo)
  registras la **salida** desde "Ver inventario" usando la misma RPC interna
  `inv_registrar_movimiento` (`tipo='salida'`, `motivo='Venta tienda'`,
  `referencia=<lo que quieras anotar>`). Cero piezas nuevas, cero secretos
  nuevos, y el libro queda igual de completo para Marketing.
- **FASE FUTURA, baja de stock automática desde la tienda.** El día que exista un
  checkout real (una pasarela o una confirmación de venta programática), se activa
  la Edge Function `registrar_venta` descrita abajo. **No es un paso del piloto.**
  La diseño ahora para que el contrato quede pensado, pero no se construye ni se
  despliega hasta que haya quién la invoque.

El resto de esta sección describe el **diseño futuro** de esa escritura pública,
para que quede documentado el patrón seguro cuando llegue el momento.

Cuando una venta **se concrete** de forma programática en la tienda, habrá que
registrar un movimiento de **salida** que reduzca el stock. Esto es una
**escritura** disparada desde un sitio público. Aquí está la línea innegociable:

> **Nunca dar escritura pública a la tabla ni exponer una llave privilegiada.**

Por eso **no** se hará desde el JavaScript de la tienda con ninguna llave que
pueda escribir. El patrón correcto (para esa fase futura):

- **Edge Function server-side `registrar_venta`** (se escribe en el repo, la
  despliega el dueño en Supabase). Corre en el servidor de Supabase, donde sí
  puede usar la service_role de forma segura (la service_role vive en las
  **variables de entorno de la Edge Function**, configuradas por el dueño en el
  dashboard, **jamás en el repo ni en el cliente**).
- La Edge Function se protege con un **secreto compartido** (un header/token que
  solo conoce el sistema que confirma la venta), o con Verify JWT según cómo se
  concrete la venta. El navegador anónimo del comprador **no** invoca esto
  directamente con permisos de escritura; lo invoca el paso de "venta
  concretada" (la pasarela/confirmación), que es donde vive el secreto.
- La función valida, y llama internamente a la lógica de
  `inv_registrar_movimiento` (o inserta el movimiento de salida con
  `tipo='salida'`, `motivo='Venta tienda'`, `referencia=<id venta>`,
  `customer_id` si existe). Todo server-side.

**Por qué así y no directo:** si la tienda pudiera escribir el stock con una
llave en el navegador, cualquiera con las herramientas de desarrollador podría
inflar o vaciar tu inventario. La Edge Function con secreto server-side es la
puerta estrecha: solo entra quien tiene el secreto, y el secreto nunca toca el
cliente ni el repositorio.

**Dónde vive cada secreto (resumen):**

| Secreto | Dónde vive | Dónde NUNCA está |
|---|---|---|
| Publishable key | Cliente (tienda y back-office) | (es pública, no es secreto) |
| service_role key | Variables de entorno de la Edge Function (dashboard Supabase) | Repo, cliente, tienda |
| Secreto de `registrar_venta` | Env de la Edge Function + el sistema que confirma la venta | Repo, JS de la tienda |

---

## 3. Estrategia de imágenes (Supabase Storage)

- **Un bucket** de Storage, propongo `productos` (o `inventario`).
- **Privacidad del bucket:** dos opciones.
  - **Bucket público de solo lectura** para las imágenes que la tienda muestra:
    las URLs son públicas (una foto de producto no es secreta), y la **escritura**
    (subir/reemplazar imagen) se restringe por policy a usuarios con el módulo.
    Simple y adecuado para fotos de vitrina.
  - **Bucket privado + URLs firmadas** si quisieras controlar quién ve cada
    imagen. Para fotos de producto de una tienda pública es sobre-ingeniería:
    las fotos están para mostrarse. **Recomiendo bucket público de lectura,
    escritura restringida.**
- **En la base guardamos `imagen_path`** (la ruta dentro del bucket), no una URL
  completa. La URL pública se arma en el cliente a partir del path. Así, si algún
  día cambia el dominio del bucket, no hay que migrar datos.
- **La subida** se hace desde "Agregar a inventario" con la sesión del usuario
  autenticado (nunca con service_role). Policy de Storage: `insert/update` solo
  si `tiene_modulo('inventario')`.
- **Nada de secretos.** La subida usa la sesión del usuario; la lectura pública
  usa la URL pública del bucket. La service_role no participa.

---

## 4. Mapa de conexiones META del ecosistema

```
                         ┌───────────────────────────┐
                         │   INVENTARIO (este módulo) │
                         │  productos + LIBRO de       │
                         │  movimientos + stock (vista)│
                         └───────────────────────────┘
                          ▲          ▲            │
        lee vitrina       │          │            │ salida (venta)
        (vista pública)   │          │            │  · FASE 1: manual desde
   ┌───────────────┐      │          │            │    back-office (RPC interna)
   │ TIENDA pública │─────┘          │            ▼
   │  magandhi.com  │                │     ┌──────────────────────┐
   │  (solo lectura,│  registrar_venta│----│ Edge Function          │
   │   sin checkout │  (FUTURO, secreto│    │ registrar_venta        │
   │   en el piloto)│   srv)          │     │ (service_role srv)     │
   └───────────────┘  · - - - - - - - - - ->│ FASE FUTURA (sin caller│
                                       │     │ en el piloto)          │
                                       │     └──────────────────────┘
                                       │ lee historial salidas por periodo
                          ┌────────────┴───────────┐
                          │  MARKETING PROJECT      │  (FUTURO)
                          │  proyección demanda,    │
                          │  clúster, elasticidad   │
                          └─────────────────────────┘

   PEDIDOS/CLIENTES (futuro) ── llenan customer_id en el libro

   CONTABILIDAD (Finanzas) ──✗── NO conectada. Manual. (Por decisión del dueño.)
```

- **Inventario ↔ Tienda:** lectura por vista pública `catalogo_publico`. La baja
  de stock por venta en **fase 1 es manual** desde el back-office (misma RPC
  interna `inv_registrar_movimiento`, `tipo='salida'`); la escritura automática
  por Edge Function con secreto server-side queda **para una fase futura**, cuando
  la tienda tenga checkout real que la invoque (ver §2.5).
- **Inventario ↔ Pedidos/Clientes (futuro):** `customer_id` y `referencia` ya
  anticipados en el libro. Cuando existan, se llenan; no se rehace nada.
- **Inventario ↔ Marketing (futuro):** Marketing lee `movimientos_inventario`
  (salidas por periodo, por producto, por cliente). El libro ES el dato que
  Marketing necesita. Por eso lo diseñamos así hoy.
- **Inventario ↔ Contabilidad:** **desconectados a propósito.** Cero enganche
  automático. Tú registras los asientos a mano en Finanzas.

### Preparación para Marketing (sin construirlo)

El Marketing Project tendrá, según lo que describiste: recolección automática de
datos + operación manual con categorías interconectadas (oportunidades de
mercado, análisis clúster, "cosas que podría estar ignorando", proyección de la
demanda con 3 métodos (promedio móvil, suavización exponencial, regresión
lineal) y elasticidad). El flujo: elegir Periodo + ajustes + método, botón
**INICIAR ANÁLISIS**, con **datos reales** de la organización.

Lo único que este plano garantiza para no bloquear a Marketing:

- **Serie temporal de ventas real:** el libro guarda `fecha`, `product_id`,
  `cantidad`, `customer_id`. Con eso se arma "cuánto vendimos en cada periodo",
  que es exactamente lo que necesitan promedio móvil, suavización exponencial y
  regresión lineal.
- **Precio en el tiempo:** `precio_venta` y `costo_unitario_mov` permiten después
  analizar elasticidad (cómo cambia la cantidad ante cambios de precio).
- **Categoría/marca/cliente:** habilitan análisis clúster y de oportunidades sin
  columnas nuevas.

No se construye ninguna tabla de Marketing ahora. Solo se deja el terreno firme.

---

## 5. Diseño / UI del área Inventario (al nivel de Finanzas)

**Regla de color (tuya, innegociable): NO metemos colores nuevos.** Ya tenemos
verde, azul y terracota. Inventario **no** estrena un cuarto color. Se diferencia
de Finanzas por **layout y jerarquía**, no por tinte.

### 5.1. Reutilización directa

- `marca.css` (tokens base) y `finanzas-core.js` como **referencia de patrón**.
  Propongo un `inventario-core.js` hermano que reutilice: `supabase-config.js`,
  `auth-guard.js`, `asegurarAcceso` (adaptado a `'inventario'`), `montarHeader`,
  `ICONOS`, `escaparHTML`, `montarSelloImpulse`, formateo de pesos. Idealmente
  se **factoriza** lo común para no duplicar (decisión de implementación: extraer
  un núcleo compartido o clonar el patrón; lo dejo para el coder con guía).
- Header institucional fijo idéntico en estructura al de Finanzas (marca +
  "ÁREA DE INVENTARIO" + avatar/perfil + volver al panel).
- Sello "Con tecnología Impulse" al pie. Solo back-office, nunca la tienda.
- Tarjetas de navegación, tablas con `tabular-nums`, modales: mismos
  componentes visuales que Finanzas.

### 5.2. Color de área SIN color nuevo

Primero, el hecho, porque en un borrador anterior lo tenía al revés y no quiero
que decidas sobre una premisa falsa. Según `marca-areas/LEEME.md`, los favicons
de área ya en uso son:

- `control-interno.png` (login / panel general) = **azul marino**.
- `finanzas.png` (Área de Finanzas) = **verde** (coincide con el token
  `--fz-salvia` #5B8A6F que Finanzas usa para el estado "cuadrado").

O sea: **el verde YA es la identidad del área de Finanzas.** Recomendar verde
para Inventario haría que las dos áreas chocaran en vez de diferenciarse. Ese es
justo el error que hay que evitar.

**Regla dura tuya, intacta:** NO se introducen colores nuevos. Los que hay son
verde (Finanzas), azul marino (control interno / header de Finanzas) y terracota
(`--rojo` de marca, el rojo principal). Inventario tiene que salir de ese set.

- **Recomendación:** Inventario **hereda el azul marino** de la familia
  back-office (`--fz-marino` #101C33, el mismo del header institucional y del
  panel), y se diferencia de Finanzas **por layout y jerarquía**, no por tinte.
  Es exactamente el fallback que este mismo plan ya proponía y es el camino más
  limpio: no toca la identidad verde de Finanzas, no reutiliza el terracota (que
  en el ecosistema carga significado contable de DEBE y de la tienda pública), y
  mantiene la cohesión visual del back-office. La diferencia se siente en la
  disposición ("vitrina de fichas" con la imagen al mando, ver §5.3), no en el
  color.
- **Si prefieres un tinte propio sin estrenar color:** la única opción que no
  pisa a otra área sería el **terracota** existente (`--rojo`). Lo dejo como
  segunda opción, pero con la advertencia honesta: el terracota ya significa
  "DEBE" en Finanzas y es el color de la tienda pública, así que reusarlo como
  color de área podría confundir. Por eso recomiendo el azul marino + layout.
- **Decisión tuya:** ¿Inventario hereda el **azul marino** y se distingue por
  layout (mi recomendación), o prefieres el **terracota** existente como tinte de
  área? Ninguna opción introduce color nuevo, y ninguna toca el verde de Finanzas.

### 5.3. Las pantallas

**Home del módulo (`inventario/index.html`)**: tarjetas de navegación, igual
que la home de Finanzas:

- **Ver inventario** → lista.
- **Agregar a inventario** → alta.
- (Futuro, dejar hueco visual): "Movimientos" (el libro completo), "Alertas de
  stock bajo".

**Ver inventario (`inventario/ver.html`)**:

- Buscador arriba (por SKU o nombre), mismo patrón que el buscador PUC.
- Tabla/tarjetas con: imagen miniatura, SKU (tabular), nombre, categoría,
  **existencias** (de la vista `stock_actual`, en grande), precio, estado
  (activo / stock bajo si `< stock_minimo`, marcado con un token existente).
- Al abrir un producto: ficha detallada + su historial de movimientos (timeline
  como la bitácora de Finanzas). Para señalar el tipo de movimiento se reutilizan
  tokens existentes (por ejemplo entradas en el verde salvia `--fz-salvia` y
  salidas en terracota `--rojo`); son colores de estado dentro de la lista, no el
  color de área, así que no compiten con la identidad de ningún módulo.
- Jerarquía visual distinta a Finanzas: Finanzas es denso y numérico por
  filas; Inventario es más "vitrina de fichas" (la imagen manda), lo que lo
  diferencia sin cambiar de paleta.

**Agregar a inventario (`inventario/agregar.html`)**:

- Formulario: nombre, descripción, marca, categoría, unidad de medida,
  contenido, costo, precio, stock mínimo, ubicación, proveedor, **cantidad
  inicial** (que genera el primer movimiento de `entrada`), **imagen** (subida a
  Storage).
- **El SKU y el UUID se muestran como "se generarán automáticamente"** (el
  dueño no los escribe). Tras guardar, se muestra el SKU generado.
- Un solo envío: crea el producto (RPC) + registra el movimiento de entrada
  inicial (RPC) + sube la imagen. Mensajes de éxito/error como en Finanzas.

**Registrar movimiento (entrada/salida/ajuste manual)**: puede ser parte de
"Ver" (botón por producto) o pantalla propia. Decisión de implementación menor.

### 5.4. Panel: nueva tarjeta

En `panel.html`, agregar una tarjeta **Inventario** análoga a la de Finanzas,
visible si `perfil.rol === 'admin' || modulos.includes('inventario')`. Icono
nuevo en el set `ICONOS` (una caja/almacén), sin color nuevo. El favicon de área
va en `marca-areas/` con el color de área que decidas en §5.2 (azul marino
recomendado); **no verde**, porque el verde ya es de Finanzas.

---

## 6. Plan de implementación por pasos (cuando se apruebe)

Orden pensado para el flujo Git del proyecto: **rama nueva + PR por cada
feature**, nunca push directo a main, el dueño mergea y aplica el SQL a mano en
Supabase siguiendo `INSTRUCCIONES.md`.

Las migraciones seguirían el prefijo de fecha ordenado, después de las de
finanzas (`20250201...`). Propongo prefijo `20250301...` para Inventario:

1. **Migración: catálogo `productos` + `clientes` mínima + config de SKU**
   (`20250301000000_inventario_productos.sql`). Tablas, índices, secuencia del
   consecutivo de SKU, tabla/fila de configuración del prefijo (clonable).
2. **Migración: libro `movimientos_inventario`**
   (`20250301000100_inventario_movimientos.sql`). Con FKs, checks de cantidad y
   tipo, índices por `product_id` y `fecha` (Marketing).
3. **Migración: vista `stock_actual`**
   (`20250301000200_inventario_stock_vista.sql`). Derivación del libro.
4. **Migración: RLS de todas las tablas de inventario**
   (`20250301000300_inventario_rls.sql`). Con `tiene_modulo('inventario')`.
5. **Migración: RPCs de escritura**
   (`20250301000400_inventario_funciones.sql`). `inv_crear_producto`,
   `inv_registrar_movimiento`, `inv_editar_producto`, generación de SKU.
6. **Migración: GRANTs de capa 1**
   (`20250301000500_inventario_grants.sql`). SELECT a `authenticated` sobre lo
   que el cliente lee directo (lección de Finanzas).
7. **Migración: superficie pública de la tienda**
   (`20250301000600_inventario_catalogo_publico.sql`). Vista `catalogo_publico`
   + GRANT SELECT a `anon`. Solo campos de vitrina.
8. **Storage: bucket + policies** (documentado en `INSTRUCCIONES.md`, lo crea el
   dueño en el dashboard; el repo documenta el paso).
9. **Frontend back-office:** `inventario/index.html`, `inventario/ver.html`,
   `inventario/agregar.html`, `inventario/inventario-core.js`,
   `inventario/inventario.css` (reutilizando patrón de Finanzas, sin color
   nuevo), favicon de área en `marca-areas/`. Incluye el registro **manual** de
   salida por venta (misma RPC `inv_registrar_movimiento`), que es la baja de
   stock del piloto.
10. **Panel:** tarjeta Inventario en `panel.html` con el candado por rol/módulo.
11. **`INSTRUCCIONES.md`:** sección nueva de Inventario con el orden EXACTO de
    ejecución del SQL, verificaciones (crear producto, registrar entrada, ver
    stock derivado, registrar salida manual, confirmar que baja), y cómo dar
    acceso al módulo a un empleado (`modulos = '{inventario}'`).

Cada paso es un PR revisable. El SQL no se despliega solo: lo aplica el dueño.

### Trabajo FUTURO (fuera del piloto, no son pasos de fase 1)

Estos NO se construyen hasta que exista quién los use. Los dejo listados para
que quede claro que están pensados, pero fuera de alcance del piloto:

- **Edge Function `registrar_venta`** (carpeta `supabase/functions/`): se activa
  cuando la tienda tenga un **checkout real** que la invoque. Se documentará el
  despliegue manual y las env vars/secretos; el dueño la desplegaría con Verify
  JWT / secreto según convenga (ver §2.5). Sin checkout, no tiene caller, así que
  no es un paso del piloto.
- **Tienda `magandhi.com` (repo aparte):** página de producto real que lee
  `catalogo_publico` y resuelve el 404 del hero. Entregable del otro repo; se
  planifica por separado, pero el contrato de datos (la vista pública) queda
  definido aquí. Mientras tanto, la vitrina puede quedarse en los botones de
  contacto actuales.

---

## 7. Preguntas abiertas para el dueño (decisiones que faltan)

Para no asumir por ti, estas son las decisiones que quiero que confirmes antes
de implementar:

1. **Formato de SKU:** ¿`MAG-SHAM-0001` (con categoría) o `MAG-0001` (simple)?
2. **Color de área:** el verde **ya es de Finanzas** (favicon `finanzas.png`),
   así que queda descartado para Inventario. La pregunta real es: ¿Inventario
   **hereda el azul marino** y se distingue por layout (mi recomendación, ver
   §5.2), o prefieres el **terracota** existente como tinte de área? Ninguna
   opción introduce color nuevo.
3. **Lotes / fecha de vencimiento:** ¿fase 1 o lo dejamos para después? (Mi
   recomendación honesta: para después; un sistema de lotes bien hecho es
   complejo y sería gold-plating para el piloto.)
4. **Tabla `clientes` mínima:** ¿la creamos vacía ya (para que `customer_id` sea
   FK real) o dejamos `customer_id` sin FK hasta construir Clientes? (Recomiendo
   crearla mínima.)
5. **`hay_stock` en la vitrina pública:** ¿la tienda puede mostrar
   "disponible/agotado", o ni siquiera eso (asume disponible)? Afecta qué expone
   `catalogo_publico`.

**Decisiones que ya tomé en este plan (antes eran preguntas abiertas, pero son
load-bearing y no debían quedar en el aire; las puedes revertir, pero el plan
tiene postura por defecto):**

- **Signo del `ajuste`:** resuelto con dos tipos separados `ajuste_entrada` /
  `ajuste_salida` (ver §1.3 y §1.6). `cantidad` sigue siendo siempre positiva y
  el `tipo` define el signo. Sin ambigüedad en el check ni en la vista.
- **Venta sin stock:** por defecto se **permite y se alerta** (existencias
  negativas visibles como señal honesta), porque en el piloto la venta se
  confirma a mano y bloquear a nivel de datos daría una falsa sensación de
  control (ver §2.3 y §2.5). Si prefieres bloquear la salida cuando dejaría el
  stock en negativo, es un cambio de una línea en la RPC; dímelo y lo invierto.

---

## 8. Riesgos y notas honestas (sin humo)

- **La baja de stock automática es la pieza con más partes móviles, y por eso la
  saqué del piloto.** La Edge Function `registrar_venta` se escribiría en el repo
  y la desplegaría el dueño con sus secretos, pero **no hay quién la invoque
  todavía**: la tienda solo tiene botones de contacto (correo, WhatsApp,
  Instagram), el enlace de producto da 404 y no hay checkout. Construirla ahora
  sería diseñar para un flujo inexistente. **Decisión tomada:** en fase 1 la baja
  de stock por venta se hace **a mano desde el back-office** (registras la salida
  con la misma RPC interna); la Edge Function queda diseñada y documentada para
  una **fase futura**, cuando exista un checkout real. Así no dependemos de la
  pieza más frágil para tener el módulo funcionando.
- **Stock negativo:** con la decisión por defecto (permitir la salida y alertar,
  ver §2.3), el libro puede dar existencias negativas cuando registras una venta
  de algo que no tenías cargado. Es información **honesta** (te avisa que hay que
  reconciliar el conteo), no un error a esconder. La UI lo muestra en rojo como
  señal. Si prefieres bloquear la salida en negativo, es un cambio de una línea
  en la RPC (ver §7).
- **Clonabilidad:** el prefijo de SKU y cualquier textito de "MAGANDHI" en el
  área deben salir de configuración/tokens, no ir escritos a fuego, para que
  Impulse clone el módulo a otra organización cambiando pocas cosas.
- **No hay build ni tests automatizados** en este proyecto (sitio estático). La
  verificación es manual: aplicar el SQL en un entorno de Supabase y correr las
  queries de comprobación (crear producto → registrar entrada → ver stock → 
  registrar salida → confirmar que baja), más revisión visual de las páginas.

---

## Resumen de una línea

Inventario = catálogo de productos con `product_id` (UUID) + SKU legible
autogenerados, cuyo stock **se deriva de un libro de movimientos append-only**
(igual que el mayor se deriva del diario en Finanzas); seguro por RLS +
`tiene_modulo('inventario')` + RPCs; con lectura pública mínima para la tienda
vía vista, y baja de stock por venta vía Edge Function con secreto server-side
(nunca llaves en el cliente); imágenes en Storage por ruta; visualmente hermano
de Finanzas **sin color nuevo**; y con el libro diseñado para alimentar
Marketing sin rehacer nada. Contabilidad queda manual y desconectada, como pediste.
