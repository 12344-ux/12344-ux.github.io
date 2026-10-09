# Pantallas de F3 (Finanzas) con las RPC REALES (simulador -> Postgres local).
# Las lecturas de tablas con recursos anidados (asientos + lineas + PUC) se
# sirven desde la MISMA base con SQL, porque el simulador no las traduce.
# PC 1280 y celular 390.
import functools, http.server, threading, json, time, base64, urllib.request, urllib.parse, subprocess, sys
from playwright.sync_api import sync_playwright
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory="/projects/sandbox/12344-ux.github.io")
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
S = http.server.ThreadingHTTPServer(("127.0.0.1", 8773), H); threading.Thread(target=S.serve_forever, daemon=True).start()
B = "http://127.0.0.1:8773/finanzas/"
SB = "https://bxlzipwxyxdtffnuizbz.supabase.co"
UID = "89e5028d-8c17-4deb-89c3-59acbd0ee2f2"
CAPTURAS = "--capturas" in sys.argv
def b64(o): return base64.urlsafe_b64encode(json.dumps(o).encode()).decode().rstrip("=")
exp = int(time.time()) + 3600
jwt = b64({"alg": "HS256"}) + "." + b64({"sub": UID, "role": "authenticated", "exp": exp}) + ".x"
SES = {"access_token": jwt, "refresh_token": "r", "token_type": "bearer", "expires_in": 3600, "expires_at": exp,
       "user": {"id": UID, "email": "admin@local.invalid", "aud": "authenticated"}}
res = []; chk = lambda ok, q: res.append((bool(ok), q))
ESTADO = {"sin_origen": False}   # simula la base SIN la migracion de F3 (columna origen ausente)

def sql(q):
    return subprocess.run(["psql", "-tAqc", q, "-d", "impulse_pruebas"], capture_output=True, text=True,
                          env={"PGHOST": "/var/lib/pgdata", "PGUSER": "postgres", "PATH": "/usr/bin"}).stdout.strip()

def asientos_json(select, filtro_id):
    con_origen = "origen" in select
    donde = "where a.id = '%s'" % filtro_id if filtro_id else ""
    return sql("""select coalesce(jsonb_agg(x order by x->>'fecha' desc, x->>'creado' desc), '[]')::text from (
      select jsonb_build_object('id', a.id, 'fecha', a.fecha, 'descripcion', a.descripcion, 'estado', a.estado,
             'creado', a.creado %s,
             'asiento_lineas', (select coalesce(jsonb_agg(jsonb_build_object('cuenta_codigo', l.cuenta_codigo,
                  'detalle', l.detalle, 'debe', l.debe, 'haber', l.haber, 'orden', l.orden,
                  'puc_cuentas', jsonb_build_object('nombre', p.nombre)) order by l.orden), '[]')
                from asiento_lineas l join puc_cuentas p on p.codigo = l.cuenta_codigo where l.asiento_id = a.id)) x
        from asientos a %s) t""" % (", 'origen', a.origen, 'origen_ref', a.origen_ref" if con_origen else "", donde))

def man(route):
    rq = route.request; u = rq.url
    if "/rest/v1/perfiles" in u: return route.fulfill(json={"rol": "admin", "modulos": []})
    if "/rest/v1/rpc/" in u:
        name = u.split("/rest/v1/rpc/")[1].split("?")[0]
        r = urllib.request.Request("http://localhost:54321/rest/v1/rpc/" + name,
                                   data=rq.post_data_buffer or b"{}", method="POST",
                                   headers={"content-type": "application/json"})
        try: resp = urllib.request.urlopen(r); st, body = resp.status, resp.read()
        except urllib.error.HTTPError as e: st, body = e.code, e.read()
        return route.fulfill(status=st, body=body, headers={"content-type": "application/json"})
    if "/rest/v1/asientos" in u:
        q = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
        select = q.get("select", [""])[0]
        if ESTADO["sin_origen"] and "origen" in select:
            return route.fulfill(status=400, json={"code": "42703", "message": "column asientos.origen does not exist"})
        fid = q.get("id", [""])[0].replace("eq.", "")
        filas = json.loads(asientos_json(select, fid) or "[]")
        if "vnd.pgrst.object" in (rq.headers.get("accept") or ""):
            return route.fulfill(json=filas[0] if filas else None)
        return route.fulfill(json=filas)
    if "/rest/v1/asiento_bitacora" in u:
        q = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
        aid = q.get("asiento_id", [""])[0].replace("eq.", "")
        return route.fulfill(body=sql("""select coalesce(jsonb_agg(jsonb_build_object('accion', accion, 'cuando', cuando,
             'actor', actor, 'detalle_cambio', detalle_cambio) order by cuando desc), '[]')::text
             from asiento_bitacora where asiento_id = '%s'""" % aid) or "[]", headers={"content-type": "application/json"})
    if "/rest/v1/puc_cuentas" in u: return route.fulfill(json=[])
    if "/auth/v1/" in u: return route.fulfill(json=SES["user"])
    return route.fulfill(status=404, body="{}")

