"""Synthesised Japanese instruments for KASSEN (numpy only).

taiko family (odaiko / nagado / shime) : modal membrane synthesis with pitch-glide, stick noise and shell click
kane (atarigane)                       : inharmonic metallic partials
hyoshigi                               : clapper sticks (two hard-wood bars)
koto                                   : additive plucked string with pluck-position comb, inharmonicity and body
breath flutes (shakuhachi / shinobue)  : additive harmonics + harmonic-locked breath noise (STFT), vibrato, bends
horagai                                : lip-buzz source through conch formants, roughness and overblow breaks
voices                                 : shouted male voice formant synth for "ei-ei-oh" crowds
"""
import numpy as np
from dsp import SR, TAU, lowpass, highpass, bandpass, formant_filter, fade, stereo

# ------------------------------------------------------------------ helpers
def _t(dur):
    return np.arange(int(dur * SR)) / SR


def _noise(n, rng):
    return rng.standard_normal(n)


def _glide_phase(t, f0, bend, tau):
    """phase of f(t) = f0 * (1 + bend*exp(-t/tau))"""
    return TAU * (f0 * t + f0 * bend * tau * (1 - np.exp(-t / tau)))


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# ------------------------------------------------------------------ taiko family
TAIKO = {
    # f0, ratios, amps, decays (s), bend, bend tau, noise lp, click centre, dur
    'odaiko': dict(f0=58, ratios=[1, 1.47, 1.98, 2.52, 3.03, 3.61], amps=[1, .45, .30, .16, .09, .05],
                   decays=[1.6, .75, .45, .28, .18, .12], bend=.42, btau=.045, thump=180, click=1500, dur=2.6, drive=1.4),
    'nagado': dict(f0=118, ratios=[1, 1.50, 1.99, 2.47, 2.96, 3.5], amps=[1, .5, .35, .2, .12, .07],
                   decays=[.75, .38, .24, .16, .1, .07], bend=.30, btau=.03, thump=320, click=2200, dur=1.4, drive=1.6),
    'okedo': dict(f0=165, ratios=[1, 1.56, 2.1, 2.6, 3.2], amps=[1, .55, .35, .2, .1],
                  decays=[.42, .22, .14, .09, .06], bend=.22, btau=.02, thump=450, click=2600, dur=.9, drive=1.5),
    'shime': dict(f0=392, ratios=[1, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.5], amps=[1, .7, .5, .45, .35, .3, .2, .15],
                  decays=[.16, .1, .075, .07, .055, .05, .04, .035], bend=.08, btau=.012, thump=900, click=4200, dur=.5, drive=1.2),
}


def taiko(kind='nagado', vel=1.0, seed=0, pitch=1.0, rim=False):
    """One hit. vel 0..1 drives level, brightness and pitch glide."""
    p = TAIKO[kind]
    rng = np.random.default_rng(seed)
    t = _t(p['dur'])
    n = len(t)
    f0 = p['f0'] * pitch * (1 + rng.uniform(-0.012, 0.012))
    y = np.zeros(n)
    bright = 0.35 + 0.65 * vel
    for k, (r, a, d) in enumerate(zip(p['ratios'], p['amps'], p['decays'])):
        amp = a * (bright ** (k * 0.8)) * (1 + rng.uniform(-0.15, 0.15))
        dec = d * (0.85 + 0.3 * vel) * rng.uniform(0.92, 1.08)
        ph = _glide_phase(t, f0 * r * (1 + rng.uniform(-0.01, 0.01) * (k > 0)), p['bend'] * (0.5 + 0.7 * vel), p['btau'])
        y += amp * np.sin(ph + rng.uniform(0, TAU) * (k > 0)) * np.exp(-t / dec)
    # soft attack (a few ms) so the fundamental 'blooms'
    y *= 1 - np.exp(-t / 0.0015)
    # head thump: low-passed noise burst
    nz = _noise(n, rng)
    thump = lowpass(nz, p['thump'], 2) * np.exp(-t / 0.022) * 1.6
    # bachi click: band noise, very short
    click = bandpass(nz, p['click'] * 0.5, p['click'] * 2.2, 2) * np.exp(-t / 0.0035) * (0.12 + 0.5 * vel ** 2)
    y = y + thump * (0.4 + 0.6 * vel) + click
    if rim:  # kara / fuchi rim hit: wood click only
        y = bandpass(nz, 900, 4500, 2) * np.exp(-t / 0.006) * 0.8 + 0.25 * y * np.exp(-t / 0.03)
    y = softclip(y * 0.6, p['drive'])
    return fade(y * vel ** 0.9, 0.0, 0.05)


