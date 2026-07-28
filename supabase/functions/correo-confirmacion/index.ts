// ============================================================
// Stramont · Correo automático de confirmación de compra (Correo 1 de 3)
// Se dispara desde checkout.html (Paso 4) tras registrar el pedido, y
// envía al CLIENTE un correo branded vía Resend.
//
// SEGURIDAD (por qué NO recibe datos ni secretos desde el navegador):
//   checkout.html es público. Si le pasáramos el LINK_SECRET quedaría
//   expuesto (protege informe/entrega). Y si aceptáramos "manda un correo
//   a X" desde el front, sería un relay de spam abierto sobre nuestro
//   dominio Resend. Por eso el navegador SOLO manda el pedido_id:
//     - El correo se envía a la dirección GUARDADA en ese pedido (no a la
//       que diga el navegador) -> imposible spamear a terceros.
//     - Se envía UNA sola vez por pedido (idempotencia con la columna
//       correo_confirmacion_enviado) -> nadie puede bombardear reenvíos.
//     - El enlace del Kit va fijo aquí (no inyectable).
//   La RESEND_API_KEY vive SOLO en Supabase Secrets; se lee del lado del
//   servidor y nunca sale de aquí.
//
//   POST { "pedido_id": "P30-260703-xxxx" }
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const FROM = "Montaguth Institute <notificaciones@send.montaguth.institute>";
const REPLY_TO = "contacto@montaguth.institute";
const ENLACE_KIT = "https://montaguth.institute/kit-stramont.zip";

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

// Misma regla de "correo de prueba" que usan checkout.html e informe.
function esCorreoPrueba(correo: string): boolean {
  const c = (correo || "").toLowerCase().trim();
  if (c === "pruebasmontaguth@gmail.com") return true;
  return c.startsWith("prueba") || c.endsWith("@example.com") || c.endsWith(".test");
}

