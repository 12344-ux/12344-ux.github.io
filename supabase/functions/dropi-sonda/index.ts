// ============================================================================
// MAGANDHI · Edge Function · dropi-sonda (Dropshipping · D1)
// ----------------------------------------------------------------------------
// La puerta de SOLO LECTURA entre el panel interno y el catálogo de Dropi.
//
// D1 amplía la sonda diagnóstica original, pero no cambia su línea roja:
//   · GET categories/                    -> verifica que el token entra
//   · POST products/index                -> busca / pagina catálogo (POST
//                                            porque la ruta recibe filtros;
//                                            NO crea nada)
//   · GET products/v2/{id}               -> ficha + stock por bodega
//   · GET products/{id}                  -> diagnóstico (hoy responde 400;
//                                            nunca se usa como fuente de stock)
//
// No llama orders/*, no escribe en Supabase, no guarda la respuesta y no
// descarga imágenes. Las fotos que devuelve son URLs HTTPS de PREVIEW para la
// bandeja PRIVADA: D2 volverá a leer la ficha por id y recién entonces podrá
// descargar las seleccionadas al bucket propio `campanas`.
//
// Body read-only:
//   { buscar?: string, producto_id?: number|string, inicio?: number,
//     tamano?: number }
//   - buscar: hasta 60 caracteres.
//   - inicio: offset 0..1200 (default 0).
//   - tamano: 1..48 (default 5). Límites intencionales: cada página es un clic
//     humano; el panel no recorre ni replica el catálogo completo.
//
// Ajuste de uso real D1 (10-oct-2026, reporte del dueño):
//   · Fotos: Dropi NO manda URLs absolutas. Cada foto es un objeto con `urlS3`
//     (ruta relativa a su CDN) o, en registros viejos, `url` (relativa a
//     api.dropi.co). Lo confirma el plugin Dropify v4.7.3 (Product_List.php y
//     ProductsModel.php). Antes se esperaba una URL https completa y por eso
//     ninguna tarjeta mostraba foto.
//   · Paginación: el `count` de products/index no es confiable (en la cuenta
//     real llegó 0 con resultados; el plugin tampoco lo usa y fija 9999). Se
//     pide UN producto de más: si llega, hay página siguiente.
//
// Quien puede llamarla: usuario con sesión y rol admin en perfiles.
// Verify JWT: ENCENDIDO.
//
// LÍNEA ROJA: DROPI_TOKEN solo vive en Edge Functions → Secrets. Nunca se
// devuelve ni se loguea. Ningún dato de cliente entra a esta función.
// Diseño: docs/dropshipping-envios/DROPI.md y .kiro/steering/dropshipping-magandhi.md.
// ============================================================================

