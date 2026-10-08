// Bateria HTTP contra em-webhook servida localmente. Firma real Svix.
const URL_FN = "http://localhost:8000";
const URL_FN_SIN_SECRETO = "http://localhost:8001";
const SECRETO = Deno.env.get("SECRETO")!; // whsec_...
const enc = new TextEncoder();
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([ok, q]);

async function firmar(id: string, ts: number, cuerpo: string, secreto = SECRETO) {
  const llave = Uint8Array.from(atob(secreto.replace(/^whsec_/, "")), (c) => c.charCodeAt(0));
  const k = await crypto.subtle.importKey("raw", llave, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(`${id}.${ts}.${cuerpo}`)));
  return "v1," + btoa(String.fromCharCode(...mac));
}
const ahora = () => Math.floor(Date.now() / 1000);
async function enviar(o: { id?: string; ts?: number; cuerpo: string; firma?: string; url?: string; sinHeaders?: boolean }) {
  const id = o.id ?? "msg_" + crypto.randomUUID().replace(/-/g, "");
  const ts = o.ts ?? ahora();
  const h: Record<string, string> = { "Content-Type": "application/json" };
  if (!o.sinHeaders) {
    h["svix-id"] = id; h["svix-timestamp"] = String(ts);
    h["svix-signature"] = o.firma ?? await firmar(id, ts, o.cuerpo);
  }
  const r = await fetch(o.url ?? URL_FN, { method: "POST", headers: h, body: o.cuerpo });
  const j = await r.json().catch(() => ({}));
  return { s: r.status, j };
}
async function sql(q: string) {
  const o = await new Deno.Command("psql", { args: ["-tAqc", q, "-d", "impulse_pruebas"], env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" } }).output();
  return new TextDecoder().decode(o.stdout).trim();
}
const ev = (type: string, data: Record<string, unknown>) => JSON.stringify({ type, created_at: new Date().toISOString(), data });

// 1. Valido
const c1 = ev("email.delivered", { broadcast_id: "bc-sim", email_id: "e1", to: ["sim@x.invalid"] });
let r = await enviar({ id: "msg_sim_ok_1", cuerpo: c1 });
chk(r.s === 200 && r.j.estado === "procesado", "firma valida -> 200 procesado");
chk(await sql("select count(*) from em_eventos where svix_id='msg_sim_ok_1'") === "1", "evento guardado en la base");

// 2. Reintento de Resend: mismo svix-id, nuevo timestamp y nueva firma
r = await enviar({ id: "msg_sim_ok_1", ts: ahora() + 3, cuerpo: c1 });
chk(r.s === 200 && r.j.estado === "repetido", "reintento con mismo svix-id -> 200 repetido");
chk(await sql("select count(*) from em_eventos where svix_id='msg_sim_ok_1'") === "1", "reintento no duplica");

// 3. Firma invalida / cuerpo alterado / otro secreto
r = await enviar({ id: "msg_sim_mala", cuerpo: c1, firma: "v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" });
chk(r.s === 401, "firma inventada -> 401");
{
  const ts = ahora(); const f = await firmar("msg_sim_alt", ts, c1);
  r = await enviar({ id: "msg_sim_alt", ts, cuerpo: c1.replace("sim@x.invalid", "otro@x.invalid"), firma: f });
  chk(r.s === 401, "cuerpo alterado tras firmar -> 401");
}
{
  const otro = "whsec_" + btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(24))));
  const ts = ahora();
  r = await enviar({ id: "msg_sim_otro", ts, cuerpo: c1, firma: await firmar("msg_sim_otro", ts, c1, otro) });
  chk(r.s === 401, "firmado con otro secreto -> 401");
}
{
  const ts = ahora(); const f = await firmar("msg_sim_idcambiado", ts, c1);
  r = await enviar({ id: "msg_sim_idcambiado_x", ts, cuerpo: c1, firma: f });
  chk(r.s === 401, "svix-id cambiado -> 401");
}
chk(await sql("select count(*) from em_eventos where svix_id in ('msg_sim_mala','msg_sim_alt','msg_sim_otro','msg_sim_idcambiado_x')") === "0", "nada rechazado llega a la base");

// 4. Timestamps fuera de tolerancia (aunque la firma sea correcta)
r = await enviar({ id: "msg_sim_vieja", ts: ahora() - 6 * 60, cuerpo: c1 });
chk(r.s === 401 && /vencida/i.test(r.j.error), "timestamp de hace 6 min -> 401 vencida");
r = await enviar({ id: "msg_sim_futura", ts: ahora() + 6 * 60, cuerpo: c1 });
chk(r.s === 401, "timestamp 6 min en el futuro -> 401");
r = await enviar({ id: "msg_sim_4min", ts: ahora() - 4 * 60, cuerpo: ev("email.opened", { broadcast_id: "bc-sim", to: ["sim@x.invalid"] }) });
chk(r.s === 200, "timestamp de hace 4 min -> aceptado");

