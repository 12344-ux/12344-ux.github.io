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


---

# Anuncio narrativo 45s — "La hora que nunca cuenta como estudiar"

Segunda pieza, mucho más ambiciosa: un **spot con historia** (45 s, 9:16) con
**voz en off, diseño sonoro y música**, siguiendo el guion técnico del dueño
(6 escenas con arco emocional: silencio → caos → valle → revelación → calma → marca).

- `anuncio-historia.html` — la escena animada de las 6 escenas (motion graphics).
  Usa **material real del proyecto**: la foto de apuntes `apuntes-cliente.jpg`
  (mesa cenital), `apunte-seg-1/2/3.jpg` dentro de ventanas de PDF/foto/cuaderno,
  y la captura real de la guía para el reveal.
- `video/anuncio-historia.mp4` — el video final (1080×1920, 30 fps, con audio).
- `audio/mezcla.py` — **motor de diseño sonoro**: sintetiza (con numpy, sin
  librerías de audio externas) los SFX y la música, y mezcla la voz en los
  timestamps del guion. Reproducible: `python3 mezcla.py`.
- `audio/voz/01..11.mp3` — las 11 líneas de voz en off (ElevenLabs, modelo v3
  con etiquetas de emoción por escena). Se guardan para poder re-renderizar
  **sin volver a gastar créditos**.

## Escenas y sincronía
| t | Escena | Visual | Audio |
|---|---|---|---|
| 0–5 s | Caos silencioso | foto real de apuntes (Ken Burns) | silencio + 2 clics de mouse; voz "¿Te ha pasado esto?" |
| 5–10 s | Búsqueda sin sentido | ventanas PDF/foto/cuaderno/WhatsApp + cursor saltando | ráfaga de UI + pulso 85 BPM |
| 10–17 s | Preguntas | 5 preguntas en cascada sobre negro | blips sincronizados + **corte seco de silencio** |
| 17–23 s | Cansancio | contador a **20:00** "y todavía no empiezas" | UI lenta (pitch-down) → **valle de silencio** |
| 23–30 s | Revelación | la guía real aparece + "Empieza aquí" | whoosh + **pad cálido en La mayor** |
| 30–38 s | Sistema | 4 tarjetas: Idea · Ejemplo · Pruébate · Repaso | card-flips idénticos + **pausa de 1 s innegociable** |
| 38–45 s | Cierre | logo + posicionamiento + CTA | chime de marca + resolución armónica |

## Cómo re-renderizar
1. `pw/render-hist-chunk.mjs <from> <to> 30` por tramos (1350 frames @30fps).
2. `pw/render-hist-chunk.mjs encode 30` para ensamblar.
3. `audio/mezcla.py` para la pista, y muxear con ffmpeg (`-c:v copy -c:a aac`).

> Nota: la voz se generó con ElevenLabs. La clave **nunca** se guarda en el repo;
> vive fuera del árbol de trabajo y se rota al terminar.
