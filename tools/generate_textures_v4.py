"""Fourth batch of textures: high-resolution, realistic, seamlessly tiling PBR
sets (albedo / normal / roughness / height) built with FFT noise, Worley cells
and domain warping. Everything is circular (FFT, wrapped sampling), so every
map tiles perfectly.

Replaces: asphalt, concrete, rusted_metal, wood_planks, zombie_skin, fabric,
denim, camo, leather, gorilla_hide, monster_scales.
New: gunmetal, wood_grain, macro_noise (large-scale variation for the world
shader: R = tone, G = puddles, B = grime).

Normal maps use the OpenGL (Y+) convention Godot expects.
Run with: python tools/generate_textures_v4.py [names...] [--sheet out.png]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")
N = 1024


# ---------------------------------------------------------------------------
# NOISE TOOLKIT (all tileable)
# ---------------------------------------------------------------------------
def _freqs(n):
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    return fx, fy


def norm01(a, lo_pct=0.5, hi_pct=99.5):
    lo, hi = np.percentile(a, [lo_pct, hi_pct])
    return np.clip((a - lo) / max(hi - lo, 1e-9), 0.0, 1.0).astype(np.float32)


def spectral(n, beta=2.0, lo=1.0, hi=None, seed=0, aniso=(1.0, 1.0)):
    """Fractal noise with power ~ 1/f^beta inside [lo, hi] cycles per tile.
    aniso=(ax, ay): ax > 1 stretches features along x, ay > 1 along y."""
    r = np.random.default_rng(seed)
    fx, fy = _freqs(n)
    f = np.sqrt((fx * aniso[0]) ** 2 + (fy * aniso[1]) ** 2)
    f[0, 0] = 1.0
    hi = hi or n / 2
    amp = f ** (-beta / 2.0) / (1.0 + (lo / f) ** 6) / (1.0 + (f / hi) ** 6)
    amp[0, 0] = 0.0
    return norm01(np.real(np.fft.ifft2(np.fft.fft2(r.normal(size=(n, n))) * amp)))


def blur(a, sx, sy=None):
    sy = sx if sy is None else sy
    n = a.shape[0]
    fx, fy = _freqs(n)
    g = np.exp(-2.0 * np.pi ** 2 * ((sx * fx / n) ** 2 + (sy * fy / n) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def worley(n, cells, seed=0, jitter=0.9):
    """Tileable Worley noise: (F1, F2) in cell units and the nearest cell id."""
    r = np.random.default_rng(seed)
    pts = 0.5 + (r.random((cells, cells, 2)) - 0.5) * jitter
    cs = n / cells
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    cy = np.minimum((ys / cs).astype(np.int32), cells - 1)
    cx = np.minimum((xs / cs).astype(np.int32), cells - 1)
    f1 = np.full((n, n), 1e9, np.float32)
    f2 = f1.copy()
    ids = np.zeros((n, n), np.int32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ny = (cy + oy) % cells
            nx = (cx + ox) % cells
            px = (cx + ox + pts[ny, nx, 0]) * cs
            py = (cy + oy + pts[ny, nx, 1]) * cs
            d = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, ny * cells + nx, ids)
            f1 = np.where(closer, d, f1)
    return f1 / cs, f2 / cs, ids


def sample(a, x, y):
    n = a.shape[0]
    x = np.mod(x, n)
    y = np.mod(y, n)
    x0 = np.floor(x).astype(np.int32) % n
    y0 = np.floor(y).astype(np.int32) % n
    tx = x - np.floor(x)
    ty = y - np.floor(y)
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (a[y0, x0] * (1 - tx) * (1 - ty) + a[y0, x1] * tx * (1 - ty)
            + a[y1, x0] * (1 - tx) * ty + a[y1, x1] * tx * ty).astype(np.float32)


def warp(a, wx, wy):
    n = a.shape[0]
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    return sample(a, xs + wx, ys + wy)


def warp_field(n, amount, seed, lo=2, hi=24):
    return ((spectral(n, 2.0, lo, hi, seed) - 0.5) * amount, (spectral(n, 2.0, lo, hi, seed + 1) - 0.5) * amount)


def cracks_from_worley(n, cells, width, seed, warp_amt=40.0, keep=0.5):
    f1, f2, _ = worley(n, cells, seed=seed, jitter=0.85)
    wx, wy = warp_field(n, warp_amt, seed + 7, 2, 40)
    edge = warp(f2 - f1, wx, wy)
    jag = spectral(n, 1.5, 30, 300, seed + 9)
    c = np.clip(1.0 - edge / (width * (0.6 + 0.8 * jag)), 0.0, 1.0)
    mask = spectral(n, 2.0, 1, 6, seed + 11)
    return c * np.clip((mask - (1.0 - keep)) * 6.0, 0.0, 1.0)


def scratches(n, count, seed, length=(20, 160), width=1, value=1.0):
    """Thin random scratch lines, drawn wrapped so the map still tiles."""
    r = np.random.default_rng(seed)
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x0, y0 = r.uniform(0, n), r.uniform(0, n)
        ang = r.uniform(0, np.pi)
        ln = r.uniform(*length)
        x1, y1 = x0 + np.cos(ang) * ln, y0 + np.sin(ang) * ln
        v = int(255 * value * r.uniform(0.4, 1.0))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                d.line([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)], fill=v, width=width)
    return np.asarray(img, np.float32) / 255.0


def cavity(h, sigma=5.0, k=2.5):
    return np.clip(1.0 - (blur(h, sigma) - h) * k, 0.0, 1.0)


def mix(a, b, t):
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    t = np.asarray(t, np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


def to_normal(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    ln = np.sqrt(dx * dx + dy * dy + nz)
    return np.stack([-dx / ln, dy / ln, nz / ln], -1) * 0.5 + 0.5


def save_rgb(name, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT_DIR, name + ".png"))


def save_gray(name, g):
    Image.fromarray((np.clip(g, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT_DIR, name + ".png"))


def save_set(prefix, albedo, height, rough, nstrength, target_lum=None):
    if target_lum is not None:
        albedo = np.clip(albedo * (target_lum / max(float(albedo.mean()), 1e-4)), 0.0, 1.0)
    save_rgb(prefix + "_albedo", albedo)
    save_rgb(prefix + "_normal", to_normal(height, nstrength))
    save_gray(prefix + "_rough", rough)
    save_gray(prefix + "_height", height)
    print("%-15s lum %.3f std %.3f rough %.2f" % (prefix, albedo.mean(), albedo.std(), rough.mean()))


# ---------------------------------------------------------------------------
# GROUND & BUILDINGS
# ---------------------------------------------------------------------------
def build_asphalt():
    n = N
    r = np.random.default_rng(12)
    f1, f2, ids = worley(n, 150, seed=11, jitter=0.95)
    tone = r.random(150 * 150).astype(np.float32)[ids]
    stone = np.clip(1.0 - f1 / 0.6, 0.0, 1.0) ** 0.6 * np.clip((f2 - f1) / 0.1, 0.0, 1.0)
    exposed = np.clip(spectral(n, 2.0, 2, 30, seed=13) * 1.4 - 0.2, 0.0, 1.0)
    stone *= 0.3 + 0.7 * exposed
    grit = spectral(n, 0.8, 100, 512, seed=14)
    macro = spectral(n, 3.0, 1, 10, seed=15)
    cr = np.maximum(cracks_from_worley(n, 5, 0.03, 16, 70.0, 0.55),
                    cracks_from_worley(n, 22, 0.045, 30, 20.0, 0.3) * 0.8)
    tar = cracks_from_worley(n, 3, 0.07, 40, 90.0, 0.35)
    stains = np.clip((spectral(n, 2.2, 2, 24, seed=22) - 0.6) * 3.5, 0.0, 1.0)
    binder = mix([0.07, 0.07, 0.075], [0.15, 0.15, 0.155], macro * 0.7 + grit * 0.3)
    stone_col = mix([0.2, 0.2, 0.19], [0.34, 0.33, 0.31], tone)
    albedo = mix(binder, stone_col, stone * 0.6)
    albedo = mix(albedo, [0.025, 0.025, 0.03], tar * 0.9)
    albedo *= (1.0 - 0.45 * stains)[..., None]
    albedo *= (1.0 - 0.7 * cr)[..., None]
    height = norm01(0.45 * stone + 0.12 * grit + 0.1 * macro - 0.7 * cr + 0.08 * tar)
    albedo *= (0.6 + 0.4 * cavity(height, 3.0, 3.0))[..., None]
    rough = np.clip(0.86 + 0.1 * grit - 0.3 * stains - 0.45 * tar - 0.1 * stone * tone, 0.05, 1.0)
    save_set("asphalt", albedo, height, rough, 10.0, target_lum=0.15)


def build_concrete():
    n = N
    r = np.random.default_rng(31)
    macro = spectral(n, 3.0, 1, 8, seed=31)
    mid = spectral(n, 2.2, 6, 80, seed=32)
    fine = spectral(n, 1.1, 80, 512, seed=33)
    pf1, _, pid = worley(n, 130, seed=34)
    pore_on = (r.random(130 * 130) < 0.25)[pid]
    pore_r = (0.07 + 0.16 * r.random(130 * 130)).astype(np.float32)[pid]
    pores = np.clip(1.0 - pf1 / pore_r, 0.0, 1.0) ** 0.6 * pore_on
    # Formwork panels (2x2 per tile) with seams and tie-rod holes
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    panel = n / 2.0
    dx = np.minimum(xs % panel, panel - xs % panel)
    dy = np.minimum(ys % panel, panel - ys % panel)
    seam = np.clip(1.0 - np.minimum(dx, dy) / 2.2, 0.0, 1.0)
    pidx = (xs // panel).astype(np.int32) * 2 + (ys // panel).astype(np.int32)
    panel_tone = np.array([0.0, 0.035, -0.03, 0.02], np.float32)[pidx]
    holes = np.zeros((n, n), np.float32)
    for hx in (0.25, 0.75):
        for hy in (0.25, 0.75):
            ddx = np.minimum(np.abs((xs % panel) - hx * panel), panel)
            ddy = np.abs((ys % panel) - hy * panel)
            d = np.sqrt(ddx ** 2 + ddy ** 2)
            holes = np.maximum(holes, np.clip(1.0 - d / 10.0, 0.0, 1.0) ** 0.8)
    ring = np.clip(1.0 - np.abs(blur(holes, 6.0) - 0.08) / 0.08, 0.0, 1.0) * 0.4
    streak = spectral(n, 2.0, 2, 160, seed=36, aniso=(1.0, 9.0))
    streaks = np.clip((streak - 0.55) * 3.0, 0.0, 1.0) * np.clip(spectral(n, 2.0, 1, 5, seed=37) * 1.6 - 0.3, 0.0, 1.0)
    cr = cracks_from_worley(n, 4, 0.02, 38, 60.0, 0.45)
    moss = np.clip((spectral(n, 2.6, 2, 20, seed=39) - 0.72) * 4.0, 0.0, 1.0)
    base = mix([0.52, 0.51, 0.49], [0.64, 0.63, 0.6], macro * 0.6 + mid * 0.4)
    base += (fine[..., None] - 0.5) * 0.08 + panel_tone[..., None]
    albedo = mix(base, base * np.array([0.72, 0.68, 0.62], np.float32), streaks)
    albedo = mix(albedo, [0.3, 0.32, 0.24], moss * 0.3)
    albedo *= (1.0 - 0.5 * pores - 0.35 * seam - 0.5 * cr - 0.55 * holes + ring * 0.0)[..., None]
    height = norm01(0.3 * mid + 0.18 * fine - 0.5 * pores - 0.45 * seam - 0.9 * holes - 0.6 * cr - 0.05 * streaks)
    albedo *= (0.7 + 0.3 * cavity(height, 4.0, 2.5))[..., None]
    rough = np.clip(0.9 + 0.08 * fine - 0.18 * streaks - 0.1 * moss, 0.0, 1.0)
    save_set("concrete", albedo, height, rough, 9.0, target_lum=0.33)


def build_rusted_metal():
    n = N
    wx, wy = warp_field(n, 90.0, 51, 2, 20)
    cover = warp(spectral(n, 2.4, 1, 24, seed=52), wx, wy)
    rust = np.clip((cover - 0.56) * 7.0, 0.0, 1.0)
    rim = np.clip(1.0 - np.abs(cover - 0.53) / 0.025, 0.0, 1.0)
    deep = np.clip((cover - 0.72) * 6.0, 0.0, 1.0)
    flake = spectral(n, 1.3, 40, 512, seed=53)
    pits_f1, _, pits_id = worley(n, 110, seed=54)
    r = np.random.default_rng(55)
    pits = np.clip(1.0 - pits_f1 / 0.22, 0.0, 1.0) * (r.random(110 * 110) < 0.5)[pits_id] * rust
    sc = scratches(n, 260, 56, (15, 140), 1)
    paint_var = spectral(n, 2.5, 1, 12, seed=57)
    drip = np.clip((spectral(n, 2.0, 2, 120, seed=58, aniso=(1.0, 8.0)) - 0.58) * 3.0, 0.0, 1.0) * (1.0 - rust)
    paint = mix([0.58, 0.58, 0.56], [0.68, 0.68, 0.66], paint_var)
    rust_col = mix([0.42, 0.2, 0.08], [0.24, 0.11, 0.05], flake)
    rust_col = mix(rust_col, [0.12, 0.07, 0.04], deep * 0.7)
    albedo = mix(paint, rust_col, rust)
    albedo = mix(albedo, [0.5, 0.25, 0.1], drip * 0.5)
    albedo = mix(albedo, [0.78, 0.77, 0.75], rim * 0.6)
    albedo = mix(albedo, [0.82, 0.82, 0.8], sc * (1.0 - rust) * 0.7)
    albedo *= (1.0 - 0.5 * pits)[..., None]
    height = norm01(0.35 * rust * flake + 0.15 * rust + 0.1 * rim - 0.4 * pits - 0.25 * sc + 0.05 * paint_var)
    albedo *= (0.75 + 0.25 * cavity(height, 3.0, 2.0))[..., None]
    rough = np.clip(0.48 + 0.42 * rust + 0.08 * flake - 0.25 * sc * (1.0 - rust) - 0.1 * rim, 0.05, 1.0)
    save_set("rusted_metal", albedo, height, rough, 8.0, target_lum=0.3)


def build_gunmetal():
    n = N
    brushed = spectral(n, 1.0, 20, 512, seed=61, aniso=(10.0, 1.0))
    smudge = spectral(n, 2.4, 2, 20, seed=62)
    sc = scratches(n, 180, 63, (8, 90), 1, 0.8)
    wear = np.clip((spectral(n, 2.2, 3, 40, seed=64) - 0.8) * 4.0, 0.0, 1.0)
    specks = np.clip((spectral(n, 0.5, 200, 512, seed=65) - 0.86) * 8.0, 0.0, 1.0)
    albedo = mix([0.66, 0.67, 0.7], [0.74, 0.75, 0.78], brushed)
    albedo = mix(albedo, [0.88, 0.88, 0.9], np.maximum(sc * 0.5, wear * 0.22))
    albedo *= (1.0 - 0.35 * specks)[..., None]
    height = norm01(0.25 * brushed - 0.5 * sc + 0.05 * smudge)
    rough = np.clip(0.36 + 0.14 * smudge + 0.05 * brushed - 0.12 * wear + 0.15 * specks, 0.05, 1.0)
    save_set("gunmetal", albedo, height, rough, 4.0, target_lum=0.72)


def _grain(n, seed, rings=26.0, warp_amt=30.0):
    """Wood grain running along x: growth rings bent by noise."""
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    bend = spectral(n, 2.4, 1, 10, seed, aniso=(6.0, 1.0)) * warp_amt
    phase = (ys + bend) / n * rings * 2.0 * np.pi
    fib = spectral(n, 1.2, 30, 512, seed + 1, aniso=(14.0, 1.0))
    ringv = 0.5 + 0.5 * np.sin(phase + fib * 2.0)
    late = np.clip((ringv - 0.55) * 4.0, 0.0, 1.0)
    return late, fib


def build_wood_planks():
    n = N
    r = np.random.default_rng(71)
    rows = 6
    ph = n / rows
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    row = (ys // ph).astype(np.int32)
    late, fib = _grain(n, 72, rings=40.0, warp_amt=36.0)
    tone = np.zeros((n, n), np.float32)
    joint = np.zeros((n, n), np.float32)
    nails = np.zeros((n, n), np.float32)
    weather = spectral(n, 2.2, 1, 10, seed=73)
    for ri in range(rows):
        sel = row == ri
        x = r.uniform(0, n)
        start = x
        while x < start + n:
            ln = r.uniform(0.45, 1.1) * n
            seg_t = r.uniform(-0.12, 0.12)
            sx0 = x
            sx1 = min(x + ln, start + n)
            u = (xs - sx0) % n
            inside = sel & (u < (sx1 - sx0))
            tone[inside] = seg_t
            for ex in (sx0, sx1):
                d = np.minimum(np.abs(xs - (ex % n)), n - np.abs(xs - (ex % n)))
                joint = np.maximum(joint, np.clip(1.0 - d / 2.0, 0.0, 1.0) * sel)
                for k in (0.28, 0.72):
                    cy = (ri + k) * ph
                    for side in (6.0, -6.0):
                        nxp = (ex + side) % n
                        dd = np.sqrt(np.minimum(np.abs(xs - nxp), n - np.abs(xs - nxp)) ** 2 + (ys - cy) ** 2)
                        nails = np.maximum(nails, np.clip(1.0 - dd / 3.2, 0.0, 1.0))
            x = sx1
    gap = np.clip(1.0 - np.minimum(ys % ph, ph - ys % ph) / 2.5, 0.0, 1.0)
    base = mix([0.36, 0.23, 0.13], [0.46, 0.31, 0.18], fib)
    base = mix(base, [0.22, 0.13, 0.07], late * 0.7)
    base *= (1.0 + tone)[..., None]
    gray = base.mean(axis=2, keepdims=True) * np.array([1.0, 0.98, 0.94], np.float32)
    albedo = mix(base, gray * 1.15, np.clip(weather * 1.3 - 0.4, 0.0, 0.8))
    albedo *= (1.0 - 0.8 * np.maximum(gap, joint))[..., None]
    albedo = mix(albedo, [0.12, 0.12, 0.13], nails * 0.9)
    height = norm01(0.25 * late + 0.15 * fib - 0.9 * np.maximum(gap, joint) + 0.1 * tone - 0.3 * nails)
    albedo *= (0.7 + 0.3 * cavity(height, 3.0, 2.5))[..., None]
    rough = np.clip(0.8 + 0.1 * fib + 0.05 * late, 0.0, 1.0)
    save_set("wood_planks", albedo, height, rough, 7.0, target_lum=0.26)


def build_wood_grain():
    n = N
    late, fib = _grain(n, 81, rings=11.0, warp_amt=120.0)
    late = late * (0.55 + 0.45 * spectral(n, 2.0, 1, 8, seed=84))
    figure = spectral(n, 2.0, 2, 30, seed=82)
    sc = scratches(n, 60, 83, (10, 60), 1, 0.6)
    base = mix([0.46, 0.3, 0.19], [0.58, 0.4, 0.26], fib * 0.6 + figure * 0.4)
    albedo = mix(base, [0.28, 0.16, 0.09], late * 0.55)
    albedo = mix(albedo, [0.75, 0.55, 0.35], sc * 0.4)
    height = norm01(0.2 * late + 0.1 * fib - 0.3 * sc)
    rough = np.clip(0.42 + 0.15 * late + 0.1 * fib + 0.2 * sc, 0.0, 1.0)
    save_set("wood_grain", albedo, height, rough, 4.0, target_lum=0.42)


# ---------------------------------------------------------------------------
# ORGANIC
# ---------------------------------------------------------------------------
def build_zombie_skin():
    n = N
    r = np.random.default_rng(91)
    mott = spectral(n, 2.6, 2, 40, seed=92)
    mott2 = spectral(n, 2.2, 4, 60, seed=93)
    wx, wy = warp_field(n, 60.0, 94, 2, 16)
    vn = warp(spectral(n, 2.0, 3, 28, seed=95), wx, wy)
    veins = np.clip(1.0 - np.abs(vn - 0.5) / 0.022, 0.0, 1.0) * np.clip(spectral(n, 2.0, 1, 8, seed=96) * 1.8 - 0.4, 0.0, 1.0)
    vn2 = warp(spectral(n, 2.0, 8, 60, seed=97), wx * 0.5, wy * 0.5)
    veins = np.maximum(veins, np.clip(1.0 - np.abs(vn2 - 0.5) / 0.012, 0.0, 1.0) * 0.6)
    bruise = np.clip((spectral(n, 2.8, 2, 16, seed=98) - 0.62) * 3.5, 0.0, 1.0)
    sf1, sf2, sid = worley(n, 12, seed=99)
    sore_on = (r.random(144) < 0.12)[sid]
    sore_r = (0.1 + 0.16 * r.random(144)).astype(np.float32)[sid]
    sd = sf1 / sore_r
    wobble = spectral(n, 1.6, 10, 80, seed=100) * 0.5
    sd = sd + (wobble - 0.25) * 0.6
    sore = np.clip(1.0 - sd, 0.0, 1.0) * sore_on
    sore_rim = np.clip(1.0 - np.abs(sd - 1.0) / 0.18, 0.0, 1.0) * sore_on
    pores = spectral(n, 0.6, 180, 512, seed=101)
    wrinkle = spectral(n, 1.8, 20, 160, seed=102, aniso=(1.0, 4.0))
    dirt = np.clip((spectral(n, 2.4, 2, 30, seed=103) - 0.55) * 2.5, 0.0, 1.0)
    blood = np.clip((spectral(n, 2.2, 3, 40, seed=104) - 0.8) * 5.0, 0.0, 1.0)
    base = mix([0.56, 0.61, 0.55], [0.67, 0.71, 0.64], mott)
    base = mix(base, [0.62, 0.57, 0.62], np.clip(mott2 - 0.55, 0.0, 1.0) * 1.6)
    base = mix(base, [0.6, 0.64, 0.44], np.clip(spectral(n, 2.4, 2, 20, seed=105) - 0.6, 0.0, 1.0) * 1.5)
    albedo = mix(base, [0.3, 0.3, 0.44], veins * 0.8)
    albedo = mix(albedo, mix([0.45, 0.3, 0.45], [0.62, 0.6, 0.35], np.clip(bruise * 1.6 - 0.6, 0.0, 1.0)), bruise * 0.6)
    albedo = mix(albedo, [0.4, 0.4, 0.33], dirt * 0.3)
    albedo = mix(albedo, [0.24, 0.03, 0.03], blood * 0.8)
    albedo = mix(albedo, [0.66, 0.6, 0.34], sore_rim * 0.7)
    albedo = mix(albedo, mix([0.35, 0.06, 0.05], [0.12, 0.03, 0.03], sore), np.clip(sore * 3.0, 0.0, 1.0))
    albedo *= (0.94 + 0.12 * pores)[..., None]
    height = norm01(0.12 * pores + 0.18 * wrinkle + 0.15 * veins + 0.3 * sore_rim - 0.5 * sore + 0.08 * mott)
    albedo *= (0.75 + 0.25 * cavity(height, 2.5, 2.0))[..., None]
    rough = np.clip(0.62 + 0.15 * pores - 0.3 * np.clip(sore * 3.0, 0.0, 1.0) - 0.2 * blood + 0.15 * dirt, 0.05, 1.0)
    save_set("zombie_skin", albedo, height, rough, 6.0, target_lum=0.45)


def _weave(n, threads, seed, twill=False):
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    u = xs / n * threads
    v = ys / n * threads
    jx, jy = warp_field(n, 3.0, seed, 4, 60)
    u += jx / n * threads * 0.3
    v += jy / n * threads * 0.3
    iu = np.floor(u).astype(np.int32)
    iv = np.floor(v).astype(np.int32)
    over = ((iu + iv) % 4 < 2) if twill else ((iu + iv) % 2 == 0)
    pu = np.sin(np.pi * (u - iu)) ** 0.7
    pv = np.sin(np.pi * (v - iv)) ** 0.7
    r = np.random.default_rng(seed + 1)
    tu = r.random(threads + 1).astype(np.float32)[iu % threads]
    tv = r.random(threads + 1).astype(np.float32)[iv % threads]
    h = np.where(over, pv * 0.6 + 0.4 * pu, pu * 0.6 + 0.4 * pv)
    return h.astype(np.float32), over, tu, tv


def build_fabric():
    n = N
    h, over, tu, tv = _weave(n, 160, 111)
    slub = spectral(n, 1.5, 20, 200, seed=112, aniso=(1.0, 6.0))
    dirt = np.clip((spectral(n, 2.4, 2, 24, seed=113) - 0.5) * 2.0, 0.0, 1.0)
    grime = spectral(n, 2.0, 1, 6, seed=114)
    blood = np.clip((warp(spectral(n, 2.3, 3, 30, seed=115), *warp_field(n, 40.0, 116)) - 0.84) * 6.0, 0.0, 1.0)
    holes = np.clip((spectral(n, 2.6, 4, 40, seed=117) - 0.91) * 12.0, 0.0, 1.0)
    thread_tone = np.where(over, tv, tu)
    base = mix([0.78, 0.78, 0.77], [0.9, 0.9, 0.89], thread_tone * 0.6 + slub * 0.4)
    albedo = mix(base, [0.5, 0.44, 0.36], dirt * 0.45 + grime[..., None][..., 0] * 0.1)
    albedo = mix(albedo, [0.32, 0.05, 0.04], blood * 0.9)
    albedo *= (0.78 + 0.22 * h)[..., None]
    albedo *= (1.0 - 0.85 * holes)[..., None]
    height = norm01(h * 0.8 + 0.2 * slub - 0.8 * holes)
    rough = np.clip(0.92 - 0.25 * blood + 0.04 * h, 0.0, 1.0)
    save_set("fabric", albedo, height, rough, 5.0, target_lum=0.66)


def build_denim():
    n = N
    h, over, tu, tv = _weave(n, 180, 121, twill=True)
    fade = spectral(n, 2.5, 1, 14, seed=122)
    whisk = np.clip((spectral(n, 2.0, 2, 60, seed=123, aniso=(5.0, 1.0)) - 0.62) * 3.0, 0.0, 1.0)
    dirt = np.clip((spectral(n, 2.4, 2, 24, seed=124) - 0.6) * 2.5, 0.0, 1.0)
    blood = np.clip((spectral(n, 2.3, 3, 30, seed=125) - 0.8) * 6.0, 0.0, 1.0)
    indigo = mix([0.12, 0.18, 0.34], [0.2, 0.28, 0.46], tv)
    weft = mix([0.62, 0.64, 0.68], [0.78, 0.8, 0.84], tu)
    albedo = np.where(over[..., None], indigo, mix(indigo, weft, 0.65))
    albedo = mix(albedo, [0.42, 0.5, 0.62], np.clip(fade * 0.6 + whisk * 0.5 - 0.15, 0.0, 0.8))
    albedo = mix(albedo, [0.35, 0.3, 0.24], dirt * 0.5)
    albedo = mix(albedo, [0.22, 0.04, 0.04], blood * 0.85)
    albedo *= (0.8 + 0.2 * h)[..., None]
    height = norm01(h)
    rough = np.clip(0.9 + 0.05 * h - 0.2 * blood, 0.0, 1.0)
    save_set("denim", albedo, height, rough, 5.0, target_lum=0.33)


def build_camo():
    n = N
    def blobs(seed, thr, lo=2, hi=18):
        wx, wy = warp_field(n, 70.0, seed + 50, 2, 14)
        return warp(spectral(n, 2.8, lo, hi, seed), wx, wy) > thr
    green = blobs(131, 0.5)
    brown = blobs(132, 0.6)
    black = blobs(133, 0.7, 4, 30)
    albedo = np.ones((n, n, 3), np.float32) * np.array([0.6, 0.56, 0.42], np.float32)
    albedo[green] = [0.3, 0.37, 0.21]
    albedo[brown] = [0.4, 0.29, 0.18]
    albedo[black] = [0.11, 0.11, 0.1]
    h, over, tu, tv = _weave(n, 200, 134)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    rip = np.maximum(np.clip(1.0 - np.minimum(xs % 40.0, 40.0 - xs % 40.0) / 1.5, 0.0, 1.0),
                     np.clip(1.0 - np.minimum(ys % 40.0, 40.0 - ys % 40.0) / 1.5, 0.0, 1.0))
    dirt = np.clip((spectral(n, 2.4, 2, 24, seed=135) - 0.55) * 2.2, 0.0, 1.0)
    fade = spectral(n, 2.5, 1, 10, seed=136)
    blood = np.clip((spectral(n, 2.3, 3, 30, seed=137) - 0.8) * 6.0, 0.0, 1.0)
    albedo = mix(albedo, albedo.mean(axis=2, keepdims=True) * 1.2, fade * 0.25)
    albedo = mix(albedo, [0.36, 0.3, 0.22], dirt * 0.45)
    albedo = mix(albedo, [0.22, 0.04, 0.03], blood * 0.85)
    albedo *= (0.8 + 0.2 * h + 0.08 * rip)[..., None]
    height = norm01(h + 0.6 * rip)
    rough = np.clip(0.9 - 0.2 * blood, 0.0, 1.0)
    save_set("camo", albedo, height, rough, 5.0, target_lum=0.3)


def build_leather():
    n = N
    f1, f2, ids = worley(n, 110, seed=141)
    pebble = np.clip(1.0 - f1 / 0.7, 0.0, 1.0) ** 0.5
    creases_n = warp(spectral(n, 2.0, 2, 20, seed=142, aniso=(3.0, 1.0)), *warp_field(n, 50.0, 143))
    creases = np.clip(1.0 - np.abs(creases_n - 0.5) / 0.015, 0.0, 1.0)
    scuff = np.clip((spectral(n, 2.4, 3, 40, seed=144) - 0.65) * 3.0, 0.0, 1.0)
    tone = spectral(n, 2.5, 1, 12, seed=145)
    albedo = mix([0.42, 0.33, 0.25], [0.5, 0.4, 0.3], tone)
    albedo = mix(albedo, [0.66, 0.56, 0.45], scuff * 0.6)
    albedo *= (0.85 + 0.15 * pebble - 0.4 * creases)[..., None]
    height = norm01(0.4 * pebble - 0.6 * creases + 0.1 * tone)
    albedo *= (0.75 + 0.25 * cavity(height, 2.0, 2.0))[..., None]
    rough = np.clip(0.55 + 0.15 * pebble - 0.2 * scuff + 0.15 * creases, 0.0, 1.0)
    save_set("leather", albedo, height, rough, 5.0, target_lum=0.3)


def build_fur():
    n = N
    r = np.random.default_rng(151)
    wx, wy = warp_field(n, 80.0, 152, 2, 12)
    strands = warp(blur(r.random((n, n)).astype(np.float32), 0.7, 14.0), wx * 0.6, wy * 0.2)
    strands = norm01(strands)
    clumps = warp(spectral(n, 2.2, 3, 30, seed=153, aniso=(1.0, 3.0)), wx, wy)
    under = spectral(n, 2.0, 2, 40, seed=154)
    shade = strands * 0.7 + clumps * 0.3
    albedo = mix([0.08, 0.07, 0.065], [0.42, 0.37, 0.32], shade ** 1.3)
    albedo = mix(albedo, [0.32, 0.18, 0.15], np.clip((0.3 - shade) * 2.0, 0.0, 1.0) * under * 0.6)
    height = norm01(shade)
    rough = np.clip(0.75 + 0.2 * (1.0 - shade), 0.0, 1.0)
    save_set("gorilla_hide", albedo, height, rough, 6.0, target_lum=0.22)


def build_monster_scales():
    n = N
    f1, f2, ids = worley(n, 28, seed=161, jitter=0.6)
    r = np.random.default_rng(162)
    tone = r.random(28 * 28).astype(np.float32)[ids]
    dome = np.clip(1.0 - f1 / 0.75, 0.0, 1.0) ** 0.6
    edge = np.clip(1.0 - (f2 - f1) / 0.06, 0.0, 1.0)
    fine = spectral(n, 1.2, 60, 512, seed=163)
    albedo = mix([0.3, 0.06, 0.07], [0.55, 0.16, 0.14], dome * 0.7 + tone * 0.3)
    albedo = mix(albedo, [0.08, 0.02, 0.03], edge * 0.8)
    albedo *= (0.9 + 0.2 * fine)[..., None]
    height = norm01(dome - 0.8 * edge + 0.1 * fine)
    rough = np.clip(0.35 + 0.35 * edge + 0.1 * fine, 0.0, 1.0)
    save_set("monster_scales", albedo, height, rough, 8.0, target_lum=0.2)


def build_macro_noise():
    n = 512
    tone = spectral(n, 3.0, 1, 8, seed=171)
    puddles = spectral(n, 3.2, 1, 7, seed=172)
    grime = spectral(n, 2.5, 2, 16, seed=173)
    save_rgb("macro_noise", np.stack([tone, puddles, grime], -1))
    print("macro_noise     saved")


def build_sky_night():
    """Equirectangular night sky for ProceduralSkyMaterial.sky_cover (added on
    top of the sky gradient): stars, Milky Way with dust lanes, moonlit
    clouds, and a cratered moon in the same direction as the moonlight
    (DirectionalLight rotation -52, -34). Godot maps u = atan2(x, -z) / 2pi,
    v = acos(y) / pi."""
    W, H = 2048, 1024
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    theta = ys / H * np.pi
    phi = xs / W * 2.0 * np.pi
    dx = np.sin(theta) * np.sin(phi)
    dy = np.cos(theta)
    dz = -np.sin(theta) * np.cos(phi)
    up = np.clip(dy, 0.0, 1.0)
    r = np.random.default_rng(181)

    # Stars, uniform over the upper hemisphere, brighter ones rarer
    stars = np.zeros((H, W, 3), np.float32)
    n_st = 6500
    sy = r.random(n_st) ** 0.85
    sth = np.arccos(sy)
    sph = r.random(n_st) * 2.0 * np.pi
    bright = np.clip(r.pareto(2.4, n_st) * 0.07 + 0.02, 0.0, 1.0)
    tint = r.random(n_st)
    for i in range(n_st):
        cx = sph[i] / (2.0 * np.pi) * W
        cy = sth[i] / np.pi * H
        stretch = 1.0 / max(np.sin(sth[i]), 0.08)
        sig = 0.55 + bright[i] * 0.9
        rx = int(min(3 + sig * stretch * 2.5, 40))
        ry = 3
        x0, x1 = int(cx) - rx, int(cx) + rx + 1
        y0, y1 = max(0, int(cy) - ry), min(H, int(cy) + ry + 1)
        gx = np.arange(x0, x1)
        gy = np.arange(y0, y1)
        X, Y = np.meshgrid(gx + 0.5, gy + 0.5)
        g = np.exp(-(((X - cx) / (sig * stretch)) ** 2 + ((Y - cy) / sig) ** 2))
        col = np.array([0.8, 0.88, 1.0]) if tint[i] < 0.6 else (np.array([1.0, 0.92, 0.78]) if tint[i] < 0.9 else np.array([1.0, 0.75, 0.6]))
        stars[gy[0]:gy[-1] + 1, :, :][:, gx % W, :] += g[..., None] * col * bright[i]
    stars *= np.clip(dy * 4.0, 0.0, 1.0)[..., None]

    # Milky Way band along a tilted great circle, with dark dust lanes
    nm = np.array([0.35, 0.5, 0.79])
    nm /= np.linalg.norm(nm)
    band_d = np.abs(dx * nm[0] + dy * nm[1] + dz * nm[2])
    glow = spectral(1024, 2.2, 3, 120, seed=182)
    glow = np.asarray(Image.fromarray((glow * 255).astype(np.uint8)).resize((W, H)), np.float32) / 255.0
    lanes = spectral(1024, 2.0, 6, 80, seed=183)
    lanes = np.asarray(Image.fromarray((lanes * 255).astype(np.uint8)).resize((W, H)), np.float32) / 255.0
    band = np.exp(-(band_d / 0.16) ** 2) * (0.35 + 0.65 * glow) * (1.0 - 0.75 * np.clip((lanes - 0.45) * 3.0, 0.0, 1.0))
    milky = band[..., None] * np.array([0.075, 0.08, 0.1]) * np.clip(dy * 3.0, 0.0, 1.0)[..., None]

    # Moon
    md = np.array([-0.344, 0.788, 0.511])
    md /= np.linalg.norm(md)
    cosang = np.clip(dx * md[0] + dy * md[1] + dz * md[2], -1.0, 1.0)
    ang = np.arccos(cosang)
    R = np.radians(1.5)
    disk = np.clip((R - ang) / np.radians(0.08), 0.0, 1.0)
    maria = spectral(1024, 2.4, 4, 60, seed=184)
    maria = np.asarray(Image.fromarray((maria * 255).astype(np.uint8)).resize((W, H)), np.float32) / 255.0
    limb = np.sqrt(np.clip(1.0 - (ang / R) ** 2, 0.0, 1.0))
    moon = disk * (0.62 + 0.38 * limb) * (0.78 + 0.22 * np.clip(maria * 1.6 - 0.3, 0.0, 1.0))
    halo = np.exp(-ang / 0.03) * 0.22 + np.exp(-ang / 0.14) * 0.05

    # Clouds: denser toward the horizon, silver-lined near the moon
    cl = spectral(1024, 2.6, 2, 70, seed=185, aniso=(1.0, 2.2))
    cl = np.asarray(Image.fromarray((cl * 255).astype(np.uint8)).resize((W, H), Image.Resampling.BICUBIC), np.float32) / 255.0
    cover = np.clip((cl - 0.5) * 2.2 + (1.0 - up) * 0.55 - 0.15, 0.0, 1.0) * np.clip(dy * 6.0, 0.0, 1.0)
    moonlit = np.exp(-ang / 0.5)
    edge = np.clip(1.0 - np.abs(cover - 0.45) / 0.3, 0.0, 1.0)
    cloud_col = cover[..., None] * np.array([0.02, 0.024, 0.032]) + (moonlit * edge * cover * 0.16)[..., None] * np.array([0.85, 0.9, 1.0])

    sky = (stars + milky) * (1.0 - cover * 0.97)[..., None] + cloud_col
    sky += (moon * (1.0 - cover * 0.6))[..., None] * np.array([0.95, 0.94, 0.88])
    sky += (halo * (1.0 - cover * 0.3))[..., None] * np.array([0.6, 0.66, 0.8])
    sky *= (dy > -0.02)[..., None]
    save_rgb("sky_night", np.clip(sky, 0.0, 1.0))
    print("sky_night       saved")


def build_blood_vignette():
    """Full-screen low-health overlay: wet blood creeping in from the edges,
    with droplets, smears and drips running down from the top."""
    W, H = 1920, 1080
    def big(noise):
        return np.asarray(Image.fromarray((noise * 255).astype(np.uint8)).resize((W, H), Image.Resampling.BICUBIC), np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx = xx / W * 2.0 - 1.0
    ny = yy / H * 2.0 - 1.0
    dist = np.sqrt(nx * nx * 0.8 + ny * ny * 1.25)
    edge_n = big(spectral(1024, 2.2, 3, 60, seed=191))
    fine_n = big(spectral(1024, 1.4, 30, 400, seed=192))
    base = np.clip((dist - 0.66 + (edge_n - 0.5) * 0.42) * 3.2, 0.0, 1.0)
    # Droplets near the edges
    r = np.random.default_rng(193)
    drops = np.zeros((H, W), np.float32)
    for _ in range(260):
        ang = r.uniform(0, 2 * np.pi)
        rad = r.uniform(0.62, 1.15)
        cx = W * 0.5 + np.cos(ang) * rad * W * 0.55
        cy = H * 0.5 + np.sin(ang) * rad * H * 0.5
        rr = r.uniform(3.0, 26.0) * (1.0 + (rad - 0.6))
        x0, x1 = int(max(0, cx - rr * 2)), int(min(W, cx + rr * 2))
        y0, y1 = int(max(0, cy - rr * 2)), int(min(H, cy + rr * 2))
        if x1 <= x0 or y1 <= y0:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / rr
        drops[y0:y1, x0:x1] = np.maximum(drops[y0:y1, x0:x1], np.clip((1.0 - d) * 4.0, 0.0, 1.0))
    # Drips running down from the top edge
    drips = np.zeros((H, W), np.float32)
    for _ in range(26):
        x = r.uniform(0, W)
        length = r.uniform(0.12, 0.42) * H
        wdt = r.uniform(3.0, 9.0)
        X = np.arange(W) + 0.5
        col = np.clip(1.0 - np.abs(X - x) / wdt, 0.0, 1.0)
        Y = np.arange(H) + 0.5
        run = np.clip((length - Y) / 18.0, 0.0, 1.0)
        bulb = np.exp(-((Y - length) / (wdt * 1.2)) ** 2)
        drips = np.maximum(drips, np.outer(np.maximum(run, bulb), col))
    alpha = np.clip(np.maximum(base, np.maximum(drops * 0.95, drips * 0.9)), 0.0, 1.0) ** 1.15
    shade = 0.55 + 0.45 * fine_n
    rgba = np.zeros((H, W, 4), np.float32)
    rgba[..., 0] = 0.28 + 0.34 * shade
    rgba[..., 1] = 0.01 + 0.03 * shade
    rgba[..., 2] = 0.012 + 0.025 * shade
    rgba[..., 3] = alpha * 0.93
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_DIR, "blood_vignette.png"))
    print("blood_vignette  saved")


BUILDERS = {
    "asphalt": build_asphalt, "concrete": build_concrete, "rusted_metal": build_rusted_metal,
    "gunmetal": build_gunmetal, "wood_planks": build_wood_planks, "wood_grain": build_wood_grain,
    "zombie_skin": build_zombie_skin, "fabric": build_fabric, "denim": build_denim, "camo": build_camo,
    "leather": build_leather, "gorilla_hide": build_fur, "monster_scales": build_monster_scales,
    "macro_noise": build_macro_noise, "sky_night": build_sky_night, "blood_vignette": build_blood_vignette,
}


def contact_sheet(path, names):
    tiles = []
    for nm in names:
        if nm in ("macro_noise", "sky_night", "blood_vignette"):
            continue
        a = Image.open(os.path.join(OUT_DIR, nm + "_albedo.png")).convert("RGB").resize((256, 256))
        nn = Image.open(os.path.join(OUT_DIR, nm + "_normal.png")).convert("RGB").resize((256, 256))
        tiles.append((a, nn))
    sheet = Image.new("RGB", (256 * 2 * 4, 256 * ((len(tiles) + 3) // 4)), (20, 20, 20))
    for i, (a, nn) in enumerate(tiles):
        x = (i % 4) * 512
        y = (i // 4) * 256
        sheet.paste(a, (x, y))
        sheet.paste(nn, (x + 256, y))
    sheet.save(path)


if __name__ == "__main__":
    args = sys.argv[1:]
    sheet = None
    if "--sheet" in args:
        sheet = args[args.index("--sheet") + 1]
        args = args[: args.index("--sheet")]
    names = args or list(BUILDERS.keys())
    for nm in names:
        BUILDERS[nm]()
    if sheet:
        contact_sheet(sheet, names)
    print("Generated v4 textures")
