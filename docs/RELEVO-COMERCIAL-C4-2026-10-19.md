# Relevo de sesión · Comercial C4 · cuenta y ciclo del carrito · 19 de octubre de 2026

Este es el punto general vigente para continuar el frente comercial. Leer junto
con `CONTEXTO-MAGANDHI.md`, `docs/PLANO-FASE-COMERCIAL.md` y
`supabase/INSTRUCCIONES.md`. Los relevos de Comercial C1–C3 quedan como memoria
histórica. No reconstruir esos tramos ni confundir Comercial C4 con Cuentas C4.

## 1. Estado exacto

**Comercial C4 está construido, fusionado y publicado en Pages, pero NO está
aplicado en Supabase ni medido en producción.**

- Backend/back-office: PR #283 fusionado a `main` en `0d35d8f`; Pages run
  `39321890522` terminó `SUCCESS`.
- Tienda `12344-ux/magandhi`: PR #108 fusionado a `main` en `55e0187`; Pages run
  `39321900476` terminó `SUCCESS`.
- Migración pendiente:
  `20261105000000_comercial_c4_cuenta_ciclo_carrito.sql`.
- Las Edge Functions `crear-intencion-pago` y `estado-pago` todavía deben
  redesplegarse y medirse junto con este cierre.
- Producción sigue llegando únicamente a
  `20261104000000_comercial_c3_checkout_multiproducto.sql` (Comercial C3), con
  `carrito_habilitado=false`, según la última evidencia y la confirmación del
  dueño.
- No se aplicó `20261105000000`; no existen preflight/postflight productivos ni
  evidencia de recorridos C4. Ventas/tienda están publicadas, pero contenidas por
  el flag OFF.
