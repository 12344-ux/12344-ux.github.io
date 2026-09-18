# 🏗️ ANDAMIOS — Diligencia de correcciones + conexión Wompi (MAGANDHI / Impulse)
# 🏗️ ANDAMIOS — Plan maestro: correcciones + conexión Wompi (MAGANDHI / Impulse)

> **Qué es este archivo.** El plan maestro de la jornada de "corregir y conectar".
> Es una lista larga de tareas agrupadas en **TRAMOS ordenados por dependencia**
> (primero esto para que luego pueda ir aquello). Se **actualiza a medida que se
> avanza**: cada tramo terminado se marca ✅ con su PR. El objetivo es que si no
> terminamos en una sesión, **el próximo Kiro sepa EXACTO dónde retomar** sin
> perder el hilo. Cuando todo esté ✅, este archivo se archiva y su contenido se
> vuelca a `CONTEXTO-MAGANDHI.md`.
>
> **Metodología del dueño (respetarla):** regar fichas → discutir → mirar bajo
> los tapetes → trazar → construir. Nada de afán. La interfaz es PILAR. Verificar
> con EVIDENCIA, no con el papel. Rama nueva + PR por cada TRAMO; nunca push a
> main; el dueño mergea. El SQL/Edge/Storage lo aplica el dueño a mano.
>
> **Repos:** back-office = `12344-ux/12344-ux.github.io` (montaguth.institute) ·
> tienda = `12344-ux/magandhi` (magandhi.com).
>
> _Última actualización: **Fases A–E COMPLETAS y F1 (Wompi · intención de pago) ✅ TERMINADO Y VERIFICADO** (D3 ⏸️ pospuesto por decisión del dueño). La tienda ya llega al **checkout REAL de Wompi en sandbox**: formulario del comprador → Edge Function `crear-intencion-pago` → precio releído de la BD server-side → firma de integridad → checkout con métodos de pago cargados. El dueño desplegó la primera Edge Function del proyecto, puso el secret `WOMPI_INTEGRITY_SANDBOX`, pegó la llave pública sandbox y corrió los grants. **SIGUIENTE: TRAMO F2 (webhook + idempotencia + estados)** — es ahí donde un pago APPROVED por fin crea el pedido, baja el stock y habilita el asiento. Antes de tocar Edge Functions, LEER las "LECCIONES DE F1" al final de este archivo (los grants a `service_role`, la vista que pierde grants al recrearse, y por qué la config se lee por RPC security definer)._

---

## 🎯 REGLAS QUE GOBIERNAN TODA ESTA DILIGENCIA (no negociables)

1. **El precio NUNCA sale del navegador.** En Wompi, el monto y la firma de
   integridad se calculan server-side (Edge Function) leyendo el precio de la BD.
2. **La verdad del pago llega SOLO por webhook server-side de Wompi**, nunca desde
   la URL de retorno del cliente. Solo `APPROVED` crea pedido + asiento.
3. **El stock baja solo AL PAGAR** (venta web) o al registrar (venta manual).
4. **Idempotencia estricta** en el webhook: un mismo pago jamás crea dos pedidos.
5. **Asiento automático solo para venta web con pago confirmado.** Venta manual =
   asiento manual (el dueño decide). MAGANDHI **no es responsable de IVA** → el
   asiento NO toca la cuenta 2408.
6. **Nada se hardcodea que impida clonar a otra organización Impulse:** cuentas
   contables y llaves Wompi viven en tablas de configuración (una fila).
7. **Si el asiento falla, el pedido NO falla.** La venta es sagrada; el registro
   contable se reintenta. Nunca al revés.
8. **Sandbox primero, real después, con un solo interruptor** (fila de config), no
   dos construcciones.
9. **Montos SIEMPRE bigint (pesos enteros).** Cero float en dinero.
10. Seguridad = línea roja: RLS + RPC security-definer + vista pública lista
    blanca + cero service_role en repos.

---

## 🗺️ ORDEN LÓGICO (por qué este orden y no otro)

