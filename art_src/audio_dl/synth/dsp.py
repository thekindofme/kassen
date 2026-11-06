"""Small offline DSP toolkit (numpy only) for KASSEN audio synthesis and processing.

Everything is zero-phase / FFT based where possible because the build runs offline.
All signals are float64, mono (n,) or stereo (n, 2), at SR.
"""
import subprocess, os, re
import numpy as np
from oggwrite import write_ogg

SR = 44100
TAU = 2 * np.pi


# ---------------------------------------------------------------- io
def load(path, ch=2, sr=SR):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', str(ch), '-ar', str(sr), '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return x.reshape(-1, ch) if ch > 1 else x


def stereo(x):
    x = np.asarray(x, dtype=np.float64)
    return np.stack([x, x], 1) if x.ndim == 1 else x


def mono(x):
    return x.mean(1) if x.ndim == 2 else x


def save(path, x, quality=0.6):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pk = np.max(np.abs(x))
    assert pk <= 1.0 + 1e-6, f'{path} would clip ({pk})'
    assert np.all(np.isfinite(x)), path
    write_ogg(path, x, SR, quality)


def ebur128(path):
    r = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                       capture_output=True, text=True).stderr
    I = re.findall(r'I:\s+(-?[\d.]+|-inf) LUFS', r)
    TP = re.findall(r'Peak:\s+(-?[\d.]+|-inf) dBFS', r)
    return float(I[-1]) if I and I[-1] != '-inf' else -99.0, float(TP[-1]) if TP and TP[-1] != '-inf' else -99.0


# ---------------------------------------------------------------- loudness (BS.1770 K-weighting, FFT approximation)
def _kweight_mag(f):
    # high shelf +4 dB above ~1.5 kHz and RLB high-pass ~38 Hz (magnitude approximation of the biquads)
    shelf = 1 + (10 ** (4 / 20) - 1) * (f / 1500.0) ** 2 / (1 + (f / 1500.0) ** 2)
    hp = (f / 38.0) ** 2 / np.sqrt(1 + (f / 38.0) ** 4)
    return shelf * hp


def lufs(x):
    """Integrated loudness (gated) of a signal, FFT-K-weighted approximation of BS.1770."""
    x = stereo(x)
    n = len(x)
    if n < SR * 0.4:
        x = np.concatenate([x, np.zeros((int(SR * 0.4) - n + 1, 2))])
        n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    H = _kweight_mag(f)
    y = np.fft.irfft(np.fft.rfft(x, axis=0) * H[:, None], n, axis=0)
    blk = int(0.4 * SR); hop = int(0.1 * SR)
    p = np.array([np.mean(y[i:i + blk] ** 2, axis=0).sum() for i in range(0, n - blk + 1, hop)])
    lk = -0.691 + 10 * np.log10(p + 1e-20)
    g = p[lk > -70]
    if len(g) == 0:
        return -99.0
    rel = -0.691 + 10 * np.log10(g.mean()) - 10
    g2 = p[(lk > -70) & (lk > rel)]
    return -0.691 + 10 * np.log10(g2.mean() + 1e-20)


def db(v):
    return 10 ** (v / 20)


def normalize_lufs(x, target, peak_db=-1.0):
    """Gain to target integrated LUFS, then a transparent limiter for peaks."""
    g = db(target - lufs(x))
    return limit(x * g, peak_db)


def normalize_peak(x, peak_db=-1.0):
    return x * (db(peak_db) / (np.max(np.abs(x)) + 1e-12))


def normalize_punch(x, rms_db=-14.0, peak_db=-1.0, win=0.1):
    """For one-shots: set the loudest `win`-second window RMS to rms_db, then limit."""
    m = mono(x)
    w = int(win * SR)
    if len(m) <= w:
        r = np.sqrt(np.mean(m ** 2))
    else:
        c = np.cumsum(np.concatenate([[0], m ** 2]))
        r = np.sqrt(np.max(c[w:] - c[:-w]) / w)
    return limit(x * (db(rms_db) / (r + 1e-12)), peak_db)


def _movmin(a, w):
    # sliding-window minimum (centered-left) via doubling trick
    out = a.copy()
    k = 1
    while k < w:
        s = min(k, w - k)
        out[:-s] = np.minimum(out[:-s], out[s:])
        k += s
    return out


