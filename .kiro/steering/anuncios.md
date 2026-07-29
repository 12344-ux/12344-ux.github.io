# CHIP DE ANUNCIOS — Producción de video para Stramont

> Receta probada y aprobada por el dueño (reacción: *"me voló la cabeza"*, *"una auténtica locura"*).
> Lee esto **antes** de producir cualquier pieza de video/publicidad. Guardar y reutilizar
> el pipeline; no reinventarlo. Y recordar: **siempre se puede mejorar**.

## 0. Lo que ya existe (no rehacer)
| Pieza | Archivo | Qué es |
|---|---|---|
| **Hero** (~12 s, mudo/con sonido) | `ads/anuncio.html` | Loop premium de la guía. Adaptable `?f=9x16\|1x1\|16x9` |
| **Narrativo** (45 s, con voz) | `ads/anuncio-historia.html` | Spot con historia, 6 escenas, arco emocional |
| Motor de audio | `ads/audio/mezcla.py` | Síntesis de SFX + música + mezcla de voz (numpy) |
| Voz en off | `ads/audio/voz/01..11.mp3` | 11 líneas ya generadas (re-render sin gastar créditos) |
| Videos | `ads/video/*.mp4` | Entregables (artefactos regenerables) |

## 1. Pipeline técnico de video (OBLIGATORIO)
**Nunca grabar pantalla.** `recordVideo` de Playwright usa bitrate bajo (VP8) y produce
**banding/"remolinos"** en los degradados oscuros de la marca. En su lugar:

1. La escena web expone `window.__seek(t_ms)`: pausa `document.getAnimations()` y fija
   `currentTime` (o, mejor, una función `frame(t)` que calcula todo por tiempo — más
   determinista). Activar con `?render=1` y avisar con `window.__renderReady`.
2. Capturar **PNG sin pérdida** cuadro por cuadro a 30 fps.
3. Ensamblar con el **ffmpeg estático** (libx264, `-crf 16..17`, `-preset slow`,
   `format=yuv420p`, `-movflags +faststart`).
4. Añadir **capa de grano** (`.grain`, `feTurbulence` en SVG data-URI, `opacity:.06`,
   `mix-blend-mode:overlay`) → rompe el banding y da textura fílmica.

⚠️ **Trampas que ya nos costaron tiempo:**
- **NO** usar `page.screenshot({animations:'disabled'})` con `__seek`: Playwright salta las
  animaciones a su **estado final** y todos los cuadros salen idénticos.
- **Renderizar POR TRAMOS** (~230 cuadros por llamada). Una sola llamada larga **se aborta**.
  Script: `render-hist-chunk.mjs <from> <to> <fps>` acumulando en un directorio + `encode` final.
- Supersample a 2x es **demasiado lento** (timeouts). Escala 1 basta: el problema era la
  compresión, no la resolución.
- ffmpeg del sistema no existe y el de Playwright es mínimo (sin H.264). Instalar el estático:
  descargar `ffmpeg-release-amd64-static.tar.xz` y descomprimir con Python (`lzma`), porque
  `xz` no está disponible.
- Entregar **siempre MP4 (H.264)**, no solo WebM: el WebM no se reproduce en iPhone/Safari.
- Los screenshots full-page muy altos superan el límite de 8000 px → usar `deviceScaleFactor: 1`.

## 2. Pipeline de audio
- **Voz: ElevenLabs, modelo `eleven_v3`** — acepta **etiquetas de emoción** (`[whispering]`,
  `[tired]`, `[sighs]`, `[weary]`, `[warm]`, `[calm]`, `[confident]`), ideales para dirección
  actoral por escena. Voz usada: *Will – Relaxed Optimist* (`bIHbv24MWmeRgasZH58o`).
  Generar **una línea por frase** (control fino de timing), medir duraciones con `ffprobe`
  y **ajustar el timeline a la voz real** (no al revés).
- **SFX y música: sintetizados con numpy** en `ads/audio/mezcla.py` (sin librerías de audio).
  Incluye clics, ráfaga de UI, blips, whoosh, card-flips, chime con cola de reverb, kick de
  pulso (85 BPM), drone tenso y pad en La mayor. **Ducking** automático: la música baja
  ~4,7 dB mientras habla la voz.
- **Niveles:** voz ≈ −6 dB · música ≈ −18 dB (−12 dB en silencios de voz) · SFX ≈ −10 dB.
  Cerrar con limitador suave (`tanh`) y fade de 1,5 s.
- **Verificación sin poder oír** (hacerlo siempre y reportarlo):
  1. Etiquetas: generar la frase **con y sin** etiquetas → si la etiquetada dura **menos**,
     se interpretan y no se leen en voz alta.
  2. `volumedetect`: media ≈ −17/−22 dB, pico ≈ −2 dB → hay voz real, sin clipping.
  3. **RMS por segundo** de la mezcla → confirma el arco (silencios, clímax, valle, pausas).
