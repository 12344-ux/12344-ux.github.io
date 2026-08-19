#!/usr/bin/env python3
"""
MONTAGUTH · Rastreador de nichos v1
===================================

Qué hace (y qué NO hace)
------------------------
SÍ:  descubre términos en alza a partir de categorías semilla, mide la demanda real
     de cada candidato en Google Trends (Colombia, 12 meses), calcula si sube o baja,
     descarta lo que viola nuestras reglas, y puntúa lo que queda.
NO:  no adivina "productos ganadores" ni ve ventas privadas de otras tiendas.
     Su valor es DESCARTAR rápido: te deja una lista corta que vale la pena mirar a mano.

El precio y el margen NO se pueden automatizar todavía (hay que verlos en el proveedor).
El score de demanda te dice QUÉ investigar; el margen decide si se vende.

Uso
---
    pip install pytrends pandas
    python3 rastreador.py                      # corre con las semillas por defecto
    python3 rastreador.py --semillas "cocina,gimnasio en casa"
    python3 rastreador.py --candidatos "masajeador cuello,proyector portatil"
    python3 rastreador.py --geo CO --meses 12

Salidas en ./salidas/ : un .md para leer y un .csv para filtrar.
"""

import argparse
import csv
import json
import os
import re
import sys
import time
from datetime import datetime

try:
    from pytrends.request import TrendReq
except ImportError:
    sys.exit("Falta pytrends.  ->  pip install pytrends pandas")


# ---------------------------------------------------------------- configuración

# Categorías amplias de las que sacamos candidatos (consultas "en alza" relacionadas).
SEMILLAS = [
    "organizador",
    "cocina",
    "gimnasio en casa",
    "escritorio",
    "mascotas",
    "carro accesorios",
]

# LISTA NEGRA — se descarta sin discutir (regla de marca, §ética del proyecto).
#  1) marcas de terceros y clones  -> falsificación: cierra pasarelas y baneos
#  2) salud / suplementos / cosmética con promesas -> regulado (INVIMA) + política de anuncios
#  3) categorías con riesgo o certificación -> devoluciones y responsabilidad
LISTA_NEGRA = [
    # marcas y clones
    r"\b(nike|adidas|apple|iphone|airpods|samsung|xiaomi|jordan|puma|rolex|gucci|"
    r"playstation|nintendo|lego|stanley|dyson|jbl|bose|gopro)\b",
    r"\b(replica|réplica|clon|imitacion|imitación|aaa|primera copia|tipo apple|estilo nike)\b",
    # salud y afines
    r"\b(suplemento|adelgaz|quema grasa|proteina|proteína|vitamina|colageno|colágeno|"
    r"pastilla|medicamento|crema reductora|blanqueador dental|viagra|cbd|melatonina)\b",
    # riesgo / certificación / restringido
    r"\b(vape|vaporizador|cigarrillo|arma|airsoft|taser|laser|láser|dron|drone|"
    r"bebe|bebé|cuna|silla de carro|casco|bicicleta electrica|patineta electrica|"
    r"bateria de litio|batería de litio)\b",
    # commodities donde solo se compite por precio
    r"\b(cable usb|memoria usb|protector de pantalla|funda para celular|audifonos baratos)\b",
]

# Palabras que indican que el usuario está COMPRANDO (no solo investigando).
INTENCION_COMPRA = [r"\bcomprar\b", r"\bprecio\b", r"\bdonde comprar\b", r"\bdónde comprar\b", r"\bbarato\b"]

PAUSA = 8.0          # segundos entre consultas (Google Trends bloquea rápido si lo apuras)
REINTENTOS = 4

# Caché en disco: Google Trends limita fuerte (429). Sin caché, cada corrida pelea
# de nuevo por datos que ya teníamos. Con caché, una corrida interrumpida se
# retoma donde quedó y las métricas de un término se piden UNA sola vez.
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "salidas", ".cache-trends.json")
_cache = None


def cache_cargar():
    global _cache
    if _cache is None:
        try:
            with open(CACHE, encoding="utf-8") as f:
                _cache = json.load(f)
        except Exception:
            _cache = {"metricas": {}, "relacionadas": {}}
    return _cache


def cache_guardar():
    if _cache is None:
        return
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(_cache, f, ensure_ascii=False, indent=1)


# ---------------------------------------------------------------- utilidades

def limpio(t):
    return re.sub(r"\s+", " ", (t or "").strip().lower())


def en_lista_negra(termino):
    t = limpio(termino)
    for patron in LISTA_NEGRA:
        m = re.search(patron, t)
        if m:
            return m.group(0)
    return None


