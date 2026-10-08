# Aviso de pagos sin pedido (Wompi F2) en la portada de Ventas, con las RPC REALES
# (simulador -> Postgres local). PC 1280 y celular 390.
import functools, http.server, threading, json, time, base64, urllib.request, subprocess, sys
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8772), H); threading.Thread(target=S.serve_forever, daemon=True).start()
B = "http://127.0.0.1:8772/ventas/"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPTURAS = "--capturas" in sys.argv
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp,
       "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []; chk = lambda ok, q: res.append((bool(ok), q))
def sql(q):
    return subprocess.run(["psql", "-tAqc", q, "-d", "impulse_pruebas"], capture_output=True, text=True,
                          env={"PGHOST": "/var/lib/pgdata", "PGUSER": "postgres", "PATH": "/usr/bin"}).stdout.strip()

def man(route, rol):
    u = route.request.url
    if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": rol, "modulos": ["ventas"]})
    if "/rest/v1/rpc/" in u:
        name = u.split("/rest/v1/rpc/")[1].split("?")[0]
        r = urllib.request.Request("http://localhost:54321/rest/v1/rpc/" + name,
                                   data=route.request.post_data_buffer or b"{}", method="POST",
                                   headers={"content-type": "application/json"})
        try: resp = urllib.request.urlopen(r); st, body = resp.status, resp.read()
        except urllib.error.HTTPError as e: st, body = e.code, e.read()
        return route.fulfill(status=st, body=body, headers={"content-type": "application/json"})
    if "/auth/v1/" in u: return route.fulfill(json=SES["user"])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho, rol="admin"):
    c = b.new_context(viewport={"width": ancho, "height": 900})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}" % json.dumps(json.dumps(SES)))
    pg = c.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    pg.route(SB + "/**", lambda r: man(r, rol))
    pg.goto(B + "index.html"); pg.wait_for_timeout(2600)
    return c, pg, err

desb = lambda pg: pg.evaluate("""document.scrollingElement.scrollWidth > innerWidth + 1 ||
  [...document.querySelectorAll('.vt-rev-btn, .vt-rev-monto, .vt-rev-tit, .vt-rev-nota')].some(e => {
    const r = e.getBoundingClientRect(), c = e.closest('.vt-rev-item, .vt-revisiones');
    if (!c || !r.width) return false; const q = c.getBoundingClientRect();
    return r.right > q.right + 1 || r.left < q.left - 1; })""")

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        # --- Con 2 pagos pendientes ---
        c, pg, err = abrir(b, ancho)
        chk(pg.locator(".vt-revisiones").count() == 1, f"{d}: el aviso aparece cuando hay pagos sin pedido")
        chk("2 pagos recibidos sin pedido" in pg.text_content(".vt-rev-tit"), f"{d}: el título dice cuántos son")
        chk(pg.locator(".vt-rev-item").count() == 2, f"{d}: una tarjeta por pago")
        txt = pg.text_content(".vt-revisiones")
        chk("ya no había unidades disponibles" in txt, f"{d}: el motivo de stock se explica en lenguaje claro")
        chk("no coincide con el que se firmó" in txt, f"{d}: el motivo de monto se explica en lenguaje claro")
        chk("Eva Sin Stock" in txt and "3009998877" in txt, f"{d}: trae los datos de contacto para resolver")
        chk("$30.000" in txt, f"{d}: muestra el monto en pesos (no en centavos)")
        chk(pg.locator(".vt-rev-nota").count() == 2 and pg.locator(".vt-rev-btn").count() == 2,
            f"{d}: cada pago tiene su nota y su botón")
        chk(pg.locator(".vt-cards .vt-card").count() >= 2, f"{d}: el aviso no estorba las sub-áreas del área")
        chk(not desb(pg) and not err, f"{d}: sin desborde ni errores {err[:1]}")
        if CAPTURAS and ancho == 1280:
            pg.screenshot(path="/projects/sandbox/pruebas-em5/vt-revisiones-pc.png", clip={"x": 0, "y": 0, "width": 1280, "height": 900})
        if CAPTURAS and ancho == 390:
            pg.screenshot(path="/projects/sandbox/pruebas-em5/vt-revisiones-movil.png", clip={"x": 0, "y": 0, "width": 390, "height": 900})

        # --- No se puede cerrar sin nota ---
        pg.locator(".vt-rev-btn").first.click(); pg.wait_for_timeout(600)
        chk("Escribe qué hiciste" in pg.text_content(".vt-rev-msg"), f"{d}: no deja cerrar sin decir qué se hizo")
        chk(sql("select count(*) from pagos_intencion where resuelta_en is not null") == "0",
            f"{d}: nada se marcó resuelto sin nota")

        # --- Resolver con nota ---
        ref = pg.locator(".vt-rev-item").first.get_attribute("data-ref")
        pg.locator(".vt-rev-nota").first.fill("Devolví el dinero por Nequi")
        pg.locator(".vt-rev-btn").first.click(); pg.wait_for_timeout(1800)
        chk(sql(f"select resuelta_nota from pagos_intencion where referencia = '{ref}'") == "Devolví el dinero por Nequi",
            f"{d}: la nota queda guardada en la base")
        chk(sql(f"select resuelta_por is not null from pagos_intencion where referencia = '{ref}'") == "t",
            f"{d}: queda constancia de quién lo resolvió")
        chk(pg.locator(".vt-rev-item").count() == 1, f"{d}: el pago resuelto sale del aviso")
        chk("1 pago recibido sin pedido" in pg.text_content(".vt-rev-tit"), f"{d}: el título queda en singular")
        c.close()

        # --- Resolver el ultimo: el aviso desaparece del todo ---
        c, pg, err = abrir(b, ancho)
        pg.locator(".vt-rev-nota").first.fill("Repuse el producto y lo entregué")
        pg.locator(".vt-rev-btn").first.click(); pg.wait_for_timeout(1800)
        chk(pg.locator(".vt-revisiones").count() == 0, f"{d}: sin pendientes, el aviso NO se pinta")
        chk(pg.locator(".vt-cards .vt-card").count() >= 2, f"{d}: el área sigue funcionando sin el aviso")
        c.close()

        # --- Volver a dejar 2 pendientes para la siguiente vuelta (celular) ---
        sql("update pagos_intencion set resuelta_en = null, resuelta_por = null, resuelta_nota = null where estado = 'requiere_revision'")
    b.close()
S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
