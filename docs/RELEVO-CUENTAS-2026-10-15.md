# Relevo de sesión · cuentas de cliente · 15 de octubre de 2026

Este es el punto exacto para continuar en un chat nuevo. Leer junto con
`CONTEXTO-MAGANDHI.md` y `docs/CUENTAS-CLIENTE.md`. No volver a diseñar C1: ya
está cerrado.

## 1. Dónde quedamos

**C1 está fusionado, desplegado y verificado. Lo siguiente es C2.**

- PR del panel **#268**, fusionado a `main` el 15-oct-2026.
- Migración más alta aplicada: `20261031000000_cuentas_cliente_cimientos.sql`.
- El dueño aplicó la migración completa en Supabase.
- `Allow new users to sign up` está **apagado** mientras se construye C2.
- Email Auth sigue habilitado y exige confirmación (`mailer_autoconfirm=false`).
- `montaguth.institute/acceso-interno.js` responde 200 y coincide exactamente
  con el archivo fusionado.
- La API de producción reconoce `cuentas_cliente` y `es_cuenta_cliente()`, pero
  `anon` recibe 401/42501 en ambas: existen y siguen cerradas.
- No hay Edge Functions ni secretos nuevos en C1.

## 2. Decisión comercial cerrada

MAGANDHI tendrá **dos caminos permanentes**:

1. **Compra como invitado**, sin iniciar sesión, para no crear fricción en una
   marca nueva.
2. **Cuenta opcional**, con comodidad y beneficios, sin ser requisito para
   pagar.

Más adelante las cuentas podrán participar en puntos, cupones o recompensas.
No se creó una columna mutable `puntos`: cuando exista la regla comercial se
hará un libro append-only de movimientos, saldo derivado e idempotencia por
pedido.

## 3. Identidad que no se debe rediseñar

- `auth.users.id`: identidad de acceso y sesión.
- `clientes.id`: identidad comercial canónica.
- `pedidos.customer_id`: sigue apuntando a `clientes.id`.
- `cuentas_cliente`: puente 1:0..1 entre Auth y el cliente comercial.

No reemplazar `customer_id` por el UID de Auth. Borrar/cerrar Auth no borra al
cliente, sus pedidos, asientos u opiniones.

`perfiles` es solo para personal de `montaguth.institute` y
`cuentas_cliente` solo para clientes de `magandhi.com`. Los triggers bloquean la
misma fila de `auth.users`, por lo que el mismo UID no puede quedar en ambas ni
siquiera con dos altas concurrentes.

Las sesiones viven por origen: iniciar sesión en `magandhi.com` no comparte
localStorage con `montaguth.institute`. Aunque alguien escriba sus credenciales
de cliente en el login interno, Auth puede reconocerlas pero el sitio exige fila
en `perfiles`, cierra solo esa sesión local y no entrega datos. Los HTML son
públicos por ser estáticos; no contienen datos. RLS/grants/RPC son el candado
autoritativo.

## 4. Evidencia de C1

- 76 migraciones aplicadas desde cero.
- Banco SQL **641/641**.
- Matriz de permisos **202/202**, con actor cliente Auth sin perfil.
- Suite C1 **28/28**.
- Dos carreras reales cliente↔personal **2/2**.
- Guardia/login interno **12/12**.
- CI del PR verde y revisión semántica independiente aprobada.

## 5. Lo siguiente exacto: C2

Construir la autenticación pública en el repositorio `12344-ux/magandhi`, sin
encender todavía el registro de producción:

- `/cuenta/`: crear cuenta e iniciar sesión;
- confirmación obligatoria de correo;
- recuperación y cambio de contraseña;
- cierre de sesión;
- callback/redirects seguros de `magandhi.com`;
- CAPTCHA y límites contra bots;
- SMTP propio mediante Resend, con remitente/subdominio de Auth separado de
  `news.magandhi.com` (marketing) y `updates.magandhi.com` (pedidos);
- alta server-side de `cuentas_cliente` solo para correo confirmado;
- vínculo seguro con un `clientes.id` histórico por correo normalizado
  verificado; los conflictos nunca se fusionan a ciegas;
- mensajes no enumerables: no revelar si un correo existe.

Base recomendada para C2: **correo + contraseña**. Google/social puede venir
después; no hace falta para abrir la primera versión.

El interruptor `Allow new users to sign up` permanece apagado durante el
desarrollo. Se enciende al final de C2, después de medir SMTP, confirmación,
recuperación, CAPTCHA, redirects, RLS y el rechazo del panel interno.

## 6. Después de C2

- **C3:** Mi cuenta útil: perfil, direcciones, pedidos/estado/seguimiento y
  opiniones de compras entregadas.
- **C4:** checkout autenticado, datos rellenados y `customer_id` derivado en
  servidor; el flujo invitado permanece intacto.

Opiniones no se reemplazan: el cliente logueado podrá autorizarse por propiedad
de un pedido entregado y el código actual seguirá sirviendo para invitados e
histórico. Crear cuenta tampoco concede consentimiento de Email marketing.

## 7. Cómo arrancar el próximo chat

> Retomamos MAGANDHI justo después de C1. Lee
> `docs/RELEVO-CUENTAS-2026-10-15.md`, `docs/CUENTAS-CLIENTE.md` y
> `CONTEXTO-MAGANDHI.md`. C1 está fusionado, desplegado y medido; la migración
> más alta es `20261031000000`, el registro público está apagado y el panel
> interno ya rechaza cuentas cliente. Empieza directamente por **C2: registro,
> confirmación, login y recuperación en magandhi.com**, manteniendo compra como
> invitado. No rediseñes C1 ni cambies `clientes.id`/`pedidos.customer_id`.
