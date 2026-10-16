# Relevo de sesión · Cuentas C2 · preapertura · 16 de octubre de 2026

Este es el punto exacto para continuar en un chat nuevo. Leer junto con
`CONTEXTO-MAGANDHI.md`, `docs/CUENTAS-CLIENTE.md` y, en el repositorio de la
tienda, `cuenta/CONFIGURACION.md`. No volver a construir C1 ni C2 desde cero.

## 1. Estado exacto

**C2 está fusionado, publicado y desplegado, pero el registro público sigue
apagado.** Google Identity Services y Cloudflare Turnstile ya fueron probados de
extremo a extremo. La siguiente acción es un registro nuevo controlado por
correo; solo después se continúa hacia la apertura.

Código fusionado el 16-oct-2026:

- Back-office/backend: PR `12344-ux/12344-ux.github.io#270`, merge
  `a62319594316bd3c2a903a259e33a3de522980ef`.
- Tienda C2: PR `12344-ux/magandhi#93`, merge
  `e17afa9eca01e79e4e109298f69aa4cb5d53e835`.
- Google Identity Services: PR `12344-ux/magandhi#95`, merge
  `558ac97a002dff578954636d57ef49fb428d6329`.
- Turnstile, site key y render perezoso: PR `12344-ux/magandhi#97`, merge
  `b330c41b0951389ef494c3db26e8eb7af0a97bc4`.
- Turnstile obligatorio en formularios Auth: PR `12344-ux/magandhi#98`, merge
  `aa89177b9d9e61d134dc33ee1d3d2205f1853e5a`.
- Los workflows de backend C2 y de las entregas de tienda C2, Google GIS y
  Turnstile terminaron en verde. El banco del backend ejecutó PostgreSQL 15 +
  Deno 2; la tienda pasó 17/17 contratos C2.

Producción medida por el dueño:

- Migración máxima aplicada:
  `20261101000000_cuentas_cliente_c2.sql`.
- El preflight de solo lectura dio C1=`true`, C2=`true` y `0` en las cinco
  medidas de normalización, ambigüedad y duplicidad.
- Edge Function `cuenta-inicializar` desplegada con Verify JWT activado.
- `/cuenta/` y `/cuenta/callback/` están publicados en `magandhi.com`.
- Google Identity Services está publicado; el selector muestra `magandhi.com`
  en lugar del dominio técnico de Supabase.
- La prueba controlada conservó el mismo UID e identidad Google y exactamente
  una fila activa después del segundo acceso.
- Turnstile está activo en frontend y Supabase: login y recuperación aceptaron
  token válido, una llamada sin token devolvió `captcha_failed`/400 y el widget
  renovó el token después de expirar.
- `Allow new users to sign up` permanece **apagado**.

## 2. Qué entrega C2

- Registro e inicio por correo + contraseña.
- Google Identity Services mediante ID token validado por Supabase Auth.
- Confirmación obligatoria y recuperación con `TokenHash`; los enlaces se
  probaron abriéndolos en otro navegador.
- Callback TokenHash para correo, compatibilidad PKCE transitoria, limpieza
  inmediata de credenciales de la URL y comprobante breve/de un solo uso para
  cambiar contraseña.
- Cierre de sesión local.
- Inicialización server-side idempotente de `cuentas_cliente`.
- Vínculo histórico solo ante una coincidencia única del correo confirmado;
  cero/ambiguo/ocupado no fusionan a ciegas.
- Personal interno y cuentas bloqueadas/cerradas reciben el mismo rechazo
  opaco.
- Compra como invitado intacta; C2 no modifica checkout ni `customer_id`.

## 3. Evidencia funcional ya obtenida

Con un usuario Auth creado manualmente y autoconfirmado:

1. Login real en `magandhi.com/cuenta/`: correcto.
2. `cuenta-inicializar`: correcto.
3. `cuentas_cliente`: exactamente una fila, activa.
4. Segundo login: siguió existiendo una sola fila (idempotencia).
5. Solicitud de recuperación: correcta.
6. Resend: correo entregado desde el subdominio Auth.
7. Enlace abierto en otro navegador: correcto.
8. Nueva contraseña y login posterior: correctos.
9. La cuenta siguió en una sola fila activa.
10. El OAuth redirigido enlazó Google al mismo UID sin duplicar la cuenta.
11. Google Identity Services sustituyó el redirect visible mediante la tienda
    PR #95; el selector pasó a mostrar `magandhi.com`.
12. Dos accesos GIS en ventanas privadas regresaron sin advertencias y
    mantuvieron el mismo UID, identidad enlazada y una sola fila activa.
13. Widget Turnstile administrado medido en login, registro y recuperación, en
    móvil y escritorio; ajustes visuales menores quedaron para otra tarea.
14. Login y recuperación con token válido: correctos.
15. Solicitud sin token: rechazada por Supabase con `captcha_failed`/400.
16. Widget dejado más de cinco minutos: renovó correctamente la validación.

No registrar en documentos el correo, contraseña, UID, TokenHash, API key de
Resend ni secretos OAuth usados en estas pruebas.

## 4. Configuración externa ya completada

### Supabase Auth

- Site URL: `https://magandhi.com`.
- Redirect allowlist:
  - `https://magandhi.com/cuenta/callback/`
  - `https://magandhi.com/cuenta/callback/?flow=signup`
  - `https://magandhi.com/cuenta/callback/?flow=recovery`
- Confirmación de correo obligatoria.
- Custom SMTP guardado.
- Límite inicial de correos Auth: 30/hora.
- Plantillas `Confirm signup` y `Reset password` configuradas con enlaces
  directos a MAGANDHI y `{{ .TokenHash }}`.

