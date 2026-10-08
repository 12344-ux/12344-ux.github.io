# EM6 de punta a punta en Chromium: tienda local -> em-suscripcion real -> base local -> correo simulado -> enlace -> confirmar.
import functools, http.server, threading, json, subprocess, re, urllib.request
from playwright.sync_api import sync_playwright

H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/magandhi")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8768), H); threading.Thread(target=S.serve_forever, daemon=True).start()
B = "http://127.0.0.1:8768/"
FN = "https://bxlzipwxyxdtffnuizbz.supabase.co/functions/v1/em-suscripcion"
res = []
chk = lambda ok, q: res.append((bool(ok), q))
def sql(q): return subprocess.run(["psql", "-tAqc", q, "-d", "impulse_pruebas"], capture_output=True, text=True, env={"PGHOST": "/var/lib/pgdata", "PGUSER": "postgres", "PATH": "/usr/bin"}).stdout.strip()
def correos(): return json.load(urllib.request.urlopen("http://localhost:54322/__correos"))

def puente(route):
    # La llamada del navegador a Supabase se reenvia a la funcion REAL local.
    req = route.request
    if req.method == "OPTIONS":
        return route.fulfill(status=204, headers={"access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, OPTIONS"})
    r = urllib.request.Request("http://localhost:8000", data=req.post_data_buffer, method="POST",
                               headers={"content-type": "application/json", "origin": "https://magandhi.com", "x-forwarded-for": "181.1.1.1"})
    try:
        resp = urllib.request.urlopen(r); st, body = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        st, body = e.code, e.read()
    route.fulfill(status=st, body=body, headers={"content-type": "application/json", "access-control-allow-origin": "*"})

def pagina(b, ancho):
    pg = b.new_page(viewport={"width": ancho, "height": 900}); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.route(FN, puente)
    pg.route("https://bxlzipwxyxdtffnuizbz.supabase.co/rest/**", lambda r: r.fulfill(json=[]))
    pg.route("https://bxlzipwxyxdtffnuizbz.supabase.co/storage/**", lambda r: r.fulfill(status=404, body=""))
    return pg, err

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        sql("update em_config set captura_publica_activa = false where id")
        pg, err = pagina(b, ancho)
        pg.goto(B + "index.html"); pg.wait_for_timeout(2500)
        chk(pg.evaluate("document.getElementById('mg-suscripcion').hidden") and pg.locator("#mg-suscripcion form").count() == 0, f"{d}: apagada -> la tienda no muestra nada")
        pg.close()

        sql("update em_config set politica_publicada = true, politica_url = 'https://magandhi.com/politicas/datos/', politica_version = 'borrador-0', captura_publica_activa = true where id")
        pg, err = pagina(b, ancho)
        pg.goto(B + "index.html"); pg.wait_for_timeout(2500)
        sec = pg.locator("#mg-suscripcion")
        chk(sec.is_visible() and pg.locator("#mg-suscripcion form").count() == 1, f"{d}: encendida -> formulario visible")
        chk(not pg.is_checked("input[name=acepto]"), f"{d}: la casilla de autorización arranca DESMARCADA")
        chk(pg.locator("input[name=tema]:checked").count() == 2, f"{d}: temas elegibles (Novedades y Ofertas)")
        chk(pg.get_attribute(".su-acepto a", "href") == "https://magandhi.com/politicas/datos/" and "Autorizo" in pg.text_content(".su-acepto"), f"{d}: texto de autorización del servidor + enlace a la política")
        bb = pg.locator("input[name=sitio_web]").bounding_box()
        chk(bb is None or bb["x"] + bb["width"] < 0, f"{d}: el campo trampa queda fuera de la pantalla")
        sec.screenshot(path="/projects/sandbox/pruebas-em5/su-" + ("movil" if ancho == 390 else "pc") + ".png")
        correo = f"cliente-{d.lower()}@z.invalid"
        pg.fill("input[name=correo]", correo); pg.fill("input[name=nombre]", "Lu")
        antes = len(correos())
        pg.click(".su-btn"); pg.wait_for_timeout(600)
        chk("casilla" in pg.text_content(".su-msg") and len(correos()) == antes, f"{d}: sin marcar la casilla no se envía nada")
        pg.check("input[name=acepto]"); pg.click(".su-btn"); pg.wait_for_timeout(2500)
        chk(pg.locator(".su-ok").count() == 1 and "te llegará un enlace" in pg.text_content(".su-ok"), f"{d}: mensaje de éxito neutro")
        cs = correos(); c = cs[-1] if cs else {}
        chk(len(cs) == antes + 1 and c.get("to") == [correo], f"{d}: llegó 1 correo de confirmación a esa dirección")
        chk(sql(f"select count(*) from em_contactos where correo_norm = '{correo}'") == "0", f"{d}: todavía NO es contacto")
        chk(not pg.evaluate("document.scrollingElement.scrollWidth > innerWidth + 1"), f"{d}: home sin desborde")
        chk(not err, f"{d}: home sin errores de JS {err[:1]}")
        pg.close()

        m = re.search(r'href="https://magandhi\.com(/suscripcion/confirmar/#t=[A-Za-z0-9_-]+)"', c.get("html", ""))
        pg, err = pagina(b, ancho)
        pg.goto(B.rstrip("/") + (m.group(1) if m else "/suscripcion/confirmar/#t=x")); pg.wait_for_timeout(2500)
        chk("Suscripción confirmada" in pg.text_content("h1"), f"{d}: el enlace del correo confirma")
        chk("#t=" not in pg.url, f"{d}: el token se borra de la barra de direcciones")
        chk(pg.evaluate("document.querySelector('meta[name=referrer]').content") == "no-referrer", f"{d}: no-referrer en la página de confirmación")
        chk(sql(f"select estado || '|' || fuente || '|' || politica_version from em_contactos where correo_norm = '{correo}'") == "suscrito|formulario_tienda|borrador-0", f"{d}: contacto suscrito, fuente formulario, versión borrador-0")
        pg.goto("about:blank"); pg.goto(B.rstrip("/") + (m.group(1) if m else "/x")); pg.wait_for_timeout(2000)
        chk("Ya estaba confirmada" in pg.text_content("h1"), f"{d}: abrirlo otra vez -> ya estaba confirmada")
        pg.goto("about:blank"); pg.goto(B + "suscripcion/confirmar/#t=" + "Z" * 43); pg.wait_for_timeout(2000)
        chk("Enlace no válido" in pg.text_content("h1"), f"{d}: token inventado -> enlace no válido")
        pg.goto("about:blank"); pg.goto(B + "suscripcion/confirmar/"); pg.wait_for_timeout(800)
        chk("Enlace no válido" in pg.text_content("h1"), f"{d}: sin token -> enlace no válido")
        chk(not pg.evaluate("document.scrollingElement.scrollWidth > innerWidth + 1") and not err, f"{d}: confirmación sin desborde ni errores {err[:1]}")
        pg.close()

        pg, err = pagina(b, ancho)
        pg.goto(B + "producto/?slug=x"); pg.wait_for_timeout(1500)
        chk(not err, f"{d}: la página de producto sigue sin errores {err[:1]}")
        pg.close()
    b.close()
S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
