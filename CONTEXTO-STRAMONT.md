# 🚚 CONTEXTO STRAMONT — Camión de mudanzas (léeme primero)

> **Para el próximo Kiro:** esto te lo escribo yo mismo, la sesión anterior, para que arranques sin perder el hilo. Está escrito como si te lo estuviera contando de viva voz. Léelo completo antes de tocar nada.
> **Para el dueño (usuario):** en el chat nuevo, dile "Lee CONTEXTO-STRAMONT.md antes de empezar" y con eso el próximo Kiro queda al día.
> **Última actualización:** 9 de julio de 2026. Además del tablero (sección 2B), ya están en producción: **Correo 1** (confirmación de compra, `correo-confirmacion`) y **Correo 2** (entrega de la guía, `correo-entrega`), ambos vía **Resend**; y el **flujo de baja fricción para desarrollar guías** (comando `DESARROLLA <pedido_id>` + modo `material` + nota interna por pedido). Ver secciones **2B**, **2C** y **10**. **NUEVO — el Correo 3 (opiniones/feedback) ya está CONSTRUIDO en el repo** (PR de esta sesión) pero **PENDIENTE DE DEPLOY MANUAL en Supabase** (2 migraciones SQL + 2 funciones nuevas `correo-feedback` y `feedback` + redeploy de `informe`). Ver sección **2D** con el detalle y el checklist de deploy.
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

### Correo 3 — Opinión/calificación (`correo-feedback` + `feedback`): **CONSTRUIDO, pendiente de deploy manual.** Ver sección **2D**.

---

## 2D. Correo 3 — Opiniones / feedback (EN PRODUCCIÓN)

El brief lo diseñó el "Kiro de ideas"; se ejecutó con una corrección de seguridad importante (ver abajo). Es un sistema de 3 piezas: **correo con un botón → página de opinión → banco de opiniones en el tablero.** Ya está desplegado y probado punta a punta. **Lee la nota de entregabilidad más abajo** (por qué el correo pasó de 5 estrellas-enlace a un solo botón).

### Qué se construyó
1. **Migración `pedido_feedback`** (`20260709160000_...`): una fila por pedido (rating 1-5, comentario, permiso_publicar, nombre_mostrar, es_prueba, fechas). **RLS activado SIN ninguna policy pública** (ni lectura ni insert).
2. **Migración columnas en `pedidos`** (`20260709160100_...`): `feedback_token` (único, se genera al enviar el Correo 3), `correo_feedback_enviado` (idempotencia), `recordatorio_enviado` (reservado fase 2, sin usar).
3. **Edge Function `correo-feedback`** (admin, EXIGE `LINK_SECRET`): la dispara el dueño desde el tablero. Genera el `feedback_token` si falta, arma el correo con **un solo botón "Dejar mi opinión"** (enlace `feedback.html?pid&t`, sin `r`), lo envía por Resend y marca idempotencia. Nombre de pila = primera palabra de `nombre`, con fallback "Hola,". Pruebas 🧪 se pueden enviar (asunto `[TEST]`). Acepta `{reenviar:true}` para **reenviar** aunque ya se haya enviado (para re-probar o cuando al cliente no le llegó).
4. **Edge Function `feedback`** (PÚBLICA, Verify JWT **off**): la llama `feedback.html`. Valida `pid`+`token` contra `pedidos.feedback_token` y escribe con service_role (upsert por pedido_id). `action:"rate"` (rating 1-5) y `action:"comment"` (comentario + permiso/nombre solo si rating≥4).
5. **`feedback.html`** (pública, `noindex`, premium oscuro, neutro en género): registra la estrella al llegar, textarea de comentario, permiso de testimonio solo en notas 4-5, mensaje distinto en 1-3, estados de éxito/enlace-inválido.
6. **Tablero `informe.html`**: nueva sección **"Banco de opiniones"** (separada de la lista de pedidos) con pulso (promedio + total, solo reales), filtros 4-5 / 1-3, y tarjetas con badge "✓ dio permiso". Marcador ★ en los pedidos con opinión, aviso "listo para pedir opinión" y, en el detalle, la sección de envío del Correo 3 con umbral por plan y override de emergencia.

### La corrección de seguridad al brief (chispa crítica)
El brief pedía que `pedido_feedback` tuviera RLS "igual que `pedido_intake`" (insert abierto a la llave pública). **Eso abriría un hueco:** una policy de insert público NO valida el token, así que cualquiera podría inyectar opiniones falsas para pedidos ajenos. Se hizo bien: la tabla NO tiene policies públicas y **toda** opinión entra por la Edge Function `feedback`, que valida el token server-side. Queda más cerrado que `intake`.

