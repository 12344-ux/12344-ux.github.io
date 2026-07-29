#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Diseño sonoro + mezcla del anuncio de 45s "La hora que nunca cuenta como estudiar".
Sintetiza música y SFX (sin librerías de audio externas) y mezcla la voz de ElevenLabs
en los timestamps del guion. Niveles: voz > música > SFX.
"""
import numpy as np, wave, os, sys

SR = 44100
DUR = 45.0
N = int(SR * DUR)
OUT = '/projects/sandbox/voz/pista-final.wav'
VOZ = '/projects/sandbox/voz/wav'

rng = np.random.default_rng(7)
mix = np.zeros((N, 2), dtype=np.float32)

def idx(t): return int(round(t * SR))

def add(sig, t, gain=1.0, pan=0.0):
    """Suma una señal mono en el tiempo t (s) con ganancia y paneo (-1..1)."""
    s = np.asarray(sig, dtype=np.float32) * gain
    i = idx(t)
    if i >= N: return
    s = s[:max(0, N - i)]
    l = np.sqrt((1 - pan) / 2); r = np.sqrt((1 + pan) / 2)
    mix[i:i+len(s), 0] += s * l
    mix[i:i+len(s), 1] += s * r

def env(n, a=0.005, d=0.05, s_lvl=0.0, r=0.05, hold=None):
    """Envolvente ADSR simple."""
    e = np.zeros(n, dtype=np.float32)
    na, nd = int(a*SR), int(d*SR)
    nr = int(r*SR)
    ns = max(0, n - na - nd - nr)
    p = 0
    if na: e[p:p+na] = np.linspace(0,1,na); p += na
    if nd: e[p:p+nd] = np.linspace(1,s_lvl,nd); p += nd
    if ns: e[p:p+ns] = s_lvl; p += ns
    if nr: e[p:p+nr] = np.linspace(e[p-1] if p>0 else s_lvl, 0, nr)
    return e

def expdec(n, tau):
    return np.exp(-np.arange(n)/(tau*SR)).astype(np.float32)

def noise(dur):
    return rng.uniform(-1, 1, int(dur*SR)).astype(np.float32)

def lp(x, cut):
    """Lowpass one-pole."""
    a = np.exp(-2*np.pi*cut/SR)
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1-a)*x[i] + a*acc
        y[i] = acc
    return y

def lp_fast(x, cut):
    """Lowpass vectorizado aproximado (cascada de medias móviles)."""
    k = max(1, int(SR/(2*np.pi*cut)))
    if k <= 1: return x
    c = np.cumsum(np.concatenate(([0.0], x)))
    y = (c[k:] - c[:-k]) / k
    return np.concatenate((y, np.full(len(x)-len(y), y[-1] if len(y) else 0.0))).astype(np.float32)

def hp_fast(x, cut):
    return (x - lp_fast(x, cut)).astype(np.float32)

def sine(f, dur, phase=0.0):
    t = np.arange(int(dur*SR))/SR
    return np.sin(2*np.pi*f*t + phase).astype(np.float32)

def fsweep(f0, f1, dur):
    t = np.arange(int(dur*SR))/SR
    f = np.linspace(f0, f1, len(t))
    ph = 2*np.pi*np.cumsum(f)/SR
    return np.sin(ph).astype(np.float32)

# ---------------- SFX ----------------
def sfx_click(hard=1.0):
    n = int(0.035*SR)
    x = hp_fast(noise(0.035), 1800) * expdec(n, 0.006)
    x += sine(2600, 0.035) * expdec(n, 0.004) * 0.25
    return x * hard

def sfx_pop():
    n = int(0.09*SR)
    x = sine(720, 0.09) * expdec(n, 0.02)
    x += hp_fast(noise(0.09), 1200) * expdec(n, 0.008) * 0.5
    return x

def sfx_paper():
    d = 0.16; n = int(d*SR)
    x = hp_fast(noise(d), 2500) * (expdec(n, 0.05) * env(n, a=0.01, d=0.02, s_lvl=0.5, r=0.08))
    return x * 0.9

def sfx_swoosh(dur=0.35, up=True):
    n = int(dur*SR)
    base = noise(dur)
    x = lp_fast(base, 3000) - lp_fast(base, 600)      # banda media
    e = np.linspace(0,1,n)**2 if up else np.linspace(1,0,n)**2
    x = x * e * env(n, a=0.02, d=0.05, s_lvl=0.8, r=0.12)
    x += fsweep(300, 1400, dur) * e * 0.18 if up else fsweep(1400, 300, dur) * e * 0.18
    return x

def sfx_ping():
    d = 0.5; n = int(d*SR)
    x = sine(1050, d)*expdec(n,0.09) + sine(1560, d)*expdec(n,0.06)*0.5
    return x * 0.5

def sfx_blip():
    d = 0.07; n = int(d*SR)
    return (sine(1250, d)*expdec(n, 0.012) + sine(2500, d)*expdec(n,0.008)*0.3)

def sfx_flip():
    d = 0.22; n = int(d*SR)
    x = hp_fast(noise(d), 1500)*expdec(n,0.035)*0.7
    x += sine(520, d)*expdec(n,0.05)*0.35
    return x

def sfx_tap():
    d = 0.12; n = int(d*SR)
    return (sine(430, d)*expdec(n,0.03) + hp_fast(noise(d),2000)*expdec(n,0.01)*0.4)

def sfx_chime():
    """Chime de marca: una nota clara con cola de reverb."""
    d = 2.6; n = int(d*SR)
    x = sine(659.25, d)*expdec(n, 0.55)
    x += sine(988.9, d)*expdec(n, 0.35)*0.35     # quinta
    x += sine(1318.5, d)*expdec(n, 0.22)*0.18
    # cola tipo reverb (eco difuso)
    y = x.copy()
    for dl, g in [(0.055,0.45),(0.11,0.3),(0.19,0.2),(0.29,0.12)]:
        k = int(dl*SR); y[k:] += x[:-k]*g
    return y*0.6

def sfx_kick():
    d = 0.22; n = int(d*SR)
    return fsweep(110, 45, d)*expdec(n, 0.055)*0.9

# ---------------- MÚSICA ----------------
def drone(dur, base=55.0):
    """Textura fría y tensa (escenas 1-4)."""
    t = np.arange(int(dur*SR))/SR
    x  = np.sin(2*np.pi*base*t)
    x += np.sin(2*np.pi*(base*1.005)*t)*0.7
    x += np.sin(2*np.pi*(base*1.5)*t)*0.25
    trem = 1 + 0.18*np.sin(2*np.pi*0.09*t)
    return (x*trem).astype(np.float32)*0.33

def pad_major(dur):
    """Pad cálido en La mayor (escenas 5-6)."""
    t = np.arange(int(dur*SR))/SR
    freqs = [(110.0,0.50),(164.81,0.34),(220.0,0.26),(277.18,0.16),(329.63,0.10)]
    x = np.zeros(len(t), dtype=np.float32)
    for f,g in freqs:
        x += (np.sin(2*np.pi*f*t) + 0.35*np.sin(2*np.pi*f*1.004*t)).astype(np.float32)*g
    trem = 1 + 0.10*np.sin(2*np.pi*0.11*t)
    x = x*trem
    return lp_fast(x, 900)*0.32

def note(f, dur, g=1.0):
    n = int(dur*SR)
    x = sine(f, dur)*expdec(n, dur*0.35)
    x += sine(f*2, dur)*expdec(n, dur*0.18)*0.25
    return lp_fast(x, 2500)*g

def fade(sig, fin=0.0, fout=0.0):
    n = len(sig); s = sig.copy()
    if fin:
        k = int(fin*SR); k=min(k,n); s[:k] *= np.linspace(0,1,k)
    if fout:
        k = int(fout*SR); k=min(k,n); s[-k:] *= np.linspace(1,0,k)
    return s

# =========================================================
#  MONTAJE POR ESCENAS  (niveles: SFX ~-10dB=0.32, mus -18dB=0.126)
# =========================================================
G_SFX, G_MUS, G_VOZ = 0.30, 0.115, 0.80

# --- room tone (todo el spot, casi imperceptible) ---
rt = lp_fast(noise(DUR), 420)*0.010
add(rt, 0, 1.0)

# --- ESCENA 1 (0-5): silencio + clics ---
add(sfx_click(1.0), 1.25, G_SFX*0.85, -0.12)
add(sfx_click(1.0), 3.45, G_SFX*0.95,  0.10)
add(fade(drone(17.0), fin=2.2, fout=1.2), 3.0, G_MUS*0.75)   # tensión entra

# --- ESCENA 2 (5-10): ráfaga de interfaz + pulso ---
add(sfx_swoosh(0.30, True), 5.25, G_SFX*0.8, -0.15)   # abre PDF
add(sfx_click(), 6.05, G_SFX*0.7, 0.1); add(sfx_pop(), 6.12, G_SFX*0.55, 0.12)  # foto
add(sfx_paper(), 6.95, G_SFX*0.75, -0.2)              # cuaderno
add(sfx_swoosh(0.26, False), 7.75, G_SFX*0.7, 0.18)   # volver
add(sfx_ping(), 8.35, G_SFX*0.62, 0.22)               # notificación
add(sfx_click(), 9.15, G_SFX*0.7, -0.08); add(sfx_pop(), 9.22, G_SFX*0.5, -0.06)
# pulso 85 BPM desde 5.6 hasta 15.0, intensificando
bpm, t0, t1 = 85.0, 5.6, 15.0
beat = 60.0/bpm
tb = t0
while tb < t1:
    prog = (tb - t0)/(t1 - t0)
    add(sfx_kick(), tb, G_MUS*(0.55 + 0.85*prog))
    tb += beat

# --- ESCENA 3 (10-17): blips de texto + CORTE seco ---
for tq in [10.30, 11.40, 12.50, 13.60, 14.60]:
    add(sfx_blip(), tq, G_SFX*0.5, 0.0)
# (el pulso ya termina en 15.0 → silencio de shock 15.0-15.4)

# --- ESCENA 4 (17-23): interfaz lenta y "pesada" (pitch-down) + valle ---
add(sfx_swoosh(0.42, True)*0.8, 17.35, G_SFX*0.5, -0.1)
add(sfx_paper()*0.8, 18.75, G_SFX*0.45, 0.12)
add(sfx_click()*0.8, 19.85, G_SFX*0.45, -0.05)
add(fade(drone(4.6, base=48.0), fin=0.8, fout=2.2), 17.2, G_MUS*0.5)
# 20.6-23: prácticamente silencio (solo room tone) → el valle emocional

# --- ESCENA 5 (23-30): whoosh + pad cálido + UI limpia ---
add(sfx_swoosh(0.55, True), 22.85, G_SFX*0.85)
add(fade(pad_major(22.4), fin=1.4, fout=1.6), 22.9, G_MUS*1.0)
add(sfx_swoosh(0.22, True)*0.7, 23.85, G_SFX*0.45, 0.0)   # aparece la guía
add(sfx_tap(), 26.20, G_SFX*0.6)                           # botón "Empieza aquí"

# --- ESCENA 6A (30-38): 4 card-flips idénticos + melodía simple ---
for i, tc in enumerate([30.30, 31.30, 32.30, 33.30]):
    add(sfx_flip(), tc, G_SFX*0.5, (-0.12 if i % 2 else 0.12))
add(note(329.63, 2.2), 30.5, G_MUS*0.5)
add(note(440.00, 2.2), 32.4, G_MUS*0.42)
add(note(554.37, 2.6), 34.5, G_MUS*0.38)   # acompaña la frase clave

# --- ESCENA 6B (38-45): chime de logo + resolución + tap CTA ---
add(sfx_chime(), 38.30, G_SFX*0.85)
add(sfx_tap(), 40.15, G_SFX*0.5)
add(note(220.0, 6.0, 0.8), 38.4, G_MUS*0.55)      # resolución armónica
add(note(329.63, 5.6, 0.6), 38.6, G_MUS*0.4)

# =========================================================
#  VOZ (ElevenLabs) en los timestamps del guion
# =========================================================
def load_wav_mono(path):
    with wave.open(path,'rb') as w:
        nch, sw, sr, nfr = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nfr)
    a = np.frombuffer(raw, dtype=np.int16).astype(np.float32)/32768.0
    if nch == 2: a = a.reshape(-1,2).mean(axis=1)
    return a

# (archivo, t_inicio)
PLAN = [('01',  2.55), ('02',  5.60), ('03',  8.45), ('04', 15.40),
        ('05', 18.00), ('06', 20.45), ('07', 24.00), ('08', 26.80),
        ('09', 30.60), ('10', 34.40), ('11', 39.20)]

ducks = []   # tramos donde hay voz (para bajar música)
for name, t in PLAN:
    p = os.path.join(VOZ, name + '.wav')
    if not os.path.exists(p):
        print('FALTA', p); continue
    v = load_wav_mono(p)
    # normaliza cada línea a un pico consistente
    pk = np.max(np.abs(v)) or 1.0
    v = v/pk*0.92
    add(v, t, G_VOZ)
    ducks.append((t, t + len(v)/SR))

# --- ducking: la música/SFX bajan mientras habla la voz ---
# (aplicado sobre la mezcla previa a la voz sería lo ideal; aquí atenuamos
#  suavemente el lecho en esos tramos usando una curva de ganancia)
bed = np.zeros(N, dtype=np.float32)
for a,b in ducks:
    ia, ib = idx(a), min(N, idx(b))
    ramp = int(0.18*SR)
    bed[max(0,ia-ramp):ib+ramp] = 1.0
# suaviza la máscara
bed = lp_fast(bed, 6.0)
gain = 1.0 - 0.42*bed          # -4.7 dB aprox durante la voz
# La voz ya está sumada; para no atenuarla, reconstruimos: atenuamos todo y
# volvemos a sumar la voz al nivel pleno.
mix[:,0] *= gain; mix[:,1] *= gain
for name, t in PLAN:
    p = os.path.join(VOZ, name + '.wav')
    if not os.path.exists(p): continue
    v = load_wav_mono(p); pk = np.max(np.abs(v)) or 1.0
    v = v/pk*0.92
    i = idx(t); s = v[:max(0, N-i)]*G_VOZ*0.42   # compensa lo atenuado
    mix[i:i+len(s),0] += s; mix[i:i+len(s),1] += s

# --- fade final + limitador suave ---
mix[:,0] = fade(mix[:,0], fin=0.05, fout=1.5)
mix[:,1] = fade(mix[:,1], fin=0.05, fout=1.5)
peak = float(np.max(np.abs(mix)))
if peak > 0.98:
    mix *= (0.98/peak)
mix = np.tanh(mix*1.06)*0.965     # saturación muy suave (pegamento)

# --- escribe WAV 16-bit ---
out = (np.clip(mix, -1, 1)*32767).astype('<i2')
with wave.open(OUT,'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(out.tobytes())
print('OK ->', OUT, f'{os.path.getsize(OUT)/1024/1024:.2f} MB', f'pico={peak:.3f}')
