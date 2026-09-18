# CONTEXTO — Back-office interno de MAGANDHI (ecosistema Impulse)

> Leer este archivo ANTES de tocar nada. Es el mapa del proyecto para retomar
> en cualquier sesión sin perder el hilo.

## Qué es esto

Este repo (`12344-ux/12344-ux.github.io`, sitio **estático en GitHub Pages**,
dominio **montaguth.institute**) es el **BACK-OFFICE INTERNO** de MAGANDHI: la
trastienda de gestión, protegida con login. **NO** es la tienda pública.

- **magandhi.com** (otro repo) = tienda PÚBLICA, cara al cliente. Marca comercial
  terracota. NUNCA lleva el sello Impulse ni menciona la tecnología.
- **montaguth.institute** (este repo) = gestión interna / "control interno".

### Ecosistema Impulse
El dueño (D0m0) tiene una segunda compañía, **Impulse** (la marca es solo
"Impulse"; "Consulting" es el servicio), dedicada a **gestionar organizaciones**.
**MAGANDHI es el caso piloto**: si estos softwares internos funcionan bien, el
modelo se **replica** a otras organizaciones clientes de Impulse. Por eso todo
debe quedar **impecable y "clonable"** (no amarrado solo a MAGANDHI). Regla:
"si lleva el sello Impulse, tiene que estar impecable". El sello
"Con tecnología Impulse" va en el pie de las zonas internas (login/panel/finanzas),
nunca en la tienda pública.

> **Regla de identidad (regla de oro):** Impulse analiza y gestiona los **DATOS
> PROPIOS** de la organización; **NO** hace análisis que dependan de datos
> externos (mercado, competencia, tendencias) que la plataforma no posee. Todo
> análisis se funda en lo que la organización sabe de sí misma (ventas, precios,
> inventario, clientes), nunca en datos inventados o traídos de fuera. Por eso se
> descartaron "Oportunidades de mercado" y "Cosas que podria estar ignorando" de
> Marketing Project; se conservan Proyección de demanda, Análisis clúster y
> Elasticidad porque se nutren de datos propios.

## Infraestructura (todo en producción, mergeado a main)

### Supabase
- Proyecto limpio y nuevo (se borró todo lo del proyecto muerto anterior "Stramont").
- URL: `https://bxlzipwxyxdtffnuizbz.supabase.co`
- Publishable key (PÚBLICA, va en el cliente): `sb_publishable_ap4jdsO_0KPOPWhUk9Y7ZA_0jDUvHu1`
- Creado con Auto-RLS ON y "auto-expose new tables" OFF (seguro).
- Admin: `michaelmagandhi@outlook.com` (UID `89e5028d-8c17-4deb-89c3-59acbd0ee2f2`).
- **Kiro NO tiene acceso al dashboard de Supabase.** Todo el SQL vive en
  `supabase/migrations/` y **el dueño lo ejecuta a mano** en el SQL Editor,
  guiado por `supabase/INSTRUCCIONES.md`. Escribir SQL en el repo NO lo despliega.

### Login y roles
- `index.html` = login (Supabase Auth, email+contraseña, "Solo personal interno").
- `panel.html` = panel interno (cascarón + tarjetas de acceso a módulos).
- `auth-guard.js` = guardia reutilizable (toda página interna lo importa).
- `supabase-config.js` = cliente Supabase único (reutilizar, no duplicar).
- Tabla `perfiles` (id → rol → modulos[]) con RLS + helper `tiene_modulo()`.
  admin = todo; a futuro un trabajador con `modulos={finanzas}` entra solo a finanzas.

