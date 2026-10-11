// ============================================================================
// MAGANDHI · D2c.1 · prueba runtime de dropi-refrescar-stock
// ----------------------------------------------------------------------------
// Ejecuta la Edge Function REAL contra dobles locales de PostgREST y de Dropi.
// No toca red real, token real, catalogo real ni orders/.
//
// El doble de Dropi imita la forma MEDIDA en la cuenta real (10-oct-2026):
// `objects` como objeto suelto, stock por bodega en `warehouse_product`, y
// variantes con su stock en `warehouse_product_variation`.
// ============================================================================
const repo = Deno.env.get("REPO") ?? "/projects/sandbox/12344-ux.github.io";
const PORT = 8799;
const BASE = `http://127.0.0.1:${PORT}/`;
const SECRETO = "SECRETO-DE-REFRESCO-DE-PRUEBA";

// Estado del doble, manipulable por cada caso.
let cola: Record<string, unknown>[] = [];
let escrituras: Record<string, unknown>[] = [];
const rutasDropi: string[] = [];
let forzar429 = false;
let forzar404 = false;
let colaFalla = false;

const servidor = Deno.serve({ port: PORT, onListen() {} }, async (req) => {
  const ruta = new URL(req.url).pathname;

  // --- Doble de PostgREST ---------------------------------------------------
  if (ruta.startsWith("/rest/v1/rpc/")) {
    // Sin la llave de servicio en apikey Y Authorization, PostgREST degradaria
    // el rol: el doble lo exige para que la prueba detecte esa regresion.
    const apikey = req.headers.get("apikey") ?? "";
    const auth = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!apikey || apikey !== auth) {
      return Response.json({ message: "rol degradado" }, { status: 403 });
    }
    const nombre = ruta.split("/").pop();
    const cuerpo = await req.json().catch(() => ({}));

    if (nombre === "ds_productos_por_refrescar") {
      if (colaFalla) return Response.json({ message: "boom" }, { status: 500 });
      return Response.json(cola);
    }
    if (nombre === "ds_registrar_lectura_stock") {
      escrituras.push(cuerpo);
      return Response.json(cuerpo.p_error ? null : new Date().toISOString());
    }
    return Response.json({ message: "rpc no esperada" }, { status: 404 });
  }

  // --- Doble de Dropi -------------------------------------------------------
  if (ruta.startsWith("/integrations/")) {
    rutasDropi.push(`${req.method} ${ruta}`);
    if (forzar429) {
      return Response.json({ isSuccess: false, message: "Too Many Requests" }, { status: 429 });
    }
    if (forzar404) {
      return Response.json({ isSuccess: false, message: "No existe" }, { status: 404 });
    }
    // Producto SIMPLE: stock por bodega.
    if (ruta === "/integrations/products/v2/101") {
      return Response.json({
        isSuccess: true,
        objects: {
          id: 101, name: "Simple", type: "SIMPLE",
          warehouse_product: [{ warehouse_id: 1, stock: 30 }, { warehouse_id: 2, stock: 70 }],
        },
      });
    }
    // Producto VARIABLE: una variante con unidades y otra en cero.
    if (ruta === "/integrations/products/v2/202") {
      return Response.json({
        isSuccess: true,
        objects: {
          id: 202, name: "Variable", type: "VARIABLE", warehouse_product: [],
          variations: [
            { id: 7001, warehouse_product_variation: [{ warehouse_id: 1, stock: 4 }, { warehouse_id: 2, stock: 6 }] },
            { id: 7002, stock: 0 },
          ],
        },
      });
    }
    return Response.json({ isSuccess: false, message: "ruta no esperada" }, { status: 404 });
  }

  return Response.json({ error: "ruta no esperada" }, { status: 404 });
});

Deno.env.set("SUPABASE_URL", BASE.slice(0, -1));
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "LLAVE-DE-SERVICIO-QUE-NO-DEBE-SALIR");
Deno.env.set("DROPI_API_BASE", `${BASE}integrations/`);
Deno.env.set("DROPI_TOKEN", "TOKEN-SECRETO-QUE-NO-DEBE-SALIR");
Deno.env.set("DROPI_USER_AGENT", "MAGANDHI-Impulse/prueba");
Deno.env.set("DROPI_REFRESCO_SECRETO", SECRETO);
Deno.env.set("DROPI_PAUSA_MS", "1"); // la prueba no espera 600 ms por producto

