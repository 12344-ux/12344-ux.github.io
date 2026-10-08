# Interfaz EM5 en Chromium headless con Supabase SIMULADO (intercepta la red).
# PC 1280 y celular 390. Comprueba DOM, textos, desbordes y errores de JS.
import json, sys, time, base64, subprocess, os
from playwright.sync_api import sync_playwright

BASE = "http://localhost:8765/marketing/email-marketing/"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
C1 = "b0000000-0000-4000-8000-000000000001"
C2 = "b0000000-0000-4000-8000-000000000002"
CT = "a0000000-0000-4000-8000-000000000001"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256", "typ": "JWT"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp, "email": "admin@local.invalid"}) + ".firma"
SESION = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp,
          "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated", "role": "authenticated", "user_metadata": {}}}

RES_C1 = {"destinatarios": 4, "enviados": 4, "entregados": 3, "retrasados": 0, "rebotes": 1, "rebotes_temporales": 0, "suprimidos": 0,
          "fallidos": 0, "quejas": 0, "aperturas": 1, "clics_personas": 2, "clics_total": 3, "bajas": 0,
          "enlaces": [{"enlace": "https://magandhi.com/producto/?slug=grisi-gold-shampoo-manzanilla-curcuma-extra-aclarante-400ml", "clics": 2, "personas": 1},
                      {"enlace": "https://magandhi.com/", "clics": 1, "personas": 1}],
          "ventas": {"exactas_n": 1, "exactas_valor": 40000, "aprox_n": 1, "aprox_valor": 22000,
                     "pedidos": [{"ref": "#D0000000", "fecha": "2026-10-08", "total": 40000, "cliente": "Caro Tres", "tipo": "exacta"},
                                 {"ref": "#D0000003", "fecha": "2026-09-30", "total": 22000, "cliente": "Beto Dos", "tipo": "aproximada"}]},
          "primer_evento": "2026-09-28T10:00:00Z", "ultimo_evento": "2026-10-08T10:00:00Z", "archivado": False,
          "webhook_ultimo_evento": "2026-10-08T10:00:00Z"}
VACIO = {"destinatarios": 3, "enviados": 0, "entregados": 0, "rebotes": 0, "quejas": 0, "aperturas": 0, "clics_personas": 0,
         "clics_total": 0, "bajas": 0, "enlaces": [], "ventas": {"exactas_n": 0, "exactas_valor": 0, "aprox_n": 0, "aprox_valor": 0, "pedidos": []},
         "primer_evento": None, "archivado": False, "webhook_ultimo_evento": None}

def camp(id, nombre, estado):
    return {"id": id, "nombre_interno": nombre, "asunto": "Asunto " + nombre, "preheader": None, "estado": estado,
            "contenido": [{"tipo": "titulo", "texto": "Hola"}], "segmento_id": "s1", "tema": "novedades", "audiencia_n": 4,
            "programada_para": None, "enviada_en": "2026-09-28T10:00:00Z", "utm_campaign": "c1", "resend_broadcast_id": "bc",
            "confirmada_en": "2026-09-28T09:59:00Z", "error": None, "actualizado": "2026-09-28T10:00:00Z"}

