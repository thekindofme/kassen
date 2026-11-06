#!/usr/bin/env python3
"""Process environment, FX, art and UI raw images into game assets.

    python3 tools/build_env.py [terrain] [props] [fx] [art] [ui]   (default: all)

terrain : art_src/raw/tex_*.png  -> assets/terrain/<name>.png (1024², seamless, graded to the art-bible palette)
props   : art_src/raw/prop_*.png -> assets/props/<sheet>_<n>.png + props.json  (stored at PROP_SCALE x world)
fx      : art_src/raw/fx_sheet.png -> assets/fx/<kind>_<n>.png + fx.json
art     : art_src/raw/art_*.png -> assets/art/<name>.png ; portrait_* -> assets/art/portrait_<u>_{512,256}.png
ui      : ui_mon_* -> assets/ui/mon_<clan>_{512,128}.png ; ui_lacquer/ui_washi -> assets/ui/<name>.png (seamless)
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kassen_img import load_rgb, key_magenta, label, premul_resize, to_rgba8, bleed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_src", "raw")
A = os.path.join(ROOT, "assets")
REVIEW = os.path.join(ROOT, "art_src", "review")
report = []


def save(arr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(arr).save(path, optimize=True)


def luma(c):
    return c[..., 0] * 0.299 + c[..., 1] * 0.587 + c[..., 2] * 0.114


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


# ---------------------------------------------------------------- terrain
# target mean colours (art bible ground palette), all at a similar mean luminance (~0.36-0.41)
TERRAIN = {
    "grass": "#5F7139", "meadow": "#837D4B", "dirt": "#7A5A3A", "mud": "#685036",
    "forestfloor": "#525A36", "riverbed": "#3E5A63", "sand": "#7E745E", "paddy": "#56694A",
}
TEX_LUMA = {"forestfloor": 0.34, "riverbed": 0.33, "mud": 0.35}  # default 0.37: one shared mean luminance
TEX_SAT = 0.65      # saturation multiplier (soldiers must pop against the ground)
TEX_STD = 0.075     # common luma standard deviation (contrast)


def seam_score(img):
    """Mean abs difference across the wrap seam relative to the mean neighbour difference inside."""
    inner = np.abs(np.diff(img, axis=1)).mean() + np.abs(np.diff(img, axis=0)).mean()
    wrap = np.abs(img[:, 0] - img[:, -1]).mean() + np.abs(img[0] - img[-1]).mean()
    return wrap / max(inner, 1e-6)


def make_seamless(img, border=0.22):
    """Offset-and-blend: blend with the half-offset copy near the edges so the wrap is continuous."""
    h, w = img.shape[:2]
    sh = np.roll(img, (h // 2, w // 2), (0, 1))

    def ramp(n):
        t = np.minimum(np.arange(n), np.arange(n)[::-1]) / (n * border)
        t = np.clip(t, 0, 1)
        return t * t * (3 - 2 * t)

    wgt = np.outer(ramp(h), ramp(w))[..., None]
    return img * wgt + sh * (1 - wgt)


def grade(img, target):
    y = luma(img)[..., None]
    img = y + (img - y) * TEX_SAT
    gain = target / np.maximum(img.reshape(-1, 3).mean(0), 1e-3)
    img = img * gain
    y = luma(img); m = y.mean(); sd = y.std()
    k = np.clip(TEX_STD / max(sd, 1e-3), 0.6, 1.4)
    img = img.mean((0, 1)) + (img - img.mean((0, 1))) * k
    return np.clip(img, 0, 1)


def terrain():
    out = os.path.join(A, "terrain"); os.makedirs(out, exist_ok=True)
    tiles = []
    for name, tgt in TERRAIN.items():
        im = Image.open(os.path.join(RAW, f"tex_{name}.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS)
        img = np.asarray(im).astype(np.float32) / 255
        s0 = seam_score(img)
        fixed = s0 > 1.6
        if fixed:
            img = make_seamless(img)
        t = hexc(tgt)
        t = t * TEX_LUMA.get(name, 0.37) / luma(t)
        img = grade(img, t)
        s1 = seam_score(img)
        arr = (img * 255 + .5).astype(np.uint8)
        save(arr, os.path.join(out, f"{name}.png"))
        report.append(f"terrain {name}: seam {s0:.2f} -> {s1:.2f} {'(offset-blend fixed)' if fixed else ''} "
                      f"mean {arr.reshape(-1, 3).mean(0).round().astype(int).tolist()} luma {luma(img).mean():.3f} sd {luma(img).std():.3f}")
        tiles.append((name, arr))
    # review: each texture tiled 2x2 (seams visible at the centre cross), plus a splat-style blend strip
    cw = 384
    sheet = Image.new("RGB", (cw * 4, (cw + 18) * 2), (30, 30, 30)); d = ImageDraw.Draw(sheet)
    for i, (n, arr) in enumerate(tiles):
        t = Image.fromarray(np.tile(arr, (2, 2, 1))).resize((cw, cw), Image.LANCZOS)
        x, y = (i % 4) * cw, (i // 4) * (cw + 18)
        sheet.paste(t, (x, y + 18)); d.text((x + 4, y + 3), n, fill=(255, 255, 0))
    os.makedirs(REVIEW, exist_ok=True)
    sheet.save(os.path.join(REVIEW, "terrain_tiled.jpg"), quality=85)


# ---------------------------------------------------------------- props
PROP_SCALE = 2.0
# sheet -> (kind per item or single kind, tallest item height in world px)
PROPS = {
    "pines": ("tree", 160), "maples": ("tree", 150), "bamboo": ("bamboo", 150), "rocks": ("rock", 64),
    "houses": ("house", 170), "shrine": ("shrine", 150), "fences": ("fence", 58), "camp": ("camp", 140),
    "bushes": ("bush", 34),
}


PROP_MERGE = {"camp": 6}  # weapon rack sits close under the maku enclosure


def cutouts(rgb, alpha, merge_px, min_frac=0.01):
    """Group keyed pixels into objects: dilate by merge_px, label, return list of (mask, bbox) in reading order."""
    solid = alpha > 0.5
    lab, n = label(solid)
    ar = np.bincount(lab.ravel()); ar[0] = 0
    keep = ar >= 40
    solid = keep[lab]
    alpha = np.where(solid | (alpha < 0.5), alpha, 0)
    # coarse grouping on a downsampled mask (fast), then map back
    f = 4
    h, w = solid.shape
    small = solid[:h // f * f, :w // f * f].reshape(h // f, f, w // f, f).any((1, 3))
    grown = small.copy()
    for _ in range(max(1, merge_px // f)):
        grown = grown | np.roll(grown, 1, 0) | np.roll(grown, -1, 0) | np.roll(grown, 1, 1) | np.roll(grown, -1, 1)
    glab, gn = label(grown)
    full = np.zeros((h, w), np.int32)
    full[:h // f * f, :w // f * f] = np.repeat(np.repeat(glab, f, 0), f, 1)
    soft = alpha > 0
    # make sure soft pixels get a group (dilate full labels a little)
    for _ in range(3):
        for ax, s in ((0, 1), (0, -1), (1, 1), (1, -1)):
            sh = np.roll(full, s, ax); m = (full == 0) & (sh > 0); full[m] = sh[m]
    objs = []
    areas = [((full == g) & solid).sum() for g in range(1, gn + 1)]
    amax = max(areas) if areas else 0
    for g in range(1, gn + 1):
        if areas[g - 1] < min_frac * amax:
            continue
        m = (full == g) & soft
        ys, xs = np.nonzero(m)
        objs.append((m, (ys.min(), ys.max() + 1, xs.min(), xs.max() + 1)))
    # reading order: rows (by bottom, tolerance) then x
    hs = np.median([b[1] - b[0] for _, b in objs]) if objs else 1
    objs.sort(key=lambda o: (round(((o[1][0] + o[1][1]) / 2) / (hs * 0.9)), o[1][2]))
    return objs, alpha


def export_obj(rgb, alpha, m, bb, s):
    y0, y1, x0, x1 = bb
    a = np.where(m[y0:y1, x0:x1], alpha[y0:y1, x0:x1], 0)
    c = rgb[y0:y1, x0:x1]
    h, w = a.shape
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    c2, a2 = premul_resize(c, a, (nw, nh))
    a2[a2 < 0.03] = 0
    rgba = bleed(np.pad(to_rgba8(c2, a2), ((2, 2), (2, 2), (0, 0))))
    # foot anchor: bottom of the opaque mass, x = centroid of the lowest 12% of rows
    sol = rgba[..., 3] > 128
    rows = np.flatnonzero(sol.any(1))
    b = rows[-1]; t = rows[0]
    band = sol[max(t, int(b - 0.12 * (b - t))):b + 1]
    cols = band.sum(0).astype(float)
    ax = float((cols * np.arange(len(cols))).sum() / max(cols.sum(), 1))
    return rgba, ax, float(b)


def props():
    out = os.path.join(A, "props"); os.makedirs(out, exist_ok=True)
    meta = {"_scale": PROP_SCALE, "_note": "w,h,ax,ay in image px; image px = world px * _scale; anchor = foot (ground contact)"}
    review = []
    for sheet, (kind, tallest) in PROPS.items():
        rgb, alpha = key_magenta(load_rgb(os.path.join(RAW, f"prop_{sheet}.png")))
        objs, alpha = cutouts(rgb, alpha, merge_px=PROP_MERGE.get(sheet, 24))
        hmax = max(b[1] - b[0] for _, b in objs)
        s = tallest * PROP_SCALE / hmax
        for i, (m, bb) in enumerate(objs):
            rgba, ax, ay = export_obj(rgb, alpha, m, bb, s)
            name = f"{sheet}_{i}"
            save(rgba, os.path.join(out, f"{name}.png"))
            meta[name] = {"w": rgba.shape[1], "h": rgba.shape[0], "ax": round(ax, 1), "ay": round(ay, 1), "kind": kind,
                          "world_h": round(rgba.shape[0] / PROP_SCALE, 1)}
            review.append((name, rgba, ax, ay))
        report.append(f"props {sheet}: {len(objs)} objects, factor {s:.3f}")
    with open(os.path.join(out, "props.json"), "w") as f:
        json.dump(meta, f, indent=1)
    contact_props(review, "props_contact.jpg")


def contact_props(items, fname):
    cw, ch = 300, 360
    cols = 8
    rows = (len(items) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw, rows * ch), (95, 113, 57)); d = ImageDraw.Draw(img)
    for i, (n, rgba, ax, ay) in enumerate(items):
        x, y = (i % cols) * cw, (i // cols) * ch
        t = Image.fromarray(rgba)
        sc = min(1.0, (cw - 10) / t.width, (ch - 30) / t.height)
        if sc < 1:
            t = t.resize((max(1, int(t.width * sc)), max(1, int(t.height * sc))), Image.LANCZOS)
        bx, by = x + cw // 2, y + ch - 10
        img.paste(t, (int(bx - ax * sc), int(by - ay * sc)), t)
        d.line([bx - 6, by, bx + 6, by], fill=(255, 255, 0)); d.line([bx, by - 6, bx, by + 6], fill=(255, 255, 0))
        d.text((x + 4, y + 3), n, fill=(255, 255, 255))
    img.save(os.path.join(REVIEW, fname), quality=85)


# ---------------------------------------------------------------- fx
# dust keys pink (brown semi-transparent over magenta cannot be un-mixed reliably) -> dropped; the
# engine makes dust procedurally. Smoke keys cleanly (neutral grey) and is kept as an optional texture.
FX_KEEP = {"blood", "flash", "smoke"}


def fx():
    out = os.path.join(A, "fx"); os.makedirs(out, exist_ok=True)
    rgb = load_rgb(os.path.join(RAW, "fx_sheet.png"))
    # linear key: FX are semi-transparent over magenta -> alpha = 1 - magentaness, colour un-mixed
    c, a = key_magenta(rgb, lo=0.0, hi=1.0)
    a = np.clip((a - 0.06) / 0.94, 0, 1)
    objs, a = cutouts(c, a, merge_px=12, min_frac=0.05)
    counts = {}
    meta = {}
    review = []
    for m, bb in objs:
        y0, y1, x0, x1 = bb
        sel = m[y0:y1, x0:x1] & (a[y0:y1, x0:x1] > 0.3)
        col = c[y0:y1, x0:x1][sel].mean(0)
        r, g, b = col
        if r > 0.8 and g > 0.5:
            kind = "flash"
        elif r > 2.0 * g and r > 1.8 * b:
            kind = "blood"
        elif abs(r - b) < 0.08 and r > 0.55:
            kind = "smoke"
        else:
            kind = "dust"
        if kind not in FX_KEEP:
            counts["dropped_" + kind] = counts.get("dropped_" + kind, 0) + 1
            continue
        n = counts.get(kind, 0); counts[kind] = n + 1
        rgba, ax, ay = export_obj(c, a, m, bb, 0.5)
        name = f"{kind}_{n}"
        save(rgba, os.path.join(out, f"{name}.png"))
        meta[name] = {"w": rgba.shape[1], "h": rgba.shape[0], "kind": kind}
        review.append((name, rgba, rgba.shape[1] / 2, rgba.shape[0] - 3))
    with open(os.path.join(out, "fx.json"), "w") as f:
        json.dump(meta, f, indent=1)
    report.append(f"fx: {counts}")
    contact_props(review, "fx_contact.jpg")


# ---------------------------------------------------------------- art / portraits / ui
PORTRAIT_CX = {}  # per-portrait horizontal centre override (fraction), tuned in QA


def art():
    out = os.path.join(A, "art"); os.makedirs(out, exist_ok=True)
    for f in sorted(os.listdir(RAW)):
        if f.startswith("art_") and f.endswith(".png"):
            im = Image.open(os.path.join(RAW, f)).convert("RGB")
            im = im.resize((1920, 1080), Image.LANCZOS)
            im.save(os.path.join(out, f[4:-4] + ".jpg"), quality=92)
            report.append(f"art {f}: -> assets/art/{f[4:-4]}.jpg 1920x1080")
        if f.startswith("portrait_") and f.endswith(".png"):
            im = Image.open(os.path.join(RAW, f)).convert("RGB")
            w, h = im.size
            u = f[9:-4]
            side = min(w, h)
            cx = PORTRAIT_CX.get(u, 0.5) * w
            x0 = int(np.clip(cx - side / 2, 0, w - side))
            sq = im.crop((x0, 0, x0 + side, side))
            for s in (512, 256):
                sq.resize((s, s), Image.LANCZOS).save(os.path.join(out, f"portrait_{u}_{s}.png"), optimize=True)
            report.append(f"portrait {u}: crop x0={x0} side={side}")


def ui():
    out = os.path.join(A, "ui"); os.makedirs(out, exist_ok=True)
    for clan in ("hino", "mizuno"):
        rgb, a = key_magenta(load_rgb(os.path.join(RAW, f"ui_mon_{clan}.png")))
        lab, n = label(a > 0.5)
        ar = np.bincount(lab.ravel()); ar[0] = 0
        a = np.where((ar < 200)[lab] & (a > 0.5), 0, a)
        ys, xs = np.nonzero(a > 0)
        cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
        side = int(max(ys.max() - ys.min(), xs.max() - xs.min()) * 1.04)
        y0, x0 = int(cy - side / 2), int(cx - side / 2)
        pad = lambda z: np.pad(z, ((side, side), (side, side)) + ((0, 0),) * (z.ndim - 2))
        c2 = pad(rgb)[y0 + side:y0 + 2 * side, x0 + side:x0 + 2 * side]
        a2 = pad(a)[y0 + side:y0 + 2 * side, x0 + side:x0 + 2 * side]
        for s in (512, 128):
            cc, aa = premul_resize(c2, a2, (s, s))
            save(bleed(to_rgba8(cc, aa)), os.path.join(out, f"mon_{clan}_{s}.png"))
        report.append(f"ui mon_{clan}: keyed, square {side}px -> 512/128")
    for name in ("lacquer", "washi"):
        im = Image.open(os.path.join(RAW, f"ui_{name}.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS)
        img = np.asarray(im).astype(np.float32) / 255
        s0 = seam_score(img)
        if s0 > 1.6:
            img = make_seamless(img)
        save((img * 255 + .5).astype(np.uint8), os.path.join(out, f"{name}.png"))
        report.append(f"ui {name}: seam {s0:.2f} -> {seam_score(img):.2f}")


if __name__ == "__main__":
    steps = sys.argv[1:] or ["terrain", "props", "fx", "art", "ui"]
    os.makedirs(REVIEW, exist_ok=True)
    for s in steps:
        globals()[s]()
    print("\n".join(report))
    with open(os.path.join(REVIEW, "env_report.txt"), "a") as f:
        f.write("\n".join(report) + "\n")
