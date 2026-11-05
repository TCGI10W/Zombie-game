"""Photo-scanned PBR sets (CC0, from Poly Haven) converted into the game's
texture format: <prefix>_albedo / _normal (OpenGL, Y+) / _rough / _height PNGs
in assets/textures, plus `wood_board`, a strip atlas of four single planks for
the window barricades.

This replaces the procedural versions of the same sets, so run it AFTER
generate_textures_v4.py whenever both are re-run:

    python tools/import_scanned_textures.py [prefixes...] [--src dir] [--sheet out.png]

The source maps live in tools/scans/<asset>/<asset>_{diff,nor_gl,rough,ao,disp}_<res>.jpg
(hidden from Godot by a .gdignore); they are the JPG maps listed by
https://api.polyhaven.com/files/<asset> (see SETS for which asset feeds which
set). Sources and authors: assets/textures/CREDITS_CC0.md.
Afterwards re-run the model generators (v1 to v4, in order) and
tools/tune_texture_imports.py.
"""
import os
import sys

import numpy as np
from PIL import Image

import generate_textures_v4 as gt  # tileable noise toolkit for the wear layers

OUT_DIR = gt.OUT_DIR
HEIGHT_MAX = 1024

# lum: target mean albedo (sRGB) - the procedural sets' values, so the scene's
#      lighting balance stays as tuned. sat: saturation multiplier.
# ao:  how much of the scan's ambient occlusion is baked into the albedo.
SETS = {
    "asphalt":        dict(asset="asphalt_02", res="2k", lum=0.15, sat=0.85, ao=0.6),
    "concrete":       dict(asset="concrete_layers_02", res="2k", lum=0.33, sat=0.85, ao=0.55),
    "concrete_floor": dict(asset="concrete_floor_02", res="2k", lum=0.3, sat=0.75, ao=0.55),
    "rusted_metal":   dict(asset="rusty_metal_04", res="2k", lum=0.3, sat=0.85, ao=0.45),
    "wood_planks":    dict(asset="old_planks_02", res="2k", lum=0.26, sat=1.0, ao=0.6),
    "wood_grain":     dict(asset="wood_table_worn", res="1k", lum=0.3, sat=0.8, ao=0.3),
    "fabric":         dict(asset="cotton_jersey", res="1k", lum=0.66, sat=0.0, ao=0.45, wear="fabric"),
    "denim":          dict(asset="denim_fabric_04", res="1k", lum=0.33, sat=1.0, ao=0.45, wear="denim"),
    "leather":        dict(asset="brown_leather", res="1k", lum=0.3, sat=1.0, ao=0.4, wear="leather"),
    "burlap":         dict(asset="hessian_230", res="1k", lum=0.42, sat=0.9, ao=0.5, wear="burlap"),
}


# ---------------------------------------------------------------------------
# IO
# ---------------------------------------------------------------------------
_ALIASES = {"diff": ["diff", "albedo", "col"], "disp": ["disp", "height"]}


def _path(src, asset, kind, res):
    for k in _ALIASES.get(kind, [kind]):
        p = os.path.join(src, asset, "%s_%s_%s.jpg" % (asset, k, res))
        if os.path.exists(p):
            return p
    return os.path.join(src, asset, "%s_%s_%s.jpg" % (asset, kind, res))


def _open(p, mode, size):
    im = Image.open(p).convert(mode)
    if im.size != (size, size):  # a few cloth scans are a handful of pixels off square
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def load_rgb(p, size):
    return _open(p, "RGB", size)


def load_gray(p, size):
    return _open(p, "L", size)


def save_rgb(name, rgb):
    Image.fromarray((np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT_DIR, name + ".png"), optimize=True)


