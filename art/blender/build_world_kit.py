# Dead Protocol - WORLD KIT builder (Blender 5.x, run headless AFTER the map kit):
#   blender -b --factory-startup -P art/blender/build_world_kit.py
# Modular building pieces on a 4 m grid, open-world props and the drivable
# vehicles. Reuses the map kit's geometry helpers and its textures (loaded
# from art/textures, so run build_map_kit.py first).
#
# Building pieces (Blender local space; front/outside faces +Y = Godot -Z):
#   wall_<style>          4 m wide, 4.2 m tall, 0.3 m thick, spans x -2..2
#   wall_<style>_window   floor-level 2.0 x 2.4 opening (game barricade slot)
#   wall_<style>_door     3.0 x 3.2 opening (buyable door / doorway)
#   wall_<style>_glass    solid wall with a glazed window (facades)
#   corner_<style>        0.5 m post to close corners
#   floor_<mat>           4 x 4 slab, top at z = 0.05
#   roof_flat             4 x 4 slab + parapet_<style> 4 m edge
#   roof_gable_<w>        one 4 m length of a gable roof over a w-wide house
#   gable_<style>_<w>     the triangular wall end above the 4.2 m eaves
# Every piece carries "-colonly" box meshes: Godot turns those into static
# colliders on import, so the game never has to guess collision.
import bpy, math, os, sys
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import build_map_kit as K  # noqa: E402

H, T, W = 4.2, 0.3, 4.0
STYLES = {"brick": "brick", "plaster": "plaster", "siding_white": "siding_white", "siding_red": "siding_red",
          "siding_blue": "siding_blue", "metal": "rusted_metal", "concrete": "concrete"}


def load_textures():
    for f in os.listdir(K.TEX_DIR):
        if f.endswith("_albedo.png"):
            img = bpy.data.images.load(os.path.join(K.TEX_DIR, f))
            K.IMGS[f[:-len("_albedo.png")]] = img


def col(size, loc, rot=(0, 0, 0)):
    """Invisible collision box (Godot import: -colonly -> StaticBody3D)."""
    ob = K.box(size, loc, K.mat("concrete"), rot=rot, name="col-colonly", bevel=0)
    return ob


def piece(name, parts, cols):
    root = K.finish(name, parts, cols)
    for c in cols:
        c.name = name + "_col-colonly"
    return root


def trims(m, trim):
    """Base skirt + top band shared by all wall pieces."""
    return [K.box((W, T + .06, .25), (0, 0, .125), trim, bevel=.02),
            K.box((W, T + .08, .18), (0, 0, H - .09), trim, bevel=.02)]


def wall(style):
    m = K.mat(STYLES[style])
    trim = K.mat("concrete")
    P = [K.box((W, T, H), (0, 0, H / 2), m, bevel=0)] + trims(m, trim)
    return piece("wall_" + style, P, [col((W, T, H), (0, 0, H / 2))])


def wall_opening(style, ow, oh, kind):
    m = K.mat(STYLES[style])
    trim = K.mat("concrete")
    frame = K.mat("wood_board") if style.startswith("siding") else K.mat("gunmetal")
    side = (W - ow) / 2
    P = [K.box((side, T, H), (-(ow + side) / 2, 0, H / 2), m, bevel=0),
         K.box((side, T, H), ((ow + side) / 2, 0, H / 2), m, bevel=0),
         K.box((ow, T, H - oh), (0, 0, oh + (H - oh) / 2), m, bevel=0)]
    P += [K.box((side, T + .06, .25), (-(ow + side) / 2, 0, .125), trim, bevel=.02),
          K.box((side, T + .06, .25), ((ow + side) / 2, 0, .125), trim, bevel=.02),
          K.box((W, T + .08, .18), (0, 0, H - .09), trim, bevel=.02)]
    # frame: jambs + lintel, proud of both faces
    P += [K.box((.12, T + .1, oh), (-ow / 2 - .06, 0, oh / 2), frame, bevel=.015),
          K.box((.12, T + .1, oh), (ow / 2 + .06, 0, oh / 2), frame, bevel=.015),
          K.box((ow + .36, T + .14, .16), (0, 0, oh + .08), frame, bevel=.015)]
    if kind == "door":
        P.append(K.box((ow, T + .1, .05), (0, 0, .025), frame, bevel=0))  # threshold
    cols = [col((side, T, H), (-(ow + side) / 2, 0, H / 2)), col((side, T, H), ((ow + side) / 2, 0, H / 2)),
            col((ow, T, H - oh), (0, 0, oh + (H - oh) / 2))]
    return piece("wall_%s_%s" % (style, kind), P, cols)


