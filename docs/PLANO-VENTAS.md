# PLANO MAESTRO · Área de Ventas (ecosistema Impulse · piloto MAGANDHI)

> **Estado: APROBADO POR EL DUEÑO — EN CONSTRUCCIÓN.** El dueño revisó el plano
> y dio luz verde con las decisiones registradas abajo. Este documento es la
> memoria fiel del diseño.
>
> Tono: socio honesto. Donde hay una decisión con costo o un riesgo, lo digo
> sin humo. Donde algo es "para después", lo marco para no caer en
> gold-plating.

---

## ⭐ DECISIONES FINALES DEL DUEÑO (sesión de aprobación) — prevalecen sobre el resto

Estas cierran las preguntas abiertas de la §10:

- **Baja de stock: al CREAR el pedido** (no al entregar). Coherente con la puerta
  web futura, que también bajará al crear. La salida al libro (`referencia = id
  del pedido`) ocurre al registrar/crear el pedido.
- **Estados del pedido (4):** **Recibido → Preparando → En camino → Entregado.**
  ("En camino" lo añadió el dueño: es la etapa que el cliente más quiere saber.)
  Más un terminal aparte para cancelado/anulado y otro para **devuelto** (ver
  devoluciones). Los estados quedan preparados para, MÁS ADELANTE, disparar
  correos al cliente en algunas etapas (Email Marketing / notificaciones =
  enchufe futuro, NO se construye ahora).
- **Coincidencia de cliente: 3 niveles** alta / media / baja, con % y explicación;
  el humano decide con botón (nunca fusiona solo, nunca bloquea).
- **DEVOLUCIONES — decisión de alcance:** NO se construye la pantalla de
  devoluciones en esta tanda. Se construye Ventas (Pedidos + Portafolio) con el
  **MOTOR de devolución técnicamente listo por debajo**: la capacidad de revertir
  un pedido con una **entrada compensatoria** al inventario (nunca borrando; misma
  filosofía del libro append-only). La devolución **siempre se ancla a un pedido
  existente** (parte de un pedido, no de producto que aparece de la nada).
  - La CATEGORÍA "Devoluciones" será una sub-área de **PRODUCCIÓN** (hermana de
    Inventarios), NO de Ventas — porque una devolución es producto físico que
    vuelve a la bodega. Se construirá DESPUÉS, cuando el dueño defina su POLÍTICA
    de devoluciones (qué se acepta, en qué estado, plazo, y el matiz belleza vs
    objeto: un cosmético abierto/higiene no se revende por temas sanitarios; un
    objeto en buen estado sí). Esa política es decisión de NEGOCIO/LEGAL del dueño
    (marco: derecho de retracto Ley 1480), NO del software. El software registra
    la devolución que el dueño APRUEBA; no decide si procede (regla de oro: la
    máquina registra, el humano decide). El modelo actual del dueño (él revisa
    calidad antes de entregar) acota el caso a: cliente insatisfecho o daño en la
    entrega. Diseñar para devolución **parcial** (compró 3, devuelve 1) además de
    total.
- **Diseño / interfaz: PILAR innegociable**, al nivel de Finanzas. Especial
  cuidado en que "Seguimiento de pedidos" sea clarísimo de un vistazo (pantalla
  operativa para quien prepara y entrega) y en la UX del registro con las
  coincidencias (candidatos con % + botones, sin abrumar). Azul marino heredado,
  sin color nuevo, sello Impulse, wordmark MAGANDHI.
- **Alcance de HOY:** construir el área Ventas con sus 2 sub-áreas (Seguimiento de
  pedidos —con registro manual y coincidencias— y Portafolio de clientes),
  encender el `customer_id`, y dejar el enchufe de devolución listo. NO: pantalla
  de Devoluciones, ni Clúster/salud, ni Email, ni geocoding, ni enganche a
  Finanzas (cita a ciegas).

---

## Contexto: Ventas es la CUARTA área del back-office

Hoy el panel (`panel.html`) tiene tres áreas jerárquicas, cada una una carpeta:

```
PANEL ADMIN (panel.html)
├── FINANZAS    (finanzas/)      → Contabilidad PUC (v1 terminado)
├── MARKETING   (marketing/)     → Marketing Project
├── PRODUCCIÓN  (produccion/)    → Inventarios
└── VENTAS      (ventas/)        → NUEVA, la que diseña este plano
       ├── Seguimiento de pedidos   (ventas/seguimiento-pedidos/)
       └── Portafolio de clientes   (ventas/portafolio-clientes/)
```

**Ventas es un ÁREA** (como Marketing o Finanzas), no una herramienta suelta.
Vive en la carpeta `ventas/` con su `ventas/index.html` (home del área con
tarjetas de sub-área), su `ventas-core.js` hermano de los otros cores, y
**dos sub-áreas**:

1. **Seguimiento de pedidos**: dónde se muestra lo que hay que entregar, cuándo
   y a dónde (útil para quien prepara y quien entrega). Aquí vive también el
   **registro manual de un pedido**.
2. **Portafolio de clientes**: dónde se almacena la información de los clientes
   (que también podrán usar los otros softwares), para poder filtrar quién
   compró más en el último mes y ver métricas objetivas del cliente.

Este plano ata todo el diseño al **código real que ya existe**: el libro de
Inventario (`movimientos_inventario`), su RPC de escritura
(`inv_registrar_movimiento`), el wrapper de acceso (`tiene_acceso_inventario()`),
el enchufe apagado (`customer_id`) y el marcador `CONEXION FUTURA` que ya está
puesto en `marketing/marketing-project/ranking-productos.html`.

---

## 0. Qué estamos construyendo y por qué así

Ventas es el software que le dijiste al equipo: un lugar apropiado y **muy
organizado** para el seguimiento de los pedidos, donde cada pedido muestre el
correo del cliente, su pedido, cuándo hizo la orden, su dirección, su teléfono,
su nombre, en un orden apropiado. Y, en paralelo, un lugar donde esos datos se
**recolecten** en base de datos para alimentar lo que viene: la dirección para
ubicaciones geográficas y rutas (futuro), el correo para email marketing
(futuro), y todo lo demás que alimenta las fuentes.

La decisión de arquitectura central, la que hace que todo esto sea posible sin
rehacer nada mañana, es esta: **un mismo núcleo, dos puertas de entrada.** Hay
UNA sola función que crea un pedido (baja inventario, guarda la orden, vincula
al cliente, registra el precio real). Hoy esa función se invoca desde un
**formulario manual** (una venta cerrada por WhatsApp, Instagram o correo, que
tú diligencias a mano). Mañana, cuando exista checkout web con Wompi, ese mismo
núcleo lo invocará la web automáticamente. No hay dos lógicas: hay un núcleo y
dos puertas.

**Por qué manual primero:** hoy la tienda no tiene checkout (Wompi está
pendiente, ver CONTEXTO-MAGANDHI). Diseñar solo para la web sería diseñar para
un flujo que no existe. El registro manual es el flujo **de HOY**, y deja el
enchufe listo para que la web se conecte sin rehacer el núcleo.

### Lo que NO hace (para tener límites claros)

- **No tiene checkout ni cobra con Wompi todavía.** El registro manual es el
  flujo de fase 1. La puerta web queda diseñada como enchufe, no construida.