```
FASE A — LIMPIEZA Y HERIDAS ABIERTAS (barato, reversible, sin dependencias)
  Deja la tienda presentable y el back-office correcto ANTES de que entre plata.
        │
        ▼
FASE B — CIMIENTOS TRANSVERSALES (todo lo de Wompi se apoya aquí)
  parsearMonto correcto + SRI/versión fija + tablas de config. Si esto está mal,
  Wompi hereda el error. Por eso va ANTES de tocar dinero.
        │
        ▼
FASE C — CAMPAÑAS COMPLETO (la tienda debe poder crear productos de verdad)
  slug + es_placeholder + banner + -sm. Sin esto, el catálogo real no funciona,
  y Wompi vende productos de un catálogo a medias.
        │
        ▼
FASE D — VENTAS/BACK-OFFICE ENDURECIDO (lo que Wompi va a tocar debe ser sólido)
  bitácora de pedidos, roles reales, bugs de registrar, ranking vs anulaciones.
  Wompi va a escribir en Ventas → Ventas debe estar firme primero.
        │
        ▼
FASE E — IMPULSE MIDE BIEN (integridad del dato antes de conectarle más fuentes)
  serie temporal con ceros + paginación. La identidad Impulse depende de esto.
        │
        ▼
FASE F — WOMPI: EL CIERRE DEL CÍRCULO (la ficha grande, ya con todo firme debajo)
  Edge Functions + webhook + asiento automático + config. Se construye al final
  PORQUE se apoya en A–E. Sandbox primero, real con un interruptor.
        │
        ▼
FASE G — SELLADO (documentación + verificación end-to-end)
```

**Principio:** cada FASE es uno o más TRAMOS. Cada TRAMO = una rama + un PR. Se
sube, el dueño mergea, se sigue. Así nunca hay un PR gigante imposible de revisar.

---

# ═══════════ FASE A · LIMPIEZA Y HERIDAS ABIERTAS ═══════════
_Barato, reversible, sin dependencias. Deja todo presentable antes de la plata._

## TRAMO A1 — Tienda: quitar andamios y arreglar heridas visibles ✅
**Repo:** `magandhi` · **Rama:** `fix/tienda-limpieza-heridas` · **PR #36** (https://github.com/12344-ux/magandhi/pull/36)
**Estado:** subido, ⏳ ESPERANDO QUE EL DUEÑO MERGEE.

- [x] **A1.1 — Móvil sin precio ni agotado.** En `magandhi/index.html` (~línea
  286-289) el breakpoint ≤760px mete `.hg-agotado`, `.hg-urgencia` y `.hg-fila`
  (el precio) en `display:none`. **Mostrar precio y chip Agotado en móvil.** El
  hook y el aviso de urgencia sí pueden quedar ocultos (decisión de escaparate),
  pero **precio y disponibilidad son innegociables** — es el tráfico real.
- [x] **A1.2 — La página vieja del Grisi miente si Supabase falla.**
  `magandhi/producto/grisi-manzanilla-gold/index.html:792` — el `catch` solo hace
  `console.error` y deja `$ 24.900` hardcodeado + botón "Comprar" habilitado.
  **Decisión (dueño aprobó arreglarlo):** convertir esa página en un **redirect**
  a la genérica (`../?slug=...` o `?id=...`), ya que es código muerto (nada la
  enlaza) y 90% duplicada. Un `<meta refresh>` + `<link canonical>` bastan; se
  eliminan las 819 líneas. Así la URL vieja no da 404 y nunca muestra precio
  obsoleto.
- [x] **A1.3 — "Impulse" y jerga interna en el fuente PÚBLICO (línea roja).**
  Quitar los comentarios que dicen "back-office Impulse" en
  `magandhi/producto/index.html:305` (y en la legacy si no se borró en A1.2).
  Barrer también las ~41 menciones a "Campanas", "back-office", "el dueno" en los
  comentarios públicos, y el comentario obsoleto de `magandhi/index.html:52` que
  aún anuncia "productos de EJEMPLO/inventados". **Ningún término interno en HTML
  servido al cliente.**
- [x] **A1.4 — `diseno-referencia/` está publicado e indexable con precios
  inventados.** Sacarlo del docroot público. Como es "memoria de diseño", vive
  en el historial de git (que nunca olvida) o en una carpeta ignorada por Pages.
  Mínimo inmediato si se quiere conservar: `noindex` + no enlazarlo, pero lo
  correcto es retirarlo del sitio publicado.
- [x] **A1.5 — Asset muerto:** `productos/D_NQ_NP_2X_...webp` (nombre de
  MercadoLibre) no lo referencia nadie. Evaluar borrarlo en el mismo barrido.

> **NO se tocan en A1** (decisión del dueño): las **reseñas de ejemplo** se
> cambian DESPUÉS, con calma — el dueño tiene algo pensado para las reseñas. Por
> eso el `noindex` de las páginas de producto **se mantiene por ahora**.

**Verificación A1:** abrir el home en móvil (DevTools ≤760px) y ver precio +
Agotado; `grep -ri "impulse\|back-office\|el dueno" magandhi/ --include=*.html` = 0;
la URL vieja del Grisi redirige; `diseno-referencia` no accesible como página.

---

# ═══════════ FASE B · CIMIENTOS TRANSVERSALES ═══════════
_Si esto está mal, TODO lo de Wompi hereda el error. Va antes de tocar dinero._

