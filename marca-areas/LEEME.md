# Logos por área — Back-office MAGANDHI

Esta carpeta guarda los íconos/logos que distinguen cada área interna de
montaguth.institute (control interno), conservando la identidad de marca
de MAGANDHI pero con una variación cromática por área.

## Favicons oficiales (en uso)

- `control-interno.png` → ícono GENERAL (login / panel de montaguth.institute).
  Domo MAGANDHI + escudo, en **azul marino**. PNG con **fondo transparente**.
- `finanzas.png` → ícono del Área de Finanzas.
  Domo MAGANDHI + moneda ($) y gráfico ascendente, en **verde**. PNG con
  **fondo transparente**.
- `produccion.png` → ícono del Área de Producción (Inventarios adentro).
  **PLACEHOLDER provisional**: es una copia de `control-interno.png` (azul
  marino) para que las páginas de `produccion/` no queden con un favicon 404.
  El dueño debe **reemplazarlo** por el arte final del área (base del domo
  MAGANDHI en la **familia azul marino** del back-office, sin color nuevo) y
  subir el `?v=N` del `<link rel="icon">` de las páginas de Producción.
- `marketing.png` → ícono del Área de Marketing (Marketing Project adentro).
  **PLACEHOLDER provisional**: es una copia de `control-interno.png` (azul
  marino) para que las páginas de `marketing/` no queden con un favicon 404.
  El dueño debe **reemplazarlo** por el arte final del área (base del domo
  MAGANDHI en la **familia azul marino** del back-office, **sin color nuevo**:
  el verde ya es de Finanzas) y subir el `?v=N` del `<link rel="icon">` de las
  páginas de Marketing.
- `ventas.png` → ícono del Área de Ventas (Seguimiento de pedidos y Portafolio
  de clientes adentro).
  **PLACEHOLDER provisional**: es una copia de `control-interno.png` (azul
  marino) para que las páginas de `ventas/` no queden con un favicon 404.
  El dueño debe **reemplazarlo** por el arte final del área (base del domo
  MAGANDHI en la **familia azul marino** del back-office, **sin color nuevo**:
  el verde ya es de Finanzas) y subir el `?v=N` del `<link rel="icon">` de las
  páginas de Ventas.

Ambos los diseñó el dueño y se exportaron con fondo transparente (removebg /
Firefly). Se referencian con `?v=N` (cache-bust) en el `<link rel="icon">` de
cada página.

## Sistema por áreas (a futuro)

Cada área nueva del back-office (ej. pedidos, inventario) tendrá su propio
ícono con **color representativo**, conservando la base del domo MAGANDHI.
Esto es SOLO para el back-office interno (montaguth.institute), nunca para la
tienda pública magandhi.com.

## Cómo actualizar un favicon

Sube el PNG (idealmente cuadrado, fondo transparente) con el nombre del área
y sube el `?v=N` del `<link rel="icon">` en las páginas correspondientes para
forzar que el navegador tome la versión nueva.
