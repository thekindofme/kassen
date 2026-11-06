"""Generate KASSEN UI textures (lacquer frames, washi panel, brush strokes, icons, particles).

Usage:  python3 tools/gen_ui_textures.py        (writes into assets/ui/)
Inputs: assets/ui/lacquer.png, assets/ui/washi.png (seamless 1024² painted textures).
Everything else is drawn procedurally with numpy + PIL so it can be re-tuned and re-run.
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
UI = os.path.join(ROOT, "assets", "ui")
GOLD = (201, 160, 74)
GOLD_HI = (240, 206, 128)
GOLD_LO = (120, 88, 36)
RNG = np.random.default_rng(1574)


def crop(path, x, y, w, h):
    return Image.open(path).convert("RGBA").crop((x, y, x + w, y + h))


def gold_line(d, box, width, col):
    d.rectangle(box, outline=col, width=width)


def corner_ornament(d, x, y, sx, sy, s, col, hi):
    """L-bracket with a little lozenge, mirrored by (sx, sy)."""
    L = s
    d.line([(x, y + sy * L), (x, y), (x + sx * L, y)], fill=col, width=3)
    d.line([(x + sx * 5, y + sy * (L - 6)), (x + sx * 5, y + sy * 5), (x + sx * (L - 6), y + sy * 5)], fill=hi, width=1)
    cx, cy, r = x + sx * 8, y + sy * 8, 4
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=hi)


def lacquer_frame(name, size=96, bright=1.0, fill_dark=1.0, glow=0.0):
    W = H = size
    base = crop(os.path.join(UI, "lacquer.png"), 300, 300, W, H)
    arr = np.asarray(base).astype(np.float32)
    # lift the near-black lacquer a touch and add a warm sheen from the top
    yy = np.linspace(0, 1, H)[:, None]
    sheen = (1.0 - yy) * 10.0
    arr[..., :3] = arr[..., :3] * 1.6 * fill_dark + 14 * fill_dark + sheen[..., None] * np.array([1.0, 0.75, 0.5])
    # inner vignette
    xx = np.linspace(-1, 1, W)[None, :]
    yv = np.linspace(-1, 1, H)[:, None]
    edge = np.clip(np.maximum(np.abs(xx), np.abs(yv)) - 0.6, 0, 1) / 0.4
    arr[..., :3] *= (1.0 - 0.45 * edge[..., None])
    arr[..., 3] = 255
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(im)
    g = tuple(int(min(255, c * bright)) for c in GOLD)
    gh = tuple(int(min(255, c * bright)) for c in GOLD_HI)
    d.rectangle((0, 0, W - 1, H - 1), outline=(10, 6, 4, 255), width=1)
    gold_line(d, (3, 3, W - 4, H - 4), 2, g)
    gold_line(d, (8, 8, W - 9, H - 9), 1, GOLD_LO + (255,))
    for (x, y, sx, sy) in [(3, 3, 1, 1), (W - 4, 3, -1, 1), (3, H - 4, 1, -1), (W - 4, H - 4, -1, -1)]:
        corner_ornament(d, x, y, sx, sy, 20, g, gh)
    if glow > 0:
        # soft gold glow inside the border
        m = Image.new("L", (W, H), 0)
        md = ImageDraw.Draw(m)
        md.rectangle((4, 4, W - 5, H - 5), outline=255, width=6)
        m = m.filter(ImageFilter.GaussianBlur(5))
        ga = np.asarray(m).astype(np.float32)[..., None] / 255.0 * glow
        a = np.asarray(im).astype(np.float32)
        a[..., :3] = a[..., :3] * (1 - ga) + np.array(GOLD_HI) * ga
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        d = ImageDraw.Draw(im)
        gold_line(d, (3, 3, W - 4, H - 4), 2, gh)
    im.save(os.path.join(UI, name))


def washi_panel(name, W=512, H=512):
    base = crop(os.path.join(UI, "washi.png"), 100, 100, W, H)
    arr = np.asarray(base).astype(np.float32)
    # deckled (torn) alpha edge
    a = np.ones((H, W), np.float32)
    n = RNG.random((H, W)).astype(np.float32)
    nimg = Image.fromarray((n * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    n = np.asarray(nimg).astype(np.float32) / 255.0
    xs = np.arange(W)[None, :]
    ys = np.arange(H)[:, None]
    dist = np.minimum(np.minimum(xs, W - 1 - xs), np.minimum(ys, H - 1 - ys)).astype(np.float32)
    a = np.clip((dist - 1.0 - n * 5.0) / 2.0, 0, 1)
    # browned, foxed edges
    burn = np.clip(1.0 - dist / 14.0, 0, 1) ** 1.5
    arr[..., :3] = arr[..., :3] * (1 - 0.35 * burn[..., None]) + np.array([-20, -30, -40]) * burn[..., None]
    arr[..., 3] = a * 255
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(UI, name))


def brush_stroke(name, W=512, H=56, seed=3):
    """White dry-brush stroke, tapered at both ends (tint it with modulate)."""
    rng = np.random.default_rng(seed)
    a = np.zeros((H, W), np.float32)
    xs = np.arange(W) / (W - 1)
    centre = H * 0.5 + np.sin(xs * math.pi * 1.2) * 3.0
    thick = (np.sin(np.clip(xs, 0, 1) * math.pi) ** 0.4) * (H * 0.44) * (1.0 - 0.35 * xs)
    thick[: int(W * 0.04)] *= np.linspace(0.3, 1.0, int(W * 0.04))
    bristles = rng.random(H * 2) * 0.6 + 0.4
    for x in range(W):
        for y in range(H):
            t = (y - centre[x]) / max(thick[x], 0.5)
            if abs(t) < 1.0:
                b = bristles[int((t + 1) * H) % len(bristles)]
                dry = 1.0 if xs[x] < 0.55 else (1.0 if rng.random() > (xs[x] - 0.55) * 1.6 * (1 - b) else 0.0)
                a[y, x] = (1.0 - abs(t) ** 6) * b * dry
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    out.putalpha(img)
    out.save(os.path.join(UI, name))


def divider(name, W=640, H=24):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cy = H // 2
    for x in range(W):
        f = 1.0 - abs(x - W / 2) / (W / 2)
        al = int(255 * min(1.0, f * 2.5))
        d.point((x, cy), fill=GOLD + (al,))
        d.point((x, cy - 3), fill=GOLD_LO + (int(al * 0.7),))
        d.point((x, cy + 3), fill=GOLD_LO + (int(al * 0.7),))
    c = W // 2
    d.polygon([(c, cy - 9), (c + 9, cy), (c, cy + 9), (c - 9, cy)], fill=GOLD + (255,))
    d.polygon([(c, cy - 5), (c + 5, cy), (c, cy + 5), (c - 5, cy)], fill=(26, 20, 14, 255))
    for s in (-1, 1):
        d.polygon([(c + s * 18, cy - 4), (c + s * 22, cy), (c + s * 18, cy + 4), (c + s * 14, cy)], fill=GOLD_HI + (255,))
    im.save(os.path.join(UI, name))


def seal(name, S=128):
    """Rough vermilion seal square (text is added in-engine)."""
    a = np.zeros((S, S), np.float32)
    n = np.asarray(Image.fromarray((RNG.random((S, S)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255
    xs = np.arange(S)[None, :]
    ys = np.arange(S)[:, None]
    dist = np.minimum(np.minimum(xs, S - 1 - xs), np.minimum(ys, S - 1 - ys)).astype(np.float32)
    a = np.clip((dist - 4 - n * 6) / 2, 0, 1)
    inner = np.clip((np.abs(dist - 13) - 2.0 - n * 1.5), 0, 1)       # carved inner border
    a *= np.where(dist > 9, inner, 1.0)
    speck = (RNG.random((S, S)) > 0.06).astype(np.float32)
    a *= 0.85 + 0.15 * speck
    rgb = np.zeros((S, S, 4), np.float32)
    rgb[..., 0], rgb[..., 1], rgb[..., 2] = 194, 59, 34
    rgb[..., :3] *= (0.85 + 0.25 * n[..., None])
    rgb[..., 3] = a * 255
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(UI, name))


def soft_dot(name, S=64, power=2.0):
    xs = np.linspace(-1, 1, S)
    r = np.sqrt(xs[None, :] ** 2 + xs[:, None] ** 2)
    a = np.clip(1 - r, 0, 1) ** power
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(UI, name))


def mist(name, S=256):
    big = RNG.random((S // 16, S // 16)).astype(np.float32)
    im = Image.fromarray((big * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC).filter(ImageFilter.GaussianBlur(10))
    n = np.asarray(im).astype(np.float32) / 255
    xs = np.linspace(-1, 1, S)
    r = np.sqrt(xs[None, :] ** 2 + (xs[:, None] * 1.6) ** 2)
    a = np.clip(1 - r, 0, 1) ** 1.5 * (0.4 + 0.6 * n)
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(UI, name))


def icon(name, draw_fn, S=48):
    big = Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    draw_fn(d, S * 4)
    big.resize((S, S), Image.LANCZOS).save(os.path.join(UI, name))


W_ = (255, 255, 255, 255)


def _run(d, s):      # double chevron >>
    for o in (0.18, 0.48):
        x = s * o
        d.polygon([(x, s * 0.2), (x + s * 0.22, s * 0.2), (x + s * 0.44, s * 0.5), (x + s * 0.22, s * 0.8), (x, s * 0.8), (x + s * 0.22, s * 0.5)], fill=W_)


def _fire(d, s):     # arrow with fletching, pointing up-right
    d.line([(s * 0.2, s * 0.8), (s * 0.78, s * 0.22)], fill=W_, width=int(s * 0.07))
    d.polygon([(s * 0.86, s * 0.14), (s * 0.58, s * 0.24), (s * 0.76, s * 0.42)], fill=W_)
    for k in (0.0, 0.08):
        d.line([(s * (0.2 + k), s * (0.8 - k)), (s * (0.1 + k), s * (0.62 - k))], fill=W_, width=int(s * 0.05))
        d.line([(s * (0.2 + k), s * (0.8 - k)), (s * (0.38 + k), s * (0.9 - k))], fill=W_, width=int(s * 0.05))


def _rout(d, s):     # broken banner pole + flag falling
    d.line([(s * 0.3, s * 0.9), (s * 0.42, s * 0.48)], fill=W_, width=int(s * 0.08))
    d.line([(s * 0.48, s * 0.42), (s * 0.62, s * 0.1)], fill=W_, width=int(s * 0.08))
    d.polygon([(s * 0.6, s * 0.14), (s * 0.9, s * 0.3), (s * 0.84, s * 0.56), (s * 0.54, s * 0.38)], fill=W_)


def _engaged(d, s):  # crossed swords
    for (a, b) in [((0.16, 0.84), (0.84, 0.16)), ((0.84, 0.84), (0.16, 0.16))]:
        d.line([(s * a[0], s * a[1]), (s * b[0], s * b[1])], fill=W_, width=int(s * 0.07))
    for (cx, cy, dx) in [(0.28, 0.72, 1), (0.72, 0.72, -1)]:
        d.line([(s * (cx - 0.1), s * (cy - 0.1 * dx * dx)), (s * (cx + 0.1), s * (cy + 0.1))], fill=W_, width=int(s * 0.06))
    d.line([(s * 0.18, s * 0.62), (s * 0.38, s * 0.82)], fill=W_, width=int(s * 0.06))
    d.line([(s * 0.82, s * 0.62), (s * 0.62, s * 0.82)], fill=W_, width=int(s * 0.06))


def _halt(d, s):     # open hand / stop bar
    d.rounded_rectangle((s * 0.22, s * 0.22, s * 0.78, s * 0.78), radius=s * 0.08, outline=W_, width=int(s * 0.08))
    d.rectangle((s * 0.36, s * 0.36, s * 0.64, s * 0.64), fill=W_)


def _withdraw(d, s):  # curved arrow back
    d.arc((s * 0.2, s * 0.25, s * 0.8, s * 0.85), 200, 360, fill=W_, width=int(s * 0.08))
    d.polygon([(s * 0.12, s * 0.42), (s * 0.36, s * 0.42), (s * 0.24, s * 0.66)], fill=W_)


def _pause(d, s):
    d.rectangle((s * 0.28, s * 0.22, s * 0.42, s * 0.78), fill=W_)
    d.rectangle((s * 0.58, s * 0.22, s * 0.72, s * 0.78), fill=W_)


def _play(d, s):
    d.polygon([(s * 0.3, s * 0.2), (s * 0.78, s * 0.5), (s * 0.3, s * 0.8)], fill=W_)


def _tired(d, s):    # droplet (fatigue)
    d.polygon([(s * 0.5, s * 0.12), (s * 0.74, s * 0.52), (s * 0.26, s * 0.52)], fill=W_)
    d.ellipse((s * 0.26, s * 0.36, s * 0.74, s * 0.86), fill=W_)


if __name__ == "__main__":
    lacquer_frame("frame_lacquer.png")
    lacquer_frame("frame_lacquer_hover.png", bright=1.25, glow=0.55)
    lacquer_frame("frame_lacquer_pressed.png", bright=1.1, fill_dark=0.6, glow=0.25)
    lacquer_frame("frame_lacquer_disabled.png", bright=0.55, fill_dark=0.8)
    washi_panel("washi_panel.png")
    brush_stroke("brush_stroke.png")
    divider("gold_divider.png")
    seal("seal_stamp.png")
    soft_dot("ember.png", 32, 1.6)
    soft_dot("glow.png", 128, 2.2)
    mist("mist.png")
    for n, f in [("run", _run), ("fire", _fire), ("rout", _rout), ("engaged", _engaged), ("halt", _halt),
                 ("withdraw", _withdraw), ("pause", _pause), ("play", _play), ("tired", _tired)]:
        icon("icon_%s.png" % n, f)
    print("ok")