## TRAMO B1 — El dinero se lee bien (parsearMonto) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/parsear-monto-seguro`

- [ ] **B1.1 — `parsearMonto` se come los centavos en silencio.**
  `finanzas-core.js:56` hace `replace(/[^\d]/g,'')` → escribir `1.200,50` guarda
  **120050** sin avisar. **Riesgo #1 del proyecto, y CRÍTICO ahora que Wompi va a
  mover plata real.** Decisión: como el sistema es de **pesos enteros sin
  centavos**, el parseo debe (a) tratar el punto como separador de miles, (b)
  **rechazar o avisar** si detecta decimales/coma en vez de tragárselos en
  silencio. Que el usuario SEPA que escribió un decimal. Aplicar la misma
  corrección a las copias en los otros cores (ver TRAMO D-cores) o centralizar.
- [ ] **B1.2 — `mayor.html:121` pinta ceros falsos.** No comprueba
  `saldoRes.error`; si `saldos_cuenta` falla, muestra Totales en 0 y "Saldo final"
  del corrido del cliente. En un libro contable un cero falso es peor que un
  error. **Comprobar el error y mostrar aviso, nunca ceros inventados.**

**Verificación B1:** escribir "1.200,50" en un asiento → o lo rechaza o avisa,
nunca guarda 120050 callado. Simular fallo de `saldos_cuenta` → mensaje de error,
no ceros.

## TRAMO B2 — Blindaje de dependencias (SRI + versión fija) ⬜
**Repo:** ambos · **Rama:** `sec/sri-y-versiones-cdn`

- [ ] **B2.1 — `supabase-js@2` con major flotante** en los `supabase-config.js`
  de ambos repos. Fijar versión exacta (ej. `@2.XX.X`).
- [ ] **B2.2 — Cero SRI en 34 HTML.** Añadir `integrity=` + `crossorigin` a jsPDF
  y autotable (cdnjs) en los 3 informes de finanzas. Evaluar CSP básica.
- [ ] **B2.3** — Documentar por qué (si esm.sh sirviera otra cosa, ejecutaría
  código con la sesión del usuario en todo el back-office).

**Verificación B2:** `grep -c "integrity=" ` > 0 en los informes; versión de
supabase-js pineada en ambos repos.

## TRAMO B3 — Tablas de configuración (clonabilidad Impulse) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `feat/config-contable-y-pagos`
**⚠️ El dueño corre el SQL.**

- [ ] **B3.1 — `contabilidad_config`** (una fila, patrón `inventario_config`):
  códigos de cuenta para el asiento automático (banco, ingreso, comisión, costo,
  inventario). Verificado que las cuentas existen en el PUC: 1110 BANCOS, 4135
  COMERCIO, 5305 FINANCIEROS (comisión), 6135 COSTO, 1435 MERCANCÍAS. Se leen de
  aquí, NO se hardcodean.
- [ ] **B3.2 — `pagos_config`** (una fila): entorno actual (`sandbox`|`prod`),
  llaves públicas Wompi por entorno. **Los SECRETOS (integridad, eventos) NO van
  aquí en texto** → van como *secrets* de la Edge Function en Supabase (los pone
  el dueño en el dashboard). Esta tabla solo dice "qué entorno" y datos públicos.
  → **Este es el "interruptor" sandbox↔real:** cambiar una fila, no reconstruir.
- [ ] **B3.3** — RLS: ambas tablas solo lectura para authenticated con el guardia
  correspondiente; escritura solo admin vía RPC o a mano.

**Verificación B3:** `select * from contabilidad_config;` devuelve 1 fila con las
5 cuentas; `select entorno from pagos_config;` devuelve 'sandbox'.

---

# ═══════════ FASE C · CAMPAÑAS COMPLETO ═══════════
_La tienda debe poder crear productos REALES antes de venderlos con Wompi._

## TRAMO C1 — Campañas: cerrar los 4 tapetes rotos ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/campanas-slug-placeholder-banner`
**⚠️ C1.1 y C1.2 requieren SQL nuevo (el dueño lo corre).**

- [ ] **C1.1 — slug editable.** Añadir campo "dirección web (slug)" en
  `agregar.html` y `editar.html`, y parámetro `p_slug` a las RPC `cm_crear_campana`
  / `cm_editar_campana` (nueva migración; drop+create de la firma, como se hizo con
  `p_product_id_ref`). Autogenerar sugerencia desde el nombre (minúsculas, sin
  tildes, guiones) pero editable. Respeta el índice único parcial de slug que ya
  existe. **Sin esto, cada producto nuevo cae en la URL fea `?id=<uuid>`.**
