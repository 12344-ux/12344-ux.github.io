# 🚚 CONTEXTO STRAMONT — Documento de traspaso (LÉEME PRIMERO)

> **Para el próximo asistente / sesión:** lee este documento COMPLETO antes de tocar nada.
> Para el dueño (usuario): en el chat nuevo, di *"Lee CONTEXTO-STRAMONT.md antes de empezar"*.

---

## 1. ¿Qué es Stramont?

Stramont es un **emprendimiento digital** del dueño (estudiante de **Dirección de Ventas**, carrera SENA, Colombia). Empezó como una página de ensayos y se transformó en una **plataforma que convierte apuntes de clase en guías de estudio de alta retención** (basadas en ciencia del aprendizaje).

- **Marca:** Stramont. (Antes "Computador Mental" / "Montaguth Institute" — ya NO se usan).
- **Dominio:** `montaguth.institute` (GitHub Pages, sitio **estático**).
- **Repo:** `12344-ux/12344-ux.github.io` (rama `main` = lo que se publica).

### Modelo de negocio actual (IMPORTANTE)
- **Se cobra por el ALOJAMIENTO** del documento (no por créditos ni por trabajo). Cada compra = una carga de archivos.
- **2 planes (precios de ejemplo):**
  - **Estándar:** $3 USD · archivos hasta **15 MB** · alojamiento **10 días**.
  - **Premium:** $5 USD · archivos hasta **45 MB** · alojamiento **30 días**.
- El cliente sube apuntes → paga → en **menos de 24 h** recibe por correo un **enlace exclusivo** a su material (lo envía el dueño manualmente por ahora).
- **Kit de plantillas = REGALO opcional** post-compra (no obligatorio).

---

## 2. Estado actual — Archivos del sitio

| Archivo | Qué es |
|---|---|
| `index.html` | Landing principal. Hero **centrado** (sin imagen), El cambio (antes/después), La prueba/demo, Cómo funciona (proceso 1-2-3), Velocidad 24h, Confianza, Ciencia (beneficios + referencias), Emocional, CTA final. Bandas **claro/oscuro (zebra)**. |
| `simulacion.html` | ⭐ **Núcleo funcional**. Wizard de 4 pasos (plan → carga → pago SIMULADO → éxito). Sube archivos a **Supabase Storage**, avisa de la compra por **FormSubmit**, genera **comprobante PDF (jsPDF)** y entrega el **Kit de regalo**. |
| `pago.html` | Pago manual por **Nequi** (alternativa). |
| `gracias.html` | Página post-pago: descarga del Kit + subir apuntes (Drag & Drop). |
| `privacidad.html` | Política de privacidad (Ley 1581 Colombia). |
| `segmentacion-de-mercados.html` | La **guía de ejemplo gratis** (método Stramont 2.0) con muro de correo. |
| `estilos.css` | Estilos globales (de index, pago, gracias, privacidad). |
| `kit-stramont.zip` | Kit de plantillas (A4, tablet, Word, Notion, instructivo). |
| `apuntes-reales.jpeg` | Foto real de apuntes (subida por el dueño). |

---

## 3. Integraciones CONECTADAS — ⚠️ NO ROMPER

### Supabase Storage (recepción de archivos)
- **Project URL:** `https://ifvnuvjvlzpdaimelmbm.supabase.co`
- **Llave pública (publishable):** `sb_publishable_VqJi_KckupruFwz1DWynVA_qt-wlZLU` (es pública, va en el frontend; está en `simulacion.html`).
- **Bucket:** `apuntes`. Archivos indexados por correo: `correo/archivo`.
- **Policies:** INSERT y SELECT para rol `anon` (permiten subir y firmar enlaces sin login).
- ⚠️ **NUNCA** pedir ni exponer la `service_role` (secreta).
- ⚠️ Pendiente de seguridad: la subida anónima está ABIERTA (para pruebas). Hay que restringirla antes de abrir al público masivo.

### FormSubmit (correos)
- Envía a `contacto@montaguth.institute`. Ya está **activado**.
- Se usa para: aviso "💸 NUEVA COMPRA" (al dueño) y el muro de correo de la guía.
- ⚠️ El `_autoresponse` (correo automático AL CLIENTE) es **poco fiable** (cae en spam / no siempre se envía). Por eso el Kit se entrega también en pantalla.

### jsPDF (CDN) — genera el comprobante de pago en el navegador.

---

## 4. Datos de marca y contacto

