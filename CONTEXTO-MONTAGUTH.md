# 🚚 CONTEXTO MONTAGUTH — Camión de mudanzas (léeme primero)

> **Para el próximo Kiro:** esto lo escribe la sesión anterior para que arranques sin perder el hilo.
> Léelo completo antes de tocar nada. Se actualiza **al final de cada acción/PR relevante**, no solo al cerrar sesión:
> corrige lo que ya no sea cierto (no solo agregues).
>
> **Última actualización:** 18 de agosto de 2026 — sesión del **PIVOTE**: Stramont se archiva y nace **Montaguth, tienda online**.

---

## 0. Qué es esto ahora

**Montaguth** es una **tienda online** (venta por internet con modelo *dropshipping*: productos de proveedores
que despachan por nosotros). Vive en el mismo dominio de siempre: **montaguth.institute**, GitHub Pages, sitio estático.

- **Repo:** `12344-ux/12344-ux.github.io`, rama `main` = lo publicado. **Repo público.**
- **Marca:** MONTAGUTH · *"Tu mundo. Tus compras."* Rojo `#D32F2F`, negro `#111111`, blanco `#FFFFFF`, tipografía **Poppins SemiBold**.
  El logo es una **bolsa/domo/montaña** (compras + protección + crecimiento).
  ✅ **El logo ya es el ORIGINAL del manual.** El archivo que entregó el dueño está en
  `marca/logo-original.jpg` (ícono blanco sobre rojo, 1254 px). De ahí se derivaron con PIL:
  `logo-mark.png` (ícono rojo, fondo transparente → para fondos claros),
  `logo-mark-blanco.png` (para fondos oscuros/rojos), `favicon.png` y `logo.png` (tile app-icon).
  Receta para regenerarlos: `alpha = canal MÍNIMO(R,G,B)` normalizado entre 45 y 225 → recorte al
  bbox → lienzo cuadrado con 10 % de aire. (El truco del canal mínimo evita el halo rojo que deja
  un JPG con antialiasing.) **No hay SVG**: si algún día hace falta vectorial, hay que vectorizarlo.
- **Premisa del dueño (textual):** *"No queremos competir con Amazon o Mercado Libre; queremos vender por
  internet a clientes reales haciendo dropshipping."*
- **Diferenciador declarado:** confianza desde el primer vistazo + **anuncios hechos a medida** (aprovechando
  el pipeline de video que ya existe) + hipersegmentación por producto/ángulo.

### Lo que ANTES fue este dominio (Stramont)
Proyecto educativo (guías de estudio a partir de apuntes). Se **terminó, funcionó y cobró de verdad con Wompi**,
pero **nunca se lanzó al público** y **no hubo ni un pago real de cliente** (todo fueron pruebas).
El dueño lo cerró por decisión propia: modelo fácil de replicar y sin ambición comercial suficiente.
**Está congelado y es 100% recuperable:**

```
tag    stramont-v1.0-final     ← el proyecto completo, tal como quedó
rama   archivo/stramont-v1     ← misma foto, en rama
```

Si necesitas ver cómo se hacía algo en Stramont (guías, correos, tablero), consulta ahí. **No lo revivas en `main`.**

---

## 1. Quién es el dueño y cómo trabajamos

Estudiante de Dirección de Ventas (SENA, Colombia). **Es el director del proyecto**; no programa y no tiene acceso
al sistema de archivos: todo lo revisa por **Pull Request** en GitHub y en el navegador.

- **Trato de socio, no de proveedor.** Honestidad directa, "chispa crítica" (el porqué, breve y claro) y luego resolver.
  Cero humo. Nunca decir "está listo" sin haberlo probado de verdad.
- **Autonomía esperada.** Corregir lo que esté mal planteado sin pedir permiso, y explicar después por qué.
- **Dedicación real del dueño:** 6+ horas al día. Espera ritmo.
- **Trabaja en paralelo con otra IA** ("la de ideas/persuasión") que le trae briefs de marca, copy y estrategia.
  Tu papel es ejecutarlos **con criterio técnico y comercial**, no aceptarlos literales si abren un hueco.
- **Esta vez el objetivo es explícito: GANAR DINERO.** No es un ejercicio.