def wall_glass(style):
    m = K.mat(STYLES[style])
    trim = K.mat("concrete")
    frame = K.mat("wood_board") if style.startswith("siding") else K.mat("concrete")
    gw, gh, gz = 1.6, 1.4, 1.1
    side = (W - gw) / 2
    P = [K.box((side, T, H), (-(gw + side) / 2, 0, H / 2), m, bevel=0),
         K.box((side, T, H), ((gw + side) / 2, 0, H / 2), m, bevel=0),
         K.box((gw, T, gz), (0, 0, gz / 2), m, bevel=0),
         K.box((gw, T, H - gz - gh), (0, 0, gz + gh + (H - gz - gh) / 2), m, bevel=0),
         K.box((gw, T * .3, gh), (0, 0, gz + gh / 2), K.mat("window"), bevel=0),
         K.box((gw + .3, T + .2, .1), (0, 0, gz - .05), frame, bevel=.02),           # sill
         K.box((gw + .3, T + .14, .14), (0, 0, gz + gh + .07), frame, bevel=.02)]
    if style.startswith("siding") or style == "plaster":  # shutters
        sh = K.mat("siding_blue" if style != "siding_blue" else "siding_white")
        P += [K.box((.5, .05, gh), (-gw / 2 - .32, T / 2 + .04, gz + gh / 2), sh, rot=(0, 0, 0), bevel=.01),
              K.box((.5, .05, gh), (gw / 2 + .32, T / 2 + .04, gz + gh / 2), sh, rot=(0, 0, 0), bevel=.01)]
    P += trims(m, trim)
    return piece("wall_%s_glass" % style, P, [col((W, T, H), (0, 0, H / 2))])


def corner(style):
    m = K.mat(STYLES[style])
    return piece("corner_" + style, [K.box((.5, .5, H + .1), (0, 0, (H + .1) / 2), m, bevel=.03)],
                 [col((.5, .5, H + .1), (0, 0, (H + .1) / 2))])


def floor_piece(name, texname):
    return piece("floor_" + name, [K.box((W, W, .1), (0, 0, 0), K.mat(texname), bevel=0)],
                 [col((W, W, .1), (0, 0, 0))])


def roof_flat():
    m = K.mat("concrete")
    P = [K.box((W, W, .3), (0, 0, H + .15), m, bevel=0),
         K.box((W, W, .02), (0, 0, H + .31), K.mat("tin_roof"), bevel=0)]
    return piece("roof_flat", P, [col((W, W, .3), (0, 0, H + .15))])


def parapet(style):
    m = K.mat(STYLES[style])
    P = [K.box((W, T, .7), (0, 0, H + .35), m, bevel=0), K.box((W, T + .1, .08), (0, 0, H + .74), K.mat("concrete"))]
    return piece("parapet_" + style, P, [col((W, T, .7), (0, 0, H + .35))])


def roof_gable(width, texname="shingles"):
    """4 m long (along X) slice of a roof spanning `width` (along Y)."""
    m = K.mat(texname)
    pitch = math.radians(32)
    half = width / 2 + .4
    slope = half / math.cos(pitch)
    rise = math.tan(pitch) * (width / 2)
    P, C = [], []
    for s in (-1, 1):
        y = s * half / 2
        z = H + rise / 2 - .05
        rot = (s * -math.degrees(pitch), 0, 0)
        P.append(K.box((W, slope, .14), (0, y, z), m, rot=rot, bevel=0))
        C.append(col((W, slope, .14), (0, y, z), rot))
    P.append(K.box((W, .25, .25), (0, 0, H + rise + .02), m, rot=(45, 0, 0), bevel=0))  # ridge cap
    P.append(K.box((W, .1, .3), (0, half - .02, H - .3), K.mat("wood_board")))          # fascia
    P.append(K.box((W, .1, .3), (0, -half + .02, H - .3), K.mat("wood_board")))
    return piece("roof_gable_%d" % width, P, C)