def limit(x, peak_db=-1.0, look=0.004, release=0.08):
    """Look-ahead limiter. need = gain required per sample; forward moving-min over the
    look-ahead window then a trailing box blur of the same length guarantees g <= need
    everywhere (no overs) with a smooth attack; a longer trailing blur gives the release."""
    x = np.asarray(x, dtype=np.float64)
    thr = db(peak_db) * 0.995
    a = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    need = np.minimum(1.0, thr / (a + 1e-12))
    if need.min() >= 1.0:
        return x
    w = max(2, int(look * SR))
    g = _movmin(need, w)
    g2 = np.convolve(np.concatenate([np.full(w - 1, g[0]), g]), np.ones(w) / w, mode='valid')
    rw = max(2, int(release * SR))
    gr = np.convolve(np.concatenate([np.full(rw - 1, g2[0]), g2]), np.ones(rw) / rw, mode='valid')
    g3 = np.minimum(np.minimum(g2, gr), need)
    return x * (g3[:, None] if x.ndim == 2 else g3)


# ---------------------------------------------------------------- filters (zero-phase FFT)
def _apply_mag(x, H_fn, pad=0):
    x = np.asarray(x, dtype=np.float64)
    n = len(x) + pad
    N = 1 << int(np.ceil(np.log2(max(n, 2))))
    f = np.fft.rfftfreq(N, 1 / SR)
    H = H_fn(f)
    X = np.fft.rfft(x, N, axis=0)
    y = np.fft.irfft(X * (H[:, None] if x.ndim == 2 else H), N, axis=0)
    return y[:len(x)]


def lowpass(x, fc, order=2):
    return _apply_mag(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return _apply_mag(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return _apply_mag(x, lambda f: 1 / np.sqrt(1 + (f / hi) ** (2 * order)) / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order)))


def peak_eq(x, fc, gain_db, q=1.0):
    def H(f):
        bw = fc / q
        return 1 + (db(gain_db) - 1) / (1 + ((f - fc) / (bw / 2)) ** 2)
    return _apply_mag(x, H)


def shelf(x, fc, gain_db, high=True):
    def H(f):
        r = (f / fc) ** 2
        s = r / (1 + r) if high else 1 / (1 + r)
        return 1 + (db(gain_db) - 1) * s
    return _apply_mag(x, H)


def resonator_bank(n, freqs, decays, amps, phases=None):
    """Sum of exponentially decaying sines (modal synthesis)."""
    t = np.arange(n) / SR
    y = np.zeros(n)
    for i, (f, d, a) in enumerate(zip(freqs, decays, amps)):
        ph = 0 if phases is None else phases[i]
        y += a * np.sin(TAU * f * t + ph) * np.exp(-t / d)
    return y


# ---------------------------------------------------------------- envelopes & utilities
def env_adsr(n, a, d, s, r, sustain_len=None):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n) if sustain_len is None else int(sustain_len * SR)
    e = np.concatenate([np.linspace(0, 1, a_n, endpoint=False) ** 1.5 if a_n else [],
                        np.linspace(1, s, d_n, endpoint=False) if d_n else [],
                        np.full(s_n, s), np.linspace(s, 0, r_n) if r_n else []])
    e = np.concatenate([e, np.zeros(max(0, n - len(e)))])[:n]
    return e


def fade(x, fin=0.003, fout=0.01):
    x = np.array(x, dtype=np.float64)
    a, b = int(fin * SR), int(fout * SR)
    if a:
        w = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        x[:a] *= w[:, None] if x.ndim == 2 else w
    if b:
        w = np.cos(np.linspace(0, np.pi / 2, b)) ** 2
        x[-b:] *= w[:, None] if x.ndim == 2 else w
    return x


def trim(x, thresh_db=-50.0, pad_in=0.005, pad_out=0.05, rel=True):
    """Trim leading/trailing silence relative to peak; gentle fades at the cuts."""
    m = np.abs(mono(x))
    w = int(0.005 * SR)
    e = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, mode='same'))
    ref = e.max() if rel else 1.0
    idx = np.where(e > ref * db(thresh_db))[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(pad_in * SR)); b = min(len(x), idx[-1] + int(pad_out * SR))
    return fade(x[a:b], 0.002, min(0.03, (b - a) / SR / 4))


