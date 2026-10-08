// PostgREST minimo GENERICO (cualquier RPC, ejecutado como service_role contra el
// Postgres local) + Resend simulado (/emails). Puerto 54321 y 54322.
const LLAVE = Deno.env.get("LLAVE_SERVICIO_FALSA")!;
const vistos: Array<{ rpc: string; apikey: string | null; auth: string | null }> = [];
const correos: Array<Record<string, unknown>> = [];
let resendFalla = false;

function lit(v: unknown): string {
  if (v === null || v === undefined) return "NULL";
  if (Array.isArray(v) && v.some((x) => x !== null && typeof x === "object")) return "'" + JSON.stringify(v).replace(/'/g, "''") + "'::jsonb";
  if (Array.isArray(v)) return "'" + ("{" + v.map((x) => '"' + String(x).replace(/["\\]/g, "\\$&") + '"').join(",") + "}").replace(/'/g, "''") + "'";
  if (typeof v === "object") return "'" + JSON.stringify(v).replace(/'/g, "''") + "'::jsonb";
  return "'" + String(v).replace(/'/g, "''") + "'";
}

Deno.serve({ port: 54321 }, async (req) => {
  const u = new URL(req.url);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, OPTIONS" } });
  if (u.pathname === "/__vistos") return Response.json(vistos);
  // --- Lectura de TABLAS/VISTAS (GET), como hace PostgREST ------------------
  // Necesario desde Wompi F2: crear-intencion-pago lee catalogo_publico con
  // .select(...).or(...).limit(1). Se traduce a SQL real contra el Postgres
  // local. Soporta select=, filtros col=eq.valor y or=(a.eq.x,b.eq.y), limit.
  const t = u.pathname.match(/^\/rest\/v1\/([a-z_0-9]+)$/);
  if (req.method === "GET" && t) {
    const tabla = t[1];
    const cols = (u.searchParams.get("select") ?? "*").replace(/[^a-z_0-9,*\s]/gi, "");
    const donde: string[] = [];
    for (const [k, v] of u.searchParams.entries()) {
      if (["select", "limit", "offset", "order", "or"].includes(k)) continue;
      const mm = String(v).match(/^eq\.(.*)$/);
      if (mm && /^[a-z_0-9]+$/i.test(k)) donde.push(`${k} = ${lit(mm[1])}`);
    }
    const or = u.searchParams.get("or");
    if (or) {
      const partes = or.replace(/^\(|\)$/g, "").split(",")
        .map((x) => x.match(/^([a-z_0-9]+)\.eq\.(.*)$/i))
        .filter(Boolean)
        .map((mm) => `${mm![1]} = ${lit(mm![2])}`);
      if (partes.length) donde.push("(" + partes.join(" or ") + ")");
    }
    const lim = /^\d{1,4}$/.test(u.searchParams.get("limit") ?? "") ? ` limit ${u.searchParams.get("limit")}` : "";
    const sql = `select coalesce(jsonb_agg(x), '[]'::jsonb) from (select ${cols} from ${tabla}` +
      (donde.length ? ` where ${donde.join(" and ")}` : "") + lim + ") x;";
    const pp = new Deno.Command("psql", {
      args: ["-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", "impulse_pruebas"], stdin: "piped", stdout: "piped", stderr: "piped",
      env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" },
    }).spawn();
    const ww = pp.stdin.getWriter();
    await ww.write(new TextEncoder().encode(`set role service_role;\n${sql}\n`));
    await ww.close();
    const oo = await pp.output();
    const salida = new TextDecoder().decode(oo.stdout).trim();
    const errr = new TextDecoder().decode(oo.stderr).trim();
    if (!oo.success) {
      return Response.json({ code: "P0001", message: errr.replace(/^.*?ERROR:\s*/s, "").split("\n")[0] }, { status: 400 });
    }
    return new Response(salida.split("\n").pop(), { headers: { "Content-Type": "application/json" } });
  }

  const m = u.pathname.match(/^\/rest\/v1\/rpc\/([a-z_0-9]+)$/);
  if (req.method !== "POST" || !m) return Response.json({ message: "no simulado " + u.pathname }, { status: 404 });
  vistos.push({ rpc: m[1], apikey: req.headers.get("apikey"), auth: req.headers.get("authorization") });
  const PANEL = Deno.env.get("SIM_PANEL_UID");
  const esServicio = req.headers.get("apikey") === LLAVE && req.headers.get("authorization") === `Bearer ${LLAVE}`;
  if (!esServicio && !PANEL) {
    return Response.json({ code: "42501", message: "permission denied for function " + m[1] }, { status: 401 });
  }
  const rol = esServicio ? "set role service_role;" : `set request.jwt.claims to '{"sub":"${PANEL}","role":"authenticated"}'; set role authenticated;`;
  const b = (await req.json().catch(() => ({}))) as Record<string, unknown>;
  const args = Object.entries(b).map(([k, v]) => `${k} => ${lit(v)}`).join(", ");
  const p = new Deno.Command("psql", {
    args: ["-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", "impulse_pruebas"], stdin: "piped", stdout: "piped", stderr: "piped",
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" },
  }).spawn();
  const w = p.stdin.getWriter();
  await w.write(new TextEncoder().encode(`${rol}\nselect to_jsonb(${m[1]}(${args}));\n`));
  await w.close();
  const o = await p.output();
  const out = new TextDecoder().decode(o.stdout).trim(), err = new TextDecoder().decode(o.stderr).trim();
  if (!o.success) return Response.json({ code: "P0001", message: err.replace(/^.*?ERROR:\s*/s, "").split("\n")[0] }, { status: 400 });
  return new Response(out.split("\n").pop(), { headers: { "Content-Type": "application/json" } });
});

Deno.serve({ port: 54322 }, async (req) => {
  const u = new URL(req.url);
  if (u.pathname === "/__correos") return Response.json(correos);
  if (u.pathname === "/__falla") { resendFalla = u.searchParams.get("v") === "1"; return Response.json({ ok: true }); }
  if (req.method === "POST" && u.pathname === "/emails") {
    if (resendFalla) return Response.json({ message: "caido" }, { status: 500 });
    const b = await req.json();
    correos.push({ ...b, _idem: req.headers.get("idempotency-key"), _auth: req.headers.get("authorization") });
    return Response.json({ id: "email-" + correos.length });
  }
  return Response.json({ message: "no simulado" }, { status: 404 });
});
