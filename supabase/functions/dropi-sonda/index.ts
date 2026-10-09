// ============================================================================
// MAGANDHI · Edge Function · dropi-sonda (Dropshipping · fase 0)
// ----------------------------------------------------------------------------
// Pregunta una sola cosa: ¿la API de produccion de Dropi acepta nuestro token?
//
// SOLO LECTURA. Consultas a Dropi; devuelve lo que respondio:
//   1) GET  categories/            -> ¿el token entra?
//   2) POST products/index         -> busqueda del catalogo (es el listado que
//                                     usa el plugin oficial; POST porque lleva
//                                     filtros, NO crea nada)
//   3) GET  products/v2/{id}       -> ficha completa de UN producto elegido
//   4) GET  products/{id}          -> existencias de ESE producto (la consulta
//                                     que mantendria «agotado» al dia)
// Las dos ultimas solo corren si se manda { producto_id }.
// No llama a orders/*, no escribe en la base, no guarda nada.
//
// Quien puede llamarla: un usuario con sesion y rol 'admin' en perfiles.
// Verify JWT: ENCENDIDO.
//
// LINEA ROJA: DROPI_TOKEN solo en Secrets. Nunca se devuelve ni se loguea.
// Diseño: docs/dropshipping-envios/DROPI.md §6.
// ============================================================================

const BASE = (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/").replace(/\/*$/, "/");
const ESPERA_MS = 15000;

// MEDIDO el 9-oct-2026 con dropi-cabeceras: Dropi responde 401 "Access denied"
// a una peticion SIN User-Agent, y 200 a la MISMA peticion con uno. Era lo
// unico que faltaba; no era el token, ni el permiso, ni la IP. Se envia un
// User-Agent honesto que identifica a MAGANDHI (no se finge ser otro programa).
// Si algun dia Dropi endurece la regla, se cambia con el secreto. Se lee en
// cada peticion, no al arrancar, para que el cambio valga sin redesplegar.
const ua = () => (Deno.env.get("DROPI_USER_AGENT") ?? "MAGANDHI-Impulse/1.0 (+https://magandhi.com)").trim();

const ORIGENES = new Set(["https://montaguth.institute", "https://www.montaguth.institute", "https://12344-ux.github.io"]);
function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ORIGENES.has(origin) ? origin : "https://montaguth.institute",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, c: Record<string, string>) =>
  new Response(JSON.stringify(b, null, 2), { status: s, headers: { ...c, "Content-Type": "application/json; charset=utf-8" } });

type Obj = Record<string, unknown>;
const esObj = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);
const corto = (v: unknown, n = 200) => (v === undefined || v === null ? null : String(v).slice(0, n));

// Una llamada a Dropi con tiempo limite. Nunca lanza: devuelve lo que paso.
async function llamarDropi(metodo: "GET" | "POST", ruta: string, token: string, cuerpo?: Obj) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ESPERA_MS);
  const inicio = Date.now();
  try {
    const r = await fetch(BASE + ruta, {
      method: metodo,
      headers: {
        "Content-Type": "application/json;charset=UTF-8",
        "dropi-integration-key": token,
        Accept: "application/json",
        "User-Agent": ua(),
      },
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
      signal: ctrl.signal,
    });
    const texto = await r.text();
    let j: unknown = null;
    try { j = JSON.parse(texto); } catch { /* no era JSON */ }
    return { http: r.status, ms: Date.now() - inicio, j: esObj(j) ? j : null, crudo: esObj(j) ? null : texto.slice(0, 200) };
  } catch (e) {
    const abortado = (e as Error)?.name === "AbortError";
    return { http: 0, ms: Date.now() - inicio, j: null, crudo: abortado ? "Dropi no respondio a tiempo" : "No se pudo conectar con Dropi" };
  } finally {
    clearTimeout(t);
  }
}

