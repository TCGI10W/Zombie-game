"""Sixth batch: the last rigid-pivot holdouts rebuilt to sit next to the
skinned v5 characters, plus a model of its own for the Volt Phantom.

  bloater / survivor -> real armature. Bones keep the joint names the game
    already speaks (Hips, Spine, ... FootR), so SkinRigAdapter makes the
    proxies and ZombieRig drives them with no code changes.
  hound / 5 bosses   -> joint pivots with the exact names the enemy scripts
    look up (HoundEnemy.PIVOTS and Torso/Head/ArmL/ArmR/LegL/LegR). Bosses
    never build a rig, they rotate those pivots, so positions stay put.

Run:
  blender -b --factory-startup -P tools/generate_characters_v6.py \
      [-- bloater survivor hound gun gorilla necro panzer phantom]
Convention: +Y forward (-Z in Godot), +Z up. Pivots sit on joints.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_characters_v5 as v5  # noqa: E402
from generate_models import add_pivot, export_glb, make_mat  # noqa: E402
from generate_models_v3 import R90, add, ball, blob, box, cyl, props_mats, seg, torus  # noqa: E402
from generate_models_v3 import clear_scene as _clear  # noqa: E402
from generate_models_v4 import merge_per_pivot  # noqa: E402

V = Vector
sball = v5.ball


def clear_scene():
    _clear()


def neon(name, col, strength, roughness=0.25):
    return make_mat(name, (*col, 1), roughness=roughness, emission=col, emission_strength=strength)


def join_all(objs, name):
    if not objs:
        return None
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def bind_skinned(obj, arm, j, region=None, force=None):
    v5.weigh(obj, j, region, force)
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def merge_by_bone(gear, name):
    """gear: [(obj, bone), ...] -> one mesh per bone, fewer draw calls."""
    groups = {}
    for obj, bone in gear:
        groups.setdefault(bone, []).append(obj)
    out = []
    for bone, objs in groups.items():
        out.append((join_all(objs, "%s_%s" % (name, bone)), bone))
    return out


# ---------------------------------------------------------------------------
# Surface helpers. skin_body/blob run the cage through subsurf, which pulls
# the real surface a few centimetres inside the nominal radii - details
# placed on those radii end up hovering in mid-air. These snap them onto the
# mesh that actually got built.
# ---------------------------------------------------------------------------
def _ev(target):
    dg = bpy.context.evaluated_depsgraph_get()
    return target.evaluated_get(dg), dg


def surface_point(p, targets, inset=0.0, limit=1e9):
    """Nearest point on any of `targets` (mesh objects) to world point p.
    `limit` guards against a part that starts deep inside the mesh being
    dragged across it to the far side."""
    p = V(p)
    best = None
    for t in targets:
        if t is None or not isinstance(t.data, bpy.types.Mesh):
            continue
        ev, dg = _ev(t)
        ok, loc, nrm, _ = ev.closest_point_on_mesh(ev.matrix_world.inverted() @ p, depsgraph=dg)
        if not ok:
            continue
        w = ev.matrix_world @ V(loc)
        d = (w - p).length
        if best is None or d < best[0]:
            n = (ev.matrix_world.to_3x3() @ V(nrm)).normalized()
            best = (d, w, n)
    if best is None or best[0] > limit:
        return p
    return best[1] - best[2] * inset


def _world_center(obj):
    """Where the part actually is. The v3 helpers keep the object origin at
    the pivot and bake the offset into the mesh, so matrix_world.translation
    is NOT the part's position - the bounding box is."""
    ev, _ = _ev(obj)
    bb = [ev.matrix_world @ V(c) for c in ev.bound_box]
    return sum(bb, V((0.0, 0.0, 0.0))) / 8.0


def snap(obj, targets, inset=0.0, limit=0.22):
    c = _world_center(obj)
    obj.matrix_world.translation += surface_point(c, targets, inset, limit) - c
    return obj


def radial_snap(obj, center, targets, protrude=0.0):
    """Snap onto the surface along the ray from `center`: walk the point back
    until it is near the mesh, then sit it there. Details thrown wide of a
    bulging belly would otherwise be left hovering where they were placed."""
    c, p = V(center), _world_center(obj)
    for _ in range(12):
        q = surface_point(p, targets, 0.0)
        if (q - p).length < 0.12:
            p = q
            break
        p = c + (p - c) * 0.85
    obj.matrix_world.translation += surface_point(p, targets, -protrude) - _world_center(obj)
    return obj


# ---------------------------------------------------------------------------
# BLOATER (skinned: same bones as the v5 characters, swollen anatomy)
# ---------------------------------------------------------------------------
def build_bloater():
    clear_scene()
    rnd = random.Random(31)
    j = v5.joints(1.12, 1.18) # wide shoulders, normal legs -> the rig's IK is unchanged
    arm = v5.build_armature(j)

    m_skin = make_mat("BloaterSkin", (0.44, 0.52, 0.3, 1), roughness=0.6, tex_prefix="zombie_skin")
    m_belly = make_mat("BloaterBelly", (0.58, 0.62, 0.34, 1), roughness=0.38, tex_prefix="zombie_skin")
    m_pus = neon("BloaterPustule", (0.36, 0.92, 0.12), 1.2, 0.25)
    m_vein = make_mat("BloaterVein", (0.11, 0.06, 0.05, 1), roughness=0.5)
    m_bone = make_mat("BloaterBone", (0.4, 0.35, 0.24, 1), roughness=0.55)
    m_dark = make_mat("BloaterSocket", (0.02, 0.02, 0.02, 1), roughness=0.9)
    m_eye = neon("BloaterEye", (0.62, 1.0, 0.2), 2.0, 0.2)
    m_rags = make_mat("BloaterRags", (0.13, 0.12, 0.09, 1), roughness=0.95, tex_prefix="fabric")
    m_pants = make_mat("BloaterTrousers", (0.17, 0.16, 0.14, 1), roughness=0.9, tex_prefix="denim")
    m_gore = make_mat("BloaterGore", (0.05, 0.008, 0.006, 1), roughness=0.4)

    nodes = [
        (V((0, 0.0, 0.86)), (0.26, 0.24)), # pelvis, as wide as the belly
        (V((0, 0.03, 1.02)), (0.3, 0.28)), # waist
        (V((0, 0.10, 1.19)), (0.335, 0.32)), # the belly
        (V((0, 0.05, 1.36)), (0.28, 0.25)), # chest
        (V((0, 0.0, 1.47)), (0.225, 0.165)), # upper chest, sunk into the shoulders
        (V((0, 0.025, 1.52)), (0.095, 0.088)), # neck base
        (V((0, 0.045, 1.63)), (0.08, 0.078)), # neck top
    ]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
    for sx, nm in ((-1, "L"), (1, "R")):
        i0 = len(nodes)
        sh, el, hn = j["UpperArm" + nm], j["Forearm" + nm], j["Hand" + nm]
        nodes += [
            (V((sx * 0.15, -0.005, 1.5)), (0.1, 0.09)), # trapezius
            (sh, (0.1, 0.097)),
            (sh.lerp(el, 0.5), (0.085, 0.09)),
            (el, (0.072, 0.074)),
            (el.lerp(hn, 0.45), (0.07, 0.062)),
            (hn, (0.042, 0.032)),
            (hn + V((0, 0.012, -0.07)), (0.05, 0.02)), # palm
        ]
        edges += [(4, i0)] + [(i0 + k, i0 + k + 1) for k in range(6)]
        palm = i0 + 6
        for f in range(3): # stubby clawed fingers
            base = hn + V((sx * (f - 1) * 0.018, 0.02, -0.1))
            k = len(nodes)
            nodes += [(base, (0.012, 0.011)),
                      (base + V((0, 0.022, -0.05)), (0.01, 0.009)),
                      (base + V((0, 0.05, -0.075)), (0.007, 0.006))]
            edges += [(palm, k), (k, k + 1), (k + 1, k + 2)]
        i1 = len(nodes)
        hp, kn, an = j["Thigh" + nm], j["Shin" + nm], j["Foot" + nm]
        nodes += [
            (hp + V((0, 0, -0.04)), (0.155, 0.16)),
            (hp.lerp(kn, 0.5), (0.135, 0.14)),
            (kn, (0.095, 0.1)),
            (kn.lerp(an, 0.35) + V((0, -0.014, 0)), (0.09, 0.095)),
            (an + V((0, 0, 0.03)), (0.055, 0.06)),
            (an + V((0, 0.07, -0.05)), (0.06, 0.04)),
            (an + V((0, 0.16, -0.075)), (0.05, 0.028)),
        ]
        edges += [(0, i1)] + [(i1 + k, i1 + k + 1) for k in range(6)]

    body = v5.skin_body(nodes, edges, "Body", subsurf=2)
    v5.bump_noise(body, 0.0075, 11.0, 3) # stretched, blistered skin
    body.data.materials.append(m_skin)
    v5.uv_and_smooth(body)

    # --- split surfaces: the belly is shiny and drum-tight -----------------
    cloth = [v5.cloth_from(body, "BellyPatch", lambda c: 1.0 < c.z < 1.34 and c.y > 0.02, 0.006, m_belly, 0.0, 21),
             v5.cloth_from(body, "TrousersMesh", lambda c: c.z < 1.0 and c.z > 0.2 and abs(c.x) < 0.3, 0.012, m_pants, 0.3, 22),
             v5.cloth_from(body, "RagMesh", lambda c: 1.2 < c.z < 1.5 and (c.y < -0.02 or abs(c.x) > 0.14), 0.012, m_rags, 0.55, 23)]
    for c in cloth:
        v5.uv_and_smooth(c)

    # --- head --------------------------------------------------------------
    # The features sit just proud of the skull ellipsoid (centre y 0.05,
    # front 0.163), otherwise subsurf swallows them.
    parts = [sball("Skull", (0, 0.05, 1.72), (0.1, 0.113, 0.113), m_skin, 28, 20),
             sball("Face", (0, 0.105, 1.69), (0.078, 0.06, 0.064), m_skin, 22, 14),
             sball("Brow", (0, 0.15, 1.752), (0.072, 0.022, 0.015), m_skin, 20, 12),
             sball("Nose", (0, 0.168, 1.706), (0.014, 0.017, 0.022), m_skin, 12, 10),
             sball("JawMesh", (0, 0.118, 1.638), (0.062, 0.05, 0.028), m_belly, 20, 14)]
    for o in parts:
        v5.uv_and_smooth(o)
    for sx, nm in ((-1, "L"), (1, "R")):
        parts.append(sball("Socket" + nm, (sx * 0.04, 0.152, 1.742), (0.021, 0.012, 0.015), m_dark, 14, 10))
        parts.append(sball("Eye" + nm, (sx * 0.04, 0.162, 1.742), (0.01, 0.007, 0.009), m_eye, 12, 8))
        parts.append(sball("Ear" + nm, (sx * 0.104, 0.045, 1.71), (0.012, 0.024, 0.033), m_skin, 12, 8))
    for i in range(4):
        parts.append(sball("Tooth%d" % i, (-0.022 + i * 0.015, 0.17, 1.656), (0.005, 0.004, 0.009), m_bone, 8, 6))

    # --- weeping pustules, veins and burst wounds --------------------------
    # Placed on the drum-tight belly/chest ellipsoid, then snapped onto the
    # subsurfaced body so nothing floats off the skin.
    details = []
    for parent_c, radii, count, front in ((( 0, 0.13, 1.19), (0.335, 0.33, 0.32), 12, True),
                                          ((0, 0.02, 1.4), (0.27, 0.25, 0.19), 6, False),
                                          ((0, -0.02, 1.5), (0.2, 0.14, 0.1), 3, False)):
        for _ in range(count):
            th = rnd.uniform(-1.35, 1.35) if front else rnd.uniform(-math.pi, math.pi)
            ph = rnd.uniform(-0.6, 0.7)
            d = V((math.sin(th) * math.cos(ph), math.cos(th) * math.cos(ph), math.sin(ph)))
            r = rnd.uniform(0.022, 0.05)
            p = sball("Pus", (parent_c[0] + radii[0] * d.x, parent_c[1] + radii[1] * d.y,
                              parent_c[2] + radii[2] * d.z), (r, r, r * 0.82), m_pus, 12, 8)
            details.append(radial_snap(p, parent_c, [body], 0.35 * r))
    for i in range(7):
        a = -1.15 + i * 0.38
        v1 = surface_point((math.sin(a) * 0.32, 0.13 + math.cos(a) * 0.31, 1.36), [body], 0.006)
        v2 = surface_point((math.sin(a + 0.24) * 0.34, 0.13 + math.cos(a + 0.24) * 0.33, 1.02), [body], 0.006)
        details.append(seg("Vein%d" % i, v1, v2, 0.011, 0.007, m_vein, verts=6))
    for sx, nm in ((-1, "L"), (1, "R")):
        details.append(radial_snap(sball("Gash" + nm, (sx * 0.26, 0.16, 1.24),
                                         (0.05, 0.05, 0.03), m_gore, 12, 8), (sx * 0.2, 0.1, 1.2), [body], -0.01))
        details.append(radial_snap(sball("ArmBlister" + nm, (sx * 0.33, 0.04, 1.28),
                                         (0.035, 0.035, 0.03), m_pus, 12, 8), (sx * 0.26, 0.02, 1.3), [body], 0.012))
    # A split in the belly the gas got out through
    details.append(snap(sball("BellySplit", (0.05, 0.42, 1.14), (0.06, 0.03, 0.045), m_gore, 14, 10),
                        [body], 0.006))
    for i in range(5):
        details.append(radial_snap(sball("Drip%d" % i, (0.05 + rnd.uniform(-0.02, 0.02), 0.44, 1.08 - i * 0.05),
                                        (0.012, 0.012, 0.02), m_pus, 8, 6), (0.05, 0.3, 1.05), [body], 0.004))
    details = join_all(details, "SkinDetails")
    v5.uv_and_smooth(details)

    extra = [sball("Collar", (0, 0.02, 1.52), (0.13, 0.14, 0.05), m_rags, 16, 10)]

    meshes = [body, details] + cloth + extra
    for msh in meshes:
        bind_skinned(msh, arm, j, v5.body_region)
    for p in parts:
        if p.name.startswith(("Tooth", "Jaw")):
            bind_skinned(p, arm, j, force="Jaw")
        else:
            bind_skinned(p, arm, j, v5.head_region)
    export_glb("zombie_bloater.glb")


