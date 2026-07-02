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

## 3. Lo que SIEMPRE se quita
✗ Tags condescendientes ("lo entiende un niño") · ✗ "léela sin prisa" (lo reemplaza Express/Dominar) · ✗ color decorativo sin significado · ✗ fichas planas idénticas · ✗ exceso de emojis · ✗ sobrepromesas ("tan simple que no se te olvidará") · ✗ guía 100% texto plano (debe usar bloques visuales, §7) · ✗ "Pruébate" pasivo de solo pensar→revelar (debe ser **flashcard de escritura**, §6-G).

## 4. Voz y estilo
Tratamiento **"tú"**, de socio que explica; nunca corporativo ni infantil. Frases cortas, una idea por frase, cero relleno. Analogías concretas sin diminutivos condescendientes ("grupo", no "grupito"). Respeto al lector como alguien **capaz**. Español neutro-colombiano.

## 5. Sistema visual ("todos los píxeles") — dentro del `<style>` de la guía
- **Tema oscuro premium.** Fondo `#0B1220`, texto blanco hueso `#E9EDF5` (nunca blanco puro).
- **El color SIGNIFICA el nivel de profundidad:** Teal `#2DD4BF` = Nivel 1 (la idea) · Índigo `#818CF8` = Nivel 2 (conecta) · Bronce `#D9A066` = Nivel 3 (a fondo).
- **Tipografía:** sans moderna fuerte (Inter o similar). Títulos 700–800; cuerpo 400–500, line-height 1.6, base 17–18px, ancho máx ~70 caracteres. Tags en mayúsculas con letter-spacing y color muted.
- **Tarjetas:** esquinas 12–16px, fondo `#131C2E`, borde 1px con el color de su nivel. Máximo 1 ícono funcional por bloque.

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
── Nivel 1 · La idea (teal, SIEMPRE visible) ──
· Qué es (1–2 líneas) · El porqué/para qué · Origen etimológico (si ilumina) · Ancla visual
· 🧠 FLASHCARD (ver G)
── Nivel 2 · Conecta (índigo, oculto en Express) ──
· Cómo se enlaza con otros conceptos.
── Nivel 3 · A fondo (bronce, oculto en Express) ──
· Matiz, caso borde o chispa crítica profunda.
```
No fuerces los 3 niveles en conceptos simples (buen criterio > relleno), pero el **Nivel 1 y su flashcard son obligatorios siempre**.

**C) Definiciones inline:** todo término difícil = `span` con definición al hover/click (estilo Wikipedia), sin sacar del flujo.

**G) Flashcard de generación (el gimnasio, obligatorio en cada "Pruébate")**
- Pregunta → **campo de texto** donde el estudiante ESCRIBE su respuesta → botón "Revelar y comparar" → muestra la respuesta modelo junto a lo que escribió.
- **No ve la respuesta sin escribir antes.**
- **Guarda lo escrito en `localStorage`** (clave única por pregunta) para que no se pierda al recargar.

**E) Cierres obligatorios:** insight de conexión por sección · **mapa de conexiones VISUAL** (nodos/flechas, no lista) · caso práctico integrador (como flujo de pasos) · tabla resumen + ancla mnemónica · plan de repaso espaciado (Hoy/2 días/1 semana) · autoevaluación de recuperación.

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
- [ ] Cada "Pruébate" es **flashcard con campo de escritura + localStorage. PROBADO.**
- [ ] Términos difíciles con definición inline.
- [ ] Color = nivel (teal/índigo/bronce).
- [ ] Caso práctico + resumen + ancla + repaso espaciado + autoevaluación.
- [ ] **Rigor factual:** atribuciones discutidas con matiz ("se le suele atribuir a…"), no como certeza.
- [ ] Todo el CSS en el `<style>` de la guía; `estilos.css` y `simulacion.html` intactos.
- [ ] ¿Supera a un ChatGPT plano? Si no → se rehace.

## 9. Guardarraíles técnicos
- Sitio **estático**. CSS de la guía siempre inline (prohibido tocar `estilos.css`, por eso las guías no necesitan cache-bust).
- No romper `simulacion.html` ni la home.
- Entrega en **rama + PR** (nunca push a `main`).
- Cada guía entrega un **enlace privado** (sistema de entregas: bucket `guias` + visor `entrega.html` + Edge Function `entrega`).
