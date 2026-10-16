// Bateria HTTP de cuenta-inicializar contra Auth/PostgREST simulados y SQL real.
const FN = "http://localhost:8000";
const SB = "http://localhost:54321";
const ORIGEN = "https://magandhi.com";
const resultados: Array<[boolean, string]> = [];
const chk = (ok: boolean, nombre: string) => resultados.push([!!ok, nombre]);

async function sql(q: string) {
  const o = await new Deno.Command("psql", {
    args: ["-tAqc", q, "-d", "impulse_pruebas"],
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres" },
  }).output();
  return new TextDecoder().decode(o.stdout).trim();
}

async function pedir(opts: {
  method?: string;
  origin?: string | null;
  jwt?: string;
  body?: unknown;
}) {
  const headers: Record<string, string> = {};
  if (opts.origin !== null) headers.origin = opts.origin ?? ORIGEN;
  if (opts.jwt) headers.authorization = `Bearer ${opts.jwt}`;
  if ((opts.method ?? "POST") === "POST")
    headers["content-type"] = "application/json";
  const cuerpo =
    opts.body === undefined
      ? "{}"
      : typeof opts.body === "string"
        ? opts.body
        : JSON.stringify(opts.body);
  const r = await fetch(FN, {
    method: opts.method ?? "POST",
    headers,
    body: (opts.method ?? "POST") === "POST" ? cuerpo : undefined,
  });
  const texto = await r.text();
  let j: Record<string, unknown> = {};
  try {
    j = JSON.parse(texto);
  } catch {
    /* OPTIONS no lleva body */
  }
  return { status: r.status, headers: r.headers, j, texto };
}

async function pedirChunked(jwt: string) {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode('{"relleno":"'));
      controller.enqueue(encoder.encode("x".repeat(1400)));
      controller.enqueue(encoder.encode('"}'));
      controller.close();
    },
  });
  const r = await fetch(FN, {
    method: "POST",
    headers: {
      origin: ORIGEN,
      authorization: `Bearer ${jwt}`,
      "content-type": "application/json",
    },
    body,
  });
  return { status: r.status, texto: await r.text() };
}

for (const origin of [
  "https://magandhi.com",
  "https://www.magandhi.com",
  "https://12344-ux.github.io",
]) {
  const r = await pedir({ method: "OPTIONS", origin });
  chk(
    r.status === 204 &&
      r.headers.get("access-control-allow-origin") === origin &&
      r.headers.get("cache-control") === "no-store",
    `preflight permite solo ${origin} y no se cachea`,
  );
}
let r = await pedir({ method: "OPTIONS", origin: "https://malicioso.example" });
chk(
  r.status === 403 && !r.headers.has("access-control-allow-origin"),
  "preflight rechaza origen ajeno sin ACAO",
);
r = await pedir({ origin: null, jwt: "jwt-password-c2" });
chk(
  r.status === 403 && !r.headers.has("access-control-allow-origin"),
  "POST sin Origin no atraviesa CORS",
);
r = await pedir({ method: "GET", origin: ORIGEN });
chk(
  r.status === 405 && r.headers.get("cache-control") === "no-store",
  "GET se rechaza y no se cachea",
);

r = await pedir({ origin: ORIGEN });
chk(
  r.status === 401 && r.j.codigo === "CC_SESION",
  "POST sin JWT exige sesion",
);
r = await pedir({ origin: ORIGEN, jwt: "jwt-invalido-c2" });
chk(
  r.status === 401 && r.j.codigo === "CC_SESION",
  "getUser rechaza JWT invalido",
);
r = await pedir({ origin: ORIGEN, jwt: "jwt-no-confirmado-c2" });
chk(
  r.status === 403 && r.j.codigo === "CC_CONFIRMACION_REQUERIDA",
  "email_confirmed_at nulo se rechaza sin mirar proveedor",
);
chk(
  (await sql(
    "select count(*) from cuentas_cliente where auth_user_id='7ec20000-0000-4000-8000-000000002003'",
  )) === "0",
  "usuario no confirmado no deja cuenta",
);

const noDisponibles: string[] = [];
for (const [jwt, caso] of [
  ["jwt-bloqueada-c2", "cuenta bloqueada"],
  ["jwt-cerrada-c2", "cuenta cerrada"],
  ["jwt-personal-c2", "identidad de personal"],
]) {
  r = await pedir({ origin: ORIGEN, jwt });
  chk(
    r.status === 403 && r.j.codigo === "CC_NO_DISPONIBLE",
    `${caso} recibe rechazo público opaco`,
  );
  noDisponibles.push(r.texto);
}
chk(
  new Set(noDisponibles).size === 1,
  "bloqueada, cerrada y personal reciben exactamente la misma respuesta",
);

