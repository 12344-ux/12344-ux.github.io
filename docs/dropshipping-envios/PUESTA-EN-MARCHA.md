# Puesta en marcha · lo que hace el dueño (fase 0)

**Corte:** 9 de octubre de 2026 · **Estado:** en curso.

Marca cada casilla al terminar y anota la fecha. Aquí no van datos personales, contraseñas ni tokens.

## 1. Correo `operaciones@magandhi.com`

El dominio usa Zoho Mail (verificado en el DNS el 9-oct-2026). No hay que contratar nada.

**Por qué esta dirección:**

- Es de la organización, no de una persona. Las cuentas nuevas quedan a nombre de MAGANDHI.
- No es la pública: `contacto@magandhi.com` aparece en la tienda y recibe las PQRS y el spam.
- Se puede pasar a otra persona sin rehacer las cuentas.

**Pasos:**

- [ ] Crear `operaciones` como alias: Consola de administración → Usuarios → tu usuario → Configuración del buzón → Alias de correo → Agregar. Si entra alguien al equipo, Zoho permite reasignarle el alias.
- [ ] Enviar un correo de prueba desde otra cuenta y confirmar que llega.
- [ ] Activar la verificación en dos pasos en la cuenta de Zoho. Quien controle ese buzón puede cambiar la contraseña de Dropi y retirar el saldo.
- [ ] Usar un gestor de contraseñas (por ejemplo Bitwarden), con una contraseña distinta por plataforma.

## 2. Cuenta de Dropi

- [ ] **Titular: el mismo de Wompi.** El dinero de los clientes llega a ese titular y de ahí sale lo que se le paga a Dropi. Si coinciden, la contabilidad y los retiros cuadran.
- [x] **Registro directo:** cuenta de Colombia creada como **dropshipper** con `operaciones@magandhi.com`.
- [x] Identidad del titular validada por Dropi con documento y fotografías (9-oct-2026).
- [ ] Perfil bancario y facturación electrónica completos con los datos fiscales correctos del titular.
- [x] En «Mis Integraciones» se probó `magandhi.com`, tipo `WOOCOMERCE`, URL `https://magandhi.com`, porque no existe «tienda propia». **Diagnóstico posterior:** no es una conexión válida: Dropi espera `/wc-auth/v1/authorize` y MAGANDHI no es WordPress. Se conserva solo mientras soporte puede necesitar identificar la prueba; luego se retira.
- [x] Token nuevo generado después de validar y guardado en el gestor de contraseñas y en Supabase Secrets. El inicial, que apareció en una captura, quedó sustituido.

## 3. Consulta a soporte de Dropi

**Estado 9-oct-2026:** el asistente de Dropi cerró el chat y confirmó que las solicitudes de API se tramitan exclusivamente por correo. Asignó un contacto humano y pidió tres cosas: motivo/proyecto, endpoints exactos y usuario o id de la cuenta. La dirección concreta permanece en la conversación privada; no se replica en este repositorio público.

- [x] Consulta inicial enviada por el chat de Dropi. Fecha: 9-oct-2026.
- [ ] Correo breve enviado al contacto asignado por Dropi, explicando que el proyecto está **en pre-lanzamiento**, que MAGANDHI no es WooCommerce y pidiendo el tipo/acceso correcto de solo lectura.
- [x] Respuesta inicial anotada en §7.

El correo técnico debe pedir:

- habilitación de lectura del catálogo para la cuenta ya validada;
- confirmación de las rutas actuales para listar productos, detalle, categorías y bodegas;
- campos de variantes, stock, precios, imágenes y proveedor;
- creación de pedidos pagados (`SIN RECAUDO`) en borrador y consulta por id;
- guía, rastreo y cambios de estado por webhook o consulta periódica;
- ambiente de pruebas, límites e IP fija, si aplica.

No se envían tokens ni contraseñas por correo.

## 4. Muestras

- [ ] Elegir 3 a 5 candidatos con los criterios de `CURADURIA-Y-SELLO.md` §2.
- [ ] Pedir cada uno a una dirección propia como **pedido pagado (sin recaudo)**, no contraentrega. Es el ensayo completo de lo que vivirá el cliente.
- [ ] Llenar la ficha de prueba de cada muestra (`CURADURIA-Y-SELLO.md` §3).

## 5. Cotización de envíos propios

- [ ] Abrir cuenta en Mipaquete y en Skydropx con `operaciones@magandhi.com`.
- [ ] Pesar y medir el shampoo ya empacado: ____ g · ____ × ____ × ____ cm.
- [ ] Cotizar desde la ciudad de despacho con valor declarado de $69.900 y anotar:

| Destino | Plataforma | Transportadora | Precio | Días | ¿Contraentrega? |
|---|---|---|---|---|---|
| Bogotá | | | | | |
| Medellín | | | | | |
| Barranquilla | | | | | |
| Municipio pequeño: ____ | | | | | |

## 6. Cita con el contador

- [ ] En una venta de proveedor, ¿MAGANDHI factura el total o solo su margen?
- [ ] ¿Cómo se registran la recarga del saldo de Dropi y lo que se descuenta por cada pedido (costo del proveedor y flete)? ¿Qué cuentas se usan?
- [ ] Asiento de liquidación de la venta del 9-oct (pendiente #1 de `CONTEXTO-MAGANDHI.md` §9).
- [ ] Contrapartida del inventario inicial (pendiente #2).

## 7. Registro de respuestas

| Fecha | Quién respondió | Pregunta | Respuesta |
|---|---|---|---|
| 9-oct-2026 | Asistente del chat de Dropi | Canal para habilitar la API | Las solicitudes de API se atienden solo por correo. Asignó contacto humano y pidió motivo/proyecto, endpoints exactos y usuario o id de la cuenta. |
