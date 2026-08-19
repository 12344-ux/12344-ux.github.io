#!/usr/bin/env python3
"""
MONTAGUTH · RADAR DE MERCADO v1
===============================

La diferencia con el rastreador
-------------------------------
El **rastreador** VALIDA hipótesis: yo le doy productos y me dice si tienen demanda.
El problema: los productos salían de MI cabeza, no del mercado.

El **radar** DESCUBRE: sale a mirar qué está vendiendo el mercado colombiano ahora
mismo, sin que nadie le sugiera nada, y solo después valida. El orden correcto es:

    DESCUBRIR (¿qué se vende?) → FILTRAR (¿nos sirve?) → VALIDAR (¿sube o baja?)
    → PRECIO DE MERCADO (¿queda margen?) → VEREDICTO

Fuentes (todas públicas y verificadas desde el servidor)
-------------------------------------------------------
1. **Mercado Libre Colombia · listados por categoría** — de cada categoría se leen los
   productos destacados y los que ML marca con el badge **"MÁS VENDIDO"**. Contando qué
   producto se repite entre los destacados sale una señal de **demanda real de compra**
   en Colombia (no de búsquedas: de ventas).
2. **Mercado Libre · tendencias de búsqueda** (tendencias.mercadolibre.com.co) — qué
   busca la gente en Colombia.
3. **Precio de mercado en ML** — el dato que mata más ideas: si el mismo producto se
   vende a $6.000, no hay margen posible y se descarta ANTES de perder tiempo.
4. **Google Trends (`geo=CO`)** vía el rastreador — si la demanda sube o baja.

Lo que NO puede (dicho de frente)
---------------------------------
· No ve ventas privadas de otras tiendas (eso solo lo dan herramientas de pago).
· TikTok Creative Center y Meta Ad Library responden 403/"no permission" desde servidor:
  la saturación publicitaria se revisa a mano.
· No decide por ti: entrega finalistas con evidencia.

Uso
---
    pip install requests
    python3 radar.py                      # todas las categorías
    python3 radar.py --categorias "Hogar y Muebles,Mascotas"
    python3 radar.py --top 15 --paginas 2
"""

import argparse
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime
from urllib.request import Request, urlopen

BASE = os.path.dirname(os.path.abspath(__file__))
SALIDAS = os.path.join(BASE, "salidas")
CACHE = os.path.join(SALIDAS, ".cache-radar.json")

UA = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept-Language": "es-CO,es;q=0.9",
}

# Categorías de Mercado Libre Colombia aptas para dropshipping.
# (Se excluyen a propósito: Bebés, Salud, Vehículos, Inmuebles, Ropa —tallas—,
#  Celulares y Computación —marcas y márgenes imposibles—.)
CATEGORIAS = {
    "Hogar y Muebles": "https://listado.mercadolibre.com.co/hogar-muebles/",
    "Herramientas": "https://listado.mercadolibre.com.co/herramientas/",
    "Belleza": "https://listado.mercadolibre.com.co/belleza-cuidado-personal/",
    "Deportes y Fitness": "https://listado.mercadolibre.com.co/deportes-fitness/",
    "Mascotas": "https://listado.mercadolibre.com.co/animales-mascotas/",
    "Electrodomésticos": "https://listado.mercadolibre.com.co/electrodomesticos/",
    "Accesorios de Vehículos": "https://listado.mercadolibre.com.co/accesorios-vehiculos/",
    "Juegos y Juguetes": "https://listado.mercadolibre.com.co/juegos-juguetes/",
}

# Lista negra: se descarta sin discutir (regla de marca del proyecto).
LISTA_NEGRA = [
    r"\b(nike|adidas|apple|iphone|airpods|samsung|xiaomi|jordan|puma|rolex|gucci|sony|"
    r"playstation|nintendo|lego|stanley|dyson|jbl|bose|gopro|huawei|honor|motorola|lg|"
    r"whirlpool|electrolux|oster|imusa|haceb|challenger)\b",
    r"\b(replica|réplica|clon|imitacion|imitación|generico|genérico)\b",
    r"\b(suplemento|adelgaz|quema.?grasa|proteina|proteína|vitamina|colageno|colágeno|"
    r"pastilla|medicamento|reductora|blanqueador|minoxidil|melatonina|creatina)\b",
    r"\b(vape|vaporizador|cigarrillo|arma|airsoft|taser|dron|drone|bebe|bebé|cuna|"
    r"pañal|silla.?carro|casco|bateria.?litio|batería.?litio|pistola)\b",
    r"\b(cable|usb|memoria|micro.?sd|protector.?pantalla|funda|forro|vidrio.?templado|"
    r"cargador.?celular|manilla|tornillo|adhesivo|cinta|pila|bombillo|foco)\b",
]

