import functools, http.server, threading
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/magandhi")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8767), H); threading.Thread(target=S.serve_forever, daemon=True).start()
res=[]; chk=lambda ok,q: res.append((bool(ok),q))
B="http://127.0.0.1:8767/"
with sync_playwright() as p:
    b=p.chromium.launch()
    for w,d in ((1280,"PC"),(390,"celular")):
        pg=b.new_page(viewport={"width":w,"height":900}); err=[]; malos=[]
        pg.on("pageerror", lambda e: err.append(str(e)))
        pg.on("response", lambda r: malos.append(r.url) if r.status>=400 and "127.0.0.1" in r.url else None)
        for ruta in ["politicas/","politicas/datos/","politicas/cookies/","politicas/terminos/","politicas/envios/","politicas/devoluciones/"]:
            pg.goto(B+ruta); pg.wait_for_timeout(300)
            chk(pg.evaluate("document.querySelector('meta[name=robots]').content")=="noindex, nofollow", f"{d} {ruta}: noindex")
            chk(pg.evaluate("document.scrollingElement.scrollWidth <= innerWidth+1"), f"{d} {ruta}: sin desborde")
            chk(pg.locator(".pol-nav a").count()==6 and pg.locator(".pol-nav a[aria-current=page]").count()==1, f"{d} {ruta}: menú con página actual")
            links=pg.evaluate("[...document.querySelectorAll('a[href]')].map(a=>a.href).filter(h=>h.startsWith('http://127.0.0.1'))")
            for l in set(links):
                r=pg.request.get(l); chk(r.status==200, f"{d} {ruta}: enlace {l.replace(B,'')} responde")
        pg.goto(B+"politicas/datos/"); chk(pg.locator("section#responsable").count()==1 and pg.locator("section#cookies a[href='../cookies/']").count()==1, f"{d}: anclas estables (#responsable, #cookies)")
        pg.goto(B+"index.html"); pg.wait_for_timeout(500); chk(pg.locator("footer a[href='politicas/']").count()==1, f"{d}: footer del home enlaza Políticas")
        pg.goto(B+"producto/?slug=x"); pg.wait_for_timeout(500); chk(pg.locator("footer a[href='../politicas/']").count()==1, f"{d}: footer del producto enlaza Políticas")
        if w==390: pg.goto(B+"politicas/datos/"); pg.wait_for_timeout(300); pg.screenshot(path="/projects/sandbox/pruebas-em5/pol-movil.png")
        chk(not err and not malos, f"{d}: sin errores ni recursos rotos {err[:1]} {malos[:2]}")
        pg.close()
    b.close()
S.shutdown()
f=[q for o,q in res if not o]
print("\n".join("FALLA | "+q for q in f)); print("RESUMEN | %d comprobaciones · %d fallan"%(len(res),len(f)))
