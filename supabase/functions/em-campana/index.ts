// ============================================================================
// MAGANDHI · Edge Function · em-campana (Email marketing · campanas, EM4)
// ----------------------------------------------------------------------------
// La llama el back-office con la sesion del usuario. Modos:
//   vista        { asunto, preheader, contenido }       -> HTML de la vista previa
//   prueba       { campana_id?, asunto, preheader, contenido } -> envia a TU correo
//   confirmar    { campana_id, n, programada_para? }   -> congela la audiencia
//   sincronizar  { campana_id }                        -> sube una tanda de
//                contactos al segmento de Resend de la campana (repetir hasta 0)
//   enviar       { campana_id }                        -> crea y envia/programa
//                el Broadcast en Resend
//   cancelar     { campana_id, motivo }                -> cancela (y en Resend
//                si estaba programada)
//
// LINEA ROJA: RESEND_MARKETING_API_KEY solo en Secrets; nunca se devuelve ni
// se loguea. Sin service_role: todo pasa por RPC con el JWT del usuario.
// El boton final lo pulsa una persona (confirmar exige el N que vio).
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const API = (Deno.env.get("RESEND_API_URL_BASE") ?? "https://api.resend.com").replace(/\/+$/, "");
const REMITENTE = Deno.env.get("CORREO_MARKETING_REMITENTE") ?? "MAGANDHI <novedades@news.magandhi.com>";
const RESPONDER_A = Deno.env.get("CORREO_RESPONDER_A") ?? "contacto@magandhi.com";
const TIENDA = (Deno.env.get("TIENDA_URL") ?? "https://magandhi.com").replace(/\/+$/, "");
const PAUSA_MS = Number(Deno.env.get("RESEND_PAUSA_MS") ?? "220"); // < 10 req/s del plan

const ORIGENES = new Set(["https://montaguth.institute", "https://www.montaguth.institute", "https://12344-ux.github.io"]);
function cors(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin && ORIGENES.has(origin) ? origin : "https://montaguth.institute",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (b: unknown, s: number, c: Record<string, string>) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...c, "Content-Type": "application/json; charset=utf-8" } });

const ERRORES: Array<[string, number, string]> = [
  ["EM_SIN_ACCESO", 403, "Tu usuario no tiene el permiso de Email marketing."],
  ["EM_POLITICA_PENDIENTE", 409, "Las campañas se habilitan cuando la política de tratamiento de datos esté publicada. Regístrala en el Resumen de Email marketing."],
  ["EM_AUDIENCIA_CAMBIO", 409, "La audiencia cambió mientras revisabas. Vuelve a revisar el número de destinatarios."],
  ["EM_SIN_DESTINATARIOS", 409, "Nadie de este segmento está suscrito al tema elegido."],
  ["EM_CAMPANA_INCOMPLETA", 400, "La campaña está incompleta: revisa asunto, segmento, tema y que cada bloque tenga su contenido."],
  ["EM_CONTENIDO_INVALIDO", 400, "Algún bloque tiene un contenido no válido (los enlaces deben empezar por https://)."],
  ["EM_CAMPANA_NO_EDITABLE", 409, "Esta campaña ya no es un borrador."],
  ["EM_CAMPANA_YA_ENVIADA", 409, "Esta campaña ya se envió."],
  ["EM_CAMPANA_EN_CURSO", 409, "El envío ya está en curso. Espera unos segundos."],
  ["EM_CAMPANA_SIN_SINCRONIZAR", 409, "Faltan contactos por preparar."],
  ["EM_CAMPANA_NO_CANCELABLE", 409, "Esta campaña ya no se puede cancelar."],
  ["EM_PROGRAMACION_INVALIDA", 400, "Programa el envío entre 5 minutos y 30 días desde ahora."],
  ["EM_CAMPANA_NO_EXISTE", 404, "La campaña no existe."],
];
function traducir(m: string) {
  for (const [k, s, t] of ERRORES) if ((m || "").includes(k)) return { status: s, texto: t, codigo: k };
  return { status: 500, texto: "No se pudo completar la operación.", codigo: "EM_ERROR" };
}

