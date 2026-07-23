# 🚚 CONTEXTO STRAMONT — Camión de mudanzas (léeme primero)

> **Para el próximo Kiro:** esto te lo escribo yo mismo, la sesión anterior, para que arranques sin perder el hilo. Está escrito como si te lo estuviera contando de viva voz. Léelo completo antes de tocar nada.
> **Para el dueño (usuario):** en el chat nuevo, dile "Lee CONTEXTO-STRAMONT.md antes de empezar" y con eso el próximo Kiro queda al día.
> **Última actualización:** 23 de julio de 2026 (sesión: rediseño TOTAL de la landing + rediseño editorial de la guía). 👉 **El detalle completo de esta sesión está en la nueva sección 2G — léela.**
> **EN PRODUCCIÓN (todo mergeado y desplegado):** tablero interno `informe.html` (2B) · los **3 correos** automáticos vía Resend (2C, 2D) · **Base de correos** (2E) · el **flujo `DESARROLLA`** (10) · **LANDING COMPLETAMENTE REDISEÑADA** de arriba a abajo — hero pantalla-completa con visual antes→después + flecha animada, "El Cambio", "Así funciona", "Por qué confiar", "La base científica", cierre oscuro (2G) · y la **guía-demo de Segmentación con NUEVO look editorial premium** (Fraunces+Inter, íconos Lucide, teal brillante `#2DD4BF`, ámbar secundario) (2G).
> **✅ CERRADO (sesión 23-jul, tarde):** el **PR #115** (fix del drawer móvil borroso) YA está mergeado en `main`. Los **2 pendientes del rediseño de guía TAMBIÉN quedaron listos** (en un PR nuevo): (1) **auto-hospedadas las fuentes** Fraunces+Inter → se embebieron los woff2 en **base64 dentro del `<style>`** de `segmentacion-de-mercados.html` (subsets latin + latin-ext; como son variables, una cara por familia+subset con `font-weight:100 900`); se eliminaron los `<link>` a Google Fonts. **Verificado con Chromium: CERO peticiones externas** → la guía volvió a ser 100% autocontenida. (2) **El chip `metodo-guias.md` YA describe el look editorial nuevo** (teal disciplinado + ámbar, niveles por intensidad del teal, Fraunces/Inter auto-hospedadas, iconografía Lucide `.lic`, sidebar activo, rail protagonista, lección de capas z-index). **Próximo gran pendiente de negocio sigue siendo Wompi (pago real), sección 8.**
>
> **TL;DR (60 segundos) si tienes prisa:** Stramont convierte apuntes en guías interactivas (método CHIP STRAMONT, sección 4). Hay un tablero interno en `informe.html` (sección 2B) donde el dueño gestiona pedidos, y un comando `DESARROLLA <pedido_id>` (sección 10) para que tú armes la guía de un pedido con autonomía. Todo pago sigue en modo simulación (Wompi real es el pendiente #1, sección 8). Regla de oro: nunca push a `main`, siempre rama+PR (sección 6). Si un merge no se refleja en el sitio tras varios minutos, no es caché — revisa GitHub Actions (sección 6.7).
>
> **Regla permanente (pedida explícitamente por el dueño, sección 6.0): este documento se actualiza al final de CADA acción/PR relevante, no solo al cerrar sesión.** Corrige lo que haya que corregir en el momento (fechas, números de PR, qué está en producción vs. pendiente) para que nunca quede desfasado.

---

## 0.5. Cómo trabajamos juntos (léelo para que se sienta como seguir la misma conversación)

El dueño pidió explícitamente (9 jul 2026) que esta sección exista, porque para él lo que hace que un chat nuevo "se sienta como hablar con el mismo Kiro" no es solo el dato técnico — es el **tono, el criterio y la confianza**. Aquí va, de viva voz:

- **El trato es de socio, no de proveedor.** El dueño no quiere que le digas "sí" a todo ni que le vendas humo. Quiere honestidad directa: si algo no es lo ideal, dilo con una **"chispa crítica"** — el porqué, breve y claro — y luego resuelve. Nunca disimules un problema ni digas "está listo" sin haberlo probado de verdad (con Playwright cuando sea interactividad, con `deno check` en Edge Functions, con curl/fetch verificando que algo responde). Cero humo, siempre algo tangible y funcionando.
- **Tienes autonomía y criterio propio, y se espera que los uses.** El dueño ha valorado explícitamente varias veces que yo corrija cosas sin que me las pidiera (ej.: una redundancia en un texto, un dato desactualizado en este mismo documento, un campo del brief que abría un hueco de seguridad). No esperes permiso para hacer lo correcto — hazlo y explica por qué después. Eso incluye ajustar briefs que lleguen mal planteados (ver el punto siguiente).
- **Hay una línea de seguridad que es innegociable y se aplica sin preguntar** (detallada en la sección 2B): nunca exponer llaves/secretos, nunca dar el camino fácil si compromete datos de clientes. Si un brief (tuyo o del otro Kiro) pide algo que rompería esto, se corrige en silencio de ejecución pero se explica con claridad al dueño — nunca se implementa el atajo inseguro "porque lo pidieron así".
- **Trabajas en equipo con OTRA IA — el "Kiro de ideas".** El dueño tiene dos asistentes en paralelo: tú (el programador, el que lee/escribe código, hace PRs, opera Supabase) y otro Kiro que piensa estrategia, precios, textos de marketing y redacta los *briefs* de features (ej.: los tres correos automáticos vinieron así). El dueño actúa de puente: le lleva al otro Kiro lo que tú resolviste, y te trae a ti los briefs que el otro diseñó. **Tu trabajo es ejecutarlos con criterio técnico y de seguridad — no aceptarlos literal si algo está mal planteado.** Ya pasó: el brief del Correo 1 pedía poner el `LINK_SECRET` en el frontend público; se corrigió a un patrón seguro (el navegador manda solo el `pedido_id`) y se le explicó el porqué al dueño para que se lo transmitiera al otro Kiro.
- **El dueño no programa ni tiene acceso a archivos.** Todo lo revisa y aprueba a través de GitHub (PRs) y del propio tablero. Explícale en español sencillo, sin asumir que sabe qué es un merge conflict o un Edge Function — pero sin condescendencia.
- **Ritmo de trabajo real de esta colaboración:** sesiones largas, iterativas, con pruebas reales antes de decir "listo", y con el dueño mergeando rápido cada PR completo. Cuando algo se ve raro tras un merge (el sitio no cambia, un botón no aparece), la respuesta profesional es investigar con evidencia (Actions, `raw.githubusercontent.com`, `deno check`) antes de especular — nunca decir "prueba a refrescar" sin haber mirado primero.
- **Verifica SIEMPRE, por tu cuenta, que un merge se publicó de verdad** (no esperes a que el dueño te avise que algo se ve raro). Después de cada merge: revisa Actions/la API de runs, y si el deploy quedó atascado (`queued` mucho rato) o falló (`failure`/`cancelled` — ha pasado bastante, es degradación transitoria de GitHub, no nuestro código), la reacción automática es crear **una rama nueva** con un commit trivial que dispare un run limpio, nunca reutilizar una rama ya mergeada. El detalle completo está en la sección 6, regla 7.

---

## 1. Quién es el dueño y qué es Stramont

El dueño es estudiante de **Dirección de Ventas** (SENA, Colombia). Stramont convierte apuntes de clase en **guías de estudio interactivas** de alta retención, basadas en ciencia del aprendizaje.

- **Dominio:** `montaguth.institute` (GitHub Pages, sitio 100% estático).
- **Repo:** `12344-ux/12344-ux.github.io`, rama `main` = lo publicado. **Repo público.**
- **Estilo de trato que quiere:** socio honesto y directo, no adulador. Explica el porqué con "chispas críticas". Cero humo, entrega cosas tangibles y funcionando. Ya se acordó con él NO vender datos ni buscar vacíos legales — línea ética firme.
- **Modelo de negocio:** cobra por el **alojamiento/acceso** al documento (no por créditos/SaaS). Planes: **Acceso 10 días ($3 USD)** y **Acceso 30 días ($5 USD, recomendado)**. **Importante (reenfoque de hoy):** los planes YA NO se diferencian por tamaño de archivo. El tope es **45 MB por envío, igual en ambos** (tope técnico discreto, margen bajo el límite duro de 50 MB de Supabase). La diferencia de venta es la **utilidad de aprendizaje** atada al repaso espaciado: 10 días = un ciclo de repaso antes de un examen (hoy / 2 días / 1 semana); 30 días = repasar varias veces en el mes y fijar a largo plazo. El Kit de plantillas es un regalo opcional post-compra. El documento que se genera es un "Comprobante de pago", **no** una factura DIAN.

---

## 2. Qué pasamos en la sesión de hoy (3 de julio) — en orden

Arranqué retomando un hilo que venía de antes: ya existía el método **CHIP STRAMONT** en steering y una primera reconstrucción de la guía-demo de Segmentación de Mercados. Esto fue lo que hicimos hoy, en orden:

1. **El dueño trajo el CHIP STRAMONT versión definitiva** (más exigente que la anterior): flashcards de **escritura** real (no "pensar y revelar" pasivo), control Express/Dominar que tiene que ser **funcional de verdad** (no decorativo), obligación de encontrar "LA joya" del tema (el insight que unifica varios conceptos), bloques visuales obligatorios (tablas, cuadrículas, mapas visuales — nada de todo-texto), y rigor factual (atribuciones con matiz, "se le suele atribuir a...", nunca como certeza absoluta).

2. **Reescribí `.kiro/steering/metodo-guias.md`** con esa versión definitiva (PR #52, ya mergeado) y **reconstruí por completo** `segmentacion-de-mercados.html` (la guía-demo pública que se ve desde la home) para cumplirla al 100%: 14 flashcards de escritura con `localStorage`, Express/Dominar con JS real (clase en `<body>`), tabla comparativa de los 4 tipos, FODA como cuadrícula 2×2 real, widgets numéricos, mapa de conexiones en SVG. Todo esto lo **probé con Playwright** (instalé Chromium headless en el sandbox, tuve que parchear librerías del sistema a mano porque `dnf` fallaba con el paquete `nss`) simulando clics reales en el navegador, no solo mirando el código.

3. **El dueño detectó que la captura de la home (`guia-segmentacion.jpeg`) no reflejaba el contenido nuevo** — seguía mostrando solo el encabezado, que casi no cambió visualmente. Lo arreglé (PR #53): generé una captura nueva con Chromium mostrando tabla + FODA + mapa visual, los 3 bloques que sí distinguen la versión nueva.

4. **Encargo real de un cliente:** el dueño me pidió ubicar a un cliente llamado **Lucho Díaz** (correo `maicolrios.0802@gmail.com`) que ya había pagado el plan de $3 y subido sus apuntes a Supabase. Lo encontré en el bucket `apuntes` (carpeta `maicolrios.0802_gmail.com`, 5 fotos), descargué y leí las fotos (tema: **"La Empresa"** — recursos, estructura organizada, ciclo de vida, PESTEL, áreas funcionales, propósito, misión/visión/valores, creación legal). Construí su guía completa aplicando el CHIP STRAMONT, con una joya bonita: "empresa" viene del latín *in+prehendere* ("agarrar/tomar un riesgo"), que conecté directamente con una frase que el propio Lucho escribió en sus apuntes sobre el riesgo de ser empresario. La subí al bucket privado `guias` como `la-empresa-lucho-diaz.html` y generé el link firmado (10 días, según su plan). **Esta guía NO tiene muro de correos** (el muro es solo para la demo pública de la home; las entregas reales a clientes van directas).

5. **El dueño pidió un bloque nuevo en `simulacion.html`, Paso 4** (la pantalla de "¡Pago confirmado!"): un formulario opcional para que el cliente cuente para qué va a usar la guía, qué le cuesta, y alguna instrucción puntual. Lo construí (PR #54) — mismo estilo de tarjeta que el bloque del Kit, envío separado a FormSubmit (sin tocar ni duplicar la notificación de compra existente), "Omitir" que solo oculta el bloque. Probado con Playwright: orden correcto en el DOM, payload exacto, no duplica nada, botón Omitir funciona. También agregué la sección **§2.5** al método en steering: cuando un pedido venga con instrucciones del cliente, se tratan como capa de prioridad sobre el método (ajustan el modo por defecto Express/Dominar y el énfasis en ciertos conceptos), **nunca como reemplazo** del método base. Ver sección 5 de este documento para el detalle.

6. **Nos encontramos con un susto real:** después de mergear el PR #54 (y el #53 antes), el dueño refrescaba la página una y otra vez y los cambios no aparecían en `montaguth.institute`. Investigué a fondo (comparé el código en `main` vía `raw.githubusercontent.com` contra lo que servía el dominio en vivo, revisé headers `last-modified`/`etag`, y finalmente los logs de GitHub Actions) y encontré la causa real: **el deploy de GitHub Pages estaba fallando** con el error genérico `Deployment failed, try again later` — dos veces seguidas. No era nuestro código, ni la configuración del repo (que estaba perfecta: fuente `main`, dominio verificado). Era una degradación puntual de la infraestructura de GitHub. Probamos un "Re-run" manual que se quedó atascado en cola más de 6 minutos, así que en vez de seguir esperando, hice un commit nuevo (PR #56) que disparó un run de deploy limpio — **y ese sí funcionó**. Confirmé en vivo que el sitio ya sirve el bloque de instrucciones correctamente.

**Aprendizaje para la próxima vez que esto pase:** si mergeas un PR y el sitio no se actualiza después de esperar un rato razonable (varios minutos), no es necesariamente caché del navegador. Revisa `https://github.com/12344-ux/12344-ux.github.io/actions` — si ves una ❌ roja en "pages build and deployment", es un fallo de deploy (a veces del lado de GitHub, no nuestro). La solución más confiable es un commit nuevo pequeño (no un "Re-run", que puede quedarse atascado) para disparar un intento limpio.

---

## 2B. Sesión del tablero interno (3 de julio, más tarde) — TODO ESTO YA ESTÁ EN PRODUCCIÓN

El dueño reportó que `informe.html` daba **404** al meter la key. Eso destapó que el tablero interno existía como HTML pero **la Edge Function que lo alimenta nunca se había desplegado**. A partir de ahí construimos el sistema de gestión completo. Todo está mergeado, desplegado y probado con Playwright. En orden:

### Qué se construyó (PRs #58 a #66)

1. **Tabla `pedidos`** (Supabase, SQL versionado en `supabase/migrations/`). Registra cada compra: `pedido_id` (único), correo, nombre, tema, plan, dias_acceso, `carpeta_storage`, fecha_compra, `guia_entregada`, `fecha_entrega`, `tamano_apuntes_mb`, `apuntes_borrados`. **RLS: solo INSERT con la llave pública (anon), sin lectura pública** (contiene correos de clientes).

2. **Fix de colisión de carpetas (crítico).** Antes, la carpeta de subida en `simulacion.html` era solo el correo → dos compras del mismo cliente se mezclaban. Ahora cada pedido genera un `pedido_id` con formato **`P{dias}-{yymmdd}-{azar}`** (ej. `P30-260703-6iu8`; el plan va primero para que sea legible aunque el dashboard de Supabase trunque el nombre) y la carpeta es **`correo/pedidoId`**. Este aislamiento por pedido es la base de seguridad del borrado (ver abajo). El `pedido_id` viaja en el correo de aviso.

3. **Tabla `pedido_intake`** (RLS insert-only igual que pedidos). Guarda las respuestas del cuestionario opcional del Paso 4 (para qué la usa / qué le cuesta / algo puntual). Antes solo iban por correo; ahora se ven ordenadas en el detalle del pedido en el tablero.

4. **Edge Function `informe`** (`supabase/functions/informe/index.ts`). **Es el cerebro del tablero.** Usa `SUPABASE_SERVICE_ROLE_KEY` solo del lado del servidor (nunca en el navegador) y se protege con el **mismo `LINK_SECRET`** que la función `entrega`. Decisión de diseño clave: NO se da lectura pública a `pedidos` ni `list()` del bucket a la llave pública (esa llave es pública → cualquiera podría enumerar correos de clientes). Modos (todos con `?key=LINK_SECRET`):
   - `GET ?key=` → informe completo: uso del bucket `apuntes` vs 1 GB, lista de pedidos (con intake unido y flag `es_prueba`), alertas de +48h sin entregar, y ventas 15/30 días.
   - `POST ?entregada=1/0&pedido_id=` → marca/desmarca la guía como entregada.
   - `POST ?liberar=1&pedido_id=` → borra **solo los archivos de Storage** de ese pedido (conserva el registro). Candados: solo si `guia_entregada=true`, y la carpeta debe ser `correo/pedidoId` (nunca la carpeta completa de una persona).
   - `POST ?delete=1&pedido_id=` → borra el pedido completo (registro + intake + archivos) **solo si es de prueba**.

5. **`informe.html` — el tablero interno.** Uso interno, no enlazado en la navegación, `noindex`. Pide el `LINK_SECRET` en pantalla (no se guarda). Muestra: barra de capacidad del bucket, resumen de ventas (excluye pruebas), y lista de pedidos (más nuevo primero). **Cada fila es clickeable** → panel de detalle con todos los datos + el cuestionario + botones: "✓ Marcar guía como entregada" (verde, reversible), "🧹 Liberar apuntes de Storage" (habilitado solo si ya está entregada; muestra "Liberados el [fecha]"), y "🗑 Eliminar pedido de prueba" (solo en pruebas).

6. **Reenfoque de planes** (`simulacion.html`): el tamaño dejó de ser diferenciador; ambos planes 45 MB. Los textos venden repaso espaciado / retención. `data-limit` del plan de 10 días pasó de 15 a 45. `privacidad.html` alineó "Estándar/Premium" → "Acceso 10/30 días".

7. **Correos al mínimo (buzón limpio).** El dueño gestiona desde el tablero, así que ahora solo llegan **2 correos**: (a) aviso de compra simplificado ("nueva compra, pedido X, revisa el tablero" — sin volcado de datos) y (b) el de captación de la guía demo. Se **eliminó** el correo del cuestionario (ahora vive en el tablero). El Kit sigue yendo al **comprador** (no al buzón del dueño).

8. **Correo dedicado de pruebas: `pruebasmontaguth@gmail.com`.** La función `esCorreoPrueba()` (misma regla en `simulacion.html` y en la Edge Function) reconoce: ese correo, cualquiera que empiece por `prueba`, o dominios `example.com` / `.test`. Un pedido de prueba: (a) **no cuenta como venta** en el tablero, (b) se marca con 🧪, (c) **no genera ningún correo** al comprar, (d) es borrable con el botón de eliminar. Un pedido **real nunca cumple esto**, así que el borrado no lo puede tocar (candado de seguridad, no solo convención).

### La regla de seguridad permanente que dio el dueño

**"NUNCA comprometer la seguridad con llaves/claves/secretos; si el camino directo expone algo sensible, buscar SIEMPRE otra vía; explicar el porqué; jamás implementar el atajo inseguro en silencio."** Ya está guardada como learning global. Se aplicó de hecho: por eso el tablero lee vía Edge Function con service_role del lado del servidor (nunca dando lectura pública a la llave anon), y por eso NO se hizo el repo privado (ver abajo).

### Decisión sobre repo privado (NO hacerlo)

El dueño preguntó si volver el repo privado permitiría un botón de borrado "más fácil". Se investigó y se descartó con datos: en el plan gratuito, poner el repo privado **despublica el sitio** (Pages en repos privados requiere Pro); y aun pagando, el sitio de Pages sigue siendo **público** salvo Enterprise Cloud. Además, esconder el código no es seguridad real (el JS se sirve al navegador igual). La conclusión: el borrado seguro se logra server-side + `LINK_SECRET`, sin gastar ni exponer nada.

### Cómo se opera el tablero (para el dueño y el próximo Kiro)

- Se entra a `montaguth.institute/informe.html` con el `LINK_SECRET`.
- Flujo real de un pedido: llega compra → aparece "Pendiente" (amarillo) → a las 48h sin entregar se pone rojo "sin procesar" → el dueño hace la guía, la entrega, y marca "✓ entregada" (pasa a verde) → cuando ya no necesita los apuntes crudos, "🧹 liberar apuntes" (libera el 1 GB, conserva el registro).
- **Convención de pruebas:** para probar sin ensuciar datos ni buzón, usar siempre `pruebasmontaguth@gmail.com`.

### Los sustos de deploy (recurrente)

Volvió a pasar varias veces que un merge dejaba el deploy de GitHub Pages fallando o cancelado (degradación transitoria de GitHub, no nuestro código). **Aprendizaje reforzado:** mergear **de a un PR** (esperar verde antes del siguiente — mergear dos seguidos cancela el primero y roza el fallo); si el sitio no refleja el cambio, revisar Actions y disparar un **commit trivial** de deploy limpio (no "Re-run"). PRs de deploy limpio usados hoy: #56, #60, #63, #66.

### Pasos manuales de Supabase (NO se automatizan solos con el merge)

Cuando un PR toca la tabla o la función `informe`, tras mergear hay que, en el dashboard de Supabase: (1) correr el SQL nuevo en **SQL Editor**, y (2) **redeploy** de la Edge Function `informe` (Edge Functions → informe → Code → pegar el código → Deploy). El deploy de GitHub Pages solo publica el HTML; Supabase es aparte. La función `informe` requiere que "Verify JWT" esté **apagado** (usa `LINK_SECRET` propio).

---

## 2C. Correos automáticos (Resend) y flujo de baja fricción — EN PRODUCCIÓN

### Infraestructura de correo
- Se usa **Resend** (dominio verificado `send.montaguth.institute`). La `RESEND_API_KEY` vive SOLO en Supabase Secrets; ninguna función la expone. Remitente: `Montaguth Institute <notificaciones@send.montaguth.institute>`. **Reply-To:** `contacto@montaguth.institute` (las respuestas caen en el Zoho del dueño; probado).
- Patrón de seguridad (aprendido en el Correo 1): **NUNCA** poner el `LINK_SECRET` en `simulacion.html` (es público → se filtraría). Regla general: si un correo lo dispara el **cliente anónimo** (página pública), la función recibe SOLO el `pedido_id` y saca el correo/datos de la BD server-side (no del navegador) → nada de relay de spam abierto. Si lo dispara el **dueño desde el tablero** (autenticado), la función SÍ exige `LINK_SECRET`.

### Correo 1 — Confirmación de compra (`correo-confirmacion`)
- Se dispara solo desde `simulacion.html` (Paso 4) tras registrar el pedido. Envía SOLO `{pedido_id}`; la función envía al correo guardado del pedido, **una sola vez** (columna `correo_confirmacion_enviado`). Verify JWT **off**.

### Correo 2 — Entrega de la guía (`correo-entrega`)
- Lo dispara el DUEÑO desde el tablero → **exige `LINK_SECRET`** (`?key=`). Body `{pedido_id, archivo, tema?}`. Valida que la guía exista en el bucket `guias`, genera el enlace firmado **reusando la MISMA firma HMAC que la función `entrega`** (no se reinventó; probado que coinciden), envía el correo con el enlace privado, y marca el pedido: `guia_entregada`, `fecha_entrega`, `guia_archivo`, `correo_entrega_enviado`. Idempotente. Verify JWT **off**.
- En el tablero, en el detalle del pedido: sección **"Entrega de la guía"** con campo del nombre del archivo + **Vista previa** (reusa el modo `mint` de `entrega`, enlace de 1 día) + **Entregar**. El viejo "marcar entregada" quedó como override manual (sin enviar correo).
- **CAMBIO DE COPY (sesión Wompi):** en la invitación a Instagram se **quitó** "Estás entre las primeras personas que estudian con Stramont"; ahora dice **"Si quieres acceder a contenido exclusivo, síguenos en Instagram"** y, **después del enlace**, "Nuestro equipo evaluará tu solicitud." (implica IG con solicitudes revisadas). Cambiado en las DOS versiones del correo (`construirTexto` y `construirHtml`), validado con `deno check`. ⚠️ **REQUIERE REDEPLOY MANUAL de la Edge Function `correo-entrega` en Supabase** (el merge al repo NO despliega la función; hay que pegar el código en Edge Functions → correo-entrega → Deploy, Verify JWT OFF).

### Correo 3 — Opinión/calificación (`correo-feedback` + `feedback`): **CONSTRUIDO, pendiente de deploy manual.** Ver sección **2D**.

---

## 2D. Correo 3 — Opiniones / feedback (EN PRODUCCIÓN)

El brief lo diseñó el "Kiro de ideas"; se ejecutó con una corrección de seguridad importante (ver abajo). Es un sistema de 3 piezas: **correo con un botón → página de opinión → banco de opiniones en el tablero.** Ya está desplegado y probado punta a punta. **Lee la nota de entregabilidad más abajo** (por qué el correo pasó de 5 estrellas-enlace a un solo botón).

### Qué se construyó
1. **Migración `pedido_feedback`** (`20260709160000_...`): una fila por pedido (rating 1-5, comentario, permiso_publicar, nombre_mostrar, es_prueba, fechas). **RLS activado SIN ninguna policy pública** (ni lectura ni insert).
2. **Migración columnas en `pedidos`** (`20260709160100_...`): `feedback_token` (único, se genera al enviar el Correo 3), `correo_feedback_enviado` (idempotencia), `recordatorio_enviado` (reservado fase 2, sin usar).
3. **Edge Function `correo-feedback`** (admin, EXIGE `LINK_SECRET`): la dispara el dueño desde el tablero. Genera el `feedback_token` si falta, arma el correo con **un solo botón "Dejar mi opinión"** (enlace `feedback.html?pid&t`, sin `r`), lo envía por Resend y marca idempotencia. Nombre de pila = primera palabra de `nombre`, con fallback "Hola,". Pruebas 🧪 se pueden enviar (asunto `[TEST]`). **Idempotencia estricta: se pide UNA sola vez por pedido, nunca se reenvía** (decisión de marca del dueño: la opinión es opcional, insistir sería presión/acoso).
4. **Edge Function `feedback`** (PÚBLICA, Verify JWT **off**): la llama `feedback.html`. Valida `pid`+`token` contra `pedidos.feedback_token` y escribe con service_role (upsert por pedido_id). `action:"rate"` (rating 1-5) y `action:"comment"` (comentario + permiso/nombre solo si rating≥4).
5. **`feedback.html`** (pública, `noindex`, premium oscuro, neutro en género): registra la estrella al llegar, textarea de comentario, permiso de testimonio solo en notas 4-5, mensaje distinto en 1-3, estados de éxito/enlace-inválido.
6. **Tablero `informe.html`**: nueva sección **"Banco de opiniones"** (separada de la lista de pedidos) con pulso (promedio + total, solo reales), filtros 4-5 / 1-3, y tarjetas con badge "✓ dio permiso". Marcador ★ en los pedidos con opinión, aviso "listo para pedir opinión" y, en el detalle, la sección de envío del Correo 3 con umbral por plan y override de emergencia.

### La corrección de seguridad al brief (chispa crítica)
El brief pedía que `pedido_feedback` tuviera RLS "igual que `pedido_intake`" (insert abierto a la llave pública). **Eso abriría un hueco:** una policy de insert público NO valida el token, así que cualquiera podría inyectar opiniones falsas para pedidos ajenos. Se hizo bien: la tabla NO tiene policies públicas y **toda** opinión entra por la Edge Function `feedback`, que valida el token server-side. Queda más cerrado que `intake`.

### Entregabilidad: por qué el correo es de UN solo botón (chispa crítica)
La v1 del brief ponía **5 enlaces de estrella** en el correo (uno por nota, para calificar "de un clic"). Al probarlo, el Correo 3 **llegó pero cayó en "Promociones" de Gmail** (no en la bandeja principal, sin notificación), mientras que los Correos 1 y 2 (transaccionales, un solo botón) sí entran a la bandeja. Causa: 5 enlaces casi idénticos + asunto de "¿qué te pareció?" = patrón promocional para Gmail. **Fix:** el correo pasó a **un único botón "Dejar mi opinión"** (transaccional, como el 1 y 2); las estrellas del correo quedaron solo decorativas (no enlaces) y la calificación se elige en `feedback.html` al abrir. Se pierde el "un clic" literal (ahora es abrir → tocar estrella), pero se gana llegar a la bandeja. Esto obliga a **redeploy de `correo-feedback`**.

**Decisión de marca (importante):** NO existe reenvío del Correo 3. La opinión es opcional y se pide una sola vez; reenviar/insistir se sentiría como acoso u obligación, contra la voz de Stramont. Si se propone un "recordatorio" a futuro, chocaría con esta línea — no implementarlo sin que el dueño lo pida explícitamente. (La columna `recordatorio_enviado` existe reservada, pero queda SIN usar por esta misma razón.)

### El disparador: "manual asistido" (v1)
Lo envía el dueño desde el tablero (como el Correo 2). El aviso "listo para pedir opinión" se enciende cuando: guía entregada + pasó el umbral de días según plan (**10 días → 3 días; 30 días → ~10 días**, parametrizable en `informe.html` sin redeploy) + no es prueba + no se envió antes + aún no hay opinión. Se puede enviar antes del umbral (confirmación de override). Las funciones están hechas para que un **cron** las llame en el futuro (fase 2) sin rehacer nada; el cron NO se construyó.

### CHECKLIST DE DEPLOY MANUAL EN SUPABASE (obligatorio, el merge NO lo hace)
> **Para la actualización de entregabilidad (correo de un solo botón):** basta con **redeploy de `correo-feedback`** (paso 2) tras mergear; el resto ya está desplegado. Lo de abajo es el checklist completo (útil para un deploy desde cero).
1. **SQL Editor** → correr las 2 migraciones nuevas (en orden): `20260709160000_crear_tabla_pedido_feedback.sql` y `20260709160100_pedidos_feedback_columnas.sql`.
2. **Edge Functions** → crear/deploy `correo-feedback` (**Verify JWT OFF**, igual que `correo-entrega`). La seguridad la da el `LINK_SECRET` que se valida DENTRO del código; el tablero la llama con `?key=` y SIN cabecera de autorización, así que con JWT ON daría 401. (Corrección: una versión anterior de este doc y del PR #82 decían "JWT ON" por error.)
3. **Edge Functions** → crear/deploy `feedback` (**Verify JWT OFF** — la autoriza el token del pedido, igual que `correo-confirmacion`).
4. **Edge Functions** → **redeploy de `informe`** (se le añadió el bloque de opiniones).
5. Secretos: no hay nuevos. Reutiliza `LINK_SECRET`, `RESEND_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
6. Prueba con `pruebasmontaguth@gmail.com`: entrega una guía de prueba → en el detalle usa "Pedir opinión" → abre el correo, califica → verifica que aparece en el Banco de opiniones marcada 🧪 (no cuenta en el promedio).

---

## 2E. Base de correos (Frente A) — CONSTRUIDO, pendiente de deploy manual

Registro **operativo** (no marketing) de todos los correos capturados. Parte de un brief grande de 3 frentes (A base de correos, B rediseño de guías + chip, C rediseño de landing); este es el Frente A.

### Qué se construyó
1. **Migración `correos`** (`20260709170000_...`): tabla con `correo`, `origen` (default `prospecto_demo`), `es_prueba`, `creado`, único `(correo, origen)`. **RLS activado SIN policies públicas** (igual que `pedido_feedback`): la llave pública no lee ni inserta.
2. **Edge Function `captura`** (PÚBLICA, Verify JWT **off**): la llama el muro de la demo. Valida formato de correo, **rate-limit básico por IP en memoria (NO guarda IPs** — decisión de privacidad), dedupe idempotente (upsert `onConflict correo,origen ignoreDuplicates`), fija `origen` a valores conocidos, marca `es_prueba`.
3. **`informe` (función)**: nuevo `GET` devuelve `baseCorreos` (une prospectos de `correos` + clientes de `pedidos`, deduplica por correo — si un prospecto compró aparece como cliente —, excluye pruebas) y nuevo modo `POST ?correo_delete=1&id=` para borrar un prospecto.
4. **`informe.html`**: sección **"Base de correos"** (separada, como "Banco de opiniones") con pulso (prospectos + clientes reales), lista `correo · tipo · fecha` y 🗑 solo en prospectos.
5. **`segmentacion-de-mercados.html` (muro de la demo)**: al enviar, además de FormSubmit dispara la captura a Supabase **sin romper nada** (`fetch` con `keepalive`, sin `preventDefault`, en try/catch). La **casilla obligatoria** de consentimiento se cambió por una **microlínea** con enlace a la política (menos fricción; el pre-pago de `simulacion.html` ya tiene su casilla que cubre a los clientes). `privacidad.html` ya dice que el correo es solo para entregar/novedades y que nunca se vende.

### Seguridad (mismo criterio de siempre)
La captura NO es inserción pública directa (evita inundación de correos falsos), igual que se cerró en `pedido_feedback`. Todo pasa por la función server-side. No se guardan IPs (el rate-limit es en memoria, best-effort).

### CHECKLIST DE DEPLOY MANUAL (tras mergear el Frente A)
1. **SQL Editor** → correr `20260709170000_crear_tabla_correos.sql`.
2. **Edge Functions** → crear/deploy **`captura`** (**Verify JWT OFF**).
3. **Edge Functions** → **redeploy de `informe`** (se le añadió `baseCorreos` y el borrado de correos).
4. Secretos: ninguno nuevo.
5. Prueba: abre la demo con un correo `prueba...@...` → debe aparecer en "Base de correos" como prospecto 🧪 (excluido del conteo real); compra de prueba → aparece como cliente.

### Pendiente del mismo brief (siguientes PRs)
- **Frente B:** rediseño visual de las guías (look "tablero de estudio": nav lateral + rail "Activa tu aprendizaje" + top bar con progreso/tiempo) + actualizar el chip + rehacer la demo de Segmentación. Conservar SIEMPRE: color con significado (teal/índigo/bronce), Express/Dominar y "generar antes de revelar". Quitar progreso guardado y botones descargar/compartir.
- **Frente C:** landing — "El Cambio" ✅ TERMINADA (ver C1 arriba). Falta el **hero (C2)**: HTML/CSS real, dos columnas (texto izq + visual antes→después der), fondo oscuro premium, eyebrow teal, CTA sólido, "⚡ Entrega en menos de 24 horas" (sin "+150 estudiantes"). Mantener la alternancia claro/oscuro.

---

## 2F. Frente B — Rediseño de guías "tablero de estudio" (APROBADO · ES EL ESTÁNDAR)

Brief grande de 3 frentes (A base de correos ✅, B guías ✅, **C landing EN CURSO** — "El Cambio" ✅ TERMINADA, **hero (C2) pendiente = próximo foco**). El dueño **aprobó** el rediseño de las guías (lo revisó en móvil y PC). Ahora es el **estándar**: `segmentacion-de-mercados.html` es el **esqueleto de referencia** y el chip `.kiro/steering/metodo-guias.md` ya está actualizado (§5.5 layout tablero + rail inteligente + flashcards sin localStorage + tablas responsivas + glosario). Ante "hazle la guía a tal cliente", se construye con este layout automáticamente.

### Qué se hizo (solo la demo, es rediseño visual, NO motor nuevo)
- **Layout de 3 columnas:** barra superior (logo, título, tiempo estimado, **progreso honesto de scroll** — sin estado guardado), **nav lateral** por secciones (Introducción · Conceptos clave · Ejemplos reales · Preguntas de práctica · Plan de repaso · Glosario; hamburguesa + drawer en móvil), y **rail derecho "Activa tu aprendizaje"** que en móvil se vuelve **barra inferior plegable**.
- **RAIL INTELIGENTE (la decisión pivote, opción A):** muestra la pregunta de recuerdo activo de la **sección visible** (scroll-spy con `IntersectionObserver`); las 14 flashcards se movieron del inline a `data-q`/`data-a` en cada ficha y las surface el rail.
- **Se conservó lo sagrado:** color con significado (teal N1 / índigo N2 / bronce N3), **Express/Dominar** funcional, y **"generar antes de revelar"**.
- **Cambio respecto al método actual:** las flashcards ya **NO usan `localStorage`** ("sin memoria" entre visitas, como pidió el brief; en sesión sí conserva lo escrito al hacer scroll). El chip habrá que ajustarlo en esa línea si se aprueba.
- **Tablas → responsivas** (tabla en PC, tarjetas apiladas en móvil, vía `table.responsive` + `data-label`). Caso práctico como **flujo horizontal**. Callouts de **"término clave"**. **Glosario** nuevo.
- **Quitado:** progreso guardado tipo "68% completado", botones descargar/compartir. Muro con **microlínea corta** (incorpora el intent del PR #87, que se puede cerrar).
- **Probado:** `node --check` + jsdom (rail cambia de pregunta por sección, flashcard exige escribir antes de revelar, Express/Dominar, 2 tablas responsivas, sin `localStorage`).

### Estado
- ✅ Demo rehecha (PR #88, mergeado) y **aprobada**.
- ✅ Chip actualizado (PR 2): §5.5 "Layout tablero de estudio" + rail inteligente + flashcards sin localStorage + tablas responsivas + glosario + "sin progreso guardado / sin descargar-compartir". Toda guía nueva se hace así, copiando `segmentacion-de-mercados.html` como esqueleto.
- **Frente C1 — sección "El Cambio" (index.html): ✅ TERMINADA Y PULIDA (mergeada).** Tras varias iteraciones con el dueño, quedó así: estructura **narrativa antes→después en 2 etapas** (no zig-zag), clases `cx-*` (ya NO `c2-*`/`cambio2`): 
  1. **Etapa "Sin Stramont"** (gris **pizarra**, on-brand — el rojo se descartó por cliché y por estar fuera de paleta): una **foto ÚNICA real de apuntes desordenados** (`apuntes-cliente.jpg`) enmarcada con borde azul `#0B1220`, que al **hacer clic abre una vista previa ampliada (lightbox** `.cx-lightbox`/`.cx-lb-frame`, cierra con fondo/✕/Esc); debajo, los 5 puntos-dolor como **tarjetas** (`.cx-points-bad`, barra de acento pizarra + ícono en círculo). 
  2. **Flecha de transición** "Y en esto los convertimos ↓". 
  3. **Etapa "Con Stramont"** (teal): la **captura de la guía GRANDE como showcase protagonista** dentro de un marco tipo ventana de app (`.cx-window`, clicable, abre la guía), los 5 beneficios como **tarjetas teal**, las stats (6·14·7·24) y un **CTA grande** "Abrir la guía completa". 
  - **Fondo trabajado** full-bleed sutil detrás de `#cambio` (micro-grid de puntos + wash teal/índigo + máscara que lo funde con la banda). Las tarjetas van en **grilla de 2 columnas con la 5ª a todo el ancho** (resuelve la paridad impar). Todo CSS/JS autocontenido en `index.html` (NO toca `estilos.css` → sin cache-bust).
  - **PRs de esta saga (todos mergeados):** #93 showcase · #94 v2 · #95 foto real (bajada de Supabase con el correo de pruebas) · #96 tarjetas · #97 rojo→pizarra · #98 marco azul+hover (el hover se quitó después) + tooltip móvil de la guía · #99 lightbox · #100 marco del lightbox que cubre perfecto. **La foto correcta es `apuntes-cliente.jpg`** (apuntes de Segmentación de verdad desordenados); `apuntes-reales.jpeg` y `apunte-seg-1/2/3.jpg` quedaron SIN uso (candidatas a limpiar en un PR aparte).
  - **Assets vivos:** `apuntes-cliente.jpg` (el "antes") y `guia-segmentacion-nueva.jpg` (la guía, "después").
- **CÓMO REGENERAR CAPTURAS DE LA GUÍA (tooling — importante, no está en un sandbox nuevo):** las capturas se hacen con **Playwright + Chromium headless**. En una sesión nueva hay que reinstalar (y `/projects/sandbox/pw` NO persiste): `cd /projects/sandbox/pw && npm i playwright-core@1.47` y `PLAYWRIGHT_BROWSERS_PATH=/projects/sandbox/pw/browsers npx playwright@1.47 install chromium`; **instalar fuente de emojis** o salen cuadritos □: `dnf install -y google-noto-emoji-color-fonts`. Script: `chromium.launch({args:['--no-sandbox']})`, `goto('file:///projects/sandbox/12344-ux.github.io/segmentacion-de-mercados.html?ok=1')` (el `?ok=1` quita el muro), viewport ~1360×850 `deviceScaleFactor:2`, hacer scroll a `#f01` (para que el rail muestre una pregunta) y `screenshot`. Para verificar "El Cambio" se capturó el elemento `#cambio` a 1300px (escritorio) y a 390px (móvil). Solo la imagen final va al repo; el navegador y node_modules quedan fuera.
- **Frente C2 — Hero (rediseño): PENDIENTE (lo último del brief).** Rehacer el hero en HTML/CSS real (NO incrustar PNG de IA), dos columnas (texto izq + visual antes→después der), fondo oscuro premium, eyebrow **teal** (no ámbar), CTA sólido de alto contraste, y "⚡ Entrega en menos de 24 horas" (**sin** "+150 estudiantes", es falso hoy). Se puede generar la captura vertical de la guía con el tooling de arriba y reutilizar una `apunte-seg-*.jpg` para el antes→después → **no está bloqueado**, solo faltó luz verde del dueño para arrancarlo. Mantener la alternancia intencional claro/oscuro de la landing.

---

## 10. Flujo de BAJA FRICCIÓN para desarrollar guías (comando `DESARROLLA`)

Para no repetir contexto por chat con muchos pedidos, se montó esto:

- **Palabra clave (candado de seguridad del dueño):** el dueño escribe **`DESARROLLA <pedido_id>`** (o *elabora/trabaja/haz*) para ordenarme construir esa guía. **Un `pedido_id` suelto SIN palabra clave = NO tocar nada** (solo mirar/preguntar). Esto evita que trabaje sobre lo que no debe.
- **Nota interna por pedido:** en el tablero, el detalle tiene un campo **"Nota para la guía (interna)"** (columna `nota_interna`, nunca se muestra al cliente). El dueño escribe ahí sus instrucciones ("enfócale PESTEL", etc.) y viajan pegadas al pedido, no por chat.
- **Modo `material` (el que me quita la fricción):** `GET ?material=1&pedido_id=XXX&key=LINK_SECRET` en la función `informe` devuelve en UNA llamada: datos del cliente + cuestionario (intake) + `nota_interna` + **enlaces de descarga FIRMADOS (1h) de cada apunte** del bucket `apuntes`. Protegido por `LINK_SECRET`.

**Cómo lo ejecuto yo (próximo Kiro), ante "DESARROLLA <pedido_id>":** pido el `LINK_SECRET` (una vez por sesión) → llamo `informe ?material=1&pedido_id=...` → descargo y leo los apuntes → construyo la guía con el método CHIP STRAMONT (teniendo en cuenta el cuestionario y la `nota_interna`) → la subo al bucket `guias` con `entrega ?upload=1&f=<nombre>.html&key=...` → le digo al dueño el nombre del archivo para que en el tablero le dé **Vista previa** y **Entregar**. (La entrega/decisión final siempre la hace el dueño, es el control de calidad.)

---

## 2G. Sesión del 23 de julio — REDISEÑO TOTAL de la landing + rediseño editorial de la guía

Sesión larga y muy visual. Dos grandes frentes, ambos guiados por mockups de la "IA de diseño" que el dueño trae, y ejecutados con criterio (corrigiendo lo que chocaba con la marca). **Todo lo de landing YA está mergeado y en producción; el rediseño de la guía también, salvo el fix final del drawer (#115) que quedó pendiente de merge al cerrar el chat.**

### A) LANDING completa (todos los frentes cerrados, PRs #93–#109)
La landing (`index.html`) se rediseñó de arriba a abajo. Todo el CSS va **autocontenido en `index.html`** (clases `hx-*` hero, `cx-*` El Cambio, `hf-*` Así funciona, `pc-*` Por qué confiar, `sci-*` La base científica, `cc-*` cierre); **NUNCA se toca `estilos.css`** (por eso no hubo cache-bust). Secciones, en orden:
- **Hero (C2):** dos columnas — texto izq + **visual antes→después** der (foto de apuntes `apuntes-hero.jpg` → flecha teal → render de la guía `guia-hero.jpg`, con glow). **Llena la primera pantalla** (`min-height:calc(100vh - 48px)`) y la **flecha de scroll rebota** (animación). CTA sólido teal → `simulacion.html`. Correcciones de marca sobre el mockup: eyebrow en **teal** (no ámbar) y **"⚡ Entrega en menos de 24 horas"** (NO "+150 estudiantes", que es falso hoy). ⚠️ **EL HERO NO SE TOCA** salvo que el dueño lo pida explícitamente — sus dos imágenes (`apuntes-hero.jpg`, `guia-hero.jpg`) NO se regeneran.
- **El Cambio:** narrativa antes→después. Foto real de apuntes desordenados `apuntes-cliente.jpg` — al final quedó **SIN marco, derecha (sin rotación), con viñeta oscura sutil** (se le quitó el marco azul porque parecía "recorte de mala calidad"). Guía como **showcase** en marco tipo ventana de app (usa `guia-segmentacion-nueva.jpg`). Puntos como **tarjetas**; lado "Sin Stramont" en **dorado bronce oscuro `#C48E3A`** (evolución: rojo → gris pizarra → dorado, por gusto del dueño), "Con Stramont" en teal. Hay un **lightbox** al clic en la foto (marco que cubre perfecto, #100).
- **Así funciona:** infográfico — 2 tarjetas claras (pasos 1-2) + tarjeta oscura grande (paso 3, chips + "24h") + banner. **El Kit es de TOMA DE APUNTES** (NO flashcards): se respetó su copy y los mini-íconos son de apuntes.
- **Por qué confiar** (banda clara) + **La base científica** (banda oscura): rediseñadas a tarjetas; citas reales Dunlosky 2013 / Weinstein 2018 conservadas.
- **Cierre:** tarjeta **oscura premium** con glow teal, botón grande **"Necesito mi guía en menos de 24 horas"**, línea blanca separadora arriba. Se **quitó** "Empieza hoy. Recíbela mañana" y "Sin compromiso". **Footer: se eliminó el enlace de Instagram** (regla nueva: el IG solo va en correos, NUNCA en la landing).

### B) GUÍA de Segmentación — nuevo look editorial premium (PRs #110–#115)
Se aplicó **solo a `segmentacion-de-mercados.html`** como prueba aprobada por el dueño. Cambios (todos autocontenidos en la guía, sin tocar `estilos.css`):
1. **Iconografía Lucide inline** (#111): se abandonaron TODOS los emojis (incluidos los mnemotécnicos coloridos 🌍🍕🎯♟️ y FODA) por **SVG de Lucide embebidos inline** (licencia **ISC**, copiados directo — **sin CDN, sin npm, cero dependencias**). Clase única **`.lic`** (`fill:none;stroke:currentColor;stroke-width:1.8`) → cada ícono **hereda el color de su sección**. Atribución Lucide en comentario. **Este es el patrón a seguir para toda iconografía.**
2. **Rediseño editorial** (#112→#113): tipografía de 2 familias — **Fraunces** (serif display) en títulos/énfasis + **Inter** (sans) en el resto (⚠️ HOY cargan desde **Google Fonts** = única dependencia; PENDIENTE auto-hospedar). **Color disciplinado**: un solo acento **teal brillante `#2DD4BF`** (el del hero — el dueño rechazó el verde `#3CA98F` por "pesado") + **ámbar `#C9A24B`** secundario (reservado a: joya, término clave, chispa, ancla, tips). Fondo **azul-navy `#0B1220`**. **YA NO existe teal/índigo/bronce por nivel**: los 3 niveles de profundidad se distinguen por **intensidad del mismo teal** (n1 `#2DD4BF`, n2 `#67E8D6`, n3 `#14B8A6`). Sidebar con **estado activo claro** (barra izquierda teal + tinte + ícono teal). Rail "Activa tu aprendizaje" **protagonista** (cerebro teal, glow propio, foco teal en el input). Textura de fondo (glow radial + grano). Más aire (line-height 1.68).
3. **Rail "Intentar de nuevo"** (#110): la flashcard del rail ya **se puede re-practicar** (antes revelar la respuesta era de un solo uso). Botón `railReset` que oculta la modelo, limpia el input y reinicia.
4. **Tooltip de definiciones `.def`** (#101, sesión previa): `position:fixed` posicionado por JS → funciona con **hover + foco + TAP (móvil)** sin recortarse.
5. **Drawer móvil** (#114 + fix #115): panel elevado (surface + sombra) que se distingue del fondo, **altura completa `100dvh`**, backdrop suave. **Lección de capas (importante):** poner `z-index` a `.app` creaba un contexto que atrapaba el `#sidebar` por debajo del `#backdrop` (body-level) → el `backdrop-filter:blur` lo borroneaba. Fix: **textura del fondo a `z-index:-1`** (detrás de todo) y **`.app` SIN z-index** → el sidebar (190) vuelve al contexto raíz por encima del backdrop (180). **Regla:** cuidado al dar z-index a contenedores; puede atrapar elementos fixed que deben flotar por encima.

### Assets de imagen (ojo con cuáles se tocan)
- `guia-segmentacion-nueva.jpg` (2720×1700, landscape) → **captura de la guía para el showcase de "El Cambio"**; se **regeneró** con el look azul nuevo (con Chromium: viewport 1360×850 dSF2, scroll a `#conceptos`, `?ok=1` quita el muro). Si el look de la guía vuelve a cambiar, **hay que regenerarla** para que la landing "se venda sola".
- `guia-hero.jpg` (portrait) y `apuntes-hero.jpg` → **SON DEL HERO, NO TOCAR.**
- `apuntes-cliente.jpg` → foto real de apuntes desordenados (El Cambio), bajada de Supabase con el correo de pruebas.

### PENDIENTES que dejó esta sesión → TODOS CERRADOS ✅
1. ~~Mergear #115 (fix drawer borroso)~~ → **hecho, ya en `main`**.
2. ~~Auto-hospedar Fraunces + Inter~~ → **hecho**: woff2 embebidos en base64 en el `<style>` de la guía (subsets latin + latin-ext, una cara variable por familia+subset con `font-weight:100 900`); `<link>` de Google Fonts eliminados. Verificado con Chromium (cero peticiones externas, las 4 caras cargan, ē/ō y acentos españoles renderizan con la webfont). **La guía es de nuevo cero-dependencias.**
3. ~~Actualizar el chip `metodo-guias.md`~~ → **hecho**: el chip ya describe el look editorial premium (color disciplinado teal+ámbar, niveles por **intensidad del teal** n1 `#2DD4BF`/n2 `#67E8D6`/n3 `#14B8A6` —ya NO teal/índigo/bronce—, tipografía Fraunces/Inter **auto-hospedada**, iconografía Lucide `.lic` inline sin emojis, sidebar con estado activo, rail protagonista, y la lección de capas z-index). **Toda guía nueva ya nace con el look premium; `segmentacion-de-mercados.html` sigue siendo el esqueleto de referencia a copiar.**
> **Cómo auto-hospedar fuentes en una guía futura (receta):** copia el bloque de `@font-face` de `segmentacion-de-mercados.html` (ya trae Fraunces+Inter en base64). Si algún día cambian los pesos/subsets: baja los woff2 de Google Fonts con un User-Agent de Chrome (devuelve woff2), quédate con los subsets **latin + latin-ext**, y como son variables usa **una sola cara por familia+subset** con `font-weight:100 900` (NO dupliques el base64 por peso, infla el archivo). El `unicode-range` de cada subset se copia tal cual de la CSS de Google.

### Reglas de trabajo REFORZADAS esta sesión
- **SIEMPRE rama nueva + PR por cada cambio.** Solo reusar una rama si el dueño lo dice explícitamente Y no está mergeada. El dueño **mergea muy rápido** → antes de reusar una rama, verificar con `list_pull_requests`; si ya se mergeó, el commit queda huérfano (rescatar: sync main + rama nueva + cherry-pick, o crear rama nueva desde el commit local).
- **GitHub Pages a veces deja el `deploy` en "Queued"** (candado de concurrencia; hay runs zombis viejos). **Se destraba solo esperando un rato** (confirmado). No entrar en pánico ni asumir que es el código.
- **Verificar SIEMPRE con Chromium** (headless en `/projects/sandbox/pw`, reinstalar con `npm i playwright-core@1.47` + `npx playwright@1.47 install chromium`; para emojis instalar `google-noto-emoji-color-fonts`). Cuidado: `read_file` de una imagen puede devolver una versión **cacheada** — si el tamaño en bytes es idéntico al render anterior, forzar nombre de archivo nuevo.

---

## 3. Estado actual del sitio (archivos)

| Archivo | Qué es |
|---|---|
| `index.html` | Landing. Hero oscuro, sección "El cambio" (antes/después), "Cómo funciona", confianza, cierre/CTA. Menú hamburguesa turquesa en móvil (CSS puro). |
| `segmentacion-de-mercados.html` | **Guía-demo pública de referencia**, la que se abre desde "Ver en qué los convertimos" en la home. Reconstruida hoy con el CHIP STRAMONT definitivo: flashcards de escritura, Express/Dominar funcional, tabla/FODA-cuadrícula/mapa-SVG, LA JOYA del tema (graphein compartido + proyectar=pro+iacere). **Tiene muro de correos** (FormSubmit + `localStorage`), porque es la muestra pública para captar leads. |
| `guia-segmentacion.jpeg` | Captura real de la guía anterior, mostrando tabla+FODA+mapa (se usa en la home). |
| `entrega.html` | Visor público e inofensivo del sistema de entregas privadas: lee `?f&exp&sig`, llama a la Edge Function, renderiza la guía real en un `<iframe srcdoc>`. |
| `simulacion.html` | El wizard de compra (4 pasos: plan → carga → pago simulado → éxito). Tiene: bloque de instrucciones opcional en Paso 4 (`#intakeBox`, ahora guarda en `pedido_intake`), generación de `pedido_id`, registro en la tabla `pedidos`, correo de aviso simplificado, y el reenfoque de planes (45 MB ambos). Sigue diciendo "simulación" porque Wompi (pago real) sigue pendiente. **NUEVO:** en el Paso 3 (pago) hay un **bloque "Pago seguro" (Wompi)** + microcopy bajo el botón (logo oficial de Wompi en blanco `wompi-logo.svg` + "Pasarela de pagos de Bancolombia", candado, "Stramont no almacena los datos de tu tarjeta"). El texto afirma procesamiento real: es veraz **en modo producción**; se activa de cara al público junto con el switch de Wompi a producción. **NUEVO:** todos los **emojis se reemplazaron por iconos Lucide inline** (clases `.ic-svg`/`.ic-star`, currentColor), igual que en las guías; quedan a propósito solo el `🛒` del asunto de un correo interno y un `🧪` en un comentario de código (no son UI). **Ajustes posteriores (mismo PR):** (a) copy del dropzone aclarado → "imágenes o PDF, hasta 45 MB en total" (antes decía "varias imágenes o un PDF", que sonaba a un solo PDF; ahora el único límite comunicado es el tamaño, sin importar cuántos archivos); (b) botón **"← Volver a mis datos" reubicado ARRIBA** en el Paso 3 (antes el único "Atrás" quedaba al final, tras el bloque de pago); (c) **se quitó el bloque del Kit** del Paso 4 de éxito (el Kit ya se envía por correo, autoresponse de la compra), dejando solo el comprobante PDF + el cuestionario; el mensaje de éxito ahora dice que el Kit llega por correo. **NUEVO (interruptor de operaciones):** (a) botón **"← Volver al inicio"** en el Paso 1; (b) al cargar, el sitio **LEE** el booleano `config.operaciones_activas` (lectura pública, sin secretos); si está en **pausa**, oculta el wizard y muestra el mensaje de "Recepción de pedidos en pausa" + un campo de **lista de espera** (correo → Edge Function `captura` con `origen=lista_espera_reapertura`, misma seguridad server-side, microlínea de privacidad sin casilla). **FAIL-OPEN**: si no se puede leer la bandera, el pago sigue normal (nunca bloqueamos ventas por un error transitorio). No afecta a clientes que ya pagaron ni a la guía demo. |
| `wompi-logo.svg` | **NUEVO.** Logo OFICIAL de Wompi (versión secundaria = **blanca**, para fondo oscuro), descargado de `public-assets.wompi.com/brand_wompi/logos/logo-secondary.svg`. Se usa en el bloque "Pago seguro" de `simulacion.html` respetando lineamientos de marca (sin recolorear/distorsionar, sin implicar sociedad; solo indica la pasarela). |
| `informe.html` | **El tablero interno de gestión.** Uso interno, `noindex`, no enlazado. Pide el `LINK_SECRET` y consume la Edge Function `informe`. Capacidad + ventas + lista de pedidos con detalle/cuestionario y botones (entregada / liberar apuntes / borrar prueba). **NUEVO (Correo 3):** sección "Banco de opiniones", marcador ★, aviso "listo para pedir opinión" y botón de envío en el detalle. Ver secciones 2B y 2D. **NUEVO (interruptor de operaciones):** tarjeta **"⚙️ Operaciones"** arriba que muestra SIEMPRE el estado (**ACTIVAS ✓ / EN PAUSA ⏸️**) y un botón para cambiarlo: **Suspender** exige escribir `SUSPENDER` (anti-accidente); **Reactivar** es un clic. El cambio va por `informe` (`POST ?operaciones=1&estado=activas|pausa`, con `LINK_SECRET`, service_role) → escribe `config.operaciones_activas`. La **Base de correos** ahora tiene un tercer segmento **"Lista de espera"** (correos con `origen=lista_espera_reapertura`) con su conteo y filtros (Todos/Clientes/Prospectos/Lista de espera); se pueden borrar prospectos y lista de espera (no clientes). |
| `supabase/migrations/20260724000000_crear_tabla_config.sql` | **NUEVO.** Tabla `config` de una fila (`id=1`) con `operaciones_activas boolean` (bandera de pausa). RLS: **lectura pública** (solo un booleano, sin datos sensibles) + **sin policies de escritura** (solo `service_role`/la función `informe` la cambia). Correr en el SQL Editor. |
| `supabase/migrations/20260724010000_pedidos_pago_wompi.sql` | **NUEVO.** Añade a `pedidos` el estado de pago Wompi: `estado_pago` (pendiente/aprobado/rechazado/error), `wompi_transaction_id` (único, idempotencia), `monto_cents`, `moneda`, `pagado_en`. RLS intacta (sin SELECT/UPDATE público). Correr en SQL Editor. |
| `supabase/functions/wompi-firma/index.ts` | **NUEVO.** Calcula la **firma de integridad** del Web Checkout server-side (SHA256 de referencia+monto+moneda+SECRETO). El navegador nunca ve el secreto. El **monto en COP** sale de secretos `PRECIO_10_COP_CENTS`/`PRECIO_30_COP_CENTS` (los pones tú; anti-manipulación del monto). `GET ?selftest=1` verifica el algoritmo con el vector oficial. Verify JWT OFF. |
| `supabase/functions/wompi-webhook/index.ts` | **NUEVO — corazón del pago.** Recibe el evento de Wompi, **verifica la firma** (checksum = SHA256 de properties+timestamp+`WOMPI_EVENTS_SECRET`, **fail-closed**), y si `APPROVED`: marca el pedido pagado + dispara el Correo 1 (idempotente). Fuente de verdad del "pagado" (no confía en el navegador). `GET ?selftest=1` valida el motor SHA-256. Verify JWT OFF. |
| `pago-estado.html` | **NUEVO.** Página de retorno de Wompi (redirect-url). Solo informativa (`noindex`): muestra "confirmando tu pago" + "te llega por correo". La confirmación real la da el webhook. |
| `feedback.html` | **NUEVO (Correo 3) — página pública de opinión.** `noindex`. Lee `?pid&t&r`, registra la calificación al llegar, pide comentario y (en notas 4-5) permiso de testimonio. Escribe vía Edge Function `feedback` (token por pedido). Ver sección 2D. |
| `privacidad.html` | Actualizada a fondo (PR #68): responsable Montaguth Institute, sin lenguaje de "cuentas", transferencia internacional de datos, conservación concreta (10/30 días + registro de pedidos), datos del cuestionario, encargados nombrados, plazos PQRS. Terminología de planes alineada a "Acceso 10/30 días". **Ajuste (sesión Wompi):** en la sección 4 (encargados del tratamiento) se **quitaron los nombres del stack interno** (Supabase / FormSubmit / GitHub Pages) y se describen por función/categoría, para no exponer la arquitectura innecesariamente (decisión de seguridad del dueño). Se **mantiene "Wompi"** por ser la pasarela de pago pública que el cliente ya ve en el checkout. La sección 5 (transferencia internacional) se alineó (ya no nombra proveedores). Sigue pendiente la validación legal general. |
| `condiciones.html` | **NUEVA (PR #68).** Contratación/pago en USD, plazo de entrega 24h, reembolsos (solo por incumplimiento imputable a Stramont), uso permitido/contenido prohibido (con cláusula de reporte a autoridades por CSAM), propiedad intelectual, ley aplicable Colombia. Enlazada en el footer de `index.html` y aceptada vía checkbox (clickwrap) en el Paso 2 de `simulacion.html`. **Pendiente:** el dueño validarla con un abogado colombiano (registro RNBD ante la SIC, transferencia internacional). |
| `quienes-somos.html` | **NUEVA.** Página institucional "Quiénes somos" con la historia de marca + **Misión** y **Visión** + cierre destacado ("Stramont no es donde empiezas a estudiar. Es donde empiezas a entender.") y CTA a `simulacion.html`. Sigue el patrón de `condiciones.html`: reusa el shell de `estilos.css` (header/footer/back-link) y el CSS propio del contenido va **autocontenido con prefijo `qs-`** en la página (NO toca `estilos.css`). Look oscuro premium con la paleta del sitio (teal `--c1`, índigo `--c2`), responsive (grid Misión/Visión → 1 columna en móvil). **Enlazada SOLO desde el footer** (index, condiciones, privacidad y ella misma); NO va en el scroll de la landing para no interrumpir la conversión. Iconografía Lucide inline (target/eye), sin emojis. |
| `gracias.html`, `pago.html` | Sin cambios recientes. |
| `estilos.css` | CSS global de la home/páginas legales. **Las guías NUNCA lo tocan** (van con `<style>` inline autocontenido). |
| `supabase/functions/entrega/index.ts` | Edge Function del sistema de **entregas** (subir/mint/listar/borrar/servir guías). |
| `supabase/functions/informe/index.ts` | **Edge Function del tablero.** Lee pedidos/storage y ejecuta entregada/liberar/borrar. service_role server-side + `LINK_SECRET`. **NUEVO:** también devuelve las opiniones (banco) y adjunta el feedback a cada pedido. Ver secciones 2B y 2D. |
| `supabase/functions/correo-feedback/index.ts` | **NUEVO (Correo 3) — envío de la solicitud de opinión.** Admin, exige `LINK_SECRET`. Genera el `feedback_token`, arma los enlaces de estrella y envía por Resend. Ver sección 2D. |
| `supabase/functions/feedback/index.ts` | **NUEVO (Correo 3) — registro público de opiniones.** Verify JWT off; valida el token por pedido y escribe con service_role. Ver sección 2D. |
| `supabase/functions/captura/index.ts` | **NUEVO (Frente A) — captura de correos de prospectos.** Pública (JWT off). Valida formato + rate-limit en memoria (sin guardar IPs) + dedupe; escribe en `correos` con service_role. Ver sección 2E. |
| `supabase/migrations/*.sql` | **NUEVO — SQL versionado** de las tablas `pedidos` y `pedido_intake` y la columna `apuntes_borrados`. Hay que correrlo a mano en el SQL Editor de Supabase (no se aplica solo con el merge). |
| `.kiro/steering/metodo-guias.md` | **El método CHIP STRAMONT, versión definitiva.** Ábrelo y aplícalo tal cual para cualquier guía nueva. |

---

## 4. El método CHIP STRAMONT (versión definitiva) — resumen rápido

El detalle completo está en `.kiro/steering/metodo-guias.md` (inclusion: always, así que ya se te carga solo). Lo esencial que **no** puedes olvidar:

- Cada guía es un **HTML autocontenido** con su propio `<style>`. Nunca tocar ni enlazar `estilos.css`. Nunca romper `simulacion.html` ni la home.
- **Sistema visual:** fondo `#0B1220`, texto `#E9EDF5`. El color significa **nivel de profundidad**: teal `#2DD4BF` = Nivel 1 (la idea, siempre visible), índigo `#818CF8` = Nivel 2 (conecta, oculto en Express), bronce `#D9A066` = Nivel 3 (a fondo, oculto en Express).
- **Express/Dominar debe ser funcional de verdad**: JS que alterna clase `modo-express`/`modo-dominar` en `<body>`, persistido en `localStorage`. Pruébalo con un navegador automatizado antes de entregar, no confíes solo en leer el código.
- **Cada "Pruébate" es una flashcard de escritura**: `<textarea>` + botón que solo se habilita si escribiste algo + "Revelar y comparar" (muestra tu respuesta junto a la modelo) + se guarda en `localStorage`.
- **Hay que hallar LA joya del tema**: el insight que unifica varios conceptos (raíz etimológica compartida, patrón repetido) y explicitarla en una sección propia.
- **Bloques visuales obligatorios** según el contenido: tabla comparativa (elementos paralelos), cuadrícula 2×2 (marcos como FODA), mapa de conexiones visual (SVG con nodos y flechas, nunca una lista), widget numérico (cálculos visibles). Nada de todo-texto.
- **Rigor factual:** atribuciones con matiz ("se le suele atribuir a..."), nunca como certeza absoluta.
- **§2.5 — Instrucciones adicionales del cliente (nueva, agregada hoy):** si el pedido viene con un mensaje del tipo "esto dijo el cliente: ...", trátalo como una capa de prioridad sobre el método (ajusta el modo por defecto Express/Dominar según si tiene examen pronto o quiere profundizar, y refuerza los conceptos que mencionó que le cuestan), **nunca como reemplazo** del método base. La mayoría de pedidos no traerán instrucciones y deben funcionar exactamente igual.
- **Checklist de auto-QA (§8):** pásalo entero antes de entregar. Incluye probar Express/Dominar y las flashcards en el navegador, no solo revisar el código.
- Entrega siempre en **rama nueva + PR**, nunca push a `main`.

---

## 5. Sistema de entregas privadas (ya construido, ya usado con un cliente real)

Esto no cambió de arquitectura hoy, pero **hoy lo usé de verdad** para entregarle la guía a Lucho Díaz, así que confirmo que funciona punta a punta.

**Cómo funciona:**
1. La guía (HTML autocontenido, sin muro) vive en el **bucket privado `guias`** de Supabase — nunca en el repo público.
2. `entrega.html` (público, en GitHub Pages) es solo un visor: lee `f/exp/sig` de la URL, llama a la Edge Function, y muestra el HTML recibido en un `<iframe srcdoc>`.
3. La **Edge Function `entrega`** (`supabase/functions/entrega/index.ts`) entrega la guía solo si la firma HMAC es válida y no ha caducado.

**Modos de la función** (todos con `?key=LINK_SECRET`):
- `POST ?upload=1&f=archivo.html&key=...` (body=HTML) → sube la guía.
- `GET ?mint=1&f=archivo.html&days=N&key=...` → devuelve el link del visor con firma y expiración.
- `GET ?list=1&key=...` → lista las guías del bucket.
- `POST ?delete=1&f=archivo.html&key=...` → borra una guía.

**El `LINK_SECRET`:** vive solo en Supabase → Edge Functions → Secrets. **El dueño lo tiene y te lo puede compartir cuando lo necesites** (me lo dio en esta sesión para entregar la guía de Lucho). Nunca lo escribas en el repo — es público. Si te lo pasan, úsalo, haz la operación, y no lo dejes en ningún archivo persistente del sandbox.

**Estado del bucket `guias` a hoy:** tiene al menos 2 archivos (una guía de un cliente anterior y `la-empresa-lucho-diaz.html`, la de hoy).

**Cómo operar esto en la práctica (con Node, no con `curl` — el bash de este sandbox falla con curl a veces):**
```js
const res = await fetch(`${BASE}?upload=1&f=NOMBRE.html&key=${KEY}`, { method: 'POST', headers: {'Content-Type':'text/html'}, body: html });
```
Súbelo, luego mint, luego **verifica de verdad** haciendo el fetch que haría el visor (`?f&exp&sig`) antes de entregar el link al dueño — no asumas que funcionó.

---

## 6. Convenciones de trabajo — no te las salgas

0. **Mantener este CONTEXTO al día en cada acción, no solo al cerrar sesión (regla pedida explícitamente por el dueño, 9 jul 2026).** Tras cualquier cambio relevante (un PR, un feature, un fix, una decisión con el dueño), actualiza este archivo en el mismo PR o en uno aparte inmediato — no lo dejes acumulado para "el camión de mudanzas" del final. Concretamente: **corrige lo que ya no sea cierto** (no solo agregues) — números de PR ya mergeados, qué está en producción vs. pendiente, fechas, y cualquier dato que otro Kiro (o el dueño) ya haya corregido en paralelo. Antes de escribir, relee la sección 0/TL;DR y confirma con `list_pull_requests` + `pull_repository` que trabajas sobre el `main` real (puede haber avanzado por otra sesión en paralelo — ya pasó, ver el PR #76 "Camión de mudanzas v4").
1. **Nunca push directo a `main`.** Siempre rama nueva → PR → el dueño mergea (él mergea rápido, así que entrega cada PR completo de una vez).
2. **Una rama ya mergeada no se reutiliza.** Si necesitas seguir trabajando sobre algo que ya se mergeó, crea una rama nueva desde el `main` actualizado (usa `github_pull_repository` para sincronizar primero).
3. Usa las herramientas del power de GitHub (`push_to_remote`, `create_pull_request`, `pull_repository`) — nunca `git push`/`git pull` crudos vía bash (el fetch directo con git falla por auth en este sandbox).
4. Antes de crear una rama nueva, revisa `list_pull_requests` para no chocar con trabajo de la sesión.
5. Si tocas `estilos.css` alguna vez (raro — las guías nunca lo hacen), sube el cache-bust `?v=N` en todos los HTML que lo referencian.
6. El dueño no tiene acceso al sistema de archivos: todo cambio se revisa vía PR en GitHub. Recuérdale la recarga forzada (Ctrl/Cmd+Shift+R) tras un merge.
7. **Rutina fija tras CUALQUIER merge (no esperes a que el dueño reporte algo raro — verifícalo tú de una vez):**
   1. Confirma que el PR de verdad quedó `merged` (no solo `closed`): `list_pull_requests`.
   2. Mira los últimos runs de `https://github.com/12344-ux/12344-ux.github.io/actions` (o vía API: `curl -s "https://api.github.com/repos/12344-ux/12344-ux.github.io/actions/runs?per_page=4"`). Busca el run de ese merge.
   3. Si está `queued` mucho rato, o `failure`, o `cancelled` (puede pasar si se mergean dos PRs casi juntos): **no asumas caché del navegador, es un fallo/atasco real de deploy** (degradación transitoria de GitHub, no nuestro código — ya ha pasado varias veces, ver sección 2 punto 6).
   4. El arreglo: sincroniza `main` (`pull_repository`), **crea una rama nueva** (nunca reutilices una ya mergeada — ver regla 2 de esta lista) con un commit trivial (ej. cambiar el comentario `rebuild-trigger` al inicio de `simulacion.html`) para forzar un run limpio, y ábrelo en un PR nuevo. NO uses "Re-run", se puede quedar atascado igual.
   5. Solo después de confirmar el run en verde, dile al dueño que ya puede hacer la recarga forzada (Ctrl/Cmd+Shift+R).
8. Para cualquier prueba real de interactividad (JS, formularios, flashcards), usa Playwright con Chromium headless en vez de solo leer el código. Si las librerías del sistema faltan, se resuelven con `dnf install` + para `nss` específicamente con `rpm2archive` + `tar` (el paquete normal de `dnf` para `nss` falla al desempaquetar en este sandbox).

---

## 7. Decisiones estratégicas ya tomadas (no las reabras sin que el dueño lo pida)

- ❌ No vender datos de terceros, no buscar vacíos legales.
- ✅ Modelo por alojamiento, no créditos/SaaS.
- ✅ Kit de plantillas = regalo opcional.
- ✅ Documento = "Comprobante de pago", no factura DIAN.
- Pasarela elegida para pago real: **Wompi** (Stripe no cobra en Colombia). Aún no integrado — sigue en "modo simulación".

---

## 8. Pendientes / roadmap real

> **⭐ LO PRIMERO A RETOMAR (pendientes directos del rediseño de la guía, sección 2G):**

1. ~~**⭐ LLEVAR EL NUEVO DISEÑO DE GUÍA AL CHIP `metodo-guias.md`.**~~ ✅ **HECHO.** El chip ya describe el look editorial (Fraunces+Inter auto-hospedadas, Lucide `.lic` inline, color disciplinado teal `#2DD4BF` + ámbar `#C9A24B`, niveles por intensidad del teal —NO índigo/bronce—, sidebar activo, rail protagonista, lección z-index). Toda guía nueva nace ya con el look premium; `segmentacion-de-mercados.html` sigue siendo el esqueleto de referencia a copiar.
2. ~~**⭐ AUTO-HOSPEDAR las fuentes Fraunces + Inter (cero-dependencias).**~~ ✅ **HECHO.** Se embebieron los `woff2` en base64 en el `<style>` de la guía (subsets latin + latin-ext) y se quitaron los `<link>` a Google Fonts. Verificado con Chromium: cero peticiones externas. La guía volvió a ser cero-dependencias.
3. **Wompi (pago real):** ⏳ **CONSTRUIDO, pendiente de configuración + test de go-live del dueño.** Arquitectura: el checkout se lanza con firma de integridad calculada server-side (`wompi-firma`), el pago se confirma SOLO por `wompi-webhook` verificado (no por el navegador), que marca el pedido pagado y dispara el Correo 1 (que ahora incluye el **comprobante**). Todo el flujo de producción en `simulacion.html` está **detrás de la constante `WOMPI_PUBLIC_KEY`**: si está vacía → sigue en modo simulación (nada cambia); al pegar la llave `pub_prod_`/`pub_test_` se activa el pago real y el badge/botón cambian solos. **PENDIENTE del dueño:** (a) pegar `WOMPI_PUBLIC_KEY` en `simulacion.html`; (b) crear secretos en Supabase: `WOMPI_INTEGRITY_SECRET`, `WOMPI_EVENTS_SECRET`, `PRECIO_10_COP_CENTS`, `PRECIO_30_COP_CENTS` (montos en centavos COP — decisión de precio del dueño; Wompi cobra en COP, no USD); (c) desplegar `wompi-firma` y `wompi-webhook` (JWT OFF) + redeploy `correo-confirmacion`; (d) configurar la URL de eventos en el panel de Wompi → `.../functions/v1/wompi-webhook`; (e) correr las 2 migraciones nuevas; (f) hacer el test de compra real de punta a punta antes de abrir al público. **Decisión de precio USD→COP pendiente:** los planes muestran "$3/$5 USD" pero se cobra en COP; alinear el label cuando el dueño defina los montos COP. |
4. **Correo 3 (opiniones/feedback):** ✅ EN PRODUCCIÓN (2D). Fase 2 futura (no urgente): cron que lo dispare solo. **NO hacer reenvíos/recordatorios** (decisión de marca). **Landing (Frente C) y guía: ✅ TERMINADOS** (ver 2G).
3. **Validación legal de `condiciones.html`/`privacidad.html` (PR #68) con un abogado colombiano:** registro de base de datos ante la SIC (RNBD), transferencia internacional, formalización del responsable cuando haya recursos. El contenido ya refleja fielmente cómo funciona el sistema, pero no es asesoría legal certificada.
4. **Borrado automático de guías vencidas** en el bucket `guias` (hoy es manual con el modo `delete` de la función `entrega`).
5. **Asegurar el bucket `apuntes`:** limitar tamaño/MIME de subida anónima antes de un lanzamiento con más volumen (el tope de 45 MB hoy es solo del lado del cliente en `simulacion.html`).
6. Seguir usando el sistema de entregas para clientes reales (flujo en sección 5) y el **tablero `informe.html`** para gestionarlos (sección 2B), aprovechando el comando `DESARROLLA` (sección 10) para bajar la fricción.
7. **Mejoras posibles del tablero (opcionales, no urgentes):** paginación si algún día se superan ~2000 pedidos (la lista tiene ese tope de vista; la BD aguanta millones). El egress (10 GB/mes) NO es consultable por API con la llave pública → revisarlo a mano en Supabase → Reports cada 15 días (ya hay una nota fija en el tablero).

---

## 9. Cómo arrancar (próximo Kiro, esto es para ti)

1. Lee este documento completo (ya lo hiciste si llegaste aquí).
2. Activa/lee `.kiro/steering/metodo-guias.md` — es la fuente de verdad para construir cualquier guía nueva.
3. Revisa `list_pull_requests` y el estado real de `main` antes de asumir nada (usa `github_pull_repository` para sincronizar tu copia local).
4. Si el dueño te dice "nuevo cliente, revisa Supabase y hazle la guía": ya sabes el flujo completo (sección 5). Tienes autonomía para ejecutarlo sin pedir más instrucciones, salvo que necesites el `LINK_SECRET` (pídeselo al dueño, él lo tiene).
5. **Si tocas la tabla `pedidos`/`pedido_intake` o la función `informe`** (sección 2B): recuerda que tras mergear, el dueño debe correr el SQL en Supabase y redesplegar la función a mano. Guíalo paso a paso, no asumas que se aplicó solo.
6. Si el dueño reporta que un cambio no se ve en el sitio después de mergear, no asumas caché de una: revisa Actions primero (sección 2.6 y sección 6.7). Mergear **de a un PR**.
7. **Regla de seguridad permanente (innegociable):** nunca comprometer llaves/secretos; si el camino directo expone algo sensible, busca otra vía y explícalo — nunca el atajo inseguro en silencio (sección 2B).
8. Sé su socio honesto: chispa crítica cuando algo no es lo ideal, pero siempre entregando algo tangible y funcionando, probado de verdad antes de decir que está listo. Al dueño le gusta explícitamente que tomes criterio propio (p. ej., hoy corregí una redundancia en un texto sin que me lo pidiera, y lo valoró).

¡A seguir construyendo Stramont! 🚀
