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
