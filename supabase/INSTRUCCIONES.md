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
10. `supabase/migrations/20250201000900_finanzas_balance_comprobacion.sql`
    Crea la funcion `balance_comprobacion(fecha_corte date)` (Tramo 2, paso 1:
    el Balance de comprobacion A FECHA DE CORTE). Se derivan solos, de las
    MISMAS tablas que el Libro Mayor, el `total_debe`, el `total_haber` y el
    saldo repartido en `saldo_deudor` / `saldo_acreedor` por cada cuenta
    imputable con movimiento (solo asientos activos con `fecha <= corte`). Es
    una FUNCION y no una vista porque necesita el parametro de fecha de corte.
    Es de solo lectura (`STABLE`), hereda la RLS del modulo (SECURITY INVOKER,
    igual que las vistas del mayor) y no abre ninguna escritura. Como usa
    `create or replace`, si en el futuro la ajustas basta con **volver a
    ejecutar solo este archivo**, sin tocar los demas.
11. `supabase/migrations/20250201001000_finanzas_estado_resultados.sql`
    Crea la funcion `estado_resultados(p_inicio date, p_fin date)` (Tramo 2,
    paso 2a: el Estado de resultados POR PERIODO). Es la "pelicula" del
    ejercicio entre dos fechas (no la foto acumulada del balance de
    comprobacion): toma el movimiento de las cuentas de resultado (clases
    4/5/6/7) entre `p_inicio` y `p_fin` (ambas inclusive) y devuelve, por cada
    cuenta imputable con movimiento, `clase`, `cuenta_codigo`, `cuenta_nombre`,
    `naturaleza`, `total_debe`, `total_haber` y `monto_periodo`. Con eso el
    frontend arma el estado clasificado y la utilidad o perdida del ejercicio.
    Es de solo lectura (`STABLE`), hereda la RLS del modulo (SECURITY INVOKER),
    montos en `bigint` (pesos enteros) y es idempotente (`create or replace`).
    Como usa `create or replace`, si en el futuro la ajustas basta con **volver
    a ejecutar solo este archivo**, sin tocar los demas.
12. `supabase/migrations/20250201001100_finanzas_balance_general.sql`
    Crea la funcion `balance_general(p_fecha_corte date)` (Tramo 2, paso 2b:
    el Balance General o Estado de Situacion Financiera A FECHA DE CORTE). Es
    la "foto" de lo que la empresa tiene y debe: devuelve, por cada cuenta
    imputable con movimiento (asientos activos con `fecha <= corte`), la
    `seccion` (`activo` clase 1, `pasivo` clase 2, `patrimonio` clase 3),
    `cuenta_codigo`, `cuenta_nombre`, `naturaleza` y `monto` en el lado natural
    de la clase (activo = debe-haber; pasivo y patrimonio = haber-debe). Ademas
    agrega UNA sola fila `seccion='resultado'` (Resultado del ejercicio),
    calculada con el MISMO criterio del Estado de resultados (paso 2a) para el
    periodo 1-ene-del-ano-del-corte .. corte, para que cuadre
    `ACTIVO = PASIVO + PATRIMONIO + RESULTADO`. Llama internamente a
    `estado_resultados`, asi que **el archivo 11 debe estar aplicado antes**.
    Es de solo lectura (`STABLE`), hereda la RLS del modulo (SECURITY INVOKER),
    montos en `bigint` (pesos enteros) y es idempotente (`create or replace`).
    Como usa `create or replace`, si en el futuro la ajustas basta con **volver
    a ejecutar solo este archivo**, sin tocar los demas.

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

## F7. Balance de comprobacion a fecha de corte (Tramo 2, paso 1)

El archivo 10 de F1 (`20250201000900_finanzas_balance_comprobacion.sql`) crea
la funcion `balance_comprobacion(fecha_corte date)`. Es el primer informe del
Tramo 2: la "foto" del Libro Mayor **hasta una fecha de corte**. Para cada
cuenta imputable con movimiento devuelve `cuenta_codigo`, `cuenta_nombre`,
`naturaleza`, `total_debe`, `total_haber`, `saldo_deudor` y `saldo_acreedor`.

Solo cuenta asientos con `estado='activo'` y `fecha <= corte` (los anulados no
cuentan). Es una FUNCION, no una vista, porque una vista no acepta el parametro
de fecha de corte. Se deriva de las MISMAS tablas que `saldos_cuenta`
(asientos, asiento_lineas, puc_cuentas), asi que no reinventa el calculo: el
saldo por naturaleza se reparte en dos columnas de presentacion (deudor /
acreedor).

**Como verlo** (foto a hoy; cambia `current_date` por cualquier fecha de corte):

```sql
select * from balance_comprobacion(current_date) order by cuenta_codigo;
-- Ejemplo de corte a una fecha concreta:
-- select * from balance_comprobacion('2025-01-31') order by cuenta_codigo;
```

**Comprobacion de CUADRE** (la prueba de que el balance esta bien): en un libro
de partida doble cuadrado, la suma de los debitos iguala la de los creditos y
la suma de los saldos deudores iguala la de los saldos acreedores. Esta
consulta debe devolver dos parejas iguales:

```sql
select
  sum(total_debe)     as suma_debe,
  sum(total_haber)    as suma_haber,     -- debe ser igual a suma_debe
  sum(saldo_deudor)   as suma_deudor,
  sum(saldo_acreedor) as suma_acreedor   -- debe ser igual a suma_deudor
from balance_comprobacion(current_date);
-- Esperado: suma_debe = suma_haber  Y  suma_deudor = suma_acreedor (el balance cuadra).
```

Si esas parejas no cuadran, el problema NO esta en el balance (cuadra por
construccion) sino en algun asiento; revisa el Libro Diario. La funcion es de
solo lectura y no modifica nada.

> Como la funcion usa `create or replace`, si mas adelante ajustas su logica
> basta con **volver a ejecutar solo el archivo 10**
> (`20250201000900_finanzas_balance_comprobacion.sql`), sin tocar los demas.

## F8. Estado de resultados por periodo (Tramo 2, paso 2a)

El archivo 11 de F1 (`20250201001000_finanzas_estado_resultados.sql`) crea la
funcion `estado_resultados(p_inicio date, p_fin date)`. Es el segundo informe
del Tramo 2 y, a diferencia del balance de comprobacion, es la "pelicula" del
ejercicio **entre dos fechas** (no una foto acumulada a una fecha de corte).

Toma solo el movimiento de las cuentas de RESULTADO (clases 4, 5, 6 y 7) de los
asientos con `estado='activo'` y `fecha` entre `p_inicio` y `p_fin` (ambas
inclusive). Se excluyen a proposito las clases de balance (1 activo, 2 pasivo y
3 patrimonio), que no forman parte del estado de resultados. Por cada cuenta
imputable con movimiento devuelve `clase` (el primer digito del codigo),
`cuenta_codigo`, `cuenta_nombre`, `naturaleza`, `total_debe`, `total_haber` y
`monto_periodo`.

Cada clase se presenta en su **lado natural** en positivo, tomando solo el
movimiento del periodo:

