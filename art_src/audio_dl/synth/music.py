"""KASSEN music: taiko-driven battle layers (deploy / battle / intense, sample-aligned, same
tempo and length so the director can crossfade them), a shakuhachi/koto menu theme and stingers.

Everything is synthesised (instruments.py) except the shakuhachi tone, which is a CC0 single-note
recording (Wikimedia Commons "Shakuhachi-flute-440Hz.ogg") re-pitched and re-shaped per note.

python3 -E music.py [deploy battle intense menu stingers]
"""
import os, sys, time, zlib
import numpy as np
from dsp import *
from instruments import taiko, kane, koto, breath_flute, softclip, hyoshigi

HERE = os.path.dirname(os.path.abspath(__file__))
DL = os.path.dirname(HERE)
OUT = os.path.join(os.path.abspath(os.path.join(DL, '..', '..')), 'assets', 'audio', 'music')

BPM = 120.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 32
LOOP = BARS * BAR          # 64 s

# miyako-bushi on D: D Eb G A Bb ; yo on D: D E G A B
D4 = 293.66


def hz(semi_from_d4):
    return D4 * 2 ** (semi_from_d4 / 12)


IN = {'D': 0, 'Eb': 1, 'G': 5, 'A': 7, 'Bb': 8}
YO = {'D': 0, 'E': 2, 'G': 5, 'A': 7, 'B': 9}


def note(name, octave=0, scale=IN):
    return hz(scale[name] + 12 * octave)


# ------------------------------------------------------------------ hit banks (pre-rendered variations)
class Bank:
    def __init__(self):
        self.cache = {}

    def get(self, kind, vel, seed, pitch=1.0, rim=False):
        vb = int(round(vel * 4))
        key = (kind, vb, seed % 4, round(pitch, 3), rim)
        if key not in self.cache:
            self.cache[key] = taiko(kind, max(0.15, vb / 4), seed=zlib.crc32(repr(key).encode()) % 100000, pitch=pitch, rim=rim)
        return self.cache[key] * (vel / max(0.15, vb / 4)) ** 0.5


BANK = Bank()
_kane_cache = {}


def kane_hit(vel, damped, seed):
    k = (round(vel, 1), damped, seed % 3)
    if k not in _kane_cache:
        _kane_cache[k] = kane(1.0, damped, seed=seed % 3)
    return _kane_cache[k] * vel


# ------------------------------------------------------------------ shakuhachi from the CC0 sample
_SHAKU = None


def shaku_src():
    global _SHAKU
    if _SHAKU is None:
        x = mono(load(os.path.join(DL, 'commons', 'Shakuhachi-flute-440Hz.ogg'), 1 + 1))
        x = x[int(0.9 * SR):int(7.8 * SR)]
        # flatten the level of the sustain so our own envelope is in control
        w = int(0.25 * SR)
        e = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, mode='same')) + 1e-4
        _SHAKU = x / e * 0.2
    return _SHAKU


def shakuhachi_phrase(notes, dur, seed=0):
    """notes: dicts {t, f, len, vel, bend, fall}. Each note varispeeds the sample with
    attack bend, delayed vibrato, a breath swell and a muraiki chiff; adds a little of the
    additive breath model for air."""
    rng = np.random.default_rng(seed)
    src = shaku_src()
    n = int(dur * SR)
    y = np.zeros(n)
    for nt in notes:
        L = nt['len']; f = nt['f']
        m = int((L + 0.05) * SR)
        t = np.arange(m) / SR
        bend = nt.get('bend', 1.0)
        semis = -bend * np.clip(1 - t / 0.2, 0, 1) ** 2
        fall = nt.get('fall', 0.0)
        if fall:
            semis -= fall * np.clip((t - (L - 0.4)) / 0.4, 0, 1) ** 2
        vib = nt.get('vib', 0.006) * np.clip((t - 0.4) / 0.7, 0, 1) * np.sin(TAU * 5.0 * t + rng.uniform(0, TAU))
        ratio = (f / 440.0) * 2 ** (semis / 12) * (1 + vib)
        start = rng.uniform(0, 1.0) * SR
        pos = start + np.cumsum(ratio)
        if pos[-1] >= len(src) - 2:
            pos = start + (np.cumsum(ratio) % (len(src) - start - 2))  # (rarely) wrap for very long low notes
        s = np.interp(pos, np.arange(len(src)), src)
        att = 0.07
        e = np.minimum(1, t / att) ** 1.4 * np.clip((L - t) / min(0.3, L * 0.35), 0, 1) ** 1.3
        if L > 1.2:
            e *= 0.72 + 0.28 * np.sin(np.pi * np.clip(t / L, 0, 1)) ** 0.8   # komibuki-ish swell
        s *= e * nt.get('vel', 0.8)
        nz = rng.standard_normal(m)
        chiff = bandpass(nz, 1200, 7000, 2) * np.exp(-t / 0.035) * 0.35 * nt.get('vel', 0.8)
        air = bandpass(nz, 1800, 8000, 2) * e * 0.035
        a = int(nt['t'] * SR)
        seg = s + chiff + air
        k = min(len(seg), n - a)
        if k > 0:
            y[a:a + k] += seg[:k]
    return y * 0.5


