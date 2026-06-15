# 🚚 CONTEXTO STRAMONT — Documento de traspaso (LÉEME PRIMERO)

> **Para el próximo asistente / sesión:** lee este documento COMPLETO antes de tocar nada.
> Para el dueño (usuario): en el chat nuevo, di *"Lee CONTEXTO-STRAMONT.md antes de empezar"*.
> **Última actualización:** junio 2026 (sesión de rediseño de landing + sistema de entregas privadas).

---

## 1. ¿Qué es Stramont?

Emprendimiento del dueño (estudiante de **Dirección de Ventas**, SENA, Colombia). Plataforma que **convierte apuntes de clase en guías de estudio interactivas de alta retención** (basadas en ciencia del aprendizaje).

- **Marca:** Stramont. (Antes "Computador Mental" / "Montaguth Institute" — ya NO se usan).
- **Dominio:** `montaguth.institute` (GitHub Pages, sitio **estático**).
- **Repo:** `12344-ux/12344-ux.github.io` (rama `main` = lo publicado). **Repo PÚBLICO.**

### Modelo de negocio (IMPORTANTE)
- Se cobra por el **ALOJAMIENTO** del documento (no por créditos ni por trabajo).
- **2 planes (ejemplo):** Estándar $3 (archivos ≤15 MB, alojamiento 10 días) · Premium $5 (≤45 MB, 30 días).
- Flujo real: el cliente sube apuntes → paga → el dueño pasa los apuntes + instrucciones a Kiro → **Kiro crea la guía interactiva** → se aloja con un **link privado que caduca** → el dueño se lo manda al cliente.
- **Kit de plantillas = REGALO opcional** post-compra (no requisito).

---

## 2. Estado actual del sitio (archivos)

