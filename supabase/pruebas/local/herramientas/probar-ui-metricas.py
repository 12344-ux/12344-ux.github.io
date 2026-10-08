# Metricas en Chromium con las RPC REALES (simulador -> Postgres local con semilla).
import functools, http.server, threading, json, time, base64, urllib.request, subprocess, sys
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8770), H); threading.Thread(target=S.serve_forever, daemon=True).start()
B = "http://127.0.0.1:8770/metricas/"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPTURAS = "--capturas" in sys.argv
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp, "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []; chk = lambda ok, q: res.append((bool(ok), q))
def sql(q): return subprocess.run(["psql", "-tAqc", q, "-d", "impulse_pruebas"], capture_output=True, text=True, env={"PGHOST": "/var/lib/pgdata", "PGUSER": "postgres", "PATH": "/usr/bin"}).stdout.strip()
llamadas = []
def man(route, rol):
    u = route.request.url
    if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": rol, "modulos": ["metricas"]})
    if "/rest/v1/rpc/" in u:
        name = u.split("/rest/v1/rpc/")[1].split("?")[0]; llamadas.append(name)
        r = urllib.request.Request("http://localhost:54321/rest/v1/rpc/" + name, data=route.request.post_data_buffer or b"{}", method="POST", headers={"content-type": "application/json"})
        try: resp = urllib.request.urlopen(r); st, body = resp.status, resp.read()
        except urllib.error.HTTPError as e: st, body = e.code, e.read()
        return route.fulfill(status=st, body=body, headers={"content-type": "application/json"})
    if "/auth/v1/" in u: return route.fulfill(json=SES["user"])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho, pagina, rol="admin"):
    c = b.new_context(viewport={"width": ancho, "height": 900})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}" % json.dumps(json.dumps(SES)))
    pg = c.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    pg.on("dialog", lambda d: d.accept())
    pg.route(SB + "/**", lambda r: man(r, rol))
    pg.goto(B + pagina); pg.wait_for_timeout(2600)
    return c, pg, err
desb = lambda pg: pg.evaluate("""document.scrollingElement.scrollWidth > innerWidth + 1 ||
  [...document.querySelectorAll('.mt-chip, .mt-kpi-v, .mt-card-tit')].some(e => { const r = e.getBoundingClientRect(), c = e.closest('.mt-card, .mt-kpi, .mt-chips, .mt-barra'); if (!c || !r.width) return false; const q = c.getBoundingClientRect(); return r.right > q.right + 1 || r.left < q.left - 1; })""")