# ---------------------------------------------------------------------------
# SURVIVOR (v5 body + field gear)
# ---------------------------------------------------------------------------
def build_survivor():
    orig = v5.export_glb
    v5.export_glb = lambda name: None # build the body, keep everything in the scene
    try:
        v5.build_character("survivor")
    finally:
        v5.export_glb = orig
    arm = bpy.data.objects["Armature"]
    j = v5.joints(1.0, 1.08)

    m_canvas = make_mat("PackCanvas", (0.2, 0.18, 0.13, 1), roughness=0.9, tex_prefix="burlap")
    m_leather = make_mat("GearLeather", (0.14, 0.09, 0.06, 1), roughness=0.65, tex_prefix="leather")
    m_steel = make_mat("GearSteel", (0.3, 0.31, 0.33, 1), metallic=0.8, roughness=0.4, tex_prefix="gunmetal")
    m_camo = make_mat("GearCamo", (0.22, 0.24, 0.17, 1), roughness=0.9, tex_prefix="camo")
    m_brass = make_mat("Brass", (0.45, 0.34, 0.16, 1), metallic=0.7, roughness=0.4)
    m_glass = make_mat("GoggleGlass", (0.05, 0.09, 0.11, 1), metallic=0.4, roughness=0.08)
    m_patch = neon("UnitPatch", (0.15, 0.85, 0.9), 1.4, 0.5)
    m_lens = neon("RadioLens", (1.0, 0.35, 0.08), 1.8, 0.3)

    g = [] # (object, bone)
    # --- rucksack ----------------------------------------------------------
    g += [(box("PackBody", (0, -0.235, 1.3), (0.36, 0.17, 0.42), m_canvas, rot=(math.radians(-4), 0, 0)), "Chest"),
          (box("PackFlap", (0, -0.3, 1.47), (0.34, 0.09, 0.14), m_canvas, rot=(math.radians(20), 0, 0)), "Chest"),
          (box("PackPocket", (0, -0.325, 1.22), (0.26, 0.05, 0.2), m_leather), "Chest"),
          (cyl("Bedroll", (0, -0.31, 1.55), 0.062, 0.38, m_camo, rot=(0, R90, 0)), "Chest"),
          (box("BedrollStrap", (0.11, -0.31, 1.55), (0.03, 0.15, 0.15), m_leather), "Chest"),
          (box("BedrollStrap", (-0.11, -0.31, 1.55), (0.03, 0.15, 0.15), m_leather), "Chest"),
          (ball("Canteen", (-0.2, -0.24, 1.24), (0.055, 0.045, 0.07), m_canvas), "Chest"),
          (box("Radio", (0.19, -0.26, 1.4), (0.09, 0.08, 0.15), m_steel), "Chest"),
          (ball("RadioLensA", (0.19, -0.3, 1.45), (0.016, 0.016, 0.016), m_lens), "Chest"),
          (seg("Antenna", (0.22, -0.26, 1.48), (0.27, -0.36, 1.76), 0.008, 0.004, m_steel, verts=6), "Chest"),
          # shoulder straps
          (box("Strap", (-0.1, 0.155, 1.36), (0.055, 0.035, 0.34), m_leather, rot=(math.radians(8), 0.06, 0)), "Chest"),
          (box("Strap", (0.1, 0.155, 1.36), (0.055, 0.035, 0.34), m_leather, rot=(math.radians(8), -0.06, 0)), "Chest"),
          (box("StrapBuckle", (0.03, 0.175, 1.34), (0.05, 0.02, 0.045), m_brass), "Chest"),
          # bandolier of cartridges across the chest
          (box("Sling", (0.0, 0.168, 1.28), (0.32, 0.025, 0.05), m_leather, rot=(0, math.radians(38), 0)), "Chest")]
    for i in range(7):
        t = i / 6.0
        g.append((box("Shell%d" % i, (-0.15 + 0.3 * t, 0.185, 1.38 - 0.2 * t), (0.032, 0.028, 0.055),
                      m_brass, rot=(0, math.radians(38), 0)), "Chest"))
    g.append((sball("Patch", (-0.29, 0.03, 1.42), (0.035, 0.012, 0.035), m_patch), "UpperArmL"))
    # --- belt and hips -----------------------------------------------------
    g += [(box("Ammo pouch", (-0.15, 0.11, 1.03), (0.1, 0.075, 0.12), m_canvas), "Hips"),
          (box("Ammo pouch", (0.15, 0.11, 1.03), (0.1, 0.075, 0.12), m_canvas), "Hips"),
          (box("Entrenching", (-0.19, -0.06, 1.02), (0.07, 0.06, 0.3), m_leather, rot=(math.radians(6), 0, 0)), "Hips"),
          (box("Bayonet scabbard", (0.2, -0.02, 1.0), (0.05, 0.05, 0.26), m_steel, rot=(math.radians(8), 0, 0)), "Hips"),
          (box("Belt buckle", (0, 0.185, 1.03), (0.055, 0.02, 0.05), m_brass), "Hips")]
    # --- thighs, shins, hands ---------------------------------------------
    for sx, nm in ((-1, "L"), (1, "R")):
        hp, kn, an = j["Thigh" + nm], j["Shin" + nm], j["Hand" + nm]
        g.append((box("ThighPouch", (sx * 0.13, 0.075, 0.78), (0.1, 0.075, 0.16), m_canvas), "Thigh" + nm))
        g.append((box("KneePad", (sx * 0.118, 0.075, 0.52), (0.085, 0.035, 0.09), m_leather), "Shin" + nm))
        g.append((ball("Glove", (an.x, 0.02, an.z - 0.02), (0.05, 0.045, 0.062), m_leather), "Hand" + nm))
        g.append((box("WristStrap", (an.x, 0.02, an.z + 0.045), (0.055, 0.05, 0.02), m_leather), "Hand" + nm))
        # spare magazine on the boot
        g.append((box("BootMag", (sx * 0.12, 0.09, 0.28), (0.045, 0.035, 0.11), m_steel), "Shin" + nm))
    # --- helmet: rim, chin strap, goggles, foliage band --------------------
    hc = (0, 0.025, 1.79)
    g += [(torus("HelmetRim", (hc[0], hc[1], 1.735), 0.128, 0.014, m_steel), "Head"),
          (torus("FoliageBand", (hc[0], hc[1], 1.77), 0.132, 0.02, m_camo), "Head"),
          (box("GoggleLens", (-0.05, 0.15, 1.775), (0.05, 0.028, 0.038), m_glass, rot=(math.radians(-12), 0, 0)), "Head"),
          (box("GoggleLens", (0.05, 0.15, 1.775), (0.05, 0.028, 0.038), m_glass, rot=(math.radians(-12), 0, 0)), "Head"),
          (box("GoggleBridge", (0, 0.175, 1.778), (0.03, 0.02, 0.02), m_leather), "Head"),
          (seg("ChinStrap", (-0.115, 0.02, 1.74), (-0.03, 0.09, 1.65), 0.008, 0.008, m_leather, verts=6), "Head"),
          (seg("ChinStrap", (0.115, 0.02, 1.74), (0.03, 0.09, 1.65), 0.008, 0.008, m_leather, verts=6), "Head"),
          (box("Rank tab", (0, -0.13, 1.62), (0.09, 0.02, 0.05), m_camo), "Chest")]
    # folded gas mask hanging off the left shoulder
    g += [(ball("MaskBag", (-0.2, -0.02, 1.2), (0.075, 0.06, 0.085), m_canvas), "Chest"),
          (cyl("MaskFilter", (-0.2, 0.05, 1.19), 0.03, 0.05, m_steel, rot=(R90, 0, 0)), "Chest")]

    # --- hug the gear onto the body ----------------------------------------
    # The v5 torso is a subsurfaced cage, so gear placed on the nominal radii
    # hovers a few centimetres off the vest/trousers. Slide each piece onto
    # the mesh that is actually there.
    vest = bpy.data.objects.get("VestMesh")
    shirt = bpy.data.objects.get("ShirtMesh")
    pants = bpy.data.objects.get("PantsMesh")
    body_m = bpy.data.objects.get("Body")
    torso = [f for f in (vest, shirt, body_m) if f]
    legs = [f for f in (pants, body_m) if f]
    for obj, bone in g:
        if obj is None or bone == "Head" or obj.name.startswith("Antenna"):
            continue
        forms = legs if bone.startswith(("Thigh", "Shin", "Foot")) or bone == "Hips" else torso
        snap(obj, forms, -0.012)

    gear = merge_by_bone(g, "Gear")
    for obj, bone in gear:
        if obj is None:
            continue
        v5.uv_and_smooth(obj)
        bind_skinned(obj, arm, j, force=bone)
    export_glb("player_survivor.glb")


