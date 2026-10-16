# Relevo de sesión · Cuentas C2 · preapertura · 16 de octubre de 2026

Este es el punto exacto para continuar en un chat nuevo. Leer junto con
`CONTEXTO-MAGANDHI.md`, `docs/CUENTAS-CLIENTE.md` y, en el repositorio de la
tienda, `cuenta/CONFIGURACION.md`. No volver a construir C1 ni C2 desde cero.

## 1. Estado exacto

**C2 está fusionado, publicado y desplegado, pero el registro público sigue
apagado.** Google Identity Services ya fue probado de extremo a extremo en modo
Testing. La siguiente acción es configurar Cloudflare Turnstile y solo al final
se decide la apertura.

Código fusionado el 16-oct-2026:

- Back-office/backend: PR `12344-ux/12344-ux.github.io#270`, merge
  `a62319594316bd3c2a903a259e33a3de522980ef`.
- Tienda C2: PR `12344-ux/magandhi#93`, merge
  `e17afa9eca01e79e4e109298f69aa4cb5d53e835`.
- Google Identity Services: PR `12344-ux/magandhi#95`, merge
  `558ac97a002dff578954636d57ef49fb428d6329`.
- Los workflows de backend C2, tienda C2 y Google GIS terminaron en verde.
  El banco del backend ejecutó PostgreSQL 15 + Deno 2; la tienda pasó 17/17
  contratos C2.

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

## 5. Lo que NO está cerrado todavía

- `TURNSTILE_SITE_KEY` sigue vacía en `magandhi/cuenta/cuenta-config.js`.
- Cloudflare Turnstile y CAPTCHA de Supabase siguen apagados.
- No se ha probado un registro público nuevo por correo con CAPTCHA.
- Google sigue en `Testing`; no publicar la app todavía.
- Las políticas públicas siguen en versión borrador; cerrarlas antes de una
  apertura comercial definitiva.
- No aumentar el límite Auth de 30 correos/hora antes de CAPTCHA y medición.

## 6. Siguiente paso exacto

**Configurar Cloudflare Turnstile sin encender CAPTCHA ni signup todavía:**

1. En Cloudflare Turnstile, crear un widget administrado para
   `magandhi.com`. Añadir únicamente otros hosts reales si después se necesitan.
2. Guardar el secret exclusivamente en Supabase Auth CAPTCHA; nunca en Git,
   documentación o chat. Si el panel exige habilitar CAPTCHA para guardarlo,
   detenerse y publicar primero la site key.
3. Compartir únicamente la site key pública para ponerla en
   `magandhi/cuenta/cuenta-config.js` mediante rama + PR.
4. Fusionar, esperar GitHub Pages y comprobar que el widget flexible carga en
   móvil y escritorio mientras CAPTCHA y signup siguen apagados.
5. Solo después de medir el frontend, encender CAPTCHA en Supabase y probar
   token válido, ausente y vencido antes de abrir signup.

## 7. Después de Turnstile

1. Mantener signup apagado mientras se prueba CAPTCHA en login y recuperación.
2. Abrir signup de forma controlada y probar un registro real por correo:
   confirmación, inicialización, logout/login y una sola fila.
3. Probar Google con un usuario realmente nuevo.
4. Mantener compra invitada y consentimiento de marketing separados.
5. Cerrar políticas antes de pasar Google a Production y anunciar registros.
6. Revisar el límite Auth de 30 correos/hora solo después de CAPTCHA y medición.
7. Actualizar este relevo únicamente después de medir la apertura.

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
> mismo UID/identidad y una sola cuenta activa. Signup y CAPTCHA siguen apagados.
> Empieza directamente creando el widget Turnstile administrado para
> `magandhi.com`; guarda el secret solo en Supabase y publica primero la site key
> mediante rama + PR antes de encender CAPTCHA. No repitas C1, C2, SMTP, Google
> ni recuperación.
