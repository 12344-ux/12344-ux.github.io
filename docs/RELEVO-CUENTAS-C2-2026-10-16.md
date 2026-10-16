# Relevo de sesión · Cuentas C2 · preapertura · 16 de octubre de 2026

Este es el punto exacto para continuar en un chat nuevo. Leer junto con
`CONTEXTO-MAGANDHI.md`, `docs/CUENTAS-CLIENTE.md` y, en el repositorio de la
tienda, `cuenta/CONFIGURACION.md`. No volver a construir C1 ni C2 desde cero.

## 1. Estado exacto

**C2 está fusionado, publicado y desplegado, pero el registro público sigue
apagado.** La siguiente acción es una prueba controlada de Google OAuth en modo
Testing. Después se configura Cloudflare Turnstile y solo al final se decide la
apertura.

Código fusionado el 16-oct-2026:

- Back-office/backend: PR `12344-ux/12344-ux.github.io#270`, merge
  `a62319594316bd3c2a903a259e33a3de522980ef`.
- Tienda: PR `12344-ux/magandhi#93`, merge
  `e17afa9eca01e79e4e109298f69aa4cb5d53e835`.
- Los dos workflows terminaron en verde. El banco del backend ejecutó
  PostgreSQL 15 + Deno 2; la tienda pasó 17/17 contratos C2.

Producción medida por el dueño:

- Migración máxima aplicada:
  `20261101000000_cuentas_cliente_c2.sql`.
- El preflight de solo lectura dio C1=`true`, C2=`true` y `0` en las cinco
  medidas de normalización, ambigüedad y duplicidad.
- Edge Function `cuenta-inicializar` desplegada con Verify JWT activado.
- `/cuenta/` y `/cuenta/callback/` están publicados en `magandhi.com`.
- `Allow new users to sign up` permanece **apagado**.

## 2. Qué entrega C2

- Registro e inicio por correo + contraseña.
- Google OAuth mediante Supabase Auth.
- Confirmación obligatoria y recuperación con `TokenHash`; los enlaces se
  probaron abriéndolos en otro navegador.
- Callback PKCE para Google, limpieza inmediata de credenciales de la URL y
  comprobante breve/de un solo uso para cambiar contraseña.
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

### Google OAuth

Confirmado por el dueño:

- Proyecto Google creado.
- Audience `External`, estado `Testing`.
- Usuario de prueba agregado.
- Cliente Web creado.
- Callback autorizado coincide con
  `https://bxlzipwxyxdtffnuizbz.supabase.co/auth/v1/callback`.
- Google Provider habilitado en Supabase con Client ID/Secret guardados allí.
- Scopes limitados a identidad básica (`openid`, email y profile).
- Signup público sigue apagado.

## 5. Lo que NO está cerrado todavía

- Google está configurado, pero **no se ha ejecutado aún la prueba real del
  botón `Continuar con Google`**.
- `TURNSTILE_SITE_KEY` sigue vacía en `magandhi/cuenta/cuenta-config.js`.
- Cloudflare Turnstile y CAPTCHA de Supabase siguen apagados.
- No se ha probado un registro público nuevo por correo con CAPTCHA.
- Google sigue en `Testing`; no publicar la app todavía.
- Las políticas públicas siguen en versión borrador; cerrarlas antes de una
  apertura comercial definitiva.
- No aumentar el límite Auth de 30 correos/hora antes de CAPTCHA y medición.

## 6. Siguiente paso exacto

**Prueba controlada de Google con signup todavía apagado:**

1. En Supabase Auth → Users, crear manualmente un usuario autoconfirmado con el
   mismo correo del Google Test User. Usar una contraseña temporal fuerte y no
   documentarla.
2. En una ventana privada sin sesión, abrir `https://magandhi.com/cuenta/` y
   pulsar `Continuar con Google`.
3. Elegir exactamente el Google Test User.
4. Verificar regreso a MAGANDHI, sesión activa y ausencia de advertencias.
5. Medir en Supabase que existe una sola fila activa en `cuentas_cliente` para
   ese UID y revisar que Google quedó enlazado como identidad del mismo usuario,
   no como UID duplicado.
6. Cerrar sesión y repetir una vez para comprobar idempotencia.

Si Supabase bloquea Google por `disable_signup=true` aun existiendo el usuario,
**no encender signup todavía**: registrar el error exacto y pasar primero a
Turnstile.

## 7. Después de la prueba Google

1. Crear widget Cloudflare Turnstile para `magandhi.com`.
2. Guardar el secret únicamente en Supabase Auth CAPTCHA.
3. Poner la site key pública en `cuenta/cuenta-config.js` mediante rama + PR.
4. Fusionar/publicar la site key y verificar que el widget flexible carga en
   móvil y escritorio.
5. Encender CAPTCHA en Supabase y probar token válido, ausente y vencido.
6. Abrir signup de forma controlada y probar un registro real por correo:
   confirmación, inicialización, logout/login y una sola fila.
7. Probar Google con un usuario realmente nuevo.
8. Mantener compra invitada y consentimiento de marketing separados.
9. Cerrar políticas antes de pasar Google a Production y anunciar registros.
10. Actualizar este relevo solo después de medir la apertura.

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
> C2 están desplegados; la migración máxima es `20261101000000`, el preflight
> dio todo limpio, `cuenta-inicializar` está desplegada con JWT, SMTP/TokenHash
> y recuperación cross-browser están verificados, y Google OAuth está
> configurado External/Testing con proveedor habilitado. Signup y CAPTCHA siguen
> apagados. Empieza directamente con la **prueba controlada del botón Continuar
> con Google usando un usuario Auth manual con el correo del Google Test User**.
> No repitas C1, migración C2, SMTP, plantillas ni configuración OAuth.