def pan(x, p):
    """Equal-power pan, p in [-1, 1]."""
    x = mono(x)
    th = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(th), x * np.sin(th)], 1)


def mix_at(dst, src, t, gain=1.0):
    """Add src into dst at time t (seconds); stereo; wraps nothing (dst grows if needed)."""
    i = int(round(t * SR))
    src = stereo(src) * gain
    if i < 0:
        src = src[-i:]; i = 0
    end = i + len(src)
    if end > len(dst):
        dst = np.concatenate([dst, np.zeros((end - len(dst), 2))])
    dst[i:end] += src
    return dst


def mix_wrap(dst, src, t, gain=1.0):
    """Add src into a fixed-length (looping) buffer, wrapping around the end."""
    L = len(dst)
    i = int(round(t * SR)) % L
    src = stereo(src) * gain
    while len(src):
        k = min(len(src), L - i)
        dst[i:i + k] += src[:k]
        src = src[k:]; i = 0
    return dst


def resample(x, ratio):
    """Pitch/speed change by `ratio` (>1 = higher/shorter) with band-limited FFT-free cubic-ish interpolation."""
    x = np.asarray(x, dtype=np.float64)
    if ratio > 1.0:
        x = lowpass(x, 0.45 * SR / ratio, order=6)
    n = int(len(x) / ratio)
    pos = np.arange(n) * ratio
    if x.ndim == 2:
        return np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], 1)
    return np.interp(pos, np.arange(len(x)), x)


def varispeed(x, ratio_curve):
    """Time-varying resampling: ratio_curve is per-output-sample playback rate."""
    pos = np.cumsum(ratio_curve) - ratio_curve[0]
    pos = pos[pos < len(x) - 1]
    if x.ndim == 2:
        return np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], 1)
    return np.interp(pos, np.arange(len(x)), x)