const BASE = (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/").replace(/\/*$/, "/");
const ESPERA_MS = 15000;

// Ventana de paginación. Se pide `tamano + 1` a Dropi para saber si hay más.
const TAMANO_MAX = 48;
const INICIO_MAX = 1200;

// Dónde viven las fotos de Dropi Colombia, según el plugin oficial:
//   foto.urlS3 -> CDN de S3 (lo normal)
//   foto.url   -> ruta relativa al API (registros viejos)
// Solo se arman URLs sobre ESTOS dos orígenes: una ruta relativa nunca puede
// terminar apuntando a otro host.
const CDN_FOTOS = "https://d39ru7awumhhs2.cloudfront.net/";
const BASE_FOTOS_ANTIGUAS = "https://api.dropi.co/";

// MEDIDO el 9-oct-2026 con dropi-cabeceras: Dropi responde 401 "Access denied"
// sin User-Agent y 200 a la misma petición con uno. Se lee POR PETICIÓN para
// cambiarlo por Secret sin redesplegar. El valor por defecto se identifica con
// honestidad; nunca se finge ser WordPress u otro programa.
const ua = () => (Deno.env.get("DROPI_USER_AGENT") ?? "MAGANDHI-Impulse/1.0 (+https://magandhi.com)").trim();

const ORIGENES = new Set([
  "https://montaguth.institute",
  "https://www.montaguth.institute",
  "https://12344-ux.github.io",
]);
function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ORIGENES.has(origin) ? origin : "https://montaguth.institute",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, c: Record<string, string>) =>
  new Response(JSON.stringify(b, null, 2), {
    status: s,
    headers: { ...c, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

type Obj = Record<string, unknown>;
const esObj = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);
const corto = (v: unknown, n = 200) => (v === undefined || v === null ? null : String(v).slice(0, n));

// Número entero dentro de límites. Un input mal formado vuelve al default, no
// se interpreta como página/offset arbitrario contra un proveedor externo.
function enteroAcotado(v: unknown, minimo: number, maximo: number, defecto: number) {
  const n = typeof v === "number" ? v : typeof v === "string" && /^\d+$/.test(v) ? Number(v) : NaN;
  return Number.isInteger(n) && n >= minimo && n <= maximo ? n : defecto;
}

// URL de imagen aceptable SOLO para preview interno. D2 nunca confía en esta
// URL para descargar: vuelve a consultar Dropi por id y valida de nuevo en la
// Edge Function de importación. No se aceptan http, credenciales o URLs largas.
function urlPreview(v: unknown): string | null {
  if (typeof v !== "string" || v.length === 0 || v.length > 500) return null;
  try {
    const u = new URL(v);
    if (u.protocol !== "https:" || u.username || u.password) return null;
    return u.href;
  } catch {
    return null;
  }
}

// Ruta relativa de Dropi -> URL completa SOLO sobre el origen indicado. Si la
// ruta trae otro host (`//otro.com/x`, `https://otro.com/x`), se descarta: el
// resultado tiene que quedar en el mismo origen de la base.
function urlEnOrigen(ruta: unknown, base: string): string | null {
  if (typeof ruta !== "string") return null;
  const s = ruta.trim();
  if (!s || s.length > 400) return null;
  try {
    const u = new URL(s, base);
    if (u.origin !== new URL(base).origin) return null;
    return urlPreview(u.href);
  } catch {
    return null;
  }
}

// `url` puede llegar absoluta (https) o relativa al API, según la antigüedad
// del registro. Absoluta -> se valida tal cual; relativa -> api.dropi.co.
function urlAbsolutaORelativa(v: unknown): string | null {
  if (typeof v !== "string") return null;
  return /^[a-z][a-z0-9+.-]*:/i.test(v.trim()) ? urlPreview(v.trim()) : urlEnOrigen(v, BASE_FOTOS_ANTIGUAS);
}

function fotoDe(v: unknown): string | null {
  if (typeof v === "string") return urlAbsolutaORelativa(v);
  if (!esObj(v)) return null;
  // Forma real de Dropi primero (urlS3 en su CDN, url relativa al API); los
  // demás nombres quedan como tolerancia. Nunca se adivina una URL.
  return urlEnOrigen(v.urlS3, CDN_FOTOS) ?? urlAbsolutaORelativa(v.url) ??
    urlPreview(v.src) ?? urlPreview(v.image) ?? urlPreview(v.image_url) ?? null;
}

// El listado (products/index) trae `gallery`; la ficha (products/v2) trae
// `photos`. Se leen ambas, sin duplicar, porque una puede venir vacía.
function fotosPreview(p: Obj) {
  const fuente = [p.gallery, p.photos, p.images].flatMap((x) => Array.isArray(x) ? x : []);
  const vistas: string[] = [];
  for (const x of fuente) {
    const u = fotoDe(x);
    if (u && !vistas.includes(u)) vistas.push(u);
    if (vistas.length === 12) break;
  }
  return vistas;
}

function resumirVariaciones(p: Obj) {
  if (!Array.isArray(p.variations)) return [];
  return p.variations.slice(0, 30).map((v) => {
    if (!esObj(v)) return null;
    return {
      // D1 los muestra solo como diagnóstico. No se usa este valor para pedir
      // nada: D2 medirá el contrato exacto de variante antes de crear orders/.
      id: corto(v.id ?? v.variation_id ?? v.product_variation_id, 80),
      nombre: corto(v.name ?? v.title ?? v.label ?? v.value, 140),
      sku: corto(v.sku, 80),
      precio_proveedor: v.sale_price ?? v.price ?? null,
      precio_sugerido: v.suggested_price ?? null,
      stock: typeof v.stock === "number" ? v.stock : null,
      fotos_remotas: fotosPreview(v),
    };
  }).filter(Boolean);
}

// Una llamada a Dropi con tiempo límite. Nunca lanza: devuelve qué pasó sin
// incluir el token ni el cuerpo sensible en logs/respuesta.
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
    return {
      http: r.status,
      ms: Date.now() - inicio,
      j: esObj(j) ? j : null,
      crudo: esObj(j) ? null : texto.slice(0, 200),
    };
  } catch (e) {
    const abortado = (e as Error)?.name === "AbortError";
    return {
      http: 0,
      ms: Date.now() - inicio,
      j: null,
      crudo: abortado ? "Dropi no respondio a tiempo" : "No se pudo conectar con Dropi",
    };
  } finally {
    clearTimeout(t);
  }
}

