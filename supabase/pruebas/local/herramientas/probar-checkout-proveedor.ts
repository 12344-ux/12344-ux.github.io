// ============================================================================
// MAGANDHI · D2c.2c · verificacion EN VIVO antes de cobrar
// ----------------------------------------------------------------------------
// Ejecuta la Edge Function REAL crear-intencion-pago contra dobles locales de
// PostgREST y de Dropi. No toca red real, token real ni Wompi.
//
// Lo que se mide es LA DECISION DIFICIL del tramo: que pasa cuando Dropi no
// responde. El criterio elegido:
//   · Dropi dice que NO hay                      -> rechazar
//   · Dropi no responde Y la lectura es FRESCA    -> permitir
//   · Dropi no responde Y la lectura envejecio    -> rechazar
// ============================================================================
const repo = Deno.env.get("REPO") ?? "/projects/sandbox/12344-ux.github.io";
const PORT = 8821;
const BASE = `http://127.0.0.1:${PORT}/`;

type Obj = Record<string, unknown>;
const E: Obj = {};
function reset(cfg: Obj = {}) {
  for (const k of Object.keys(E)) delete E[k];
  Object.assign(E, {
    origen: "proveedor",
    dropi_id: "2296060",
    variante: "7001",
    piso: 20,
    reservadas: 0,
    minutos_desde_lectura: 1,
    frescura_max_min: 10,
    disponible_local: 230,
    // Dropi
    dropi_http: 200,
    dropi_stock_variante: 230,
    dropi_lento: false,
    sin_verificacion: false,
    intenciones: 0,
    llamadas_dropi: 0,
  }, cfg);
}
reset();

const servidor = Deno.serve({ port: PORT, onListen() {} }, async (req) => {
  const u = new URL(req.url);
  const ruta = u.pathname;

  // --- Doble de Dropi -------------------------------------------------------
  if (ruta.startsWith("/integrations/")) {
    E.llamadas_dropi = Number(E.llamadas_dropi) + 1;
    if (E.dropi_lento) await new Promise((r) => setTimeout(r, 9000)); // > timeout
    const http = Number(E.dropi_http);
    if (http !== 200) {
      return Response.json({ isSuccess: false, message: "no" }, { status: http });
    }
    return Response.json({
      isSuccess: true,
      objects: {
        id: 2296060, name: "Serum", type: "VARIABLE", warehouse_product: [],
        variations: [
          { id: 7001, stock: Number(E.dropi_stock_variante) },
          { id: 7002, stock: 999 },
        ],
      },
    });
  }

  // --- Doble de PostgREST ---------------------------------------------------
  if (ruta === "/rest/v1/catalogo_publico") {
    return Response.json({
      id: "cb000000-0000-4000-8000-00000000000b",
      slug: "camp-serum", nombre: "Serum", precio_venta: 59900, agotado: false,
    });
  }
  if (ruta === "/rest/v1/rpc/ds_verificacion_checkout") {
    if (E.sin_verificacion) return Response.json(null);
    return Response.json({
      origen: E.origen, dropi_id: E.dropi_id, variante: E.variante,
      piso: E.piso, reservadas: E.reservadas,
      minutos_desde_lectura: E.minutos_desde_lectura,
      frescura_max_min: E.frescura_max_min,
      disponible_local: E.disponible_local,
    });
  }
  if (ruta === "/rest/v1/rpc/pagos_config_para_intencion") {
    return Response.json([{
      entorno: "sandbox",
      llave_publica: "pub_test_x", moneda: "COP",
      url_redireccion: "https://magandhi.com/producto/?pago=1",
    }]);
  }
  if (ruta === "/rest/v1/rpc/pw_registrar_intencion") {
    E.intenciones = Number(E.intenciones) + 1;
    return Response.json(null);
  }
  return Response.json({ message: "ruta no esperada: " + ruta }, { status: 404 });
});

Deno.env.set("SUPABASE_URL", BASE.slice(0, -1));
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "LLAVE-DE-SERVICIO-QUE-NO-DEBE-SALIR");
Deno.env.set("DROPI_API_BASE", `${BASE}integrations/`);
Deno.env.set("DROPI_TOKEN", "TOKEN-DROPI-QUE-NO-DEBE-SALIR");
Deno.env.set("DROPI_USER_AGENT", "MAGANDHI-Impulse/prueba");
Deno.env.set("WOMPI_INTEGRITY_SANDBOX", "secreto-de-integridad-de-prueba");

const serveReal = Deno.serve;
let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => {
  handler = h;
  return { finished: Promise.resolve() };
};
await import(`${repo}/supabase/functions/crear-intencion-pago/index.ts?d2c2c=${Date.now()}`);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = serveReal;

const res: Array<{ ok: boolean; que: string }> = [];
const chk = (ok: boolean, que: string) => res.push({ ok: !!ok, que });

async function comprar() {
  const r = await handler(new Request("https://magandhi.com/x", {
    method: "POST",
    headers: { origin: "https://magandhi.com", "content-type": "application/json" },
    body: JSON.stringify({
      producto: "camp-serum", cantidad: 1,
      comprador: { nombre: "Dora Compradora", correo: "d@ejemplo.invalid",
                   telefono: "3000000000", direccion: "Calle 1", ciudad: "Leticia" },
    }),
  }));
  let cuerpo: Obj = {};
  try { cuerpo = await r.json(); } catch { /* vacio */ }
  return { status: r.status, cuerpo };
}

