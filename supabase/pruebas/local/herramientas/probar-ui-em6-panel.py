# Panel EM6: tarjeta "Formulario de la tienda" + aviso de politica borrador.
exec(open('/projects/sandbox/pruebas-em5/probar-ui.py').read().split("import functools, http.server, threading")[0])
import functools, http.server, threading
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
SERVIDOR = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), H)
threading.Thread(target=SERVIDOR.serve_forever, daemon=True).start()

llamadas = []
def abrir3(b, ancho, cap, version="borrador-0", publicada=True, admin=True):
    ctx = b.new_context(viewport={"width": ancho, "height": 900})
    ctx.add_init_script("try { if (window === window.top) localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s) } catch (e) {}" % json.dumps(json.dumps(SESION)))
    pg = ctx.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    f = fixtures("lleno")
    f["rpc/em_resumen"]["config"] = {"politica_publicada": publicada, "politica_version": version, "politica_url": "https://magandhi.com/politicas/datos/"}
    f["rpc/em_captura_estado"] = cap
    def man(route):
        u = route.request.url
        if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": "admin" if admin else "prueba", "modulos": ["email_marketing"]})
        if "/rest/v1/rpc/em_config_captura" in u:
            llamadas.append(route.request.post_data); return route.fulfill(json={"captura_publica_activa": True})
        if cap is None and "/rest/v1/rpc/em_captura_estado" in u:
            return route.fulfill(status=404, json={"code": "PGRST202", "message": "Could not find the function public.em_captura_estado"})
        return manejar(route, f, "lleno")
    pg.route(SB + "/**", man)
    pg.on("dialog", lambda d: d.accept())
    pg.goto(BASE + "index.html"); pg.wait_for_timeout(2500)
    return ctx, pg, err

CAP_OFF = {"activa": False, "politica_publicada": True, "politica_version": "borrador-0", "politica_borrador": True, "pendientes": 0, "confirmadas_30d": 0, "solicitudes_30d": 0, "contactos_borrador": 0}
CAP_ON = dict(CAP_OFF, activa=True, pendientes=2, confirmadas_30d=5, solicitudes_30d=8, contactos_borrador=5)

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        ctx, pg, err = abrir3(b, ancho, CAP_OFF)
        t = pg.text_content("#em-contenido")
        chk("Formulario de la tienda" in t and "Apagado" in t, f"{d}: tarjeta del formulario: apagado")
        chk(pg.locator("#cap-btn").count() == 1 and not pg.is_disabled("#cap-btn"), f"{d}: admin puede encenderlo (política registrada)")
        chk("versión borrador" in pg.text_content("#em-aviso") and "nunca recibirá una campaña real" in pg.text_content("#em-aviso"), f"{d}: aviso de política borrador explica la regla")
        n0 = len(llamadas); pg.click("#cap-btn"); pg.wait_for_timeout(1500)
        chk(len(llamadas) == n0 + 1 and '"p_activa":true' in (llamadas[-1] or "").replace(" ", ""), f"{d}: encender llama al servidor con p_activa=true")
        chk(not desborde(pg) and not err, f"{d}: sin desborde ni errores {err[:1]}")
        ctx.close()

        ctx, pg, err = abrir3(b, ancho, CAP_ON)
        t = pg.text_content("#em-contenido")
        chk("Encendido" in t and "Apagar el formulario" in t and "8" in t and "5 contactos entraron con una versión borrador" in t, f"{d}: encendido con sus números y el aviso de borrador")
        ctx.close()

        ctx, pg, err = abrir3(b, ancho, dict(CAP_OFF, politica_publicada=False), version="pendiente", publicada=False)
        chk(pg.is_disabled("#cap-btn") and "primero registra la política" in pg.text_content("#em-contenido"), f"{d}: sin política el botón queda deshabilitado")
        ctx.close()

        ctx, pg, err = abrir3(b, ancho, CAP_ON, admin=False)
        chk(pg.locator("#cap-btn").count() == 0 and "Encendido" in pg.text_content("#em-contenido"), f"{d}: quien no es admin ve el estado pero no el botón")
        ctx.close()

        ctx, pg, err = abrir3(b, ancho, None, version="1.0")
        chk("Formulario de la tienda" not in pg.text_content("#em-contenido") and "Personas que reciben" in pg.text_content("#em-contenido") and not err, f"{d}: sin la migración EM6 el Resumen sigue igual")
        ctx.close()
    b.close()
SERVIDOR.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
