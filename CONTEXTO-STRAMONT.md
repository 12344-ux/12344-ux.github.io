# 🚚 CONTEXTO STRAMONT — Camión de mudanzas (léeme primero)

> **Para el próximo Kiro:** esto te lo escribo yo mismo, la sesión anterior, para que arranques sin perder el hilo. Está escrito como si te lo estuviera contando de viva voz. Léelo completo antes de tocar nada.
> **Para el dueño (usuario):** en el chat nuevo, dile "Lee CONTEXTO-STRAMONT.md antes de empezar" y con eso el próximo Kiro queda al día.
> **Última actualización:** 3 de julio de 2026 (sesión de reconstrucción de guías con CHIP STRAMONT + entrega real a cliente + bloque de instrucciones + fix de deploy).

---

## 1. Quién es el dueño y qué es Stramont

El dueño es estudiante de **Dirección de Ventas** (SENA, Colombia). Stramont convierte apuntes de clase en **guías de estudio interactivas** de alta retención, basadas en ciencia del aprendizaje.

- **Dominio:** `montaguth.institute` (GitHub Pages, sitio 100% estático).
- **Repo:** `12344-ux/12344-ux.github.io`, rama `main` = lo publicado. **Repo público.**
- **Estilo de trato que quiere:** socio honesto y directo, no adulador. Explica el porqué con "chispas críticas". Cero humo, entrega cosas tangibles y funcionando. Ya se acordó con él NO vender datos ni buscar vacíos legales — línea ética firme.
- **Modelo de negocio:** cobra por el **alojamiento** del documento (no por créditos/SaaS). Planes actuales: Acceso 10 días ($3 USD, hasta 15 MB) / Acceso 30 días ($5 USD, hasta 45 MB). El Kit de plantillas es un regalo opcional post-compra. El documento que se genera es un "Comprobante de pago", **no** una factura DIAN.

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

## 3. Estado actual del sitio (archivos)

| Archivo | Qué es |
|---|---|
| `index.html` | Landing. Hero oscuro, sección "El cambio" (antes/después), "Cómo funciona", confianza, cierre/CTA. Menú hamburguesa turquesa en móvil (CSS puro). |
| `segmentacion-de-mercados.html` | **Guía-demo pública de referencia**, la que se abre desde "Ver en qué los convertimos" en la home. Reconstruida hoy con el CHIP STRAMONT definitivo: flashcards de escritura, Express/Dominar funcional, tabla/FODA-cuadrícula/mapa-SVG, LA JOYA del tema (graphein compartido + proyectar=pro+iacere). **Tiene muro de correos** (FormSubmit + `localStorage`), porque es la muestra pública para captar leads. |
| `guia-segmentacion.jpeg` | Captura real de la guía anterior, mostrando tabla+FODA+mapa (se usa en la home). |
| `entrega.html` | Visor público e inofensivo del sistema de entregas privadas: lee `?f&exp&sig`, llama a la Edge Function, renderiza la guía real en un `<iframe srcdoc>`. |
| `simulacion.html` | El wizard de compra (4 pasos: plan → carga → pago simulado → éxito). **Hoy le agregamos el bloque de instrucciones adicionales opcional en el Paso 4** (`#intakeBox`). Sigue diciendo "simulación" porque Wompi (pago real) sigue pendiente. |
| `privacidad.html`, `gracias.html`, `pago.html` | Sin cambios en esta sesión. |
| `estilos.css` | CSS global de la home/páginas legales. **Las guías NUNCA lo tocan** (van con `<style>` inline autocontenido). |
| `supabase/functions/entrega/index.ts` | Edge Function del sistema de entregas (subir/mint/listar/borrar/servir). Sin cambios hoy. |
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

1. **Nunca push directo a `main`.** Siempre rama nueva → PR → el dueño mergea (él mergea rápido, así que entrega cada PR completo de una vez).
2. **Una rama ya mergeada no se reutiliza.** Si necesitas seguir trabajando sobre algo que ya se mergeó, crea una rama nueva desde el `main` actualizado (usa `github_pull_repository` para sincronizar primero).
3. Usa las herramientas del power de GitHub (`push_to_remote`, `create_pull_request`, `pull_repository`) — nunca `git push`/`git pull` crudos vía bash (el fetch directo con git falla por auth en este sandbox).
4. Antes de crear una rama nueva, revisa `list_pull_requests` para no chocar con trabajo de la sesión.
5. Si tocas `estilos.css` alguna vez (raro — las guías nunca lo hacen), sube el cache-bust `?v=N` en todos los HTML que lo referencian.
6. El dueño no tiene acceso al sistema de archivos: todo cambio se revisa vía PR en GitHub. Recuérdale la recarga forzada (Ctrl/Cmd+Shift+R) tras un merge.
7. **Si algo no se refleja tras un merge y ya pasaron varios minutos:** no asumas que es solo caché. Revisa `https://github.com/12344-ux/12344-ux.github.io/actions` — puede ser un fallo real de deploy (ver sección 2, punto 6).
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
2. **Borrado automático de guías vencidas** en el bucket `guias` (hoy es manual con el modo `delete` de la función).
3. **Asegurar el bucket `apuntes`:** limitar tamaño/MIME de subida anónima antes de un lanzamiento con más volumen.
4. Seguir usando el sistema de entregas para clientes reales según vayan llegando (el flujo completo: ubicar en Supabase → leer apuntes → construir guía con CHIP STRAMONT → subir a `guias` → mint → entregar link — ya está probado y funciona).

---

## 9. Cómo arrancar (próximo Kiro, esto es para ti)

1. Lee este documento completo (ya lo hiciste si llegaste aquí).
2. Activa/lee `.kiro/steering/metodo-guias.md` — es la fuente de verdad para construir cualquier guía nueva.
3. Revisa `list_pull_requests` y el estado real de `main` antes de asumir nada (usa `github_pull_repository` para sincronizar tu copia local).
4. Si el dueño te dice "nuevo cliente, revisa Supabase y hazle la guía": ya sabes el flujo completo (sección 5). Tienes autonomía para ejecutarlo sin pedir más instrucciones, salvo que necesites el `LINK_SECRET` (pídeselo al dueño, él lo tiene).
5. Si el dueño reporta que un cambio no se ve en el sitio después de mergear, no asumas caché de una: revisa Actions primero (sección 2.6 y sección 6.7).
6. Sé su socio honesto: chispa crítica cuando algo no es lo ideal, pero siempre entregando algo tangible y funcionando, probado de verdad antes de decir que está listo.

¡A seguir construyendo Stramont! 🚀