def kane(vel=1.0, damped=False, seed=0, f0=1180.0):
    rng = np.random.default_rng(seed)
    dur = 0.25 if damped else 1.6
    t = _t(dur)
    ratios = [1, 2.32, 2.97, 4.25, 5.41, 6.63, 8.1]
    amps = [1, .7, .35, .5, .25, .2, .1]
    decs = [1.1, .7, .5, .4, .25, .18, .1]
    y = np.zeros(len(t))
    for r, a, d in zip(ratios, amps, decs):
        if damped:
            d = min(d, 0.045)
        y += a * np.sin(TAU * f0 * r * (1 + rng.uniform(-.004, .004)) * t + rng.uniform(0, TAU)) * np.exp(-t / d)
    y += highpass(_noise(len(t), rng), 3000, 2) * np.exp(-t / 0.002) * 0.6
    return fade(y * 0.35 * vel, 0, 0.02)


def hyoshigi(vel=1.0, seed=0, f0=2050.0, room=None):
    """Two hard-wood clappers: two slightly detuned bars struck together."""
    rng = np.random.default_rng(seed)
    t = _t(0.35)
    y = np.zeros(len(t))
    for bar in range(2):
        fb = f0 * (1 + 0.035 * (bar - 0.5) + rng.uniform(-0.01, 0.01))
        off = int(rng.uniform(0, 0.0006) * SR)
        for r, a, d in zip([1, 2.76, 5.40, 8.93], [1, .55, .25, .1], [.055, .028, .014, .008]):
            s = a * np.sin(TAU * fb * r * t) * np.exp(-t / d)
            y[off:] += s[:len(t) - off]
    nz = _noise(len(t), rng)
    y += bandpass(nz, 1200, 9000, 2) * np.exp(-t / 0.0018) * 1.4
    # low 'knock' of the wood body
    y += np.sin(TAU * 410 * t) * np.exp(-t / 0.012) * 0.35
    return fade(y * vel * 0.5, 0, 0.03)


# ------------------------------------------------------------------ koto
def koto(f0, dur=2.6, vel=0.8, seed=0, bend=0.0, bend_at=0.25, pluck_pos=0.2):
    rng = np.random.default_rng(seed)
    t = _t(dur)
    n = len(t)
    B = 1.2e-4
    # pitch curve: optional oshi-de bend (press string behind bridge) after `bend_at`
    semis = bend * np.clip((t - bend_at) / 0.12, 0, 1) ** 1.5
    fcurve = f0 * 2 ** (semis / 12)
    phase_base = TAU * np.cumsum(fcurve) / SR
    y = np.zeros(n)
    for h in range(1, 28):
        fh = h * f0 * np.sqrt(1 + B * h * h)
        if fh > 15000:
            break
        a = abs(np.sin(h * np.pi * pluck_pos)) / h ** (1.05 - 0.25 * vel)
        tau = 2.2 / (1 + 0.22 * (h - 1) ** 1.25) * (180.0 / f0) ** 0.35
        y += a * np.sin(phase_base * h * np.sqrt(1 + B * h * h) + rng.uniform(0, TAU)) * np.exp(-t / tau)
    # plectrum (tsume) click
    nz = _noise(n, rng)
    y += highpass(nz, 2500, 2) * np.exp(-t / 0.0025) * 0.25 * vel
    # paulownia body: a few short resonances excited by the string (approximate: add damped modes scaled by attack)
    body = sum(a * np.sin(TAU * fb * t) * np.exp(-t / d) for fb, a, d in [(210, .3, .05), (380, .25, .04), (690, .15, .03), (1150, .08, .02)])
    y = y + body * 0.6
    y *= 1 - np.exp(-t / 0.0008)
    return fade(y * vel * 0.35, 0, 0.08)