// Resumen de la respuesta, sin copiar todo lo que mande Dropi.
function resumir(r: Awaited<ReturnType<typeof llamarDropi>>) {
  const j = r.j ?? {};
  const objetos = Array.isArray(j.objects) ? j.objects : null;
  // Al pedir UN producto por id, Dropi devuelve `objects` como objeto suelto,
  // no como lista. Se guarda aparte para no perderlo.
  const objeto = !Array.isArray(j.objects) && esObj(j.objects) ? j.objects : null;
  return {
    http: r.http,
    ms: r.ms,
    isSuccess: j.isSuccess ?? null,
    mensaje: corto(j.message) || corto(j.error) || r.crudo,
    // Dropi devuelve la IP desde la que llegamos cuando niega el acceso.
    ip_vista_por_dropi: corto(j.ip, 60),
    cantidad: objetos ? objetos.length : null,
    total: typeof j.count === "number" ? j.count : null,
    objetos,
    objeto,
  };
}

const sumarStock = (filas: unknown) =>
  Array.isArray(filas) ? filas.reduce((s, w) => s + (esObj(w) ? Number(w.stock) || 0 : 0), 0) : null;

// Lo que nos sirve para "arrastrar" un producto. Si un campo no viene, null.
function muestraProducto(p: unknown) {
  if (!esObj(p)) return null;
  const variaciones = Array.isArray(p.variations) ? p.variations : [];
  const cats = Array.isArray(p.categories) ? p.categories.map((c) => (esObj(c) ? corto(c.name, 60) : null)).filter(Boolean) : [];
  const fotos = Array.isArray(p.gallery) ? p.gallery.length : Array.isArray(p.photos) ? p.photos.length : null;
  const prov = esObj(p.user) ? p.user : null;
  return {
    id: p.id ?? null,
    nombre: corto(p.name, 120),
    tipo: corto(p.type, 20),
    precio_proveedor: p.sale_price ?? null,
    precio_sugerido: p.suggested_price ?? null,
    stock: typeof p.stock === "number" ? p.stock : sumarStock(p.warehouse_product),
    variaciones: variaciones.length,
    categorias: cats,
    fotos,
    largo_descripcion: typeof p.description === "string" ? p.description.length : null,
    proveedor_id: prov?.id ?? p.user_id ?? null,
    proveedor_verificado: prov ? (prov.verified ?? prov.is_verified ?? null) : null,
  };
}

Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405, c);

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
  const apikey = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!supabaseUrl || !apikey) return json({ error: "Configuración del servidor incompleta." }, 500, c);
  if (!jwt) return json({ error: "Inicia sesión." }, 401, c);

  // 1) ¿Quien llama? Usuario real con sesion...
  const ru = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey, Authorization: `Bearer ${jwt}` } });
  const usuario = ru.ok ? await ru.json().catch(() => null) : null;
  if (!usuario?.id) return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, c);

  // ...y admin. perfiles deja leer solo la fila propia (RLS).
  const rp = await fetch(`${supabaseUrl}/rest/v1/perfiles?select=rol&id=eq.${encodeURIComponent(usuario.id)}`, {
    headers: { apikey, Authorization: `Bearer ${jwt}`, Accept: "application/json" },
  });
  const perfiles = rp.ok ? await rp.json().catch(() => []) : [];
  if (!Array.isArray(perfiles) || perfiles[0]?.rol !== "admin") {
    return json({ error: "Solo un administrador puede usar la sonda de Dropi." }, 403, c);
  }

  // 2) El token.
  const token = (Deno.env.get("DROPI_TOKEN") ?? "").trim();
  if (!token) {
    return json({ conectado: false, conclusion: "Falta el secreto DROPI_TOKEN en Edge Functions → Secrets." }, 200, c);
  }

  let body: Obj = {};
  try { body = await req.json(); } catch { /* sin cuerpo: busqueda vacia */ }
  const buscar = corto(body.buscar, 60) ?? "";
  // Un id concreto: es el embudo real. El dueno elige el producto en Dropi y
  // aqui se lee SOLO ese, no el catalogo entero.
  const idCrudo = body.producto_id;
  const productoId = typeof idCrudo === "number" || (typeof idCrudo === "string" && /^\d{1,12}$/.test(idCrudo))
    ? String(idCrudo)
    : null;

  // 3) Las dos consultas de solo lectura.
  const cat = resumir(await llamarDropi("GET", "categories/", token));
  const prod = resumir(await llamarDropi("POST", "products/index", token, {
    startData: 0,
    pageSize: 5,
    order_type: "desc",
    order_by: "id",
    keywords: buscar,
    active: true,
    no_count: false,
    integration: true,
    get_stock: false,
  }));

  // 3 bis) Si vino un id, se lee ese producto por las dos rutas que usa el
  // plugin: v2 para la ficha completa y la simple para refrescar existencias.
  // Esta es la prueba del STOCK sin WooCommerce de por medio.
  const detalle = productoId ? resumir(await llamarDropi("GET", `products/v2/${productoId}`, token)) : null;
  const stock = productoId ? resumir(await llamarDropi("GET", `products/${productoId}`, token)) : null;

  const entra = cat.isSuccess === true || prod.isSuccess === true;
  const negado = [cat, prod].some((r) => r.http === 401 || /access denied/i.test(r.mensaje ?? ""));
  const ip = cat.ip_vista_por_dropi ?? prod.ip_vista_por_dropi;

  // Un objeto suelto (la ficha de un producto) o el primero si vino lista.
  const unProducto = (r: typeof detalle) => (r ? (r.objeto ?? r.objetos?.[0] ?? null) : null);
  const fichaDetalle = unProducto(detalle);
  const fichaStock = unProducto(stock);

  let conclusion: string;
  if (entra) {
    conclusion = productoId
      ? (detalle?.isSuccess === true || stock?.isSuccess === true
        ? `Conectados y el producto ${productoId} se leyó directo desde Dropi: con esto se arma el embudo a Campañas.`
        : `Conectados al catálogo, pero el producto ${productoId} no se pudo leer. Revisa que el id exista en Dropi.`)
      : "Conectados: Dropi aceptó el token desde Supabase. Vuelve a correrla con { producto_id: 1234 } para leer un producto concreto y su stock.";
  } else if (negado) {
    conclusion = ip
      ? `Dropi negó el acceso. Llegamos desde la IP ${ip} con el User-Agent «${ua()}». Si antes funcionaba, prueba cambiando el secreto DROPI_USER_AGENT.`
      : "Dropi negó el acceso (token no aceptado). Revisa que el secreto sea el token de la integración autenticada.";
  } else {
    conclusion = "Dropi respondió algo inesperado. Pásale este resultado a Kiro.";
  }

  const primero = prod.objetos?.[0];
  console.log("[dropi-sonda]", JSON.stringify({ categorias: cat.http, productos: prod.http, entra }));

  return json({
    conectado: entra,
    conclusion,
    user_agent_usado: ua(),
    busqueda: buscar || null,
    // Lo que de verdad decide el frente: ¿se puede leer un producto y su stock
    // directo de Dropi, cuando queramos?
    producto: productoId
      ? {
          id_pedido: productoId,
          detalle: { http: detalle?.http ?? null, isSuccess: detalle?.isSuccess ?? null, mensaje: detalle?.mensaje ?? null },
          stock: { http: stock?.http ?? null, isSuccess: stock?.isSuccess ?? null, mensaje: stock?.mensaje ?? null },
          campos_detalle: esObj(fichaDetalle) ? Object.keys(fichaDetalle).sort() : [],
          ficha: muestraProducto(fichaDetalle),
          // La misma ficha leida por la ruta de existencias: es la que se
          // consultaria cada pocos minutos para que «agotado» siga a Dropi.
          existencias: muestraProducto(fichaStock),
          leido: new Date().toISOString(),
        }
      : null,
    categorias: {
      http: cat.http, ms: cat.ms, isSuccess: cat.isSuccess, mensaje: cat.mensaje, ip_vista_por_dropi: cat.ip_vista_por_dropi,
      cantidad: cat.cantidad,
      nombres: (cat.objetos ?? []).slice(0, 15).map((o) => (esObj(o) ? corto(o.name, 60) : null)),
    },
    productos: {
      http: prod.http, ms: prod.ms, isSuccess: prod.isSuccess, mensaje: prod.mensaje, ip_vista_por_dropi: prod.ip_vista_por_dropi,
      cantidad: prod.cantidad, total: prod.total,
      // Los nombres de los campos que manda Dropi: con esto se diseña el "arrastre".
      campos_disponibles: esObj(primero) ? Object.keys(primero).sort() : [],
      muestra: (prod.objetos ?? []).slice(0, 5).map(muestraProducto),
    },
  }, 200, c);
});