### Líneas que no se cruzan (innegociables)
1. **Nunca exponer llaves/secretos.** Si el camino fácil expone algo sensible, se busca otra vía y se explica.
   Las llaves públicas (Supabase *publishable*, Wompi `pub_prod_`) sí pueden ir en el frontend; los secretos jamás.
2. **Nada de productos falsificados, réplicas ni marcas de terceros** (ni "Pro Series", ni logos ajenos).
   Es la vía rápida a que cierren la cuenta de pago y baneen el dominio, además del riesgo legal.
3. **Nada de trucos engañosos de tienda:** reseñas inventadas, escasez falsa, contadores falsos,
   promesas de salud, precios "antes" inflados. La confianza es el producto.
4. **Se promete solo lo que la logística puede cumplir.** Si el proveedor entrega en 20 días, la web dice 20 días.

---

## 2. Estado del repo tras el pivote (qué vive, qué murió)

| Vive en `main` | Para qué sirve ahora |
|---|---|
| `index.html` | **Portada provisional de Montaguth** (marca + lista de espera de apertura). Autocontenida, CSS inline. |
| `checkout.html` | Motor de pago con **Wompi en producción**. Hereda copy de Stramont: **hay que reescribirlo** para carrito. |
| `informe.html` | Tablero interno (pide `LINK_SECRET`). Se rediseñará como **centro de pedidos**. |
| `privacidad.html`, `condiciones.html` | Legales heredadas. **Se reescriben** para tienda (+ faltan envíos y devoluciones). |
| `por-que-wompi.html` | Página de confianza de la pasarela. **Sigue siendo válida tal cual.** |
| `pago-estado.html` | Página de retorno de Wompi. |
| `estilos.css` | Shell global heredado (header/footer/bandas). Tiene CSS muerto; se limpiará al construir la tienda. |
| `favicon.png`, `logo.png`, `logo-mark.png`, `logo-mark-blanco.png` | Marca Montaguth (provisionales, ver §0). |
| `wompi-logo.svg` | Logo oficial de Wompi para el bloque de pago seguro. |
| `supabase/functions/*` | 8 Edge Functions (ver §3). |
| `supabase/migrations/*` | SQL versionado de las tablas. |
| `ads/` | **Pipeline de video** (el activo más valioso): escenas HTML de referencia + `audio/mezcla.py`. |
| `herramientas/rastreador/` | **Rastreador de nichos v1**: mide demanda en Google Trends (`geo=CO`), descubre términos en alza, veta categorías prohibidas y puntúa 0-100. Ver su `LEEME.md`. |
| `marca/logo-original.jpg` | El archivo de marca que entregó el dueño (fuente de los assets). |
| `.kiro/steering/montaguth.md` | Instrucción permanente del proyecto. |
| `.kiro/steering/anuncios.md` | Receta técnica de producción de video (sigue vigente). |

**Murió en `main`** (todo está en el tag/rama de archivo): landing de Stramont, guía demo `demo/`, `quienes-somos.html`,
`gracias.html`, `pago.html`, `entrega.html`, `feedback.html`, `kit-stramont.zip`, todas las imágenes de apuntes/guías,
los MP4 de anuncios de Stramont, la voz en off vieja, `.kiro/steering/metodo-guias.md` (el CHIP de guías),
`CONTEXTO-STRAMONT.md`, la Edge Function `entrega` y los documentos personales del SENA que estaban servidos en público.
El repo bajó de **142 MB a ~5 MB**.

---

## 3. Infraestructura heredada que SÍ se reutiliza (no rehacer)

Todo vive en Supabase (proyecto `ifvnuvjvlzpdaimelmbm`) + Resend + Wompi. **Escribir código de una Edge Function
en el repo NO la despliega**: el deploy es manual (dashboard de Supabase), lo hace el dueño.