# ---------------------------------------------------------------------------
# BLIGHT HOUND (rigid pivots: HoundEnemy.PIVOTS, positions unchanged)
# ---------------------------------------------------------------------------
def build_hound():
    clear_scene()
    m_fur = make_mat("HoundFur", (0.19, 0.16, 0.14, 1), roughness=0.95, tex_prefix="gorilla_hide")
    m_hide = make_mat("HoundHide", (0.36, 0.24, 0.2, 1), roughness=0.7, tex_prefix="zombie_skin")
    m_bone = make_mat("HoundBone", (0.42, 0.37, 0.27, 1), roughness=0.55)
    m_gore = make_mat("HoundGore", (0.07, 0.008, 0.006, 1), roughness=0.3)
    m_claw = make_mat("HoundClaw", (0.05, 0.045, 0.04, 1), roughness=0.45)
    m_teeth = make_mat("HoundTeeth", (0.66, 0.6, 0.45, 1), roughness=0.4)
    m_ember = neon("HoundEmber", (1.0, 0.34, 0.05), 4.5, 0.4)
    m_eye = neon("HoundEye", (1.0, 0.5, 0.1), 6.0, 0.2)
    m_iron = make_mat("HoundIron", (0.24, 0.22, 0.2, 1), metallic=0.75, roughness=0.5, tex_prefix="rusted_metal")

    root = add_pivot("Root", (0, 0, 0))
    body = add_pivot("Body", (0, 0, 0.66), parent=root)

    # Starved ribcage front, heavy rump, sagging belly
    ball("ChestMesh", (0, 0.24, 0.7), (0.17, 0.235, 0.2), m_fur, body)
    ball("Rump", (0, -0.42, 0.71), (0.155, 0.2, 0.165), m_fur, body)
    ball("Waist", (0, -0.1, 0.68), (0.115, 0.24, 0.13), m_hide, body)
    blob("Brisket", (0, 0.38, 0.56), (0.23, 0.2, 0.19), m_fur, body, subsurf=2)
    ball("BellySag", (0, 0.02, 0.52), (0.11, 0.24, 0.1), m_hide, body)
    ball("ShoulderHump", (0, 0.16, 0.86), (0.16, 0.2, 0.11), m_fur, body)
    forms = [o for o in bpy.data.objects if o.name in
             ("ChestMesh", "Rump", "Waist", "Brisket", "BellySag", "ShoulderHump")]
    for sx, nm in ((-1, "L"), (1, "R")):
        for i in range(5):
            y = -0.22 + i * 0.085
            seg("Rib%s%d" % (nm, i), (sx * 0.1, y, 0.79), (sx * 0.125, y + 0.03, 0.55), 0.012, 0.008, m_bone, body, verts=6)
        seg("Flank%s" % nm, (sx * 0.13, -0.34, 0.78), (sx * 0.115, -0.1, 0.62), 0.014, 0.009, m_hide, body, verts=6)
        seg("Vein%s" % nm, (sx * 0.14, -0.5, 0.76), (sx * 0.125, -0.26, 0.66), 0.009, 0.005, m_ember, body, verts=6)
        seg("VeinB%s" % nm, (sx * 0.165, 0.12, 0.78), (sx * 0.15, 0.34, 0.62), 0.008, 0.005, m_ember, body, verts=6)
        radial_snap(ball("Gash%s" % nm, (sx * 0.155, 0.06, 0.66), (0.028, 0.085, 0.048), m_gore, body),
                    (0, 0.06, 0.68), forms, -0.006)
        # scrap-iron harness bolted to the flanks
        radial_snap(box("ArmorScrap%s" % nm, (sx * 0.175, -0.16, 0.8), (0.03, 0.26, 0.16), m_iron, body,
                        rot=(0, math.radians(12 * sx), 0), bevel=0.008), (0, -0.16, 0.74), forms, -0.004)
    for i in range(5):
        ball("Vertebra%d" % i, (0, -0.3 + i * 0.1, 0.835 - abs(i - 2) * 0.008), (0.02, 0.03, 0.022), m_bone, body)
        box("SpineSpike%d" % i, (0, -0.3 + i * 0.1, 0.875 - abs(i - 2) * 0.008), (0.014, 0.05, 0.05), m_bone, body,
            rot=(math.radians(-25), 0, 0), bevel=0.006)
    # broken chain and collar around the throat
    torus("Collar", (0, 0.34, 0.79), 0.145, 0.022, m_iron, body, rot=(R90, 0, 0), seg_major=18)
    box("Tag", (0, 0.44, 0.7), (0.035, 0.006, 0.05), m_iron, body, bevel=0.004)

    neck = add_pivot("Neck", (0, 0.4, 0.78), parent=body)
    seg("NeckMesh", (0, 0.36, 0.74), (0, 0.58, 0.9), 0.125, 0.09, m_fur, neck)
    seg("NeckSinew", (0, 0.42, 0.69), (0, 0.6, 0.84), 0.055, 0.038, m_hide, neck, verts=8)
    head = add_pivot("Head", (0, 0.6, 0.9), parent=neck)
    ball("Cranium", (0, 0.65, 0.94), (0.118, 0.132, 0.105), m_fur, head)
    blob("Muzzle", (0, 0.85, 0.895), (0.115, 0.24, 0.09), m_hide, head, subsurf=2)
    ball("NoseTip", (0, 0.965, 0.9), (0.034, 0.028, 0.026), m_claw, head)
    blob("Brow", (0, 0.745, 0.975), (0.18, 0.065, 0.04), m_fur, head, subsurf=2)
    box("EarGuardL", (-0.1, 0.6, 0.95), (0.03, 0.1, 0.08), m_iron, head, rot=(0, math.radians(-12), 0), bevel=0.006)
    box("EarGuardR", (0.1, 0.6, 0.95), (0.03, 0.1, 0.08), m_iron, head, rot=(0, math.radians(12), 0), bevel=0.006)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Eye" + nm, (sx * 0.058, 0.755, 0.958), (0.02, 0.015, 0.015), m_eye, head)
        seg("Ear" + nm, (sx * 0.072, 0.6, 0.99), (sx * 0.115, 0.53, 1.15), 0.042, 0.007, m_fur, head, verts=6)
        for i in range(4):
            y = 0.8 + i * 0.038
            seg("UTooth%s%d" % (nm, i), (sx * 0.046, y, 0.865), (sx * 0.044, y, 0.826), 0.009, 0.002, m_teeth, head, verts=5)
        seg("Fang" + nm, (sx * 0.036, 0.93, 0.875), (sx * 0.034, 0.935, 0.806), 0.012, 0.002, m_teeth, head, verts=5)
    ball("MouthGlow", (0, 0.81, 0.858), (0.05, 0.115, 0.022), m_ember, head)
    jaw = add_pivot("Jaw", (0, 0.68, 0.86), parent=head)
    blob("JawMesh", (0, 0.81, 0.822), (0.095, 0.22, 0.05), m_hide, jaw, subsurf=2)
    for sx, nm in ((-1, "L"), (1, "R")):
        for i in range(3):
            y = 0.81 + i * 0.042
            seg("LTooth%s%d" % (nm, i), (sx * 0.042, y, 0.838), (sx * 0.041, y, 0.868), 0.008, 0.002, m_teeth, jaw, verts=5)

    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * 0.13, 0.3, 0.68)
        el = (sx * 0.14, 0.33, 0.36)
        wr = (sx * 0.13, 0.36, 0.1)
        up = add_pivot("FrontUpper" + nm, sh, parent=body)
        ball("Shoulder" + nm, (sx * 0.128, 0.3, 0.61), (0.075, 0.125, 0.155), m_fur, up)
        seg("FrontUpperMesh" + nm, sh, el, 0.078, 0.056, m_fur, up)
        seg("ForelegTendon" + nm, add(sh, (0, 0.03, -0.06)), add(el, (0, 0.03, 0.02)), 0.02, 0.014, m_hide, up, verts=6)
        lo = add_pivot("FrontLower" + nm, el, parent=up)
        seg("FrontLowerMesh" + nm, el, wr, 0.05, 0.034, m_hide, lo)
        ball("Elbow" + nm, el, (0.045, 0.045, 0.05), m_bone, lo)
        paw = add_pivot("FrontPaw" + nm, wr, parent=lo)
        seg("FrontPastern" + nm, wr, (sx * 0.13, 0.4, 0.04), 0.031, 0.028, m_hide, paw)
        blob("FrontPawMesh" + nm, (sx * 0.13, 0.44, 0.035), (0.08, 0.115, 0.055), m_hide, paw)
        for i in range(3):
            cx = sx * 0.13 + (i - 1) * 0.023
            seg("FClaw%s%d" % (nm, i), (cx, 0.49, 0.03), (cx, 0.525, 0.0), 0.009, 0.002, m_claw, paw, verts=5)

        hp = (sx * 0.14, -0.42, 0.66)
        kn = (sx * 0.15, -0.3, 0.42)
        hk = (sx * 0.15, -0.52, 0.2)
        th = add_pivot("HindUpper" + nm, hp, parent=body)
        ball("Haunch" + nm, (sx * 0.128, -0.4, 0.61), (0.09, 0.165, 0.175), m_fur, th)
        seg("HindUpperMesh" + nm, hp, kn, 0.082, 0.06, m_fur, th)
        sk = add_pivot("HindLower" + nm, kn, parent=th)
        seg("HindLowerMesh" + nm, kn, hk, 0.052, 0.036, m_hide, sk)
        ball("Stifle" + nm, kn, (0.045, 0.05, 0.055), m_hide, sk)
        if nm == "L": # the hide split open and the leg bone took over
            seg("ExposedBone", add(kn, (-0.03, -0.02, -0.03)), add(hk, (-0.03, 0.02, 0.04)), 0.014, 0.011, m_bone, sk, verts=6)
            ball("BoneChip", add(kn, (-0.045, -0.1, -0.12)), (0.016, 0.016, 0.02), m_bone, sk)
        ft = add_pivot("HindPaw" + nm, hk, parent=sk)
        seg("HindMeta" + nm, hk, (sx * 0.15, -0.46, 0.05), 0.031, 0.027, m_hide, ft)
        blob("HindPawMesh" + nm, (sx * 0.15, -0.43, 0.035), (0.08, 0.115, 0.055), m_hide, ft)
        for i in range(3):
            cx = sx * 0.15 + (i - 1) * 0.023
            seg("HClaw%s%d" % (nm, i), (cx, -0.38, 0.03), (cx, -0.345, 0.0), 0.009, 0.002, m_claw, ft, verts=5)

    tail = add_pivot("Tail", (0, -0.56, 0.76), parent=body)
    seg("TailBase", (0, -0.56, 0.76), (0, -0.76, 0.72), 0.048, 0.032, m_fur, tail)
    tip = add_pivot("TailTip", (0, -0.76, 0.72), parent=tail)
    for i in range(6):
        r = 0.017 - i * 0.002
        ball("TailBone%d" % i, (0, -0.79 - i * 0.052, 0.71 - i * 0.024), (r, 0.021, r), m_bone, tip)
    ball("TailEmber", (0, -0.79, 0.71), (0.022, 0.022, 0.022), m_ember, tip)

    merge_per_pivot()
    export_glb("enemy_hound.glb")


