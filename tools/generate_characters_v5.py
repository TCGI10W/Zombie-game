"""Fifth batch: skinned characters. One continuous, smoothly bending body
(skin-modifier anatomy + sculpted head) bound to a real armature, with
separate clothing layers in the photo-scanned cloth/denim/leather textures.

Bones carry the same names as the old joint pivots (Hips, Spine, Chest,
Head, Jaw, UpperArmL...), so the game's procedural rig, ragdolls and co-op
code drive them unchanged (scripts/enemies/skin_rig_adapter.gd).

Run with:  blender -b --factory-startup -P tools/generate_characters_v5.py [-- walker soldier runner survivor]
Convention: +Y forward (-Z in Godot), +Z up.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_models import clear_scene, export_glb, make_mat  # noqa: E402

V = Vector


# ---------------------------------------------------------------------------
# SKELETON
# ---------------------------------------------------------------------------
def joints(thin, bulk):
    j = {
        "Hips": V((0, 0, 0.98)), "Spine": V((0, 0, 1.06)), "Chest": V((0, 0, 1.25)),
        "Head": V((0, 0.02, 1.57)), "Jaw": V((0, 0.06, 1.68)),
    }
    for sx, nm in ((-1, "L"), (1, "R")):
        j["UpperArm" + nm] = V((sx * 0.235 * thin * bulk, 0, 1.47))
        j["Forearm" + nm] = V((sx * 0.265 * thin * bulk, -0.01, 1.2))
        j["Hand" + nm] = V((sx * 0.27 * thin * bulk, 0.01, 0.96))
        j["Thigh" + nm] = V((sx * 0.105, 0, 0.94))
        j["Shin" + nm] = V((sx * 0.115, 0.012, 0.52))
        j["Foot" + nm] = V((sx * 0.12, 0, 0.1))
    return j


PARENT = {"Hips": None, "Spine": "Hips", "Chest": "Spine", "Head": "Chest", "Jaw": "Head",
          "UpperArmL": "Chest", "ForearmL": "UpperArmL", "HandL": "ForearmL",
          "UpperArmR": "Chest", "ForearmR": "UpperArmR", "HandR": "ForearmR",
          "ThighL": "Hips", "ShinL": "ThighL", "FootL": "ShinL",
          "ThighR": "Hips", "ShinR": "ThighR", "FootR": "ShinR"}


def tails(j):
    t = {"Hips": j["Spine"], "Spine": j["Chest"], "Chest": V((0, 0.01, 1.52)),
         "Head": V((0, 0.03, 1.86)), "Jaw": V((0, 0.13, 1.63))}
    for nm in ("L", "R"):
        t["UpperArm" + nm] = j["Forearm" + nm]
        t["Forearm" + nm] = j["Hand" + nm]
        t["Hand" + nm] = j["Hand" + nm] + V((0, 0.03, -0.17))
        t["Thigh" + nm] = j["Shin" + nm]
        t["Shin" + nm] = j["Foot" + nm]
        t["Foot" + nm] = j["Foot" + nm] + V((0, 0.17, -0.07))
    return t


def build_armature(j):
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    t = tails(j)
    eb = {}
    for name in PARENT:
        b = arm_data.edit_bones.new(name)
        b.head = j[name]
        b.tail = t[name]
        eb[name] = b
    for name, par in PARENT.items():
        if par:
            eb[name].parent = eb[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ---------------------------------------------------------------------------
# SKIN WEIGHTS (distance to bone segments, smooth 2-bone blend)
# ---------------------------------------------------------------------------
def seg_dist(p, a, b):
    ab = b - a
    tt = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * tt - p).length


def weigh(obj, j, region_fn=None, force=None):
    t = tails(j)
    groups = {n: obj.vertex_groups.new(name=n) for n in PARENT}
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        if force:
            groups[force].add([v.index], 1.0, "REPLACE")
            continue
        cands = list(PARENT.keys())
        if region_fn:
            cands = region_fn(p) or cands
        ds = sorted(((seg_dist(p, j[n], t[n]), n) for n in cands))[:2]
        w = [1.0 / (d + 0.012) ** 4 for d, _ in ds]
        s = sum(w)
        for (d, n), wi in zip(ds, w):
            if wi / s > 0.02:
                groups[n].add([v.index], wi / s, "REPLACE")


def body_region(p):
    """Keep weights anatomically sane: legs never follow arms and so on."""
    side = "L" if p.x < 0 else "R"
    if p.z > 1.58:
        return ["Head", "Jaw"]
    if p.z > 1.45 and abs(p.x) < 0.09:
        return ["Chest", "Head"]
    if p.z < 0.9 and abs(p.x) > 0.03:
        return ["Thigh" + side, "Shin" + side, "Foot" + side]
    if abs(p.x) > 0.17 and p.z > 0.8:
        return ["Chest", "UpperArm" + side, "Forearm" + side, "Hand" + side]
    return ["Hips", "Spine", "Chest", "Thigh" + side, "UpperArm" + side]


def head_region(p):
    # Lower front of the face moves with the jaw
    return ["Jaw"] if (p.z < 1.665 and p.y > 0.02) else ["Head"]


# ---------------------------------------------------------------------------
# MESH HELPERS
# ---------------------------------------------------------------------------
def _activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_mods(obj):
    _activate(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def uv_and_smooth(obj):
    _activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")
    for poly in obj.data.polygons:
        poly.use_smooth = True


def skin_body(nodes, edges, name, subsurf=2):
    """nodes: list of (pos, (rx, ry)). Skin modifier -> organic quad mesh."""
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    me.from_pydata([n[0] for n in nodes], edges, [])
    me.update()
    sk = obj.modifiers.new("Skin", "SKIN")
    sk.branch_smoothing = 0.6
    sk.use_smooth_shade = True
    sv = me.skin_vertices[0].data
    for i, (_, r) in enumerate(nodes):
        sv[i].radius = r
    sv[0].use_root = True
    ss = obj.modifiers.new("Sub", "SUBSURF")
    ss.levels = subsurf
    ss.render_levels = subsurf
    apply_mods(obj)
    return obj


def ball(name, c, r, mat, segs=16, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=1.0, location=c)
    o = bpy.context.active_object
    o.name = name
    o.scale = r
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


def bump_noise(obj, amount, scale, seed):
    """Subtle surface irregularity so nothing looks machine-made."""
    rnd = random.Random(seed)
    off = V((rnd.random() * 50, rnd.random() * 50, rnd.random() * 50))
    from mathutils import noise
    me = obj.data
    me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
    for v in me.vertices:
        n = noise.noise((v.co * scale) + off)
        v.co += v.normal * n * amount


# ---------------------------------------------------------------------------
# HEAD
# ---------------------------------------------------------------------------
def sculpt_head(name, center, mat, gaunt):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=30, radius=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name

    def g(p, c, s):
        return math.exp(-((p - V(c)).length_squared) / (s * s))

    for v in o.data.vertices:
        p = v.co.copy() # unit sphere
        x, y, z = p.x, p.y, p.z
        # Skull proportions: narrower sides, deeper front-to-back
        q = V((x * 0.092, y * 0.112, z * 0.122))
        # Jaw and chin taper; the back of the skull bulges
        if z < -0.2:
            q.x *= 1.0 - 0.28 * min(1.0, (-z - 0.2) / 0.8)
        if y < -0.2 and z > -0.3:
            q.y *= 1.06
        # Brow ridge, sunken eyes, cheekbones, gaunt cheeks, nose, lips, chin
        front = max(0.0, y)
        q.y += 0.02 * g(p, (0, 0.92, 0.36), 0.3) * front
        for sx in (-1, 1):
            q.y -= 0.022 * g(p, (sx * 0.37, 0.88, 0.16), 0.2)
            q.x += sx * 0.006 * g(p, (sx * 0.62, 0.66, -0.02), 0.25)
            q.y -= gaunt * g(p, (sx * 0.55, 0.62, -0.36), 0.25)
        q.y += 0.042 * g(p, (0, 1.0, -0.06), 0.13) + 0.014 * g(p, (0, 0.98, 0.08), 0.12)
        q.y += 0.006 * g(p, (0, 0.95, -0.43), 0.15)
        q.y -= 0.006 * g(p, (0, 0.96, -0.52), 0.07)
        q.y += 0.012 * g(p, (0, 0.85, -0.82), 0.2)
        v.co = q + V(center)
    o.data.materials.append(mat)
    bump_noise(o, 0.0025, 30.0, hash(name) % 1000)
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


# ---------------------------------------------------------------------------
# CLOTHING: copies of body regions pushed slightly outward
# ---------------------------------------------------------------------------
def cloth_from(body, name, keep_fn, push, mat, ragged=0.0, seed=1):
    o = body.copy()
    o.data = body.data.copy()
    o.name = name
    bpy.context.scene.collection.objects.link(o)
    o.vertex_groups.clear()
    bm = bmesh.new()
    bm.from_mesh(o.data)
    rnd = random.Random(seed)
    kill = [f for f in bm.faces if not keep_fn(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    if ragged > 0.0:
        # Tear the hems: drop random faces along open edges
        for _ in range(2):
            edge_faces = {f for e in bm.edges if e.is_boundary for f in e.link_faces}
            torn = [f for f in edge_faces if rnd.random() < ragged]
            bmesh.ops.delete(bm, geom=torn, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * push
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


# ---------------------------------------------------------------------------
# CHARACTER
# ---------------------------------------------------------------------------
def build_character(style):
    clear_scene()
    random.seed(hash(style) % 1000)
    survivor = style == "survivor"
    thin = 0.88 if style == "runner" else 1.0
    bulk = 1.08 if style in ("soldier", "survivor") else 1.0
    gaunt = 0.0 if survivor else (0.018 if style == "runner" else 0.012)

    if survivor:
        m_skin = make_mat("SurvivorSkin", (0.58, 0.42, 0.33, 1), roughness=0.55)
    else:
        tint = {"walker": (0.62, 0.68, 0.55, 1), "soldier": (0.55, 0.6, 0.5, 1), "runner": (0.5, 0.48, 0.45, 1)}[style]
        m_skin = make_mat("Skin", tint, roughness=0.65, tex_prefix="zombie_skin")
    m_gore = make_mat("Gore", (0.05, 0.006, 0.005, 1), roughness=0.55)
    m_bone = make_mat("Bone", (0.36, 0.31, 0.22, 1), roughness=0.6)
    m_dark = make_mat("Socket", (0.03, 0.02, 0.02, 1), roughness=0.9)
    if survivor:
        m_eye = make_mat("SurvivorEye", (0.06, 0.05, 0.04, 1), roughness=0.1)
    else:
        ec = (1.0, 0.15, 0.08) if style == "runner" else (1.0, 0.7, 0.12)
        m_eye = make_mat("Eye", (*ec, 1), roughness=0.2, emission=ec, emission_strength=1.4)
    m_hair = make_mat("Hair", (0.07, 0.06, 0.05, 1), roughness=0.9, tex_prefix="burlap")
    m_leather = make_mat("BeltLeather", (0.15, 0.1, 0.07, 1), roughness=0.6, tex_prefix="leather")
    if style == "walker":
        m_shirt = make_mat("Shirt", (0.14, 0.16, 0.19, 1), roughness=0.9, tex_prefix="fabric")
        m_pants = make_mat("Pants", (0.7, 0.75, 0.85, 1), roughness=0.9, tex_prefix="denim")
        m_shoe = make_mat("Shoe", (0.25, 0.18, 0.12, 1), roughness=0.7, tex_prefix="leather")
    elif style in ("soldier", "survivor"):
        m_shirt = make_mat("Uniform", (0.75, 0.75, 0.7, 1), roughness=0.9, tex_prefix="camo")
        m_pants = m_shirt
        m_shoe = make_mat("Boot", (0.12, 0.11, 0.1, 1), roughness=0.6, tex_prefix="leather")
    else:
        m_shirt = make_mat("TankTop", (0.28, 0.05, 0.05, 1), roughness=0.9, tex_prefix="fabric")
        m_pants = make_mat("Trousers", (0.16, 0.15, 0.14, 1), roughness=0.9, tex_prefix="fabric")
        m_shoe = None

    j = joints(thin, bulk)
    arm = build_armature(j)

    # --- Body: one continuous skin-modifier mesh -------------------------
    b = bulk
    nodes = [
        (V((0, 0, 0.9)), (0.14 * b, 0.105)),      # 0 pelvis
        (V((0, 0, 1.03)), (0.125 * b * thin, 0.095)),  # 1 waist
        (V((0, 0.012, 1.17)), (0.14 * b * thin, 0.11)),  # 2 belly
        (V((0, 0.0, 1.31)), (0.17 * b * thin, 0.125)),  # 3 chest
        (V((0, -0.005, 1.43)), (0.165 * b * thin, 0.105)),  # 4 upper chest
        (V((0, 0.0, 1.5)), (0.075, 0.068)),        # 5 neck base
        (V((0, 0.02, 1.67)), (0.062, 0.062)),      # 6 neck top (into the head)
    ]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)]
    for sx, nm in ((-1, "L"), (1, "R")):
        i0 = len(nodes)
        sh = j["UpperArm" + nm]
        nodes += [
            (V((sx * 0.12 * b * thin, -0.01, 1.49)), (0.075, 0.065)),  # trapezius
            (sh, (0.066 * b * thin, 0.064 * b * thin)),
            (sh.lerp(j["Forearm" + nm], 0.5), (0.054 * b * thin, 0.058 * b * thin)),
            (j["Forearm" + nm], (0.044 * thin, 0.045 * thin)),
            (j["Forearm" + nm].lerp(j["Hand" + nm], 0.45), (0.046 * thin, 0.04 * thin)),
            (j["Hand" + nm], (0.028, 0.022)),
            (j["Hand" + nm] + V((0, 0.012, -0.07)), (0.04, 0.016)),  # palm
        ]
        edges += [(4, i0), (i0, i0 + 1), (i0 + 1, i0 + 2), (i0 + 2, i0 + 3), (i0 + 3, i0 + 4), (i0 + 4, i0 + 5), (i0 + 5, i0 + 6)]
        palm = i0 + 6
        for f in range(4):
            fx = (f - 1.5) * 0.017
            k = len(nodes)
            base = j["Hand" + nm] + V((sx * fx * 0.6 + sx * 0.0, 0.012, -0.1))
            nodes += [(base, (0.009, 0.008)), (base + V((0, 0.02, -0.045)), (0.008, 0.007)),
                      (base + V((0, 0.045, -0.07)), (0.006, 0.006))]
            edges += [(palm, k), (k, k + 1), (k + 1, k + 2)]
        k = len(nodes)
        nodes += [(j["Hand" + nm] + V((-sx * 0.025, 0.03, -0.04)), (0.01, 0.009)),
                  (j["Hand" + nm] + V((-sx * 0.035, 0.06, -0.075)), (0.008, 0.007))]
        edges += [(palm, k), (k, k + 1)]
        # legs
        i1 = len(nodes)
        hp, kn, an = j["Thigh" + nm], j["Shin" + nm], j["Foot" + nm]
        nodes += [
            (hp + V((0, 0, -0.04)), (0.085 * b, 0.09 * b)),
            (hp.lerp(kn, 0.5), (0.078 * b * thin, 0.082 * b * thin)),
            (kn, (0.052 * thin, 0.055)),
            (kn.lerp(an, 0.35) + V((0, -0.012, 0)), (0.05 * thin, 0.055 * thin)),  # calf
            (an + V((0, 0, 0.03)), (0.034, 0.036)),
            (an + V((0, 0.07, -0.05)), (0.042, 0.03)),
            (an + V((0, 0.16, -0.075)), (0.04, 0.022)),
        ]
        edges += [(0, i1), (i1, i1 + 1), (i1 + 1, i1 + 2), (i1 + 2, i1 + 3), (i1 + 3, i1 + 4), (i1 + 4, i1 + 5), (i1 + 5, i1 + 6)]
    body = skin_body(nodes, edges, "Body", subsurf=2)
    bump_noise(body, 0.003, 18.0, 7)
    body.data.materials.append(m_skin)
    uv_and_smooth(body)

    # --- Head -------------------------------------------------------------
    # Head built from overlapping forms (skull, face, brow, nose, jaw)
    head = ball("Skull", (0, 0.035, 1.73), (0.102, 0.118, 0.122), m_skin, 32, 24)
    bump_noise(head, 0.002, 30.0, 5)
    parts = [head,
             ball("Face", (0, 0.072, 1.7), (0.082, 0.068, 0.072), m_skin, 24, 16),
             ball("Brow", (0, 0.112, 1.766), (0.074, 0.024, 0.016), m_skin, 20, 12),
             ball("Nose", (0, 0.148, 1.718), (0.014, 0.018, 0.024), m_skin, 14, 10),
             ball("Cheekbones", (0, 0.098, 1.722), (0.078, 0.04, 0.022), m_skin, 20, 12),
             ball("JawMesh", (0, 0.1, 1.648), (0.056, 0.046, 0.024), m_skin, 20, 12)]
    for sx, nm in ((-1, "L"), (1, "R")):
        if not survivor:
            parts.append(ball("Socket" + nm, (sx * 0.038, 0.13, 1.738), (0.02, 0.01, 0.014), m_dark))
        parts.append(ball("Eye" + nm, (sx * 0.038, 0.137, 1.738), (0.0095, 0.007, 0.0085), m_eye))
        parts.append(ball("Ear" + nm, (sx * 0.102, 0.03, 1.72), (0.012, 0.025, 0.035), m_skin))
    for i in range(5):
        parts.append(ball("Tooth%d" % i, (-0.026 + i * 0.013, 0.14, 1.666), (0.005, 0.004, 0.008), m_bone, 8, 6))
    for o in parts:
        uv_and_smooth(o)
    if style in ("soldier", "survivor"):
        hm = make_mat("HelmetSteel", (0.24, 0.27, 0.18, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal")
        h = ball("Helmet", (0, 0.025, 1.79), (0.125, 0.14, 0.09), hm, 24, 16)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        bm = bmesh.new()
        bm.from_mesh(h.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -0.015], context="FACES")
        bm.to_mesh(h.data)
        bm.free()
        sol = h.modifiers.new("Thick", "SOLIDIFY")
        sol.thickness = 0.008
        apply_mods(h)
        parts.append(h)
    else:
        hair = ball("Hair", (0, 0.0, 1.785), (0.106, 0.12, 0.072), m_hair, 24, 16)
        bm = bmesh.new()
        bm.from_mesh(hair.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < -0.025 or
                                   (f.calc_center_median().y > 0.07 and f.calc_center_median().z < 0.01)], context="FACES")
        bm.to_mesh(hair.data)
        bm.free()
        bump_noise(hair, 0.006, 40.0, 3)
        uv_and_smooth(hair)
        parts.append(hair)

    # --- Clothes -------------------------------------------------------------
    cloth = []
    if style == "walker":
        cloth.append(cloth_from(body, "ShirtMesh", lambda c: 1.0 < c.z < 1.53 and (abs(c.x) < 0.2 or (c.x > 0 and c.z > 1.27)), 0.011, m_shirt, 0.35, 11))
    elif style == "runner":
        cloth.append(cloth_from(body, "ShirtMesh", lambda c: 1.08 < c.z < 1.46 and abs(c.x) < 0.17 and not (c.y > 0.05 and c.z < 1.2), 0.009, m_shirt, 0.45, 12))
    else:
        cloth.append(cloth_from(body, "ShirtMesh", lambda c: 0.98 < c.z < 1.53 and (abs(c.x) < 0.2 or c.z > 1.0), 0.012, m_shirt, 0.08, 13))
    pants_top = 1.07
    cloth.append(cloth_from(body, "PantsMesh", lambda c: c.z < pants_top and c.z > (0.17 if style != "runner" else 0.36) and abs(c.x) < 0.2, 0.009, m_pants, 0.25 if style == "runner" else 0.06, 14))
    if m_shoe:
        cloth.append(cloth_from(body, "ShoeMesh", lambda c: c.z < 0.2 and abs(c.x) < 0.2, 0.008, m_shoe, 0.0, 15))
    for c in cloth:
        uv_and_smooth(c)
    if style != "runner":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.135 * bulk, minor_radius=0.018, location=(0, 0, 1.055))
        belt = bpy.context.active_object
        belt.name = "Belt"
        belt.scale = (1.0, 0.78, 0.9)
        bpy.ops.object.transform_apply(scale=True)
        belt.data.materials.append(m_leather)
        cloth.append(belt)
    if style in ("soldier", "survivor"):
        vm = make_mat("Vest", (0.22, 0.24, 0.17, 1), roughness=0.8, tex_prefix="fabric")
        cloth.append(cloth_from(body, "VestMesh", lambda c: 1.12 < c.z < 1.47 and abs(c.x) < 0.17, 0.03, vm, 0.0, 16))
        for x in (-0.09, 0.0, 0.09):
            p = ball("Pouch", (x, 0.135, 1.22), (0.035, 0.022, 0.045), make_mat("Pouch", (0.25, 0.27, 0.18, 1), roughness=0.85, tex_prefix="fabric"), 12, 8)
            cloth.append(p)

    # --- Wounds (zombies only) -------------------------------------------
    gore = []
    if not survivor:
        # Torn flesh as thin dark patches (blood is in the cloth textures)
        for i, (x, z, rx, rz) in enumerate([(-0.07, 1.36, 0.04, 0.03), (0.06, 1.21, 0.035, 0.022)]):
            gore.append(ball("Wound%d" % i, (x, 0.121, z), (rx, 0.003, rz), m_gore, 12, 8))
        if style == "runner":
            gore.append(ball("Guts", (0.03, 0.1, 1.13), (0.055, 0.02, 0.045), m_gore, 12, 8))

    # --- Bind everything to the armature ----------------------------------
    weigh(body, j, body_region)
    for c in cloth:
        weigh(c, j, body_region)
    for p in parts:
        if p.name.startswith("Tooth"):
            weigh(p, j, force="Jaw")
        elif p.name == "JawMesh":
            weigh(p, j, force="Jaw")
        else:
            weigh(p, j, head_region)
    for g in gore:
        weigh(g, j, body_region)
    meshes = [body] + parts + cloth + gore
    for m in meshes:
        m.parent = arm
        mod = m.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    name = "player_survivor.glb" if survivor else "zombie_%s_v2.glb" % style
    export_glb(name)


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for st in (only or ["walker", "soldier", "runner", "survivor"]):
        build_character(st)
    print("ALL V5 CHARACTERS GENERATED")
