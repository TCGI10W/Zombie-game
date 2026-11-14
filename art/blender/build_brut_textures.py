"""Halloway Mill, BRUTALIST / METAL palette (128 px, PS1 look).

Run:  python art/blender/build_brut_textures.py
Writes art/textures/brut_<name>_albedo.png and art/textures/brut_sheet.png.

Same rules as build_mill_textures.py (whose helpers it reuses): 128 px = 2 m,
one baked top-left light, one 4x4 dither, world-up flip on save. Only the
palette and the surfaces change: board-formed and precast concrete, blued
steel, red-oxide primer, rust, one worn safety yellow as the only accent.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import build_mill_textures as K  # noqa: E402
from build_mill_textures import N, XX, YY, C, fbm, white, blur, lerp, fill, band, spots, quantise  # noqa: E402

P = {
    "conc": C("8b8c88"), "conc_lt": C("a3a49f"), "conc_dk": C("62635f"), "conc_stain": C("4e504d"),
    "block": C("7d8580"), "block_dk": C("5f6763"),
    "steel": C("4c5a63"), "steel_lt": C("6b7a83"), "steel_dk": C("2f383e"),
    "primer": C("7a3322"), "primer_dk": C("52221a"),
    "rust": C("8a4a24"), "rust_lt": C("a8642e"), "rust_dk": C("4f2a17"),
    "yellow": C("c9a227"), "black": C("23231f"),
    "tar": C("3a3b3a"), "gravel": C("75736d"), "gravel_dk": C("4d4c48"),
    "asph": C("4a4b4a"), "asph_lt": C("626361"),
    "water": C("1f2a2c"), "water_lt": C("37474a"), "oil": C("2a2622"),
}
TEX = {}


def tex(name, col, h, relief=1.6, ao=1.2):
    TEX[name] = np.clip(K.shade(col, h, relief, ao), 0, 1)


def streaks(seed, strength=1.0):
    """Water run-off streaks, vertical, tileable."""
    return band(fbm(seed, 16, 1, 3) * 0.7 + fbm(seed + 1, 3) * 0.5, 0.6, 0.85) * strength


def cast_conc():
    """Plain cast-in-place concrete: one pour line per 2 m, fine aggregate, soft run-off stains. Main exterior walls."""
    m = fbm(201, 5)
    agg = white(203)
    col = lerp(fill(P["conc_lt"]), fill(P["conc"]), m * 0.7 + blur(agg, 1) * 0.25)
    col = lerp(col, fill(P["conc_dk"]), (agg > 0.97) * 0.6)
    col = lerp(col, fill(P["conc_stain"]), streaks(202, 0.45))
    pour = YY % 128 == 0
    col[pour] = P["conc_dk"]
    tex("brut_cast_conc", col, 0.55 + 0.06 * m - pour * 0.25, relief=1.0)


def panel_conc():
    """Precast panels 2 m x 1 m with recessed joints and rust bleed from fixings."""
    joint = (YY % 64 < 2) | (XX < 2)
    m = fbm(211, 6)
    col = lerp(fill(P["conc_lt"]), fill(P["conc"]), m)
    col = lerp(col, fill(P["conc_stain"]), streaks(212, 0.5))
    bolt = ((XX - 8) ** 2 + (YY % 64 - 8) ** 2 <= 3) | ((XX - 120) ** 2 + (YY % 64 - 8) ** 2 <= 3)
    bleed = ((np.abs(XX - 8) < 2) | (np.abs(XX - 120) < 2)) & (YY % 64 > 8) & (YY % 64 < 30)
    col = lerp(col, fill(P["rust"]), bleed * (1 - (YY % 64 - 8) / 22.0) * 0.7)
    col[joint] = P["conc_dk"] * 0.8
    col[bolt] = P["rust_dk"]
    tex("brut_panel_conc", col, 0.55 + 0.05 * m - joint * 0.4 - bolt * 0.2)


def conc_floor():
    """Power-floated slab, saw-cut joints every 1 m, oil, scrapes."""
    m = fbm(221, 6)
    col = lerp(fill(P["conc"]), fill(P["conc_dk"]), m * 0.7)
    joint = (XX % 64 == 0) | (YY % 64 == 0)
    oil = spots([(26, 40, 13), (100, 96, 11), (80, 18, 6)], 222)
    col = lerp(col, fill(P["oil"]), oil * 0.7)
    scr = (np.abs(((XX * 0.3 + YY) % 23) - 11) < 0.5) & (fbm(223, 3) > 0.62)
    col[scr] = P["conc_lt"]
    col[joint] = P["conc_dk"] * 0.6
    tex("brut_conc_floor", col, 0.5 + 0.12 * m - joint * 0.4, relief=1.0)


def block():
    """Painted concrete block (CMU) 0.4 x 0.2 m, interior walls."""
    bw, bh = 26, 13  # ~0.4 x 0.2 m; tiles at 128 via 5 cols / ~10 rows
    row = YY * 10 // N
    xo = XX + (row % 2) * (N // 10)
    mx = (xo * 5) % N < 3
    my = (YY * 10) % N < 10
    m = fbm(231, 12)
    col = lerp(fill(P["block"]), fill(P["block_dk"]), m * 0.5)
    pit = white(232) > 0.94
    col[pit] = P["block_dk"] * 0.85
    mortar = mx | my
    col[mortar] = P["block_dk"] * 0.8
    scuff = spots([(30, 120, 14), (96, 124, 10)], 233)
    col = lerp(col, fill(P["conc_stain"]), scuff * 0.5)
    tex("brut_block", col, 0.55 + 0.05 * m - mortar * 0.3 - pit * 0.1)


def tread():
    """Diamond-plate steel floor."""
    u = (XX + YY) % 16
    v = (XX - YY) % 16
    a = (np.abs(u - 4) < 1.5) & (np.abs(v - 8) < 4)
    b = (np.abs(u - 12) < 1.5) & (np.abs(v - 0) % 16 < 4)
    lug = a | b
    m = fbm(241, 6)
    col = lerp(fill(P["steel_lt"]), fill(P["steel"]), m)
    col = lerp(col, fill(P["rust"]), band(fbm(242, 4), 0.7, 0.85) * 0.6)
    col[lug] = col[lug] * 1.25
    tex("brut_tread", col, 0.4 + lug * 0.4, relief=1.8)


def grate():
    """Bar grating: 32 mm bearing bars, cross rods every 0.1 m (catwalks)."""
    bar = XX % 4 == 0
    rod = YY % 6 == 0
    col = fill(P["black"])
    col[bar | rod] = P["steel_lt"]
    col = lerp(col, fill(P["rust"]), band(fbm(251, 4), 0.65, 0.8) * (bar | rod) * 0.7)
    tex("brut_grate", col, (bar | rod) * 0.7 + 0.1, relief=1.4)


def steel_panel():
    """Blued steel plate, 1 m panels, rivet rows: machinery, doors, tanks."""
    m = fbm(261, 6)
    col = lerp(fill(P["steel"]), fill(P["steel_dk"]), m * 0.7)
    seam = (XX % 64 < 1) | (YY % 64 < 1)
    rv = (((XX % 64 == 4) | (XX % 64 == 60)) & (YY % 8 == 4)) | (((YY % 64 == 4) | (YY % 64 == 60)) & (XX % 8 == 4))
    col = lerp(col, lerp(fill(P["rust"]), fill(P["rust_dk"]), m), streaks(262, 0.45))
    col[seam] = P["steel_dk"] * 0.6
    col[rv] = P["steel_lt"] * 1.15
    tex("brut_steel_panel", col, 0.5 - seam * 0.4 + rv * 0.4)


def primer():
    """Red-oxide primer on structural steel, chipped and weathered."""
    m = fbm(271, 6)
    col = lerp(fill(P["primer"]), fill(P["primer_dk"]), m * 0.7)
    chip = band(fbm(272, 8, 8, 3), 0.72, 0.76)
    col = lerp(col, fill(P["steel_dk"]), chip)
    col = lerp(col, fill(P["rust_dk"]), streaks(273, 0.4))
    tex("brut_primer", col, 0.5 - chip * 0.1)


def cladding():
    """Trapezoidal ribbed steel cladding, dark grey, rust at the laps: shed walls, fences."""
    p = XX % 32
    rib = (p >= 4) & (p < 12)
    h = np.where(rib, 0.8, 0.3)
    h = np.where((p == 3) | (p == 12), 0.55, h)
    m = fbm(281, 6)
    col = lerp(fill(P["steel"]), fill(P["steel_dk"]), m * 0.5 + (~rib) * 0.25)
    col = lerp(col, lerp(fill(P["rust"]), fill(P["rust_lt"]), m), streaks(282, 0.55))
    tex("brut_cladding", col, h, relief=1.8)


def hazard():
    """Worn safety stripes (the one accent colour): door frames, edges, the generator."""
    s = ((XX + YY) // 16) % 2 == 0
    col = np.where(s[..., None], fill(P["yellow"]), fill(P["black"]))
    wear = band(fbm(291, 6) + white(292) * 0.2, 0.68, 0.78)
    col = lerp(col, fill(P["steel_dk"]), wear)
    tex("brut_hazard", col, 0.5 - wear * 0.1)


def roof():
    """Ballasted flat roof: grey gravel over membrane."""
    w = white(301)
    m = fbm(302, 8)
    col = lerp(fill(P["gravel"]), fill(P["gravel_dk"]), blur(w, 1) * 0.8 + m * 0.3)
    tex("brut_roof", col, blur(w, 1), relief=2.0)


def ground():
    """Cracked asphalt yard with patched seams and oil."""
    m = fbm(311, 5)
    col = lerp(fill(P["asph_lt"]), fill(P["asph"]), m)
    agg = white(312) > 0.9
    col[agg] = P["gravel"]
    crack = np.clip(1 - np.abs(fbm(313, 5, 5, 3) - 0.5) / 0.005, 0, 1) * (fbm(314, 3) > 0.6) * 0.7
    col = lerp(col, fill(P["black"]), crack)
    patch = (np.abs(XX - 70) < 10) & (YY > 20) & (YY < 64)  # tar patch over a trench
    col = lerp(col, fill(P["tar"]), patch * 0.0)
    oil = spots([(30, 100, 12)], 315)
    col = lerp(col, fill(P["oil"]), oil * 0.6)
    tex("brut_ground", col, 0.5 + 0.1 * m - crack * 0.3)


def rust():
    """Heavily rusted plate: skips, old tanks, the yard fence."""
    m = fbm(321, 6)
    f = fbm(322, 16)
    col = lerp(fill(P["rust_dk"]), fill(P["rust_lt"]), m * 0.7 + f * 0.3)
    flake = band(f, 0.7, 0.75)
    col = lerp(col, fill(P["steel_dk"]), flake * 0.8)
    tex("brut_rust", col, 0.5 + 0.2 * f, relief=2.0)


def water():
    """Oily dark river."""
    r = fbm(331, 3, 12, 3)
    col = lerp(fill(P["water"]), fill(P["water_lt"]), band(r, 0.55, 0.75))
    sheen = band(fbm(332, 4), 0.72, 0.8)
    col = lerp(col, fill(P["steel_lt"]), sheen * 0.3)
    tex("brut_water", col, r * 0.3, relief=0.6)


BUILD = [cast_conc, panel_conc, conc_floor, block, tread, grate, steel_panel, primer, cladding,
         hazard, roof, ground, rust, water]


def save():
    for f in BUILD:
        f()
    tiles = []
    for name, rgb in TEX.items():
        q = (quantise(rgb) * 255).astype(np.uint8)
        Image.fromarray(q[::-1]).save(os.path.join(K.TEX_DIR, name + "_albedo.png"))
        tiles.append((name, Image.fromarray(q)))
    cell, cols = 512, 5
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
    sheet.save(os.path.join(K.TEX_DIR, "brut_sheet.png"))
    print("wrote", len(tiles), "textures")


if __name__ == "__main__":
    save()
