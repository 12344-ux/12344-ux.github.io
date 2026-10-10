# Dropshipping D1 (+ ajuste de uso real) en Chromium (PC 1280 y celular 390).
# La función dropi-sonda es la REAL (corre en :8811 contra el doble de Dropi
# en :8810). La bandeja vive en memoria con las mismas reglas del RPC.
import functools, http.server, threading, json, time, base64, urllib.request, urllib.parse, sys, re, uuid, os
from playwright.sync_api import sync_playwright

REPO = "/projects/sandbox/12344-ux.github.io"
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=REPO)
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8812), H); threading.Thread(target=S.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:8812/dropshipping/index.html"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPS = sys.argv[1] if len(sys.argv) > 1 else None
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp,
       "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []; chk = lambda ok, q: res.append((bool(ok), q))
BANDEJA = []
LLAMADAS = []

COLORES = ["#A6332E", "#101C33", "#C28A3A"]
def svg(path):
    letra = path.rsplit("/", 1)[-1][0].upper()
    color = COLORES["abc".index(letra.lower()) % 3] if letra.lower() in "abc" else "#555"
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600"><rect width="600" height="600" fill="#fff"/>'
            '<circle cx="300" cy="300" r="190" fill="%s"/><text x="300" y="335" font-size="110" text-anchor="middle" '
            'fill="#fff" font-family="sans-serif">%s</text></svg>' % (color, letra))

def man(route):
    rq = route.request; u = rq.url
    if u.startswith("https://d39ru7awumhhs2.cloudfront.net/"):
        path = urllib.parse.urlparse(u).path
        if "/roto/" in path: return route.fulfill(status=403, body="<Error/>", headers={"content-type": "application/xml"})
        return route.fulfill(status=200, body=svg(path), headers={"content-type": "image/svg+xml"})
    if "/auth/v1/" in u: return route.fulfill(json=SES["user"])
    if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": "admin", "modulos": []})
    if "/functions/v1/dropi-sonda" in u:
        if rq.method == "OPTIONS": return route.fulfill(status=204, headers={"access-control-allow-origin": "*", "access-control-allow-headers": "*"})
        LLAMADAS.append(json.loads(rq.post_data or "{}"))
        r = urllib.request.Request("http://127.0.0.1:8811/", data=rq.post_data_buffer or b"{}", method="POST",
                                   headers={"content-type": "application/json", "apikey": "anon", "authorization": "Bearer " + jwt,
                                            "origin": "https://montaguth.institute"})
        resp = urllib.request.urlopen(r)
        return route.fulfill(status=resp.status, body=resp.read(), headers={"content-type": "application/json", "access-control-allow-origin": "*"})
    if "/rest/v1/dropshipping_candidatos" in u:
        filas = sorted(BANDEJA, key=lambda c: c["actualizado"], reverse=True)
        return route.fulfill(json=filas)
    if "/rest/v1/rpc/ds_guardar_candidato" in u:
        a = json.loads(rq.post_data or "{}")
        fotos = a.get("p_fotos_remotas") or []
        if len(fotos) > 12 or any((len(x) > 500 or not re.match(r"^https://\S+$", x)) for x in fotos):
            return route.fulfill(status=400, json={"message": "DS_CANDIDATO_FOTO_INVALIDA: solo se aceptan URLs HTTPS sin espacios."})
        ex = next((c for c in BANDEJA if c["producto_externo_id"] == a["p_producto_externo_id"]), None)
        fila = ex or {"id": str(uuid.uuid4()), "variacion_externa_id": ""}
        fila.update({"producto_externo_id": a["p_producto_externo_id"], "proveedor_externo_id": a.get("p_proveedor_externo_id"),
                     "nombre_externo": a["p_nombre_externo"], "categoria_externa": a.get("p_categoria_externa"),
                     "precio_proveedor": a.get("p_precio_proveedor"), "precio_sugerido": a.get("p_precio_sugerido"),
                     "stock_reportado": a.get("p_stock_reportado"), "stock_leido_en": a.get("p_stock_leido_en"),
                     "fotos_remotas": fotos, "estado": "bandeja", "actualizado": time.time()})
        if not ex: BANDEJA.append(fila)
        return route.fulfill(json=fila["id"])
    if "/rest/v1/rpc/ds_actualizar_estado_candidato" in u:
        a = json.loads(rq.post_data or "{}")
        for c in BANDEJA:
            if c["id"] == a["p_id"]: c["estado"] = a["p_estado"]; c["actualizado"] = time.time()
        return route.fulfill(json=a["p_id"])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho):
    c = b.new_context(viewport={"width": ancho, "height": 900})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}" % json.dumps(json.dumps(SES)))
    pg = c.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    c.route("**/*", lambda r: man(r) if ("supabase.co" in r.request.url or "cloudfront.net" in r.request.url) else r.continue_())
    pg.goto(URL); pg.wait_for_selector("#ds-main:not([hidden])", timeout=15000); pg.wait_for_timeout(600)
    return c, pg, err

