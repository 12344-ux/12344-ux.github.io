# Supabase · Instrucciones para el dueno (Magandhi)

Esta guia es para aplicar manualmente, desde el dashboard de Supabase, el
cimiento de datos y seguridad del back-office interno (montaguth.institute).
El agente no tiene acceso al dashboard: por eso todo el SQL vive en el repo y
tu lo ejecutas siguiendo estos pasos en orden.

Datos del proyecto:

- URL del proyecto: `https://bxlzipwxyxdtffnuizbz.supabase.co`
- Publishable key (PUBLICA, va en el cliente): `sb_publishable_ap4jdsO_0KPOPWhUk9Y7ZA_0jDUvHu1`
- Usuario administrador (ya creado por ti): `michaelmagandhi@outlook.com`
- UID del administrador: `89e5028d-8c17-4deb-89c3-59acbd0ee2f2`

---

## 1. Abrir el SQL Editor de Supabase

1. Entra a [https://supabase.com](https://supabase.com) e inicia sesion.
2. Selecciona el proyecto de Magandhi (URL `bxlzipwxyxdtffnuizbz`).
3. En el menu lateral izquierdo, abre **SQL Editor**.
4. Pulsa **New query** para tener un editor en blanco.

## 2. Ejecutar la migracion de perfiles y roles

1. Abre en el repo el archivo `supabase/migrations/20250101000000_crear_perfiles_y_roles.sql`.
2. Copia **todo** su contenido y pegalo en el SQL Editor.
3. Pulsa **Run** (o Ctrl/Cmd + Enter).
4. Debe terminar sin errores. Esto crea:
   - La tabla `perfiles` (id -> rol -> modulos -> creado).
   - RLS activado con una unica policy de lectura (cada usuario solo lee su propia fila).
   - La fila del administrador (tu UID con rol `admin`).
   - La funcion helper `tiene_modulo(text)`.

   El archivo ya trae el `INSERT` del administrador con `on conflict do update`,
   asi que puedes re-ejecutarlo sin duplicar nada si algo falla a mitad.

## 3. Confirmar que Auth Email esta habilitado y que el usuario admin existe

1. En el menu lateral, abre **Authentication**.
2. En **Providers**, confirma que **Email** esta habilitado (ya deberia estarlo).
3. En **Users**, confirma que existe el usuario `michaelmagandhi@outlook.com`
   y que su UID coincide con `89e5028d-8c17-4deb-89c3-59acbd0ee2f2`.
   - Si el UID fuera distinto (por ejemplo, si recreaste el usuario), copia el
     UID real, ajusta el valor en el `INSERT` del paso 2 y vuelve a ejecutarlo.

## 4. Exposicion de la tabla en la API (auto-expose new tables OFF)

- La opcion **auto-expose new tables** esta en **OFF**, y asi debe quedarse.
- No hace falta exponer `perfiles` de forma insegura: el acceso correcto es a
  traves del rol `authenticated` con RLS. La policy `perfiles_lectura_propia`
  ya permite que cada usuario, tras iniciar sesion, lea unicamente su propia
  fila. Eso es suficiente para que el frontend descubra su rol.
- No crees policies de INSERT / UPDATE / DELETE para `authenticated`. La
  gestion de perfiles (asignar rol o modulos a otras personas) se hace desde
  aqui, en el SQL Editor, que corre con service_role y salta RLS.

## 5. Nota de seguridad sobre las llaves (no negociable)

- La **publishable key** (`sb_publishable_...`) es publica por diseno: va en el
  cliente (navegador). Su alcance esta limitado por las policies de RLS, por eso
  es seguro que aparezca en el frontend.
- La **secret key / service_role key** NUNCA debe ir en el repo, ni en el
  frontend, ni compartirse. Solo se usa desde el dashboard o desde una Edge
  Function del lado del servidor. Si alguna vez se filtra, rotala de inmediato
  en **Settings > API**.
- El candado real esta en los datos (RLS), no en el HTML. Ocultar una pagina en
  el navegador es solo comodidad visual, no seguridad.

## 6. Como verificar despues

1. Aplicado el SQL, ve al login del sitio (`index.html`) e inicia sesion con
   `michaelmagandhi@outlook.com`.
2. El panel interno (`panel.html`) debe cargar y leer tu rol `admin` desde la
   tabla `perfiles` (respetando RLS: solo ves tu propia fila).
3. Para delegar en el futuro (por ejemplo, dar a tu hermano solo el modulo de
   pedidos): crea su usuario en **Authentication > Users** y, desde el SQL
   Editor, ejecuta algo como:

   ```sql
   insert into perfiles (id, rol, modulos)
   values ('<UID-del-hermano>', 'hermano', '{pedidos}')
     on conflict (id) do update
       set rol = excluded.rol, modulos = excluded.modulos;
   ```

   Con eso, ese usuario solo tendra acceso al modulo `pedidos`; tu, como
   `admin`, seguiras teniendo acceso a todo.