def save_gray(name, g):
    Image.fromarray((np.clip(g, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT_DIR, name + ".png"), optimize=True)


def resize_wrap(a, size):
    """Resize a tileable map without breaking the seam (wrap-pad, resize, crop)."""
    h = a.shape[0]
    if h == size:
        return a
    pad = 16
    k = size / h
    padded = np.pad(a, ((pad, pad), (pad, pad)) + ((0, 0),) * (a.ndim - 2), mode="wrap")
    out_px = int(round(padded.shape[0] * k))
    if a.ndim == 2:
        im = Image.fromarray(padded.astype(np.float32), "F").resize((out_px, out_px), Image.LANCZOS)
        r = np.asarray(im, np.float32)
    else:
        r = np.stack([np.asarray(Image.fromarray(padded[..., c].astype(np.float32), "F").resize((out_px, out_px), Image.LANCZOS), np.float32)
                      for c in range(a.shape[2])], axis=-1)
    c = int(round(pad * k))
    return r[c:c + size, c:c + size]


# ---------------------------------------------------------------------------
# COLOR / NORMAL HELPERS
# ---------------------------------------------------------------------------
def luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def saturate_rgb(rgb, s):
    g = luma(rgb)[..., None]
    return g + (rgb - g) * s


def match_lum(rgb, target):
    return np.clip(rgb * (target / max(float(rgb.mean()), 1e-4)), 0.0, 1.0)


def decode_normal(rgb):
    n = rgb * 2.0 - 1.0
    return n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-5)


def encode_normal(n):
    n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-5)
    return n * 0.5 + 0.5


def flatten_normal(n, amount):
    """Blend toward a flat normal where `amount` is 1 (holes, blood crusts)."""
    flat = np.zeros_like(n)
    flat[..., 2] = 1.0
    return n * (1.0 - amount[..., None]) + flat * amount[..., None]


# ---------------------------------------------------------------------------
# WEAR LAYERS (zombie clothes are never clean)
# ---------------------------------------------------------------------------
def wear_fabric(n, alb, rough, nrm, height):
    dirt = np.clip((gt.spectral(n, 2.4, 2, 24, seed=113) - 0.5) * 2.0, 0.0, 1.0)
    grime = gt.spectral(n, 2.0, 1, 6, seed=114)
    blood = np.clip((gt.warp(gt.spectral(n, 2.3, 3, 30, seed=115), *gt.warp_field(n, 40.0, 116)) - 0.84) * 6.0, 0.0, 1.0)
    holes = np.clip((gt.spectral(n, 2.6, 4, 40, seed=117) - 0.91) * 12.0, 0.0, 1.0)
    alb = gt.mix(alb, alb * np.array([0.68, 0.6, 0.5], np.float32), dirt * 0.55 + grime * 0.12)
    alb = gt.mix(alb, [0.3, 0.045, 0.035], blood * 0.9)
    alb = alb * (1.0 - 0.85 * holes)[..., None]
    rough = np.clip(rough - 0.25 * blood, 0.0, 1.0)
    nrm = flatten_normal(nrm, np.clip(blood * 0.6 + holes, 0.0, 1.0))
    height = np.clip(height - 0.8 * holes, 0.0, 1.0)
    return alb, rough, nrm, height


def wear_denim(n, alb, rough, nrm, height):
    fade = gt.spectral(n, 2.5, 1, 14, seed=122)
    whisk = np.clip((gt.spectral(n, 2.0, 2, 60, seed=123, aniso=(5.0, 1.0)) - 0.62) * 3.0, 0.0, 1.0)
    dirt = np.clip((gt.spectral(n, 2.4, 2, 24, seed=124) - 0.6) * 2.5, 0.0, 1.0)
    blood = np.clip((gt.spectral(n, 2.3, 3, 30, seed=125) - 0.8) * 6.0, 0.0, 1.0)
    alb = gt.mix(alb, saturate_rgb(alb, 0.6) * 1.25, np.clip(fade * 0.5 + whisk * 0.45 - 0.15, 0.0, 0.7))
    alb = gt.mix(alb, [0.33, 0.28, 0.22], dirt * 0.5)
    alb = gt.mix(alb, [0.22, 0.04, 0.04], blood * 0.85)
    rough = np.clip(rough - 0.2 * blood, 0.0, 1.0)
    nrm = flatten_normal(nrm, blood * 0.5)
    return alb, rough, nrm, height


