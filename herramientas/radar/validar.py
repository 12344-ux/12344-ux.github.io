#!/usr/bin/env python3
"""
MONTAGUTH · Validador de candidatos
===================================
Toma una lista de productos candidatos y los somete a los criterios del proyecto,
con DATOS REALES del mercado colombiano:

  · Precio de mercado en Mercado Libre CO (piso, mediana, nº de ofertas)
       -> ¿queda margen?  ¿hay guerra de precios?  ¿hay competencia o desierto?
  · Google Trends geo=CO (demanda 12 meses y crecimiento)
       -> ¿sube o es moda muerta?

No inventa nada: si un dato no se puede leer, lo dice.

    python3 validar.py "fuente de agua para gatos,alfombra olfativa,..."
"""
import re
import sys
import time
from radar import bajar, cache_cargar, leer_listado, veta

TICKET_MIN = 80000
UTILIDAD_MIN = 40000


def precio_mercado(termino, cache):
    # BUG CORREGIDO: las tildes y la ñ rompían la URL (UnicodeEncodeError).
    from urllib.parse import quote
    url = "https://listado.mercadolibre.com.co/" + quote(re.sub(r"\s+", "-", termino))
    try:
        html = bajar(url, cache)
    except Exception as e:
        return None, f"no se pudo consultar ({type(e).__name__})"
    items, destacados = leer_listado(html)
    ps = sorted([i["precio"] for i in items if i["precio"] and i["precio"] > 1000])
    if not ps:
        return None, "sin resultados de precio"
    n = len(ps)
    return {
        "ofertas": n,
        "min": ps[0],
        "mediana": ps[n // 2],
        "max": ps[-1],
        "destacados": destacados,
    }, None


def cop(v):
    return "$" + format(int(v), ",d").replace(",", ".")


def trends(terminos):
    """Demanda y crecimiento en Colombia. Reutiliza el motor del rastreador."""
    sys.path.insert(0, "../rastreador")
    try:
        import rastreador as R
    except Exception as e:
        print("  (Trends no disponible:", e, ")")
        return {}
    R.PAUSA = 9
    from pytrends.request import TrendReq
    pt = TrendReq(hl="es-CO", tz=300, timeout=(10, 30), retries=3, backoff_factor=1.5)
    return R.medir(pt, terminos, "CO", "today 12-m")


def main():
    if len(sys.argv) < 2:
        sys.exit('Uso: python3 validar.py "producto 1,producto 2,..."')
    candidatos = [c.strip().lower() for c in sys.argv[1].split(",") if c.strip()]
    cache = cache_cargar()

    print("\n=== PRECIO REAL DE MERCADO EN COLOMBIA (Mercado Libre) ===\n")
    print(f"{'PRODUCTO':<34}{'PISO':>12}{'TÍPICO':>12}{'ALTO':>12}{'OFERTAS':>9}")
    datos = {}
    for c in candidatos:
        m, err = precio_mercado(c, cache)
        datos[c] = m
        if not m:
            print(f"{c[:33]:<34}{'—':>12}{'—':>12}{'—':>12}{'—':>9}   {err}")
            continue
        print(f"{c[:33]:<34}{cop(m['min']):>12}{cop(m['mediana']):>12}{cop(m['max']):>12}{m['ofertas']:>9}")

    print("\n=== DEMANDA Y TENDENCIA (Google Trends · Colombia · 12 meses) ===\n")
    met = trends(candidatos)
    print(f"\n{'PRODUCTO':<34}{'DEMANDA':>9}{'CRECIM.':>10}{'ESTACION.':>11}")
    for c in candidatos:
        m = met.get(c)
        if not m:
            print(f"{c[:33]:<34}{'—':>9}{'—':>10}{'—':>11}")
            continue
        print(f"{c[:33]:<34}{m['media_12m']:>9}{m['crecimiento_pct']:>+9.1f}%{('×' + str(m['estacional'])):>11}")

    print("\n=== VEREDICTO (criterios del proyecto) ===\n")
    filas = []
    for c in candidatos:
        p, t = datos.get(c), met.get(c)
        notas = []
        puntos = 0
        if p:
            if p["mediana"] >= TICKET_MIN:
                puntos += 2
                notas.append(f"ticket sano ({cop(p['mediana'])})")
            else:
                notas.append(f"ticket bajo ({cop(p['mediana'])})")
            if p["min"] < p["mediana"] * 0.3:
                notas.append(f"guerra de precios (piso {cop(p['min'])})")
            else:
                puntos += 1
                notas.append("piso de precio sano")
            if p["ofertas"] >= 8:
                puntos += 1
                notas.append("hay mercado")
        if t:
            if t["media_12m"] >= 20:
                puntos += 2
                notas.append(f"demanda alta ({t['media_12m']})")
            elif t["media_12m"] >= 8:
                puntos += 1
                notas.append(f"demanda media ({t['media_12m']})")
            else:
                notas.append(f"demanda baja ({t['media_12m']})")
            if t["crecimiento_pct"] >= 10:
                puntos += 2
                notas.append(f"creciendo {t['crecimiento_pct']:+.0f}%")
            elif t["crecimiento_pct"] >= -15:
                puntos += 1
                notas.append(f"estable ({t['crecimiento_pct']:+.0f}%)")
            else:
                notas.append(f"cayendo {t['crecimiento_pct']:+.0f}%")
        filas.append((puntos, c, notas))
    filas.sort(reverse=True)
    for puntos, c, notas in filas:
        marca = "🟢" if puntos >= 6 else ("🟡" if puntos >= 4 else "🔴")
        print(f"{marca} {puntos}/8  {c:<32} {' · '.join(notas)}")
    print()


if __name__ == "__main__":
    main()
