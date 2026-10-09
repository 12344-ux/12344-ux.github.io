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
- [x] En «Mis Integraciones», `magandhi.com` con tipo `WOOCOMERCE`, porque no existe «tienda propia». **Es la integración vigente y basta**, sin completar su OAuth: medido el 9-oct, su token lee el catálogo y la ficha de cualquier producto (`DROPI.md` §7).
- [x] Token nuevo generado después de validar y guardado en el gestor de contraseñas y en Supabase Secrets. El inicial, que apareció en una captura, quedó sustituido.

## 3. Consulta a soporte de Dropi

**Estado 9-oct-2026:** el asistente de Dropi cerró el chat y confirmó que las solicitudes de API se tramitan exclusivamente por correo. Asignó un contacto humano y pidió tres cosas: motivo/proyecto, endpoints exactos y usuario o id de la cuenta. La dirección concreta permanece en la conversación privada; no se replica en este repositorio público.

- [x] Consulta inicial enviada por el chat de Dropi. Fecha: 9-oct-2026.
- [x] Respuesta inicial anotada en §7.
- [ ] Correo al contacto asignado. **Ya no es un bloqueo**: la lectura funciona. Ahora el correo sirve para quitar deuda, no para desbloquear.

Qué pedir, con la lectura ya funcionando:

- **autorizar el `User-Agent` propio de MAGANDHI**, para no depender de enviar uno con prefijo `WordPress/` (`DROPI.md` §7);
- el contrato oficial de `products/v2/{id}` y el **límite de consultas por minuto**, para fijar cada cuánto refrescar el stock;
- si existe **webhook de cambios de stock**;
- por qué `GET products/{id}` responde «No tiene permisos» y cuál es la ruta correcta de existencias, si hay otra;
- contrato de pedidos: crear `SIN RECAUDO`, consultar por id, guía y estados.

No se envían tokens ni contraseñas por correo.

### Prueba alternativa autorizada · WooCommerce aislado

Solo para medir, sin tocar `magandhi.com`:

- [ ] Crear un sandbox WordPress público y temporal (primera opción: InstaWP gratuito, 48 h).
- [ ] Instalar WooCommerce; país Colombia y moneda COP. Sin pagos, envíos, clientes ni pedidos.
- [ ] Conectar Dropi por OAuth usando la URL temporal; token nuevo y revocable.
- [ ] Importar exactamente un producto y verificar texto, imágenes, variantes, ids, precios y stock.
- [ ] Repetir la sonda después de completar OAuth.
- [ ] Verificar stock: el plugin Dropify **no sirve como prueba de actualización periódica** por sí solo; su código vigente retorna antes de ejecutar el trabajo programado.
- [ ] Borrar integración y sandbox al terminar, salvo decisión expresa de conservarlo.

Criterio: solo se evalúa un conector permanente si importación **y** stock actualizable quedan demostrados. Nunca se instala WordPress sobre el dominio principal.

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
