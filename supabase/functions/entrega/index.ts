// ============================================================
// Stramont · Opción C — Entrega privada de guías
// Sirve una guía HTML desde un bucket PRIVADO ("guias"),
// RENDERIZADA (content-type: text/html), solo si el link
// tiene una firma válida (HMAC) y NO ha caducado.
//
// Variables que usa:
//   - SUPABASE_URL                (la inyecta Supabase sola)
//   - SUPABASE_SERVICE_ROLE_KEY   (la inyecta Supabase sola)
//   - LINK_SECRET                 (la pones tú en "Secrets")
//
// URL pública de esta función (tu proyecto):
//   https://ifvnuvjvlzpdaimelmbm.supabase.co/functions/v1/entrega
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_URL =
  "https://ifvnuvjvlzpdaimelmbm.supabase.co/functions/v1/entrega";
const BUCKET = "guias";
const enc = new TextEncoder();

// Firma HMAC-SHA256 en hexadecimal
async function firmar(secreto: string, mensaje: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secreto),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(mensaje));
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const f = url.searchParams.get("f") || "";
  const SECRET = Deno.env.get("LINK_SECRET") || "";

  if (!SECRET) {
    return new Response("Falta configurar LINK_SECRET.", { status: 500 });
  }

  // ---------- MODO MINT: generar el link del cliente ----------
  // Solo tú, que conoces LINK_SECRET, puedes generar links.
  // Ej: ...?mint=1&f=cliente-juan.html&days=30&key=TU_LINK_SECRET
  if (url.searchParams.get("mint") === "1") {
    if (url.searchParams.get("key") !== SECRET) {
      return new Response("No autorizado.", { status: 403 });
    }
    if (!f) return new Response("Falta el parámetro f (archivo).", { status: 400 });
    const days = parseInt(url.searchParams.get("days") || "30", 10);
    const exp = Math.floor(Date.now() / 1000) + days * 86400;
    const sig = await firmar(SECRET, `${f}.${exp}`);
    const link =
      `${FUNCTION_URL}?f=${encodeURIComponent(f)}&exp=${exp}&sig=${sig}`;
    return new Response(link, {
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }

  // ---------- MODO SERVIR: validar y entregar la guía ----------
  const exp = parseInt(url.searchParams.get("exp") || "0", 10);
  const sig = url.searchParams.get("sig") || "";
  const esperada = await firmar(SECRET, `${f}.${exp}`);

  if (!f || sig !== esperada) {
    return new Response("Enlace inválido.", { status: 403 });
  }
  if (Math.floor(Date.now() / 1000) > exp) {
    return new Response("Este enlace ha expirado.", { status: 410 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await supabase.storage.from(BUCKET).download(f);
  if (error || !data) {
    return new Response("Guía no encontrada.", { status: 404 });
  }

  const html = await data.text();
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "private, no-store",
    },
  });
});
