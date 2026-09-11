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

---

# Modulo Finanzas · Contabilidad de partida doble (PUC)

Esta seccion aplica el cimiento de datos del PRIMER software interno: el
modulo de Finanzas / Contabilidad basada en el PUC colombiano (Decreto 2650).
Es contabilidad MANUAL con partida doble: tu (o el trabajador de finanzas)
registras los asientos en el Libro Diario y el sistema valida el cuadre,
lleva la trazabilidad y deriva solo el Libro Mayor y los saldos.

**Requisito previo:** la migracion de perfiles y roles
(`20250101000000_crear_perfiles_y_roles.sql`) YA debe estar aplicada, porque
todas las tablas de finanzas se protegen con la funcion `tiene_modulo('finanzas')`
que se creo alli.

## F1. Orden EXACTO de ejecucion en el SQL Editor

Abre el **SQL Editor** (igual que en el paso 1 de arriba) y ejecuta, EN ESTE
ORDEN, el contenido completo de cada archivo (cada uno con su propio **Run**):

1. `supabase/migrations/20250201000000_finanzas_catalogo_puc.sql`
   Crea la tabla `puc_cuentas` (catalogo PUC de 4 niveles) y sus indices.
2. `supabase/migrations/20250201000100_finanzas_carga_puc.sql`
   Carga los datos del PUC (clases, grupos y cuentas/subcuentas de comercio).
3. `supabase/migrations/20250201000200_finanzas_asientos.sql`
   Crea `asientos` y `asiento_lineas` (montos en bigint, pesos enteros).
4. `supabase/migrations/20250201000300_finanzas_mayor_vista.sql`
   Crea las vistas `movimientos_mayor` y `saldos_cuenta` (Libro Mayor derivado).
5. `supabase/migrations/20250201000400_finanzas_trazabilidad.sql`
   Crea `asiento_bitacora` y el trigger que registra crear/anular (la
   edicion la registra `editar_asiento` como un unico evento, sin duplicar).
6. `supabase/migrations/20250201000500_finanzas_rls.sql`
   Activa RLS en TODAS las tablas de finanzas con `tiene_modulo('finanzas')`.
7. `supabase/migrations/20250201000600_finanzas_funciones.sql`
   Crea las funciones RPC `guardar_asiento`, `editar_asiento`, `anular_asiento`
   e `incrementar_uso_cuenta` (refuerzan la regla de oro server-side).
8. `supabase/migrations/20250201000700_finanzas_grants.sql`
   Otorga al rol `authenticated` el GRANT base de tabla (SELECT) que faltaba.
   POR QUE: con "auto-expose new tables" en OFF (paso 4, correcto por
   seguridad), las tablas creadas por migraciones nunca recibieron el GRANT de
   la capa 1, asi que Postgres respondia `permission denied for table perfiles`
   (403) ANTES de evaluar RLS. Este archivo destraba solo esa capa 1 con el
   minimo privilegio: SELECT en `perfiles`, `puc_cuentas`, `asientos`,
   `asiento_lineas`, `asiento_bitacora` y las vistas `movimientos_mayor` /
   `saldos_cuenta` (lo unico que el cliente lee directo). NO abre
   INSERT/UPDATE/DELETE (toda escritura va por RPC security definer) ni concede
   nada a `anon`. La seguridad real sigue siendo RLS + las RPC.
9. `supabase/migrations/20250201000800_finanzas_agregar_cuenta.sql`
   Crea la RPC security definer `agregar_cuenta_puc(codigo, nombre, naturaleza,
   imputable)`, que es la UNICA via de escritura del catalogo PUC desde el
   software (la pantalla "Agregar cuenta"). Valida SOLO admin + formato +
   duplicado + existencia del padre (jerarquia) para no crear cuentas
   huerfanas. Como usa `create or replace`, si en el futuro la ajustas basta
   con **volver a ejecutar solo este archivo**, sin tocar los demas.

Los archivos son idempotentes (`create ... if not exists`, `on conflict do
update`, `create or replace`, `drop policy if exists`): si algo falla a mitad,
puedes re-ejecutar sin duplicar nada.

## F2. Como verificar que quedo bien

Ejecuta estas consultas en el SQL Editor:

1. **Catalogo cargado** (debe devolver un numero > 0, alrededor de 130 filas
   con esta carga; ver nota de "catalogo parcial" abajo):

   ```sql
   select count(*) from puc_cuentas;
   select count(*) from puc_cuentas where imputable = true; -- cuentas de detalle
   ```

