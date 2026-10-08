// ============================================================================
// MAGANDHI · Edge Function · tienda-eventos (Metricas M1 · analitica propia, EM7)
// ----------------------------------------------------------------------------
// La llama la TIENDA, sin sesion, SOLO para visitantes que aceptaron el aviso.
//   config     {}                                        -> {activa}
//   registrar  {visitante, sesion, eventos:[{tipo, ruta, slug, origen,
//               entrada, utm_campaign, dispositivo, cuando}]}  (max 30)
//
// PRIVACIDAD Y SEGURIDAD:
//   * Verify JWT APAGADO; escribe solo por mt_registrar_eventos (service_role).
//   * La IP nunca se guarda: solo un hash con sal diaria para limitar abuso.
//   * No se guarda el navegador: el user-agent solo se mira aqui para descartar
//     bots y no sale de esta funcion.
//   * Lista blanca de campos: lo que no esta en ella se descarta antes de la
//     base (que ademas valida cada valor con CHECK).
//   * Respuestas cortas y logs sin ids de visitante, IP ni rutas.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const MAX_BYTES = 16 * 1024;
const ORIGENES = new Set(["https://magandhi.com", "https://www.magandhi.com", "https://12344-ux.github.io"]);
const BOTS = /bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview|facebookexternalhit|whatsapp|telegram|curl|wget|python|axios|node-fetch|go-http/i;
const CAMPOS = ["tipo", "ruta", "slug", "origen", "entrada", "utm_campaign", "dispositivo", "cuando"] as const;

function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ORIGENES.has(origin) ? origin : "https://magandhi.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, c: Record<string, string>) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...c, "Content-Type": "application/json; charset=utf-8" } });
const enc = new TextEncoder();
async function sha256hex(s: string) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function limpiar(e: unknown) {
  if (!e || typeof e !== "object" || Array.isArray(e)) return null;
  const o = e as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of CAMPOS) {
    const v = o[k];
    if (v === undefined || v === null || v === "") continue;
    if (k === "entrada") { out[k] = v === true; continue; }
    out[k] = String(v).slice(0, k === "ruta" ? 120 : 80);
  }
  return out.tipo ? out : null;
}

Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405, c);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !llave) return json({ error: "Configuración incompleta." }, 503, c);

  const crudo = await req.text();
  if (enc.encode(crudo).length > MAX_BYTES) return json({ error: "Demasiado grande." }, 413, c);
  let body: Record<string, unknown>;
  try { body = JSON.parse(crudo); } catch { return json({ error: "Inválido." }, 400, c); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Inválido." }, 400, c);

  const sb = createClient(supabaseUrl, llave, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${llave}`, apikey: llave } },
  });

  if (body.modo === "config") {
    const { data, error } = await sb.rpc("mt_publico_config");
    if (error) { console.error("[tienda-eventos] config", JSON.stringify({ code: error.code ?? null })); return json({ activa: false }, 200, c); }
    return json({ activa: !!(data as { activa?: boolean })?.activa }, 200, c);
  }
  if (body.modo !== "registrar") return json({ error: "Modo inválido." }, 400, c);

  // Bots: se responde 202 sin registrar (no se les da pistas).
  if (BOTS.test(req.headers.get("user-agent") ?? "")) return json({ ok: true }, 202, c);

  const eventos = (Array.isArray(body.eventos) ? body.eventos : []).slice(0, 30).map(limpiar).filter(Boolean);
  if (!eventos.length) return json({ error: "Sin eventos." }, 400, c);

  const ip = (req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || (req.headers.get("x-forwarded-for") ?? "").split(",")[0] || "").trim() || "desconocida";
  const sal = Deno.env.get("EM_IP_SAL") ?? llave;
  const ipHash = await sha256hex(`${sal}|eventos|${new Date().toISOString().slice(0, 10)}|${ip}`);

  const { data, error } = await sb.rpc("mt_registrar_eventos", {
    p_visitante: String(body.visitante ?? "").slice(0, 40), p_sesion: String(body.sesion ?? "").slice(0, 40), p_eventos: eventos, p_ip_hash: ipHash,
  });
  if (error) {
    const m = error.message ?? "";
    if (/MT_ANALITICA_APAGADA/.test(m)) return json({ ok: false, apagada: true }, 409, c);
    if (/MT_DEMASIADOS_EVENTOS/.test(m)) return json({ ok: false }, 429, c);
    if (/MT_(VISITANTE|EVENTOS)_INVALID/.test(m)) return json({ error: "Inválido." }, 400, c);
    console.error("[tienda-eventos] registrar", JSON.stringify({ code: error.code ?? null, message: m.slice(0, 120) }));
    return json({ ok: false }, 500, c);
  }
  const r = data as { aceptados?: number; descartados?: number };
  return json({ ok: true, aceptados: r?.aceptados ?? 0 }, 200, c);
});
