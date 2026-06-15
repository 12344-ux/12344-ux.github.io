# Opción C — Entrega privada de guías (Edge Function)

Sirve guías HTML desde un bucket **privado**, **renderizadas**, con un **link firmado que caduca**.
Todo se hace desde el panel de Supabase (navegador), sin instalar nada.

## 1. Crear el bucket privado
Supabase → **Storage** → **New bucket** → nombre `guias` → marcar **Private** → crear.

## 2. Crear la función
Supabase → **Edge Functions** → **Create a function** → nombre `entrega`.
Pega el contenido de `index.ts` en el editor.

## 3. Desactivar "Verify JWT"
En los ajustes de la función, **apaga "Enforce JWT verification"**.
(Si está encendido, el link del cliente pediría un token y no abriría en el navegador.)

## 4. Agregar el secreto
Edge Functions → **Secrets** → añade:
- Nombre: `LINK_SECRET`
- Valor: una frase larga e inventada (ej. `stramont-2026-aB7k9zQ...`). **Guárdala**: la necesitas para generar links.

(`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` las pone Supabase solo, no las toques.)

## 5. Deploy
Botón **Deploy**.

---

## Cómo entregar una guía a un cliente

1. **Subir la guía:** Storage → `guias` → **Upload** → sube tu `.html` (ej. `cliente-juan.html`).
2. **Generar el link (mint):** abre en el navegador
   `https://ifvnuvjvlzpdaimelmbm.supabase.co/functions/v1/entrega?mint=1&f=cliente-juan.html&days=30&key=TU_LINK_SECRET`
   → te devuelve el link firmado. **Ese** es el que mandas por correo al cliente.
   ⚠️ No compartas la URL de *mint* (lleva tu clave); solo el link que te devuelve.
3. **Listo:** el cliente abre el link → ve la guía renderizada.

## Caducidad y borrado
- A los `days` días el link dice "Este enlace ha expirado." (automático).
- Para liberar espacio: Storage → `guias` → borra el archivo (el link muere al instante).

## Prueba rápida
- Abre el link firmado → debe **renderizar** la guía.
- Cambia un carácter del `sig` → "Enlace inválido."