def con_reintentos(fn, etiqueta):
    """Google Trends devuelve 429 con facilidad; esperamos y reintentamos."""
    for intento in range(1, REINTENTOS + 1):
        try:
            return fn()
        except Exception as e:
            espera = PAUSA * intento * 2
            print(f"    · {etiqueta}: fallo ({type(e).__name__}). Reintento en {espera:.0f}s "
                  f"({intento}/{REINTENTOS})", flush=True)
            time.sleep(espera)
    print(f"    · {etiqueta}: se omite tras {REINTENTOS} intentos.", flush=True)
    return None


# ---------------------------------------------------------------- fase 1 · descubrir

def descubrir(pt, semillas, geo, timeframe):
    """De cada semilla saca las consultas relacionadas EN ALZA ('rising')."""
    c = cache_cargar()
    encontrados = {}
    for semilla in semillas:
        clave_cache = f"{geo}|{timeframe}|{semilla}"
        if clave_cache in c["relacionadas"]:
            print(f"  [descubrir] {semilla}  (caché)", flush=True)
            crudos = c["relacionadas"][clave_cache]
        else:
            print(f"  [descubrir] {semilla}", flush=True)

            def consulta():
                pt.build_payload([semilla], timeframe=timeframe, geo=geo)
                return pt.related_queries()

            datos = con_reintentos(consulta, semilla)
            time.sleep(PAUSA)
            if not datos:
                continue
            bloque = datos.get(semilla) or {}
            crudos = []
            for tipo in ("rising", "top"):
                df = bloque.get(tipo)
                if df is None or not len(df):
                    continue
                for _, fila in df.iterrows():
                    t = limpio(fila.get("query"))
                    if t and len(t) >= 4:
                        crudos.append({"termino": t, "tipo": tipo, "valor_rel": int(fila.get("value") or 0)})
            c["relacionadas"][clave_cache] = crudos
            cache_guardar()

        for item in crudos:
            previo = encontrados.get(item["termino"])
            if not previo or item["valor_rel"] > previo["valor_rel"]:
                encontrados[item["termino"]] = {**item, "origen": semilla}
    return list(encontrados.values())


# ---------------------------------------------------------------- fase 2 · medir