- **No calcula la "salud" del cliente.** El Portafolio muestra el **dato
  objetivo** (última compra, número de pedidos, total gastado) y no lo
  interpreta. La salud del cliente (por periodo, de un cliente o general) la
  hará el **Análisis Clúster** más adelante, dentro de Marketing. El Clúster
  será cargado y se hace después; aquí solo se deja el terreno (Portafolio +
  pedidos) para que lo lea.
- **No hace email marketing.** Solo deja el **correo normalizado** listo como
  enchufe. El envío de campañas es un software futuro.
- **No hace geocoding ni mapas.** Solo deja los **campos de dirección** con
  terreno para geolocalización futura. Nada de trazar rutas todavía.
- **Está DESCONECTADO de Finanzas a propósito.** Es la "cita a ciegas" que ya
  decidiste: Ventas, Inventario y Finanzas no se enganchan automáticamente. La
  contabilidad la registras a mano en Finanzas. Un error en un lado no envenena
  el otro. Este plano NO diseña ningún enganche automático Ventas → Finanzas.

### Las dos reglas de identidad de Impulse, aplicadas aquí

1. **Solo datos propios.** Ventas trabaja con lo que la organización sabe de sí
   misma: sus pedidos, sus clientes, sus precios. Nada externo.
2. **Entrega el dato, no lo interpreta.** Por eso dos cosas concretas de este
   diseño: (a) el porcentaje de coincidencia de cliente **lo decide el humano**
   con un botón (la máquina calcula el número y lo explica, tú eliges), y (b) la
   salud del cliente **no se etiqueta aquí**; el Portafolio muestra la cifra
   cruda y el Clúster futuro la analizará.

---

## 1. Modelo de datos

### 1.1. Las piezas y cómo encajan

```
  clientes ──1───────────────┐
   (identidad del cliente,    │ id (uuid) = el customer_id que ENCIENDE
    correo/telefono norm.)    │            el enchufe apagado del libro
                              ▼
   pedidos ──1──────────────► pedido_items ──► productos (product_id)
    (la orden: fecha,          (una linea por           (catalogo de
     estado, canal, total)      producto vendido,        Inventario, ya existe)
                                con PRECIO REAL)
                              │
                              │ al crear/confirmar el pedido, cada item
                              ▼ registra una SALIDA en el libro de Inventario
                    movimientos_inventario  (EL LIBRO, ya existe)
                     tipo='salida', referencia=pedido_id, customer_id=cliente

  portafolio_metricas (VISTA) = deriva de pedidos por cliente → nunca se guarda
```

El principio es el mismo de Inventario y Finanzas: **el hecho se escribe, el
agregado se deriva.** Aquí: **el pedido se escribe, las métricas del cliente se
derivan de una vista.**

### 1.2. Tabla `clientes` (identidad del cliente)

El `id` de esta tabla es **el `customer_id` que enciende el enchufe apagado**
del libro de Inventario (hoy `movimientos_inventario.customer_id` es un `uuid`
nullable SIN FK; ver §2).

| Columna | Tipo | Fase | Para qué |
|---|---|---|---|
| `id` | `uuid` PK `default gen_random_uuid()` | 1 | El `customer_id` que conecta con el libro, con los pedidos y con el Clúster futuro. Autogenerado. |
| `nombre` | `text` NOT NULL | 1 | Nombre del cliente tal como lo diligencias. |
| `correo` | `text` NULL | 1 | El correo tal como lo escribió/dictó el cliente (lo que se ve). |
| `correo_norm` | `text` NULL, indexado UNIQUE (parcial) | 1 | Correo **normalizado** (minúsculas, `trim`). Es la red anti-duplicados y la señal fuerte del algoritmo (§4). Único cuando no es nulo. |
| `telefono` | `text` NULL | 1 | Teléfono tal como se capturó (lo que se ve). |
| `telefono_norm` | `text` NULL, indexado UNIQUE (parcial) | 1 | Teléfono **normalizado** a forma canónica (§1.4). Segunda señal fuerte del algoritmo. Único cuando no es nulo. |
| `direccion` | `text` NULL | 1 | Dirección de entrega en texto libre (para quien prepara y entrega). |
| `ciudad` | `text` NULL | 1 | Ciudad/municipio. Barato de incluir; agrupa entregas. |
| `departamento` | `text` NULL | 1 | Departamento. Igual, terreno para geo futura. |
| `pais` | `text` NULL default `'Colombia'` | 1 | País. Terreno geo. |
| `lat` | `double precision` NULL | futuro | Latitud. **Solo terreno**, no se llena en fase 1 (nada de geocoding ahora). |
| `lng` | `double precision` NULL | futuro | Longitud. Igual, terreno para mapas/rutas. |
| `notas` | `text` NULL | 1 | Notas libres del cliente (referencia de la casa, preferencias). |
| `activo` | `boolean` NOT NULL default `true` | 1 | Alta/baja lógica. **Nunca se borra** un cliente (rompería el historial de pedidos): se inactiva. |
| `creado` | `timestamptz` default `now()` | 1 | Auditoría. |
| `creado_por` | `uuid` ref `auth.users` default `auth.uid()` | 1 | Quién lo registró. |
| `actualizado` | `timestamptz` NULL | 1 | Última edición de la ficha. |

**Campos que dejo PARA DESPUÉS (no inflar fase 1):**

- `documento` / tipo de identificación: útil si algún día se factura formal. Hoy
  no lo necesitamos; se agrega con un `alter table` cuando haga falta.
- Segmentos/etiquetas del cliente: eso lo produce el Clúster (§7), no se guarda a
  mano aquí.

### 1.3. Por qué correo y teléfono van DUPLICADOS (original + normalizado)

Guardamos dos columnas por cada dato de contacto: el **original** (lo que se ve
en pantalla, tal como se capturó) y el **normalizado** (la forma canónica,
indexada y única). Razón:

- El **normalizado** es lo que compara el algoritmo de coincidencia (§4) y lo que
  lleva el índice UNIQUE que actúa como **red de seguridad anti-duplicados** por
  debajo del algoritmo. Dos formas distintas de escribir el mismo correo colapsan
  a la misma clave.
- El **original** se conserva porque es lo que el cliente dijo y lo que se ve
  bonito en la ficha; no se pierde información.

La unicidad es **parcial** (solo aplica cuando el valor no es nulo), porque un
cliente puede no tener correo o no tener teléfono, y no queremos que dos clientes
sin correo choquen entre sí por tener ambos `correo_norm = NULL`.

### 1.4. Normalización (reglas claras y explicables)

Nada de magia: reglas deterministas y auditables, coherentes con "el porcentaje
se basa en datos reales" (§4).

- **Correo → `correo_norm`:** `trim` + pasar a minúsculas. Ejemplo:
  `"  Juan.Perez@Gmail.com "` → `"juan.perez@gmail.com"`. (En fase 1 no se
  aplican reglas específicas de proveedor como quitar puntos de Gmail; se deja
  como posible mejora futura para no sobre-ingenierizar.)
- **Teléfono → `telefono_norm`:** quitar espacios, guiones, paréntesis y el
  prefijo `+57` / `57` de país cuando aplique, dejando la forma canónica de
  dígitos. Ejemplo: `"+57 300-123 4567"` → `"3001234567"`. Reglas explícitas,
  fáciles de leer en el copy de la coincidencia ("mismo teléfono").

