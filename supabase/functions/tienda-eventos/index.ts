// ============================================================================
// MAGANDHI · Edge Function · tienda-eventos (Métricas M1 + Sistema Nervioso SN1)
// ----------------------------------------------------------------------------
// La llama la TIENDA, sin sesión obligatoria.
//   config     {} -> {activa: boolean, politica_version: string | null}
//                puede consultarse antes de decidir; activa solo puede ser true
//                con una versión de política válida.
//   registrar  {visitante, sesion, politica_version, eventos:[...]} (máximo 30)
//                SOLO después de aceptar la politica_version vigente; la Edge
//                y la transacción vuelven a exigir esa misma versión.
//
// PRIVACIDAD Y SEGURIDAD:
//   * Verify JWT APAGADO; escribe solo por mt_registrar_eventos (service_role).
//   * La IP nunca se guarda: solo un hash con sal diaria para limitar abuso.
//   * No se guarda el navegador: el user-agent solo descarta bots.
//   * Lista blanca tipada. No se acepta consulta cruda, uid ni customer_id.
//   * consulta_hash se re-HMACea con SN_CONSULTA_SAL; sin secreto se omite.
//   * Respuestas cortas y logs únicamente con código técnico, nunca payload/PII.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const MAX_BYTES = 32 * 1024;
const ORIGENES = new Set(["https://magandhi.com", "https://www.magandhi.com", "https://12344-ux.github.io"]);
const BOTS = /bot|crawl|spider|slurp|headless|lighthouse|pagespeed|preview|facebookexternalhit|whatsapp|telegram|curl|wget|python|axios|node-fetch|go-http/i;
const CAMPOS = [
  "tipo", "ruta", "slug", "origen", "entrada", "utm_campaign", "dispositivo", "cuando",
  "request_id", "superficie", "slot", "posicion", "layout_codigo", "modelo_version",
  "razon", "cantidad_resultados", "consulta_hash",
] as const;
const TIPOS_RECOMENDACION = new Set(["recomendacion_impresion", "recomendacion_click"]);
const SUPERFICIES = new Set([
  "home_principal", "home_descubrimiento", "categoria", "producto_final", "carrito", "busqueda",
]);
const RAZONES = new Set([
  "coincidencia_nombre", "coincidencia_categoria", "coincidencia_contenido", "coincidencia_busqueda",
  "afinidad_cuenta", "misma_categoria", "complemento", "alternativa", "continuacion", "rutina",
  "popular", "novedad", "descubrimiento", "exploracion",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CODIGO_80 = /^[a-z0-9][a-z0-9_-]{0,79}$/;
const LAYOUT = /^[a-z0-9][a-z0-9_-]{2,79}$/;
const MODELO = /^[a-z0-9][a-z0-9._-]{0,59}$/;
const HASH = /^[0-9a-f]{64}$/;
const SLUG = /^[a-z0-9-]{1,180}$/;

// Replica el contrato publicado por em_config_politica: una política publicada
// tiene versión recortada de 1..40 caracteres y nunca usa el valor "pendiente".
function validarPoliticaVersion(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const version = valor.trim();
  const longitud = Array.from(version).length;
  if (version !== valor || longitud < 1 || longitud > 40) return null;
  return version.toLowerCase() === "pendiente" ? null : version;
}

function normalizarConfigPublica(data: unknown) {
  const config = data && typeof data === "object" && !Array.isArray(data)
    ? data as Record<string, unknown>
    : null;
  const politicaVersion = validarPoliticaVersion(config?.politica_version);
  return {
    activa: config?.activa === true && politicaVersion !== null,
    politicaVersion,
  };
}

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
async function hmac256hex(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const d = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(value)));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function limpiar(e: unknown, visitante: string, sesion: string) {
  if (!e || typeof e !== "object" || Array.isArray(e)) return null;
  const o = e as Record<string, unknown>;
  if (o.tipo === undefined || o.tipo === null || o.tipo === "") return null;

  const tipo = String(o.tipo).slice(0, 80);
  const esRecomendacion = TIPOS_RECOMENDACION.has(tipo);
  const esBusqueda = tipo === "busqueda_resultados";

  if (!esRecomendacion && !esBusqueda) {
    // Contrato histórico intacto: mismos ocho campos, coerción y topes. Los
    // campos SN se ignoran para tipos anteriores o desconocidos.
    const out: Record<string, unknown> = {};
    for (const k of CAMPOS.slice(0, 8)) {
      const v = o[k];
      if (v === undefined || v === null || v === "") continue;
      if (k === "entrada") { out[k] = v === true; continue; }
      out[k] = String(v).slice(0, k === "ruta" ? 120 : 80);
    }
    return out.tipo ? out : null;
  }

  // Un evento SN se construye desde cero: ruta, origen, UTM, dispositivo y
  // cualquier clave libre se descartan antes de alcanzar service_role.
  const out: Record<string, unknown> = { tipo };
  const requestId = o.request_id;
  const superficie = o.superficie;
  const slot = o.slot;
  const posicion = o.posicion;
  const layout = o.layout_codigo;
  const modelo = o.modelo_version;
  const razon = o.razon;
  const cantidad = o.cantidad_resultados;
  const consultaHash = o.consulta_hash;
  const slug = o.slug;
  const cuando = o.cuando;

  if (typeof requestId !== "string" || !UUID.test(requestId)) return null;
  if (requestId.toLowerCase() === visitante.toLowerCase() || requestId.toLowerCase() === sesion.toLowerCase()) return null;
  if (typeof superficie !== "string" || !SUPERFICIES.has(superficie)) return null;
  if (typeof modelo !== "string" || !MODELO.test(modelo)) return null;
  if (cuando !== undefined && cuando !== null && cuando !== "") {
    if (typeof cuando !== "string" || cuando.length > 80) return null;
    out.cuando = cuando;
  }
  out.request_id = requestId.toLowerCase();
  out.superficie = superficie;
  out.modelo_version = modelo;

  if (layout !== undefined && layout !== null && layout !== "") {
    if (typeof layout !== "string" || !LAYOUT.test(layout)) return null;
    out.layout_codigo = layout;
  }
  if (consultaHash !== undefined && consultaHash !== null && consultaHash !== "") {
    if (typeof consultaHash !== "string" || !HASH.test(consultaHash)) return null;
    out.consulta_hash = consultaHash;
  }

  if (esBusqueda) {
    if (superficie !== "busqueda") return null;
    if (typeof cantidad !== "number" || !Number.isInteger(cantidad) || cantidad < 0 || cantidad > 10_000) return null;
    if (slot !== undefined && slot !== null && slot !== "") return null;
    if (posicion !== undefined && posicion !== null && posicion !== "") return null;
    if (layout !== undefined && layout !== null && layout !== "") return null;
    if (razon !== undefined && razon !== null && razon !== "") return null;
    out.cantidad_resultados = cantidad;
    return out;
  }

  if (typeof slot !== "string" || !CODIGO_80.test(slot)) return null;
  if (typeof posicion !== "number" || !Number.isInteger(posicion) || posicion < 1 || posicion > 100) return null;
  if (typeof layout !== "string" || !LAYOUT.test(layout)) return null;
  if (typeof razon !== "string" || !RAZONES.has(razon)) return null;
  if (typeof slug !== "string" || !SLUG.test(slug)) return null;
  if (cantidad !== undefined && cantidad !== null && cantidad !== "") return null;
  if (consultaHash !== undefined && consultaHash !== null && consultaHash !== "") return null;

  out.slug = slug;
  out.slot = slot;
  out.posicion = posicion;
  out.layout_codigo = layout;
  out.razon = razon;
  return out;
}

Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405, c);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !llave) return json({ error: "Configuración incompleta." }, 503, c);

  const largoDeclarado = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(largoDeclarado) && largoDeclarado > MAX_BYTES) {
    return json({ error: "Demasiado grande." }, 413, c);
  }
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
    if (error) {
      console.error("[tienda-eventos] config", JSON.stringify({ code: error.code ?? null }));
      return json({ activa: false, politica_version: null }, 200, c);
    }
    const config = normalizarConfigPublica(data);
    return json({
      activa: config.activa,
      politica_version: config.politicaVersion,
    }, 200, c);
  }
  if (body.modo !== "registrar") return json({ error: "Modo inválido." }, 400, c);

  // Bots: se responde 202 sin registrar y sin dar pistas.
  if (BOTS.test(req.headers.get("user-agent") ?? "")) return json({ ok: true }, 202, c);

  // La versión se comprueba otra vez en cada lote. Además de invalidar una
  // decisión antigua, se inyecta en el JSON limpio para que la RPC detecte un
  // cambio de política ocurrido entre esta lectura y la transacción de alta.
  const versionAceptada = validarPoliticaVersion(body.politica_version);
  const { data: configData, error: configError } = await sb.rpc("mt_publico_config");
  if (configError) {
    console.error("[tienda-eventos] registrar_config", JSON.stringify({ code: configError.code ?? null }));
    return json({ ok: false }, 503, c);
  }
  const configRegistro = normalizarConfigPublica(configData);
  if (!configRegistro.activa) {
    return json({ ok: false, apagada: true, politica_version: configRegistro.politicaVersion }, 409, c);
  }
  if (!versionAceptada || versionAceptada !== configRegistro.politicaVersion) {
    return json({
      ok: false,
      consentimiento_desactualizado: true,
      politica_version: configRegistro.politicaVersion,
    }, 412, c);
  }

  const visitante = String(body.visitante ?? "").slice(0, 40);
  const sesion = String(body.sesion ?? "").slice(0, 40);
  const eventos = (Array.isArray(body.eventos) ? body.eventos : [])
    .slice(0, 30)
    .map((evento) => limpiar(evento, visitante, sesion))
    .filter((evento): evento is Record<string, unknown> => evento !== null);
  if (!eventos.length) return json({ error: "Sin eventos." }, 400, c);
  eventos.forEach((evento) => { evento.politica_version = versionAceptada; });

  // El navegador nunca decide el valor persistido: si trae un digest de
  // consulta, la Edge lo vuelve HMAC con secreto propio. Sin secreto se omite.
  const consultaSal = Deno.env.get("SN_CONSULTA_SAL");
  await Promise.all(eventos.map(async (evento) => {
    if (typeof evento.consulta_hash !== "string") return;
    if (!consultaSal || consultaSal.length < 16) {
      delete evento.consulta_hash;
      return;
    }
    evento.consulta_hash = await hmac256hex(
      consultaSal,
      `sn1-consulta-v1|${evento.consulta_hash}`,
    );
  }));

  const ip = (req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") ||
    (req.headers.get("x-forwarded-for") ?? "").split(",")[0] || "").trim() || "desconocida";
  const sal = Deno.env.get("EM_IP_SAL") ?? llave;
  const ipHash = await sha256hex(`${sal}|eventos|${new Date().toISOString().slice(0, 10)}|${ip}`);

  const { data, error } = await sb.rpc("mt_registrar_eventos", {
    p_visitante: visitante,
    p_sesion: sesion,
    p_eventos: eventos,
    p_ip_hash: ipHash,
  });
  if (error) {
    const m = error.message ?? "";
    if (/MT_ANALITICA_APAGADA/.test(m)) return json({ ok: false, apagada: true }, 409, c);
    if (/MT_CONSENTIMIENTO_DESACTUALIZADO/.test(m)) {
      return json({ ok: false, consentimiento_desactualizado: true }, 412, c);
    }
    if (/MT_DEMASIADOS_EVENTOS/.test(m)) return json({ ok: false }, 429, c);
    if (/MT_(VISITANTE|EVENTOS)_INVALID/.test(m)) return json({ error: "Inválido." }, 400, c);
    // No registrar message: un error de base nunca debe volcar entrada pública.
    console.error("[tienda-eventos] registrar", JSON.stringify({ code: error.code ?? null }));
    return json({ ok: false }, 500, c);
  }
  const r = data as { aceptados?: number; descartados?: number };
  return json({ ok: true, aceptados: r?.aceptados ?? 0 }, 200, c);
});