# ---------------------------------------------------------------------------
# BOSSES (rigid pivots the legacy boss animation rotates directly)
# ---------------------------------------------------------------------------
def _boss_root(torso_z):
    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, torso_z), parent=root)
    return root, torso


def build_boss_gun():
    """CORP. VEX - undead commando with a targeting-carbine."""
    clear_scene()
    metal, dark, wood, conc = props_mats()
    m_skin = make_mat("CommandoSkin", (0.48, 0.54, 0.42, 1), roughness=0.7, tex_prefix="zombie_skin")
    m_armor = make_mat("TacticalArmor", (0.13, 0.16, 0.14, 1), metallic=0.4, roughness=0.55, tex_prefix="rusted_metal")
    m_cloth = make_mat("FieldCoat", (0.16, 0.17, 0.13, 1), roughness=0.92, tex_prefix="camo")
    m_steel = make_mat("RifleSteel", (0.11, 0.12, 0.14, 1), metallic=0.88, roughness=0.32, tex_prefix="gunmetal")
    m_leather = make_mat("CommandoLeather", (0.12, 0.09, 0.06, 1), roughness=0.65, tex_prefix="leather")
    m_visor = neon("RedVisor", (1.0, 0.11, 0.09), 6.0, 0.15)
    m_eye = neon("VexEye", (1.0, 0.2, 0.1), 3.0, 0.2)
    m_bone = make_mat("VexBone", (0.4, 0.35, 0.25, 1), roughness=0.55)

    root, torso = _boss_root(1.02)
    blob("Vest", (0, 0.02, 1.3), (0.62, 0.46, 0.6), m_armor, torso, subsurf=1, bevel=0.06)
    box("Pelvis", (0, 0.01, 1.0), (0.48, 0.32, 0.28), m_cloth, torso, bevel=0.03)
    box("ChestPlate", (0, 0.225, 1.4), (0.44, 0.06, 0.36), m_steel, torso, bevel=0.02)
    box("PlateTrim", (0, 0.255, 1.28), (0.36, 0.02, 0.03), m_visor, torso, bevel=0.005)
    box("CoatSkirt", (0, -0.01, 1.06), (0.66, 0.46, 0.3), m_cloth, torso, rot=(math.radians(4), 0, 0), bevel=0.03)
    box("Collar", (0, 0.02, 1.56), (0.36, 0.3, 0.1), m_cloth, torso, bevel=0.03)
    cyl("Neck", (0, 0.02, 1.55), 0.075, 0.16, m_skin, torso)
    for sx in (-1, 1):
        ball("Pauldron%s" % ("L" if sx < 0 else "R"), (sx * 0.36, 0.0, 1.5), (0.14, 0.15, 0.12), m_armor, torso)
        box("BackPouch%s" % ("L" if sx < 0 else "R"), (sx * 0.14, -0.25, 1.26), (0.18, 0.1, 0.18), m_cloth, torso, bevel=0.02)
    for i, x in enumerate((-0.17, -0.06, 0.05, 0.16)):
        box("ChestPouch%d" % i, (x, 0.235, 1.16), (0.11, 0.075, 0.14), m_cloth, torso, bevel=0.015)
    for i in range(6):
        t = i / 5.0
        box("Shell%d" % i, (-0.2 + 0.4 * t, 0.245, 1.46 - 0.26 * t), (0.04, 0.03, 0.07), m_bone, torso,
            rot=(0, math.radians(33), 0), bevel=0.008)
    ball("MaskBag", (0.15, 0.26, 1.1), (0.075, 0.05, 0.08), m_leather, torso)
    cyl("MaskFilter", (0.15, 0.31, 1.09), 0.032, 0.05, m_steel, torso, rot=(R90, 0, 0))

    head = add_pivot("Head", (0, 0.02, 1.66), parent=torso)
    ball("Skull", (0, 0.03, 1.73), (0.112, 0.125, 0.128), m_skin, head)
    blob("MuzzleJaw", (0, 0.09, 1.63), (0.1, 0.11, 0.06), m_skin, head, subsurf=2)
    box("Brow", (0, 0.115, 1.775), (0.16, 0.05, 0.03), m_skin, head, bevel=0.01)
    for i in range(4):
        box("Tooth%d" % i, (-0.024 + i * 0.016, 0.15, 1.652), (0.01, 0.008, 0.016), m_bone, head, bevel=0.002)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Eye" + nm, (sx * 0.042, 0.135, 1.748), (0.017, 0.013, 0.013), m_eye, head)
        ball("Ear" + nm, (sx * 0.108, 0.03, 1.72), (0.014, 0.026, 0.036), m_skin, head)
    blob("Helmet", (0, -0.005, 1.81), (0.31, 0.34, 0.26), m_armor, head, subsurf=1, bevel=0.03)
    torus("HelmetRim", (0, -0.005, 1.755), 0.15, 0.014, m_armor, head, rot=(R90, 0, 0), seg_major=18)
    box("Visor", (0, 0.15, 1.715), (0.25, 0.05, 0.06), m_visor, head, rot=(math.radians(-8), 0, 0), bevel=0.01)
    box("NVGMount", (0, 0.13, 1.83), (0.07, 0.08, 0.05), m_steel, head, bevel=0.01)
    box("Strap", (0, -0.16, 1.76), (0.28, 0.03, 0.04), m_leather, head, bevel=0.006)

    # left arm braces the rifle, right arm holds the trigger group
    arm_l = add_pivot("ArmL", (-0.34, 0.04, 1.5), parent=torso)
    seg("UpperArmL", (-0.34, 0.04, 1.48), (-0.3, 0.3, 1.3), 0.08, 0.062, m_cloth, arm_l)
    seg("ForearmL", (-0.3, 0.3, 1.3), (-0.06, 0.46, 1.34), 0.06, 0.048, m_skin, arm_l)
    ball("HandL", (-0.03, 0.5, 1.34), (0.05, 0.045, 0.05), m_leather, arm_l)
    arm_r = add_pivot("ArmR", (0.34, 0.04, 1.5), parent=torso)
    seg("UpperArmR", (0.34, 0.04, 1.48), (0.32, 0.28, 1.32), 0.082, 0.064, m_cloth, arm_r)
    seg("ForearmR", (0.32, 0.28, 1.32), (0.3, 0.46, 1.3), 0.062, 0.05, m_skin, arm_r)
    ball("HandR", (0.3, 0.48, 1.29), (0.052, 0.048, 0.055), m_leather, arm_r)
    # --- Carbine: receiver under the hand, barrel straight out +Y ---------
    box("Receiver", (0.3, 0.52, 1.26), (0.08, 0.52, 0.15), m_steel, arm_r, bevel=0.02)
    box("Handguard", (0.3, 0.78, 1.25), (0.07, 0.26, 0.1), m_leather, arm_r, bevel=0.02)
    cyl("Barrel", (0.3, 1.02, 1.28), 0.026, 0.42, m_steel, arm_r, rot=(R90, 0, 0))
    cyl("MuzzleBrake", (0.3, 1.24, 1.28), 0.038, 0.08, m_steel, arm_r, rot=(R90, 0, 0))
    box("Stock", (0.3, 0.22, 1.28), (0.06, 0.3, 0.12), m_leather, arm_r, rot=(math.radians(6), 0, 0), bevel=0.02)
    box("PistolGrip", (0.3, 0.44, 1.14), (0.05, 0.08, 0.18), m_leather, arm_r, rot=(math.radians(12), 0, 0), bevel=0.02)
    box("Magazine", (0.3, 0.58, 1.08), (0.06, 0.12, 0.26), m_steel, arm_r, rot=(math.radians(-14), 0, 0), bevel=0.015)
    cyl("Scope", (0.3, 0.56, 1.42), 0.035, 0.26, m_steel, arm_r, rot=(R90, 0, 0))
    box("ScopeMount", (0.3, 0.56, 1.35), (0.04, 0.06, 0.06), dark, arm_r, bevel=0.008)
    box("LaserModule", (0.3, 0.74, 1.17), (0.05, 0.16, 0.05), m_steel, arm_r, bevel=0.01)
    ball("LaserDiode", (0.3, 0.83, 1.17), (0.014, 0.014, 0.014), m_visor, arm_r)
    ball("RedDot", (0.3, 1.28, 1.28), (0.01, 0.01, 0.01), m_visor, arm_r)
    box("Sling", (0.28, 0.36, 1.36), (0.03, 0.02, 0.34), m_leather, arm_r, rot=(math.radians(60), 0, 0), bevel=0.004)

    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.16, 0, 1.0), parent=root)
        seg("Thigh" + nm, (sx * 0.16, 0, 1.0), (sx * 0.165, 0.02, 0.55), 0.105, 0.082, m_cloth, leg)
        seg("Shin" + nm, (sx * 0.165, 0.02, 0.55), (sx * 0.16, 0.0, 0.14), 0.078, 0.06, m_armor, leg)
        ball("Knee" + nm, (sx * 0.165, 0.02, 0.55), (0.07, 0.07, 0.075), m_leather, leg)
        box("KneePlate" + nm, (sx * 0.165, 0.12, 0.55), (0.13, 0.05, 0.14), m_leather, leg, bevel=0.02)
        box("Boot" + nm, (sx * 0.16, 0.07, 0.06), (0.16, 0.3, 0.12), m_leather, leg, bevel=0.02)
    merge_per_pivot()
    export_glb("boss_gun_zombie.glb")


