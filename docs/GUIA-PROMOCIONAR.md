# Guía de uso · Estudio Promocionar MAGANDHI

Esta guía explica qué hace cada control, qué se distribuye realmente y qué cosas **no** hace la herramienta.

## 1. Qué es Promocionar

Promocionar transforma una campaña guardada en tres elementos que puedes distribuir:

1. un **enlace protegido** hacia la ficha oficial del producto;
2. un **mensaje** para acompañar ese enlace;
3. una **pieza PNG** con identidad MAGANDHI y, opcionalmente, un QR.

La herramienta no publica en redes, no compra anuncios, no cobra dinero y no modifica la campaña original. Todo lo creativo vive durante la sesión actual.

## 2. Antes de empezar

La campaña debe ser real, estar activa, publicada y tener una ficha canónica. Los borradores pueden usarse para preparar el diseño, pero no permiten copiar, compartir o descargar hasta su publicación.

Abre siempre la ficha oficial y comprueba nombre, imagen y disponibilidad antes de distribuir una promoción.

## 3. Canal

El canal indica dónde piensas usar el enlace: WhatsApp, Instagram, Facebook, email, QR, anuncio manual u otro espacio controlado.

Al elegirlo, Promocionar completa automáticamente:

- `utm_source`: plataforma u origen;
- `utm_medium`: tipo de distribución;
- `utm_content`: pieza o colocación sugerida.

Elegir un canal **no publica nada**. Solo prepara etiquetas descriptivas.

## 4. Enlace protegido de compra

El enlace lleva a `https://magandhi.com/producto/<slug>/` y añade etiquetas UTM. El destino no se puede escribir libremente para evitar enlaces equivocados o externos.

La ficha del producto es la entrada segura a la compra porque allí se vuelven a comprobar en vivo:

- precio;
- disponibilidad;
- cantidad permitida;
- condiciones necesarias antes de abrir el pago.

El enlace no apunta directamente a Wompi. Los enlaces de pago son temporales y no deben distribuirse como promociones.

### Campaign y content

- `campaign` identifica la iniciativa, por ejemplo `lanzamiento-manzanilla-261020-abcd`.
- `content` distingue la pieza o colocación, por ejemplo `instagram-historia-v02`.

Nunca deben incluir nombre de cliente, teléfono, correo, UID o una audiencia identificable. La casilla de confirmación no es un permiso: es una revisión de privacidad.

## 5. Imagen y encuadre

Puedes elegir:

- Fondo de marca, sin fotografía;
- cualquier imagen aprobada de la galería de Campañas;
- una imagen temporal desde tu dispositivo.

La imagen temporal no se sube ni modifica Campañas y desaparece al recargar o cerrar la página.

### Tratamiento

- **Llenar:** cubre toda la zona visual; puede recortar bordes.
- **Producto completo:** intenta conservar la imagen completa sobre blanco.

### Posición y acercamiento

- Posición horizontal mueve el foco de izquierda a derecha.
- Posición vertical mueve el foco de arriba abajo.
- Acercamiento amplía la fotografía dentro del marco fijo.

Las estructuras Cuadrado, Historia y Horizontal no cambian de tamaño. En móvil aparece un botón flotante **Ver pieza** para saltar rápidamente a la previsualización; desde allí puedes volver al editor sin alterar el orden accesible de los controles.

## 6. Contenido de la pieza

- **Pretítulo:** sello breve que contextualiza, como “Selección MAGANDHI”. Puede ocultarse.
- **Título:** idea principal y elemento de mayor jerarquía.
- **Descripción:** apoyo corto que explica el beneficio o la selección.
- **CTA:** llamado visual como “Comprar ahora” o “Conocer producto”. Puede ocultarse.
- **Mensaje que acompaña el enlace:** texto para copiar o enviar junto con la URL; no aparece dentro del PNG.

### El CTA del PNG no es clicable

Un PNG es una imagen plana. El botón dibujado comunica qué hacer, pero no puede recibir clics. El acceso real ocurre mediante:

- Copiar enlace;
- Copiar texto;
- Compartir;
- escanear el QR.

Al publicar en una red, adjunta el PNG y pega también el enlace donde esa plataforma lo permita.

## 7. Distintivos MAGANDHI

Los tres presets iniciales son:

- **Terracota editorial:** cercanía e identidad institucional.
- **Negro curaduría:** apariencia sobria y boutique.
- **Negro + dorado:** edición especial o protagonista.

Después de elegir un preset puedes ajustar individualmente:

- superficie general;
- panel de contenido;
- color del pretítulo;
- color del título;
- color de la descripción;
- acento;
- fondo del CTA;
- texto del CTA.

No existe selector de color libre: solo se ofrecen colores oficiales MAGANDHI. Si una combinación no alcanza contraste suficiente, **Copiar enlace** continúa disponible porque la URL permanece segura, pero el PNG no se descarga hasta corregirla. Los mensajes y piezas también se bloquean si detectan otra URL, PII, precio, stock, proveedor o costo.

## 8. Formatos

- **Cuadrado · 1080×1080:** publicaciones de feed y usos generales.
- **Historia · 1080×1920:** historias y pantallas verticales.
- **Horizontal · 1200×628:** enlaces, publicaciones horizontales y previews.

Un texto puede caber en Cuadrado y no en Horizontal. Si aparece “Acorta Título/Descripción/CTA”, edita el contenido para ese formato antes de descargar.

## 9. QR

El QR representa exactamente el mismo enlace protegido mostrado en la pantalla. Se calcula dentro del navegador; la URL no se envía a un servicio generador de códigos.

El interruptor controla si aparece dentro del PNG. Aunque se oculte en la pieza, el enlace continúa disponible para copiar y compartir.

## 10. Acciones finales

- **Descargar PNG:** guarda la pieza en resolución completa en el dispositivo.
- **Copiar enlace:** copia solo la URL protegida.
- **Copiar texto:** copia mensaje más URL.
- **Compartir:** abre el menú nativo del teléfono o sistema. Nada se envía hasta que eliges una aplicación o destinatario.

El navegador puede solicitar acceso al portapapeles o permiso para guardar un archivo. No se solicitan cámara, micrófono, ubicación ni contactos.

## 11. Confirmaciones

Hay tres comprobaciones humanas:

1. que `campaign` y `content` no identifiquen personas;
2. que los textos públicos no contengan personas, URL externas, precio, stock, proveedor o costo;
3. que la ficha oficial abra correctamente.

No conceden acceso al sistema y no cambian datos. Evitan distribuir un enlace incorrecto o información sensible.

## 12. Flujo recomendado

1. Abre Promocionar desde una campaña.
2. Lee la guía rápida si es la primera vez.
3. Elige canal y revisa UTM.
4. Selecciona imagen y ajusta el encuadre.
5. Edita pretítulo, título, descripción y CTA.
6. Elige un preset MAGANDHI y afina colores si hace falta.
7. Revisa los tres formatos por separado.
8. Abre la ficha oficial y completa las confirmaciones.
9. Descarga el PNG.
10. Copia o comparte el enlace junto con la pieza.

## 13. Qué queda fuera de P2

P2 prepara material, pero todavía no cuenta clics ni atribuye ventas. Esas funciones pertenecen a:

- P3: enlaces cortos y clics aproximados;
- P4: atribución a intención, pedido y pago;
- P5: resultados y conversión comercial.
