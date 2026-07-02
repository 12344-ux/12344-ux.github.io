---
inclusion: always
---

# CHIP STRAMONT — Cómo construimos las guías (método permanente)

> Aplica a TODA guía, de cualquier materia o cliente. Reemplaza cualquier método anterior.

## Reglas de oro
1. Cada guía es un **archivo HTML autocontenido** con su propio `<style>` inline. **NUNCA** modifiques ni enlaces `estilos.css` (es el CSS global de la home y las páginas legales; tocarlo las rompe). Todo el diseño de la guía vive dentro de su `<style>`.
2. **NUNCA** rompas `simulacion.html` (Supabase + FormSubmit + comprobante jsPDF) ni la home.
3. **NUNCA** hagas push a `main`. Entrega en **rama nueva + Pull Request**; el dueño mergea.
4. **Autonomía:** cuando llegue "nuevo cliente, revisa apuntes, desarrolla la guía y dame el link", ejecútalo sin pedir más instrucciones. Hay internet: investiga.

## 1. Filosofía
No hacemos resúmenes bonitos: hacemos que el estudiante **entienda de verdad y no lo olvide**.
- Quitamos el esfuerzo **inútil** (organizar, resumir); exigimos el esfuerzo **útil** (recordar, explicar, conectar).
- **Profundidad a elección del estudiante** según su tiempo. Nunca abrumar.
- Toda guía debe **superar lo que daría un ChatGPT plano**. Si no lo supera, se rehace.

## 2. Proceso por cada pedido
1. Lee los apuntes/tema e identifica los **conceptos que sostienen el tema**.
2. **Investiga en internet** cada concepto clave: su **porqué/para qué**, **origen etimológico** cuando ilumine, **ejemplos reales** (prioriza contexto colombiano: pesos, ciudades, marcas conocidas) y las **conexiones** entre conceptos.
3. **Elige los bloques** (§7) y **estructura** con la anatomía (§6).
4. **Construye** respetando voz (§4) y sistema visual (§5), todo dentro del `<style>` de la guía.
5. **Pasa el checklist de auto-QA (§8).** Si falla algo, corrige antes de entregar.
6. Entrega: **rama + PR** + el link de la guía (enlace privado vía sistema de entregas).

## 3. Lo que SIEMPRE se quita
- Tags condescendientes ("lo entiende un niño").
- Indicaciones de ritmo ("léela sin prisa") → las reemplaza el control Express/Dominar.
- Color como adorno rotativo sin significado.
- Fichas planas y uniformes (todas idénticas).
- Exceso de emojis decorativos.
- Sobrepromesas ("tan simple que no se te olvidará").

## 4. Voz y estilo
- Tratamiento **"tú"**, cercano, de socio que explica. Nunca corporativo ni infantil.
- **Frases cortas**, una idea por frase, cero relleno.
- **Analogías concretas** para lo abstracto, sin diminutivos condescendientes ("grupo", no "grupito").
- Respeto al lector como alguien **capaz**: explicamos desde cero sin tratar a nadie como tonto.
- Español neutro-colombiano.

## 5. Sistema visual (dentro del `<style>` de la guía)
- **Tema oscuro premium.** Fondo azul-negro (`#0B1220`), texto blanco hueso (`#E9EDF5`), nunca blanco puro.
- **El color SIGNIFICA el nivel de profundidad** (no es decoración):
  - **Teal** (`#2DD4BF`) = Nivel 1 · "La idea" (esencial, siempre visible).
  - **Índigo** (`#818CF8`) = Nivel 2 · "Conecta".
  - **Bronce/ámbar** (`#D9A066`) = Nivel 3 · "A fondo".
- **Tipografía:** sans moderna fuerte (Inter o similar). Títulos peso 700–800; cuerpo 400–500, line-height 1.6, base 17–18px, ancho de línea máx ~70 caracteres. Tags en mayúsculas, letter-spacing amplio, color muted.
- **Tarjetas:** esquinas redondeadas (12–16px), fondo `#131C2E`, borde 1px que **toma el color de su nivel**. Máximo 1 ícono funcional por bloque.

## 6. Estructura obligatoria de cada guía

**A) Encabezado**
- `STRAMONT` (wordmark espaciado, muted).
- Título del tema (grande, blanco hueso, peso 800; degradado sutil teal→índigo permitido).
- `[Materia] · Clase/Tema.` (subtítulo).
- Frase-gancho: *Del "creo que lo sé" al "lo entiendo de verdad."*
- Metadata útil: badge `MÉTODO STRAMONT` + Materia (sin emojis random).
- Control real **¿Cuánto tiempo tienes? [ Express ] [ Dominar ]** (default: Express).
  - **Express** = solo Nivel 1 de cada concepto (Niveles 2 y 3 plegados).
  - **Dominar** = despliega todo.