- **Paleta (web principal):** teal `#2a9d8f` (--c1), índigo `#4a63c4` (--c2), bronce `#bd8a40` (--c3). Base oscura. **Turquesa = color de atención** (CTAs, datos). Diseño en **bandas claro/oscuro (zebra)**.
- **Azul institucional:** `#1a3a8f` (usado en `simulacion.html`).
- **Contacto:** `contacto@montaguth.institute` · WhatsApp/Nequi **322 364 3728** · Instagram **@montaguth.institute**.

---

## 5. CÓMO TRABAJAMOS — Convenciones críticas (síguelas)

1. **Sitio estático en GitHub Pages.** La rama `main` es lo que se publica en `montaguth.institute`.
2. **NUNCA hacer push directo a `main`.** Siempre: crear **rama nueva → PR → el dueño hace merge**.
3. **Una vez el dueño mergea un PR, NO se reutiliza esa rama.** Cualquier cambio nuevo va en un **PR nuevo**. (Esto causó confusión varias veces: si agregas commits a una rama ya mergeada, quedan huérfanos).
4. **Cache-busting:** cada vez que cambies `estilos.css`, sube el número de versión en el `<link rel="stylesheet" href="estilos.css?v=N">` (vamos por **v=7**). Sin esto, el navegador muestra CSS viejo.
5. **El dueño NO ve el sistema de archivos** (está en navegador). Para que vea cambios: push + PR, y él mergea. Recuérdale **recargar forzado** (Ctrl/Cmd+Shift+R).
6. **Herramientas:** usar las del power de GitHub (`push_to_remote`, `create_pull_request`, etc.), NO `git push` directo.

---

## 6. Personalidad / estilo que el dueño valora (MUY importante)

- Trato de **socio honesto y directo**, no adulador. Decir las verdades técnicas (qué se puede y qué no en estático).
- Explicar **el porqué** de las cosas; añadir "chispas críticas" / insights.
- **Cero humo**: entregar cosas tangibles y funcionando.
- **Ética y legalidad firmes**: ya se descartó (con su acuerdo) vender datos / "lobo de Wall Street" / "vacíos legales". Mantener esa línea.
- Celebrar los avances (es muy entusiasta) pero sin exagerar.

---

## 7. Decisiones estratégicas YA tomadas (mantener coherencia)

- ❌ NO vender bases de datos / datos de terceros (ilegal en Colombia, Ley 1581).
- ✅ Captura de correos **con consentimiento** (lista propia), legal.
- ✅ Modelo **por alojamiento** (no créditos, no SaaS complejo — se descartó por complejidad).
- ✅ Kit de plantillas = **regalo opcional**, no requisito.
- ✅ Documento de pago = **"Comprobante de pago"**, NO "Factura" (factura DIAN tiene requisitos legales).
- Pasarela elegida: **Wompi** (Colombia). **Stripe NO sirve para cobrar en Colombia.**

---

## 8. PENDIENTES / Roadmap (lo que sigue)

1. **Conectar Wompi (pago real):** crear *Payment Link*, poner URL de redirección de éxito → `https://montaguth.institute/gracias.html`, y reemplazar el "pago simulado". El dueño debe dar el **link público** (NO claves secretas).
2. **Asegurar el bucket de Supabase:** cerrar/limitar la subida anónima tras las pruebas; topes de tamaño y tipo (MIME).
3. **Correo al cliente 100% fiable:** montar **Supabase Edge Function + Resend** (dominio verificado) para enviar el enlace/regalo sin depender del autoresponse de FormSubmit.
4. **Decisión pendiente del dueño:** renombrar "guía" → "método" en TODA la web (por ahora solo se cambió en partes).
5. **PRs:** al momento del traspaso, el #27 (hero centrado) estaba listo para merge; el #26 (mockup viejo) quedó obsoleto → cerrar sin merge.

---

## 9. Infraestructura de generación (PDF / Kit)

Vive FUERA del repo, en el workspace (`/projects/sandbox/pdfgen` y `/projects/sandbox/kitgen`):
- **Chromium headless + Puppeteer** (con librerías NSS en `pdfgen/libs` y `LD_LIBRARY_PATH`) para renderizar HTML → PDF.
- **python-docx** para el Word del Kit. **zip** para empaquetar.
- Si hay que regenerar el Kit o algún PDF, ahí están los scripts (`gen.js`, `render-kit.js`, `make-docx.py`).

---

## 10. Cómo arrancar (para el próximo asistente)

1. Lee este documento completo.
2. Revisa los **PRs abiertos** (`list_pull_requests`) antes de crear ramas.
3. Confirma el estado de `main` (puede haber avanzado).
4. Antes de tocar `simulacion.html` u otra cosa conectada, entiende el flujo de la sección 3.
5. Trabaja siempre con rama nueva + PR. Cache-bust si tocas CSS.
6. Sé el socio honesto del dueño. ¡A construir Stramont! 🚀
