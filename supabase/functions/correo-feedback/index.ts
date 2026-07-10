// ============================================================
// Stramont · Correo 3 de 3 — Opinión / calificación (vía Resend)
// La dispara el DUEÑO desde el tablero (informe.html), unos días después
// de entregar la guía. El cliente califica con un clic (1-5 estrellas).
//
// SEGURIDAD:
//   - Acción de ADMIN: EXIGE el LINK_SECRET (?key=). Igual que el Correo 2.
//   - El correo se envía al correo GUARDADO del pedido (server-side).
//   - El enlace de opinión NO lleva el LINK_SECRET. Lleva un
//     feedback_token ACOTADO por pedido (se genera aquí si no existe):
//     si se filtrara, lo peor posible es calificar ESE pedido.
//   - RESEND_API_KEY y LINK_SECRET viven solo en Supabase Secrets.
//
//   POST ?key=LINK_SECRET   body: { pedido_id }
//
// Diseñada para que un CRON pueda llamarla en el futuro (fase 2) sin
// rehacer nada: toda la lógica (token, idempotencia, envío) vive aquí; el
// cron solo tendría que POSTear el pedido_id con el secreto.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const FROM = "Montaguth Institute <notificaciones@send.montaguth.institute>";
const REPLY_TO = "contacto@montaguth.institute";
const FEEDBACK_URL = "https://montaguth.institute/feedback.html";

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


