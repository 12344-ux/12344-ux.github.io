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
convierte un prospecto en cliente. Después de confirmar el correo, C2 intenta
vincularla únicamente si existe una coincidencia histórica única; si no existe,
el vínculo se completa en C4 al primer pago aprobado.

## 2. Los dos modos

### Invitado

El flujo actual queda intacto: ficha → datos de entrega → Wompi → webhook →
`crear_pedido`. El servidor resuelve el cliente por correo/teléfono como hoy y
el código de reseña sigue habilitando opiniones.

### Con cuenta

La Edge Function valida el JWT y congela el UID del propietario en la intención.
`customer_id` no se acepta del navegador ni se inventa al abrir Wompi: durante
la primera aprobación C4, el servidor lo deriva desde `cuentas_cliente` y el
correo Auth confirmado, y crea o vincula el cliente comercial dentro de la misma
transacción del pedido. Cada pedido conserva por separado el snapshot de
nombre, correo, teléfono y dirección del destinatario.

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
| **C2** | registro, confirmación, login, recuperación, SMTP propio, Google, CAPTCHA y vínculo seguro | **Infraestructura desplegada y verificada en preapertura 16-oct-2026; signup OFF y Google Testing hasta publicar políticas** |
| **C3** | Mi cuenta: perfil, direcciones, pedidos, estado y opiniones | Pendiente |
| **C4** | checkout con cuenta y `customer_id` server-side; expiración firmada, retorno JWT y ciclo postpago del carrito | **Construido en PR backend #283 y tienda #108; banco PostgreSQL 15/Deno aprobado; pendiente de merge, despliegue y medición productiva** |

La cantidad inmediata para invitado ya quedó entregada por **Comercial C1**:
selector `1..max_comprable`, máximo y total visibles, con validación server-side.
El carrito autenticado y el checkout multiproducto quedaron desplegados y
probados en estructura por **Comercial C2/C3**, con flag final `false`.
**Comercial C4 ya está construido en rama**: deriva/vincula `customer_id` en la
primera aprobación, separa destinatario, expira la ventana Wompi, bloquea
pendiente/revisión y consume o libera el carrito según el resultado. Los PR #283
(backend) y #108 (tienda) siguen abiertos; el banco PostgreSQL 15/Deno pasó,
pero C4 no está aplicado, publicado ni medido. C3 no tuvo pago aprobado, por lo
que tampoco prueba pedido, inventario, asiento o correo end-to-end.

C1 y el backend de C2 de Cuentas ya están aplicados. `disable_signup=true` continúa
vigente: correo/contraseña, SMTP, TokenHash y recuperación fueron medidos;
Google Identity Services, Turnstile, CAPTCHA, un registro nuevo por correo y un
usuario Google realmente nuevo quedaron medidos con identidades únicas y una
sola cuenta activa. C2 queda cerrado técnicamente en preapertura. Signup sigue
OFF y Google Testing hasta publicar políticas y avisos contextuales; solo después
se prepara la apertura.

**Punto global de entrada:** `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`.
Para retomar específicamente la apertura de cuentas, usar el relevo histórico
temático `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
