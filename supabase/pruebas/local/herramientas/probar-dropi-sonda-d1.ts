// ============================================================================
// MAGANDHI · Prueba runtime de dropi-sonda D1
// ----------------------------------------------------------------------------
// No toca Dropi, Supabase ni secretos reales. Levanta un doble local de ambos,
// captura el handler REAL de la Edge Function y prueba que D1 sigue siendo
// lectura: paginación acotada, preview HTTPS, ficha/stock por id y NUNCA orders/.
// Se ejecuta desde correr-dropi-sonda-d1.sh.
// ============================================================================

const repo = Deno.env.get("REPO") ?? "/projects/sandbox/12344-ux.github.io";
const PORT = 8798;
const BASE = `http://127.0.0.1:${PORT}/`;
const ADMIN = "admin-jwt-prueba";
const NO_ADMIN = "operador-jwt-prueba";

let esAdmin = true;
let ultimoBodyIndice: unknown = null;
const rutasDropi: string[] = [];

const servidor = Deno.serve({ port: PORT, onListen() {} }, async (req) => {
  const url = new URL(req.url);
  const ruta = url.pathname;

  // Doble mínimo de Supabase Auth / perfil.
  if (ruta === "/auth/v1/user") {
    const auth = req.headers.get("authorization") ?? "";
    if (auth === `Bearer ${ADMIN}` || auth === `Bearer ${NO_ADMIN}`) {
      return Response.json({ id: "11111111-1111-4111-8111-111111111111" });
    }
    return Response.json({ error: "bad jwt" }, { status: 401 });
  }
  if (ruta === "/rest/v1/perfiles") {
    return Response.json([{ rol: esAdmin ? "admin" : "operador" }]);
  }

  // Doble de Dropi. Todo request se registra: las aserciones comprueban que
  // nunca aparece orders/ ni un método distinto de GET/POST de catálogo.
  if (ruta.startsWith("/integrations/")) {
    rutasDropi.push(`${req.method} ${ruta}`);
    if (ruta === "/integrations/categories/") {
      return Response.json({ isSuccess: true, objects: [{ name: "Cuidado" }] });
    }
    if (ruta === "/integrations/products/index") {
      ultimoBodyIndice = await req.json();
      // Forma REAL (ajuste de uso real D1): el listado trae `gallery` con objetos
      // `{ urlS3 }` relativos al CDN, y `count` llega 0 aunque haya
      // resultados. La versión anterior del doble mandaba URLs completas y un
      // count correcto: por eso las pruebas pasaban y en producción no había
      // fotos ni botón «Siguiente».
      const f = ultimoBodyIndice as Record<string, unknown>;
      const palabra = String(f.keywords ?? "");
      const totalCatalogo = palabra === "mucho" ? 5000 : 30;
      const desde = Number(f.startData) || 0;
      const cuantos = Number(f.pageSize) || 0;
      const objetos = [];
      for (let i = desde; i < Math.min(desde + cuantos, totalCatalogo); i++) {
        objetos.push({
          id: 101 + i,
          name: i === 0 ? "Producto de prueba" : `Producto ${101 + i}`,
          sku: "PRODUCTO",
          active: true,
          sale_price: 12000,
          suggested_price: 30000,
          categories: [{ name: "Cuidado" }],
          gallery: [
            { id: 1, urlS3: "colombia/products/101/foto 1.jpg" },
            { id: 2, urlS3: "//otro-host.invalid/no-debe-salir.jpg" },
            { id: 3, urlS3: "https://otro-host.invalid/no-debe-salir.jpg" },
            { id: 4, url: "storage/products/viejo.jpg" },
          ],
          photos: [
            "https://cdn.dropi.invalid/foto-segura.jpg",
            "http://cdn.dropi.invalid/no-debe-salir.jpg",
            "https://usuario:clave@cdn.dropi.invalid/no-debe-salir.jpg",
          ],
          variations: [{ id: 55, name: "500 ml", sku: "P-500", sale_price: 12000, stock: 3 }],
          warehouse_product: [{ warehouse_id: 1, stock: 3 }, { warehouse_id: 2, stock: 2 }],
          user: { id: 77, verified: true },
        });
      }
      return Response.json({
        isSuccess: true,
        count: palabra === "contado" ? totalCatalogo : 0,
        objects: objetos,
      });
    }
    if (ruta === "/integrations/products/v2/101") {
      return Response.json({
        isSuccess: true,
        objects: {
          id: 101,
          name: "Producto de prueba",
          sku: "PRODUCTO",
          active: true,
          sale_price: 12000,
          suggested_price: 30000,
          // La ficha (products/v2) trae `photos` con la misma forma `{ urlS3 }`.
          photos: [{ id: 9, urlS3: "colombia/products/101/ficha.jpg" }],
          variations: [{ id: 55, name: "500 ml", sku: "P-500", sale_price: 12000, stock: 3 }],
          warehouse_product: [{ warehouse_id: 1, stock: 3 }, { warehouse_id: 2, stock: 2 }],
          user: { id: 77, verified: true },
        },
      });
    }
    if (ruta === "/integrations/products/101") {
      return Response.json({ isSuccess: false, message: "No tiene permisos para ver este producto" }, { status: 400 });
    }
    return Response.json({ error: "ruta no esperada" }, { status: 404 });
  }

  return Response.json({ error: "ruta no esperada" }, { status: 404 });
});

