"""Build KASSEN SFX / UI / ambience from the downloaded CC0 sources plus synthesis.

Run from anywhere:  python3 -E art_src/audio_dl/synth/build_sfx.py [group ...]
Groups: weapons bows guns horses voices loops ui amb   (default: all)
Outputs Ogg Vorbis into assets/audio/{sfx,ui,amb}/
"""
import os, sys, glob, time
import numpy as np
from dsp import *
from instruments import taiko, kane, hyoshigi, shout_voice, horagai, softclip

HERE = os.path.dirname(os.path.abspath(__file__))
DL = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(DL, '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio')
RNG = np.random.default_rng(1574)

_cache = {}


def src(rel):
    p = os.path.join(DL, rel)
    if p not in _cache:
        _cache[p] = load(p, 2)
    return _cache[p].copy()


def out(sub, name, x, mode='punch', **kw):
    x = stereo(x)
    x = highpass(x, kw.pop('hp', 30), 2)
    target = None
    if mode == 'punch':
        x = normalize_punch(x, kw.get('rms', -14.0), -1.5)
    elif mode == 'lufs':
        target = kw.get('lufs', -16.0)
        x = normalize_lufs(x, target, -1.5)
    elif mode == 'peak':
        x = normalize_peak(x, -1.5)
    path = os.path.join(OUT, sub, name + '.ogg')
    I, TP = save_checked(path, x, target)
    print(f'  {sub}/{name}.ogg  {len(x)/SR:5.2f}s  I {I:6.1f}  TP {TP:5.1f}', flush=True)
    return x


IR_SMALL = None
IR_FIELD = None
IR_BIG = None


def irs():
    global IR_SMALL, IR_FIELD, IR_BIG
    if IR_SMALL is None:
        IR_SMALL = make_ir(t60=0.35, predelay=0.004, early=8, damp_hf=0.4, size=0.4, seed=11)
        IR_FIELD = make_ir(t60=1.6, predelay=0.02, early=6, damp_hf=0.3, size=1.5, seed=12, bright=4000)
        IR_BIG = make_ir(t60=3.2, predelay=0.035, early=10, damp_hf=0.25, size=2.5, seed=13, bright=3500)
    return IR_SMALL, IR_FIELD, IR_BIG


def onsets_split(x, min_len=0.15, max_len=2.0, thresh_db=-30, gap=0.12):
    """Split a recording of several isolated events into pieces by envelope gating."""
    m = mono(x)
    w = int(0.01 * SR)
    e = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    on = e > e.max() * db(thresh_db)
    segs = []
    i = 0
    n = len(m)
    g = int(gap * SR)
    while i < n:
        if on[i]:
            j = i
            last = i
            while j < n and (j - last) < g:
                if on[j]:
                    last = j
                j += 1
            a = max(0, i - int(0.01 * SR)); b = min(n, last + int(0.08 * SR))
            if min_len * SR <= b - a <= max_len * SR:
                segs.append(x[a:b])
            i = j
        else:
            i += 1
    return segs


def distance(x, d):
    """d in 0..1: 0 = close, 1 = far (darker, quieter)."""
    return lowpass(x, 16000 * (1 - d) + 2500 * d, 2) * db(-10 * d)


def place(buf, x, t, gain=1.0, p=0.0, wrap=False):
    s = pan(mono(x), p) if p is not None else stereo(x)
    return mix_wrap(buf, s, t, gain) if wrap else mix_at(buf, s, t, gain)


