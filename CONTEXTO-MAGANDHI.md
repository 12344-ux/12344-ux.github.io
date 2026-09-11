# CONTEXTO — Back-office interno de MAGANDHI (ecosistema Impulse)

> Leer este archivo ANTES de tocar nada. Es el mapa del proyecto para retomar
> en cualquier sesión sin perder el hilo.

## Qué es esto

Este repo (`12344-ux/12344-ux.github.io`, sitio **estático en GitHub Pages**,
dominio **montaguth.institute**) es el **BACK-OFFICE INTERNO** de MAGANDHI: la
trastienda de gestión, protegida con login. **NO** es la tienda pública.

- **magandhi.com** (otro repo) = tienda PÚBLICA, cara al cliente. Marca comercial
  terracota. NUNCA lleva el sello Impulse ni menciona la tecnología.
- **montaguth.institute** (este repo) = gestión interna / "control interno".

### Ecosistema Impulse
El dueño (D0m0) tiene una segunda compañía, **Impulse** (la marca es solo
"Impulse"; "Consulting" es el servicio), dedicada a **gestionar organizaciones**.
**MAGANDHI es el caso piloto**: si estos softwares internos funcionan bien, el
modelo se **replica** a otras organizaciones clientes de Impulse. Por eso todo
debe quedar **impecable y "clonable"** (no amarrado solo a MAGANDHI). Regla:
"si lleva el sello Impulse, tiene que estar impecable". El sello
"Con tecnología Impulse" va en el pie de las zonas internas (login/panel/finanzas),
nunca en la tienda pública.

## Infraestructura (todo en producción, mergeado a main)

### Supabase
- Proyecto limpio y nuevo (se borró todo lo del proyecto muerto anterior "Stramont").
- URL: `https://bxlzipwxyxdtffnuizbz.supabase.co`
- Publishable key (PÚBLICA, va en el cliente): `sb_publishable_ap4jdsO_0KPOPWhUk9Y7ZA_0jDUvHu1`
- Creado con Auto-RLS ON y "auto-expose new tables" OFF (seguro).
- Admin: `michaelmagandhi@outlook.com` (UID `89e5028d-8c17-4deb-89c3-59acbd0ee2f2`).
- **Kiro NO tiene acceso al dashboard de Supabase.** Todo el SQL vive en
  `supabase/migrations/` y **el dueño lo ejecuta a mano** en el SQL Editor,
  guiado por `supabase/INSTRUCCIONES.md`. Escribir SQL en el repo NO lo despliega.

### Login y roles
- `index.html` = login (Supabase Auth, email+contraseña, "Solo personal interno").
- `panel.html` = panel interno (cascarón + tarjetas de acceso a módulos).
- `auth-guard.js` = guardia reutilizable (toda página interna lo importa).
- `supabase-config.js` = cliente Supabase único (reutilizar, no duplicar).
- Tabla `perfiles` (id → rol → modulos[]) con RLS + helper `tiene_modulo()`.
  admin = todo; a futuro un trabajador con `modulos={finanzas}` entra solo a finanzas.

### Identidad visual
- Paleta base MAGANDHI en `marca.css` (terracota #A6332E, crema, negro, Poppins).
- Favicons por área en `marca-areas/` (transparentes): `control-interno.png` (azul,
  login/panel), `finanzas.png` (verde, finanzas/*). Cada área futura = su color.
- Área de finanzas: header azul marino #101C33, terracota=DEBE, azul marino=HABER,
  números tabular-nums, COP con puntos de miles.

## SOFTWARE 1 — Módulo Finanzas / Contabilidad PUC  ✅ TERMINADO v1

Contabilidad de partida doble, PUC colombiano (Decreto 2650). Todo en `finanzas/`.

- **Nuevo asiento** (`nuevo-asiento.html`): cuadre EN VIVO, no guarda si Debe≠Haber
  (reforzado server-side).
- **Libro Diario** (`diario.html`) + **editar/anular** (`editar-asiento.html`) con
  **trazabilidad** (bitácora; nada se borra en silencio; "punto medio" — NO es para
  la DIAN, es control interno).
- **Libro Mayor** (`mayor.html`): saldos por cuenta, derivados automáticamente.
- **Catálogo PUC** (`puc.html`): buscable, prioriza por uso. Carga PARCIAL a propósito
  (cuentas de comercio) con plantilla para ampliar en la migración de carga.
- **Agregar cuentas** (`agregar-cuenta.html`): SOLO admin, valida jerarquía/padre
  (no crea cuentas huérfanas). Aparecen al instante en el buscador del asiento.
- **Informes (Tramo 2):** `balance-comprobacion.html` (a corte), `estado-resultados.html`
  (por periodo), `balance-general.html` (a corte). Los tres exportan a **PDF**
  (jsPDF 2.5.1 + autotable 3.8.2 por CDN, con logo/marca) y **Excel/CSV** (BOM UTF-8 + ';').

### Reglas duras del módulo (no negociables)
- Montos SIEMPRE **bigint** (pesos enteros, nunca float).
- Toda tabla financiera con **RLS** vía `tiene_modulo('finanzas')`.
- Funciones de informe **STABLE + SECURITY INVOKER** (heredan RLS). Escritura solo
  vía RPC **security-definer**. Cero secret/service_role en el repo.
- El Balance General calcula el resultado del ejercicio **llamando a
  `estado_resultados`** (año fiscal = año calendario, 1-ene → corte) para que
  coincida al peso y alimente el patrimonio: **Activo = Pasivo + Patrimonio + Resultado**.

### Pendientes del contable (apuntados, NO para ya)
- **Pulido de exportación (Paso 3):** solo cuando el dueño dé feedback tras usarlo
  con operaciones REALES.
- **Cierre anual contable:** necesario al pasar de un año fiscal a otro (p.ej. enero
  2027). Hoy no hace falta (MAGANDHI arranca este año; documentado en el Balance
  General por qué cuadra). NO gold-plating (presupuestos, flujo de caja, multimoneda).

## Próximos pasos posibles (decidir con el dueño)

- **Módulos del back-office:** PEDIDOS (venta en magandhi.com → aparece en el panel;
  idea original del dueño), INVENTARIO, CLIENTES.
- **Tienda pública magandhi.com:** falta la PÁGINA DE PRODUCTO REAL (el hero lleva a
  404); diseño v1 ya aprobado.

## Flujo de trabajo Git
- Rama nueva + PR por cada cambio. NUNCA push directo a main. El dueño mergea rápido.
- Verificar PRs antes de reusar ramas. `.agents/` está en `.gitignore`.
- Los cambios de SQL requieren que el dueño los aplique a mano en Supabase (ver
  `supabase/INSTRUCCIONES.md`, con orden exacto y queries de verificación).

---
_Última actualización: cierre de la jornada en que se terminó el módulo Finanzas v1
(PRs #153–#165, todos mergeados)._