// ----------------------------------------------------------------------------
// Render
// ----------------------------------------------------------------------------
type Bloque = Record<string, unknown> & { tipo: string };
type Producto = { slug: string; nombre: string; precio_venta: number | null; imagen: string | null; agotado: boolean };

const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const cop = (n: unknown) => "$" + Math.round(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
const F = "font-family:Poppins,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";

// {nombre} y {nombre|alternativa}. modo 'resend' -> marcador de Resend; 'muestra' -> nombre de ejemplo.
function nombres(textoEscapado: string, modo: "resend" | "muestra", ejemplo: string) {
  return textoEscapado.replace(/\{nombre(?:\|([^{}]{0,40}))?\}/g, (_m, alt) => {
    const a = String(alt ?? "").replace(/[|{}]/g, "");
    return modo === "resend" ? "{{{contact.first_name|" + a + "}}}" : (ejemplo || a);
  });
}

function conUtm(url: string, utm: string) {
  try {
    const u = new URL(url);
    if (!/(^|\.)magandhi\.com$/.test(u.hostname)) return url;
    u.searchParams.set("utm_source", "email");
    u.searchParams.set("utm_medium", "email");
    u.searchParams.set("utm_campaign", utm);
    return u.toString();
  } catch { return url; }
}

function boton(texto: string, url: string) {
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:6px auto 22px auto;"><tr><td style="border-radius:10px;background-color:#A6332E;">
    <a href="${esc(url)}" style="${F}display:inline-block;padding:14px 32px;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none;border-radius:10px;">${esc(texto)}</a></td></tr></table>`;
}

function renderBloques(bl: Bloque[], prods: Map<string, Producto>, utm: string, modo: "resend" | "muestra", ejemplo: string) {
  const n = (s: string) => nombres(s, modo, ejemplo);
  return bl.map((b) => {
    if (b.tipo === "titulo" && String(b.texto ?? "").trim()) {
      return `<h1 style="${F}margin:0 0 14px 0;font-size:23px;line-height:1.3;color:#111111;font-weight:600;">${n(esc(b.texto))}</h1>`;
    }
    if (b.tipo === "texto" && String(b.texto ?? "").trim()) {
      return String(b.texto).split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
        .map((p) => `<p style="${F}margin:0 0 16px 0;font-size:15px;line-height:1.65;color:#3A3A3A;">${n(esc(p)).replace(/\n/g, "<br>")}</p>`).join("");
    }
    if (b.tipo === "imagen" && b.url) {
      const img = `<img src="${esc(b.url)}" alt="${esc(b.alt ?? "")}" width="528" style="display:block;width:100%;max-width:528px;height:auto;border:0;border-radius:12px;">`;
      return `<div style="margin:4px 0 20px 0;">${b.enlace ? `<a href="${esc(conUtm(String(b.enlace), utm))}">${img}</a>` : img}</div>`;
    }
    if (b.tipo === "boton" && b.texto && b.url) return boton(String(b.texto), conUtm(String(b.url), utm));
    if (b.tipo === "separador") return `<div style="height:1px;background-color:#EDE6DC;margin:6px 0 22px 0;line-height:1px;font-size:1px;">&#160;</div>`;
    if (b.tipo === "producto" && b.slug) {
      const p = prods.get(String(b.slug));
      if (!p) return `<p style="${F}font-size:13px;color:#A6332E;">[Producto no disponible: ${esc(b.slug)}]</p>`;
      const url = conUtm(`${TIENDA}/producto/?slug=${encodeURIComponent(p.slug)}`, utm);
      return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:4px 0 22px 0;border:1px solid #D9AE6E;border-radius:14px;">
        ${p.imagen ? `<tr><td style="padding:16px 16px 0 16px;"><a href="${esc(url)}"><img src="${esc(p.imagen)}" alt="${esc(p.nombre)}" width="494" style="display:block;width:100%;max-width:494px;height:auto;border:0;border-radius:10px;"></a></td></tr>` : ""}
        <tr><td style="${F}padding:14px 18px 2px 18px;font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#C28A3A;font-weight:600;">Elegido por MAGANDHI</td></tr>
        <tr><td style="${F}padding:2px 18px 4px 18px;font-size:17px;font-weight:600;color:#111111;">${esc(p.nombre)}</td></tr>
        <tr><td style="${F}padding:0 18px 12px 18px;font-size:16px;color:#111111;">${p.precio_venta ? esc(cop(p.precio_venta)) : ""}${p.agotado ? ` <span style="font-size:12px;color:#A6332E;">· Agotado por ahora</span>` : ""}</td></tr>
        <tr><td align="center" style="padding:0 18px 6px 18px;">${boton(b.boton_texto ? String(b.boton_texto) : "Ver producto", url)}</td></tr></table>`;
    }
    return "";
  }).join("");
}

function construirHtml(o: { asunto: string; preheader: string | null; bloques: Bloque[]; prods: Map<string, Producto>; utm: string; modo: "resend" | "muestra"; ejemplo: string; tema: string; prueba: boolean }) {
  const pre = nombres(esc(o.preheader ?? ""), o.modo, o.ejemplo);
  const baja = o.modo === "resend" ? "{{{RESEND_UNSUBSCRIBE_URL}}}" : "#";
  return `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light"><title>${esc(o.asunto)}</title></head>
<body style="margin:0;padding:0;background-color:#EFE7DD;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;font-size:1px;line-height:1px;color:#EFE7DD;">${pre}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#EFE7DD;"><tr><td align="center" style="padding:28px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background-color:#FFFFFF;border-radius:16px;overflow:hidden;">
${o.prueba ? `<tr><td style="${F}padding:10px 36px;background-color:#111111;color:#FFFFFF;font-size:12px;text-align:center;">Correo de PRUEBA. Así lo verán tus contactos.</td></tr>` : ""}
<tr><td align="center" style="padding:30px 36px 8px 36px;">
<img src="${TIENDA}/logo-mark-terracota.png" width="44" height="44" alt="" style="display:block;border:0;width:44px;height:44px;">
<div style="${F}margin-top:10px;font-size:15px;letter-spacing:.32em;font-weight:600;color:#111111;">MAG<span style="color:#A6332E;">A</span>NDHI</div></td></tr>
<tr><td style="padding:22px 36px 12px 36px;">${renderBloques(o.bloques, o.prods, o.utm, o.modo, o.ejemplo)}</td></tr></table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;"><tr><td align="center" style="${F}padding:18px 24px 0 24px;font-size:11.5px;line-height:1.6;color:#8A8076;">
MAGANDHI · Tunja, Colombia · <a href="${TIENDA}" style="color:#8A8076;">magandhi.com</a><br>
Recibes este correo porque autorizaste recibir ${esc(o.tema ? o.tema.toLowerCase() : "novedades")} de MAGANDHI.<br>
<a href="${baja}" style="color:#8A8076;text-decoration:underline;">Dejar de recibir estos correos</a></td></tr></table>
</td></tr></table></body></html>`;
}

function construirTexto(bl: Bloque[], prods: Map<string, Producto>, utm: string, modo: "resend" | "muestra", ejemplo: string) {
  const n = (s: string) => nombres(s, modo, ejemplo);
  const out: string[] = [];
  for (const b of bl) {
    if ((b.tipo === "titulo" || b.tipo === "texto") && b.texto) out.push(n(String(b.texto)), "");
    if (b.tipo === "boton" && b.texto && b.url) out.push(`${b.texto}: ${conUtm(String(b.url), utm)}`, "");
    if (b.tipo === "producto" && b.slug) {
      const p = prods.get(String(b.slug));
      if (p) out.push(`${p.nombre}${p.precio_venta ? " · " + cop(p.precio_venta) : ""}: ${conUtm(`${TIENDA}/producto/?slug=${p.slug}`, utm)}`, "");
    }
  }
  out.push("MAGANDHI · Tunja, Colombia · magandhi.com",
    "Dejar de recibir estos correos: " + (modo === "resend" ? "{{{RESEND_UNSUBSCRIBE_URL}}}" : TIENDA));
  return out.join("\n");
}

// deno-lint-ignore no-explicit-any
async function cargarProductos(sb: any, bl: Bloque[], supabaseUrl: string) {
  const slugs = [...new Set(bl.filter((b) => b.tipo === "producto" && b.slug).map((b) => String(b.slug)))];
  const mapa = new Map<string, Producto>();
  if (!slugs.length) return mapa;
  const { data } = await sb.from("catalogo_publico").select("slug, nombre, precio_venta, imagen_banner_path, imagenes, agotado").in("slug", slugs);
  for (const r of (data ?? []) as Array<Record<string, unknown>>) {
    const path = (r.imagen_banner_path as string) || ((r.imagenes as string[]) || [])[0] || null;
    mapa.set(String(r.slug), {
      slug: String(r.slug), nombre: String(r.nombre), precio_venta: r.precio_venta as number, agotado: r.agotado === true,
      imagen: path ? `${supabaseUrl}/storage/v1/object/public/campanas/${encodeURIComponent(path)}` : null,
    });
  }
  return mapa;
}

// ----------------------------------------------------------------------------
// Resend
// ----------------------------------------------------------------------------
const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function resend(key: string, metodo: string, ruta: string, cuerpo?: unknown) {
  for (let intento = 0; intento < 3; intento++) {
    const r = await fetch(API + ruta, {
      method: metodo,
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
    });
    if (r.status === 429) { await dormir(1100); continue; }
    const j = await r.json().catch(() => ({}));
    return { ok: r.ok, status: r.status, j: j as Record<string, unknown> };
  }
  return { ok: false, status: 429, j: { message: "Límite de peticiones de Resend" } };
}
const msgResend = (r: { status: number; j: Record<string, unknown> }) => `Resend ${r.status}: ${String(r.j?.message ?? "error")}`;
const limpiarNombre = (s: unknown) => String(s ?? "").replace(/[<>&"{}|]/g, "").trim().slice(0, 60);

// ----------------------------------------------------------------------------
Deno.serve(async (req) => {
  const c = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: c });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405, c);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const apikey = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY");
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!supabaseUrl || !apikey) return json({ error: "Configuración del servidor incompleta." }, 500, c);
  if (!jwt) return json({ error: "Inicia sesión." }, 401, c);
  const sb = createClient(supabaseUrl, apikey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: u, error: uErr } = await sb.auth.getUser(jwt);
  if (uErr || !u?.user) return json({ error: "Tu sesión no es válida. Vuelve a iniciar sesión." }, 401, c);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Body inválido." }, 400, c); }
  const modo = String(body.modo ?? "");
  const idCampana = typeof body.campana_id === "string" ? body.campana_id : null;
  const falla = (e: { message?: string } | null, ctx: string) => {
    console.error("[em-campana]", ctx, JSON.stringify({ message: e?.message ?? null }));
    const t = traducir(e?.message ?? "");
    const extra = (e?.message ?? "").match(/EM_AUDIENCIA_CAMBIO:(\d+)/);
    return json({ error: t.texto, codigo: t.codigo, ...(extra ? { audiencia: Number(extra[1]) } : {}) }, t.status, c);
  };

  // ---------------- vista / prueba ----------------
  if (modo === "vista" || modo === "prueba") {
    const bloques = Array.isArray(body.contenido) ? (body.contenido as Bloque[]).slice(0, 30) : [];
    const asunto = String(body.asunto ?? "").slice(0, 150);
    const preheader = body.preheader ? String(body.preheader).slice(0, 200) : null;
    const tema = String(body.tema_nombre ?? "Novedades").slice(0, 40);
    // Acceso al modulo (la vista tambien lo exige): consulta guardada.
    const acc = await sb.rpc("em_campana_audiencia", { p_segmento_id: null, p_tema: null });
    if (acc.error && /EM_SIN_ACCESO/.test(acc.error.message)) return falla(acc.error, "acceso");
    const prods = await cargarProductos(sb, bloques, supabaseUrl);
    const nombre = (u.user.user_metadata?.nombre as string) || "Ana";
    const html = construirHtml({ asunto, preheader, bloques, prods, utm: "vista-previa", modo: "muestra", ejemplo: nombre, tema, prueba: modo === "prueba" });
    if (modo === "vista") return json({ html, asunto: nombres(asunto, "muestra", nombre) }, 200, c);

    const key = Deno.env.get("RESEND_MARKETING_API_KEY");
    if (!key) return json({ error: "Falta RESEND_MARKETING_API_KEY en Supabase Secrets." }, 503, c);
    if (!asunto.trim()) return json({ error: "Escribe un asunto antes de enviar la prueba." }, 400, c);
    const destino = u.user.email!;
    const r = await resend(key, "POST", "/emails", {
      from: REMITENTE, to: [destino], reply_to: RESPONDER_A, subject: "[Prueba] " + nombres(asunto, "muestra", nombre),
      html, text: construirTexto(bloques, prods, "vista-previa", "muestra", nombre),
      tags: [{ name: "tipo", value: "prueba_campana" }],
    });
    if (!r.ok) return json({ error: "No se pudo enviar la prueba: " + msgResend(r) }, 502, c);
    if (idCampana) await sb.rpc("em_campana_registrar_prueba", { p_id: idCampana, p_destinatario: destino });
    return json({ ok: true, destinatario: destino }, 200, c);
  }

  if (!idCampana) return json({ error: "Falta la campaña." }, 400, c);

  // ---------------- confirmar ----------------
  if (modo === "confirmar") {
    const { data, error } = await sb.rpc("em_campana_confirmar", {
      p_id: idCampana, p_n_esperado: Number(body.n), p_programada_para: body.programada_para ?? null,
    });
    if (error) return falla(error, "confirmar");
    return json({ ok: true, ...(data as object) }, 200, c);
  }

  const key = Deno.env.get("RESEND_MARKETING_API_KEY");
  if (!key) return json({ error: "Falta RESEND_MARKETING_API_KEY en Supabase Secrets." }, 503, c);

  // ---------------- sincronizar (una tanda) ----------------
  if (modo === "sincronizar") {
    const { data, error } = await sb.rpc("em_campana_pendientes", { p_id: idCampana, p_limite: 40 });
    if (error) return falla(error, "pendientes");
    const p = data as { estado: string; resend_segment_id: string | null; utm_campaign: string; restantes: number; lote: Array<Record<string, string | null>> };
    if (p.estado !== "preparando") return json({ error: "La campaña no está en preparación." }, 409, c);
    let seg = p.resend_segment_id;
    if (!seg) {
      const r = await resend(key, "POST", "/segments", { name: `campana-${p.utm_campaign}` });
      if (!r.ok) return json({ error: "No se pudo crear el segmento en Resend: " + msgResend(r) }, 502, c);
      seg = String(r.j.id);
      await sb.rpc("em_campana_set_segmento_resend", { p_id: idCampana, p_segment_id: seg });
      const again = await sb.rpc("em_campana_pendientes", { p_id: idCampana, p_limite: 0 });
      seg = (again.data as { resend_segment_id: string }).resend_segment_id ?? seg;
    }
    let procesados = 0, excluidos = 0;
    for (const d of p.lote) {
      const correo = String(d.correo);
      let contactId = d.resend_contact_id;
      let desuscrito = false;
      const g = await resend(key, "GET", `/contacts/${encodeURIComponent(contactId || correo)}`);
      await dormir(PAUSA_MS);
      if (g.ok) {
        contactId = String(g.j.id);
        desuscrito = g.j.unsubscribed === true;
        if (!desuscrito) {
          const a = await resend(key, "POST", `/contacts/${contactId}/segments/${seg}`);
          await dormir(PAUSA_MS);
          if (!a.ok && a.status !== 409) return json({ error: "Resend rechazó agregar un contacto: " + msgResend(a), procesados }, 502, c);
        }
      } else if (g.status === 404) {
        const cr = await resend(key, "POST", "/contacts", {
          email: correo, first_name: limpiarNombre(d.nombre) || undefined, unsubscribed: false, segments: [{ id: seg }],
        });
        await dormir(PAUSA_MS);
        if (!cr.ok) return json({ error: "Resend rechazó crear un contacto: " + msgResend(cr), procesados }, 502, c);
        contactId = String(cr.j.id);
      } else {
        return json({ error: "Resend no respondió al consultar un contacto: " + msgResend(g), procesados }, 502, c);
      }
      const res = await sb.rpc("em_campana_destinatario_resultado", {
        p_id: idCampana, p_contacto_id: d.contacto_id, p_resend_contact_id: contactId, p_excluir_motivo: desuscrito ? "baja_en_resend" : null,
      });
      if (res.error) return falla(res.error, "resultado");
      procesados++; if (desuscrito) excluidos++;
    }
    return json({ ok: true, procesados, excluidos, restantes: Math.max(0, p.restantes - procesados) }, 200, c);
  }

  // ---------------- enviar ----------------
  if (modo === "enviar") {
    const { data, error } = await sb.rpc("em_campana_reservar_envio", { p_id: idCampana });
    if (error) return falla(error, "reservar");
    const r0 = data as { resend_segment_id: string; programada_para: string | null; asunto: string; preheader: string | null; contenido: Bloque[]; utm_campaign: string; nombre_interno: string; tema: string; listos: number };
    const prods = await cargarProductos(sb, r0.contenido, supabaseUrl);
    const html = construirHtml({ asunto: r0.asunto, preheader: r0.preheader, bloques: r0.contenido, prods, utm: r0.utm_campaign, modo: "resend", ejemplo: "", tema: r0.tema, prueba: false });
    const cuerpo: Record<string, unknown> = {
      segment_id: r0.resend_segment_id, from: REMITENTE, reply_to: RESPONDER_A,
      subject: r0.asunto.replace(/\{nombre(?:\|([^{}]{0,40}))?\}/g, (_m: string, a: string) => "{{{contact.first_name|" + String(a ?? "").replace(/[|{}]/g, "") + "}}}"),
      html, text: construirTexto(r0.contenido, prods, r0.utm_campaign, "resend", ""),
      name: r0.nombre_interno.slice(0, 100), send: true,
    };
    if (r0.programada_para) cuerpo.scheduled_at = new Date(r0.programada_para).toISOString();
    const r = await resend(key, "POST", "/broadcasts", cuerpo);
    if (!r.ok) {
      await sb.rpc("em_campana_marcar_enviada", { p_id: idCampana, p_ok: false, p_broadcast_id: null, p_error: msgResend(r) });
      return json({ error: "Resend no aceptó la campaña: " + msgResend(r) }, 502, c);
    }
    const m = await sb.rpc("em_campana_marcar_enviada", { p_id: idCampana, p_ok: true, p_broadcast_id: String(r.j.id), p_error: null });
    if (m.error) console.error("[em-campana] enviada en Resend pero no marcada:", JSON.stringify({ campana: idCampana, broadcast: r.j.id }));
    console.log("[em-campana] enviada", JSON.stringify({ campana: idCampana, destinatarios: r0.listos, programada: !!r0.programada_para }));
    return json({ ok: true, programada: !!r0.programada_para, destinatarios: r0.listos }, 200, c);
  }

  // ---------------- cancelar ----------------
  if (modo === "cancelar") {
    const det = await sb.rpc("em_campana_detalle", { p_id: idCampana });
    if (det.error) return falla(det.error, "detalle");
    const camp = (det.data as { campana: { estado: string; resend_broadcast_id: string | null } }).campana;
    if (camp.estado === "programada" && camp.resend_broadcast_id) {
      const r = await resend(key, "POST", `/broadcasts/${camp.resend_broadcast_id}/cancel`);
      if (!r.ok) return json({ error: "Resend no pudo cancelar el envío programado: " + msgResend(r) }, 502, c);
    }
    const { error } = await sb.rpc("em_campana_cancelar", { p_id: idCampana, p_motivo: String(body.motivo ?? "").slice(0, 300) });
    if (error) return falla(error, "cancelar");
    return json({ ok: true }, 200, c);
  }

  return json({ error: "Modo inválido." }, 400, c);
});
