// ============================================================
// Stramont · Wompi — Firma de integridad (server-side)
//
// POR QUÉ EXISTE (seguridad): para lanzar el Web Checkout de Wompi hay que
// enviar una "signature:integrity" = SHA256(referencia + monto + moneda +
// SECRETO_DE_INTEGRIDAD). Ese SECRETO NUNCA puede ir en el frontend (lo
// expondría). Por eso el navegador NO calcula la firma: llama a esta función,
// que la calcula del lado del servidor y devuelve solo el hash (que sí es
// público por diseño).
//
// ANTI-MANIPULACIÓN DEL MONTO: el navegador NO decide cuánto se cobra. Esta
// función lee el pedido (creado justo antes, en estado 'pendiente'), toma su
// plan (dias_acceso) y su PRECIO EN USD de un SECRETO que TÚ configuras
// (PRECIO_10_USD / PRECIO_30_USD). El sitio muestra el precio en USD, pero
// Wompi solo cobra en COP: por eso aquí se convierte USD -> COP a la TASA DEL
// MOMENTO (TRM oficial de Colombia, con respaldos) y se firma ese monto COP.
// Así nadie puede firmar un monto arbitrario ni cobrarse $1 por un plan de $5.
//
//   POST { "pedido_id": "P30-260724-xxxx" }
//   -> { reference, amountInCents, currency:"COP", signature }
//
// Verify JWT: OFF (la llama el frontend público). No expone ningún secreto.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "*",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

async function sha256Hex(texto: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Rango sano de la tasa COP/USD (evita cobrar montos absurdos si una fuente
// devuelve basura). El USD/COP ha estado ~3.500–5.000; 2.000–10.000 es un cerco amplio.
function trmValida(v: number): boolean {
  return Number.isFinite(v) && v >= 2000 && v <= 10000;
}

// Tasa USD -> COP del momento. Prioridad: (1) TRM oficial de Colombia
// (datos.gov.co) -> (2) open.er-api.com (sin llave) -> (3) secreto TRM_FALLBACK.
// Valida el rango en cada fuente. Si ninguna sirve, lanza error (no cobra).
async function obtenerTRM(): Promise<number> {
  try {
    const r = await fetch(
      "https://www.datos.gov.co/resource/32sa-8pi3.json?$select=valor&$order=vigenciadesde%20DESC&$limit=1",
      { headers: { "accept": "application/json" } },
    );
    if (r.ok) {
      const j = await r.json();
      const v = Number(j?.[0]?.valor);
      if (trmValida(v)) return v;
    }
  } catch (_e) { /* pasamos al respaldo */ }
  try {
    const r = await fetch("https://open.er-api.com/v6/latest/USD");
    if (r.ok) {
      const j = await r.json();
      const v = Number(j?.rates?.COP);
      if (trmValida(v)) return v;
    }
  } catch (_e) { /* pasamos al respaldo */ }
  const fb = Number(Deno.env.get("TRM_FALLBACK"));
  if (trmValida(fb)) return fb;
  throw new Error("sin fuente de tasa USD->COP válida (configura el secreto TRM_FALLBACK).");
}

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // Autoprueba con el vector oficial de la doc de Wompi (no usa secretos reales).
  // GET ?selftest=1  -> debe devolver ok:true si el algoritmo es correcto.
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.get("selftest") === "1") {
    const esperado = "37c8407747e595535433ef8f6a811d853cd943046624a0ec04662b17bbf33bf5";
    const calc = await sha256Hex("sk8-438k4-xmxm392-sn2m2490000COPprod_integrity_Z5mMke9x0k8gpErbDqwrJXMqsI6SFli6");
    return json({ ok: calc === esperado, calc, esperado });
  }

  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  const SECRET = Deno.env.get("WOMPI_INTEGRITY_SECRET");
  if (!SECRET) return json({ error: "Falta configurar WOMPI_INTEGRITY_SECRET." }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido." }, 400); }
  const pedidoId = String(body?.pedido_id || "").trim();
  if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);

  const client = sb();
  const { data: row, error } = await client
    .from("pedidos").select("pedido_id, dias_acceso, estado_pago").eq("pedido_id", pedidoId).maybeSingle();
  if (error) return json({ error: "Error leyendo el pedido: " + error.message }, 500);
  if (!row) return json({ error: "Pedido no encontrado." }, 404);
  if (row.estado_pago === "aprobado") return json({ error: "Este pedido ya está pagado." }, 409);

  // Precio en USD del plan (lo fijas tú vía secreto). El sitio muestra USD; el
  // cobro se hace en COP a la tasa del día (Wompi solo cobra en COP).
  const dias = Number(row.dias_acceso);
  const envPrecio = dias === 10 ? "PRECIO_10_USD" : dias === 30 ? "PRECIO_30_USD" : "";
  const usd = envPrecio ? Number(Deno.env.get(envPrecio)) : NaN;
  if (!envPrecio || !Number.isFinite(usd) || usd <= 0) {
    return json({
      error: "Precio USD no configurado para este plan. Define el secreto " +
        (envPrecio || "PRECIO_<dias>_USD") + " en Supabase (dólares, ej. 3).",
    }, 500);
  }

  // Tasa USD -> COP del momento (TRM oficial, con respaldos). El monto se
  // "congela" aquí, justo al iniciar el pago.
  let trm: number;
  try {
    trm = await obtenerTRM();
  } catch (e) {
    return json({ error: "No se pudo obtener la tasa USD->COP: " + (e as Error).message }, 502);
  }

  const currency = "COP";
  const amountInCents = Math.round(usd * trm * 100); // centavos de COP
  const signature = await sha256Hex(`${pedidoId}${amountInCents}${currency}${SECRET}`);
  return json({ reference: pedidoId, amountInCents, currency, signature, usd, trm });
});
