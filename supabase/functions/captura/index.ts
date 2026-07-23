// ============================================================
// Stramont · Captura de correos (Base de correos — Frente A) · PÚBLICA
// La llama el muro de la guía demo (segmentacion-de-mercados.html) cuando
// un prospecto deja su correo. Guarda el correo en la tabla "correos".
//
// SEGURIDAD / ANTI-ABUSO (por qué NO es inserción pública directa):
//   - La tabla "correos" no acepta inserción con la llave pública (evita
//     que cualquiera inunde la base con correos falsos). Todo pasa por aquí.
//   - Validación estricta de formato de correo + topes de longitud.
//   - Rate-limit BÁSICO por IP, EN MEMORIA (no se guardan IPs: sería un dato
//     personal extra que preferimos no almacenar). Es best-effort; se
//     reinicia en cada arranque en frío, suficiente para frenar un flood.
//   - Dedupe: (correo, origen) es único -> el mismo correo no crea filas
//     repetidas (idempotente).
//   - "origen" se fija a valores conocidos; no se acepta cualquier cosa.
//
// Verify JWT debe estar APAGADO (la página pública la llama sin token).
//   POST body: { correo, origen? }
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "*",
};
const ORIGENES_VALIDOS = ["prospecto_demo", "lista_espera_reapertura"];
const MAX_CORREO = 120;
const RL_MAX = 5;            // máximo de capturas
const RL_VENTANA_MS = 60000; // por IP y por minuto

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

function esCorreoPrueba(correo: string): boolean {
  const c = (correo || "").toLowerCase().trim();
  if (c === "pruebasmontaguth@gmail.com") return true;
  return c.startsWith("prueba") || c.endsWith("@example.com") || c.endsWith(".test");
}

// Validación de formato razonable (no exhaustiva, pero corta lo obvio).
function correoValido(c: string): boolean {
  if (!c || c.length > MAX_CORREO) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(c);
}

// Rate-limit en memoria por IP (sin persistir IPs). Best-effort.
const golpes = new Map<string, number[]>();
function rateLimited(ip: string): boolean {
  const ahora = Date.now();
  const previos = (golpes.get(ip) || []).filter((t) => ahora - t < RL_VENTANA_MS);
  previos.push(ahora);
  golpes.set(ip, previos);
  if (golpes.size > 5000) golpes.clear(); // evita crecer sin límite
  return previos.length > RL_MAX;
}


Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  // IP para el rate-limit (no se guarda, solo se usa en memoria).
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "desconocida";
  if (rateLimited(ip)) return json({ error: "Demasiados intentos. Espera un momento." }, 429);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "JSON inválido." }, 400); }

  const correo = String(body?.correo || "").trim().toLowerCase();
  let origen = String(body?.origen || "prospecto_demo").trim();
  if (!ORIGENES_VALIDOS.includes(origen)) origen = "prospecto_demo";
  if (!correoValido(correo)) return json({ error: "Correo no válido." }, 400);

  const client = sb();
  // Upsert idempotente: si (correo, origen) ya existe, no crea otra fila.
  const { error } = await client.from("correos").upsert(
    { correo, origen, es_prueba: esCorreoPrueba(correo) },
    { onConflict: "correo,origen", ignoreDuplicates: true },
  );
  if (error) return json({ error: "No se pudo registrar." }, 500);

  return json({ ok: true });
});
