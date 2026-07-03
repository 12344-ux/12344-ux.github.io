// ============================================================
// Stramont · Informe interno (capacidad + trazabilidad + ventas)
// - NUNCA se llama con la llave pública desde el navegador: usa
//   SUPABASE_SERVICE_ROLE_KEY del lado del servidor, igual que la
//   función "entrega", y se protege con el mismo LINK_SECRET.
// - informe.html (uso interno, no enlazado en la navegación pública)
//   le pide este secreto al dueño y lo reenvía aquí.
//
// Por qué existe esta función y no se lee la tabla "pedidos" ni el
// bucket "apuntes" directo desde el navegador con la llave pública:
// esa llave YA es pública (queda visible en el código fuente de
// simulacion.html). Si le diéramos permiso de lectura sobre pedidos
// o listado completo del bucket, cualquier visitante podría enumerar
// correos y carpetas de todos los clientes. Eso rompe la línea
// ética del proyecto (nunca exponer datos de clientes).
//
// Modo (uno solo, de solo lectura):
//   GET ?key=LINK_SECRET
//     -> JSON con: uso de storage (bucket "apuntes"), lista de pedidos,
//        alertas de pedidos sin entregar hace >48h, y resumen de
//        ventas de los últimos 15/30 días.
//
// Variables (ya existen en el proyecto, compartidas con "entrega"):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, LINK_SECRET
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUCKET_APUNTES = "apuntes";
const LIMITE_STORAGE_BYTES = 1024 * 1024 * 1024; // 1 GB (plan gratuito Supabase)
const HORAS_ALERTA = 48; // pedidos sin guia_entregada pasadas estas horas -> alerta
const PRECIOS: Record<string, number> = {
  "Acceso 10 días": 3,
  "Acceso 30 días": 5,
};

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "*",
};

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// El bucket "apuntes" tiene estructura correo/pedidoId/archivo, así que
// list() de un solo nivel no basta: hay que recorrer subcarpetas.
async function sumarBucket(client: ReturnType<typeof sb>, bucket: string, prefijo = "", profundidadMax = 6): Promise<{ bytes: number; archivos: number }> {
  if (profundidadMax <= 0) return { bytes: 0, archivos: 0 };
  const { data, error } = await client.storage.from(bucket).list(prefijo, {
    limit: 1000,
    sortBy: { column: "name", order: "asc" },
  });
  if (error || !data) return { bytes: 0, archivos: 0 };

  let bytes = 0;
  let archivos = 0;
  for (const item of data) {
    const ruta = prefijo ? `${prefijo}/${item.name}` : item.name;
    // Un objeto real tiene id != null; una "carpeta" no tiene id ni metadata.
    if (item.id !== null && item.metadata) {
      bytes += item.metadata.size ?? 0;
      archivos += 1;
    } else {
      const sub = await sumarBucket(client, bucket, ruta, profundidadMax - 1);
      bytes += sub.bytes;
      archivos += sub.archivos;
    }
  }
  return { bytes, archivos };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") return new Response("Usa GET.", { status: 405, headers: CORS });

  const url = new URL(req.url);
  const SECRET = Deno.env.get("LINK_SECRET") || "";
  if (!SECRET) return new Response("Falta configurar LINK_SECRET.", { status: 500, headers: CORS });
  if (url.searchParams.get("key") !== SECRET) {
    return new Response(JSON.stringify({ error: "No autorizado." }), { status: 403, headers: { ...CORS, "content-type": "application/json" } });
  }

  const client = sb();

  // --- Capacidad de Storage (bucket "apuntes") ---
  const uso = await sumarBucket(client, BUCKET_APUNTES);
  const storage = {
    bytesUsados: uso.bytes,
    archivos: uso.archivos,
    limiteBytes: LIMITE_STORAGE_BYTES,
    porcentaje: Math.round((uso.bytes / LIMITE_STORAGE_BYTES) * 1000) / 10,
  };

  // --- Pedidos (tabla) ---
  const { data: pedidosRaw, error: errPedidos } = await client
    .from("pedidos")
    .select("*")
    .order("fecha_compra", { ascending: false })
    .limit(500);

  if (errPedidos) {
    return new Response(JSON.stringify({ error: "Error leyendo pedidos: " + errPedidos.message }), {
      status: 500, headers: { ...CORS, "content-type": "application/json" },
    });
  }

  const ahora = Date.now();
  const pedidos = (pedidosRaw || []).map((p: any) => {
    const horasDesdeCompra = p.fecha_compra ? (ahora - new Date(p.fecha_compra).getTime()) / 3_600_000 : 0;
    return {
      ...p,
      alerta_pendiente: !p.guia_entregada && horasDesdeCompra >= HORAS_ALERTA,
      horas_desde_compra: Math.round(horasDesdeCompra),
    };
  });

  // --- Resumen de ventas (15 y 30 días) ---
  function resumen(dias: number) {
    const desde = ahora - dias * 86_400_000;
    const enRango = (pedidosRaw || []).filter((p: any) => p.fecha_compra && new Date(p.fecha_compra).getTime() >= desde);
    const porPlan: Record<string, number> = {};
    let ingreso = 0;
    for (const p of enRango) {
      const plan = p.plan || "(sin plan)";
      porPlan[plan] = (porPlan[plan] || 0) + 1;
      ingreso += PRECIOS[plan] ?? 0;
    }
    return { dias, total: enRango.length, porPlan, ingresoEstimadoUSD: ingreso };
  }

  const ventas = { ultimos15: resumen(15), ultimos30: resumen(30) };

  return new Response(
    JSON.stringify({ storage, pedidos, ventas, generadoEn: new Date().toISOString() }, null, 2),
    { headers: { ...CORS, "content-type": "application/json; charset=utf-8" } },
  );
});