// Escapa caracteres peligrosos en el HTML del correo. Construimos el "&"
// aparte (String.fromCharCode(38)) para que este código sea 100% seguro al
// copiar/pegar: no hay entidades HTML literales (&amp; &quot; ...) que un
// editor o render pueda "decodificar" y romper la sintaxis al pegarlo.
function esc(s: unknown): string {
  const A = String.fromCharCode(38);
  return String(s == null ? "" : s)
    .replace(/&/g, A + "amp;")
    .replace(/</g, A + "lt;")
    .replace(/>/g, A + "gt;")
    .replace(/"/g, A + "quot;");
}

// Versión de texto plano (multipart mejora la entregabilidad / anti-spam).
interface Comprobante { pedidoId: string; plan: string; monto: string; fecha: string; }

function fmtMonto(cents: number | null | undefined, moneda: string | null | undefined): string {
  if (!cents && cents !== 0) return "";
  const pesos = Number(cents) / 100;
  let s: string;
  try { s = pesos.toLocaleString("es-CO"); } catch { s = String(pesos); }
  return "$" + s + " " + (moneda || "COP");
}

function construirTexto(nombre: string, tema: string, dias: number | string, comp: Comprobante | null): string {
  const compLineas = comp ? [
    `--- Comprobante de pago ---`,
    `No. de pedido: ${comp.pedidoId}`,
    `Plan: ${comp.plan}`,
    `Monto pagado: ${comp.monto}`,
    `Fecha: ${comp.fecha}`,
    ``,
  ] : [];
  return [
    `Hola, ${nombre}.`,
    ``,
    `Todo salió bien. Ya recibimos tu pago y también el material de tu clase sobre ${tema}.`,
    ``,
    ...compLineas,
    `Desde este momento nuestro equipo empezará a convertirlos en una guía de estudio personalizada.`,
    ``,
    `¿Qué pasará ahora?`,
    `1. Revisaremos con cuidado el material de tu clase.`,
    `2. Prepararemos tu guía personalizada con el método Stramont.`,
    `3. La recibirás en menos de 24 horas, a este mismo correo. Estará disponible durante ${dias} días.`,
    ``,
    `Mientras tanto, aquí tienes un regalo: el Kit Stramont (plantillas para tomar apuntes con método científico).`,
    `Descárgalo aquí: ${ENLACE_KIT}`,
    ``,
    `Si hay algo importante que debamos tener en cuenta (un examen próximo, un tema que te cueste, etc.), responde este correo. Leemos cada mensaje.`,
    ``,
    `Gracias por confiar en nosotros. Nuestro objetivo no es resumir tu clase; es ayudarte a entenderla.`,
    ``,
    `Nos vemos en menos de 24 horas.`,
    `Equipo Montaguth Institute · montaguth.institute`,
  ].join("\n");
}

function construirHtml(nombre: string, tema: string, dias: number | string, comp: Comprobante | null): string {
  const n = esc(nombre);
  const t = esc(tema);
  const d = esc(dias);
  const fila = (k: string, v: string) =>
    `<tr><td style="padding:3px 0;color:#96a1b5;font-size:13px;">${esc(k)}</td><td style="padding:3px 0;text-align:right;color:#E9EDF5;font-size:13px;font-weight:700;">${esc(v)}</td></tr>`;
  const compHtml = comp ? `
          <tr>
            <td style="padding:6px 36px 0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <div style="border:1px solid rgba(255,255,255,0.10);border-radius:12px;padding:16px 18px;">
                <div style="font-size:12px;text-transform:uppercase;letter-spacing:1px;color:#2DD4BF;font-weight:700;margin-bottom:10px;">Comprobante de pago</div>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                  ${fila("No. de pedido", comp.pedidoId)}
                  ${fila("Plan", comp.plan)}
                  ${fila("Monto pagado", comp.monto)}
                  ${fila("Fecha", comp.fecha)}
                </table>
              </div>
            </td>
          </tr>` : "";
  const preheader = "Pago confirmado \u2713 \u00b7 Material recibido \u2713 \u00b7 Tu gu\u00eda llegar\u00e1 en menos de 24 horas.";
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>Ya recibimos el material de tu clase</title>
</head>
<body style="margin:0;padding:0;background-color:#0B1220;">
  <!-- preheader oculto (texto de preview en la bandeja) -->
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
              <h1 style="margin:0 0 6px 0;font-size:23px;line-height:1.3;color:#E9EDF5;font-weight:800;">Hola, ${n}.</h1>
              <p style="margin:0 0 18px 0;font-size:16px;line-height:1.6;color:#E9EDF5;">Todo salió bien.</p>
              <p style="margin:0 0 18px 0;font-size:15.5px;line-height:1.65;color:#c3ccdb;">Ya recibimos tu pago y también el material de tu clase sobre <strong style="color:#E9EDF5;">${t}</strong>.</p>
              <p style="margin:0 0 24px 0;font-size:15.5px;line-height:1.65;color:#c3ccdb;">Desde este momento nuestro equipo empezará a convertirlos en una guía de estudio personalizada, diseñada para ayudarte a comprender el tema con mayor claridad y estudiar de forma más organizada.</p>
            </td>
          </tr>${compHtml}
          <tr>
            <td style="padding:0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <div style="font-size:13px;text-transform:uppercase;letter-spacing:1px;color:#818CF8;font-weight:700;margin-bottom:14px;">¿Qué pasará ahora?</div>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                <tr><td style="padding:0 0 14px 0;color:#E9EDF5;font-size:15px;line-height:1.55;"><strong style="color:#E9EDF5;">1. Revisaremos con cuidado el material de tu clase.</strong><br><span style="color:#96a1b5;">Nos aseguraremos de entender el contenido antes de comenzar.</span></td></tr>
                <tr><td style="padding:0 0 14px 0;color:#E9EDF5;font-size:15px;line-height:1.55;"><strong style="color:#E9EDF5;">2. Prepararemos tu guía personalizada.</strong><br><span style="color:#96a1b5;">Aplicaremos el método Stramont para transformar el material de tu clase en una guía clara, visual y fácil de estudiar.</span></td></tr>
                <tr><td style="padding:0 0 6px 0;color:#E9EDF5;font-size:15px;line-height:1.55;"><strong style="color:#E9EDF5;">3. La recibirás en menos de 24 horas.</strong><br><span style="color:#96a1b5;">Te enviaremos un enlace privado a este mismo correo. Tu guía estará disponible durante <strong style="color:#E9EDF5;">${d} días</strong>, según el plan que elegiste.</span></td></tr>
              </table>
            </td>
          </tr>
          <tr><td style="padding:24px 36px;"><div style="height:1px;background-color:rgba(255,255,255,0.10);line-height:1px;font-size:1px;">&nbsp;</div></td></tr>
          <tr>
            <td style="padding:0 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#E9EDF5;">
              <p style="margin:0 0 8px 0;font-size:16px;font-weight:700;color:#E9EDF5;">Mientras tanto, aquí tienes un regalo.</p>
              <p style="margin:0 0 20px 0;font-size:15px;line-height:1.6;color:#c3ccdb;">Queremos que empieces a mejorar tu forma de estudiar incluso antes de recibir tu guía. Por eso preparamos el <strong style="color:#E9EDF5;">Kit Stramont</strong>, una colección de plantillas para tomar apuntes con método científico.</p>
              <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:10px;background-color:#2DD4BF;">
                <a href="${ENLACE_KIT}" style="display:inline-block;padding:13px 26px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:#0B1220;text-decoration:none;border-radius:10px;">Descargar mi Kit Stramont</a>
              </td></tr></table>
            </td>
          </tr>
          <tr><td style="padding:24px 36px;"><div style="height:1px;background-color:rgba(255,255,255,0.10);line-height:1px;font-size:1px;">&nbsp;</div></td></tr>
          <tr>
            <td style="padding:0 36px 8px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <p style="margin:0 0 18px 0;font-size:14.5px;line-height:1.6;color:#96a1b5;">Si hay algo importante que debamos tener en cuenta al preparar tu guía (un examen próximo, un tema que te esté costando o cualquier aclaración sobre tu material), simplemente <strong style="color:#E9EDF5;">responde este correo</strong>. Leemos personalmente cada mensaje.</p>
              <p style="margin:0 0 4px 0;font-size:15px;line-height:1.6;color:#c3ccdb;">Gracias por confiar en nosotros.</p>
              <p style="margin:0 0 18px 0;font-size:15px;line-height:1.6;color:#c3ccdb;">Nuestro objetivo no es resumir tu clase; es ayudarte a entenderla.</p>
              <p style="margin:0 0 4px 0;font-size:15px;line-height:1.6;color:#E9EDF5;">Nos vemos en menos de 24 horas.</p>
              <p style="margin:0 0 4px 0;font-size:15px;font-weight:700;color:#E9EDF5;">Equipo Montaguth Institute</p>
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

  // CANDADO DE PAGO (invariante del proyecto: nada ocurre sin pago aprobado).
  // El Correo 1 dice "ya recibimos tu pago" e incluye el comprobante: JAMÁS
  // debe salir si el pago no está confirmado por el webhook verificado. Este
  // endpoint es PÚBLICO (solo recibe pedido_id), así que sin este candado
  // alguien podría disparar un falso "pago recibido" a un correo con solo
  // adivinar un pedido_id, o un cambio futuro podría llamarlo antes de aprobar.
  // En operación normal el webhook lo llama SOLO tras marcar 'aprobado', así
  // que esto no cambia el flujo real; solo cierra el hueco. Se permite el
  // correo de PRUEBA (direcciones del equipo) para no romper el flujo de
  // pruebas/simulación.
  if (row.estado_pago !== "aprobado" && !esCorreoPrueba(row.correo)) {
    return json({ ok: false, noAprobado: true, estado_pago: row.estado_pago || null, pedido_id: pedidoId }, 409);
  }

  // Idempotencia: si ya se envió, no reenviar.
  if (row.correo_confirmacion_enviado) {
    return json({ ok: true, yaEnviado: true, pedido_id: pedidoId });
  }

  const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
  if (!RESEND_API_KEY) return json({ error: "Falta configurar RESEND_API_KEY." }, 500);

  const nombre = row.nombre || "";
  const correo = String(row.correo);
  const dias = row.dias_acceso || "";
  const tema = "tu materia"; // el tema no se conoce en el momento de la compra
  // Comprobante de pago: solo si el pedido ya tiene datos de pago (flujo Wompi
  // por webhook). En modo simulación (sin monto) NO se muestra -> correo igual que antes.
  const comp: Comprobante | null = (row.monto_cents !== null && row.monto_cents !== undefined) ? {
    pedidoId: String(row.pedido_id || pedidoId),
    plan: String(row.plan || ("Acceso " + (row.dias_acceso || "") + " días")),
    monto: fmtMonto(row.monto_cents, row.moneda),
    fecha: row.pagado_en ? new Date(row.pagado_en).toLocaleString("es-CO") : new Date().toLocaleString("es-CO"),
  } : null;
  const prueba = esCorreoPrueba(correo);
  const asunto = (prueba ? "[TEST] " : "") + (nombre ? nombre + ", " : "") + "ya recibimos el material de tu clase.";

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
      html: construirHtml(nombre, tema, dias, comp),
      text: construirTexto(nombre, tema, dias, comp),
      headers: { "X-Entity-Ref-ID": pedidoId },
    }),
  });

  if (!resp.ok) {
    const detalle = await resp.text().catch(() => "");
    return json({ error: "Resend respondió " + resp.status, detalle }, 502);
  }

  // Marca idempotencia (no bloquea la respuesta de éxito si esto fallara).
  await client.from("pedidos")
    .update({ correo_confirmacion_enviado: new Date().toISOString() })
    .eq("pedido_id", pedidoId);

  return json({ ok: true, pedido_id: pedidoId, enviado_a: correo, prueba });
});
