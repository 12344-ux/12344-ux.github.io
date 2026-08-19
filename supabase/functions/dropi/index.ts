// ============================================================
// Montaguth · Puente con la API de Dropi (proveedor)
//
// POR QUÉ EXISTE (seguridad): la API de Dropi se autentica con un token de la
// cuenta del dueño (header `dropi-integration-key`). Ese token NO puede vivir en
// el frontend, ni en el repo, ni pasearse por un chat: con él se ve el catálogo,
// los precios de proveedor y —a futuro— se crean pedidos. Vive SOLO en Supabase
// Secrets (`DROPI_TOKEN`) y se usa exclusivamente aquí, del lado del servidor.
//
// PRINCIPIO DE MENOR PRIVILEGIO (importante, y a propósito): esta función NO usa
// el `LINK_SECRET` del tablero. Usa un secreto propio, `DROPI_LINK_KEY`.
//   · el LINK_SECRET abre TODOS los datos de clientes (pedidos, correos, opiniones);
//   · esta función solo lee catálogo de proveedor.
// Darle el LINK_SECRET sería regalar acceso de más para una tarea que no lo necesita.
// Además `DROPI_LINK_KEY` se puede ROTAR sin tocar nada del resto del sistema.
//
// De dónde salen el endpoint y los parámetros: no hay documentación pública de la
// API de Dropi, pero su plugin oficial de WooCommerce es código abierto
// (wordpress.org/plugins/wc-dropi-integration) y ahí está el contrato real:
//   POST {API}/products/index   header `dropi-integration-key`
//   body { startData, pageSize, order_type, order_by, keywords, active,
//          no_count, integration, get_stock, category?, warehouse_id?,
//          stockmayor?, notNulldescription?, userVerified? }
//   respuesta { isSuccess, objects: [...], message, status, count }
// Verificado en vivo: sin token válido responde 401 {"message":"Access denied"}.
//
// MODOS (todos exigen ?key=DROPI_LINK_KEY):
//   GET ?selftest=1            -> ¿está configurado el token? (no lo expone) + ping a Dropi
//   GET ?muestra=1             -> UN producto con TODOS sus campos crudos.
//                                 Sirve para descubrir el esquema real antes de normalizar.
//   GET ?catalogo=1&pagina=0&tam=50&buscar=&categoria=&bodega=&con_stock=1
//                              -> catálogo paginado y NORMALIZADO para analizar márgenes
//
// Verify JWT: OFF (la autorización la da DROPI_LINK_KEY, validado dentro del código).
// ============================================================

const PAIS_API: Record<string, string> = {
  co: "https://api.dropi.co/integrations",
  mx: "https://api.dropi.mx/integrations",
  pe: "https://api.dropi.pe/integrations",
  cl: "https://api.dropi.cl/integrations",
  ec: "https://api.dropi.ec/integrations",
  pa: "https://api.dropi.pa/integrations",
  es: "https://api.dropi.com.es/integrations",
  py: "https://api.dropi.com.py/integrations",
  ar: "https://api.dropi.ar/integrations",
  cr: "https://api.dropi.cr/integrations",
};

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "*",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

function base(): string {
  const pais = (Deno.env.get("DROPI_PAIS") || "co").toLowerCase();
  return PAIS_API[pais] || PAIS_API.co;
}