# ---------------------------------------------------------------- reverb
def make_ir(t60=1.8, predelay=0.012, early=12, damp_hf=0.35, width=1.0, size=1.0, seed=7, bright=6000.0):
    """Synthetic stereo IR: sparse early reflections + exponentially decaying noise whose
    high frequencies decay faster (t60 scaled by damp_hf above `bright`)."""
    rng = np.random.default_rng(seed)
    n = int((t60 * 1.3 + predelay) * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    # diffuse tail, frequency-dependent decay: split into 4 bands
    edges = [0, 250, 1500, bright, SR / 2]
    t60s = [t60 * 1.15, t60, t60 * (0.55 + 0.45 * damp_hf), t60 * damp_hf]
    for c in range(2):
        nz = rng.standard_normal(n)
        tail = np.zeros(n)
        for (lo, hi), tt in zip(zip(edges[:-1], edges[1:]), t60s):
            if lo == 0:
                b = lowpass(nz, hi, 4)
            elif hi >= SR / 2:
                b = highpass(nz, lo, 4)
            else:
                b = bandpass(nz, lo, hi, 4)
            tail += b * np.exp(-6.9 * t / tt)
        # fade-in of the diffuse field
        tail *= 1 - np.exp(-t / (0.02 * size))
        ir[:, c] = tail
    # mix to adjust stereo width
    m = ir.mean(1, keepdims=True)
    ir = m + (ir - m) * width
    pd = int(predelay * SR)
    ir = np.concatenate([np.zeros((pd, 2)), ir])[:n]
    # early reflections
    for k in range(early):
        d = predelay + rng.uniform(0.004, 0.08) * size
        g = rng.uniform(0.25, 0.7) * np.exp(-d * 18)
        i = int(d * SR)
        ir[i, 0] += g * rng.choice([-1, 1]) * rng.uniform(0.6, 1.0)
        ir[i + int(rng.uniform(0, 0.0015) * SR), 1] += g * rng.choice([-1, 1]) * rng.uniform(0.6, 1.0)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    return ir


def convolve(x, ir):
    """Stereo FFT convolution, output length len(x)+len(ir)-1."""
    x = stereo(x)
    n = len(x) + len(ir) - 1
    N = 1 << int(np.ceil(np.log2(n)))
    X = np.fft.rfft(x, N, axis=0)
    H = np.fft.rfft(ir, N, axis=0)
    return np.fft.irfft(X * H, N, axis=0)[:n]


def reverb(x, ir, wet=0.25, dry=1.0, keep_len=False):
    x = stereo(x)
    y = convolve(x, ir) * wet
    y[:len(x)] += x * dry
    return y[:len(x)] if keep_len else y


def reverb_loop(x, ir, wet=0.25, dry=1.0):
    """Circular reverb for seamless loops: the tail wraps back onto the start."""
    x = stereo(x)
    L = len(x)
    y = convolve(x, ir) * wet
    out = x * dry
    for k in range(0, len(y), L):
        seg = y[k:k + L]
        out[:len(seg)] += seg
    return out


# ---------------------------------------------------------------- loops
def loop_crossfade(x, L, xf):
    """Make a seamless loop of length L from x (len >= L+xf): the head is
    equal-power crossfaded with the material just after L."""
    x = stereo(x)
    assert len(x) >= L + xf
    out = x[:L].copy()
    t = np.linspace(0, 1, xf)
    fi = np.sin(t * np.pi / 2); fo = np.cos(t * np.pi / 2)
    out[:xf] = x[:xf] * fi[:, None] + x[L:L + xf] * fo[:, None]
    return out


def loop_seam_report(x):
    """Discontinuity at the loop seam vs. typical sample-to-sample step."""
    x = stereo(x)
    d = np.abs(np.diff(x, axis=0)).mean()
    seam = np.abs(x[0] - x[-1]).max()
    return seam, d


# ---------------------------------------------------------------- stft (for source-filter vocal/brass synthesis)
def stft(x, n=2048, hop=256):
    w = np.hanning(n)
    pad = np.concatenate([np.zeros(n), x, np.zeros(n)])
    frames = np.lib.stride_tricks.sliding_window_view(pad, n)[::hop] * w
    return np.fft.rfft(frames, axis=1)


def istft(S, length, n=2048, hop=256):
    w = np.hanning(n)
    frames = np.fft.irfft(S, n, axis=1) * w
    out = np.zeros(len(frames) * hop + n)
    norm = np.zeros_like(out)
    for i, fr in enumerate(frames):
        out[i * hop:i * hop + n] += fr
        norm[i * hop:i * hop + n] += w ** 2
    out /= np.maximum(norm, 1e-6)
    return out[n:n + length]


def formant_filter(src, formant_tracks, n=2048, hop=256, tilt_db_per_oct=0.0):
    """Time-varying spectral envelope. formant_tracks(t_array) -> list of (freq[t], bw[t], gain[t])."""
    S = stft(src, n, hop)
    T = S.shape[0]
    t = (np.arange(T) * hop - n) / SR
    f = np.fft.rfftfreq(n, 1 / SR)
    env = np.zeros((T, len(f))) + 1e-3
    for (F, B, G) in formant_tracks(t):
        env += G[:, None] / (1 + ((f[None, :] - F[:, None]) / (B[:, None] / 2)) ** 2)
    if tilt_db_per_oct:
        env *= (np.maximum(f, 50) / 500.0) ** (tilt_db_per_oct / 6.02)
    return istft(S * env, len(src), n, hop)


def save_checked(path, x, lufs_target=None, tp_max=-1.0, peak_db=-1.5, quality=0.6):
    """Save, then measure the encoded file with ffmpeg's ebur128 (integrated loudness and true
    peak) and correct: gain towards `lufs_target` (if given) and a lower limiter ceiling whenever
    the encoded true peak would exceed `tp_max`."""
    ceil = peak_db
    x = limit(x, ceil)
    I, TP = -99.0, 0.0
    for _ in range(4):
        save(path, x, quality)
        I, TP = ebur128(path)
        g = (lufs_target - I) if (lufs_target is not None and I > -90) else 0.0
        over = TP + g - tp_max
        if abs(g) < 0.3 and over <= 0:
            break
        if over > 0:
            ceil -= over + 0.15
        x = limit(x * db(g), ceil)
    return I, TP