def fixtures(modo):
    lista = [dict(camp(C1, "Lanzamiento Grisi", "enviada"), segmento="Tunja", tema="Novedades", listos=4, pendientes=0, bloques=1),
             dict(camp(C2, "Borrador octubre", "borrador"), segmento=None, tema=None, listos=0, pendientes=0, bloques=1, audiencia_n=None)]
    f = {
        "rpc/em_campanas_lista": lista,
        "rpc/em_campanas_resultados_lista": {C1: {"entregados": 3, "clics": 2, "pedidos": 2}},
        "rpc/em_segmentos_lista": [{"id": "s1", "nombre": "Tunja", "tipo": "reglas", "suscritos": 4}],
        "rpc/em_campana_audiencia": {"n": 4, "sin_nombre": 0, "politica_publicada": True, "muestra": []},
        "rpc/em_campana_detalle": {"campana": camp(C1, "Lanzamiento Grisi", "enviada"), "estado_visible": "enviada",
                                   "segmento": {"id": "s1", "nombre": "Tunja", "tipo": "reglas", "archivado": False},
                                   "tema": {"codigo": "novedades", "nombre": "Novedades"},
                                   "destinatarios": {"total": 4, "listos": 4, "pendientes": 0, "excluidos": 0},
                                   "confirmada_por_correo": "admin@local.invalid", "bitacora": []},
        "rpc/em_campana_resultados": RES_C1 if modo == "lleno" else VACIO,
        "rpc/em_resumen": {"total": 5, "por_estado": {"suscrito": 3, "rebotado": 1, "baja": 1}, "por_fuente": {"manual": 3},
                           "por_tema": [{"codigo": "novedades", "nombre": "Novedades", "suscritos": 3}], "vinculados": 2,
                           "altas_30d": 5, "bajas_30d": 1, "clientes_con_correo_sin_contacto": 0,
                           "semanas": [{"semana": "2026-10-05", "altas": 5, "bajas": 1}],
                           "seguimiento_30d": {"enviados": 2, "fallidos": 0, "ultimo": "2026-10-08T10:00:00Z"},
                           "config": {"politica_publicada": True, "politica_version": "1.0", "politica_url": "https://magandhi.com/p"}},
        "rpc/em_salud_lista": ({"periodo_dias": 60, "enviados": 52, "entregados": 49, "rebotes": 3, "quejas": 0, "tasa_rebote": 5.77,
                                "tasa_queja": 0.0, "limite_rebote": 4, "limite_queja": 0.08, "ultimo_evento": "2026-10-08T10:00:00Z",
                                "suprimidos_auto_30d": 2} if modo == "lleno" else
                               {"periodo_dias": 60, "enviados": 0, "entregados": 0, "rebotes": 0, "quejas": 0, "tasa_rebote": None,
                                "tasa_queja": None, "limite_rebote": 4, "limite_queja": 0.08, "ultimo_evento": None, "suprimidos_auto_30d": 0}),
        "rpc/em_correos_seguimiento": [
            {"id": "e1", "creado": "2026-10-08T10:00:00Z", "etapa": "recibido", "estado": "enviado", "destinatario": "caro@x.invalid", "asunto": "a",
             "es_prueba": False, "es_reenvio": False, "error": None, "pedido_ref": "#D0000009", "cliente_nombre": "Caro", "entrega": "entregado", "entrega_en": "2026-10-08T10:01:00Z"},
            {"id": "e2", "creado": "2026-10-08T11:00:00Z", "etapa": "preparando", "estado": "enviado", "destinatario": "caro@x.invalid", "asunto": "a",
             "es_prueba": False, "es_reenvio": False, "error": None, "pedido_ref": "#D0000009", "cliente_nombre": "Caro", "entrega": "rebote", "entrega_en": "2026-10-08T11:01:00Z"},
            {"id": "e3", "creado": "2026-10-08T12:00:00Z", "etapa": "en_camino", "estado": "enviado", "destinatario": "ana@x.invalid", "asunto": "a",
             "es_prueba": False, "es_reenvio": False, "error": None, "pedido_ref": "#D0000001", "cliente_nombre": "Ana", "entrega": None, "entrega_en": None}],
        "em_contactos": [{"id": CT, "correo": "ana@x.invalid", "nombre": "Ana", "estado": "baja", "fuente": "manual", "temas": ["novedades"],
                          "customer_id": None, "consentimiento_en": "2026-10-01T00:00:00Z", "creado": "2026-10-01T00:00:00Z", "politica_version": "1.0"}],
        "rpc/em_contacto_detalle": {"contacto": {"id": CT, "correo": "ana@x.invalid", "nombre": "Ana", "estado": "baja", "fuente": "manual", "temas": ["novedades"],
                                                 "consentimiento_en": "2026-10-01T00:00:00Z", "consentimiento_texto": "Autorizo...", "politica_version": "1.0",
                                                 "evidencia": {"canal": "whatsapp", "detalle": "Lo pidió por WhatsApp"}, "baja_en": "2026-10-07T00:00:00Z",
                                                 "baja_motivo": "Se dio de baja desde el enlace de un correo (Resend)", "creado": "2026-10-01T00:00:00Z"},
                                    "registrado_por_correo": "admin@local.invalid", "cliente": None, "seguimiento": [],
                                    "bitacora": [{"accion": "baja", "estado_anterior": "suscrito", "estado_nuevo": "baja", "detalle": {"evento": "contact.updated", "origen": "resend_webhook"}, "cuando": "2026-10-07T00:00:00Z", "actor_correo": None},
                                                 {"accion": "alta", "estado_anterior": None, "estado_nuevo": "suscrito", "detalle": {"evidencia": {"canal": "whatsapp"}}, "cuando": "2026-10-01T00:00:00Z", "actor_correo": "admin@local.invalid"}]},
        "rpc/em_contacto_campanas": [{"campana_id": C1, "nombre": "Lanzamiento Grisi", "asunto": "x", "cuando": "2026-09-28T10:00:00Z", "eventos": ["clic", "entregado", "apertura"]}],
        "em_temas": [{"codigo": "novedades", "nombre": "Novedades", "descripcion": "", "orden": 1}],
        "catalogo_publico": [],
        "em_config": [{"politica_publicada": True, "politica_version": "1.0"}],
    }
    return f

