#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diseño sonoro del anuncio viral de 25 s ("Hoy sí voy a estudiar").
Decisión narrativa: los primeros 12 s NO llevan música — solo sonido real de
habitación (portátil, clics, tela, respiración). La música entra en 0:12 para
acompañar la lectura, y se vuelve cálida en la revelación de Stramont.
Salida: pista-25.wav (estéreo, 44.1 kHz, 25 s)
"""
import numpy as np, wave, os

SR = 44100; DUR = 25.0; N = int(SR*DUR)
OUT = '/projects/sandbox/voz25/pista-25.wav'
VOZ = '/projects/sandbox/voz25'

rng = np.random.default_rng(11)
mix = np.zeros((N,2), dtype=np.float32)
def idx(t): return int(round(t*SR))

def add(sig, t, gain=1.0, pan=0.0):
    s = np.asarray(sig, dtype=np.float32)*gain
    i = idx(t)
    if i >= N or i < 0: return
    s = s[:max(0, N-i)]
    l = np.sqrt((1-pan)/2); r = np.sqrt((1+pan)/2)
    mix[i:i+len(s),0] += s*l; mix[i:i+len(s),1] += s*r

def expdec(n, tau): return np.exp(-np.arange(n)/(tau*SR)).astype(np.float32)
def noise(d): return rng.uniform(-1,1,int(d*SR)).astype(np.float32)
def lp(x, cut):
    k = max(1, int(SR/(2*np.pi*cut)))
    if k <= 1: return x
    c = np.cumsum(np.concatenate(([0.0], x)))
    y = (c[k:]-c[:-k])/k
    return np.concatenate((y, np.full(len(x)-len(y), y[-1] if len(y) else 0.0))).astype(np.float32)
def hp(x, cut): return (x - lp(x, cut)).astype(np.float32)
def bp(x, lo, hi): return lp(hp(x, lo), hi)
def sine(f, d, ph=0.0):
    t = np.arange(int(d*SR))/SR
    return np.sin(2*np.pi*f*t+ph).astype(np.float32)
def fsweep(f0,f1,d):
    t = np.arange(int(d*SR))/SR; f = np.linspace(f0,f1,len(t))
    return np.sin(2*np.pi*np.cumsum(f)/SR).astype(np.float32)
def fade(x, fi=0.0, fo=0.0):
    y = x.copy(); n = len(y)
    if fi:
        k = min(int(fi*SR), n); y[:k] *= np.linspace(0,1,k)
    if fo:
        k = min(int(fo*SR), n); y[-k:] *= np.linspace(1,0,k)
    return y

# ---------------- SFX de habitación (bloque 1) ----------------
def click(sharp=1.0):
    n = int(0.03*SR)
    return (hp(noise(0.03),2200)*expdec(n,0.005) + sine(2800,0.03)*expdec(n,0.003)*0.2)*sharp

def tecla():
    n = int(0.05*SR)
    return (hp(noise(0.05),1400)*expdec(n,0.009) + sine(430,0.05)*expdec(n,0.012)*0.3)*0.8

def rueda():           # tick de scroll
    n = int(0.02*SR)
    return hp(noise(0.02),3000)*expdec(n,0.004)*0.7

def bisagra(abrir=True):   # tapa del portátil
    d = 0.55; n = int(d*SR)
    x = bp(noise(d), 220, 1100)
    e = np.linspace(0,1,n)**1.5 if abrir else np.linspace(1,0.1,n)**1.2
    x = x*e*0.5
    x += (fsweep(280,520,d) if abrir else fsweep(520,260,d))*e*0.12
    am = 1 + 0.35*np.sin(2*np.pi*11*np.arange(n)/SR)     # crujidito
    return x*am

def cierre():          # golpe seco de cerrar la tapa
    d = 0.35; n = int(d*SR)
    x = fsweep(160,60,d)*expdec(n,0.05)*0.9              # thunk grave
    nk = int(0.05*SR)                                     # chasquido del pestillo
    x[:nk] += hp(noise(0.05),1800)*expdec(nk,0.006)*0.8
    return x

def tela(d=0.5, g=1.0):    # roce de sábanas
    n = int(d*SR)
    x = bp(noise(d), 700, 5200)
    env = np.abs(lp(rng.uniform(-1,1,n).astype(np.float32), 7.0))
    env = env/ (env.max()+1e-9)
    return x*env*g

def cuerpo():          # dejarse caer en la cama
    d = 0.7; n = int(d*SR)
    x = fsweep(120,42,d)*expdec(n,0.10)*1.0
    x[:int(0.5*SR)] += tela(0.5, 0.8)
    return x

def respiro():         # exhalación
    d = 1.2; n = int(d*SR)
    x = bp(noise(d), 380, 2100)
    e = np.concatenate((np.linspace(0,1,int(0.25*SR)), np.linspace(1,0,n-int(0.25*SR))))**1.4
    return x*e*0.7

def ventilador(d):     # zumbido del portátil / cuarto
    t = np.arange(int(d*SR))/SR
    x = lp(rng.uniform(-1,1,len(t)).astype(np.float32), 260)
    x += np.sin(2*np.pi*118*t)*0.25 + np.sin(2*np.pi*236*t)*0.08
    am = 1 + 0.06*np.sin(2*np.pi*0.7*t)
    return (x*am).astype(np.float32)

def whoosh(d=0.55):
    n = int(d*SR); base = noise(d)
    x = lp(base,3200)-lp(base,520)
    e = np.linspace(0,1,n)**2
    return x*e + fsweep(280,1500,d)*e*0.16

def chime():
    d = 2.4; n = int(d*SR)
    x  = sine(659.25,d)*expdec(n,0.55)
    x += sine(988.9,d)*expdec(n,0.32)*0.34
    x += sine(1318.5,d)*expdec(n,0.2)*0.16
    y = x.copy()
    for dl,g in [(0.05,0.42),(0.105,0.28),(0.18,0.18),(0.28,0.1)]:
        k = int(dl*SR); y[k:] += x[:-k]*g
    return y*0.6

def ui_soft():
    d = 0.25; n = int(d*SR)
    return (sine(520,d)*expdec(n,0.05) + hp(noise(d),2200)*expdec(n,0.012)*0.35)*0.7

# ---------------- Música ----------------
def pad(freqs, d, cut=850, trem=0.10, rate=0.11):
    t = np.arange(int(d*SR))/SR
    x = np.zeros(len(t), dtype=np.float32)
    for f,g in freqs:
        x += (np.sin(2*np.pi*f*t)+0.32*np.sin(2*np.pi*f*1.004*t)).astype(np.float32)*g
    x *= (1 + trem*np.sin(2*np.pi*rate*t))
    return lp(x, cut)*0.3

def nota(f, d, g=1.0):
    n = int(d*SR)
    x = sine(f,d)*expdec(n,d*0.32) + sine(f*2,d)*expdec(n,d*0.16)*0.22
    return lp(x,2600)*g

G_SFX, G_MUS, G_VOZ = 0.30, 0.112, 0.82

# ===== BLOQUE 1 (0-12 s): SIN MÚSICA. Solo la habitación. =====
add(fade(ventilador(12.4), fi=0.6, fo=1.0), 0.0, 0.055)      # zumbido/room tone
add(bisagra(True),  0.10, G_SFX*0.55, -0.10)                 # abre la tapa
add(tecla(),        2.95, G_SFX*0.5,   0.06)
add(click(),        3.35, G_SFX*0.55,  0.08)                 # toca el trackpad
add(click(),        4.05, G_SFX*0.6,   0.05)                 # doble clic: abre la carpeta
add(click(),        4.17, G_SFX*0.6,   0.05)
add(whoosh(0.3)*0.5, 4.35, G_SFX*0.4)                        # se abre la ventana
for i,tt in enumerate([5.15, 5.75, 6.35]):                   # scroll entre 247 archivos
    for k in range(5):
        add(rueda(), tt+k*0.055, G_SFX*0.42, 0.04*(1 if i%2 else -1))
# 7.0-9.2 → SILENCIO (solo zumbido). Es el beat de la cara.
add(cierre(),       9.35, G_SFX*0.62, -0.06)                 # cierra el portátil
add(tela(0.6),      9.95, G_SFX*0.45,  0.10)
add(cuerpo(),      10.75, G_SFX*0.55,  0.04)                 # se acuesta
add(respiro(),     11.45, G_SFX*0.42, -0.05)                 # exhala

# ===== BLOQUE 2 (12-19 s): entra música muy sutil para leer =====
add(fade(pad([(110,0.5),(164.81,0.3),(196.0,0.2),(246.94,0.12)], 7.2, cut=700), fi=1.5, fo=1.0),
    12.10, G_MUS*0.72)

# ===== BLOQUE 3 (19-25 s): revelación cálida (La mayor) =====
add(whoosh(0.6), 18.85, G_SFX*0.8)
add(fade(pad([(110,0.52),(164.81,0.34),(220,0.26),(277.18,0.16),(329.63,0.1)], 6.3), fi=1.1, fo=1.4),
    18.95, G_MUS*1.05)
add(ui_soft(), 19.65, G_SFX*0.5)                             # sube el teléfono
add(nota(440.0, 2.0), 21.5, G_MUS*0.42)
add(chime(), 23.95, G_SFX*0.85)                              # logo
add(nota(220.0, 3.2, 0.8), 24.0, G_MUS*0.5)

# ===== VOZ =====
def load_wav(p):
    with wave.open(p,'rb') as w:
        nch, sw, sr, nfr = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nfr)
    a = np.frombuffer(raw, dtype=np.int16).astype(np.float32)/32768.
    if nch == 2: a = a.reshape(-1,2).mean(axis=1)
    return a

PLAN = [('v1.wav', 0.62)]     # "Hoy sí voy a estudiar."
ducks = []
for f,t in PLAN:
    p = os.path.join(VOZ,f)
    if not os.path.exists(p): print('FALTA',p); continue
    v = load_wav(p); v = v/(np.max(np.abs(v)) or 1.0)*0.92
    ducks.append((t, t+len(v)/SR))

# ducking del lecho mientras habla
bedmask = np.zeros(N, dtype=np.float32)
for a,b in ducks:
    ia, ib = idx(a), min(N, idx(b)); r = int(0.15*SR)
    bedmask[max(0,ia-r):ib+r] = 1.0
gain = 1.0 - 0.40*lp(bedmask, 6.0)
mix[:,0] *= gain; mix[:,1] *= gain

for f,t in PLAN:
    p = os.path.join(VOZ,f)
    if not os.path.exists(p): continue
    v = load_wav(p); v = v/(np.max(np.abs(v)) or 1.0)*0.92
    add(v, t, G_VOZ)

# ===== Master =====
mix[:,0] = fade(mix[:,0], fi=0.04, fo=1.1)
mix[:,1] = fade(mix[:,1], fi=0.04, fo=1.1)
peak = float(np.max(np.abs(mix)))
if peak > 0:
    mix *= 0.92/peak          # normaliza (conserva el contraste dinámico entre bloques)
mix = np.tanh(mix*1.05)*0.96

out = (np.clip(mix,-1,1)*32767).astype('<i2')
with wave.open(OUT,'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes())
print('OK ->', OUT, f'{os.path.getsize(OUT)/1024/1024:.2f} MB  pico={peak:.3f}')
