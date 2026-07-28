# Vista previa — Tarjetas de comprensión (SOLO PARA REVISIÓN)

Estas imágenes son **capturas de referencia** para que el dueño vea cómo quedaron
las tarjetas descargables antes de aprobar. **NO las usa el sitio.**

Se generaron con Playwright/Chromium sobre `demo/index.html` (canvas real).

> ⚠️ Esta carpeta `preview-tarjetas/` es temporal. Se elimina cuando el dueño
> apruebe (en el PR que lleva las tarjetas al chip y a las guías de cliente),
> para que `main` no quede con archivos que el sitio no usa.

- `1-concepto-teal.png` — tarjeta "Hoy entendí" (paleta teal, con nombre)
- `2-concepto-clara.png` — misma tarjeta en paleta clara (contraste)
- `3-concepto-rosa.png` — paleta rosa
- `4-certificado-morado.png` — certificado final (paleta morado)
- `5-certificado-teal.png` — certificado final (paleta teal)
- `6-modal-escritorio.png` — el modal de personalización (escritorio)
- `7-modal-movil.png` — el modal en móvil (390px)

## Cambios de esta versión (según tu feedback)

- **Tarjetas normales (durante la guía)** — estructura fija:
  Encabezado `HOY ENTENDÍ` · Logro · Reflexión (frase corta) · Firma (tu nombre).
  El nombre ya **no** sale con el guion `—`; aparece limpio en color de acento.
- **Certificado final** — copy nuevo:
  `STRAMONT` · `HOY ENTENDÍ` · `Segmentación de Mercados` ·
  *"No basta con dividir clientes. La clave es entender por qué compran."* ·
  `✔ Tema comprendido` · **el nombre del dueño de la guía** · `montaguth.institute`.
  Se **quitó la fecha**.
- Verificado sin errores de consola en escritorio (1360px) y móvil (390px).
  La descarga genera el PNG (`stramont-...-.png`) correctamente.
