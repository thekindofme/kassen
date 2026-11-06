"""Shared image helpers for the KASSEN art pipeline (numpy + PIL only, no scipy/cv2)."""
import numpy as np
from PIL import Image


def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255.0


def key_magenta(rgb, lo=0.30, hi=0.62):
    """Return (rgb_despilled, alpha) from an RGB float image on #FF00FF.

    'magentaness' m = min(R,B) - G: ~1.0 on the background, ~0 on neutral/red/blue subject
    pixels. Alpha ramps from 1 (m<=lo) to 0 (m>=hi), giving soft anti-aliased edges.
    Despill: the colour is un-mixed from magenta for edge pixels, then any remaining
    magenta cast (min(R,B) > G) is pulled back towards neutral.
    """
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = np.minimum(r, b) - g
    alpha = np.clip((hi - m) / (hi - lo), 0.0, 1.0)
    out = rgb.copy()
    # un-premultiply against the magenta background for partially transparent pixels
    bg = np.array([1.0, 0.0, 1.0], np.float32)
    a = alpha[..., None]
    with np.errstate(divide="ignore", invalid="ignore"):
        un = (rgb - (1 - a) * bg) / np.maximum(a, 1e-3)
    out = np.where((a > 0.02) & (a < 0.98), np.clip(un, 0, 1), out)
    # despill: limit R and B so that min(R,B) <= G + small tolerance
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    spill = np.clip(np.minimum(r, b) - g - 0.01, 0, None)
    out[..., 0] = r - spill
    out[..., 2] = b - spill
    alpha[alpha < 0.04] = 0.0
    return out, alpha


def label(mask):
    """8-connected component labelling via run-length union-find. Returns (labels, n)."""
    h, w = mask.shape
    parent = [0]

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    runs_prev = []  # (start, end, label) for previous row
    lab = np.zeros((h, w), np.int32)
    for y in range(h):
        row = mask[y]
        d = np.diff(np.concatenate(([0], row.astype(np.int8), [0])))
        starts = np.flatnonzero(d == 1)
        ends = np.flatnonzero(d == -1)  # exclusive
        runs = []
        j = 0
        for s, e in zip(starts, ends):
            cur = 0
            # advance j over prev runs that end before s-1
            while j < len(runs_prev) and runs_prev[j][1] < s:  # prev end(excl) < s  -> no 8-touch
                j += 1
            k = j
            while k < len(runs_prev) and runs_prev[k][0] <= e:  # prev start <= e (8-conn)
                pl = find(runs_prev[k][2])
                if cur == 0:
                    cur = pl
                elif pl != cur:
                    a, b = sorted((pl, cur))
                    parent[b] = a
                    cur = a
                k += 1
            if cur == 0:
                cur = len(parent)
                parent.append(cur)
            runs.append((s, e, cur))
            lab[y, s:e] = cur
        runs_prev = runs
    # flatten
    lut = np.zeros(len(parent), np.int32)
    nxt = 0
    roots = {}
    for i in range(1, len(parent)):
        r = find(i)
        if r not in roots:
            nxt += 1
            roots[r] = nxt
        lut[i] = roots[r]
    return lut[lab], nxt


def premul_resize(rgb, alpha, size):
    """Resize RGB+alpha with premultiplied alpha (no dark/pink fringes). size=(w,h)."""
    pm = np.concatenate([rgb * alpha[..., None], alpha[..., None]], axis=-1)
    chans = []
    for c in range(4):
        im = Image.fromarray(pm[..., c].astype(np.float32), mode="F")
        chans.append(np.asarray(im.resize(size, Image.LANCZOS)))
    pm2 = np.clip(np.stack(chans, -1), 0, 1)
    a = pm2[..., 3]
    with np.errstate(divide="ignore", invalid="ignore"):
        col = np.where(a[..., None] > 1e-4, pm2[..., :3] / np.maximum(a[..., None], 1e-4), 0)
    return np.clip(col, 0, 1), a


def to_rgba8(rgb, alpha):
    arr = np.concatenate([rgb, alpha[..., None]], -1)
    arr = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    # zero colour under fully transparent pixels -> clean filtering in engine (use edge bleed instead)
    return arr


def bleed(rgba, iters=4):
    """Extend edge colours into transparent pixels (keeps alpha) so bilinear sampling has no dark halo."""
    rgb = rgba[..., :3].astype(np.float32)
    a = rgba[..., 3] > 0
    for _ in range(iters):
        acc = np.zeros_like(rgb); cnt = np.zeros(a.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh_a = np.roll(a, (dy, dx), (0, 1)); sh = np.roll(rgb, (dy, dx), (0, 1))
            acc += sh * sh_a[..., None]; cnt += sh_a
        grow = (~a) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        a = a | grow
    out = rgba.copy(); out[..., :3] = rgb.astype(np.uint8)
    return out


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1); mn = rgb.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r); gm = nz & (mx == g) & ~rm; bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    h = (h % 360) / 60.0
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (a, b_, c) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        m = i == k
        out[m, 0] = a[m]; out[m, 1] = b_[m]; out[m, 2] = c[m]
    return out
