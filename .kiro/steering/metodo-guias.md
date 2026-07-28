---
inclusion: always
---

# CHIP STRAMONT — VERSIÓN DEFINITIVA

> Cómo construimos TODAS las guías, de cualquier materia o cliente. Reemplaza cualquier versión anterior.

## ⛔ Reglas de oro (léelas antes de tocar nada)
1. Cada guía es un **HTML autocontenido** con su propio `<style>` inline. **NUNCA** modifiques ni enlaces `estilos.css` (es el CSS global de la home y las páginas legales; si lo tocas, las rompes).
2. **NUNCA** rompas `simulacion.html` (Supabase + FormSubmit + comprobante) ni la home. Si tu cambio los toca, está mal.
3. **NUNCA** hagas push a `main`. Entrega en **rama nueva + Pull Request**; el dueño hace merge.
4. **Autonomía:** con este chip, ante "nuevo cliente, revisa apuntes y haz la guía", ejecutas sin pedir más instrucciones. Tienes internet: investiga tú.

## 1. Filosofía
No hacemos resúmenes bonitos: hacemos que el estudiante **entienda de verdad y no lo olvide**.
- Le quitamos el esfuerzo **inútil** (organizar/resumir); le exigimos el esfuerzo **útil** (recordar, escribir, conectar). Montamos el gimnasio y lo obligamos a levantar la pesa.
- **Profundidad a elección del estudiante** según su tiempo.
- Toda guía debe **superar lo que daría un ChatGPT plano**. Si no lo supera, se rehace.

## 2. Tu proceso por cada pedido
1. Lee los apuntes/tema e identifica los **conceptos que sostienen el tema**.
2. **Investiga en internet** por concepto clave: porqué/para qué, etimología cuando ilumine, ejemplos reales (prioriza contexto colombiano), y las conexiones entre conceptos.
3. **Busca LA joya del tema:** el insight que unifica varios conceptos en una sola idea (raíz compartida, patrón) y la etimología que explique el nombre mismo de la materia/tema. Es **obligatorio** hallarla y hacerla explícita.
4. **Elige bloques (§7)** y **estructura (§6)**.
5. **Construye** con la voz (§4) y el sistema visual (§5), todo dentro del `<style>` de la guía.
6. **Pasa el checklist de auto-QA (§8).** Si falla una casilla, corrige antes de entregar.
7. Entrega: **rama + PR + link**.

## 2.5 · Instrucciones adicionales del cliente (opcional)
Algunos clientes, al comprar, dejan instrucciones adicionales además de sus apuntes (para qué usan la guía, qué les cuesta, algo puntual a no dejar fuera). Esto no siempre estará presente — la mayoría de pedidos serán solo "nuevo cliente, revisa Supabase y haz la guía", sin más contexto, y así deben funcionar perfectamente igual.

Cuando el pedido venga acompañado de un mensaje tipo "esto dijo adicionalmente el cliente: [...]", trátalo como una **capa de prioridad sobre el método, no como un reemplazo**:

- Si dice **"tengo examen pronto"** → la guía arranca en **modo Express** por defecto (en vez de Express genérico, ajusta el énfasis hacia lo esencial y el caso práctico; no recortes contenido, solo el punto de partida).
- Si dice **"quiero entender a fondo"** → arranca en **modo Dominar** por defecto.
- Si menciona **qué le cuesta** → dedica un poco más de profundidad (Nivel 2/3, ejemplos extra) a esos conceptos puntuales, sin desequilibrar el resto de la guía.
- Si da una **instrucción puntual** (ej. "mi profesor insiste en el caso práctico") → asegúrate de que esa parte de la guía quede reforzada o más desarrollada.

**Nunca ignores el método base por seguir una instrucción del cliente** (sigue aplicando gancho, niveles, flashcards, bloques, etc.). Las instrucciones adicionales afinan la guía, no la sustituyen.