def build_boss_gorilla():
    """SUBJECT GOLIATH - silverback specimen in a broken containment harness."""
    clear_scene()
    # gorilla_hide is near-black, which turned the whole silhouette into a
    # hole; concrete grain is mid-grey and takes a cool tint much better.
    m_fur = make_mat("GorillaFur", (0.40, 0.41, 0.45, 1), roughness=0.85, tex_prefix="concrete")
    m_silver = make_mat("SilverBack", (0.8, 0.83, 0.9, 1), roughness=0.66, tex_prefix="concrete")
    m_skin = make_mat("GorillaChest", (0.5, 0.34, 0.3, 1), roughness=0.58, tex_prefix="burlap")
    m_rage = neon("RageVeins", (1.0, 0.32, 0.05), 5.5, 0.2)
    m_bone = make_mat("GoliathBone", (0.42, 0.38, 0.28, 1), roughness=0.55)
    m_iron = make_mat("ContainmentIron", (0.2, 0.18, 0.17, 1), metallic=0.8, roughness=0.5, tex_prefix="rusted_metal")

    root, torso = _boss_root(1.15)
    # The chest is a mass, not a planet: it used to swallow the head whole.
    chest = ball("BarrelChest", (0, 0.1, 1.42), (0.6, 0.46, 0.46), m_fur, torso)
    hump = ball("SilverHump", (0, -0.26, 1.58), (0.5, 0.38, 0.4), m_silver, torso)
    pec = blob("Pectoral", (0, 0.44, 1.42), (0.5, 0.22, 0.34), m_skin, torso, subsurf=2)
    forms = [chest, hump, pec]
    snap(box("CoreScar", (0, 0.56, 1.5), (0.2, 0.05, 0.12), m_rage, torso,
             rot=(math.radians(20), 0, 0), bevel=0.01), forms, -0.012)
    ball("Pelvis", (0, -0.02, 1.1), (0.34, 0.3, 0.26), m_fur, torso)
    box("ApronHide", (0, 0.3, 1.06), (0.44, 0.1, 0.44), m_skin, torso, rot=(math.radians(-12), 0, 0), bevel=0.02)
    for sx, nm in ((-1, "L"), (1, "R")):
        p1 = surface_point((sx * 0.44, -0.1, 1.72), forms, -0.01)
        p2 = surface_point((sx * 0.5, 0.2, 1.3), forms, -0.01)
        seg("RageVein%s" % nm, p1, p2, 0.026, 0.014, m_rage, torso, verts=6)
        snap(ball("Sac%s" % nm, (sx * 0.36, 0.36, 1.34), (0.09, 0.07, 0.1), m_skin, torso), forms, -0.03)
        snap(box("Rivet%s%d" % (nm, 0), (sx * 0.3, 0.5, 1.6), (0.05, 0.03, 0.05), m_iron, torso, bevel=0.006),
             forms, -0.008)
    # containment collar, one side torn off
    torus("Collar", (0, 0.04, 1.78), 0.42, 0.05, m_iron, torso, rot=(R90, 0, 0), seg_major=20)
    snap(box("CollarBreak", (0.36, -0.1, 1.76), (0.12, 0.16, 0.1), m_iron, torso,
             rot=(0, math.radians(30), 0), bevel=0.01), forms, -0.01)
    for i in range(4):
        snap(ball("Chain%d" % i, (-0.1 - i * 0.09, -0.56 - i * 0.03, 1.66 - i * 0.09),
                    (0.035, 0.03, 0.035), m_iron, torso), forms, -0.012)
    for i in range(5):
        snap(box("SpinePlate%d" % i, (0, -0.52 - i * 0.02, 1.72 - i * 0.13),
                 (0.16 - i * 0.012, 0.1, 0.1), m_iron, torso,
                 rot=(math.radians(-14), 0, 0), bevel=0.015), forms, -0.01)

    head = add_pivot("Head", (0, 0.42, 1.96), parent=torso)
    H = (0, 0.42, 1.96)
    ball("Cranium", add(H, (0, 0.02, 0.08)), (0.27, 0.29, 0.27), m_fur, head)
    blob("BrowRidge", add(H, (0, 0.22, 0.12)), (0.26, 0.12, 0.08), m_silver, head, subsurf=2)
    box("HeavyJaw", add(H, (0, 0.16, -0.1)), (0.22, 0.24, 0.14), m_skin, head, bevel=0.03)
    for i in range(4):
        box("Fang%d" % i, add(H, (-0.08 + i * 0.055, 0.3, -0.02)), (0.03, 0.05, 0.07), m_bone, head,
            rot=(math.radians(15), 0, 0), bevel=0.006)
    ball("Nose", add(H, (0, 0.29, 0.04)), (0.06, 0.05, 0.05), m_skin, head)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Eye%s" % nm, add(H, (sx * 0.11, 0.24, 0.13)), (0.03, 0.024, 0.024), m_rage, head)
        ball("Ear%s" % nm, add(H, (sx * 0.28, 0.0, 0.02)), (0.05, 0.07, 0.08), m_fur, head)
    box("CranialTag", add(H, (0.14, -0.26, 0.14)), (0.08, 0.02, 0.06), m_iron, head,
        rot=(0, math.radians(-20), 0), bevel=0.004)

    for sx, nm in ((-1, "L"), (1, "R")):
        A = (sx * 0.74, 0.12, 1.78)
        arm = add_pivot("Arm" + nm, A, parent=torso)
        ball("Deltoid" + nm, add(A, (sx * 0.06, 0, -0.06)), (0.28, 0.27, 0.28), m_silver, arm)
        seg("UpperArm" + nm, (sx * 0.74, 0.12, 1.78), (sx * 0.82, 0.2, 1.3), 0.19, 0.14, m_fur, arm)
        seg("MassiveForearm" + nm, (sx * 0.82, 0.2, 1.3), (sx * 0.84, 0.36, 0.62), 0.15, 0.12, m_fur, arm)
        ball("Wrist" + nm, (sx * 0.84, 0.36, 0.62), (0.14, 0.14, 0.14), m_skin, arm)
        blob("CrusherFist" + nm, (sx * 0.84, 0.44, 0.44), (0.3, 0.32, 0.26), m_skin, arm, subsurf=2)
        for i in range(4):
            kx = sx * (0.72 + i * 0.08)
            seg("Knuckle%s%d" % (nm, i), (kx, 0.54, 0.44), (kx, 0.62, 0.14), 0.045, 0.03, m_bone, arm, verts=6)
        box("KnuckleGlow%s" % nm, (sx * 0.84, 0.56, 0.5), (0.24, 0.06, 0.07), m_rage, arm, rot=(math.radians(25), 0, 0), bevel=0.008)
        seg("ArmVein%s" % nm, (sx * 0.78, 0.28, 1.5), (sx * 0.82, 0.34, 0.9), 0.022, 0.014, m_rage, arm, verts=6)

    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.36, -0.08, 1.05), parent=root)
        ball("Haunch" + nm, (sx * 0.38, -0.06, 0.85), (0.22, 0.26, 0.3), m_fur, leg)
        seg("ThighMesh" + nm, (sx * 0.36, -0.08, 1.0), (sx * 0.38, -0.02, 0.55), 0.16, 0.12, m_fur, leg)
        seg("Calf" + nm, (sx * 0.38, -0.02, 0.55), (sx * 0.38, -0.1, 0.1), 0.12, 0.09, m_skin, leg)
        ball("Ankle" + nm, (sx * 0.38, -0.1, 0.12), (0.09, 0.09, 0.09), m_bone, leg)
        blob("Foot" + nm, (sx * 0.38, 0.08, 0.05), (0.22, 0.36, 0.1), m_skin, leg, subsurf=2)
        for i in range(3):
            tx = sx * 0.38 + (i - 1) * 0.07
            seg("Toe%s%d" % (nm, i), (tx, 0.24, 0.04), (tx, 0.34, 0.02), 0.03, 0.02, m_bone, leg, verts=5)
    merge_per_pivot()
    export_glb("boss_gorilla.glb")


