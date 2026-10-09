# Dropshipping y envíos · frente nuevo de MAGANDHI

**Corte:** 9 de octubre de 2026 · **Estado:** puesta en marcha (cuentas, consultas y muestras). Todavía no hay código.

Esta carpeta documenta el frente que abrió el dueño el 9-oct-2026:

- vender, además de los productos propios, productos de proveedores de **Dropi** que el proveedor despacha directo al cliente;
- dar **guía de envío y rastreo** a los pedidos propios, que hoy salen sin número de guía.

Es la entrada única del frente. Cuando una fase llegue a producción, su resumen sube a `CONTEXTO-MAGANDHI.md`.

> **Repositorio público.** Aquí no van datos personales, tokens ni llaves, ni costos o márgenes reales de productos. Esos datos viven en los paneles privados (Dropi, Supabase, Inventario).

## 1. La decisión

MAGANDHI venderá dos tipos de producto:

| Tipo | La mercancía | Dónde está | Quién lo despacha |
|---|---|---|---|
| **Propio** (como el shampoo) | MAGANDHI la compra por adelantado | Inventario de MAGANDHI | MAGANDHI, con guía de una plataforma de envíos |
| **De proveedor** | La tiene el proveedor; MAGANDHI paga solo cuando vende | Bodega del proveedor en Dropi | El proveedor, por medio de Dropi |

- **La esencia no cambia:** la misma tienda, el mismo pago, los mismos correos y la atención personal del dueño.
- **El sello «Elegido por MAGANDHI» solo lo lleva un producto probado por el equipo**, sea propio o de proveedor. Ver `CURADURIA-Y-SELLO.md`.
- **Solo Colombia** por ahora.
- MAGANDHI asume la responsabilidad ante el cliente. Es una decisión del CEO del 9-oct-2026.

## 2. Supuestos vigentes

El dueño puede cambiarlos:

1. Al lanzar, **solo pago por adelantado** con Wompi. Sin contraentrega.
2. Al principio, el dueño **confirma con un clic** cada pedido de proveedor antes de enviarlo a Dropi.
3. **Una unidad por compra**, como hoy (`crear-intencion-pago` lo exige). Así una compra nunca mezcla productos propios y de proveedor.

## 3. Responsabilidades que MAGANDHI asume

- **Ante el cliente, el vendedor es MAGANDHI**, aunque despache el proveedor. Responde por la garantía, el retracto y la reversión del pago (Ley 1480 de 2011). Con cada proveedor hay que acordar quién cubre qué.
- **Cosméticos, suplementos y alimentos:** se verifica su notificación o registro sanitario en el INVIMA antes de publicarlos.
- **Nada de réplicas ni imitaciones** de marcas ajenas.
- **Datos personales:** antes del lanzamiento, la política de datos debe nombrar a quienes reciben los datos del comprador (Dropi, proveedores, transportadoras).
- **Opiniones:** las verificadas se publican siempre, también las negativas. Un mal proveedor baja la calificación de MAGANDHI.

## 4. Estado por fase

| Fase | Qué entrega | Estado |
|---|---|---|
| 0 | Cuentas, consulta a Dropi, muestras y cotizaciones (`PUESTA-EN-MARCHA.md`) | **En curso** |
| 1 | Guía manual en Ventas y correo «En camino» automático con el rastreo | Diseñada, no depende de nadie |
| 2 | Guías automáticas para productos propios | Espera las cotizaciones |
| 3 | Catálogo de proveedor y sello ligado a una prueba registrada | Espera la respuesta de Dropi |
| 4 | Pedidos de proveedor enviados a Dropi y seguimiento de la guía | Espera la respuesta de Dropi |
| 5 | Contraentrega | Solo si los números lo piden |

**Antes de vender productos de proveedor, la tienda necesita dos arreglos** (pendientes #3 y #4 de `CONTEXTO-MAGANDHI.md` §9):

- la confirmación al volver de Wompi, para evitar el pago doble;
- que los detalles de entrega lleguen al pedido.

## 5. Archivos

| Archivo | Para qué |
|---|---|
| `PUESTA-EN-MARCHA.md` | Lo que hace el dueño, con casillas y registro de respuestas |
| `DROPI.md` | Lo que se sabe de la integración, lo que falta confirmar y cómo se mueve el dinero |
| `ENVIOS-PROPIOS.md` | Plataformas de guías evaluadas y cómo se decide |
| `CURADURIA-Y-SELLO.md` | Cómo entra un producto a la tienda y cómo se gana el sello |
| `PLANO.md` | Diseño técnico propuesto, por fases |

## 6. Reglas del frente

- **Tokens y llaves** de Dropi, Mipaquete o Skydropx: los carga el dueño en Supabase → Edge Functions → Secrets. Nunca van en el chat, en WhatsApp, en el repositorio ni en el frontend.
- **La tienda nunca muestra proveedor ni costo.** Es el mismo contrato de `catalogo_publico`.
- **Medir antes de afirmar.** La API de Dropi no tiene documentación pública: nada se da por hecho hasta probarlo.
- Las reglas de entrega de `CONTEXTO-MAGANDHI.md` §10 aplican igual.