2. **Acceso por modulo** (estando logueado como admin devuelve `true`):

   ```sql
   select tiene_modulo('finanzas');
   ```

3. **Un asiento descuadrado es RECHAZADO** (esto DEBE dar error, es la prueba
   de que la regla de oro funciona server-side):

   ```sql
   select guardar_asiento(
     current_date,
     'PRUEBA descuadrada (debe fallar)',
     '[{"cuenta_codigo":"110505","debe":100000,"haber":0},
       {"cuenta_codigo":"413505","debe":0,"haber":90000}]'::jsonb
   );
   -- Esperado: ERROR "El asiento no cuadra: total DEBE (100000) distinto de total HABER (90000)."
   ```

4. **Un asiento CUADRADO se guarda** (venta de contado con IVA, ejemplo):

   ```sql
   select guardar_asiento(
     current_date,
     'Venta de mercancia de contado',
     '[{"cuenta_codigo":"110505","detalle":"Efectivo","debe":119000,"haber":0},
       {"cuenta_codigo":"413505","detalle":"Venta","debe":0,"haber":100000},
       {"cuenta_codigo":"240805","detalle":"IVA 19%","debe":0,"haber":19000}]'::jsonb
   );
   -- Esperado: devuelve el uuid del asiento creado.
   ```

5. **Los saldos se derivan solos** (tras el paso 4 debe devolver filas):

   ```sql
   select * from saldos_cuenta order by cuenta_codigo;
   select * from movimientos_mayor order by fecha;
   ```

6. **La bitacora registro la creacion** (debe haber una fila con accion 'crear'):

   ```sql
   select accion, cuando, detalle_cambio from asiento_bitacora order by cuando desc;
   ```

7. **El GRANT de la capa 1 destrabo el acceso (fin del 403)**: tras aplicar el
   archivo 8, cierra sesion y vuelve a entrar al sitio (`index.html`), inicia
   sesion y abre **panel > Finanzas**. El modulo debe leer tu perfil y el
   catalogo SIN el error `permission denied for table perfiles` (403) que
   aparecia en la consola del navegador (`auth-guard.js: No se pudo leer el
   perfil`). Si aun ves el 403, confirma que ejecutaste el archivo 8 completo y
   que la fila de tu usuario existe en `perfiles` (paso 3).

   (Opcional) Para dejar limpio tras las pruebas, puedes anular el asiento de
   prueba con `select anular_asiento('<uuid-devuelto-en-el-paso-4>', 'prueba');`
   No lo borres: el modelo no permite borrado fisico, solo anulacion trazable.

## F3. Como DAR ACCESO al modulo finanzas a un usuario

El acceso al modulo se controla con la lista `modulos` de la tabla `perfiles`
(el `admin` ya tiene todo). Para que una persona (por ejemplo, el trabajador
del area de finanzas) pueda entrar SOLO a finanzas:

1. Crea su usuario en **Authentication > Users** (o pidele que se registre).
2. Copia su UID y ejecuta en el SQL Editor:

   ```sql
   insert into perfiles (id, rol, modulos)
   values ('<UID-del-usuario-de-finanzas>', 'finanzas', '{finanzas}')
     on conflict (id) do update
       set rol = excluded.rol, modulos = excluded.modulos;
   ```

   Ese usuario solo vera el modulo de finanzas; no vera pedidos ni ningun otro.
   Si quisieras darle finanzas ADEMAS de otro modulo, usa `'{finanzas,pedidos}'`.

## F4. Montos en pesos enteros (importante)

Todos los montos (`debe`, `haber`) son `bigint`: **pesos colombianos enteros,
sin centavos**. Por ejemplo, $1.200.000 se guarda como `1200000`. Nunca uses
decimales: las funciones rechazan montos con punto decimal. Esto evita los
errores de redondeo del punto flotante.

Ademas hay un **tope por linea de 1.000.000.000.000 (un billon de pesos)**:
cualquier linea con un `debe` o `haber` mayor es rechazada por `fz_validar_lineas`
(y la interfaz tampoco deja guardar). Es un candado de rango, muy por encima de
cualquier operacion real de un comercio, que cierra el techo de precision del
calculo de cuadre en el navegador (JavaScript solo es exacto por debajo de 2^53).
Si en el futuro necesitaras registrar importes mayores, sube ese tope en los DOS
lugares: `c_tope_linea` en `20250201000600_finanzas_funciones.sql` y
`TOPE_MONTO_LINEA` en `finanzas/finanzas-core.js`.