def wear_leather(n, alb, rough, nrm, height):
    scuff = np.clip((gt.spectral(n, 2.4, 3, 40, seed=144) - 0.66) * 3.0, 0.0, 1.0)
    mud = np.clip((gt.spectral(n, 2.2, 2, 20, seed=146) - 0.62) * 2.5, 0.0, 1.0)
    alb = gt.mix(alb, saturate_rgb(alb, 0.5) * 1.5, scuff * 0.45)
    alb = gt.mix(alb, [0.2, 0.17, 0.13], mud * 0.4)
    rough = np.clip(rough + 0.15 * scuff + 0.25 * mud, 0.0, 1.0)
    return alb, rough, nrm, height


def wear_burlap(n, alb, rough, nrm, height):
    dirt = np.clip((gt.spectral(n, 2.4, 2, 24, seed=161) - 0.48) * 2.0, 0.0, 1.0)
    damp = np.clip((gt.spectral(n, 2.6, 1, 10, seed=162) - 0.6) * 3.0, 0.0, 1.0)
    alb = gt.mix(alb, alb * np.array([0.6, 0.55, 0.48], np.float32), dirt * 0.6)
    alb = alb * (1.0 - 0.3 * damp)[..., None]
    rough = np.clip(rough - 0.1 * damp, 0.0, 1.0)
    return alb, rough, nrm, height


WEAR = {"fabric": wear_fabric, "denim": wear_denim, "leather": wear_leather, "burlap": wear_burlap}


# ---------------------------------------------------------------------------
# CONVERSION
# ---------------------------------------------------------------------------
def load_set(src, cfg):
    a, r = cfg["asset"], cfg["res"]
    n = 2048 if r == "2k" else 1024
    alb = load_rgb(_path(src, a, "diff", r), n)
    nrm = decode_normal(load_rgb(_path(src, a, "nor_gl", r), n))
    rough = load_gray(_path(src, a, "rough", r), n)
    ao = load_gray(_path(src, a, "ao", r), n)
    height = gt.norm01(load_gray(_path(src, a, "disp", r), n))
    return alb, nrm, rough, ao, height


def convert(prefix, src):
    cfg = SETS[prefix]
    alb, nrm, rough, ao, height = load_set(src, cfg)
    n = alb.shape[0]
    alb = alb * (1.0 - cfg["ao"] * (1.0 - ao))[..., None]
    alb = saturate_rgb(alb, cfg["sat"])
    alb = match_lum(alb, cfg["lum"])
    if "wear" in cfg:
        alb, rough, nrm, height = WEAR[cfg["wear"]](n, alb, rough, nrm, height)
        alb = match_lum(alb, cfg["lum"])
    save_rgb(prefix + "_albedo", alb)
    save_rgb(prefix + "_normal", encode_normal(nrm))
    save_gray(prefix + "_rough", rough)
    save_gray(prefix + "_height", resize_wrap(height, min(n, HEIGHT_MAX)))
    print("%-15s %-20s %dpx lum %.3f std %.3f rough %.2f" % (prefix, cfg["asset"], n, alb.mean(), alb.std(), rough.mean()))
    return alb, nrm, rough, height