## 3. Lo que SIEMPRE se quita
✗ Tags condescendientes ("lo entiende un niño") · ✗ "léela sin prisa" (lo reemplaza Express/Dominar) · ✗ color decorativo sin significado · ✗ fichas planas idénticas · ✗ **emojis** (toda la iconografía es **SVG de Lucide embebidos inline**, §5) · ✗ sobrepromesas ("tan simple que no se te olvidará") · ✗ guía 100% texto plano (debe usar bloques visuales, §7) · ✗ "Pruébate" pasivo de solo pensar→revelar (debe ser **flashcard de escritura**, §6-G) · ✗ **progreso guardado falso** ("68% completado") · ✗ **botón para descargar/compartir la GUÍA** (el HTML/PDF; el acceso es web efímero) — **excepción:** las **tarjetas de comprensión** descargables (§5.6) SÍ son núcleo y SÍ se quedan · ✗ **estado persistente en flashcards** (`localStorage`): la práctica es **sin memoria** entre visitas · ✗ **dependencias externas** (fuentes de CDN, íconos de CDN/npm): la guía es 100% autocontenida (§5).

## 4. Voz y estilo
Tratamiento **"tú"**, de socio que explica; nunca corporativo ni infantil. Frases cortas, una idea por frase, cero relleno. Analogías concretas sin diminutivos condescendientes ("grupo", no "grupito"). Respeto al lector como alguien **capaz**. Español neutro-colombiano.

## 5. Sistema visual ("todos los píxeles") — dentro del `<style>` de la guía
**Look editorial premium (ESTÁNDAR APROBADO).** Todo va dentro del `<style>` inline de la guía; nada de CDN ni archivos externos. El esqueleto de referencia es `demo/index.html`.

- **Tema oscuro navy.** Fondo `#0B1220`, superficies `#121B2E`/`#182338`, texto blanco `#FFFFFF`, texto atenuado `#A8B0B8`, muted `#7C8AA3`. Más aire: line-height ~1.68.
- **COLOR DISCIPLINADO — un solo acento + un secundario.** El acento principal es **teal brillante `#2DD4BF`** (el mismo del hero de la landing). El secundario es **ámbar `#C9A24B`**, reservado SOLO a: la joya del tema, término clave, chispa crítica, ancla mnemónica y tips. **Rechazados por el dueño:** el verde `#3CA98F` ("pesado"). Nada de una paleta de colores decorativa.
- **EL NIVEL DE PROFUNDIDAD SE DISTINGUE POR INTENSIDAD DEL MISMO TEAL, no por hue distinto.** (Esto reemplaza el viejo esquema teal/índigo/bronce, que ya NO se usa.)
  - Nivel 1 "La idea" (siempre visible) = teal `#2DD4BF`.
  - Nivel 2 "Conecta" (oculto en Express) = teal claro `#67E8D6`.
  - Nivel 3 "A fondo" (oculto en Express) = teal profundo `#14B8A6`.
- **Tipografía de 2 familias, AUTO-HOSPEDADA (cero dependencias):**
  - **Fraunces** (serif display, con eje óptico) para títulos, encabezados y énfasis; **Inter** (sans) para el cuerpo, UI, tags y flashcards. Ambas son **variables**.
  - **Se EMBEBEN en base64 dentro de `@font-face` en el `<style>`** — NUNCA se cargan desde Google Fonts ni ningún CDN (eso rompía la regla de "guía autocontenida"). Subsets **latin + latin-ext** (latin-ext es obligatorio: cubre los macrones de etimologías griegas/latinas: ā ē ī ō ū). Como son variables, basta **una cara por familia y subset** con `font-weight:100 900` (no repetir el base64 por peso). Copia los `@font-face` ya listos de `demo/index.html`.
  - Fallbacks en el `font-family` por si acaso: `"Fraunces",Georgia,serif` y `"Inter",system-ui,sans-serif`. Títulos 600–800; cuerpo 400–500. Tags en mayúsculas con letter-spacing y color muted.
- **ICONOGRAFÍA = SVG de Lucide EMBEBIDOS INLINE** (licencia ISC, copiados directo del set — **sin CDN, sin npm, cero dependencias**). Clase única **`.lic`** (`fill:none; stroke:currentColor; stroke-width:1.8`) para que **cada ícono herede el color de su sección**. Deja la atribución a Lucide en un comentario. **Prohibidos los emojis.**
- **Tarjetas:** esquinas 12–16px, fondo de superficie, borde 1px con el teal de su nivel. Máximo 1 ícono funcional por bloque. Textura de fondo sutil (glow radial teal + grano) permitida, pero **a `z-index:-1`** (ver lección de capas en §5.5).

