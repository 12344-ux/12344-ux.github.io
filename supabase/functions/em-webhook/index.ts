// ============================================================================
// MAGANDHI · Edge Function · em-webhook (Email marketing · resultados, EM5)
// ----------------------------------------------------------------------------
// La llama RESEND (no el navegador) cada vez que pasa algo con un correo:
// entregado, rebote, queja, apertura, clic, baja, supresion... Atiende el UNICO
// webhook del plan gratis: campanas (news.magandhi.com) y correos del pedido
// (updates.magandhi.com).
//
// CANDADO: la firma Svix. Se despliega con "Verify JWT" APAGADO porque Resend
// no envia JWT; a cambio, NADA se procesa sin una firma valida:
//   - headers svix-id, svix-timestamp, svix-signature obligatorios;
//   - el timestamp debe estar a menos de 5 minutos (anti-replay);
//   - HMAC-SHA256 de "<svix-id>.<svix-timestamp>.<cuerpo crudo>" con el secreto
//     RESEND_WEBHOOK_SECRET (whsec_..., solo en Supabase Secrets), comparado en
//     tiempo constante contra cada firma "v1,<base64>" del header.
//
// ESCRITURA: un solo RPC, em_webhook_registrar, que SOLO puede ejecutar
// service_role (ni anon ni usuarios del panel). La llave de servicio la inyecta
// el runtime de Supabase; jamas sale de aqui ni se loguea. El RPC es
// idempotente por svix-id (Resend repite el mismo id en cada reintento).
//
// RESPUESTAS (importan: si fallamos muchas veces, Resend apaga el webhook):
//   200 -> procesado, repetido o ignorado (pruebas, eventos que no usamos).
//   400/401 -> peticion invalida o firma mala: Resend no debe insistir.
//   500/503 -> fallo nuestro transitorio: Resend reintenta (~28 h).
// Los logs nunca llevan el cuerpo, correos ni secretos.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const TOLERANCIA_S = 5 * 60;
const MAX_BYTES = 256 * 1024;
const enc = new TextEncoder();

const json = (b: unknown, s: number) =>
  new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json; charset=utf-8" } });

function b64aBytes(s: string): Uint8Array<ArrayBuffer> | null {
  try {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch { return null; }
}
function bytesAb64(b: Uint8Array) {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s);
}
function igualesTiempoConstante(a: string, b: string) {
  const x = enc.encode(a), y = enc.encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

// Verificacion Svix (https://docs.svix.com/receiving/verifying-payloads/how-manual)
async function verificarFirma(
  secreto: string, id: string, ts: string, firmas: string, cuerpo: string, ahoraS = Math.floor(Date.now() / 1000),
): Promise<"ok" | "vencida" | "invalida"> {
  if (!/^\d{1,12}$/.test(ts)) return "invalida";
  if (Math.abs(ahoraS - Number(ts)) > TOLERANCIA_S) return "vencida";
  const llave = b64aBytes(secreto.startsWith("whsec_") ? secreto.slice(6) : secreto);
  if (!llave || !llave.length) return "invalida";
  const k = await crypto.subtle.importKey("raw", llave, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(`${id}.${ts}.${cuerpo}`)));
  const esperada = bytesAb64(mac);
  let ok = false;
  for (const parte of firmas.split(" ")) {
    const [ver, sig] = parte.split(",", 2);
    if (ver === "v1" && sig && igualesTiempoConstante(sig, esperada)) ok = true; // sin cortar: tiempo constante
  }
  return ok ? "ok" : "invalida";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  const secreto = Deno.env.get("RESEND_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const llaveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secreto || !supabaseUrl || !llaveServicio) {
    console.error("[em-webhook] configuracion incompleta", JSON.stringify({ secreto: !!secreto, url: !!supabaseUrl, servicio: !!llaveServicio }));
    return json({ error: "Configuración incompleta." }, 503);
  }

  const id = req.headers.get("svix-id") ?? "";
  const ts = req.headers.get("svix-timestamp") ?? "";
  const firmas = req.headers.get("svix-signature") ?? "";
  if (!id || !ts || !firmas) return json({ error: "Faltan los encabezados de firma." }, 400);

  const largo = Number(req.headers.get("content-length") ?? "0");
  if (largo > MAX_BYTES) return json({ error: "Cuerpo demasiado grande." }, 413);
  const cuerpo = await req.text(); // CRUDO: la firma se calcula sobre el texto exacto
  if (enc.encode(cuerpo).length > MAX_BYTES) return json({ error: "Cuerpo demasiado grande." }, 413);

  const v = await verificarFirma(secreto, id, ts, firmas, cuerpo);
  if (v !== "ok") {
    console.warn("[em-webhook] firma rechazada", JSON.stringify({ motivo: v }));
    return json({ error: v === "vencida" ? "Firma vencida." : "Firma inválida." }, 401);
  }

  let evento: unknown;
  try { evento = JSON.parse(cuerpo); } catch { return json({ error: "JSON inválido." }, 400); }
  if (!evento || typeof evento !== "object" || Array.isArray(evento)) return json({ error: "Evento inválido." }, 400);

  // Cliente de servicio. apikey Y Authorization = llave de servicio: asi
  // PostgREST resuelve el rol service_role (leccion de Wompi F1: si la apikey
  // fuera la publica, degradaria el rol).
  const sb = createClient(supabaseUrl, llaveServicio, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${llaveServicio}`, apikey: llaveServicio } },
  });
  const { data, error } = await sb.rpc("em_webhook_registrar", { p_svix_id: id, p_evento: evento });
  if (error) {
    const m = error.message ?? "";
    console.error("[em-webhook] rpc", JSON.stringify({ code: error.code ?? null, message: m.slice(0, 200), hint: error.hint ?? null }));
    if (/EM_WEBHOOK_(ID|EVENTO)_INVALIDO/.test(m)) return json({ error: "Evento inválido." }, 400);
    return json({ error: "No se pudo registrar el evento." }, 500);
  }
  const r = data as { estado?: string; tipo?: string; origen?: string; suprimio?: boolean; motivo?: string };
  console.log("[em-webhook]", JSON.stringify({ estado: r?.estado, tipo: r?.tipo ?? null, origen: r?.origen ?? null, suprimio: r?.suprimio ?? false, motivo: r?.motivo ?? null }));
  return json({ ok: true, estado: r?.estado ?? "procesado" }, 200);
});