| Función | Estado / para qué sirve en la tienda |
|---|---|
| `wompi-firma` | Firma de integridad server-side + conversión USD→COP con TRM. **Habrá que cambiarla a monto de carrito.** |
| `wompi-webhook` | **Única fuente de verdad del "pagado"** (fail-closed, idempotente, maneja reversas). Se reusa casi igual. |
| `correo-confirmacion` | Correo 1. Pasa a ser "recibimos tu pedido" + resumen de compra. Exige pago aprobado. |
| `correo-entrega` | Correo 2. Pasa a ser "tu pedido va en camino" + número de guía/tracking. Exige pago aprobado. |
| `correo-feedback` | Correo 3. Pasa a ser reseña del producto (prueba social real). |
| `feedback` | Registro público de opiniones validado por token por pedido. |
| `captura` | Captura de correos server-side (la usa la portada nueva, `origen=lista_espera_reapertura`). **Ya desplegada y funcionando.** |
| `informe` | Cerebro del tablero (service_role + `LINK_SECRET`). Se adapta a pedidos de tienda. |

**Tablas:** `pedidos`, `pedido_intake`, `pedido_feedback`, `correos`, `config`. RLS verificada: la llave pública
**no puede leer** datos de clientes; solo inserta pedidos/intake y lee el booleano `config.operaciones_activas`.

**Interruptor de operaciones:** `informe.html` → ⚙️ Operaciones → Suspender/Reactivar. Sirve para cerrar la caja.
⚠️ **Pendiente del dueño: dejar operaciones EN PAUSA** mientras la tienda no exista (hoy `checkout.html` todavía cobraría).

### ⚠️ Riesgo operativo confirmado: Supabase gratuito se PAUSA por inactividad
El 18-ago el proyecto estaba pausado y **el subdominio dejó de resolver** (`ENOTFOUND`) → todo el
backend caído (captura, tablero, pagos) sin ningún aviso. Se restauró desde el dashboard y se
**verificó en vivo**: `captura` responde `200 {"ok":true}`, es idempotente al repetir el mismo
correo y rechaza inválidos con `400`. **Implicación para una tienda que cobra:** si pasa una semana
sin actividad, la tienda se cae sola. Mitigación pendiente: un ping programado que mantenga el
proyecto despierto, o plan pago cuando entren las primeras ventas.

### Deudas técnicas heredadas (documentadas en la auditoría de Stramont, siguen vigentes)
1. **El aviso de compra al dueño no se envía** desde que Wompi entró en producción: vivía en el Paso 4 de
   `checkout.html`, que ya no se alcanza (el navegador se va a Wompi). Hay que moverlo al webhook. **Alta prioridad.**
2Rehacer el `estado_pago` del tablero: si viene `null`, el pill dice "Pagado · por procesar" y el detalle dice
   "Sin confirmar — NO entregar" (contradicción).
3. El tablero **no bloquea** entregar un pedido no pagado (el servidor sí lo bloquea; falta el guard en la UI).
4. El `LINK_SECRET` viaja en la query string (`?key=`) → queda en logs. Debería ir en cabecera.
5. `checkout.html` carga jsPDF y `@supabase/supabase-js@2` desde CDN **sin SRI ni versión fija**.

---

## 4. Decisiones de negocio ya tomadas

- ✅ **Dominio:** se queda `montaguth.institute`. La tienda vive en la **raíz** (no en `/shop`).
- ✅ **Marca:** Montaguth, nombre paraguas **neutro a propósito** (permite cambiar de producto sin cambiar de marca).
- ✅ **Sin cuentas de usuario** por ahora (no hay login; el pedido se rastrea por correo + número de pedido).
- ✅ **Pasarela:** Wompi, ya integrada. ⚠️ **Falta avisarle a Wompi el cambio de actividad** (de guías digitales a
  productos físicos): si no, riesgo de retención/bloqueo de fondos.
- ✅ **Pago contraentrega:** deseable, pero **no se puede simular** (alguien tiene que recaudar el efectivo:
  transportadora o plataforma). Se arranca con **pago anticipado** y se suma después si el volumen lo justifica.
- ⏸️ **Presupuesto de anuncios:** se define en la etapa de anuncios (decisión del dueño). Ojo: si es cero,
  el producto elegido debe ser apto para **orgánico** (demostrable en video).
- ⏸️ **Formalización** (RUT / registro / factura electrónica): se resolverá más adelante; el retracto de
  **5 días hábiles** (Ley 1480, art. 47) aplica igual desde la primera venta.

