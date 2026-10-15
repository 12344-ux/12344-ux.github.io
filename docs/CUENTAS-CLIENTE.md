# Cuentas de cliente · MAGANDHI

**Decisión del dueño · 15-oct-2026:** la tienda conservará los dos caminos.
Comprar como invitado seguirá siendo posible; iniciar sesión será opcional y
dará comodidad y beneficios, nunca será una barrera para pagar.

## 1. Frontera de identidad

No se reemplaza ningún identificador existente:

| Identidad | Uso |
|---|---|
| `auth.users.id` | acceso, sesión, confirmación y recuperación |
| `clientes.id` | identidad comercial, pedidos, métricas y relación histórica |
| `pedidos.customer_id` | sigue apuntando a `clientes.id` |
| `cuentas_cliente` | puente entre la cuenta Auth y el cliente comercial |

`perfiles` queda reservado al personal de `montaguth.institute` y
`cuentas_cliente` a clientes de `magandhi.com`. El mismo UID no puede pertenecer
a las dos tablas, ni siquiera ante dos altas simultáneas. Las sesiones tampoco
se comparten automáticamente entre los dos dominios porque cada origen guarda
su propia sesión; el candado definitivo sigue siendo RLS/RPC en la base.

Una cuenta puede nacer sin `customer_id`: registrarse no inventa una compra ni
convierte un prospecto en cliente. Después de confirmar el correo, C2 podrá
vincularla con un cliente histórico; si no existe, el vínculo se completa al
primer pago aprobado.

## 2. Los dos modos

### Invitado

El flujo actual queda intacto: ficha → datos de entrega → Wompi → webhook →
`crear_pedido`. El servidor resuelve el cliente por correo/teléfono como hoy y
el código de reseña sigue habilitando opiniones.

### Con cuenta

La Edge Function valida el JWT, obtiene el `customer_id` desde el servidor y lo
guarda en la intención antes de abrir Wompi. Nunca acepta un `customer_id`
arbitrario del navegador. El checkout puede rellenar datos, pero cada pedido
conserva su snapshot de destinatario y dirección.

## 3. Qué entregará Mi cuenta v1

1. Perfil y direcciones.
2. Pedidos propios, estado y seguimiento público.
3. Acceso directo a opinar sobre productos de pedidos entregados.
4. Preferencias de novedades separadas del acceso a la cuenta.
5. Cerrar sesión, recuperar y cambiar contraseña.

Los pedidos se expondrán por una RPC/vista de lista blanca. Nunca saldrán costos,
proveedor, IDs de Dropi, notas internas, revisiones privadas ni datos de otras
personas.

## 4. Opiniones y marketing

La opinión conserva su llave real `(pedido_id, product_id)`. Con cuenta se
añade otra forma de autorizar —ser dueño de un pedido entregado—, pero no se
retira el código: sigue cubriendo invitados y compras históricas.

Crear cuenta no es autorizar publicidad. `em_contactos` conserva por separado
el texto aceptado, la versión de política, la fecha, los temas y la bitácora.

## 5. Recompensas futuras

La cuenta deja el cimiento para puntos/cupones, pero C1 no inventa todavía una
columna `puntos`. Cuando exista una regla comercial aprobada se hará un libro de
movimientos append-only (ganó, usó, venció, ajuste), con saldo derivado e
idempotencia por pedido. Así un cambio de campaña no reescribe la historia.

## 6. Tramos

| Tramo | Entrega | Estado |
|---|---|---|
| **C1** | puente de identidad, separación cliente/personal, guardia interna y actor cliente en la matriz | **Desplegado y verificado 15-oct-2026, PR #268** |
| **C2** | registro, confirmación, login, recuperación, SMTP propio, CAPTCHA y vínculo seguro | Pendiente |
| **C3** | Mi cuenta: perfil, direcciones, pedidos, estado y opiniones | Pendiente |
| **C4** | checkout con cuenta, rellenado y `customer_id` server-side; invitado intacto | Pendiente |

C1 ya está aplicado. Antes y durante C2 se mantiene cerrado el registro público:
`disable_signup=true`, medido el 15-oct-2026. La apertura se hace solo cuando
los correos de Auth salgan por un remitente separado de marketing y estén
verificados registro, confirmación, recuperación, CAPTCHA, redirects y RLS.

**Próximo punto de entrada:** `docs/RELEVO-CUENTAS-2026-10-15.md`.