const serveReal = Deno.serve;
let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => {
  handler = h;
  return { finished: Promise.resolve() };
};
await import(`${repo}/supabase/functions/dropi-refrescar-stock/index.ts?d2c1=${Date.now()}`);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = serveReal;

const resultados: Array<{ ok: boolean; que: string }> = [];
const chk = (ok: boolean, que: string) => resultados.push({ ok: !!ok, que });

async function llamar(secreto: string | null = SECRETO, metodo = "POST") {
  const headers: Record<string, string> = {};
  if (secreto !== null) headers["x-refresco-secreto"] = secreto;
  return await handler(new Request("https://x.invalid/functions/v1/dropi-refrescar-stock", { method: metodo, headers }));
}
function reiniciar() {
  escrituras = [];
  rutasDropi.length = 0;
  forzar429 = false;
  forzar404 = false;
  colaFalla = false;
}

// --- La puerta --------------------------------------------------------------
{
  reiniciar();
  const r = await llamar(null);
  chk(r.status === 401, "sin el secreto responde 401");
  chk(rutasDropi.length === 0 && escrituras.length === 0, "sin secreto NO toca Dropi ni la base");
}
{
  reiniciar();
  const r = await llamar("secreto-equivocado-de-la-misma-longitud!");
  chk(r.status === 401, "con un secreto equivocado responde 401");
  chk(rutasDropi.length === 0, "con secreto equivocado no llega a Dropi");
}
{
  const r = await llamar(SECRETO, "GET");
  chk(r.status === 405, "solo acepta POST");
}
{
  const r = await llamar(null);
  const d = await r.json();
  chk(!JSON.stringify(d).includes(SECRETO), "el 401 no revela el secreto esperado");
  chk((d.error ?? "").length < 30, "el mensaje de 401 es mudo: no ayuda a adivinar");
}

// --- La vuelta normal -------------------------------------------------------
{
  reiniciar();
  cola = [{ product_id: "11111111-1111-4111-8111-111111111111", producto_externo_id: "101", variacion_externa_id: "" }];
  const r = await llamar();
  const d = await r.json();
  chk(r.status === 200 && d.refrescados === 1 && d.fallidos === 0, "refresca un producto SIMPLE");
  chk(escrituras[0]?.p_stock === 100, "suma el stock de las dos bodegas (30 + 70 = 100)");
  chk(escrituras[0]?.p_error === undefined, "una lectura buena no manda error");
}
{
  // El caso que de verdad importa: un producto MAGANDHI por VARIANTE de Dropi.
  // Si tomara el total del producto, vendería humo de una variante agotada.
  reiniciar();
  cola = [{ product_id: "22222222-2222-4222-8222-222222222222", producto_externo_id: "202", variacion_externa_id: "7001" }];
  await llamar();
  chk(escrituras[0]?.p_stock === 10, "con variante fijada usa el stock de ESA variante (4 + 6 = 10)");
}
{
  reiniciar();
  cola = [{ product_id: "22222222-2222-4222-8222-222222222222", producto_externo_id: "202", variacion_externa_id: "7002" }];
  await llamar();
  chk(escrituras[0]?.p_stock === 0, "una variante en cero se registra como 0, no como el total del producto");
}
{
  reiniciar();
  cola = [{ product_id: "22222222-2222-4222-8222-222222222222", producto_externo_id: "202", variacion_externa_id: "" }];
  await llamar();
  chk(escrituras[0]?.p_stock === 10, "un VARIABLE sin variante fijada suma sus variantes (no un falso 0)");
}
{
  // Una variante que desaparecio del catalogo es exactamente «no hay».
  reiniciar();
  cola = [{ product_id: "33333333-3333-4333-8333-333333333333", producto_externo_id: "202", variacion_externa_id: "9999" }];
  const r = await llamar();
  const d = await r.json();
  chk(escrituras[0]?.p_stock === 0, "una variante que ya no existe se registra como 0 (saca el producto de la vitrina ya)");
  chk(/variante/.test(JSON.stringify(d.detalle)), "y lo deja dicho en el detalle");
}

