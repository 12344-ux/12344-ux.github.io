# Dropshipping D2a («Llevar a Campañas») en Chromium (PC 1280 y celular 390).
# dropi-sonda es la REAL (:8811) contra el doble de Dropi (:8810). Storage,
# bandeja, RPC de importación y lecturas del editor se simulan en memoria con
# las mismas reglas de la migración (keys propias ya subidas, idempotencia).
import functools, http.server, threading, json, time, base64, urllib.request, urllib.parse, sys, re, uuid, io
from playwright.sync_api import sync_playwright
from PIL import Image

REPO = "/projects/sandbox/12344-ux.github.io"
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=REPO)
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8813), H); threading.Thread(target=S.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:8813/"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPS = sys.argv[1] if len(sys.argv) > 1 else None
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp,
       "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []; chk = lambda ok, q: res.append((bool(ok), q))

def png(color, size=(1200, 1200)):
    b = io.BytesIO(); Image.new("RGB", size, color).save(b, "PNG"); return b.getvalue()
FOTO = {"a": png((166, 51, 46)), "b": png((16, 28, 51)), "c": png((194, 138, 58)), "negro": png((20, 20, 20))}

E = {}
def reset():
    E.update(bandeja=[], storage={}, removidos=[], fichas=[], campanas=[], rpc=[], fallar_rpc=False, productos=[])
reset()

def fila_candidato(a):
    return {"id": str(uuid.uuid4()), "variacion_externa_id": "", "producto_externo_id": a["p_producto_externo_id"],
            "proveedor_externo_id": a.get("p_proveedor_externo_id"), "nombre_externo": a["p_nombre_externo"],
            "categoria_externa": a.get("p_categoria_externa"), "precio_proveedor": a.get("p_precio_proveedor"),
            "precio_sugerido": a.get("p_precio_sugerido"), "stock_reportado": a.get("p_stock_reportado"),
            "stock_leido_en": a.get("p_stock_leido_en"), "fotos_remotas": a.get("p_fotos_remotas") or [],
            "estado": "bandeja", "actualizado": time.time()}

def llevar(a):
    if E["fallar_rpc"]:
        return 400, {"message": "DS_SIN_ACCESO: llevar a Campañas exige los módulos Dropshipping y Marketing."}
    cand = next((c for c in E["bandeja"] if c["id"] == a["p_candidato_id"]), None)
    if not cand: return 400, {"message": "DS_CANDIDATO_NO_ENCONTRADO: no existe."}
    var = a.get("p_variacion_externa_id") or ""
    for k in a.get("p_imagenes") or []:
        if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,100}\.(webp|jpg|jpeg|png)$", k) or re.search(r"-sm\.[a-z]+$", k):
            return 400, {"message": "DS_IMAGEN_INVALIDA: " + k}
        if k not in E["storage"]: return 400, {"message": "DS_IMAGEN_NO_SUBIDA: " + k}
    ex = next((f for f in E["fichas"] if f["producto_externo_id"] == cand["producto_externo_id"] and f["variacion_externa_id"] == var), None)
    if ex:
        cp = next(c for c in E["campanas"] if c["product_id_ref"] == ex["product_id"])
        return 200, {"ya_existia": True, "producto_id": ex["product_id"], "campana_id": cp["id"]}
    pid, cid = str(uuid.uuid4()), str(uuid.uuid4())
    E["productos"].append({"id": pid, "sku": "MAG-DROP-%04d" % (len(E["productos"]) + 1), "nombre": a["p_nombre"], "origen": "proveedor", "activo": True})
    E["fichas"].append({"product_id": pid, "candidato_id": cand["id"], "producto_externo_id": cand["producto_externo_id"],
                        "variacion_externa_id": var, "variacion_nombre": a.get("p_variacion_nombre"),
                        "costo_reportado": a.get("p_costo_reportado"), "stock_reportado": a.get("p_stock_reportado"),
                        "stock_leido_en": a.get("p_stock_leido_en")})
    E["campanas"].append({"id": cid, "nombre": a["p_nombre"], "product_id_ref": pid, "publicado": False,
                          "imagenes": a.get("p_imagenes") or [], "slug": None, "categoria_codigo": None, "precio_venta": None})
    cand["estado"] = "llevado_a_campanas"; cand["actualizado"] = time.time()
    return 200, {"ya_existia": False, "producto_id": pid, "sku": E["productos"][-1]["sku"], "campana_id": cid}

