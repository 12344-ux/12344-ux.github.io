---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `CONTEXTO-MAGANDHI.md` (realidad operativa y pendientes vigentes).
2. Leer `docs/RELEVO-COMERCIAL-C2-2026-10-16.md`: es el relevo general más
   reciente. **Comercial C2 queda desplegado y probado en estructura, apagado
   hasta C3; no reconstruir C1/C2 ni afirmar un cierre completo.**
3. Leer `docs/PLANO-FASE-COMERCIAL.md`: C1 y C2 están estructuralmente listos y
   el siguiente tramo aprobado es C3, intención y checkout multiproducto.
4. `docs/RELEVO-COMERCIAL-C1-2026-10-16.md` es histórico: conserva la evidencia
   de C1 y su límite de no pago real de dos unidades.
5. Si la tarea toca identidad o apertura de cuentas, leer
   `docs/CUENTAS-CLIENTE.md` y el relevo temático histórico
   `docs/RELEVO-CUENTAS-C2-2026-10-16.md`. Cuentas C2 sigue cerrado
   técnicamente en preapertura; signup está OFF y Google Testing hasta publicar
   políticas.
6. Solo si la tarea vuelve a Dropshipping, leer además
   `docs/dropshipping-envios/RELEVO-2026-10-10.md` y aplicar
   `.kiro/steering/dropshipping-magandhi.md`.

Realidad de arranque al 16-oct-2026:

- La migración más alta aplicada en producción es `20261103000000`.
- Comercial C1 está desplegado y probado en estructura. **No hubo compra real
  qty2:** no atribuirle webhook, pedido, baja2, asiento, correo ni
  repetición/idempotencia. Una prueba real qty2 es opcional y exige autorización
  expresa del dueño.
- **Comercial C2 desplegado y probado en estructura, apagado hasta C3.** Backend
  #278: implementación `f68fd24`, matriz `8d4c64d`, merge
  `a811082cc585ad8d77a98aa346ffbd06ac2ac3f4` y Pages construido. Tienda #104:
  implementación `90dcb6d42eabd26935743b5bae4de9bba9692e39`, merge
  `35a104a1c12b9b9276773bc7d7c082c0733c73a9` y Pages construido.
- Preflight 3/3 `true`, migración aplicada y postflight 10/10 `true`. El dueño
  confirmó flag OFF correcto, activación temporal, agregar/consolidar/cambiar/
  retirar, persistencia entre navegadores, aislamiento entre dos cuentas,
  conflicto entre pestañas, logout/compra invitada, `sin_doble_activo=true` y
  `sin_huerfanas=true`.
- No hubo dinero, Wompi, pedido ni Inventario. El flag final quedó `false`.
- El siguiente tramo aprobado es Comercial C3, intención y checkout
  multiproducto. No reconstruir C1/C2 ni presentar la fase como cerrada.
- Cuentas C1/C2 continúan desplegados; Cuentas C2 está cerrado técnicamente en
  preapertura. CAPTCHA sigue activo, signup permanece OFF y Google
  External/Testing hasta publicar políticas y avisos contextuales.
- `clientes.id` sigue siendo la identidad comercial; nunca reemplazarlo por el
  UID de Auth. `cuentas_cliente` es el puente.
- La tienda conserva compra como invitado y cuenta opcional.

Reglas que no cambian:

- Rama nueva + PR por cambio; migraciones forward; medir antes de afirmar.
- Cuando el dueño deba pegar o desplegar algo, dar **links directos**: el raw de
  GitHub fijado al commit probado (comprobado: responde 200 y coincide con lo
  probado) y la pantalla exacta del dashboard de Supabase
  (`https://supabase.com/dashboard/project/bxlzipwxyxdtffnuizbz/...`).
- En un sandbox nuevo, armar el banco con
  `bash supabase/pruebas/local/herramientas/preparar.sh` antes de dar algo por
  bueno.