- El workflow [Banco de pruebas · run
  39320288166](https://github.com/12344-ux/12344-ux.github.io/actions/runs/39320288166)
  terminó `SUCCESS` sobre `90fbdf2`, con PostgreSQL 15 y Deno. Este gate no
  equivale a producción.
- El paquete autoritativo para continuar es
  `supabase/operacion/COMERCIAL-C4-CIERRE.md`; incluye pre/postflight, estado,
  activación/desactivación y un puente de retorno C3→C4.

No inferir aplicación de base, despliegue de Edge o prueba por el merge, Pages o
la presencia del código.

## 2. Contrato implementado

### 2.1 Expiración autoritativa y sucesión de C3

- Cada intención C4 tiene una expiración autoritativa de **30 minutos** calculada
  en servidor. El mismo instante ISO persistido se incorpora a la firma de
  integridad enviada a Wompi; el navegador no decide ni recalcula ese límite.
- La intención productiva de C3 permanece intacta con `ciclo=0`; no se borra, no
  se edita y no se reetiqueta como C4.
- Al siguiente checkout de ese carrito/versión, el backend registra de forma
  durable la sucesión de la intención C3, avanza una vez la versión y permite a
  `crear-intencion-pago` reintentar técnicamente con la nueva versión.
- Un `APPROVED` posterior a rechazo o expiración, o para una intención con
  sucesora, es una aprobación tardía: no crea automáticamente otro pedido y
  pasa a `requiere_revision`.

### 2.2 Identidad comercial y destinatario

- `crear-intencion-pago` valida el JWT y deriva el UID desde Auth. El navegador
  no puede decidir UID, `customer_id`, correo Auth ni identidad comercial.
- Durante la aprobación, `customer_id` se deriva de la cuenta activa y Auth. Si
  la cuenta todavía no tiene cliente, se crea o vincula dentro de la misma
  transacción del pedido y bajo el advisory lock `cc-correo:` compartido con
  Cuentas C2. Ambigüedad, vínculo ajeno o carrera fallan cerrados.
- Nombre, correo y teléfono de entrega pertenecen al destinatario y no deciden
  `customer_id`. El pedido conserva esos datos y la dirección como snapshot de
  la orden.

### 2.3 Bloqueo y retorno del checkout

- El snapshot del carrito expone `bloqueo_pago` con `null`, `pendiente` o
  `revision`; no expone la referencia ni un booleano `bloqueado_checkout`.
- `pendiente` impide editar mientras la intención siga bloqueante y no haya
  expirado. `revision` mantiene el bloqueo hasta su resolución explícita.
- La expiración libera el carrito y avanza una vez la versión. El bloqueo no es
  una reserva de inventario.
- El retorno v2 pasa por la Edge Function `estado-pago`. Requiere un JWT válido
  del propietario y consulta `pw_estado_checkout_publico`; una referencia v2
  sin JWT, con JWT inválido o de otra cuenta no revela su existencia.
- La respuesta v2 devuelve el estado saneado y el descriptor necesario para
  recargar —ID del carrito propio y versión incluidos—, sin PII, monto, pedido,
  transacción, motivo ni entorno. `pw_estado_publico` conserva solo los caminos
  históricos v0/v1.

### 2.4 Resultado del pago y cantidades

- **APPROVED normal:** valida identidad, cuenta, monto, moneda, entorno y líneas
  congeladas; crea un solo pedido y sustrae del carrito las cantidades
  congeladas. Si el usuario agregó unidades extra o líneas nuevas, las
  preserva; ante drift histórico puede registrar consumo parcial en vez de
  destruir el carrito completo.
- **DECLINED, VOIDED o ERROR:** conserva las líneas, libera el bloqueo y avanza
  exactamente una vez la versión.
- **Expiración:** conserva las líneas, libera el bloqueo y avanza exactamente
  una vez la versión.
- **PENDING o estado no terminal:** no libera, no avanza versión y no convierte
  la intención en rechazada; conserva líneas e intención bloqueante.
- **APPROVED tardío:** pasa a `requiere_revision` sin automatizar un segundo
  pedido.
- **Revisión:** solo se resuelve mediante una acción explícita del back-office de
  Ventas, después de confirmar el reembolso, con
  `pw_resolver_revision_c4(..., 'reembolsado_liberar', nota)`. Esa acción libera
  el carrito y deja evidencia; no hay desbloqueo implícito ni resolución por
  editar datos.
- Compra inmediata e invitada conservan sus caminos históricos independientes.

### 2.5 Superficie SQL

Las RPC nominales son las únicas puertas previstas. Los helpers propios de C4
`co__*`, `pw__*`, `crear_pedido_c3_base` y `crear_pedido_c4` no deben quedar con
`EXECUTE` de API. El helper booleano histórico `pw__contexto_servidor()` no
expone ni muta datos y queda fuera de esa auditoría porque su ownership varía
entre reconstrucciones. La Edge accede por puertas nominales.

## 3. Validación disponible y límite de evidencia

La validación histórica del corte de implementación terminó `SUCCESS` en el
workflow [Banco de pruebas · run
39320288166](https://github.com/12344-ux/12344-ux.github.io/actions/runs/39320288166)
sobre `90fbdf2`/`2483bb2`, con PostgreSQL 15 y Deno. Ese run antecede a los SQL
operativos y al cambio de compatibilidad del puente; el corte actual debe
obtener su propio banco verde antes de operar producción.

**Ese resultado no constituye aplicación ni evidencia productiva.** La
migración `20261105000000` NO está aplicada; no hay pre/postflight productivos;
las Edge no están redesplegadas y no hubo dinero ni medición. Tienda y
back-office sí están publicados en Pages, contenidos por el flag OFF.

Por tanto, todavía no están demostrados en producción:

- objetos, constraints, índices, RLS, grants, firmas e invariantes resultantes;
- expiración/sucesión, PENDING, aprobación tardía y resolución de revisión;
- creación o vínculo real de `customer_id` durante una aprobación;
- pedido, consumo completo/parcial, preservación de extras, inventario o reserva
  de proveedor, asiento, correo e idempotencia productiva;
- integración desplegada de las dos Edge Functions, Ventas y la tienda.

C3 conserva además su límite anterior: la intención v2 productiva quedó sin
pagar y no hubo aprobación end-to-end. No atribuir a C4 evidencia de C3 ni
presentar ninguno de los dos tramos como cierre transaccional.

## 4. Plan de despliegue controlado

El banco local/CI y los merges/Pages están cumplidos. El procedimiento
operativo exacto y los resultados esperados viven en
`supabase/operacion/COMERCIAL-C4-CIERRE.md`. Orden obligatorio:

1. ejecutar `comercial-c4-preflight.sql` sobre C3 con flag OFF;
2. instalar `comercial-c4-puente-estado.sql` y desplegar primero `estado-pago`
   C4; el puente conserva simultáneamente el retorno antiguo y el nuevo;
3. aplicar una sola vez `20261105000000_comercial_c4_cuenta_ciclo_carrito.sql`;
   su `CREATE OR REPLACE` sustituye el puente por la versión autoritativa sin
   cortar la Edge;
4. ejecutar `comercial-c4-postflight.sql`; mantener OFF ante cualquier falla;
5. desplegar `crear-intencion-pago`, verificar ambas Edge y hacer regresión de
   compra inmediata/invitada, sesión, Ventas y tienda con OFF;
6. abrir una ventana temporal solo con `comercial-c4-activar.sql`, medir los
   recorridos sin dinero y cerrarla siempre con
   `comercial-c4-desactivar.sql`; usar `comercial-c4-estado.sql` para evidencia;
7. dinero únicamente con autorización expresa y observación de pedido único,
   identidad, snapshots, consumo/preservación, inventario/proveedor, asiento,
   correo e idempotencia;
8. actualizar documentos y decidir el flag final solo después de medir.

La ejecución manual en SQL Editor puede no registrar la versión en
`supabase_migrations.schema_migrations`; documentar la aplicación y no usar
`supabase db push` hasta reconciliar el historial por el procedimiento aprobado.
No editar a mano las tablas internas de historial durante este cierre.

## 5. Reglas para continuar

- No reaplicar `20261104000000`; `20261105000000` se aplicará una sola vez cuando
  el preflight autorice el despliegue.
- Mantener `carrito_habilitado=false` durante aplicación y publicación.
- No confiar en identidad, precio, expiración ni `customer_id` enviados por el
  navegador.
- No liberar una revisión sin la acción explícita `reembolsado_liberar` y la
  evidencia de reembolso exigida por la operación.
- No borrar ni editar la intención estructural C3 ni fabricar eventos.
- No declarar aplicación de base, despliegue de Edge, prueba o medición que no
  exista. PR #283 y PR #108 sí están fusionados y Pages terminó `SUCCESS`; esos
  hechos no cierran producción.
- Wompi permanece en `prod`; cualquier prueba con dinero requiere autorización
  expresa.

## 6. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI para **terminar y cerrar Comercial C4**. Lee primero
> `supabase/operacion/COMERCIAL-C4-CIERRE.md` y después este relevo,
> `CONTEXTO-MAGANDHI.md`, `docs/PLANO-FASE-COMERCIAL.md` y
> `supabase/INSTRUCCIONES.md`. Backend PR #283 y tienda PR #108 están
> fusionados; Pages terminó `SUCCESS`. El banco PostgreSQL 15/Deno run
> `39320288166` también terminó `SUCCESS`. Eso no acredita Supabase: según la
> última evidencia, producción sigue en `20261104000000`/C3, flag OFF, sin Edge
> C4 ni medición. Continúa exactamente por el paquete operativo: preflight;
> puente C3→C4; desplegar primero `estado-pago`; aplicar una vez `20261105000000`;
> postflight; desplegar `crear-intencion-pago`; regresión OFF; ventana temporal
> con activar/estado/desactivar; dinero solo con autorización. No edites la
> intención C3 ni afirmes cierre end-to-end antes de observarlo.