- Ingresos (clase 4, natural credito): `monto_periodo = sum(haber) - sum(debe)`.
- Gastos (clase 5, natural debito): `monto_periodo = sum(debe) - sum(haber)`.
- Costo de ventas (clase 6, natural debito): `sum(debe) - sum(haber)`.
- Costos de produccion (clase 7, natural debito): `sum(debe) - sum(haber)`.

Con esos montos, la **utilidad (o perdida) del ejercicio** es:

```
utilidad = Ingresos(clase 4) - Costos(clase 6 + clase 7) - Gastos(clase 5)
```

Si el resultado es positivo hay utilidad; si es negativo, perdida. Como la
utilidad reutiliza exactamente los mismos montos enteros del informe, es exacta
(no hay redondeos). Esto importa porque esa **utilidad del ejercicio alimentara
despues el patrimonio del Balance General (paso 2b)**: cualquier diferencia de
un peso se arrastraria al balance.

**Como verlo** (ejemplo del ano corriente hasta hoy; cambia `p_inicio` por
cualquier fecha):

```sql
select * from estado_resultados('2025-01-01', current_date) order by cuenta_codigo;
```

**Comprobacion de la UTILIDAD** (agrega `monto_periodo` por clase usando el
primer digito del codigo y confirma que utilidad = ingresos - costos - gastos):

```sql
with r as (
  select left(cuenta_codigo, 1) as clase, sum(monto_periodo) as monto
  from estado_resultados('2025-01-01', current_date)
  group by left(cuenta_codigo, 1)
)
select
  coalesce(sum(monto) filter (where clase = '4'), 0)                as ingresos,
  coalesce(sum(monto) filter (where clase in ('6','7')), 0)         as costos,
  coalesce(sum(monto) filter (where clase = '5'), 0)                as gastos,
  coalesce(sum(monto) filter (where clase = '4'), 0)
    - coalesce(sum(monto) filter (where clase in ('6','7')), 0)
    - coalesce(sum(monto) filter (where clase = '5'), 0)            as utilidad_ejercicio
from r;
-- Esperado: utilidad_ejercicio = ingresos - costos - gastos.
```

Ejemplo concreto: si en el periodo se registra una venta con un ingreso (clase
4) de 100000 al haber, un costo de ventas (clase 6) de 20000 al debe y un gasto
(clase 5) de 30000 al debe, el informe presenta ingresos=100000, costos=20000,
gastos=30000 y `utilidad_ejercicio = 100000 - 20000 - 30000 = 50000` (utilidad).
Con la venta de contado del ejemplo F2 (ingreso 413505 de 100000, sin costos ni
gastos) la utilidad del periodo seria 100000.

La funcion es de solo lectura y no modifica nada.

> Como la funcion usa `create or replace`, si mas adelante ajustas su logica
> basta con **volver a ejecutar solo el archivo 11**
> (`20250201001000_finanzas_estado_resultados.sql`), sin tocar los demas.

## F9. Balance General a fecha de corte (Tramo 2, paso 2b)

El archivo 12 de F1 (`20250201001100_finanzas_balance_general.sql`) crea la
funcion `balance_general(p_fecha_corte date)`. Es el tercer informe del Tramo 2:
la "foto" de lo que la empresa TIENE y DEBE **hasta una fecha de corte**,
organizada en el gran cuadre contable `ACTIVO = PASIVO + PATRIMONIO`.

Por cada cuenta imputable con movimiento (asientos con `estado='activo'` y
`fecha <= corte`) devuelve `seccion`, `cuenta_codigo`, `cuenta_nombre`,
`naturaleza` y `monto`, presentando cada clase en su lado natural en positivo:

- ACTIVO (clase 1, natural debito): `monto = sum(debe) - sum(haber)`.
- PASIVO (clase 2, natural credito): `monto = sum(haber) - sum(debe)`.
- PATRIMONIO (clase 3, natural credito): `monto = sum(haber) - sum(debe)`.

Ademas agrega **una sola fila** con `seccion='resultado'` y `cuenta_nombre =
'Resultado del ejercicio'`. Ese resultado NO esta guardado en ninguna cuenta de
patrimonio (clase 3) porque este software aun no hace el asiento de CIERRE
ANUAL; por eso se calcula aparte, con EXACTAMENTE el mismo criterio del Estado
de resultados (paso 2a), para el periodo que va del **1 de enero del ano del
corte** hasta la fecha de corte (ano fiscal = ano calendario, ambas fechas
inclusive). Los meses sin movimiento suman cero: el inicio siempre es el 1-ene
del ano del corte, nunca se "detecta la primera operacion". La funcion llama por
dentro a `estado_resultados(1-ene-ano, corte)` para que ese numero coincida al
peso con el informe 2a:

```
resultado = Ingresos(clase 4) - Costos(clase 6 + clase 7) - Gastos(clase 5)
```

**Como verlo** (foto a hoy; cambia `current_date` por cualquier fecha de corte):

```sql
select * from balance_general(current_date) order by seccion, cuenta_codigo;
-- Ejemplo de corte a una fecha concreta:
-- select * from balance_general('2025-01-31') order by seccion, cuenta_codigo;
```

**Comprobacion de CUADRE** (la prueba de que el balance esta bien): en un libro
de partida doble cuadrado, el activo iguala al pasivo mas el patrimonio mas el
resultado del ejercicio. Esta consulta agrega `monto` por seccion y debe
devolver `activo = pasivo + patrimonio + resultado` (es decir, `diferencia = 0`):

```sql
with b as (
  select seccion, sum(monto) as monto
  from balance_general(current_date)
  group by seccion
)
select
  coalesce(sum(monto) filter (where seccion = 'activo'), 0)      as activo,
  coalesce(sum(monto) filter (where seccion = 'pasivo'), 0)      as pasivo,
  coalesce(sum(monto) filter (where seccion = 'patrimonio'), 0)  as patrimonio,
  coalesce(sum(monto) filter (where seccion = 'resultado'), 0)   as resultado,
  coalesce(sum(monto) filter (where seccion = 'activo'), 0)
    - coalesce(sum(monto) filter (where seccion = 'pasivo'), 0)
    - coalesce(sum(monto) filter (where seccion = 'patrimonio'), 0)
    - coalesce(sum(monto) filter (where seccion = 'resultado'), 0) as diferencia
from b;
-- Esperado: diferencia = 0  (activo = pasivo + patrimonio + resultado, el balance cuadra).
```

**Comprobacion de que el resultado coincide con el Estado de resultados (2a)**:
la fila `resultado` del balance debe ser identica a la utilidad que arroja
`estado_resultados` para el mismo periodo (1-ene-del-ano-del-corte .. corte).
Esta consulta debe devolver las dos columnas iguales (`iguales = true`):

