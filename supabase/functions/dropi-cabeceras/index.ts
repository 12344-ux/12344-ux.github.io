// ============================================================================
// MAGANDHI · Edge Function · dropi-cabeceras (Dropshipping · fase 0)
// ----------------------------------------------------------------------------
// POR QUE EXISTE: el 9-oct-2026 quedo demostrado que el token SI puede leer el
// catalogo de Dropi. El plugin de WooCommerce, desde el servidor de un sandbox,
// lista miles de productos con el MISMO token y el MISMO endpoint que nuestra
// sonda, a la que Dropi responde 401 desde Supabase y desde un PC.
//
// Si el token sirve, el problema no es el permiso: es COMO llamamos. Esta
// funcion prueba varias combinaciones de cabeceras en una sola corrida y dice
// cual devuelve 200. Imita al plugin (User-Agent de WordPress) y a una
// integracion de terceros documentada (Origin y Referer con el dominio de la
// tienda registrada en Dropi).
//
// SOLO LECTURA Y DESECHABLE. Repite la MISMA consulta de catalogo con distintas
// cabeceras: nunca llama a orders/, no escribe en la base y no guarda nada.
// Cuando sepamos que cabeceras hacen falta, esto se borra y se corrige
// dropi-sonda.
//
// Quien puede llamarla: un usuario con sesion y rol 'admin' en perfiles.
// Verify JWT: ENCENDIDO. DROPI_TOKEN solo en Secrets; nunca sale en la
// respuesta ni en los logs.
// ============================================================================