def build_board_strips(src, planks):
    """Window barricade boards: four single planks cut from the plank scan,
    turned so the grain runs along the board, stacked into one 2048x1024 atlas
    (strip k fills v in [k/4, (k+1)/4])."""
    alb, nrm, rough, height = planks
    # Grain runs vertically in the scan: rotate 90 deg CCW so it runs along u.
    alb = np.rot90(alb, 1)
    rough = np.rot90(rough, 1)
    height = np.rot90(height, 1)
    nrm = np.rot90(nrm, 1)
    nrm = np.stack([-nrm[..., 1], nrm[..., 0], nrm[..., 2]], axis=-1)  # rotate the vectors too
    # Plank seams are the deepest rows of the height profile.
    prof = height.mean(axis=1)
    k = 9
    prof = np.convolve(np.pad(prof, k, mode="wrap"), np.ones(2 * k + 1) / (2 * k + 1), mode="same")[k:-k]
    seams = []
    for i in np.argsort(prof):
        if all(min(abs(int(i) - s), len(prof) - abs(int(i) - s)) > 150 for s in seams):
            seams.append(int(i))
        if len(seams) >= 8:
            break
    seams.sort()
    spans = [(seams[i], seams[(i + 1) % len(seams)] + (len(prof) if i == len(seams) - 1 else 0)) for i in range(len(seams))]
    spans = [s for s in spans if 200 < s[1] - s[0] < 600]
    spans.sort(key=lambda s: -(s[1] - s[0]))
    spans = sorted(spans[:4])
    if len(spans) < 4:
        raise RuntimeError("could not find four planks in the scan (seams %s)" % seams)
    W, H = 2048, 256
    out = {"albedo": [], "normal": [], "rough": []}
    nrm_enc = encode_normal(nrm)
    for a, b in spans:
        rows = np.arange(a + 14, b - 14) % len(prof)
        for key, arr in (("albedo", alb), ("normal", nrm_enc), ("rough", rough)):
            strip = arr[rows]
            mode = "RGB" if strip.ndim == 3 else "L"
            im = Image.fromarray((np.clip(strip, 0, 1) * 255 + 0.5).astype(np.uint8), mode).resize((W, H), Image.LANCZOS)
            out[key].append(np.asarray(im, np.float32) / 255.0)
    alb_atlas = np.concatenate(out["albedo"], axis=0)
    save_rgb("wood_board_albedo", match_lum(alb_atlas, SETS["wood_planks"]["lum"]))
    save_rgb("wood_board_normal", np.concatenate(out["normal"], axis=0))
    save_gray("wood_board_rough", np.concatenate(out["rough"], axis=0))
    print("wood_board      %d planks, widths %s px" % (len(spans), [b - a for a, b in spans]))


def contact_sheet(path, names):
    tiles = []
    for nm in names + ["wood_board"]:
        p = os.path.join(OUT_DIR, nm + "_albedo.png")
        if not os.path.exists(p):
            continue
        a = Image.open(p).convert("RGB").resize((320, 320 if nm != "wood_board" else 160))
        nn = Image.open(os.path.join(OUT_DIR, nm + "_normal.png")).convert("RGB").resize(a.size)
        tiles.append((nm, a, nn))
    sheet = Image.new("RGB", (640 * 3, 336 * ((len(tiles) + 2) // 3)), (20, 20, 20))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for i, (nm, a, nn) in enumerate(tiles):
        x, y = (i % 3) * 640, (i // 3) * 336
        sheet.paste(a, (x, y))
        sheet.paste(nn, (x + 320, y))
        d.text((x + 4, y + 322), nm, fill=(240, 240, 240))
    sheet.save(path)


if __name__ == "__main__":
    args = sys.argv[1:]
    sheet = None
    if "--sheet" in args:
        sheet = args[args.index("--sheet") + 1]
        args = args[: args.index("--sheet")]
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scans")
    if "--src" in args:
        src = args[args.index("--src") + 1]
        args = args[: args.index("--src")] + args[args.index("--src") + 2:]
    unknown = [a for a in args if a not in SETS]
    if unknown:
        sys.exit("unknown set(s) %s\n%s" % (unknown, __doc__))
    names = args or list(SETS.keys())
    for nm in names:
        result = convert(nm, src)
        if nm == "wood_planks":
            build_board_strips(src, result)
    if sheet:
        contact_sheet(sheet, names)
    print("Imported scanned textures")
