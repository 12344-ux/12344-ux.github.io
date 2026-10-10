// Doble local de Supabase Auth/perfil + Dropi con la forma REAL de los datos
// (gallery/photos con urlS3 relativo, count = 0, variantes con
// attribute_values y warehouse_product_variation). Solo para verificación.
const NOMBRES = ["Bafle Bluetooth", "Bafle Bluetooth Diseño Carro Deportivo H", "Combo Que Golazo Airpods + Bafle",
  "Parlantes Bafles Pc Computador Luces Rgb", "Bafle Altavoz Bluetooth Inalámbrico 2-1", "BAFLE RECARGABLE CON MICROFONO LED 8MM"];
const TOTAL = 60;
const ID_VARIABLE = 2213853;
function producto(i: number) {
  const id = 2213853 - i * 37;
  return {
    id,
    name: NOMBRES[i % NOMBRES.length] + (i >= NOMBRES.length ? ` · ${i + 1}` : ""),
    sku: "PRODUCTO", type: id === ID_VARIABLE ? "VARIABLE" : "SIMPLE", active: true,
    sale_price: 40000 + i * 1000, suggested_price: 80000 + i * 1500,
    categories: [{ name: "Tecnología" }],
    gallery: i === 2
      ? [{ id: 1, urlS3: "colombia/products/roto/foto.jpg" }]
      : [
        { id: 1, urlS3: `colombia/products/${id}/a.jpg` },
        { id: 2, urlS3: `colombia/products/${id}/b.jpg` },
        { id: 3, urlS3: `colombia/products/${id}/c.jpg` },
      ],
    variations: id === ID_VARIABLE
      ? [
        { id: 7001, sku: "B-N", sale_price: 41000, suggested_price: 82000,
          attribute_values: [{ attribute_name: "Color", value: "Negro" }],
          warehouse_product_variation: [{ warehouse_id: 1, stock: 4 }, { warehouse_id: 2, stock: 6 }],
          gallery: [{ urlS3: `colombia/products/${id}/negro.jpg` }] },
        { id: 7002, sku: "B-R", sale_price: 42000, stock: 3,
          attribute_values: [{ attribute_name: "Color", value: "Rojo" }] },
      ]
      : (i % 5 === 4 ? [{ id: 1, name: "Negro" }, { id: 2, name: "Rojo" }] : []),
    warehouse_product: id === ID_VARIABLE ? [] : [{ warehouse_id: 1, stock: i % 5 === 4 ? 0 : 100 }],
    user: { id: 8785 + i, verified: true },
  };
}
Deno.serve({ port: 8810, onListen() {} }, async (req) => {
  const ruta = new URL(req.url).pathname;
  if (ruta === "/auth/v1/user") return Response.json({ id: "89e5028d-8c17-4deb-89c3-59acbd0ee2f2" });
  if (ruta === "/rest/v1/perfiles") return Response.json([{ rol: "admin" }]);
  if (ruta === "/integrations/categories/") return Response.json({ isSuccess: true, objects: [{ name: "Tecnología" }] });
  if (ruta === "/integrations/products/index") {
    const f = await req.json();
    const desde = Number(f.startData) || 0, n = Number(f.pageSize) || 0;
    const objetos = [];
    for (let i = desde; i < Math.min(desde + n, TOTAL); i++) objetos.push(producto(i));
    return Response.json({ isSuccess: true, count: 0, objects: objetos });
  }
  const m = ruta.match(/^\/integrations\/products\/v2\/(\d+)$/);
  if (m) {
    const id = Number(m[1]);
    const i = Math.round((2213853 - id) / 37);
    const base = (i >= 0 && i < TOTAL && 2213853 - i * 37 === id) ? producto(i) : { ...producto(0), id, name: "Ficha abierta por id" };
    const p = { ...base } as Record<string, unknown>;
    p.photos = p.gallery; delete p.gallery;
    return Response.json({ isSuccess: true, objects: p });
  }
  if (/^\/integrations\/products\/\d+$/.test(ruta)) return Response.json({ isSuccess: false, message: "No tiene permisos" }, { status: 400 });
  return Response.json({ error: "no esperada " + ruta }, { status: 404 });
});