// Escape copy-paste-safe (el "&" se construye aparte para no dejar
// entidades HTML literales que un editor pueda decodificar y romper).
function esc(s: unknown): string {
  const A = String.fromCharCode(38);
  return String(s == null ? "" : s)
    .replace(/&/g, A + "amp;")
    .replace(/</g, A + "lt;")
    .replace(/>/g, A + "gt;")
    .replace(/"/g, A + "quot;");
}

// Nombre de pila usable: la primera palabra de "nombre". Si no hay nada
// limpio, devuelve "" -> el saludo será "Hola," a secas (fallback pedido).
function primerNombre(nombre: unknown): string {
  const n = String(nombre == null ? "" : nombre).trim();
  if (!n) return "";
  const primera = n.split(/\s+/)[0] || "";
  // Evita usar como nombre algo que sea claramente un correo o basura.
  if (primera.includes("@") || primera.length > 24) return "";
  return primera;
}

// Enlace ÚNICO a la página de opinión. La calificación se elige allí (la
// página feedback.html funciona sin ?r). Un solo enlace mantiene el correo
// "transaccional" y evita que Gmail lo mande a Promociones (que fue lo que
// pasó con la primera versión de 5 enlaces de estrella).
function enlaceOpinion(pedidoId: string, token: string): string {
  return `${FEEDBACK_URL}?pid=${encodeURIComponent(pedidoId)}&t=${encodeURIComponent(token)}`;
}

function construirTexto(saludo: string, pedidoId: string, token: string): string {
  return [
    saludo,
    ``,
    `Preparamos tu guía con cuidado y queremos saber si estuvo a la altura.`,
    ``,
    `¿Nos dejas tu opinión? Toma unos segundos y nos ayuda a mejorar las guías que vienen:`,
    enlaceOpinion(pedidoId, token),
    ``,
    `Al abrir el enlace eliges tu calificación (de 1 a 5) y, si quieres, dejas un comentario.`,
    ``,
    `Gracias por tomarte el momento. Si prefieres, también puedes responder directamente a este correo.`,
    ``,
    `Equipo Montaguth Institute · montaguth.institute`,
  ].join("\n");
}


function construirHtml(saludo: string, pedidoId: string, token: string): string {
  const s = esc(saludo);
  const preheader = "Cu\u00e9ntanos qu\u00e9 te pareci\u00f3 tu gu\u00eda en unos segundos.";
  const url = esc(enlaceOpinion(pedidoId, token));
  // Estrellas SOLO decorativas (NO son enlaces). Un correo con 5 enlaces casi
  // idénticos disparaba el filtro de "Promociones" de Gmail; un único botón lo
  // mantiene transaccional, como los Correos 1 y 2 (que sí llegan a la bandeja).
  const estrellasDeco = "\u2605\u2605\u2605\u2605\u2605";
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>¿Qué te pareció tu guía?</title>
</head>
<body style="margin:0;padding:0;background-color:#0B1220;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;font-size:1px;line-height:1px;color:#0B1220;">
    ${esc(preheader)}
  </div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#0B1220;">
    <tr>
      <td align="center" style="padding:28px 14px;">
        <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background-color:#111827;border-radius:16px;border:1px solid rgba(255,255,255,0.08);">
          <tr>
            <td style="padding:34px 36px 8px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <div style="font-size:13px;letter-spacing:2px;text-transform:uppercase;color:#2DD4BF;font-weight:700;">Montaguth Institute</div>
            </td>
          </tr>
          <tr>
            <td style="padding:10px 36px 0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#E9EDF5;">
              <h1 style="margin:0 0 14px 0;font-size:23px;line-height:1.3;color:#E9EDF5;font-weight:800;">${s}</h1>
              <p style="margin:0 0 10px 0;font-size:15.5px;line-height:1.65;color:#c3ccdb;">Preparamos tu guía con cuidado y queremos saber si estuvo a la altura.</p>
              <p style="margin:0 0 8px 0;font-size:15.5px;line-height:1.65;color:#E9EDF5;font-weight:700;">¿Qué te pareció? Cuéntanos, toma unos segundos.</p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:14px 24px 2px 24px;">
              <div style="font-size:30px;line-height:1;color:#2DD4BF;letter-spacing:6px;">${estrellasDeco}</div>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:10px 36px 6px 36px;">
              <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:12px;background-color:#2DD4BF;">
                <a href="${url}" style="display:inline-block;padding:15px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;font-weight:800;color:#0B1220;text-decoration:none;border-radius:12px;">Dejar mi opinión</a>
              </td></tr></table>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 36px 4px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <p style="margin:0;font-size:14px;line-height:1.6;color:#96a1b5;">Al abrir el enlace eliges tu calificación y, si quieres, dejas un comentario. Nos ayuda a mejorar las guías que vienen.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 36px 30px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <div style="border-top:1px solid rgba(255,255,255,0.08);padding-top:16px;">
                <p style="margin:0 0 4px 0;font-size:12.5px;color:#6b7688;">Montaguth Institute · <a href="https://montaguth.institute" style="color:#2DD4BF;text-decoration:none;">montaguth.institute</a></p>
                <p style="margin:0;font-size:11.5px;line-height:1.5;color:#5b6577;">Recibiste este correo porque estudiaste con una guía de montaguth.institute.</p>
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  const url = new URL(req.url);
  const SECRET = Deno.env.get("LINK_SECRET") || "";
  if (!SECRET) return json({ error: "Falta configurar LINK_SECRET." }, 500);
  // Acción de admin: exige el secreto (la dispara el tablero autenticado).
  if (url.searchParams.get("key") !== SECRET) return json({ error: "No autorizado." }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido." }, 400); }
  const pedidoId = String(body?.pedido_id || "").trim();
  if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);

  const client = sb();
  const { data: row, error: errRow } = await client
    .from("pedidos").select("*").eq("pedido_id", pedidoId).maybeSingle();
  if (errRow) return json({ error: "Error leyendo el pedido: " + errRow.message }, 500);
  if (!row) return json({ error: "Pedido no encontrado." }, 404);
  if (!row.correo) return json({ error: "El pedido no tiene correo." }, 422);

  // Idempotencia estricta: la opinión se pide UNA sola vez por pedido. No se
  // reenvía nunca. Pedir opinión es opcional; insistir con reenvíos se sentiría
  // como presión/acoso y va contra la voz de marca de Stramont (quitar
  // fricción, no imponerla). Si el cliente quiere opinar, tiene su enlace.
  if (row.correo_feedback_enviado) {
    return json({ ok: true, yaEnviado: true, pedido_id: pedidoId });
  }

  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  if (!RESEND_API_KEY) return json({ error: "Falta configurar RESEND_API_KEY." }, 500);

  // Token acotado por pedido: se genera aquí si aún no existe.
  let token = String(row.feedback_token || "").trim();
  if (!token) {
    token = crypto.randomUUID();
    const { error: errTok } = await client.from("pedidos")
      .update({ feedback_token: token }).eq("pedido_id", pedidoId);
    if (errTok) return json({ error: "No se pudo generar el token: " + errTok.message }, 500);
  }

  const correo = String(row.correo);
  const n = primerNombre(row.nombre);
  const saludo = n ? `Hola, ${n}.` : "Hola,";
  const prueba = esCorreoPrueba(correo);
  const asunto = (prueba ? "[TEST] " : "") + "¿Qué te pareció tu guía?";

  const resp = await fetch(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + RESEND_API_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM,
      to: [correo],
      reply_to: REPLY_TO,
      subject: asunto,
      html: construirHtml(saludo, pedidoId, token),
      text: construirTexto(saludo, pedidoId, token),
      headers: { "X-Entity-Ref-ID": pedidoId + "-feedback" },
    }),
  });

  if (!resp.ok) {
    const detalle = await resp.text().catch(() => "");
    return json({ error: "Resend respondió " + resp.status, detalle }, 502);
  }

  await client.from("pedidos")
    .update({ correo_feedback_enviado: new Date().toISOString() })
    .eq("pedido_id", pedidoId);

  return json({ ok: true, pedido_id: pedidoId, enviado_a: correo, prueba });
});