## 5.5 · Layout "tablero de estudio" (ESTÁNDAR VISUAL OBLIGATORIO — aprobado por el dueño)
**Toda guía nueva usa este layout.** El esqueleto de referencia es `demo/index.html` (la guía demo): **cópiala como base** y reemplaza el contenido. ⚠️ **La demo tiene bloques SOLO-DEMO que NO van en una guía de cliente** (todos marcados con el comentario `SOLO DEMO`): la barra con el CTA "Quiero mi guía" y el "← Inicio", el CTA grande del final, y los tags Open Graph/preview del `<head>`. **Quítalos siempre** al armar la guía de un cliente — una guía de cliente se entrega por link privado (bucket `guias`), así que NO lleva CTA de compra, ni "Inicio", ni vista previa social. ⚠️ **NO confundas los bloques SOLO-DEMO con las tarjetas de comprensión** (`.momento`/`.certi` + el modal `#tarjetaModal` + su CSS y su script): esas están marcadas `NÚCLEO de guía` y **SÍ se quedan** en toda guía de cliente (§5.6); solo se les adapta el copy al tema nuevo. **Mobile-first**: la mayoría estudia en el celular; prueba SIEMPRE en móvil y PC.
- **Barra superior fija:** wordmark STRAMONT · título del tema · **tiempo estimado** (texto estático, ej. "~15 min") · **barra de progreso honesta** (se llena solo con el scroll, SIN estado guardado). En móvil aparece el botón **hamburguesa**.
- **Nav lateral izquierda (sticky):** enlaces-ancla a **Introducción · Conceptos clave · Ejemplos reales · Preguntas de práctica · Plan de repaso · Glosario**, con scroll-spy que resalta la sección visible. La sección activa lleva **estado claro**: barra izquierda teal + tinte de fondo + ícono en teal. El control **Express/Dominar** vive abajo del nav. En móvil el nav es un **drawer** que abre la hamburguesa (con backdrop).
- **Rail derecho "Activa tu aprendizaje" (sticky) — RAIL INTELIGENTE y PROTAGONISTA:** muestra la **flashcard de la ficha que el lector está viendo** (scroll-spy con `IntersectionObserver`). Va destacado (ícono de cerebro teal con glow propio, foco teal en el input). En móvil se vuelve **barra inferior plegable**. Es la pieza estrella: el "Pruébate" deja de ir inline y se centraliza aquí. La flashcard es **re-practicable** (botón `railReset` que oculta la respuesta, limpia el input y reinicia — ver §6-G).
- **Cómo se conecta el rail:** cada elemento recordable (ficha u otro bloque) lleva `class="recall"` + `data-q="pregunta"` y `data-a="respuesta modelo"`. El JS observa los `[data-q]` y actualiza el rail con el que esté en pantalla.
- **Lección de capas (z-index) — importante:** NO le pongas `z-index` al contenedor `.app`. Al hacerlo se crea un contexto de apilamiento que **atrapa el drawer/sidebar `fixed` por debajo del backdrop** (que vive a nivel de `body`), y el `backdrop-filter:blur` lo borronea. Solución: la **textura de fondo va a `z-index:-1`** (detrás de todo) y `.app` **sin z-index**; así el sidebar (z-index alto) vuelve al contexto raíz por encima del backdrop.
- El motor pedagógico **no cambia** (nivel = intensidad de teal §5, Express/Dominar, generar-antes-de-revelar). Es rediseño visual.

## 5.6 · Tarjetas de comprensión descargables (NÚCLEO — va en TODA guía, aprobado por el dueño)
Momentos "para compartir": el estudiante descarga una **imagen PNG bonita** (1080×1350, formato historia/post) que dice **"HOY ENTENDÍ …"**. No es publicidad invasiva — parece un diario de estudio, con un discreto `montaguth.institute` abajo. Es nuestra jugada de **crecimiento orgánico** (la gente comparte identidad, no anuncios). **La ÚNICA descarga permitida** en la guía (la guía en sí nunca se descarga, §3).

