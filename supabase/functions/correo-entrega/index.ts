// ============================================================
// Stramont · Correo 2 de 3 — Entrega de la guía (vía Resend)
// La dispara el DUEÑO desde el tablero (informe.html), tras revisar la guía.
//
// SEGURIDAD:
//   - Es una acción de ADMIN (no un cliente anónimo), así que EXIGE el
//     LINK_SECRET (?key=). A diferencia del Correo 1 (confirmación, que sí
//     lo dispara el comprador anónimo y por eso solo recibe pedido_id),
//     aquí el que llama es el tablero autenticado.
//   - El correo se envía al correo GUARDADO del pedido (server-side), nunca
//     a uno que venga del navegador.
//   - RESEND_API_KEY y LINK_SECRET viven solo en Supabase Secrets.
//
//   POST ?key=LINK_SECRET   body: { pedido_id, archivo, tema? }
//
// El enlace privado se firma con EL MISMO algoritmo que la función "entrega"
// (HMAC-SHA256 de `${archivo}.${exp}`), para que entrega.html + su modo
// "serve" lo acepten. Si algún día cambias la firma en una, cámbiala en la
// otra.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const FROM = "Montaguth Institute <notificaciones@send.montaguth.institute>";
const REPLY_TO = "contacto@montaguth.institute";
const VIEWER_URL = "https://montaguth.institute/entrega.html";
const BUCKET_GUIAS = "guias";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "*",
};

const enc = new TextEncoder();

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

// MISMA firma que la función "entrega" (debe coincidir byte a byte).
async function firmar(secreto: string, mensaje: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secreto),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(mensaje));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function esCorreoPrueba(correo: string): boolean {
  const c = (correo || "").toLowerCase().trim();
  if (c === "pruebasmontaguth@gmail.com") return true;
  return c.startsWith("prueba") || c.endsWith("@example.com") || c.endsWith(".test");
}

