# Dropshipping D2c.1 (stock vivo y saldo) en Chromium (PC 1280 y celular 390).
# No necesita el doble de Dropi ni la Edge Function real: lo que se mide aqui es
# la PANTALLA. ds_estado_stock y la sonda de dinero se responden desde Python con
# las formas exactas que devuelven en produccion (ds_estado_stock con su
# `motivo`, y la sonda con `saldo.wallet_amount`, el nombre REAL medido en la
# cuenta del dueno).
#
# Lo que importa comprobar:
#   · el motivo por el que un producto esta fuera de vitrina se ve y se entiende;
#   · una lectura vencida se distingue a simple vista;
#   · el saldo en cero grita, porque es el fallo silencioso (se vende y no se
#     puede despachar);
#   · un problema con Dropi NO puede dejar la tabla de stock en blanco: son dos
#     lecturas independientes;
#   · un perfil sin admin no ve el saldo, y no se le inventa un error.
import functools, http.server, threading, json, time, base64, sys
from playwright.sync_api import sync_playwright

REPO = "/projects/sandbox/12344-ux.github.io"
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=REPO)
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8815), H)
threading.Thread(target=S.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:8815/"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPS = sys.argv[1] if len(sys.argv) > 1 else None

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600,
       "expires_at": exp, "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []
chk = lambda ok, q: res.append((bool(ok), q))

ahora = time.time()
def iso(ts): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ts)) + "Z"

# Las cuatro situaciones que la pantalla tiene que saber contar.
FILAS = [
    # En vitrina: lectura fresca y stock sobre el piso.
    {"product_id": "a1", "sku": "MAG-DROP-9001", "nombre": "Gotas Berberine", "dropi_id": "2296060",
     "variante": None, "stock": 230, "piso_efectivo": 20, "leido_en": iso(ahora - 60),
     "vence_en": iso(ahora + 7000), "vigente": True, "en_vitrina": True,
     "motivo": "en vitrina", "ultimo_error": None},
    # El derrumbe medido: 300 -> 0.
    {"product_id": "a2", "sku": "MAG-DROP-9002", "nombre": "Lipogan 6 Frascos", "dropi_id": "2296058",
     "variante": None, "stock": 0, "piso_efectivo": 20, "leido_en": iso(ahora - 120),
     "vence_en": iso(ahora + 7000), "vigente": True, "en_vitrina": False,
     "motivo": "por debajo del piso", "ultimo_error": None},
    # Lectura vencida con stock de sobra: el fallo cerrado.
    {"product_id": "a3", "sku": "MAG-DROP-9003", "nombre": "Pantalón Palazzo", "dropi_id": "2296061",
     "variante": "7001", "stock": 500, "piso_efectivo": 20, "leido_en": iso(ahora - 20000),
     "vence_en": iso(ahora - 8000), "vigente": False, "en_vitrina": False,
     "motivo": "lectura vencida", "ultimo_error": "429 · Dropi frenó por exceso de consultas"},
    # Nunca se ha leído.
    {"product_id": "a4", "sku": "MAG-DROP-9004", "nombre": "Recién importado", "dropi_id": "2296099",
     "variante": None, "stock": None, "piso_efectivo": 50, "leido_en": None,
     "vence_en": None, "vigente": False, "en_vitrina": False,
     "motivo": "sin lectura todavía", "ultimo_error": None},
]

E = {}
def reset(**kw):
    E.update(rol="admin", filas=FILAS, stock_falla=False, saldo=150000.5,
             saldo_frenado=False, saldo_falla=False, sin_campo=False)
    E.update(kw)