// 5. Varias firmas en el header (rotacion de secreto): una valida basta
{
  const ts = ahora(); const id = "msg_sim_multi"; const cu = ev("email.opened", { broadcast_id: "bc-sim", to: ["sim@x.invalid"] });
  r = await enviar({ id, ts, cuerpo: cu, firma: "v1,bWFsYQ== " + await firmar(id, ts, cu) });
  chk(r.s === 200, "varias firmas, una valida -> 200");
  r = await enviar({ id: "msg_sim_v2", ts, cuerpo: cu, firma: (await firmar("msg_sim_v2", ts, cu)).replace("v1,", "v2,") });
  chk(r.s === 401, "version de firma distinta de v1 -> 401");
}

// 6. Peticiones mal formadas
r = await enviar({ cuerpo: c1, sinHeaders: true });
chk(r.s === 400, "sin encabezados de firma -> 400");
{ const g = await fetch(URL_FN, { method: "GET" }); await g.body?.cancel(); chk(g.status === 405, "GET -> 405"); }
r = await enviar({ id: "msg_sim_json", cuerpo: "{no es json" });
chk(r.s === 400, "JSON invalido (firmado) -> 400");
r = await enviar({ id: "msg_sim_arr", cuerpo: "[1,2]" });
chk(r.s === 400, "JSON que no es objeto -> 400");
r = await enviar({ id: "x", cuerpo: c1 });
chk(r.s === 400, "svix-id con formato invalido -> 400 (Resend no insiste)");
r = await enviar({ id: "msg_sim_grande", cuerpo: JSON.stringify({ type: "email.opened", data: { relleno: "x".repeat(300 * 1024) } }) });
chk(r.s === 413, "cuerpo de mas de 256 KB -> 413");

// 7. Ignorados con 200 (para que Resend no apague el webhook)
r = await enviar({ id: "msg_sim_prueba", cuerpo: ev("email.delivered", { email_id: "zz", to: ["a@x.invalid"], tags: { tipo: "prueba_campana" } }) });
chk(r.s === 200 && r.j.estado === "ignorado", "envio de prueba -> 200 ignorado");
r = await enviar({ id: "msg_sim_dominio", cuerpo: ev("domain.updated", { id: "d" }) });
chk(r.s === 200 && r.j.estado === "ignorado", "evento no usado -> 200 ignorado");

// 8. Supresion de punta a punta
r = await enviar({ id: "msg_sim_bounce", cuerpo: ev("email.bounced", { broadcast_id: "bc-sim", to: ["sim@x.invalid"], bounce: { type: "Permanent", subType: "General", message: "x" } }) });
chk(r.s === 200 && (await sql("select estado from em_contactos where correo_norm='sim@x.invalid'")) === "rebotado", "rebote permanente por HTTP -> contacto rebotado");

// 9. Fallo transitorio de la base -> 500 (Resend reintenta)
r = await enviar({ id: "msg_forzar_falla_db", cuerpo: c1 });
chk(r.s === 500, "base caida -> 500 para que Resend reintente");

// 10. Sin secreto configurado -> 503
r = await enviar({ id: "msg_sim_503", cuerpo: c1, url: URL_FN_SIN_SECRETO });
chk(r.s === 503, "sin RESEND_WEBHOOK_SECRET -> 503 (no procesa nada)");

// 11. La funcion mando la llave de servicio en apikey Y Authorization
const vistos = await (await fetch("http://localhost:54321/__vistos")).json() as Array<{ apikey: string; auth: string }>;
const LL = Deno.env.get("LLAVE_SERVICIO_FALSA");
chk(vistos.length > 0 && vistos.every((v) => v.apikey === LL && v.auth === "Bearer " + LL), "PostgREST recibe service_role en apikey y Authorization (" + vistos.length + " llamadas)");


// 12. Interoperabilidad: firmado con la libreria OFICIAL de Svix
{
  const { Webhook } = await import("npm:svix@1");
  const wh = new Webhook(SECRETO);
  const id = "msg_sim_oficial"; const fecha = new Date(); const cu = ev("email.opened", { broadcast_id: "bc-sim", to: ["sim@x.invalid"] });
  const firma = wh.sign(id, fecha, cu);
  r = await enviar({ id, ts: Math.floor(fecha.getTime() / 1000), cuerpo: cu, firma });
  chk(r.s === 200 && r.j.estado === "procesado", "firma generada por la libreria oficial svix -> aceptada");
  // y al reves: nuestra firma la acepta la libreria oficial
  const ts = ahora(); const mia = await firmar("msg_x", ts, cu);
  let okLib = true; try { wh.verify(cu, { "svix-id": "msg_x", "svix-timestamp": String(ts), "svix-signature": mia }); } catch { okLib = false; }
  chk(okLib, "la libreria oficial svix valida la firma calculada con el mismo esquema");
}

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log("RESUMEN | " + res.length + " comprobaciones · " + res.filter((x) => !x[0]).length + " fallan");
