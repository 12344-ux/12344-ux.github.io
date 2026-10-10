# Dropshipping y envíos · frente nuevo de MAGANDHI

**Corte:** 10 de octubre de 2026 · **Estado:** D1 (cimientos internos) **desplegado en producción**. La lectura real de Dropi funciona; D1 suma área propia, bandeja privada y separación firme entre proveedor e Inventario. No hay todavía importación, publicación, pedido ni despacho de proveedor. **Lo siguiente es D2.**

> **¿Migrando a un chat nuevo?** Empieza por `RELEVO-2026-10-10.md`: resume qué quedó desplegado y el plan de D2.

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
| 0 | Cuentas, consulta a Dropi, muestras y cotizaciones (`PUESTA-EN-MARCHA.md`), y la sonda de solo lectura (`DROPI.md` §6) | **Casi cerrada.** **Dropi ya le responde a MAGANDHI:** faltaba el `User-Agent` (§7). Quedan muestras, cotizaciones y contador |
| **D1 · Cimientos internos** | Área propia, bandeja privada, `origen=proveedor`, ficha externa, bloqueo de Inventario/Métricas y sonda paginable | **Desplegada en producción (10-oct-2026).** No publica, no crea productos/campañas, no descarga imágenes ni llama `orders/`. **Ajuste de uso real** (fotos directas de Dropi, 24 por página con Anterior/Siguiente, bandeja como carrito): sin migración, falta redesplegar `dropi-sonda` (runbook «Dropshipping D1 · ajuste de uso real») |
| 1 | Guía manual en Ventas y correo «En camino» automático con el rastreo | Diseñada, no depende de nadie |
| 2 | Guías automáticas para productos propios | Espera las cotizaciones |
| 3 | Embudo por producto y sello ligado a una prueba registrada | **D2 en tres tramos** (`PLANO.md` §4): **D2a · Llevar a Campañas** en PR (importación atómica con fotos propias, sin publicar); D2b sello con prueba; D2c stock vivo, fallo cerrado y venta |
| 4 | Pedidos de proveedor enviados a Dropi y seguimiento de la guía | Falta confirmar el contrato de `orders/`, la reserva `PENDIENTE CONFIRMACION`, su liberación/cancelación y el contador |
| 5 | Contraentrega | Solo si los números lo piden |

**Los dos arreglos que la tienda necesitaba antes de vender productos de proveedor ya están hechos** (D0, 9-oct-2026): la confirmación al volver de Wompi, que cierra el pago doble, y los detalles de entrega llegando al pedido. **Desplegados el 10-oct-2026** (runbook `supabase/INSTRUCCIONES.md` §D0). El que sigue siendo requisito propio de este frente es la **lista cerrada de municipios**: Dropi necesita que la ciudad coincida con su catálogo, y hoy en la tienda es texto libre, así que un pedido podría fallar *después* de que el cliente pagó.

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
