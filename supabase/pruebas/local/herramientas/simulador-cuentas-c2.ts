// Supabase Auth + PostgREST minimo para probar cuenta-inicializar con JWT real.
const ANON = Deno.env.get("ANON_KEY_FALSA")!;
const UID_PASSWORD = "7ec20000-0000-4000-8000-000000002001";
const UID_GOOGLE = "7ec20000-0000-4000-8000-000000002002";
const UID_NO_CONFIRMADO = "7ec20000-0000-4000-8000-000000002003";
const UID_BLOQUEADA = "7ec20000-0000-4000-8000-000000002004";
const UID_CERRADA = "7ec20000-0000-4000-8000-000000002005";
const UID_PERSONAL = "7ec20000-0000-4000-8000-000000002006";
const usuarios: Record<
  string,
  { id: string; email: string; confirmado: boolean; proveedor: string }
> = {
  "jwt-password-c2": {
    id: UID_PASSWORD,
    email: "http-password-c2@local.invalid",
    confirmado: true,
    proveedor: "email",
  },
  "jwt-google-c2": {
    id: UID_GOOGLE,
    email: "http-google-c2@local.invalid",
    confirmado: true,
    proveedor: "google",
  },
  "jwt-no-confirmado-c2": {
    id: UID_NO_CONFIRMADO,
    email: "http-no-confirmado-c2@local.invalid",
    confirmado: false,
    proveedor: "email",
  },
  "jwt-bloqueada-c2": {
    id: UID_BLOQUEADA,
    email: "http-bloqueada-c2@local.invalid",
    confirmado: true,
    proveedor: "email",
  },
  "jwt-cerrada-c2": {
    id: UID_CERRADA,
    email: "http-cerrada-c2@local.invalid",
    confirmado: true,
    proveedor: "email",
  },
  "jwt-personal-c2": {
    id: UID_PERSONAL,
    email: "http-personal-c2@local.invalid",
    confirmado: true,
    proveedor: "email",
  },
};
const vistos: Array<{
  ruta: string;
  apikey: string | null;
  authorization: string | null;
}> = [];

function token(req: Request): string {
  return (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
}

async function ejecutarRpc(
  uid: string,
): Promise<{ ok: boolean; salida: string; error: string }> {
  const claims = JSON.stringify({ sub: uid, role: "authenticated" }).replace(
    /'/g,
    "''",
  );
  const p = new Deno.Command("psql", {
    args: ["-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", "impulse_pruebas"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" },
  }).spawn();
  const w = p.stdin.getWriter();
  await w.write(
    new TextEncoder().encode(
      `set request.jwt.claims to '${claims}'; set role authenticated; select cc_inicializar_cuenta();\n`,
    ),
  );
  await w.close();
  const o = await p.output();
  return {
    ok: o.success,
    salida:
      new TextDecoder().decode(o.stdout).trim().split("\n").pop() ?? "null",
    error: new TextDecoder()
      .decode(o.stderr)
      .replace(/^.*?ERROR:\s*/s, "")
      .split("\n")[0],
  };
}

Deno.serve({ port: 54321 }, async (req: Request) => {
  const u = new URL(req.url);
  if (u.pathname === "/") return Response.json({ ok: true });
  if (u.pathname === "/__vistos") return Response.json(vistos);

  vistos.push({
    ruta: u.pathname,
    apikey: req.headers.get("apikey"),
    authorization: req.headers.get("authorization"),
  });

  if (req.headers.get("apikey") !== ANON) {
    return Response.json({ message: "apikey invalida" }, { status: 401 });
  }

  const jwt = token(req);
  const usuario = usuarios[jwt];
  if (req.method === "GET" && u.pathname === "/auth/v1/user") {
    if (!usuario)
      return Response.json({ message: "jwt invalido" }, { status: 401 });
    return Response.json({
      id: usuario.id,
      aud: "authenticated",
      role: "authenticated",
      email: usuario.email,
      email_confirmed_at: usuario.confirmado ? "2026-11-01T00:00:00Z" : null,
      phone: "",
      app_metadata: {
        provider: usuario.proveedor,
        providers: [usuario.proveedor],
      },
      user_metadata: {},
      identities: [],
      created_at: "2026-11-01T00:00:00Z",
      updated_at: "2026-11-01T00:00:00Z",
    });
  }

  if (
    req.method === "POST" &&
    u.pathname === "/rest/v1/rpc/cc_inicializar_cuenta"
  ) {
    if (!usuario)
      return Response.json({ message: "jwt invalido" }, { status: 401 });
    const r = await ejecutarRpc(usuario.id);
    if (!r.ok)
      return Response.json(
        { code: "P0001", message: r.error },
        { status: 400 },
      );
    return new Response(r.salida, {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  return Response.json({ message: "ruta no simulada" }, { status: 404 });
});