def build_boss_necro():
    """MORBUS-9 - hazmat cultist walking on the tanks that made him."""
    clear_scene()
    m_suit = make_mat("HazmatSuit", (0.38, 0.36, 0.16, 1), roughness=0.65, tex_prefix="fabric")
    m_suit2 = make_mat("HazmatSealed", (0.22, 0.22, 0.14, 1), roughness=0.4, tex_prefix="leather")
    m_flesh = make_mat("MutantFlesh", (0.23, 0.32, 0.2, 1), roughness=0.55, tex_prefix="zombie_skin")
    m_acid = neon("AcidGlow", (0.24, 1.0, 0.16), 5.5, 0.15)
    m_acid2 = neon("AcidFluid", (0.35, 0.95, 0.2), 2.2, 0.1)
    m_steel = make_mat("LabSteel", (0.3, 0.31, 0.32, 1), metallic=0.85, roughness=0.35, tex_prefix="gunmetal")
    m_bone = make_mat("MorbBone", (0.44, 0.4, 0.3, 1), roughness=0.55)
    m_dark = make_mat("MorbDark", (0.04, 0.05, 0.03, 1), roughness=0.9)

    root, torso = _boss_root(1.12)
    blob("SuitBody", (0, 0.01, 1.42), (0.56, 0.42, 0.74), m_suit, torso, subsurf=1, bevel=0.05)
    box("Apron", (0, 0.22, 1.16), (0.44, 0.06, 0.56), m_suit2, torso, bevel=0.02)
    box("SeamStripe", (0, 0.25, 1.5), (0.05, 0.02, 0.5), m_acid, torso, bevel=0.004)
    box("PelvisSeal", (0, 0.0, 1.06), (0.5, 0.36, 0.16), m_suit2, torso, bevel=0.03)
    # dorsal tanks with gauges and hoses
    for sx, nm in ((-1, "L"), (1, "R")):
        cyl("Tank%s" % nm, (sx * 0.19, -0.28, 1.52), 0.125, 0.58, m_steel, torso, rot=(math.radians(6), 0, 0))
        ball("TankCap%s" % nm, (sx * 0.19, -0.28, 1.82), (0.1, 0.1, 0.07), m_steel, torso)
        cyl("TankFluid%s" % nm, (sx * 0.19, -0.22, 1.5), 0.06, 0.4, m_acid2, torso, rot=(math.radians(6), 0, 0))
        box("Bracket%s" % nm, (sx * 0.19, -0.36, 1.66), (0.28, 0.04, 0.07), m_steel, torso, bevel=0.008)
        ball("Gauge%s" % nm, (sx * 0.3, -0.24, 1.74), (0.045, 0.03, 0.045), m_acid, torso)
        seg("Hose%s" % nm, (sx * 0.19, -0.34, 1.78), (sx * 0.1, 0.12, 1.86), 0.026, 0.026, m_dark, torso, verts=8)
        seg("HoseLow%s" % nm, (sx * 0.2, -0.32, 1.28), (sx * 0.26, 0.16, 1.34), 0.024, 0.024, m_dark, torso, verts=8)
    for i in range(3):
        box("Vial%d" % i, (-0.12 + i * 0.12, 0.24, 1.26), (0.05, 0.04, 0.12), m_acid2, torso, rot=(math.radians(10), 0, 0), bevel=0.006)
    ball("HumpSpore", (0.0, -0.05, 1.7), (0.14, 0.14, 0.1), m_flesh, torso)
    for i in range(6):
        ball("Boil%d" % i, (random.Random(i + 3).uniform(-0.2, 0.2), random.Random(i + 9).uniform(-0.1, 0.2), 1.3 + i * 0.06),
             (0.035, 0.03, 0.03), m_acid2, torso)

    head = add_pivot("Head", (0, 0.06, 1.88), parent=torso)
    H = (0, 0.06, 1.88)
    blob("Hood", add(H, (0, -0.02, 0.06)), (0.3, 0.34, 0.34), m_suit, head, subsurf=2)
    ball("GasMask", add(H, (0, 0.06, -0.02)), (0.15, 0.16, 0.16), m_suit2, head)
    box("Goggles", add(H, (0, 0.16, 0.03)), (0.22, 0.05, 0.08), m_acid, head, rot=(math.radians(-6), 0, 0), bevel=0.01)
    cyl("FilterL", add(H, (-0.08, 0.16, -0.08)), 0.05, 0.09, m_steel, head, rot=(R90, 0, 0))
    cyl("FilterR", add(H, (0.08, 0.16, -0.08)), 0.05, 0.09, m_steel, head, rot=(R90, 0, 0))
    seg("Whistle", add(H, (0, 0.2, -0.04)), add(H, (0, 0.3, -0.16)), 0.022, 0.016, m_steel, head, verts=6)
    box("WardSigil", add(H, (0, -0.19, 0.06)), (0.14, 0.02, 0.18), m_bone, head, bevel=0.006)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("EyeLens%s" % nm, add(H, (sx * 0.06, 0.185, 0.04)), (0.026, 0.014, 0.026), m_acid, head)

    for sx, nm in ((-1, "L"), (1, "R")):
        arm = add_pivot("Arm" + nm, (sx * 0.34, 0.02, 1.74), parent=torso)
        ball("ShoulderPad" + nm, (sx * 0.36, 0.02, 1.72), (0.13, 0.14, 0.12), m_steel, arm)
        seg("Sleeve" + nm, (sx * 0.34, 0.02, 1.72), (sx * 0.37, 0.3, 1.44), 0.09, 0.07, m_suit, arm)
        seg("TendrilArm" + nm, (sx * 0.37, 0.3, 1.44), (sx * 0.35, 0.62, 1.24), 0.065, 0.045, m_flesh, arm)
        ball("AcidSac" + nm, (sx * 0.36, 0.46, 1.34), (0.1, 0.11, 0.09), m_acid, arm)
        # three long clawed fingers, dripping
        for i in range(3):
            fx = sx * 0.35 + (i - 1) * 0.045 * sx
            seg("Finger%s%d" % (nm, i), (fx, 0.64, 1.22), (fx + sx * 0.02, 0.74, 1.08), 0.018, 0.006, m_bone, arm, verts=5)
        ball("Drip%s" % nm, (sx * 0.37, 0.72, 1.02), (0.02, 0.02, 0.028), m_acid, arm)
        box("Bracer" + nm, (sx * 0.36, 0.3, 1.46), (0.14, 0.14, 0.12), m_suit2, arm, bevel=0.02)

    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.16, 0, 1.1), parent=root)
        seg("ThighStilt" + nm, (sx * 0.16, 0, 1.1), (sx * 0.18, -0.04, 0.56), 0.09, 0.06, m_suit, leg)
        seg("ShinStilt" + nm, (sx * 0.18, -0.04, 0.56), (sx * 0.17, 0.02, 0.12), 0.055, 0.035, m_suit2, leg)
        ball("KneeJoint" + nm, (sx * 0.18, -0.04, 0.56), (0.06, 0.06, 0.06), m_flesh, leg)
        box("ClothDrape%s" % nm, (sx * 0.17, -0.08, 0.9), (0.16, 0.04, 0.3), m_suit, leg, rot=(math.radians(8), 0, 0), bevel=0.01)
        blob("HoofBoot" + nm, (sx * 0.17, 0.06, 0.06), (0.12, 0.24, 0.1), m_suit2, leg, subsurf=2)
    merge_per_pivot()
    export_glb("boss_necromancer.glb")


