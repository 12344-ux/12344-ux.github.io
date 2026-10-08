// Bateria HTTP de em-suscripcion contra PostgREST + Resend simulados (RPC reales).
const FN = "http://localhost:8000";
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([!!ok, q]);
async function sql(q: string) {
  const o = await new Deno.Command("psql", { args: ["-tAqc", q, "-d", "impulse_pruebas"], env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" } }).output();
  return new TextDecoder().decode(o.stdout).trim();
}
async function post(body: unknown, ip = "200.1.1.1", origin = "https://magandhi.com") {
  const r = await fetch(FN, { method: "POST", headers: { "Content-Type": "application/json", "x-forwarded-for": ip, origin }, body: typeof body === "string" ? body : JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  return { s: r.status, j, h: r.headers };
}
const correos = async () => (await (await fetch("http://localhost:54322/__correos")).json()) as Array<Record<string, any>>;
async function sha(s: string) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join(""); }
const sus = (correo: string, extra: Record<string, unknown> = {}, ip?: string) => post({ modo: "suscribir", correo, nombre: "Ana", temas: ["novedades"], acepto: true, sitio_web: "", ...extra }, ip);

// 1. Apagado
let r = await post({ modo: "config" });
chk(r.s === 200 && r.j.activa === false && !("texto_consentimiento" in r.j), "apagada: config dice activa=false y no expone nada más");
r = await sus("ana@z.invalid");
chk(r.s === 403, "apagada: suscribir -> 403");
await sql("update em_config set politica_publicada = true, politica_url = 'https://magandhi.com/politicas/datos/', politica_version = 'borrador-0', captura_publica_activa = true where id");

// 2. Config activa
r = await post({ modo: "config" });
chk(r.s === 200 && r.j.activa === true && /Autorizo/.test(r.j.texto_consentimiento) && r.j.politica_url.endsWith("/politicas/datos/") && r.j.temas.length === 2, "activa: texto de autorización, política y temas");

// 3. Camino feliz
r = await sus("Ana@Z.invalid");
const msgNuevo = r.j.mensaje;
let cs = await correos();
chk(r.s === 200 && r.j.ok && cs.length === 1, "suscribir válido -> 200 y 1 correo de confirmación");
const c0 = cs[0];
const enlace = String(c0.html).match(/href="(https:\/\/magandhi\.com\/suscripcion\/confirmar\/#t=([A-Za-z0-9_-]+))"/);
chk(!!enlace, "el enlace va a /suscripcion/confirmar/ con el token en el fragmento #t=");
const token = enlace ? enlace[2] : "";
chk(token.length >= 40, "token de 256 bits (" + token.length + " caracteres)");
chk(c0.to[0] === "Ana@Z.invalid" && /Confirma tu suscripción/.test(c0.subject) && c0.tags[0].value === "confirmacion_suscripcion" && /^confirmacion-[0-9a-f-]{36}$/.test(c0._idem), "destinatario, asunto, etiqueta e Idempotency-Key");
chk(String(c0.text).includes(enlace ? enlace[1] : "x"), "versión de texto plano con el mismo enlace");
chk(await sql(`select count(*) from em_confirmaciones where token_hash = '${await sha(token)}'`) === "1", "en la base solo está el hash del token");
chk(await sql("select count(*) from em_contactos where correo_norm = 'ana@z.invalid'") === "0", "pedir no crea contacto");
r = await post({ modo: "confirmar", token });
chk(r.s === 200 && r.j.estado === "confirmado", "confirmar con el token del correo -> confirmado");
chk(await sql("select estado || '|' || fuente from em_contactos where correo_norm = 'ana@z.invalid'") === "suscrito|formulario_tienda", "contacto suscrito desde el formulario");
r = await post({ modo: "confirmar", token });
chk(r.j.estado === "ya_confirmado", "segundo clic -> ya confirmado");

// 4. No revela si existe
r = await sus("ana@z.invalid");
chk(r.s === 200 && r.j.mensaje === msgNuevo && (await correos()).length === 1, "ya suscrita: misma respuesta exacta y no se envía correo");

// 5. Trampa y validaciones
r = await sus("bot@z.invalid", { sitio_web: "http://spam" });
chk(r.s === 200 && r.j.mensaje === msgNuevo && (await sql("select count(*) from em_confirmaciones where correo_norm = 'bot@z.invalid'")) === "0", "campo trampa: responde igual y no guarda nada");
r = await sus("nueva@z.invalid", { acepto: false });
chk(r.s === 400 && /casilla/.test(r.j.error), "sin autorización -> 400 con mensaje claro");
r = await sus("acepto-string@z.invalid", { acepto: "true" });
chk(r.s === 400, "acepto debe ser true de verdad (no un texto)");
r = await sus("no-es-correo");
chk(r.s === 400 && /no parece válido/.test(r.j.error), "correo inválido -> 400");
r = await sus("sin-temas@z.invalid", { temas: [] });
chk(r.s === 400 && /qué quieres recibir/.test(r.j.error), "sin temas -> 400");

// 6. Límite por IP (10 al día)
let ult = 0;
for (let i = 0; i < 11; i++) ult = (await sus(`ip${i}@z.invalid`, {}, "190.9.9.9")).s;
chk(ult === 429, "11.ª solicitud desde la misma IP -> 429");
chk(await sql("select count(*) from em_suscripcion_intentos where ip_hash like '%190.9.9.9%'") === "0", "la IP no se guarda en claro");

// 7. Resend caído
await fetch("http://localhost:54322/__falla?v=1");
r = await sus("caido@z.invalid", {}, "201.2.2.2");
chk(r.s === 502, "Resend caído -> 502 (la persona puede reintentar)");
chk(await sql("select count(*) from em_contactos where correo_norm = 'caido@z.invalid'") === "0", "sin correo enviado no hay contacto");
await fetch("http://localhost:54322/__falla?v=0");

// 8. Tokens raros
r = await post({ modo: "confirmar", token: "../../etc" });
chk(r.s === 200 && r.j.estado === "invalido", "token con formato raro -> inválido");
r = await post({ modo: "confirmar", token: "A".repeat(43) });
chk(r.s === 200 && r.j.estado === "invalido", "token inventado -> inválido");

// 9. HTTP
{ const o = await fetch(FN, { method: "OPTIONS", headers: { origin: "https://www.magandhi.com" } }); await o.body?.cancel();
  chk(o.status === 204 && o.headers.get("access-control-allow-origin") === "https://www.magandhi.com", "CORS: la tienda (www) permitida"); }
{ const o = await fetch(FN, { method: "OPTIONS", headers: { origin: "https://malicioso.example" } }); await o.body?.cancel();
  chk(o.headers.get("access-control-allow-origin") === "https://magandhi.com", "CORS: otro origen no queda autorizado"); }
{ const g = await fetch(FN); await g.body?.cancel(); chk(g.status === 405, "GET -> 405"); }
r = await post(JSON.stringify({ modo: "suscribir", correo: "x@z.invalid", relleno: "x".repeat(5000) }));
chk(r.s === 413, "cuerpo de más de 4 KB -> 413");
r = await post("{roto");
chk(r.s === 400, "JSON inválido -> 400");
r = await post({ modo: "otro" });
chk(r.s === 400, "modo desconocido -> 400");

// 10. Apagar en caliente
await sql("update em_config set captura_publica_activa = false where id");
r = await sus("tarde@z.invalid", {}, "202.3.3.3");
chk(r.s === 403, "apagada en caliente -> 403");
r = await post({ modo: "config" });
chk(r.j.activa === false, "config vuelve a decir apagada");

// 11. Llave de servicio en todas las llamadas
const vistos = await (await fetch("http://localhost:54321/__vistos")).json() as Array<{ apikey: string; auth: string }>;
const LL = Deno.env.get("LLAVE_SERVICIO_FALSA");
chk(vistos.length > 10 && vistos.every((v) => v.apikey === LL && v.auth === "Bearer " + LL), `todas las llamadas usan service_role en apikey y Authorization (${vistos.length})`);
Deno.writeTextFileSync("/projects/sandbox/pruebas-em5/token-prueba.txt", token);

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log("RESUMEN | " + res.length + " comprobaciones · " + res.filter((x) => !x[0]).length + " fallan");
