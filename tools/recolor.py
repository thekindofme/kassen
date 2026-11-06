"""Hino crimson -> Mizuno indigo hue remap.

Only saturated crimson/red lacquer (hue within ~12 deg of pure red, high saturation) is moved to the
indigo #23356B family. Skin (orange hue 15-35), wood, gold (40-55), steel (low sat), white and horse
coats (dark low-value browns, hue 10-30) are left alone. The mask is soft so lacquer highlights and
shadows transition cleanly.
"""
import numpy as np
from kassen_img import rgb_to_hsv, hsv_to_rgb


def crimson_weight(rgb, unit=None):
    h, s, v = rgb_to_hsv(rgb)
    hd = np.where(h > 180, h - 360, h)  # signed distance from red, degrees
    # hue window: full weight in [-25, 6], fading out at 11 (keeps skin / bay horse / gold untouched)
    wh = np.clip((11 - hd) / 5, 0, 1) * np.clip((hd + 40) / 15, 0, 1)
    ws = np.clip((s - 0.42) / 0.15, 0, 1)
    wv = np.clip((v - 0.10) / 0.08, 0, 1)
    # skin guard: skin tones have G noticeably above B and moderate saturation
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    skin = np.clip(((g - b) - 0.06) / 0.06, 0, 1) * np.clip((0.75 - s) / 0.15, 0, 1) * (hd > 2)
    # lacquer crimson has G tiny relative to R (A3201E: g/r=0.20); bay horse coats, leather and skin
    # are browner/oranger (g/r >= 0.45). Fade out between 0.36 and 0.46.
    gr = g / np.maximum(r, 1e-3)
    wg = np.clip((0.46 - gr) / 0.10, 0, 1)
    return wh * ws * wv * wg * (1 - skin)


def to_mizuno(rgb, alpha=None, unit=None):
    w = crimson_weight(rgb, unit)[..., None]
    h, s, v = rgb_to_hsv(rgb)
    hd = np.where(h > 180, h - 360, h)
    nh = 224 + hd * 0.3
    ns = np.clip(s * 0.78, 0, 1)
    nv = np.clip(v * 0.70 + 0.02, 0, 1)
    ind = hsv_to_rgb(nh, ns, nv)
    return rgb * (1 - w) + ind * w
