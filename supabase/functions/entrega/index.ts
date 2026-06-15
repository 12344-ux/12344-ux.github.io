// ============================================================
// Stramont · Entrega privada de guías (con visor)
// - Guarda guías en bucket PRIVADO "guias" (modo subir).
// - Las entrega solo con firma válida (HMAC) y sin caducar.
// - El visor (entrega.html en la web) las renderiza en un iframe.
//   La función responde con CORS para que el visor pueda leerla.
//
// Variables:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (Supabase las inyecta)
//   LINK_SECRET                              (la pones tú en Secrets)
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const VIEWER_URL = "https://montaguth.institute/entrega.html";
const BUCKET = "guias";
const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "*",
};
const enc = new TextEncoder();

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

async function firmar(secreto: string, mensaje: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secreto),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(mensaje));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const f = url.searchParams.get("f") || "";
  const SECRET = Deno.env.get("LINK_SECRET") || "";
  if (!SECRET) return new Response("Falta configurar LINK_SECRET.", { status: 500, headers: CORS });

  // ---------- MODO SUBIR ----------
  if (url.searchParams.get("upload") === "1") {
    if (req.method !== "POST") return new Response("Usa POST.", { status: 405, headers: CORS });
    if (url.searchParams.get("key") !== SECRET) return new Response("No autorizado.", { status: 403, headers: CORS });
    if (!f) return new Response("Falta f.", { status: 400, headers: CORS });
    const html = await req.text();
    const { error } = await sb().storage.from(BUCKET).upload(
      f, new Blob([html], { type: "text/html" }), { contentType: "text/html", upsert: true },
    );
    if (error) return new Response("Error al subir: " + error.message, { status: 500, headers: CORS });
    return new Response("OK: subido " + f, { status: 200, headers: CORS });
  }

  // ---------- MODO MINT (devuelve el link del VISOR) ----------
  if (url.searchParams.get("mint") === "1") {
    if (url.searchParams.get("key") !== SECRET) return new Response("No autorizado.", { status: 403, headers: CORS });
    if (!f) return new Response("Falta f.", { status: 400, headers: CORS });
    const days = parseInt(url.searchParams.get("days") || "30", 10);
    const exp = Math.floor(Date.now() / 1000) + days * 86400;
    const sig = await firmar(SECRET, `${f}.${exp}`);
    const link = `${VIEWER_URL}?f=${encodeURIComponent(f)}&exp=${exp}&sig=${sig}`;
    return new Response(link, { headers: { ...CORS, "content-type": "text/plain; charset=utf-8" } });
  }

  // ---------- MODO SERVIR (lo lee el visor) ----------
  const exp = parseInt(url.searchParams.get("exp") || "0", 10);
  const sig = url.searchParams.get("sig") || "";
  const esperada = await firmar(SECRET, `${f}.${exp}`);
  if (!f || sig !== esperada) return new Response("Enlace inválido.", { status: 403, headers: CORS });
  if (Math.floor(Date.now() / 1000) > exp) return new Response("Este enlace ha expirado.", { status: 410, headers: CORS });

  const { data, error } = await sb().storage.from(BUCKET).download(f);
  if (error || !data) return new Response("Guía no encontrada.", { status: 404, headers: CORS });

  const html = await data.text();
  return new Response(html, { headers: { ...CORS, "content-type": "text/html; charset=utf-8" } });
});