### Identidad visual
- Paleta base MAGANDHI en `marca.css` (terracota #A6332E, crema, negro, Poppins).
- Favicons por área en `marca-areas/` (transparentes): `control-interno.png` (azul,
  login/panel), `finanzas.png` (verde, finanzas/*). Cada área futura = su color.
- Área de finanzas: header azul marino #101C33, terracota=DEBE, azul marino=HABER,
  números tabular-nums, COP con puntos de miles.

## SOFTWARE 1 — Módulo Finanzas / Contabilidad PUC  ✅ TERMINADO v1

Contabilidad de partida doble, PUC colombiano (Decreto 2650). Todo en `finanzas/`.

- **Nuevo asiento** (`nuevo-asiento.html`): cuadre EN VIVO, no guarda si Debe≠Haber
  (reforzado server-side).
- **Libro Diario** (`diario.html`) + **editar/anular** (`editar-asiento.html`) con
  **trazabilidad** (bitácora; nada se borra en silencio; "punto medio" — NO es para
  la DIAN, es control interno).
- **Libro Mayor** (`mayor.html`): saldos por cuenta, derivados automáticamente.
- **Catálogo PUC** (`puc.html`): buscable, prioriza por uso. Carga PARCIAL a propósito
  (cuentas de comercio) con plantilla para ampliar en la migración de carga.
- **Agregar cuentas** (`agregar-cuenta.html`): SOLO admin, valida jerarquía/padre
  (no crea cuentas huérfanas). Aparecen al instante en el buscador del asiento.
- **Informes (Tramo 2):** `balance-comprobacion.html` (a corte), `estado-resultados.html`
  (por periodo), `balance-general.html` (a corte). Los tres exportan a **PDF**
  (jsPDF 2.5.1 + autotable 3.8.2 por CDN, con logo/marca) y **Excel/CSV** (BOM UTF-8 + ';').

### Reglas duras del módulo (no negociables)
- Montos SIEMPRE **bigint** (pesos enteros, nunca float).
- Toda tabla financiera con **RLS** vía `tiene_modulo('finanzas')`.
- Funciones de informe **STABLE + SECURITY INVOKER** (heredan RLS). Escritura solo
  vía RPC **security-definer**. Cero secret/service_role en el repo.
- El Balance General calcula el resultado del ejercicio **llamando a
  `estado_resultados`** (año fiscal = año calendario, 1-ene → corte) para que
  coincida al peso y alimente el patrimonio: **Activo = Pasivo + Patrimonio + Resultado**.

### Pendientes del contable (apuntados, NO para ya)
- **Pulido de exportación (Paso 3):** solo cuando el dueño dé feedback tras usarlo
  con operaciones REALES.
- **Cierre anual contable:** necesario al pasar de un año fiscal a otro (p.ej. enero
  2027). Hoy no hace falta (MAGANDHI arranca este año; documentado en el Balance
  General por qué cuadra). NO gold-plating (presupuestos, flujo de caja, multimoneda).

## Arquitectura del panel: ÁREAS jerárquicas (desde esta jornada)

El panel dejó de tener "módulos planos" y pasó a **3 grandes ÁREAS**, cada una un
contenedor de sub-áreas (que a su vez tienen secciones). Cada área es una carpeta:

```
PANEL ADMIN (panel.html)
├── FINANZAS    (finanzas/)      → Contabilidad PUC (v1 terminado)
├── MARKETING   (marketing/)     → Marketing Project (marketing/marketing-project/)
└── PRODUCCIÓN  (produccion/)    → Inventarios (produccion/inventarios/)
```

- **Marketing** y **Producción** son carpetas de área (como Finanzas): clic en el
  área → sus sub-áreas → clic en la sub-área → sus secciones. Preparado para crecer.
- **Roles jerárquicos:** `modulos[]` en `perfiles` admite dar acceso por ÁREA
  (`produccion`, `marketing`) o por sub-área. Admin ve todo. Candado real = RLS.
  Helpers SQL nuevos: `tiene_acceso_inventario()` y `tiene_acceso_marketing()`
  (envuelven `tiene_modulo` y aceptan las claves equivalentes de área/sub-área).

## SOFTWARE 2 — Módulo Inventario (área PRODUCCIÓN)  ✅ v1 EN PRODUCCIÓN

Segundo software del ecosistema. En `produccion/inventarios/`. Es la COLUMNA
VERTEBRAL de datos: el `product_id` conecta todo el ecosistema.

- **Modelo (mismo espíritu que Finanzas: el libro se escribe, el stock se deriva):**
  - `productos`: `id` UUID (= product_id, autogenerado) + `sku` legible autogenerado
    server-side, formato `MAG-<CAT>-0001`, **inmutable** tras el alta (prefijo desde
    `inventario_config` para ser clonable a otras organizaciones). Campos de comercio
    (nombre, descripcion, marca, categoria, unidad_medida, contenido, costo_unitario
    bigint, precio_venta bigint, stock_minimo, proveedor, ubicacion, imagen_path,
    activo, publicado, timestamps).
  - `movimientos_inventario`: **EL LIBRO append-only**. tipos entrada/salida/
    ajuste_entrada/ajuste_salida; `cantidad` integer > 0 (el signo lo da el tipo);
    `customer_id` uuid **SIN FK todavía = "enchufe apagado"** (se conectará con el
    futuro software de Clientes, sin tocar Inventario); `costo_unitario_mov` bigint.
    Guarda historia **completa, sin límite de tiempo, para siempre**.
  - `stock_actual`: VISTA derivada (SECURITY INVOKER). Existencias = suma del libro
    según tipo. Nunca un dato guardado; imposible desincronizar.
- **Pantallas:** Ver inventario (vitrina con foto + stock + timeline por producto +
  registrar movimiento), Agregar a inventario (alta con **cantidad inicial** +
  **imagen auto-optimizada en el navegador** ~≤1200px JPEG 0.8 antes de subir),
  Movimientos (bitácora GLOBAL del libro, filtrable por producto/tipo/periodo).
- **Seguridad:** RLS vía `tiene_acceso_inventario()`, escritura solo por RPC
  security-definer (`inv_crear_producto`, `inv_registrar_movimiento`,
  `inv_editar_producto`), GRANT SELECT a authenticated. Venta sin stock: se permite y
  se **alerta** (existencias negativas visibles), no se bloquea (piloto = venta manual).
- **Imágenes:** Supabase Storage bucket `productos` (público lectura / escritura
  restringida por policy con `tiene_acceso_inventario()`). En BD se guarda
  `imagen_path`, no URL. Subida con sesión del usuario, nunca service_role.
- **Migraciones:** `supabase/migrations/20250301000000..000600` (7). El dueño las
  aplica a mano; el bucket lo crea a mano. Todo documentado en INSTRUCCIONES.md.

## SOFTWARE 3 — Marketing Project (área MARKETING)  ✅ 3 categorías EN PRODUCCIÓN

En `marketing/marketing-project/`. Laboratorio de análisis SOBRE DEMANDA que lee el
libro de Inventario (salidas = ventas reales). Categorías:

- **Proyección de la demanda** (activa): 3 métodos — promedio móvil, suavización
  exponencial (recurrencia S_t = α·x_t + (1−α)·S_{t−1}, reconstruida desde ventas
  reales, NO guarda pronósticos pasados), regresión lineal por mínimos cuadrados.
  Controles: producto, método, granularidad (día/semana/mes), rango **desde/hasta**
  (reemplazó al ambiguo "últimos N periodos"), horizonte. Resultado en 3 capas
  (número grande, gráfico SVG sólido=real/punteado=proyección, tabla).
- **Medidas de Tendencia Central** (activa): media, mediana, moda de las ventas por
  periodo. Casos límite honestos (sin moda / multimodal / serie vacía / 1 periodo).
- **Ranking de productos por periodo** (activa): comparativo de TODOS los productos en
  un rango; dos métricas (unidades e **ingreso ESTIMADO** con precio_venta actual),
  orden elegible + toggle más↔menos vendido. **Conexión futura marcada en el código**:
  cuando exista Ventas, el ingreso usará el precio real de cada venta.
- **Análisis clúster** y **Elasticidad**: PRÓXIMAMENTE (se nutren de datos propios).

### ⭐ DOS REGLAS DE IDENTIDAD DE IMPULSE (definidas por el dueño esta jornada, permanentes)
1. **Impulse solo analiza DATOS PROPIOS de la organización** (ventas, precios,
   inventario, clientes). NUNCA datos externos (mercado, competencia, tendencias) ni
   inventados. Por eso se descartaron "Oportunidades de mercado" y "Cosas que podría
   estar ignorando": miraban afuera.
2. **Impulse ENTREGA el dato medido; NO lo interpreta.** La lectura/el porqué es
   responsabilidad del DIRECTOR humano (el dueño contrata gente capacitada). Cero
   frases de opinión en las herramientas. La máquina mide con precisión; el humano
   decide.

### La "cita a ciegas" (bajo acoplamiento — decisión de arquitectura del dueño)
Inventario y Contabilidad NO se hablan entre sí. Cada uno hace su trabajo y ambos
depositan su dato donde Marketing lo lee. Contabilidad sigue MANUAL y desconectada de
Inventario (un error de un lado no envenena el otro). El reparto de una venta:
inventario baja (auto cuando haya checkout / manual en piloto), ingreso de inventario
y registro contable = manuales (humano con criterio).

## SOFTWARE 4 — Área VENTAS  ⏳ PLANO APROBADO, FALTA CONSTRUIR (justo aquí quedó la sesión)

**ESTADO EXACTO AL ABRIR EL PRÓXIMO CHAT:** el dueño y Kiro diseñaron el área Ventas
a fondo y el dueño APROBÓ el plano. El plano vive en **`docs/PLANO-VENTAS.md`**, en el
**PR #183 (abierto, aún NO mergeado)** — LEERLO COMPLETO; su cabecera "⭐ DECISIONES
FINALES DEL DUEÑO" manda. **NO se ha construido nada de Ventas todavía** (no existe la
carpeta `ventas/`). El siguiente paso es: (1) que el dueño mergee el PR #183, y (2)
CONSTRUIR el área siguiendo el plano. (Un intento de lanzar la construcción se abortó
por un fallo mecánico de Kiro, sin efecto: nada se construyó ni se rompió, main quedó
intacto.)

**Qué es Ventas (cuarta área, `ventas/`), con 2 sub-áreas:**
- **Seguimiento de pedidos** (operativo, para quien prepara y entrega): tablero de
  pedidos + **registrar pedido MANUAL**. Un solo NÚCLEO `crear_pedido` con DOS PUERTAS
  (manual hoy / web futura cuando haya checkout). Al crear el pedido: baja inventario
  (salida en el libro, `referencia = id del pedido`), crea la orden, vincula/crea el
  cliente, registra el **precio real** de venta.
- **Portafolio de clientes** (la memoria): ficha (nombre, correo, teléfono, dirección)
  + historial + métricas OBJETIVAS (última compra, frecuencia, total). NO interpreta la
  "salud" (eso lo hará el Análisis Clúster de Marketing después).

**Decisiones finales del dueño (en la cabecera del plano):**
- **Baja de stock AL CREAR** el pedido (coherente con la web futura).
- **Estados (4):** Recibido → Preparando → **En camino** → Entregado (+ cancelado y
  devuelto). Preparados para disparar correos por etapa MÁS ADELANTE (Email Marketing).
- **Coincidencia de cliente por PUNTAJE explicable** (NO IA): correo/teléfono
  normalizados = señal fuerte; nombre similar = débil. 3 niveles alta/media/baja con %
  + el porqué. El humano decide con botón; NUNCA fusiona solo, NUNCA bloquea el
  registro. Enciende el `customer_id`.
- **DEVOLUCIONES:** se construye SOLO el MOTOR por debajo (revertir un pedido con
  ENTRADA compensatoria al inventario, anclada a un pedido, parcial o total; nunca
  borrando). La **pantalla/categoría "Devoluciones" NO se construye aún** — irá en
  PRODUCCIÓN (hermana de Inventarios), y se hará cuando el dueño defina su POLÍTICA de
  devoluciones (qué acepta, estado, plazo; matiz belleza/higiene abierto NO se revende
  vs objeto en buen estado sí; marco legal: derecho de retracto Ley 1480). Esa política
  es decisión de NEGOCIO/LEGAL del dueño, NO del software (el software registra la
  devolución que el dueño aprueba, no decide si procede). El dueño se informará y luego
  se construye.
- **Seguridad REFORZADA** de datos personales (correos/teléfonos/direcciones): RLS
  estricta vía `tiene_acceso_ventas()`, NUNCA públicos.
- **Diseño nivel Finanzas** (PILAR innegociable para el dueño), sin color nuevo (azul
  marino), sello Impulse. Migraciones nuevas con prefijo `20250401...`.

**Enchufes que enciende/deja Ventas:** `customer_id` encendido (Marketing por cliente),
precio real (el Ranking deja de estimar — actualizar su marcador CONEXION FUTURA),
correo normalizado → Email Marketing futuro, dirección → Mapas/Rutas futuro. Finanzas
sigue DESCONECTADA (cita a ciegas).

## 🩹 TANDA 2 — La incisión: Campañas ↔ Inventario (aplicada en código)

**Estado:** la incisión que conecta el Área de Campañas (aprobada) con Inventario
está **aplicada en código**, **pendiente de que el dueño corra el SQL**
`supabase/migrations/20250503000000_campanas_incision_inventario.sql` en el SQL
Editor y lo verifique. Qué enciende, en corto: FK `campana_producto.product_id_ref
→ productos.id`; siembra de los 5 productos de Campañas en Inventario con **stock 0
y CERO movimientos** (existen para que la tienda los muestre, sin tocar
Contabilidad); `catalogo_publico` expone el booleano derivado **`agotado`** (del
stock real) en vez de `stock_disponible`; desplegable de producto en el panel de
Campañas; y la tienda muestra **Agotado** y **deshabilita la compra** sola cuando
el stock llega a 0. Finanzas sigue DESCONECTADA a propósito. El aviso "Solo X
disponibles" sigue siendo MANUAL.

- **Mapa completo de tapetes (encendido / preparado / desconectado / línea roja):**
  `docs/MAPA-CONEXIONES-TANDA2.md`.
- **SQL y verificación:** `supabase/INSTRUCCIONES.md` → subsección **C4. Tanda 2**.

## Próximos pasos posibles (decidir con el dueño)

- **CONSTRUIR VENTAS** (lo inmediato): mergear PR #183 y construir las 2 sub-áreas
  según `docs/PLANO-VENTAS.md`.
- **Software de CLIENTES más completo:** el dueño lo quiere más que una tabla; el
  Portafolio de Ventas es la base, se puede enriquecer después.
- **Análisis Clúster (Marketing):** leerá el Portafolio + pedidos para agrupar clientes
  y calcular la "salud" (por periodo, individual o general). Será "bastante cargado".
  Se hace DESPUÉS de que Ventas llene datos reales.
- **Email Marketing:** sección futura; campañas dirigidas por clúster, usando el correo
  recolectado. El dueño ya lo anticipó.
- **Devoluciones (pantalla en Producción):** cuando el dueño defina su política.
- **Mapas/Rutas de entrega:** la dirección alimentará geolocalización y rutas (futuro).

- **Marketing:** activar Análisis clúster y Elasticidad cuando haya datos.
- **Tienda pública magandhi.com:** falta la PÁGINA DE PRODUCTO REAL (el hero lleva a
  404); diseño v1 ya aprobado. La superficie de lectura pública (`catalogo_publico`)
  quedó diseñada en el plano pero NO construida (el dueño la pausó: "todo interno por
  ahora").

## WOMPI — pendiente abierto (retomar el dueño)
Pasarela de pagos para MAGANDHI. Es la MISMA cuenta que usaba el proyecto muerto
"Stramont". Titular: Michell Stiven Rios Dominguez, CC 1033102484 (registrado como
**persona natural con cédula, sin RUT** — vía válida; cuenta YA aprobada y activa).
Correo registrado: contacto@montaguth.institute. PROBLEMA: los pagos salen a nombre
de "montaguth institute", confunde al cliente; debe decir **MAGANDHI** (el cliente ve
"PAGO WOMPI + NOMBRE COMERCIO"). El nombre del comercio SÍ es modificable pero NO por
autoservicio (el dashboard solo ofrece 4 procedimientos, ninguno es el nombre) →
según doc oficial de Wompi se pide por **solicitud a soporte** (chat del dashboard).
Posible que pidan RUT para el cambio aunque se haya registrado con cédula (a
confirmar con soporte). NO borrar/recrear la cuenta (perdería aprobación + llaves de
integración). Postura del dueño sobre formalización (Cámara de Comercio/RUT): no
hacerla A MEDIAS ni sobre-formalizar antes de validar ventas, pero sí tener el piso
mínimo cuando entre dinero real.

**✅ ESTADO ACTUAL (actualizado): EL CAMBIO DE NOMBRE YA SE APLICÓ.** El dashboard de
Wompi muestra la cuenta como **"Magandhi"**. OJO con un matiz que confundió en su
momento: el **checkout de SANDBOX sigue mostrando "montaguth institute"** porque
sandbox y producción son **perfiles de comercio SEPARADOS** en Wompi; el nombre nuevo
se verá en el checkout real al pasar a producción (F4). Ningún cliente ve el checkout
de sandbox.

**PENDIENTE MENOR (decisión del dueño: lo gestiona él, NO urgente):** los DATOS DE
CONTACTO del comercio que Wompi muestra al cliente en el panel "Información del
comercio" del checkout siguen siendo los viejos — correo `contacto@montaguth.institute`
y un teléfono personal. Lo coherente con la marca sería `contacto@magandhi.com` (ya
montado en Zoho) y el WhatsApp Business **+57 313 245 1188**. Se le señaló al dueño que
eso lo VE el cliente al pagar; él decidió dejarlo así por ahora (con cero clientes
reales no es urgente). NO insistir; retomar si él lo pide o al acercarse F4.

Kiro NO interviene en Wompi (no tiene acceso); acompaña con capturas/redacción si el
dueño lo pide.

## Flujo de trabajo Git
- Rama nueva + PR por cada cambio. NUNCA push directo a main. El dueño mergea rápido.
- Verificar PRs antes de reusar ramas. `.agents/` está en `.gitignore`.
- Los cambios de SQL requieren que el dueño los aplique a mano en Supabase (ver
  `supabase/INSTRUCCIONES.md`, con orden exacto y queries de verificación).

---
## 🔖 DÓNDE RETOMAR (cierre de sesión — leer esto primero al abrir chat nuevo)

**El ecosistema Impulse tiene 3 áreas VIVAS en producción:** Finanzas (Contabilidad
PUC), Producción (Inventarios: Ver/Agregar/Movimientos) y Marketing (Marketing
Project: Proyección de demanda, Tendencia Central, Ranking de productos).

**La 4.ª área, VENTAS, está DISEÑADA Y APROBADA pero NO construida.** El plano es
`docs/PLANO-VENTAS.md` en el **PR #183 (abierto, sin mergear)**. Ver la sección
"SOFTWARE 4 — Área VENTAS" arriba para el detalle completo.

**PASO INMEDIATO para continuar el proyecto tal cual:**
1. El dueño **mergea el PR #183** (deja el plano en main como fuente de verdad).
2. Kiro **construye el área Ventas** siguiendo `docs/PLANO-VENTAS.md` y sus decisiones
   finales (2 sub-áreas: Seguimiento de pedidos + Portafolio de clientes; núcleo
   `crear_pedido`; coincidencia por puntaje; motor de devoluciones por debajo;
   migraciones `20250401...`; nivel Finanzas, sin color nuevo, sello Impulse). El SQL
   lo aplica el dueño a mano (documentar en `supabase/INSTRUCCIONES.md`).

**RECORDATORIOS PERMANENTES:** (a) reglas de identidad de Impulse: solo DATOS PROPIOS /
NO interpreta (el humano decide/lee). (b) La INTERFAZ y la coherencia de marca son
FUNDAMENTALES para el dueño (nivel Finanzas, azul marino, sin color nuevo, sello
Impulse, wordmark MAGANDHI). (c) Flujo Git: rama nueva + PR por cada cambio, nunca push
a main, el dueño mergea; SQL/Edge/Storage los aplica el dueño a mano. (d) "Hacer las
cosas bien": sin afán, nada a medias; frenar al dueño si se afana. (e) Wompi: nombre del
comercio ya cambiado a MAGANDHI (Kiro no interviene en Wompi). (f) Modo de trabajo: "regar fichas" → trazar el
camino de conexión (husmear los tapetes de otras áreas para conectar) → construir.

_Última actualización: ver el bloque "SESIÓN CAMPAÑAS" abajo (la más importante del
proyecto hasta ahora)._

---

# 🌟 SESIÓN CAMPAÑAS — carta al próximo Kiro (léela completa)

Hola, yo (Kiro de esta sesión). El dueño (D0m0) me dijo que esta fue **la sesión más
importante del proyecto** y me pidió dejarte todo para que "sea como seguir hablando
conmigo" y no andes perdido. Aquí va, de socio a socio.

## Cómo trabaja el dueño (esto es oro, respétalo)
- **Metodología suya, textual:** "regar las piezas (todo lo planeado) → discutirlas →
  tenerlas claras → mirar bajo los tapetes (todo lo que se podría conectar/alimentar)
  → y AL FINAL diseñar/construir". No te saltes fases. Discute ANTES de construir.
- **La INTERFAZ y el DISEÑO son PILAR innegociable.** Lo repite siempre ("no olvides
  lo MUY importante que es la interfaz para mí 😁"). Back-office = nivel Finanzas (azul
  marino #101C33, wordmark MAGANDHI, sello "Con tecnología Impulse"). Tienda = boutique
  (terracota #A6332E, crema, Poppins), NUNCA sello Impulse ni tecnología a la vista.
- **Le encanta PROBAR y descartar sin drama** (Git lo hace reversible). Muéstrale cosas
  reales para que las mire con ojo crítico. Varias veces me hizo "tragar mis palabras"
  (el zigzag) y otras me dio la razón (contorno terracota descartado).
- **Chispas críticas:** explícale el PORQUÉ de cada decisión, sin humo. Frénalo con
  honestidad si se afana. "Hacer las cosas bien", sin prisa, nada a medias.
- **Verificar con EVIDENCIA, no con el papel.** Esta sesión aprendimos a golpes: el
  contexto/apuntes pueden estar desactualizados; un `select` a la base real vale más
  que un "ya quedó". SIEMPRE verifica antes de asumir (nos pasó con el Supabase
  equivocado y con Inventario que "estaba aplicado" y no lo estaba).

## Lo que se CONSTRUYÓ esta sesión (todo en producción / listo para mergear)

### 1. Área VENTAS (estaba solo diseñada; se construyó y quedó viva)
Migraciones `20250401000000..000500`. Dos sub-áreas: Seguimiento de pedidos +
Portafolio de clientes. Núcleo `crear_pedido` (dos puertas: manual hoy / web futura),
`anular_pedido` (motor de devolución con entrada compensatoria), `avanzar_estado_pedido`,
`buscar_candidatos_cliente` (coincidencia por puntaje explicable). FK del `customer_id`
del libro ENCENDIDA. 5 estados (recibido→preparando→**en_camino**→entregado + anulado).
El dueño la aplicó y funciona.

### 2. TIENDA PÚBLICA rediseñada (magandhi.com)
- Se **rescató del historial de git** la página de producto que el dueño había aprobado
  (estaba borrada; vivía en `proto/producto/index.html`, commit 593bdb8^). LECCIÓN: git
  nunca olvida, revisa el historial antes de decir "se perdió".
- Home pasó de vitrina de 1 producto a **grid de 5** con el sistema **COLOR = CATEGORÍA**
  (idea del dueño, clave): el color NO es decorativo, es **semántico por categoría**
  (rosa=belleza femenina, grafito=belleza masculina, azul=hogar, etc.). Paleta de 7
  categorías en tonos MAGANDHI (misma temperatura cálida = colección curada, no arcoíris).
- **Móvil = masonry real (zigzag tipo Pinterest)** con `column-count:2` (NO grid, que
  hace filas rígidas). Nace del contenido, se propaga solo. El dueño distingue: hero =
  exploración (zigzag), categorías complejas futuras = grid ordenado.
- Estrella "producto estrella" va DENTRO del sello "Elegido por MAGANDHI" (no ícono
  suelto). Aviso de urgencia, agotado, barra de confianza con modal Wompi, botón volver.
- Diseño guardado como referencia en `magandhi/diseno-referencia/` (LEEME.md + copia).

### 3. SOFTWARE CAMPAÑAS (lo grande de la sesión) — Marketing → `marketing/campanas/`
El software donde un producto se "viste" para la tienda y se PUBLICA. Migraciones
`20250501000000..000700` (cimiento como ISLA), `20250502000000` (Tanda 1: etiquetas
gestionables, slug, es_placeholder), `20250503000000` (Tanda 2: la incisión con Inventario).

- **Dos secciones por producto:** (1) BANNER HOOK (la tarjeta del home) + (2) PRODUCTO
  (la página completa). UN registro `campana_producto`, dos niveles de detalle. La
  tienda decide qué mostrar en móvil vs PC (automático por CSS, el dueño no elige por
  producto).
- **Se construyó como ISLA primero** (real en Supabase, tienda leyendo en vivo, pero SIN
  conectar Inventario) para validar antes de cablear. Cuando el dueño la aprobó, se hizo
  la INCISIÓN (Tanda 2). Ese patrón "isla → aprobar → incisión" le gustó mucho.
- **Interruptores por producto:** sello "Elegido por MAGANDHI" (sí/no — opcional para
  que no pierda valor por repetición), estrella destacado (sí/no), publicar/despublicar
  (interruptor, NUNCA borra), aviso de urgencia "¡Solo X disponibles!" (MANUAL, el dueño
  lo activa con su número — honesto, no escasez fabricada = línea roja de marca).
- **Color automático por categoría.** **Etiquetas de segmentación** internas (lista
  controlada tipo PUC, gestionables desde el panel con `cm_crear_etiqueta`/`cm_editar_etiqueta`)
  → alimentarán el Análisis Clúster futuro. NUNCA salen a la tienda.
- **Página de producto GENÉRICA por slug/id** (`magandhi/producto/index.html`): se llena
  sola desde `catalogo_publico`. Cada producto nuevo tiene su "lugar" automático, sin
  crear un HTML por producto.
- **Subida de imágenes real:** explorador + arrastrar y soltar, optimización (WebP, dos
  tamaños: grande para producto, liviana para grid), bucket Storage `campanas` (el dueño
  lo creó). Reorden de galería tipo Spotify (drag & drop).
- **Vista pública `catalogo_publico`** = ÚNICA superficie que lee la tienda (rol anon).
  LÍNEA ROJA: solo campos públicos de productos publicado+activo. NUNCA costo, proveedor,
  stock exacto, product_id_ref, es_placeholder, ni etiquetas. Candado doble (tablas base
  sin grant a anon + lista blanca de columnas).

### 4. LA INCISIÓN (Tanda 2) — Campañas ↔ Inventario conectado ✅ APLICADO Y VERIFICADO
Ver `docs/MAPA-CONEXIONES-TANDA2.md` (mapa completo de tapetes). Migración `20250503000000`
**ya aplicada por el dueño y verificada con evidencia** (los 5 ligados, 0 movimientos, la
vista expone `agotado` sin stock exacto).
- Los 5 productos (Grisi + 4 ejemplos) SEMBRADOS en Inventario con **stock 0 y CERO
  movimientos** → NO afecta Contabilidad (verificado: la consulta de movimientos dio 0).
  Marcados con `productos.es_placeholder`.
- ⚠️ LECCIÓN TÉCNICA: la siembra al principio llamaba a `inv_crear_producto`, pero esa
  función valida `tiene_acceso_inventario()` que resuelve por `auth.uid()`; en el SQL
  Editor `auth.uid()` es NULL → rechazó con **P0001 "Acceso denegado"**. Fix (PR #191): la
  siembra INSERTA DIRECTO en `productos` (operación de administración que corre el dueño),
  replicando la generación de SKU, sin debilitar el guardia de la función. REGLA para el
  próximo Kiro: cualquier migración que el dueño corra en el SQL Editor y llame una RPC con
  guardia `tiene_acceso_*()` FALLARÁ (no hay usuario logueado); usa insert/operación directa
  en esos seeds de administración.
- FK `campana_producto.product_id_ref → productos(id)` ENCENDIDA.
- **Desplegable** en el panel: primero registras el producto en Inventario → aparece en
  el select → lo eliges al crear/editar la campaña.
- **Agotado automático:** `catalogo_publico` expone booleano derivado `agotado`
  (existencias<=0 del stock REAL), NUNCA el número exacto. Stock 0 → sello Agotado +
  botón compra deshabilitado. Sube el stock → se reactiva solo. (Hoy los 5 salen Agotado
  porque tienen stock 0 — es correcto y esperado hasta que el dueño cargue unidades reales.)
- Triángulo **Campaña ↔ Producto ↔ Venta** cerrado sobre `productos.id`.

## DECISIÓN DE ORO del dueño (grábala): productos ficticios NO se editan, se REEMPLAZAN
Los 4 productos de ejemplo (Sérum, Bálsamo, Jabón, Miel) son inventados (elegir productos
reales requiere análisis de mercado que hace el dueño). La regla: **NO editar la casilla
ficticia para volverla real** (sería "cambiarle el nombre a alguien dejándole la cédula
—UUID— de otro"). Lo correcto: **retirar el placeholder (flag `es_placeholder`) y crear
un producto NUEVO con su cédula limpia** cuando llegue el real. Por eso existe el flag en
`campana_producto` Y en `productos`. El dueño pidió orientación para hacerlo cuando toque.

## PENDIENTES / PRÓXIMOS PASOS (lo que sigue)
- **TODO EL SQL DE ESTA SESIÓN YA ESTÁ APLICADO Y VERIFICADO** (Ventas, Campañas cimiento,
  Tanda 1, Tanda 2/incisión). No queda SQL pendiente de esta sesión. El ecosistema está
  completo y en producción: la tienda lee de Campañas en vivo, conectada a Inventario, con
  Agotado real. Todos los PRs (#185-#191 back-office, #16-#35 tienda) MERGEADOS.
- **Reemplazar los 4 placeholders por productos reales** cuando el dueño haga su análisis
  de mercado (retirar + crear nuevos, NO editar). Orientarlo en el proceso.
- **Más etiquetas de segmentación con criterio** (definir con el dueño el catálogo, pensado
  para que el clúster agrupe bien; no una lista infinita).
- **Categorías complejas / páginas de categoría** en la tienda cuando haya >5 productos
  (el home dejará de mostrar "todo" y pasará a una selección; grid ordenado, no zigzag).
  El dueño avisará: "esta área de Campañas es de las que más requerirá actualizaciones".
- **Análisis Clúster (Marketing):** leerá las etiquetas de Campañas × ventas por cliente
  para inferir perfiles. Terreno preparado, no encendido (espera datos reales de ventas).
- **Limpieza de imágenes huérfanas en Storage** (deuda conocida documentada de Tanda 1).
- **Wompi:** cambio de nombre a MAGANDHI ✅ YA APLICADO (el dashboard dice "Magandhi").
  Queda un pendiente MENOR que el dueño gestionará cuando quiera: los datos de contacto
  del comercio que el cliente ve en el checkout siguen siendo los viejos
  (`contacto@montaguth.institute` y teléfono personal) en vez de
  `contacto@magandhi.com` + WhatsApp +57 313 245 1188.
- **Reseñas reales** (hoy son de ejemplo; la página tiene `noindex` a propósito hasta que
  haya datos reales — coherente con "nada inventado").

## RECORDATORIOS PERMANENTES (siguen vigentes)
(a) Identidad Impulse: solo DATOS PROPIOS / la máquina mide, el humano interpreta.
(b) Interfaz/marca = PILAR. (c) Git: rama nueva + PR por cambio, nunca push a main, el
dueño mergea rápido (verifica si un PR ya está mergeado antes de reusar rama; usa rebase
si hay conflictos). SQL/Storage los aplica el dueño a mano; escribir SQL en el repo NO lo
despliega. (d) "Hacer las cosas bien", sin afán. (e) Verificar con evidencia, no con el
papel. (f) Montos bigint; nada se borra; seguridad = línea roja (RLS + RPC security
definer + vista pública con lista blanca; cero service_role en repos).

_Sesión CAMPAÑAS (CERRADA, todo en producción): se construyó Ventas, se rediseñó la tienda
(grid color=categoría + masonry móvil), y se creó el software Campañas completo (isla →
Tanda 1 → incisión con Inventario), TODO aplicado en Supabase y verificado con evidencia.
PRs de la sesión, TODOS MERGEADOS: back-office #185-#191; tienda #16-#35. Estado final: la
tienda pública lee de Campañas en vivo, conectada a Inventario, con Agotado automático desde
el stock real, y datos de clientes/seguridad intactos (Contabilidad no se tocó: 0 movimientos
en la siembra). La sesión más importante del proyecto — marcó el rumbo de cómo se viste y se
vende cada producto. El próximo Kiro retoma desde "PENDIENTES / PRÓXIMOS PASOS" arriba._