// --- Caso normal: Dropi confirma que hay --------------------------------
{
  reset();
  const r = await comprar();
  chk(r.status === 200, `con stock confirmado por Dropi, la compra procede (${r.status})`);
  chk(Number(E.llamadas_dropi) === 1, "se le pregunta a Dropi UNA vez, no por visita");
  chk(Number(E.intenciones) === 1, "y la intención de pago queda registrada");
}

// --- Dropi dice que NO hay: fallo cerrado -------------------------------
{
  reset({ dropi_stock_variante: 0 });
  const r = await comprar();
  chk(r.status === 409, "si Dropi dice que no hay, se rechaza con 409");
  chk(r.cuerpo.error === "Producto agotado.",
    "con el MISMO mensaje que el agotado normal (un texto distinto delataría el dropshipping)");
  chk(Number(E.intenciones) === 0, "y NO queda una intención de pago que nunca debió existir");
}

// --- El piso manda también aquí ----------------------------------------
{
  reset({ dropi_stock_variante: 19, piso: 20 });
  const r = await comprar();
  chk(r.status === 409, "19 unidades con piso 20: se rechaza aunque Dropi diga que hay");
}
{
  reset({ dropi_stock_variante: 25, reservadas: 10, piso: 20 });
  const r = await comprar();
  chk(r.status === 409,
    "25 reportadas menos 10 ya reservadas sin transcribir = 15: por debajo del piso, se rechaza");
}

// --- La variante es la que importa -------------------------------------
{
  // La variante 7001 está en 0; la 7002 tiene 999. Tomar el total vendería humo.
  reset({ dropi_stock_variante: 0, variante: "7001" });
  const r = await comprar();
  chk(r.status === 409, "usa el stock de LA VARIANTE vendida, no el total del producto");
}
{
  reset({ variante: "9999", dropi_stock_variante: 500 });
  const r = await comprar();
  chk(r.status === 409, "una variante que ya no está en la ficha se trata como «no hay»");
}

// --- LA DECISION DIFICIL: Dropi no responde ----------------------------
{
  reset({ dropi_http: 500, minutos_desde_lectura: 2, frescura_max_min: 10 });
  const r = await comprar();
  chk(r.status === 200,
    "Dropi caído + lectura FRESCA (2 min): se permite, porque bloquear sería tienda caída");
}
{
  reset({ dropi_http: 500, minutos_desde_lectura: 45, frescura_max_min: 10 });
  const r = await comprar();
  chk(r.status === 409,
    "Dropi caído + lectura VIEJA (45 min): se rechaza, no hay con qué confirmar");
}
{
  reset({ dropi_http: 429, minutos_desde_lectura: 1 });
  const r = await comprar();
  chk(r.status === 200, "un 429 con lectura fresca no tumba la venta");
}
{
  reset({ dropi_http: 429, minutos_desde_lectura: 90 });
  const r = await comprar();
  chk(r.status === 409, "un 429 con lectura vieja sí la detiene");
}
{
  reset({ dropi_lento: true, minutos_desde_lectura: 1 });
  const inicio = Date.now();
  const r = await comprar();
  const ms = Date.now() - inicio;
  chk(r.status === 200 && ms < 8500,
    `si Dropi tarda, no se deja esperando a quien paga: corta y decide (${ms} ms)`);
}
{
  reset({ minutos_desde_lectura: null, dropi_http: 500 });
  const r = await comprar();
  chk(r.status === 409, "sin ninguna lectura previa Y sin confirmación de Dropi, no se cobra");
}
{
  // La edad de la lectura SOLO decide cuando Dropi no responde. Si confirma,
  // da igual que nunca hubiera habido una lectura en cache.
  reset({ minutos_desde_lectura: null, dropi_http: 200 });
  const r = await comprar();
  chk(r.status === 200, "pero si Dropi confirma, la falta de lectura previa no importa");
}

// --- Producto propio: no se le pregunta nada a Dropi -------------------
{
  reset({ origen: "propio" });
  const r = await comprar();
  chk(r.status === 200, "un producto PROPIO pasa sin cambios");
  chk(Number(E.llamadas_dropi) === 0,
    "y NO gasta una petición a Dropi: su candado es el libro de Inventario");
}

// --- Tolerancia: si la migración no está aplicada ----------------------
{
  reset({ sin_verificacion: true });
  const r = await comprar();
  chk(r.status === 200,
    "si D2c.2c no está aplicada, no se bloquea una venta que ya funcionaba");
  chk(Number(E.llamadas_dropi) === 0, "y no se inventa una verificación");
}

// --- Sin ficha de proveedor --------------------------------------------
{
  reset({ dropi_id: null });
  const r = await comprar();
  chk(r.status === 409,
    "un producto de proveedor sin id de Dropi se rechaza: no hay a quién pedírselo");
}

// --- Secretos -----------------------------------------------------------
{
  reset();
  const r = await comprar();
  const crudo = JSON.stringify(r.cuerpo);
  chk(!crudo.includes("TOKEN-DROPI-QUE-NO-DEBE-SALIR"), "el token de Dropi no sale en la respuesta");
  chk(!crudo.includes("LLAVE-DE-SERVICIO-QUE-NO-DEBE-SALIR"), "la llave de servicio no sale");
  chk(!/\b(230|19|25)\b/.test(String(r.cuerpo.error ?? "")),
    "ningún mensaje de error revela existencias exactas");
}

await servidor.shutdown();
for (const r of res) console.log(`${r.ok ? "pasa" : "FALLA"} | ${r.que}`);
const fallan = res.filter((r) => !r.ok).length;
console.log(`RESUMEN | ${res.length} comprobaciones · ${fallan} fallan`);
if (fallan) Deno.exit(1);
