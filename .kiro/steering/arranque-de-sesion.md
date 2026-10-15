---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `CONTEXTO-MAGANDHI.md` (realidad operativa y pendientes vigentes).
2. Leer `docs/RELEVO-CUENTAS-2026-10-15.md`: es el relevo más reciente. **C1
   está desplegado; lo siguiente exacto es C2 en magandhi.com.**
3. Leer `docs/CUENTAS-CLIENTE.md` para las decisiones de identidad, compra como
   invitado y tramos C1–C4.
4. Solo si la tarea vuelve a Dropshipping, leer además
   `docs/dropshipping-envios/RELEVO-2026-10-10.md` y aplicar
   `.kiro/steering/dropshipping-magandhi.md`.

Realidad de arranque al 15-oct-2026:

- La migración más alta aplicada en producción es `20261031000000`.
- C1 de cuentas está fusionado, desplegado y medido.
- El registro público de Supabase Auth está apagado mientras se construye C2.
- `clientes.id` sigue siendo la identidad comercial; nunca reemplazarlo por el
  UID de Auth. `cuentas_cliente` es el puente.
- La tienda conservará compra como invitado y cuenta opcional.
- El próximo tramo es C2: registro, confirmación, login y recuperación en el
  repositorio `magandhi`, sin encender altas hasta verificar todo.

Reglas que no cambian:

- Rama nueva + PR por cambio; migraciones forward; medir antes de afirmar.
- Cuando el dueño deba pegar o desplegar algo, dar **links directos**: el raw de
  GitHub fijado al commit probado (comprobado: responde 200 y coincide con lo
  probado) y la pantalla exacta del dashboard de Supabase
  (`https://supabase.com/dashboard/project/bxlzipwxyxdtffnuizbz/...`).
- En un sandbox nuevo, armar el banco con
  `bash supabase/pruebas/local/herramientas/preparar.sh` antes de dar algo por
  bueno.
