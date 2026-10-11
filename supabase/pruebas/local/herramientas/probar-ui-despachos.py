# Ventas · Despachos de proveedor (D2c.2) en Chromium (PC 1280 y celular 390).
# Mide la PANTALLA: que diga exactamente qué pedir en Dropi, que exija el número
# de pedido, que acepte montos con puntos, que avise cuando el asiento queda
# pendiente, y que el aviso de la portada de Ventas aparezca solo si hay algo.
import functools, http.server, threading, json, time, base64, sys
from playwright.sync_api import sync_playwright

REPO = "/projects/sandbox/12344-ux.github.io"
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=REPO)
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8817), H)
threading.Thread(target=S.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:8817/"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPS = sys.argv[1] if len(sys.argv) > 1 else None

def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600,
       "expires_at": exp, "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []
chk = lambda ok, q: res.append((bool(ok), q))

FILA = {
    "pedido_id": "11111111-1111-4111-8111-111111111111",
    "pedido_corto": "11111111",
    "fecha_orden": "2026-10-11",
    "estado": "recibido",
    "total": 59900,
    "product_id": "22222222-2222-4222-8222-222222222222",
    "producto": "Gotas Berberine",
    "sku": "MAG-DROP-9001",
    "dropi_id": "2296060",
    "variante": "7001",
    "cantidad": 2,
    "stock_al_vender": 230,
    "ciudad": "Leticia",
    "departamento": "Amazonas",
    "horas_esperando": 3.4,
}

E = {}
def reset(**kw):
    E.update(filas=[dict(FILA)], registros=[], falla_registro=None, falla_lista=False)
    E.update(kw)

def man(route):
    rq = route.request
    u = rq.url
    if "/auth/v1/" in u:
        return route.fulfill(json=SES["user"])
    if "/rest/v1/perfiles" in u:
        return route.fulfill(json={"rol": "admin", "modulos": ["ventas", "dropshipping"]})
    if "/rest/v1/rpc/ds_pedidos_por_transcribir" in u:
        if E["falla_lista"]:
            return route.fulfill(status=500, json={"message": "boom"})
        return route.fulfill(json=E["filas"])
    if "/rest/v1/rpc/ds_registrar_transcripcion" in u:
        a = json.loads(rq.post_data or "{}")
        if E["falla_registro"]:
            return route.fulfill(status=400, json={"message": E["falla_registro"]})
        E["registros"].append(a)
        E["filas"] = []          # al registrarlo desaparece de la lista
        return route.fulfill(json={"ya_estaba": False, "pedido_externo_id": a.get("p_pedido_externo_id")})
    # La portada de Ventas también consulta los pagos sin pedido (F2).
    if "/rest/v1/rpc/pw_revisiones" in u:
        return route.fulfill(json={"pendientes": 0, "lista": []})
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho, pagina):
    c = b.new_context(viewport={"width": ancho, "height": 1000})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}"
                      % json.dumps(json.dumps(SES)))
    pg = c.new_page()
    err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text)
          if m.type == "error" and "Failed to load resource" not in m.text else None)
    c.route("**/*", lambda r: man(r) if "supabase.co" in r.request.url else r.continue_())
    pg.goto(BASE + pagina)
    pg.wait_for_selector("#vt-main:not([hidden])", timeout=15000)
    return c, pg, err

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        # ---------- La pantalla con un despacho pendiente ----------
        reset()
        c, pg, err = abrir(b, ancho, "ventas/despachos-proveedor/index.html")
        pg.wait_for_selector(".dp-item", timeout=15000)

        txt = pg.text_content(".dp-copiar") or ""
        chk("2296060" in txt, f"{d}: dice el id de Dropi que hay que pedir")
        chk("7001" in txt, f"{d}: dice la variante")
        chk("Leticia" in txt and "Amazonas" in txt, f"{d}: dice el destino completo")
        chk("SIN RECAUDO" in txt, f"{d}: recuerda que va SIN RECAUDO (el cliente ya pagó)")
        chk("230" in (pg.text_content(".dp-evidencia") or ""),
            f"{d}: muestra la evidencia de lo que Dropi reportaba al cobrar")
        chk("hace 3 h" in (pg.text_content(".dp-meta") or ""),
            f"{d}: dice cuánto lleva esperando el pedido")

        # El número de pedido es obligatorio: sin él no se puede verificar nada.
        pg.click('[data-c="guardar"]')
        pg.wait_for_timeout(250)
        chk("número de pedido" in (pg.text_content('[data-c="msg"]') or ""),
            f"{d}: sin el número de Dropi no deja registrar y lo explica")
        chk(len(E["registros"]) == 0, f"{d}: y no llama al servidor")

        # Montos con puntos, como en el resto de Ventas.
        pg.fill('[data-c="externo"]', "DROPI-99881")
        pg.fill('[data-c="costo"]', "21.000")
        pg.fill('[data-c="flete"]', "14.500")
        pg.click('[data-c="guardar"]')
        pg.wait_for_selector("#vt-estado .dp-banner--ok", timeout=10000)
        r = E["registros"][0] if E["registros"] else {}
        chk(r.get("p_pedido_externo_id") == "DROPI-99881", f"{d}: envía el número de pedido")
        chk(r.get("p_costo_real") == 21000 and r.get("p_flete") == 14500,
            f"{d}: interpreta «21.000» y «14.500» como enteros en pesos")
        chk("Finanzas" in (pg.text_content("#vt-estado") or ""),
            f"{d}: avisa que el asiento ya se puede registrar en Finanzas")
        chk("No hay despachos pendientes" in (pg.text_content("#vt-lista") or ""),
            f"{d}: y la lista queda vacía")
        chk(not err, f"{d}: la pantalla carga sin errores de consola ({err[:1]})")
        if CAPS:
            pg.screenshot(path=f"{CAPS}/despachos-{ancho}.png", full_page=True)
        c.close()

        # ---------- Sin costo ni flete: el asiento queda pendiente ----------
        reset()
        c, pg, err = abrir(b, ancho, "ventas/despachos-proveedor/index.html")
        pg.wait_for_selector(".dp-item", timeout=15000)
        pg.fill('[data-c="externo"]', "DROPI-555")
        pg.click('[data-c="guardar"]')
        pg.wait_for_selector("#vt-estado .dp-banner--ok", timeout=10000)
        r = E["registros"][0]
        chk(r.get("p_costo_real") is None and r.get("p_flete") is None,
            f"{d}: se puede registrar sin costo ni flete (Dropi no siempre los muestra)")
        chk("pendiente" in (pg.text_content("#vt-estado") or ""),
            f"{d}: y avisa que el asiento queda PENDIENTE hasta anotarlos")
        c.close()

        # ---------- Un monto que no se entiende ----------
        reset()
        c, pg, err = abrir(b, ancho, "ventas/despachos-proveedor/index.html")
        pg.wait_for_selector(".dp-item", timeout=15000)
        pg.fill('[data-c="externo"]', "DROPI-1")
        pg.fill('[data-c="costo"]', "veintiun mil")
        pg.click('[data-c="guardar"]')
        pg.wait_for_timeout(250)
        chk("no se entiende" in (pg.text_content('[data-c="msg"]') or ""),
            f"{d}: un monto en letras se rechaza con un mensaje claro")
        chk(len(E["registros"]) == 0, f"{d}: y no se envía nada al servidor")
        c.close()

        # ---------- El error del servidor se muestra tal cual ----------
        reset(falla_registro="DS_FALTA_PEDIDO_EXTERNO: anota el numero de pedido que te dio Dropi.")
        c, pg, err = abrir(b, ancho, "ventas/despachos-proveedor/index.html")
        pg.wait_for_selector(".dp-item", timeout=15000)
        pg.fill('[data-c="externo"]', "X")
        pg.click('[data-c="guardar"]')
        pg.wait_for_selector('.dp-msg--err', timeout=10000)
        m = pg.text_content('[data-c="msg"]') or ""
        chk("anota el numero" in m, f"{d}: el mensaje del servidor se muestra, no se tapa")
        chk("DS_FALTA" not in m, f"{d}: pero sin el código interno, que al dueño no le dice nada")
        c.close()

        # ---------- Si la lista falla ----------
        reset(falla_lista=True)
        c, pg, err = abrir(b, ancho, "ventas/despachos-proveedor/index.html")
        pg.wait_for_selector("#vt-estado .dp-banner--err", timeout=15000)
        chk("No se pudo leer" in (pg.text_content("#vt-estado") or ""),
            f"{d}: si la lista falla se dice, en vez de una pantalla vacía")
        c.close()

        # ---------- El aviso en la portada de Ventas ----------
        reset()
        c, pg, err = abrir(b, ancho, "ventas/index.html")
        pg.wait_for_selector("#vt-despachos .vt-revisiones", timeout=15000)
        av = pg.text_content("#vt-despachos") or ""
        chk("1 pedido por crear en Dropi" in av,
            f"{d}: la portada de Ventas avisa cuántos pedidos faltan")
        chk("3 h" in av, f"{d}: y cuánto lleva esperando el más antiguo")
        chk(pg.locator('#vt-despachos a[href="despachos-proveedor/index.html"]').count() == 1,
            f"{d}: con un enlace directo a la pantalla")
        chk(pg.locator('.vt-card[href="despachos-proveedor/index.html"]').count() == 1,
            f"{d}: y hay tarjeta propia en el área")
        c.close()

        # ---------- Sin pendientes: el aviso NO aparece ----------
        reset(filas=[])
        c, pg, err = abrir(b, ancho, "ventas/index.html")
        pg.wait_for_timeout(900)
        chk((pg.text_content("#vt-despachos") or "").strip() == "",
            f"{d}: sin pendientes no se pinta aviso (uno que siempre aparece deja de serlo)")
        chk(not err, f"{d}: la portada carga sin errores ({err[:1]})")
        c.close()

    b.close()

for ok, q in res:
    print(("pasa" if ok else "FALLA") + " | " + q)
fallan = sum(1 for ok, _ in res if not ok)
print(f"RESUMEN | {len(res)} comprobaciones · {fallan} fallan")
sys.exit(1 if fallan else 0)
