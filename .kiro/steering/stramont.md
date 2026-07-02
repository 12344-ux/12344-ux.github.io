---
inclusion: always
---

# Proyecto Stramont — instrucción permanente

Este repositorio es **Stramont** (montaguth.institute), un sitio **estático** en GitHub Pages
que vende guías de estudio hechas a partir de apuntes.

➡️ **ANTES DE HACER CUALQUIER CAMBIO, lee el archivo `CONTEXTO-STRAMONT.md` en la raíz del repo.**
Contiene el modelo de negocio, integraciones conectadas, convenciones y pendientes.

➡️ **PARA CONSTRUIR CUALQUIER GUÍA, sigue el método en `.kiro/steering/metodo-guias.md` (CHIP STRAMONT).**
Define filosofía, voz, sistema visual, estructura obligatoria, biblioteca de bloques y checklist de auto-QA. Reemplaza cualquier método anterior.

## Reglas críticas (resumen)
- NUNCA push directo a `main`. Siempre rama nueva → PR → el dueño hace merge.
- Una rama ya mergeada NO se reutiliza; cambios nuevos = PR nuevo.
- Si tocas `estilos.css`, sube el `?v=N` (cache-bust) en el `<link>`.
- NO romper lo conectado: `simulacion.html` (Supabase Storage + FormSubmit + comprobante jsPDF).
- Supabase: bucket `apuntes`; usar solo la llave **publishable** (pública). Nunca la `service_role`.
- Pasarela = **Wompi** (Stripe no cobra en Colombia). Pedir solo el link público, no claves.
- Trato: socio honesto y directo, explica el porqué, cero humo, mantén la línea ética/legal.