// --- Cuando Dropi falla -----------------------------------------------------
{
  reiniciar();
  forzar404 = true;
  cola = [{ product_id: "11111111-1111-4111-8111-111111111111", producto_externo_id: "101", variacion_externa_id: "" }];
  const r = await llamar();
  const d = await r.json();
  chk(d.fallidos === 1 && d.refrescados === 0, "un 404 cuenta como fallo");
  chk(escrituras[0]?.p_stock === null && /404/.test(String(escrituras[0]?.p_error)),
    "un fallo registra error y p_stock null: NO toca el stock ni la vigencia");
}
{
  // 429: se aborta la vuelta. Insistir solo alarga el castigo.
  reiniciar();
  forzar429 = true;
  cola = [
    { product_id: "11111111-1111-4111-8111-111111111111", producto_externo_id: "101", variacion_externa_id: "" },
    { product_id: "22222222-2222-4222-8222-222222222222", producto_externo_id: "202", variacion_externa_id: "" },
    { product_id: "33333333-3333-4333-8333-333333333333", producto_externo_id: "101", variacion_externa_id: "" },
  ];
  const r = await llamar();
  const d = await r.json();
  chk(d.frenado_por_dropi === true, "un 429 se informa como frenado_por_dropi");
  chk(rutasDropi.length === 1, `ante un 429 ABORTA la vuelta: una sola petición, no tres (hizo ${rutasDropi.length})`);
  chk(escrituras.length === 1 && /429/.test(String(escrituras[0]?.p_error)), "deja constancia del 429 en el producto que lo recibió");
  chk(/429/.test(d.conclusion ?? ""), "la conclusión nombra el 429");
}

// --- Cola vacia y cola rota -------------------------------------------------
{
  reiniciar();
  cola = [];
  const r = await llamar();
  const d = await r.json();
  chk(r.status === 200 && d.refrescados === 0, "una cola vacía no es un error (el auto-freno dijo «todavía no»)");
  chk(rutasDropi.length === 0, "con cola vacía no gasta ni una petición a Dropi");
}
{
  reiniciar();
  colaFalla = true;
  const r = await llamar();
  chk(r.status === 500, "si la cola falla responde 500 y no inventa trabajo");
  chk(rutasDropi.length === 0, "si la cola falla no llama a Dropi");
}
{
  reiniciar();
  cola = [{ product_id: "11111111-1111-4111-8111-111111111111", producto_externo_id: "no-numerico", variacion_externa_id: "" }];
  const r = await llamar();
  const d = await r.json();
  chk(rutasDropi.length === 0 && d.refrescados === 0, "un id externo no numérico se omite sin llamar a Dropi");
}

// --- Secretos y linea roja --------------------------------------------------
{
  reiniciar();
  cola = [{ product_id: "11111111-1111-4111-8111-111111111111", producto_externo_id: "101", variacion_externa_id: "" }];
  const r = await llamar();
  const crudo = JSON.stringify(await r.json());
  chk(!crudo.includes("TOKEN-SECRETO-QUE-NO-DEBE-SALIR"), "el token de Dropi no aparece en la respuesta");
  chk(!crudo.includes("LLAVE-DE-SERVICIO-QUE-NO-DEBE-SALIR"), "la llave de servicio no aparece en la respuesta");
  chk(!crudo.includes(SECRETO), "el secreto de refresco no aparece en la respuesta");
}
chk(rutasDropi.every((r) => r.startsWith("GET ")), "contra Dropi SOLO hace GET: nunca escribe");
chk(!rutasDropi.some((r) => /orders|myorders|importlist/.test(r)), "NUNCA toca orders/ ni ninguna ruta de escritura");
chk(rutasDropi.every((r) => /\/integrations\/products\/v2\//.test(r)), "solo usa products/v2/{id}, la ruta medida para ficha y stock");

await servidor.shutdown();
for (const r of resultados) console.log(`${r.ok ? "pasa" : "FALLA"} | ${r.que}`);
const fallan = resultados.filter((r) => !r.ok).length;
console.log(`RESUMEN | ${resultados.length} comprobaciones · ${fallan} fallan`);
if (fallan) Deno.exit(1);