# ------------------------------------------------------------------ breath flutes
def _pitch_curve(t, notes, glide=0.06):
    """notes: list of (start, freq). Returns per-sample frequency with portamento."""
    f = np.full(len(t), notes[0][1], dtype=float)
    for i, (st, fr) in enumerate(notes):
        prev = notes[i - 1][1] if i else fr
        k = np.clip((t - st) / glide, 0, 1)
        k = k * k * (3 - 2 * k)
        m = t >= st
        f[m] = prev * (fr / prev) ** k[m]
    return f


def breath_flute(notes, dur, kind='shakuhachi', seed=0, vib_depth=None, level_curve=None):
    """notes: list of dicts {t, f, len, vel, bend(semitones from below at attack), vib}
    Phrase-level synthesis so legato, breath and vibrato are continuous between notes."""
    rng = np.random.default_rng(seed)
    t = _t(dur)
    n = len(t)
    shaku = kind == 'shakuhachi'
    harm_amps = [1, .42, .22, .16, .08, .06, .035, .02] if shaku else [1, .28, .1, .06, .03]
    # pitch curve and amplitude envelope assembled from the notes
    f = np.zeros(n); amp = np.zeros(n); vib = np.zeros(n)
    base = notes[0]['f']
    f[:] = base
    for i, nt in enumerate(notes):
        a = int(nt['t'] * SR); b = min(n, int((nt['t'] + nt['len']) * SR))
        if a >= n:
            continue
        seg_t = t[a:b] - nt['t']
        L = nt['len']
        bend = nt.get('bend', 0.0)
        # attack bend (meri -> kari) over 0.12-0.25 s
        bt = 0.18 if shaku else 0.07
        fseg = nt['f'] * 2 ** ((-bend * np.clip(1 - seg_t / bt, 0, 1) ** 2) / 12)
        # optional end fall (shakuhachi 'otoshi')
        fall = nt.get('fall', 0.0)
        if fall:
            fseg *= 2 ** (-fall * np.clip((seg_t - (L - 0.35)) / 0.35, 0, 1) ** 2 / 12)
        f[a:b] = fseg
        if b < n:
            f[b:] = fseg[-1] if len(fseg) else nt['f']
        att = 0.09 if shaku else 0.04
        rel = min(0.25, L * 0.3)
        e = np.minimum(1, seg_t / att) ** 1.3 * np.clip((L - seg_t) / rel, 0, 1) ** 1.2
        # shakuhachi swell (crescendo) on long notes
        if shaku and L > 1.0:
            e *= 0.75 + 0.25 * np.sin(np.pi * np.clip(seg_t / L, 0, 1)) ** 0.7
        amp[a:b] = np.maximum(amp[a:b], e * nt.get('vel', 0.8))
        vd = nt.get('vib', 0.007 if shaku else 0.005) if vib_depth is None else vib_depth
        vib[a:b] = vd * np.clip((seg_t - 0.35) / 0.6, 0, 1)
    # light smoothing of the frequency curve
    k = int(0.008 * SR)
    f = np.convolve(np.concatenate([np.full(k, f[0]), f, np.full(k, f[-1])]), np.ones(k) / k, mode='same')[k:-k]
    rate = 5.2 if shaku else 6.0
    drift = lowpass(rng.standard_normal(n), 3, 1)
    drift *= 0.002 / (np.std(drift) + 1e-9)
    fm = f * (1 + vib * np.sin(TAU * rate * t + 0.3 * np.sin(TAU * 0.7 * t)) + drift)
    ph = TAU * np.cumsum(fm) / SR
    y = np.zeros(n)
    for h, a in enumerate(harm_amps, 1):
        # higher harmonics come in with breath pressure
        y += a * np.sin(h * ph + rng.uniform(0, TAU)) * amp ** (1 + 0.35 * (h - 1))
    # breath noise locked to harmonics (narrow bands around h*f0), plus broadband air
    nz = rng.standard_normal(n)
    fr_hop = 256

    def tracks(tt):
        idx = np.clip((tt * SR).astype(int), 0, n - 1)
        f_t = fm[idx]
        out = []
        for h, a in enumerate(harm_amps[:6], 1):
            out.append((f_t * h, np.full(len(tt), 35.0 + 18 * h), np.full(len(tt), a)))
        return out
    harm_noise = formant_filter(nz, tracks, 2048, fr_hop)
    harm_noise /= np.std(harm_noise) + 1e-9
    air = bandpass(nz, 1500 if shaku else 2500, 9000, 2)
    air /= np.std(air) + 1e-9
    breathy = 0.11 if shaku else 0.06
    y += harm_noise * breathy * amp ** 0.9 + air * (0.025 if shaku else 0.02) * amp
    # 'muraiki' attack chiff on each note
    for nt in notes:
        a = int(nt['t'] * SR)
        if a >= n:
            continue
        L = min(int(0.09 * SR), n - a)
        tt = np.arange(L) / SR
        y[a:a + L] += air[a:a + L] * np.exp(-tt / 0.03) * (0.25 if shaku else 0.12) * nt.get('vel', 0.8) * nt.get('chiff', 1.0)
    if level_curve is not None:
        y *= level_curve
    # shakuhachi body: gentle formant around 1.2k and roll-off
    y = lowpass(y, 7000 if shaku else 9000, 2)
    return y * 0.3