def qs(u): return urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
def en(q, campo):
    v = q.get(campo, [""])[0]
    if v.startswith("in.("): return [x.strip('"') for x in v[4:-1].split(",")]
    if v.startswith("eq."): return [v[3:]]
    return None

def man(route):
    rq = route.request; u = rq.url
    obj = "vnd.pgrst.object" in (rq.headers.get("accept") or "")
    if u.startswith("https://d39ru7awumhhs2.cloudfront.net/"):
        path = urllib.parse.urlparse(u).path
        if "/roto/" in path: return route.fulfill(status=403, body="<Error/>", headers={"content-type": "application/xml", "access-control-allow-origin": "*"})
        nombre = path.rsplit("/", 1)[-1].split(".")[0]
        return route.fulfill(status=200, body=FOTO.get(nombre, FOTO["a"]), headers={"content-type": "image/png", "access-control-allow-origin": "*"})
    if "/storage/v1/object/public/campanas/" in u:
        return route.fulfill(status=200, body=FOTO["a"], headers={"content-type": "image/png"})
    if "/storage/v1/object/campanas/" in u and rq.method == "POST":
        key = urllib.parse.unquote(u.split("/storage/v1/object/campanas/")[1].split("?")[0])
        if key in E["storage"]: return route.fulfill(status=400, json={"statusCode": "409", "error": "Duplicate", "message": "The resource already exists"})
        E["storage"][key] = len(rq.post_data_buffer or b"")
        return route.fulfill(json={"Key": "campanas/" + key, "Id": str(uuid.uuid4())})
    if "/storage/v1/object/campanas" in u and rq.method == "DELETE":
        pref = (json.loads(rq.post_data or "{}")).get("prefixes", [])
        for k in pref: E["storage"].pop(k, None); E["removidos"].append(k)
        return route.fulfill(json=[{"name": k} for k in pref])
    if "/auth/v1/" in u: return route.fulfill(json=SES["user"])
    if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": "admin", "modulos": []})
    if "/functions/v1/dropi-sonda" in u:
        if rq.method == "OPTIONS": return route.fulfill(status=204, headers={"access-control-allow-origin": "*", "access-control-allow-headers": "*"})
        r = urllib.request.Request("http://127.0.0.1:8811/", data=rq.post_data_buffer or b"{}", method="POST",
                                   headers={"content-type": "application/json", "apikey": "anon", "authorization": "Bearer " + jwt,
                                            "origin": "https://montaguth.institute"})
        resp = urllib.request.urlopen(r)
        return route.fulfill(status=resp.status, body=resp.read(), headers={"content-type": "application/json", "access-control-allow-origin": "*"})
    if "/rest/v1/rpc/ds_guardar_candidato" in u:
        a = json.loads(rq.post_data or "{}")
        ex = next((c for c in E["bandeja"] if c["producto_externo_id"] == a["p_producto_externo_id"]), None)
        if ex: ex.update({**fila_candidato(a), "id": ex["id"], "estado": ex["estado"] if ex["estado"] == "llevado_a_campanas" else "bandeja"})
        else: E["bandeja"].append(fila_candidato(a))
        return route.fulfill(json=(ex or E["bandeja"][-1])["id"])
    if "/rest/v1/rpc/ds_actualizar_estado_candidato" in u:
        a = json.loads(rq.post_data or "{}")
        for c in E["bandeja"]:
            if c["id"] == a["p_id"]: c["estado"] = a["p_estado"]; c["actualizado"] = time.time()
        return route.fulfill(json=a["p_id"])
    if "/rest/v1/rpc/ds_llevar_a_campanas" in u:
        a = json.loads(rq.post_data or "{}"); E["rpc"].append(a)
        st, body = llevar(a)
        return route.fulfill(status=st, json=body)
    if "/rest/v1/dropshipping_candidatos" in u:
        return route.fulfill(json=sorted(E["bandeja"], key=lambda c: c["actualizado"], reverse=True))
    if "/rest/v1/producto_proveedor" in u:
        q = qs(u); cand = en(q, "candidato_id"); prod = en(q, "product_id")
        filas = [f for f in E["fichas"] if (cand is None or f["candidato_id"] in cand) and (prod is None or f["product_id"] in prod)]
        return route.fulfill(json=(filas[0] if filas else None) if obj else filas)
    if "/rest/v1/campana_producto" in u:
        q = qs(u); ref = en(q, "product_id_ref"); ids = en(q, "id")
        filas = [c for c in E["campanas"] if (ref is None or c["product_id_ref"] in ref) and (ids is None or c["id"] in ids)]
        if obj and filas:
            c = filas[0]
            return route.fulfill(json={**c, "detalle_presentacion": None, "imagen_banner_path": None, "caracteristica_adicional": None,
                                       "hook_largo": None, "por_que_magandhi": None, "sobre_este_producto": None, "ficha_tecnica": [],
                                       "sello_elegido": False, "tope_escaparate": None, "aviso_urgencia_activo": False,
                                       "aviso_urgencia_cantidad": None, "campana_producto_etiqueta": []})
        return route.fulfill(json=(filas[0] if filas else None) if obj else filas)
    if "/rest/v1/productos" in u:
        q = qs(u); ids = en(q, "id"); origen = en(q, "origen")
        propios = [{"id": "11111111-0000-4000-8000-000000000001", "sku": "MAG-CAB-0001", "nombre": "Shampoo propio", "activo": True, "origen": "propio"}]
        todos = propios + E["productos"]
        filas = [p for p in todos if (ids is None or p["id"] in ids) and (origen is None or p["origen"] in origen)]
        return route.fulfill(json=(filas[0] if filas else None) if obj else filas)
    if "/rest/v1/campana_categoria" in u: return route.fulfill(json=[{"codigo": "hogar", "nombre": "Hogar/limpieza", "orden": 1}])
    if "/rest/v1/campana_etiqueta" in u: return route.fulfill(json=[])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho):
    c = b.new_context(viewport={"width": ancho, "height": 900})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}" % json.dumps(json.dumps(SES)))
    pg = c.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    c.route("**/*", lambda r: man(r) if ("supabase.co" in r.request.url or "cloudfront.net" in r.request.url) else r.continue_())
    pg.goto(BASE + "dropshipping/index.html"); pg.wait_for_selector("#ds-main:not([hidden])", timeout=15000); pg.wait_for_timeout(500)
    return c, pg, err