---

## 5. Reglas de trabajo (no te las saltes)

1. **Nunca push directo a `main`.** Rama nueva → PR → el dueño mergea (mergea rápido; entrega PRs completos).
2. **Una rama mergeada no se reutiliza.** Cambio nuevo = rama nueva + PR nuevo.
3. Antes de crear rama, revisa los PRs abiertos (`gh api repos/12344-ux/12344-ux.github.io/pulls`).
4. Si tocas `estilos.css`, sube el cache-bust `?v=N` en todos los HTML que lo referencian.
5. **Tras cada merge, verifica tú que el deploy salió** (GitHub Actions). Si queda `queued` mucho rato o falla,
   suele ser degradación transitoria de GitHub: se destraba con un commit nuevo en **otra** rama (no "Re-run").
6. Prueba de verdad: Chromium headless para interactividad, `deno check` para Edge Functions.
   Instalación de Playwright en sandbox nuevo: `cd /projects/sandbox/pw && npm i playwright-core@1.47` +
   `PLAYWRIGHT_BROWSERS_PATH=/projects/sandbox/pw/browsers npx playwright@1.47 install chromium`.
7. **Mantén este documento al día en cada PR relevante.**

---

## 6. Roadmap acordado (en orden)

1. ✅ **Desmontaje de Stramont + portada de marca** (PR #142, mergeado). Logo original aplicado después.
2. ✅ **Arquitectura DECIDIDA: marca paraguas + landings de producto.** La home es la credencial de
   confianza; la venta ocurre en `/p/<producto>`, donde cae el anuncio. Cada producto = una landing con
   su ángulo y su video (así se sostiene el multi-nicho sin fingir un inventario que no existe).
   Se descartó la home tipo marketplace: competir por surtido/precio/logística es el terreno donde
   Amazon y Mercado Libre ganan siempre, y una tienda generalista con 12 productos se ve vacía.
   **Del mockup del dueño se conservan** logo, Poppins, la paleta, la barra superior de confianza y la
   grilla de garantías; **se descartan** buscador central, 6 categorías vacías, carrusel, login y
   precios en rojo (el rojo va en dosis: a pantalla completa lee como "marketplace de descuentos").
3. ✅ **Rastreador de nichos v1** (PR #143, mergeado). Fuentes verificadas desde el sandbox:
   Google Trends vía pytrends ✅ (con caché en disco por el 429), Amazon best sellers ✅,
   TikTok Creative Center ✅, Dropi ✅, CJ ✅ (requiere cuenta) · **Meta Ad Library y API de
   Mercado Libre devuelven 403 desde servidor** → se revisan a mano.
4. **Proveedor**: el dueño ya creó cuenta en **Dropi** (nacional, entrega 24–72 h). Falta cargar
   **precios reales de proveedor** al rastreador para pasar de "demanda interesante" a margen por venta.
   Opción internacional: CJ Dropshipping tiene API abierta (no hace falta Shopify).
   ⚠️ Preguntar siempre al proveedor por **envío neutro/sin marca** (si el paquete llega con la marca
   de otro, se rompe la confianza que es nuestro diferenciador) y declarar la **transferencia de datos
   personales** al proveedor en la política de privacidad (solo nombre, dirección y teléfono; nunca pago).
5. **Motor de tienda**: catálogo/variantes/carrito/órdenes + checkout de carrito + correos + centro de pedidos.
6. **Legales de tienda**: privacidad, condiciones, **envíos** y **devoluciones/retracto**.
7. **Anuncios** con el pipeline de `ads/` y publicación sostenida.

---

## 7. Cómo arrancar (próximo Kiro)

1. Lee este documento y `.kiro/steering/montaguth.md`.
2. Sincroniza `main` y mira los PRs abiertos antes de asumir nada.
3. Si necesitas el `LINK_SECRET` (tablero/entregas), pídeselo al dueño; **nunca lo dejes escrito en el repo**.
4. Si algo de Stramont hace falta como referencia: `git show stramont-v1.0-final:<archivo>`.
5. Sé su socio honesto: chispa crítica cuando algo no sea lo ideal, pero siempre entregando algo tangible y probado.

¡A vender! 🛒