```sql
with er as (
  select left(cuenta_codigo, 1) as clase, sum(monto_periodo) as monto
  from estado_resultados(
         make_date(extract(year from current_date)::int, 1, 1),
         current_date
       )
  group by left(cuenta_codigo, 1)
)
select
  (select monto from balance_general(current_date) where seccion = 'resultado') as resultado_balance,
  coalesce(sum(monto) filter (where clase = '4'), 0)
    - coalesce(sum(monto) filter (where clase in ('6','7')), 0)
    - coalesce(sum(monto) filter (where clase = '5'), 0)                          as utilidad_estado_resultados,
  (select monto from balance_general(current_date) where seccion = 'resultado')
    = (coalesce(sum(monto) filter (where clase = '4'), 0)
        - coalesce(sum(monto) filter (where clase in ('6','7')), 0)
        - coalesce(sum(monto) filter (where clase = '5'), 0))                     as iguales
from er;
-- Esperado: resultado_balance = utilidad_estado_resultados  (iguales = true).
```

> **CAVEAT HONESTO (cierre anual no implementado):** el cuadre
> `ACTIVO = PASIVO + PATRIMONIO + RESULTADO` asume que TODO el movimiento de las
> cuentas de resultado (clases 4/5/6/7) del libro pertenece al ano del corte.
> Como este software AUN NO hace el asiento de cierre anual (el que salda las
> clases 4/5/6/7 contra el patrimonio al terminar cada ano), si existieran
> movimientos de resultado de un ANO ANTERIOR al del corte y sin cerrar, la
> ecuacion simple podria no cuadrar exactamente (ese resultado viejo no estaria
> ni en el patrimonio clase 3 ni dentro del periodo 1-ene-ano..corte que aqui se
> calcula). Para el uso actual de MAGANDHI (empieza este ano, sin ejercicios
> anteriores) cuadra perfecto. El cierre anual queda como funcion futura; el
> informe NO aplica ningun ajuste, esta es solo una nota honesta.

> Como la funcion usa `create or replace`, si mas adelante ajustas su logica
> basta con **volver a ejecutar solo el archivo 12**
> (`20250201001100_finanzas_balance_general.sql`), sin tocar los demas. Recuerda
> que necesita que el archivo 11 (`estado_resultados`) ya este aplicado.

---

# Modulo Inventario + Marketing (Produccion)

Esta seccion aplica el cimiento de datos del SEGUNDO software interno: el
modulo de **Inventario** (dentro del area de Produccion) y su lectura desde el
area de **Marketing** (Marketing Project -> Proyeccion de la demanda). Mismo
estandar y misma filosofia que Finanzas: nada se borra en silencio, cantidades
enteras (unidades), montos en `bigint` (pesos enteros, nunca float), y el
candado real vive en los DATOS (RLS + RPC security definer), no en el HTML.

Idea central (la misma del Libro Mayor de Finanzas): **el stock NO es un numero
editable**. Se registra un LIBRO de movimientos (append-only) y el stock
ACTUAL se DERIVA sumando ese libro. Se guarda TODO PARA SIEMPRE, sin limite de
tiempo; un error no se borra, se compensa con un ajuste que deja el rastro.

**Cita a ciegas (decision del dueno):** Inventario y Contabilidad NO se hablan
entre si. Inventario alimenta a Marketing por el DATO (el libro), no por
codigo, y Contabilidad sigue siendo MANUAL y desconectada de Inventario. No hay
ningun enganche automatico Inventario -> Finanzas.

**Requisito previo:** la migracion de perfiles y roles
(`20250101000000_crear_perfiles_y_roles.sql`) YA debe estar aplicada, porque
todas las tablas de este modulo se protegen con la funcion central
`tiene_modulo(text)` que se creo alli. Sobre ella, este modulo crea dos
envoltorios de acceso que aceptan varias claves equivalentes (ver la
**convencion de claves** en I4): `tiene_acceso_inventario()` (creada en el
archivo 4) y `tiene_acceso_marketing()` (creada en el archivo 7, el puente de
Marketing).

## I1. Orden EXACTO de ejecucion en el SQL Editor

Abre el **SQL Editor** (igual que en el paso 1 de arriba) y ejecuta, EN ESTE
ORDEN, el contenido completo de cada archivo (cada uno con su propio **Run**):

1. `supabase/migrations/20250301000000_inventario_productos.sql`
   Crea `inventario_config` (una sola fila, prefijo del SKU = `MAG`), la
   secuencia `inventario_sku_seq` (consecutivo global del SKU) y la tabla
   `productos` (la ficha / el "que" se vende). No guarda stock: eso se deriva.
2. `supabase/migrations/20250301000100_inventario_movimientos.sql`
   Crea `movimientos_inventario`, EL LIBRO append-only (tipos
   `entrada`/`salida`/`ajuste_entrada`/`ajuste_salida`, cantidad siempre
   positiva). Incluye `customer_id` como columna ANTICIPADA (sin FK: aun no
   hay tabla de clientes).
3. `supabase/migrations/20250301000200_inventario_stock_vista.sql`
   Crea la vista `stock_actual` (existencias DERIVADAS del libro por producto;
   entrada/ajuste_entrada suman, salida/ajuste_salida restan). SECURITY
   INVOKER: hereda la RLS de sus tablas base.
4. `supabase/migrations/20250301000300_inventario_rls.sql`
   Crea la funcion de acceso del modulo `tiene_acceso_inventario()` (envuelve
   `tiene_modulo` y acepta las claves equivalentes `inventario`/`produccion`/
   `inventarios`) y activa RLS en TODAS las tablas del modulo usandola. Solo
   policies de SELECT; sin INSERT/UPDATE/DELETE (toda escritura va por RPC) y
   sin DELETE en ninguna tabla.
5. `supabase/migrations/20250301000400_inventario_funciones.sql`
   Crea las RPC security definer `inv_crear_producto`,
   `inv_registrar_movimiento` e `inv_editar_producto` (la UNICA via de
   escritura; cada una valida `tiene_acceso_inventario()` al entrar). **Corre
   DESPUES del archivo 4**, que es donde se define esa funcion.
6. `supabase/migrations/20250301000500_inventario_grants.sql`
   Otorga al rol `authenticated` el GRANT base de tabla (SELECT) que faltaba
   por tener "auto-expose new tables" en OFF. POR QUE: igual que en Finanzas
   (archivo 8 de F1), sin este GRANT de capa 1 Postgres responde
   `permission denied` (403) ANTES de evaluar RLS. Destraba solo esa capa con
   el minimo privilegio: SELECT en `productos`, `movimientos_inventario`,
   `inventario_config` y la vista `stock_actual`. NO abre
   INSERT/UPDATE/DELETE (toda escritura va por RPC) ni concede nada a `anon`.
7. `supabase/migrations/20250301000600_inventario_marketing_lectura.sql`
   **Ejecutalo DESPUES de los anteriores.** Es el puente de LECTURA
   Inventario -> Marketing: crea la funcion `tiene_acceso_marketing()`
   (envuelve `tiene_modulo` y acepta las claves equivalentes `marketing`/
   `marketing-project`) y anade policies SELECT extra en `productos` y
   `movimientos_inventario` que ADEMAS permiten leer cuando esa funcion es
   verdadera, para que un usuario SOLO de marketing pueda alimentar la
   Proyeccion de la demanda sin darle el modulo de inventario. Estrictamente de
   lectura: no toca INSERT/UPDATE/DELETE.

Los archivos son idempotentes (`create ... if not exists`, `on conflict do
nothing`, `create or replace`, `drop policy if exists`): si algo falla a mitad,
puedes re-ejecutar sin duplicar nada.

