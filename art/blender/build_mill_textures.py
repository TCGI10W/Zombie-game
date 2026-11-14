"""Halloway Mill texture set (128 px, PS1 look).

Run:  python art/blender/build_mill_textures.py
Writes art/textures/mill_<name>_albedo.png and art/textures/mill_sheet.png.

Rules that keep the set consistent:
  * one texel density: 128 px = 2.0 m (64 px / m). In Godot use uv_scale 0.5.
  * one palette (PAL below), 1970s logging town: faded barn red, cream paint,
    pine, creosote brown, kiln brick, machine green, galvanised grey.
  * one baked key light from the top-left (world up), same relief/AO.
  * one ordered 4x4 dither, 24 levels per channel.
  * images are authored world-up and flipped on save, because the PS1
    triplanar shader maps world +y to texture +v.
Grain and specks use seeded tileable noise; all layout (boards, bricks,
seams, stains) is set by hand.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "art", "textures")
N = 128
PX_M = 64
YY, XX = np.mgrid[0:N, 0:N]
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def C(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


PAL = {
    # paint
    "barn_red": C("8a3b2c"), "barn_red_lt": C("a5503a"), "barn_red_dk": C("5e271f"),
    "cream": C("d8cfb2"), "cream_dk": C("b3a888"),
    "inst_green": C("9fae93"), "inst_green_dk": C("7f8f77"),
    "machine": C("4f6656"), "machine_dk": C("33463b"),
    # wood
    "pine": C("b58a58"), "pine_lt": C("cfa673"), "pine_dk": C("7d5934"),
    "weathered": C("8a8378"), "weathered_dk": C("5f5a52"),
    "creosote": C("4a3426"), "creosote_dk": C("2d1f17"),
    "bark": C("4b3a2c"), "bark_dk": C("2a2019"),
    # masonry / ground
    "brick": C("9a5a3c"), "brick_lt": C("b26d48"), "brick_dk": C("6b3a27"), "mortar": C("a99f8c"),
    "concrete": C("8e8b84"), "concrete_dk": C("6c6963"),
    "dirt": C("6e5a44"), "dirt_dk": C("4d3e2f"), "sawdust": C("c9a877"),
    "tar": C("3c3b3a"), "tar_lt": C("575551"),
    # metal / water
    "galv": C("8f979a"), "galv_dk": C("626a6e"), "rust": C("8b4a26"), "rust_dk": C("5a2f19"),
    "steel": C("3d3f40"), "soot": C("2b2724"),
    "river": C("253a40"), "river_lt": C("3d5a60"),
}


# ------------------------------------------------------------------ noise
def noise(cx, cy, seed):
    """Tileable value noise, cx x cy cells (anisotropic for grain)."""
    g = np.random.default_rng(seed).random((cy, cx))

    def axis(cells):
        t = np.arange(N) * cells / N
        i0 = t.astype(int) % cells
        f = t - np.floor(t)
        return i0, (i0 + 1) % cells, f * f * (3 - 2 * f)
    y0, y1, fy = axis(cy)
    x0, x1, fx = axis(cx)
    a = g[np.ix_(y0, x0)] * (1 - fx) + g[np.ix_(y0, x1)] * fx
    b = g[np.ix_(y1, x0)] * (1 - fx) + g[np.ix_(y1, x1)] * fx
    return a * (1 - fy)[:, None] + b * fy[:, None]


def fbm(seed, cx=4, cy=None, octaves=4):
    cy = cy or cx
    out, amp, tot = np.zeros((N, N)), 1.0, 0.0
    for o in range(octaves):
        out += noise(cx * 2 ** o, cy * 2 ** o, seed + o * 17) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def white(seed):
    return np.random.default_rng(seed).random((N, N))


def blur(h, r=1):
    out = np.zeros_like(h)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(np.roll(h, dy, 0), dx, 1)
    return out / (2 * r + 1) ** 2


def lerp(a, b, m):
    m = np.clip(m, 0, 1)[..., None]
    return a * (1 - m) + b * m


def fill(c):
    return np.ones((N, N, 3)) * c


def band(v, lo, hi):
    return np.clip((v - lo) / (hi - lo), 0, 1)


def shade(col, h, relief=1.6, ao=1.2):
    """Same key light for every texture: from the top-left, world up (row 0 = top)."""
    gx = np.roll(h, 1, 1) - np.roll(h, -1, 1)
    gy = np.roll(h, 1, 0) - np.roll(h, -1, 0)
    lit = (gx + gy) * relief
    cav = h - blur(h, 3)
    return col * np.clip(1.0 + lit + cav * ao, 0.45, 1.45)[..., None]


def spots(points, seed=0):
    """Soft round stains at hand-picked (x, y, radius) points, tileable."""
    m = np.zeros((N, N))
    for x, y, r in points:
        dx = (XX - x + N / 2) % N - N / 2
        dy = (YY - y + N / 2) % N - N / 2
        m = np.maximum(m, np.clip(1 - np.sqrt(dx * dx + dy * dy) / r, 0, 1))
    return m * (0.7 + 0.3 * fbm(seed, 8))


TEX = {}


def tex(name, col, h, relief=1.6, ao=1.2):
    TEX[name] = np.clip(shade(col, h, relief, ao), 0, 1)


# ------------------------------------------------------------------ set
def board_red():
    """Board-and-batten, faded barn red: sawmill, kiln sheds, power house trim."""
    w = 16  # 0.25 m boards
    bx = XX % w
    board = XX // w
    tint = np.array([0.0, 0.04, -0.03, 0.02, -0.05, 0.03, -0.02, 0.05])[board]
    grain = fbm(11, 2, 24, 3)
    h = 0.5 + 0.12 * grain
    batten = (bx < 3) | (bx > w - 2)
    h = np.where(batten, 0.85, h)
    h = np.where((bx == 3) | (bx == w - 2), 0.3, h)  # shadow line beside batten
    wear = band(fbm(12, 3, 6) + 0.25 * grain, 0.72, 0.80) * 0.7
    wear *= ~batten
    col = lerp(fill(PAL["barn_red"]), fill(PAL["barn_red_lt"]), grain * 0.6)
    col = col * (1 + tint)[..., None]
    col = lerp(col, lerp(fill(PAL["weathered"]), fill(PAL["weathered_dk"]), grain), wear)
    # nail heads on battens every 0.5 m
    nail = ((YY % 32) == 6) & ((bx == 1) | (bx == w - 1))
    col[nail] = PAL["steel"]
    tex("mill_board_red", col, h)


def clap_cream():
    """Horizontal clapboard, cream paint peeling to grey wood: office, boarding house, store."""
    w = 16  # 0.25 m exposure
    by = YY % w
    h = 0.35 + 0.5 * by / w          # lap thickens downward
    h = np.where(by == w - 1, 0.1, h)  # shadow under each lap
    grain = fbm(21, 24, 2, 3)
    peel = band(fbm(22, 6, 4) + 0.2 * grain, 0.76, 0.80) * 0.8
    col = lerp(fill(PAL["cream"]), fill(PAL["cream_dk"]), grain * 0.7 + (by > w - 4) * 0.4)
    col = lerp(col, lerp(fill(PAL["weathered"]), fill(PAL["weathered_dk"]), grain), peel)
    h = h - peel * 0.08
    tex("mill_clap_cream", col, h)


def plank_floor():
    """Pine floor boards along x, staggered butt joints: office, store, house."""
    w = 16
    row = YY // w
    by = YY % w
    ends = [37, 101, 70, 12, 88, 51, 120, 26]  # hand-staggered joints per board
    jx = np.array(ends)[row]
    dj = np.abs(((XX - jx) + N / 2) % N - N / 2)
    grain = fbm(31, 24, 2, 3)
    tone = np.array([0.0, -0.08, 0.05, -0.03, 0.07, -0.06, 0.02, -0.1])[row]
    col = lerp(fill(PAL["pine"]), fill(PAL["pine_lt"]), grain)
    col = col * (1 + tone)[..., None]
    col = lerp(col, fill(PAL["pine_dk"]), band(fbm(32, 4, 8), 0.55, 0.85) * 0.6)  # wear and dirt
    h = 0.55 + 0.1 * grain
    seam = (by == 0) | (dj < 1)
    h = np.where(seam, 0.15, h)
    col[seam] = PAL["creosote_dk"]
    nails = (dj == 3) & ((by == 4) | (by == 11))
    col[nails] = PAL["steel"]
    tex("mill_plank_floor", col, h)


def conc_floor():
    """Poured slab, joints every 1 m, oil and sawdust: sawmill, kiln, power house."""
    m = fbm(41, 6)
    col = lerp(fill(PAL["concrete"]), fill(PAL["concrete_dk"]), m * 0.8)
    joint = (XX % 64 == 0) | (YY % 64 == 0)
    h = 0.5 + 0.15 * m - joint * 0.4
    oil = spots([(30, 44, 14), (96, 100, 10), (84, 20, 7)], 42)
    col = lerp(col, fill(PAL["soot"]), oil * 0.75)
    saw = (white(43) > 0.93) * band(fbm(44, 3), 0.45, 0.7)
    col = lerp(col, fill(PAL["sawdust"]), saw * 0.8)
    col[joint] = PAL["concrete_dk"] * 0.7
    tex("mill_conc_floor", col, h, relief=1.0)


def brick_kiln():
    """Kiln brick with soot: kiln sheds, chimneys, power house."""
    bw, bh = 16, 8  # 0.25 x 0.125 m incl. mortar
    row = YY // bh
    xo = XX + (row % 2) * (bw // 2)
    col_i = (xo // bw) % (N // bw)
    idx = row * 31 + col_i
    tone = np.random.default_rng(51).random(idx.max() + 1)[idx]
    mx = xo % bw
    my = YY % bh
    mortar = (mx == 0) | (my == 0)
    face = fbm(52, 16)
    col = lerp(fill(PAL["brick_dk"]), fill(PAL["brick_lt"]), tone * 0.8 + face * 0.3)
    dark = tone > 0.86  # over-fired headers
    col[dark] = (PAL["brick_dk"] * 0.75)
    col[mortar] = PAL["mortar"]
    soot = band(fbm(53, 3, 4), 0.5, 0.8)
    col = lerp(col, fill(PAL["soot"]), soot * 0.55)
    h = np.where(mortar, 0.2, 0.6 + 0.1 * face)
    tex("mill_brick_kiln", col, h)


def corr_metal():
    """Galvanised corrugated sheet with rust runs: fences, sheds, roofs."""
    wave = 0.5 + 0.5 * np.cos(XX * 2 * np.pi / 8)
    lap = (XX % 64) < 2
    runs = fbm(61, 16, 1, 2)  # vertical streaks
    rust = band(fbm(62, 4) * 0.7 + runs * 0.5, 0.78, 0.92) * 0.85
    col = lerp(fill(PAL["galv"]), fill(PAL["galv_dk"]), (1 - wave) * 0.6 + fbm(63, 8) * 0.3)
    col = lerp(col, lerp(fill(PAL["rust"]), fill(PAL["rust_dk"]), runs), rust)
    col[lap] = PAL["galv_dk"] * 0.7
    rivet = lap & (YY % 32 == 10)
    col[rivet] = PAL["steel"]
    tex("mill_corr_metal", col, wave * 0.6 + 0.2, relief=2.2)


def plaster_int():
    """Institutional green interior paint over plaster: office, store, house."""
    m = fbm(71, 6)
    col = lerp(fill(PAL["inst_green"]), fill(PAL["inst_green_dk"]), m * 0.6)
    crack = np.clip(1 - np.abs(fbm(72, 5, 5, 3) - 0.5) / 0.006, 0, 1) * (fbm(73, 3) > 0.62) * 0.5
    col = lerp(col, fill(PAL["inst_green_dk"] * 0.6), crack)
    scuff = spots([(20, 110, 9), (90, 118, 12), (60, 100, 6)], 74)
    col = lerp(col, fill(PAL["cream_dk"] * 0.8), scuff * 0.4)
    tex("mill_plaster_int", col, 0.5 + 0.06 * m - crack * 0.2, relief=1.0)


def yard_dirt():
    """Packed dirt with sawdust, bark chips and stones: yard, landing, outside."""
    m = fbm(81, 5)
    col = lerp(fill(PAL["dirt"]), fill(PAL["dirt_dk"]), m)
    saw = band(fbm(82, 3), 0.55, 0.75) * (white(83) > 0.5)
    col = lerp(col, fill(PAL["sawdust"]), saw * 0.35)
    w = white(84)
    chips = w > 0.992
    stones = w < 0.006
    col[chips] = PAL["bark_dk"]
    col[stones] = PAL["concrete"]
    h = 0.5 + 0.2 * m + stones * 0.3 - chips * 0.1
    tex("mill_yard_dirt", col, blur(h, 1) * 0.5 + h * 0.5)


def roof_tar():
    """Rolled tar paper, 0.5 m courses with lapped seams: flat roofs, walkway roofs."""
    by = YY % 32
    grit = white(91)
    col = lerp(fill(PAL["tar"]), fill(PAL["tar_lt"]), grit * 0.5 + fbm(92, 4) * 0.4)
    seam = by > 28
    col[seam] = PAL["tar"] * 0.75
    h = 0.5 + grit * 0.1 - seam * 0.3
    tex("mill_roof_tar", col, h)


def bark():
    """Fir bark, vertical furrows: log decks, infeed logs."""
    f = fbm(101, 6, 1, 4)
    ridges = band(np.sin((XX + f * 24) * 2 * np.pi / 10), -0.3, 0.9)
    col = lerp(fill(PAL["bark_dk"]), fill(PAL["bark"]), ridges)
    moss = band(fbm(102, 4), 0.68, 0.8)
    col = lerp(col, fill(PAL["inst_green_dk"] * 0.6), moss * 0.6)
    tex("mill_bark", col, ridges, relief=2.0)


def lumber():
    """Fresh sawn pine planks stacked, grain along x: lumber stacks, crates, racks."""
    row = YY // 8  # 0.125 m planks
    tone = np.array([0.0, 0.06, -0.05, 0.03, -0.08, 0.05, -0.02, 0.07, -0.04, 0.02, 0.08, -0.06, 0.01, -0.03, 0.04, -0.07])[row]
    grain = fbm(111, 24, 2, 3)
    col = lerp(fill(PAL["pine_lt"]), fill(PAL["pine"]), grain) * (1 + tone)[..., None]
    gap = YY % 8 == 7
    col[gap] = PAL["creosote_dk"]
    tex("mill_lumber", col, 0.55 + 0.08 * grain - gap * 0.4)


def machine_paint():
    """Machine-green painted steel, chipped to bare metal: saw, vats, turbine."""
    m = fbm(121, 6)
    col = lerp(fill(PAL["machine"]), fill(PAL["machine_dk"]), m * 0.7)
    chip = band(fbm(122, 8, 8, 3), 0.7, 0.74)
    col = lerp(col, fill(PAL["steel"]), chip)
    plate = (XX % 64 == 0) | (YY % 64 == 0)
    col[plate] = PAL["machine_dk"] * 0.7
    rivet = ((XX % 64 == 4) | (XX % 64 == 60)) & (YY % 16 == 8)
    col[rivet] = PAL["machine"] * 1.3
    oil = spots([(40, 120, 18)], 123)
    col = lerp(col, fill(PAL["soot"]), oil * 0.5)
    tex("mill_machine", col, 0.5 - plate * 0.3 + rivet * 0.4 - chip * 0.1)


def creosote():
    """Creosote-stained timber boards, vertical: yard fence, posts, catwalks."""
    w = 20
    bx = XX % w
    grain = fbm(131, 2, 20, 3)
    tone = np.array([0.0, 0.08, -0.06, 0.04, -0.03, 0.06, -0.08])[(XX // w) % 7]
    col = lerp(fill(PAL["creosote"]), fill(PAL["creosote_dk"]), grain) * (1 + tone)[..., None]
    gap = bx == 0
    col[gap] = PAL["soot"] * 0.6
    tex("mill_creosote", col, 0.55 + 0.12 * grain - gap * 0.4)


def river():
    """Slow dark river, horizontal ripple bands."""
    r = fbm(141, 3, 12, 3)
    col = lerp(fill(PAL["river"]), fill(PAL["river_lt"]), band(r, 0.55, 0.75))
    tex("mill_river", col, r * 0.3, relief=0.6)


BUILD = [board_red, clap_cream, plank_floor, conc_floor, brick_kiln, corr_metal, plaster_int,
         yard_dirt, roof_tar, bark, lumber, machine_paint, creosote, river]


def quantise(rgb):
    d = np.tile(BAYER, (N // 4, N // 4))[..., None]
    return np.clip(np.floor(rgb * 24 + d + 0.5) / 24, 0, 1)


def save():
    os.makedirs(TEX_DIR, exist_ok=True)
    for f in BUILD:
        f()
    tiles = []
    for name, rgb in TEX.items():
        q = (quantise(rgb) * 255).astype(np.uint8)
        Image.fromarray(q[::-1]).save(os.path.join(TEX_DIR, name + "_albedo.png"))  # world-up flip
        tiles.append((name, Image.fromarray(q)))
    # contact sheet: each texture tiled 2x2 (4 m x 4 m) at 2x, authored orientation
    cell = 512
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 24)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(tiles):
        t = Image.new("RGB", (256, 256))
        for ty in range(2):
            for tx in range(2):
                t.paste(im, (tx * N, ty * N))
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        sheet.paste(t.resize((cell, cell), Image.NEAREST), (x, y + 24))
        dr.text((x + 6, y + 6), name, fill=(255, 220, 90))
    sheet.save(os.path.join(TEX_DIR, "mill_sheet.png"))
    print("wrote", len(tiles), "textures")


if __name__ == "__main__":
    save()