def abrir(b, ancho, pagina):
    c = b.new_context(viewport={"width": ancho, "height": 900})
    c.add_init_script("try{localStorage.setItem('sb-bxlzipwxyxdtffnuizbz-auth-token', %s)}catch(e){}" % json.dumps(json.dumps(SES)))
    pg = c.new_page(); err = []
    pg.on("pageerror", lambda e: err.append(str(e)))
    pg.on("console", lambda m: err.append(m.text) if m.type == "error" and "Failed to load resource" not in m.text else None)
    pg.route(SB + "/**", man)
    pg.goto(B + pagina); pg.wait_for_timeout(2600)
    return c, pg, err

desb = lambda pg: pg.evaluate("""document.scrollingElement.scrollWidth > innerWidth + 1 ||
  [...document.querySelectorAll('.fz-pend-btn, .fz-pend-monto, .fz-pend-tit, .fz-tag-auto, .fz-auto-nota')].some(e => {
    const r = e.getBoundingClientRect(), c = e.closest('.fz-pend-item, .fz-pendientes, .fz-asiento');
    if (!c || !r.width) return false; const q = c.getBoundingClientRect();
    return r.right > q.right + 1 || r.left < q.left - 1; })""")
PEDIDO = sql("select pedido_id from pagos_intencion where referencia = 'MAG-a2000000-1791549152798-0a1b2c3d4e5f'")