## I2. Como verificar que quedo bien

Ejecuta estas consultas en el SQL Editor:

1. **Acceso al modulo** (estando logueado como admin ambas devuelven `true`):

   ```sql
   select tiene_modulo('inventario');      -- clave canonica del dato
   select tiene_acceso_inventario();       -- acepta inventario/produccion/inventarios
   select tiene_acceso_marketing();         -- acepta marketing/marketing-project
   ```

   El `admin` ve todo, asi que las tres dan `true`. Para un no-admin, el
   candado real es `tiene_acceso_inventario()` / `tiene_acceso_marketing()`
   (ver la **convencion de claves** en I4), no `tiene_modulo` a secas.

2. **Crear un producto** (la RPC genera el `product_id` uuid y el SKU
   server-side; el dueno NO los escribe). La firma completa lleva 13 parametros
   con valores por defecto, asi que basta con nombrar los que interesan:

   ```sql
   select inv_crear_producto(
     p_nombre           => 'Shampoo solido de romero',
     p_descripcion      => 'Barra 100 g',
     p_categoria        => 'Cuidado del cabello',
     p_precio_venta     => 28000,
     p_cantidad_inicial => 10
   );
   -- Esperado: jsonb {"id": "<uuid>", "sku": "MAG-CUID-0001"}.
   ```

   El SKU es `<prefijo>-<CAT>-<consecutivo 4 digitos>`:
   - `<prefijo>` = `MAG`, tomado de `inventario_config` (clonable, no escrito a
     fuego en la RPC).
   - `<CAT>` = los primeros 3-4 caracteres de la categoria en MAYUSCULAS y sin
     acentos, dejando solo `A-Z0-9`. La RPC hace: `upper(trim(...))` ->
     translitera acentos -> borra todo lo que no sea `A-Z0-9` (incluidos los
     espacios) -> toma los primeros 4 caracteres. Aqui `Cuidado del cabello`
     se vuelve `CUIDADODELCABELLO` y sus primeros 4 caracteres dan `CUID`, por
     eso el SKU es `MAG-CUID-0001`. Si el producto no tiene categoria, ese
     tramo se OMITE por completo (`MAG-0001`).
   - `<consecutivo>` = `nextval('inventario_sku_seq')` relleno a 4 digitos
     (concurrencia-seguro; NO se cuentan filas). Es global, no por categoria.

   > El tramo `<CAT>` tiene entre 1 y 4 caracteres segun la categoria (una
   > categoria corta como `Te` daria `MAG-TE-0001`). Cambia el ejemplo por la
   > categoria real que uses; lo importante es la forma `MAG-<CAT>-0001`.

3. **El stock se DERIVA solo** (tras el paso 2, el producto recien creado
   aparece con `existencias` igual a la cantidad inicial declarada, 10):

   ```sql
   select * from stock_actual order by sku;
   -- Esperado: la fila del SKU MAG-CUID-0001 con existencias = 10.
   ```

4. **Registrar una salida y ver que el stock BAJA** (usa el `id` uuid devuelto
   en el paso 2; la firma es
   `inv_registrar_movimiento(p_product_id, p_tipo, p_cantidad, p_motivo, p_referencia, p_costo_unitario_mov, p_fecha)`):

   ```sql
   select inv_registrar_movimiento(
     '<uuid-del-producto>', 'salida', 3, 'Venta tienda'
   );
   -- Esperado: jsonb {"id": "<uuid-mov>", "existencias": 7}.

   select existencias from stock_actual where product_id = '<uuid-del-producto>';
   -- Esperado: 7 (bajo 3 respecto de 10).
   ```

5. **Una salida MAYOR que el stock deja existencias NEGATIVAS (permitido)**.
   No es un error: es una senal honesta para reconciliar (PLANO §2.3, decision
   del dueno). Bloquearla a nivel de datos daria falsa sensacion de control y
   podria impedir registrar una venta que de verdad ocurrio:

   ```sql
   select inv_registrar_movimiento(
     '<uuid-del-producto>', 'salida', 100, 'Venta tienda'
   );
   -- Esperado: jsonb {"id": "<uuid-mov>", "existencias": -93}.
   -- La operacion NO falla; el stock queda en -93 como aviso de reconciliacion.
   ```

   La interfaz muestra ese numero en rojo para que decidas manualmente (no hay
   reposicion automatica ni cruce proyeccion <-> stock: se prefiere ver el
   numero puro y decidir a mano).

6. **Append-only: no hay via de borrado.** Ninguna tabla del modulo tiene
   policy de DELETE ni RPC de borrado; un producto no se elimina, se marca
   `activo = false` con `inv_editar_producto`, y un movimiento equivocado no se
   edita ni se borra: se compensa con un `ajuste_entrada` / `ajuste_salida` que
   deja el rastro. Se guarda TODO PARA SIEMPRE.

   (Opcional) Para dejar limpio tras las pruebas NO borres nada: puedes
   compensar la salida de prueba con una `entrada` por la misma cantidad, o
   dejar el producto de prueba marcado `activo=false`. El modelo, igual que
   Finanzas, no permite borrado fisico.

## I3. Storage: bucket de imagenes de producto

El inventario interno guarda una foto por producto. El dueno crea el bucket
UNA sola vez en el dashboard (el agente no tiene acceso a Storage):

1. En el menu lateral abre **Storage** y pulsa **New bucket**.
2. Nombre del bucket: **`productos`** (exacto; asi lo usa el frontend).
3. Marca el bucket como **Public** (lectura publica): la foto de un producto no
   es secreta y se ve en el inventario sin friccion. La ESCRITURA si queda
   restringida (siguiente paso).
4. Anade las policies de Storage para que **solo** quien tenga el modulo
   `inventario` pueda subir o reemplazar imagenes (lectura publica, escritura
   restringida). En **Storage > Policies** (sobre `storage.objects`) crea:

   ```sql
   -- INSERT: subir una imagen nueva solo si tiene_acceso_inventario().
   create policy "productos_img_insert" on storage.objects
     for insert to authenticated
     with check (bucket_id = 'productos' and tiene_acceso_inventario());

   -- UPDATE: reemplazar una imagen existente solo si tiene_acceso_inventario().
   create policy "productos_img_update" on storage.objects
     for update to authenticated
     using (bucket_id = 'productos' and tiene_acceso_inventario())
     with check (bucket_id = 'productos' and tiene_acceso_inventario());
   ```

   > Usa `tiene_acceso_inventario()` (no `tiene_modulo('inventario')` a secas)
   > para que la MISMA clave que abre la sub-area Inventarios en el panel
   > (`produccion` / `inventarios` / `inventario`) tambien habilite la subida de
   > imagen. Asi el trabajador de bodega con `'{produccion}'` puede subir fotos
   > sin recibir 403. **Crea estas policies DESPUES de aplicar el archivo 4 de
   > I1** (`20250301000300_inventario_rls.sql`), que es donde se define esa
   > funcion.

   La lectura publica ya la habilita el que el bucket sea **Public**; no hace
   falta una policy de SELECT para leer. NO crees policy de DELETE (append-only:
   las imagenes tampoco se borran desde el cliente).