- [ ] **C1.2 — es_placeholder en la UI (Decisión de Oro).** Mostrar/leer/escribir
  el flag `es_placeholder` en el panel para poder **retirar** un producto de
  ejemplo sin SQL manual. Recordar la regla: NO editar un ficticio para volverlo
  real → se retira y se crea uno nuevo. La UI debe empujar a ese flujo (ej. botón
  "retirar producto de ejemplo").
- [ ] **C1.3 — Banner roto en la lista.** `marketing/campanas/index.html:137`
  usa el path crudo en `background-image:url(...)`. Cambiar a `urlPublicaImagen()`
  (que ya existe en el core). Borrar el comentario obsoleto de la línea ~133 que
  dice "el back-office no aloja las fotos" (mentira desde que se añadió Storage).
- [ ] **C1.4 — Imagen `-sm` que nadie usa en el back-office.** Decidir: que el
  grid del panel consuma la liviana (coherente con la tienda) — recomendado, poco
  trabajo — o dejar de generarla. No dejarla huérfana pagando espacio.
- [ ] **C1.5 (menor) — Race del banner.** `agregar/editar.html`: la galería tiene
  guardia "optimizando" pero el banner no. Guardar mientras el banner optimiza lo
  guarda vacío. Añadir la misma guardia al banner.

**Verificación C1:** crear una campaña nueva desde el panel → tiene slug bonito y
su banner se ve en la lista; retirar un placeholder desde la UI funciona.

## TRAMO C2 — Campañas: subida de imágenes atómica (deuda) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/campanas-imagenes-atomicas`

- [ ] **C2.1** — Subida no atómica (RPC→Storage→RPC): si falla el paso 2/3 quedan
  huérfanos en Storage y se muestran a la vez éxito y error. Ordenar el flujo y los
  mensajes; documentar/mitigar huérfanas. (También aplica a Inventario `agregar`.)
- [x] **C2.2** — Edición de ficha de producto de Inventario. ABORDADA en la rama
  `feat/inventario-editar-ficha-filtros`. La pantalla de edición se resolvió como
  un **MODO EDICIÓN dentro del modal de detalle** de `produccion/inventarios/ver.html`
  (no una página `editar.html` nueva): el modal ya mostraba la ficha completa y ya
  alojaba "Registrar movimiento", así que un "modo editar" ahí es el patrón más
  coherente. Consume `inv_editar_producto` (15 args) sin tocar `sku` ni existencias.
  **Decisión de precio:** en Inventario NO se muestra ni edita `precio_venta`; se
  edita el COSTO (`costo_unitario`). Al guardar se reenvía el `precio_venta` actual
  sin modificar (borrar la columna del modelo es ficha futura, ver abajo). En el
  mismo tramo: se cortó la herencia de precio Inventario→Campañas en
  `marketing/campanas/agregar.html` y `editar.html` (ya no autocompleta el precio;
  conserva la sugerencia de nombre) y se añadieron filtros por existencias en la
  vitrina (Todos / Agotados / Con más unidades / Con menos unidades). Sin SQL nuevo.

### Fichas futuras derivadas de C2.2 (NO construidas)
- [ ] **F-C2.2a — TOPE DE ESCAPARATE en Campañas.** Una llave que limite cuántas
  unidades del stock real se ofrecen en la web sin exceder el stock de Inventario
  (para no vender más de lo que hay). Requiere **SQL propio** (columna/tabla del
  tope por campaña o producto) + lógica de "no exceder el stock" al publicar/vender.
  Toca Campañas y la vista pública.
- [ ] **F-C2.2b — BORRAR `precio_venta` del modelo de `productos`.** Limpieza del
  modelo: hoy `precio_venta` sigue en `productos` aunque Inventario ya no lo maneje
  y Campañas escriba su propio precio. Antes de borrarla hay que resolver el
  **Ranking de Marketing**, que hoy usa `precio_venta` como ingreso estimado
  (fallback). Toca **RPC** (`inv_editar_producto`/`inv_crear_producto`), la **vista**
  de ranking y **Marketing**. Ficha delicada: coordinar con D4 (ranking vs anulaciones).

---

# ═══════════ FASE D · VENTAS / BACK-OFFICE ENDURECIDO ═══════════
_Lo que Wompi va a tocar (Ventas) debe estar sólido ANTES de conectarlo._

## TRAMO D1 — Ventas: bugs del registro manual ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/ventas-registro-bugs`

- [ ] **D1.1 — `<input required>` del nombre rompe cliente recurrente.**
  `registrar.html:108` vs lógica de línea 400: si identificas por correo y marcas
  candidato sin escribir nombre, el navegador bloquea el submit. Quitar el
  `required` nativo y validar en JS coherente con la lógica de cliente elegido.
