// ============================================================================
// MAGANDHI · Edge Function · em-suscripcion (Email marketing · captura, EM6)
// ----------------------------------------------------------------------------
// La llama la TIENDA (magandhi.com), sin sesion. Modos:
//   config     {}                                   -> si el formulario esta
//              activo, texto de autorizacion, enlace a la politica y temas.
//   suscribir  {correo, nombre?, temas[], acepto, sitio_web}
//              -> guarda una SOLICITUD y envia "Confirma tu suscripcion".
//   confirmar  {token}                              -> crea/reactiva el contacto.
//
// SEGURIDAD:
//   * Verify JWT APAGADO (la tienda no tiene sesion). Escribe solo por RPC que
//     unicamente puede ejecutar service_role (em_publico_*); la llave la
//     inyecta Supabase y nunca sale de aqui.
//   * Respuesta publica identica exista o no el correo ("si es correcto, te
//     llega un enlace"): nadie puede averiguar quien esta suscrito.
//   * Token de 256 bits; viaja en el FRAGMENTO del enlace (#t=), que el
//     navegador no envia a ningun servidor ni a terceros (referer). En la base
//     solo queda su sha256.
//   * IP: solo un hash con sal diaria para limitar abuso (10/dia por IP en la
//     base). Campo trampa "sitio_web" contra bots.
//   * Logs sin correos, nombres, tokens ni secretos.
// Correo: RESEND_MARKETING_API_KEY (dominio news.magandhi.com), Idempotency-Key
// = id de la solicitud. tags tipo=confirmacion_suscripcion.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const API = (Deno.env.get("RESEND_API_URL_BASE") ?? "https://api.resend.com").replace(/\/+$/, "");
const REMITENTE = Deno.env.get("CORREO_MARKETING_REMITENTE") ?? "MAGANDHI <novedades@news.magandhi.com>";
const RESPONDER_A = Deno.env.get("CORREO_RESPONDER_A") ?? "contacto@magandhi.com";
const TIENDA = (Deno.env.get("TIENDA_URL") ?? "https://magandhi.com").replace(/\/+$/, "");
const MAX_BYTES = 4096;

const ORIGENES = new Set(["https://magandhi.com", "https://www.magandhi.com", "https://12344-ux.github.io"]);
function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ORIGENES.has(origin) ? origin : "https://magandhi.com",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, c: Record<string, string>) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...c, "Content-Type": "application/json; charset=utf-8" } });

const MSG_OK = "Listo. Si el correo es correcto, te llegará un enlace para confirmar tu suscripción. Revisa también Promociones y Spam.";
const ERRORES: Array<[string, number, string]> = [
  ["EM_CAPTURA_APAGADA", 403, "La suscripción todavía no está disponible."],
  ["EM_CORREO_INVALIDO", 400, "Ese correo no parece válido. Revísalo."],
  ["EM_CONFIRMACION_REQUERIDA", 400, "Para suscribirte, marca la casilla de autorización."],
  ["EM_TEMAS_REQUERIDOS", 400, "Elige al menos qué quieres recibir."],
  ["EM_DEMASIADOS_INTENTOS", 429, "Demasiados intentos desde esta conexión. Intenta de nuevo mañana."],
];

