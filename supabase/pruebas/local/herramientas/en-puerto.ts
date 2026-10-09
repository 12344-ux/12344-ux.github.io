// ============================================================
// Arranca una Edge Function SIN modificarla en otro puerto, para tener varias
// funciones vivas a la vez en el banco local (Deno.serve sin puerto usa 8000).
// Uso: PUERTO_FN=8001 MODULO_FN=/ruta/index.ts deno run -A en-puerto.ts
// ============================================================
const puerto = Number(Deno.env.get("PUERTO_FN") ?? "8001");
const original = Deno.serve.bind(Deno);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (a: any, b?: any) =>
  typeof a === "function" ? original({ port: puerto }, a) : original({ ...a, port: puerto }, b);
await import(new URL(Deno.env.get("MODULO_FN")!, "file://").href);
