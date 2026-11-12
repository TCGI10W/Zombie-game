# Dead Protocol - MAP KIT builder v2 (Blender 5.x, run headless):
#   blender -b --factory-startup -P art/blender/build_map_kit.py
# Everything is made from zero here, no downloaded art:
#  * textures: tileable 128px, each drawn as a HEIGHT field first; light and
#    crevice shadow are then baked into the colour (the PS1 way - the retro
#    shader only reads albedo), then dithered and posterized.
#  * props: low-poly primitives with bevelled edges (flat shaded, so the
#    chamfers catch light), world-scale box UVs, nearest-filtered textures.
# Output: art/textures/<name>_albedo.png, art/models/<prop>.glb and
# art/blender/map_kit.blend (all props laid out in a row for editing).
# Conventions: Blender Z up, a prop's FRONT faces +Y (= Godot -Z), origin on
# the floor at the centre. Animated parts keep the names the game looks up:
# LidPivot (crate), Lever + StatusLight (generator).
import bpy, bmesh, math, os, random
import numpy as np
from mathutils import Vector, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "art", "textures")
MODEL_DIR = os.path.join(ROOT, "art", "models")
os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(MODEL_DIR, exist_ok=True)
N = 128

# =================================================================== textures
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5
YY, XX = np.mgrid[0:N, 0:N]


def noise(n, cells, seed):
    """Tileable value noise 0..1 (smoothstep between a cells x cells grid)."""
    g = np.random.default_rng(seed).random((cells, cells))
    t = np.arange(n) * cells / n
    i0 = t.astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    a = g[np.ix_(i0, i0)] * (1 - f)[None, :] + g[np.ix_(i0, i1)] * f[None, :]
    b = g[np.ix_(i1, i0)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(seed, base=4, octaves=4, n=N):
    out, amp, tot = np.zeros((n, n)), 1.0, 0.0
    for o in range(octaves):
        out += noise(n, base * 2 ** o, seed + o * 13) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def white(seed):
    return np.random.default_rng(seed).random((N, N))


def blur(h, r=2):
    out = np.zeros_like(h)
    k = 0
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(np.roll(h, dy, 0), dx, 1)
            k += 1
    return out / k


def ramp(v, cols):
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, [p for p, _ in cols], [col[c] for _, col in cols])
    return out


def mix(a, b, m):
    m = np.clip(m, 0, 1)[..., None]
    return a * (1 - m) + b * m


def shade(col, h, relief=2.0, ao=1.5):
    """Bake top-left key light + cavity occlusion from a height field."""
    gx = np.roll(h, 1, 1) - np.roll(h, -1, 1)
    gy = np.roll(h, 1, 0) - np.roll(h, -1, 0)
    lit = (gx + gy) * relief
    cav = h - blur(h, 3)
    k = np.clip(1.0 + lit + cav * ao, 0.35, 1.6)
    return col * k[..., None]


def cracks(seed, width=0.012, base=6):
    n = fbm(seed, base, 3)
    return np.clip(1 - np.abs(n - 0.5) / width, 0, 1) * (fbm(seed + 5, 3, 2) > 0.5)