### Entregabilidad: por qué el correo es de UN solo botón (chispa crítica)
La v1 del brief ponía **5 enlaces de estrella** en el correo (uno por nota, para calificar "de un clic"). Al probarlo, el Correo 3 **llegó pero cayó en "Promociones" de Gmail** (no en la bandeja principal, sin notificación), mientras que los Correos 1 y 2 (transaccionales, un solo botón) sí entran a la bandeja. Causa: 5 enlaces casi idénticos + asunto de "¿qué te pareció?" = patrón promocional para Gmail. **Fix:** el correo pasó a **un único botón "Dejar mi opinión"** (transaccional, como el 1 y 2); las estrellas del correo quedaron solo decorativas (no enlaces) y la calificación se elige en `feedback.html` al abrir. Se pierde el "un clic" literal (ahora es abrir → tocar estrella), pero se gana llegar a la bandeja. Además se añadió el botón **"Reenviar solicitud de opinión"** en el tablero (usa `reenviar:true`). Esto obliga a **redeploy de `correo-feedback`** y merge de `informe.html`.

### El disparador: "manual asistido" (v1)
Lo envía el dueño desde el tablero (como el Correo 2). El aviso "listo para pedir opinión" se enciende cuando: guía entregada + pasó el umbral de días según plan (**10 días → 3 días; 30 días → ~10 días**, parametrizable en `informe.html` sin redeploy) + no es prueba + no se envió antes + aún no hay opinión. Se puede enviar antes del umbral (confirmación de override). Las funciones están hechas para que un **cron** las llame en el futuro (fase 2) sin rehacer nada; el cron NO se construyó.