**Ya está construida en el esqueleto `demo/index.html`** (CSS `.momento`/`.certi`/`#tarjetaModal`/`.tm-*`, el modal y su `<script>` al final). Es **cero dependencias**: se dibuja en `<canvas>` con las fuentes Fraunces+Inter ya embebidas. **Cópiala tal cual** y **solo cambia los `data-*` y el copy** al tema de la guía nueva. No la borres al quitar los bloques SOLO-DEMO.

**Dónde van los botones (con criterio, no en cada concepto — si sobran, se abaratan):**
- **Tarjetas "momento" (`.momento`, `data-tipo="concepto"`)** — exactamente **1 o 2 por guía**, justo **al cerrar un hito real**: al terminar el bloque de conceptos clave y/o después del **caso práctico integrador**. Es el instante de "por fin lo entendí".
- **Certificado (`.certi`, `data-tipo="certificado"`)** — **UNO solo, al final** de la guía (sección propia antes del `footer`), como cierre: "comprendiste este tema".

**Estructura de copy FIJA (respétala; el dueño la aprobó así):**
- **Momento:** encabezado fijo `HOY ENTENDÍ` → **Logro** (`data-logro`, el logro concreto de ese punto, ej. "Aplicar la segmentación a un caso real") → **Reflexión** (`data-reflexion`, **una frase corta que haga pensar**, tono diario de estudio, NUNCA publicidad, ej. "Entender un concepto es útil. Poder aplicarlo es cuando de verdad se vuelve tuyo.") → **Firma** (el nombre, que pinta el motor). El `.momento-txt` de al lado es contextual ("Acabas de resolver un caso completo. Guarda la tarjeta de este avance.").
- **Certificado:** `STRAMONT` → `HOY ENTENDÍ` → **Tema** (`data-tema`, el nombre del tema) → **frase joya** entre comillas (`data-reflexion`, la idea que unifica el tema — la joya, §2 paso 3) → pill `✔ Tema comprendido` → **nombre del dueño de la guía** → `montaguth.institute`. **Sin fecha.**

**Nombre del comprador (pre-rellenado):** el motor lee `document.body[data-nombre]`. Al **construir la guía de un cliente**, hornea su nombre en el `<body>`: `<body class="modo-express" data-nombre="Nombre del comprador">` (lo sabes por el pedido en Supabase). El campo del modal queda **editable** por si quiere otro. En la **demo** va vacío (el visitante lo escribe). Verificado: dentro del `<iframe srcdoc>` de `entrega.html` (sin `sandbox`) el nombre se pre-rellena, el canvas dibuja y la descarga dispara, en escritorio y móvil.

**Colores:** 6 paletas **curadas** (teal por defecto · ámbar · azul · morado · rosa · clara). **No** pongas selector libre de color — protege el look premium de marca.

**Al adaptar a un tema nuevo:** cambia `data-logro`/`data-reflexion`/`data-tema` y el `.momento-txt`; deja intactos el modal, el CSS y el `<script>` del motor. **Pruébalo en móvil 390px y PC:** modal completo sin cortes, 0 errores de consola, la descarga genera el PNG.

## 6. Estructura obligatoria

**A) Encabezado**
```
STRAMONT                                   (wordmark, letra espaciada, muted)
[Título del tema]                          (grande, blanco hueso, peso 800)
[Materia] · Clase/Tema
[ GANCHO DE ILUSIÓN: 2–3 líneas ]          (OBLIGATORIO)
[ badge: MÉTODO STRAMONT ]  [ Materia ]
¿Cuánto tiempo tienes?  [ Express ]  [ Dominar ]
```
- **Gancho de ilusión (obligatorio):** presenta el tema → lanza una pregunta que el estudiante no podrá responder (el porqué/origen del concepto central) → remata: "no lo entendías tan bien como creías. Empecemos."
- **Control Express/Dominar — DEBE SER FUNCIONAL, no decorativo:**
  - **Express** (por defecto): muestra solo el Nivel 1; Niveles 2 y 3 ocultos.
  - **Dominar:** revela Niveles 2 y 3 en todas las fichas.
  - **Implementación:** envuelve cada Nivel 2 y 3 en contenedores `.nivel2`/`.nivel3`; alterna clase en `<body>` (`modo-express`/`modo-dominar`) con JS; CSS: `body.modo-express .nivel2, body.modo-express .nivel3{display:none}`. Arranca en `modo-express`. **Verifica que oculte/muestre de verdad** (pruébalo).

