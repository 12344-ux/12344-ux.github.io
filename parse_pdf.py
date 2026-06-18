#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extrae el contenido del PDF SENA en una estructura por competencia.

Reconstruye los items que el PDF parte en varias lineas combinando dos senales:
  - borde derecho (x1): si la linea anterior llego al margen estaba "llena" (wrap)
  - salto vertical (gap): dentro de un item ~1.7, entre items ~5
Una linea continua el item anterior si  prev_x1 > X_FULL  Y  gap < GAP_CONT.
"""
import re
import json
import pdfplumber

PDF = 'Programa de Formación Titulada - Dirección de Ventas.pdf'
X_FULL = 500.0     # x1 por encima de esto => la linea estaba "llena" (se ajusto)
GAP_CONT = 3.0     # salto vertical por debajo de esto => misma unidad de texto

# una linea que empieza asi SIEMPRE es un item nuevo (vinetas / numeracion)
BULLET_RE = re.compile(r'^([\-*•]\s|\d{1,2}[-.)]\s)')

HEADER_LINES = {
    'LÍNEA TECNOLÓGICA DEL PROGRAMA', 'CLIENTE', 'RED TECNOLÓGICA',
    'Modelo de VENTAS Y COMERCIALIZACIÓN', 'Mejora Continua',
}
FOOTER_RE = re.compile(r'^\d{1,2}/\d{1,2}/\d{2,4}\s+\d{1,2}:\d{2}\s+Página\s+\d+\s+de\s+\d+')


def clean(t):
    t = t.replace('(cid:9)', ' ')
    t = re.sub(r'\s+', ' ', t).strip()
    return t


# 1) Recolectar lineas de contenido con geometria, sin encabezados/pies
#    Cada item: {'text', 'x1', 'page', 'top', 'bottom', 'cont'}
lines = []
with pdfplumber.open(PDF) as pdf:
    prev_bottom = None
    prev_x1 = None
    prev_page = None
    for pi, page in enumerate(pdf.pages):
        for ln in page.extract_text_lines():
            s = ln['text'].strip()
            if s in HEADER_LINES or FOOTER_RE.match(s):
                continue
            top = ln['top']
            # decidir si continua la linea previa
            if not lines:
                cont = False
            elif BULLET_RE.match(s):
                cont = False  # vineta/numeracion => siempre item nuevo
            elif prev_page != pi or prev_bottom is None:
                # frontera de pagina: continua solo si la anterior estaba llena
                cont = (prev_x1 is not None and prev_x1 > X_FULL)
            else:
                gap = top - prev_bottom
                cont = (prev_x1 > X_FULL) and (gap < GAP_CONT)
            lines.append({'text': s, 'x1': ln['x1'], 'page': pi, 'cont': cont})
            prev_bottom = ln['bottom']
            prev_x1 = ln['x1']
            prev_page = pi

n = len(lines)
texts = [l['text'] for l in lines]


def join_items(start, end):
    """Agrupa lines[start:end] en items usando el flag 'cont'."""
    items = []
    cur = ''
    for i in range(start, end):
        ln = lines[i]
        if ln['cont'] and cur:
            cur += ' ' + ln['text']
        else:
            if cur:
                items.append(clean(cur))
            cur = ln['text']
    if cur.strip():
        items.append(clean(cur))
    return [x for x in items if x]


def find(marker, start=0):
    for i in range(start, n):
        if texts[i].startswith(marker):
            return i
    return -1


comp_starts = [i for i, t in enumerate(texts)
               if t.startswith('1. CONTENIDOS CURRICULARES DE LA COMPETENCIA')]

competencias = []
for idx, cstart in enumerate(comp_starts):
    cend = comp_starts[idx + 1] if idx + 1 < len(comp_starts) else n

    dur_i = find('DURACIÓN ESTIMADA', cstart)
    code = version = ''
    denom_parts = []
    for i in range(cstart + 1, dur_i):
        t = texts[i]
        if t in ('CÓDIGO: DENOMINACIÓN', 'VERSIÓN DE', 'LA NCL'):
            continue
        m = re.match(r'^(\d{6,9})\s+(\d+)$', t)
        if m:
            code, version = m.group(1), m.group(2)
            continue
        m2 = re.match(r'^(\d{6,9})\s+(\d+)\s+(.+)$', t)
        if m2 and not code:
            code, version = m2.group(1), m2.group(2)
            denom_parts.append(m2.group(3))
            continue
        denom_parts.append(t)
    denominacion = clean(' '.join(denom_parts))

    duracion = ''
    for i in range(dur_i, min(dur_i + 4, cend)):
        mdur = re.search(r'(\d+)\s*horas', texts[i])
        if mdur:
            duracion = mdur.group(1) + ' horas'
            break

    res_i = find('2. RESULTADOS DE APRENDIZAJE', cstart)
    con_i = find('3. CONOCIMIENTOS', cstart)
    s31_i = find('3.1. CONOCIMIENTOS DE CONCEPTOS', cstart)
    s32_i = find('3.2. CONOCIMIENTOS DE PROCESO', cstart)
    cri_i = find('4. CRITERIOS DE EVALUACIÓN', cstart)

    resultados = []
    if res_i != -1:
        rstart = res_i + 1
        if rstart < n and texts[rstart] == 'DENOMINACIÓN':
            rstart += 1
        rend = con_i if (con_i != -1 and con_i < cend) else cend
        resultados = join_items(rstart, rend)

    saber = []
    if s31_i != -1:
        send = s32_i if (s32_i != -1 and s32_i < cend) else cend
        saber = join_items(s31_i + 1, send)

    proceso = []
    if s32_i != -1:
        pend = cri_i if (cri_i != -1 and cri_i < cend) else cend
        proceso = join_items(s32_i + 1, pend)

    criterios = []
    if cri_i != -1:
        criterios = join_items(cri_i + 1, cend)

    competencias.append({
        'orden': idx + 1, 'codigo': code, 'version': version,
        'denominacion': denominacion, 'duracion': duracion,
        'resultados_aprendizaje': resultados,
        'conocimientos_proceso': proceso,
        'conocimientos_saber': saber,
        'criterios_evaluacion': criterios,
    })

with open('competencias.json', 'w') as f:
    json.dump(competencias, f, ensure_ascii=False, indent=2)

print('Competencias extraidas:', len(competencias))
for c in competencias:
    print(f"  [{c['orden']:2}] {c['codigo']} v{c['version']} ({c['duracion']}) | "
          f"RA={len(c['resultados_aprendizaje'])} PROC={len(c['conocimientos_proceso'])} "
          f"SABER={len(c['conocimientos_saber'])} CRIT={len(c['criterios_evaluacion'])}")