def manejar(route, f, modo):
    url = route.request.url
    if "/auth/v1/user" in url:
        return route.fulfill(json=SESION["user"])
    if "/functions/v1/em-campana" in url:
        return route.fulfill(json={"html": "<html><body><p>Vista previa</p></body></html>", "asunto": "x"})
    if "/rest/v1/" in url:
        clave = url.split("/rest/v1/")[1].split("?")[0]
        if clave == "perfiles":
            return route.fulfill(json={"rol": "admin", "modulos": []})
        if modo == "sin_em5" and clave in ("rpc/em_campana_resultados", "rpc/em_campanas_resultados_lista", "rpc/em_salud_lista", "rpc/em_contacto_campanas"):
            return route.fulfill(status=404, json={"code": "PGRST202", "message": "Could not find the function public." + clave[4:] + " without parameters"})
        if clave in f:
            return route.fulfill(json=f[clave])
        return route.fulfill(status=404, json={"message": "no simulado: " + clave})
    return route.fulfill(status=404, body="")

res = []
def chk(ok, q): res.append((bool(ok), q))

def abrir(b, ancho, ruta, modo="lleno"):
    ctx = b.new_context(viewport={"width": ancho, "height": 900})
    ctx.add_init_script("try { if (window === window.top) localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s) } catch (e) {}" % json.dumps(json.dumps(SESION)))
    pg = ctx.new_page()
    errores = []
    pg.on("pageerror", lambda e: errores.append(str(e)))
    pg.on("console", lambda m: errores.append(m.text + " @" + str(m.location.get("url",""))[:60]) if m.type == "error" and "404" not in m.text and "Failed to load resource" not in m.text else None)
    f = fixtures(modo)
    pg.route(SB + "/**", lambda r: manejar(r, f, modo))
    pg.goto(BASE + ruta)
    pg.wait_for_timeout(2500)
    return ctx, pg, errores

def desborde(pg):
    return pg.evaluate("document.scrollingElement.scrollWidth > window.innerWidth + 1")

