# Curaduría y sello «Elegido por MAGANDHI»

**Corte:** 10 de octubre de 2026 · **Estado:** D2b desplegado y verificado por el dueño (PR #261). La regla comercial rige y el contrato técnico vigente de D2b es una casilla simple por campaña.

## 1. La regla

**El sello solo lo lleva un producto probado por el equipo de MAGANDHI**, sea propio o de proveedor.

La curaduría también decide qué entra a la tienda, no solo qué lleva el sello. Todo lo publicado responde por la marca, porque las opiniones verificadas se publican siempre.

## 2. Criterios para que un producto entre

- Lo compraríamos y lo recomendaríamos.
- El proveedor tiene bodega en Colombia y stock suficiente.
- El margen es positivo después de costo, flete y comisiones. Los números viven en el panel, no aquí.
- Cosméticos (notificación sanitaria obligatoria, NSO), suplementos y alimentos (registro sanitario): verificados en el INVIMA.
- Las fotos y la descripción corresponden a lo que llega.
- Se conoce el tiempo real de entrega.

**No entran:**

- réplicas o imitaciones de marcas ajenas («tipo original», «1.1»);
- productos que requieren registro sanitario y no lo tienen;
- productos con promesas de salud que no se pueden sostener.

## 3. Protocolo de la muestra (operativo, no formulario D2b)

Cada candidato se pide a una dirección propia como pedido pagado, igual que lo pediría un cliente. Esta guía ayuda al equipo a decidir si el producto entra y si merece sello; **D2b no guarda estos puntos como fechas, notas, veredictos ni historial en el panel.**

| Punto | Qué se mira |
|---|---|
| Tiempo | Días desde el pago hasta la entrega |
| Guía | Qué remitente aparece |
| Paquete | Estado del empaque. Si trae factura, precios o publicidad del proveedor |
| Producto | Si coincide con las fotos y la descripción, su calidad y el registro sanitario en la etiqueta |
| Uso | Quién lo probó, durante cuánto tiempo y su conclusión |
| Veredicto | Entra con sello · entra sin sello · no entra |

Las fotos de la ficha se toman de la muestra real.

## 4. Cómo queda en el sistema (D2b desplegado · 10-oct-2026)

- **Una sola casilla por campaña:** «Este producto fue probado por MAGANDHI», persistida en `campana_producto.probado_por_magandhi`.
- **Solo con producto ligado y casilla marcada** se habilita `sello_elegido`. La UI guía; `cm_crear_campana`, `cm_editar_campana`, `cm_publicar_campana` y un trigger vuelven a imponerlo en servidor.
- **No hay tabla `producto_pruebas`, RPC de registro, formulario, fecha, notas, veredicto ni bitácora.** La casilla no inventa evidencia de muestras ni exige completar hechos históricos.
- Si una campaña histórica conserva sello pero la casilla nueva está en falso, el editor muestra una advertencia y permite confirmarla o elegir «Ninguno» al guardar; nunca borra el sello al cargar.
- **Lo que no cambia:** la regla de un solo distintivo, el sello o el aviso de urgencia, nunca los dos (`campana_producto_un_distintivo_chk`); y D2b no habilita publicar ni vender un producto de proveedor antes de D2c.