Reglas de oro del Storage (no negociables):

- Las subidas usan **la sesion del usuario autenticado** (llave publishable,
  rol `authenticated`), **NUNCA** `service_role`. La `service_role` no va en el
  repo ni en el navegador jamas (ver paso 5 de seguridad, arriba).
- La base de datos guarda `productos.imagen_path` como una **key** dentro del
  bucket, no una URL completa. El frontend sube al bucket `productos` con la key
  `<product_id>.jpg` (sin prefijo `productos/`: el bucket ya se llama asi, y
  anteponerlo crearia una carpeta anidada redundante `productos/productos/...`)
  y guarda esa misma key en `imagen_path`; luego arma la URL publica en el
  cliente con `getPublicUrl(path)` sobre el bucket `productos`. Subida y lectura
  usan la MISMA key, y si algun dia cambia el dominio de Storage las keys
  guardadas no se rompen.
- El cliente **optimiza la imagen antes de subirla**: la redimensiona, la
  comprime y la reencoda a JPEG en el navegador (para que no ocupe tanto
  espacio) antes de mandarla al bucket. La foto original no se sube tal cual.

## I4. Modulos por AREA y sub-area (jerarquia del panel)

El panel de admin organiza el back-office en 3 areas: **FINANZAS**, **MARKETING**
y **PRODUCCION**. Marketing y Produccion funcionan como carpetas que abren sus
sub-areas (dentro de Marketing esta "Marketing Project" y sus categorias; dentro
de Produccion esta "Inventarios"). El acceso se controla con la lista `modulos`
de la tabla `perfiles`, con la misma convencion que Finanzas (el `admin` ve todo).

Claves de area: `finanzas`, `marketing`, `produccion`.
Claves de sub-area: `inventarios`, `marketing-project`.

### Convencion de claves (una sola historia: panel, cores y DATOS)

Esta es la regla clave para que el SEGUNDO usuario (un no-admin) funcione de
punta a punta y no vea la UI "viva" pero los datos "muertos" (403). Hay tres
capas que deben hablar el MISMO idioma:

- **Panel** (`panel.html`) y **cores** (`inventario-core.js`,
  `marketing-core.js`): deciden que carpeta se VE con las claves de area/
  sub-area (`produccion`/`inventarios`, `marketing`/`marketing-project`).
- **Datos** (RLS, RPC, policies de Storage y puente de Marketing): el candado
  REAL. Para que coincida con lo que ve la UI, NO exige una unica clave literal:
  usa dos funciones envoltorio que aceptan cualquiera de las claves equivalentes
  del area:
  - `tiene_acceso_inventario()` → `true` si el perfil tiene **`inventario`**
    (clave canonica del dato) **o** **`produccion`** (area) **o** **`inventarios`**
    (sub-area), o si es `admin`.
  - `tiene_acceso_marketing()` → `true` si el perfil tiene **`marketing`** (area)
    **o** **`marketing-project`** (sub-area), o si es `admin`.

Consecuencia practica: **quien ve la carpeta, puede operar sus datos.** Dar
`'{produccion}'` a un trabajador de bodega le abre Inventarios en el panel Y le
permite leer/registrar movimientos y subir imagenes, sin 403. Puedes usar
indistintamente `'{produccion}'`, `'{inventarios}'` o `'{inventario}'`: las tres
son equivalentes para Inventario (recomendado: la clave del area, `'{produccion}'`,
por ser la mas legible). Igual para Marketing con `'{marketing}'` o
`'{marketing-project}'`.

> Clonable: un area nueva copia este patron: define su(s) clave(s) en el panel/
> core y una funcion `tiene_acceso_<area>()` que las envuelva, y usala en RLS/
> RPC/Storage. Un solo lugar decide el vocabulario del area.

Para dar acceso a una persona (igual que en F3):

1. Crea su usuario en **Authentication > Users** (o pidele que se registre).
2. Copia su UID y ejecuta en el SQL Editor el `insert ... on conflict` que
   corresponda.

**Trabajador de bodega / Produccion (inventarios):**

```sql
insert into perfiles (id, rol, modulos)
values ('<UID-del-trabajador>', 'produccion', '{produccion}')
  on conflict (id) do update
    set rol = excluded.rol, modulos = excluded.modulos;
```

**Analista de Marketing (Proyeccion de la demanda):**

```sql
insert into perfiles (id, rol, modulos)
values ('<UID-del-analista>', 'marketing', '{marketing}')
  on conflict (id) do update
    set rol = excluded.rol, modulos = excluded.modulos;
```

El analista necesita LEER el libro de inventario para proyectar la demanda. Con
el archivo 7 de I1 aplicado (`20250301000600_inventario_marketing_lectura.sql`),
`tiene_acceso_marketing()` ya puede hacer SELECT sobre `productos` y
`movimientos_inventario`, asi que `'{marketing}'` basta y NO hay que darle
tambien acceso al modulo de inventario. **Si NO aplicaste ese archivo 7**, el
analista solo con `'{marketing}'` recibiria 403 al leer el libro; en ese caso,
dale ademas una clave de inventario para que la RLS de inventario lo deje leer,
p.ej. `'{marketing,produccion}'` (`produccion` es una de las claves que acepta
`tiene_acceso_inventario()`). **Lo recomendado es aplicar el archivo 7** para
que baste `'{marketing}'`. Puedes combinar modulos como en Finanzas
(`'{finanzas,marketing}'`, etc.); el `admin` no necesita nada de esto porque ve
todo.

## I5. Que NO se construye en esta vuelta (nota honesta)

Igual que la nota honesta del Balance General, aqui esta lo que queda pendiente
a proposito, para no dejar cosas a medias:

- **No hay tabla de clientes.** `movimientos_inventario.customer_id` existe como
  columna ANTICIPADA (sin FK), lista para el dia que exista un software de
  Clientes mas completo. No se crea una tabla clientes a medias.
- **No hay superficie publica (`catalogo_publico`).** La columna
  `productos.publicado` queda lista, pero la tienda / catalogo visible al
  cliente no se construye esta vuelta. Todo el modulo es tras login
  (`authenticated`); no se concede nada a `anon`.
- **No hay Edge Function `registrar_venta`.** El orquestador de ventas
  (descontar stock + costear la venta en un paso) es trabajo futuro. Hoy la
  salida se registra a mano con `inv_registrar_movimiento`.
- **La Proyeccion de la demanda NO cruza proyeccion <-> stock.** Muestra el
  numero puro (promedio movil / suavizacion exponencial / regresion lineal
  sobre el libro real); no dice "te faltarian X, considera reponer". La
  reposicion la decide el dueno manualmente. Si no hay datos, muestra un aviso
  sobrio "aun no hay informacion" (como el Balance General), sin bloquear ni
  limitar el software.
- **Contabilidad sigue MANUAL y desconectada de Inventario.** No hay enganche
  automatico Inventario -> Finanzas: cada area alimenta a Marketing por su
  cuenta (cita a ciegas). Registrar una salida NO crea ningun asiento contable.

---

# Modulo Ventas · Pedidos, clientes y portafolio