# ------------------------------------------------------------------ horagai
def horagai(calls, dur, seed=3):
    """calls: list of dicts {t, len, f0, breaks:[(t_rel, len, ratio)], vel}"""
    rng = np.random.default_rng(seed)
    t = _t(dur)
    n = len(t)
    f = np.full(n, calls[0]['f0'] * 0.9)
    amp = np.zeros(n)
    for c in calls:
        a = int(c['t'] * SR); b = min(n, int((c['t'] + c['len']) * SR))
        st = t[a:b] - c['t']
        L = c['len']
        # scoop up into the note, slight sag through the breath
        fc = c['f0'] * (0.82 + 0.18 * (1 - np.exp(-st / 0.12))) * (1 - 0.015 * st / L)
        for (bt, bl, ratio) in c.get('breaks', []):
            k = np.clip((st - bt) / 0.05, 0, 1) * np.clip((bt + bl - st) / 0.06, 0, 1)
            fc *= 1 + (ratio - 1) * k
        f[a:b] = fc
        if b < n:
            f[b:] = fc[-1]
        e = (1 - np.exp(-st / 0.09)) * np.clip((L - st) / 0.18, 0, 1) ** 1.5
        e *= 0.85 + 0.15 * np.sin(np.pi * np.clip(st / L, 0, 1))
        amp[a:b] = np.maximum(amp[a:b], e * c.get('vel', 1.0))
    jit = lowpass(rng.standard_normal(n), 25, 1)
    jit *= 0.012 / (np.std(jit) + 1e-9)
    fm = f * (1 + jit)
    ph = TAU * np.cumsum(fm) / SR
    rl = lowpass(rng.standard_normal(n), 60, 1); rough = 1 + 0.18 * rl / (np.std(rl) + 1e-9)
    y = np.zeros(n)
    nh = int(9000 / f.min())
    for h in range(1, nh):
        a = h ** -0.6
        # brassy: upper harmonics grow strongly with pressure
        y += a * np.sin(h * ph + rng.uniform(0, TAU)) * amp ** (1 + 0.12 * (h - 1))
    # subharmonic rasp (period doubling) characteristic of conch blowing
    y += 0.18 * np.sin(0.5 * ph) * amp ** 2.5 * (0.5 + 0.5 * np.sin(TAU * 0.9 * t))
    y *= rough
    nz = rng.standard_normal(n)
    y += highpass(nz, 600, 2) * amp * 0.07

    def tracks(tt):
        m = np.ones(len(tt))
        return [(m * 480, m * 170, m * 1.0), (m * 1150, m * 280, m * .8), (m * 2400, m * 450, m * .45),
                (m * 3500, m * 700, m * .18), (m * 220, m * 120, m * .3)]
    y = formant_filter(y, tracks, 2048, 256)
    y = softclip(y / (np.max(np.abs(y)) + 1e-9) * 1.8, 1.5)
    return y


