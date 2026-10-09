// ============================================================================
// MAGANDHI · Edge Function · enviar-correo-pedido (correos transaccionales)
// ----------------------------------------------------------------------------
// La llama el BACK-OFFICE (montaguth.institute) con la sesion del usuario de
// Ventas. Tres modos:
//
//   { modo: "pedido", pedido_id, etapa, reenviar? }
//       Envia al CLIENTE el correo de esa etapa del pedido.
//   { modo: "prueba", etapa, borrador? }
//       Envia la etapa al correo del PROPIO usuario, con datos de ejemplo.
//   { modo: "vista",  etapa, borrador }
//       Devuelve el HTML del correo para previsualizar. No envia nada.
//   { modo: "automatico", pedido_id }            (F3 · solo servidor)
//       Lo llama wompi-webhook con la LLAVE DE SERVICIO cuando un pago web crea
//       un pedido: envia el «Recibido» de ese pedido web una sola vez.
//
// Etapas: recibido | preparando | en_camino | entregado.
//
// ============================================================================
// LINEA ROJA DE SEGURIDAD (orden permanente del dueno · NO negociable):
//   - RESEND_API_KEY vive SOLO en Supabase Secrets. Nunca se devuelve ni se
//     registra en logs.
//   - Las PERSONAS nunca pasan por service_role: sus modos llaman a los RPC con
//     el JWT del usuario, asi que tiene_acceso_ventas() y auth.uid() se evaluan
//     de verdad en la base. El unico camino de servicio es el modo automatico
//     (F3), que solo se abre con la llave de servicio y que la base limita al
//     «Recibido» de pedidos web.
//   - El destinatario sale de la BASE (clientes.correo / auth.users), nunca del
//     navegador: no se puede usar para escribirle a cualquier direccion.
//   - El codigo de reseña solo viaja dentro del correo de "entregado"; no se
//     registra en logs ni se devuelve al navegador.
// ============================================================================

// supabase-js pineado a la version EXACTA del proyecto (regla B2).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

// Sobrescribible solo para pruebas locales con un simulador; en produccion no se
// define y se usa la API real.
const RESEND_ENDPOINT = Deno.env.get("RESEND_API_URL") ??
  "https://api.resend.com/emails";

// Configurables por Secrets sin tocar codigo (con valores por defecto sanos).
const REMITENTE = Deno.env.get("CORREO_REMITENTE") ??
  "MAGANDHI <orders@updates.magandhi.com>";
const RESPONDER_A = Deno.env.get("CORREO_RESPONDER_A") ??
  "contacto@magandhi.com";
const TIENDA = (Deno.env.get("TIENDA_URL") ?? "https://magandhi.com")
  .replace(/\/+$/, "");
const WHATSAPP = Deno.env.get("CORREO_WHATSAPP_URL") ??
  "https://wa.me/573132451188";

const ETAPAS = ["recibido", "preparando", "en_camino", "entregado"] as const;
type Etapa = typeof ETAPAS[number];

// ----------------------------------------------------------------------------
// CORS: solo el back-office (y el subdominio de GitHub Pages de desarrollo).
// ----------------------------------------------------------------------------
const ORIGENES_PERMITIDOS = new Set<string>([
  "https://montaguth.institute",
  "https://www.montaguth.institute",
  "https://12344-ux.github.io",
]);