const enc = new TextEncoder();
async function sha256hex(s: string) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function tokenAleatorio() {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const F = "font-family:Poppins,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";

// Copy PROVISIONAL (el equipo lo reescribe antes de abrir la tienda).
function correoHtml(nombre: string | null, enlace: string) {
  const hola = nombre ? `Hola, ${esc(nombre)}.` : "Hola.";
  return `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light"><title>Confirma tu suscripción</title></head>
<body style="margin:0;padding:0;background-color:#EFE7DD;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Un clic y tu suscripción a MAGANDHI queda activa.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#EFE7DD;"><tr><td align="center" style="padding:28px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background-color:#FFFFFF;border-radius:16px;">
<tr><td align="center" style="padding:30px 36px 8px 36px;">
<img src="${TIENDA}/logo-mark-terracota.png" width="44" height="44" alt="" style="display:block;border:0;width:44px;height:44px;">
<div style="${F}margin-top:10px;font-size:15px;letter-spacing:.32em;font-weight:600;color:#111111;">MAG<span style="color:#A6332E;">A</span>NDHI</div></td></tr>
<tr><td style="padding:22px 36px 8px 36px;">
<h1 style="${F}margin:0 0 14px 0;font-size:23px;line-height:1.3;color:#111111;font-weight:600;">Confirma tu suscripción</h1>
<p style="${F}margin:0 0 16px 0;font-size:15px;line-height:1.65;color:#3A3A3A;">${hola} Recibimos una solicitud para enviar novedades de MAGANDHI a este correo. Para activarla, confírmala con el botón.</p>
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:6px auto 22px auto;"><tr><td style="border-radius:10px;background-color:#A6332E;">
<a href="${esc(enlace)}" style="${F}display:inline-block;padding:14px 32px;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:10px;">Confirmar mi suscripción</a></td></tr></table>
<p style="${F}margin:0 0 16px 0;font-size:13px;line-height:1.6;color:#8A8076;">El enlace vence en 48 horas. Si no fuiste tú, ignora este correo: sin tu confirmación no te inscribimos.</p>
</td></tr></table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;"><tr><td align="center" style="${F}padding:18px 24px 0 24px;font-size:11.5px;line-height:1.6;color:#8A8076;">
MAGANDHI · Tunja, Colombia · <a href="${TIENDA}" style="color:#8A8076;">magandhi.com</a></td></tr></table>
</td></tr></table></body></html>`;
}
function correoTexto(nombre: string | null, enlace: string) {
  return [nombre ? `Hola, ${nombre}.` : "Hola.", "",
    "Recibimos una solicitud para enviar novedades de MAGANDHI a este correo. Para activarla, confírmala aquí:", enlace, "",
    "El enlace vence en 48 horas. Si no fuiste tú, ignora este correo: sin tu confirmación no te inscribimos.", "",
    "MAGANDHI · Tunja, Colombia · magandhi.com"].join("\n");
}

function ipCliente(req: Request) {
  return (req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") ||
    (req.headers.get("x-forwarded-for") ?? "").split(",")[0] || "").trim() || "desconocida";
}

Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405, c);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !llave) return json({ error: "Configuración del servidor incompleta." }, 503, c);

  const crudo = await req.text();
  if (enc.encode(crudo).length > MAX_BYTES) return json({ error: "Solicitud demasiado grande." }, 413, c);
  let body: Record<string, unknown>;
  try { body = JSON.parse(crudo); } catch { return json({ error: "Solicitud inválida." }, 400, c); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Solicitud inválida." }, 400, c);

  const sb = createClient(supabaseUrl, llave, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${llave}`, apikey: llave } },
  });
  const modo = String(body.modo ?? "");

  if (modo === "config") {
    const { data, error } = await sb.rpc("em_publico_config");
    if (error) { console.error("[em-suscripcion] config", JSON.stringify({ code: error.code ?? null, message: (error.message ?? "").slice(0, 160) })); return json({ activa: false }, 200, c); }
    const d = data as Record<string, unknown>;
    if (!d?.activa) return json({ activa: false }, 200, c);
    return json({ activa: true, texto_consentimiento: d.texto_consentimiento, politica_url: d.politica_url, temas: d.temas }, 200, c);
  }

  if (modo === "confirmar") {
    const token = typeof body.token === "string" ? body.token : "";
    if (!/^[A-Za-z0-9_-]{20,100}$/.test(token)) return json({ estado: "invalido" }, 200, c);
    const { data, error } = await sb.rpc("em_publico_confirmar", { p_token_hash: await sha256hex(token) });
    if (error) {
      console.error("[em-suscripcion] confirmar", JSON.stringify({ code: error.code ?? null, message: (error.message ?? "").slice(0, 160) }));
      return json({ error: "No pudimos confirmar ahora. Intenta de nuevo en un momento." }, 500, c);
    }
    const estado = String((data as { estado?: string })?.estado ?? "invalido");
    console.log("[em-suscripcion] confirmar", JSON.stringify({ estado }));
    return json({ estado }, 200, c);
  }

  if (modo !== "suscribir") return json({ error: "Modo inválido." }, 400, c);

  // Campo trampa: los bots lo llenan; las personas no lo ven.
  if (String(body.sitio_web ?? "").trim() !== "") {
    console.log("[em-suscripcion] suscribir", JSON.stringify({ estado: "trampa" }));
    return json({ ok: true, mensaje: MSG_OK }, 200, c);
  }

  const dia = new Date().toISOString().slice(0, 10);
  const sal = Deno.env.get("EM_IP_SAL") ?? llave;
  const ipHash = await sha256hex(`${sal}|${dia}|${ipCliente(req)}`);
  const token = tokenAleatorio();
  const temas = Array.isArray(body.temas) ? (body.temas as unknown[]).slice(0, 10).map((t) => String(t).slice(0, 40)) : [];

  const { data, error } = await sb.rpc("em_publico_suscribir", {
    p_correo: String(body.correo ?? "").slice(0, 254), p_nombre: body.nombre ? String(body.nombre).slice(0, 80) : null,
    p_temas: temas, p_acepto: body.acepto === true, p_token_hash: await sha256hex(token), p_ip_hash: ipHash,
  });
  if (error) {
    const m = error.message ?? "";
    for (const [k, s, t] of ERRORES) if (m.includes(k)) {
      console.log("[em-suscripcion] suscribir", JSON.stringify({ estado: "rechazado", codigo: k }));
      return json({ error: t, codigo: k }, s, c);
    }
    console.error("[em-suscripcion] suscribir", JSON.stringify({ code: error.code ?? null, message: m.slice(0, 160) }));
    return json({ error: "No pudimos registrar tu solicitud ahora. Intenta de nuevo en un momento." }, 500, c);
  }
  const r = data as { enviar?: boolean; motivo?: string; confirmacion_id?: string; correo?: string; nombre?: string | null };
  if (!r?.enviar) {
    console.log("[em-suscripcion] suscribir", JSON.stringify({ estado: "sin_envio", motivo: r?.motivo ?? null }));
    return json({ ok: true, mensaje: MSG_OK }, 200, c);
  }

  const key = Deno.env.get("RESEND_MARKETING_API_KEY");
  if (!key) { console.error("[em-suscripcion] falta RESEND_MARKETING_API_KEY"); return json({ error: "No pudimos enviar el correo ahora. Intenta más tarde." }, 503, c); }
  const enlace = `${TIENDA}/suscripcion/confirmar/#t=${token}`;
  const nombre = r.nombre ?? null;
  const env = await fetch(API + "/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Idempotency-Key": `confirmacion-${r.confirmacion_id}` },
    body: JSON.stringify({
      from: REMITENTE, to: [r.correo], reply_to: RESPONDER_A, subject: "Confirma tu suscripción a MAGANDHI",
      html: correoHtml(nombre, enlace), text: correoTexto(nombre, enlace),
      tags: [{ name: "tipo", value: "confirmacion_suscripcion" }],
    }),
  }).catch(() => null);
  if (!env || !env.ok) {
    console.error("[em-suscripcion] resend", JSON.stringify({ status: env?.status ?? null }));
    await env?.body?.cancel();
    return json({ error: "No pudimos enviar el correo ahora. Intenta más tarde." }, 502, c);
  }
  await env.body?.cancel();
  console.log("[em-suscripcion] suscribir", JSON.stringify({ estado: "enviado" }));
  return json({ ok: true, mensaje: MSG_OK }, 200, c);
});
