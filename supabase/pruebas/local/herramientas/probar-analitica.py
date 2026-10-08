# EM7 de punta a punta en Chromium: tienda -> tienda-eventos REAL -> base local.
import functools, http.server, threading, json, subprocess, urllib.request
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/magandhi")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8769), H); threading.Thread(target=S.serve_forever, daemon=True).start()
B = "http://127.0.0.1:8769/"
SBU = "https://bxlzipwxyxdtffnuizbz.supabase.co"
res = []; chk = lambda ok, q: res.append((bool(ok), q))
def sql(q): return subprocess.run(["psql", "-tAqc", q, "-d", "impulse_pruebas"], capture_output=True, text=True, env={"PGHOST": "/var/lib/pgdata", "PGUSER": "postgres", "PATH": "/usr/bin"}).stdout.strip()

registros = []
def puente(route):
    req = route.request
    if req.method == "OPTIONS":
        return route.fulfill(status=204, headers={"access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, OPTIONS"})
    body = req.post_data or ""
    if '"registrar"' in body: registros.append(json.loads(body))
    r = urllib.request.Request("http://localhost:8000", data=body.encode(), method="POST",
        headers={"content-type": "application/json", "origin": "https://magandhi.com", "x-forwarded-for": "181.2.2.2", "user-agent": "Mozilla/5.0 Chrome"})
    try: resp = urllib.request.urlopen(r); st, b = resp.status, resp.read()
    except urllib.error.HTTPError as e: st, b = e.code, e.read()
    route.fulfill(status=st, body=b, headers={"content-type": "application/json", "access-control-allow-origin": "*"})

def ctx_nuevo(b, ancho):
    c = b.new_context(viewport={"width": ancho, "height": 860})
    c.route(SBU + "/functions/v1/tienda-eventos", puente)
    c.route(SBU + "/functions/v1/em-suscripcion", lambda r: r.fulfill(json={"activa": False}))
    c.route(SBU + "/rest/**", lambda r: r.fulfill(json=[]))
    c.route(SBU + "/storage/**", lambda r: r.fulfill(status=404, body=""))
    return c

def n_ev(where=""): return int(sql("select count(*) from tienda_eventos" + (" where " + where if where else "")) or 0)

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        sql("delete from tienda_eventos; delete from tienda_eventos_limite;")
        sql("update em_config set politica_publicada = true, politica_version = 'borrador-0', analitica_activa = false where id")
        c = ctx_nuevo(b, ancho); pg = c.new_page(); err = []; pg.on("pageerror", lambda e: err.append(str(e)))
        pg.goto(B + "index.html"); pg.wait_for_timeout(2500)
        chk(pg.locator("#mg-aviso-analitica").count() == 0 and n_ev() == 0, f"{d}: apagada -> ni aviso ni eventos")
        c.close()

        sql("update em_config set analitica_activa = true where id")
        registros.clear()
        c = ctx_nuevo(b, ancho); pg = c.new_page(); err = []; pg.on("pageerror", lambda e: err.append(str(e)))
        pg.goto(B + "index.html"); pg.wait_for_timeout(2500)
        chk(pg.locator("#mg-aviso-analitica").is_visible(), f"{d}: encendida -> aparece el aviso")
        chk(n_ev() == 0 and not registros, f"{d}: antes de decidir NO se envía nada")
        bs = [pg.locator(".an-no").bounding_box(), pg.locator(".an-si").bounding_box()]
        chk(abs(bs[0]["width"] - bs[1]["width"]) < 2 and abs(bs[0]["height"] - bs[1]["height"]) < 2, f"{d}: Rechazar y Aceptar del mismo tamaño (igual de fácil)")
        chk(pg.get_attribute(".an-txt a", "href").endswith("/politicas/cookies/"), f"{d}: enlace a la política de cookies")
        chk(not pg.evaluate("document.scrollingElement.scrollWidth > innerWidth + 1"), f"{d}: aviso sin desborde")
        if ancho == 390: pg.locator("#mg-aviso-analitica").screenshot(path="/projects/sandbox/pruebas-em5/aviso-movil.png")
        pg.click(".an-no"); pg.wait_for_timeout(800)
        chk(pg.locator("#mg-aviso-analitica").count() == 0, f"{d}: Rechazar cierra el aviso")
        pg.reload(); pg.wait_for_timeout(2000)
        chk(pg.locator("#mg-aviso-analitica").count() == 0 and n_ev() == 0 and not registros, f"{d}: tras rechazar: no vuelve a preguntar y no se envía nada")
        chk(pg.evaluate("localStorage.getItem('mg_vid')") is None, f"{d}: tras rechazar no queda identificador")
        pg.evaluate("window.mgCookies()"); pg.wait_for_timeout(800)
        chk(pg.locator("#mg-aviso-analitica").is_visible(), f"{d}: 'Preferencias de cookies' reabre el aviso")
        pg.click(".an-si"); pg.wait_for_timeout(2500)
        chk(n_ev("tipo = 'pagina_vista'") == 1, f"{d}: cambiar a Aceptar empieza a medir (1 página vista)")
        c.close()

        sql("delete from tienda_eventos;"); registros.clear()
        c = ctx_nuevo(b, ancho); pg = c.new_page(); err = []; pg.on("pageerror", lambda e: err.append(str(e)))
        pg.goto(B + "index.html?utm_source=email&utm_medium=email&utm_campaign=c1-test"); pg.wait_for_timeout(2000)
        pg.click(".an-si"); pg.wait_for_timeout(2500)
        fila = sql("select origen || '|' || entrada || '|' || coalesce(utm_campaign,'') || '|' || dispositivo from tienda_eventos where tipo = 'pagina_vista'")
        esp_disp = "movil" if ancho == 390 else "pc"
        chk(fila == f"email|true|c1-test|{esp_disp}", f"{d}: llegada desde un correo: origen email, entrada, campaña y dispositivo ({fila})")
        chk(n_ev("tipo = 'llegada_campana' and utm_campaign = 'c1-test'") == 1, f"{d}: evento llegada_campana")
        pg.goto(B + "producto/?slug=grisi-gold"); pg.wait_for_timeout(2500)
        chk(n_ev("tipo = 'producto_visto' and slug = 'grisi-gold'") == 1, f"{d}: producto visto con su slug")
        chk(sql("select origen is null and not entrada from tienda_eventos where tipo = 'pagina_vista' and ruta = '/producto/'") == "t", f"{d}: navegación interna no cuenta como nueva entrada")
        pg.evaluate("window.mgEvento('clic_comprar', {slug: 'grisi-gold'})"); pg.wait_for_timeout(2500)
        chk(n_ev("tipo = 'clic_comprar'") == 1, f"{d}: clic en Comprar registrado")
        hook = pg.evaluate("(() => { const b = document.getElementById('mg-comprar'); if (!b) return 'sin-boton'; b.disabled = false; b.click(); return 'ok' })()")
        pg.wait_for_timeout(2500)
        chk(hook == "ok" and n_ev("tipo = 'clic_comprar'") == 2, f"{d}: el botón real 'Comprar ahora' dispara el evento ({hook})")
        chk(sql("select count(distinct visitante) from tienda_eventos") == "1" and sql("select count(distinct sesion) from tienda_eventos") == "1", f"{d}: un visitante y una sesión en toda la visita")
        envio = json.dumps(registros)
        chk("referrer" not in envio and "127.0.0.1" not in envio and "http" not in envio, f"{d}: lo enviado no incluye URLs de procedencia ni el host")
        chk(not err, f"{d}: sin errores de JS {err[:1]}")
        c.close()
    b.close()
S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
