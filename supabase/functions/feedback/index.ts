// ============================================================
// Stramont · Registro de opiniones (Correo 3) — función PÚBLICA
// La llama feedback.html (página pública) cuando el cliente califica o
// deja un comentario. NO es una acción de admin.
//
// SEGURIDAD (por qué NO usa LINK_SECRET ni escribe con la llave pública):
//   - feedback.html es público: darle el LINK_SECRET lo expondría.
//   - La tabla pedido_feedback NO tiene policy pública (ni insert): si la
//     tuviera, cualquiera podría inyectar opiniones falsas para pedidos
//     ajenos, porque una policy de insert no valida el token.
//   - Por eso todo pasa por aquí: se valida un feedback_token ACOTADO por
//     pedido (que viaja en el enlace del correo) contra pedidos.feedback_token,
//     y solo entonces se escribe con service_role. La capacidad del token
//     es mínima: solo permite registrar la opinión de ESE pedido.
//
//   POST  body: { pedido_id, token, action: "rate"|"comment", ... }
//     action "rate"    -> { rating: 1..5 }
//     action "comment" -> { comentario, permiso, nombre }
//
// Verify JWT debe estar APAGADO (igual que correo-confirmacion): la
// autorización la da el token del pedido, no un JWT de Supabase.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "*",
};
const MAX_COMENTARIO = 4000;
const MAX_NOMBRE = 60;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

function esCorreoPrueba(correo: string): boolean {
  const c = (correo || "").toLowerCase().trim();
  if (c === "pruebasmontaguth@gmail.com") return true;
  return c.startsWith("prueba") || c.endsWith("@example.com") || c.endsWith(".test");
}


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido." }, 400); }

  const pedidoId = String(body?.pedido_id || "").trim();
  const token = String(body?.token || "").trim();
  const action = String(body?.action || "").trim();
  if (!pedidoId || !token) return json({ error: "Enlace no válido." }, 400);
  if (action !== "rate" && action !== "comment") return json({ error: "Acción no válida." }, 400);

  const client = sb();

  // Validación del token ACOTADO: el pedido debe existir y su feedback_token
  // (no nulo) debe coincidir exactamente con el que llega. Sin esto, no se
  // toca nada. Es la única autorización de esta función pública.
  const { data: row, error: errRow } = await client
    .from("pedidos").select("pedido_id, correo, feedback_token")
    .eq("pedido_id", pedidoId).maybeSingle();
  if (errRow) return json({ error: "Error del servidor." }, 500);
  if (!row || !row.feedback_token || row.feedback_token !== token) {
    return json({ error: "Enlace no válido o expirado." }, 403);
  }

  const prueba = esCorreoPrueba(String(row.correo || ""));
  const ahora = new Date().toISOString();

  if (action === "rate") {
    const rating = Math.round(Number(body?.rating));
    if (!(rating >= 1 && rating <= 5)) return json({ error: "Calificación no válida." }, 400);
    // Upsert por pedido_id: fija/actualiza rating sin tocar el comentario.
    const { error: errUp } = await client.from("pedido_feedback").upsert({
      pedido_id: pedidoId,
      rating,
      es_prueba: prueba,
      feedback_recibido_at: ahora,
    }, { onConflict: "pedido_id" });
    if (errUp) return json({ error: "No se pudo registrar la calificación." }, 500);
    return json({ ok: true, rating });
  }

  // action === "comment"
  const comentario = String(body?.comentario || "").trim().slice(0, MAX_COMENTARIO);
  // Necesitamos la calificación actual: el permiso/testimonio solo aplica a
  // notas altas (4-5). Leemos la fila ya creada por el "rate".
  const { data: fb } = await client.from("pedido_feedback")
    .select("rating").eq("pedido_id", pedidoId).maybeSingle();
  const ratingActual = fb && typeof fb.rating === "number" ? fb.rating : null;
  const altaNota = ratingActual != null && ratingActual >= 4;

  const permiso = altaNota && body?.permiso === true;
  const nombreMostrar = permiso
    ? (String(body?.nombre || "").trim().slice(0, MAX_NOMBRE) || null)
    : null;

  const { error: errUp } = await client.from("pedido_feedback").upsert({
    pedido_id: pedidoId,
    comentario: comentario || null,
    permiso_publicar: permiso,
    nombre_mostrar: nombreMostrar,
    es_prueba: prueba,
    comentario_recibido_at: ahora,
  }, { onConflict: "pedido_id" });
  if (errUp) return json({ error: "No se pudo registrar el comentario." }, 500);

  return json({ ok: true });
});