**B) Fichas de concepto (3 niveles)**
```
[nº] Concepto
── Nivel 1 · La idea (teal #2DD4BF, SIEMPRE visible) ──
· Qué es (1–2 líneas) · El porqué/para qué · Origen etimológico (si ilumina) · Ancla visual
· FLASHCARD (ver G) — se surface en el rail, no inline
── Nivel 2 · Conecta (teal claro #67E8D6, oculto en Express) ──
· Cómo se enlaza con otros conceptos.
── Nivel 3 · A fondo (teal profundo #14B8A6, oculto en Express) ──
· Matiz, caso borde o chispa crítica profunda.
```
No fuerces los 3 niveles en conceptos simples (buen criterio > relleno), pero el **Nivel 1 y su flashcard son obligatorios siempre**.

**C) Definiciones inline (accesibles en móvil — OBLIGATORIO):** todo término difícil = `span.def` con la definición en un atributo **`data-def`** (NUNCA el `title` nativo: solo funciona con hover de mouse → **inservible en móvil**). El tooltip es un **único elemento con `position:fixed`** posicionado por JS y **limitado a los bordes del viewport**, de modo que **ningún contenedor con `overflow:hidden`** (tarjetas redondeadas) lo pueda recortar. Debe abrir con **hover (escritorio) + foco (teclado) + TAP (móvil)** y cerrarse al tocar fuera / `Esc` / scroll. El tap **siempre muestra** (no alterna: en táctil el `mouseenter` sintético lo abriría y un toggle lo cerraría al instante). Copia el patrón ya probado de `demo/index.html` (bloque `.def` / `.def-tip` + su script).

**G) Flashcard de generación (el gimnasio, obligatorio en cada "Pruébate")**
- Pregunta → **campo de texto** donde el estudiante ESCRIBE su respuesta → botón "Comprobar/Revelar" → muestra la respuesta modelo junto a lo que escribió.
- **No ve la respuesta sin escribir antes.**
- **Re-practicable (OBLIGATORIO, no es de un solo uso):** al revelar debe aparecer un **"↺ Intentar de nuevo"** (SVG, no glifo de fuente) que **oculta la respuesta modelo, limpia el campo y reinicia el flujo** → se puede practicar el recuerdo activo cuantas veces se quiera. Sin esto el recuerdo activo pierde el sentido (solo serviría para responder una vez). Copia el patrón `railReset` de `demo/index.html`.
- **Vive en el RAIL "Activa tu aprendizaje" (§5.5), no inline.** Cada ficha declara `class="recall"` + `data-q`/`data-a`; el rail muestra la de la ficha visible (scroll-spy).
- **SIN `localStorage`** (la práctica es "sin memoria" entre visitas; en la misma sesión sí conserva lo escrito al desplazarte). Decisión de marca: nada de estado persistente hasta que exista la plataforma con cuentas.

**E) Cierres obligatorios:** insight de conexión por sección · **mapa de conexiones VISUAL** (nodos/flechas, no lista) · caso práctico integrador (**flujo horizontal** de pasos) · tabla resumen + ancla mnemónica · plan de repaso espaciado (Hoy/2 días/1 semana) · autoevaluación de recuperación (sección "Preguntas de práctica") · **glosario** de términos clave (sección propia, en el nav).

**F) Tablas responsivas:** toda `<table>` usa `class="responsive"` + `data-label` en cada `<td>` → en escritorio es tabla, en móvil se apila como tarjetas. Callouts de **"término clave"** (ámbar `#C9A24B`, con ícono Lucide) para los conceptos centrales.

