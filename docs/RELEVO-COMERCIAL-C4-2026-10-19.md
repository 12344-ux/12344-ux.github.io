# Relevo de sesión · Comercial C4 · cuenta y ciclo del carrito · 19 de octubre de 2026

Este es el punto general vigente para continuar el frente comercial. Leer junto
con `CONTEXTO-MAGANDHI.md`, `docs/PLANO-FASE-COMERCIAL.md` y
`supabase/INSTRUCCIONES.md`. Los relevos de Comercial C1–C3 quedan como memoria
histórica. No reconstruir esos tramos ni confundir Comercial C4 con Cuentas C4.

## 1. Estado exacto

**Comercial C4 está construido, pero NO está aplicado, NO está desplegado y NO
está medido en producción.**

- Backend/back-office: rama `feat/comercial-c4-ciclo-carrito`, PR #283 abierto.
- Tienda `12344-ux/magandhi`: rama `feat/comercial-c4-ciclo-carrito`, PR #108
  abierto. La tienda C4 está implementada; su despliegue y medición están
  pendientes, no su construcción.
- Migración candidata:
  `20261105000000_comercial_c4_cuenta_ciclo_carrito.sql`.
- Las Edge Functions `crear-intencion-pago` y `estado-pago` cambiaron y deben
  redesplegarse junto con este corte.
- El back-office de Ventas cambió para atender la revisión C4 y también debe
  publicarse.
- Producción sigue llegando únicamente a
  `20261104000000_comercial_c3_checkout_multiproducto.sql` (Comercial C3), con
  `carrito_habilitado=false`.
- No se aplicó `20261105000000`; no se redesplegaron las Edge C4; no se
  publicaron el back-office ni la tienda C4; no existe evidencia productiva de
  sus objetos, permisos, invariantes ni recorridos.
- **Evidencia nueva local/CI:** el workflow [Banco de pruebas · run
  39319540269](https://github.com/12344-ux/12344-ux.github.io/actions/runs/39319540269)
  terminó `SUCCESS` sobre el commit `1afc029` de
  `feat/comercial-c4-ciclo-carrito`, usando PostgreSQL 15 y Deno. Pasaron las
  migraciones y el banco CI, además de los checks de Node, el diff y la revisión.
  Después de ese commit solo hubo ajustes documentales/de matriz; el estado
  final del código permanece en la misma rama.

No inferir aplicación, despliegue o prueba por la presencia del código, por el
estado abierto de los PR ni por una interfaz construida.

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
- La respuesta v2 devuelve el estado saneado y el descriptor de checkout
  necesario para recargar el carrito, sin PII, monto, ids privados, pedido,
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

La validación local/CI de este corte está cumplida. El workflow [Banco de
pruebas · run
39319540269](https://github.com/12344-ux/12344-ux.github.io/actions/runs/39319540269)
terminó `SUCCESS` sobre el commit `1afc029` de
`feat/comercial-c4-ciclo-carrito`, usando PostgreSQL 15 y Deno. Pasaron:

- las migraciones y el banco CI;
- los checks de Node;
- el diff;
- la revisión.

Después de `1afc029` solo hubo ajustes documentales/de matriz; el estado final
del código permanece en la misma rama.

**Este resultado no constituye aplicación ni evidencia productiva.** La
migración `20261105000000` NO está aplicada en producción; no hay preflight ni
postflight productivos de C4; las Edge Functions no están redesplegadas; la
tienda y el back-office no están publicados; no hubo dinero ni medición
productiva.

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

El banco local/CI con PostgreSQL 15 y Deno ya es un gate cumplido por el run
`39319540269`. Todavía deben ejecutarse el preflight, la migración y el
postflight productivos, además de las pruebas controladas de producción.
Respetar este orden; no publicar las superficies antes de que su dependencia
anterior esté aplicada:

1. **Preflight de solo lectura.** Confirmar que producción termina en
   `20261104000000`, la historia C3 es coherente y
   `carrito_habilitado=false`.
2. **Migración.** Aplicar una sola vez
   `20261105000000_comercial_c4_cuenta_ciclo_carrito.sql` con el flag OFF y
   ejecutar postflight de objetos, firmas, constraints, índices, grants, RLS,
   historia v2 e invariantes. El flag debe seguir OFF.
3. **Ambas Edge Functions.** Redesplegar `crear-intencion-pago` y `estado-pago`;
   comprobar autenticación, expiración/firma y retorno v2 sin filtrar datos.
4. **Back-office y tienda.** Publicar Ventas C4 y la tienda ya implementada en
   PR #108, conservando compra inmediata e invitada y sin anunciar apertura.
5. **Pruebas controladas de producción.** Con el gate local/CI ya aprobado,
   probar sin dinero sobre flag OFF/ON propiedad, sucesión, expiración, bloqueo,
   retry, retorno v2, PENDING y revisión. Volver a OFF ante cualquier duda.
6. **Dinero solo con autorización expresa.** Medir aprobación, rechazo,
   aprobación tardía, reembolso/liberación, pedido único, `customer_id`,
   snapshots, consumo/preservación de líneas, versión, inventario/proveedor,
   asiento, correo e idempotencia.
7. **Actualizar después de medir.** Solo con resultados observados modificar el
   relevo, plano, runbook y contexto, y decidir el valor final del flag.

## 5. Reglas para continuar

- No reaplicar `20261104000000`; `20261105000000` se aplicará una sola vez cuando
  el preflight autorice el despliegue.
- Mantener `carrito_habilitado=false` durante aplicación y publicación.
- No confiar en identidad, precio, expiración ni `customer_id` enviados por el
  navegador.
- No liberar una revisión sin la acción explícita `reembolsado_liberar` y la
  evidencia de reembolso exigida por la operación.
- No borrar ni editar la intención estructural C3 ni fabricar eventos.
- No declarar merge, despliegue, prueba o medición que no exista. PR #283 y PR
  #108 siguen abiertos.
- Wompi permanece en `prod`; cualquier prueba con dinero requiere autorización
  expresa.

## 6. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI después de construir Comercial C4. Backend/back-office está
> en `feat/comercial-c4-ciclo-carrito`, PR #283 abierto; la tienda está
> implementada en la misma rama de `12344-ux/magandhi`, PR #108 abierto. Lee
> `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`, `CONTEXTO-MAGANDHI.md`,
> `docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. El workflow
> «Banco de pruebas» run `39319540269` terminó `SUCCESS` sobre `1afc029` en
> `feat/comercial-c4-ciclo-carrito`, usando PostgreSQL 15 y Deno; pasaron las
> migraciones, el banco CI, los checks de Node, el diff y la revisión. Después
> solo hubo ajustes documentales/de matriz y el estado final del código permanece
> en esa rama. Este gate local/CI no cambia que C4 no está aplicado, desplegado
> ni medido; producción sigue en `20261104000000`/C3 con
> `carrito_habilitado=false`. Continúa en orden: preflight productivo, migración,
> postflight productivo, `crear-intencion-pago` y `estado-pago`,
> back-office/tienda y pruebas controladas de producción. Las Edge no están
> desplegadas, la tienda y el back-office no están publicados, y no hubo dinero
> ni medición. Dinero solo con autorización y actualización documental
> únicamente después de medir.