> **Reaplicacion tras esta correccion:** el archivo 7
> (`20250201000600_finanzas_funciones.sql`) cambio (tope por linea y, en
> `editar_asiento`, snapshot de las lineas anteriores en la bitacora). Como todas
> las funciones usan `create or replace`, basta con **volver a ejecutar ese
> archivo** en el SQL Editor; no hay que tocar los demas ni borrar nada.

## F5. NOTA · El catalogo PUC quedo PARCIAL (a proposito)

La carga del paso F1.2 **no incluye las ~800 cuentas completas** del Decreto
2650. Incluye las 9 clases, los grupos y las cuentas/subcuentas que un comercio
como MAGANDHI usa de verdad (caja, bancos, clientes, mercancias, IVA,
retenciones, proveedores, patrimonio, ingresos por venta, gastos de
administracion y de ventas, costo de ventas, etc.). Con eso ya puedes operar.

Para anadir cualquier otra cuenta oficial del PUC mas adelante, usa la
**PLANTILLA DE INSERT** que esta comentada al final del archivo
`20250201000100_finanzas_carga_puc.sql`: inserta primero la cuenta padre (si
no existe) y luego la subcuenta, con la naturaleza de su clase
(clases 1,5,6,7,8 -> debito; 2,3,4,9 -> credito; salvo cuentas correctoras) e
`imputable=true` solo en el nivel de detalle. **Nunca inventes codigos:** usa
los codigos oficiales del Decreto 2650.

Ahora, ademas de esa plantilla SQL, tienes la opcion mas comoda: **agregar
cuentas desde el propio software** (ver F6), sin abrir el SQL Editor.

## F6. Agregar cuentas al PUC desde el software (solo admin)

Ya no necesitas tocar SQL para anadir una cuenta nueva: hay una pantalla dentro
del modulo de Finanzas. **Solo el administrador puede usarla.** Este es un
doble control: la interfaz oculta la opcion a los no-admin (comodidad), y la
RPC `agregar_cuenta_puc` (archivo 9 de F1) **rechaza** la operacion en el
servidor si quien la ejecuta no es admin (ese es el candado real; no depende de
lo que muestre el navegador).

**Como abrirla:** entra al modulo Finanzas, ve a **Catalogo PUC** y pulsa
**Agregar cuenta** (el enlace solo aparece si eres admin). Tambien hay una
tarjeta "Agregar cuenta" en la home del modulo, tambien solo para admin.

**Que valida (cuida la integridad del Libro):** la RPC comprueba el formato del
codigo (solo digitos, longitud 1/2/4/6), que la naturaleza sea debito o credito,
que el nombre no este vacio, que la cuenta no exista ya y, sobre todo, **que
exista la cuenta padre** segun la jerarquia (6->4->2->1). Asi **no se crean
cuentas huerfanas** que romperian el Libro Mayor. La pantalla ademas sugiere en
vivo la naturaleza por clase, el nivel por la longitud y marca imputable para
los codigos de 6 digitos; todo sigue siendo confirmable por ti.

**Prueba manual (agregar y verla en el Nuevo Asiento):**

1. Como admin, abre **Catalogo PUC > Agregar cuenta**.
2. Agrega una subcuenta imputable de prueba **cuyo padre ya exista**. Por
   ejemplo `110599` (nombre "Otras cajas de prueba"): su padre es `1105`, que
   ya esta cargado. Deja la naturaleza sugerida (debito) e imputable marcado.
   Debe aparecer el mensaje verde "✓ Cuenta 110599 agregada...".
3. Ve a **Nuevo asiento** y en el buscador de cuenta escribe `110599` (o parte
   del nombre). **Debe aparecer** en la lista para poder contabilizarla: la
   pantalla de agregar y la de Nuevo Asiento leen la MISMA tabla `puc_cuentas`,
   asi que una cuenta imputable nueva aparece de inmediato, sin pasos extra.

**Prueba de rechazo (ver la validacion de jerarquia):**

- Vuelve a **Agregar cuenta** e intenta agregar un codigo cuyo padre NO exista,
  por ejemplo `9995` (su padre seria el grupo `99`, que no esta cargado). La RPC
  lo **rechaza** con un mensaje como *"Primero debe existir la cuenta padre 99.
  No se pueden crear cuentas huerfanas."*. Tambien puedes probar a repetir un
  codigo existente (ej. `110505`) para ver el mensaje de duplicado. Asi
  compruebas que el candado server-side protege el Libro aunque la interfaz
  falle.

> Como la RPC usa `create or replace`, si mas adelante ajustas su logica basta
> con **volver a ejecutar solo el archivo 9**
> (`20250201000800_finanzas_agregar_cuenta.sql`), sin tocar los demas.