# ------------------------------------------------------------------ shouted voices
VOWELS = {  # shouted adult male: (F1, F2, F3, F4) — F1 raised for shouting
    'a': (800, 1300, 2550, 3500), 'e': (600, 1850, 2550, 3500), 'i': (380, 2150, 2900, 3600),
    'o': (620, 980, 2500, 3400), 'u': (420, 900, 2350, 3300),
}


def shout_voice(syllables, dur, seed=0, f0=200.0, fscale=1.0):
    """syllables: list of dicts {t, len, v0, v1 (diphthong target), f0mul, vel}"""
    rng = np.random.default_rng(seed)
    t = _t(dur)
    n = len(t)
    f = np.full(n, f0); amp = np.zeros(n)
    vt = np.zeros((n, 4))
    vt[:] = VOWELS[syllables[0]['v0']]
    for s in syllables:
        a = int(s['t'] * SR); b = min(n, int((s['t'] + s['len']) * SR))
        if a >= n:
            continue
        st = t[a:b] - s['t']; L = s['len']
        # pitch: rise into the shout then fall (declarative shout contour)
        fp = f0 * s.get('f0mul', 1.0) * (0.85 + 0.25 * np.clip(st / 0.08, 0, 1) - 0.18 * np.clip((st - 0.1) / L, 0, 1))
        f[a:b] = fp
        if b < n:
            f[b:] = fp[-1]
        v0 = np.array(VOWELS[s['v0']]); v1 = np.array(VOWELS[s.get('v1', s['v0'])])
        k = np.clip((st - L * 0.35) / (L * 0.45), 0, 1)[:, None]
        vt[a:b] = v0 * (1 - k) + v1 * k
        if b < n:
            vt[b:] = vt[b - 1]
        e = np.clip(st / 0.03, 0, 1) * np.clip((L - st) / 0.07, 0, 1) ** 1.2
        amp[a:b] = np.maximum(amp[a:b], e * s.get('vel', 1.0))
    jit = lowpass(rng.standard_normal(n), 30, 1)
    jit *= 0.02 / (np.std(jit) + 1e-9)
    fm = f * (1 + jit)
    ph = TAU * np.cumsum(fm) / SR
    # glottal source ~ band-limited sawtooth with steep tilt; pressed/shouted voice is bright
    y = np.zeros(n)
    for h in range(1, int(7000 / f0)):
        y += np.sin(h * ph) / h ** 0.85
    sl = lowpass(rng.standard_normal(n), 40, 1); shim = 1 + 0.1 * sl / (np.std(sl) + 1e-9)
    y *= amp * shim
    y += highpass(rng.standard_normal(n), 1500, 2) * amp * 0.05  # aspiration
    vt *= fscale

    def tracks(tt):
        idx = np.clip((tt * SR).astype(int), 0, n - 1)
        F = vt[idx]
        return [(F[:, 0], np.full(len(tt), 110.0), np.full(len(tt), 1.0)),
                (F[:, 1], np.full(len(tt), 140.0), np.full(len(tt), 0.55)),
                (F[:, 2], np.full(len(tt), 220.0), np.full(len(tt), 0.3)),
                (F[:, 3], np.full(len(tt), 320.0), np.full(len(tt), 0.12))]
    y = formant_filter(y, tracks, 1024, 128)
    return y
