# Halloway Mill building kit (Blender 5.x, headless):
#   blender -b --factory-startup -P art/blender/build_mill_kit.py
# Modelled pieces that dress the map's 0.6 m walls (WALL_T), 4.2 m high (WALL_H), with
# floor-height openings: windows 2.0 x 2.4, doors 3.0 x 3.2 (bunker_arena.gd).
# Like the METRO 9 kit, detail lives in the geometry, not the textures: each surface is one
# named material (M_brick, M_corrugated, ...) that MillMap swaps for the METRO 9 scan material
# (art/textures/ms_<name>_albedo.png), so the glbs carry no images.
# Conventions: Z up, a piece's OUTSIDE faces +Y (Godot -Z), origin on the floor at the wall's
# centreline and the piece's centre. Output: art/models/mill/<piece>.glb, art/blender/mill_kit.blend.
import bpy, bmesh, math, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_map_kit as K  # geometry helpers only (box, cyl, rod, finish, export)

ROOT = K.ROOT
K.MODEL_DIR = os.path.join(ROOT, "art", "models", "mill")
os.makedirs(K.MODEL_DIR, exist_ok=True)

WT, WH = 0.6, 4.2          # wall thickness and height
HT = WT / 2                 # half thickness: outside face at +HT
WIN_W, WIN_H = 2.0, 2.4
DOOR_W, DOOR_H = 3.0, 3.2

# Preview colours only (Godot replaces these by name).
COL = {"brick": (.42, .2, .14), "plaster": (.55, .53, .5), "concrete": (.45, .45, .44), "screed": (.36, .36, .36),
       "corrugated": (.4, .42, .44), "rust": (.35, .18, .1), "steel": (.25, .27, .3), "wood": (.4, .3, .2)}
_M = {}


def M(name):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new("M_" + name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*COL[name], 1)
    b.inputs["Roughness"].default_value = 0.9
    _M[name] = m
    return m


box, cyl, rod = K.box, K.cyl, K.rod