Deno.env.set("SUPABASE_URL", BASE.slice(0, -1));
Deno.env.set("SUPABASE_ANON_KEY", "anon-prueba");
Deno.env.set("DROPI_API_BASE", `${BASE}integrations/`);
Deno.env.set("DROPI_TOKEN", "TOKEN-SECRETO-QUE-NO-DEBE-SALIR");
Deno.env.set("DROPI_USER_AGENT", "MAGANDHI-Impulse/prueba");

// Capturamos el handler real: importar la Edge Function no abre un segundo
// puerto ni depende de infraestructura de Supabase.
const serveReal = Deno.serve;
let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => {
  handler = h;
  return { finished: Promise.resolve() };
};
await import(`${repo}/supabase/functions/dropi-sonda/index.ts?d1=${Date.now()}`);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = serveReal;

const resultados: Array<{ ok: boolean; que: string }> = [];
const chk = (ok: boolean, que: string) => resultados.push({ ok: !!ok, que });

async function llamar(body: unknown, jwt = ADMIN, metodo = "POST") {
  return await handler(new Request("https://montaguth.institute/functions/v1/dropi-sonda", {
    method: metodo,
    headers: {
      origin: "https://montaguth.institute",
      apikey: "anon-prueba",
      authorization: `Bearer ${jwt}`,
      "content-type": "application/json",
    },
    body: metodo === "POST" ? JSON.stringify(body) : undefined,
  }));
}

// CORS y frontera de método.
{
  const r = await handler(new Request("https://montaguth.institute/functions/v1/dropi-sonda", {
    method: "OPTIONS", headers: { origin: "https://montaguth.institute" },
  }));
  chk(r.status === 204, "OPTIONS responde 204");
  chk(r.headers.get("Access-Control-Allow-Origin") === "https://montaguth.institute", "CORS refleja el panel permitido");
}
{
  const r = await llamar({}, ADMIN, "GET");
  chk(r.status === 405, "solo acepta POST");
}
{
  rutasDropi.length = 0;
  const r = await llamar({}, "jwt-invalido");
  chk(r.status === 401, "sin sesión válida responde 401");
  chk(rutasDropi.length === 0, "sin sesión no toca Dropi");
}
{
  rutasDropi.length = 0;
  esAdmin = false;
  const r = await llamar({ buscar: "shampoo" }, NO_ADMIN);
  chk(r.status === 403, "un no-admin no consulta Dropi en D1");
  chk(rutasDropi.length === 0, "no-admin no toca Dropi");
  esAdmin = true;
}

// `null` era un borde de la versión anterior: ahora es búsqueda vacía, no 500.
{
  rutasDropi.length = 0;
  const r = await llamar(null);
  const j = await r.json();
  chk(r.status === 200 && j.conectado === true, "body JSON null se degrada a búsqueda vacía sin romper");
  chk(rutasDropi.includes("POST /integrations/products/index"), "búsqueda vacía usa products/index de solo lectura");
}

// Paginación acotada y fotos remotas seguras.
{
  rutasDropi.length = 0;
  ultimoBodyIndice = null;
  const r = await llamar({ buscar: "shampoo", inicio: 12, tamano: 6 });
  const j = await r.json();
  const filtro = ultimoBodyIndice as Record<string, unknown>;
  chk(r.status === 200 && j.conectado === true, "búsqueda con página responde conectada");
  chk(filtro.startData === 12 && filtro.pageSize === 7 && filtro.keywords === "shampoo", "envía offset, tamaño+1 (para saber si hay más) y palabra exactos a products/index");
  chk(j.productos.muestra.length === 6 && j.productos.cantidad === 6, "muestra exactamente el tamaño pedido, nunca el producto de más");
  chk(j.consulta.inicio === 12 && j.consulta.tamano === 6 && j.consulta.anterior_inicio === 6 && j.consulta.siguiente_inicio === 18 && j.consulta.hay_mas === true, "con count=0 de Dropi igual habilita Siguiente porque llegó uno de más");
  chk(j.productos.total === null && j.productos.total_reportado_por_dropi === 0, "un count de 0 con resultados no se presenta como total («0 coincidencias»)");
  const p = j.productos.muestra[0];
  chk(p.fotos_remotas.includes("https://d39ru7awumhhs2.cloudfront.net/colombia/products/101/foto%201.jpg"), "foto real `gallery[].urlS3` se arma sobre el CDN de Dropi (y codifica espacios)");
  chk(p.fotos_remotas.includes("https://api.dropi.co/storage/products/viejo.jpg"), "foto antigua `url` relativa se arma sobre api.dropi.co");
  chk(p.fotos_remotas.includes("https://cdn.dropi.invalid/foto-segura.jpg"), "una URL HTTPS completa sigue aceptándose");
  chk(!p.fotos_remotas.some((u: string) => u.includes("otro-host.invalid")), "una ruta relativa nunca puede saltar a otro host");
  chk(!p.fotos_remotas.some((u: string) => u.startsWith("http:") || u.includes("@")), "preview descarta HTTP y URLs con credenciales");
  chk(p.fotos_remotas.length === 3 && p.fotos === 3, "fotos válidas sin duplicados entre gallery y photos");
  chk(p.detalle_variaciones.length === 1 && String(p.detalle_variaciones[0].id) === "55", "expone variante como diagnóstico sin crearla ni seleccionarla");
  chk(!JSON.stringify(j).includes("TOKEN-SECRETO-QUE-NO-DEBE-SALIR"), "la respuesta nunca filtra DROPI_TOKEN");
}