def build_boss_panzer():
    """PANZER-KRIEG - flamethrower mech. The power core is the weakpoint, so it
    sits exactly where take_damage() looks for it: (0, +0.35, 1.55)."""
    clear_scene()
    m_iron = make_mat("PanzerIron", (0.2, 0.19, 0.18, 1), metallic=0.85, roughness=0.42, tex_prefix="rusted_metal")
    m_plate = make_mat("PanzerPlate", (0.13, 0.13, 0.14, 1), metallic=0.8, roughness=0.35, tex_prefix="gunmetal")
    m_brass = make_mat("PanzerBrass", (0.46, 0.34, 0.16, 1), metallic=0.75, roughness=0.38)
    m_core = neon("PanzerCore", (1.0, 0.7, 0.12), 7.0, 0.15)
    m_hot = neon("PanzerHot", (1.0, 0.4, 0.06), 4.0, 0.3)
    m_hose = make_mat("PanzerHose", (0.05, 0.05, 0.05, 1), roughness=0.85, tex_prefix="leather")
    m_skin = make_mat("PanzerFlesh", (0.4, 0.3, 0.26, 1), roughness=0.7, tex_prefix="zombie_skin")

    root, torso = _boss_root(1.18)
    box("Chassis", (0, 0.0, 1.6), (0.94, 0.62, 0.84), m_iron, torso, bevel=0.06)
    box("ChestRidge", (0, 0.3, 1.86), (0.7, 0.14, 0.14), m_plate, torso, rot=(math.radians(-14), 0, 0), bevel=0.02)
    box("WaistGuard", (0, 0.02, 1.2), (0.8, 0.58, 0.24), m_iron, torso, bevel=0.04)
    # --- the weakpoint ------------------------------------------------------
    torus("CoreRim", (0, 0.315, 1.55), 0.19, 0.045, m_brass, torso, rot=(R90, 0, 0), seg_major=20)
    cyl("CoreHousing", (0, 0.33, 1.55), 0.17, 0.1, m_plate, torso, rot=(R90, 0, 0))
    ball("PowerCore", (0, 0.37, 1.55), (0.13, 0.07, 0.13), m_core, torso)
    for i in range(6):
        a = i * math.tau / 6
        box("CoreBolt%d" % i, (math.sin(a) * 0.2, 0.32 + math.cos(a) * 0.0, 1.55 + math.cos(a) * 0.2),
            (0.04, 0.04, 0.04), m_brass, torso, bevel=0.006)
    # fuel backpack, vents, rivets
    for sx, nm in ((-1, "L"), (1, "R")):
        cyl("FuelTank%s" % nm, (sx * 0.26, -0.42, 1.66), 0.15, 0.62, m_plate, torso, rot=(math.radians(8), 0, 0))
        ball("TankCap%s" % nm, (sx * 0.26, -0.42, 1.98), (0.12, 0.12, 0.07), m_brass, torso)
        seg("FeedHose%s" % nm, (sx * 0.26, -0.46, 1.36), (sx * 0.4, -0.1, 1.42), 0.03, 0.03, m_hose, torso, verts=8)
        box("Vent%s" % nm, (sx * 0.42, -0.06, 1.88), (0.1, 0.28, 0.2), m_plate, torso, rot=(0, math.radians(10 * sx), 0), bevel=0.01)
        for j in range(3):
            box("VentSlot%s%d" % (nm, j), (sx * 0.47, -0.06, 1.94 - j * 0.05), (0.02, 0.24, 0.018), m_hot, torso,
                rot=(0, math.radians(10 * sx), 0), bevel=0.002)
    for i in range(4):
        ball("Rivet%d" % i, (-0.3 + i * 0.2, 0.29, 1.94), (0.022, 0.022, 0.022), m_brass, torso)
    box("ShoulderYoke", (0, 0.0, 2.0), (0.98, 0.44, 0.16), m_iron, torso, bevel=0.03)

    head = add_pivot("Head", (0, 0.04, 2.04), parent=torso)
    H = (0, 0.04, 2.04)
    cyl("DomeHelmet", add(H, (0, 0, 0.16)), 0.22, 0.34, m_iron, head, bevel=0.03)
    ball("DomeTop", add(H, (0, 0, 0.3)), (0.22, 0.22, 0.12), m_iron, head)
    box("SlitVisor", add(H, (0, 0.19, 0.14)), (0.28, 0.05, 0.06), m_core, head, bevel=0.008)
    box("JawGuard", add(H, (0, 0.14, -0.02)), (0.3, 0.16, 0.14), m_plate, head, bevel=0.02)
    cyl("Breather", add(H, (0, 0.24, -0.04)), 0.07, 0.12, m_brass, head, rot=(R90, 0, 0))
    box("CrestSight", add(H, (0, -0.04, 0.36)), (0.05, 0.24, 0.06), m_plate, head, bevel=0.008)
    for sx, nm in ((-1, "L"), (1, "R")):
        seg("AntennaStub%s" % nm, add(H, (sx * 0.2, -0.02, 0.2)), add(H, (sx * 0.26, -0.06, 0.38)),
            0.012, 0.006, m_brass, head, verts=5)

    arm_l = add_pivot("ArmL", (-0.58, 0, 1.82), parent=torso)
    ball("LarpL", (-0.61, 0, 1.76), (0.19, 0.2, 0.18), m_iron, arm_l)
    seg("LeftUpperArm", (-0.58, 0, 1.8), (-0.66, 0.22, 1.44), 0.13, 0.11, m_iron, arm_l)
    seg("LeftForearm", (-0.66, 0.22, 1.44), (-0.6, 0.46, 1.16), 0.11, 0.1, m_plate, arm_l)
    box("BulwarkPlate", (-0.6, 0.52, 1.2), (0.3, 0.06, 0.5), m_iron, arm_l, rot=(math.radians(12), 0, 0), bevel=0.02)
    for i in range(3):
        box("BulwarkSpine%d" % i, (-0.68 + i * 0.08, 0.56, 1.2), (0.035, 0.06, 0.36), m_hot, arm_l,
            rot=(math.radians(12), 0, 0), bevel=0.006)
    blob("LeftGauntlet", (-0.58, 0.56, 1.0), (0.24, 0.26, 0.2), m_skin, arm_l, subsurf=2)

    arm_r = add_pivot("ArmR", (0.58, 0, 1.82), parent=torso)
    ball("DeltoidR", (0.61, 0, 1.76), (0.19, 0.2, 0.18), m_iron, arm_r)
    seg("RightUpperArm", (0.58, 0, 1.8), (0.6, 0.26, 1.58), 0.14, 0.12, m_iron, arm_r)
    cyl("FlameCannon", (0.55, 0.62, 1.56), 0.12, 0.7, m_plate, arm_r, rot=(R90, 0, 0))
    cyl("CannonShroud", (0.55, 0.86, 1.55), 0.15, 0.2, m_brass, arm_r, rot=(R90, 0, 0))
    cyl("PilotRing", (0.55, 1.02, 1.54), 0.1, 0.06, m_hot, arm_r, rot=(R90, 0, 0))
    ball("PilotTip", (0.55, 1.07, 1.54), (0.05, 0.05, 0.05), m_core, arm_r)
    box("CannonGrip", (0.55, 0.44, 1.38), (0.06, 0.1, 0.2), m_hose, arm_r, rot=(math.radians(14), 0, 0), bevel=0.02)
    cyl("IgniterDrum", (0.68, 0.46, 1.66), 0.09, 0.22, m_brass, arm_r, rot=(0, R90, 0))
    seg("CannonHose", (0.6, 0.3, 1.72), (0.3, -0.34, 1.72), 0.032, 0.032, m_hose, arm_r, verts=8)

    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.28, 0, 1.15), parent=root)
        cyl("PistonUpper%s" % nm, (sx * 0.28, 0, 1.02), 0.14, 0.42, m_iron, leg)
        cyl("PistonLower%s" % nm, (sx * 0.28, -0.01, 0.6), 0.1, 0.42, m_brass, leg)
        ball("KneeCap%s" % nm, (sx * 0.28, 0.06, 0.8), (0.11, 0.1, 0.11), m_plate, leg)
        box("GreaseBoot%s" % nm, (sx * 0.28, -0.01, 0.34), (0.2, 0.2, 0.28), m_iron, leg, bevel=0.03)
        box("FootPlate%s" % nm, (sx * 0.28, 0.08, 0.08), (0.26, 0.4, 0.12), m_plate, leg, bevel=0.02)
        box("ToeClaw%s" % nm, (sx * 0.28, 0.3, 0.06), (0.14, 0.14, 0.08), m_hot, leg, bevel=0.01)
    merge_per_pivot()
    export_glb("boss_juggernaut.glb")