def gable_end(style, width):
    """Triangle wall filling the gable above the eaves (local x = across)."""
    m = K.mat(STYLES[style])
    rise = math.tan(math.radians(32)) * (width / 2)
    bm = K.bmesh.new()
    v = [bm.verts.new(p) for p in ((-width / 2, -T / 2, 0), (width / 2, -T / 2, 0), (0, -T / 2, rise),
                                   (-width / 2, T / 2, 0), (width / 2, T / 2, 0), (0, T / 2, rise))]
    for f in ((0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)):
        bm.faces.new([v[i] for i in f])
    K.bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tri = K._obj("part", bm, m)
    tri.location = (0, 0, H)
    P = [tri, K.box((.6, .05, .6), (0, T / 2 + .03, H + rise * .45), K.mat("window"), bevel=0)]
    # rough collider: two boxes
    C = [col((width * .7, T, rise * .5), (0, 0, H + rise * .25)), col((width * .3, T, rise * .5), (0, 0, H + rise * .7))]
    return piece("gable_%s_%d" % (style, width), P, C)


# ------------------------------------------------------------- world props
def p_gas_pump():
    R, M, G = K.mat("paint_rust_red"), K.mat("gunmetal"), K.mat("glass_dark", emit=(.9, .7, .3))
    P = [K.box((.9, .6, .2), (0, 0, .1), K.mat("concrete")), K.box((.7, .45, 1.6), (0, 0, 1.0), R, bevel=.03),
         K.box((.5, .03, .3), (0, .24, 1.4), G, bevel=0), K.box((.74, .5, .12), (0, 0, 1.86), K.mat("sign")),
         K.box((.12, .1, .3), (.42, 0, 1.0), M), K.rod((.42, 0, .85), (.45, .35, .2), .02, K.mat("rubber"))]
    return piece("prop_gas_pump", P, [col((.8, .55, 1.9), (0, 0, .95))])


def p_gas_canopy():
    M, W_ = K.mat("paint_hospital"), K.mat("gunmetal")
    P = [K.box((12, 8, .7), (0, 0, 5.2), M, bevel=.05), K.box((12.1, 8.1, .25), (0, 0, 4.85), K.mat("paint_rust_red"))]
    for x in (-4.5, 4.5):
        P.append(K.box((.45, .45, 4.8), (x, 0, 2.4), W_))
    for x in (-3, 0, 3):
        P.append(K.box((1.6, .8, .03), (x, 0, 4.7), K.mat("glass_dark", emit=(.9, .9, .8)), bevel=0))
    C = [col((.5, .5, 4.8), (-4.5, 0, 2.4)), col((.5, .5, 4.8), (4.5, 0, 2.4)), col((12, 8, .9), (0, 0, 5.1))]
    return piece("prop_gas_canopy", P, C)


def p_silo():
    M, R = K.mat("rusted_metal", metal=.5), K.mat("paint_rust_red")
    P = [K.cyl(3, 14, (0, 0, 7), M, seg=14), K.cyl(3.1, 2.2, (0, 0, 15.1), M, seg=14, r2=.6),
         K.box((7, 7, .4), (0, 0, .2), K.mat("concrete"))]
    for z in (3, 6, 9, 12):
        P.append(K.cyl(3.05, .12, (0, 0, z), R, seg=14, bevel=0))
    for z in range(1, 15):
        P.append(K.rod((3.15, -.25, z), (3.15, .25, z), .025, K.mat("gunmetal")))
    P += [K.rod((3.15, -.25, .4), (3.15, -.25, 15), .03, K.mat("gunmetal")),
          K.rod((3.15, .25, .4), (3.15, .25, 15), .03, K.mat("gunmetal"))]
    return piece("prop_silo", P, [col((6, 6, 16), (0, 0, 8))])


def p_water_tower():
    M, R = K.mat("rusted_metal", metal=.5), K.mat("gunmetal")
    P = [K.cyl(3.2, 4.5, (0, 0, 14), M, seg=12), K.cyl(3.3, 1.5, (0, 0, 17), M, seg=12, r2=.3),
         K.cyl(3.6, .2, (0, 0, 11.7), R, seg=12)]
    for a in range(4):
        r = math.radians(45 + a * 90)
        p = (math.cos(r) * 2.8, math.sin(r) * 2.8)
        P.append(K.rod((p[0] * 1.2, p[1] * 1.2, 0), (p[0], p[1], 11.8), .14, R, seg=6))
        P.append(K.box((.6, .6, .3), (p[0] * 1.2, p[1] * 1.2, .15), K.mat("concrete")))
    for z in (4, 8):
        for a in range(4):
            r0, r1 = math.radians(45 + a * 90), math.radians(135 + a * 90)
            k = 1.2 - z / 11.8 * .2
            P.append(K.rod((math.cos(r0) * 2.8 * k, math.sin(r0) * 2.8 * k, z),
                           (math.cos(r1) * 2.8 * k, math.sin(r1) * 2.8 * k, z), .05, R))
    C = [col((.5, .5, 12), (x, y, 6)) for x, y in ((2.4, 2.4), (-2.4, 2.4), (2.4, -2.4), (-2.4, -2.4))]
    return piece("prop_water_tower", P, C)


