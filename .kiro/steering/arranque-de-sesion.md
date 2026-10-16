---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `CONTEXTO-MAGANDHI.md` (realidad operativa y pendientes vigentes).
2. Leer `docs/RELEVO-CUENTAS-C2-2026-10-16.md`: es el relevo más reciente.
   **C2 está desplegado en preapertura; Google GIS y Turnstile están medidos y
   lo siguiente exacto es un registro nuevo controlado por correo.**
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
- Signup sigue apagado. Turnstile y CAPTCHA de Supabase están activos: login y
  recuperación válidos, omisión rechazada con `captcha_failed`/400 y renovación
  tras expiración están medidos.
- `clientes.id` sigue siendo la identidad comercial; nunca reemplazarlo por el
  UID de Auth. `cuentas_cliente` es el puente.
- La tienda conserva compra como invitado y cuenta opcional.
- El próximo paso es abrir signup solo durante un registro nuevo controlado por
  correo con CAPTCHA activo; cerrarlo tras aceptar el alta y completar
  confirmación, inicialización e idempotencia. Después: Google con un usuario
  realmente nuevo y políticas.

Reglas que no cambian:

- Rama nueva + PR por cambio; migraciones forward; medir antes de afirmar.
- Cuando el dueño deba pegar o desplegar algo, dar **links directos**: el raw de
  GitHub fijado al commit probado (comprobado: responde 200 y coincide con lo
  probado) y la pantalla exacta del dashboard de Supabase
  (`https://supabase.com/dashboard/project/bxlzipwxyxdtffnuizbz/...`).
- En un sandbox nuevo, armar el banco con
  `bash supabase/pruebas/local/herramientas/preparar.sh` antes de dar algo por
  bueno.