function cabecerasCors(origin: string | null): Record<string, string> {
  const permitido = origin && ORIGENES_PERMITIDOS.has(origin)
    ? origin
    : "https://montaguth.institute";
  return {
    "Access-Control-Allow-Origin": permitido,
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(
  cuerpo: unknown,
  status: number,
  cors: Record<string, string>,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

// ----------------------------------------------------------------------------
// Errores estables de los RPC (CORREO_*) -> mensaje claro + HTTP.
// ----------------------------------------------------------------------------
function traducirError(mensaje: string): { status: number; texto: string } {
  const m = mensaje || "";
  const tabla: Array<[string, number, string]> = [
    ["CORREO_SIN_ACCESO", 403, "Tu usuario no tiene acceso al área de Ventas."],
    ["CORREO_ETAPA_INVALIDA", 400, "Etapa de correo inválida."],
    ["CORREO_PEDIDO_NO_EXISTE", 404, "El pedido no existe."],
    ["CORREO_PEDIDO_ANULADO", 409, "El pedido está anulado; no se envían correos."],
    ["CORREO_ETAPA_NO_ALCANZADA", 409, "El pedido todavía no llega a esa etapa. Avanza su estado primero."],
    ["CORREO_CLIENTE_SIN_CORREO", 409, "El cliente no tiene un correo válido registrado."],
    ["CORREO_SIN_PLANTILLA", 500, "Falta la plantilla de esa etapa."],
    ["CORREO_EN_CURSO", 409, "Ese correo se está enviando en este momento. Espera unos segundos."],
    ["CORREO_YA_ENVIADO", 409, "Ese correo ya se envió. Usa «Reenviar» si de verdad hace falta."],
    ["CORREO_ENVIO_NO_PENDIENTE", 409, "Ese envío ya estaba cerrado."],
    ["CORREO_SOLO_WEB", 409, "El correo automático es solo para pedidos web."],
  ];
  for (const [clave, status, texto] of tabla) {
    if (m.includes(clave)) return { status, texto };
  }
  return { status: 500, texto: "No se pudo preparar el correo." };
}

// ----------------------------------------------------------------------------
// Construccion del correo (HTML + texto plano). Todo lo variable se escapa.
// ----------------------------------------------------------------------------
type Plantilla = {
  asunto: string;
  preheader: string | null;
  titulo: string;
  cuerpo: string;
  boton_texto: string | null;
};
type Item = {
  nombre: string;
  cantidad: number;
  subtotal: number;
  slug: string | null;
};
type Datos = {
  etapa: Etapa;
  nombre: string;
  pedido: string;
  total: number;
  items: Item[];
  direccion: string | null;
  codigo_resena: string | null;
  plantilla: Plantilla;
  es_prueba: boolean;
};

function esc(s: unknown): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function variables(texto: string, d: Datos): string {
  return (texto || "")
    .replaceAll("{nombre}", d.nombre || "")
    .replaceAll("{pedido}", d.pedido || "");
}

function cop(n: number): string {
  const v = Math.round(Number(n) || 0);
  return "$" + v.toLocaleString("es-CO").replace(/,/g, ".");
}

function parrafos(texto: string): string[] {
  return (texto || "").split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
}

const NOMBRE_ETAPA: Record<Etapa, string> = {
  recibido: "Recibido",
  preparando: "Preparando",
  en_camino: "En camino",
  entregado: "Entregado",
};

const FUENTE =
  "font-family:Poppins,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";

function enlaceResena(d: Datos): string | null {
  if (!d.codigo_resena) return null;
  const conSlug = d.items.find((i) => i.slug);
  if (!conSlug) return null;
  // El codigo va en el FRAGMENTO (#): no se envia a ningun servidor ni queda en
  // el Referer. La tienda lo lee, prellena el formulario y lo borra de la URL.
  return `${TIENDA}/producto/?slug=${encodeURIComponent(conSlug.slug!)}` +
    `#resena=${encodeURIComponent(d.codigo_resena)}`;
}

function construirAsunto(d: Datos): string {
  const base = variables(d.plantilla.asunto, d);
  return d.es_prueba ? `[Prueba] ${base}` : base;
}

function construirHtml(d: Datos): string {
  const pl = d.plantilla;
  const titulo = esc(variables(pl.titulo, d));
  const pre = esc(variables(pl.preheader ?? "", d));
  const cuerpoHtml = parrafos(variables(pl.cuerpo, d))
    .map((p) =>
      `<p style="margin:0 0 16px 0;font-size:15px;line-height:1.65;color:#3A3A3A;">${
        esc(p).replace(/\n/g, "<br>")
      }</p>`
    ).join("");

  // Linea de progreso: 4 etapas, la actual y las anteriores marcadas.
  const idx = ETAPAS.indexOf(d.etapa);
  const progreso = ETAPAS.map((e, i) => {
    const hecho = i <= idx;
    return `<td align="center" style="${FUENTE}padding:0 2px;">
      <div style="height:4px;border-radius:2px;background-color:${
      hecho ? "#A6332E" : "#E4DCD1"
    };"></div>
      <div style="margin-top:6px;font-size:11px;letter-spacing:.02em;color:${
      hecho ? "#111111" : "#9A9086"
    };font-weight:${i === idx ? "600" : "400"};">${esc(NOMBRE_ETAPA[e])}</div>
    </td>`;
  }).join("");

  const filasItems = d.items.map((it) =>
    `<tr>
      <td style="${FUENTE}padding:6px 0;font-size:14px;color:#111111;">${
      esc(it.nombre)
    } <span style="color:#9A9086;">× ${esc(it.cantidad)}</span></td>
      <td align="right" style="${FUENTE}padding:6px 0;font-size:14px;color:#111111;white-space:nowrap;">${
      esc(cop(it.subtotal))
    }</td>
    </tr>`
  ).join("");

  const resumen = `
    <tr><td style="padding:8px 36px 0 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #EDE6DC;border-bottom:1px solid #EDE6DC;">
        <tr><td colspan="2" style="${FUENTE}padding:14px 0 4px 0;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#9A9086;font-weight:600;">Pedido ${
    esc(d.pedido)
  }</td></tr>
        ${filasItems}
        <tr>
          <td style="${FUENTE}padding:8px 0 14px 0;font-size:14px;color:#111111;font-weight:600;">Total</td>
          <td align="right" style="${FUENTE}padding:8px 0 14px 0;font-size:14px;color:#111111;font-weight:600;">${
    esc(cop(d.total))
  }</td>
        </tr>
        ${
    d.direccion
      ? `<tr><td colspan="2" style="${FUENTE}padding:0 0 14px 0;font-size:13px;color:#6B635B;">Entrega: ${
        esc(d.direccion)
      }</td></tr>`
      : ""
  }
      </table>
    </td></tr>`;

  // Bloque del codigo de reseña (solo entregado). UN solo boton: patron
  // transaccional que entra a la bandeja principal (leccion de Stramont).
  let bloqueResena = "";
  if (d.etapa === "entregado" && d.codigo_resena) {
    const url = enlaceResena(d);
    const boton = esc(pl.boton_texto || "Dejar mi opinión");
    bloqueResena = `
    <tr><td style="padding:22px 36px 0 36px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #D9AE6E;border-radius:12px;">
        <tr><td align="center" style="${FUENTE}padding:18px 18px 6px 18px;font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:#9A9086;font-weight:600;">Tu código de reseña</td></tr>
        <tr><td align="center" style="padding:0 18px 16px 18px;font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:20px;letter-spacing:.08em;color:#111111;font-weight:700;">${
      esc(d.codigo_resena)
    }</td></tr>
        ${
      url
        ? `<tr><td align="center" style="padding:0 18px 20px 18px;">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:10px;background-color:#A6332E;">
            <a href="${
          esc(url)
        }" style="${FUENTE}display:inline-block;padding:13px 30px;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:10px;">${boton}</a>
          </td></tr></table>
        </td></tr>`
        : `<tr><td align="center" style="${FUENTE}padding:0 18px 18px 18px;font-size:13px;color:#6B635B;">Ingrésalo en la página del producto, en «Dejar una reseña».</td></tr>`
    }
      </table>
    </td></tr>`;
  }

  const avisoPrueba = d.es_prueba
    ? `<tr><td style="${FUENTE}padding:10px 36px;background-color:#111111;color:#FFFFFF;font-size:12px;text-align:center;">Correo de PRUEBA con datos de ejemplo. No corresponde a un pedido real.</td></tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${titulo}</title>
</head>
<body style="margin:0;padding:0;background-color:#EFE7DD;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;font-size:1px;line-height:1px;color:#EFE7DD;">${pre}</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#EFE7DD;">
    <tr><td align="center" style="padding:28px 12px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background-color:#FFFFFF;border-radius:16px;overflow:hidden;">
        ${avisoPrueba}
        <tr><td align="center" style="padding:30px 36px 6px 36px;">
          <img src="${TIENDA}/logo-mark-terracota.png" width="44" height="44" alt="" style="display:block;border:0;width:44px;height:44px;">
          <div style="${FUENTE}margin-top:10px;font-size:15px;letter-spacing:.32em;font-weight:600;color:#111111;">MAG<span style="color:#A6332E;">A</span>NDHI</div>
        </td></tr>
        <tr><td style="padding:22px 36px 4px 36px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>${progreso}</tr></table>
        </td></tr>
        <tr><td style="${FUENTE}padding:24px 36px 0 36px;">
          <h1 style="margin:0 0 16px 0;font-size:22px;line-height:1.3;color:#111111;font-weight:600;">${titulo}</h1>
          ${cuerpoHtml}
        </td></tr>
        ${bloqueResena}
        ${resumen}
        <tr><td style="${FUENTE}padding:20px 36px 30px 36px;font-size:13px;line-height:1.6;color:#6B635B;">
          ¿Dudas? Responde este correo o escríbenos por <a href="${
    esc(WHATSAPP)
  }" style="color:#A6332E;text-decoration:underline;">WhatsApp</a>.
        </td></tr>
      </table>
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;">
        <tr><td align="center" style="${FUENTE}padding:18px 24px 0 24px;font-size:11.5px;line-height:1.6;color:#8A8076;">
          MAGANDHI · Tunja, Colombia · <a href="${TIENDA}" style="color:#8A8076;">magandhi.com</a><br>
          Recibes este correo porque hiciste un pedido en MAGANDHI. Es un aviso sobre tu compra, no publicidad.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function construirTexto(d: Datos): string {
  const pl = d.plantilla;
  const lineas: string[] = [];
  if (d.es_prueba) lineas.push("[CORREO DE PRUEBA · datos de ejemplo]", "");
  lineas.push(variables(pl.titulo, d), "");
  for (const p of parrafos(variables(pl.cuerpo, d))) lineas.push(p, "");
  if (d.etapa === "entregado" && d.codigo_resena) {
    lineas.push(`Tu código de reseña: ${d.codigo_resena}`);
    const url = enlaceResena(d);
    if (url) lineas.push(`${pl.boton_texto || "Dejar mi opinión"}: ${url}`);
    lineas.push("");
  }
  lineas.push(`Pedido ${d.pedido}`);
  for (const it of d.items) {
    lineas.push(`- ${it.nombre} × ${it.cantidad}: ${cop(it.subtotal)}`);
  }
  lineas.push(`Total: ${cop(d.total)}`);
  if (d.direccion) lineas.push(`Entrega: ${d.direccion}`);
  lineas.push(
    "",
    `¿Dudas? Responde este correo o escríbenos por WhatsApp: ${WHATSAPP}`,
    "",
    "MAGANDHI · Tunja, Colombia · magandhi.com",
    "Recibes este correo porque hiciste un pedido en MAGANDHI. Es un aviso sobre tu compra, no publicidad.",
  );
  return lineas.join("\n");
}

// Borrador del editor (modo vista/prueba) normalizado y acotado.
function leerBorrador(b: unknown): Plantilla | null {
  if (!b || typeof b !== "object") return null;
  const o = b as Record<string, unknown>;
  const t = (k: string, max: number) =>
    typeof o[k] === "string" ? (o[k] as string).trim().slice(0, max) : "";
  const asunto = t("asunto", 150);
  const titulo = t("titulo", 150);
  const cuerpo = t("cuerpo", 4000);
  if (!asunto || !titulo || !cuerpo) return null;
  return {
    asunto,
    titulo,
    cuerpo,
    preheader: t("preheader", 200) || null,
    boton_texto: t("boton_texto", 40) || null,
  };
}

function datosEjemplo(etapa: Etapa, pl: Plantilla): Datos {
  return {
    etapa,
    nombre: "Prueba",
    pedido: "#PRUEBA01",
    total: 32900,
    // Slug de ejemplo para que la vista previa muestre el boton de opinion.
    items: [{ nombre: "Producto de ejemplo", cantidad: 1, subtotal: 32900, slug: "ejemplo" }],
    direccion: "Calle de ejemplo 1-23, Tunja",
    codigo_resena: etapa === "entregado" ? "MG-EJEMPLO000" : null,
    plantilla: pl,
    es_prueba: true,
  };
}

// ----------------------------------------------------------------------------
// Envio a Resend. Idempotency-Key = envio_id: si la peticion se repite, Resend
// no manda dos correos.
// ----------------------------------------------------------------------------
async function enviarResend(
  apiKey: string,
  envioId: string,
  destinatario: string,
  d: Datos,
): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  try {
    const r = await fetch(RESEND_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": envioId,
      },
      body: JSON.stringify({
        from: REMITENTE,
        to: [destinatario],
        reply_to: RESPONDER_A,
        subject: construirAsunto(d),
        html: construirHtml(d),
        text: construirTexto(d),
        tags: [
          { name: "tipo", value: d.es_prueba ? "prueba" : "pedido" },
          { name: "etapa", value: d.etapa },
        ],
      }),
    });
    const cuerpo = await r.json().catch(() => ({}));
    if (!r.ok) {
      const msg = (cuerpo as { message?: string })?.message ??
        `HTTP ${r.status}`;
      return { ok: false, error: `Resend: ${msg}` };
    }
    return { ok: true, id: String((cuerpo as { id?: string })?.id ?? "") };
  } catch (e) {
    return { ok: false, error: `Sin conexión con Resend: ${String(e)}` };
  }
}

// ----------------------------------------------------------------------------
// F3 · MODO AUTOMATICO (servidor a servidor)
// ----------------------------------------------------------------------------
// Lo llama wompi-webhook cuando un pago web aprobado crea un pedido. No hay
// persona detras, asi que no hay sesion: se autentica con la LLAVE DE SERVICIO
// (ya vive en el entorno de las dos funciones; nunca viaja al navegador).
// Alcance minimo, impuesto por la base (correo_auto_recibido_preparar):
// solo el correo «Recibido», solo de pedidos WEB, al correo que esta en la base
// y una sola vez por pedido. Las personas siguen usando los modos de siempre.
// ----------------------------------------------------------------------------
const enc = new TextEncoder();

/** Comparacion en tiempo constante (no revela donde difieren). */
function igualesTiempoConstante(a: string, b: string): boolean {
  const x = enc.encode(a), y = enc.encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function modoAutomatico(
  req: Request,
  supabaseUrl: string,
  llave: string,
  cors: Record<string, string>,
): Promise<Response> {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body inválido; se esperaba JSON." }, 400, cors);
  }
  const pedidoId = String(body?.pedido_id ?? "");
  if (body?.modo !== "automatico" || !UUID.test(pedidoId)) {
    return json({ error: "Solicitud automática inválida." }, 400, cors);
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.error("[enviar-correo-pedido] automatico: falta RESEND_API_KEY.");
    return json({ error: "Correo sin configurar.", estado: "sin_configurar" }, 503, cors);
  }

  // Cliente de servicio: apikey Y Authorization = llave de servicio, para que
  // PostgREST resuelva service_role (leccion de Wompi F1).
  const sb = createClient(supabaseUrl, llave, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${llave}`, apikey: llave } },
  });

  const { data: prep, error: prepErr } = await sb.rpc("correo_auto_recibido_preparar", {
    p_pedido_id: pedidoId,
  });
  if (prepErr || !prep) {
    const m = prepErr?.message ?? "";
    // Lo que ya esta resuelto no es un error: el correo salio o esta saliendo.
    const tranquilos: Array<[string, string]> = [
      ["CORREO_YA_ENVIADO", "ya_enviado"],
      ["CORREO_EN_CURSO", "en_curso"],
      ["CORREO_CLIENTE_SIN_CORREO", "sin_correo"],
    ];
    for (const [clave, estado] of tranquilos) {
      if (m.includes(clave)) {
        console.log(`[enviar-correo-pedido] automatico: ${estado}`);
        return json({ ok: true, estado }, 200, cors);
      }
    }
    console.error("[enviar-correo-pedido] automatico: no se pudo preparar:", JSON.stringify({
      message: m || null,
      code: (prepErr as { code?: string } | null)?.code ?? null,
    }));
    const t = traducirError(m);
    return json({ error: t.texto, estado: "no_preparado" }, t.status, cors);
  }

  const p = prep as Record<string, unknown>;
  const envioId = String(p.envio_id);
  const datos: Datos = {
    etapa: "recibido",
    nombre: String(p.nombre ?? ""),
    pedido: String(p.pedido ?? ""),
    total: Number(p.total ?? 0),
    items: Array.isArray(p.items) ? (p.items as Item[]) : [],
    direccion: (p.direccion as string) || null,
    codigo_resena: null,
    plantilla: p.plantilla as Plantilla,
    es_prueba: false,
  };

  const res = await enviarResend(resendKey, envioId, String(p.destinatario), datos);

  const { error: cierreErr } = await sb.rpc("correo_auto_resultado", {
    p_envio_id: envioId,
    p_ok: res.ok,
    p_proveedor_id: res.ok ? res.id : null,
    p_error: res.ok ? null : res.error,
  });
  if (cierreErr) {
    // El correo pudo salir; queda 'pendiente' y se cierra como huerfano a los
    // 10 min. Se avisa para no reenviar a ciegas.
    console.error("[enviar-correo-pedido] automatico: fallo al cerrar envio:", JSON.stringify({
      envio_id: envioId,
      message: cierreErr.message,
    }));
  }

  console.log("[enviar-correo-pedido]", JSON.stringify({
    modo: "automatico",
    etapa: "recibido",
    envio_id: envioId,
    ok: res.ok,
  }));

  if (!res.ok) {
    return json({ error: `No se pudo enviar: ${res.error}`, estado: "fallido" }, 502, cors);
  }
  return json({ ok: true, estado: "enviado", envio_id: envioId }, 200, cors);
}

