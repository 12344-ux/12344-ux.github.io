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
// plan (dias_acceso) y saca el monto en centavos COP de un SECRETO de entorno
// que TÚ configuras (PRECIO_10_COP_CENTS / PRECIO_30_COP_CENTS). Así nadie
// puede firmar un monto arbitrario ni cobrarse $1 por un plan de $5.
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

  // Monto en centavos COP según el plan, tomado de SECRETOS DE ENTORNO (los
  // configuras tú; nunca los inventa el código ni el navegador).
  const dias = Number(row.dias_acceso);
  const envPrecio = dias === 10 ? "PRECIO_10_COP_CENTS" : dias === 30 ? "PRECIO_30_COP_CENTS" : "";
  const montoStr = envPrecio ? Deno.env.get(envPrecio) : "";
  const amountInCents = Number(montoStr);
  if (!envPrecio || !montoStr || !Number.isInteger(amountInCents) || amountInCents <= 0) {
    return json({
      error: "Monto no configurado para este plan. Define el secreto " +
        (envPrecio || "PRECIO_<dias>_COP_CENTS") + " en Supabase (centavos COP, entero).",
    }, 500);
  }

  const currency = "COP";
  const signature = await sha256Hex(`${pedidoId}${amountInCents}${currency}${SECRET}`);
  return json({ reference: pedidoId, amountInCents, currency, signature });
});
