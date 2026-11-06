#!/usr/bin/env python3
"""Build the KASSEN unit atlas from raw 8-frame magenta sheets.

    python3 tools/build_atlas.py            # all units
    python3 tools/build_atlas.py --units yari teppo

Inputs : art_src/raw/unit_<type>_<anim>.png   (8 frames, one row, #FF00FF, facing right, crimson)
Outputs: assets/atlas/units.png + units.json  (TECH.md contract, scale 3.0)
         art_src/review/units_contact.png      (QA contact sheet, anchors marked)
         art_src/review/atlas_report.txt       (per-sheet stats / flags)
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kassen_img import load_rgb, key_magenta, label, premul_resize, to_rgba8, bleed
from recolor import to_mizuno

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_src", "raw")
OUT = os.path.join(ROOT, "assets", "atlas")
REVIEW = os.path.join(ROOT, "art_src", "review")
SCALE = 3.0
NFR = 8
ANIMS = {"yari": ["idle", "walk", "attack", "death"], "yumi": ["idle", "walk", "shoot", "death"],
         "teppo": ["idle", "walk", "fire", "death"], "samurai": ["idle", "walk", "attack", "death"],
         "cavalry": ["idle", "walk", "attack", "death"], "general": ["idle", "walk", "attack", "death"]}
# target figure height in world px (feet -> top of head/helmet; mounted: hooves -> rider helmet)
TARGET_H = {"yari": 44, "yumi": 44, "teppo": 44, "samurai": 46, "cavalry": 64, "general": 64}
MOUNTED = {"cavalry", "general"}
FIRE_FRAME = {"teppo": {"fire": 3}, "yumi": {"shoot": 4}}  # shot/release frame (0-based), see QA.md


# reference height per anim, as a fraction of the standing (idle) figure height:
#   mode 'median' -> median frame height; 'first' -> frame 0 (death starts standing); 'max' -> tallest frame
POSE_REF = {"idle": ("median", 1.0), "walk": ("median", 0.97), "attack": ("max", 0.97), "shoot": ("max", 1.0),
            "fire": ("max", 1.0), "death": ("first", 1.0)}
POSE_OVERRIDE = {}
AREA_TWEAK = {("yari", "walk"): 0.85}  # (unit, anim) -> extra multiplier, tuned during QA


def sheet_ref_height(unit, anim, fr):
    mode, frac = POSE_OVERRIDE.get((unit, anim), POSE_REF[anim])
    hs = [f["ay"] - f["top"] for f in fr]
    v = {"median": float(np.median(hs)), "first": hs[0], "max": max(hs)}[mode]
    return v / frac


def erode(mask, r):
    m = mask.copy()
    for _ in range(r):
        m = m & np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    return m


def dilate_labels(lab, r):
    out = lab.copy()
    for _ in range(r):
        for ax, s in ((0, 1), (0, -1), (1, 1), (1, -1)):
            sh = np.roll(out, s, ax)
            fill = (out == 0) & (sh > 0)
            out[fill] = sh[fill]
    return out


def split_frames(alpha, name, log):
    """Return an ownership map (H,W) int with values 1..8 per frame (0 = background) and flags."""
    flags = []
    solid = alpha > 0.5
    lab, n = label(solid)
    areas = np.bincount(lab.ravel(), minlength=n + 1); areas[0] = 0
    # bounding boxes / centres
    ys, xs = np.nonzero(lab)
    ll = lab[ys, xs]
    x0 = np.full(n + 1, 1 << 30); x1 = np.zeros(n + 1, int); y0 = np.full(n + 1, 1 << 30); y1 = np.zeros(n + 1, int)
    np.minimum.at(x0, ll, xs); np.maximum.at(x1, ll, xs); np.minimum.at(y0, ll, ys); np.maximum.at(y1, ll, ys)
    cx = np.zeros(n + 1); np.add.at(cx, ll, xs); cx = cx / np.maximum(areas, 1)
    order = np.argsort(-areas)
    top = areas[order[:NFR]]
    thr = 0.25 * np.median(top[top > 0]) if len(top) else 0
    bodies = [int(i) for i in order if areas[i] >= thr and i > 0]
    specks = [i for i in range(1, n + 1) if areas[i] < 60]

    groups = [[b] for b in sorted(bodies, key=lambda i: cx[i])]
    gx = lambda g: sum(cx[i] * areas[i] for i in g) / sum(areas[i] for i in g)
    # too many bodies: merge closest neighbours (e.g. rider thrown off his horse)
    while len(groups) > NFR:
        d = [gx(groups[k + 1]) - gx(groups[k]) for k in range(len(groups) - 1)]
        k = int(np.argmin(d))
        groups[k] = groups[k] + groups.pop(k + 1)
        flags.append("merged-bodies")
    own = np.zeros_like(lab)
    cut_mode = len(groups) < NFR
    if cut_mode:
        # merged frames (spear touching neighbour): fall back to column-gap / column-minimum cuts
        flags.append(f"only {len(groups)} body comps -> column cuts")
        col = (alpha > 0.5).sum(0).astype(float)
        occ = np.flatnonzero(col > 0)
        L, R = occ[0], occ[-1]
        cuts = []
        for k in range(1, NFR):
            guess = L + (R - L) * k / NFR
            w = (R - L) / NFR * 0.3
            lo, hi = int(guess - w), int(guess + w)
            sm = np.convolve(col, np.ones(9) / 9, "same")
            cuts.append(lo + int(np.argmin(sm[lo:hi])))
        edges = [0] + cuts + [alpha.shape[1]]
        for k in range(NFR):
            sl = np.zeros_like(solid); sl[:, edges[k]:edges[k + 1]] = True
            own[solid & sl] = k + 1
    else:
        for k, g in enumerate(groups):
            for i in g:
                own[lab == i] = k + 1
        # assign remaining (non-speck) parts to the nearest frame body by horizontal distance
        gb = [(min(x0[i] for i in g), max(x1[i] for i in g)) for g in groups]
        body_set = {i for g in groups for i in g}
        for i in range(1, n + 1):
            if i in body_set or areas[i] < 60:
                continue
            c = cx[i]
            dist = [max(a - c, 0, c - b) for a, b in gb]
            # prefer overlap fraction for long thin parts (spears)
            ov = [max(0, min(x1[i], b) - max(x0[i], a)) for a, b in gb]
            k = int(np.argmax(ov)) if max(ov) > 0 else int(np.argmin(dist))
            own[lab == i] = k + 1
    # soft edge pixels -> nearest owner
    own = dilate_labels(own, 3)
    own[alpha <= 0] = 0
    return own, flags


def frame_metrics(a, mounted):
    """a: cropped alpha of one frame (full res). Returns (anchor_x, anchor_y, fig_top, fig_len)."""
    m = erode(a > 0.5, 5)
    if m.sum() < 50:
        m = a > 0.5
    rows = np.flatnonzero(m.any(1))
    t, b = rows[0], rows[-1]
    rw = m.sum(1)
    big = np.flatnonzero(rw > 0.25 * rw.max())
    top = big[0]
    h = b - top
    band = m[int(top + 0.30 * h):int(top + 0.85 * h) + 1]
    if band.sum() == 0:
        band = m
    cols = band.sum(0).astype(float)
    ax = float((cols * np.arange(len(cols))).sum() / cols.sum())
    ay = float(b + 5)  # compensate for the erosion
    occ = np.flatnonzero(m.any(0))
    return ax, ay, float(top - 5), float(occ[-1] - occ[0] + 10), float(m.sum())


def process_sheet(unit, anim, log):
    path = os.path.join(RAW, f"unit_{unit}_{anim}.png")
    rgb = load_rgb(path)
    rgb, alpha = key_magenta(rgb)
    own, flags = split_frames(alpha, f"{unit}_{anim}", log)
    frames = []
    for k in range(1, NFR + 1):
        sel = own == k
        if not sel.any():
            flags.append(f"frame {k} empty"); continue
        ys, xs = np.nonzero(sel)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        a = np.where(sel[y0:y1, x0:x1], alpha[y0:y1, x0:x1], 0)
        c = rgb[y0:y1, x0:x1]
        ax, ay, top, ln, area = frame_metrics(a, unit in MOUNTED)
        frames.append(dict(rgb=c, a=a, ax=ax, ay=ay, top=top, len=ln, area=area))
    if len(frames) != NFR:
        flags.append(f"{len(frames)} frames")
    # teppo fire: strip the generated muzzle flash + smoke (the engine draws its own FX)
    if unit == "teppo" and anim == "fire" and len(frames) == NFR:
        for f in frames[3:5]:
            c = f["rgb"]; v = c.max(-1); s = (v - c.min(-1)) / np.maximum(v, 1e-3)
            H = f["ay"] - f["top"]
            hot = (v > 0.62) & ((s < 0.45) | ((c[..., 0] > 0.75) & (c[..., 1] > 0.35)))
            front = np.zeros_like(hot); front[:, int(f["ax"] + 0.30 * H):] = True
            above = np.zeros_like(hot); above[:int(f["top"] + 0.10 * H)] = True
            kill = hot & (front | above)
            # grow the kill mask a little to catch the soft glow edges
            for _ in range(3):
                kill = kill | (np.roll(kill, 1, 0) | np.roll(kill, -1, 0) | np.roll(kill, 1, 1) | np.roll(kill, -1, 1)) & (v > 0.5) & (front | above)
            f["a"][kill] = 0
            # drop now-isolated fragments in front of the muzzle
            lab, n = label(f["a"] > 0.3)
            if n > 1:
                ar = np.bincount(lab.ravel()); ar[0] = 0
                keep = ar >= 0.02 * ar.max()
                f["a"][~keep[lab]] = 0
        flags.append("teppo: stripped flash/smoke in frames 3-4")
    return frames, flags


def build(units, debug=False):
    os.makedirs(OUT, exist_ok=True); os.makedirs(REVIEW, exist_ok=True)
    report = []
    sprites = {}  # (unit, clan, anim) -> list of (rgba uint8, ax, ay)
    for unit in units:
        sheets = {}
        for anim in ANIMS[unit]:
            fr, fl = process_sheet(unit, anim, report)
            sheets[anim] = fr
            report.append(f"{unit}_{anim}: {len(fr)} frames {'; '.join(fl) if fl else 'OK'}")
        # Each generated sheet has its own drawing scale, so every sheet is normalised separately
        # from a pose-aware reference height (see POSE_REF).
        # idle is normalised by figure height; the other sheets by body *area* (thin weapons eroded away),
        # which is nearly pose-invariant (running crouch, lunge, lying corpse) unlike height.
        factors = {}
        idle_h = float(np.median([f["ay"] - f["top"] for f in sheets["idle"]]))
        f_idle = TARGET_H[unit] * SCALE / idle_h
        a_idle = float(np.median([f["area"] for f in sheets["idle"]]))
        for anim, fr in sheets.items():
            a_s = float(np.median([f["area"] for f in fr[:3]] if anim == "death" else [f["area"] for f in fr]))
            factors[anim] = f_idle * np.sqrt(a_idle / a_s) * AREA_TWEAK.get((unit, anim), 1.0)
            hs = [(f["ay"] - f["top"]) * factors[anim] / SCALE for f in fr]
            report.append(f"  {unit}_{anim}: factor {factors[anim]:.3f}  world height median {np.median(hs):.1f} max {max(hs):.1f}")
        lens = [f["len"] * factors["idle"] / SCALE for f in sheets["idle"]]
        report.append(f"{unit}: idle length {np.median(lens):.1f} world px")
        for anim, fr in sheets.items():
            s = factors[anim]
            for clan in ("hino", "mizuno"):
                out = []
                for f in fr:
                    h, w = f["a"].shape
                    nw, nh = max(1, round(w * s)), max(1, round(h * s))
                    col = f["rgb"] if clan == "hino" else to_mizuno(f["rgb"], f["a"], unit)
                    c2, a2 = premul_resize(col, f["a"], (nw, nh))
                    a2[a2 < 0.03] = 0
                    rgba = to_rgba8(c2, a2)
                    # trim + pad 2
                    nz = np.argwhere(rgba[..., 3] > 0)
                    (ty0, tx0), (ty1, tx1) = nz.min(0), nz.max(0) + 1
                    rgba = np.pad(rgba[ty0:ty1, tx0:tx1], ((2, 2), (2, 2), (0, 0)))
                    rgba = bleed(rgba)
                    ax = f["ax"] * nw / w - tx0 + 2
                    ay = f["ay"] * nh / h - ty0 + 2
                    out.append((rgba, ax, ay))
                sprites[(unit, clan, anim)] = out
    # stabilise: walk/idle anchor y = per-frame feet; ax smoothed to the anim median offset from frame centre? keep per-frame torso.
    # pack (shelf packer, tallest first)
    items = [(k, i, sp[0]) for k, lst in sprites.items() for i, sp in enumerate(lst)]
    items.sort(key=lambda t: -t[2].shape[0])
    W = 4096
    x = y = shelf_h = 0
    pos = {}
    for k, i, im in items:
        h, w = im.shape[:2]
        if x + w + 1 > W:
            x = 0; y += shelf_h + 1; shelf_h = 0
        pos[(k, i)] = (x, y)
        x += w + 1; shelf_h = max(shelf_h, h)
    H = y + shelf_h
    H = 1 << int(np.ceil(np.log2(max(H, 1))))
    assert H <= 4096, f"atlas overflow: {H}"
    atlas = np.zeros((H, W, 4), np.uint8)
    data = {"scale": SCALE, "units": {}, "fire_frame": {u: d for u, d in FIRE_FRAME.items() if u in units},
            "facing": "right", "frames": NFR}
    for (unit, clan, anim), lst in sprites.items():
        arr = []
        for i, (im, ax, ay) in enumerate(lst):
            px, py = pos[((unit, clan, anim), i)]
            h, w = im.shape[:2]
            atlas[py:py + h, px:px + w] = im
            arr.append({"x": int(px), "y": int(py), "w": int(w), "h": int(h), "ax": round(float(ax), 1), "ay": round(float(ay), 1)})
        data["units"].setdefault(unit, {}).setdefault(clan, {})[anim] = arr
    # crop unused height
    used = np.flatnonzero(atlas[..., 3].any(1))
    Image.fromarray(atlas).save(os.path.join(OUT, "units.png"), optimize=True)
    with open(os.path.join(OUT, "units.json"), "w") as f:
        json.dump(data, f, indent=1)
    report.append(f"atlas {W}x{H}, used rows {used[-1] + 1 if len(used) else 0}")
    contact(sprites, units)
    with open(os.path.join(REVIEW, "atlas_report.txt"), "w") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(report))


def contact(sprites, units):
    cell_w, cell_h, lab_w = 270, 230, 150
    rows = [(u, c, a) for u in units for c in ("hino", "mizuno") for a in ANIMS[u]]
    img = Image.new("RGB", (lab_w + NFR * cell_w, len(rows) * cell_h), (96, 112, 70))
    d = ImageDraw.Draw(img)
    for r, (u, c, a) in enumerate(rows):
        y = r * cell_h
        d.rectangle([0, y, img.width, y + cell_h - 1], fill=(92, 108, 66) if r % 2 else (104, 120, 76))
        d.text((6, y + 8), f"{u}\n{c}\n{a}", fill=(255, 255, 255))
        base = y + cell_h - 20
        for i, (im, ax, ay) in enumerate(sprites.get((u, c, a), [])):
            cx = lab_w + i * cell_w + cell_w // 2
            d.line([cx - 60, base, cx + 60, base], fill=(60, 70, 40))
            tile = Image.fromarray(im)
            img.paste(tile, (int(cx - ax), int(base - ay)), tile)
            d.line([cx - 5, base, cx + 5, base], fill=(255, 255, 0)); d.line([cx, base - 5, cx, base + 5], fill=(255, 255, 0))
    img.save(os.path.join(REVIEW, "units_contact.png"))
    # downscaled preview for quick viewing
    pv = img.copy(); pv.thumbnail((1800, 4000)); pv.save(os.path.join(REVIEW, "units_contact_small.jpg"), quality=85)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--units", nargs="*", default=list(ANIMS))
    a = ap.parse_args()
    build(a.units)