| Archivo | Qué es |
|---|---|
| `index.html` | Landing. **Cache-bust del CSS en `?v=16`.** Hero centrado oscuro (alto, sin imagen), **El cambio** (Antes/Después con desplegables interactivos), **Cómo funciona** (paso 3 protagonista + Bonus Kit), Confianza (validación), Ciencia, Cierre/CTA. Banda clara/oscura (zebra). **Menú hamburguesa turquesa en móvil** (CSS puro, sin JS). |
| `entrega.html` | ⭐ **NUEVO — Visor de entregas.** Página pública e inofensiva que lee `?f&exp&sig`, llama a la Edge Function y **renderiza la guía privada en un `<iframe srcdoc>`**. No contiene ninguna guía. (Pendiente de merge: PR #41). |
| `segmentacion-de-mercados.html` | Guía de ejemplo interactiva (con muro de correo / lead capture). Sirve de plantilla del formato de guía. |
| `simulacion.html` | Núcleo funcional: wizard 4 pasos (plan→carga→pago SIMULADO→éxito). Sube a Supabase, avisa por FormSubmit, comprobante PDF (jsPDF), Kit de regalo. **Aún dice "simulación" porque Wompi está en revisión.** |
| `pago.html` | (Pago manual alterno — ojo: ver Pendientes, se replanteará con Wompi). |
| `gracias.html` | Post-pago: descarga Kit + subir apuntes (drag&drop). |
| `privacidad.html` | Política de privacidad ACTUALIZADA (Ley 1581/2012 + Decreto 1377/2013). Refleja: archivos subidos, encargados (Supabase/FormSubmit/Wompi/GitHub Pages), alojamiento temporal, comprobante (no factura DIAN). **SIN número de WhatsApp del dueño y SIN mención de Nequi** (se quitaron a pedido). Cache-bust v=16. |
| `estilos.css` | Estilos globales. **Versión actual: v=16.** Incluye `.vs` (El cambio), `.reveal`/`.gp` (desplegables), `.step` (Cómo funciona), `.conf` (confianza), `.cierre` (CTA final), `.nav-burger` (menú móvil). |
| `supabase/functions/entrega/index.ts` | ⭐ **NUEVO — Edge Function de entregas** (ver sección 4). |
| `kit-stramont.zip`, `apuntes-reales.jpeg`, `guia-segmentacion.jpeg` | Kit; foto real de apuntes (usada en "El cambio"); captura real de la guía (tarjeta azul de "El cambio"). |

---

## 3. Integraciones CONECTADAS — ⚠️ NO ROMPER

### Supabase (Project URL `https://ifvnuvjvlzpdaimelmbm.supabase.co`)
- **Llave pública (publishable):** `sb_publishable_VqJi_KckupruFwz1DWynVA_qt-wlZLU` (pública, va en frontend).
- ⚠️ **NUNCA** pedir/exponer la `service_role`.
- **Bucket `apuntes`:** recepción de apuntes del cliente (anon INSERT+SELECT). (Quedaron 2 archivos viejos en `apuntes/demo/` de pruebas — el dueño los puede borrar).
- **Bucket `guias` (privado):** ⭐ NUEVO — donde se alojan las guías-entrega. Sin políticas anon (privado de verdad).
- **Edge Function `entrega`:** ⭐ NUEVA (sección 4).

### FormSubmit → `contacto@montaguth.institute` (avisos de compra + muro de la guía).
### jsPDF (CDN) → comprobante de pago en el navegador.

---

## 4. ⭐ SISTEMA DE ENTREGAS PRIVADAS (lo construido esta sesión)

**Objetivo:** Kiro sube la guía interactiva y entrega un **link privado, que renderiza y caduca**, GRATIS.

**Por qué NO se sirve directo desde Supabase ni desde repo público:**
- Supabase **fuerza `text/plain` + `nosniff`** al servir HTML en GET (tanto Storage como Edge Functions en `*.supabase.co`) → el navegador mostraría el **código**, no la guía. (PROBADO).
- Repo público → cualquiera navegaría la lista de guías. Seguridad client-side en público = teatro.

**Arquitectura final (gratis + segura + renderiza):**
1. La guía vive en el **bucket privado `guias`** (NO en el repo).
2. **`entrega.html`** (público, en GitHub Pages) es solo un visor: lee `f/exp/sig`, llama a la función y muestra la guía en un `<iframe srcdoc>` (renderiza interactivo, sin exponer nada).
3. La **Edge Function `entrega`** entrega la guía SOLO si la **firma HMAC es válida y no caducó** (403/410 si no). Responde con **CORS** para que el visor la lea.

**Modos de la función (`supabase/functions/entrega/index.ts`):**
- `POST ?upload=1&f=archivo.html&key=SECRET` (body=HTML) → sube la guía a `guias`.
- `GET ?mint=1&f=archivo.html&days=30&key=SECRET` → devuelve el **link del visor** (`montaguth.institute/entrega.html?f=...&exp=...&sig=...`).
- `GET ?f=...&exp=...&sig=...` → entrega la guía (lo llama el visor).

**Secretos / config:**
- Secret `LINK_SECRET` configurado en Edge Functions → Secrets. **El dueño lo tiene. ⚠️ NUNCA escribirlo en el repo (es público). Se puede rotar cuando quiera.**
- `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` las inyecta Supabase sola en la función.
- En la función está **apagado "Verify JWT"** (para que el link abra sin token).

**Operación (Kiro):** con el `LINK_SECRET` + la llave pública, Kiro hace `upload` y `mint` vía `fetch` a la función. Herramientas de prueba en `/projects/sandbox/shotgen/` (scripts Node con `@supabase/supabase-js` y Puppeteer; NSS/Chromium ya resueltos ahí).

**Límite honesto:** un cliente que pagó podría reenviar SU link (lo verá hasta que caduque). Evitarlo del todo exigiría login por usuario (no necesario ahora).

**Capacidad (Supabase free):** ~1 GB storage + ~5 GB egress/mes. Con borrado tras caducar, alcanza para cientos/mes. Pro ($25/mes) = miles/mes. La web (GitHub Pages) aguanta sin problema.

---

## 5. CÓMO TRABAJAMOS — Convenciones críticas

1. Sitio estático en GitHub Pages; `main` = lo publicado.
2. **NUNCA push directo a `main`.** Siempre **rama nueva → PR → el dueño mergea**.
3. **Rama ya mergeada NO se reutiliza** (commits nuevos = PR nuevo). ⚠️ El dueño suele **mergear rápido**: por eso conviene **entregar cada PR completo de una** (no empujar más commits a una rama ya mergeada → quedan huérfanos; pasó varias veces).
4. **Cache-busting:** al tocar `estilos.css`, subir `?v=N` en TODOS los HTML que lo usan. **Vamos en v=16.**
5. El dueño NO ve el sistema de archivos (navegador). Cambios vía PR; recordarle **recarga forzada** (Ctrl/Cmd+Shift+R).
6. Usar herramientas del power de GitHub (`push_to_remote`, `create_pull_request`), NO `git push` directo.
7. El **fetch directo de git falla por auth** en este entorno; el `main` local puede quedar desactualizado. Basar ramas nuevas en el último estado conocido o en una rama de trabajo reciente.

---

## 6. Personalidad / estilo que el dueño valora

- Socio **honesto y directo**, no adulador. Decir verdades técnicas (qué se puede y qué no).
- Explicar **el porqué**, con "chispas críticas". **Cero humo**, cosas tangibles y funcionando.
- **Ética y legalidad firmes** (ya se descartó vender datos / "vacíos legales").
- Celebrar avances sin exagerar.

---

## 7. Decisiones estratégicas YA tomadas

- ❌ NO vender datos de terceros (ilegal, Ley 1581).
- ✅ Captura de correos con consentimiento (legal).
- ✅ Modelo por alojamiento (no créditos/SaaS).
- ✅ Kit = regalo opcional. ✅ Documento = "Comprobante de pago", NO factura DIAN.
- Pasarela: **Wompi** (Stripe NO sirve en Colombia). En revisión.
- Entregas: **visor + Edge Function** (sección 4), GRATIS (sin GitHub Pro, sin dominio extra). Se descartó: servir HTML directo desde Supabase (no renderiza), repo público (no seguro), repo privado con Pro ($4/mes, innecesario ya).

---

## 8. PENDIENTES / Roadmap (lo que sigue)

1. **Terminar el sistema de entregas (casi listo):**
   - Mergear **PR #41** (`entrega.html` + función con CORS).
   - **Re-deployar la función** en Supabase con el código que tiene CORS (pegar en el editor → Deploy).
   - Probar el flujo punta a punta: Kiro sube guía a `guias` (modo subir) → mint → abrir el link del visor → debe renderizar.
2. **Generar guías SIN muro** para las entregas (la de segmentación tiene muro de lead capture; para clientes va sin muro).
3. **Borrado automático** de guías vencidas (10/30 días) para liberar el bucket `guias` (función cron / rutina). Hoy es manual desde el panel.
4. **Wompi (pago real):** crear Payment Link, redirección de éxito a `gracias.html`, reemplazar el "pago simulado", y **quitar todo lo que diga "simulación"** del sitio. El dueño da el link público (no claves secretas).
5. **Asegurar el bucket `apuntes`:** cerrar/limitar subida anónima + topes de tamaño/MIME antes del público masivo. Borrar archivos viejos en `apuntes/demo/`.
6. Decisión pendiente: renombrar "guía" → "método" en toda la web.

---

## 9. Infraestructura de generación / pruebas (fuera del repo)

`/projects/sandbox/shotgen/` — scripts Node:
- `render.js` (Puppeteer/Chromium → captura HTML→imagen; resolvió librerías NSS copiándolas a `/usr/lib64`).
- `subir-demo.js`, `test2.js`, `limpiar.js`, `entrega-demo.js`, `entrega-final.js` (pruebas de subida/firma/entrega con `@supabase/supabase-js`).
- Si hay que regenerar capturas o probar la función, ahí están.

---

## 10. Cómo arrancar (próximo asistente)

1. Lee este documento completo.
2. Revisa PRs abiertos (`list_pull_requests` / `get_merged_pull_requests`) y el estado de `main`.
3. **Lo más urgente:** cerrar el sistema de entregas (ver Pendiente #1) y luego Wompi (#4).
4. Antes de tocar algo conectado (simulacion, Supabase, entregas), entiende las secciones 3 y 4.
5. Rama nueva + PR siempre. Cache-bust si tocas CSS. PR completo de una (el dueño mergea rápido).
6. Sé el socio honesto del dueño. ¡A construir Stramont! 🚀