// Última página: Dropi devuelve menos de tamano+1 -> no hay Siguiente.
{
  const r = await llamar({ buscar: "shampoo", inicio: 24, tamano: 6 });
  const j = await r.json();
  chk(j.productos.muestra.length === 6 && j.consulta.hay_mas === false && j.consulta.siguiente_inicio === null && j.consulta.anterior_inicio === 18, "en la última página Siguiente se apaga y Anterior sigue");
}

// Página de 24 (la del panel) y count creíble: sí se informa el total.
{
  ultimoBodyIndice = null;
  const r = await llamar({ buscar: "contado", inicio: 0, tamano: 24 });
  const j = await r.json();
  const filtro = ultimoBodyIndice as Record<string, unknown>;
  chk(filtro.pageSize === 25 && j.productos.muestra.length === 24 && j.consulta.siguiente_inicio === 24, "página de 24 pide 25 y muestra 24");
  chk(j.productos.total === 30, "si el count de Dropi cuadra con lo visto, se informa el total");
}

// Ventana máxima: hay más, pero no se sigue paginando sin fin.
{
  const r = await llamar({ buscar: "mucho", inicio: 1200, tamano: 24 });
  const j = await r.json();
  chk(j.consulta.inicio === 1200 && j.consulta.hay_mas === true && j.consulta.siguiente_inicio === null && j.consulta.limite_alcanzado === true, "al final de la ventana avisa límite en vez de recorrer el catálogo");
}

// Entradas fuera de rango regresan a la ventana segura por defecto.
{
  ultimoBodyIndice = null;
  const r = await llamar({ inicio: 999999, tamano: 200, producto_id: "no-es-id" });
  const j = await r.json();
  const filtro = ultimoBodyIndice as Record<string, unknown>;
  chk(j.consulta.inicio === 0 && j.consulta.tamano === 5, "paginación fuera de rango vuelve a 0/5");
  chk(filtro.startData === 0 && filtro.pageSize === 6, "Dropi nunca recibe offset/tamaño fuera de límites");
  chk(j.producto === null, "id no numérico no activa lectura individual");
}

// Ficha por id: stock proviene de products/v2/bodegas; la ruta simple queda
// visible como diagnóstico 400 y no se convierte en fuente de stock.
{
  rutasDropi.length = 0;
  const r = await llamar({ producto_id: 101 });
  const j = await r.json();
  chk(j.producto.detalle.http === 200 && j.producto.detalle.isSuccess === true, "ficha products/v2 por id responde 200");
  chk(j.producto.ficha.stock === 5 && j.producto.ficha.bodegas.length === 2, "stock se suma desde warehouse_product");
  chk(j.producto.ficha.fotos_remotas.length === 1 && j.producto.ficha.fotos_remotas[0] === "https://d39ru7awumhhs2.cloudfront.net/colombia/products/101/ficha.jpg", "la ficha por id también trae su foto real `photos[].urlS3`");
  chk(j.producto.ruta_stock_aparte.http === 400, "ruta simple queda como diagnóstico 400, no fuente de stock");
  chk(rutasDropi.includes("GET /integrations/products/v2/101") && rutasDropi.includes("GET /integrations/products/101"), "consulta ambas rutas documentadas por id");
}

// La línea roja: ni una sola ruta de pedido, mutación o proveedor aparece.
chk(!rutasDropi.some((r) => /orders|POST \/integrations\/products\/(?!index)/.test(r)), "NUNCA llama orders/ ni muta un producto Dropi");

await servidor.shutdown();
for (const r of resultados) console.log(`${r.ok ? "pasa" : "FALLA"} | ${r.que}`);
const fallan = resultados.filter((r) => !r.ok).length;
console.log(`RESUMEN | ${resultados.length} comprobaciones · ${fallan} fallan`);
if (fallan) Deno.exit(1);