- [ ] **D1.2 — Precio arrastrado.** Si escribes precio y luego cambias el
  producto, se conserva el precio anterior → venta al precio equivocado sin aviso.
  Al cambiar producto, resetear/re-sugerir el precio.
- [ ] **D1.3 — Precio 0 pasa de punta a punta.** `reunirItems` no lo filtra, el
  mensaje miente ("con cantidad y precio"), la RPC solo rechaza `<0`. Decidir si 0
  es válido (producto gratis) o se rechaza; hacer coherentes UI + RPC.
- [ ] **D1.4 (relacionado B1)** — En `agregar.html` de inventario, `parsearMonto(...)
  || null` convierte un costo/precio legítimo de 0 en NULL. Revisar junto con B1.

## TRAMO D2 — Ventas: bitácora de pedidos (trazabilidad real) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `feat/ventas-bitacora-pedidos`
**⚠️ SQL nuevo (el dueño lo corre).**

- [ ] **D2.1 — No hay bitácora de pedidos.** `avanzar_estado_pedido` pisa el
  estado y el timeline del drawer se INVENTA el progreso. Crear `pedido_bitacora`
  (espejo de `asiento_bitacora`): registrar cada cambio de estado con fecha y
  usuario. El timeline debe LEER la bitácora, no inventar. **Esto es requisito
  para Wompi:** el webhook va a mover estados y hay que poder auditarlo.
- [ ] **D2.2** — Guardar la dirección de entrega EN EL PEDIDO (hoy usa la del
  cliente al momento, y cambiarla reescribe el histórico de envíos).

## TRAMO D3 — Roles reales (granularidad de acceso) ⏸️
**Repo:** `12344-ux.github.io` · **Rama:** `sec/roles-granularidad`
**⚠️ SQL (RLS/funciones) — el dueño lo corre.**

> ⏸️ **POSPUESTO POR DECISIÓN DEL DUEÑO.** Motivo: hoy el único usuario es admin
> (ve todo por diseño, vía `tiene_modulo`), así que los sub-bugs D3.1–D3.4 no
> tienen víctima todavía. **CONDICIÓN DE REACTIVACIÓN (requisito bloqueante):**
> retomar D3 **ANTES** de crear el primer usuario con rol reducido (p.ej. el
> hermano "solo pedidos" o un analista "solo ver números"), idealmente junto con
> el panel de gestión de accesos (otorgar/quitar categorías). El riesgo (leer PII
> de clientes / publicar sin permiso) está latente mientras solo exista admin; se
> activa en cuanto exista otro usuario. Los sub-puntos D3.1–D3.4 siguen siendo el
> trabajo pendiente cuando se reactive.

- [ ] **D3.1 — `tiene_acceso_marketing()` deja a un analista PUBLICAR productos.**
  Acepta 'marketing' o 'marketing-project' indistintamente. Separar: ver números
  (marketing-project) ≠ crear/publicar campañas (marketing). Aplicar en UI **y**
  en las RPC/RLS (el candado real es server-side).
- [ ] **D3.2 — `tiene_acceso_ventas()` es un OR de 4 claves.** Quien tiene solo
  'pedidos' lee toda la tabla `clientes`; quien tiene solo 'clientes' puede crear
  pedidos y mover inventario. Separar responsabilidades reales.
- [ ] **D3.3 — `productos_select_marketing` no restringe columnas** → un usuario
  de Marketing saca `costo_unitario` y `proveedor` desde la consola. Restringir a
  columnas públicas para ese rol (vista o política por columnas).
- [ ] **D3.4 — `buscar_candidatos_cliente`** filtra PII (correo/teléfono) de
  terceros por similitud de nombre. Revisar qué devuelve; acotar.

> Nota: hoy el único usuario es el dueño (admin), así que esto no es urgente para
> operar, PERO es requisito antes de que el hermano entre "solo a pedidos".

## TRAMO D4 — Ranking vs anulaciones (dato correcto) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/ranking-anulaciones`

- [ ] **D4.1** — Un pedido anulado devuelve stock con una 'entrada', pero el
  ranking solo suma 'salida' → las unidades del anulado siguen contadas y su
  ingreso cae al fallback de precio de lista → **anular infla el ingreso
  estimado.** Corregir para que la anulación descuente unidades e ingreso.

## TRAMO D5 — Truncamiento silencioso (8 pantallas) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/paginacion-o-aviso-limites`

- [ ] **D5.1** — Libro Diario `.limit(200)` mientras promete "todos"; inventario
  `.limit(300)`+filtro cliente; pedidos 500; clientes 2000 (×2 consultas).
  Ninguna pagina ni avisa. **Mínimo:** avisar cuando se truncó ("mostrando los
  últimos N"). **Ideal:** paginación real. Empezar por el Libro Diario (es un
  libro contable, no puede ocultar registros en silencio).

