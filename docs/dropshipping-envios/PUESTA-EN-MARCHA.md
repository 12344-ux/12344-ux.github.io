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
- [ ] **Registro directo:** dropi.co → «Regístrate» → Colombia, como **dropshipper**, con `operaciones@magandhi.com` y el celular de MAGANDHI. Sin enlaces de afiliado: inscriben la cuenta en la «comunidad» de quien los comparte.
- [ ] Perfil y datos bancarios del titular completos.
- [ ] En «Mis tiendas», crear la tienda «MAGANDHI» con el dominio `magandhi.com`. Si obliga a elegir Shopify o WooCommerce y no hay opción de tienda propia o API, no elegir nada todavía: se resuelve con soporte.
- [ ] Si aparece un token, guardarlo en el gestor de contraseñas. No se pega en ningún chat.

## 3. Consulta a soporte de Dropi

Canal: WhatsApp, desde dropi.co/contactanos (según Dropi, es la vía más rápida).

- [ ] Mensaje enviado. Fecha: ____
- [ ] Respuesta anotada en §7.

Mensaje para copiar:

```
Hola, equipo de Dropi. Soy [tu nombre], de MAGANDHI (magandhi.com), tienda online
en Colombia. Ya abrimos la cuenta con operaciones@magandhi.com.

Nuestra tienda es desarrollo propio (no Shopify ni WooCommerce) y queremos
enviarles los pedidos por API. Tenemos estas preguntas:

1. ¿Cómo se habilita el acceso a la API de producción para una tienda propia?
   ¿Tienen documentación oficial?
2. ¿Exigen IP fija? Nuestro servidor está en la nube (Supabase) y no tiene IP fija.
3. ¿Hay un ambiente de pruebas para desarrollar sin crear pedidos reales?
4. ¿Nos avisan (webhook) cuando cambia el estado de un pedido o se genera la guía?
   Si no, ¿qué consulta usamos y cada cuánto podemos hacerla?
5. Nuestros clientes pagan por adelantado. En un pedido sin recaudo, ¿cómo se
   cobran el costo del proveedor y el flete? ¿Se descuentan de la wallet?
   ¿Cómo se recarga? ¿Qué comisión cobra Dropi en esos pedidos?
6. ¿Qué remitente aparece en la guía? ¿El paquete puede ir sin factura, precios
   ni publicidad del proveedor?
7. ¿Cómo funcionan las devoluciones y garantías en pedidos ya pagados?

¡Gracias!
```

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
| | | | |