## 7. Biblioteca de bloques (obligatorio usar los que apliquen; nada de todo-texto)
Elige el bloque que MEJOR represente cada contenido:
1. **Ficha de concepto** (3 niveles) → por defecto.
2. **Tabla comparativa** → elementos paralelos (varios tipos, opciones).
3. **Cuadrícula/2×2** → marcos como FODA.
4. **Mapa de conexiones visual** → relaciones entre conceptos (nodos y flechas).
5. **Flujo de pasos** → procesos y casos prácticos.
6. **Mini-widget numérico** → cifras/fórmulas (promedios, proyecciones, cálculos visibles).
7. **Caja de chispa crítica** → insight profundo (va como Nivel 3).
8. **Resumen + ancla mnemónica** y 9. **Autoevaluación**.
9. **Diagrama etiquetado sobre imagen** → SOLO contenido espacial (anatomía, mapas) con imagen base (el más costoso: úsalo solo si el contenido es realmente espacial).

**Regla de selección:** conceptual→ficha · comparación→tabla · marco→cuadrícula · relaciones→mapa visual · proceso→flujo · números→widget · espacial→diagrama.

## 8. Checklist de auto-QA (antes de entregar)
- [ ] Gancho de ilusión al abrir.
- [ ] Express oculta N2/N3 y Dominar los muestra. **PROBADO en el navegador.**
- [ ] Cada concepto con Nivel 1 + su porqué (etimología cuando ilumine).
- [ ] Hallé y expliqué **LA joya** que unifica el tema + la etimología del nombre de la materia.
- [ ] Nivel 2 "Conecta" + insight de conexión por sección + **mapa de conexiones VISUAL** (no lista).
- [ ] Usé los bloques que aplicaban (tabla/cuadrícula/flujo/widget), no todo texto.
- [ ] Cada "Pruébate" es **flashcard de escritura en el RAIL inteligente (§5.5), SIN localStorage. PROBADO** (el rail cambia de pregunta según la sección visible; no revela sin escribir).
- [ ] Términos difíciles con definición inline **accesible por hover Y por TAP, con tooltip `position:fixed` que NO se recorta en móvil. PROBADO en móvil.**
- [ ] Color = nivel por **intensidad de teal** (n1 `#2DD4BF` / n2 `#67E8D6` / n3 `#14B8A6`); ámbar `#C9A24B` solo para joya/término/chispa/ancla/tips (§5).
- [ ] **Tipografía Fraunces (títulos) + Inter (cuerpo) AUTO-HOSPEDADA en base64** (`@font-face` inline, subsets latin + latin-ext). CERO `<link>` a Google Fonts u otro CDN. **Verificado que no hay peticiones externas.**
- [ ] **Iconografía = SVG de Lucide inline** (clase `.lic`, `currentColor`). CERO emojis, cero CDN.
- [ ] **Layout de tablero (§5.5):** barra superior (tiempo + progreso de scroll), nav lateral con secciones + glosario (con estado activo teal) y rail "Activa tu aprendizaje" protagonista. **Probado en móvil Y en PC.**
- [ ] Tablas con `class="responsive"` + `data-label` (se apilan como tarjetas en móvil).
- [ ] NO hay progreso guardado falso, NI botón para descargar/compartir **la guía** (el HTML/PDF).
- [ ] **Tarjetas de comprensión (§5.6):** 1–2 `.momento` en hitos reales + **1** `.certi` al final; copy adaptado al tema (logro/reflexión/tema/frase joya); nombre pre-rellenado con `body[data-nombre]` (guía de cliente); las 6 paletas. **PROBADO en móvil Y PC:** modal completo sin cortes, 0 errores, la descarga genera el PNG.
- [ ] Caso práctico + resumen + ancla + repaso espaciado + autoevaluación.
- [ ] **Rigor factual:** atribuciones discutidas con matiz ("se le suele atribuir a…"), no como certeza.
- [ ] Todo el CSS en el `<style>` de la guía; `estilos.css` y `simulacion.html` intactos.
- [ ] ¿Si hubo instrucciones adicionales del cliente, quedaron reflejadas en el modo por defecto y/o el énfasis de la guía?
- [ ] ¿Supera a un ChatGPT plano? Si no → se rehace.

## 9. Guardarraíles técnicos
- Sitio **estático**. CSS de la guía siempre inline (prohibido tocar `estilos.css`, por eso las guías no necesitan cache-bust).
- No romper `simulacion.html` ni la home.
- Entrega en **rama + PR** (nunca push a `main`).
- Cada guía entrega un **enlace privado** (sistema de entregas: bucket `guias` + visor `entrega.html` + Edge Function `entrega`).