def cells(cols, rows, offset=0.0, jitter=0.0, seed=0):
    """Per-pixel cell id, distance to the cell edge (px), for bricks/tiles."""
    ch, cw = N / rows, N / cols
    r = (YY // ch).astype(int)
    xo = XX + (r % 2) * cw * offset
    c = (xo // cw).astype(int) % cols
    ex = np.minimum(xo % cw, cw - xo % cw)
    ey = np.minimum(YY % ch, ch - YY % ch)
    return r * 131 + c, np.minimum(ex, ey)


def per_cell(ids, seed):
    return np.random.default_rng(seed).random(ids.max() + 1)[ids]


def rivets(spacing, r, offs=(0, 0)):
    dx = (XX + offs[0]) % spacing - spacing / 2
    dy = (YY + offs[1]) % spacing - spacing / 2
    return np.clip(1 - np.sqrt(dx * dx + dy * dy) / r, 0, 1)


TEX = {}


def tex(name, col, h=None, relief=2.0, ao=1.5):
    if h is not None:
        col = shade(col, h, relief, ao)
    TEX[name] = np.clip(col, 0, 1)


def build_textures():
    # --- concrete wall: cast panels, form-tie holes, water streaks, chips
    ids, edge = cells(2, 2, 0, seed=1)
    h = fbm(10) * 0.25 + (edge > 1.5) * 0.3 - rivets(32, 2.2, (16, 16)) * 0.5
    h -= cracks(11) * 0.4
    streak = noise(N, 24, 12)[:1].repeat(N, 0) * np.linspace(1, .2, N)[:, None]
    c = ramp(fbm(13) * .6 + per_cell(ids, 14) * .25 + white(15) * .15,
             [(0, (.27, .27, .26)), (.5, (.44, .43, .40)), (1, (.6, .58, .54))])
    c = mix(c, c * np.array([.62, .66, .6]), (streak - .55) * 3)
    tex("concrete", c, h, 1.6, 1.8)
    # --- concrete floor: large slabs, cracks, oil stains
    ids, edge = cells(2, 2, 0.5, seed=2)
    h = fbm(20) * .2 + (edge > 1.2) * .35 - cracks(21) * .5
    c = ramp(fbm(22) * .5 + per_cell(ids, 23) * .3 + white(24) * .2,
             [(0, (.2, .2, .19)), (.5, (.37, .36, .33)), (1, (.5, .49, .45))])
    c = mix(c, c * .45, (fbm(25, 3) - .62) * 6)
    tex("concrete_floor", c, h, 1.6, 1.6)
    # --- asphalt: aggregate, patch repairs, cracks, worn lane paint
    h = white(30) * .3 + fbm(31, 8) * .3 - cracks(32, .015) * .6
    c = ramp(white(33) * .55 + fbm(34) * .45, [(0, (.07, .07, .08)), (.6, (.17, .17, .18)), (1, (.3, .29, .28))])
    patch = (fbm(35, 2, 2) > .6)
    c = mix(c, c * .6, patch)
    paint = (np.abs(XX - N / 2) < 3) & (fbm(36) > .4) & ((YY % 64) < 40)
    c[paint] = c[paint] * .3 + np.array([.62, .56, .3]) * .7
    tex("asphalt", c, h, 1.4, 1.0)
    # --- brick: 4 x 8 running bond, recessed mortar, per-brick tone, soot
    ids, edge = cells(4, 8, 0.5, seed=3)
    mortar = edge < 1.6
    h = np.where(mortar, 0.0, .6 + fbm(40, 16, 2) * .3)
    h = np.minimum(h, blur(h, 1) + .2)
    tone = per_cell(ids, 41)
    c = ramp(tone * .55 + fbm(42, 16, 2) * .45, [(0, (.22, .1, .07)), (.5, (.36, .17, .11)), (1, (.48, .3, .22))])
    c[mortar] = ramp(fbm(43)[mortar] , [(0, (.3, .29, .26)), (1, (.48, .46, .42))])
    c = mix(c, c * .45, (fbm(44, 2, 3) - .5) * 3)
    tex("brick", c, h, 2.2, 2.0)
    # --- stone blocks (church / crypt): big ashlar, chipped corners, moss
    ids, edge = cells(2, 4, 0.5, seed=4)
    joint = edge < (1.5 + fbm(50, 8) * 3)
    h = np.where(joint, 0.0, .55 + fbm(51, 8, 3) * .45)
    c = ramp(per_cell(ids, 52) * .4 + fbm(53, 8, 3) * .6, [(0, (.3, .29, .27)), (.5, (.46, .44, .4)), (1, (.6, .58, .52))])
    c[joint] *= .45
    moss = (fbm(54, 4) - .5) * 4 * np.linspace(.3, 1, N)[:, None]
    c = mix(c, np.array([.2, .26, .12]) * (0.7 + fbm(55, 16, 2)[..., None] * .6), moss)
    tex("stone_block", c, h, 2.0, 2.2)
    # --- plaster with peeling patches that show brick underneath
    ids, edge = cells(4, 8, 0.5, seed=5)
    peel = fbm(60, 3) > .62
    h = np.where(peel, .1 + (edge > 1.5) * .2, .6 + fbm(61, 16, 2) * .1)
    c = ramp(fbm(62) * .7 + white(63) * .3, [(0, (.48, .47, .42)), (1, (.68, .66, .6))])
    c = mix(c, ramp(per_cell(ids, 64), [(0, (.36, .16, .1)), (1, (.55, .3, .2))]), peel)
    c = mix(c, c * .55, (noise(N, 32, 65)[:1].repeat(N, 0) - .6) * 3 * np.linspace(1, .3, N)[:, None])
    tex("plaster", c, h, 2.0, 1.6)
    # --- hospital tiles: 8x8 small tiles, dirty grout, broken ones
    ids, edge = cells(8, 8, 0, seed=6)
    grout = edge < 1.2
    broken = per_cell(ids, 70) > .93
    h = np.where(grout | broken, 0.0, .6)
    c = ramp(per_cell(ids, 71) * .3 + fbm(72) * .7, [(0, (.5, .56, .52)), (1, (.74, .78, .74))])
    c[grout] = (.22, .23, .2)
    c[broken] = ramp(fbm(73)[broken], [(0, (.18, .18, .16)), (1, (.3, .3, .27))])
    c = mix(c, c * np.array([.7, .6, .45]), (fbm(74, 2) - .55) * 4)
    tex("tiles", c, h, 1.6, 1.4)
    # --- dirt ground: mud, pebbles, dead grass
    peb = (white(80) > .993).astype(float)
    peb = np.clip(blur(peb, 1) * 9, 0, 1)
    h = fbm(81, 8) * .5 + peb * .5
    c = ramp(fbm(82, 4) * .7 + white(83) * .3, [(0, (.13, .1, .07)), (.6, (.25, .2, .14)), (1, (.33, .28, .2))])
    c = mix(c, np.array([.3, .28, .25]), peb * .8)
    grass = (white(84) > .92) & (fbm(85, 4) > .5)
    c[grass] = c[grass] * .4 + np.array([.33, .32, .17]) * .6
    tex("dirt", c, h, 1.6, 1.2)
    # --- corrugated rusted metal with rivets and rust bloom
    ribs = np.sin(XX / N * np.pi * 2 * 8) * .5 + .5
    h = ribs * .5 + rivets(16, 1.6, (8, 4)) * (YY % 64 < 8) * .5
    rust = np.clip((fbm(90, 4, 5) - .42) * 5, 0, 1)
    base = ramp(fbm(91) * .5 + ribs * .5, [(0, (.26, .28, .29)), (1, (.46, .47, .47))])
    rr = ramp(fbm(92, 8), [(0, (.25, .1, .04)), (.6, (.5, .24, .09)), (1, (.68, .42, .18))])
    c = mix(base, rr, rust + (noise(N, 32, 93)[:1].repeat(N, 0) - .5) * np.linspace(0, 2, N)[:, None])
    tex("rusted_metal", c, h, 1.8, 1.2)
    # --- wood planks: 4 boards, grain, knots, nails, gaps
    ids, edge = cells(1, 4, 0, seed=7)
    gap = (YY % 32) < 2
    grain = np.sin(XX / N * np.pi * 2 * 3 + fbm(100, 4) * 10 + per_cell(ids, 101) * 6) * .5 + .5
    knot = np.clip(1 - np.hypot((XX - 40 - per_cell(ids, 102) * 50) % N - 0, (YY % 32) - 16) / 5, 0, 1)
    h = np.where(gap, 0, .5 + grain * .2 - knot * .3) + rivets(32, 1.5, (12, 16)) * .4 * ((XX % 64) < 24)
    c = ramp(grain * .45 + per_cell(ids, 103) * .35 + fbm(104, 16, 2) * .2 - knot * .4,
             [(0, (.13, .08, .05)), (.5, (.34, .22, .13)), (1, (.5, .35, .21))])
    c[gap] = (.04, .03, .02)
    tex("wood_planks", c, h, 1.8, 1.6)
    grain2 = np.sin(XX / N * np.pi * 2 * 2 + fbm(105, 4) * 8) * .5 + .5
    tex("wood_board", ramp(grain2 * .6 + fbm(106) * .4, [(0, (.22, .14, .08)), (1, (.54, .39, .24))]), grain2 * .3, 1.2)
    # --- wooden crate face: frame + diagonal brace + stencil
    frame = (np.minimum.reduce([XX, YY, N - 1 - XX, N - 1 - YY]) < 12)
    brace = np.abs(XX - YY) < 8
    board = frame | brace
    h = board * .6 + (np.abs(XX - YY) < 9) * .1 + ((YY % 21) < 1) * -.2
    c = ramp(grain2 * .5 + fbm(107) * .5, [(0, (.28, .18, .1)), (1, (.56, .42, .26))])
    c[~board] *= .78
    stencil = (np.abs(XX - 92) < 14) & (np.abs(YY - 34) < 5) & ((XX // 4) % 2 == 0)
    c[stencil] = c[stencil] * .35
    tex("crate", c, h, 2.0, 1.4)
    # --- burlap sandbag weave
    weave = (((XX // 2) + (YY // 2)) % 2) * .3
    h = weave + fbm(110) * .4
    tex("burlap", ramp(weave + fbm(111) * .7, [(0, (.32, .27, .17)), (1, (.6, .5, .33))]), h, 1.2, 1.0)
    # --- gunmetal: brushed, scratches, panel line, bolts
    brush = noise(N, 64, 120)[:1].repeat(N, 0) * .4 + fbm(121) * .6
    scratch = (cracks(122, .02, 10) > .5)
    h = brush * .2 + rivets(32, 2.0, (6, 6)) * .6 - ((YY % 64) < 1) * .5
    c = ramp(brush, [(0, (.1, .11, .12)), (1, (.3, .31, .33))])
    c[scratch] = c[scratch] * 1.8
    tex("gunmetal", c, h, 1.6, 1.0)
    # --- machine panel: plates, rivets, vent slots
    ids, edge = cells(2, 2, 0, seed=8)
    vent = ((XX % 64) > 34) & ((XX % 64) < 58) & ((YY % 64) > 8) & ((YY % 64) < 30) & (YY % 4 < 2)
    h = (edge > 2) * .5 + rivets(64, 2.5, (6, 6)) * .5 - vent * .6
    c = ramp(fbm(130) * .6 + per_cell(ids, 131) * .4, [(0, (.13, .15, .14)), (1, (.36, .4, .36))])
    c[vent] *= .3
    tex("panel", c, h, 1.8, 1.4)
    # --- painted metals with chipped edges showing rust / bare metal
    for name, a, b, seed in (("paint_rust_red", (.36, .09, .06), (.55, .14, .09), 140),
                             ("paint_olive", (.17, .2, .1), (.31, .34, .18), 150),
                             ("paint_hospital", (.5, .55, .52), (.74, .78, .73), 160),
                             ("paint_dumpster", (.1, .2, .14), (.2, .33, .22), 170),
                             ("paint_orange", (.6, .22, .05), (.85, .4, .1), 180)):
        chip = np.clip((fbm(seed, 6, 4) - .63) * 8, 0, 1)
        h = (1 - chip) * .4 + fbm(seed + 1) * .1
        c = mix(ramp(fbm(seed + 2), [(0, a), (1, b)]),
                ramp(fbm(seed + 3, 16), [(0, (.25, .11, .05)), (1, (.5, .3, .16))]), chip)
        tex(name, c, h, 1.6, 1.2)
    # --- bark, rubber, bone, rock, glass, mattress, hazard, sign
    bark = np.sin(XX / N * np.pi * 2 * 10 + fbm(200, 4) * 6) * .5 + .5
    tex("bark", ramp(bark * .6 + fbm(201) * .4, [(0, (.06, .05, .04)), (1, (.27, .23, .19))]), bark * .6, 2.0)
    tread = ((XX // 6 + YY // 12) % 2) * .4
    tex("rubber", ramp(fbm(210, 16, 2) * .5 + tread * .5, [(0, (.04, .04, .04)), (1, (.16, .16, .15))]), tread, 1.4)
    tex("bone", ramp(fbm(220), [(0, (.42, .37, .27)), (1, (.84, .79, .66))]), fbm(221, 8) * .4, 1.4, 2.0)
    rh = fbm(230, 6, 5)
    tex("rock", ramp(rh, [(0, (.18, .17, .16)), (1, (.52, .5, .47))]), rh, 2.4, 2.0)
    tex("glass_dark", ramp(fbm(240) * .3 + (np.abs(XX - YY) < 10) * .4 + (np.abs(XX - YY - 30) < 4) * .3,
                           [(0, (.03, .05, .06)), (1, (.24, .3, .32))]))
    stain = np.clip((fbm(250, 3) - .58) * 5, 0, 1)
    quilt = ((XX % 32) < 1) | ((YY % 32) < 1)
    tex("mattress", mix(ramp(fbm(251), [(0, (.55, .55, .5)), (1, (.72, .72, .67))]), np.array([.4, .08, .06]), stain),
        quilt * -.4 + .5, 1.2)
    hz = (((XX + YY) // 16) % 2).astype(float)
    worn = fbm(260, 8) > .7
    c = ramp(hz * .85 + fbm(261) * .15, [(0, (.07, .07, .06)), (.6, (.62, .52, .1)), (1, (.78, .64, .15))])
    c[worn] = c[worn] * .5 + np.array([.3, .3, .3]) * .5
    tex("hazard", c)
    # signs: white panel with a red band and dark stripe "lettering"
    c = ramp(fbm(270) * .4 + .6, [(0, (.55, .55, .5)), (1, (.8, .8, .75))])
    c[(YY > 8) & (YY < 30)] = (.55, .1, .08)
    letters = (YY > 50) & (YY < 80) & ((XX // 6) % 3 != 0) & (XX > 12) & (XX < 116)
    c[letters] = (.1, .1, .1)
    tex("sign", mix(c, c * .5, (fbm(271, 4) - .55) * 3))
    # world-shader macro variation map (greyscale, 256)
    m = fbm(300, 2, 5, 256)
    TEX["macro_noise"] = np.repeat(m[..., None], 3, 2)


def save_textures():
    imgs = {}
    for name, rgb in TEX.items():
        n = rgb.shape[0]
        levels = 32 if name == "macro_noise" else 24
        d = np.tile(BAYER, (n // 4, n // 4))[..., None]
        q = np.clip(np.floor(rgb * levels + d + 0.5) / levels, 0, 1)
        fname = name if name == "macro_noise" else name + "_albedo"
        img = bpy.data.images.new(fname, n, n, alpha=False)
        px = np.ones((n, n, 4), dtype=np.float32)
        px[..., :3] = q[::-1]
        img.pixels.foreach_set(px.ravel())
        img.filepath_raw = os.path.join(TEX_DIR, fname + ".png")
        img.file_format = 'PNG'
        img.save()
        imgs[name] = img
    return imgs


# ================================================================== materials
IMGS, MATS = {}, {}


def mat(name, emit=None, metal=0.0, rough=0.9):
    key = (name, emit)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("M_" + name + ("_glow" if emit else ""))
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    img = IMGS.get(name)
    if img:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        tn.interpolation = 'Closest'
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
        if not img:
            bsdf.inputs["Base Color"].default_value = (*emit, 1)
    MATS[key] = m
    return m


# =================================================================== geometry
TEXEL = 1.0  # metres per texture repeat on props


def _obj(name, bm, m):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(m)
    return ob


def _place(ob, loc, rot):
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    return ob


def box(size, loc, m, rot=(0, 0, 0), name="part", bevel=None, taper=None):
    """Bevelled box. `taper` scales the top face (x, y) for wedges/hoods."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if taper:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    b = min(size) * 0.12 if bevel is None else bevel
    b = min(b, 0.035)
    if b > 0.002:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=b, segments=1, affect='EDGES', profile=0.5)
    return _place(_obj(name, bm, m), loc, rot)


def cyl(r, h, loc, m, seg=8, rot=(0, 0, 0), r2=None, name="part", bevel=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    b = min(r, h) * 0.15 if bevel is None else bevel
    b = min(b, 0.03)
    if b > 0.003:
        rim = [e for e in bm.edges if len(e.link_faces) == 2 and
               abs(e.link_faces[0].normal.z) != abs(e.link_faces[1].normal.z)]
        bmesh.ops.bevel(bm, geom=rim, offset=b, segments=1, affect='EDGES', profile=0.5)
    return _place(_obj(name, bm, m), loc, rot)


def ring(r, tube, loc, m, seg=10, tseg=4, rot=(0, 0, 0)):
    """Low-poly torus (tires, hoops)."""
    bm = bmesh.new()
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(tseg):
            b = 2 * math.pi * j / tseg + math.pi / tseg
            rr = r + tube * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), tube * 1.3 * math.sin(b))))
        verts.append(row)
    for i in range(seg):
        for j in range(tseg):
            bm.faces.new((verts[i][j], verts[(i + 1) % seg][j], verts[(i + 1) % seg][(j + 1) % tseg],
                          verts[i][(j + 1) % tseg]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _place(_obj("part", bm, m), loc, rot)


def ball(r, loc, m, seg=8, rings=6, scale=(1, 1, 1), name="part", jitter=0.0, seed=0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    if jitter:
        rnd = random.Random(seed)
        for v in bm.verts:
            v.co *= 1 + rnd.uniform(-jitter, jitter)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    ob = _obj(name, bm, m)
    ob.location = loc
    return ob


def rod(a, b, r, m, seg=4):
    a, b = Vector(a), Vector(b)
    d = b - a
    ob = cyl(r, d.length, (a + b) / 2, m, seg, bevel=0)
    ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return ob


def box_uv(ob):
    """World-scale box projection; dominant axis per face."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    mw = ob.matrix_world
    for f in bm.faces:
        n = mw.to_3x3() @ f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = mw @ l.vert.co
            u, v = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            if (ax == 0 and n[0] < 0) or (ax == 1 and n[1] > 0):
                u = -u
            l[uv].uv = (u / TEXEL, v / TEXEL)
    bm.to_mesh(me)
    bm.free()


def face_uv(ob):
    """Each face gets the whole 0..1 texture (crate faces, signs)."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        pts = [[(l.vert.co.y, l.vert.co.z), (l.vert.co.x, l.vert.co.z), (l.vert.co.x, l.vert.co.y)][ax] for l in f.loops]
        us, vs = [p[0] for p in pts], [p[1] for p in pts]
        du, dv = (max(us) - min(us)) or 1, (max(vs) - min(vs)) or 1
        for l, p in zip(f.loops, pts):
            l[uv].uv = ((p[0] - min(us)) / du, (p[1] - min(vs)) / dv)
    bm.to_mesh(me)
    bm.free()
    ob["face_uv"] = True


def finish(root_name, parts, children=()):
    bpy.context.view_layer.update()
    for p in list(parts) + [c for c in children if c.type == 'MESH']:
        if not p.get("face_uv"):
            box_uv(p)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = root_name + "_mesh"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    root = bpy.data.objects.new(root_name, None)
    bpy.context.scene.collection.objects.link(root)
    body.parent = root
    for c in children:
        if c.parent is None:
            c.parent = root
    return root


def select_tree(ob):
    ob.select_set(True)
    for c in ob.children:
        select_tree(c)


def export(root):
    bpy.ops.object.select_all(action='DESELECT')
    select_tree(root)
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODEL_DIR, root.name + ".glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True)


def wheel(x, y, r, w, m, hub):
    return [cyl(r, w, (x, y, r), m, seg=10, rot=(0, 90, 0)),
            cyl(r * .55, w + .02, (x, y, r), hub, seg=8, rot=(0, 90, 0))]


# ====================================================================== props
def p_barrel():
    M, R = mat("rusted_metal", metal=.6), mat("paint_rust_red")
    P = [cyl(.3, .92, (0, 0, .47), R, seg=12), cyl(.27, .02, (0, 0, .935), M, seg=12, bevel=0)]
    for z in (.03, .32, .64, .92):
        P.append(cyl(.315, .045, (0, 0, z), M, seg=12, bevel=.01))
    P.append(cyl(.05, .04, (.15, .08, .95), M, seg=6))
    P.append(cyl(.03, .03, (-.15, -.1, .95), M, seg=6))
    P.append(box((.26, .01, .16), (0, .3, .6), mat("hazard"), bevel=0))
    return finish("prop_barrel", P)


def p_tire_stack():
    T, M = mat("rubber"), mat("gunmetal")
    P = []
    for i in range(4):
        P.append(ring(.32, .12, (random.uniform(-.04, .04), random.uniform(-.04, .04), .12 + i * .22), T,
                      seg=12, rot=(random.uniform(-4, 4), random.uniform(-4, 4), random.uniform(0, 30))))
    P.append(cyl(.24, .02, (0, 0, .05), M, seg=8, bevel=0))
    return finish("prop_tire_stack", P)


def p_sandbags():
    B = mat("burlap")
    P = []
    for row in range(3):
        n = 3 - (row == 2)
        for i in range(n):
            x = (i - (n - 1) / 2) * .54 + (row % 2) * .04
            P.append(ball(.3, (x, 0, .11 + row * .21), B, seg=8, rings=4, scale=(.95, .6, .38),
                          jitter=.08, seed=row * 7 + i))
    return finish("prop_sandbags", P)


def p_car_wreck():
    R, G, T, M, H = mat("paint_rust_red"), mat("glass_dark"), mat("rubber"), mat("rusted_metal"), mat("gunmetal")
    P = [box((1.84, 4.3, .5), (0, 0, .58), R, bevel=.06),
         box((1.6, 2.1, .52), (0, -.3, 1.08), R, taper=(.86, .8), bevel=.05),
         box((1.4, .06, .44), (0, .67, 1.08), G, rot=(-38, 0, 0), bevel=0),
         box((1.4, .06, .4), (0, -1.3, 1.08), G, rot=(30, 0, 0), bevel=0),
         box((1.86, 1.7, .3), (0, -.3, 1.04), G, taper=(.9, .9), bevel=0),
         box((1.9, .18, .22), (0, 2.16, .42), H), box((1.9, .18, .22), (0, -2.16, .42), H),
         box((1.5, .02, .2), (0, 2.16, .65), M, bevel=0),           # grille
         box((.3, .02, .14), (-.65, 2.16, .7), mat("glass_dark", emit=(.9, .8, .5))),
         box((.3, .02, .14), (.65, 2.16, .7), G),                   # smashed headlight
         box((.4, .02, .1), (-.6, -2.16, .72), mat("paint_rust_red", emit=(.6, .05, .03))),
         box((1.7, 1.2, .06), (0, 1.45, .86), R, rot=(6, 0, 0)),    # crumpled bonnet
         box((.04, .5, .3), (.93, -.3, .85), M), box((.04, .5, .3), (-.93, .4, .85), M)]
    for x in (-.82, .82):
        for y in (-1.35, 1.4):
            P += wheel(x, y, .33, .22, T, H)
    return finish("prop_car_wreck", P)


def p_truck():
    O, G, T, M, C, H = (mat("paint_olive"), mat("glass_dark"), mat("rubber"), mat("gunmetal", metal=.5),
                        mat("burlap"), mat("hazard"))
    P = [box((2.0, 7.0, .3), (0, 0, .85), M),
         box((2.4, 2.0, 1.5), (0, 2.5, 1.8), O, bevel=.06),
         box((2.3, 1.4, .7), (0, 2.6, 2.85), O, taper=(.95, .8)),
         box((2.0, .06, .55), (0, 3.25, 2.8), G, rot=(-15, 0, 0), bevel=0),
         box((.06, .9, .5), (1.2, 2.5, 2.75), G, bevel=0), box((.06, .9, .5), (-1.2, 2.5, 2.75), G, bevel=0),
         box((2.3, .1, .6), (0, 3.52, 1.3), M),                           # grille
         box((2.5, .25, .25), (0, 3.6, .9), H),                           # bumper
         box((2.45, 4.6, .5), (0, -1.1, 1.25), O),                        # bed
         box((2.45, 4.6, .08), (0, -1.1, 3.6), C, bevel=.02),             # tarp roof
         box((.06, 4.6, 2.1), (1.2, -1.1, 2.55), C, bevel=0), box((.06, 4.6, 2.1), (-1.2, -1.1, 2.55), C, bevel=0),
         box((2.4, .06, 1.5), (0, -3.38, 2.3), C, bevel=0),
         box((.5, .6, .5), (1.1, .8, .9), M), cyl(.25, .9, (-1.0, .8, .95), M, seg=8, rot=(90, 0, 0)),
         rod((1.25, 1.6, 1.2), (1.25, 1.6, 3.3), .05, M), box((.35, .05, .25), (-1.25, 3.3, 2.5), M)]
    for i in range(3):
        P.append(box((2.5, .08, .08), (0, -3.2 + i * 2.1, 3.55), M, rot=(0, 0, 0)))
        P.append(box((.08, .08, 2.2), (1.24, -3.2 + i * 2.1, 2.5), M))
        P.append(box((.08, .08, 2.2), (-1.24, -3.2 + i * 2.1, 2.5), M))
    for x in (-1.05, 1.05):
        for y in (2.5, -1.0, -2.4):
            P += wheel(x, y, .55, .4, T, M)
    return finish("prop_truck", P)


def p_fuel_tank():
    M, H, R = mat("rusted_metal", metal=.6), mat("hazard"), mat("paint_rust_red")
    P = [cyl(.95, 3.2, (0, 0, 1.2), M, seg=12, rot=(90, 0, 0)),
         cyl(.9, .2, (0, 1.68, 1.2), M, seg=12, r2=.5, rot=(-90, 0, 0)),
         cyl(.9, .2, (0, -1.68, 1.2), M, seg=12, r2=.5, rot=(90, 0, 0))]
    for y in (-1.0, 0, 1.0):
        P.append(cyl(.97, .06, (0, y, 1.2), M, seg=12, rot=(90, 0, 0), bevel=0))
    for y in (-1.1, 1.1):
        P.append(box((1.8, .3, .5), (0, y, .25), H, taper=(.7, 1)))
    P.append(cyl(.25, .25, (0, .5, 2.2), M, seg=8))
    P.append(cyl(.3, .05, (0, .5, 2.34), R, seg=8))
    P.append(box((.6, .03, .4), (.96, 0, 1.2), mat("sign"), rot=(0, 0, 90), bevel=0))
    for z in (.3, .9, 1.5):
        P.append(rod((1.0, 1.4, z), (1.0, 1.75, z), .02, M))
    P.append(rod((1.0, 1.4, .1), (1.0, 1.4, 2.2), .03, M))
    P.append(rod((1.0, 1.75, .1), (1.0, 1.75, 2.2), .03, M))
    P.append(cyl(.06, .5, (-.6, 1.6, .35), M, seg=6, rot=(90, 0, 0)))
    return finish("prop_fuel_tank", P)


def p_dead_tree():
    B = mat("bark")
    P = [cyl(.36, 1.0, (0, 0, .45), B, seg=7, r2=.28), cyl(.28, 2.4, (0, 0, 2.1), B, seg=7, r2=.18)]
    rnd = random.Random(7)

    def branch(a, d, length, r, depth):
        b = a + d.normalized() * length
        P.append(rod(a, b, r, B, seg=5))
        if depth:
            for _ in range(2 + (depth == 2)):
                nd = d.normalized() + Vector((rnd.uniform(-.9, .9), rnd.uniform(-.9, .9), rnd.uniform(-.1, .7)))
                branch(b, nd, length * rnd.uniform(.55, .7), r * .6, depth - 1)
    for ang, z in ((0, 3.1), (2.1, 2.5), (4.2, 3.2), (1.0, 1.9)):
        branch(Vector((0, 0, z)), Vector((math.cos(ang), math.sin(ang), 1.0)), 1.8, .12, 2)
    for ang in range(0, 360, 60):
        a = math.radians(ang + 10)
        P.append(rod((0, 0, .35), (math.cos(a) * .9, math.sin(a) * .9, -.08), .11, B, seg=5))
    return finish("prop_dead_tree", P)


def p_desk():
    W, M, G, Pn = mat("wood_board"), mat("gunmetal"), mat("glass_dark"), mat("panel")
    P = [box((1.6, .8, .05), (0, -.4, .76), W, bevel=.01)]
    for x in (-.76, .76):
        P.append(box((.05, .74, .72), (x, -.4, .37), M))
    P += [box((.48, .7, .55), (.5, -.4, .46), Pn),
          box((.44, .02, .14), (.5, -.04, .6), M), box((.44, .02, .14), (.5, -.04, .4), M),
          box((.12, .02, .03), (.5, -.03, .62), mat("gunmetal")),
          box((.5, .42, .38), (0, -.62, 1.0), Pn, taper=(.8, .7)),                 # CRT back
          box((.52, .1, .42), (0, -.38, 1.0), Pn),
          box((.42, .02, .32), (0, -.32, 1.0), mat("glass_dark", emit=(.15, .4, .25))),
          box((.45, .16, .03), (0, -.15, .8), M),                                  # keyboard
          box((.25, .3, .02), (-.5, -.3, .79), mat("sign"), rot=(0, 0, 15), bevel=0),  # papers
          cyl(.04, .1, (-.62, -.55, .83), mat("paint_hospital"), seg=6),           # mug
          box((.5, .5, .05), (-.15, .3, .47), W), box((.5, .05, .55), (-.15, .54, .75), W, rot=(-8, 0, 0)),
          cyl(.03, .44, (-.15, .3, .23), M, seg=5), box((.5, .05, .04), (-.15, .3, .02), M, rot=(0, 0, 0)),
          box((.05, .5, .04), (-.15, .3, .02), M)]
    return finish("prop_desk", P)


def p_gurney():
    M, S, T = mat("gunmetal", metal=.6), mat("mattress"), mat("rubber")
    P = [box((.66, 1.9, .12), (0, 0, .86), S, bevel=.04), box((.72, 1.98, .05), (0, 0, .78), M),
         box((.6, .4, .1), (0, .72, .97), S, rot=(-12, 0, 0), bevel=.03),        # pillow
         box((.02, 1.6, .02), (.37, 0, .95), M), box((.02, 1.6, .02), (-.37, 0, .95), M)]
    for x in (-.3, .3):
        for y in (-.88, .88):
            P.append(box((.035, .035, .66), (x, y, .43), M, bevel=0))
            P.append(cyl(.055, .04, (x, y, .06), T, seg=8, rot=(0, 90, 0)))
    P.append(box((.6, .03, .03), (0, -.88, .3), M)), P.append(box((.6, .03, .03), (0, .88, .3), M))
    P.append(box((.72, .04, .4), (0, .98, 1.0), M))
    P.append(box((.72, .04, .3), (0, -.98, .95), M))
    return finish("prop_gurney", P)


def p_lamp_post():
    M = mat("gunmetal", metal=.5)
    P = [cyl(.22, .12, (0, 0, .06), M, seg=8), cyl(.16, .5, (0, 0, .35), M, seg=8, r2=.11),
         cyl(.08, 4.0, (0, 0, 2.55), M, seg=8, r2=.055), cyl(.1, .1, (0, 0, 4.5), M, seg=8),
         rod((0, 0, 4.45), (0, .55, 4.62), .045, M), rod((0, .55, 4.62), (0, .95, 4.58), .045, M),
         box((.3, .55, .16), (0, 1.0, 4.52), M, taper=(.7, .8)),
         box((.22, .38, .03), (0, 1.0, 4.43), mat("glass_dark", emit=(1.0, .8, .45)), bevel=0),
         box((.18, .02, .5), (0, -.09, 2.2), mat("sign"), bevel=0),               # flyer
         box((.25, .18, .32), (0, -.15, 1.4), M)]                                 # junction box
    return finish("prop_lamp_post", P)


def p_lockers():
    M, D = mat("panel"), mat("gunmetal")
    P = [box((2.2, .72, 1.94), (0, 0, 1.0), M, bevel=.02), box((2.24, .76, .06), (0, 0, .03), D)]
    for i in range(4):
        x = -.825 + i * .55
        if i == 2:  # one door hangs open
            P.append(box((.5, .03, 1.8), (x + .2, .62, 1.0), M, rot=(0, 0, 65), bevel=.01))
            P.append(box((.48, .02, 1.8), (x, .35, 1.0), mat("glass_dark"), bevel=0))
            P.append(box((.4, .3, .02), (x, .2, 1.5), D, bevel=0))
            continue
        P.append(box((.5, .03, 1.8), (x, .37, 1.0), M, bevel=.01))
        for k in range(4):
            P.append(box((.3, .02, .025), (x, .39, 1.55 + k * .06), D, bevel=0))
        P.append(box((.03, .03, .14), (x + .18, .39, 1.0), D, bevel=0))
        P.append(box((.12, .01, .05), (x, .39, 1.82), mat("sign"), bevel=0))
    return finish("prop_lockers", P)


def p_radio_tower():
    M, H = mat("rusted_metal", metal=.6), mat("hazard")
    P = []
    top = 22.0
    w = lambda z: 1.4 * (1 - z / top) + .25
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for cx, cy in corners:
        P.append(rod((cx * w(0), cy * w(0), 0), (cx * w(top), cy * w(top), top), .07, M))
        P.append(box((.4, .4, .3), (cx * w(0), cy * w(0), .15), mat("concrete")))
    z = 0.0
    while z < top - .1:
        z2 = min(z + 2.0, top)
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            P.append(rod((a[0] * w(z), a[1] * w(z), z), (b[0] * w(z2), b[1] * w(z2), z2), .03, M))
            P.append(rod((b[0] * w(z), b[1] * w(z), z), (a[0] * w(z2), a[1] * w(z2), z2), .03, M))
            P.append(rod((a[0] * w(z2), a[1] * w(z2), z2), (b[0] * w(z2), b[1] * w(z2), z2), .035, M))
        z = z2
    P.append(box((.8, .2, 1.2), (.4, .4, 15), M)), P.append(box((.8, .2, 1.2), (-.4, -.4, 17), M))
    P.append(cyl(.5, .15, (0, .55, 19), M, seg=8, rot=(90, 0, 0)))                 # dish
    P.append(cyl(.04, 2.5, (0, 0, top + 1.25), M, seg=4))
    P.append(ball(.16, (0, 0, top + 2.6), mat("glass_dark", emit=(1, .1, .05)), seg=6, rings=4))
    P.append(ball(.12, (0, 0, 11), mat("glass_dark", emit=(1, .1, .05)), seg=6, rings=4))
    P.append(box((2.4, .1, 1.0), (0, 1.6, .5), H, bevel=0))
    return finish("prop_radio_tower", P)


def p_rubble():
    C, R, B = mat("concrete"), mat("rusted_metal"), mat("brick")
    rnd = random.Random(11)
    P = []
    for i in range(12):
        s = rnd.uniform(.25, .85)
        P.append(box((s, s * rnd.uniform(.6, 1.2), s * rnd.uniform(.3, .6)),
                     (rnd.uniform(-.85, .85), rnd.uniform(-.75, .75), s * .15 + (i > 7) * .35),
                     C if i % 3 else B, rot=(rnd.uniform(-30, 30), rnd.uniform(-30, 30), rnd.uniform(0, 90)),
                     taper=(rnd.uniform(.6, 1), rnd.uniform(.6, 1))))
    for i in range(8):
        P.append(ball(.08, (rnd.uniform(-1, 1), rnd.uniform(-.9, .9), .03), mat("rock"), seg=5, rings=3,
                      jitter=.3, seed=i))
    for i in range(5):
        a = Vector((rnd.uniform(-.6, .6), rnd.uniform(-.6, .6), .2))
        P.append(rod(a, a + Vector((rnd.uniform(-.6, .6), rnd.uniform(-.6, .6), rnd.uniform(.4, 1.0))), .015, R))
    return finish("prop_rubble", P)


def p_generator():
    O, M, H, Pn = mat("paint_olive"), mat("gunmetal", metal=.5), mat("hazard"), mat("panel")
    P = [box((2.5, 1.2, 1.7), (0, 0, 1.05), O, bevel=.05), box((2.6, 1.26, .2), (0, 0, .1), H),
         box((2.3, 1.0, .1), (0, 0, 1.95), M),
         cyl(.4, 2.0, (-.15, -.15, 2.4), M, seg=10, rot=(0, 90, 0)),
         cyl(.42, .05, (-.9, -.15, 2.4), O, seg=10, rot=(0, 90, 0), bevel=0),
         cyl(.42, .05, (.6, -.15, 2.4), O, seg=10, rot=(0, 90, 0), bevel=0),
         cyl(.09, .7, (1.0, -.35, 2.3), M, seg=6), cyl(.12, .1, (1.0, -.35, 2.7), M, seg=6),
         box((.95, .05, .8), (-.5, .61, 1.3), Pn, bevel=.01),
         box((.8, .04, .2), (-.5, .64, 1.6), mat("sign"), bevel=0),
         cyl(.07, .04, (-.75, .64, 1.0), M, seg=8, rot=(90, 0, 0)),
         cyl(.07, .04, (-.25, .64, 1.0), M, seg=8, rot=(90, 0, 0))]
    for i in range(7):
        P.append(box((.05, .04, 1.1), (.35 + i * .13, .61, 1.05), M, bevel=0))
    for x in (-1.2, 1.2):
        P.append(box((.12, 1.3, .12), (x, 0, 2.0), M))
    rnd = random.Random(5)
    cable = [Vector((1.25, .2, .3))]
    for i in range(5):
        cable.append(cable[-1] + Vector((rnd.uniform(.2, .4), rnd.uniform(-.3, .3), -.05 if i == 0 else 0)))
    for a, b in zip(cable, cable[1:]):
        P.append(rod(a, b, .03, mat("rubber")))
    lever = bpy.data.objects.new("Lever", None)
    bpy.context.scene.collection.objects.link(lever)
    lever.location = (-.6, .66, 1.2)
    base = box((.14, .06, .14), (-.6, .64, 1.2), M)
    P.append(base)
    stick = box((.05, .05, .45), (0, 0, .22), M, name="LeverStick")
    knob = ball(.06, (0, 0, .46), mat("paint_rust_red"), seg=6, rings=4, name="LeverKnob")
    for o in (stick, knob):
        o.parent = lever
    status = box((.14, .05, .14), (.45, .63, 1.4), mat("glass_dark", emit=(1, .15, .1)), name="StatusLight")
    return finish("prop_generator", P, [lever, stick, knob, status])


def p_radio_console():
    Pn, M, G = mat("panel"), mat("gunmetal"), mat("glass_dark", emit=(.3, .9, .4))
    P = [box((1.5, .72, 1.05), (0, 0, .53), Pn, bevel=.02), box((1.4, .5, .95), (0, -.1, 1.55), Pn, bevel=.02),
         box((1.5, .45, .06), (0, .2, 1.08), M), box((.62, .03, .4), (-.3, .16, 1.68), G, bevel=0),
         box((.7, .04, .48), (-.3, .155, 1.68), M), box((.4, .03, .2), (.4, .16, 1.85), mat("glass_dark")),
         box((.25, .1, .2), (.35, .3, 1.2), M), rod((.35, .35, 1.3), (.35, .45, 1.32), .02, mat("rubber")),
         box((1.3, .02, .5), (0, .37, .55), M)]
    for i in range(6):
        P.append(cyl(.035, .04, (.15 + i * .09, .16, 1.48), mat("paint_rust_red"), seg=6, rot=(90, 0, 0)))
    for i in range(4):
        P.append(box((.03, .02, .1), (-.55 + i * .1, .16, 1.32), mat("sign"), bevel=0))
    P += [cyl(.03, 1.3, (.55, -.2, 2.65), M, seg=4), ball(.05, (.55, -.2, 3.3), mat("glass_dark", emit=(1, .2, .1)),
                                                         seg=6, rings=4),
          rod((-.5, -.25, 2.0), (-.5, -.25, 2.9), .015, M)]
    return finish("prop_radio_console", P)


def p_mystery_crate():
    W, M = mat("crate"), mat("gunmetal")
    body = box((1.6, .74, .55), (0, 0, .28), W, bevel=.02)
    face_uv(body)
    P = [body]
    for x in (-.78, .78):
        P.append(box((.06, .78, .6), (x, 0, .3), M))
    for y in (-.38, .38):
        P.append(box((1.62, .04, .06), (0, y, .05), M))
    P.append(box((1.3, .02, .16), (0, .38, .3), mat("hazard"), bevel=0))
    for x in (-.5, .5):
        P.append(box((.12, .06, .1), (x, .39, .5), M))  # latches
    piv = bpy.data.objects.new("LidPivot", None)
    bpy.context.scene.collection.objects.link(piv)
    piv.location = (0, -.37, .56)
    lid = box((1.62, .76, .14), (0, .37, .07), W, name="Lid", bevel=.02)
    face_uv(lid)
    lid.parent = piv
    strap = box((.08, .78, .16), (.5, .37, .07), M, name="LidStrap")
    strap.parent = piv
    glow = box((1.4, .6, .02), (0, 0, .54), mat("glass_dark", emit=(.4, .8, 1.0)), name="Glow", bevel=0)
    return finish("prop_mystery_crate", P, [piv, lid, strap, glow])


def p_med_station():
    H, G, M = mat("paint_hospital"), mat("glass_dark"), mat("gunmetal")
    R = mat("paint_rust_red", emit=(1, .15, .15))
    P = [box((1.4, .5, 2.1), (0, 0, 1.05), H, bevel=.03), box((1.46, .55, .1), (0, 0, 2.12), M),
         box((1.1, .03, 1.0), (0, .26, 1.35), G, bevel=0), box((1.18, .04, 1.08), (0, .255, 1.35), M),
         box((.4, .03, .12), (0, .27, 1.98), R, bevel=0), box((.12, .03, .4), (0, .27, 1.98), R, bevel=0),
         box((1.2, .3, .03), (0, .1, 1.0), H), box((1.2, .3, .03), (0, .1, 1.45), H),
         box((.8, .04, .6), (0, .26, .45), H), box((.15, .02, .03), (0, .29, .6), M),
         box((.4, .02, .12), (.35, .27, .25), mat("sign"), bevel=0)]
    for i in range(4):
        P.append(cyl(.05, .2, (-.4 + i * .27, .1, 1.12), mat("glass_dark", emit=(.2, 1, .4)), seg=6))
        P.append(box((.14, .1, .12), (-.4 + i * .27, .1, 1.53), mat("paint_hospital")))
    return finish("prop_med_station", P)


def p_weapon_forge():
    M, H, W = mat("gunmetal", metal=.6), mat("hazard"), mat("wood_board")
    P = [box((1.8, 1.0, .85), (0, 0, .43), M), box((1.86, 1.1, .08), (0, 0, .9), W, bevel=.01),
         box((1.6, .7, 1.2), (0, -.2, 2.4), M, taper=(.7, .6)), box((1.7, .9, .12), (0, -.05, 1.75), H),
         rod((.85, .35, .94), (.85, .35, 1.7), .04, M), rod((-.85, .35, .94), (-.85, .35, 1.7), .04, M),
         box((.45, .22, .14), (.35, .1, 1.0), mat("rock")), box((.25, .15, .14), (.35, .1, 1.14), mat("rock")),
         box((.6, .03, .4), (-.4, .51, .5), mat("glass_dark", emit=(1, .5, .1)), bevel=0),
         box((.66, .04, .46), (-.4, .505, .5), M),
         cyl(.12, .7, (.6, -.3, 3.3), M, seg=6), box((1.4, .05, .5), (0, -.52, 1.25), mat("panel")),
         box((.06, .3, .02), (-.3, .1, .95), M, rot=(0, 0, 30)), box((.05, .05, .25), (-.2, .2, .97), W,
                                                                    rot=(0, 80, 20))]
    for i in range(5):
        P.append(box((.03, .02, .2), (-.6 + i * .15, -.5, 1.3), M, bevel=0))  # hanging tools
    return finish("prop_weapon_forge", P)


def p_augment_furnace():
    S, M = mat("brick"), mat("rusted_metal", metal=.5)
    P = [box((1.6, 1.0, 1.9), (0, 0, 1.05), S, bevel=.02), box((1.0, .55, 1.0), (0, 0, 2.5), S, taper=(.8, .8)),
         cyl(.16, 1.0, (0, 0, 3.0), M, seg=8), cyl(.2, .1, (0, 0, 3.45), M, seg=8),
         box((.8, .05, .7), (0, .51, .9), mat("glass_dark", emit=(1, .35, .05)), bevel=0),
         box((.95, .08, .85), (0, .5, .9), M), box((.9, .1, .06), (0, .55, .4), M),
         box((1.7, 1.06, .15), (0, 0, .08), M), box((1.7, 1.06, .1), (0, 0, 2.0), M),
         box((.3, .1, .15), (.6, .52, 1.6), mat("panel")), cyl(.05, .3, (-.5, .6, 1.5), M, seg=6, rot=(90, 0, 0))]
    for x in (-.8, .8):
        for y in (-.5, .5):
            P.append(box((.1, .1, 2.0), (x, y, 1.0), M))
    return finish("prop_augment_furnace", P)


def p_skull():
    B, D = mat("bone"), mat("rubber")
    P = [ball(.1, (0, -.01, .15), B, seg=10, rings=7, scale=(.95, 1.15, 1)),
         box((.13, .08, .06), (0, .08, .06), B, bevel=.015), box((.1, .06, .03), (0, .07, .02), B, bevel=.01)]
    for x in (-.04, .04):
        P.append(box((.04, .03, .035), (x, .11, .135), D, bevel=.008))
    P.append(box((.02, .02, .03), (0, .125, .09), D, bevel=0))
    return finish("prop_skull", P)


def p_grenade():
    O, M = mat("paint_olive"), mat("gunmetal", metal=.6)
    P = [ball(.034, (0, 0, 0), O, seg=8, rings=6, scale=(1, 1, 1.25)),
         cyl(.016, .03, (0, 0, .05), M, seg=6), box((.008, .015, .075), (.022, 0, .025), M, rot=(0, -8, 0)),
         ring(.012, .003, (-.018, 0, .062), M, seg=6, tseg=3, rot=(90, 0, 0))]
    return finish("prop_grenade", P)


# ---- new kit pieces
def p_wood_crate():
    W, M = mat("crate"), mat("gunmetal")
    b = box((1.2, 1.2, 1.2), (0, 0, .6), W, bevel=.03)
    face_uv(b)
    return finish("prop_wood_crate", [b, box((1.22, .05, .05), (0, -.6, .03), M), box((1.22, .05, .05), (0, .6, .03), M)])


def p_pallet():
    W = mat("wood_board")
    P = []
    for i in range(5):
        P.append(box((.14, 1.2, .025), (-.48 + i * .24, 0, .13), W, bevel=.005))
    for x in (-.5, 0, .5):
        P.append(box((.1, 1.2, .1), (x, 0, .06), W, bevel=.01))
    P.append(box((1.0, 1.0, .02), (0, 0, .16), mat("crate"), rot=(0, 0, 4), bevel=0))
    return finish("prop_pallet", P)


def p_dumpster():
    G, M, R = mat("paint_dumpster"), mat("gunmetal"), mat("rubber")
    P = [box((1.9, 1.1, 1.1), (0, 0, .7), G, taper=(1, 1.15), bevel=.04),
         box((2.0, .7, .06), (0, -.25, 1.3), mat("paint_dumpster"), rot=(-8, 0, 0)),
         box((2.0, .55, .06), (0, .45, 1.55), mat("paint_dumpster"), rot=(-70, 0, 0)),   # open lid
         box((2.0, .08, .08), (0, .62, 1.0), M), box((1.0, .02, .3), (0, .62, .7), mat("sign"), bevel=0)]
    for x in (-.8, .8):
        for y in (-.4, .4):
            P.append(cyl(.08, .06, (x, y, .08), R, seg=8, rot=(0, 90, 0)))
    for i in range(4):
        P.append(ball(.25, (-.5 + i * .33, -.1, 1.3), R, seg=6, rings=4, jitter=.2, seed=i))  # bags poking out
    return finish("prop_dumpster", P)


def p_jersey_barrier():
    C, H = mat("concrete"), mat("hazard")
    P = [box((2.0, .6, .3), (0, 0, .15), C, bevel=.02), box((2.0, .6, .55), (0, 0, .55), C, taper=(1, .35)),
         box((2.0, .24, .02), (0, .2, .55), H, rot=(-68, 0, 0), bevel=0)]
    P.append(rod((-.9, 0, .8), (-.9, 0, .95), .02, mat("rusted_metal")))
    return finish("prop_jersey_barrier", P)


def p_traffic_cone():
    O, R = mat("paint_orange"), mat("rubber")
    P = [box((.38, .38, .04), (0, 0, .02), R), cyl(.15, .6, (0, 0, .34), O, seg=8, r2=.03),
         cyl(.115, .08, (0, 0, .4), mat("paint_hospital"), seg=8, r2=.095, bevel=0)]
    return finish("prop_traffic_cone", P)


def p_bench():
    W, M = mat("wood_board"), mat("gunmetal")
    P = []
    for i in range(3):
        P.append(box((1.8, .12, .04), (0, -.15 + i * .14, .45), W, bevel=.008))
    for i in range(2):
        P.append(box((1.8, .04, .12), (0, .2, .62 + i * .16), W, rot=(-10, 0, 0), bevel=.008))
    for x in (-.8, .8):
        P += [box((.06, .5, .06), (x, 0, .42), M), box((.06, .06, .45), (x, -.2, .22), M),
              box((.06, .06, .85), (x, .2, .42), M)]
    P[0].rotation_euler.y = math.radians(-4)  # one sagging slat
    return finish("prop_bench", P)


def p_gravestone():
    S = mat("stone_block")
    P = [box((.7, .2, .7), (0, 0, .35), S, bevel=.02), cyl(.35, .2, (0, 0, .7), S, seg=10, rot=(90, 0, 0)),
         box((.9, .35, .1), (0, .02, .05), S), box((.4, .02, .05), (0, .1, .55), mat("rock"), bevel=0),
         box((.3, .02, .04), (0, .1, .45), mat("rock"), bevel=0),
         box((.7, 1.6, .06), (0, .9, .03), mat("dirt"), bevel=0)]  # grave mound
    return finish("prop_gravestone", P)


def p_grave_cross():
    S = mat("stone_block")
    P = [box((.18, .16, 1.2), (0, 0, .65), S), box((.7, .16, .18), (0, 0, .95), S),
         box((.6, .4, .1), (0, 0, .05), S), box((.7, 1.6, .06), (0, .9, .03), mat("dirt"), bevel=0)]
    for p in P[:2]:
        p.rotation_euler.y = math.radians(7)
    return finish("prop_grave_cross", P)


def p_trash_bags():
    R = mat("rubber")
    P = [ball(.3, (rx, ry, .22), R, seg=7, rings=5, scale=(1, .9, .8), jitter=.15, seed=i)
         for i, (rx, ry) in enumerate(((0, 0), (.45, .15), (-.35, .25), (.15, -.4)))]
    P.append(box((.3, .25, .2), (.5, -.35, .1), mat("crate"), rot=(0, 0, 30)))
    return finish("prop_trash_bags", P)


def p_street_sign():
    M = mat("gunmetal")
    P = [cyl(.04, 2.6, (0, 0, 1.3), M, seg=6), box((.7, .03, .45), (0, .05, 2.3), mat("sign"), rot=(0, 6, 0)),
         box((.5, .03, .14), (.15, .05, 1.85), mat("paint_dumpster"), rot=(0, 0, 0)), box((.2, .2, .1), (0, 0, .05), M)]
    return finish("prop_street_sign", P)


def p_pipe_stack():
    M, W = mat("rusted_metal", metal=.5), mat("wood_board")
    P = []
    for row, n in ((0, 4), (1, 3), (2, 2)):
        for i in range(n):
            x = (i - (n - 1) / 2) * .42
            P.append(cyl(.2, 3.0, (x, 0, .3 + row * .36), M, seg=8, rot=(90, 0, 0)))
            P.append(cyl(.15, 3.02, (x, 0, .3 + row * .36), mat("rubber"), seg=8, rot=(90, 0, 0), bevel=0))
    for y in (-1.1, 1.1):
        P.append(box((1.9, .15, .1), (0, y, .05), W))
    return finish("prop_pipe_stack", P)


def p_iv_stand():
    M = mat("gunmetal")
    P = [cyl(.025, 1.7, (0, 0, .9), M, seg=5)]
    for a in range(0, 360, 72):
        r = math.radians(a)
        P.append(rod((0, 0, .08), (math.cos(r) * .3, math.sin(r) * .3, .04), .015, M))
        P.append(cyl(.025, .03, (math.cos(r) * .3, math.sin(r) * .3, .025), mat("rubber"), seg=6, bevel=0))
    P += [rod((-.15, 0, 1.75), (.15, 0, 1.75), .012, M),
          box((.12, .04, .2), (.13, 0, 1.6), mat("glass_dark", emit=(.4, .1, .1)), bevel=.01),
          rod((.13, 0, 1.5), (.05, .1, 1.0), .005, M)]
    return finish("prop_iv_stand", P)


PROPS = [p_barrel, p_tire_stack, p_sandbags, p_car_wreck, p_truck, p_fuel_tank, p_dead_tree, p_desk, p_gurney,
         p_lamp_post, p_lockers, p_radio_tower, p_rubble, p_generator, p_radio_console, p_mystery_crate,
         p_med_station, p_weapon_forge, p_augment_furnace, p_skull, p_grenade,
         p_wood_crate, p_pallet, p_dumpster, p_jersey_barrier, p_traffic_cone, p_bench, p_gravestone,
         p_grave_cross, p_trash_bags, p_street_sign, p_pipe_stack, p_iv_stand]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_textures()
    IMGS.update(save_textures())
    random.seed(3)
    roots = []
    for fn in PROPS:
        r = fn()
        export(r)
        roots.append(r)
    x = 0.0
    for r in roots:
        r.location.x = x
        x += 4.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", "blender", "map_kit.blend"))
    print("KIT OK %d props %d textures" % (len(roots), len(TEX)))


main()
