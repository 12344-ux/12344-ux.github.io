const FN = "http://localhost:8000";
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([!!ok, q]);
async function sql(q: string) {
  const o = await new Deno.Command("psql", { args: ["-tAqc", q, "-d", "impulse_pruebas"], env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" } }).output();
  return new TextDecoder().decode(o.stdout).trim();
}
async function post(body: unknown, h: Record<string, string> = {}) {
  const r = await fetch(FN, { method: "POST", headers: { "Content-Type": "application/json", origin: "https://magandhi.com", "user-agent": "Mozilla/5.0 (iPhone) Safari", "x-forwarded-for": "190.5.5.5", ...h }, body: typeof body === "string" ? body : JSON.stringify(body) });
  return { s: r.status, j: await r.json().catch(() => ({})), h: r.headers };
}
const V = "vis-0123456789abcdefXY", S = "ses-01234567";
const ev = (e: unknown[]) => post({ modo: "registrar", visitante: V, sesion: S, eventos: e });

let r = await post({ modo: "config" });
chk(r.s === 200 && r.j.activa === false, "apagada: config activa=false");
r = await ev([{ tipo: "pagina_vista", ruta: "/" }]);
chk(r.s === 409 && r.j.apagada, "apagada: registrar -> 409 (la tienda deja de enviar)");
await sql("update em_config set politica_publicada = true, politica_version = 'borrador-0', analitica_activa = true where id");
r = await post({ modo: "config" });
chk(r.j.activa === true, "encendida: config activa=true");

r = await ev([{ tipo: "pagina_vista", ruta: "/", origen: "instagram", entrada: true, dispositivo: "movil", ip: "1.2.3.4", correo: "x@y.z", userAgent: "UA" },
              { tipo: "producto_visto", ruta: "/producto/", slug: "grisi", dispositivo: "movil" }]);
chk(r.s === 200 && r.j.aceptados === 2, "registrar 2 eventos válidos -> 200");
chk(await sql(`select count(*) from tienda_eventos where visitante = '${V}'`) === "2", "quedan en la base");
chk(await sql("select count(*) from tienda_eventos where ruta ~ '1\\.2\\.3\\.4' or ruta ~ '@'") === "0", "campos fuera de la lista blanca (ip, correo, UA) no viajan");

r = await post({ modo: "registrar", visitante: V, sesion: S, eventos: [{ tipo: "pagina_vista", ruta: "/" }] }, { "user-agent": "Googlebot/2.1" });
chk(r.s === 202 && (await sql(`select count(*) from tienda_eventos where visitante = '${V}'`)) === "2", "bot: 202 y no se registra");
r = await post({ modo: "registrar", visitante: V, sesion: S, eventos: [{ tipo: "pagina_vista", ruta: "/" }] }, { "user-agent": "Mozilla/5.0 HeadlessChrome" });
chk(r.s === 202, "navegador sin interfaz: tratado como bot");
r = await post({ modo: "registrar", visitante: "corto", sesion: S, eventos: [{ tipo: "pagina_vista", ruta: "/" }] });
chk(r.s === 400, "visitante inválido -> 400");
r = await ev([]);
chk(r.s === 400, "sin eventos -> 400");
r = await ev(Array.from({ length: 45 }, () => ({ tipo: "pagina_vista", ruta: "/" })));
chk(r.s === 200 && r.j.aceptados === 30, "más de 30: se recorta a 30");
r = await post("x".repeat(17000));
chk(r.s === 413, "más de 16 KB -> 413");
r = await post("{roto");
chk(r.s === 400, "JSON roto -> 400");

let ult = 0;
for (let i = 0; i < 21; i++) ult = (await post({ modo: "registrar", visitante: V, sesion: S, eventos: Array.from({ length: 30 }, () => ({ tipo: "pagina_vista", ruta: "/" })) }, { "x-forwarded-for": "201.7.7.7" })).s;
chk(ult === 429, "más de 600 eventos/hora desde una IP -> 429");
chk(await sql("select count(*) from tienda_eventos_limite where ip_hash ~ '201\\.7'") === "0", "la IP no se guarda");

{ const o = await fetch(FN, { method: "OPTIONS", headers: { origin: "https://www.magandhi.com" } }); await o.body?.cancel();
  chk(o.status === 204 && o.headers.get("access-control-allow-origin") === "https://www.magandhi.com" && o.headers.get("access-control-max-age") === "86400", "CORS de la tienda con caché de 24 h"); }
{ const g = await fetch(FN); await g.body?.cancel(); chk(g.status === 405, "GET -> 405"); }

const vistos = await (await fetch("http://localhost:54321/__vistos")).json() as Array<{ apikey: string; auth: string }>;
const LL = Deno.env.get("LLAVE_SERVICIO_FALSA");
chk(vistos.length > 5 && vistos.every((v) => v.apikey === LL && v.auth === "Bearer " + LL), `service_role en apikey y Authorization (${vistos.length})`);
for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log("RESUMEN | " + res.length + " comprobaciones · " + res.filter((x) => !x[0]).length + " fallan");