// ----------------------------------------------------------------------------
// Handler
// ----------------------------------------------------------------------------
Deno.serve(async (req: Request): Promise<Response> => {
  const cors = cabecerasCors(req.headers.get("origin"));

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Método no permitido; usa POST." }, 405, cors);
  }

  // --- Sesion del usuario (obligatoria en los tres modos) -------------------
  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  // F3: el servidor (wompi-webhook) se identifica con la llave de servicio. Se
  // elige el camino por la CREDENCIAL, no por lo que diga el cuerpo.
  const llaveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (supabaseUrl && llaveServicio && jwt && igualesTiempoConstante(jwt, llaveServicio)) {
    return await modoAutomatico(req, supabaseUrl, llaveServicio, cors);
  }

  const apiKey = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !apiKey) {
    return json({ error: "Configuración del servidor incompleta (Supabase)." }, 500, cors);
  }
  if (!jwt) {
    return json({ error: "Inicia sesión para enviar correos." }, 401, cors);
  }

  // Cliente con el JWT del USUARIO: los RPC corren como authenticated y
  // auth.uid() es el usuario real (sin service_role).
  const supabase = createClient(supabaseUrl, apiKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: u, error: uErr } = await supabase.auth.getUser(jwt);
  if (uErr || !u?.user) {
    return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, cors);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body inválido; se esperaba JSON." }, 400, cors);
  }

  const modo = String(body?.modo ?? "pedido");
  const etapa = String(body?.etapa ?? "") as Etapa;
  if (!ETAPAS.includes(etapa)) {
    return json({ error: "Etapa de correo inválida." }, 400, cors);
  }

  // --- MODO VISTA: solo renderiza (no reserva ni envia) ---------------------
  if (modo === "vista") {
    const pl = leerBorrador(body?.borrador);
    if (!pl) {
      return json({ error: "Completa asunto, título y cuerpo para previsualizar." }, 400, cors);
    }
    const d = datosEjemplo(etapa, pl);
    return json({ asunto: construirAsunto(d), html: construirHtml(d) }, 200, cors);
  }

  if (modo !== "pedido" && modo !== "prueba") {
    return json({ error: "Modo inválido." }, 400, cors);
  }

  // Sin llave de Resend no se reserva nada: mensaje claro para el panel.
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    return json({
      error: "El envío de correos aún no está configurado (falta RESEND_API_KEY en Supabase Secrets).",
    }, 503, cors);
  }

  // --- Reservar el envio en la base (valida todo server-side) ---------------
  const rpc = modo === "pedido"
    ? supabase.rpc("correo_pedido_preparar", {
      p_pedido_id: String(body?.pedido_id ?? ""),
      p_etapa: etapa,
      p_reenviar: body?.reenviar === true,
    })
    : supabase.rpc("correo_prueba_preparar", {
      p_etapa: etapa,
      p_borrador: leerBorrador(body?.borrador),
    });

  const { data: prep, error: prepErr } = await rpc;
  if (prepErr || !prep) {
    console.error("[enviar-correo-pedido] Fallo al preparar:", JSON.stringify({
      modo,
      etapa,
      message: prepErr?.message ?? null,
      code: (prepErr as { code?: string } | null)?.code ?? null,
      details: (prepErr as { details?: string } | null)?.details ?? null,
      hint: (prepErr as { hint?: string } | null)?.hint ?? null,
    }));
    const t = traducirError(prepErr?.message ?? "");
    return json({ error: t.texto }, t.status, cors);
  }

  const p = prep as Record<string, unknown>;
  const envioId = String(p.envio_id);
  const destinatario = String(p.destinatario);
  const datos: Datos = {
    etapa,
    nombre: String(p.nombre ?? ""),
    pedido: String(p.pedido ?? ""),
    total: Number(p.total ?? 0),
    items: Array.isArray(p.items) ? (p.items as Item[]) : [],
    direccion: (p.direccion as string) || null,
    codigo_resena: (p.codigo_resena as string) || null,
    plantilla: p.plantilla as Plantilla,
    es_prueba: p.es_prueba === true,
  };

  // --- Entregar a Resend ----------------------------------------------------
  const res = await enviarResend(resendKey, envioId, destinatario, datos);

  // --- Cerrar el envio en la bitacora ---------------------------------------
  const { error: cierreErr } = await supabase.rpc("correo_pedido_resultado", {
    p_envio_id: envioId,
    p_ok: res.ok,
    p_proveedor_id: res.ok ? res.id : null,
    p_error: res.ok ? null : res.error,
  });
  if (cierreErr) {
    // El correo pudo salir; queda 'pendiente' y el RPC lo cerrara como huerfano
    // a los 10 min. Se avisa para no reenviar a ciegas.
    console.error("[enviar-correo-pedido] Fallo al cerrar envio:", JSON.stringify({
      envio_id: envioId,
      message: cierreErr.message,
    }));
  }

  console.log("[enviar-correo-pedido]", JSON.stringify({
    modo,
    etapa,
    envio_id: envioId,
    ok: res.ok,
  }));

  if (!res.ok) {
    return json({ error: `No se pudo enviar: ${res.error}` }, 502, cors);
  }
  return json({ ok: true, envio_id: envioId, destinatario }, 200, cors);
});