Esta seccion aplica el cimiento de datos del TERCER software interno: el **Area
de Ventas**, con dos sub-areas (Seguimiento de pedidos y Portafolio de
clientes). Mismo estandar y misma filosofia que Finanzas e Inventario: nada se
borra en silencio, cantidades enteras (unidades), montos en `bigint` (pesos
enteros, nunca float), y el candado real vive en los DATOS (RLS + RPC security
definer), no en el HTML.

Idea central: **el pedido es el HECHO que se escribe; el resto se DERIVA.** El
pedido baja el stock del MISMO libro de Inventario (una `salida` con
`referencia = pedido_id` y `customer_id` estampado), y las metricas del
Portafolio (ultima compra, numero de pedidos, total gastado) NO se guardan: se
derivan de `pedidos` con la vista `portafolio_metricas`. Anular un pedido
registra una ENTRADA compensatoria en el libro y la metrica se recalcula sola.

**El enchufe apagado se enciende aqui (decision del dueno):**
`movimientos_inventario.customer_id` existia como columna ANTICIPADA sin FK
desde Inventario. El archivo 4 de V1 (`20250401000300_ventas_rls.sql`) le
enciende la FK hacia `clientes(id)`, por eso **la tabla `clientes` debe existir
antes** (archivo 1). Ventas alimenta a Marketing por el DATO (el Ranking usa el
precio real de `pedido_items`), no por codigo.

**Requisito previo:** la migracion de perfiles y roles
(`20250101000000_crear_perfiles_y_roles.sql`) y el modulo de **Inventario**
(seccion I1 completa, en especial `productos` y `movimientos_inventario`) YA
deben estar aplicados: `pedido_items.product_id` es FK a `productos`, el pedido
baja stock del libro de Inventario y `tiene_acceso_ventas()` envuelve la misma
funcion central `tiene_modulo(text)`.

## V1. Orden EXACTO de ejecucion en el SQL Editor

Abre el **SQL Editor** (igual que en el paso 1 de arriba) y ejecuta, EN ESTE
ORDEN, el contenido completo de cada archivo (cada uno con su propio **Run**):

1. `supabase/migrations/20250401000000_ventas_clientes.sql`
   Crea la tabla `clientes` (identidad del cliente: nombre, correo/telefono y
   sus formas normalizadas `correo_norm`/`telefono_norm`, direccion, ciudad,
   etc.), con indices UNIQUE PARCIALES sobre `correo_norm`/`telefono_norm`
   (piso duro anti-duplicados). Su `id` es el `customer_id` del libro. Debe ir
   PRIMERO porque el archivo 4 enciende la FK que apunta a esta tabla.
2. `supabase/migrations/20250401000100_ventas_pedidos.sql`
   Crea `pedidos` (la orden: `customer_id`, `fecha_orden`, `estado`
   recibido/preparando/en_camino/entregado/anulado, `canal` manual/web,
   `total` bigint, `anulado`) y `pedido_items` (las lineas: `pedido_id`,
   `product_id`, `cantidad`, `precio_unitario` = PRECIO REAL de la venta,
   `subtotal`). Ese `precio_unitario` es el que enciende el ingreso real del
   Ranking de Marketing.
3. `supabase/migrations/20250401000200_ventas_portafolio_vista.sql`
   Crea la vista `portafolio_metricas` (una fila por cliente, DERIVADA de sus
   pedidos NO anulados: `ultima_compra`, `num_pedidos`, `total_gastado`).
   SECURITY INVOKER: hereda la RLS de `clientes`/`pedidos`. Corre DESPUES de los
   archivos 1 y 2.
4. `supabase/migrations/20250401000300_ventas_rls.sql`
   Crea la funcion de acceso del area `tiene_acceso_ventas()` (envuelve
   `tiene_modulo` y acepta las claves equivalentes `ventas`/`pedidos`/
   `clientes`/`portafolio`) y activa RLS de SOLO SELECT en `clientes`,
   `pedidos`, `pedido_items` (y una policy SELECT extra en `productos` para el
   usuario de ventas). **Ademas ENCIENDE LA FK del enchufe:**
   `movimientos_inventario.customer_id -> clientes(id)`; por eso `clientes`
   (archivo 1) tiene que existir antes de este paso. Sin policies de
   INSERT/UPDATE/DELETE (toda escritura va por RPC).
5. `supabase/migrations/20250401000400_ventas_funciones.sql`
   Crea las RPC security definer (la UNICA via de escritura; cada una valida
   `tiene_acceso_ventas()` al entrar): `buscar_candidatos_cliente` (solo
   lectura, algoritmo de coincidencia), `crear_pedido` (nucleo unico: resuelve/
   crea cliente, inserta pedido + items con precio real, baja stock con una
   `salida` directa en el libro), `anular_pedido` (anulacion logica + entrada
   compensatoria) y `avanzar_estado_pedido` (mueve el estado operativo).
   **Corre DESPUES del archivo 4**, que es donde se define `tiene_acceso_ventas()`.
6. `supabase/migrations/20250401000500_ventas_grants.sql`
   Otorga al rol `authenticated` el GRANT base de tabla (SELECT) que faltaba
   por tener "auto-expose new tables" en OFF. POR QUE: igual que en Finanzas
   (archivo 8 de F1) e Inventario (archivo 6 de I1), sin este GRANT de capa 1
   Postgres responde `permission denied` (403) ANTES de evaluar RLS. Destraba
   solo esa capa con el minimo privilegio: SELECT en `clientes`, `pedidos`,
   `pedido_items` y la vista `portafolio_metricas`. NO abre INSERT/UPDATE/DELETE
   (toda escritura va por RPC) ni concede nada a `anon` (los datos personales de
   terceros nunca se exponen al publico).

Los archivos son idempotentes (`create ... if not exists`, `create or replace`,
`drop policy if exists`, y la FK se anade solo si no existe): si algo falla a
mitad, puedes re-ejecutar sin duplicar nada.

## V2. Como verificar que quedo bien

Ejecuta estas consultas en el SQL Editor (estando logueado como admin). Primero
necesitas el `id` uuid de un producto con stock; tomalo del inventario:

```sql
select product_id, sku, existencias from stock_actual order by sku;
-- Copia el product_id de un producto para usarlo abajo como <uuid-del-producto>.
```

1. **Acceso al area** (estando logueado como admin devuelve `true`):

   ```sql
   select tiene_acceso_ventas();   -- acepta ventas/pedidos/clientes/portafolio
   ```

2. **Registrar un pedido manual** (crea el cliente si es nuevo y baja stock en un
   solo paso; NO escribes tu el customer_id ni el pedido_id, los devuelve la
   RPC). La firma de items es un array jsonb de
   `{product_id, cantidad, precio_unitario}` con el PRECIO REAL cobrado:

   ```sql
   select crear_pedido(
     p_nombre        => 'Cliente de prueba Ventas',
     p_correo        => 'prueba.ventas@example.com',
     p_telefono      => '3001234567',
     p_ciudad        => 'Cali',
     p_canal         => 'manual',
     p_items         => '[{"product_id":"<uuid-del-producto>","cantidad":2,"precio_unitario":25000}]'::jsonb
   );
   -- Esperado: jsonb {"pedido_id":"<uuid>","customer_id":"<uuid>","total":50000}.
   -- Copia el pedido_id y el customer_id para los pasos siguientes.
   ```

   > Si el cliente ya existia (mismo `correo_norm` o `telefono_norm`), la RPC NO
   > lo duplica: resuelve al existente y devuelve su `customer_id` (§4.5). Para
   > un cliente nuevo el `p_nombre` es obligatorio.