// Resumen seguro de la respuesta, sin copiar todo lo que mande Dropi.
function resumir(r: Awaited<ReturnType<typeof llamarDropi>>) {
  const j = r.j ?? {};
  const objetos = Array.isArray(j.objects) ? j.objects : null;
  // Al pedir UN producto por id, Dropi devuelve `objects` como objeto suelto,
  // no como lista. Se conserva aparte para la ficha.
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
  Array.isArray(filas)
    ? filas.reduce((s, w) => s + (esObj(w) ? Number(w.stock) || 0 : 0), 0)
    : null;

// Lo que sirve para la bandeja privada. Si Dropi omite un campo, sale null;
// nunca se inventa. `fotos_remotas` sigue siendo URL externa temporal, no una
// key de Storage MAGANDHI.
function muestraProducto(p: unknown) {
  if (!esObj(p)) return null;
  const variaciones = Array.isArray(p.variations) ? p.variations : [];
  const cats = Array.isArray(p.categories)
    ? p.categories.map((c) => esObj(c) ? corto(c.name, 60) : null).filter(Boolean)
    : [];
  const prov = esObj(p.user) ? p.user : null;
  // MEDIDO el 9-oct-2026: GET products/{id} responde 400 «No tiene permisos»;
  // la ficha products/v2 ya trae warehouse_product. De ahí sale el stock.
  const bodegas = Array.isArray(p.warehouse_product)
    ? p.warehouse_product.map((w) => esObj(w)
      ? { bodega_id: w.warehouse_id ?? w.id ?? null, stock: Number(w.stock) || 0 }
      : null).filter(Boolean)
    : [];
  return {
    id: p.id ?? null,
    nombre: corto(p.name, 120),
    sku: corto(p.sku, 60),
    tipo: corto(p.type, 20),
    activo: p.active ?? null,
    privado: p.privated_product ?? null,
    precio_proveedor: p.sale_price ?? null,
    precio_sugerido: p.suggested_price ?? null,
    stock: typeof p.stock === "number" ? p.stock : sumarStock(p.warehouse_product),
    bodegas,
    variaciones: variaciones.length,
    detalle_variaciones: resumirVariaciones(p),
    categorias: cats,
    fotos: fotosPreview(p).length,
    fotos_remotas: fotosPreview(p),
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

  // 1) Usuario real con sesión...
  const ru = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey, Authorization: `Bearer ${jwt}` },
  });
  const usuario = ru.ok ? await ru.json().catch(() => null) : null;
  if (!usuario?.id) return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, c);

  // ...y admin. D1 no abre la API externa a perfiles reducidos: D3 debe cerrar
  // permisos por capacidad antes del primer usuario no-admin.
  const rp = await fetch(`${supabaseUrl}/rest/v1/perfiles?select=rol&id=eq.${encodeURIComponent(usuario.id)}`, {
    headers: { apikey, Authorization: `Bearer ${jwt}`, Accept: "application/json" },
  });
  const perfiles = rp.ok ? await rp.json().catch(() => []) : [];
  if (!Array.isArray(perfiles) || perfiles[0]?.rol !== "admin") {
    return json({ error: "Solo un administrador puede consultar Dropi en D1." }, 403, c);
  }

  // 2) El token queda solo dentro del runtime.
  const token = (Deno.env.get("DROPI_TOKEN") ?? "").trim();
  if (!token) {
    return json({
      conectado: false,
      conclusion: "Falta el secreto DROPI_TOKEN en Edge Functions → Secrets.",
    }, 200, c);
  }

  // JSON válido `null`/array no es un objeto de filtros: se degrada a la
  // búsqueda vacía en vez de lanzar al intentar leer body.buscar.
  let leido: unknown = {};
  try { leido = await req.json(); } catch { /* sin cuerpo: búsqueda vacía */ }
  const body: Obj = esObj(leido) ? leido : {};
  const buscar = corto(body.buscar, 60) ?? "";
  const inicio = enteroAcotado(body.inicio, 0, INICIO_MAX, 0);
  const tamano = enteroAcotado(body.tamano, 1, TAMANO_MAX, 5);

  // Un id concreto: el embudo real. Se lee SOLO ese producto; no se recorre el
  // catálogo completo. Una variante sigue siendo diagnóstico en D1.
  const idCrudo = body.producto_id;
  const productoId = typeof idCrudo === "number" ||
    (typeof idCrudo === "string" && /^\d{1,12}$/.test(idCrudo))
    ? String(idCrudo)
    : null;

  // 3) Las dos consultas de catálogo, estrictamente read-only.
  const cat = resumir(await llamarDropi("GET", "categories/", token));
  const prod = resumir(await llamarDropi("POST", "products/index", token, {
    startData: inicio,
    // Uno de más: si Dropi lo devuelve, hay página siguiente. No se muestra.
    pageSize: tamano + 1,
    order_type: "desc",
    order_by: "id",
    keywords: buscar,
    active: true,
    no_count: false,
    integration: true,
    get_stock: false,
  }));

  // 3 bis) Si vino un id, se mide la ficha por las dos rutas conocidas. La
  // simple permanece solo como evidencia de que no sirve; products/v2 es la
  // fuente actual de ficha + bodegas.
  const detalle = productoId
    ? resumir(await llamarDropi("GET", `products/v2/${productoId}`, token))
    : null;
  const stock = productoId
    ? resumir(await llamarDropi("GET", `products/${productoId}`, token))
    : null;

  const entra = cat.isSuccess === true || prod.isSuccess === true;
  const negado = [cat, prod].some((r) => r.http === 401 || /access denied/i.test(r.mensaje ?? ""));
  const ip = cat.ip_vista_por_dropi ?? prod.ip_vista_por_dropi;

  const unProducto = (r: typeof detalle) => r ? (r.objeto ?? r.objetos?.[0] ?? null) : null;
  const fichaDetalle = unProducto(detalle);
  const fichaStock = unProducto(stock);

  let conclusion: string;
  if (entra) {
    conclusion = productoId
      ? (detalle?.isSuccess === true
        ? `Conectados: el producto ${productoId} se leyó directo desde Dropi. La ficha y sus bodegas salen de products/v2; aún no se creó ningún producto, campaña, reserva ni pedido.`
        : `Conectados al catálogo, pero la ficha del producto ${productoId} no se pudo leer. Revisa que el id exista en Dropi.`)
      : "Conectados: Dropi aceptó el token desde Supabase. Esta consulta es de solo lectura; puedes buscar, cambiar página o abrir una ficha por id.";
  } else if (negado) {
    conclusion = ip
      ? `Dropi negó el acceso. Llegamos desde la IP ${ip} con el User-Agent «${ua()}». Si antes funcionaba, revisa el secreto DROPI_USER_AGENT.`
      : "Dropi negó el acceso (token no aceptado). Revisa que el secreto sea el token de la integración autenticada.";
  } else {
    conclusion = "Dropi respondió algo inesperado. Comparte este resultado sin incluir secretos.";
  }

  const primero = prod.objetos?.[0];
  const pagina = (prod.objetos ?? []).slice(0, tamano);
  const hayMas = (prod.objetos?.length ?? 0) > tamano;
  const siguiente = inicio + tamano;
  // El `count` de Dropi solo se cree si cuadra con lo que se ve: llegó 0 con
  // resultados en la cuenta real. Si no cuadra, no se informa un total.
  const totalCreible = prod.total !== null && prod.total > 0 &&
      prod.total >= inicio + pagina.length && (hayMas ? prod.total > siguiente : true)
    ? prod.total
    : null;
  console.log("[dropi-sonda]", JSON.stringify({
    categorias: cat.http,
    productos: prod.http,
    entra,
    inicio,
    tamano,
    productoId: productoId ?? null,
  }));

  return json({
    conectado: entra,
    conclusion,
    user_agent_usado: ua(),
    busqueda: buscar || null,
    consulta: {
      inicio,
      tamano,
      hay_mas: hayMas,
      siguiente_inicio: hayMas && siguiente <= INICIO_MAX ? siguiente : null,
      // Hay más resultados, pero la ventana de páginas terminó: conviene
      // afinar la palabra en vez de seguir pasando páginas.
      limite_alcanzado: hayMas && siguiente > INICIO_MAX,
      anterior_inicio: inicio > 0 ? Math.max(0, inicio - tamano) : null,
    },
    // Lo que decide el frente: ¿podemos leer la ficha/stock de un candidato
    // desde Dropi cuando queramos, sin intermediario ni catálogo duplicado?
    producto: productoId ? {
      id_pedido: productoId,
      detalle: { http: detalle?.http ?? null, isSuccess: detalle?.isSuccess ?? null, mensaje: detalle?.mensaje ?? null },
      // Esperado hoy: 400. Queda visible para no volver a apoyarse en ella.
      ruta_stock_aparte: { http: stock?.http ?? null, isSuccess: stock?.isSuccess ?? null, mensaje: stock?.mensaje ?? null },
      campos_detalle: esObj(fichaDetalle) ? Object.keys(fichaDetalle).sort() : [],
      ficha: muestraProducto(fichaDetalle),
      existencias: muestraProducto(fichaStock),
      leido: new Date().toISOString(),
    } : null,
    categorias: {
      http: cat.http,
      ms: cat.ms,
      isSuccess: cat.isSuccess,
      mensaje: cat.mensaje,
      ip_vista_por_dropi: cat.ip_vista_por_dropi,
      cantidad: cat.cantidad,
      nombres: (cat.objetos ?? []).slice(0, 15).map((o) => esObj(o) ? corto(o.name, 60) : null),
    },
    productos: {
      http: prod.http,
      ms: prod.ms,
      isSuccess: prod.isSuccess,
      mensaje: prod.mensaje,
      ip_vista_por_dropi: prod.ip_vista_por_dropi,
      cantidad: pagina.length,
      total: totalCreible,
      // Lo que Dropi mandó en `count`, sin interpretar: diagnóstico.
      total_reportado_por_dropi: prod.total,
      campos_disponibles: esObj(primero) ? Object.keys(primero).sort() : [],
      muestra: pagina.map(muestraProducto),
    },
  }, 200, c);
});