import functools, http.server, threading
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
SERVIDOR = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), H)
threading.Thread(target=SERVIDOR.serve_forever, daemon=True).start()
with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, disp in ((1280, "PC"), (390, "celular")):
        # 1. Campana enviada con resultados
        ctx, pg, err = abrir(b, ancho, "campanas.html?id=" + C1)
        t = pg.text_content("#rs-caja") if pg.query_selector("#rs-caja") else ""
        chk("Resultados" in t, f"{disp}: campaña enviada muestra Resultados")
        chk(pg.locator(".rs-embudo li").count() == 5, f"{disp}: embudo de 5 pasos")
        chk("aproximado" in t and "Abrieron" in t, f"{disp}: aperturas rotuladas como aproximadas")
        chk("75%" in t, f"{disp}: entregados 3 de 4 = 75%")
        chk("$40.000" in t and "$22.000" in t, f"{disp}: ventas exactas y aproximadas en pesos")
        chk(pg.locator(".rs-tag.aprox").count() == 1 and pg.locator(".rs-tag:not(.aprox)").count() == 1, f"{disp}: cada pedido marcado Exacta/Aproximada")
        chk(pg.locator(".rs-enlaces li").count() == 2, f"{disp}: enlaces más clicados")
        chk("siguiente tramo" not in pg.text_content("body"), f"{disp}: ya no dice 'llegan en el siguiente tramo'")
        chk(not desborde(pg), f"{disp}: sin desborde horizontal (resultados)")
        tw = pg.evaluate("(() => { const t = document.querySelector('.rs-tabla'), c = document.querySelector('.rs-tabla-caja'); return t && c ? t.scrollWidth <= c.clientWidth + 1 : null })()")
        chk(tw is True, f"{disp}: la tabla de ventas cabe sin cortarse")
        chk("1 pedido web" in pg.text_content("#rs-caja") and "1 pedidos" not in pg.text_content("#rs-caja"), f"{disp}: singular correcto (1 pedido)")
        lw = pg.evaluate("(() => { const e = document.querySelector('.rs-enlaces .url'); return e ? e.scrollWidth > e.clientWidth : null })()")
        chk(lw is True, f"{disp}: enlace largo se recorta con puntos suspensivos")
        if ancho == 1280:
            pg.locator("#rs-caja").screenshot(path="/projects/sandbox/pruebas-em5/rs-pc.png")
        else:
            pg.locator("#rs-caja").screenshot(path="/projects/sandbox/pruebas-em5/rs-movil.png")
        chk(not err, f"{disp}: sin errores de JS (resultados) {err[:2]}")
        ctx.close()

        # 2. Lista con columna de resultados
        ctx, pg, err = abrir(b, ancho, "campanas.html")
        rs = pg.locator(".cp-item-rs")
        chk(rs.count() == 1 and "3 entregados" in rs.text_content() and "2 pedidos" in rs.text_content(), f"{disp}: lista muestra resultados solo en la enviada")
        chk(not desborde(pg), f"{disp}: sin desborde (lista)")
        chk(not err, f"{disp}: sin errores de JS (lista) {err[:2]}")
        ctx.close()

        # 3. Sin avisos todavia y sin webhook
        ctx, pg, err = abrir(b, ancho, "campanas.html?id=" + C1, "vacio")
        t = pg.text_content("#rs-caja")
        chk("webhook" in t and pg.locator(".rs-embudo").count() == 0, f"{disp}: sin avisos explica que falta conectar el webhook")
        chk(not err, f"{disp}: sin errores (vacío) {err[:2]}")
        ctx.close()

        # 4. Migracion EM5 sin aplicar: nada se rompe
        ctx, pg, err = abrir(b, ancho, "campanas.html?id=" + C1, "sin_em5")
        chk("20261013000000" in pg.text_content("#rs-caja"), f"{disp}: sin EM5 aplicada avisa la migración")
        ctx.close()
        ctx, pg, err = abrir(b, ancho, "campanas.html", "sin_em5")
        chk(pg.locator(".cp-item").count() == 2 and pg.locator(".cp-item-rs").count() == 0, f"{disp}: sin EM5 la lista sigue funcionando")
        chk(not err, f"{disp}: sin errores de JS (sin EM5) {err[:2]}")
        ctx.close()

        # 5. Resumen con salud
        ctx, pg, err = abrir(b, ancho, "index.html")
        t = pg.text_content("body")
        chk("Salud de la lista" in t and "5,77%" in t, f"{disp}: salud de la lista con tasa de rebote")
        chk(pg.locator(".sl-med.alerta").count() == 1, f"{disp}: rebote sobre el límite de 4 % marcado en alerta")
        chk(not desborde(pg), f"{disp}: sin desborde (resumen)")
        chk(not err, f"{disp}: sin errores (resumen) {err[:2]}")
        ctx.close()
        ctx, pg, err = abrir(b, ancho, "index.html", "vacio")
        chk("ningún aviso de Resend" in pg.text_content("body"), f"{disp}: salud sin webhook lo explica")
        ctx.close()
        ctx, pg, err = abrir(b, ancho, "index.html", "sin_em5")
        chk("Salud de la lista" not in pg.text_content("#em-contenido") and "Personas que reciben" in pg.text_content("#em-contenido"), f"{disp}: sin EM5 el Resumen sigue igual")
        ctx.close()

        # 6. Seguimiento con entrega
        ctx, pg, err = abrir(b, ancho, "seguimiento.html")
        t = pg.text_content("body")
        if ancho == 1280:
            chk("Entregado" in t and "Rebotó" in t and "Sin aviso aún" in t, f"{disp}: seguimiento muestra Entregado / Rebotó / Sin aviso")
        else:
            chk(pg.locator("th.em-ocultar-movil").count() >= 1, f"{disp}: columna Entrega oculta en celular como Destinatario")
        chk(not desborde(pg), f"{disp}: sin desborde (seguimiento)")
        chk(not err, f"{disp}: sin errores (seguimiento) {err[:2]}")
        ctx.close()

        # 7. Ficha del contacto
        ctx, pg, err = abrir(b, ancho, "contactos.html?id=" + CT)
        t = pg.text_content("#ficha-body") if pg.query_selector("#ficha-body") else ""
        chk("Campañas recibidas" in t and "Lanzamiento Grisi" in t and "hizo clic" in t, f"{disp}: ficha con campañas recibidas y lo que hizo")
        chk("Dejar de recibir" in t and "automático" in t, f"{disp}: historial explica la baja automática desde el correo")
        chk(not err, f"{disp}: sin errores (ficha) {err[:2]}")
        ctx.close()
    b.close()
SERVIDOR.shutdown()

for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