with sync_playwright() as p:
    b = p.chromium.launch()
    for ancho, d in ((1280, "PC"), (390, "celular")):
        # --- Portada: la venta real sin asiento (falta el IVA) ---
        c, pg, err = abrir(b, ancho, "index.html")
        chk(pg.locator(".fz-pendientes").count() == 1, f"{d}: el aviso aparece cuando hay una venta web sin asiento")
        chk("1 venta web sin asiento" in (pg.text_content(".fz-pend-tit") or ""), f"{d}: el título dice cuántas son")
        txt = pg.text_content(".fz-pendientes") or ""
        chk("IVA" in txt and "$69.900" in txt and "MAG-a2000000-1791549152798-0a1b2c3d4e5f" in txt,
            f"{d}: muestra el motivo real (IVA), el monto en pesos y la referencia de Wompi")
        chk("Hilda" not in txt and "hilda@" not in txt and "3014443322" not in txt,
            f"{d}: sin datos personales del comprador")
        chk(pg.locator(".fz-pend-item").count() == 1, f"{d}: la venta de PRUEBA (sandbox) no aparece")
        chk(pg.locator(".fz-cards .fz-card").count() >= 7, f"{d}: el aviso no estorba las tarjetas del área")
        pg.locator(".fz-pend-btn").first.click(); pg.wait_for_timeout(1200)
        chk("Todavía falta" in (pg.text_content(".fz-pend-msg") or "") and "IVA" in (pg.text_content(".fz-pend-motivo") or ""),
            f"{d}: si todavía falta algo, el botón lo dice sin repetir el motivo que ya está a la vista")
        chk(sql(f"select count(*) from asientos where origen_ref = '{PEDIDO}'") == "0", f"{d}: y no escribe nada")
        chk(not desb(pg) and not err, f"{d}: sin desborde ni errores {err[:1]}")
        if CAPTURAS:
            pg.screenshot(path=f"/projects/sandbox/pruebas-em5/fz-pendientes-{ancho}.png",
                          clip={"x": 0, "y": 0, "width": ancho, "height": 900})
        c.close()

        # --- El dueño define el IVA: listo para registrar y se registra ---
        sql("update contabilidad_config set iva_ventas_pct = 0 where id = 1")
        c, pg, err = abrir(b, ancho, "index.html")
        chk("listo para registrar" in (pg.text_content(".fz-pend-motivo") or ""), f"{d}: con el IVA definido dice «listo para registrar»")
        pg.locator(".fz-pend-btn").first.click(); pg.wait_for_timeout(700)
        chk("Registrado" in (pg.text_content(".fz-pend-msg") or ""), f"{d}: confirma que quedó en el Libro Diario")
        chk(sql(f"select string_agg(cuenta_codigo || ':' || debe || ':' || haber, ',' order by orden) from asiento_lineas l "
                f"join asientos a on a.id = l.asiento_id where a.origen = 'venta_web' and a.origen_ref = '{PEDIDO}'")
            == "138095:69900:0,413505:0:69900,613505:25000:0,143505:0:25000", f"{d}: el asiento quedó al peso en la base")
        pg.wait_for_timeout(1500)
        chk(pg.locator(".fz-pendientes").count() == 0, f"{d}: resuelto, el aviso desaparece")
        c.close()

        # --- Diario: marca Automático, sin Editar/Anular; los manuales igual que siempre ---
        c, pg, err = abrir(b, ancho, "diario.html")
        auto = pg.locator(".fz-asiento", has=pg.locator(".fz-tag-auto"))
        manual = pg.locator(".fz-asiento", has_text="Aporte inicial (manual)")
        chk(auto.count() == 1 and "Automático · venta web" in (auto.first.text_content() or ""),
            f"{d}: el asiento de la venta web lleva la marca «Automático · venta web»")
        chk(auto.first.locator(".fz-accion.editar, .fz-accion.anular").count() == 0,
            f"{d}: el automático NO ofrece Editar ni Anular")
        chk("anulando el pedido en Ventas" in (auto.first.text_content() or ""), f"{d}: y explica cómo se corrige")
        chk(manual.locator(".fz-accion.editar").count() == 1 and manual.locator(".fz-accion.anular").count() == 1,
            f"{d}: el asiento manual conserva Editar y Anular")
        auto.first.locator(".fz-accion.historial").click(); pg.wait_for_timeout(900)
        chk("Creado" in (auto.first.text_content() or ""), f"{d}: el historial del automático muestra su creación")
        chk(not desb(pg) and not err, f"{d}: Diario sin desborde ni errores {err[:1]}")
        if CAPTURAS:
            auto.first.scroll_into_view_if_needed()
            pg.screenshot(path=f"/projects/sandbox/pruebas-em5/fz-diario-auto-{ancho}.png",
                          clip={"x": 0, "y": 0, "width": ancho, "height": 900})
        c.close()

        # --- Editar asiento por URL: solo lectura con explicación ---
        aid = sql(f"select id from asientos where origen = 'venta_web' and origen_ref = '{PEDIDO}'")
        c, pg, err = abrir(b, ancho, "editar-asiento.html?id=" + aid)
        chk(pg.locator("#fz-auto-aviso").is_visible(), f"{d}: Editar muestra que lo registró el sistema")
        chk(not pg.locator("#fz-guardar").is_visible() and not pg.locator("#fz-anular").is_visible(),
            f"{d}: sin botones de Guardar ni Anular")
        chk(pg.locator("#fz-desc").is_disabled(), f"{d}: los campos quedan de solo lectura")
        chk(not err, f"{d}: Editar sin errores {err[:1]}")
        c.close()

        # --- Base SIN F3: el Diario no se cae (degrada sin la marca) ---
        ESTADO["sin_origen"] = True
        c, pg, err = abrir(b, ancho, "diario.html")
        chk(pg.locator(".fz-asiento").count() >= 2 and pg.locator(".fz-tag-auto").count() == 0,
            f"{d}: con la base sin F3 el Diario carga igual (sin la marca)")
        chk(not err, f"{d}: y sin errores {err[:1]}")
        c.close()
        ESTADO["sin_origen"] = False

        # Dejar la venta otra vez pendiente para la vuelta del celular.
        sql(f"delete from asiento_bitacora where asiento_id in (select id from asientos where origen_ref = '{PEDIDO}')")
        sql(f"delete from asiento_lineas where asiento_id in (select id from asientos where origen_ref = '{PEDIDO}')")
        sql(f"delete from asientos where origen_ref = '{PEDIDO}'")
        sql("update contabilidad_config set iva_ventas_pct = null where id = 1")
    b.close()
S.shutdown()
for ok, q in res: print(("pasa" if ok else "FALLA") + " | " + q)
print("RESUMEN | %d comprobaciones · %d fallan" % (len(res), sum(1 for o, _ in res if not o)))