# ------------------------------------------------------------------ drone
def drone(dur, freqs, seed=0, swell_period=16.0, cutoff=900.0):
    """Sustained bowed/voiced drone built directly in the frequency domain, so it is exactly
    periodic over `dur` (seamless loops) and cheap to compute."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR); t = np.arange(n) / SR
    y = np.zeros((n, 2))
    for c in range(2):
        X = np.zeros(n // 2 + 1, dtype=complex)
        for f in freqs:
            for det in (-0.06, 0.0, 0.055):
                ff = f * 2 ** ((det if c else -det) / 12)
                for h in range(1, 40):
                    fh = h * ff
                    if fh > cutoff * 3:
                        break
                    a = 1.0 / h ** 1.15 / np.sqrt(1 + (fh / cutoff) ** 4)
                    X[int(round(fh * n / SR))] += a * np.exp(1j * rng.uniform(0, TAU)) * n / 2
        # breathy band of noise around the voice formant
        f = np.fft.rfftfreq(n, 1 / SR)
        band = np.exp(-((f - 550) / 380) ** 2) * (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f)))
        X += band * np.abs(X).max() * 0.004
        y[:, c] = np.fft.irfft(X, n)
    sw = 0.6 + 0.4 * np.sin(TAU * t / swell_period - np.pi / 2) ** 2
    y *= sw[:, None]
    return y / (np.max(np.abs(y)) + 1e-9)


# ------------------------------------------------------------------ sequencing helpers
class Track:
    def __init__(self, L, name):
        self.buf = np.zeros((int(L * SR), 2))
        self.name = name

    def add(self, x, t, gain=1.0, p=0.0):
        mix_wrap(self.buf, pan(x, p) if x.ndim == 1 else stereo(x), t, gain)


def human(t, rng, ms=6):
    return t + rng.normal(0, ms / 1000)


def parse(pattern):
    """'X..x.X..' -> list of (step, vel). X=accent, x=normal, o=ghost, r=rim"""
    out = []
    for i, ch in enumerate(pattern.replace(' ', '')):
        if ch in 'Xxor':
            out.append((i, {'X': 1.0, 'x': 0.72, 'o': 0.42, 'r': 0.7}[ch], ch == 'r'))
    return out


# ------------------------------------------------------------------ battle score
NAGADO_A = ['X...x.X.X...x.x.', 'X...x.X.x.X.X...']
NAGADO_B = ['..x...X...x...X.', '..x.x...x...X.xx']
FILL = ['X.x.X.x.XxXxXXXX', 'X.xxX.xxX.xxXXXX']
NAG16 = ['XxoxXxoxXxoxXoXx', 'XoxxXoxxXxXoXxXX']


def battle_score(layer, seed=1):
    rng = np.random.default_rng(seed)
    dens = {'deploy': 0, 'battle': 1, 'intense': 2}[layer]
    tr = {k: Track(LOOP, k) for k in ['odaiko', 'nagado', 'shime', 'kane', 'flute', 'drone', 'koto', 'voice']}
    s16 = BAR / 16
    for bar in range(BARS):
        t0 = bar * BAR
        phrase_pos = bar % 8
        is_fill = phrase_pos == 7
        is_peak = bar % 16 == 15
        # ---------------- odaiko
        if dens == 0:
            tr['odaiko'].add(BANK.get('odaiko', 0.75, bar), human(t0, rng), 1.0, 0.0)
            if bar % 2 == 1:
                tr['odaiko'].add(BANK.get('odaiko', 0.45, bar + 1), human(t0 + 3.5 * BEAT, rng), 0.8, 0.0)
            if is_fill:
                for k, b in enumerate([2.0, 2.5, 3.0]):
                    tr['odaiko'].add(BANK.get('odaiko', 0.5 + 0.12 * k, k), human(t0 + b * BEAT, rng), 0.9, 0.0)
        else:
            beats = [0, 2] if dens == 1 else [0, 1, 2, 3]
            for b in beats:
                v = 1.0 if b == 0 else (0.8 if b == 2 else 0.62)
                tr['odaiko'].add(BANK.get('odaiko', v, bar * 4 + b), human(t0 + b * BEAT, rng), 1.0, 0.0)
            if dens == 2 and (bar % 2 == 1):
                tr['odaiko'].add(BANK.get('odaiko', 0.55, bar), human(t0 + 3.5 * BEAT, rng), 0.8, 0.0)
        # ---------------- nagado (two players L/R; a third in intense)
        if dens >= 1:
            pats = [(NAGADO_A, -0.45), (NAGADO_B, 0.45)]
            if dens == 2:
                pats.append((NAG16, 0.0))
            for pi, (pset, pn) in enumerate(pats):
                pat = FILL[bar % 2] if is_fill else pset[(bar // 2) % len(pset)]
                if dens == 2 and pi == 2 and not is_fill and phrase_pos < 2:
                    continue  # leave room at phrase start
                for step, v, rim in parse(pat):
                    vv = v * rng.uniform(0.9, 1.05)
                    tt = human(t0 + step * s16, rng, 5)
                    tr['nagado'].add(BANK.get('nagado', vv, step + pi, pitch=[1.0, 0.94, 1.06][pi], rim=rim), tt, 0.75, pn + rng.uniform(-0.05, 0.05))
        elif phrase_pos in (3, 7):
            # deploy: distant nagado pulse answering the odaiko
            for step, v, rim in parse('....x.......o.x.'):
                tr['nagado'].add(BANK.get('nagado', v * 0.7, step), human(t0 + step * s16, rng), 0.5, -0.3)
        # ---------------- shime: ji-uchi 8ths (battle), 16ths with accents (intense)
        if dens >= 1:
            grid = 8 if dens == 1 else 16
            for k in range(grid):
                step_t = t0 + k * BAR / grid
                acc = (k % (grid // 4) == 0)
                v = 0.85 if acc else 0.5
                if dens == 2 and k % 2 == 1:
                    v = 0.38
                if is_fill and k >= grid // 2:
                    v = 0.4 + 0.5 * (k - grid // 2) / (grid // 2)
                tr['shime'].add(BANK.get('shime', v, k), human(step_t, rng, 3), 0.55, 0.25 + 0.1 * (k % 2))
        elif bar % 4 == 2:
            for k in range(4):
                tr['shime'].add(BANK.get('shime', 0.3 + 0.08 * k, k), human(t0 + (2 + k * 0.5) * BEAT, rng, 3), 0.4, 0.3)
        # ---------------- kane: chan-chiki
        if dens >= 1:
            for k in range(8):
                tt = t0 + k * BEAT / 2
                if k % 4 == 0:
                    tr['kane'].add(kane_hit(0.55, False, k), human(tt, rng, 4), 0.5, -0.2)
                elif k % 2 == 1 or dens == 2:
                    tr['kane'].add(kane_hit(0.5, True, k), human(tt, rng, 4), 0.45, -0.2)
        elif bar % 8 == 0:
            tr['kane'].add(kane_hit(0.4, False, bar), t0, 0.35, -0.3)
        # ---------------- kakegoe shouts on fills / peaks
        if dens >= 1 and (is_fill or is_peak):
            tr['voice'].events = getattr(tr['voice'], 'events', [])
            tr['voice'].events.append(t0 + 3.5 * BEAT)
            if dens == 2:
                tr['voice'].events.append(t0 + 1.5 * BEAT)
    # ---------------- unison accents every 16 bars (battle/intense): big hit on the downbeat after peak
    if dens >= 1:
        for bar in (0, 16):
            t0 = bar * BAR
            for p in (-0.4, 0.4):
                tr['nagado'].add(BANK.get('nagado', 1.0, bar + int(p * 10)), t0, 0.6, p)
            tr['kane'].add(kane_hit(0.8, False, 7), t0, 0.5, 0.0)
    # ---------------- drone (all layers; quieter as drums take over)
    tr['drone'].add(drone(LOOP, [note('D', -2), note('A', -2)], seed=5, swell_period=BAR * 8), 0.0, [0.4, 0.35, 0.3][dens])
    # ---------------- melody
    melody_bars = {0: [2, 10, 18, 26], 1: [8, 24], 2: [0, 8, 16, 24]}[dens]
    for mb in melody_bars:
        t0 = mb * BAR
        if dens == 0:
            ph = shaku_line(t0, rng, variant=mb // 8)
            tr['flute'].add(ph, 0.0, 0.9, -0.15)
        else:
            ph = fue_line(t0, rng, variant=(mb // 8) % 2, busy=dens == 2)
            tr['flute'].add(ph, 0.0, 0.55 if dens == 1 else 0.6, 0.2)
    # ---------------- koto (deploy) : sparse motif echoes
    if dens == 0:
        motif = [('D', 0), ('A', 0), ('Bb', 0), ('A', 0), ('D', 1)]
        for b in (0, 8, 16, 24):
            for k, (nm, o) in enumerate(motif):
                tt = (b + 6) * BAR + k * BEAT * 0.75
                tr['koto'].add(koto(note(nm, o - 1), 2.4, 0.7, seed=b + k), human(tt, rng, 10), 0.8, 0.35)
    return tr


def shaku_line(t0, rng, variant=0):
    """slow, sparse shakuhachi phrase spanning ~6 bars, miyako-bushi with meri bends"""
    lines = [
        [('A', 0, 2.5, 1.0), ('Bb', 0, 1.0, 0.6), ('A', 0, 3.0, 0.4), ('G', 0, 1.5, 1.0), ('A', 0, 4.0, 0.3, 0.8)],
        [('D', 1, 3.0, 1.2), ('Eb', 1, 1.0, 0.5), ('D', 1, 2.0, 0.4), ('Bb', 0, 1.5, 1.0), ('A', 0, 4.5, 0.5, 1.0)],
        [('G', 0, 2.0, 1.0), ('A', 0, 1.0, 0.5), ('Bb', 0, 2.5, 0.5), ('A', 0, 1.0, 0.4), ('G', 0, 1.0, 0.4), ('D', 0, 4.5, 1.0, 0.7)],
        [('A', 0, 3.0, 1.0), ('D', 1, 2.0, 1.0), ('Eb', 1, 1.0, 0.5), ('D', 1, 3.5, 0.4, 1.0)],
    ][variant % 4]
    notes = []
    t = t0
    for item in lines:
        nm, o, beats, bend = item[:4]
        fall = item[4] if len(item) > 4 else 0.0
        L = beats * BEAT * 2   # half-time feel
        notes.append({'t': t - t0 + 0.05, 'f': note(nm, o), 'len': L * 0.97, 'vel': rng.uniform(0.7, 0.85), 'bend': bend, 'fall': fall})
        t += L
    y = shakuhachi_phrase(notes, t - t0 + 1.0, seed=int(t0))
    return place_in_loop(y, t0)


def fue_line(t0, rng, variant=0, busy=False):
    """shinobue line over 8 bars: brisk, ornamented, upper register"""
    seq = [
        [('D', 2, 1), ('A', 1, .5), ('Bb', 1, .5), ('A', 1, 1), ('G', 1, 1), ('A', 1, 2), ('D', 2, 1), ('Eb', 2, 1),
         ('D', 2, 2), ('Bb', 1, 1), ('A', 1, 1), ('G', 1, 1.5), ('A', 1, .5), ('D', 1, 4)],
        [('A', 1, 1), ('D', 2, 1), ('Eb', 2, .5), ('D', 2, .5), ('Bb', 1, 1), ('A', 1, 2), ('G', 1, 1), ('A', 1, 1),
         ('Bb', 1, 1), ('D', 2, 3), ('Bb', 1, .5), ('A', 1, .5), ('G', 1, 1), ('A', 1, 4)],
    ][variant]
    notes = []
    t = 0.0
    for nm, o, beats in seq:
        L = beats * BEAT * (1 if busy else 2) * 0.5 * 2
        notes.append({'t': t, 'f': note(nm, o - 1), 'len': L * 0.92, 'vel': rng.uniform(0.7, 0.9),
                      'bend': 0.6 if L > BEAT else 0.0, 'vib': 0.006 if L > BEAT else 0.0})
        t += L
    y = breath_flute(notes, t + 1.0, 'fue', seed=int(t0) + 3)
    return place_in_loop(y, t0)


def place_in_loop(y, t0):
    buf = np.zeros((int(LOOP * SR), 2))
    mix_wrap(buf, stereo(y), t0)
    return buf


def kakegoe(rng):
    """short 'Ha!'/'Sore!'-like shout from the CC0 yell recordings"""
    import glob
    fs = sorted(glob.glob(os.path.join(DL, 'oga_male_yelling/x/yelling sounds/*yell*.wav')))
    x = load(fs[rng.integers(len(fs))], 2)
    x = trim(x, -35)
    x = x[:int(rng.uniform(0.28, 0.4) * SR)]
    x = resample(x, rng.uniform(0.95, 1.05))
    return fade(x / (np.max(np.abs(x)) + 1e-9), 0.003, 0.08)


# ------------------------------------------------------------------ mix & master
def mixdown(tr, target_lufs, layer, seed=0):
    rng = np.random.default_rng(seed)
    hall = make_ir(t60=2.3, predelay=0.025, early=12, damp_hf=0.35, size=1.8, seed=101, bright=5000)
    long = make_ir(t60=3.4, predelay=0.04, early=8, damp_hf=0.3, size=2.4, seed=102, bright=4500)
    gains = {'odaiko': 1.0, 'nagado': 0.85, 'shime': 0.5, 'kane': 0.4, 'flute': 0.6, 'drone': 0.32, 'koto': 0.5, 'voice': 0.4}
    wets = {'odaiko': 0.22, 'nagado': 0.2, 'shime': 0.15, 'kane': 0.25, 'flute': 0.35, 'drone': 0.3, 'koto': 0.3, 'voice': 0.3}
    if hasattr(tr['voice'], 'events'):
        for t in tr['voice'].events:
            tr['voice'].add(kakegoe(rng), human(t, rng, 15), 0.8, rng.uniform(-0.4, 0.4))
    out = np.zeros((int(LOOP * SR), 2))
    for k, t in tr.items():
        x = t.buf
        if not np.any(x):
            continue
        # per-stem tone
        if k == 'odaiko':
            x = highpass(x, 38, 2)
        if k == 'nagado':
            x = peak_eq(x, 2500, 2.0, 0.8)
        if k == 'drone':
            x = highpass(x, 65, 2)
        x = x / (np.max(np.abs(x)) + 1e-9)
        ir = long if k in ('flute', 'drone', 'koto') else hall
        x = reverb_loop(x, ir, wets[k], 1.0)
        out += x * gains[k]
    out = highpass(out, 32, 3)
    # gentle bus 'glue': soft saturation on the sum
    out = softclip(out / (np.max(np.abs(out)) + 1e-9) * 1.1, 1.2) * 0.9
    out = normalize_lufs(out, target_lufs, -1.0)
    return out


def write(name, x, target=-16.0):
    path = os.path.join(OUT, name + '.ogg')
    I, TP = save_checked(path, x, target)
    seam, step = loop_seam_report(x)
    print(f'  music/{name}.ogg {len(x)/SR:.1f}s  I {I:.1f} LUFS  TP {TP:.1f}  seam {seam:.4f} (mean step {step:.4f})', flush=True)


# ------------------------------------------------------------------ menu theme
def menu():
    rng = np.random.default_rng(77)
    bpm = 66.0; beat = 60 / bpm; bar = 4 * beat
    nbars = 20
    L = nbars * bar
    koto_tr = np.zeros((int(L * SR), 2)); fl = np.zeros_like(koto_tr); dr = np.zeros_like(koto_tr); dk = np.zeros_like(koto_tr)
    # koto ostinato: 8ths, two-bar cells over a slow harmonic cycle
    cells = [[('D', 0), ('A', 0), ('Bb', 0), ('D', 1), ('A', 0), ('Bb', 0), ('A', 0), ('G', 0)],
             [('D', 0), ('G', 0), ('A', 0), ('Bb', 0), ('A', 0), ('G', 0), ('Eb', 0), ('D', 0)],
             [('G', -1), ('D', 0), ('Eb', 0), ('G', 0), ('A', 0), ('G', 0), ('Eb', 0), ('D', 0)],
             [('A', -1), ('D', 0), ('A', 0), ('Bb', 0), ('A', 0), ('D', 1), ('Bb', 0), ('A', 0)]]
    for b in range(nbars):
        cell = cells[(b // 2) % 4]
        sparse = b < 2 or b >= nbars - 1
        for k, (nm, o) in enumerate(cell):
            if sparse and k % 2:
                continue
            t = b * bar + k * beat / 2
            v = 0.75 if k % 4 == 0 else 0.55
            bend = 1.0 if (nm == 'Bb' and rng.random() < 0.3) else 0.0
            mix_wrap(koto_tr, pan(koto(note(nm, o - 1), 2.8, v, seed=b * 8 + k, bend=bend * 0.0, pluck_pos=0.18 + 0.05 * rng.random()), 0.25 if o <= 0 else 0.4),
                     human(t, rng, 8))
        if b % 4 == 0:  # bass string on the cycle
            mix_wrap(koto_tr, pan(koto(note('D', -2), 4.0, 0.8, seed=900 + b), 0.1), b * bar)
    # shakuhachi melody (enters bar 4, rests, returns)
    phrases = [(4, [('A', 0, 3, 1.0), ('Bb', 0, 1, .5), ('A', 0, 2, .4), ('G', 0, 2, 1.0, 0.0), ('A', 0, 6, .4, 0.7)]),
               (9, [('D', 1, 3, 1.2), ('Eb', 1, 1, .6), ('D', 1, 2, .4), ('Bb', 0, 2, 1.0), ('A', 0, 2, .5), ('G', 0, 2, .4), ('A', 0, 5, .5, 1.0)]),
               (15, [('G', 0, 2, 1.0), ('A', 0, 2, .6), ('Bb', 0, 2, .5), ('A', 0, 1, .4), ('G', 0, 1, .4), ('D', 0, 7, 1.0, 0.0)])]
    for b0, line in phrases:
        notes = []; t = 0.0
        for item in line:
            nm, o, beats, bend = item[:4]; fall = item[4] if len(item) > 4 else 0.0
            Ln = beats * beat
            notes.append({'t': t + 0.05, 'f': note(nm, o), 'len': Ln * 0.96, 'vel': rng.uniform(0.72, 0.85), 'bend': bend, 'fall': fall})
            t += Ln
        y = shakuhachi_phrase(notes, t + 1.0, seed=b0)
        mix_wrap(fl, pan(y, -0.15), b0 * bar)
    mix_wrap(dr, drone(L, [note('D', -2), note('A', -2)], seed=8, swell_period=bar * 4, cutoff=700), 0.0)
    for b in range(0, nbars, 2):  # distant odaiko heartbeat
        mix_wrap(dk, stereo(taiko('odaiko', 0.45, seed=b)), b * bar)
    long = make_ir(t60=3.8, predelay=0.04, early=8, damp_hf=0.3, size=2.4, seed=103, bright=4500)
    mixd = (reverb_loop(koto_tr / (np.max(np.abs(koto_tr)) + 1e-9), long, 0.35) * 0.55 +
            reverb_loop(fl / (np.max(np.abs(fl)) + 1e-9), long, 0.45) * 0.7 +
            reverb_loop(dr, long, 0.3) * 0.18 +
            reverb_loop(lowpass(dk, 600) / (np.max(np.abs(dk)) + 1e-9), long, 0.35) * 0.3)
    mixd = normalize_lufs(highpass(mixd, 35, 2), -16.0, -1.0)
    write('music_menu', mixd, -16.0)


# ------------------------------------------------------------------ stingers
def stingers():
    rng = np.random.default_rng(99)
    hall = make_ir(t60=2.8, predelay=0.03, early=10, damp_hf=0.33, size=2.0, seed=104, bright=5000)
    # victory: shime roll crescendo -> unison hit -> fue yo-scale flourish -> don don DON
    L = 9.0
    buf = np.zeros((int(L * SR), 2))
    t = 0.0
    k = 0
    while t < 1.25:
        v = 0.25 + 0.7 * t / 1.25
        mix_at(buf, pan(taiko('shime', v, seed=k), 0.2 * (k % 2 * 2 - 1)), t, 0.6)
        t += 0.11 - 0.06 * t / 1.25
        k += 1
    for p in (-0.4, 0.0, 0.4):
        mix_at(buf, pan(taiko('nagado', 1.0, seed=int(p * 10) + 5), p), 1.3, 0.8)
    mix_at(buf, stereo(taiko('odaiko', 1.0, seed=3)), 1.3, 1.0)
    mix_at(buf, stereo(kane(0.9, False, seed=1)), 1.3, 0.5)
    yo = [('D', 1, .25), ('E', 1, .25), ('G', 1, .25), ('A', 1, .5), ('B', 1, .25), ('A', 1, .25), ('D', 2, 1.8)]
    notes = []; tt = 0.0
    for nm, o, d in yo:
        notes.append({'t': tt, 'f': note(nm, o - 1, YO), 'len': d * 0.95, 'vel': 0.85, 'bend': 0.0 if d < 0.5 else 0.7})
        tt += d
    fue = breath_flute(notes, tt + 1.0, 'fue', seed=7)
    mix_at(buf, pan(fue, 0.15), 1.55, 0.9)
    for i, (tt, v) in enumerate([(4.6, 0.8), (5.1, 0.85), (5.6, 1.0)]):
        mix_at(buf, stereo(taiko('odaiko', v, seed=10 + i)), tt, 1.0)
        for p in (-0.4, 0.4):
            mix_at(buf, pan(taiko('nagado', v, seed=20 + i + int(p * 10)), p), tt, 0.7)
    mix_at(buf, stereo(kane(1.0, False, seed=2)), 5.6, 0.55)
    y = reverb(buf, hall, 0.3)[:int(L * SR)]
    y = fade(y, 0.0, 1.5)
    write('stinger_victory', normalize_lufs(highpass(y, 32, 2), -15.0, -1.0), -15.0)
    # defeat: two slow, low odaiko strokes, shakuhachi falling line (meri), drone, damped kane
    L = 10.0
    buf = np.zeros((int(L * SR), 2))
    for i, tt in enumerate([0.0, 1.6]):
        mix_at(buf, stereo(taiko('odaiko', 0.9 - 0.2 * i, seed=30 + i, pitch=0.88)), tt, 1.0)
    line = [('A', 0, 1.2, 1.0), ('G', 0, 0.8, .6), ('Eb', 0, 1.6, 1.2), ('D', 0, 4.0, 1.0, 1.2)]
    notes = []; tt = 0.0
    for item in line:
        nm, o, d, bend = item[:4]
        notes.append({'t': tt + 0.05, 'f': note(nm, o), 'len': d * 0.97, 'vel': 0.75, 'bend': bend, 'fall': item[4] if len(item) > 4 else 0})
        tt += d
    mix_at(buf, pan(shakuhachi_phrase(notes, tt + 1.0, seed=31), -0.1), 0.8, 1.1)
    dr = drone(L, [note('D', -2)], seed=9, swell_period=L * 2, cutoff=500) * env_adsr(int(L * SR), 1.0, 0.5, 0.8, 4.0)[:, None]
    buf += dr * 0.25
    mix_at(buf, stereo(kane(0.5, True, seed=2)), 7.8, 0.4)
    y = reverb(buf, hall, 0.35)[:int(L * SR)]
    write('stinger_defeat', normalize_lufs(highpass(fade(y, 0, 2.0), 32, 2), -17.0, -1.0), -17.0)
    # general fallen: three heavy strokes slowing down + open kane
    L = 6.0
    buf = np.zeros((int(L * SR), 2))
    for i, tt in enumerate([0.0, 0.7, 1.6]):
        mix_at(buf, stereo(taiko('odaiko', 1.0 - 0.1 * i, seed=40 + i, pitch=0.95)), tt, 1.0)
        mix_at(buf, pan(taiko('nagado', 0.9, seed=50 + i), -0.3 + 0.3 * i), tt, 0.6)
    mix_at(buf, stereo(kane(0.9, False, seed=0)), 1.6, 0.5)
    y = reverb(buf, hall, 0.32)[:int(L * SR)]
    write('stinger_general_fallen', normalize_lufs(highpass(fade(y, 0, 1.5), 32, 2), -16.0, -1.0), -16.0)


def battle_layers(which):
    targets = {'deploy': -17.0, 'battle': -16.0, 'intense': -15.5}
    for layer in which:
        t0 = time.time()
        tr = battle_score(layer, seed=11)
        x = mixdown(tr, targets[layer], layer, seed=12)
        write('music_' + layer, x, targets[layer])
        print(f'   [{layer}] {time.time() - t0:.0f}s', flush=True)


if __name__ == '__main__':
    want = sys.argv[1:] or ['deploy', 'battle', 'intense', 'menu', 'stingers']
    layers = [w for w in want if w in ('deploy', 'battle', 'intense')]
    if layers:
        battle_layers(layers)
    if 'menu' in want:
        menu()
    if 'stingers' in want:
        stingers()