def hover_tip(pg, sel):
    pg.locator(sel).first.scroll_into_view_if_needed(); pg.wait_for_timeout(150)
    box = pg.locator(sel).first.bounding_box()
    if not box: return False
    pg.mouse.move(box["x"] + box["width"] * 0.7, box["y"] + box["height"] * 0.5); pg.wait_for_timeout(250)
    return pg.locator(sel + " .mt-tip.visible").count() > 0 or pg.locator(".mt-tip.visible").count() > 0

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        sql("update em_config set analitica_activa = true where id")
        # ---------- En vivo ----------
        c, pg, err = abrir(b, ancho, "index.html")
        chk(pg.locator("#vv-kpis .mt-kpi").count() == 5 and pg.locator("#vv-kpis .mt-kpi.destacado").count() == 1, f"{d} vivo: 5 indicadores, uno destacado")
        chk(int(pg.text_content("#vv-kpis .mt-kpi.destacado .mt-kpi-v")) >= 4, f"{d} vivo: visitantes ahora con datos reales")
        chk(pg.locator("#vv-horas svg .barra").count() == 24 and pg.locator("#vv-horas .barra.ahora").count() == 1, f"{d} vivo: 24 horas con la actual resaltada")
        chk(pg.locator(".mt-tab[aria-current=page]").text_content().strip() == "En vivo", f"{d} vivo: pestaña activa")
        chk(pg.locator("#vv-actividad li").count() >= 5 and "Tocó «Comprar»" in pg.text_content("#vv-actividad"), f"{d} vivo: actividad reciente legible")
        chk(pg.locator("#vv-pedidos tbody tr").count() == 8, f"{d} vivo: últimos 8 pedidos")
        chk("En vivo" in pg.text_content("#vv-estado") and "actualizado" in pg.text_content("#vv-estado"), f"{d} vivo: indicador en vivo con hora de actualización")
        chk(pg.locator("#vv-aviso .mt-aviso").count() == 0, f"{d} vivo: sin aviso con la analítica encendida")
        pg.locator("#vv-horas").scroll_into_view_if_needed()
        b0 = pg.locator("#vv-horas .col").nth(20).bounding_box()
        pg.mouse.move(b0["x"] + b0["width"] / 2, b0["y"] + 10); pg.wait_for_timeout(250)
        chk(pg.locator("#vv-horas .mt-tip.visible").count() == 1, f"{d} vivo: lectura exacta al pasar sobre una barra")
        pg.click("[data-serie=pedidos]"); pg.wait_for_timeout(300)
        chk("Pedidos registrados" in pg.text_content("#vv-hoy-sub"), f"{d} vivo: cambiar a pedidos")
        chk(not desb(pg) and not err, f"{d} vivo: sin desborde ni errores {err[:1]}")
        if CAPTURAS and ancho == 1280: pg.screenshot(path="/projects/sandbox/pruebas-em5/mt-vivo-pc.png", clip={"x": 0, "y": 0, "width": 1280, "height": 1150})
        if CAPTURAS and ancho == 390: pg.screenshot(path="/projects/sandbox/pruebas-em5/mt-vivo-movil.png", clip={"x": 0, "y": 0, "width": 390, "height": 1180})
        c.close()

        # ---------- Ventas ----------
        llamadas.clear()
        c, pg, err = abrir(b, ancho, "ventas.html")
        chk(pg.locator("#vt-kpis .mt-kpi").count() == 5 and pg.locator("#vt-kpis .mt-delta").count() >= 4, f"{d} ventas: 5 indicadores con variación")
        chk(pg.locator("#vt-kpis .mt-kpi-spark svg").count() == 2, f"{d} ventas: minigráficas en ingresos y pedidos")
        chk(pg.locator("#vt-serie path.linea").count() == 2 and pg.locator("#vt-serie path.linea.comp").count() == 1, f"{d} ventas: serie con periodo anterior")
        chk(hover_tip(pg, "#vt-serie"), f"{d} ventas: lectura al pasar el cursor")
        chk(pg.locator("#vt-productos .mt-fila").count() >= 3 and pg.locator("#vt-ciudades .mt-fila").count() >= 3, f"{d} ventas: productos y ciudades")
        chk(pg.locator("#vt-calor .c").count() == 168, f"{d} ventas: mapa de calor 7×24")
        chk(pg.locator("#vt-canal .mt-reparto span").count() == 2, f"{d} ventas: reparto por canal")
        pg.click("[data-periodo='90']"); pg.wait_for_timeout(1800)
        chk("periodo=90" in pg.url and llamadas.count("mt_ventas") == 2, f"{d} ventas: cambiar a 90 días vuelve a consultar")
        pg.click("#mt-main [data-serie=pedidos]"); pg.wait_for_timeout(300)
        chk(pg.text_content("#vt-serie-tit") == "Pedidos por día" and pg.locator("#vt-serie path.linea.comp").count() == 0, f"{d} ventas: vista de pedidos")
        chk(not desb(pg) and not err, f"{d} ventas: sin desborde ni errores {err[:1]}")
        if CAPTURAS and ancho == 1280:
            pg.click("[data-periodo='30']"); pg.wait_for_timeout(1500); pg.click("#mt-main [data-serie=ingresos]"); pg.wait_for_timeout(300)
            pg.screenshot(path="/projects/sandbox/pruebas-em5/mt-ventas-pc.png", clip={"x": 0, "y": 0, "width": 1280, "height": 1200})
        c.close()

        # ---------- Tienda ----------
        c, pg, err = abrir(b, ancho, "tienda.html")
        chk(pg.locator("#tn-kpis .mt-kpi").count() == 5, f"{d} tienda: 5 indicadores")
        chk(pg.locator("#tn-serie path.linea").count() == 2, f"{d} tienda: visitantes y páginas por día")
        chk(pg.locator("#tn-embudo .mt-paso").count() == 5 and pg.locator("#tn-embudo .mt-conv").count() == 4, f"{d} tienda: embudo de 5 pasos con conversión entre pasos")
        chk(pg.locator("#tn-productos .mt-fila").count() == 5 and "Shampoo Grisi Gold" in pg.text_content("#tn-productos"), f"{d} tienda: productos más vistos por nombre")
        chk(pg.locator("#tn-origenes .mt-reparto span").count() >= 5, f"{d} tienda: orígenes")
        chk(pg.locator("#tn-disp .mt-reparto span").count() == 3, f"{d} tienda: dispositivos")
        chk(pg.locator("#tn-calor .c").count() == 168, f"{d} tienda: cuándo navegan")
        chk(pg.locator("#an-interruptor").count() == 1 and pg.is_checked("#an-interruptor"), f"{d} tienda: interruptor de analítica (admin)")
        chk(not desb(pg) and not err, f"{d} tienda: sin desborde ni errores {err[:1]}")
        if CAPTURAS and ancho == 1280: pg.screenshot(path="/projects/sandbox/pruebas-em5/mt-tienda-pc.png", clip={"x": 0, "y": 0, "width": 1280, "height": 1200})
        c.close()

        # ---------- Analítica apagada ----------
        sql("update em_config set analitica_activa = false where id")
        c, pg, err = abrir(b, ancho, "tienda.html")
        chk(pg.locator("#an-aviso").count() == 1 and pg.locator("#an-encender").count() == 1, f"{d} tienda apagada: aviso con botón para encender (admin)")
        pg.click("#an-encender"); pg.wait_for_timeout(1800)
        chk(sql("select analitica_activa from em_config where id") == "t" and pg.locator("#an-aviso").count() == 0, f"{d} tienda: encender desde el panel funciona y el aviso desaparece")
        c.close()
        sql("update em_config set analitica_activa = false where id")
        c, pg, err = abrir(b, ancho, "index.html", rol="prueba")
        chk(pg.locator("#an-aviso").count() == 1 and pg.locator("#an-encender").count() == 0, f"{d} vivo apagado: quien no es admin ve el aviso sin el botón")
        c.close()
    b.close()
S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