def p_hay_bale():
    Hh = K.mat("hay")
    P = [K.cyl(.75, 1.4, (0, 0, .75), Hh, seg=10, rot=(0, 90, 0)),
         K.cyl(.6, 1.42, (0, 0, .75), K.mat("bark"), seg=8, rot=(0, 90, 0), bevel=0)]
    P[1].data.materials[0] = K.mat("hay")
    return piece("prop_hay_bale", P, [col((1.4, 1.4, 1.4), (0, 0, .7))])


def p_hay_stack():
    Hh = K.mat("hay")
    P = []
    for i, (x, y, z) in enumerate(((-.6, 0, .35), (.6, 0, .35), (0, 0, 1.05), (-.6, 1.1, .35))):
        P.append(K.box((1.15, .9, .7), (x, y, z), Hh, rot=(0, 0, (i * 7) % 11 - 5), bevel=.06))
    return piece("prop_hay_stack", P, [col((2.4, 2.1, 1.4), (0, .5, .7))])


def p_power_pylon():
    M = K.mat("gunmetal", metal=.5)
    P = []
    top = 18.0
    w = lambda z: 2.2 * (1 - z / top) + .5
    cs = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for cx, cy in cs:
        P.append(K.rod((cx * w(0), cy * w(0), 0), (cx * w(top), cy * w(top), top), .08, M))
    z = 0.0
    while z < top - .1:
        z2 = min(z + 3, top)
        for i in range(4):
            a, b = cs[i], cs[(i + 1) % 4]
            P.append(K.rod((a[0] * w(z), a[1] * w(z), z), (b[0] * w(z2), b[1] * w(z2), z2), .04, M))
        z = z2
    for z, span in ((top - 1, 5.0), (top - 4, 4.0)):
        P.append(K.box((span * 2, .3, .3), (0, 0, z), M))
        for s in (-1, 1):
            P.append(K.cyl(.12, .6, (s * span * .9, 0, z - .45), K.mat("glass_dark"), seg=6))
    return piece("prop_power_pylon", P, [col((2.6, 2.6, 6), (0, 0, 3))])


def p_utility_pole():
    B, M = K.mat("bark"), K.mat("gunmetal")
    P = [K.cyl(.14, 9, (0, 0, 4.5), K.mat("wood_board"), seg=6, r2=.11), K.box((2.2, .12, .12), (0, 0, 8.3), K.mat("wood_board")),
         K.cyl(.3, .8, (0, .3, 7.2), M, seg=8)]
    for x in (-.9, 0, .9):
        P.append(K.cyl(.05, .18, (x, 0, 8.45), K.mat("glass_dark"), seg=5))
    return piece("prop_utility_pole", P, [col((.3, .3, 9), (0, 0, 4.5))])


def p_fence_wood():
    Wd = K.mat("wood_board")
    P = []
    for x in (-2, 0, 2):
        P.append(K.box((.14, .14, 1.3), (x, 0, .65), Wd))
    for z in (.4, .95):
        P.append(K.box((4.1, .06, .16), (0, .08, z), Wd, rot=(0, (z * 7) % 3 - 1.5, 0), bevel=.01))
    return piece("prop_fence_wood", P, [col((4.1, .2, 1.3), (0, 0, .65))])


def p_fence_metal():
    M = K.mat("gunmetal")
    P = [K.box((4.0, .04, 2.0), (0, 0, 1.1), K.mat("rusted_metal"), bevel=0)]
    for x in (-2, 2):
        P.append(K.cyl(.05, 2.3, (x, 0, 1.15), M, seg=6))
    P.append(K.rod((-2, 0, 2.15), (2, 0, 2.15), .03, M))
    for i in range(8):
        P.append(K.rod((-2 + i * .5, .03, 2.2), (-1.75 + i * .5, .03, 2.45), .01, M))  # barbed wire
    return piece("prop_fence_metal", P, [col((4.0, .2, 2.3), (0, 0, 1.15))])