**B) Gancho de ilusión** (bajo el encabezado): 2–3 líneas que pinchen el "creía que lo sabía" con **una** pregunta que no podrá responder (el porqué/origen del concepto central) y remate: "no lo entendías tan bien como creías. Empecemos."

**C) Fichas de concepto** (el corazón). Cada concepto con **3 niveles**:
- **Nivel 1 · "La idea"** (teal, SIEMPRE visible): qué es (1–2 líneas) · el porqué/para qué (1 línea) · origen etimológico (solo si ilumina) · ancla visual (imagen mental) · **🧠 Pruébate** en 2 pasos ("escríbelo con tus palabras o dilo en voz alta antes de abrir" → revelar respuesta modelo).
- **Nivel 2 · "Conecta"** (índigo, PLEGADO): cómo se enlaza con otros conceptos.
- **Nivel 3 · "A fondo"** (bronce, PLEGADO): matiz, caso borde o chispa crítica profunda.

**D) Definiciones inline:** todo término difícil = span con definición al hover/click (estilo Wikipedia), sin sacar del flujo.

**E) Cierres obligatorios:**
- Un **insight de conexión** al final de cada sección.
- Un **mapa de conexiones** de todo el tema al final.
- **Caso práctico integrador** paso a paso.
- **Tabla resumen** + **ancla mnemónica** (busca el número o patrón que se repita).
- **Plan de repaso espaciado** (Hoy / En 2 días / En 1 semana) + **Autoevaluación** de recuperación.

## 7. Biblioteca de bloques (ensambla, no inventes formato)
1. **Ficha de concepto** (3 niveles) → por defecto para todo concepto.
2. **Tabla comparativa** → elementos paralelos.
3. **Mapa de conexiones** → diagrama nodal de enlaces.
4. **Flujo de pasos** → procesos y procedimientos.
5. **Mini-widget numérico** → cifras y fórmulas.
6. **Caja de chispa crítica** → insight profundo (va como Nivel 3).
7. **Resumen + ancla mnemónica.**
8. **Autoevaluación de recuperación.**
9. **Diagrama etiquetado sobre imagen** → SOLO contenido espacial (anatomía, mapas, partes) y solo si hay imagen base (bloque más costoso).

**Selección:** conceptual → ficha · comparación → tabla · proceso → flujo · números → widget · relaciones → mapa · espacial → diagrama.

## 8. Checklist de auto-QA (antes de entregar)
- [ ] Encabezado con control Express/Dominar y **sin** los elementos eliminados (§3).
- [ ] Gancho de ilusión al abrir.
- [ ] Cada concepto con Nivel 1 (porqué + origen cuando ilumina).
- [ ] Nivel 2 "Conecta" + insight de conexión por sección + mapa final.
- [ ] Color = nivel (teal/índigo/bronce), no decoración.
- [ ] Términos difíciles con definición inline.
- [ ] "Pruébate" pide generar antes de revelar.
- [ ] Modo Express se lee completo y autónomo solo con Nivel 1.
- [ ] Caso práctico + resumen + ancla mnemónica + repaso espaciado + autoevaluación.
- [ ] Bloques bien elegidos según el tipo de contenido (§7).
- [ ] Todo el CSS de la guía en su `<style>` inline; `estilos.css` intacto.
- [ ] `simulacion.html` y la home intactos.
- [ ] ¿Supera lo que daría un ChatGPT plano? Si no → se rehace.

## 9. Guardarraíles técnicos
- Sitio **estático** (GitHub Pages).
- **Aislamiento de estilos:** el CSS de cada guía va SIEMPRE en su `<style>` inline. Prohibido tocar o enlazar `estilos.css`. Las guías no dependen de `estilos.css`, así que **no requieren cache-bust** (`?v=N` solo aplica si algún día se edita el CSS global, que NO es parte del trabajo de guías).
- No romper `simulacion.html` ni la home.
- Entrega: rama nueva + Pull Request (nunca push a `main`). Devuelve el link de la guía y el link del PR.
- Cada guía se aloja como **enlace privado** listo para el cliente (sistema de entregas: bucket `guias` + visor `entrega.html` + Edge Function `entrega`).
