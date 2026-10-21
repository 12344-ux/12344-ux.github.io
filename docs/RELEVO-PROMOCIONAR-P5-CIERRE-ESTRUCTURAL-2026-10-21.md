# Relevo de sesión · Promocionar P5 · cierre estructural · 21 de octubre de 2026

**Estado inequívoco:** P5 está fusionado, publicado e instalado en producción. Queda **cerrado estructural y productivamente**, no monetaria ni end-to-end: las lecturas de Resultados, Métricas y Ventas están disponibles, pero no se ejecutó una compra, un pago `APPROVED`, un pedido atribuido ni un ingreso para este cierre. P3 permanece cerrado FINAL; P4 permanece activo y cerrado estructuralmente. P5 no cambió la tienda ni el contrato de captura P4.

Leer después `PLANO-PROMOCIONAR-P5.md`, `PLANO-PROMOCIONAR-P4.md` y `../supabase/operacion/PROMOCIONAR-P5-DESPLIEGUE.md`. No existe un P6 definido.

## 1. Implementación y publicación acreditadas

- Implementación P5: PR #308, merge `3205e1b0cfcd5fc98126ccf2f37aa3cb2bf914f1` el 21-oct-2026.
- CI de rama run `39643360479`: `success`; reportó 88 migraciones, la matriz terminó 230/0 y la suite final informó `Todo pasa.`
- Pages producción run `39645791554`: `success` sobre el merge.
- El dueño confirmó que `20261110000000_promocionar_p5_lectura_comercial.sql` fue ejecutada una sola vez.
- El dueño recorrió la prueba integral final de Resultados, Métricas y Ventas y confirmó: «Todo en orden».

Esta evidencia acredita el cierre estructural/productivo de P5. No acredita por extensión hechos monetarios ni los casos productivos que se enumeran como no recorridos en este relevo.

## 2. Diagnóstico final exacto

```text
instalado=true
P3: enlaces=1; detalle_desde=null; detalle_hasta=null; clics_detalle_filas=0; compactado=0
P4: intenciones_atribuidas=1; convertidas_approved=0; pedidos_con_fk=0; ventas_exactas_autoritativas=0; divergencias_fk=0; incidencias_pendientes=0
analítica consentida: activa=false; primer_evento=2026-10-08T18:34:59.188+00:00; ultimo_evento=2026-10-08T18:34:59.188+00:00
intención sintética identificable=false
```

Lectura directa:

- `instalado=true` confirma la presencia nominal de las lecturas P5 medidas por el diagnóstico.
- P3 tiene un enlace, ninguna fila diaria fechada y ningún clic compactado sin fecha. Por tanto, este diagnóstico no justifica avisar sobre histórico P3 sin fecha.
- La captura nueva de analítica voluntaria está desactivada. P5 conserva cualquier evento histórico ya consentido del periodo, pero no completa los intervalos sin captura; por eso las sesiones y los checkouts pueden ser parciales. Los pedidos y los ingresos se leen por una vía transaccional independiente. El instante conservado como primer y último evento confirma que existe histórico aunque la captura esté inactiva en este corte.
- P4 conserva una intención atribuida, pero registra cero conversiones `APPROVED`, cero pedidos con FK y cero ventas exactas autoritativas. También registra cero divergencias y cero incidencias pendientes.
- La intención sintética no es identificable de forma fiable. No se elimina ni se reclasifica mediante una heurística, y nunca se presenta como pedido o ingreso.

## 3. Qué quedó cerrado

- La implementación P5 quedó fusionada y su Pages de producción fue publicada sobre ese merge.
- La migración read-only P5 quedó instalada una sola vez, sin modificar ni reaplicar migraciones anteriores.
- El recorrido integral final cubrió las tres superficies previstas: Resultados, Métricas y Ventas.
- P5 puede leer por separado clics aproximados, actividad consentida disponible y hechos transaccionales autoritativos sin convertir una intención en venta.
- El aviso parcial de Métricas debe explicar la razón declarada por `cobertura.razones`: analítica voluntaria inactiva, histórico P3 compactado sin fecha solo cuando esa razón exista, o ausencia de eventos consentidos durante analítica activa como caso separado.

Esto cierra la entrega de lectura P5 en estructura y producción. No cierra el recorrido monetario común de Comercial C5, Promocionar P4 y Promocionar P5.

## 4. Límite honesto

No quedaron confirmados en este cierre preflight ni postflight productivos separados. Tampoco quedaron acreditados:

- categorías de atribución recorridas con datos reales;
- una compra;
- un pago `APPROVED`;
- un pedido atribuido;
- un ingreso.

Tampoco se atribuyen recorridos individuales de todos los estados, periodos o casos históricos del runbook. La prueba integral final y el diagnóstico exacto son la evidencia productiva disponible; no deben ampliarse por inferencia.

## 5. Continuidad

No hay P6 definido. La próxima decisión puede ser una de estas dos:

1. autorizar una compra real para cerrar transaccionalmente el pendiente común C5/P4/P5, midiendo sin atajos pago `APPROVED`, pedido atribuido e ingreso; o
2. retomar otro pendiente vigente del proyecto.

Cualquier paso que cobre dinero requiere autorización expresa del dueño. Mientras no exista esa autorización, no afirmar cierre monetario/end-to-end y no tratar la intención atribuida existente como venta.

No reaplicar `20261110000000`. Toda corrección SQL futura debe ser una migración forward. El relevo P4 queda como historia del contrato de captura y del cierre sin dinero; este archivo es el relevo vigente de Promocionar.
## 6. Punto exacto para la próxima sesión · activar EM7 después de publicar políticas

P5 queda cerrado; no necesita otra migración ni reconstrucción. La única fuente promocional actualmente apagada es la **captura de interacción consentida EM7**. Esto no apaga los clics agregados P3, la atribución transaccional P4, pagos, pedidos ni las lecturas P5.

EM7 permanece apagada porque las políticas públicas siguen en borrador y el servidor exige una política registrada antes de activarla. Cuando el dueño confirme que publicó las políticas definitivas, continuar en este orden:

1. registrar la versión exacta publicada desde **Email marketing → Resumen**;
2. entrar como administrador a **Métricas → En vivo** o **Métricas → Tienda** y pulsar **Encender analítica**;
3. confirmar que la tienda muestra el aviso de cookies/analítica;
4. hacer una sola prueba integral: rechazo sin captura, aceptación con captura y aparición posterior de visita, producto visto y checkout en Métricas/P5;
5. registrar el resultado en las fuentes de estado.

La captura solo comienza para actividad futura de personas que acepten. No reconstruye retroactivamente sesiones ni interacciones del periodo en que estuvo apagada. Si el servidor rechaza la activación, comunicar el error exacto y no intentar saltarse el gate de política.