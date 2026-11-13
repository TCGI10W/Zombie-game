"""Substation 3-lane tactical FPS blockout (standalone tool, not wired into the game).

Builds a 90 m (X, east-west) x 64 m (Y, north-south) rain-slicked industrial
substation blockout: sunken cargo courtyard (centre), enclosed server bunker
(west), wet fuel depot + loading dock (east), two spawn courtyards (Y = +/-27).
Every solid mesh ends in "-col" (stair ramp colliders end in "-colonly") so
Godot 4 builds collision on .glb import. The script finishes by validating the
map against the scale metrics with geometry checks and ray casts, and exits
with code 1 if any check fails.

Run headless (PowerShell):
  & 'D:\\blender.exe' -b --factory-startup -P tools/generate_substation_blockout.py -- `
      --glb  C:/somewhere/substation_blockout.glb `
      --blend C:/somewhere/substation_blockout.blend `
      --render C:/somewhere/substation_topdown.png
All three outputs are optional; with none the map is only built and validated.
Coordinates: +X east, +Y north, +Z up, ground at Z = 0.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix

# ---------------------------------------------------------------------------
# Scale metrics (metres / degrees)
# ---------------------------------------------------------------------------
PLAYER_R = 0.40
PLAYER_H = 1.80
EYE_H = 1.65
CROUCH_H = 1.00
DOOR_W, DOOR_H = 1.60, 2.40
WAIST_H, WAIST_T = 1.10, 0.55
GLITCH_H = 1.45
LOS_H, LOS_T = 3.60, 0.30
MAX_SLOPE_DEG = 20.0
MIN_RAMP_W = 2.2

MAP_X, MAP_Y = 45.0, 32.0          # half extents (90 x 64)
PERIM_H = 6.0
PIT_HX, PIT_HY, PIT_Z = 12.0, 9.0, -1.2   # 24 x 18 pit, floor at -1.2
PIT_RAMP_DEG = 18.0
PIT_RAMP_RUN = abs(PIT_Z) / math.tan(math.radians(PIT_RAMP_DEG))
CATWALK_Z, CATWALK_W, RAIL_H = 4.2, 2.4, 1.05
DECK_T = 0.2
BUNKER_CEIL = 4.0
ATRIUM_H = 7.5
CORR_X0, CORR_X1 = -20.1, -14.6     # 5.5 m corridor interior
CORR_Y = 18.0                       # corridor interior Y -18..18
STAIR_DEG = 19.0
RISER = 0.15
TREAD = RISER / math.tan(math.radians(STAIR_DEG))
FLIGHT_STEPS = 14                   # 14 x 0.15 = 2.1 m per flight
LANDING = 2.4
STAIR_W = 2.4
WALL_T = 0.30
CONT_L, CONT_W, CONT_H = 6.06, 2.44, 2.59
RACK = (1.4, 0.8, 2.1)              # footprint X x Y, height (0.8 x 1.4 x 2.1 rack)
RACK_STEP = 3.2
TANK_R, TANK_H = 1.5, 3.8
DOCK_Z = 1.2

SUN_ELEV, SUN_AZ = 14.0, 215.0
SUN_HEX, SUN_E = "7899C8", 1.6
FLOOD_HEX, FLOOD_W, FLOOD_SIZE = "FF7A1A", 420.0, 1.5
CYAN_HEX, CYAN_W = "00E5FF", 45.0
FOG_DENSITY, FOG_ANISO = 0.012, 0.5

DOORS = []      # registered wall openings, measured by ray casts in validate()
COLL = {}


# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"glb": None, "blend": None, "render": None}
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key in opts and i + 1 < len(argv):
            opts[key] = os.path.abspath(argv[i + 1])
            i += 2
        else:
            i += 1
    return opts


# ---------------------------------------------------------------------------
# Scene / materials
# ---------------------------------------------------------------------------
def srgb_to_linear(hexstr):
    out = []
    for i in (0, 2, 4):
        c = int(hexstr[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    for name in ("01_Architecture", "02_Cover_Props", "03_Lighting_Volumes"):
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        COLL[name] = c


def _node_tree(mat):
    try:
        mat.use_nodes = True     # deprecated (always on) in Blender 5.x
    except Exception:
        pass
    return mat.node_tree


def make_mat(name, rgb, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.new(name)
    nt = _node_tree(mat)
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) \
            or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*rgb, 1.0)       # viewport / workbench colour
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


def build_materials():
    return {
        "asphalt": make_mat("M_WetAsphalt", (0.045, 0.05, 0.055), 0.0, 0.12),
        "concrete": make_mat("M_Concrete", (0.36, 0.36, 0.34), 0.0, 0.55),
        "concrete_dark": make_mat("M_ConcreteDark", (0.18, 0.185, 0.19), 0.0, 0.45),
        "pit": make_mat("M_PitConcreteWet", (0.22, 0.22, 0.21), 0.0, 0.2),
        "steel": make_mat("M_SteelGrating", (0.30, 0.32, 0.34), 0.9, 0.35),
        "rail": make_mat("M_RailHazard", (0.75, 0.55, 0.05), 0.3, 0.4),
        "cont_a": make_mat("M_ContainerRust", (0.42, 0.10, 0.04), 0.6, 0.45),
        "cont_b": make_mat("M_ContainerTeal", (0.03, 0.20, 0.22), 0.6, 0.45),
        "rack": make_mat("M_ServerRack", (0.03, 0.03, 0.035), 0.7, 0.3),
        "barrier": make_mat("M_JerseyBarrier", (0.55, 0.55, 0.50), 0.0, 0.5),
        "tank": make_mat("M_FuelTank", (0.62, 0.62, 0.58), 0.6, 0.3),
        "dressing": make_mat("M_Transformer", (0.20, 0.24, 0.20), 0.5, 0.5),
    }


# ---------------------------------------------------------------------------
# Geometry primitives -> (verts, faces) in object-local space
# ---------------------------------------------------------------------------
_BOX_F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box(x0, y0, z0, x1, y1, z1):
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    z0, z1 = min(z0, z1), max(z0, z1)
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    return v, _BOX_F


def obox(cx, cy, z0, sx, sy, sz, rot_deg=0.0):
    """Box centred on (cx, cy), base at z0, rotated about its own Z axis."""
    c, s = math.cos(math.radians(rot_deg)), math.sin(math.radians(rot_deg))
    hx, hy = sx / 2, sy / 2
    ring = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    pts = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in ring]
    v = [(x, y, z0) for x, y in pts] + [(x, y, z0 + sz) for x, y in pts]
    return v, _BOX_F


def prism(profile, axis, t0, t1):
    """Extrude a 2D polygon. axis 'x': profile is (y, z); axis 'y': profile is (x, z)."""
    n = len(profile)
    mk = (lambda t, u, w: (t, u, w)) if axis == "x" else (lambda t, u, w: (u, t, w))
    v = [mk(t0, u, w) for u, w in profile] + [mk(t1, u, w) for u, w in profile]
    f = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    f += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return v, f


def cylinder(cx, cy, z0, r, h, seg=32):
    v = []
    for z in (z0, z0 + h):
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    f = [tuple(range(seg)), tuple(range(2 * seg - 1, seg - 1, -1))]
    f += [(i, (i + 1) % seg, seg + (i + 1) % seg, seg + i) for i in range(seg)]
    return v, f


_NAMES = set()


def make_obj(name, parts, coll, mat, loc=(0, 0, 0), rot_z=0.0, role=None, suffix="-col", **props):
    full = name + suffix
    assert full not in _NAMES, "duplicate object name " + full
    _NAMES.add(full)
    verts, faces = [], []
    for pv, pf in parts:
        off = len(verts)
        verts += pv
        faces += [tuple(i + off for i in f) for f in pf]
    me = bpy.data.meshes.new(full)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.validate()
    if mat is not None:
        me.materials.append(mat)
    ob = bpy.data.objects.new(full, me)
    ob.location = loc
    ob.rotation_euler = (0, 0, math.radians(rot_z))
    COLL[coll].objects.link(ob)
    if role:
        ob["role"] = role
    for k, val in props.items():
        ob[k] = val
    return ob


def wall(name, axis, c, a0, a1, z0, z1, mat, openings=(), t=WALL_T, coll="01_Architecture", role="wall"):
    """Straight wall. axis 'x' runs along X at y=c; axis 'y' runs along Y at x=c.
    openings: (u_centre, width, z_bottom, z_top, kind) cut out of the wall."""
    ops = [(u - w / 2, u + w / 2, zb, zt, kind) for u, w, zb, zt, kind in openings]
    cuts = sorted({a0, a1} | {max(a0, min(a1, x)) for o in ops for x in o[:2]})
    parts = []
    for b0, b1 in zip(cuts, cuts[1:]):
        if b1 - b0 < 1e-6:
            continue
        mid = (b0 + b1) / 2
        cover = sorted((o[2], o[3]) for o in ops if o[0] < mid < o[1])
        spans, cur = [], z0
        for zb, zt in cover:
            if zb > cur:
                spans.append((cur, zb))
            cur = max(cur, zt)
        if cur < z1:
            spans.append((cur, z1))
        for s0, s1 in spans:
            if axis == "x":
                parts.append(box(b0, c - t / 2, s0, b1, c + t / 2, s1))
            else:
                parts.append(box(c - t / 2, b0, s0, c + t / 2, b1, s1))
    for u, w, zb, zt, kind in openings:
        DOORS.append(dict(wall=name, axis=axis, c=c, u=u, w=w, zb=zb, zt=zt, kind=kind, t=t))
    return make_obj(name, parts, coll, mat, role=role, height=z1 - z0, thickness=t)


def door(u, kind="door"):
    return (u, DOOR_W, 0.0, DOOR_H, kind)


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------
def build_ground(M):
    A = "01_Architecture"
    make_obj("Ground_North", [box(-MAP_X, PIT_HY + WALL_T, -0.3, MAP_X, MAP_Y, 0)], A, M["asphalt"], role="floor")
    make_obj("Ground_South", [box(-MAP_X, -MAP_Y, -0.3, MAP_X, -PIT_HY - WALL_T, 0)], A, M["asphalt"], role="floor")
    make_obj("Ground_West", [box(-MAP_X, -PIT_HY - WALL_T, -0.3, -PIT_HX - WALL_T, PIT_HY + WALL_T, 0)], A, M["asphalt"], role="floor")
    make_obj("Ground_East", [box(PIT_HX + WALL_T, -PIT_HY - WALL_T, -0.3, MAP_X, PIT_HY + WALL_T, 0)], A, M["asphalt"], role="floor")
    zb = PIT_Z - 0.3
    make_obj("Pit_Floor", [box(-PIT_HX, -PIT_HY, zb, PIT_HX, PIT_HY, PIT_Z)], A, M["pit"], role="pit_floor")
    t = WALL_T
    make_obj("Pit_Retaining_Wall", [
        box(-PIT_HX - t, PIT_HY, zb, PIT_HX + t, PIT_HY + t, 0),
        box(-PIT_HX - t, -PIT_HY - t, zb, PIT_HX + t, -PIT_HY, 0),
        box(-PIT_HX - t, -PIT_HY, zb, -PIT_HX, PIT_HY, 0),
        box(PIT_HX, -PIT_HY, zb, PIT_HX + t, PIT_HY, 0),
    ], A, M["concrete_dark"], role="pit_wall")
    # Perimeter walls sit just outside the 90 x 64 play rectangle.
    make_obj("Wall_Perimeter_N", [box(-MAP_X - t, MAP_Y, 0, MAP_X + t, MAP_Y + t, PERIM_H)], A, M["concrete"], role="perimeter")
    make_obj("Wall_Perimeter_S", [box(-MAP_X - t, -MAP_Y - t, 0, MAP_X + t, -MAP_Y, PERIM_H)], A, M["concrete"], role="perimeter")
    make_obj("Wall_Perimeter_W", [box(-MAP_X - t, -MAP_Y, 0, -MAP_X, MAP_Y, PERIM_H)], A, M["concrete"], role="perimeter")
    make_obj("Wall_Perimeter_E", [box(MAP_X, -MAP_Y, 0, MAP_X + t, MAP_Y, PERIM_H)], A, M["concrete"], role="perimeter")


def ramp_y(name, x0, x1, y_top, y_bot, z_top, z_bot, mat, coll="01_Architecture", role="ramp", suffix="-col"):
    """Solid wedge sloping along Y (top edge at y_top), width along X."""
    prof = [(y_top, z_top), (y_bot, z_bot), (y_top, z_bot)]
    return make_obj(name, [prism(prof, "x", x0, x1)], coll, mat, role=role, suffix=suffix)


def build_pit(M):
    A = "01_Architecture"
    L = PIT_RAMP_RUN
    # North / south main ramps (4 m wide), inside the pit against the retaining wall.
    ramp_y("Ramp_Pit_North", -2.0, 2.0, PIT_HY, PIT_HY - L, 0.0, PIT_Z, M["concrete"])
    ramp_y("Ramp_Pit_South", -2.0, 2.0, -PIT_HY, -PIT_HY + L, 0.0, PIT_Z, M["concrete"])
    # West / east side landings (bunker breach + east ledge) with ramps both ways.
    for side, sx in (("West", -1), ("East", 1)):
        xa, xb = sx * PIT_HX, sx * (PIT_HX - STAIR_W)
        make_obj("Pit_Landing_" + side, [box(xa, -1.2, PIT_Z, xb, 1.2, 0.0)], A, M["concrete"], role="landing")
        ramp_y("Ramp_Pit%s_N" % side, xa, xb, 1.2, 1.2 + L, 0.0, PIT_Z, M["concrete"])
        ramp_y("Ramp_Pit%s_S" % side, xa, xb, -1.2, -1.2 - L, 0.0, PIT_Z, M["concrete"])


def build_container(tag, cx, cy, rot, mat, door_end):
    """Hollow ISO container, open double doors at local +X (door_end=1) or -X end."""
    C = "02_Cover_Props"
    L, W, H, t, ft = CONT_L, CONT_W, CONT_H, 0.08, 0.12
    hl, hw = L / 2, W / 2
    closed = -door_end * hl
    parts = [
        box(-hl, -hw, 0, hl, hw, ft),                       # floor
        box(-hl, -hw, H - t, hl, hw, H),                    # roof
        box(-hl, -hw, ft, hl, -hw + t, H - t),              # side walls
        box(-hl, hw - t, ft, hl, hw, H - t),
        box(closed, -hw + t, ft, closed + door_end * t, hw - t, H - t),   # closed end
    ]
    ob = make_obj("Container_" + tag, parts, C, mat, loc=(cx, cy, PIT_Z), rot_z=rot, role="container",
                  interior_w=W - 2 * t, interior_h=H - t - ft, floor_t=ft)
    # Door leaves swung 110 deg outward, as separate solids.
    th = math.radians(110)
    for hinge_y, sgn in ((hw, -1), (-hw, 1)):
        dx, dy = door_end * math.sin(th), sgn * math.cos(th)
        hx, hy = door_end * (hl + 0.03), hinge_y
        ccx, ccy = hx + dx * hw / 2, hy + dy * hw / 2
        ang = math.degrees(math.atan2(dy, dx))
        # local -> world
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        wx, wy = cx + ccx * c - ccy * s, cy + ccx * s + ccy * c
        leaf = "L" if hinge_y > 0 else "R"
        make_obj("Container_%s_Door_%s" % (tag, leaf), [obox(0, 0, 0.05, hw, 0.05, H - 0.1)], C, mat,
                 loc=(wx, wy, PIT_Z), rot_z=rot + ang, role="container_door")
    return ob


def build_courtyard_props(M):
    C = "02_Cover_Props"
    build_container("A", -5.6, 3.7, 22.0, M["cont_a"], 1)
    build_container("B", 5.6, -3.7, -15.0, M["cont_b"], -1)
    # Waist cover in the pit and head-glitch / waist cover on the plazas (point-symmetric).
    cover = [("Cover_Pit_NE", 3.5, 3.0, PIT_Z, WAIST_H), ("Cover_Pit_SW", -3.5, -3.0, PIT_Z, WAIST_H),
             ("Cover_Plaza_N_Glitch", -5.0, 11.2, 0, GLITCH_H), ("Cover_Plaza_S_Glitch", 5.0, -11.2, 0, GLITCH_H),
             ("Cover_Plaza_N_Waist", 6.0, 13.5, 0, WAIST_H), ("Cover_Plaza_S_Waist", -6.0, -13.5, 0, WAIST_H),
             ("Cover_Yard_NW_Waist", -12.0, 20.0, 0, WAIST_H), ("Cover_Yard_SE_Waist", 12.0, -20.0, 0, WAIST_H)]
    for name, x, y, z, h in cover:
        role = "cover_glitch" if h == GLITCH_H else "cover_waist"
        make_obj(name, [obox(0, 0, 0, 2.4, WAIST_T, h)], C, M["concrete"], loc=(x, y, z), role=role)


def slotted_rail(x0, x1, y0, y1, z, axis):
    """1.05 m slotted ballistic railing on the deck at height z.
    axis 'x': runs along X between x0..x1 occupying y0..y1; axis 'y' swaps roles."""
    parts = []

    def b(a0, a1, z0, z1):
        if axis == "x":
            parts.append(box(a0, y0, z + z0, a1, y1, z + z1))
        else:
            parts.append(box(y0, a0, z + z0, y1, a1, z + z1))

    length = x1 - x0
    n_posts = max(2, int(math.ceil(length / 1.5)) + 1)
    for i in range(n_posts):
        p = x0 + (length - 0.06) * i / (n_posts - 1)
        b(p, p + 0.06, 0, RAIL_H)
    b(x0, x1, RAIL_H - 0.08, RAIL_H)          # top rail
    b(x0, x1, 0.0, 0.15)                       # kick plate
    b(x0, x1, 0.55, 0.60)                      # mid rail
    pitch, plate = 0.30, 0.22                  # ballistic plates with 8 cm slots
    p = x0 + 0.06
    while p + plate <= x1 - 0.06:
        b(p, p + plate, 0.20, RAIL_H - 0.12)
        p += pitch
    return parts


def stair_flight(x0, x1, y_bottom, direction, z_base, steps=FLIGHT_STEPS):
    """Solid steps from the ground (z=0). direction=-1 climbs toward -Y."""
    parts = []
    for k in range(1, steps + 1):
        ya = y_bottom + direction * (k - 1) * TREAD
        yb = y_bottom + direction * k * TREAD
        parts.append(box(x0, ya, 0.0, x1, yb, z_base + k * RISER))
    return parts


def stair_collider(name, x0, x1, y_bottom, direction, z_base, steps=FLIGHT_STEPS):
    """Smooth ramp collider through the step nosings (Godot -colonly)."""
    rise = steps * RISER
    y_start = y_bottom - direction * TREAD          # starts one tread before the first riser
    y_nose = y_bottom + direction * (steps - 1) * TREAD
    y_end = y_bottom + direction * steps * TREAD
    prof = [(y_start, z_base), (y_nose, z_base + rise), (y_end, z_base + rise), (y_end, z_base)]
    return make_obj(name, [prism(prof, "x", x0, x1)], "01_Architecture", None,
                    role="stair_collider", suffix="-colonly")


def sloped_rail(name, x0, x1, pts, M):
    """Solid 1.05 m balustrade following a polyline of (y, floor_z)."""
    parts = []
    for (ya, za), (yb, zb) in zip(pts, pts[1:]):
        prof = [(ya, za), (yb, zb), (yb, zb + RAIL_H), (ya, za + RAIL_H)]
        parts.append(prism(prof, "x", x0, x1))
    make_obj(name, parts, "01_Architecture", M["rail"], role="railing")


def build_bunker(M):
    A, C = "01_Architecture", "02_Cover_Props"
    con, dark = M["concrete"], M["concrete_dark"]
    t = WALL_T
    xw, xe = CORR_X0 - t / 2, CORR_X1 + t / 2           # wall centre lines
    yn, ys = CORR_Y + t / 2, -CORR_Y - t / 2
    ya = 3.0                                            # atrium bay Y -3..3
    portal = (0.0, 2.6, BUNKER_CEIL, 6.8, "portal")     # catwalk pass-through
    # East wall: breach onto the courtyard ledge, catwalk portal above it.
    wall("Wall_Bunker_East_S", "y", xe, ys - t / 2, -ya, 0, BUNKER_CEIL, con)
    wall("Wall_Bunker_East_Atrium", "y", xe, -ya, ya, 0, ATRIUM_H, con,
         openings=[(0.0, 2.4, 0.0, 2.6, "breach"), portal])
    wall("Wall_Bunker_East_N", "y", xe, ya, yn + t / 2, 0, BUNKER_CEIL, con)
    # West wall: corridor | stair hall, with the stair-hall door and the catwalk portal.
    stair_door_y = 16.9
    wall("Wall_Bunker_West_S", "y", xw, ys - t / 2, -ya, 0, BUNKER_CEIL, con)
    wall("Wall_Bunker_West_N", "y", xw, -ya, yn + t / 2, 0, ATRIUM_H, con,
         openings=[portal, door(stair_door_y)])
    # Corridor ends: two doorways each. South end wall also seals the HV-yard pocket.
    doors_x = [door(-18.9), door(-15.8)]
    wall("Wall_Bunker_North", "x", yn, xw - t / 2, xe + t / 2, 0, BUNKER_CEIL, con, openings=doors_x)
    wall("Wall_Bunker_South", "x", ys, -23.4, xe + t / 2, 0, BUNKER_CEIL, con, openings=doors_x)
    # Stair hall (interior X -22.8..-20.4, Y -1.2..18).
    sx0, sx1 = xw - t / 2 - STAIR_W, xw - t / 2        # -22.8, -20.4
    wall("Wall_StairHall_West", "y", sx0 - t / 2, -1.2 - t, CORR_Y + t, 0, ATRIUM_H, con)
    wall("Wall_StairHall_South", "x", -1.2 - t / 2, sx0 - t, sx1, 0, ATRIUM_H, con)
    wall("Wall_StairHall_North", "x", yn, sx0 - t, sx1, 0, ATRIUM_H, con)
    # Atrium gables above the low roof.
    for tag, sy in (("N", 1), ("S", -1)):
        wall("Wall_Atrium_Gable_" + tag, "x", sy * (ya + t / 2), CORR_X0, CORR_X1, BUNKER_CEIL + 0.3, ATRIUM_H, con)
    # Roofs (ceiling underside at Z 4.0 in the corridor).
    make_obj("Roof_Bunker_S", [box(CORR_X0, ys - t / 2, BUNKER_CEIL, xe + t / 2, -ya, BUNKER_CEIL + 0.3)], A, dark, role="roof")
    make_obj("Roof_Bunker_N", [box(CORR_X0, ya, BUNKER_CEIL, xe + t / 2, yn + t / 2, BUNKER_CEIL + 0.3)], A, dark, role="roof")
    make_obj("Roof_Bunker_Atrium", [box(xw - t / 2, -ya - t, ATRIUM_H, xe + t / 2, ya + t, ATRIUM_H + 0.3)], A, dark, role="roof")
    make_obj("Roof_StairHall", [box(sx0 - t, -1.2 - t, ATRIUM_H, sx1, CORR_Y + t, ATRIUM_H + 0.3)], A, dark, role="roof")
    # Switchback-free straight stair: flight 1 (0 -> 2.1) and flight 2 (2.1 -> 4.2), climbing south.
    y_top = 1.2                                        # top landing = catwalk deck Y -1.2..1.2
    y_f2_bottom = y_top + FLIGHT_STEPS * TREAD
    y_mid_n = y_f2_bottom + LANDING
    y_f1_bottom = y_mid_n + FLIGHT_STEPS * TREAD
    parts = stair_flight(sx0, sx1, y_f1_bottom, -1, 0.0)
    parts.append(box(sx0, y_f2_bottom, 0.0, sx1, y_mid_n, 2.1))           # mid landing
    parts += stair_flight(sx0, sx1, y_f2_bottom, -1, 2.1)
    parts.append(box(sx0, -1.2, 0.0, sx1, y_top, CATWALK_Z - DECK_T))     # under the top landing
    make_obj("Stair_West", parts, A, con, role="stair", rise=RISER, tread=TREAD, width=STAIR_W)
    stair_collider("Stair_West_Flight1_Ramp", sx0, sx1, y_f1_bottom, -1, 0.0)
    stair_collider("Stair_West_Flight2_Ramp", sx0, sx1, y_f2_bottom, -1, 2.1)
    # Server racks: 11, every 3.2 m, staggered left/right of the corridor centre line.
    cxm = (CORR_X0 + CORR_X1) / 2
    for i in range(11):
        y = -16.0 + RACK_STEP * i
        x = cxm + (1.2 if i % 2 == 0 else -1.2)
        make_obj("Rack_Server_%02d" % (i + 1), [obox(0, 0, 0, RACK[0], RACK[1], RACK[2])], C, M["rack"],
                 loc=(x, y, 0), role="rack")
    # Breach rubble, kept outside the 2.4 m opening.
    rub = []
    for sy in (-1, 1):
        for sx, dx in ((-1, 0.5), (1, 0.6)):
            rub.append(obox(xe + sx * dx, sy * 1.75, 0, 0.7, 0.55, 0.35 + 0.1 * (sx > 0), 17 * sy * sx))
    make_obj("Rubble_Breach", rub, C, dark, role="rubble")
    # Broken chunks in the breach's upper corners (blown-out silhouette).
    make_obj("Rubble_Breach_Lintel", [obox(xe, sy * 1.05, 2.25, 0.3, 0.3, 0.35, 0) for sy in (-1, 1)],
             C, dark, role="rubble")


def build_catwalk(M):
    A = "01_Architecture"
    x_west, x_east = -22.8, 14.7
    hw = CATWALK_W / 2
    make_obj("Catwalk_Deck", [box(x_west, -hw, CATWALK_Z - DECK_T, x_east, hw, CATWALK_Z)], A, M["steel"],
             role="catwalk", width=CATWALK_W)
    z = CATWALK_Z
    rails = []
    for sy in (-1, 1):   # inside the atrium (drop into the corridor)
        y0, y1 = sorted((sy * hw, sy * (hw + 0.06)))
        rails += slotted_rail(CORR_X0, CORR_X1, y0, y1, z, "x")
    yn0, yn1 = hw, hw + 0.06
    rails += slotted_rail(CORR_X1 + WALL_T, x_east + 0.06, yn0, yn1, z, "x")          # north edge
    rails += slotted_rail(CORR_X1 + WALL_T, 12.3, -yn1, -yn0, z, "x")                # south edge (stair gap)
    rails += slotted_rail(-hw, hw, x_east, x_east + 0.06, z, "y")                    # east end
    make_obj("Catwalk_Railing", rails, A, M["rail"], role="railing", height=RAIL_H)
    cols = [box(x - 0.15, -0.15, PIT_Z, x + 0.15, 0.15, CATWALK_Z - DECK_T) for x in (-6.0, 0.0, 6.0)]
    cols.append(box(14.35, 0.75, 0.0, 14.65, 1.05, CATWALK_Z - DECK_T))
    make_obj("Catwalk_Columns", cols, A, M["steel"], role="column")
    # East exterior steel stair down to the depot strip (climbs north).
    x0, x1 = 12.3, 12.3 + STAIR_W
    y_f1_top = -hw
    y_f1_bottom = y_f1_top - FLIGHT_STEPS * TREAD
    y_mid_s = y_f1_bottom - LANDING
    y_f2_bottom = y_mid_s - FLIGHT_STEPS * TREAD
    parts = stair_flight(x0, x1, y_f2_bottom, 1, 0.0)
    parts.append(box(x0, y_mid_s, 0.0, x1, y_f1_bottom, 2.1))
    parts += stair_flight(x0, x1, y_f1_bottom, 1, 2.1)
    make_obj("Stair_East", parts, A, M["steel"], role="stair", rise=RISER, tread=TREAD, width=STAIR_W)
    stair_collider("Stair_East_Flight1_Ramp", x0, x1, y_f2_bottom, 1, 0.0)
    stair_collider("Stair_East_Flight2_Ramp", x0, x1, y_f1_bottom, 1, 2.1)
    line = [(y_f2_bottom, 0.0), (y_mid_s, 2.1), (y_f1_bottom, 2.1), (y_f1_top, CATWALK_Z)]
    sloped_rail("Rail_StairEast_W", x0 - 0.06, x0, line, M)
    sloped_rail("Rail_StairEast_E", x1, x1 + 0.06, line, M)


def jersey_profile():
    h = WAIST_T / 2
    return [(-h, 0), (h, 0), (h, 0.075), (0.15, 0.33), (0.075, WAIST_H),
            (-0.075, WAIST_H), (-0.15, 0.33), (-h, 0.075)]


def build_depot(M):
    A, C = "01_Architecture", "02_Cover_Props"
    con = M["concrete"]
    # Lane divider between the courtyard strip and the depot.
    wall("Wall_Divider_East", "y", 17.15, -18.0, 18.0, 0, LOS_H, con, openings=[door(6.0), door(-6.0)], role="los_wall")
    # Six staggered jersey barriers across the 42 m north-south sightline (point-symmetric about (28, 0)).
    spots = [(26.6, 15.0, 6), (29.4, 9.0, -8), (26.6, 3.0, 4), (29.4, -3.0, 4), (26.6, -9.0, -8), (29.4, -15.0, 6)]
    for i, (x, y, r) in enumerate(spots, 1):
        make_obj("Barrier_Jersey_%02d" % i, [prism(jersey_profile(), "x", -1.5, 1.5)], C, M["barrier"],
                 loc=(x, y, 0), rot_z=r, role="cover_waist", kind="jersey")
    for i, (x, y) in enumerate(((38.5, -8.0), (38.5, -14.0)), 1):
        make_obj("FuelTank_%02d" % i, [cylinder(0, 0, 0, TANK_R, TANK_H)], C, M["tank"], loc=(x, y, 0), role="tank")
        make_obj("FuelTank_%02d_Plinth" % i, [obox(0, 0, 0, 3.6, 3.6, 0.15)], C, M["concrete_dark"],
                 loc=(x, y, 0), role="plinth")
    make_obj("Cover_Depot_N_Waist", [obox(0, 0, 0, 2.4, WAIST_T, WAIST_H)], C, con, loc=(22.0, 12.0, 0), role="cover_waist")
    make_obj("Cover_Depot_S_Waist", [obox(0, 0, 0, 2.4, WAIST_T, WAIST_H)], C, con, loc=(34.0, -12.0, 0), role="cover_waist")
    # Raised loading platform (NE corner) with an 18 deg ramp and a stair.
    px0, px1, py0, py1 = 35.0, MAP_X, 12.0, 20.0
    make_obj("Platform_LoadingDock", [box(px0, py0, 0, px1, py1, DOCK_Z)], A, con, role="platform")
    ramp_y("Ramp_LoadingDock", 41.5, 44.5, py0, py0 - DOCK_Z / math.tan(math.radians(PIT_RAMP_DEG)), DOCK_Z, 0.0, con)
    steps = int(round(DOCK_Z / RISER))
    parts = [box(px0 - (steps - k + 1) * TREAD, 15.0, 0, px0 - (steps - k) * TREAD, 18.0, k * RISER)
             for k in range(1, steps + 1)]
    make_obj("Stair_LoadingDock", parts, A, con, role="stair", rise=RISER, tread=TREAD, width=3.0)
    prof = [(px0 - (steps + 1) * TREAD, 0), (px0 - TREAD, DOCK_Z), (px0, DOCK_Z), (px0, 0)]
    make_obj("Stair_LoadingDock_Ramp", [prism(prof, "y", 15.0, 18.0)], A, None, role="stair_collider", suffix="-colonly")


def build_spawns_and_yards(M):
    A, D = "01_Architecture", "02_Cover_Props"
    con = M["concrete"]
    for tag, s in (("N", 1), ("S", -1)):
        y_in, y_out = s * 22.0, s * MAP_Y
        lo, hi = sorted((y_in - s * WALL_T, y_out))
        dys = [door(s * 25.0, "door"), door(s * 29.0, "door")]
        wall("Wall_Spawn%s_West" % tag, "y", -9.15, lo, hi, 0, LOS_H, con, openings=dys, role="los_wall")
        wall("Wall_Spawn%s_East" % tag, "y", 9.15, lo, hi, 0, LOS_H, con, openings=dys, role="los_wall")
        wall("Wall_Spawn%s_Front" % tag, "x", y_in - s * WALL_T / 2, -9.3, 9.3, 0, LOS_H, con,
             openings=[(0.0, 4.0, 0.0, LOS_H, "gap")], role="los_wall")
        wall("Wall_Spawn%s_Baffle" % tag, "x", s * 19.5, -4.0, 4.0, 0, LOS_H, con, role="los_wall")
        e = bpy.data.objects.new("Spawn_" + ("North" if s > 0 else "South"), None)
        e.empty_display_type = "ARROWS"
        e.location = (0, s * 27.0, 0)
        e.rotation_euler = (0, 0, 0 if s < 0 else math.pi)   # face the map centre
        COLL[A].objects.link(e)
    # HV transformer yard (out of bounds) west of the bunker.
    wall("Wall_Fence_HVYard_N", "y", -23.25, 18.0, MAP_Y, 0, PERIM_H, con, role="perimeter")
    wall("Wall_Fence_HVYard_S", "y", -23.25, -MAP_Y, -18.0, 0, PERIM_H, con, role="perimeter")
    for i, (x, y) in enumerate(((-34.0, 22.0), (-34.0, 8.0), (-34.0, -8.0), (-34.0, -22.0)), 1):
        make_obj("Transformer_%02d" % i, [obox(0, 0, 0, 5.0, 4.0, 4.5), obox(0, 0, 4.5, 3.0, 2.0, 1.2)],
                 D, M["dressing"], loc=(x, y, 0), role="set_dressing")


# ---------------------------------------------------------------------------
# Lighting, fog, colour management
# ---------------------------------------------------------------------------
def add_light(name, ltype, loc, hexcol, energy, rot=(0, 0, 0), **kw):
    ld = bpy.data.lights.new(name, ltype)
    ld.color = srgb_to_linear(hexcol)
    ld.energy = energy
    for k, v in kw.items():
        setattr(ld, k, v)
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    ob.rotation_euler = rot
    COLL["03_Lighting_Volumes"].objects.link(ob)
    return ob


def build_lighting():
    el, az = math.radians(SUN_ELEV), math.radians(SUN_AZ)   # azimuth clockwise from north (+Y)
    to_sun = Vector((math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el)))
    sun = add_light("Sun_Key", "SUN", (0, 0, 30), SUN_HEX, SUN_E, angle=math.radians(1.0))
    sun.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()        # light shines along -Z
    floods = [("N_Ramp", 0.0, 10.5), ("S_Ramp", 0.0, -10.5), ("Bunker_Breach", -12.5, 0.0),
              ("Depot_N", 28.0, 19.0), ("Depot_S", 28.0, -19.0), ("EastStair_Base", 13.5, -17.5)]
    for tag, x, y in floods:
        add_light("Flood_Sodium_" + tag, "AREA", (x, y, 8.0), FLOOD_HEX, FLOOD_W, size=FLOOD_SIZE, shape="SQUARE")
    cx = (CORR_X0 + CORR_X1) / 2
    for i, y in enumerate((-13.6, -6.4, 6.4, 13.6), 1):
        add_light("Point_Bunker_Cyan_%02d" % i, "POINT", (cx, y, 3.6), CYAN_HEX, CYAN_W, shadow_soft_size=0.15)
    # Bounding fog volume.
    mat = bpy.data.materials.new("M_Fog_Volume")
    nt = _node_tree(mat)
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = FOG_DENSITY
    vol.inputs["Anisotropy"].default_value = FOG_ANISO
    vol.inputs["Color"].default_value = (0.55, 0.62, 0.72, 1.0)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    fog = make_obj("Fog_Volume", [box(-MAP_X - 0.5, -MAP_Y - 0.5, PIT_Z - 0.5, MAP_X + 0.5, MAP_Y + 0.5, 16.0)],
                   "03_Lighting_Volumes", mat, role="fog", suffix="")
    fog.display_type = "WIRE"
    return fog


def set_color_management(scene):
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    vs = scene.view_settings
    vs.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
        try:
            vs.look = look
            break
        except TypeError:
            continue
    else:
        print("Warning: no 'Medium High Contrast' look found; look left as", vs.look)
    world = bpy.data.worlds.new("World_Night_Rain")
    scene.world = world
    nt = _node_tree(world)
    bg = next((n for n in nt.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.008, 0.011, 0.018, 1.0)
        bg.inputs["Strength"].default_value = 1.0
    world.color = (0.008, 0.011, 0.018)


# ---------------------------------------------------------------------------
# UVs: Smart UV Project, then 1 UV unit = 2 m
# ---------------------------------------------------------------------------
def uv_area(me):
    uv = me.uv_layers.active.data
    total = 0.0
    for p in me.polygons:
        pts = [uv[i].uv for i in p.loop_indices]
        a = 0.0
        for j in range(len(pts)):
            x0, y0 = pts[j]
            x1, y1 = pts[(j + 1) % len(pts)]
            a += x0 * y1 - x1 * y0
        total += abs(a) / 2
    return total


def unwrap_all():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.005)
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in meshes:
        me = o.data
        a3, auv = sum(p.area for p in me.polygons), uv_area(me)
        if auv <= 0:
            continue
        k = math.sqrt(a3 / auv) / 2.0          # metres-per-UV -> 2 m per UV unit
        for d in me.uv_layers.active.data:
            d.uv = d.uv * k
        o["uv_m_per_unit"] = round(math.sqrt(a3 / uv_area(me)), 4)
    bpy.ops.object.select_all(action="DESELECT")


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
class Validator:
    def __init__(self, fog):
        bpy.context.view_layer.update()
        self.dg = bpy.context.evaluated_depsgraph_get()
        self.scene = bpy.context.scene
        self.ignore = {fog.name}
        self.fails, self.passes = [], 0

    def check(self, ok, msg):
        if ok:
            self.passes += 1
        else:
            self.fails.append(msg)
            print("FAIL:", msg)

    def ray(self, o, d, dist):
        o, d = Vector(o), Vector(d).normalized()
        travelled = 0.0
        while travelled < dist:
            hit, loc, nrm, _i, ob, _m = self.scene.ray_cast(self.dg, o, d, distance=dist - travelled)
            if not hit:
                return None
            step = (loc - o).length
            if ob.name in self.ignore:
                o = loc + d * 1e-3
                travelled += step + 1e-3
                continue
            return travelled + step, ob.name
        return None

    def dist(self, o, d, dist=200.0):
        r = self.ray(o, d, dist)
        return r[0] if r else None


def world_verts(ob):
    mw = ob.matrix_world
    return [mw @ v.co for v in ob.data.vertices]


def local_extent(ob):
    vs = [v.co for v in ob.data.vertices]
    return [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]


def validate(fog):
    V = Validator(fog)
    objs = {o.name: o for o in bpy.context.scene.objects}
    near = lambda a, b, tol=0.005: abs(a - b) <= tol

    # 1. Collections and naming.
    for cname in ("01_Architecture", "02_Cover_Props", "03_Lighting_Volumes"):
        V.check(cname in bpy.data.collections, "collection %s missing" % cname)
    for cname in ("01_Architecture", "02_Cover_Props"):
        for o in COLL[cname].objects:
            if o.type == "MESH":
                V.check(o.name.endswith("-col") or o.name.endswith("-colonly"), "mesh %s lacks -col suffix" % o.name)

    # 2. Ramps and stairs: slope <= 20 deg, width >= 2.2 m (measured from sloped faces).
    for o in objs.values():
        role = o.get("role")
        if role not in ("ramp", "stair_collider"):
            continue
        mw = o.matrix_world
        rot = mw.to_3x3()
        max_tilt, width = 0.0, 0.0
        for p in o.data.polygons:
            n = (rot @ p.normal).normalized()
            if 0.2 < n.z < 0.9999:
                tilt = math.degrees(math.acos(n.z))
                max_tilt = max(max_tilt, tilt)
                dh = Vector((n.x, n.y, 0)).normalized()
                perp = Vector((-dh.y, dh.x, 0))
                proj = [perp.dot(mw @ o.data.vertices[i].co) for i in p.vertices]
                width = max(width, max(proj) - min(proj))
        V.check(0 < max_tilt <= MAX_SLOPE_DEG + 1e-3, "%s slope %.2f deg" % (o.name, max_tilt))
        V.check(width >= MIN_RAMP_W - 1e-3, "%s width %.2f m" % (o.name, width))
        if o.name.startswith("Ramp_Pit"):
            V.check(near(max_tilt, PIT_RAMP_DEG, 0.05), "%s should be 18 deg, is %.2f" % (o.name, max_tilt))
    for o in objs.values():
        if o.get("role") == "stair":
            ang = math.degrees(math.atan2(o["rise"], o["tread"]))
            V.check(ang <= MAX_SLOPE_DEG and o["width"] >= MIN_RAMP_W, "%s pitch %.1f / width %.2f" % (o.name, ang, o["width"]))

    # 3. Openings measured by rays: width / height and capsule clearance.
    for d in DOORS:
        if d["kind"] == "gap":
            continue
        ax = Vector((1, 0, 0)) if d["axis"] == "x" else Vector((0, 1, 0))
        nrm = Vector((0, 1, 0)) if d["axis"] == "x" else Vector((1, 0, 0))
        floor_z = CATWALK_Z if d["kind"] == "portal" else d["zb"]   # the deck runs through the portal
        base = ax * d["u"] + nrm * d["c"] + Vector((0, 0, floor_z))
        mid = base + Vector((0, 0, min(1.2, (d["zt"] - floor_z) / 2)))
        w = (V.dist(mid, ax, 5) or 99) + (V.dist(mid, -ax, 5) or 99)
        h = V.dist(base + Vector((0, 0, 0.01)), (0, 0, 1), 10)
        h = (h + 0.01) if h else 99
        want_w = {"door": DOOR_W, "breach": 2.4, "portal": 2.6}[d["kind"]]
        V.check(near(w, want_w), "%s %s width %.3f (want %.2f)" % (d["wall"], d["kind"], w, want_w))
        if d["kind"] == "door":
            V.check(near(h, DOOR_H), "%s door height %.3f (want %.2f)" % (d["wall"], h, DOOR_H))
        else:
            V.check(h >= PLAYER_H + 0.2, "%s %s height %.2f" % (d["wall"], d["kind"], h))
        # Clear passage through the wall at capsule width.
        blocked = 0
        for du in (-(w / 2 - PLAYER_R), 0.0, w / 2 - PLAYER_R):
            for z in (0.15, 1.0, 1.75):
                o = base + ax * du + Vector((0, 0, z)) - nrm * (d["t"] / 2 + 0.45)
                if V.ray(o, nrm, d["t"] + 0.9):
                    blocked += 1
        V.check(blocked == 0, "%s %s blocked at %d capsule samples" % (d["wall"], d["kind"], blocked))
    V.check(sum(1 for d in DOORS if d["kind"] == "door") >= 13, "doorway count")

    # 4. Walkable probes: floor height, standing headroom, capsule radius clearance.
    T = TREAD
    probes = [
        ("spawn N", 0, 27, 0), ("spawn S", 0, -27, 0), ("spawn N west exit", -10.5, 25, 0),
        ("spawn S east exit", 10.5, -25, 0), ("plaza N", 0, 15, 0), ("plaza S", 0, -15, 0),
        ("pit floor NE", 8, 6, PIT_Z), ("pit floor SW", -8, -6, PIT_Z), ("pit centre", 0, -2.0, PIT_Z),
        ("container A inside", -5.6, 3.7, PIT_Z + 0.12), ("container B inside", 5.6, -3.7, PIT_Z + 0.12),
        ("ramp N mid", 0, PIT_HY - PIT_RAMP_RUN / 2, PIT_Z / 2), ("ramp S mid", 0, -PIT_HY + PIT_RAMP_RUN / 2, PIT_Z / 2),
        ("corridor S end", -17.0, -17.0, 0), ("corridor -8", -17.0, -8.0, 0), ("corridor under catwalk", -17.0, 0.0, 0),
        ("corridor +8", -17.0, 8.0, 0), ("corridor N end", -17.0, 17.0, 0),
        ("stair hall foot", -21.6, 17.0, 0), ("stair W mid landing", -21.6, 1.2 + 14 * T + 1.2, 2.1),
        ("stair W top landing", -21.6, 0.0, CATWALK_Z), ("catwalk atrium", -17.35, 0, CATWALK_Z),
        ("catwalk west", -9.0, 0, CATWALK_Z), ("catwalk centre", 0, 0, CATWALK_Z), ("catwalk east", 9.0, 0, CATWALK_Z),
        ("catwalk east landing", 13.5, 0, CATWALK_Z), ("stair E mid landing", 13.5, -1.2 - 14 * T - 1.2, 2.1),
        ("breach ledge", -13.3, 0, 0), ("pit landing W", -10.8, 0, 0), ("pit landing E", 10.8, 0, 0),
        ("depot strip", 15.85, -8.0, 0), ("depot centre", 28, 0, 0), ("depot N", 28, 19, 0), ("depot S", 28, -19, 0),
        ("loading dock", 40, 16, DOCK_Z), ("dock ramp mid", 43, 12 - 1.85, 0.6), ("tank alley", 36, -11, 0),
        ("yard NW", -16, 25, 0), ("yard SE", 16, -25, 0), ("yard NE", 25, 25, 0), ("yard SW", -25 + 5, -25, 0),
    ]
    for name, x, y, z in probes:
        top = V.dist((x, y, z + 0.6), (0, 0, -1), 3.0)
        floor = (z + 0.6 - top) if top is not None else None
        tol = 0.06 if "mid" in name and "landing" not in name else 0.005
        ok = floor is not None and abs(floor - z) <= tol
        V.check(ok, "probe %s floor %s (want %.2f)" % (name, "none" if floor is None else "%.3f" % floor, z))
        if not ok:
            continue
        head = V.dist((x, y, floor + 0.01), (0, 0, 1), 5.0)
        V.check(head is None or head >= PLAYER_H, "probe %s headroom %.2f" % (name, head or 0))
        clear = True
        for zc in (0.45, 1.0, PLAYER_H - PLAYER_R):
            for a in range(8):
                ang = a * math.pi / 4
                if V.ray((x, y, floor + zc), (math.cos(ang), math.sin(ang), 0), PLAYER_R):
                    clear = False
        V.check(clear, "probe %s capsule (r=%.2f) blocked" % (name, PLAYER_R))

    # 5. Key dimensions by ray.
    cx = (CORR_X0 + CORR_X1) / 2
    cw = V.dist((cx, -17, 1), (1, 0, 0)) + V.dist((cx, -17, 1), (-1, 0, 0))
    V.check(near(cw, 5.5), "corridor width %.3f" % cw)
    ceil = V.dist((cx, 10, 0.01), (0, 0, 1)) + 0.01
    V.check(near(ceil, BUNKER_CEIL), "corridor ceiling %.3f" % ceil)
    ww = V.dist((0, 0, 4.7), (0, 1, 0)) + V.dist((0, 0, 4.7), (0, -1, 0))
    V.check(near(ww, CATWALK_W), "catwalk clear width %.3f" % ww)
    rail_top = 7.0 - V.dist((2.0, 1.23, 7.0), (0, 0, -1))
    V.check(near(rail_top - CATWALK_Z, RAIL_H), "railing height %.3f" % (rail_top - CATWALK_Z))
    pf = objs["Pit_Floor-col"]
    ex = local_extent(pf)
    V.check(near(ex[0], 24) and near(ex[1], 18) and near(max(v.z for v in world_verts(pf)), PIT_Z),
            "pit floor %s" % ex)

    # 6. Cover, walls, props.
    for o in objs.values():
        role = o.get("role")
        if o.type != "MESH" or role is None:
            continue
        ex = local_extent(o)
        if role == "cover_waist":
            V.check(near(ex[2], WAIST_H) and near(min(ex[0], ex[1]), WAIST_T), "%s waist cover %s" % (o.name, ex))
        elif role == "cover_glitch":
            V.check(near(ex[2], GLITCH_H) and near(min(ex[0], ex[1]), WAIST_T), "%s glitch cover %s" % (o.name, ex))
        elif role == "los_wall":
            V.check(near(ex[2], LOS_H) and near(min(ex[0], ex[1]), LOS_T), "%s LOS wall %s" % (o.name, ex))
        elif role == "rack":
            V.check(near(ex[0], RACK[0]) and near(ex[1], RACK[1]) and near(ex[2], RACK[2]), "%s rack %s" % (o.name, ex))
        elif role == "tank":
            V.check(near(ex[0], 2 * TANK_R) and near(ex[2], TANK_H), "%s tank %s" % (o.name, ex))
        elif role == "container":
            V.check(near(ex[0], CONT_L) and near(ex[1], CONT_W) and near(ex[2], CONT_H), "%s container %s" % (o.name, ex))
            V.check(o["interior_w"] >= 2 * PLAYER_R and o["interior_h"] >= PLAYER_H, "%s interior" % o.name)
    racks = sorted((o for o in objs.values() if o.get("role") == "rack"), key=lambda o: o.location.y)
    gaps = {round(b.location.y - a.location.y, 3) for a, b in zip(racks, racks[1:])}
    sides = [o.location.x > cx for o in racks]
    V.check(gaps == {RACK_STEP} and all(a != b for a, b in zip(sides, sides[1:])), "rack spacing/stagger %s" % gaps)
    jerseys = [o for o in objs.values() if o.get("kind") == "jersey"]
    V.check(len(jerseys) == 6, "jersey barrier count %d" % len(jerseys))
    for xl in (25.5, 27.0, 28.0, 29.0, 30.5):   # the 42 m depot sightline must be broken
        V.check(V.ray((xl, -21, 0.9), (0, 1, 0), 42.0) is not None, "depot sightline x=%.0f unbroken" % xl)
    rot = {o.name: round(math.degrees(o.rotation_euler.z), 3) for o in objs.values() if o.get("role") == "container"}
    V.check(sorted(rot.values()) == [-15.0, 22.0], "container rotations %s" % rot)

    # 7. No spawn-to-spawn sightlines (eye and crouch height).
    blocked = total = 0
    pts = [(x, y) for x in (-8.5, -4, 0, 4, 8.5) for y in (22.6, 27.0, 31.4)]
    for h in (EYE_H, CROUCH_H):
        for ax_, ay in pts:
            for bx, by in pts:
                a, b = Vector((ax_, ay, h)), Vector((bx, -by, h))
                total += 1
                if V.ray(a, b - a, (b - a).length):
                    blocked += 1
    V.check(blocked == total, "spawn sightlines open: %d of %d" % (total - blocked, total))

    # 8. Bounds.
    for o in objs.values():
        if o.type == "MESH" and o.get("role") not in ("fog",):
            for v in world_verts(o):
                if abs(v.x) > MAP_X + 0.31 or abs(v.y) > MAP_Y + 0.31:
                    V.check(False, "%s outside 90 x 64 bounds at %s" % (o.name, tuple(round(c, 2) for c in v)))
                    break

    # 9. Lighting.
    lights = [o for o in objs.values() if o.type == "LIGHT"]
    floods = [o for o in lights if o.data.type == "AREA"]
    cyans = [o for o in lights if o.data.type == "POINT"]
    suns = [o for o in lights if o.data.type == "SUN"]
    V.check(len(floods) == 6 and all(near(o.data.energy, FLOOD_W) and near(o.data.size, FLOOD_SIZE) for o in floods), "floodlights")
    V.check(len(cyans) == 4 and all(near(o.data.energy, CYAN_W) for o in cyans), "bunker cyan lights")
    if suns:
        d = suns[0].matrix_world.to_3x3() @ Vector((0, 0, 1))
        el = math.degrees(math.asin(d.z))
        az = math.degrees(math.atan2(d.x, d.y)) % 360
        V.check(len(suns) == 1 and near(el, SUN_ELEV, 0.01) and near(az, SUN_AZ, 0.01), "sun el %.2f az %.2f" % (el, az))
    else:
        V.check(False, "no sun")
    uvd = [o.get("uv_m_per_unit", 0) for o in objs.values() if o.type == "MESH"]
    V.check(all(near(u, 2.0, 0.01) for u in uvd), "UV density off on %d meshes" % sum(not near(u, 2.0, 0.01) for u in uvd))

    print("Validation: %d passed, %d failed" % (V.passes, len(V.fails)))
    return not V.fails


# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
def render_topdown(path, fog):
    scene = bpy.context.scene
    hidden = [o for o in scene.objects if o.get("role") in ("roof", "fog")]
    for o in hidden:
        o.hide_render = True
    cam_data = bpy.data.cameras.new("Cam_TopDown_Check")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2 * MAP_X + 2
    cam = bpy.data.objects.new("Cam_TopDown_Check", cam_data)
    cam.location = (0, 0, 60)
    scene.collection.objects.link(cam)
    scene.camera = cam
    prev = (scene.render.engine, scene.view_settings.view_transform, scene.view_settings.look)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.view_settings.view_transform = "Standard"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.show_object_outline = True
    sh.show_shadows = True
    scene.render.resolution_x = 1840
    scene.render.resolution_y = int(1840 * (2 * MAP_Y + 2) / (2 * MAP_X + 2))
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("Exported:", path)
    scene.render.engine, scene.view_settings.view_transform = prev[0], prev[1]
    try:
        scene.view_settings.look = prev[2]
    except TypeError:
        pass
    for o in hidden:
        o.hide_render = False
    bpy.data.objects.remove(cam)


def export_glb(path, fog):
    """Geometry + spawn empties only: the game (PvpMapArena) builds its own lights,
    fog and materials for this map, and glTF cannot carry area lights or volumes."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.objects:
        if o is not fog and o.type in ("MESH", "EMPTY"):
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              use_selection=True, export_extras=True, export_materials="EXPORT")
    print("Exported:", path)


def main():
    opts = parse_args()
    clear_scene()
    M = build_materials()
    build_ground(M)
    build_pit(M)
    build_courtyard_props(M)
    build_bunker(M)
    build_catwalk(M)
    build_depot(M)
    build_spawns_and_yards(M)
    fog = build_lighting()
    set_color_management(bpy.context.scene)
    unwrap_all()
    ok = validate(fog)
    if opts["blend"]:
        os.makedirs(os.path.dirname(opts["blend"]), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=opts["blend"])
        print("Exported:", opts["blend"])
    if opts["glb"]:
        os.makedirs(os.path.dirname(opts["glb"]), exist_ok=True)
        export_glb(opts["glb"], fog)
    if opts["render"]:
        os.makedirs(os.path.dirname(opts["render"]), exist_ok=True)
        render_topdown(opts["render"], fog)
    if not ok:
        print("Error: substation blockout failed validation")
        sys.exit(1)
    print("Substation blockout OK")


if __name__ == "__main__":
    main()