3. **El stock BAJA y la salida queda estampada** con `referencia = <pedido_id>` y
   `customer_id` (el enchufe encendido):

   ```sql
   select product_id, tipo, cantidad, motivo, referencia, customer_id, fecha
   from movimientos_inventario
   where referencia = '<pedido_id>'
   order by fecha;
   -- Esperado: una fila tipo='salida', motivo='Venta', cantidad=2,
   -- referencia=<pedido_id>, customer_id=<customer_id del paso 2>.

   select existencias from stock_actual where product_id = '<uuid-del-producto>';
   -- Esperado: bajo 2 unidades respecto de lo que tenia antes.
   ```

4. **Ver las metricas derivadas del Portafolio** (sin anular todavia):

   ```sql
   select * from portafolio_metricas where customer_id = '<customer_id>';
   -- Esperado: num_pedidos=1, total_gastado=50000, ultima_compra=hoy.
   ```

5. **Anular el pedido y confirmar la ENTRADA compensatoria** (nada se borra: el
   libro conserva la salida original Y la entrada que la revierte):

   ```sql
   select anular_pedido('<pedido_id>', 'prueba de anulacion');
   -- Esperado: jsonb {"pedido_id":"<uuid>","revertidos":1}.

   select tipo, cantidad, motivo, referencia, customer_id
   from movimientos_inventario
   where referencia = '<pedido_id>'
   order by fecha, tipo;
   -- Esperado: DOS filas con el mismo referencia: la 'salida' original (Venta) y
   -- una 'entrada' nueva (motivo='Anulacion de venta') por la misma cantidad.

   select existencias from stock_actual where product_id = '<uuid-del-producto>';
   -- Esperado: vuelve al valor que tenia ANTES del pedido (la salida quedo
   -- compensada por la entrada).
   ```

6. **La metrica se recalcula sola** (la vista excluye los pedidos anulados; no
   hay contador que actualizar a mano):

   ```sql
   select * from portafolio_metricas where customer_id = '<customer_id>';
   -- Esperado: num_pedidos=0, total_gastado=0, ultima_compra NULL (el unico
   -- pedido quedo anulado). El cliente sigue existiendo en el portafolio.
   ```

   (Opcional) Para dejar limpio tras las pruebas NO borres nada: el pedido ya
   quedo anulado y el stock compensado. El modelo, igual que Finanzas e
   Inventario, no permite borrado fisico; el cliente de prueba puede quedarse o
   marcarse `activo=false` mas adelante si estorba.

## V3. Como DAR ACCESO al Area de Ventas a un usuario

El acceso al area se controla con la lista `modulos` de la tabla `perfiles`
(el `admin` ya tiene todo), con la misma convencion que Finanzas e Inventario.
`tiene_acceso_ventas()` acepta cualquiera de las claves equivalentes del area:
la del area (`ventas`) o la de una sub-area (`pedidos`, `clientes`,
`portafolio`); cualquiera de ellas abre la carpeta Ventas en el panel Y habilita
operar sus datos (quien ve la carpeta, puede operar sus datos).

1. Crea su usuario en **Authentication > Users** (o pidele que se registre).
2. Copia su UID y ejecuta en el SQL Editor:

   ```sql
   insert into perfiles (id, rol, modulos)
   values ('<UID-del-usuario-de-ventas>', 'ventas', '{ventas}')
     on conflict (id) do update
       set rol = excluded.rol, modulos = excluded.modulos;
   ```

   Ese usuario solo vera el Area de Ventas. Puedes usar indistintamente
   `'{ventas}'`, `'{pedidos}'`, `'{clientes}'` o `'{portafolio}'`: las cuatro
   son equivalentes para Ventas (recomendado: la clave del area, `'{ventas}'`,
   por ser la mas legible). Si quisieras darle Ventas ADEMAS de otra area, combina
   como en Finanzas: `'{ventas,marketing}'`, etc.

   > El analista de Marketing NO necesita el Area de Ventas para su trabajo
   > habitual: el Ranking de productos usa el precio real de `pedido_items`, pero
   > si el analista no tiene acceso a Ventas la consulta cae limpio al precio de
   > venta actual (ingreso estimado) sin romperse. Dale `'{ventas}'` ademas de
   > `'{marketing}'` solo si quieres que vea el ingreso REAL en el Ranking.

## V4. Que NO se construye en esta vuelta (nota honesta)

Igual que las notas honestas de Balance General e Inventario, aqui esta lo que
queda pendiente a proposito, para no dejar cosas a medias:

- **La pantalla de DEVOLUCIONES no se construye.** El MOTOR por debajo si queda
  listo: `anular_pedido` revierte el stock con una entrada compensatoria y deja
  el rastro completo. Pero NO hay una pantalla dedicada de devoluciones
  (parciales por item, motivos catalogados, etc.); hoy la reversion es la
  anulacion completa del pedido. La pantalla de devoluciones queda como trabajo
  futuro sobre ese motor.
- **Contabilidad sigue MANUAL y desconectada de Ventas (cita a ciegas).** Igual
  que Inventario, registrar o anular un pedido NO crea ningun asiento contable.
  No hay enganche automatico Ventas -> Finanzas; Finanzas se sigue llevando a
  mano en el Libro Diario. Ventas alimenta a Marketing por el DATO (el Ranking),
  no a Finanzas por codigo.
- **El canal `web` queda como enchufe, sin checkout.** `pedidos.canal` acepta
  `web`, listo para que un checkout futuro (Wompi) invoque el MISMO nucleo
  `crear_pedido` con `canal=web`. Hoy todos los pedidos entran `manual`; la
  superficie publica de compra no se construye esta vuelta.

---

# CAMPANAS (Area Marketing) · Producto vestido para la tienda publica

Esta seccion aplica el cimiento de datos de CAMPANAS: el software con el que se
"viste" un producto (dos secciones: BANNER HOOK y PRODUCTO) y se PUBLICA en la
tienda publica (magandhi.com). CAMPANAS es una ISLA: NO se cruza con la tabla
`productos` de Inventario, NO lee stock real y NO usa su product_id. Tiene su
propia identidad y deja un enchufe apagado (`product_id_ref` uuid NULL SIN FK)
para conectar Inventario despues sin cirugia.

La tienda publica lee EN VIVO una VISTA segura, `catalogo_publico`, que solo
expone productos publicados y solo campos publicos. JAMAS expone costo,
proveedor, stock interno, `product_id_ref`, `creado_por` ni las etiquetas de
segmentacion (internas).

**Requisito previo:** deben estar aplicadas la migracion de perfiles y roles
(`20250101000000_crear_perfiles_y_roles.sql`, de alli sale `tiene_modulo`) y el
puente de lectura de Marketing (`20250301000600_inventario_marketing_lectura.sql`,
de alli sale `tiene_acceso_marketing()`, que usan la RLS y las RPC de Campanas).

