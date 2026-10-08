# EM5.1 en Chromium: Segmentos (campos de respuesta a email) y Clúster (variables nuevas).
import json
exec(open('/projects/sandbox/pruebas-em5/probar-ui.py').read().split("import functools, http.server, threading")[0])
import functools, http.server, threading
from playwright.sync_api import sync_playwright

H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
SERVIDOR = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), H)
threading.Thread(target=SERVIDOR.serve_forever, daemon=True).start()

OPC = {"ciudades": ["Tunja"], "departamentos": ["Boyacá"], "categorias": ["Cuidado capilar"], "productos": [], "temas": [{"codigo": "novedades", "nombre": "Novedades"}],
       "campanas": [{"id": C1, "nombre": "Lanzamiento Grisi", "fecha": "2026-09-28T10:00:00Z"}]}
SEGS = [{"id": "s1", "nombre": "Interesados Grisi", "descripcion": None, "tipo": "reglas", "archivado": False, "actualizado": "2026-10-08T10:00:00Z",
         "definicion": {"modo": "y", "reglas": [{"campo": "clico_campana", "op": "incluye", "valor": C1}, {"campo": "compras_por_email", "op": "eq", "valor": "0"}]},
         "coinciden": 2, "suscritos": 2}]
PERF = []
for i in range(14):
    PERF.append({"cliente_ref": "c%02d" % i, "num_pedidos": 1 + i % 3, "unidades": 1 + i % 3, "gasto_total": 30000 + 5000 * i, "ticket_promedio": 30000,
                 "dias_desde_ultima_compra": 5 + i, "dias_entre_compras": None, "precio_min": 30000, "precio_max": 30000, "precio_prom": 30000,
                 "pct_rebajado": 0, "productos_distintos": 1, "categoria_dominante": "Cuidado capilar", "num_opiniones": 0, "estrellas_prom": None,
                 "pct_opinadas": None, "dias_entrega_opinion": None, "ciudad": "Tunja", "departamento": "Boyacá", "es_local": True, "pct_web": 0,
                 "franja_moda": "tarde", "dia_moda": "lunes", "pct_hora_exacta": 0, "suscrito": i < 10,
                 "email_campanas_recibidas": 3 if i < 7 else None, "email_pct_clic": (66.7 if i < 4 else 0) if i < 7 else None,
                 "email_clics_90d": (2 if i < 4 else 0) if i < 7 else None, "email_dias_desde_ultimo_clic": (1 + i) if i < 4 else None,
                 "email_compras_atribuidas": (1 if i < 2 else 0) if i < 7 else None})

def fx(modo):
    f = fixtures("lleno")
    f["rpc/em_segmento_opciones"] = dict(OPC, campanas=[] if modo == "sin_campanas" else OPC["campanas"])
    f["rpc/em_segmentos_lista"] = SEGS
    f["rpc/em_segmento_previa"] = {"coinciden": 2, "suscritos": 2, "clientes": 2, "por_estado": {"suscrito": 2}, "total_suscritos": 5, "muestra": []}
    f["rpc/mk_perfiles_clientes"] = PERF
    return f