def buscar_y_agregar(pg, n=1):
    pg.fill("#ds-buscar", "bafle"); pg.click("#ds-consultar")
    pg.wait_for_selector("#ds-resultados .ds-grid", timeout=15000); pg.wait_for_timeout(500)
    for i in range(n):
        pg.locator("#ds-resultados .ds-card").nth(i).locator(".ds-guardar").click()
        pg.wait_for_function("document.querySelector('#ds-carrito-n').textContent === '%d'" % (i + 1), timeout=8000)

def abrir_llevar(pg, idx=0):
    pg.click("#ds-carrito"); pg.wait_for_timeout(350)
    pg.locator("#ds-bandeja .ds-item").nth(idx).locator("[data-llevar]").click()
    pg.wait_for_selector("#ds-importar .ds-imp-paso", timeout=15000); pg.wait_for_timeout(600)

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        reset()
        c, pg, err = abrir(b, ancho)
        buscar_y_agregar(pg, 3)   # 0 = VARIABLE con 2 variantes, 2 = foto rota
        # -------- Dialogo: relee ficha, variantes y fotos --------
        abrir_llevar(pg, 2)  # el más viejo agregado = tarjeta 0 (orden por actualizado desc)
        dlg = pg.locator("#ds-importar")
        chk(dlg.is_visible() and not pg.locator("#ds-cajon").is_visible(), f"{d}: «Llevar a Campañas» abre la ventana y cierra el carrito")
        chk(pg.locator(".ds-imp-var").count() == 2 and "Color: Negro" in (pg.text_content(".ds-imp-var >> nth=0") or ""),
            f"{d}: relee Dropi y muestra las 2 variantes con su nombre real")
        chk(pg.locator(".ds-imp-var >> nth=0 >> input").is_checked() and "10 reportadas" in (pg.text_content(".ds-imp-var >> nth=0") or ""),
            f"{d}: preselecciona la primera variante y muestra su stock por bodega (10)")
        n_fotos = pg.locator(".ds-imp-foto").count()
        chk(n_fotos == 4 and pg.locator(".ds-imp-foto input:checked").count() == 4, f"{d}: fotos = la de la variante + 3 del producto, todas elegidas ({n_fotos})")
        chk(pg.input_value("#ds-imp-nombre").endswith("· Negro"), f"{d}: nombre de trabajo sugerido con la variante: {pg.input_value('#ds-imp-nombre')}")
        chk(not pg.locator("#ds-imp-crear").is_disabled(), f"{d}: «Crear borrador» habilitado")
        fuera = pg.evaluate("""[...document.querySelectorAll('#ds-importar button, #ds-importar .ds-tag, #ds-importar input')].some(e => {
            const r = e.getBoundingClientRect(); return r.width && (r.right > innerWidth + 1 || r.left < -1); })""")
        anchoTag = pg.evaluate("document.querySelector('.ds-imp-var .ds-tag').getBoundingClientRect().width")
        chk(not fuera and anchoTag < 160, f"{d}: nada de la ventana se sale de la pantalla y la etiqueta de stock no se estira ({anchoTag:.0f}px)")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/ds-d2a-llevar-{'pc' if ancho == 1280 else 'celular'}.png", clip={"x": 0, "y": 0, "width": ancho, "height": 900})
        pg.locator(".ds-imp-foto").nth(3).click(); pg.wait_for_timeout(100)
        chk(pg.text_content("#ds-imp-cuenta") == "3 de 4", f"{d}: desmarcar una foto actualiza el contador (3 de 4)")
        pg.fill("#ds-imp-nombre", "Bafle curado · Negro")
        # -------- Crear --------
        pg.click("#ds-imp-crear")
        pg.wait_for_url("**/marketing/campanas/editar.html?id=*", timeout=20000)
        chk("desde=dropshipping" in pg.url, f"{d}: al crear abre el editor de Campañas del borrador")
        a = E["rpc"][-1]
        chk(a["p_variacion_externa_id"] == "7001" and a["p_variacion_nombre"] == "Color: Negro" and a["p_costo_reportado"] == 41000
            and a["p_stock_reportado"] == 10 and a["p_nombre"] == "Bafle curado · Negro", f"{d}: la RPC recibe variante, costo y stock de la RELECTURA")
        chk(len(a["p_imagenes"]) == 3 and all(k in E["storage"] for k in a["p_imagenes"]) and all(not k.endswith(("-sm.webp", "-sm.jpg")) for k in a["p_imagenes"]),
            f"{d}: guarda 3 keys GRANDES ya subidas (nunca una URL de Dropi)")
        sm = [k for k in E["storage"] if re.search(r"-sm\.(webp|jpg)$", k)]
        chk(len(sm) == 3 and len(E["storage"]) == 6, f"{d}: cada foto subió grande + -sm (6 objetos)")
        chk(all(v > 0 for v in E["storage"].values()), f"{d}: los objetos subidos tienen contenido (convertidos en el navegador)")
        # -------- Editor en modo proveedor --------
        pg.wait_for_selector("#cm-main:not([hidden])", timeout=15000); pg.wait_for_timeout(800)
        chk(pg.locator("#cm-proveedor").is_visible() and "Borrador creado desde Dropshipping" in (pg.text_content("#cm-proveedor-tit") or ""),
            f"{d}: el editor avisa que es un borrador de proveedor recién creado")
        datos = pg.text_content("#cm-proveedor-datos") or ""
        chk("Dropi #2213853" in datos and "Color: Negro" in datos and "MAG-DROP-" in datos, f"{d}: muestra Dropi #, variante y SKU interno: {datos}")
        chk(pg.locator("#cm-producto").is_disabled() and pg.input_value("#cm-producto") == E["productos"][-1]["id"],
            f"{d}: el selector de producto queda bloqueado en su ficha proveedor")
        chk(not pg.locator("#cm-tope").is_visible(), f"{d}: el tope de escaparate (stock propio) se oculta")
        chk(pg.input_value("#cm-nombre") == "Bafle curado · Negro", f"{d}: el nombre de trabajo llegó al borrador")
        opciones = pg.eval_on_selector_all("#cm-producto option", "os => os.map(o => o.textContent)")
        chk(any("Shampoo propio" in o for o in opciones), f"{d}: el selector lista productos propios")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/ds-d2a-editor-{'pc' if ancho == 1280 else 'celular'}.png", clip={"x": 0, "y": 0, "width": ancho, "height": 900})
        chk(not err, f"{d}: sin errores de consola hasta el editor {err[:2]}")
        err.clear()
        # -------- Volver: la bandeja enlaza al borrador y ofrece otra variante --------
        pg.goto(BASE + "dropshipping/index.html"); pg.wait_for_selector("#ds-main:not([hidden])", timeout=15000); pg.wait_for_timeout(600)
        pg.click("#ds-carrito"); pg.wait_for_timeout(350)
        item = pg.locator("#ds-bandeja .ds-item").filter(has_text="Abrir en Campañas")
        chk(item.count() == 1 and "Color: Negro" in (item.text_content() or "") and "Borrador" in (item.text_content() or ""),
            f"{d}: la bandeja enlaza al borrador con su variante")
        chk(item.locator("[data-llevar]").text_content().strip() == "Llevar otra variante" and item.locator("[data-estado]").count() == 0,
            f"{d}: ofrece llevar otra variante y ya no permite descartarlo")
        item.locator("[data-llevar]").click(); pg.wait_for_selector("#ds-importar .ds-imp-paso", timeout=15000); pg.wait_for_timeout(500)
        chk(pg.locator(".ds-imp-var--hecha").count() == 1 and pg.locator(".ds-imp-var >> nth=1 >> input").is_checked(),
            f"{d}: la variante ya llevada sale marcada «Ya en Campañas» y se preselecciona la otra")
        # -------- Fallo de la RPC: compensa las fotos subidas --------
        E["fallar_rpc"] = True
        antes = set(E["storage"])
        pg.click("#ds-imp-crear")
        pg.wait_for_function("document.querySelector('#ds-imp-msg').textContent.includes('No quedó nada a medias')", timeout=20000)
        nuevas = [k for k in E["removidos"]]
        chk(set(E["storage"]) == antes and len(nuevas) >= 2, f"{d}: si la RPC falla, borra las fotos recién subidas ({len(nuevas)})")
        chk("exige los módulos" in (pg.text_content("#ds-imp-msg") or "") and "DS_" not in (pg.text_content("#ds-imp-msg") or ""),
            f"{d}: muestra el motivo sin el código técnico")
        chk(not pg.locator("#ds-imp-crear").is_disabled(), f"{d}: y deja reintentar")
        E["fallar_rpc"] = False
        pg.keyboard.press("Escape"); pg.wait_for_timeout(300)
        chk(not pg.locator("#ds-importar").is_visible(), f"{d}: Escape cierra la ventana cuando no está trabajando")
        # -------- Producto sin variantes con una foto rota --------
        pg.click("#ds-carrito"); pg.wait_for_timeout(300)
        pg.locator("#ds-bandeja .ds-item").filter(has_text="Combo").locator("[data-llevar]").click()
        pg.wait_for_selector("#ds-importar .ds-imp-paso", timeout=15000); pg.wait_for_timeout(500)
        chk("sin variantes" in (pg.text_content("#ds-imp-cuerpo") or "") and pg.locator(".ds-imp-foto").count() == 1,
            f"{d}: producto sin variantes: una sola campaña y su única foto")
        pg.click("#ds-imp-crear")
        pg.wait_for_function("document.querySelector('#ds-imp-crear').textContent.includes('Abrir el editor')", timeout=20000)
        chk("no se pudo traer" in (pg.text_content("#ds-imp-cuerpo") or "") and E["rpc"][-1]["p_imagenes"] == [],
            f"{d}: una foto que Dropi no entrega no frena: crea el borrador y avisa que se suba en el editor")
        chk(not err, f"{d}: sin errores de consola {err[:2]}")
        c.close()
    b.close()

S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
f = sum(1 for ok, _ in res if not ok)
print(f"RESUMEN | {len(res)} comprobaciones · {f} fallan")
sys.exit(1 if f else 0)