---

# ═══════════ FASE E · IMPULSE MIDE BIEN ═══════════
_Integridad del dato antes de conectarle más fuentes (Wompi alimentará ventas)._

## TRAMO E1 — Serie temporal con periodos en cero ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `fix/impulse-serie-temporal`

- [ ] **E1.1 — Sesgo sistemático al alza.** `agruparPorPeriodo`
  (`marketing-core.js:639`) solo emite periodos CON movimiento → cada día sin
  ventas desaparece del promedio, el eje X es "posición en arreglo" no tiempo, y
  la etiqueta dice "días". Para productos intermitentes (todos en fase 1) el
  promedio se infla y la regresión se distorsiona. **Rellenar periodos en cero**
  a lo largo del rango real de fechas, para que promedio móvil, suavización y
  regresión midan contra el calendario verdadero. Reusar auto-chequeo del core.
- [ ] **E1.2 — Sin paginación en las 4 lecturas** de Marketing Project → pasadas
  ~1000 filas PostgREST trunca en silencio y toda la matemática queda mal.
  Paginar/agregar server-side o traer con `.range()` en bloques.

> **Por qué importa (identidad Impulse):** "la máquina mide con precisión, el
> humano interpreta". Si mide con sesgo y rotula con unidades de calendario que no
> corresponden, el humano interpreta un dato falso. Se cumple la letra y se
> traiciona el espíritu. Innegociable antes de sumar la fuente Wompi.

---

# ═══════════ FASE F · WOMPI — EL CIERRE DEL CÍRCULO ═══════════
_La ficha grande. Se apoya en A–E. Sandbox primero, real con un interruptor._
_TODAS las fichas técnicas 1-9 que el dueño aprobó viven aquí._

## TRAMO F1 — Datos del comprador + intención de pago ⬜
**Repo:** ambos · **Rama:** `feat/wompi-intencion-pago`
**⚠️ Edge Function (el dueño despliega) + SQL.**

- [ ] **F1.1 — Formulario de datos del comprador** en la tienda (nombre, correo,
  teléfono, dirección, ciudad) — hoy no existe ni un formulario de compra.
- [ ] **F1.2 — Edge Function `crear-intencion-pago`:** lee el precio de la BD
  (NUNCA del navegador), calcula la firma de integridad Wompi con el secreto
  server-side, devuelve el link/datos de pago. (Ficha técnica 1.)
- [ ] **F1.3 — Botones de compra reales.** Hoy `#mg-comprar` y "Preguntar por
  WhatsApp" son botones muertos (0 listeners). Cablear "Comprar" → intención de
  pago; cablear WhatsApp → `wa.me/573132451188` con mensaje prellenado del
  producto.

## TRAMO F2 — Webhook + idempotencia + estados ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `feat/wompi-webhook`
**⚠️ Edge Function (el dueño despliega) + SQL.**

- [ ] **F2.1 — Tabla `pagos_wompi`** (idempotencia): guarda cada referencia de
  transacción y su estado. (Ficha técnica 3.)
- [ ] **F2.2 — Edge Function `wompi-webhook`:** valida la firma de evento de
  Wompi (server-to-server), es idempotente, y SOLO con `APPROVED` invoca
  `crear_pedido(canal='web')`. Registra también DECLINED/VOIDED/ERROR/PENDING para
  que el dueño vea intentos fallidos. (Fichas 2 y 9.)
- [ ] **F2.3 — Página `gracias`** en la tienda (cosmética; la verdad la da el
  webhook, no esta página).

## TRAMO F3 — Asiento contable automático ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `feat/wompi-asiento-automatico`
**⚠️ SQL (el dueño lo corre).**

- [ ] **F3.1 — Función `generar_asiento_venta_web(pedido, pago)`:** crea el
  asiento leyendo cuentas de `contabilidad_config`. Estructura (Ficha 5, SIN IVA):
  - Debe `1110 BANCOS` = lo que REALMENTE llegó (precio − comisión Wompi).
  - Debe `5305 FINANCIEROS` = comisión Wompi (leída del evento, no adivinada).
  - Haber `4135 COMERCIO` = venta completa.
  - **+ Costo de ventas (Ficha 5b, aprobado):** Debe `6135` / Haber `1435` por el
    costo de la mercancía (de `productos.costo_unitario`).
