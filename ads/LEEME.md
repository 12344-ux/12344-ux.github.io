# Anuncios en video — Stramont (v1, estilo "hero")

Contenido de video para **anuncios/ventas**, en el estilo limpio y premium tipo
"hero" (como el asset de referencia de Claude): una animación de la **guía real**,
en loop suave, **sin audio** (el 85% del feed se ve en mute).

## Cómo se genera (cero dependencias, reproducible)
- `anuncio.html` — la escena animada (CSS keyframes, timeline fija ~12s). Adaptable
  por query: `?f=9x16` (por defecto), `?f=1x1`, `?f=16x9`. Usa las capturas reales
  de la guía como "producto".
- `assets/` — capturas reales de la guía demo (móvil + escritorio) hechas con Playwright.
- `video/` — los videos grabados (`.webm`) que salen de grabar `anuncio.html` con
  Playwright `recordVideo`. **Son artefactos de revisión** (se pueden regenerar).

Scripts (en el entorno de trabajo, no en el repo): `record-anuncio.mjs <fmt> <w> <h>`
graba el video; `stills.mjs` saca fotogramas para revisar.

## Formatos
- **9:16** (1080×1920) — Reels/Stories, TikTok, WhatsApp Estado. *(prioritario)*
- **1:1** (1080×1080) — feed de Instagram/Facebook.
- **16:9** (1920×1080) — YouTube, Facebook, web.

## Guion (v1)
1. "Tu clase entra **confusa**." (aparece la guía en un teléfono, con glow de marca)
2. La guía hace scroll suave; entran los pills **Explica simple · Pruébate · Repaso**
   y la tarjeta **HOY ENTENDÍ**.
3. "Sale como una guía **para entender**."
4. Cierre: logo + **Stramont** + *"Entiende. No solo memorices."* + montaguth.institute.

## Pendiente / notas
- **v1 sin audio.** Si se quiere, se añade música ambiente + 1–2 clics sutiles con
  ffmpeg (solo audio libre/CC0, nunca copyrighted).
- Estos `.webm` y las capturas pesan; son para revisar. Si no se quieren en `main`,
  se pueden mover a hosting aparte o borrar tras aprobar el estilo.