Estas normalizaciones las hace la RPC server-side al crear/editar el cliente
(no el navegador), para que la clave única sea consistente de verdad.

### 1.5. Tabla `pedidos` (la orden)

| Columna | Tipo | Fase | Para qué |
|---|---|---|---|
| `id` | `uuid` PK `default gen_random_uuid()` | 1 | El id del pedido. **Es el valor que va en `movimientos_inventario.referencia`** al bajar stock (§2). |
| `customer_id` | `uuid` NOT NULL ref `clientes(id)` | 1 | A qué cliente pertenece el pedido. FK real (dentro de Ventas sí hay FK, ver §2 para la del libro). |
| `fecha_orden` | `date` NOT NULL default `current_date` | 1 | Cuándo se realizó la orden (dato que pediste mostrar). Fecha contable de la venta. |
| `estado` | `text` NOT NULL check (ciclo de vida, §5) | 1 | En qué punto va el pedido (recibido / preparando / entregado / anulado). |
| `canal` | `text` NOT NULL check in (`'manual'`,`'web'`) default `'manual'` | 1 | Por qué puerta entró. Hoy siempre `'manual'`; `'web'` queda listo para el checkout futuro (§3). |
| `total` | `bigint` NOT NULL default `0` | 1 | Total del pedido en **pesos enteros** (bigint, nunca float). Se calcula desde los items. |
| `notas` | `text` NULL | 1 | Notas del pedido (instrucciones de entrega, observaciones). |
| `anulado` | `boolean` NOT NULL default `false` | 1 | Marca de anulación lógica. **Nada se borra** (§5). |
| `motivo_anulacion` | `text` NULL | 1 | Bitácora de por qué se anuló. |
| `creado` | `timestamptz` default `now()` | 1 | Auditoría. |
| `creado_por` | `uuid` ref `auth.users` default `auth.uid()` | 1 | Quién registró el pedido. |
| `actualizado` | `timestamptz` NULL | 1 | Última actualización de estado. |

### 1.6. Tabla `pedido_items` (las líneas del pedido)

| Columna | Tipo | Fase | Para qué |
|---|---|---|---|
| `id` | `uuid` PK `default gen_random_uuid()` | 1 | Identidad de la línea. |
| `pedido_id` | `uuid` NOT NULL ref `pedidos(id)` | 1 | A qué pedido pertenece. |
| `product_id` | `uuid` NOT NULL ref `productos(id)` | 1 | Qué producto se vendió (llave del catálogo de Inventario). |
| `cantidad` | `integer` NOT NULL check (`cantidad > 0`) | 1 | Cuántas unidades. **Entero** (unidades enteras), igual que el libro. |
| `precio_unitario` | `bigint` NOT NULL | 1 | **El PRECIO REAL de esta venta**, en pesos enteros (bigint). Este es el dato que enciende el "ingreso real" del Ranking de Marketing (hoy estimado con `precio_venta` actual del producto; ver §7). |
| `subtotal` | `bigint` NOT NULL | 1 | `cantidad * precio_unitario`, en pesos enteros. Redundante pero explícito y auditable. |

**Por qué `precio_unitario` aquí y no leer `productos.precio_venta`:** el precio
de un producto cambia con el tiempo. Si el Ranking calculara el ingreso con el
precio actual, sería una estimación (así lo dice hoy honestamente el marcador
`CONEXION FUTURA` en `ranking-productos.html`). Guardando el precio **en el
momento de la venta**, el ingreso pasa de estimado a exacto sin rehacer nada.

### 1.7. DDL de EJEMPLO (propuesta, NO migración definitiva)

Esto es una **propuesta** embebida en el documento, igual que hace
PLANO-INVENTARIO. No es una migración aplicable; el DDL real se afina y se
ordena al construir (§9).

```sql
-- PROPUESTA (no aplicar): tabla clientes
create table if not exists clientes (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  correo        text,
  correo_norm   text,
  telefono      text,
  telefono_norm text,
  direccion     text,
  ciudad        text,
  departamento  text,
  pais          text default 'Colombia',
  lat           double precision,   -- terreno geo futuro (sin geocoding hoy)
  lng           double precision,   -- terreno geo futuro
  notas         text,
  activo        boolean not null default true,
  creado        timestamptz default now(),
  creado_por    uuid default auth.uid(),
  actualizado   timestamptz
);

-- Indices UNICOS parciales = red anti-duplicados por debajo del algoritmo (§4).
create unique index if not exists clientes_correo_norm_uidx
  on clientes (correo_norm) where correo_norm is not null;
create unique index if not exists clientes_telefono_norm_uidx
  on clientes (telefono_norm) where telefono_norm is not null;
-- Indice de apoyo para la busqueda por nombre (senal debil):
create index if not exists clientes_nombre_idx on clientes (lower(nombre));

-- PROPUESTA (no aplicar): tabla pedidos
create table if not exists pedidos (
  id               uuid primary key default gen_random_uuid(),
  customer_id      uuid not null references clientes(id),
  fecha_orden      date not null default current_date,
  estado           text not null default 'recibido'
                     check (estado in ('recibido','preparando','entregado','anulado')),
  canal            text not null default 'manual'
                     check (canal in ('manual','web')),
  total            bigint not null default 0,
  notas            text,
  anulado          boolean not null default false,
  motivo_anulacion text,
  creado           timestamptz default now(),
  creado_por       uuid default auth.uid(),
  actualizado      timestamptz
);
create index if not exists pedidos_customer_idx on pedidos (customer_id);
create index if not exists pedidos_fecha_idx    on pedidos (fecha_orden);

-- PROPUESTA (no aplicar): lineas del pedido
create table if not exists pedido_items (
  id              uuid primary key default gen_random_uuid(),
  pedido_id       uuid not null references pedidos(id),
  product_id      uuid not null references productos(id),
  cantidad        integer not null check (cantidad > 0),
  precio_unitario bigint not null,   -- PRECIO REAL de la venta (bigint, pesos)
  subtotal        bigint not null
);
create index if not exists pedido_items_pedido_idx  on pedido_items (pedido_id);
create index if not exists pedido_items_product_idx on pedido_items (product_id);
```

### 1.8. Métricas del Portafolio como VISTA derivada (no dato guardado)

Igual que `stock_actual` deriva del libro de Inventario, las métricas del cliente
**se derivan de `pedidos`**, no se guardan. Una vista `portafolio_metricas`
(SECURITY INVOKER, hereda RLS) por cliente:

- **Última compra:** `max(fecha_orden)` de sus pedidos no anulados.
- **Número de pedidos:** conteo de pedidos no anulados.
- **Total gastado:** suma de `total` de sus pedidos no anulados.