def medir(pt, terminos, geo, timeframe, lote=4):
    """interest_over_time por lotes, con caché. Devuelve métricas de demanda por término."""
    c = cache_cargar()
    resultado = {}
    pendientes = []
    for t in terminos:
        clave = f"{geo}|{timeframe}|{t}"
        if clave in c["metricas"]:
            resultado[t] = c["metricas"][clave]
        else:
            pendientes.append(t)
    if resultado:
        print(f"  [medir] {len(resultado)} término(s) desde caché", flush=True)

    for i in range(0, len(pendientes), lote):
        grupo = pendientes[i:i + lote]
        print(f"  [medir] {', '.join(grupo)}", flush=True)

        def consulta():
            pt.build_payload(grupo, timeframe=timeframe, geo=geo)
            return pt.interest_over_time()

        df = con_reintentos(consulta, ", ".join(grupo))
        time.sleep(PAUSA)
        if df is None or not len(df):
            continue
        if "isPartial" in df.columns:
            df = df[df["isPartial"] == False]  # noqa: E712  (última semana incompleta)
        for termino in grupo:
            if termino not in df.columns:
                continue
            serie = df[termino].astype(float)
            if serie.empty or serie.max() == 0:
                continue
            n = len(serie)
            recientes = serie.tail(max(4, n // 4))
            previos = serie.head(n - len(recientes)).tail(max(4, n // 4))
            media_rec = float(recientes.mean())
            media_prev = float(previos.mean()) if len(previos) else media_rec
            crecimiento = ((media_rec - media_prev) / media_prev * 100) if media_prev > 0 else 0.0
            m = {
                "media_reciente": round(media_rec, 1),
                "media_previa": round(media_prev, 1),
                "crecimiento_pct": round(crecimiento, 1),
                "pico": float(serie.max()),
                "media_12m": round(float(serie.mean()), 1),
                "estacional": round(float(serie.max() / max(serie.mean(), 0.1)), 2),
                "semanas": n,
            }
            resultado[termino] = m
            c["metricas"][f"{geo}|{timeframe}|{termino}"] = m
        cache_guardar()
    return resultado


# ---------------------------------------------------------------- fase 3 · puntuar

def puntuar(m, termino):
    """
    Score 0-100. Pondera lo que de verdad importa para NUESTRO canal (video + anuncios):
      · volumen sostenido (40)  -> que exista demanda todo el año, no un pico
      · crecimiento (35)        -> que vaya subiendo, no muriendo
      · estabilidad (15)        -> penaliza lo hiperestacional (un pico y nada)
      · intención de compra (10)-> el término suena a comprar, no a investigar
    """
    volumen = min(m["media_12m"] / 50 * 40, 40)
    crec = m["crecimiento_pct"]
    crecimiento = 35 if crec >= 50 else (25 + (crec - 20) / 30 * 10) if crec >= 20 else \
                  (15 + crec / 20 * 10) if crec >= 0 else max(0, 15 + crec / 4)
    estabilidad = 15 if m["estacional"] <= 2 else (10 if m["estacional"] <= 3 else
                  (5 if m["estacional"] <= 4.5 else 0))
    intencion = 10 if any(re.search(p, termino) for p in INTENCION_COMPRA) else 0
    return round(min(volumen + crecimiento + estabilidad + intencion, 100), 1)


def veredicto(score, m):
    """
    La razón tiene que describir los NÚMEROS REALES, no una frase bonita.
    (Un 'demanda en alza' sobre un término que cae -10% te hace tomar una mala decisión.)
    """
    crec = m["crecimiento_pct"]
    if m["media_12m"] < 5:
        return "descartar", "demanda demasiado baja para sostener una landing"
    if crec <= -25:
        return "descartar", f"cayendo {crec:.0f}%: moda que ya pasó"
    if m["estacional"] > 5:
        return "vigilar", f"muy estacional (×{m['estacional']:.0f}): solo sirve en su temporada"
    if score >= 65:
        if crec >= 10:
            return "investigar", f"demanda alta y creciendo ({crec:+.0f}%): buscar precio de proveedor"
        if crec >= -15:
            return "investigar", f"demanda alta y estable ({crec:+.0f}%): buscar precio de proveedor"
        return "vigilar", f"demanda alta pero enfriándose ({crec:+.0f}%): entrar solo con buen margen"
    if score >= 45:
        if crec >= 20:
            return "vigilar", f"creciendo fuerte ({crec:+.0f}%) pero volumen bajo ({m['media_12m']}): seguir de cerca"
        return "vigilar", f"señal media ({crec:+.0f}%): depende del margen que dé el proveedor"
    return "descartar", f"señal débil (volumen {m['media_12m']}, {crec:+.0f}%) frente al esfuerzo"


# ---------------------------------------------------------------- salida

def escribir(filas, carpeta, geo, timeframe, origen_desc):
    os.makedirs(carpeta, exist_ok=True)
    sello = datetime.now().strftime("%Y%m%d-%H%M")
    ruta_csv = os.path.join(carpeta, f"nichos-{sello}.csv")
    ruta_md = os.path.join(carpeta, f"nichos-{sello}.md")

    campos = ["termino", "score", "veredicto", "razon", "media_12m", "crecimiento_pct",
              "estacional", "pico", "origen", "tipo", "semanas"]
    with open(ruta_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos, extrasaction="ignore")
        w.writeheader()
        w.writerows(filas)

    grupos = {"investigar": [], "vigilar": [], "descartar": []}
    for fila in filas:
        grupos[fila["veredicto"]].append(fila)

    with open(ruta_md, "w", encoding="utf-8") as f:
        f.write(f"# Rastreador de nichos · Montaguth\n\n")
        f.write(f"- **Corrida:** {datetime.now():%Y-%m-%d %H:%M}\n")
        f.write(f"- **Mercado:** `{geo}` · **Ventana:** `{timeframe}`\n")
        f.write(f"- **Origen de los candidatos:** {origen_desc}\n")
        f.write(f"- **Candidatos evaluados:** {len(filas)}\n\n")
        f.write("> El score mide DEMANDA, no rentabilidad. El margen del proveedor decide.\n")
        f.write("> Todo lo de 'investigar' hay que verificarlo a mano: precio, peso, proveedor y competencia.\n\n")
        for nombre, titulo in (("investigar", "🟢 Investigar"),
                               ("vigilar", "🟡 Vigilar"),
                               ("descartar", "🔴 Descartar")):
            lista = grupos[nombre]
            f.write(f"## {titulo} ({len(lista)})\n\n")
            if not lista:
                f.write("_Nada en este grupo._\n\n")
                continue
            f.write("| Término | Score | Demanda 12m | Crecimiento | Estacionalidad | Por qué |\n")
            f.write("|---|---:|---:|---:|---:|---|\n")
            for r in lista:
                f.write(f"| {r['termino']} | {r['score']} | {r['media_12m']} | "
                        f"{r['crecimiento_pct']:+.1f}% | ×{r['estacional']} | {r['razon']} |\n")
            f.write("\n")
        f.write("---\n\n## Filtro manual obligatorio antes de elegir\n\n")
        f.write("1. Ticket ≥ $80.000 COP y margen ≥ 50% (o ≥ $40.000 absolutos).\n"
                "2. Se demuestra en video en menos de 10 segundos.\n"
                "3. Liviano, no frágil.\n"
                "4. Sin tallas ni variantes complicadas.\n"
                "5. Sin marcas de terceros, sin salud/regulados.\n"
                "6. Resuelve un problema o da estatus (no commodity).\n"
                "7. Proveedor con entrega rápida disponible.\n"
                "8. Con competencia, pero no saturado.\n")
    return ruta_md, ruta_csv


# ---------------------------------------------------------------- principal

def main():
    global PAUSA
    ap = argparse.ArgumentParser(description="Rastreador de nichos de Montaguth")
    ap.add_argument("--semillas", default=",".join(SEMILLAS))
    ap.add_argument("--candidatos", default="", help="evalúa estos términos directamente (salta el descubrimiento)")
    ap.add_argument("--geo", default="CO")
    ap.add_argument("--meses", type=int, default=12)
    ap.add_argument("--tope", type=int, default=24, help="máx. candidatos a medir")
    ap.add_argument("--pausa", type=float, default=PAUSA, help="segundos entre consultas (súbelo si te bloquean)")
    ap.add_argument("--salidas", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "salidas"))
    args = ap.parse_args()

    PAUSA = args.pausa
    timeframe = f"today {args.meses}-m"
    semillas = [limpio(s) for s in args.semillas.split(",") if limpio(s)]
    # retries/backoff propios de pytrends + los nuestros: Trends devuelve 429 con facilidad.
    pt = TrendReq(hl="es-CO", tz=300, timeout=(10, 30), retries=3, backoff_factor=1.5)

    print(f"\nMONTAGUTH · rastreador de nichos   (mercado {args.geo}, {timeframe})\n")

    if args.candidatos:
        candidatos = [{"termino": limpio(c), "origen": "manual", "tipo": "manual", "valor_rel": 0}
                      for c in args.candidatos.split(",") if limpio(c)]
        origen_desc = "lista manual (`--candidatos`)"
    else:
        origen_desc = "descubrimiento por semillas: " + ", ".join(semillas)
        print("FASE 1 · descubrir candidatos")
        candidatos = descubrir(pt, semillas, args.geo, timeframe)
        print(f"  -> {len(candidatos)} términos crudos\n")

    # Descarte por lista negra ANTES de gastar consultas
    limpios, vetados = [], []
    for c in candidatos:
        motivo = en_lista_negra(c["termino"])
        (vetados if motivo else limpios).append({**c, "motivo": motivo})
    if vetados:
        print(f"FASE 1b · vetados por reglas de marca ({len(vetados)}):")
        for v in vetados[:12]:
            print(f"  ✗ {v['termino']}  ({v['motivo']})")
        print()

    limpios.sort(key=lambda x: x["valor_rel"], reverse=True)
    limpios = limpios[:args.tope]
    if not limpios:
        sys.exit("No quedaron candidatos que medir.")

    print(f"FASE 2 · medir demanda ({len(limpios)} términos)")
    metricas = medir(pt, [c["termino"] for c in limpios], args.geo, timeframe)
    print()

    filas = []
    for c in limpios:
        m = metricas.get(c["termino"])
        if not m:
            continue
        score = puntuar(m, c["termino"])
        v, razon = veredicto(score, m)
        filas.append({**c, **m, "score": score, "veredicto": v, "razon": razon})
    filas.sort(key=lambda r: r["score"], reverse=True)

    if not filas:
        sys.exit("Google Trends no devolvió datos (probablemente rate limit). Reintenta en unos minutos.")

    md, csv_ = escribir(filas, args.salidas, args.geo, timeframe, origen_desc)
    print("FASE 3 · resultado\n")
    print(f"  {'TÉRMINO':<34}{'SCORE':>6}  {'12M':>5}  {'CREC':>8}  VEREDICTO")
    for r in filas[:15]:
        print(f"  {r['termino'][:33]:<34}{r['score']:>6}  {r['media_12m']:>5}  "
              f"{r['crecimiento_pct']:>+7.1f}%  {r['veredicto']}")
    print(f"\n  informe : {md}\n  tabla   : {csv_}\n")


if __name__ == "__main__":
    main()