def abrir2(b, ancho, ruta, modo="lleno"):
    ctx = b.new_context(viewport={"width": ancho, "height": 900})
    ctx.add_init_script("try { if (window === window.top) localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s) } catch (e) {}" % json.dumps(json.dumps(SESION)))
    pg = ctx.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "404" not in m.text and "Failed to load resource" not in m.text else None)
    f = fx(modo)
    pg.route(SB + "/**", lambda r: manejar(r, f, "lleno"))
    pg.goto("http://localhost:8765/marketing/" + ruta); pg.wait_for_timeout(2500)
    return ctx, pg, err

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, disp in ((1280, "PC"), (390, "celular")):
        # Lista de segmentos: la condicion nueva en palabras
        ctx, pg, err = abrir2(b, ancho, "email-marketing/segmentos.html")
        t = pg.text_content("#lista")
        chk("Hizo clic en Lanzamiento Grisi" in t and "Compras atribuidas a correos igual a 0" in t, f"{disp}: tarjeta describe las condiciones de email en palabras")
        chk(not desborde(pg) and not err, f"{disp}: lista sin desborde ni errores {err[:2]}")
        ctx.close()

        # Editor: grupo nuevo, opciones de campana, ideas
        ctx, pg, err = abrir2(b, ancho, "email-marketing/segmentos.html?nuevo=1")
        grupo = pg.evaluate("[...document.querySelectorAll('.sg-campo optgroup')].find(g => g.label === 'Respuesta a email')?.children.length || 0")
        chk(grupo == 9, f"{disp}: grupo 'Respuesta a email' con 9 datos ({grupo})")
        chk(pg.evaluate("![...document.querySelectorAll('.sg-campo option')].some(o => /abri|apertura/i.test(o.textContent))"), f"{disp}: no se ofrece segmentar por aperturas")
        pg.select_option(".sg-campo", "clico_campana"); pg.wait_for_timeout(300)
        ops = pg.evaluate("[...document.querySelectorAll('.sg-op option')].map(o => o.textContent)")
        vals = pg.evaluate("[...document.querySelectorAll('.sg-valor select option')].map(o => o.textContent)")
        chk(ops == ["hizo clic en", "no hizo clic en"], f"{disp}: operadores en palabras {ops}")
        chk(any(v.startswith("Lanzamiento Grisi · ") for v in vals), f"{disp}: elige la campaña por nombre y fecha {vals}")
        pg.select_option(".sg-valor select", C1); pg.wait_for_timeout(800)
        chk("2" in (pg.text_content("#ed-previa") if pg.query_selector("#ed-previa") else pg.text_content("body")), f"{disp}: vista previa en vivo responde")
        ideas = pg.evaluate("[...document.querySelectorAll('#ed-ideas [data-i]')].map(b => b.textContent)")
        chk("Hicieron clic y no compraron" in ideas and "Llevan 4 campañas sin clic" in ideas, f"{disp}: ideas nuevas disponibles")
        chk(not desborde(pg) and not err, f"{disp}: editor sin desborde ni errores {err[:2]}")
        ctx.close()

        ctx, pg, err = abrir2(b, ancho, "email-marketing/segmentos.html?nuevo=1", "sin_campanas")
        pg.select_option(".sg-campo", "recibio_campana"); pg.wait_for_timeout(300)
        chk(pg.evaluate("(() => { const s = document.querySelector('.sg-valor select'); return !!s && s.disabled && /Aún no has enviado campañas/.test(s.textContent) })()"), f"{disp}: sin campañas lo dice (no pide escribir un id)")
        ctx.close()

        # Clúster: variables nuevas con cobertura
        ctx, pg, err = abrir2(b, ancho, "marketing-project/analisis-cluster.html")
        g = pg.evaluate("""(() => { const k = [...document.querySelectorAll('.cl-grupo-k')].find(x => x.textContent === 'Respuesta a email');
             return k ? [...k.parentElement.querySelectorAll('.cl-chip')].map(c => c.textContent) : [] })()""")
        chk(len(g) == 6, f"{disp}: clúster con grupo 'Respuesta a email' (6 variables) {len(g)}")
        chk(any("% de campañas con clic" in x and "50%" in x for x in g), f"{disp}: cobertura honesta (50 % recibió campañas) {g[:3]}")
        chk(any("Días desde su último clic" in x and "29%" in x for x in g), f"{disp}: poca cobertura marcada ({[x for x in g if 'último' in x]})")
        pg.evaluate("document.querySelectorAll('input[name=\"cl-var\"]').forEach(x => x.checked = ['gasto_total','email_pct_clic','email_clics_90d'].includes(x.value))")
        pg.click("#cl-analizar"); pg.wait_for_timeout(1500)
        t = pg.text_content("#cl-res")
        chk("% de campañas con clic" in t and "grupos" in t, f"{disp}: analiza con variables de email y las muestra en el comparativo")
        chk(not desborde(pg) and not err, f"{disp}: clúster sin desborde ni errores {err[:2]}")
        ctx.close()
    b.close()
SERVIDOR.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