- [ ] **F3.2 — Marcar el asiento como AUTOMÁTICO** y visible en el Diario; anulable
  con trazabilidad (nunca borrado). (Ficha 7 — evolución consciente de la "cita a
  ciegas".)
- [ ] **F3.3 — Si el asiento falla, el pedido NO falla** (se reintenta el asiento).
  (Regla 7.)

## TRAMO F4 — Sandbox → producción (el interruptor) ⬜
**Repo:** `12344-ux.github.io` · **Rama:** `feat/wompi-go-live`

- [ ] **F4.1** — Probar TODO el circuito en sandbox (pagos falsos), incluidos
  asientos de prueba que luego se limpian.
- [ ] **F4.2** — Verificación end-to-end con evidencia: pago sandbox APPROVED →
  pedido creado → stock bajó → cliente vinculado → asiento correcto al peso →
  aparece en Diario. Pago DECLINED → NO crea nada, se registra el intento.
- [ ] **F4.3** — Cambiar `pagos_config.entorno` a 'prod' + secretos de producción
  (el dueño). Una prueba real pequeña. **Recién aquí la tienda cobra de verdad.**

## FICHA FUTURA (anotada, NO se construye ahora)
- **Reservas de stock que caducan** (estilo Mercado Libre/Amazon). Decisión del
  dueño: NO construir aún — es gold-plating para el volumen de fase 1. La regla
  "baja solo al pagar" cubre hoy. Retomar cuando haya ventas simultáneas reales
  que lo justifiquen.
- **Reseñas reales** — el dueño tiene algo pensado; se define después con calma.
  Mientras: se mantienen `noindex` y NO se inventan.
- **Páginas legales** (privacidad, retracto Ley 1480, envíos, devoluciones) — el
  dueño ya está elaborando los documentos. Cuando los tenga, se maquetan y se
  enlazan (hoy los 4 links del footer van a `#`). Requisito para cobrar formal.

---

# ═══════════ FASE G · SELLADO ═══════════

## TRAMO G1 — Documentación y cierre ⬜
- [ ] Volcar todo lo hecho a `CONTEXTO-MAGANDHI.md` (estado real, no el papel
  viejo). Corregir las incoherencias detectadas (ranking "estimado"→real, slug,
  es_placeholder, Agotado en móvil, etc.).
- [ ] Actualizar `docs/MAPA-CONEXIONES-TANDA2.md` con el circuito Wompi.
- [ ] Guardar aprendizajes en la memoria (learnings) del proyecto.
- [ ] Archivar este `ANDAMIOS.md` (o dejarlo como bitácora histórica).

---

## 📌 TABLERO DE ESTADO (actualizar aquí al cerrar cada tramo)

| Tramo | Descripción | Estado | PR | Notas |
|---|---|---|---|---|
| A1 | Tienda: limpieza + heridas | ✅ | [#36](https://github.com/12344-ux/magandhi/pull/36) | mergeado (repo magandhi) |
| B1 | parsearMonto + mayor ceros | ✅ | [#194](https://github.com/12344-ux/12344-ux.github.io/pull/194) | crítico pre-Wompi · mergeado |
| B2 | SRI + versión CDN | ✅ | [#195](https://github.com/12344-ux/12344-ux.github.io/pull/195) · [#37](https://github.com/12344-ux/magandhi/pull/37) | supabase-js pineado @2.116.0 en ambos repos |
| B3 | Tablas de config (contable+pagos) | ✅ | [#196](https://github.com/12344-ux/12344-ux.github.io/pull/196) | SQL corrido por el dueño (5 cuentas · entorno=sandbox) |
| C1 | Campañas: slug/placeholder/banner + -sm | ✅ | [#197](https://github.com/12344-ux/12344-ux.github.io/pull/197) | SQL corrido por el dueño |
| C2.1 | Campañas: imágenes atómicas | ✅ | [#198](https://github.com/12344-ux/12344-ux.github.io/pull/198) | solo frontend |
| C2.2 | Inventario: editar ficha en modal + filtros + cortar herencia de precio | ✅ | [#199](https://github.com/12344-ux/12344-ux.github.io/pull/199) | sin SQL |
| F-C2.2a | Tope de escaparate (opción A: solo booleano agotado) | ✅ | [#200](https://github.com/12344-ux/12344-ux.github.io/pull/200) | derivada de C2.2 · SQL corrido (migración 20250602000000) |
| D1 | Ventas: bugs registro | ✅ | [#201](https://github.com/12344-ux/12344-ux.github.io/pull/201) | solo frontend |
| D2 | Ventas: bitácora pedidos | ✅ | [#202](https://github.com/12344-ux/12344-ux.github.io/pull/202) | SQL corrido (migración 20250603000000) · req. Wompi |
| D3 | Roles granularidad | ⏸️ | [#203](https://github.com/12344-ux/12344-ux.github.io/pull/203) | pospuesto: reactivar antes del 1er usuario con rol reducido / panel de accesos |
| D4 | Ranking vs anulaciones | ✅ | [#204](https://github.com/12344-ux/12344-ux.github.io/pull/204) | solo frontend |
| D5 | Truncamiento/paginación | ✅ | [#205](https://github.com/12344-ux/12344-ux.github.io/pull/205) | Diario paginado + avisos en 5 pantallas |
| E1 | Impulse: serie temporal + paginación | ✅ | [#206](https://github.com/12344-ux/12344-ux.github.io/pull/206) | identidad Impulse · solo frontend |
| F1 | Wompi: intención de pago | ✅ | back-office [#208](https://github.com/12344-ux/12344-ux.github.io/pull/208) [#209](https://github.com/12344-ux/12344-ux.github.io/pull/209) [#210](https://github.com/12344-ux/12344-ux.github.io/pull/210) [#211](https://github.com/12344-ux/12344-ux.github.io/pull/211) [#212](https://github.com/12344-ux/12344-ux.github.io/pull/212) · tienda [#38](https://github.com/12344-ux/magandhi/pull/38) [#39](https://github.com/12344-ux/magandhi/pull/39) | **VERIFICADO con evidencia:** checkout REAL de Wompi alcanzado en sandbox (métodos de pago cargados). Edge Fn desplegada + secret + llave pública + grants |
| F2 | Wompi: webhook + idempotencia | ⬜ | — | Edge Fn + SQL |
| F3 | Wompi: asiento automático | ⬜ | — | SQL dueño |
| F4 | Wompi: sandbox→prod | ⬜ | — | interruptor |
| G1 | Sellado + docs | ⬜ | — | — |

**Leyenda:** ⬜ pendiente · 🔨 en curso · ✅ mergeado · ⏸️ bloqueado (esperando dueño) o pospuesto por decisión

---

## 🧭 PARA EL PRÓXIMO KIRO (si esta sesión no termina)

1. **Lee este archivo entero primero**, luego `CONTEXTO-MAGANDHI.md`.
2. Mira el **TABLERO DE ESTADO**: el primer tramo ⬜ (o 🔨) es donde retomas.
   **Hoy ese punto de retorno es F2 (Wompi: webhook + idempotencia)** — las Fases
   A–E están ✅ (con D3 ⏸️ pospuesto) y **F1 quedó ✅ y VERIFICADO**: la tienda ya
   llega al checkout real de Wompi en sandbox. Lo que F1 NO hace (a propósito) es
   crear el pedido: eso es exactamente F2.

   ### ⚠️ LECCIONES DE F1 (leerlas antes de tocar Edge Functions · costaron horas)
   - **`service_role` tiene BYPASSRLS pero NO se salta los GRANTS.** Son dos capas
     distintas. Una Edge Function puede tener la RLS a favor y aun así recibir
     `permission denied` por faltarle el `grant select`. En este proyecto
     "auto-expose new tables" está en **OFF**, así que **todo grant se da a mano y
     a propósito** (ya versionados en `20250605000000`).
   - **Trampa de `catalogo_publico`:** es una VISTA que varias migraciones recrean
     con `drop view` + `create view`, y el DROP **borra sus grants**. Toda
     migración futura que la recree debe re-otorgar también a `service_role`, o la
     intención de pago se rompe con `42501`.
   - **PostgREST degrada el rol:** aunque el cliente use la SERVICE_ROLE_KEY, la
     petición del navegador lleva `apikey=anon` y PostgREST resuelve el rol
     efectivo como anon. Por eso la config de pagos se lee por **RPC security
     definer** (`pagos_config_para_intencion`), no por lectura directa de tabla.
   - **Depurar a ciegas cuesta carísimo:** el 500 llegaba con un mensaje genérico
     y el motivo real (`permission denied for view catalogo_publico`) solo
     apareció al **loguear el error** (ver F1.9 de INSTRUCCIONES.md). Si algo falla
     en una Edge Function, **lo primero es hacer que escupa el error real**.
   - **Sandbox y producción de Wompi son perfiles de comercio SEPARADOS.** El
     checkout de sandbox puede mostrar datos viejos del comercio aunque el
     dashboard ya muestre los nuevos. Confirmar el nombre/datos reales en F4.
3. **Respeta el orden de fases** (A→B→C→D→E→F→G): las de arriba son cimiento de
   las de abajo. No saltes a Wompi (F) si B (parsearMonto, config) no está ✅.
4. **Un tramo = una rama = un PR.** Nunca push a main. El dueño mergea.
5. **El SQL/Edge/Storage lo corre/despliega el DUEÑO** a mano; tú escribes el
   código y le das instrucciones exactas en `supabase/INSTRUCCIONES.md`.
6. **Verifica con EVIDENCIA** (un select, una captura), no con "ya quedó".
7. El dueño está disponible en la sesión para desplegar, correr SQL y responder.
