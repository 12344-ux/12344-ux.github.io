---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `CONTEXTO-MAGANDHI.md` (realidad operativa y pendientes vigentes).
2. Leer `docs/RELEVO-CUENTAS-C2-2026-10-16.md`: es el relevo más reciente.
   **C2 está desplegado en preapertura; Google GIS ya fue medido y lo siguiente
   exacto es configurar Turnstile sin encender signup todavía.**
3. Leer `docs/CUENTAS-CLIENTE.md` para las decisiones de identidad, compra como
   invitado y tramos C1–C4.
4. Solo si la tarea vuelve a Dropshipping, leer además
   `docs/dropshipping-envios/RELEVO-2026-10-10.md` y aplicar
   `.kiro/steering/dropshipping-magandhi.md`.

Realidad de arranque al 16-oct-2026:

- La migración más alta aplicada en producción es `20261101000000`.
- C1 y C2 están fusionados; migración C2 y `cuenta-inicializar` están
  desplegadas y el preflight dio todo limpio.
- Login, inicialización idempotente, SMTP, TokenHash, recuperación en otro
  navegador y cambio de contraseña están medidos.
- Google Identity Services está publicado desde la tienda PR #95 y medido en
  `External / Testing`: el selector muestra `magandhi.com`, conserva el mismo
  UID/identidad y una sola cuenta activa tras el segundo acceso.
- El registro público y CAPTCHA siguen apagados; `TURNSTILE_SITE_KEY` está
  vacía.
- `clientes.id` sigue siendo la identidad comercial; nunca reemplazarlo por el
  UID de Auth. `cuentas_cliente` es el puente.
- La tienda conserva compra como invitado y cuenta opcional.
- El próximo paso es crear el widget Turnstile administrado para
  `magandhi.com`, guardar el secret solo en Supabase y publicar primero la site
  key sin encender CAPTCHA ni signup. Después: medir CAPTCHA, registro real
  controlado y políticas.

Reglas que no cambian:

- Rama nueva + PR por cambio; migraciones forward; medir antes de afirmar.
- Cuando el dueño deba pegar o desplegar algo, dar **links directos**: el raw de
  GitHub fijado al commit probado (comprobado: responde 200 y coincide con lo
  probado) y la pantalla exacta del dashboard de Supabase
  (`https://supabase.com/dashboard/project/bxlzipwxyxdtffnuizbz/...`).
- En un sandbox nuevo, armar el banco con
  `bash supabase/pruebas/local/herramientas/preparar.sh` antes de dar algo por
  bueno.