### CHECKLIST DE DEPLOY MANUAL EN SUPABASE (obligatorio, el merge NO lo hace)
> **Para la actualización de entregabilidad (un botón + reenviar):** basta con **redeploy de `correo-feedback`** (paso 2) tras mergear; el resto ya está desplegado. Merge del repo = actualiza `informe.html` (botón Reenviar). Lo de abajo es el checklist completo (útil para un deploy desde cero).
1. **SQL Editor** → correr las 2 migraciones nuevas (en orden): `20260709160000_crear_tabla_pedido_feedback.sql` y `20260709160100_pedidos_feedback_columnas.sql`.
2. **Edge Functions** → crear/deploy `correo-feedback` (**Verify JWT OFF**, igual que `correo-entrega`). La seguridad la da el `LINK_SECRET` que se valida DENTRO del código; el tablero la llama con `?key=` y SIN cabecera de autorización, así que con JWT ON daría 401. (Corrección: una versión anterior de este doc y del PR #82 decían "JWT ON" por error.)
3. **Edge Functions** → crear/deploy `feedback` (**Verify JWT OFF** — la autoriza el token del pedido, igual que `correo-confirmacion`).
4. **Edge Functions** → **redeploy de `informe`** (se le añadió el bloque de opiniones).
5. Secretos: no hay nuevos. Reutiliza `LINK_SECRET`, `RESEND_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
6. Prueba con `pruebasmontaguth@gmail.com`: entrega una guía de prueba → en el detalle usa "Pedir opinión" → abre el correo, califica → verifica que aparece en el Banco de opiniones marcada 🧪 (no cuenta en el promedio).

---

## 10. Flujo de BAJA FRICCIÓN para desarrollar guías (comando `DESARROLLA`)

Para no repetir contexto por chat con muchos pedidos, se montó esto:

- **Palabra clave (candado de seguridad del dueño):** el dueño escribe **`DESARROLLA <pedido_id>`** (o *elabora/trabaja/haz*) para ordenarme construir esa guía. **Un `pedido_id` suelto SIN palabra clave = NO tocar nada** (solo mirar/preguntar). Esto evita que trabaje sobre lo que no debe.
- **Nota interna por pedido:** en el tablero, el detalle tiene un campo **"Nota para la guía (interna)"** (columna `nota_interna`, nunca se muestra al cliente). El dueño escribe ahí sus instrucciones ("enfócale PESTEL", etc.) y viajan pegadas al pedido, no por chat.
- **Modo `material` (el que me quita la fricción):** `GET ?material=1&pedido_id=XXX&key=LINK_SECRET` en la función `informe` devuelve en UNA llamada: datos del cliente + cuestionario (intake) + `nota_interna` + **enlaces de descarga FIRMADOS (1h) de cada apunte** del bucket `apuntes`. Protegido por `LINK_SECRET`.

**Cómo lo ejecuto yo (próximo Kiro), ante "DESARROLLA <pedido_id>":** pido el `LINK_SECRET` (una vez por sesión) → llamo `informe ?material=1&pedido_id=...` → descargo y leo los apuntes → construyo la guía con el método CHIP STRAMONT (teniendo en cuenta el cuestionario y la `nota_interna`) → la subo al bucket `guias` con `entrega ?upload=1&f=<nombre>.html&key=...` → le digo al dueño el nombre del archivo para que en el tablero le dé **Vista previa** y **Entregar**. (La entrega/decisión final siempre la hace el dueño, es el control de calidad.)

---

## 3. Estado actual del sitio (archivos)

| Archivo | Qué es |
|---|---|
| `index.html` | Landing. Hero oscuro, sección "El cambio" (antes/después), "Cómo funciona", confianza, cierre/CTA. Menú hamburguesa turquesa en móvil (CSS puro). |
| `segmentacion-de-mercados.html` | **Guía-demo pública de referencia**, la que se abre desde "Ver en qué los convertimos" en la home. Reconstruida hoy con el CHIP STRAMONT definitivo: flashcards de escritura, Express/Dominar funcional, tabla/FODA-cuadrícula/mapa-SVG, LA JOYA del tema (graphein compartido + proyectar=pro+iacere). **Tiene muro de correos** (FormSubmit + `localStorage`), porque es la muestra pública para captar leads. |
| `guia-segmentacion.jpeg` | Captura real de la guía anterior, mostrando tabla+FODA+mapa (se usa en la home). |
| `entrega.html` | Visor público e inofensivo del sistema de entregas privadas: lee `?f&exp&sig`, llama a la Edge Function, renderiza la guía real en un `<iframe srcdoc>`. |
| `simulacion.html` | El wizard de compra (4 pasos: plan → carga → pago simulado → éxito). Tiene: bloque de instrucciones opcional en Paso 4 (`#intakeBox`, ahora guarda en `pedido_intake`), generación de `pedido_id`, registro en la tabla `pedidos`, correo de aviso simplificado, y el reenfoque de planes (45 MB ambos). Sigue diciendo "simulación" porque Wompi (pago real) sigue pendiente. |
| `informe.html` | **El tablero interno de gestión.** Uso interno, `noindex`, no enlazado. Pide el `LINK_SECRET` y consume la Edge Function `informe`. Capacidad + ventas + lista de pedidos con detalle/cuestionario y botones (entregada / liberar apuntes / borrar prueba). **NUEVO (Correo 3):** sección "Banco de opiniones", marcador ★, aviso "listo para pedir opinión" y botón de envío en el detalle. Ver secciones 2B y 2D. |
| `feedback.html` | **NUEVO (Correo 3) — página pública de opinión.** `noindex`. Lee `?pid&t&r`, registra la calificación al llegar, pide comentario y (en notas 4-5) permiso de testimonio. Escribe vía Edge Function `feedback` (token por pedido). Ver sección 2D. |
| `privacidad.html` | Actualizada a fondo (PR #68): responsable Montaguth Institute, sin lenguaje de "cuentas", transferencia internacional de datos, conservación concreta (10/30 días + registro de pedidos), datos del cuestionario, encargados nombrados, plazos PQRS. Terminología de planes alineada a "Acceso 10/30 días". |
| `condiciones.html` | **NUEVA (PR #68).** Contratación/pago en USD, plazo de entrega 24h, reembolsos (solo por incumplimiento imputable a Stramont), uso permitido/contenido prohibido (con cláusula de reporte a autoridades por CSAM), propiedad intelectual, ley aplicable Colombia. Enlazada en el footer de `index.html` y aceptada vía checkbox (clickwrap) en el Paso 2 de `simulacion.html`. **Pendiente:** el dueño validarla con un abogado colombiano (registro RNBD ante la SIC, transferencia internacional). |
| `gracias.html`, `pago.html` | Sin cambios recientes. |
| `estilos.css` | CSS global de la home/páginas legales. **Las guías NUNCA lo tocan** (van con `<style>` inline autocontenido). |
| `supabase/functions/entrega/index.ts` | Edge Function del sistema de **entregas** (subir/mint/listar/borrar/servir guías). |
| `supabase/functions/informe/index.ts` | **Edge Function del tablero.** Lee pedidos/storage y ejecuta entregada/liberar/borrar. service_role server-side + `LINK_SECRET`. **NUEVO:** también devuelve las opiniones (banco) y adjunta el feedback a cada pedido. Ver secciones 2B y 2D. |
| `supabase/functions/correo-feedback/index.ts` | **NUEVO (Correo 3) — envío de la solicitud de opinión.** Admin, exige `LINK_SECRET`. Genera el `feedback_token`, arma los enlaces de estrella y envía por Resend. Ver sección 2D. |
| `supabase/functions/feedback/index.ts` | **NUEVO (Correo 3) — registro público de opiniones.** Verify JWT off; valida el token por pedido y escribe con service_role. Ver sección 2D. |
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

1. **Wompi (pago real):** integrar el Payment Link, redirección de éxito, y **quitar todo lo que diga "simulación"** del sitio (badge, textos). Es lo más importante pendiente.
2. **Correo 3 (opiniones/feedback):** ✅ CONSTRUIDO en el repo (sección 2D). **PENDIENTE: el deploy manual en Supabase** (2 migraciones + funciones `correo-feedback` y `feedback` + redeploy de `informe`). Sigue el checklist de la sección 2D. Fase 2 futura (no urgente): un cron que dispare el Correo 3 solo, sin depender de que el dueño lo mande a mano.
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