### Resend

- Dominio `auth.magandhi.com` verificado mediante DNS en Porkbun.
- Región: São Paulo (`sa-east-1`).
- Remitente Auth: `MAGANDHI <cuenta@auth.magandhi.com>`.
- SMTP: `smtp.resend.com:465`, usuario `resend`.
- API key exclusiva creada y guardada únicamente en Supabase; no está en Git.
- No crear un tracking subdomain para Auth ni reescribir sus enlaces.

### Google Identity Services

Confirmado por el dueño y medido en producción:

- Proyecto Google creado.
- Audience `External`, estado `Testing`.
- Usuario de prueba agregado.
- Cliente Web creado; `https://magandhi.com` está autorizado como JavaScript
  origin.
- El callback OAuth heredado se conserva durante la transición:
  `https://bxlzipwxyxdtffnuizbz.supabase.co/auth/v1/callback`.
- Google Provider habilitado en Supabase con Client ID/Secret guardados allí.
- El botón oficial usa nonce e ID token con `signInWithIdToken`; el Client ID
  público está en el frontend y el Client Secret nunca sale de Supabase.
- Scopes limitados a identidad básica (`openid`, email y profile).
- El selector identifica `magandhi.com`; mismo UID/identidad y una fila activa
  quedaron confirmados después del segundo acceso.
- Signup público sigue apagado.

### Cloudflare Turnstile

- Widget administrado creado para `magandhi.com`.
- Site key pública en `cuenta-config.js`; secret únicamente en Supabase Auth.
- `TURNSTILE_REQUIRED=true`; CAPTCHA habilitado en Supabase.
- Render perezoso por formulario visible y token nuevo después de cada intento.
- Login, recuperación, omisión y renovación tras expiración medidos.
- Signup público sigue apagado.

## 5. Lo que NO está cerrado todavía

- No se ha probado un registro público nuevo por correo con CAPTCHA.
- No se ha probado Google con un usuario realmente nuevo.
- Google sigue en `Testing`; no publicar la app todavía.
- Las políticas públicas siguen en versión borrador; cerrarlas antes de una
  apertura comercial definitiva.
- No aumentar el límite Auth de 30 correos/hora antes de medir la apertura.

## 6. Siguiente paso exacto

**Registro nuevo controlado por correo con CAPTCHA activo:**

1. Elegir privadamente un correo real controlado que no exista en Auth ni
   pertenezca a `perfiles`. No documentarlo.
2. En una ventana privada dejar listo `https://magandhi.com/cuenta/` en la
   pestaña Crear cuenta y comprobar que Turnstile está resuelto.
3. En Supabase Auth activar `Allow new users to sign up` solo para esta prueba.
   CAPTCHA debe permanecer activo.
4. Enviar inmediatamente el registro con una contraseña fuerte.
5. Cuando el alta sea aceptada, volver a apagar signup; la confirmación del
   usuario ya creado puede continuar.
6. Abrir el correo de confirmación, volver a MAGANDHI y comprobar sesión activa
   sin advertencias.
7. Medir en Supabase exactamente un usuario confirmado y una fila activa en
   `cuentas_cliente`; `customer_id` nulo es válido.
8. Cerrar sesión, iniciar otra vez con correo/contraseña y confirmar que continúa
   existiendo una sola fila.

Si algo falla, apagar signup antes de investigar. Nunca eliminar, fusionar o
reasignar identidades manualmente para forzar la prueba.

## 7. Después del registro por correo

1. Probar Google con un usuario realmente nuevo mientras continúa en Testing.
2. Mantener compra invitada y consentimiento de marketing separados.
3. Cerrar políticas antes de pasar Google a Production y anunciar registros.
4. Revisar el límite Auth de 30 correos/hora solo después de medir apertura.
5. Actualizar este relevo únicamente después de cada medición.

## 8. Reglas que no cambian

- `auth.users.id` es acceso; `clientes.id` es identidad comercial;
  `pedidos.customer_id` sigue apuntando a `clientes.id`.
- El navegador nunca elige ni escribe `customer_id`.
- `perfiles` es personal interno; `cuentas_cliente` es cliente público.
- No poner secretos de Google, Resend, Turnstile o Supabase en Git/chat.
- No afirmar despliegue por presencia en Git: medir producción.
- Migraciones aplicadas son inmutables; cualquier corrección es forward.
- Rama y PR nuevos por cambio.

## 9. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI en C2 preapertura. Lee
> `docs/RELEVO-CUENTAS-C2-2026-10-16.md`, `CONTEXTO-MAGANDHI.md`,
> `docs/CUENTAS-CLIENTE.md` y `magandhi/cuenta/CONFIGURACION.md`. C1 y el backend
> C2 están desplegados; migración máxima `20261101000000`, preflight limpio,
> `cuenta-inicializar` con JWT y SMTP/TokenHash verificados. Google Identity
> Services está publicado y medido en External/Testing: `magandhi.com` visible,
> mismo UID/identidad y una sola cuenta activa. Turnstile y CAPTCHA de Supabase
> están activos y medidos: login/recuperación válidos, omisión rechazada con
> `captcha_failed`/400 y renovación después de expirar. Signup sigue apagado.
> Empieza directamente con un registro nuevo controlado por correo: deja el
> formulario y Turnstile listos, abre signup solo para aceptar esa alta y vuelve
> a apagarlo antes de confirmar e inicializar la cuenta. No repitas C1, C2,
> SMTP, Google, recuperación ni Turnstile.