/** Llama a la API de Dropi con el token del servidor. Nunca devuelve el token. */
async function dropi(ruta: string, cuerpo: Record<string, unknown>) {
  const token = Deno.env.get("DROPI_TOKEN");
  if (!token) throw new Error("Falta configurar el secreto DROPI_TOKEN en Supabase.");
  const r = await fetch(`${base()}/${ruta}`, {
    method: "POST",
    headers: {
      "content-type": "application/json;charset=UTF-8",
      "dropi-integration-key": token,
    },
    body: JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let datos: any = null;
  try { datos = JSON.parse(texto); } catch { /* Dropi devolvió algo que no es JSON */ }
  if (!r.ok) {
    // 401 = token inválido o vencido. Mensaje claro, sin filtrar el token.
    throw new Error(`Dropi respondió ${r.status}: ${(datos?.message || texto || "").slice(0, 200)}`);
  }
  return datos;
}

/** Primer número válido entre varios alias posibles (el esquema de Dropi no está documentado). */
function num(obj: any, ...alias: string[]): number | null {
  for (const k of alias) {
    const v = obj?.[k];
    if (v === null || v === undefined || v === "") continue;
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function texto(obj: any, ...alias: string[]): string | null {
  for (const k of alias) {
    const v = obj?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return null;
}

/**
 * Normaliza un producto a lo que de verdad necesitamos para decidir:
 * cuánto cuesta, a cuánto se sugiere venderlo, cuánto deja y si hay stock.
 * Tolerante a alias porque el esquema no está documentado (usa ?muestra=1 para verlo crudo).
 */
function normalizar(p: any) {
  const costo = num(p, "price", "cost", "precio", "provider_price", "wholesale_price");
  const sugerido = num(p, "suggested_price", "sale_price", "suggestedPrice", "price_suggested", "public_price");
  const utilidad = (costo !== null && sugerido !== null) ? sugerido - costo : null;
  const margen = (utilidad !== null && sugerido) ? Math.round((utilidad / sugerido) * 1000) / 10 : null;
  const galeria = Array.isArray(p?.gallery)
    ? p.gallery.map((g: any) => (typeof g === "string" ? g : g?.url || g?.urlS3 || null)).filter(Boolean)
    : [];
  return {
    id: p?.id ?? null,
    nombre: texto(p, "name", "nombre", "title"),
    sku: texto(p, "sku", "code", "reference"),
    costo_proveedor: costo,
    precio_sugerido: sugerido,
    utilidad_bruta: utilidad,
    margen_pct: margen,
    stock: num(p, "stock", "quantity", "available_stock"),
    categoria: texto(p?.categories?.[0] || p?.category || {}, "name", "nombre") || texto(p, "category_name"),
    bodega: texto(p?.warehouse || {}, "name", "nombre") || texto(p, "warehouse_name"),
    proveedor: texto(p?.user || p?.provider || {}, "name", "store_name", "nombre"),
    descripcion: (texto(p, "description", "descripcion") || "").slice(0, 400) || null,
    imagenes: galeria.slice(0, 4),
    imagenes_total: galeria.length,
    variaciones: Array.isArray(p?.variations) ? p.variations.length : 0,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") return json({ error: "Usa GET." }, 405);

  const url = new URL(req.url);
  const LLAVE = Deno.env.get("DROPI_LINK_KEY") || "";
  if (!LLAVE) return json({ error: "Falta configurar DROPI_LINK_KEY." }, 500);
  if (url.searchParams.get("key") !== LLAVE) return json({ error: "No autorizado." }, 403);

  // ---------- AUTOPRUEBA ----------
  // Confirma configuración y conectividad SIN revelar el token.
  if (url.searchParams.get("selftest") === "1") {
    const tieneToken = !!Deno.env.get("DROPI_TOKEN");
    let ping: string;
    try {
      const d = await dropi("products/index", {
        startData: 0, pageSize: 1, order_type: "desc", order_by: "id",
        keywords: "", active: true, no_count: true, integration: true, get_stock: false,
      });
      ping = d?.isSuccess ? "ok" : `respuesta inesperada: ${String(d?.message || "").slice(0, 120)}`;
    } catch (e) {
      ping = "error: " + (e as Error).message;
    }
    return json({ ok: tieneToken && ping === "ok", token_configurado: tieneToken, api: base(), ping });
  }

  // ---------- MUESTRA CRUDA (para descubrir el esquema real) ----------
  if (url.searchParams.get("muestra") === "1") {
    try {
      const d = await dropi("products/index", {
        startData: 0, pageSize: 1, order_type: "desc", order_by: "id",
        keywords: url.searchParams.get("buscar") || "",
        active: true, no_count: true, integration: true, get_stock: false,
      });
      const p = d?.objects?.[0] ?? null;
      return json({
        ok: !!p,
        campos: p ? Object.keys(p).sort() : [],
        crudo: p,
        normalizado: p ? normalizar(p) : null,
      });
    } catch (e) {
      return json({ error: (e as Error).message }, 502);
    }
  }

  // ---------- CATÁLOGO NORMALIZADO ----------
  if (url.searchParams.get("catalogo") === "1") {
    const pagina = Math.max(0, parseInt(url.searchParams.get("pagina") || "0", 10) || 0);
    const tam = Math.min(100, Math.max(1, parseInt(url.searchParams.get("tam") || "50", 10) || 50));
    const cuerpo: Record<string, unknown> = {
      startData: pagina * tam,
      pageSize: tam,
      order_type: url.searchParams.get("orden") || "desc",
      order_by: url.searchParams.get("ordenar_por") || "id",
      keywords: url.searchParams.get("buscar") || "",
      active: true,
      no_count: true,
      integration: true,
      get_stock: false,
    };
    if (url.searchParams.get("categoria")) cuerpo.category = url.searchParams.get("categoria");
    if (url.searchParams.get("bodega")) cuerpo.warehouse_id = url.searchParams.get("bodega");
    if (url.searchParams.get("con_stock") === "1") cuerpo.stockmayor = 1;
    if (url.searchParams.get("con_descripcion") === "1") cuerpo.notNulldescription = true;
    if (url.searchParams.get("verificados") === "1") cuerpo.userVerified = true;

    try {
      const d = await dropi("products/index", cuerpo);
      const objetos: any[] = Array.isArray(d?.objects) ? d.objects : [];
      return json({
        ok: true,
        pagina,
        tam,
        devueltos: objetos.length,
        productos: objetos.map(normalizar),
      });
    } catch (e) {
      return json({ error: (e as Error).message }, 502);
    }
  }

  return json({
    error: "Indica un modo.",
    modos: ["?selftest=1", "?muestra=1", "?catalogo=1&pagina=0&tam=50&buscar=&con_stock=1"],
  }, 400);
});
