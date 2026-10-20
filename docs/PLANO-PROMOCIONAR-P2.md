# MAGANDHI · Promocionar P2 · Estudio de campaña

**Estado:** implementación inicial en curso.  
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
- Texto inicial determinista desde contenido aprobado de la campaña, con campos separados para el texto visible del PNG y el mensaje que acompaña el enlace; la edición vive solo durante la sesión.
- QR generado íntegramente en el navegador mediante una biblioteca versionada localmente.
- Piezas PNG locales en 1080×1080, 1080×1920 y 1200×628.
- Previsualización responsive que no altera la resolución exportada.

## 3. Decisiones de interfaz

El producto se presenta como un estudio editorial y no como otro formulario largo. En escritorio, controles y lienzo conviven en dos columnas; en móvil se conserva el orden natural de trabajo —canal, enlace, mensaje, confirmación y pieza— para que la lectura visual, el teclado y los lectores de pantalla coincidan. La jerarquía primaria es `Descargar PNG`; copiar y compartir son utilidades secundarias.

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

Los textos y piezas pueden usar nombre, categoría, detalle, característica, hook, curaduría e imágenes aprobadas de Campañas. El campo `Texto visible en la pieza` gobierna directamente el resumen del PNG; el campo `Mensaje para compartir` acompaña el enlace copiado o Web Share. No congelan precio, stock, disponibilidad, máximo, proveedor, costo ni urgencia. La edición no se persiste en Supabase durante P2.

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