# ------------------------------------------------------------------ weapons
def weapons():
    print('weapons', flush=True)
    small, field, _ = irs()
    clashes = [f'oga_starninjas_sword/x/sword_clash.{i}.ogg' for i in (1, 2, 3, 4, 5, 6, 8, 10)]
    for k, f in enumerate(clashes, 1):
        x = trim(lowpass(src(f), 11000, 2), -45)
        x = x / (np.max(np.abs(x)) + 1e-9)
        body = trim(src(f'oga_starninjas_impact/x/impact.{(k % 10) + 1}.ogg'), -45)
        body = lowpass(body / (np.max(np.abs(body)) + 1e-9), 3000)[:int(0.25 * SR)]
        x = mix_at(x, fade(body, 0.0, 0.08) * 0.35, 0.0)
        x = shelf(x, 7000, -3.0)
        x = reverb(x, small, 0.12)
        out('sfx', f'sword_clash_{k:02d}', trim(x, -55), rms=-13)
    blades = [f'oga_starninjas_sword/x/sword - StarNinjas/sword.{i}.ogg' for i in (2, 3, 4, 6, 7, 10)]
    bodies = [f'oga_starninjas_impact/x/impact.{i}.ogg' for i in (1, 4, 5, 6, 8, 9)]
    for k, (b, h) in enumerate(zip(blades, bodies), 1):
        xb = trim(lowpass(src(b), 12000, 2), -45); xb /= np.max(np.abs(xb)) + 1e-9
        xh = trim(src(h), -45); xh /= np.max(np.abs(xh)) + 1e-9
        y = mix_at(np.zeros((1, 2)), xb * 0.8, 0.0)
        y = mix_at(y, xh * 0.75, 0.035)
        out('sfx', f'sword_hit_{k:02d}', trim(reverb(y, small, 0.1), -55), rms=-13)
    swishes = sorted(glob.glob(os.path.join(DL, 'oga_swishes/x/swishes/swish-*.wav')))
    thunks = ['oga_100cc0_metalwood/x/wood_misc_06.ogg', 'oga_100cc0_metalwood/x/wood_misc_07.ogg',
              'oga_75cc0_breaking/x/bfh1_wood_hit_03.ogg', 'oga_100cc0_metalwood/x/wood_hit_05.ogg',
              'oga_100cc0_metalwood/x/wood_misc_04.ogg']
    stabs = ['oga_kenney_rpg/x/OGG/knifeSlice.ogg', 'oga_kenney_rpg/x/OGG/knifeSlice2.ogg', 'oga_kenney_rpg/x/OGG/chop.ogg',
             'oga_starninjas_impact/x/impact.10.ogg', 'oga_starninjas_impact/x/impact.3.ogg']
    for k in range(5):
        sw = trim(load(swishes[(k * 3 + 1) % len(swishes)], 2), -45); sw /= np.max(np.abs(sw)) + 1e-9
        th = trim(src(thunks[k]), -45); th /= np.max(np.abs(th)) + 1e-9
        st = trim(src(stabs[k]), -45); st /= np.max(np.abs(st)) + 1e-9
        y = mix_at(np.zeros((1, 2)), sw * 0.7, 0.0)
        y = mix_at(y, th * 0.9, len(sw) / SR * 0.7)
        y = mix_at(y, st * 0.45, len(sw) / SR * 0.7 + 0.005)
        out('sfx', f'spear_thrust_{k + 1:02d}', trim(reverb(y, small, 0.1), -55), rms=-14)
    rattles = ['oga_rpg_sound_pack/x/RPG Sound Pack/inventory/armor-light.wav', 'oga_rpg_sound_pack/x/RPG Sound Pack/inventory/chainmail1.wav',
               'oga_rpg_sound_pack/x/RPG Sound Pack/inventory/chainmail2.wav', 'oga_75cc0_breaking/x/bfh1_metal_hit_02.ogg',
               'oga_75cc0_breaking/x/bfh1_metal_hit_04.ogg', 'oga_100cc0_metalwood/x/metal_hit_03.ogg']
    for k, f in enumerate(rattles, 1):
        r = trim(src(f), -45); r /= np.max(np.abs(r)) + 1e-9
        h = trim(src(bodies[(k + 2) % len(bodies)]), -45); h /= np.max(np.abs(h)) + 1e-9
        y = mix_at(np.zeros((1, 2)), h * 0.8, 0.0)
        y = mix_at(y, lowpass(r, 11000) * 0.8, 0.008)
        out('sfx', f'armour_impact_{k:02d}', trim(reverb(y, small, 0.1), -55), rms=-14)


# ------------------------------------------------------------------ bows & arrows
def bow_twang(seed, f0=None):
    rng = np.random.default_rng(seed)
    n = int(0.5 * SR); t = np.arange(n) / SR
    f0 = f0 or rng.uniform(105, 150)
    y = np.zeros(n)
    for h in range(1, 14):
        fh = f0 * h * (1 - 0.03 * np.exp(-t / 0.02))
        y += np.sin(TAU * np.cumsum(fh) / SR + rng.uniform(0, TAU)) * np.exp(-t / (0.16 / (1 + 0.35 * (h - 1)))) / h ** 0.9
    y *= 1 - np.exp(-t / 0.0005)
    nz = rng.standard_normal(n)
    slap = bandpass(nz, 500, 5000, 2) * np.exp(-t / 0.007) * 3.5
    crack = highpass(nz, 2500, 2) * np.exp(-t / 0.0015) * 1.5
    limb = np.sin(TAU * rng.uniform(55, 75) * t) * np.exp(-t / 0.04) * 0.35
    air = bandpass(nz, 800, 5000, 1) * np.exp(-((t - 0.05) / 0.04) ** 2) * 0.5
    y = highpass(y, 180, 2) * 0.7 + slap + crack + limb + air
    y = softclip(y * 0.6, 1.3)
    return fade(y, 0, 0.05)