def build_boss_phantom():
    """WRAITH-11 - the Volt Reaper: a phase-torn husk in a scorched officer's
    cloak, holding two shock blades. Round 5 was reusing the necromancer mesh."""
    clear_scene()
    m_cloak = make_mat("WraithCloak", (0.045, 0.05, 0.075, 1), roughness=0.9, tex_prefix="fabric")
    m_cloak2 = make_mat("WraithLining", (0.09, 0.1, 0.14, 1), roughness=0.7, tex_prefix="leather")
    m_flesh = make_mat("WraithFlesh", (0.24, 0.27, 0.32, 1), roughness=0.5, tex_prefix="zombie_skin")
    m_bone = make_mat("WraithBone", (0.5, 0.52, 0.5, 1), roughness=0.5)
    m_volt = neon("VoltEdge", (0.45, 0.75, 1.0), 6.0, 0.15)
    m_core = neon("VoltCore", (0.2, 0.6, 1.0), 3.2, 0.2)
    m_steel = make_mat("WraithSteel", (0.28, 0.3, 0.34, 1), metallic=0.85, roughness=0.3, tex_prefix="gunmetal")
    m_dark = make_mat("WraithVoid", (0.008, 0.01, 0.015, 1), roughness=0.95)

    root, torso = _boss_root(1.15)
    # torso inside the cloak, so the chest glow reads through the opening
    ball("HuskChest", (0, 0.02, 1.36), (0.19, 0.17, 0.22), m_flesh, torso)
    for i in range(4):
        seg("Rib%d" % i, (-0.13 + i * 0.09, 0.16, 1.5), (-0.13 + i * 0.09, 0.15, 1.2), 0.014, 0.01, m_bone, torso, verts=6)
    ball("VoltHeart", (0, 0.19, 1.36), (0.06, 0.05, 0.06), m_core, torso)
    for i in range(3):
        torus("FieldRing%d" % i, (0, 0.19, 1.42 - i * 0.1), 0.09 + i * 0.035, 0.008, m_volt, torso, rot=(R90, 0, 0), seg_major=16)
    # the cloak: shoulders, flared skirt, hanging rags. Set back from the
    # chest so the VoltHeart and the field rings show through the opening.
    blob("ShoulderMass", (0, -0.04, 1.6), (1.05, 0.72, 0.45), m_cloak, torso, subsurf=2, bevel=0.0)
    seg("NeckGlow", (0, 0.02, 1.66), (0, 0.03, 1.86), 0.062, 0.05, m_core, torso, verts=8)
    for sx, nm in ((-1, "L"), (1, "R")):
        box("Pauldron%s" % nm, (sx * 0.3, 0.0, 1.62), (0.18, 0.26, 0.14), m_steel, torso,
            rot=(0, math.radians(-14 * sx), 0), bevel=0.02)
        box("Epaulette%s" % nm, (sx * 0.34, 0.0, 1.72), (0.1, 0.16, 0.05), m_cloak2, torso,
            rot=(0, math.radians(-18 * sx), 0), bevel=0.01)
        for i in range(4):
            seg("Tassel%s%d" % (nm, i), (sx * (0.3 + i * 0.01), 0.06, 1.68), (sx * (0.32 + i * 0.015), 0.09, 1.5 - i * 0.02),
                0.012, 0.006, m_volt, torso, verts=5)
    cloak_body = blob("CloakBody", (0, -0.14, 1.28), (1.0, 0.8, 0.98), m_cloak, torso, subsurf=2, bevel=0.0)
    skirt = seg("CloakSkirt", (0, -0.12, 0.22), (0, -0.12, 1.28), 0.42, 0.24, m_cloak, torso, verts=12)
    cloak_forms = [skirt, cloak_body]
    for i in range(9):
        a = -2.4 + i * 0.6
        snap(box("HemTag%d" % i, (math.sin(a) * 0.5, -0.12 + math.cos(a) * 0.42, 0.3),
                 (0.055, 0.02, 0.3), m_cloak2, torso, rot=(0, math.radians(6), a), bevel=0.008),
             cloak_forms, -0.012)
    for i in range(5):
        seg("Arc%d" % i, (math.sin(i * 1.9) * 0.4, -0.1 + math.cos(i * 1.3) * 0.3, 1.1 + i * 0.14),
            (math.sin(i * 1.9 + 0.9) * 0.46, -0.1 + math.cos(i * 1.3 + 0.9) * 0.34, 0.96 + i * 0.14),
            0.008, 0.005, m_volt, torso, verts=4)
    box("Belt", (0, 0.0, 1.12), (0.5, 0.4, 0.08), m_cloak2, torso, bevel=0.02)
    ball("Buckle", (0, 0.2, 1.12), (0.05, 0.02, 0.05), m_steel, torso)
    box("Satchel", (0.24, -0.14, 1.1), (0.16, 0.12, 0.18), m_cloak2, torso, bevel=0.02)

    head = add_pivot("Head", (0, 0.03, 1.92), parent=torso)
    H = (0, 0.03, 1.92)
    blob("Hood", add(H, (0, -0.01, 0.02)), (0.36, 0.4, 0.38), m_cloak, head, subsurf=2, bevel=0.0)
    ball("VoidFace", add(H, (0, 0.08, -0.02)), (0.11, 0.09, 0.13), m_dark, head)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Eye%s" % nm, add(H, (sx * 0.045, 0.145, 0.01)), (0.022, 0.016, 0.02), m_volt, head)
        seg("EyeTrails%s" % nm, add(H, (sx * 0.045, 0.15, 0.0)), add(H, (sx * 0.06, 0.11, -0.1)),
            0.01, 0.003, m_volt, head, verts=4)
        seg("CheekBone%s" % nm, add(H, (sx * 0.06, 0.13, -0.06)), add(H, (sx * 0.03, 0.16, -0.14)),
            0.014, 0.008, m_bone, head, verts=5)
    box("HoodRidge", add(H, (0, 0.1, 0.11)), (0.16, 0.1, 0.03), m_steel, head, rot=(math.radians(-50), 0, 0), bevel=0.008)
    ball("JawBone", add(H, (0, 0.1, -0.13)), (0.06, 0.05, 0.04), m_bone, head)
    for i in range(3):
        box("HoodVents%d" % i, add(H, (-0.06 + i * 0.06, -0.16, 0.04)), (0.02, 0.03, 0.1), m_volt, head, bevel=0.002)

    # twin shock blades; _animate_melee_swipe swings these through the player
    for sx, nm in ((-1, "L"), (1, "R")):
        arm = add_pivot("Arm" + nm, (sx * 0.33, 0.02, 1.62), parent=torso)
        seg("Sleeve%s" % nm, (sx * 0.33, 0.02, 1.6), (sx * 0.36, 0.22, 1.34), 0.1, 0.07, m_cloak, arm)
        seg("Wrist%s" % nm, (sx * 0.36, 0.22, 1.34), (sx * 0.33, 0.44, 1.2), 0.055, 0.04, m_flesh, arm)
        ball("Grip%s" % nm, (sx * 0.33, 0.47, 1.18), (0.05, 0.05, 0.06), m_cloak2, arm)
        box("Guard%s" % nm, (sx * 0.33, 0.55, 1.2), (0.16, 0.04, 0.06), m_steel, arm, rot=(math.radians(18), 0, 0), bevel=0.01)
        seg("Blade%s" % nm, (sx * 0.33, 0.58, 1.22), (sx * 0.3, 1.16, 1.06), 0.028, 0.006, m_steel, arm, verts=6)
        seg("BladeEdge%s" % nm, (sx * 0.33, 0.6, 1.2), (sx * 0.3, 1.12, 1.05), 0.012, 0.004, m_volt, arm, verts=4)
        ball("Pommel%s" % nm, (sx * 0.33, 0.44, 1.16), (0.03, 0.03, 0.03), m_volt, arm)
        for i in range(3):
            torus("Coil%s%d" % (nm, i), (sx * 0.345, 0.3 + i * 0.08, 1.3 - i * 0.05), 0.05, 0.008, m_volt, arm,
                  rot=(R90, 0, 0), seg_major=12)

    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.14, 0, 1.05), parent=root)
        seg("LegWrap%s" % nm, (sx * 0.14, 0, 1.05), (sx * 0.15, -0.02, 0.5), 0.08, 0.055, m_cloak, leg)
        seg("ShinBone%s" % nm, (sx * 0.15, -0.02, 0.5), (sx * 0.15, 0.0, 0.12), 0.045, 0.032, m_bone, leg)
        ball("Knot%s" % nm, (sx * 0.15, -0.02, 0.5), (0.05, 0.05, 0.05), m_cloak2, leg)
        box("GhostBoot%s" % nm, (sx * 0.15, 0.06, 0.06), (0.12, 0.26, 0.1), m_cloak2, leg, bevel=0.02)
        box("Spur%s" % nm, (sx * 0.15, 0.19, 0.03), (0.06, 0.06, 0.03), m_volt, leg, bevel=0.005)
    merge_per_pivot()
    export_glb("boss_phantom.glb")


BUILDERS = {
    "bloater": build_bloater,
    "survivor": build_survivor,
    "hound": build_hound,
    "gun": build_boss_gun,
    "gorilla": build_boss_gorilla,
    "necro": build_boss_necro,
    "panzer": build_boss_panzer,
    "phantom": build_boss_phantom,
}
ALL = list(BUILDERS)

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "bosses" in only:
        only = [n for n in ALL if n in ("gun", "gorilla", "necro", "panzer", "phantom")]
    for name in (only or ALL):
        BUILDERS[name]()
        print("built:", name)
    print("ALL V6 MODELS GENERATED")