Al ser una vista, es **filtrable** (por ejemplo, "quién compró más en el último
mes" = ordenar por total gastado con `fecha_orden` en el último mes). Y como no
es un dato guardado, **es imposible desincronizar**: si se anula un pedido, la
métrica cambia sola.

```sql
-- PROPUESTA (no aplicar): metricas objetivas del Portafolio
create or replace view portafolio_metricas as
select
  c.id                                   as customer_id,
  c.nombre                               as nombre,
  max(p.fecha_orden)                     as ultima_compra,
  count(p.id)                            as num_pedidos,
  coalesce(sum(p.total), 0)::bigint      as total_gastado
from clientes c
  left join pedidos p
    on p.customer_id = c.id and p.anulado = false
group by c.id, c.nombre;
```

**El Portafolio muestra el DATO OBJETIVO y no interpreta la salud del cliente.**
Frecuencia, recencia y gasto son cifras crudas. Decidir si un cliente está
"sano", "en riesgo" o "dormido" es el trabajo del **Análisis Clúster** futuro
(§7), que leerá estas mismas tablas. Aquí no hay etiquetas de opinión, por la
regla de identidad de Impulse.

---

## 2. Cómo se enciende el `customer_id` y se conecta con el libro

Hoy, en `movimientos_inventario` (ver
`20250301000100_inventario_movimientos.sql`):

- `customer_id` es un `uuid` **nullable SIN FK**: el "enchufe apagado". El
  comentario de la columna lo dice literal: preparado para cuando exista el
  software de Clientes, sin tocar Inventario.
- `referencia` es un `text` pensado para el id de un origen externo (el id del
  pedido).

**Al encender Ventas**, cuando se crea/confirma un pedido, cada línea del pedido
registra una **salida** en el libro usando la RPC que YA existe:

```
inv_registrar_movimiento(
  p_product_id = <product_id del item>,
  p_tipo       = 'salida',
  p_cantidad   = <cantidad del item>,
  p_motivo     = 'Venta',
  p_referencia = <pedidos.id>,           -- el id del pedido va aqui
  p_costo_unitario_mov = null,
  p_fecha      = <fecha_orden>
)
```

Y el `customer_id` del cliente del pedido se estampa en esa fila del libro. Así
Marketing (y el Clúster futuro) podrá cruzar "qué compró quién" leyendo el libro,
que es exactamente para lo que el enchufe se dejó apagado.

Recordatorio de contrato ya existente: una **salida sin stock NO se bloquea**
(la RPC la permite y devuelve las existencias resultantes para que la UI alerte).
Ese comportamiento se respeta tal cual; Ventas no lo cambia.

### ¿Convertir `movimientos_inventario.customer_id` en FK real a `clientes(id)`?

**Recomendación: SÍ, convertirla en FK real**, en la migración de Ventas que
crea `clientes`. Razones:

- Integridad: un `customer_id` en el libro que no exista en `clientes` sería un
  dato huérfano imposible de cruzar; la FK lo previene.
- Bajo riesgo de migración: hoy la columna está **vacía en producción** (nunca se
  ha llenado porque Ventas no existe), así que agregar la FK no exige migrar ni
  reconciliar datos viejos. Es el momento barato de hacerlo.

Postura honesta por defecto: convertirla a FK **cuando se cree `clientes`** (paso
`20250401000400`, ver §9), con `alter table ... add constraint ... references
clientes(id)`. Si prefieres dejarla suelta un tiempo más (por si el diseño de
`clientes` cambia), es una decisión tuya (§10); mi recomendación es encenderla
ya, porque está vacía y el costo es mínimo.

---

## 3. El núcleo único `crear_pedido` (RPC) con dos puertas

Una sola RPC server-side, `crear_pedido` (nombre propuesto; también sirve
`ventas_crear_pedido` para mantener prefijo de área, ver §10), que **ambas
puertas invocan**:

- **Puerta 1, manual (HOY):** el formulario de "Seguimiento de pedidos". Una
  venta cerrada por WhatsApp, Instagram o correo, que tú diligencias. No depende
  de Wompi.
- **Puerta 2, web (FUTURO):** el checkout de la tienda cuando exista Wompi.
  Invocará el **mismo** núcleo. No se rehace nada.

### La cadena que dispara `crear_pedido` (en una transacción)

1. **Vincular o crear el cliente** en el Portafolio: recibe el `customer_id`
   elegido por el humano (§4) o, si es cliente nuevo, crea la fila en `clientes`
   con la normalización de correo/teléfono (§1.4). **Ante colisión del UNIQUE
   parcial** (`correo_norm` o `telefono_norm` ya existente), la RPC **no falla y
   no crea un cliente duplicado**: resuelve al cliente existente que ya tiene ese
   contacto y lo usa como `customer_id`, de modo que **el registro del pedido
   nunca se cae**. El detalle de este comportamiento y su orden de precedencia
   está en §4.5.
2. **Crear la orden:** inserta en `pedidos` (con `canal`, `fecha_orden`, estado
   inicial) y una fila en `pedido_items` por cada producto, guardando el
   **`precio_unitario` real** de la venta. Calcula `total` en bigint.
3. **Bajar inventario:** por cada item, una **salida** en el libro vía
   `inv_registrar_movimiento` (`tipo='salida'`, `motivo='Venta'`,
   `referencia=pedidos.id`, `customer_id=cliente`). El momento exacto de la baja
   (al crear vs al entregar) se decide en §5.
4. **Registrar el precio real:** ya guardado en `pedido_items.precio_unitario`,
   lo que **enciende el ingreso real del Ranking** de Marketing.

### El enchufe para la web futura

`crear_pedido` recibe el `canal` como parámetro. El checkout web futuro llamará
la misma RPC con `canal='web'` (y, cuando haya Wompi, tras confirmar el pago).
No hay una segunda lógica de "venta web": es la misma puerta con otro rótulo de
canal. Esto es lo que hace innecesario rehacer el núcleo el día que llegue Wompi.

### Reglas duras que respeta la RPC

- `security definer` con `set search_path = public`.
- Chequea `tiene_acceso_ventas()` al entrar (§6), espejo del patrón de las RPC de
  Inventario.
- Montos en **bigint** (total, precio_unitario, subtotal), cantidades **integer**.
- Reutiliza `inv_registrar_movimiento` para tocar el libro (no reimplementa la
  baja de stock; respeta el contrato existente, incluida la salida sin stock).

---

## 4. Algoritmo de coincidencia de cliente (identidad)

Este es el corazón técnico que pediste: identificar si un cliente ya había
comprado o es nuevo, casi infalible, **sin basarse solo en el nombre**
(ineficiente), reconociendo patrones sobre **datos reales** (reglas claras y
explicables, NO una IA de caja negra). Debe dejarte registrar el pedido aunque la
coincidencia sea baja, **nunca fusiona solo y nunca bloquea**.

### 4.1. Puntaje por señales (explicable)

Se calcula un puntaje sumando señales, cada una con un peso fijo y una razón
legible. Jerarquía de confianza:

| Señal | Fuerza | Cómo se detecta | Peso propuesto |
|---|---|---|---|
| Mismo `correo_norm` exacto | **FUERTE** | Igualdad sobre el correo normalizado (§1.4) | muy alto |
| Mismo `telefono_norm` exacto | **FUERTE** | Igualdad sobre el teléfono normalizado | muy alto |
| Nombre muy parecido | débil | Similitud por distancia de edición (Levenshtein) sobre el nombre normalizado (minúsculas, sin acentos, `trim`) | bajo/medio según similitud |
| Correo con typo | débil | Similitud alta pero no exacta sobre `correo_norm` (un carácter de diferencia) | bajo |
| Misma ciudad/dirección aproximada | débil (apoyo) | Coincidencia de ciudad; refuerza, no decide | muy bajo |

Regla de diseño: **una señal fuerte sola ya da confianza alta**; las señales
débiles **no alcanzan por sí solas** una confianza alta (el nombre parecido nunca
basta, justo lo que pediste). Varias débiles juntas suben, pero de forma acotada.

### 4.2. Traducción a porcentaje y clasificación

El puntaje total se traduce a un **porcentaje** (0 a 100) y se clasifica en tres
bandas con **explicación textual**:

- **Alta** (por ejemplo, correo o teléfono exactos): "coincidencia alta por
  correo y teléfono".
- **Media** (varias señales débiles, o una débil fuerte como correo con un typo):
  "coincidencia media por nombre muy parecido y misma ciudad".
- **Baja** (solo nombre algo parecido): "coincidencia baja, solo por el nombre".

Los umbrales exactos de cada banda (qué porcentaje separa alta de media de baja)
son una **pregunta abierta para ti** (§10): los propongo con valores de arranque
y los afinamos con datos reales. El punto innegociable es que el **porcentaje se
basa en datos reales y reglas fijas**, no en un modelo opaco: cada número se
puede explicar en una frase.

### 4.3. Dónde corre el cálculo (RPC server-side)

**Recomendación: una RPC de búsqueda server-side**, `buscar_candidatos_cliente`
(nombre propuesto), que reciba correo/teléfono/nombre ya normalizados y devuelva
una lista de candidatos, cada uno con su **score, su porcentaje y sus señales**
(el porqué). Razones:

- No trae toda la tabla `clientes` al navegador (privacidad + rendimiento; son
  datos personales de terceros, §6).
- El cálculo del puntaje vive en un solo lugar auditable, no disperso en el
  cliente.

Implicación de esquema (ya prevista en §1): `correo_norm` y `telefono_norm` en
columnas aparte, **indexadas**, con **UNIQUE parcial** como red de seguridad
anti-duplicados por debajo del algoritmo. La distancia de edición para el nombre
puede apoyarse en `pg_trgm` (a evaluar al construir; si no se habilita, hay
alternativas explicables en SQL puro).

### 4.4. Flujo de UI (tú decides, la máquina no)

Tal como lo visualizas:

1. Diligencias los datos del pedido (arriba).
2. **Debajo del formulario** aparece la lista de candidatos, cada uno con su **%
   y el porqué** ("coincidencia de 92% por mismo correo y teléfono").
3. Tú eliges con un botón: **"Es este cliente"** (por candidato) o **"Registrar
   como cliente nuevo"**.
4. Si eliges un candidato de alta coincidencia, un mensaje de confirmación sobrio
   ("Este cliente coincide en un X% con [nombre]. ¿Registrar el pedido como él?").

Reglas de hierro:

- **El sistema NUNCA fusiona solo.** Siempre eres tú quien confirma.
- **El sistema NUNCA bloquea el registro.** Aunque la coincidencia sea baja o
  nula, siempre puedes registrar (como el candidato que elijas o como nuevo).

Los copys de este documento son **ejemplos**; el copy final se afina en
implementación (voz MAGANDHI, sin jerga técnica). Lo cuadras tú.

### 4.5. Las dos redes anti-duplicados y quién manda (orden de precedencia)

Hay **dos** mecanismos que evitan clientes duplicados, y conviven en distinta
capa. Es importante decir cuál gana para que nunca se contradigan:

1. **El UNIQUE parcial sobre `correo_norm`/`telefono_norm` (§1) es el PISO DURO.**
   Vive en la base de datos, es infalible dentro de su regla: no puede haber dos
   filas de `clientes` con el mismo `correo_norm` (o el mismo `telefono_norm`).
2. **El puntaje explicable (§4.1 a §4.4) es la RECOMENDACIÓN BLANDA para ti.**
   Ordena candidatos con un porcentaje y su porqué, pero no decide nada por su
   cuenta.

**Regla de precedencia: el UNIQUE gana.** Los dos pueden discrepar (por ejemplo,
un candidato con porcentaje bajo pero con `correo_norm` idéntico al que estás
diligenciando). Para que eso **nunca aborte el registro**, `crear_pedido` se
comporta así ante una colisión de `_norm`:

- Si diligencias un correo/teléfono cuyo normalizado **ya existe** y pediste
  "registrar como cliente nuevo", la RPC **no inserta un duplicado**: **resuelve
  al cliente existente** que tiene ese contacto y registra el pedido a su nombre.
  El pedido se crea igual (nunca se bloquea).
- Cómo se te presenta esto al humano: ese cliente existente **siempre aparece
  como candidato en la lista de abajo** (con su porqué: "mismo correo" o "mismo
  teléfono"), aunque el puntaje por otras señales sea bajo. Es decir, un `_norm`
  idéntico **fuerza** que el dueño de ese contacto salga como candidato, para que
  no elijas "nuevo" a ciegas contra el piso duro. Si aun así confirmas, el sistema
  te lo asigna a ese cliente existente en vez de fallar.
- El caso raro de **dos personas reales que comparten un teléfono** (familia,
  negocio) se aborda en §11: como el piso duro no debe tumbar una venta legítima,
  la salida es relajar la unicidad del teléfono (dejarla solo en correo). Nunca
  se sacrifica la regla de hierro "no bloquea" por mantener el índice.

En resumen: **la máquina protege contra duplicados con el UNIQUE, tú decides la
identidad con el puntaje, y el registro del pedido nunca se cae.**

---

## 5. Ciclo de vida del pedido y manejo honesto de cancelación/devolución

### 5.1. Estados (sobrios, sin sobre-ingeniería)

Propuesta de `estado` con `check` (o enum): `recibido` → `preparando` →
`entregado`, más `anulado` como estado terminal aparte. Sin estados de más para
el piloto; los nombres exactos son pregunta abierta (§10).

```
 recibido ──► preparando ──► entregado
     │              │
     └──────────────┴──────► anulado  (con bitacora, nunca se borra)
```

### 5.2. ¿Cuándo baja el stock? (al crear vs al entregar)

**Recomendación: bajar el stock al CREAR/CONFIRMAR el pedido** (estado inicial),
no al marcarlo entregado. Razones:

- En el piloto, un pedido manual se registra **porque la venta ya se concretó**
  (se cerró por WhatsApp). El producto ya salió o está comprometido; reflejarlo en
  el libro de inmediato mantiene el stock honesto.
- Es coherente con el contrato de Inventario: la salida sin stock no se bloquea,
  se alerta. Registrar la salida temprano da la señal a tiempo.

Contrapartida honesta: si un pedido se anula después, hay que **revertir** la
salida (§5.3). Es un caso conocido y barato de manejar con un movimiento
compensatorio. El momento exacto de la baja es, aun así, decisión tuya (§10);
dejo la recomendación con su porqué.

### 5.3. Cancelación / devolución (nunca borrando)

Coherente con el libro append-only de Inventario: **nada se borra.**

- **Anular un pedido:** se marca `pedidos.anulado = true` con
  `motivo_anulacion` (bitácora), NO se hace DELETE.
- **Revertir el stock:** por cada item del pedido anulado, se registra un
  movimiento de **ENTRADA compensatorio** en el libro (vía
  `inv_registrar_movimiento`, `tipo='entrada'`, `motivo='Anulacion de venta'`,
  `referencia=pedidos.id`), que devuelve al inventario lo que la salida había
  restado. El libro conserva ambos hechos (la salida original y la entrada
  compensatoria), auditable de punta a punta.

Una devolución parcial se maneja igual: una entrada compensatoria por la
cantidad devuelta. Sin borrar, sin editar hechos viejos.

**La cadena de anulación corre en una TRANSACCIÓN** (igual que `crear_pedido`,
§3): marcar `pedidos.anulado = true` y registrar las entradas compensatorias en
el libro son un solo hecho atómico. O pasa todo, o no pasa nada. Así se evita el
caso feo de que la entrada compensatoria se registre pero el `update` de
`pedidos.anulado` no (o al revés), que dejaría el libro y el estado del pedido
**desincronizados**. Esta anulación vive en su propia RPC security definer
(nombre propuesto `anular_pedido`, ver §10), con `set search_path = public` y
chequeo de `tiene_acceso_ventas()`, igual que el resto.

---

## 6. Arquitectura de seguridad (el candado real está en los datos)

Se reutiliza **exactamente** el patrón de Inventario y Finanzas.

### 6.1. Wrapper `tiene_acceso_ventas()`, espejo de `tiene_acceso_inventario()`

Igual que `tiene_acceso_inventario()` envuelve `tiene_modulo()` y acepta las tres
claves equivalentes (`inventario`/`produccion`/`inventarios`),
`tiene_acceso_ventas()` envuelve `tiene_modulo()` y acepta las claves de área y
sub-área de Ventas:

```sql
-- PROPUESTA (no aplicar): wrapper de acceso del area Ventas
create or replace function tiene_acceso_ventas()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('ventas')       -- clave del area
      or tiene_modulo('pedidos')       -- sub-area seguimiento de pedidos
      or tiene_modulo('clientes')      -- sub-area portafolio
      or tiene_modulo('portafolio');   -- alias de la sub-area portafolio
$$;
```

Así el candado de datos habla el mismo idioma que el panel y el core. El admin ve
todo (lo resuelve `tiene_modulo`).

### 6.2. RLS estricta y datos personales de terceros

| Tabla / vista | authenticated puede | Escritura |
|---|---|---|
| `clientes` | SELECT si `tiene_acceso_ventas()` | Solo por RPC security definer |
| `pedidos` | SELECT si `tiene_acceso_ventas()` | Solo por RPC security definer |
| `pedido_items` | SELECT si `tiene_acceso_ventas()` | Solo por RPC security definer |
| `portafolio_metricas` (vista) | hereda de sus tablas base | SECURITY INVOKER |

Línea firme del dueño, reforzada aquí: **los datos personales de terceros
(correos, teléfonos, direcciones) NUNCA se exponen al rol `anon`/público.** La
publishable key desde afuera **no debe poder leerlos**. Concretamente:

- **Cero GRANT a `anon`** sobre cualquier tabla o vista de Ventas. Todo el área es
  tras login (`authenticated`).
- **Escritura solo vía RPC security definer de ESCRITURA** (`crear_pedido`,
  `anular_pedido`, y las que editen cliente), cada una con
  `set search_path = public` y chequeo de `tiene_acceso_ventas()` al entrar.
  Ninguna tabla tiene policy de INSERT/UPDATE/DELETE para el cliente.
- **Lectura controlada:** `buscar_candidatos_cliente` (§4.3) es una RPC de **SOLO
  LECTURA**. Corre como `security definer` no para escribir, sino para **leer de
  forma acotada** (devuelve candidatos con su score y señales) sin abrir toda la
  tabla `clientes` al navegador. No escribe nada; se lista aparte de las RPC de
  escritura justamente por eso.
- **SIN DELETE** en ninguna tabla: clientes y pedidos se inactivan/anulan con
  bitácora.
- **GRANT SELECT explícito a `authenticated`** sobre lo que el cliente lee directo
  (auto-expose OFF, misma lección que Inventario: sin ese GRANT de capa 1,
  Postgres rechaza antes de evaluar RLS).
- **Cero `service_role` / secretos en el repo.**
- La vista `portafolio_metricas` es **SECURITY INVOKER**: hereda la RLS de
  `clientes`/`pedidos`, no la evade.

---

## 7. Mapa META de conexiones del ecosistema

```
                     ┌─────────────────────────────┐
                     │   VENTAS (esta area)         │
                     │  clientes + pedidos +        │
                     │  pedido_items + metricas     │
                     └─────────────────────────────┘
                       │            ▲            ▲
    salida por pedido  │            │            │ lee Portafolio + pedidos
    (referencia=ped.id,│            │            │ (FUTURO: Analisis Cluster
     customer_id)      ▼            │            │  agrupa clientes / salud)
             ┌──────────────────┐  │      ┌──────┴───────────────┐
             │  INVENTARIO      │  │      │  MARKETING           │
             │  (el LIBRO ya    │  │      │  Ranking usa precio  │
             │   existe)        │  │      │  REAL (deja de       │
             │  salida='Venta'  │  │      │  estimar)            │
             │  entrada=        │──┘      └──────────────────────┘
             │  compensacion    │
             └──────────────────┘

   VENTAS → EMAIL MARKETING (FUTURO): correo_norm alimentara campanas. Solo enchufe.
   VENTAS → MAPAS / RUTAS   (FUTURO): direccion/ciudad alimentaran geo. Solo terreno.
   VENTAS ──✗── FINANZAS: DESCONECTADO a proposito (cita a ciegas). Contabilidad manual.
```

- **Ventas ↔ Inventario:** cada pedido baja stock con una salida en el libro
  usando el enchufe `referencia` (= `pedidos.id`) y `customer_id`. La
  cancelación/devolución se maneja con un **movimiento de entrada compensatorio**
  (§5.3). Reutiliza `inv_registrar_movimiento`; no toca el esquema de Inventario
  salvo, opcionalmente, encender la FK del `customer_id` (§2).
- **Ventas ↔ Marketing:** enciende el `customer_id` del libro para el análisis
  por cliente/Clúster, y aporta el **precio real** de cada venta
  (`pedido_items.precio_unitario`) para que el Ranking deje de estimar. **NOTA de
  implementación:** cuando se construya Ventas, hay que actualizar el marcador
  `CONEXION FUTURA (software de Ventas)` que ya existe en
  `marketing/marketing-project/ranking-productos.html` (en la función
  `agregarRanking`, donde hoy toma `prod?.precio_venta` como precio), para que el
  ingreso use el precio real de cada venta en vez del `precio_venta` actual. Al
  hacerlo, se ajusta también la nota `.mk-transparencia` (que hoy dice "Será
  exacto cuando exista el software de Ventas") y el rótulo "Ingreso estimado".
- **Ventas → Análisis Clúster (FUTURO, en Marketing):** leerá `clientes`,
  `pedidos` y `portafolio_metricas` para agrupar clientes y calcular la **salud
  por periodo** (de un cliente o general). NO se construye ahora; Ventas solo deja
  el terreno firme.
- **Ventas → Email Marketing (FUTURO):** el `correo_norm` normalizado alimentará
  campañas. Solo enchufe, sin envío.
- **Ventas → Mapas / Rutas (FUTURO):** `direccion`, `ciudad`, `lat`, `lng`
  alimentarán geolocalización y rutas. Solo terreno, sin geocoding.
- **Ventas ↔ Finanzas: DESCONECTADO a propósito.** La cita a ciegas. Cero
  enganche automático. La contabilidad la registras a mano en Finanzas. Este
  plano NO diseña ese enganche.

---

## 8. Diseño / UI de las dos pantallas (al nivel de Finanzas)

**Regla de color (tuya, innegociable): SIN color nuevo.** Ventas **hereda el
azul marino** `#101C33` del back-office (el mismo del header institucional y del
panel) y se diferencia por **layout y jerarquía**, no por tinte. Como dijiste:
"no quiero un arcoíris". El verde ya es de Finanzas; el terracota carga
significado en Finanzas (DEBE) y en la tienda pública.

### 8.1. Reutilización: `ventas-core.js` hermano

Un `ventas-core.js` hermano de `inventario-core.js` y `marketing-core.js`, que
reutilice `supabase-config.js` y `auth-guard.js` y exponga:

- `asegurarAcceso`: **gate de UX en JS**, equivalente al de los otros cores. Ojo
  con no confundir dos cosas que se llaman parecido:
  - El **gate de UX** vive en el core (JS) y es una **comodidad**: lee
    `perfil.modulos` con un helper cliente (`tieneAccesoVentas(perfil)`, espejo
    de `tieneAccesoMarketing(perfil)` en `marketing-core.js`) para decidir si
    muestra u oculta la pantalla y redirige con gracia. NO llama a la función
    SQL. Sirve para que el usuario sin permiso no vea una pantalla rota.
  - El **candado real** (el que de verdad protege los datos) es la **RLS
    server-side** apoyada en la función SQL `tiene_acceso_ventas()` (§6). Ese
    candado se cumple aunque alguien salte el JS: Postgres no devuelve filas si
    la RLS no pasa.
  - Por eso el gate de UX **no se cuelga de** `tiene_acceso_ventas()` (la función
    de datos): son capas distintas. El core solo replica la comodidad de UX que
    ya tienen Inventario y Marketing; la seguridad de verdad está en §6.
- `montarHeader` con "ÁREA DE VENTAS", header azul marino, wordmark MAGANDHI.
- `ICONOS`, `escaparHTML`, `formatearCOP` (pesos con puntos de miles).
- `montarSelloImpulse` (pie "Con tecnología Impulse", solo back-office).

### 8.2. Estructura de carpetas y archivos (siguiendo produccion/ y marketing/)

```
ventas/
├── index.html                       (home del area: tarjetas de sub-area)
├── ventas-core.js                   (core hermano)
├── ventas.css                       (estilos del area, sin color nuevo)
├── seguimiento-pedidos/
│   ├── index.html                   (tablero/lista de pedidos)
│   └── registrar.html               (formulario de pedido manual + candidatos)
└── portafolio-clientes/
    ├── index.html                   (lista/filtro de clientes)
    └── ver.html                     (ficha de un cliente)
```

(Los nombres de carpeta de sub-área son propuesta; ver §10.)

### 8.3. Seguimiento de pedidos

- **Tablero/lista muy organizado** (importa la interfaz, lo sabes): por cada
  pedido, los datos del cliente en orden apropiado (nombre, correo, teléfono,
  dirección), el pedido (producto(s) + cantidad), la **fecha de la orden**, y el
  **ESTADO** con su ciclo de vida (§5), útil para quien prepara y quien entrega.
  Tabla con `tabular-nums`, filtros por estado/fecha, modal de detalle con
  timeline como Finanzas/Inventario.
- **Registrar pedido manual:** formulario con los datos del pedido y, **debajo**,
  la lista de candidatos de coincidencia con su % y su porqué (§4), con los
  botones "Es este cliente" / "Registrar como cliente nuevo".

### 8.4. Portafolio de clientes

- **Lista filtrable** de clientes (por ejemplo, "quién compró más en el último
  mes", ordenando por total gastado con `fecha_orden` reciente).
- **Ficha por cliente** (`ver.html`): datos del cliente + historial de pedidos +
  **métricas objetivas** (última compra, frecuencia/número de pedidos, total
  gastado), tomadas de la vista `portafolio_metricas`. Muestra **solo el dato
  objetivo**: no interpreta la salud (eso es el Clúster futuro).

### 8.5. Panel: nueva tarjeta de Ventas (cuarta entrada de `AREAS`)

En `panel.html`, agregar la **cuarta entrada** al arreglo `AREAS` y su tarjeta
HTML, análoga a las de Finanzas/Marketing/Producción:

```js
// PROPUESTA para el arreglo AREAS de panel.html (cuarta entrada):
{ id: 'ventas', claves: ['ventas','pedidos','clientes','portafolio'], card: 'mg-card-ventas' },
```

Visible si `perfil.rol === 'admin'` o `modulos` contiene alguna de esas claves.
Ícono nuevo en el set `ICONOS` (por ejemplo, un carrito/recibo), **sin color
nuevo**. Favicon de área en `marca-areas/` en la **familia azul marino** (como
hoy son placeholders `produccion.png`/`marketing.png`), sin estrenar color: el
área se distingue por layout, no por tinte.

---

## 9. Plan de implementación por pasos (cuando se apruebe)

Orden pensado para el flujo Git del proyecto: **rama nueva + PR por cada
feature**, nunca push directo a main, el dueño mergea y aplica el SQL a mano en
Supabase siguiendo `INSTRUCCIONES.md`.

Las migraciones de Inventario usan el prefijo `20250301...` y las de Finanzas
`20250201...`. Para Ventas propongo el **siguiente**, `20250401...`:

1. **`20250401000000_ventas_clientes.sql`**: tabla `clientes` + normalización
   (columnas `_norm`) + índices UNIQUE parciales (red anti-duplicados) + índice
   de nombre.
2. **`20250401000100_ventas_pedidos.sql`**: tablas `pedidos` y `pedido_items` +
   `check` del ciclo de vida + índices por `customer_id`, `fecha_orden`,
   `pedido_id`, `product_id`.
3. **`20250401000200_ventas_portafolio_vista.sql`**: vista `portafolio_metricas`
   (SECURITY INVOKER, derivada de `pedidos`).
4. **`20250401000300_ventas_rls.sql`**: wrapper `tiene_acceso_ventas()` + RLS
   (solo SELECT bajo el wrapper) en `clientes`/`pedidos`/`pedido_items`; **cero**
   policy para `anon`. Aquí también, opcionalmente, se **enciende la FK** de
   `movimientos_inventario.customer_id → clientes(id)` (§2).
5. **`20250401000400_ventas_funciones.sql`**: RPCs `crear_pedido` (las dos
   puertas, la cadena completa, transaccional), `anular_pedido` (anulación +
   entrada compensatoria, también transaccional, §5.3) y
   `buscar_candidatos_cliente` (solo lectura, el algoritmo de coincidencia).
   Todas security definer, `set search_path = public`, chequean
   `tiene_acceso_ventas()`.
6. **`20250401000500_ventas_grants.sql`**: `GRANT SELECT` a `authenticated`
   sobre `clientes`, `pedidos`, `pedido_items` y la vista (auto-expose OFF, misma
   lección que Inventario). Nada a `anon`.

Luego, frontend y panel (cada uno un PR revisable):

7. **Frontend back-office:** carpeta `ventas/` con `index.html`, `ventas-core.js`,
   `ventas.css`, las dos sub-áreas (`seguimiento-pedidos/`,
   `portafolio-clientes/`) y el favicon de área en `marca-areas/` (familia azul
   marino, sin color nuevo).
8. **Panel:** cuarta tarjeta de Ventas en `panel.html` (entrada en `AREAS` +
   HTML), con el candado por rol/módulo.
9. **Marcador de Marketing:** actualizar el `CONEXION FUTURA` en
   `marketing/marketing-project/ranking-productos.html` para que el Ranking use el
   **precio real** (`pedido_items.precio_unitario`) en vez del `precio_venta`
   actual, y ajustar la nota `.mk-transparencia` y el rótulo "Ingreso estimado".
10. **`supabase/INSTRUCCIONES.md`:** sección nueva de Ventas con el **orden EXACTO
    de aplicación manual** del SQL (000000 → 000500), queries de verificación
    (crear un cliente, registrar un pedido manual, confirmar que baja el stock en
    el libro con `referencia=pedido_id`, anular un pedido y confirmar la entrada
    compensatoria, ver las métricas derivadas del Portafolio), y cómo dar acceso
    al área a un empleado (`modulos = '{ventas}'` o una sub-área).

El SQL no se despliega solo: lo aplica el dueño a mano.

---

## 10. Preguntas abiertas para el dueño (decisiones que faltan)

Para no asumir por ti, confirma estas antes de implementar:

1. **Nombres exactos de los estados del ciclo de vida:** propongo
   `recibido / preparando / entregado / anulado`. ¿Te sirven esos rótulos o
   prefieres otros (por ejemplo, "en camino")?
2. **Momento en que baja el stock:** ¿al crear/confirmar el pedido (mi
   recomendación, §5.2) o al marcarlo entregado?
3. **Claves del wrapper y de los módulos de rol:** propongo
   `ventas / pedidos / clientes / portafolio` para `tiene_acceso_ventas()` y para
   el arreglo `AREAS`. ¿Confirmas ese conjunto?
4. **FK del `customer_id` del libro:** ¿la convertimos en FK real a `clientes(id)`
   ahora que está vacía (mi recomendación, §2) o la dejamos suelta un tiempo más?
5. **Umbrales del % de coincidencia:** ¿qué porcentaje separa **alta / media /
   baja** (§4.2)? Los propongo con valores de arranque y los afinamos con datos
   reales.
6. **Nombres de las carpetas de sub-área:** propongo
   `ventas/seguimiento-pedidos/` y `ventas/portafolio-clientes/`. ¿Te gustan o
   prefieres otros?
7. **Nombre de la RPC del núcleo:** `crear_pedido` o `ventas_crear_pedido` (para
   mantener el prefijo de área). Detalle menor, tú decides. Lo mismo para la RPC
   de anulación (`anular_pedido` o `ventas_anular_pedido`, §5.3).

**Nota:** el **copy final** del algoritmo de coincidencia (los mensajes de "es
este cliente", "coincidencia de X%", etc.) lo afina el dueño/orquestador en
implementación, con la voz MAGANDHI y sin jerga técnica. Los textos de este
documento son solo ejemplos.

---

## 11. Riesgos y notas honestas (sin humo)

- **El algoritmo de coincidencia es la pieza con más criterio, no la más
  compleja de código.** El código (comparar normalizados, distancia de edición)
  es directo; lo delicado son los **pesos y umbrales**. Por eso el diseño insiste
  en que sea explicable y en que **el humano decide**: si un umbral queda flojo,
  se ajusta un número, no se rehace nada. Y como nunca fusiona solo, un umbral
  imperfecto no daña datos.
- **Duplicados de cliente:** el índice UNIQUE parcial sobre `correo_norm` y
  `telefono_norm` es la red de seguridad (piso duro) por debajo del algoritmo. El
  orden de precedencia entre ese UNIQUE y el puntaje explicable, y qué hace
  `crear_pedido` ante una colisión de `_norm` (resolver al cliente existente en
  vez de fallar, sin bloquear el registro), están **cerrados en §4.5**, no
  quedan al aire. Riesgo residual honesto: si dos clientes reales comparten un
  teléfono (una familia, un negocio), el UNIQUE de teléfono podría empujar dos
  ventas legítimas al mismo cliente. Es un caso raro en el piloto; si aparece, se
  maneja relajando la unicidad del teléfono (dejándola solo en correo) sin romper
  nada, porque **la regla de hierro "no bloquea" siempre gana sobre mantener el
  índice**. Lo dejo anotado, no lo sobre-diseño ahora.
- **Bajar stock al crear el pedido puede dejar existencias negativas** si se
  vende algo no cargado en Inventario. Eso NO se bloquea (contrato existente de
  `inv_registrar_movimiento`): es una señal honesta de reconciliación, y la UI la
  muestra. La anulación revierte con una entrada compensatoria.
- **Wompi sigue pendiente** (ver CONTEXTO-MAGANDHI): por eso la puerta web es
  enchufe, no construcción. El registro manual no depende de Wompi y es el flujo
  de fase 1. El día que Wompi esté listo, el checkout invoca el mismo
  `crear_pedido` con `canal='web'`.
- **No hay build ni tests automatizados** (sitio estático). La verificación es
  manual: aplicar el SQL en Supabase y correr las queries de comprobación
  (crear cliente → registrar pedido manual → ver que baja el stock con
  `referencia=pedido_id` → anular → confirmar entrada compensatoria → ver
  métricas del Portafolio), más revisión visual de las dos pantallas.
- **Clonabilidad:** como el resto del ecosistema, evitar textos "MAGANDHI"
  escritos a fuego en el área; que salgan de la marca compartida, para que Impulse
  replique Ventas a otra organización con pocos cambios.

---

## Resumen de una línea

Ventas = la cuarta área del back-office (carpeta `ventas/`) con dos sub-áreas
(Seguimiento de pedidos y Portafolio de clientes), montada sobre un **núcleo
único `crear_pedido` con dos puertas** (manual hoy, web con Wompi mañana) que
baja stock en el libro de Inventario vía `inv_registrar_movimiento`
(`tipo='salida'`, `referencia=pedido_id`, encendiendo el `customer_id`) y guarda
el **precio real** que apaga la estimación del Ranking (marcador `CONEXION
FUTURA` en `ranking-productos.html`); con un **algoritmo de coincidencia de
cliente por puntaje explicable** (señal fuerte = correo/teléfono normalizados,
débil = nombre parecido) que propone porcentajes pero **nunca fusiona solo ni
bloquea** (tú eliges con un botón); seguro por RLS + `tiene_acceso_ventas()` +
RPCs security definer, con datos personales de terceros **nunca públicos**; con
las métricas del Portafolio **derivadas de una vista** (sin interpretar la salud,
eso es el Clúster futuro); visualmente hermano de Finanzas **sin color nuevo**; y
**desconectado de Finanzas a propósito** (la cita a ciegas, contabilidad manual).