def fotos_cargadas(pg):
    return pg.evaluate("""[...document.querySelectorAll('#ds-resultados .ds-foto img')].filter(i => i.complete && i.naturalWidth > 0).length""")

def buscar(pg, palabra):
    pg.fill("#ds-buscar", palabra); pg.click("#ds-consultar")
    pg.wait_for_selector("#ds-resultados .ds-grid", timeout=15000); pg.wait_for_timeout(900)

desborde = lambda pg: pg.evaluate("document.scrollingElement.scrollWidth > innerWidth + 1")

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        BANDEJA.clear(); LLAMADAS.clear()
        c, pg, err = abrir(b, ancho)
        chk(pg.locator("#ds-carrito").is_visible() and pg.text_content("#ds-carrito-n") == "0", f"{d}: el carrito aparece en la esquina con 0")
        chk(pg.locator("text=Bandeja de curaduría").count() == 1 and not pg.locator("#ds-cajon").is_visible(), f"{d}: la bandeja ya no ocupa la página; vive en el panel cerrado")
        buscar(pg, "bafle")
        chk(LLAMADAS[-1].get("tamano") == 24, f"{d}: pide 24 por página")
        chk(pg.locator("#ds-resultados .ds-card").count() == 24, f"{d}: muestra 24 resultados (antes 6)")
        meta = pg.text_content("#ds-meta-resultados") or ""
        chk("Mostrando 1–24" in meta and "hay más" in meta and "0 coincidencias" not in meta, f"{d}: el contador ya no dice «0 coincidencias»: «{meta}»")
        pg.evaluate("window.scrollTo(0, document.body.scrollHeight)"); pg.wait_for_timeout(900)
        pg.evaluate("window.scrollTo(0, 0)"); pg.wait_for_timeout(300)
        n = fotos_cargadas(pg)
        chk(n == 23, f"{d}: 23 de 24 fotos remotas se ven ({n}); la rota muestra caja")
        chk(pg.locator("#ds-resultados .ds-foto--rota").count() == 1 and pg.locator("#ds-resultados .ds-foto--rota .ds-foto-ph").is_visible(), f"{d}: una foto rota se reemplaza por «Foto no disponible»")
        src = pg.get_attribute("#ds-resultados .ds-card >> nth=0 >> img", "src") or ""
        chk(src.startswith("https://d39ru7awumhhs2.cloudfront.net/colombia/products/"), f"{d}: la foto sale directo del CDN de Dropi")
        primera = pg.locator("#ds-resultados .ds-card").first
        primera.locator(".ds-foto").hover(); primera.locator(".ds-foto-nav--next").click(); pg.wait_for_timeout(250)
        chk((primera.locator("img").get_attribute("src") or "").endswith("/b.jpg") and primera.locator(".ds-foto-n").text_content() == "2/3", f"{d}: la flecha pasa a la foto 2/3")
        if CAPS and ancho == 1280:
            pg.screenshot(path=f"{CAPS}/ds-d1-1-resultados-pc.png", clip={"x": 0, "y": 0, "width": 1280, "height": 1500}, full_page=True)
        if CAPS and ancho == 390:
            pg.screenshot(path=f"{CAPS}/ds-d1-1-resultados-celular.png", clip={"x": 0, "y": 0, "width": 390, "height": 1500}, full_page=True)
        # Paginación
        sig = pg.locator(".ds-result-head .ds-btn--sig")
        chk(sig.is_enabled() and pg.locator(".ds-result-head [data-pagina]").first.is_disabled(), f"{d}: en la página 1, Siguiente habilitado y Anterior no")
        sig.click(); pg.wait_for_function("document.querySelector('#ds-meta-resultados').textContent.includes('25–48')", timeout=15000); pg.wait_for_timeout(300)
        chk(LLAMADAS[-1].get("inicio") == 24 and "producto_id" not in LLAMADAS[-1], f"{d}: Siguiente pide inicio 24")
        chk(pg.locator(".ds-result-head [data-pagina]").first.is_enabled() and "Página 2" in (pg.text_content(".ds-result-head .ds-paginacion") or ""), f"{d}: página 2 con Anterior habilitado")
        pg.locator(".ds-paginacion--pie .ds-btn--sig").click(); pg.wait_for_function("document.querySelector('#ds-meta-resultados').textContent.includes('49–60')", timeout=15000); pg.wait_for_timeout(300)
        chk(pg.locator("#ds-resultados .ds-card").count() == 12 and pg.locator(".ds-result-head .ds-btn--sig").is_disabled(), f"{d}: última página (12) sin Siguiente")
        pg.locator(".ds-result-head [data-pagina]").first.click(); pg.wait_for_function("document.querySelector('#ds-meta-resultados').textContent.includes('25–48')", timeout=15000)
        chk(True, f"{d}: Anterior vuelve a la página 2")
        # Agregar a la bandeja
        card = pg.locator("#ds-resultados .ds-card").first
        nombre = card.locator("h3").text_content()
        card.locator(".ds-guardar").click(); pg.wait_for_function("document.querySelector('#ds-carrito-n').textContent === '1'", timeout=8000); pg.wait_for_timeout(300)
        card = pg.locator("#ds-resultados .ds-card").first
        chk("En la bandeja" in (card.locator(".ds-card-acciones").text_content() or "") and card.locator(".ds-btn--hecho").is_disabled(), f"{d}: el botón pasa a «En la bandeja» y el carrito cuenta 1")
        chk(len(BANDEJA) == 1 and len(BANDEJA[0]["fotos_remotas"]) == 3, f"{d}: el snapshot guarda las 3 URLs de preview (no descarga nada)")
        pg.locator("#ds-resultados .ds-card").nth(1).locator(".ds-guardar").click(); pg.wait_for_function("document.querySelector('#ds-carrito-n').textContent === '2'", timeout=8000)
        # Abrir el carrito
        pg.click("#ds-carrito"); pg.wait_for_timeout(450)
        chk(pg.locator("#ds-cajon").is_visible() and pg.locator("#ds-bandeja .ds-item").count() == 2, f"{d}: el carrito abre el panel con los 2 candidatos")
        chk(pg.evaluate("[...document.querySelectorAll('#ds-bandeja .ds-foto img')].every(i => i.complete && i.naturalWidth > 0)"), f"{d}: las fotos de la bandeja también vienen de Dropi")
        chk(pg.locator("#ds-bandeja .ds-item").first.locator("[data-llevar]").is_enabled(), f"{d}: «Llevar a Campañas» habilitado para admin (D2a)")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/ds-d1-1-bandeja-{'pc' if ancho == 1280 else 'celular'}.png", clip={"x": 0, "y": 0, "width": ancho, "height": 900})
        pg.locator("#ds-bandeja .ds-item").first.locator("[data-estado=descartado]").click(); pg.wait_for_function("document.querySelector('#ds-carrito-n').textContent === '1'", timeout=8000)
        chk(pg.locator("#ds-bandeja .ds-item").count() == 1 and pg.text_content("#ds-n-descartado") == "1", f"{d}: descartar lo pasa a Descartados y baja el contador")
        pg.click("[data-filtro=descartado]"); pg.wait_for_timeout(200)
        chk(pg.locator("#ds-bandeja .ds-item.ds-descartado").count() == 1, f"{d}: la pestaña Descartados lo muestra")
        pg.locator("#ds-bandeja [data-estado=bandeja]").click(); pg.wait_for_function("document.querySelector('#ds-carrito-n').textContent === '2'", timeout=8000)
        chk(True, f"{d}: Restaurar lo devuelve a curaduría")
        pg.keyboard.press("Escape"); pg.wait_for_timeout(300)
        chk(not pg.locator("#ds-cajon").is_visible() and pg.evaluate("document.activeElement.id") == "ds-carrito", f"{d}: Escape cierra y devuelve el foco al carrito")
        # Abrir por id sin palabra: solo la ficha
        pg.fill("#ds-buscar", ""); pg.fill("#ds-producto-id", "101"); pg.click("#ds-consultar")
        pg.wait_for_function("document.querySelector('#ds-meta-resultados').textContent.includes('Ficha por id')", timeout=15000); pg.wait_for_timeout(500)
        chk(pg.locator("#ds-resultados .ds-card").count() == 1 and "Ficha abierta por id" in (pg.text_content("#ds-resultados h3") or ""), f"{d}: abrir por id muestra solo esa ficha")
        chk(fotos_cargadas(pg) == 1, f"{d}: la ficha por id también trae su foto")
        chk(not desborde(pg), f"{d}: sin desborde horizontal")
        chk(not err, f"{d}: sin errores de consola {err[:2]}")
        c.close()
    b.close()

S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
f = sum(1 for ok, _ in res if not ok)
print(f"RESUMEN | {len(res)} comprobaciones · {f} fallan")
sys.exit(1 if f else 0)
