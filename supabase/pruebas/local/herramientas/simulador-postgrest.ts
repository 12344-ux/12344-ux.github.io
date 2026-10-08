// PostgREST minimo para probar em-webhook contra el Postgres LOCAL.
// Solo atiende POST /rest/v1/rpc/em_webhook_registrar y lo ejecuta como
// service_role con psql. Registra los headers recibidos para comprobar que la
// funcion manda la llave de servicio en apikey y Authorization.
const LLAVE = Deno.env.get("LLAVE_SERVICIO_FALSA")!;
const vistos: Array<{ apikey: string | null; auth: string | null }> = [];

Deno.serve({ port: 54321 }, async (req) => {
  const u = new URL(req.url);
  if (u.pathname === "/__vistos") return Response.json(vistos);
  if (req.method !== "POST" || u.pathname !== "/rest/v1/rpc/em_webhook_registrar") {
    return Response.json({ message: "ruta no simulada " + u.pathname }, { status: 404 });
  }
  vistos.push({ apikey: req.headers.get("apikey"), auth: req.headers.get("authorization") });
  if (req.headers.get("apikey") !== LLAVE || req.headers.get("authorization") !== `Bearer ${LLAVE}`) {
    return Response.json({ code: "42501", message: "permission denied for function em_webhook_registrar" }, { status: 401 });
  }
  const b = await req.json();
  if (b.p_svix_id === "msg_forzar_falla_db") {
    return Response.json({ code: "57P01", message: "terminating connection due to administrator command" }, { status: 503 });
  }
  const p = new Deno.Command("psql", {
    args: ["-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", "impulse_pruebas",
           "-v", "id=" + String(b.p_svix_id), "-v", "ev=" + JSON.stringify(b.p_evento)],
    stdin: "piped", stdout: "piped", stderr: "piped",
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" },
  }).spawn();
  const w = p.stdin.getWriter();
  await w.write(new TextEncoder().encode("set role service_role;\nselect em_webhook_registrar(:'id', :'ev'::jsonb);\n"));
  await w.close();
  const o = await p.output();
  const out = new TextDecoder().decode(o.stdout).trim();
  const err = new TextDecoder().decode(o.stderr).trim();
  if (!o.success) {
    const m = err.replace(/^psql:.*?ERROR:\s*/s, "").split("\n")[0];
    return Response.json({ code: "P0001", message: m }, { status: 400 });
  }
  return new Response(out.split("\n").pop(), { headers: { "Content-Type": "application/json" } });
});