- **Entregar dos versiones:** con sonido y **muda** (≈85 % del feed se ve en mute; algunas
  plataformas ponen su propia música).

## 3. Reglas creativas (marca)
- **Estilo "hero" limpio y premium.** Nada de anuncios recargados ni gamificación infantil.
- Paleta de marca: fondo oscuro, **teal `#2DD4BF`**, índigo, ámbar. **Sin emojis** (iconografía
  Lucide inline). Tipografía Fraunces + Inter/DM Sans.
- **Mensaje central** (§2L del CONTEXTO): *la transformación, no el insumo* →
  "Tu clase entra **confusa**. Sale como una guía **para entender**".
  Cierre de marca: *"Organizamos el conocimiento. Para que tú solo tengas que entender."*
- **Subtítulos SIEMPRE** (el feed se ve en mute) y sincronizados a la voz real, con un
  `scrim` degradado detrás cuando hay foto para que se lean.
- **Material auténtico > stock.** Usar las fotos reales del proyecto: `apuntes-cliente.jpg`
  (mesa cenital de apuntes), `apunte-seg-1/2/3.jpg`, `guia-segmentacion-nueva.jpg`, y las
  capturas reales de la guía (`ads/assets/`). El contraste caos-real → producto-premium es
  la magia de la marca.
- **Arco emocional que funcionó** (spot narrativo): silencio incómodo → caos creciente →
  valle de fatiga → quiebre/alivio → calma segura → resolución de marca. El **silencio** es
  tan importante como el sonido; las **pausas dramáticas no se recortan**.
- **Honestidad:** cero sobrepromesas ("garantizado", "domina cualquier examen").

## 4. Formatos
- **9:16** (1080×1920) — Reels, Stories, TikTok, estado de WhatsApp. *(prioritario)*
- **1:1** (1080×1080) — feed de Instagram/Facebook.
- **16:9** (1920×1080) — YouTube, Facebook, web.
Una sola escena adaptable por query (`?f=`) y layouts por clase `.f-9x16 / .f-1x1 / .f-16x9`.

## 5. Material que aporta el dueño (`ads/fuentes/`)
Si el dueño entrega imágenes/fotos propias, van en **`ads/fuentes/`** (subcarpeta por
campaña, ej. `ads/fuentes/2026-08-lanzamiento/`). Recomendaciones a pedirle:
- **Vertical o cuadrada** cuando sea para 9:16, y **≥1500 px** en el lado corto.
- **Sin texto quemado** encima (el texto lo ponemos nosotros, así se puede traducir/ajustar).
- Que incluyan **momentos humanos**: manos escribiendo, escritorio real, alguien estudiando
  de noche, el celular en la mano. Eso es lo que no podemos fabricar y lo que más conecta.
- Nombrar los archivos descriptivamente (`mesa-desordenada-01.jpg`, `manos-cuaderno-02.jpg`).
⚠️ **Licencias:** solo usar imágenes **propias del dueño** o con licencia libre/CC0 verificable.
Nunca imágenes tomadas de internet sin derechos, ni logos/marcas de terceros (salvo Wompi
según sus lineamientos, como en `por-que-wompi.html`).

## 6. Seguridad de claves (API)
- Las claves (ElevenLabs, etc.) **NUNCA** se guardan en el repositorio. Van en un archivo
  fuera del árbol de trabajo con permisos `600`.
- Pedirlas **restringidas** (solo Text-to-Speech) y con **límite de créditos**.
- Recordarle al dueño **rotarlas** al terminar si las escribió en el chat.
- Verificar antes de subir: `grep -rIl -E "sk_[0-9a-f]{32}" . --exclude-dir=.git`.
- La clave de **Gemini falló** (formato `AQ.Ab8…` → `ACCESS_TOKEN_TYPE_UNSUPPORTED`; la API
  espera `AIza…`). Si se reintenta Gemini, pedir una API key de AI Studio válida.

## 7. Checklist antes de entregar
- [ ] Render **frame a frame** (no grabación), con grano, CRF ≤ 17, MP4 H.264 + `faststart`.
- [ ] 0 errores de consola en la escena (`pageerror`).
- [ ] Subtítulos sincronizados con la voz real; legibles sobre foto (scrim).
- [ ] Audio verificado (etiquetas, `volumedetect`, RMS por segundo) y niveles respetados.
- [ ] Versión **con sonido** y **muda**.
- [ ] Formatos pedidos (por defecto 9:16) sin desbordes ni recortes de texto.
- [ ] **Enlaces directos de descarga** (raw de GitHub con el SHA del commit) en la respuesta.
- [ ] Sin claves en el repo. CONTEXTO §2O actualizado.