def p_transformer():
    O, M, H_ = K.mat("paint_olive"), K.mat("gunmetal"), K.mat("hazard")
    P = [K.box((2.4, 1.6, 2.2), (0, 0, 1.3), O, bevel=.04), K.box((2.8, 2.0, .2), (0, 0, .1), K.mat("concrete")),
         K.box((2.0, .05, .4), (0, .82, 2.0), H_, bevel=0)]
    for i in range(3):
        P.append(K.cyl(.12, .8, (-.7 + i * .7, 0, 2.8), K.mat("glass_dark"), seg=6))
    for i in range(8):
        P.append(K.box((.06, 1.65, 1.6), (-1.05 + i * .3, 0, 1.2), M, bevel=0))
    return piece("prop_transformer", P, [col((2.8, 2.0, 2.6), (0, 0, 1.3))])


def p_bus_stop():
    M, G = K.mat("gunmetal"), K.mat("glass_dark")
    P = [K.box((3.2, 1.4, .1), (0, 0, 2.6), M), K.box((3.0, .05, 2.2), (0, -.65, 1.3), G, bevel=0),
         K.box((.05, 1.3, 2.2), (-1.55, 0, 1.3), G, bevel=0), K.box((2.6, .4, .06), (0, -.3, .5), K.mat("wood_board")),
         K.box((.8, .05, 1.2), (1.55, -.3, 1.4), K.mat("sign"), rot=(0, 0, 90), bevel=0)]
    for x in (-1.55, 1.55):
        for y in (-.65, .65):
            P.append(K.box((.08, .08, 2.6), (x, y, 1.3), M))
    return piece("prop_bus_stop", P, [col((3.2, .2, 2.6), (0, -.65, 1.3)), col((.2, 1.4, 2.6), (-1.55, 0, 1.3))])


def p_billboard():
    M = K.mat("gunmetal")
    P = [K.box((7, .25, 3.2), (0, 0, 6.2), K.mat("sign"), bevel=.03), K.box((7.2, .3, .2), (0, 0, 7.9), M),
         K.box((7, .8, .08), (0, .45, 4.6), M)]
    for x in (-2.5, 2.5):
        P.append(K.box((.3, .3, 6), (x, -.2, 3), M))
    return piece("prop_billboard", P, [col((.4, .4, 6), (-2.5, -.2, 3)), col((.4, .4, 6), (2.5, -.2, 3))])


def p_tractor():
    R, T_, M = K.mat("paint_rust_red"), K.mat("rubber"), K.mat("gunmetal")
    P = [K.box((1.0, 2.2, .9), (0, .5, 1.2), R, bevel=.06), K.box((1.4, 1.2, .3), (0, -.7, 1.1), R),
         K.box((.9, .8, .1), (0, -.7, 2.3), R), K.cyl(.08, 1.0, (.3, 1.2, 2.0), M, seg=6),
         K.box((.5, .4, .2), (0, -.6, 1.4), M)]
    for x in (-.85, .85):
        P += [K.cyl(.85, .45, (x, -.7, .85), T_, seg=12, rot=(0, 90, 0)), K.cyl(.45, .5, (x, -.7, .85), R, seg=8, rot=(0, 90, 0))]
        P += [K.cyl(.45, .3, (x * .8, 1.3, .45), T_, seg=10, rot=(0, 90, 0))]
    for x in (-.55, .55):
        P.append(K.rod((x, -1.2, 1.2), (x, -1.2, 2.3), .03, M))
    return piece("prop_tractor", P, [col((2.0, 3.2, 2.2), (0, 0, 1.1))])


def p_mailbox():
    M = K.mat("gunmetal")
    P = [K.box((.1, .1, 1.1), (0, 0, .55), K.mat("wood_board")), K.box((.25, .45, .25), (0, 0, 1.2), K.mat("siding_blue"), bevel=.05),
         K.box((.03, .1, .15), (.14, -.1, 1.3), K.mat("paint_rust_red"))]
    return piece("prop_mailbox", P, [])


