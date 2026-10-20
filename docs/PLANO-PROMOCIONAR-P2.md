# MAGANDHI · Promocionar P2 · Estudio de campaña

**Estado:** P2 base desplegado; refinación de identidad MAGANDHI y editor creativo en construcción.
**Tramo anterior:** P1 desplegado y cerrado estructuralmente.  
**Límite:** P2 crea material local; no mide, publica, pauta ni atribuye ventas.

## 1. Objetivo

Dar al equipo una pantalla visual propia desde cada Campaña para preparar y descargar material promocional consistente con MAGANDHI, apoyado en la URL canónica P1 y en los siete canales definidos por P0.

## 2. Entrega funcional

- Acción `Promocionar` desde una campaña activa.
- Enlace oficial `https://magandhi.com/producto/<slug>/` construido internamente.
- Presets cerrados de canal y pares `source/medium` de P0.
- UTM descriptiva con `campaign` y `content` normalizados.
- Copia de enlace, copia de texto y Web Share cuando el navegador lo permita.
- Texto inicial determinista desde contenido aprobado de la campaña, con edición independiente de pretítulo, título, descripción, CTA y mensaje que acompaña el enlace; la edición vive solo durante la sesión.
- Selector de imagen cerrado a galería de Campañas, fondo de marca o archivo temporal local, con modo, posición y acercamiento; nunca URL arbitraria.
- Tres presets oficiales —Terracota editorial, Negro curaduría y Negro + dorado— y ajustes por rol limitados a la paleta MAGANDHI.
- Validación bloqueante de contraste y de desbordes antes de descargar el PNG.
- Guía rápida integrada y manual completo en `docs/GUIA-PROMOCIONAR.md`.
- QR calculado íntegramente en el navegador mediante `qrcode-generator` 1.4.4, cargado desde una URL fija con Subresource Integrity; la URL promocional nunca se envía al proveedor del script.
- Piezas PNG locales en 1080×1080, 1080×1920 y 1200×628.
- Previsualización responsive que no altera la resolución exportada.

## 3. Decisiones de interfaz

El producto se presenta como un estudio editorial MAGANDHI y no como otro formulario largo ni como una superficie visual de Impulse. En escritorio, controles y lienzo conviven en dos columnas; en móvil se conserva el orden natural de trabajo —canal, enlace, imagen, contenido, marca, confirmación y pieza— para que la lectura visual, el teclado y los lectores de pantalla coincidan. El enlace protegido es la salida funcional principal; `Descargar PNG`, copiar y compartir son acciones complementarias.

Toda la superficie usa negro, terracota, dorado, arena, crema y blanco de MAGANDHI. El azul operativo de Impulse no aparece en el estudio ni en píxeles exportados. Las geometrías Cuadrado, Historia y Horizontal permanecen fijas; la libertad editorial ocurre dentro de ellas.

La pantalla muestra siempre si la campaña está publicada, si tiene slug y si el operador confirmó manualmente que el shell P1 abre correctamente. Se permite preparar una campaña en borrador, pero copiar, compartir y exportar permanecen bloqueados hasta que esté publicada y la ficha haya sido comprobada.

## 4. Contrato UTM

| Canal | `utm_source` | `utm_medium` |
|---|---|---|
| WhatsApp | `whatsapp` | `mensajeria` |
| Instagram | `instagram` | `social` |
| Facebook | `facebook` | `social` |
| Email | `email` | `email` |
| Código QR | `qr` | `offline` |
| Anuncio manual | `anuncio-manual` | `paid-manual` |
| Otro controlado | `otro-controlado` | `referral` |

`campaign` usa `<producto>-<aammdd Colombia>-<4 Crockford base32>` como sugerencia local, con 20 bits criptográficos y base máxima de 48 caracteres. `content` describe canal y formato. Ambos pueden editarse, se normalizan y nunca deben contener una persona, correo, teléfono, UID o audiencia identificable. Además del bloqueo heurístico de señales obvias, cualquier edición desmarca una confirmación humana explícita de que ambos valores describen solo iniciativa y colocación. La UTM es descriptiva; no constituye atribución autoritativa ni sustituye la comprobación server-side de unicidad que corresponde a P3.

## 5. Contenido permitido

Los textos y piezas pueden usar nombre, categoría, detalle, característica, hook, curaduría e imágenes aprobadas de Campañas. Pretítulo, título, descripción y CTA gobiernan directamente el PNG; el `Mensaje que acompaña el enlace` se usa únicamente al copiar o compartir. El CTA rasterizado es visual y nunca sustituye el enlace real. No se congelan precio, stock, disponibilidad, máximo, proveedor, costo ni urgencia. La edición no se persiste en Supabase durante P2.

## 6. Seguridad y privacidad

- Destino fijo de lista blanca en `magandhi.com/producto/`; no se acepta URL arbitraria.
- Lectura autenticada mínima bajo RLS existente.
- Sin INSERT, UPDATE, RPC, Edge Function, tabla o migración P2.
- Sin `service_role`, PII, telemetría nueva o almacenamiento promocional.
- QR, canvas y PNG se generan localmente; nada se sube.

## 7. Fuera de alcance

- P3: códigos propios, redirector, enlaces cortos y conteo de clics.
- P4: visita promocional y atribución a intención/pedido/pago.
- P5: resultados, conversión y lectura comercial.
- Meta Ads, Pixel, Conversions API, gasto y publicación automática.

## 8. Gate operativo

P2 no puede conocer por Supabase si GitHub Pages ya publicó el shell P1. Después de crear, publicar o cambiar una campaña se mantiene la operación de tienda: `--sync`, `--check`, merge, Pages y comprobación HTTP. La casilla de verificación de la pantalla es una confirmación humana de ese paso, no una medición automática.

## 9. Criterios de cierre

1. Los siete canales producen exclusivamente los pares P0.
2. Canonical y UTM siempre apuntan a la ficha MAGANDHI.
3. Los tres PNG tienen dimensiones exactas y composición legible.
4. QR escaneable, local y con zona silenciosa.
5. Teclado, foco, estados y experiencia móvil 390 px verificados.
6. Campaña no publicada o shell no confirmado no puede compartir ni exportar.
7. Ningún flujo escribe datos ni adelanta P3–P5.
8. No aparece azul Impulse en la interfaz ni en las exportaciones.
9. Imagen, pretítulo, título, descripción, CTA y roles de color responden a sus controles.
10. Una combinación sin contraste o un texto desbordado bloquea solamente la descarga; el enlace protegido permanece disponible.