r = await pedir({ origin: ORIGEN, jwt: "jwt-password-c2" });
const respuestaPassword = r.texto;
chk(
  r.status === 200 && r.j.ok === true && Object.keys(r.j).length === 1,
  "password confirmado inicializa con respuesta minima",
);
chk(
  r.headers.get("cache-control") === "no-store",
  "respuesta autenticada usa no-store",
);
chk(
  (await sql(
    "select count(*) from cuentas_cliente where auth_user_id='7ec20000-0000-4000-8000-000000002001' and customer_id='7ec21000-0000-4000-8000-000000002001'",
  )) === "1",
  "RPC real vincula el historico del usuario password",
);
r = await pedir({ origin: ORIGEN, jwt: "jwt-password-c2" });
chk(
  r.status === 200 &&
    r.texto === respuestaPassword &&
    (await sql(
      "select count(*) from cuentas_cliente where auth_user_id='7ec20000-0000-4000-8000-000000002001'",
    )) === "1",
  "repetir HTTP es idempotente y responde igual",
);

r = await pedir({ origin: "https://www.magandhi.com", jwt: "jwt-google-c2" });
chk(
  r.status === 200 && r.j.ok === true,
  "Google confirmado usa la misma puerta agnostica",
);
chk(
  (await sql(
    "select count(*) from cuentas_cliente where auth_user_id='7ec20000-0000-4000-8000-000000002002' and customer_id is null",
  )) === "1",
  "Google sin historia crea cuenta sin customer_id",
);

r = await pedir({
  origin: ORIGEN,
  jwt: "jwt-password-c2",
  body: { customer_id: "7ec21000-0000-4000-8000-000000002001" },
});
chk(r.status === 400, "body no puede elegir customer_id");
r = await pedir({ origin: ORIGEN, jwt: "jwt-password-c2", body: [] });
chk(r.status === 400, "body debe ser exactamente un objeto vacio");
r = await pedir({ origin: ORIGEN, jwt: "jwt-password-c2", body: "{roto" });
chk(r.status === 400, "JSON invalido se rechaza");
r = await pedir({
  origin: ORIGEN,
  jwt: "jwt-password-c2",
  body: JSON.stringify({ relleno: "x".repeat(1100) }),
});
chk(r.status === 413, "body con Content-Length mayor a 1 KiB se rechaza");
const chunked = await pedirChunked("jwt-password-c2");
chk(
  chunked.status === 413,
  "body chunked sin Content-Length se corta al superar 1 KiB",
);

const vistos = (await (await fetch(`${SB}/__vistos`)).json()) as Array<{
  ruta: string;
  apikey: string;
  authorization: string;
}>;
const anon = Deno.env.get("ANON_KEY_FALSA");
chk(
  vistos.some((v) => v.ruta === "/auth/v1/user") &&
    vistos.some((v) => v.ruta === "/rest/v1/rpc/cc_inicializar_cuenta"),
  "la Function ejecuta getUser explicito antes de la RPC",
);
chk(
  vistos.length > 0 && vistos.every((v) => v.apikey === anon),
  "todas las llamadas Supabase usan solo ANON key",
);
chk(
  vistos.every((v) => /^Bearer jwt-/.test(v.authorization ?? "")),
  "Authorization conserva solo el JWT de la persona",
);

const salidaPublica =
  resultados.map(([, n]) => n).join(" ") + respuestaPassword;
chk(
  !/@local\.invalid|7ec2[0-9a-f-]{30,}|customer_id|coincidencias|correo_ambiguo/.test(
    respuestaPassword,
  ),
  "respuesta publica no revela PII, IDs ni resultado del vinculo",
);
chk(
  !salidaPublica.includes(
    Deno.env.get("SERVICE_ROLE_FALSA") ?? "servicio-que-no-existe",
  ),
  "la prueba no observa service_role",
);

for (const [ok, nombre] of resultados)
  console.log(`${ok ? "pasa" : "FALLA"} | ${nombre}`);
console.log(
  `RESUMEN | ${resultados.length} comprobaciones · ${resultados.filter(([ok]) => !ok).length} fallan`,
);
if (resultados.some(([ok]) => !ok)) Deno.exit(1);