def arrow_flyby(rng, dur=0.7):
    """single arrow passing: band-noise with doppler-ish downward sweep and fletching flutter"""
    n = int(dur * SR); t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    c = t / dur
    env = np.exp(-((c - 0.45) / 0.22) ** 2)
    hi = bandpass(nz, 1800, 5500, 2)
    lo = bandpass(nz, 500, 1600, 2)
    mixk = np.clip(c * 1.6, 0, 1)  # bright early, darker after passing
    y = (hi * (1 - mixk) + lo * mixk * 1.3) * env
    flutter = 1 + 0.35 * np.sin(TAU * rng.uniform(28, 55) * t)
    return y * flutter


def bows():
    print('bows', flush=True)
    small, field, big = irs()
    swishes = sorted(glob.glob(os.path.join(DL, 'oga_swishes/x/swishes/swish-*.wav')))
    for k in range(5):
        y = stereo(bow_twang(100 + k))
        sw = trim(load(swishes[(k * 2 + 5) % len(swishes)], 2), -45)
        sw = highpass(sw, 400, 2) / (np.max(np.abs(sw)) + 1e-9)
        y = mix_at(y, sw * 0.8, 0.012)
        out('sfx', f'bow_release_{k + 1:02d}', trim(reverb(y, small, 0.12), -55), rms=-15)
    for k in range(3):
        rng = np.random.default_rng(200 + k)
        buf = np.zeros((int(2.2 * SR), 2))
        nb = rng.integers(22, 34)
        for j in range(nb):
            tw = bow_twang(1000 + 50 * k + j, rng.uniform(100, 160))
            d = rng.uniform(0, 0.8)
            t0 = abs(rng.normal(0, 0.18)) + 0.02  # tight 'hanate!' release with stragglers
            buf = place(buf, distance(tw, d), t0, rng.uniform(0.35, 0.7), rng.uniform(-0.6, 0.6))
        for j in range(nb // 2):  # early whoosh of arrows leaving
            a = arrow_flyby(rng, rng.uniform(0.5, 0.9))
            buf = place(buf, a, rng.uniform(0.05, 0.45), 0.12, rng.uniform(-0.5, 0.5))
        y = reverb(buf, field, 0.22)
        out('sfx', f'bow_volley_{k + 1:02d}', trim(y, -55), rms=-13)
    bed = src('oga_air_whoosh/whoosh2_0.wav')
    for k in range(3):
        rng = np.random.default_rng(300 + k)
        dur = 2.2
        buf = np.zeros((int(dur * SR), 2))
        for j in range(40):
            a = arrow_flyby(rng, rng.uniform(0.45, 1.0))
            buf = place(buf, distance(a, rng.uniform(0, 0.6)), rng.uniform(0.0, 1.1), rng.uniform(0.15, 0.4), rng.uniform(-0.8, 0.8))
        st = int(rng.uniform(0, 2.5) * SR)
        b = bed[st:st + len(buf)]
        b = b * np.sin(np.linspace(0, np.pi, len(b)))[:, None] ** 2
        buf[:len(b)] += highpass(b, 300) * 0.5
        out('sfx', f'arrow_whoosh_{k + 1:02d}', fade(trim(reverb(buf, field, 0.15), -55), 0.05, 0.3), rms=-16)
    hits = ['oga_100cc0_metalwood/x/wood_hit_05.ogg', 'oga_100cc0_metalwood/x/wood_hit_07.ogg', 'oga_100cc0_metalwood/x/wood_hit_08.ogg',
            'oga_75cc0_breaking/x/bfh1_wood_hit_01.ogg', 'oga_75cc0_breaking/x/bfh1_wood_hit_02.ogg', 'oga_75cc0_breaking/x/bfh1_hit_06.ogg']
    impacts = []
    for k, f in enumerate(hits, 1):
        rng = np.random.default_rng(400 + k)
        x = trim(src(f), -45); x /= np.max(np.abs(x)) + 1e-9
        n = int(0.15 * SR); t = np.arange(n) / SR
        tick = stereo(bandpass(rng.standard_normal(n), 2500, 8000, 2) * np.exp(-t / 0.003) * 0.5)
        y = mix_at(stereo(x) * 0.9, tick, 0.0)
        y = fade(y, 0, min(0.12, len(y) / SR * 0.5))
        impacts.append(y)
        out('sfx', f'arrow_impact_{k:02d}', trim(reverb(y, small, 0.1), -55), rms=-16)
    clinks = [src(f) for f in ['oga_rpg_sound_pack/x/RPG Sound Pack/inventory/metal-small1.wav', 'oga_80cc0_rpg/x/metal_02.ogg',
                               'oga_kenney_rpg/x/OGG/metalClick.ogg']]
    for k in range(3):
        rng = np.random.default_rng(500 + k)
        buf = np.zeros((int(1.8 * SR), 2))
        for j in range(rng.integers(28, 40)):
            s = impacts[rng.integers(len(impacts))] if rng.random() < 0.8 else trim(clinks[rng.integers(3)], -40)
            s = resample(s, rng.uniform(0.85, 1.15))
            buf = place(buf, distance(s, rng.uniform(0, 0.7)), abs(rng.normal(0.25, 0.25)), rng.uniform(0.2, 0.55), rng.uniform(-0.7, 0.7))
        out('sfx', f'arrow_rain_{k + 1:02d}', trim(reverb(buf, field, 0.15), -55), rms=-15)


# ------------------------------------------------------------------ guns
def guns():
    print('guns', flush=True)
    small, field, big = irs()
    shots = onsets_split(src('oga_gunshots/Black%20Powder.wav'), 0.2, 1.2, -32, 0.15)
    shots += onsets_split(src('oga_gunshots/Unkown.wav'), 0.2, 1.2, -32, 0.15)
    print('   found', len(shots), 'shots', flush=True)
    clean = []
    for s in shots:
        s = trim(s, -40, 0.002, 0.05)
        s = s / (np.max(np.abs(s)) + 1e-9)
        n = len(s); t = np.arange(n) / SR
        boom = lowpass(RNG.standard_normal(n), 140, 2) * np.exp(-t / 0.07) * 2.2 + np.sin(TAU * 52 * t) * np.exp(-t / 0.09) * 0.5
        s = s + stereo(boom) * 0.35
        s = softclip(s / (np.max(np.abs(s)) + 1e-9) * 2.2, 1.8)
        clean.append(s)
    for k in range(4):
        s = clean[k % len(clean)]
        s = resample(s, [1.0, 0.94, 1.05, 0.9][k])
        y = reverb(s, big, 0.16)
        # hill echo
        e = lowpass(y, 2500) * 0.18
        y = mix_at(y, e, RNG.uniform(0.35, 0.6))
        out('sfx', f'matchlock_shot_{k + 1:02d}', fade(trim(y, -60), 0, 0.4), rms=-11)
    for k in range(3):
        rng = np.random.default_rng(600 + k)
        buf = np.zeros((int(3.0 * SR), 2))
        n = rng.integers(16, 26)
        for j in range(n):
            s = clean[rng.integers(len(clean))]
            s = resample(s, rng.uniform(0.88, 1.08))
            t0 = abs(rng.normal(0, 0.22)) if rng.random() < 0.8 else rng.uniform(0.3, 1.3)  # ragged with stragglers
            buf = place(buf, distance(s, rng.uniform(0, 0.75)), 0.02 + t0, rng.uniform(0.3, 0.6), rng.uniform(-0.75, 0.75))
        y = reverb(buf, big, 0.22)
        e = lowpass(y, 2000) * 0.15
        y = mix_at(y, e, 0.5)
        out('sfx', f'matchlock_volley_{k + 1:02d}', fade(trim(y, -60), 0, 0.6), rms=-10)


# ------------------------------------------------------------------ horses
def horses():
    print('horses', flush=True)
    small, field, big = irs()
    g = src('commons/Six_Horses_Galloping_By.ogg')
    # flatten the pass-by envelope (gain riding with a 0.4 s window), then layer offset copies
    def ride(x):
        m = mono(x); w = int(0.4 * SR)
        e = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same')) + 1e-4
        return x / e[:, None] * 0.1
    seg = ride(g[int(4.6 * SR):int(10.8 * SR)])
    L = int(4.0 * SR); xf = int(0.6 * SR)
    loop = np.zeros((L, 2))
    for j, (off, pr, gain, p) in enumerate([(0.0, 1.0, 1.0, 0.0), (0.9, 1.03, 0.7, -0.4), (1.5, 0.97, 0.7, 0.4)]):
        s = resample(seg, pr)[int(off * SR):]
        if len(s) < L + xf:
            continue
        l = loop_crossfade(s, L, xf)
        m = mono(l)
        loop += pan(m, p) * gain if p else stereo(m) * gain
    loop = highpass(loop, 60)
    out('sfx', 'horse_gallop_loop', reverb_loop(loop, small, 0.15), 'lufs', lufs=-18)
    w = src('commons/Wiehern.ogg')
    for k, pr in enumerate([1.0, 0.93, 1.07], 1):
        y = reverb(resample(trim(w, -45), pr), field, 0.18)
        out('sfx', f'horse_whinny_{k:02d}', trim(y, -55), rms=-15)
    # cavalry charge impact: body thud + snapping shafts + armour clatter + whinny tail
    bodies = [src(f'oga_starninjas_impact/x/impact.{i}.ogg') for i in (1, 4, 5, 8, 10)]
    breaks = [src(f) for f in ['oga_100cc0_metalwood/x/wood_breaking_01.ogg', 'oga_100cc0_metalwood/x/wood_breaking_02.ogg',
                               'oga_75cc0_breaking/x/bfh1_wood_breaking_01.ogg', 'oga_75cc0_breaking/x/bfh1_wood_breaking_02.ogg']]
    rattles = [src(f) for f in ['oga_rpg_sound_pack/x/RPG Sound Pack/inventory/chainmail1.wav',
                                'oga_rpg_sound_pack/x/RPG Sound Pack/inventory/armor-light.wav', 'oga_80cc0_rpg/x/chain_01.ogg']]
    for k in range(3):
        rng = np.random.default_rng(700 + k)
        n = int(1.0 * SR); t = np.arange(n) / SR
        thud = lowpass(rng.standard_normal(n), 160, 2) * np.exp(-t / 0.06) * 3 + np.sin(TAU * (48 + 30 * np.exp(-t / 0.03)) * t) * np.exp(-t / 0.12)
        buf = stereo(softclip(thud * 0.5, 1.5))
        for j in range(6):
            b = bodies[rng.integers(len(bodies))]
            buf = place(buf, trim(b, -40), rng.uniform(0, 0.25), 0.5, rng.uniform(-0.5, 0.5))
        buf = place(buf, trim(breaks[(k + 1) % 4], -40), rng.uniform(0.02, 0.1), 0.6, rng.uniform(-0.3, 0.3))
        buf = place(buf, trim(breaks[(k + 2) % 4], -40), rng.uniform(0.12, 0.3), 0.4, rng.uniform(-0.6, 0.6))
        for j in range(2):
            buf = place(buf, trim(rattles[(k + j) % 3], -40), rng.uniform(0.03, 0.2), 0.45, rng.uniform(-0.6, 0.6))
        buf = place(buf, resample(trim(w, -45), rng.uniform(0.95, 1.08)), rng.uniform(0.25, 0.4), 0.28, rng.uniform(-0.4, 0.4))
        out('sfx', f'cavalry_charge_impact_{k + 1:02d}', trim(reverb(buf, field, 0.2), -55), rms=-11)


# ------------------------------------------------------------------ voices
YELL_DIR = 'oga_male_yelling/x/yelling sounds'


def yells(long_only=True):
    fs = sorted(glob.glob(os.path.join(DL, YELL_DIR, '*yell*.wav')))
    out_ = []
    for f in fs:
        x = trim(load(f, 2), -40)
        if long_only and len(x) < 0.5 * SR:
            continue
        out_.append(x / (np.max(np.abs(x)) + 1e-9))
    return out_


def voices():
    print('voices', flush=True)
    small, field, big = irs()
    ys = yells()
    print('   yells', len(ys), flush=True)
    crowd = src('oga_crowd_shouting/crowd_shouting.ogg')
    for k in range(5):
        rng = np.random.default_rng(800 + k)
        buf = np.zeros((int(3.5 * SR), 2))
        for j in range(rng.integers(14, 22)):
            y = ys[rng.integers(len(ys))]
            y = resample(y, rng.uniform(0.9, 1.1))
            buf = place(buf, distance(y, rng.uniform(0, 0.7)), abs(rng.normal(0, 0.12)), rng.uniform(0.35, 0.7), rng.uniform(-0.8, 0.8))
        st = int(rng.uniform(2, 20) * SR)
        c = crowd[st:st + int(2.0 * SR)] * env_adsr(int(2.0 * SR), 0.15, 0.5, 0.6, 1.0)[:, None]
        buf[:len(c)] += c * 0.35
        out('sfx', f'warcry_{k + 1:02d}', fade(trim(reverb(buf, field, 0.25), -55), 0, 0.3), rms=-13)
    for k in range(3):
        rng = np.random.default_rng(850 + k)
        buf = np.zeros((int(3.5 * SR), 2))
        for j in range(rng.integers(6, 10)):
            y = ys[rng.integers(len(ys))]
            y = resample(y, rng.uniform(1.04, 1.18))
            buf = place(buf, distance(y, rng.uniform(0.1, 0.7)), rng.uniform(0, 1.4), rng.uniform(0.35, 0.65), rng.uniform(-0.8, 0.8))
        out('sfx', f'rout_cry_{k + 1:02d}', fade(trim(reverb(buf, field, 0.25), -55), 0, 0.3), rms=-14)
    # death grunts: split the CC0 grunt reel + short grunts
    reel = src('oga_grunts_death/death%20pain%20grunts.wav')
    segs = onsets_split(reel, 0.25, 1.6, -28, 0.12)
    segs += [load(f, 2) for f in sorted(glob.glob(os.path.join(DL, YELL_DIR, '3grunt*.wav')))]
    print('   grunt segments', len(segs), flush=True)
    scored = sorted(segs, key=lambda s: -np.sqrt(np.mean(mono(s) ** 2)))[:14]
    k = 0
    for s in scored:
        s = trim(s, -40)
        if len(s) < 0.2 * SR:
            continue
        k += 1
        out('sfx', f'death_grunt_{k:02d}', trim(reverb(highpass(s, 110), small, 0.12), -55), rms=-15)
        if k >= 10:
            break
    # 'Ei! Ei! Oh!' (kachidoki) — leader + ranks, synthesised voices layered with real yells for grit
    rng = np.random.default_rng(900)
    dur = 7.5
    buf = np.zeros((int(dur * SR), 2))
    calls = [0.0, 2.4, 4.8]
    for c0 in calls:
        lead = shout_voice([{'t': 0.05, 'len': 0.42, 'v0': 'e', 'v1': 'i', 'vel': 1.0},
                            {'t': 0.62, 'len': 0.45, 'v0': 'e', 'v1': 'i', 'vel': 1.0, 'f0mul': 1.04}], 1.3, seed=rng.integers(1000000), f0=175)
        buf = place(buf, lead, c0, 0.9, 0.0)
        for v in range(4):
            s = shout_voice([{'t': 0.05 + rng.uniform(0, .04), 'len': 0.42, 'v0': 'e', 'v1': 'i'},
                             {'t': 0.62 + rng.uniform(0, .04), 'len': 0.45, 'v0': 'e', 'v1': 'i'}], 1.3, seed=rng.integers(1000000), f0=rng.uniform(150, 200), fscale=rng.uniform(0.93, 1.07))
            buf = place(buf, distance(s, 0.2), c0, 0.3, rng.uniform(-0.3, 0.3))
        for v in range(36):  # the ranks answer "Oh!"
            st = c0 + 1.25 + abs(rng.normal(0, 0.05))
            L = rng.uniform(0.75, 1.05)
            s = shout_voice([{'t': 0.02, 'len': L, 'v0': 'o', 'v1': 'o', 'vel': 1.0}], L + 0.1, seed=rng.integers(1000000), f0=rng.uniform(140, 230), fscale=rng.uniform(0.9, 1.1))
            buf = place(buf, distance(s, rng.uniform(0, 0.8)), st, rng.uniform(0.12, 0.25), rng.uniform(-0.9, 0.9))
        for v in range(6):
            y = ys[rng.integers(len(ys))]
            y = lowpass(resample(y, rng.uniform(0.9, 1.0)), 2500)[:int(1.0 * SR)]
            buf = place(buf, fade(distance(y, rng.uniform(0.3, 0.8)), 0.01, 0.3), c0 + 1.28 + rng.uniform(0, 0.08), 0.25, rng.uniform(-0.8, 0.8))
    out('sfx', 'kachidoki_01', fade(trim(reverb(buf, big, 0.3), -60), 0, 0.5), rms=-13)


def horagai_group():
    print('horagai', flush=True)
    small, field, big = irs()
    for k, (dist_, f0) in enumerate([(0.0, 158.0), (0.55, 150.0)], 1):
        calls_ = [{'t': 0.1, 'len': 2.6, 'f0': f0, 'breaks': [(1.9, 0.45, 1.5)]},
                  {'t': 3.25, 'len': 3.6, 'f0': f0, 'breaks': [(1.2, 0.35, 1.5), (2.7, 0.55, 1.5)]}]
        y = horagai(calls_, 7.4, seed=30 + k)
        y = stereo(y)
        y = distance(y, dist_)
        y = reverb(y, big, 0.25 + 0.3 * dist_)
        e = lowpass(y, 1800) * 0.22
        y = mix_at(y, e, 0.62)
        out('sfx', 'horagai_01' if k == 1 else 'horagai_answer_01', fade(trim(y, -60), 0.01, 0.8), 'lufs', lufs=-14 - 4 * dist_)


# ------------------------------------------------------------------ loops
def loops():
    print('loops', flush=True)
    small, field, big = irs()
    rng = np.random.default_rng(1000)
    # marching: ~40 ashigaru, 2 steps/s, two loose sync groups, gear rattle
    L = 8.0
    buf = np.zeros((int(L * SR), 2))
    steps = [src(f'oga_kenney_rpg/x/OGG/footstep0{i}.ogg') for i in range(10)]
    crunch = [src(f) for f in sorted(glob.glob(os.path.join(DL, 'oga_fantozzi_footsteps/x/Fantozzi-footsteps/ogg/Fantozzi-Sand*.ogg')))]
    gear = [src(f) for f in ['oga_kenney_rpg/x/OGG/cloth1.ogg', 'oga_kenney_rpg/x/OGG/cloth2.ogg', 'oga_kenney_rpg/x/OGG/beltHandle1.ogg',
                             'oga_kenney_rpg/x/OGG/beltHandle2.ogg', 'oga_80cc0_rpg/x/chain_02.ogg', 'oga_rpg_sound_pack/x/RPG Sound Pack/inventory/armor-light.wav']]
    period = 0.5
    for s in range(40):
        ph = (0.0 if s % 2 else period / 2) + rng.normal(0, 0.035)
        d = rng.uniform(0, 0.8); p = rng.uniform(-0.8, 0.8)
        t = ph
        while t < L:
            fs = steps[rng.integers(10)] if rng.random() < 0.65 else crunch[rng.integers(len(crunch))] * 0.5
            buf = place(buf, distance(fs, d), t, rng.uniform(0.12, 0.22), p, wrap=True)
            if rng.random() < 0.18:
                gsm = gear[rng.integers(len(gear))]
                buf = place(buf, distance(gsm, d), t + rng.uniform(0, 0.1), rng.uniform(0.05, 0.12), p, wrap=True)
            t += period + rng.normal(0, 0.008)
    out('sfx', 'march_loop', reverb_loop(highpass(buf, 70), field, 0.12), 'lufs', lufs=-18)
    # melee beds: crowd bed + dense clashes, impacts, grunts and yells, circular so it loops cleanly
    crowd = src('oga_crowd_shouting/crowd_shouting.ogg')
    clash = [trim(src(f'oga_starninjas_sword/x/sword_clash.{i}.ogg'), -45) for i in range(1, 11)]
    clash = [lowpass(c / (np.max(np.abs(c)) + 1e-9), 11000) for c in clash]
    blade = [trim(src(f'oga_80cc0_rpg/x/blade_0{i}.ogg'), -45) for i in (1, 2, 3)]
    hits = [trim(src(f'oga_starninjas_impact/x/impact.{i}.ogg'), -45) for i in range(1, 11)]
    hits = [h / (np.max(np.abs(h)) + 1e-9) for h in hits]
    woods = [trim(src(f), -45) for f in ['oga_100cc0_metalwood/x/wood_misc_06.ogg', 'oga_100cc0_metalwood/x/wood_misc_07.ogg', 'oga_100cc0_metalwood/x/wood_hit_08.ogg']]
    ys = yells()
    reel = src('oga_grunts_death/death%20pain%20grunts.wav')
    grunts = onsets_split(reel, 0.25, 1.6, -28, 0.12)
    for k in range(2):
        rng = np.random.default_rng(1100 + k)
        L = 12.0
        Ln = int(L * SR); xf = int(1.5 * SR)
        st = int(rng.uniform(0.5, 27.3 - L - 1.6) * SR)
        bed = loop_crossfade(crowd[st:st + Ln + xf], Ln, xf) * 0.45
        buf = np.zeros((Ln, 2))
        def sprinkle(pool, rate, gain, pitch=(0.9, 1.1), dmax=0.85):
            nonlocal buf
            for j in range(int(rate * L)):
                s = pool[rng.integers(len(pool))]
                s = resample(s, rng.uniform(*pitch))
                buf = place(buf, distance(s, rng.uniform(0.15, dmax)), rng.uniform(0, L), gain * rng.uniform(0.5, 1.0), rng.uniform(-0.85, 0.85), wrap=True)
        sprinkle(clash, 5.0, 0.35)
        sprinkle(blade, 1.5, 0.25)
        sprinkle(hits, 4.0, 0.35)
        sprinkle(woods, 1.5, 0.3)
        sprinkle(grunts, 1.2, 0.3)
        sprinkle(ys, 0.7, 0.25)
        steps_fast = [resample(s, 1.3) for s in steps]
        sprinkle(steps_fast, 10.0, 0.1, (0.95, 1.05))
        y = reverb_loop(bed + buf, field, 0.2)
        out('sfx', f'melee_loop_{k + 1:02d}', y, 'lufs', lufs=-17)


# ------------------------------------------------------------------ ui
def ui():
    print('ui', flush=True)
    small, field, _ = irs()
    room = make_ir(t60=0.5, predelay=0.006, early=10, damp_hf=0.45, size=0.5, seed=21)
    for k, f0 in enumerate([2350, 2550, 2150], 1):
        y = stereo(hyoshigi(0.8, seed=k, f0=f0))
        out('ui', f'ui_click_{k:02d}', trim(reverb(y, room, 0.12), -60), rms=-17)
    y = stereo(hyoshigi(0.4, seed=9, f0=3100))[:int(0.12 * SR)]
    out('ui', 'ui_hover_01', fade(reverb(y, room, 0.08), 0, 0.03), rms=-24)
    buf = np.zeros((1, 2))
    buf = mix_at(buf, hyoshigi(0.8, seed=31, f0=1650), 0.0)
    buf = mix_at(buf, hyoshigi(0.6, seed=32, f0=1500), 0.085)
    out('ui', 'ui_back_01', trim(reverb(buf, room, 0.12), -60), rms=-17)
    buf = mix_at(np.zeros((1, 2)), hyoshigi(1.0, seed=41, f0=2050), 0.0)
    buf = mix_at(buf, kane(0.35, damped=True, seed=4), 0.0)
    out('ui', 'ui_select_01', trim(reverb(buf, room, 0.15), -60), rms=-16)
    for k in range(3):  # order acknowledged: two quick shime taps ("te-ke") + soft wood
        buf = mix_at(np.zeros((1, 2)), taiko('shime', 0.55, seed=50 + k, pitch=1.0 + 0.03 * k), 0.0)
        buf = mix_at(buf, taiko('shime', 0.85, seed=60 + k, pitch=1.0 + 0.03 * k), 0.075)
        out('ui', f'order_confirm_{k + 1:02d}', trim(reverb(buf, room, 0.15), -60), rms=-16)
    for k in range(2):  # attack order: nagado "don" + damped kane
        buf = mix_at(np.zeros((1, 2)), taiko('nagado', 0.9, seed=70 + k), 0.0)
        buf = mix_at(buf, kane(0.6, damped=True, seed=80 + k), 0.01)
        out('ui', f'order_attack_{k + 1:02d}', trim(reverb(buf, field, 0.15), -60)[:int(1.2 * SR)], rms=-15)


# ------------------------------------------------------------------ ambience
def amb():
    print('ambience', flush=True)
    def mkloop(path, start, L, xf, target, hp=40, lp=None, name=''):
        x = load(os.path.join(DL, path), 2)
        a = int(start * SR)
        seg = x[a:a + int((L + xf) * SR)]
        seg = highpass(seg, hp, 2)
        if lp:
            seg = lowpass(seg, lp, 2)
        y = loop_crossfade(seg, int(L * SR), int(xf * SR))
        seam, step = loop_seam_report(y)
        print(f'   {name}: seam {seam:.4f} vs mean step {step:.4f}', flush=True)
        out('amb', name, y, 'lufs', lufs=target)
    # the CC0 wind recording is mostly sub-bass mic rumble; keep a little of it (high-passed) under
    # a synthesised plain wind: gusting band-noise with a moving centre, faint whistle, grass rustle
    L = 40.0; xf = 4.0
    n = int((L + xf) * SR)
    rng = np.random.default_rng(42)
    def slow(rate, k=1):
        v = lowpass(rng.standard_normal(n), rate, 1)
        return (v - v.mean()) / (np.std(v) + 1e-9)
    gust = np.clip(0.55 + 0.3 * slow(0.12) + 0.15 * slow(0.5), 0.12, 1.3)
    centre = 380 * 2 ** (0.9 * (gust - 0.55))
    nz = rng.standard_normal(n)
    def body_tracks(tt):
        idx = np.clip((tt * SR).astype(int), 0, n - 1)
        c = centre[idx]; o = np.ones(len(tt))
        return [(c, c * 1.6, o), (c * 2.6, c * 2.5, o * 0.35)]
    chans = []
    for ch in range(2):
        nz = rng.standard_normal(n)
        b = formant_filter(nz, body_tracks, 2048, 512)
        w = bandpass(rng.standard_normal(n), 1400, 3200, 2) * np.clip(gust - 0.75, 0, None) ** 1.5 * 0.6
        g = highpass(rng.standard_normal(n), 3500, 2) * (0.3 + 0.7 * np.clip(gust, 0, 1.2)) * 0.12
        chans.append(b / (np.std(b) + 1e-9) * gust + w / (np.std(w) + 1e-9) * 0.15 + g / (np.std(g) + 1e-9) * 0.1)
    syn = np.stack(chans, 1)
    rec = load(os.path.join(DL, 'oga_mild_wind/wind%20background%20noise%202.wav'), 2)
    rec = highpass(rec[int(1.5 * SR):int(1.5 * SR) + n], 90, 3)
    rec = rec / (np.std(rec) + 1e-9) * 0.35
    y = syn + np.concatenate([rec, np.zeros((n - len(rec), 2))])[:n]
    y = loop_crossfade(y, int(L * SR), int(xf * SR))
    out('amb', 'wind_plain_loop', y, 'lufs', lufs=-23)
    mkloop('oga_park_ambiences/park_ambience_birds.wav', 60.0, 45.0, 4.0, -24, 150, None, 'birds_loop')
    mkloop('oga_park_ambiences/park_ambience_river.wav', 60.0, 45.0, 4.0, -22, 50, None, 'river_loop')


GROUPS = {'horagai': horagai_group, 'weapons': weapons, 'bows': bows, 'guns': guns, 'horses': horses, 'voices': voices, 'loops': loops, 'ui': ui, 'amb': amb}

if __name__ == '__main__':
    want = sys.argv[1:] or list(GROUPS)
    for g in want:
        t0 = time.time()
        GROUPS[g]()
        print(f'[{g}] {time.time() - t0:.0f}s', flush=True)