// Escape copy-paste-safe (el "&" se construye aparte; sin entidades HTML
// literales que un editor/render pueda decodificar y romper la sintaxis).
function esc(s: unknown): string {
  const A = String.fromCharCode(38);
  return String(s == null ? "" : s)
    .replace(/&/g, A + "amp;")
    .replace(/</g, A + "lt;")
    .replace(/>/g, A + "gt;")
    .replace(/"/g, A + "quot;");
}

function construirTexto(nombre: string, tema: string, enlace: string, dias: number | string): string {
  return [
    `Hola, ${nombre}.`,
    ``,
    `Tu guía personalizada sobre ${tema} ya está lista. A partir de este momento puedes acceder a ella desde este enlace privado:`,
    enlace,
    ``,
    `Un consejo: no la leas de principio a fin. Trabaja con ella: explícate las ideas, responde los "Pruébate" y vuelve según el plan de repaso. Ahí es donde ocurre el aprendizaje.`,
    ``,
    `Antes de empezar, dos recomendaciones:`,
    `1. Intenta responder antes de revelar la respuesta. En cada concepto hay una sección "Pruébate": intenta escribir tu respuesta antes de abrir la correcta. Ese esfuerzo fija el conocimiento mucho más que releer.`,
    `2. Sigue el plan de repaso. Al final hay un plan sencillo para volver a revisar el contenido en los próximos días. Unos minutos de repaso valen más que memorizar todo de una vez.`,
    ``,
    `Tu enlace estará disponible durante ${dias} días, para que vuelvas cuando lo necesites y estudies a tu ritmo.`,
    ``,
    `Gracias por confiar en nosotros.`,
    ``,
    `Cuando hayas usado la guía, nos encantará saber cómo te fue. Y si tienes cualquier duda, responde directamente a este correo.`,
    ``,
    `Un abrazo,`,
    `Equipo Montaguth Institute · montaguth.institute`,
  ].join("\n");
}

function construirHtml(nombre: string, tema: string, enlace: string, dias: number | string): string {
  const n = esc(nombre);
  const t = esc(tema);
  const d = esc(dias);
  const url = esc(enlace);
  const preheader = "\u00c1brela, pon a prueba tus conocimientos y empieza a estudiar de una forma m\u00e1s inteligente.";
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>Tu guía ya está lista</title>
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
              <h1 style="margin:0 0 14px 0;font-size:23px;line-height:1.3;color:#E9EDF5;font-weight:800;">Hola, ${n}.</h1>
              <p style="margin:0 0 26px 0;font-size:15.5px;line-height:1.65;color:#c3ccdb;">Tu guía personalizada sobre <strong style="color:#E9EDF5;">${t}</strong> ya está lista. A partir de este momento puedes acceder a ella desde el siguiente enlace privado.</p>
            </td>
          </tr>
          <!-- CTA principal -->
          <tr>
            <td align="center" style="padding:0 36px 6px 36px;">
              <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:12px;background-color:#2DD4BF;">
                <a href="${url}" style="display:inline-block;padding:16px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:17px;font-weight:800;color:#0B1220;text-decoration:none;border-radius:12px;">Abrir mi guía</a>
              </td></tr></table>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:12px 44px 6px 44px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <p style="margin:0;font-size:13px;line-height:1.55;color:#8b97ab;">No la leas de principio a fin. Trabaja con ella: explícate las ideas, responde los "Pruébate" y vuelve según el plan de repaso. Ahí es donde ocurre el aprendizaje.</p>
            </td>
          </tr>
          <tr><td style="padding:22px 36px;"><div style="height:1px;background-color:rgba(255,255,255,0.10);line-height:1px;font-size:1px;">&#160;</div></td></tr>
          <!-- Recomendaciones -->
          <tr>
            <td style="padding:0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#E9EDF5;">
              <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#c3ccdb;">Antes de empezar, dos recomendaciones. La guía está diseñada para ayudarte a comprender y recordar mejor, no solo para leer más rápido.</p>
              <p style="margin:0 0 12px 0;font-size:15px;line-height:1.55;color:#E9EDF5;"><strong style="color:#E9EDF5;">🧠 1. Intenta responder antes de revelar la respuesta.</strong><br><span style="color:#96a1b5;">En cada concepto encontrarás la sección "Pruébate". Antes de abrir la respuesta, intenta escribirla por tu cuenta. Ese pequeño esfuerzo fija el conocimiento mucho más que releer.</span></p>
              <p style="margin:0 0 6px 0;font-size:15px;line-height:1.55;color:#E9EDF5;"><strong style="color:#E9EDF5;">📅 2. Sigue el plan de repaso.</strong><br><span style="color:#96a1b5;">Al final encontrarás un plan sencillo para volver a revisar el contenido en los próximos días. Unos minutos de repaso valen más que memorizar todo de una vez.</span></p>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 36px 0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <p style="margin:0 0 18px 0;font-size:14.5px;line-height:1.6;color:#96a1b5;">Tu enlace estará disponible durante <strong style="color:#E9EDF5;">${d} días</strong>, para que vuelvas cuando lo necesites y estudies a tu ritmo.</p>
              <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#c3ccdb;">Gracias por confiar en nosotros.</p>
              <p style="margin:0 0 4px 0;font-size:14.5px;line-height:1.6;color:#96a1b5;">Esperamos que esta guía te ayude a comprender mejor el tema. Cuando la hayas usado, nos encantará saber cómo fue tu experiencia. Y si tienes cualquier duda, <strong style="color:#E9EDF5;">responde directamente a este correo</strong>. Estamos para ayudarte.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 36px 8px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <p style="margin:0 0 2px 0;font-size:15px;line-height:1.6;color:#E9EDF5;">Un abrazo,</p>
              <p style="margin:0;font-size:15px;font-weight:700;color:#E9EDF5;">Equipo Montaguth Institute</p>
            </td>
          </tr>
          <tr>
            <td style="padding:22px 36px 30px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <div style="border-top:1px solid rgba(255,255,255,0.08);padding-top:16px;">
                <p style="margin:0 0 4px 0;font-size:12.5px;color:#6b7688;">Montaguth Institute · <a href="https://montaguth.institute" style="color:#2DD4BF;text-decoration:none;">montaguth.institute</a></p>
                <p style="margin:0;font-size:11.5px;line-height:1.5;color:#5b6577;">Recibiste este correo porque compraste una guía en montaguth.institute.</p>
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
  const archivo = String(body?.archivo || "").trim();
  const temaBody = String(body?.tema || "").trim();
  if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);
  if (!archivo) return json({ error: "Falta el nombre del archivo de la guía." }, 400);

  const client = sb();
  const { data: row, error: errRow } = await client
    .from("pedidos").select("*").eq("pedido_id", pedidoId).maybeSingle();
  if (errRow) return json({ error: "Error leyendo el pedido: " + errRow.message }, 500);
  if (!row) return json({ error: "Pedido no encontrado." }, 404);
  if (!row.correo) return json({ error: "El pedido no tiene correo." }, 422);

  // CANDADO DE PAGO (invariante del proyecto: nada se entrega sin pago
  // aprobado). Aunque hoy el tablero solo lista pedidos aprobados/prueba, este
  // candado lo garantiza a nivel de SERVIDOR (defensa en profundidad): bloquea
  // entregar a un pedido sin pagar o REVERSADO/anulado tras la aprobación. Se
  // permite el correo de PRUEBA (equipo) para poder probar la entrega.
  if (row.estado_pago !== "aprobado" && !esCorreoPrueba(row.correo)) {
    return json({ error: "No se puede entregar: el pago de este pedido no está aprobado (estado: " + (row.estado_pago || "pendiente") + "). Solo se entrega con pago confirmado por Wompi." }, 409);
  }

  // Idempotencia: si ya se entregó por correo, no reenviar.
  if (row.correo_entrega_enviado) {
    return json({ ok: true, yaEnviado: true, pedido_id: pedidoId });
  }

  // Validar que la guía EXISTA en el bucket (evita enviar un enlace roto).
  const { error: errDl } = await client.storage.from(BUCKET_GUIAS).download(archivo);
  if (errDl) {
    return json({ error: "No encontré la guía \"" + archivo + "\" en el bucket. Revisa el nombre del archivo y que ya esté subida." }, 404);
  }

  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  if (!RESEND_API_KEY) return json({ error: "Falta configurar RESEND_API_KEY." }, 500);

  const nombre = row.nombre || "";
  const correo = String(row.correo);
  const dias = row.dias_acceso || 30;
  const tema = temaBody || row.tema || "tu materia";

  // Enlace privado firmado (misma firma que la función "entrega").
  const exp = Math.floor(Date.now() / 1000) + Number(dias) * 86400;
  const sig = await firmar(SECRET, `${archivo}.${exp}`);
  const enlace = `${VIEWER_URL}?f=${encodeURIComponent(archivo)}&exp=${exp}&sig=${sig}`;

  const prueba = esCorreoPrueba(correo);
  const asunto = (prueba ? "[TEST] " : "") + (nombre ? nombre + ", " : "") + "tu guía ya está lista.";

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
      html: construirHtml(nombre, tema, enlace, dias),
      text: construirTexto(nombre, tema, enlace, dias),
      headers: { "X-Entity-Ref-ID": pedidoId + "-entrega" },
    }),
  });

  if (!resp.ok) {
    const detalle = await resp.text().catch(() => "");
    return json({ error: "Resend respondió " + resp.status, detalle }, 502);
  }

  // Marca el pedido como entregado y guarda archivo/tema/fecha del envío.
  await client.from("pedidos").update({
    guia_entregada: true,
    fecha_entrega: new Date().toISOString(),
    guia_archivo: archivo,
    tema: tema,
    correo_entrega_enviado: new Date().toISOString(),
  }).eq("pedido_id", pedidoId);

  return json({ ok: true, pedido_id: pedidoId, enviado_a: correo, enlace, prueba });
});
