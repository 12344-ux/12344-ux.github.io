// ============================================================================
// MAGANDHI · Edge Function · woo-sonda (Dropshipping · fase 0)
// ----------------------------------------------------------------------------
// Mide la SEGUNDA MITAD del puente: ¿puede MAGANDHI leer los productos y el
// stock de un WooCommerce al que Dropi ya empuja productos?
//
// Esta mitad no depende del permiso de Dropi: usa las llaves de la API REST de
// WooCommerce (Consumer Key / Secret) que genera el dueno en su propio
// WordPress. Si Dropi deja el producto ahi, nosotros lo leemos de aqui.
//
// SOLO LECTURA. Una sola llamada:
//   GET {WOO_URL}/wp-json/wc/v3/products?per_page=5&status=any
// No crea, no edita, no borra, no escribe en nuestra base y no toca pedidos.
//
// Quien puede llamarla: un usuario con sesion y rol 'admin' en perfiles.
// Verify JWT: ENCENDIDO.
//
// LINEA ROJA: WOO_KEY y WOO_SECRET solo en Secrets. Nunca se devuelven ni se
// loguean. Diseno: docs/dropshipping-envios/DROPI.md.
// ============================================================================

const ESPERA_MS = 15000;

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

// Lo que nos sirve de cada producto para alimentar Campanas. Si un campo no
// viene, queda null: no se inventa nada.
function muestraProducto(p: unknown) {
  if (!esObj(p)) return null;
  const metas = Array.isArray(p.meta_data) ? p.meta_data : [];
  // El plugin de Dropi marca los productos importados con meta propia.
  const claveDropi = metas
    .map((m) => (esObj(m) ? corto(m.key, 60) : null))
    .filter((k): k is string => !!k && /dropi/i.test(k));
  const imagenes = Array.isArray(p.images) ? p.images.length : null;
  const categorias = Array.isArray(p.categories)
    ? p.categories.map((c) => (esObj(c) ? corto(c.name, 60) : null)).filter(Boolean)
    : [];
  return {
    id_woo: p.id ?? null,
    nombre: corto(p.name, 120),
    sku: corto(p.sku, 60),
    tipo: corto(p.type, 20),
    estado: corto(p.status, 20),
    precio: corto(p.price, 30),
    precio_regular: corto(p.regular_price, 30),
    // Las tres piezas del stock: si gestiona stock, cuanto hay y el estado.
    gestiona_stock: p.manage_stock ?? null,
    stock: typeof p.stock_quantity === "number" ? p.stock_quantity : p.stock_quantity ?? null,
    estado_stock: corto(p.stock_status, 20),
    variaciones: Array.isArray(p.variations) ? p.variations.length : null,
    imagenes,
    categorias,
    largo_descripcion: typeof p.description === "string" ? p.description.length : null,
    // Prueba de que el producto vino de Dropi y con que id quedo ligado.
    marcas_dropi: claveDropi,
    modificado: corto(p.date_modified_gmt ?? p.date_modified, 40),
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

  // 1) Usuario real con sesion...
  const ru = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey, Authorization: `Bearer ${jwt}` } });
  const usuario = ru.ok ? await ru.json().catch(() => null) : null;
  if (!usuario?.id) return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, c);

  // ...y admin. perfiles deja leer solo la fila propia (RLS).
  const rp = await fetch(`${supabaseUrl}/rest/v1/perfiles?select=rol&id=eq.${encodeURIComponent(usuario.id)}`, {
    headers: { apikey, Authorization: `Bearer ${jwt}`, Accept: "application/json" },
  });
  const perfiles = rp.ok ? await rp.json().catch(() => []) : [];
  if (!Array.isArray(perfiles) || perfiles[0]?.rol !== "admin") {
    return json({ error: "Solo un administrador puede usar la sonda de WooCommerce." }, 403, c);
  }

  // 2) Los tres secretos.
  const base = (Deno.env.get("WOO_URL") ?? "").trim().replace(/\/+$/, "");
  const llave = (Deno.env.get("WOO_KEY") ?? "").trim();
  const secreto = (Deno.env.get("WOO_SECRET") ?? "").trim();
  const faltan = [
    !base ? "WOO_URL" : null,
    !llave ? "WOO_KEY" : null,
    !secreto ? "WOO_SECRET" : null,
  ].filter(Boolean);
  if (faltan.length) {
    return json({ conectado: false, conclusion: `Faltan secretos en Edge Functions → Secrets: ${faltan.join(", ")}.` }, 200, c);
  }
  if (!/^https:\/\//i.test(base)) {
    return json({ conectado: false, conclusion: "WOO_URL debe empezar por https:// (la API de WooCommerce exige HTTPS)." }, 200, c);
  }

  // 3) La consulta de solo lectura. status=any para ver tambien los borradores.
  const url = `${base}/wp-json/wc/v3/products?per_page=5&status=any&orderby=date&order=desc`;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ESPERA_MS);
  const inicio = Date.now();
  let http = 0, ms = 0, cuerpo: unknown = null, crudo: string | null = null;
  try {
    const r = await fetch(url, {
      headers: { Authorization: `Basic ${btoa(`${llave}:${secreto}`)}`, Accept: "application/json" },
      signal: ctrl.signal,
    });
    http = r.status;
    ms = Date.now() - inicio;
    const texto = await r.text();
    try { cuerpo = JSON.parse(texto); } catch { crudo = texto.slice(0, 200); }
  } catch (e) {
    ms = Date.now() - inicio;
    crudo = (e as Error)?.name === "AbortError" ? "WooCommerce no respondió a tiempo" : "No se pudo conectar con WooCommerce";
  } finally {
    clearTimeout(t);
  }

  const lista = Array.isArray(cuerpo) ? cuerpo : null;
  const err = esObj(cuerpo) ? cuerpo : null;
  const entra = http === 200 && !!lista;

  let conclusion: string;
  if (entra) {
    const conDropi = (lista ?? []).filter((p) => (muestraProducto(p)?.marcas_dropi ?? []).length > 0).length;
    conclusion = lista!.length === 0
      ? "Conectados con WooCommerce, pero todavía no hay ningún producto. Importa uno desde Dropi y vuelve a correr la sonda."
      : `Conectados: WooCommerce devolvió ${lista!.length} producto(s)` +
        (conDropi ? `, ${conDropi} con marca de Dropi.` : ". Ninguno trae marca de Dropi todavía.");
  } else if (http === 401) {
    conclusion = "WooCommerce rechazó las llaves (401). Revisa que la Consumer Key y el Secret sean los que generaste tú en WooCommerce → Ajustes → Avanzado → API REST, con permiso de lectura.";
  } else if (http === 404) {
    conclusion = "No se encontró la API (404). Revisa WOO_URL y que los enlaces permanentes estén en «Nombre de la entrada».";
  } else if (http === 0) {
    conclusion = crudo ?? "No se pudo conectar con WooCommerce.";
  } else {
    conclusion = `WooCommerce respondió ${http}. ${corto(err?.message) ?? crudo ?? ""}`.trim();
  }

  console.log("[woo-sonda]", JSON.stringify({ http, ms, productos: lista?.length ?? null }));

  const primero = lista?.[0];
  return json({
    conectado: entra,
    conclusion,
    http,
    ms,
    // El mensaje de WooCommerce cuando niega, sin datos nuestros.
    mensaje: corto(err?.message) ?? crudo,
    codigo: corto(err?.code, 60),
    cantidad: lista?.length ?? null,
    // Los nombres de campo reales: con esto se disena el arrastre a Campanas.
    campos_disponibles: esObj(primero) ? Object.keys(primero).sort() : [],
    muestra: (lista ?? []).map(muestraProducto),
  }, 200, c);
});