const BASE = (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/").replace(/\/*$/, "/");
const ESPERA_MS = 15000;
const PAUSA_MS = 350; // no martillar la API de un tercero

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
const corto = (v: unknown, n = 160) => (v === undefined || v === null ? null : String(v).slice(0, n));
const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

// El mismo cuerpo que manda el plugin al listar el catalogo. Es una CONSULTA,
// aunque el verbo sea POST.
const CUERPO_LISTA = {
  startData: 0,
  pageSize: 3,
  order_type: "desc",
  order_by: "id",
  keywords: "",
  active: true,
  no_count: true,
  integration: true,
  get_stock: false,
};

// Una sola llamada. Nunca lanza: devuelve lo que paso.
async function probar(nombre: string, extra: Record<string, string>) {
  const token = (Deno.env.get("DROPI_TOKEN") ?? "").trim();
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ESPERA_MS);
  const inicio = Date.now();
  try {
    const r = await fetch(BASE + "products/index", {
      method: "POST",
      headers: {
        "Content-Type": "application/json;charset=UTF-8",
        "dropi-integration-key": token,
        Accept: "application/json",
        ...extra,
      },
      body: JSON.stringify(CUERPO_LISTA),
      signal: ctrl.signal,
    });
    const texto = await r.text();
    let j: unknown = null;
    try { j = JSON.parse(texto); } catch { /* no era JSON */ }
    const o = esObj(j) ? j : {};
    const objetos = Array.isArray(o.objects) ? o.objects : null;
    return {
      variante: nombre,
      cabeceras_extra: Object.keys(extra),
      http: r.status,
      ms: Date.now() - inicio,
      isSuccess: o.isSuccess ?? null,
      mensaje: corto(o.message) || corto(o.error) || (esObj(j) ? null : texto.slice(0, 160)),
      // Dropi devuelve la IP de origen cuando niega el acceso.
      ip_vista_por_dropi: corto(o.ip, 60),
      productos: objetos ? objetos.length : null,
      entra: o.isSuccess === true,
    };
  } catch (e) {
    const abortado = (e as Error)?.name === "AbortError";
    return {
      variante: nombre,
      cabeceras_extra: Object.keys(extra),
      http: 0,
      ms: Date.now() - inicio,
      isSuccess: null,
      // Deno puede rechazar una cabecera reservada: eso tambien es un dato.
      mensaje: abortado ? "Dropi no respondio a tiempo" : corto((e as Error)?.message) ?? "No se pudo conectar",
      ip_vista_por_dropi: null,
      productos: null,
      entra: false,
    };
  } finally {
    clearTimeout(t);
  }
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

  const ru = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey, Authorization: `Bearer ${jwt}` } });
  const usuario = ru.ok ? await ru.json().catch(() => null) : null;
  if (!usuario?.id) return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, c);

  const rp = await fetch(`${supabaseUrl}/rest/v1/perfiles?select=rol&id=eq.${encodeURIComponent(usuario.id)}`, {
    headers: { apikey, Authorization: `Bearer ${jwt}`, Accept: "application/json" },
  });
  const perfiles = rp.ok ? await rp.json().catch(() => []) : [];
  if (!Array.isArray(perfiles) || perfiles[0]?.rol !== "admin") {
    return json({ error: "Solo un administrador puede usar el diagnóstico de Dropi." }, 403, c);
  }

  if (!(Deno.env.get("DROPI_TOKEN") ?? "").trim()) {
    return json({ conectado: false, conclusion: "Falta el secreto DROPI_TOKEN en Edge Functions → Secrets." }, 200, c);
  }

  // La tienda registrada en Dropi. Es lo que el plugin tiene como dominio y lo
  // que una integracion de terceros documentada envia en Origin y Referer.
  let body: Obj = {};
  try { body = await req.json(); } catch { /* sin cuerpo */ }
  const tienda = (corto(body.tienda, 120) ?? Deno.env.get("DROPI_TIENDA_URL") ?? "").trim().replace(/\/+$/, "");
  const faltaTienda = !/^https?:\/\//i.test(tienda);

  // Imita al plugin: WordPress se presenta asi al hacer wp_remote_post.
  const UA_WP = `WordPress/6.8; ${tienda || "https://magandhi.com"}`;

  const variantes: Array<[string, Record<string, string>]> = [
    ["1 · como hoy (solo el token)", {}],
    ["2 · + User-Agent de WordPress", { "User-Agent": UA_WP }],
    ...(faltaTienda ? [] : [
      ["3 · + Origin y Referer de la tienda", { Origin: tienda, Referer: tienda + "/" }] as [string, Record<string, string>],
      ["4 · + User-Agent, Origin y Referer", { "User-Agent": UA_WP, Origin: tienda, Referer: tienda + "/" }] as [string, Record<string, string>],
    ]),
    ["5 · + User-Agent de navegador", { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }],
  ];

  const resultados = [];
  for (const [nombre, extra] of variantes) {
    resultados.push(await probar(nombre, extra));
    await dormir(PAUSA_MS);
  }

  const gano = resultados.find((r) => r.entra);
  const ip = resultados.map((r) => r.ip_vista_por_dropi).find(Boolean) ?? null;

  let conclusion: string;
  if (gano) {
    conclusion = `Encontrado: la variante «${gano.variante}» entró. Lo que faltaba son estas cabeceras: ${gano.cabeceras_extra.join(", ") || "ninguna"}. Con esto se corrige dropi-sonda y no hace falta WooCommerce.`;
  } else if (faltaTienda) {
    conclusion = "Ninguna variante entró, pero no se probaron Origin ni Referer porque falta la URL de la tienda registrada en Dropi. Vuelve a correrla pasando { tienda: 'https://...' }.";
  } else {
    conclusion = ip
      ? `Ninguna variante entró. Dropi nos ve desde la IP ${ip}. Como el token sí funciona desde el servidor del sandbox, el filtro es por IP o por algo más del entorno: toca pedirle a soporte que autorice el acceso.`
      : "Ninguna variante entró y Dropi no devolvió la IP. Pásale este resultado a Kiro.";
  }

  console.log("[dropi-cabeceras]", JSON.stringify(resultados.map((r) => ({ v: r.variante, http: r.http, entra: r.entra }))));

  return json({
    conectado: !!gano,
    conclusion,
    tienda_usada: faltaTienda ? null : tienda,
    ip_vista_por_dropi: ip,
    variantes: resultados,
  }, 200, c);
});