# ---------------------------------------------------------------- vehicles
def vehicle(name, body_mat, length, width, cab, bed, wheel_r, wheel_x, wheel_y):
    """Drivable car: body mesh + four separately named wheel nodes (Wheel_FL ...)
    with their origin on the axle, so the game can spin and steer them."""
    G, T_, M = K.mat("glass_dark"), K.mat("rubber"), K.mat("gunmetal")
    hl, tl = K.mat("glass_dark", emit=(1, .9, .6)), K.mat("paint_rust_red", emit=(.8, .05, .03))
    zb = wheel_r + .1
    P = [K.box((width, length, .55), (0, 0, zb + .28), body_mat, bevel=.06),
         K.box((width + .04, .22, .25), (0, length / 2, zb + .1), M), K.box((width + .04, .22, .25), (0, -length / 2, zb + .1), M),
         K.box((width * .7, .03, .2), (0, length / 2 + .01, zb + .4), M, bevel=0),
         K.box((.3, .03, .14), (-width * .35, length / 2 + .01, zb + .42), hl, bevel=0),
         K.box((.3, .03, .14), (width * .35, length / 2 + .01, zb + .42), hl, bevel=0),
         K.box((.3, .03, .12), (-width * .38, -length / 2 - .01, zb + .45), tl, bevel=0),
         K.box((.3, .03, .12), (width * .38, -length / 2 - .01, zb + .45), tl, bevel=0)]
    cy0, cy1 = cab
    clen = cy1 - cy0
    P += [K.box((width * .92, clen, .6), (0, (cy0 + cy1) / 2, zb + .86), body_mat, taper=(.88, .78), bevel=.05),
          K.box((width * .84, clen * .7, .44), ((0), (cy0 + cy1) / 2, zb + .84), G, taper=(.9, .8), bevel=0)]
    for s in (-1, 1):  # door lines + mirrors
        P.append(K.box((.02, .04, .5), (s * width / 2, (cy0 + cy1) / 2, zb + .3), M, bevel=0))
        P.append(K.box((.12, .05, .1), (s * (width / 2 + .07), cy1 - .1, zb + .75), M))
    if bed:
        b0, b1 = bed
        P += [K.box((.08, b1 - b0, .45), (width / 2 - .04, (b0 + b1) / 2, zb + .78), body_mat),
              K.box((.08, b1 - b0, .45), (-width / 2 + .04, (b0 + b1) / 2, zb + .78), body_mat),
              K.box((width, .08, .45), (0, b0 + .04, zb + .78), body_mat), K.box((width - .2, b1 - b0 - .2, .03), (0, (b0 + b1) / 2, zb + .57), M)]
    root = K.finish(name, P)
    for tag, x, y in (("FL", -wheel_x, wheel_y), ("FR", wheel_x, wheel_y), ("RL", -wheel_x, -wheel_y), ("RR", wheel_x, -wheel_y)):
        piv = bpy.data.objects.new("Wheel_" + tag, None)
        bpy.context.scene.collection.objects.link(piv)
        piv.location = (x, y, wheel_r)
        piv.parent = root
        tyre = K.cyl(wheel_r, .26, (0, 0, 0), T_, seg=10, rot=(0, 90, 0), name="Tyre_" + tag)
        hub = K.cyl(wheel_r * .55, .28, (0, 0, 0), M, seg=8, rot=(0, 90, 0), name="Hub_" + tag)
        for o in (tyre, hub):
            o.parent = piv
            K.box_uv(o)
    return root


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    K.TEXEL = 2.5  # building faces: one texture repeat per 2.5 m
    load_textures()
    roots = []
    for s in STYLES:
        roots += [wall(s), wall_opening(s, 2.0, 2.4, "window"), wall_opening(s, 3.0, 3.2, "door"), wall_glass(s),
                  corner(s), parapet(s)]
        for w in (8, 12):
            roots.append(gable_end(s, w))
    for name, t in (("concrete", "concrete_floor"), ("wood", "wood_planks"), ("tiles", "tiles")):
        roots.append(floor_piece(name, t))
    roots.append(roof_flat())
    for w in (8, 12):
        roots.append(roof_gable(w))
        r = roof_gable(w, "tin_roof")
        r.name = "roof_tin_%d" % w
        roots.append(r)
    for fn in (p_gas_pump, p_gas_canopy, p_silo, p_water_tower, p_hay_bale, p_hay_stack, p_power_pylon,
               p_utility_pole, p_fence_wood, p_fence_metal, p_transformer, p_bus_stop, p_billboard, p_tractor, p_mailbox):
        roots.append(fn())
    roots.append(vehicle("vehicle_pickup", K.mat("paint_olive"), 5.0, 1.95, (-.1, 1.4), (-2.4, -.1), .42, .86, 1.6))
    roots.append(vehicle("vehicle_sedan", K.mat("siding_blue"), 4.4, 1.8, (-1.3, 1.0), None, .36, .8, 1.35))
    for r in roots:
        K.export(r)
    x = 0.0
    for r in roots:
        r.location.x = x
        x += 6.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(K.ROOT, "art", "blender", "world_kit.blend"))
    print("WORLD KIT OK %d pieces" % len(roots))


main()