# Palabras que no son el producto (se ignoran al extraer el sustantivo del título).
RUIDO = {
    "de", "para", "con", "y", "en", "la", "el", "los", "las", "un", "una", "del", "al",
    "por", "sin", "kit", "set", "x", "pack", "combo", "unidades", "unidad", "pcs", "pzas",
    "nuevo", "nueva", "original", "premium", "profesional", "portatil", "portátil",
    "recargable", "inalambrico", "inalámbrico", "electrico", "eléctrico", "automatico",
    "automático", "digital", "led", "usb", "grande", "pequeño", "mini", "color", "negro",
    "blanco", "gris", "azul", "rojo", "verde", "rosa", "acero", "inoxidable", "plastico",
    "plástico", "silicona", "metal", "madera", "alta", "super", "ultra", "multi", "doble",
    "triple", "gran", "gran", "hogar", "casa", "cocina", "baño", "bano", "oficina", "cm",
    "mts", "ml", "lts", "litros", "pulgadas", "w", "v", "kg",
}


# ------------------------------------------------------------------ utilidades

def cache_cargar():
    try:
        with open(CACHE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def cache_guardar(c):
    os.makedirs(SALIDAS, exist_ok=True)
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(c, f, ensure_ascii=False)


def bajar(url, cache, ttl_horas=12):
    """GET con caché en disco (evita repetir peticiones entre corridas)."""
    ahora = time.time()
    hit = cache.get(url)
    if hit and (ahora - hit["t"]) < ttl_horas * 3600:
        return hit["html"]
    req = Request(url, headers=UA)
    with urlopen(req, timeout=30) as r:
        html = r.read().decode("utf-8", errors="ignore")
    cache[url] = {"t": ahora, "html": html}
    cache_guardar(cache)
    time.sleep(1.2)  # cortesía con el servidor
    return html


def veta(texto):
    t = texto.lower()
    for p in LISTA_NEGRA:
        m = re.search(p, t)
        if m:
            return m.group(0)
    return None


def limpiar(t):
    t = re.sub(r"\s+", " ", (t or "").strip().lower())
    return re.sub(r"[^\wáéíóúñü ]", "", t)


def nucleo(titulo, palabras=2):
    """
    Saca el 'producto' de un título de Mercado Libre.
    Los títulos de ML empiezan por el sustantivo: "Humidificador Atomizador Difusor..."
    -> nos quedamos con las primeras palabras significativas.
    """
    ps = [p for p in limpiar(titulo).split() if p not in RUIDO and len(p) > 2 and not p.isdigit()]
    return " ".join(ps[:palabras]) if ps else ""


def plata(txt):
    try:
        return int(re.sub(r"[^\d]", "", txt))
    except Exception:
        return None


# ------------------------------------------------------------------ 1) descubrir

def leer_listado(html):
    """Extrae (titulo, precio, es_mas_vendido) de un listado de Mercado Libre."""
    items = []
    # Los títulos y precios vienen en clases estables del componente 'poly'.
    titulos = re.findall(r'class="poly-component__title[^"]*"[^>]*>(?:<a[^>]*>)?([^<]{5,120})<', html)
    precios = re.findall(r'class="andes-money-amount__fraction"[^>]*>([\d.]+)<', html)
    # El badge "MÁS VENDIDO" viaja en el JSON embebido; contamos su presencia global
    # y la asociamos por orden de aparición aproximado.
    destacados = html.count("MÁS VENDIDO")
    for i, t in enumerate(titulos):
        items.append({
            "titulo": t.strip(),
            "precio": plata(precios[i]) if i < len(precios) else None,
        })
    return items, destacados


def descubrir(categorias, paginas, cache):
    """Recorre categorías de ML y cuenta qué PRODUCTO se repite entre los destacados."""
    conteo = Counter()
    precios = defaultdict(list)
    origen = {}
    vetados = Counter()

    for nombre, url in categorias.items():
        for p in range(paginas):
            u = url if p == 0 else f"{url}_Desde_{p * 50 + 1}"
            try:
                html = bajar(u, cache)
            except Exception as e:
                print(f"  · {nombre} pág.{p+1}: no se pudo bajar ({type(e).__name__})")
                continue
            items, destacados = leer_listado(html)
            print(f"  · {nombre} pág.{p+1}: {len(items)} productos · {destacados} marcados 'MÁS VENDIDO'")
            for it in items:
                motivo = veta(it["titulo"])
                if motivo:
                    vetados[motivo] += 1
                    continue
                n = nucleo(it["titulo"])
                if not n or len(n) < 5:
                    continue
                conteo[n] += 1
                origen.setdefault(n, nombre)
                if it["precio"]:
                    precios[n].append(it["precio"])
    return conteo, precios, origen, vetados


def tendencias_busqueda(cache):
    """Términos que la gente busca en Mercado Libre Colombia (tendencias públicas)."""
    try:
        html = bajar("https://tendencias.mercadolibre.com.co/", cache)
    except Exception:
        return []
    t = re.findall(r'<a[^>]+href="[^"]*listado[^"]*"[^>]*>([^<]{3,60})</a>', html)
    fuera = {"ver todos", "ver más"}
    return [x.strip() for x in dict.fromkeys(t)
            if x.strip().lower() not in fuera and not veta(x) and x.strip().islower()]


# ------------------------------------------------------------------ 2) precio de mercado

def precio_mercado(termino, cache):
    """
    Rango de precios REALES del producto en Colombia. Es el filtro que más ideas mata:
    si el piso del mercado es $6.000, no hay margen que sostenga una landing con anuncios.
    """
    url = "https://listado.mercadolibre.com.co/" + re.sub(r"\s+", "-", termino)
    try:
        html = bajar(url, cache)
    except Exception:
        return None
    items, destacados = leer_listado(html)
    ps = sorted([i["precio"] for i in items if i["precio"]])
    if not ps:
        return None
    n = len(ps)
    return {
        "ofertas": n,
        "min": ps[0],
        "mediana": ps[n // 2],
        "max": ps[-1],
        "destacados_mas_vendido": destacados,
    }


# ------------------------------------------------------------------ 3) veredicto

TICKET_MIN = 80000     # COP: por debajo, los anuncios se comen la venta
UTILIDAD_MIN = 40000   # COP de utilidad esperada por venta


def veredicto(m):
    """m = {mediana, min, ofertas}. Decide si vale la pena mirarlo con el proveedor."""
    if not m:
        return "sin datos", "no se pudo leer el precio de mercado"
    mediana, minimo = m["mediana"], m["min"]
    if mediana < TICKET_MIN:
        return "descartar", (f"precio típico ${mediana:,} — muy bajo para pagar anuncios"
                             .replace(",", "."))
    if minimo < mediana * 0.25:
        return "vigilar", (f"hay quien lo vende a ${minimo:,} vs. típico ${mediana:,}: "
                           "guerra de precios".replace(",", "."))
    return "investigar", (f"precio típico ${mediana:,} con piso sano: "
                          "buscarlo en el proveedor".replace(",", "."))


# ------------------------------------------------------------------ informe

def escribir(filas, tendencias, vetados, carpeta):
    os.makedirs(carpeta, exist_ok=True)
    sello = datetime.now().strftime("%Y%m%d-%H%M")
    ruta = os.path.join(carpeta, f"radar-{sello}.md")
    with open(ruta, "w", encoding="utf-8") as f:
        f.write("# Radar de mercado · Montaguth\n\n")
        f.write(f"- **Corrida:** {datetime.now():%Y-%m-%d %H:%M} · **Mercado:** Colombia\n")
        f.write("- **Fuentes:** listados y destacados de Mercado Libre CO + tendencias de "
                "búsqueda + precios reales de mercado\n")
        f.write(f"- **Candidatos con datos:** {len(filas)}\n\n")
        f.write("> El radar DESCUBRE qué se está vendiendo; no adivina ganadores.\n"
                "> Cada 'investigar' hay que buscarlo en el proveedor y validar utilidad real.\n\n")
        f.write("| # | Producto | Veces destacado | Precio típico (COP) | Piso | Ofertas | Categoría | Veredicto | Por qué |\n")
        f.write("|---:|---|---:|---:|---:|---:|---|---|---|\n")
        for i, r in enumerate(filas, 1):
            m = r["mercado"] or {}
            f.write(f"| {i} | **{r['producto']}** | {r['repeticiones']} | "
                    f"{('$' + format(m.get('mediana', 0), ',d').replace(',', '.')) if m else '—'} | "
                    f"{('$' + format(m.get('min', 0), ',d').replace(',', '.')) if m else '—'} | "
                    f"{m.get('ofertas', '—')} | {r['categoria']} | {r['veredicto']} | {r['razon']} |\n")
        f.write("\n## Tendencias de búsqueda en Colombia (Mercado Libre)\n\n")
        f.write(", ".join(tendencias[:40]) if tendencias else "_no disponibles_")
        f.write("\n\n## Descartados automáticamente por reglas de marca\n\n")
        for motivo, n in vetados.most_common(12):
            f.write(f"- `{motivo}` → {n} productos\n")
        f.write("\n## Siguiente paso\n\n"
                "1. Buscar los 'investigar' en el proveedor (Dropi) y anotar costo y precio sugerido.\n"
                "2. Utilidad = sugerido − costo. Exigir ≥ $40.000 por venta.\n"
                "3. Pasar los que sobrevivan por `herramientas/rastreador` (tendencia en Google Trends).\n"
                "4. Revisar saturación a mano en TikTok Creative Center y Meta Ad Library.\n")
    return ruta


# ------------------------------------------------------------------ principal

def main():
    ap = argparse.ArgumentParser(description="Radar de mercado de Montaguth")
    ap.add_argument("--categorias", default="")
    ap.add_argument("--paginas", type=int, default=1)
    ap.add_argument("--top", type=int, default=12, help="cuántos candidatos analizar a fondo")
    args = ap.parse_args()

    cats = CATEGORIAS
    if args.categorias:
        pedidas = [c.strip().lower() for c in args.categorias.split(",")]
        cats = {k: v for k, v in CATEGORIAS.items() if any(p in k.lower() for p in pedidas)}
        if not cats:
            sys.exit("Ninguna categoría coincide. Opciones: " + ", ".join(CATEGORIAS))

    cache = cache_cargar()
    print(f"\nMONTAGUTH · RADAR DE MERCADO   (Colombia · {len(cats)} categorías)\n")

    print("FASE 1 · descubrir qué se está vendiendo")
    conteo, precios, origen, vetados = descubrir(cats, args.paginas, cache)
    print(f"  -> {len(conteo)} productos distintos · {sum(vetados.values())} descartados por reglas\n")

    print("FASE 2 · tendencias de búsqueda en Colombia")
    tend = tendencias_busqueda(cache)
    print(f"  -> {len(tend)} términos\n")

    candidatos = [p for p, n in conteo.most_common(args.top * 3) if n >= 2][:args.top]
    if not candidatos:
        candidatos = [p for p, _ in conteo.most_common(args.top)]

    print(f"FASE 3 · precio real de mercado de los {len(candidatos)} más repetidos")
    filas = []
    for p in candidatos:
        m = precio_mercado(p, cache)
        v, razon = veredicto(m)
        filas.append({"producto": p, "repeticiones": conteo[p], "categoria": origen.get(p, "—"),
                      "mercado": m, "veredicto": v, "razon": razon})
        med = f"${m['mediana']:,}".replace(",", ".") if m else "—"
        print(f"  · {p[:34]:<36} {med:>12}  {v}")

    orden = {"investigar": 0, "vigilar": 1, "descartar": 2, "sin datos": 3}
    filas.sort(key=lambda r: (orden[r["veredicto"]], -r["repeticiones"]))

    ruta = escribir(filas, tend, vetados, SALIDAS)
    print(f"\n  informe: {ruta}\n")


if __name__ == "__main__":
    main()