## C1. Orden EXACTO de ejecucion en el SQL Editor

Abre el **SQL Editor** y ejecuta, EN ESTE ORDEN, el contenido completo de cada
archivo (cada uno con su propio **Run**):

1. `supabase/migrations/20250501000000_campanas_producto.sql`
   Crea `campana_producto` con las DOS secciones (banner hook + producto), los
   interruptores (sello_elegido, estrella, stock_disponible, aviso_urgencia_activo,
   aviso_urgencia_cantidad, publicado) y el enchufe apagado `product_id_ref`
   (uuid NULL SIN FK). Montos en bigint. Indices por publicado/categoria/orden.
2. `supabase/migrations/20250501000100_campanas_categorias.sql`
   Crea y siembra `campana_categoria` (catalogo controlado) con la paleta EXACTA
   de 7 categorias (color_fuerte / color_claro / color_sombra). El color del
   producto es AUTOMATICO segun su categoria. Enciende la FK
   `campana_producto.categoria_codigo -> campana_categoria(codigo)` con guard
   idempotente sobre `pg_constraint`.
3. `supabase/migrations/20250501000200_campanas_etiquetas.sql`
   Crea `campana_etiqueta` (catalogo controlado de segmentacion INTERNA) + la
   tabla puente `campana_producto_etiqueta`, y siembra un set inicial de
   etiquetas. Estas etiquetas NUNCA salen a la tienda.
4. `supabase/migrations/20250501000300_campanas_vista_publica.sql`
   Crea la vista SEGURA `catalogo_publico` (WHERE publicado=true AND activo=true,
   solo campos publicos + colores por join a categoria). No incluye la tabla de
   etiquetas ni campos internos.
5. `supabase/migrations/20250501000400_campanas_rls.sql`
   Activa RLS en las 4 tablas base con `SELECT ... using (tiene_acceso_marketing())`.
   Sin INSERT/UPDATE/DELETE directo. CERO policy para anon sobre las tablas base.
6. `supabase/migrations/20250501000500_campanas_funciones.sql`
   Crea las RPC security definer `cm_crear_campana`, `cm_editar_campana` y
   `cm_publicar_campana` (unica via de escritura). Validan `tiene_acceso_marketing()`,
   precio_venta >= 0 (bigint) y, si el aviso de urgencia esta activo, exigen
   cantidad > 0. Nada se borra (despublicar).
7. `supabase/migrations/20250501000600_campanas_grants.sql`
   Capa 1 de GRANT: `select` de las 4 tablas base a `authenticated` (el panel las
   lee) y `select` de la VISTA `catalogo_publico` a `anon, authenticated` (la
   tienda publica la lee sin login). NO grant a anon sobre las tablas base.
8. `supabase/migrations/20250501000700_campanas_seed.sql`
   Siembra los 5 productos actuales del home (Grisi real + 4 de ejemplo) con ids
   fijos e idempotencia (`on conflict (id) do update`), y asigna etiquetas de
   segmentacion por producto. Todos con `publicado=true`.

Los archivos son idempotentes (`create ... if not exists`, `create or replace`,
`drop policy if exists`, `on conflict do update`, guard sobre `pg_constraint`):
si algo falla a mitad, puedes re-ejecutar sin duplicar nada.

## C2. Imagenes de Campanas (Storage) · opcional

Si en el panel (FEAT-003) decides subir imagenes de banner/galeria desde el
navegador, crea en **Storage** un bucket llamado `campanas`:

1. En el menu lateral abre **Storage** y pulsa **New bucket**.
2. Nombre: `campanas`. Marca **Public bucket** (lectura publica: la tienda debe
   poder mostrar las imagenes sin login).
3. Para la ESCRITURA (subir/borrar), agrega una policy que exija acceso de
   Marketing, por ejemplo (Storage usa la tabla `storage.objects`):

   ```sql
   -- Lectura publica de las imagenes de campanas
   create policy "campanas_lectura_publica" on storage.objects
     for select to anon, authenticated
     using (bucket_id = 'campanas');

   -- Escritura solo para quien tiene acceso al Area de Marketing
   create policy "campanas_escritura_marketing" on storage.objects
     for insert to authenticated
     with check (bucket_id = 'campanas' and tiene_acceso_marketing());
   ```

   Mientras no se suban imagenes desde el panel, los campos `imagen_banner_path`
   e `imagenes` pueden apuntar a rutas del repo de la tienda (como el Grisi).

## C3. Como verificar que quedo bien

Ejecuta estas consultas en el SQL Editor:

1. **Productos sembrados** (debe devolver 5):

   ```sql
   select count(*) from campana_producto;
   ```

2. **La vista publica solo trae lo publicado y publico** (5 filas, con nombre,
   precio y colores; SIN costo/proveedor/product_id_ref/etiquetas/creado_por):

   ```sql
   select id, nombre, categoria_codigo, color_fuerte, precio_venta,
          sello_elegido, estrella, aviso_urgencia_activo, aviso_urgencia_cantidad
     from catalogo_publico
    order by orden;
   ```

3. **anon NO puede leer las tablas base, pero SI la vista.** En **SQL Editor**
   puedes simular el rol anon dentro de una transaccion:

   ```sql
   begin;
   set local role anon;
   -- Esto DEBE fallar (permission denied): las tablas base no tienen grant a anon
   select * from campana_producto limit 1;
   rollback;

   begin;
   set local role anon;
   -- Esto DEBE funcionar (la unica superficie publica)
   select nombre, precio_venta from catalogo_publico limit 1;
   rollback;
   ```

   (Tambien puedes probar en vivo desde la tienda con la publishable key: leer
   `catalogo_publico` responde; leer `campana_producto` da error de permiso.)

4. **La vista NO expone campos internos** (esta consulta DEBE fallar con
   "column ... does not exist", porque no estan en la vista):

   ```sql
   select product_id_ref from catalogo_publico limit 1;   -- error esperado
   select creado_por     from catalogo_publico limit 1;   -- error esperado
   ```

5. **Escribir sin acceso de marketing es RECHAZADO** (con un rol/usuario sin la
   clave de Marketing, esto DEBE dar error "Acceso denegado: se requiere el
   modulo marketing."):

   ```sql
   select cm_crear_campana('Prueba sin acceso');
   ```

6. **El aviso de urgencia exige cantidad > 0** (esto DEBE fallar por la
   validacion del aviso manual y honesto):

   ```sql
   -- aviso activo pero sin cantidad -> error esperado
   select cm_crear_campana(
     'Prueba aviso', 'cabello', null, null, null, null, 1000, null, null, null,
     '[]'::jsonb, '[]'::jsonb, false, false, 3, true, null, '{}'
   );
   ```

7. **Las etiquetas de segmentacion son INTERNAS** (existen para el panel, pero
   la tienda no las ve porque no estan en la vista):

   ```sql
   select count(*) from campana_producto_etiqueta;   -- > 0 (asignadas en el seed)
   ```

Como las RPC usan `create or replace` y las tablas/vista son idempotentes, si
mas adelante ajustas algo basta con **volver a ejecutar solo el archivo que
cambio**, sin tocar los demas.
