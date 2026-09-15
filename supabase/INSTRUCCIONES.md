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
todas las tablas de este modulo se protegen con la funcion
`tiene_modulo('inventario')` (y el puente de Marketing usa
`tiene_modulo('marketing')`) que se creo alli.

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
   Activa RLS en TODAS las tablas del modulo con `tiene_modulo('inventario')`.
   Solo policies de SELECT; sin INSERT/UPDATE/DELETE (toda escritura va por
   RPC) y sin DELETE en ninguna tabla.
5. `supabase/migrations/20250301000400_inventario_funciones.sql`
   Crea las RPC security definer `inv_crear_producto`,
   `inv_registrar_movimiento` e `inv_editar_producto` (la UNICA via de
   escritura; cada una valida `tiene_modulo('inventario')` al entrar).
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
   Inventario -> Marketing: anade policies SELECT extra en `productos` y
   `movimientos_inventario` que ADEMAS permiten leer cuando
   `tiene_modulo('marketing')`, para que un usuario SOLO de marketing pueda
   alimentar la Proyeccion de la demanda sin darle el modulo de inventario.
   Estrictamente de lectura: no toca INSERT/UPDATE/DELETE.

Los archivos son idempotentes (`create ... if not exists`, `on conflict do
nothing`, `create or replace`, `drop policy if exists`): si algo falla a mitad,
puedes re-ejecutar sin duplicar nada.

## I2. Como verificar que quedo bien

Ejecuta estas consultas en el SQL Editor:

1. **Acceso por modulo** (estando logueado como admin devuelve `true`):

   ```sql
   select tiene_modulo('inventario');
   ```

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
   -- INSERT: subir una imagen nueva solo si tiene_modulo('inventario').
   create policy "productos_img_insert" on storage.objects
     for insert to authenticated
     with check (bucket_id = 'productos' and tiene_modulo('inventario'));

   -- UPDATE: reemplazar una imagen existente solo si tiene_modulo('inventario').
   create policy "productos_img_update" on storage.objects
     for update to authenticated
     using (bucket_id = 'productos' and tiene_modulo('inventario'))
     with check (bucket_id = 'productos' and tiene_modulo('inventario'));
   ```

   La lectura publica ya la habilita el que el bucket sea **Public**; no hace
   falta una policy de SELECT para leer. NO crees policy de DELETE (append-only:
   las imagenes tampoco se borran desde el cliente).

Reglas de oro del Storage (no negociables):

- Las subidas usan **la sesion del usuario autenticado** (llave publishable,
  rol `authenticated`), **NUNCA** `service_role`. La `service_role` no va en el
  repo ni en el navegador jamas (ver paso 5 de seguridad, arriba).
- La base de datos guarda `productos.imagen_path` como una **ruta**, no una URL
  completa. El frontend sube al bucket `productos` en la ruta
  `productos/<product_id>.jpg` y guarda ese mismo `imagen_path`; luego arma la
  URL publica en el cliente con `getPublicUrl(path)`. Asi, si algun dia cambia
  el dominio de Storage, las rutas guardadas no se rompen.
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
`tiene_modulo('marketing')` ya puede hacer SELECT sobre `productos` y
`movimientos_inventario`, asi que `'{marketing}'` basta. **Si NO aplicaste ese
archivo**, dale en cambio `'{marketing,inventarios}'` para que pueda leer el
libro. Puedes combinar modulos como en Finanzas (`'{finanzas,marketing}'`,
etc.); el `admin` no necesita nada de esto porque ve todo.

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