def man(route):
    rq = route.request
    u = rq.url
    if "/auth/v1/" in u:
        return route.fulfill(json=SES["user"])
    if "/rest/v1/perfiles" in u:
        return route.fulfill(json={"rol": E["rol"], "modulos": ["dropshipping"]})
    if "/rest/v1/rpc/ds_estado_stock" in u:
        if E["stock_falla"]:
            return route.fulfill(status=500, json={"message": "boom en la base"})
        return route.fulfill(json=E["filas"])
    if "/functions/v1/dropi-sonda" in u:
        if rq.method == "OPTIONS":
            return route.fulfill(status=204, headers={"access-control-allow-origin": "*",
                                                      "access-control-allow-headers": "*"})
        if E["saldo_falla"]:
            return route.fulfill(status=500, body="{}", headers={"content-type": "application/json",
                                                                 "access-control-allow-origin": "*"})
        cuerpo = {"sonda": "dinero", "frenado_por_dropi": bool(E["saldo_frenado"]),
                  "conclusion": "x",
                  "saldo": ({} if E["sin_campo"] else {"wallet_amount": E["saldo"]})}
        return route.fulfill(json=cuerpo, headers={"access-control-allow-origin": "*"})
    # Nada mas de Supabase debe hacer falta en esta pantalla.
    if "/rest/v1/dropshipping_candidatos" in u:
        return route.fulfill(json=[])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho):
    c = b.new_context(viewport={"width": ancho, "height": 1000})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}"
                      % json.dumps(json.dumps(SES)))
    pg = c.new_page()
    err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text)
          if m.type == "error" and "Failed to load resource" not in m.text else None)
    c.route("**/*", lambda r: man(r) if "supabase.co" in r.request.url else r.continue_())
    pg.goto(BASE + "dropshipping/index.html")
    pg.wait_for_selector("#ds-main:not([hidden])", timeout=15000)
    return c, pg, err

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        # ---------- Caso normal ----------
        reset()
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-vivo .ds-tabla", timeout=15000)
        pg.wait_for_timeout(400)

        chk(pg.locator("#ds-vivo .ds-tabla tbody tr").count() == 4,
            f"{d}: la tabla lista los 4 productos de proveedor")

        f2 = pg.text_content("#ds-vivo .ds-tabla tbody tr >> nth=1") or ""
        chk("por debajo del piso" in f2,
            f"{d}: el derrumbe (300 ⇒ 0) se explica como «por debajo del piso»")

        f3 = pg.locator("#ds-vivo .ds-tabla tbody tr").nth(2)
        chk("lectura vencida" in (f3.text_content() or ""),
            f"{d}: una lectura vencida con 500 unidades se explica como «lectura vencida»")
        chk(f3.locator("td.ds-vencido").count() == 1 and "vencida" in (f3.locator("td.ds-vencido").text_content() or ""),
            f"{d}: la fecha vencida se marca aparte para verla de un golpe")
        chk("429" in (f3.text_content() or ""),
            f"{d}: el último fallo de Dropi queda a la vista en su fila")
        chk("variante 7001" in (f3.text_content() or ""),
            f"{d}: la fila dice de qué variante de Dropi es el producto")

        f4 = pg.text_content("#ds-vivo .ds-tabla tbody tr >> nth=3") or ""
        chk("sin lectura todavía" in f4, f"{d}: un producto recién importado dice que aún no se ha leído")
        chk("—" in f4, f"{d}: sin stock no se inventa un 0: se muestra un guion")

        chk("1 producto" in (pg.text_content("#ds-vivo .ds-meta") or "") or
            "3 fuera de vitrina" in (pg.text_content("#ds-vivo .ds-meta") or ""),
            f"{d}: el pie cuenta cuántos están fuera de vitrina")
        chk("bloqueada" in (pg.text_content("#ds-vivo .ds-meta") or ""),
            f"{d}: el pie recuerda que la publicación de proveedor sigue bloqueada")

        # ---------- El saldo ----------
        chk("150.000" in (pg.text_content("#ds-saldo") or ""),
            f"{d}: el saldo de Dropi se muestra formateado en pesos")
        chk(pg.locator(".ds-saldo-caja--alerta").count() == 0,
            f"{d}: con saldo positivo no hay alerta")
        chk(not err, f"{d}: la pantalla carga sin errores de consola ({err[:1]})")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/d2c1-vivo-{ancho}.png", full_page=True)
        c.close()

        # ---------- Saldo en cero: el fallo silencioso ----------
        reset(saldo=0)
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector(".ds-saldo-caja", timeout=15000)
        chk(pg.locator(".ds-saldo-caja--alerta").count() == 1,
            f"{d}: saldo en 0 pinta la alerta")
        chk("no se puede despachar" in (pg.text_content("#ds-saldo") or ""),
            f"{d}: y explica la consecuencia real (se vende y no se puede despachar)")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/d2c1-saldo-cero-{ancho}.png", full_page=True)
        c.close()

        # ---------- Dropi falla: la tabla NO puede quedar en blanco ----------
        reset(saldo_falla=True)
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-vivo .ds-tabla", timeout=15000)
        pg.wait_for_timeout(400)
        chk(pg.locator("#ds-vivo .ds-tabla tbody tr").count() == 4,
            f"{d}: si la consulta del saldo falla, la tabla de stock se pinta igual")
        chk(pg.locator("#ds-saldo .ds-aviso").count() == 1,
            f"{d}: el fallo del saldo se avisa en su propia caja")
        chk("Aún no has hecho una consulta" in (pg.text_content("#ds-meta-resultados") or ""),
            f"{d}: y NO pisa el estado del área de búsqueda")
        c.close()

        # ---------- 429 ----------
        reset(saldo_frenado=True)
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-saldo .ds-aviso", timeout=15000)
        chk("429" in (pg.text_content("#ds-saldo") or ""),
            f"{d}: un 429 se nombra tal cual, no como un error genérico")
        chk("temporal" in (pg.text_content("#ds-saldo") or "").lower(),
            f"{d}: y dice que es temporal, para no asustar")
        c.close()

        # ---------- Dropi responde sin el campo del saldo ----------
        reset(sin_campo=True)
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-saldo .ds-aviso", timeout=15000)
        chk("sin el saldo" in (pg.text_content("#ds-saldo") or ""),
            f"{d}: si el campo del saldo cambia de nombre otra vez, se dice en vez de mostrar 0")
        c.close()

        # ---------- La base falla ----------
        reset(stock_falla=True)
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-vivo .ds-aviso", timeout=15000)
        chk(pg.locator("#ds-vivo .ds-aviso--err").count() == 1,
            f"{d}: si la base falla, se dice con un aviso de error y no una tabla vacía")
        c.close()

        # ---------- Sin productos de proveedor ----------
        reset(filas=[])
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-vivo.ds-vacio", timeout=15000)
        chk("Todavía no hay productos de proveedor" in (pg.text_content("#ds-vivo") or ""),
            f"{d}: sin productos explica qué hacer, en vez de una tabla vacía")
        c.close()

        # ---------- Un perfil sin admin ----------
        reset(rol="operador")
        c, pg, err = abrir(b, ancho)
        pg.wait_for_selector("#ds-vivo .ds-tabla", timeout=15000)
        pg.wait_for_timeout(400)
        chk((pg.text_content("#ds-saldo") or "").strip() == "",
            f"{d}: un perfil no-admin no ve el saldo (la sonda es de admin hasta D3)")
        chk(pg.locator("#ds-vivo .ds-tabla tbody tr").count() == 4,
            f"{d}: pero sí ve el estado del stock, que sale de la base con su módulo")
        c.close()

    b.close()

for ok, q in res:
    print(("pasa" if ok else "FALLA") + " | " + q)
fallan = sum(1 for ok, _ in res if not ok)
print(f"RESUMEN | {len(res)} comprobaciones · {fallan} fallan")
sys.exit(1 if fallan else 0)
