# Dead Protocol - MAP KIT builder (Blender 5.x, run headless):
#   blender -b --factory-startup -P art/blender/build_map_kit.py
# Draws every map texture from scratch (tileable, small, posterized, dithered
# PSX style) and builds every map prop out of low-poly primitives, then saves
# art/blender/map_kit.blend and exports art/models/<prop>.glb.
# Conventions: Blender Z up, a prop's FRONT faces +Y (= Godot -Z). Origin on
# the floor at the prop's centre. Animated parts keep the names the game
# looks up: LidPivot (crate), Lever + StatusLight (generator).
import bpy, bmesh, math, os, random
import numpy as np
from mathutils import Vector, Matrix, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "art", "textures")
MODEL_DIR = os.path.join(ROOT, "art", "models")
os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(MODEL_DIR, exist_ok=True)
rng = np.random.default_rng(1997)

# ---------------------------------------------------------------- textures
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def noise(n, cells, seed):
    """Tileable value noise in 0..1, bilinear between a cells x cells grid."""
    g = np.random.default_rng(seed).random((cells, cells))
    t = np.arange(n) * cells / n
    i0 = t.astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    a = g[np.ix_(i0, i0)] * (1 - f)[None, :] + g[np.ix_(i0, i1)] * f[None, :]
    b = g[np.ix_(i1, i0)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(n, seed, base=4, octaves=4):
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += noise(n, base * 2 ** o, seed + o) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def ramp(v, cols):
    """Map 0..1 to a colour ramp given as list of (pos, (r,g,b))."""
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(v, [p for p, _ in cols], [col[c] for _, col in cols])
    return out


def psx(rgb, levels=24):
    """Ordered-dither then posterize to a 15-bit-ish palette."""
    n = rgb.shape[0]
    d = np.tile(BAYER, (n // 4, n // 4))[..., None]
    return np.clip(np.floor(rgb * levels + d + 0.5) / levels, 0, 1)


def save(name, rgb, levels=24):
    rgb = psx(rgb, levels)
    n = rgb.shape[0]
    img = bpy.data.images.new(name, n, n, alpha=False)
    px = np.ones((n, n, 4), dtype=np.float32)
    px[..., :3] = rgb[::-1]  # numpy row 0 = top of image
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    img.file_format = 'PNG'
    img.save()
    return img


def grid_lines(n, cols, rows, width, offset_rows=False):
    """1 inside mortar/seam lines, 0 elsewhere. Also returns per-cell id."""
    y, x = np.mgrid[0:n, 0:n]
    ch, cw = n / rows, n / cols
    r = (y // ch).astype(int)
    xo = x + (r % 2) * (cw / 2 if offset_rows else 0)
    c = (xo // cw).astype(int) % cols
    line = ((y % ch) < width) | ((xo % cw) < width)
    return line, r * 97 + c


def cell_rand(ids, seed):
    lut = np.random.default_rng(seed).random(ids.max() + 1)
    return lut[ids]


def make_textures():
    N = 128
    T = {}
    # concrete walls: grey, blotchy, a few cracks and drip stains
    v = fbm(N, 10) * 0.7 + fbm(N, 20, 16, 2) * 0.3
    drip = noise(N, 32, 30)[:1].repeat(N, 0) * np.linspace(0.3, 1.0, N)[:, None]
    v = v - (drip > 0.75) * 0.18
    T["concrete_albedo"] = ramp(v, [(0, (.23, .23, .22)), (.5, (.42, .41, .38)), (1, (.58, .56, .52))])
    # concrete floor: big slabs with seams
    line, ids = grid_lines(N, 2, 2, 2)
    v = fbm(N, 40) * 0.8 + cell_rand(ids, 41) * 0.2 - line * 0.35
    T["concrete_floor_albedo"] = ramp(v, [(0, (.16, .16, .15)), (.5, (.36, .35, .32)), (1, (.5, .48, .44))])
    # asphalt: dark, speckled, a faded paint stripe
    v = fbm(N, 50, 8) * 0.5 + rng.random((N, N)) * 0.5
    a = ramp(v, [(0, (.08, .08, .09)), (1, (.26, .25, .25))])
    stripe = (np.abs(np.arange(N) - N / 2) < 3)[None, :] & (fbm(N, 51) > 0.45)
    a[stripe] = a[stripe] * 0.4 + np.array([.55, .5, .25]) * 0.6
    T["asphalt_albedo"] = a
    # rusted metal: corrugated panel with rust bloom
    rust = fbm(N, 60, 4, 5)
    ribs = (np.sin(np.arange(N) / N * np.pi * 2 * 8) * 0.5 + 0.5)[None, :]
    base = ramp(ribs * 0.6 + fbm(N, 61) * 0.4, [(0, (.24, .26, .27)), (1, (.42, .44, .44))])
    rr = ramp(fbm(N, 62, 8), [(0, (.28, .12, .05)), (.6, (.52, .26, .1)), (1, (.66, .4, .18))])
    m = np.clip((rust - 0.45) * 5, 0, 1)[..., None]
    T["rusted_metal_albedo"] = base * (1 - m) + rr * m
    # wood planks (floors / boarding): 4 boards with grain and nails
    y, x = np.mgrid[0:N, 0:N]
    line, ids = grid_lines(N, 1, 4, 2)
    grain = np.sin(x / N * np.pi * 2 * 3 + fbm(N, 70, 4) * 9) * 0.5 + 0.5
    v = grain * 0.45 + cell_rand(ids, 71) * 0.35 + fbm(N, 72, 16, 2) * 0.2 - line * 0.6
    w = ramp(v, [(0, (.13, .08, .05)), (.5, (.33, .21, .12)), (1, (.48, .33, .2))])
    nails = ((x % 64) < 2) & ((y % 32 > 13) & (y % 32 < 16)) & ((x % 64) >= 0)
    w[nails] = (.15, .15, .16)
    T["wood_planks_albedo"] = w
    T["wood_board_albedo"] = ramp(grain * 0.6 + fbm(N, 73) * 0.4, [(0, (.2, .13, .07)), (1, (.52, .37, .22))])
    # burlap sandbag cloth: woven checker + dirt
    weave = (((x // 2) + (y // 2)) % 2) * 0.25
    T["burlap_albedo"] = ramp(weave + fbm(N, 80) * 0.75, [(0, (.3, .25, .16)), (1, (.6, .5, .33))])
    # gunmetal: dark brushed steel, worn edges are lighter streaks
    brush = noise(N, 64, 90)[:1].repeat(N, 0) * 0.5 + fbm(N, 91) * 0.5
    T["gunmetal_albedo"] = ramp(brush, [(0, (.1, .11, .12)), (1, (.3, .31, .33))])
    # ---- prop textures
    T["paint_rust_red_albedo"] = ramp(fbm(N, 100), [(0, (.3, .08, .06)), (.6, (.5, .12, .08)), (1, (.55, .3, .15))])
    T["paint_olive_albedo"] = ramp(fbm(N, 110), [(0, (.18, .2, .1)), (.6, (.3, .33, .17)), (1, (.4, .36, .2))])
    T["paint_hospital_albedo"] = ramp(fbm(N, 115), [(0, (.45, .5, .48)), (1, (.72, .76, .72))])
    bark = np.sin(x / N * np.pi * 2 * 10 + fbm(N, 120, 4) * 6) * 0.5 + 0.5
    T["bark_albedo"] = ramp(bark * 0.6 + fbm(N, 121) * 0.4, [(0, (.07, .06, .05)), (1, (.27, .23, .19))])
    T["rubber_albedo"] = ramp(fbm(N, 130, 16, 2), [(0, (.05, .05, .05)), (1, (.15, .15, .14))])
    T["bone_albedo"] = ramp(fbm(N, 140), [(0, (.45, .4, .3)), (1, (.82, .77, .64))])
    T["rock_albedo"] = ramp(fbm(N, 150, 8), [(0, (.2, .19, .18)), (1, (.5, .48, .45))])
    hz = (((x + y) // 16) % 2).astype(float)
    T["hazard_albedo"] = ramp(hz * 0.8 + fbm(N, 160) * 0.2, [(0, (.08, .08, .07)), (.6, (.6, .5, .1)), (1, (.75, .62, .15))])
    line, ids = grid_lines(N, 2, 2, 3)
    T["panel_albedo"] = ramp(fbm(N, 170) * 0.7 + cell_rand(ids, 171) * 0.3 - line * 0.4,
                             [(0, (.12, .14, .13)), (1, (.36, .4, .36))])
    T["glass_dark_albedo"] = ramp(fbm(N, 180) * 0.4 + (np.abs(x - y) < 10) * 0.4, [(0, (.04, .06, .07)), (1, (.22, .28, .3))])
    T["mattress_albedo"] = ramp(fbm(N, 190) + (fbm(N, 191, 4) > 0.62) * 0.6,
                                [(0, (.55, .55, .5)), (.7, (.7, .7, .65)), (1, (.42, .1, .08))])
    # world-shader macro variation map (greyscale)
    m = fbm(256, 200, 2, 5)
    T["macro_noise"] = np.repeat(m[..., None], 3, 2)
    imgs = {}
    for k, v in T.items():
        imgs[k] = save(k, v, 32 if k == "macro_noise" else 24)
    return imgs


# ---------------------------------------------------------------- materials
IMGS = {}
MATS = {}


def mat(name, emit=None, metal=0.0, rough=0.9):
    key = (name, emit)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(("M_" + name) + ("_glow" if emit else ""))
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    img = IMGS.get(name + "_albedo")
    if img:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        tn.interpolation = 'Closest'  # nearest sampler in glTF = crunchy PSX texels
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
        if not img:
            bsdf.inputs["Base Color"].default_value = (*emit, 1)
    MATS[key] = m
    return m


# ---------------------------------------------------------------- geometry
TEXEL = 1.0  # metres per texture repeat on props


def _new_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob


def box(size, loc, m, rot=(0, 0, 0), name="part"):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = _new_obj(name, bm, m)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    return ob


def cyl(r, h, loc, m, seg=8, rot=(0, 0, 0), r2=None, name="part"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    ob = _new_obj(name, bm, m)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    return ob


def ball(r, loc, m, seg=8, rings=6, scale=(1, 1, 1), name="part"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    ob = _new_obj(name, bm, m)
    ob.location = loc
    return ob


def rod(a, b, r, m, seg=4):
    """Cylinder from point a to b (for braces, branches, rebar)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    ob = cyl(r, d.length, (a + b) / 2, m, seg)
    ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return ob


def box_uv(ob):
    """World-scale box projection so texel density matches across a prop."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    mw = ob.matrix_world
    for f in bm.faces:
        n = (mw.to_3x3() @ f.normal)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = mw @ l.vert.co
            u, v = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            l[uv].uv = (u / TEXEL, v / TEXEL)
    bm.to_mesh(me)
    bm.free()


def finish(root_name, parts, children=()):
    """UV + join loose parts into one mesh named <root>, parent animated parts."""
    for p in list(parts) + [c for c in children if c.type == 'MESH']:
        bpy.context.view_layer.update()
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
    bpy.ops.export_scene.gltf(filepath=os.path.join(MODEL_DIR, root.name + ".glb"),
                              export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='AUTO')


# ---------------------------------------------------------------- props
def wheel(x, y, r, w, m):
    return cyl(r, w, (x, y, r), m, seg=8, rot=(0, 90, 0))


def p_barrel():
    M, R = mat("rusted_metal", metal=.6, rough=.7), mat("paint_rust_red")
    P = [cyl(.31, .94, (0, 0, .47), R, seg=10)]
    for z in (.2, .74):
        P.append(cyl(.325, .05, (0, 0, z), M, seg=10))
    P.append(cyl(.06, .03, (.15, .1, .95), M, seg=6))
    return finish("prop_barrel", P)


def p_tire_stack():
    T = mat("rubber")
    P = [cyl(.45 - (i % 2) * .02, .21, (random.uniform(-.03, .03), random.uniform(-.03, .03), .11 + i * .22), T, seg=10)
         for i in range(4)]
    P.append(cyl(.2, .02, (0, 0, .89), mat("rock"), seg=8))
    return finish("prop_tire_stack", P)


def p_sandbags():
    B = mat("burlap")
    P = []
    for row in range(2):
        n = 3 if row == 0 else 2
        for i in range(n):
            x = (i - (n - 1) / 2) * .55
            b = box((.54, .36, .22), (x, 0, .14 + row * .24), B, rot=(0, 0, random.uniform(-6, 6)))
            P.append(b)
            P.append(box((.48, .3, .06), (x, 0, .27 + row * .24), B))  # rounded top
    return finish("prop_sandbags", P)


def p_car_wreck():
    R, G, T, M = mat("paint_rust_red"), mat("glass_dark"), mat("rubber"), mat("rusted_metal")
    P = [box((1.86, 4.3, .55), (0, 0, .55), R),
         box((1.6, 2.0, .5), (0, -.25, 1.07), R),
         box((1.5, .1, .4), (0, .78, 1.08), G, rot=(-25, 0, 0)),
         box((1.62, 1.6, .38), (0, -.2, 1.06), G),
         box((1.9, .2, .25), (0, 2.15, .42), M), box((1.9, .2, .25), (0, -2.15, .42), M)]
    for x in (-.85, .85):
        for y in (-1.35, 1.4):
            P.append(wheel(x, y, .33, .24, T))
    P[1].rotation_euler.x = math.radians(3)
    return finish("prop_car_wreck", P)


def p_truck():
    O, G, T, M, C = mat("paint_olive"), mat("glass_dark"), mat("rubber"), mat("gunmetal", metal=.5), mat("burlap")
    P = [box((2.4, 7.0, .4), (0, 0, .8), M),
         box((2.4, 2.0, 1.9), (0, 2.5, 1.95), O),
         box((2.2, .1, .8), (0, 3.5, 2.35), G),
         box((2.45, 4.6, .6), (0, -1.1, 1.3), O),
         box((2.4, 4.5, 1.9), (0, -1.1, 2.55), C),  # canvas tarp
         box((2.45, .15, .4), (0, 3.55, 1.0), M)]
    for i in range(3):
        P.append(box((2.45, .1, 2.0), (0, -3.2 + i * 2.1, 2.6), M))
    for x in (-1.05, 1.05):
        for y in (2.5, -1.0, -2.4):
            P.append(wheel(x, y, .55, .42, T))
    return finish("prop_truck", P)


def p_fuel_tank():
    M, H = mat("rusted_metal", metal=.6), mat("hazard")
    P = [cyl(.95, 3.4, (0, 0, 1.2), M, seg=10, rot=(90, 0, 0))]
    for y in (-1.71, 1.71):
        P.append(cyl(.8, .04, (0, y, 1.2), M, seg=10, rot=(90, 0, 0)))
    for y in (-1.1, 1.1):
        P.append(box((1.8, .3, .4), (0, y, .2), H))
    P.append(cyl(.2, .3, (0, .5, 2.2), M, seg=6))
    P.append(rod((.95, 1.6, 1.2), (.95, 1.6, .1), .04, M))
    return finish("prop_fuel_tank", P)


def p_dead_tree():
    B = mat("bark")
    P = [cyl(.32, 3.2, (0, 0, 1.5), B, seg=6, r2=.2)]
    random.seed(7)

    def branch(a, d, length, r, depth):
        b = a + d.normalized() * length
        P.append(rod(a, b, r, B, seg=4))
        if depth:
            for _ in range(2):
                nd = d.normalized() + Vector((random.uniform(-.8, .8), random.uniform(-.8, .8), random.uniform(0, .7)))
                branch(b, nd, length * .65, r * .6, depth - 1)
    for ang, z in ((0, 3.0), (2.1, 2.6), (4.2, 3.1)):
        branch(Vector((0, 0, z)), Vector((math.cos(ang), math.sin(ang), 1.1)), 1.7, .13, 2)
    for ang in range(0, 360, 72):  # roots
        a = math.radians(ang)
        P.append(rod((0, 0, .3), (math.cos(a) * .8, math.sin(a) * .8, -.1), .12, B))
    return finish("prop_dead_tree", P)


def p_desk():
    W, M, G, P_ = mat("wood_board"), mat("gunmetal"), mat("glass_dark"), mat("panel")
    P = [box((1.6, .8, .06), (0, -.4, .76), W)]
    for x in (-.75, .75):
        P.append(box((.06, .75, .73), (x, -.4, .37), M))
    P.append(box((.5, .7, .55), (.5, -.4, .46), P_))
    P.append(box((.55, .4, .42), (0, -.6, 1.02), P_))  # CRT monitor
    P.append(box((.44, .02, .34), (0, -.39, 1.04), mat("glass_dark", emit=(.2, .45, .3))))
    P.append(box((.6, .62, .05), (-.2, .25, .45), W))  # chair seat
    P.append(box((.6, .05, .6), (-.2, .55, .75), W))
    return finish("prop_desk", P)


def p_gurney():
    M, S = mat("gunmetal", metal=.6), mat("mattress")
    P = [box((.7, 1.95, .12), (0, 0, .86), S), box((.72, 1.98, .04), (0, 0, .78), M)]
    for x in (-.32, .32):
        for y in (-.9, .9):
            P.append(box((.04, .04, .7), (x, y, .43), M))
            P.append(cyl(.06, .04, (x, y, .06), mat("rubber"), seg=6, rot=(0, 90, 0)))
    P.append(box((.72, .04, .35), (0, .97, 1.0), M))
    return finish("prop_gurney", P)


def p_lamp_post():
    M = mat("gunmetal", metal=.5)
    P = [cyl(.2, .3, (0, 0, .15), M, seg=6), cyl(.09, 4.4, (0, 0, 2.35), M, seg=6, r2=.06),
         rod((0, 0, 4.4), (0, .9, 4.55), .05, M), box((.32, .5, .14), (0, 1.0, 4.5), M),
         box((.24, .4, .03), (0, 1.0, 4.42), mat("glass_dark", emit=(1.0, .8, .45)))]
    return finish("prop_lamp_post", P)


def p_lockers():
    M, D = mat("panel"), mat("gunmetal")
    P = [box((2.2, .75, 1.96), (0, 0, .98), M)]
    for i in range(4):
        x = -.825 + i * .55
        door = box((.5, .04, 1.84), (x, .38, .98), M, rot=(0, 0, 40 if i == 2 else 0))
        P.append(door)
        for k in range(3):
            P.append(box((.3, .02, .03), (x, .41, 1.6 + k * .07), D))
        P.append(box((.03, .03, .12), (x + .18, .41, 1.0), D))
    return finish("prop_lockers", P)


def p_radio_tower():
    M, H = mat("rusted_metal", metal=.6), mat("hazard")
    P = []
    H_ = 22.0
    w = lambda z: 1.5 * (1 - z / H_) + .25
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for cx, cy in corners:
        P.append(rod((cx * w(0), cy * w(0), 0), (cx * w(H_), cy * w(H_), H_), .07, M))
    z = 0.0
    step = 2.2
    while z < H_ - .1:
        z2 = min(z + step, H_)
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            P.append(rod((a[0] * w(z), a[1] * w(z), z), (b[0] * w(z2), b[1] * w(z2), z2), .035, M))
            P.append(rod((a[0] * w(z2), a[1] * w(z2), z2), (b[0] * w(z2), b[1] * w(z2), z2), .035, M))
        z = z2
    P.append(box((3.0, 3.0, .3), (0, 0, .15), H))
    P.append(ball(.18, (0, 0, H_ + .25), mat("glass_dark", emit=(1, .1, .05)), seg=6, rings=4))
    P.append(cyl(.04, 2.0, (0, 0, H_ + 1.2), M, seg=4))
    return finish("prop_radio_tower", P)


def p_rubble():
    C, R = mat("concrete"), mat("rusted_metal")
    random.seed(11)
    P = []
    for i in range(9):
        s = random.uniform(.35, .9)
        P.append(box((s, s * random.uniform(.6, 1.2), s * .55),
                     (random.uniform(-.8, .8), random.uniform(-.7, .7), s * .2 + (i > 5) * .4),
                     C, rot=(random.uniform(-25, 25), random.uniform(-25, 25), random.uniform(0, 90))))
    for i in range(4):
        a = Vector((random.uniform(-.6, .6), random.uniform(-.6, .6), .2))
        P.append(rod(a, a + Vector((random.uniform(-.6, .6), random.uniform(-.6, .6), random.uniform(.5, 1.0))), .02, R))
    return finish("prop_rubble", P)


def p_generator():
    O, M, H = mat("paint_olive"), mat("gunmetal", metal=.5), mat("hazard")
    P = [box((2.5, 1.2, 1.8), (0, 0, 1.1), O), box((2.6, 1.26, .2), (0, 0, .1), H),
         cyl(.45, 2.2, (-.2, -.2, 2.25), M, seg=8, rot=(0, 90, 0)),
         cyl(.1, .8, (1.0, -.35, 2.5), M, seg=6), box((.9, .05, .7), (-.5, .61, 1.3), mat("panel"))]
    for i in range(6):
        P.append(box((.05, .03, 1.2), (.4 + i * .14, .61, 1.1), M))
    # Lever: pivot on the front panel, handle points up; game tweens rotation:x
    lever = bpy.data.objects.new("Lever", None)
    bpy.context.scene.collection.objects.link(lever)
    lever.location = (-.6, .66, 1.2)
    stick = box((.05, .05, .45), (0, 0, .22), M, name="LeverStick")
    knob = ball(.06, (0, 0, .46), mat("paint_rust_red"), seg=6, rings=4, name="LeverKnob")
    for o in (stick, knob):
        o.parent = lever
    status = box((.14, .05, .14), (.45, .63, 1.4), mat("glass_dark", emit=(1, .15, .1)), name="StatusLight")
    return finish("prop_generator", P, [lever, stick, knob, status])


def p_radio_console():
    P_, M, G = mat("panel"), mat("gunmetal"), mat("glass_dark", emit=(.3, .9, .4))
    P = [box((1.5, .72, 1.1), (0, 0, .55), P_), box((1.4, .5, .9), (0, -.1, 1.55), P_),
         box((.7, .03, .45), (-.25, .16, 1.65), G), box((1.5, .4, .06), (0, .2, 1.12), M)]
    for i in range(5):
        P.append(cyl(.04, .04, (.2 + i * .1, .16, 1.4), mat("paint_rust_red"), seg=6, rot=(90, 0, 0)))
    P.append(cyl(.03, 1.2, (.55, -.2, 2.6), M, seg=4))
    P.append(ball(.05, (.55, -.2, 3.15), mat("glass_dark", emit=(1, .2, .1)), seg=6, rings=4))
    return finish("prop_radio_console", P)


def p_mystery_crate():
    W, M = mat("wood_board"), mat("gunmetal")
    P = [box((1.6, .74, .55), (0, 0, .28), W)]
    for x in (-.75, .75):
        P.append(box((.08, .76, .58), (x, 0, .29), M))
    P.append(box((1.3, .02, .2), (0, .38, .3), mat("hazard")))
    piv = bpy.data.objects.new("LidPivot", None)  # hinge on the back top edge
    bpy.context.scene.collection.objects.link(piv)
    piv.location = (0, -.37, .56)
    lid = box((1.62, .76, .16), (0, .37, .08), W, name="Lid")
    lid.parent = piv
    glow = box((1.4, .6, .02), (0, 0, .54), mat("glass_dark", emit=(.4, .8, 1.0)), name="Glow")
    return finish("prop_mystery_crate", P, [piv, lid, glow])


def p_med_station():
    H, G, R = mat("paint_hospital"), mat("glass_dark"), mat("paint_rust_red", emit=(1, .15, .15))
    P = [box((1.4, .5, 2.15), (0, 0, 1.08), H), box((1.1, .03, 1.0), (0, .26, 1.4), G),
         box((.4, .03, .12), (0, .27, 1.98), R), box((.12, .03, .4), (0, .27, 1.98), R),
         box((1.2, .3, .04), (0, .1, 1.0), H)]
    for i in range(4):
        P.append(cyl(.06, .22, (-.4 + i * .27, .1, 1.13), mat("glass_dark", emit=(.2, 1, .4)), seg=6))
    return finish("prop_med_station", P)


def p_weapon_forge():
    M, H, W = mat("gunmetal", metal=.6), mat("hazard"), mat("wood_board")
    P = [box((1.8, 1.0, .9), (0, 0, .45), M), box((1.8, 1.1, .08), (0, 0, .94), W),
         box((1.6, .7, 1.3), (0, -.2, 2.35), M), box((1.7, .9, .12), (0, -.05, 1.66), H),
         box((.5, .25, .3), (.3, .1, 1.13), mat("rock")),
         box((.6, .03, .4), (-.4, .51, .5), mat("glass_dark", emit=(1, .5, .1))),
         cyl(.12, .6, (.6, -.3, 2.8), M, seg=6)]
    return finish("prop_weapon_forge", P)


def p_augment_furnace():
    C, M = mat("concrete"), mat("rusted_metal", metal=.5)
    P = [box((1.6, 1.0, 2.0), (0, 0, 1.0), C), box((1.0, .5, 1.0), (0, 0, 2.5), C),
         cyl(.15, .9, (0, 0, 2.6), M, seg=6),
         box((.8, .05, .7), (0, .51, .9), mat("glass_dark", emit=(1, .35, .05))),
         box((1.7, 1.05, .15), (0, 0, .08), M), box((1.7, 1.05, .1), (0, 0, 2.0), M)]
    return finish("prop_augment_furnace", P)


def p_skull():
    B, D = mat("bone"), mat("rubber")
    P = [ball(.1, (0, 0, .14), B, seg=8, rings=6, scale=(1, 1.2, 1)),
         box((.12, .1, .06), (0, .07, .05), B)]
    for x in (-.04, .04):
        P.append(box((.035, .02, .035), (x, .115, .13), D))
    return finish("prop_skull", P)


def p_grenade():
    O, M = mat("paint_olive"), mat("gunmetal", metal=.6)
    P = [ball(.035, (0, 0, 0), O, seg=8, rings=6, scale=(1, 1, 1.25)),
         cyl(.015, .03, (0, 0, .05), M, seg=6), box((.01, .015, .07), (.02, 0, .03), M)]
    return finish("prop_grenade", P)


PROPS = [p_barrel, p_tire_stack, p_sandbags, p_car_wreck, p_truck, p_fuel_tank, p_dead_tree, p_desk,
         p_gurney, p_lamp_post, p_lockers, p_radio_tower, p_rubble, p_generator, p_radio_console,
         p_mystery_crate, p_med_station, p_weapon_forge, p_augment_furnace, p_skull, p_grenade]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    IMGS.update(make_textures())
    random.seed(3)
    roots = []
    for i, fn in enumerate(PROPS):
        r = fn()
        roots.append(r)
        export(r)
    # lay the kit out in a row in the .blend so it can be browsed / edited
    x = 0.0
    for r in roots:
        r.location.x = x
        x += 4.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", "blender", "map_kit.blend"))
    print("KIT OK", len(roots), "props")


main()