def corr_sheet(w, h, loc, m, rib=0.15, depth=0.035, vertical=True, name="sheet"):
    """Corrugated sheet in the XZ plane (ribs run up), trapezoid profile, faces +Y."""
    bm = bmesh.new()
    n = max(2, int(round(w / rib)))
    prof = []
    for i in range(n + 1):
        x = -w / 2 + w * i / n
        prof.append((x, depth if i % 2 else 0.0))
    lo = [bm.verts.new((x, y, -h / 2)) for x, y in prof]
    hi = [bm.verts.new((x, y, h / 2)) for x, y in prof]
    for i in range(n):
        bm.faces.new((lo[i], lo[i + 1], hi[i + 1], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:  # all face +Y
        if f.normal.y < 0:
            f.normal_flip()
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.01)
    ob = K._obj(name, bm, m)
    ob.location = loc
    if not vertical:
        ob.rotation_euler = (0, math.radians(90), 0)
    return ob


# ------------------------------------------------------------------ brick buildings
def win_brick():
    C, S = M("concrete"), M("steel")
    P = [box((WIN_W + .7, WT + .16, .35), (0, 0, WIN_H + .175), C, bevel=.02)]     # precast lintel
    for s in (-1, 1):
        x = s * (WIN_W / 2 + .06)
        P.append(box((.12, WT + .04, WIN_H), (x, 0, WIN_H / 2), C, bevel=.01))    # reveal / jamb
        P.append(box((.06, .08, WIN_H - .1), (s * (WIN_W / 2 - .03), HT - .12, WIN_H / 2), S, bevel=0))  # steel frame
    P.append(box((WIN_W, .08, .06), (0, HT - .12, WIN_H - .05), S, bevel=0))
    P.append(box((WIN_W + .3, .2, .1), (0, HT + .06, .05), C, bevel=.01))         # kerb at the foot
    return K.finish("mk_win_brick", P)


def door_brick():
    C, S = M("concrete"), M("steel")
    P = [box((DOOR_W + .9, WT + .16, .4), (0, 0, DOOR_H + .2), C, bevel=.02)]
    for s in (-1, 1):
        P.append(box((.14, WT + .04, DOOR_H), (s * (DOOR_W / 2 + .07), 0, DOOR_H / 2), C, bevel=.01))
    P.append(box((DOOR_W + .6, .9, .12), (0, HT + .45, .06), C, bevel=.02))       # step slab
    P.append(box((DOOR_W + .8, .7, .06), (0, HT + .4, DOOR_H + .55), S, rot=(-8, 0, 0), bevel=0))  # canopy
    for s in (-1, 1):
        P.append(rod((s * (DOOR_W / 2 + .3), HT, DOOR_H + .9), (s * (DOOR_W / 2 + .3), HT + .7, DOOR_H + .55), .02, S))
    return K.finish("mk_door_brick", P)


def pier_brick():
    B, C = M("brick"), M("concrete")
    P = [box((.6, .14, WH - .1), (0, HT + .07, (WH - .1) / 2), B, bevel=.01),
         box((.7, .22, .12), (0, HT + .09, WH - .05), C, bevel=.01),
         box((.7, .2, .4), (0, HT + .1, .2), C, bevel=.01)]
    return K.finish("mk_pier_brick", P)


def coping(L):
    C = M("concrete")
    P = [box((L, WT + .16, .16), (0, 0, WH + .08), C, bevel=.015),
         box((L, .06, .1), (0, HT + .05, WH - .05), C, bevel=0)]   # drip edge
    return K.finish("mk_coping_%dm" % L, P)


def plinth(L):
    C = M("concrete")
    return K.finish("mk_plinth_%dm" % L, [box((L, .08, .45), (0, HT + .04, .225), C, bevel=.01)])


def string_course(L):
    C = M("concrete")
    return K.finish("mk_band_%dm" % L, [box((L, .08, .16), (0, HT + .04, 3.0), C, bevel=.01)])


def gutter(L):
    S = M("steel")
    P = [box((L, .16, .1), (0, HT + .08, WH - .1), S, bevel=0), box((L, .02, .14), (0, HT + .16, WH - .08), S, bevel=0)]
    return K.finish("mk_gutter_%dm" % L, P)


def downpipe():
    S = M("steel")
    P = [cyl(.05, WH - .2, (0, HT + .1, (WH - .2) / 2 + .1), S, seg=6),
         cyl(.05, .3, (0, HT + .22, .1), S, seg=6, rot=(60, 0, 0))]
    for z in (1.0, 2.4, 3.6):
        P.append(box((.14, .12, .04), (0, HT + .06, z), S, bevel=0))
    return K.finish("mk_downpipe", P)


# ------------------------------------------------------------------ steel / corrugated buildings
def clad(L):
    R, S = M("corrugated"), M("steel")
    P = [corr_sheet(L, WH - .6, (0, HT + .02, .6 + (WH - .6) / 2), R),
         box((L, .1, .08), (0, HT + .05, .62), S, bevel=0),           # base angle
         box((L, .12, .1), (0, HT + .06, WH - .05), S, bevel=0),      # eaves angle
         box((L, .1, .6), (0, HT + .05, .3), M("concrete"), bevel=.01)]  # concrete upstand
    return K.finish("mk_clad_%dm" % L, P)


def column_steel():
    S, C = M("steel"), M("concrete")
    P = [box((.3, .04, WH + .4), (0, HT + .28, (WH + .4) / 2), S, bevel=0),   # outer flange
         box((.3, .04, WH + .4), (0, HT + .04, (WH + .4) / 2), S, bevel=0),   # inner flange
         box((.03, .24, WH + .4), (0, HT + .16, (WH + .4) / 2), S, bevel=0),  # web
         box((.5, .45, .3), (0, HT + .16, .15), C, bevel=.02)]               # pad
    return K.finish("mk_column_steel", P)


def win_metal():
    S = M("steel")
    P = [box((WIN_W + .5, WT + .1, .25), (0, 0, WIN_H + .125), S, bevel=0)]
    for s in (-1, 1):
        P.append(box((.2, WT + .1, WIN_H), (s * (WIN_W / 2 + .1), 0, WIN_H / 2), S, bevel=0))
    P.append(box((WIN_W + .4, .3, .06), (0, HT + .15, WIN_H + .3), S, rot=(-12, 0, 0), bevel=0))  # flashing hood
    return K.finish("mk_win_metal", P)


def door_metal():
    """Bay door: steel frame and the rolled-up shutter's drum box over the 3.0 x 3.2 opening."""
    S, R = M("steel"), M("rust")
    P = [box((DOOR_W + .6, WT + .1, .3), (0, 0, DOOR_H + .15), S, bevel=0)]
    for s in (-1, 1):
        P.append(box((.25, WT + .1, DOOR_H), (s * (DOOR_W / 2 + .125), 0, DOOR_H / 2), S, bevel=0))
        P.append(box((.1, .14, DOOR_H), (s * (DOOR_W / 2 - .05), -HT - .07, DOOR_H / 2), S, bevel=0))  # guide rails
    P.append(cyl(.32, DOOR_W + .4, (0, -HT - .32, DOOR_H + .2), R, seg=8, rot=(0, 90, 0)))   # drum
    P.append(box((DOOR_W + .4, .5, .08), (0, -HT - .32, DOOR_H + .56), S, bevel=0))
    for s in (-1, 1):
        P.append(box((.6, .9, .25), (s * (DOOR_W / 2 + .3), HT + .45, .125), M("rust"), bevel=.02))  # bollard pads
        P.append(cyl(.1, 1.0, (s * (DOOR_W / 2 + .3), HT + .45, .75), M("steel"), seg=8))
    return K.finish("mk_door_metal", P)


# ------------------------------------------------------------------ roofs and structure
def roof_corr():
    """4 x 4 m corrugated roof panel (ribs run along Y), on two steel purlins."""
    R, S = M("corrugated"), M("steel")
    sh = corr_sheet(4.0, 4.0, (0, 0, 0), R)
    sh.rotation_euler = (math.radians(90), 0, 0)   # lie flat, ribs along Y, top faces +Z
    sh.location = (0, 0, .05)
    P = [sh]
    for x in (-1.0, 1.0):
        P.append(box((.08, 4.0, .16), (x, 0, -.06), S, bevel=0))
    return K.finish("mk_roof_corr", P)


def truss(span):
    """Steel roof truss across `span` m (along X), seated on the wall tops at Z=WH."""
    S = M("steel")
    rise = span * 0.18
    a, b, c = (-span / 2, 0, WH), (span / 2, 0, WH), (0, 0, WH + rise)
    P = [rod(a, b, .06, S), rod(a, c, .07, S), rod(b, c, .07, S)]
    n = 6
    for i in range(1, n):
        t = i / n
        x = -span / 2 + span * t
        top = WH + rise * (1 - abs(2 * t - 1))
        P.append(rod((x, 0, WH), (x, 0, top), .035, S))
        if i < n - 1:
            nx = -span / 2 + span * (i + 1) / n
            ntop = WH + rise * (1 - abs(2 * (i + 1) / n - 1))
            P.append(rod((x, 0, WH), (nx, 0, ntop), .03, S) if t < .5 else rod((x, 0, top), (nx, 0, WH), .03, S))
    return K.finish("mk_truss_%dm" % span, P)


def chimney():
    B, C, S = M("brick"), M("concrete"), M("steel")
    H = 12.0
    P = [box((1.8, 1.8, 1.0), (0, 0, .5), C, bevel=.03),
         box((1.4, 1.4, H), (0, 0, H / 2), B, taper=(.8, .8), bevel=.02)]
    for z in (4.0, 8.0):
        w = 1.4 - .4 * z / H + .12
        P.append(box((w, w, .25), (0, 0, z), C, bevel=.02))
    P.append(box((1.3, 1.3, .35), (0, 0, H + .1), C, bevel=.02))
    for z in range(1, 12):       # rungs up one face
        P.append(rod((-.2, .62 + (H - z) * .016, z), (.2, .62 + (H - z) * .016, z), .02, S))
    return K.finish("mk_chimney", P)


def porch(L):
    """Boarding-house porch along the outside face: deck, posts, rail, lean-to roof."""
    W, R = M("wood"), M("corrugated")
    D = 2.4
    P = [box((L, D, .2), (0, HT + D / 2, .1), W, bevel=.01)]
    n = int(L / 2) + 1
    for i in range(n):
        x = -L / 2 + .15 + (L - .3) * i / (n - 1)
        P.append(box((.16, .16, 2.9), (x, HT + D - .12, 1.55), W, bevel=.015))
        if i < n - 1:
            nx = -L / 2 + .15 + (L - .3) * (i + 1) / (n - 1)
            for z in (.55, 1.0):
                P.append(box((nx - x - .16, .06, .1), ((x + nx) / 2, HT + D - .12, z), W, bevel=0))
    P.append(box((L, .2, .2), (0, HT + D - .12, 3.0), W, bevel=.01))
    roof = box((L + .4, D + .5, .06), (0, HT + D / 2 + .1, 3.45), R, rot=(14, 0, 0), bevel=0)
    P.append(roof)
    return K.finish("mk_porch_%dm" % L, P)


def dock(L):
    C, S, R = M("concrete"), M("steel"), M("rust")
    P = [box((L, 2.0, 1.1), (0, HT + 1.0, .55), C, bevel=.03),
         box((L, .08, .12), (0, HT + 2.0, 1.06), S, bevel=0)]
    for x in (-L / 2 + .6, L / 2 - .6):
        P.append(box((.4, .22, .5), (x, HT + 2.1, .55), M("rust"), bevel=.04))
    P.append(box((1.2, 2.0, .06), (L / 2 - 1.0, HT + 1.0, 1.12), S, bevel=0))  # dock plate
    return K.finish("mk_dock_%dm" % L, P)


PIECES = [win_brick, door_brick, pier_brick, lambda: coping(2), lambda: coping(4), lambda: plinth(2), lambda: plinth(4),
          lambda: string_course(4), lambda: gutter(4), downpipe,
          lambda: clad(2), lambda: clad(4), column_steel, win_metal, door_metal,
          roof_corr, lambda: truss(12), lambda: truss(18), chimney, lambda: porch(6), lambda: dock(6)]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    roots = []
    for fn in PIECES:
        r = fn()
        K.export(r)
        roots.append(r)
    x = 0.0
    for r in roots:
        r.location.x = x
        x += 8.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", "blender", "mill_kit.blend"))
    print("MILL KIT OK %d pieces" % len(roots))


if __name__ == "__main__":
    main()
