"""Third batch of Blender models:
- Fully jointed zombies (hips/spine/chest/neck/jaw, shoulders/elbows/wrists,
  hips/knees/ankles) in three styles: civilian walker, soldier, runner.
- All first-person guns rebuilt WITH gloved arms and named moving parts
  (SlidePivot, BoltPivot, PumpPivot, MagPivot, CylinderPivot, ArmL, ArmR).
- Knife and grenade hands.
- Map props: lamp post, generator, wrecked car, dead tree, barbed wire,
  rubble, crate, gurney, lockers, desk, skull, radio tower, trap pylon,
  tire stack, fuel tank.

Run with:  blender -b --factory-startup -P tools/generate_models_v3.py
Convention: +Y forward (-Z in Godot), +Z up. Pivots sit on joints.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_models import TEX_DIR, add_part, add_pivot, export_glb, make_mat  # noqa: E402
from generate_models import clear_scene as _gm_clear_scene  # noqa: E402

import numpy as np  # noqa: E402

R90 = math.radians(90)


def clear_scene():
    _gm_clear_scene()  # also empties the shared texture caches


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
def _finish(obj, mat, parent, bevel=0.0, subsurf=0):
    if bevel > 0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel
        bev.segments = 2
        bev.limit_method = "ANGLE"
    if subsurf > 0:
        sub = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        sub.levels = subsurf
        sub.render_levels = subsurf
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if mat:
        obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def seg(name, p0, p1, r0, r1, mat, parent=None, verts=10, subsurf=0):
    """Tapered limb segment from p0 (radius r0) to p1 (radius r1)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    length = max(d.length, 0.001)
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=length, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.translate(bm, vec=(0, 0, length / 2), verts=bm.verts)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=p0, verts=bm.verts)
    bm.to_mesh(obj.data)
    bm.free()
    return _finish(obj, mat, parent, bevel=min(r0, r1) * 0.3, subsurf=subsurf)


def blob(name, center, size, mat, parent=None, rot=(0, 0, 0), subsurf=1, bevel=None):
    """Rounded box (organic when subsurf=1)."""
    b = bevel if bevel is not None else min(size) * 0.3
    return add_part(name, "CUBE", (0, 0, 0), size, rot=rot, mat=mat, parent=parent, bevel=b, subsurf=subsurf, offset=center)


def ball(name, center, radii, mat, parent=None):
    return add_part(name, "SPHERE", (0, 0, 0), (radii[0] * 2, radii[1] * 2, radii[2] * 2), mat=mat, parent=parent, bevel=0, offset=center)


def box(name, center, size, mat, parent=None, rot=(0, 0, 0), bevel=0.01):
    return add_part(name, "CUBE", (0, 0, 0), size, rot=rot, mat=mat, parent=parent, bevel=bevel, offset=center)


def cyl(name, center, radius, depth, mat, parent=None, rot=(0, 0, 0), bevel=0.005):
    return add_part(name, "CYLINDER", (0, 0, 0), (radius * 2, radius * 2, depth), rot=rot, mat=mat, parent=parent, bevel=bevel, offset=center)


def torus(name, center, major, minor, mat, parent=None, rot=(0, 0, 0), seg_major=24):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg_major, minor_segments=8, location=(0, 0, 0), rotation=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if rot != (0, 0, 0):
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot, "XYZ").to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    bm.to_mesh(obj.data)
    bm.free()
    return _finish(obj, mat, parent)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


# ---------------------------------------------------------------------------
# ZOMBIES
# ---------------------------------------------------------------------------
def build_zombie(style):
    clear_scene()
    skin_tint = {"walker": (0.62, 0.68, 0.55, 1), "soldier": (0.55, 0.6, 0.5, 1), "runner": (0.5, 0.48, 0.45, 1)}[style]
    m_skin = make_mat("Skin", skin_tint, roughness=0.65, tex_prefix="zombie_skin")
    m_gore = make_mat("Gore", (0.07, 0.006, 0.005, 1), roughness=0.3)
    m_bone = make_mat("Bone", (0.32, 0.27, 0.18, 1), roughness=0.6)
    m_dark = make_mat("Socket", (0.03, 0.02, 0.02, 1), roughness=0.9)
    eye_col = (1.0, 0.15, 0.08) if style == "runner" else (1.0, 0.7, 0.12)
    m_eye = make_mat("Eye", (*eye_col, 1), roughness=0.2, emission=eye_col, emission_strength=1.2)
    m_hair = make_mat("Hair", (0.07, 0.06, 0.05, 1), roughness=0.9)
    if style == "walker":
        m_shirt = make_mat("Shirt", (0.14, 0.16, 0.19, 1), roughness=0.9, tex_prefix="fabric")
        m_pants = make_mat("Pants", (0.7, 0.75, 0.85, 1), roughness=0.9, tex_prefix="denim")
        m_shoe = make_mat("Shoe", (0.25, 0.18, 0.12, 1), roughness=0.7, tex_prefix="leather")
    elif style == "soldier":
        m_shirt = make_mat("Uniform", (0.75, 0.75, 0.7, 1), roughness=0.9, tex_prefix="camo")
        m_pants = m_shirt
        m_shoe = make_mat("Boot", (0.12, 0.11, 0.1, 1), roughness=0.6, tex_prefix="leather")
    else:
        m_shirt = make_mat("TankTop", (0.28, 0.05, 0.05, 1), roughness=0.9, tex_prefix="fabric")
        m_pants = make_mat("Trousers", (0.16, 0.15, 0.14, 1), roughness=0.9, tex_prefix="fabric")
        m_shoe = m_skin

    thin = 0.85 if style == "runner" else 1.0
    bulk = 1.1 if style == "soldier" else 1.0

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    blob("Pelvis", (0, 0, 0.97), (0.36 * bulk, 0.22, 0.2), m_pants, hips)
    if style != "runner":
        box("Belt", (0, 0.0, 1.06), (0.37 * bulk, 0.23, 0.05), make_mat("BeltLeather", (0.15, 0.1, 0.07, 1), roughness=0.6), hips, bevel=0.01)

    spine = add_pivot("Spine", (0, 0, 1.06), parent=hips)
    blob("Abdomen", (0, 0.0, 1.17), (0.32 * thin * bulk, 0.2, 0.24), m_shirt, spine)
    if style == "runner":
        # Bare torn belly with guts showing
        ball("Guts", (0.04, 0.08, 1.14), (0.08, 0.05, 0.07), m_gore, spine)

    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    blob("ChestMesh", (0, 0.0, 1.39), (0.44 * thin * bulk, 0.26 * bulk, 0.34), m_shirt, chest)
    # Torn chest wound with ribs
    # Torn, irregular wound (no neat shapes)
    for i, (x, z, rx, rz) in enumerate([(-0.1, 1.4, 0.07, 0.05), (-0.06, 1.35, 0.05, 0.06), (-0.13, 1.33, 0.035, 0.04), (0.07, 1.22, 0.06, 0.035)]):
        ball("Wound%d" % i, (x, 0.112, z), (rx, 0.018, rz), m_gore, chest)
    box("RibA", (-0.11, 0.128, 1.38), (0.05, 0.008, 0.009), m_bone, chest, rot=(0, 0.4, 0), bevel=0.002)
    if style == "soldier":
        blob("Vest", (0, 0.01, 1.38), (0.48, 0.3, 0.3), make_mat("Vest", (0.22, 0.24, 0.17, 1), roughness=0.8, tex_prefix="fabric"), chest)
        for x in (-0.13, 0.0, 0.13):
            blob("Pouch", (x, 0.165, 1.3), (0.09, 0.05, 0.1), make_mat("Pouch", (0.25, 0.27, 0.18, 1), roughness=0.85), chest)
    if style == "runner":
        for i in range(5):
            ball("SpineBone%d" % i, (0, -0.13, 1.18 + i * 0.065), (0.025, 0.02, 0.022), m_bone, chest)

    # Head & neck
    head = add_pivot("Head", (0, 0.02, 1.57), parent=chest)
    seg("Neck", (0, 0.01, 1.52), (0, 0.03, 1.66), 0.055, 0.05, m_skin, head)
    ball("Skull", (0, 0.035, 1.73), (0.105, 0.12, 0.125), m_skin, head)
    blob("Brow", (0, 0.115, 1.768), (0.15, 0.045, 0.03), m_skin, head, subsurf=2)
    blob("Nose", (0, 0.15, 1.72), (0.025, 0.03, 0.04), m_skin, head, subsurf=2)
    ball("Face", (0, 0.07, 1.7), (0.085, 0.07, 0.07), m_skin, head)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Socket" + nm, (sx * 0.042, 0.122, 1.742), (0.024, 0.014, 0.016), m_dark, head)
        ball("Eye" + nm, (sx * 0.042, 0.13, 1.742), (0.009, 0.007, 0.008), m_eye, head)
        ball("Ear" + nm, (sx * 0.105, 0.03, 1.72), (0.012, 0.025, 0.035), m_skin, head)
    if style == "soldier":
        ball("Helmet", (0, 0.025, 1.79), (0.135, 0.15, 0.1), make_mat("HelmetSteel", (0.24, 0.27, 0.18, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal"), head)
        cyl("HelmetRim", (0, 0.025, 1.76), 0.145, 0.025, make_mat("HelmetRim", (0.2, 0.22, 0.15, 1), roughness=0.6), head)
    else:
        ball("Hair", (0, 0.0, 1.785), (0.104, 0.118, 0.07), m_hair, head)
        ball("ScalpWound", (0.05, 0.04, 1.845), (0.035, 0.035, 0.012), m_gore, head)
    jaw = add_pivot("Jaw", (0, 0.06, 1.68), parent=head)
    blob("JawMesh", (0, 0.105, 1.645), (0.11, 0.09, 0.045), m_skin, jaw, subsurf=2)
    for i in range(5):
        box("Tooth%d" % i, (-0.03 + i * 0.015, 0.145, 1.668), (0.009, 0.008, 0.016), m_bone, jaw, bevel=0.002)

    # Arms: hang down in the rest pose
    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * 0.25 * thin * bulk, 0.0, 1.49)
        el = (sx * 0.27 * thin * bulk, 0.0, 1.21)
        wr = (sx * 0.27 * thin * bulk, 0.01, 0.96)
        upper = add_pivot("UpperArm" + nm, sh, parent=chest)
        ball("Shoulder" + nm, sh, (0.062 * bulk, 0.062 * bulk, 0.06), m_shirt, upper)
        sleeve_mat = m_shirt if (style == "soldier" or (style == "walker" and nm == "R")) else m_skin
        seg("UpperArmMesh" + nm, sh, el, 0.062 * thin * bulk, 0.052 * thin * bulk, sleeve_mat, upper)
        fore = add_pivot("Forearm" + nm, el, parent=upper)
        ball("Elbow" + nm, el, (0.05, 0.05, 0.05), m_skin if sleeve_mat == m_skin else sleeve_mat, fore)
        seg("ForearmMesh" + nm, el, wr, 0.048 * thin, 0.038 * thin, m_skin if style != "soldier" else m_shirt, fore)
        if nm == "L" and style == "walker":
            seg("ExposedBone" + nm, add(el, (0, 0.03, -0.05)), add(wr, (0, 0.03, 0.05)), 0.012, 0.01, m_bone, fore)
            ball("ArmWound" + nm, add(el, (0, 0.035, -0.12)), (0.035, 0.02, 0.06), m_gore, fore)
        hand = add_pivot("Hand" + nm, wr, parent=fore)
        blob("Palm" + nm, add(wr, (0, 0.01, -0.06)), (0.06, 0.035, 0.09), m_skin, hand)
        for i, fy in enumerate((-0.012, 0.0, 0.012, 0.024)):
            f0 = add(wr, (sx * -0.0 + (i - 1.5) * 0.014 * sx * 0 + (i - 1.5) * 0.014, 0.022, -0.1))
            f1 = add(f0, (0, 0.035, -0.06))
            seg("Finger%s%d" % (nm, i), f0, f1, 0.009, 0.006, m_skin, hand, verts=6)
            ball("Claw%s%d" % (nm, i), f1, (0.007, 0.01, 0.012), m_dark, hand)
        seg("Thumb" + nm, add(wr, (-sx * 0.03, 0.02, -0.05)), add(wr, (-sx * 0.035, 0.06, -0.08)), 0.01, 0.007, m_skin, hand, verts=6)

    # Legs
    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.11, 0.0, 0.94)
        kn = (sx * 0.12, 0.01, 0.52)
        an = (sx * 0.12, 0.0, 0.1)
        thigh = add_pivot("Thigh" + nm, hp, parent=hips)
        seg("ThighMesh" + nm, hp, kn, 0.088 * bulk, 0.068 * bulk, m_pants, thigh)
        shin = add_pivot("Shin" + nm, kn, parent=thigh)
        ball("Knee" + nm, kn, (0.065 * bulk, 0.065 * bulk, 0.06), m_pants, shin)
        bare_shin = style == "runner" or (style == "walker" and nm == "L")
        if bare_shin:
            seg("ShinCloth" + nm, kn, add(kn, (0, 0, -0.14)), 0.068, 0.072, m_pants, shin)
            seg("ShinMesh" + nm, add(kn, (0, 0, -0.1)), an, 0.05, 0.038, m_skin, shin)
        else:
            seg("ShinMesh" + nm, kn, an, 0.064 * bulk, 0.05 * bulk, m_pants, shin)
        foot = add_pivot("Foot" + nm, an, parent=shin)
        bare_foot = style == "runner" or (style == "walker" and nm == "L")
        fmat = m_skin if bare_foot else m_shoe
        blob("FootMesh" + nm, add(an, (0, 0.06, -0.05)), (0.1, 0.25 if not bare_foot else 0.22, 0.09 if not bare_foot else 0.07), fmat, foot)
        if style == "soldier":
            seg("BootTop" + nm, add(an, (0, 0, -0.02)), add(an, (0, 0, 0.16)), 0.058, 0.06, m_shoe, foot)

    export_glb("zombie_%s_v2.glb" % style)


# ---------------------------------------------------------------------------
# FIRST-PERSON ARMS
# ---------------------------------------------------------------------------
def arm_mats():
    sleeve = make_mat("Sleeve", (0.7, 0.7, 0.65, 1), roughness=0.9, tex_prefix="camo")
    glove = make_mat("Glove", (0.12, 0.11, 0.1, 1), roughness=0.55, tex_prefix="leather")
    cuff = make_mat("Cuff", (0.12, 0.12, 0.11, 1), roughness=0.8)
    return sleeve, glove, cuff


def right_arm(root, hand, mats, arm_dir=(0.17, -0.27, -0.21)):
    """Right hand gripping a pistol grip that runs roughly along Z at `hand`."""
    sleeve, glove, cuff = mats
    piv = add_pivot("ArmR", hand, parent=root)
    blob("PalmR", add(hand, (0.022, -0.006, 0.0)), (0.028, 0.07, 0.085), glove, piv)
    blob("FingersR", add(hand, (0.004, 0.03, -0.006)), (0.055, 0.03, 0.078), glove, piv)
    for i in range(4):
        ball("KnuckleR%d" % i, add(hand, (0.012, 0.045, 0.025 - i * 0.018)), (0.012, 0.01, 0.009), glove, piv)
    seg("ThumbR", add(hand, (-0.012, -0.01, 0.03)), add(hand, (-0.022, 0.03, 0.04)), 0.012, 0.009, glove, piv, verts=8)
    wrist = add(hand, (0.03, -0.055, -0.03))
    seg("WristR", add(hand, (0.022, -0.03, -0.012)), wrist, 0.032, 0.034, glove, piv)
    elbow = add(wrist, arm_dir)
    seg("CuffR", wrist, add(wrist, (arm_dir[0] * 0.12, arm_dir[1] * 0.12, arm_dir[2] * 0.12)), 0.04, 0.042, cuff, piv)
    seg("ForearmR", add(wrist, (arm_dir[0] * 0.1, arm_dir[1] * 0.1, arm_dir[2] * 0.1)), elbow, 0.042, 0.055, sleeve, piv)
    seg("UpperArmR", elbow, add(elbow, (0.12, -0.25, -0.05)), 0.058, 0.065, sleeve, piv)
    return piv


def left_arm_support(root, hand, mats, parent=None, arm_dir=(-0.2, -0.24, -0.2)):
    """Left hand cupping a horizontal handguard/barrel at `hand`."""
    sleeve, glove, cuff = mats
    piv = add_pivot("ArmL", hand, parent=parent or root)
    blob("PalmL", add(hand, (0.0, 0.0, -0.028)), (0.062, 0.08, 0.026), glove, piv)
    blob("FingersL", add(hand, (0.032, 0.008, -0.004)), (0.022, 0.075, 0.05), glove, piv)
    blob("ThumbL", add(hand, (-0.03, 0.01, 0.0)), (0.018, 0.055, 0.02), glove, piv)
    wrist = add(hand, (-0.035, -0.055, -0.05))
    seg("WristL", add(hand, (-0.015, -0.03, -0.03)), wrist, 0.032, 0.034, glove, piv)
    elbow = add(wrist, arm_dir)
    seg("CuffL", wrist, add(wrist, (arm_dir[0] * 0.12, arm_dir[1] * 0.12, arm_dir[2] * 0.12)), 0.04, 0.042, cuff, piv)
    seg("ForearmL", add(wrist, (arm_dir[0] * 0.1, arm_dir[1] * 0.1, arm_dir[2] * 0.1)), elbow, 0.042, 0.055, sleeve, piv)
    seg("UpperArmL", elbow, add(elbow, (-0.12, -0.25, -0.05)), 0.058, 0.065, sleeve, piv)
    return piv


def left_arm_pistol(root, hand, mats):
    """Left hand wrapped around the right hand on a pistol grip."""
    sleeve, glove, cuff = mats
    piv = add_pivot("ArmL", hand, parent=root)
    blob("PalmL", add(hand, (-0.03, -0.004, -0.01)), (0.026, 0.07, 0.08), glove, piv)
    blob("FingersL", add(hand, (-0.002, 0.042, -0.02)), (0.06, 0.026, 0.06), glove, piv)
    wrist = add(hand, (-0.035, -0.06, -0.045))
    seg("WristL", add(hand, (-0.03, -0.03, -0.02)), wrist, 0.032, 0.034, glove, piv)
    arm_dir = (-0.15, -0.26, -0.22)
    elbow = add(wrist, arm_dir)
    seg("CuffL", wrist, add(wrist, (arm_dir[0] * 0.12, arm_dir[1] * 0.12, arm_dir[2] * 0.12)), 0.04, 0.042, cuff, piv)
    seg("ForearmL", add(wrist, (arm_dir[0] * 0.1, arm_dir[1] * 0.1, arm_dir[2] * 0.1)), elbow, 0.042, 0.055, sleeve, piv)
    seg("UpperArmL", elbow, add(elbow, (-0.1, -0.25, -0.05)), 0.058, 0.065, sleeve, piv)
    return piv


def gun_mats(prefix):
    steel = make_mat(prefix + "Steel", (0.13, 0.135, 0.15, 1), metallic=0.8, roughness=0.38, tex_prefix="gunmetal")
    dark = make_mat(prefix + "Dark", (0.08, 0.085, 0.095, 1), metallic=0.7, roughness=0.45)
    wood = make_mat(prefix + "Wood", (0.32, 0.17, 0.09, 1), roughness=0.66, tex_prefix="wood_grain")
    sight = make_mat(prefix + "Sight", (0.25, 1.0, 0.45, 1), roughness=0.2, emission=(0.25, 1.0, 0.45), emission_strength=1.5)
    brass = make_mat(prefix + "Brass", (0.8, 0.6, 0.25, 1), metallic=0.95, roughness=0.3)
    return steel, dark, wood, sight, brass


# ---------------------------------------------------------------------------
# GUNS (sight lines match GameState ads_pos values)
# ---------------------------------------------------------------------------
def build_pistol():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Pst")
    r = add_pivot("Root")
    slide = add_pivot("SlidePivot", (0, 0, 0.04), parent=r)
    box("Slide", (0, 0.08, 0.04), (0.042, 0.26, 0.046), steel, slide, bevel=0.006)
    for i in range(5):
        box("Serration%d" % i, (0, -0.02 + i * 0.012, 0.064), (0.044, 0.004, 0.004), dark, slide, bevel=0.0)
    for sx in (-0.011, 0.011):
        box("RearSight", (sx, -0.035, 0.068), (0.008, 0.012, 0.012), sight, slide, bevel=0.001)
    box("FrontSight", (0, 0.195, 0.068), (0.006, 0.012, 0.013), sight, slide, bevel=0.001)
    box("Frame", (0, 0.06, 0.008), (0.038, 0.22, 0.028), dark, r, bevel=0.004)
    cyl("Barrel", (0, 0.22, 0.042), 0.009, 0.06, dark, r, rot=(R90, 0, 0))
    box("Grip", (0, -0.02, -0.055), (0.036, 0.062, 0.125), wood, r, rot=(math.radians(16), 0, 0), bevel=0.006)
    box("TriggerGuard", (0, 0.04, -0.01), (0.008, 0.06, 0.008), dark, r)
    mag = add_pivot("MagPivot", (0, -0.025, -0.07), parent=r)
    box("Mag", (0, -0.03, -0.11), (0.03, 0.05, 0.06), dark, mag, rot=(math.radians(16), 0, 0))
    mats = arm_mats()
    right_arm(r, (0.0, -0.025, -0.055), mats)
    left_arm_pistol(r, (-0.01, -0.02, -0.065), mats)
    export_glb("vm_pistol.glb")


def build_smg():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Smg")
    r = add_pivot("Root")
    box("Receiver", (0, 0.06, 0.03), (0.05, 0.30, 0.07), steel, r, bevel=0.006)
    cyl("Shroud", (0, 0.28, 0.035), 0.028, 0.16, dark, r, rot=(R90, 0, 0))
    for i in range(4):
        cyl("Vent%d" % i, (0, 0.22 + i * 0.035, 0.035), 0.03, 0.008, steel, r, rot=(R90, 0, 0))
    cyl("Barrel", (0, 0.39, 0.035), 0.012, 0.1, steel, r, rot=(R90, 0, 0))
    mag = add_pivot("MagPivot", (0, 0.11, -0.01), parent=r)
    box("Mag", (0, 0.11, -0.1), (0.03, 0.05, 0.2), dark, mag, rot=(math.radians(8), 0, 0), bevel=0.004)
    box("Grip", (0, -0.05, -0.05), (0.034, 0.055, 0.11), dark, r, rot=(math.radians(16), 0, 0), bevel=0.006)
    for sx in (-0.018, 0.018):
        box("StockRod", (sx, -0.21, 0.03), (0.008, 0.24, 0.012), steel, r, bevel=0.002)
    box("ButtPlate", (0, -0.33, 0.02), (0.05, 0.012, 0.08), dark, r)
    bolt = add_pivot("BoltPivot", (0.03, 0.12, 0.05), parent=r)
    box("ChargingHandle", (0.03, 0.12, 0.05), (0.03, 0.02, 0.012), steel, bolt, bevel=0.002)
    for sx in (-0.012, 0.012):
        box("RearSight", (sx, -0.06, 0.068), (0.007, 0.012, 0.014), sight, r, bevel=0.001)
    box("FrontSight", (0, 0.30, 0.066), (0.006, 0.012, 0.018), sight, r, bevel=0.001)
    mats = arm_mats()
    right_arm(r, (0.0, -0.055, -0.045), mats)
    left_arm_support(r, (0.0, 0.27, 0.0), mats)
    export_glb("vm_smg.glb")


def build_rifle():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Rfl")
    r = add_pivot("Root")
    box("Receiver", (0, 0.06, 0.03), (0.054, 0.34, 0.068), steel, r, bevel=0.007)
    box("Handguard", (0, 0.36, 0.026), (0.05, 0.32, 0.054), wood, r, bevel=0.008)
    cyl("Barrel", (0, 0.62, 0.036), 0.011, 0.34, steel, r, rot=(R90, 0, 0))
    box("Stock", (0, -0.22, 0.0), (0.046, 0.28, 0.095), wood, r, bevel=0.009)
    box("PistolGrip", (0, -0.07, -0.05), (0.034, 0.05, 0.1), wood, r, rot=(math.radians(18), 0, 0), bevel=0.006)
    mag = add_pivot("MagPivot", (0, 0.14, -0.005), parent=r)
    box("Mag", (0, 0.14, -0.075), (0.034, 0.075, 0.17), steel, mag, rot=(math.radians(-14), 0, 0), bevel=0.004)
    bolt = add_pivot("BoltPivot", (0.035, 0.08, 0.045), parent=r)
    box("OpRod", (0.035, 0.1, 0.045), (0.012, 0.12, 0.014), steel, bolt, bevel=0.002)
    box("BoltKnob", (0.045, 0.06, 0.045), (0.02, 0.02, 0.02), steel, bolt, bevel=0.003)
    # Aperture rear sight with a real hole look: two ears
    for sx in (-0.012, 0.012):
        box("RearEar", (sx, -0.06, 0.074), (0.006, 0.02, 0.02), steel, r, bevel=0.002)
    box("FrontPost", (0, 0.72, 0.064), (0.007, 0.012, 0.024), sight, r, bevel=0.001)
    mats = arm_mats()
    right_arm(r, (0.0, -0.07, -0.04), mats)
    left_arm_support(r, (0.0, 0.36, -0.01), mats)
    export_glb("vm_rifle.glb")


def build_shotgun():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Sgn")
    shell = make_mat("ShellRed", (0.78, 0.12, 0.12, 1), roughness=0.40)
    r = add_pivot("Root")
    box("Receiver", (0, 0.04, 0.03), (0.06, 0.28, 0.074), steel, r, bevel=0.008)
    cyl("HeavyBarrel", (0, 0.44, 0.048), 0.015, 0.56, steel, r, rot=(R90, 0, 0))
    cyl("MagTube", (0, 0.40, 0.014), 0.0125, 0.48, steel, r, rot=(R90, 0, 0))
    box("Stock", (0, -0.22, -0.008), (0.05, 0.28, 0.10), wood, r, bevel=0.01)
    box("PistolGrip", (0, -0.07, -0.05), (0.036, 0.05, 0.1), wood, r, rot=(math.radians(18), 0, 0), bevel=0.006)
    for i in range(4):
        cyl("SideShell%d" % i, (0.034, 0.0 + i * 0.032, 0.032), 0.0065, 0.048, shell, r)
    box("Bead", (0, 0.71, 0.066), (0.006, 0.006, 0.006), sight, r, bevel=0.001)
    pump = add_pivot("PumpPivot", (0, 0.36, 0.012), parent=r)
    cyl("PumpForend", (0, 0.36, 0.012), 0.021, 0.22, wood, pump, rot=(R90, 0, 0))
    for i in range(5):
        cyl("PumpRib%d" % i, (0, 0.28 + i * 0.04, 0.012), 0.0225, 0.01, dark, pump, rot=(R90, 0, 0))
    mats = arm_mats()
    right_arm(r, (0.0, -0.07, -0.04), mats)
    left_arm_support(r, (0.0, 0.36, 0.0), mats, parent=pump)
    export_glb("vm_shotgun.glb")


def build_lmg():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Lmg")
    r = add_pivot("Root")
    box("Receiver", (0, 0.05, 0.03), (0.07, 0.42, 0.09), steel, r, bevel=0.008)
    cover = add_pivot("CoverPivot", (0, -0.1, 0.086), parent=r)
    box("FeedCover", (0, 0.0, 0.086), (0.074, 0.20, 0.024), dark, cover, bevel=0.004)
    for sx in (-0.012, 0.012):
        box("RearSight", (sx, -0.08, 0.104), (0.007, 0.012, 0.016), sight, cover, bevel=0.001)
    cyl("Barrel", (0, 0.52, 0.04), 0.02, 0.52, steel, r, rot=(R90, 0, 0))
    cyl("HeatShield", (0, 0.40, 0.04), 0.033, 0.30, dark, r, rot=(R90, 0, 0))
    mag = add_pivot("MagPivot", (-0.02, 0.06, -0.03), parent=r)
    box("BoxMag", (-0.02, 0.06, -0.09), (0.12, 0.12, 0.13), dark, mag, bevel=0.01)
    for i in range(5):
        cyl("Belt%d" % i, (0.05, 0.0 + i * 0.022, 0.03 - i * 0.008), 0.007, 0.05, brass, mag, rot=(0, R90, 0))
    box("CarryHandle", (0, 0.24, 0.13), (0.014, 0.16, 0.012), dark, r, bevel=0.003)
    for y in (0.17, 0.31):
        box("HandlePost", (0, y, 0.105), (0.014, 0.014, 0.05), dark, r, bevel=0.002)
    for sx in (-0.02, 0.02):
        cyl("Bipod", (sx, 0.58, 0.0), 0.006, 0.28, steel, r, rot=(R90, 0, 0))
    box("Stock", (0, -0.28, 0.01), (0.05, 0.26, 0.10), dark, r, bevel=0.01)
    box("Grip", (0, -0.10, -0.06), (0.036, 0.055, 0.11), dark, r, rot=(math.radians(16), 0, 0), bevel=0.006)
    bolt = add_pivot("BoltPivot", (0.04, 0.12, 0.05), parent=r)
    box("ChargingHandle", (0.045, 0.12, 0.05), (0.025, 0.025, 0.02), steel, bolt, bevel=0.003)
    box("FrontPost", (0, 0.74, 0.075), (0.014, 0.014, 0.07), dark, r, bevel=0.002)
    box("FrontSight", (0, 0.74, 0.104), (0.006, 0.012, 0.016), sight, r, bevel=0.001)
    mats = arm_mats()
    right_arm(r, (0.0, -0.105, -0.055), mats)
    left_arm_support(r, (0.0, 0.36, 0.012), mats)
    export_glb("vm_lmg.glb")


def build_sniper():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Snp")
    lens = make_mat("SnpLens", (0.2, 0.55, 1.0, 1), roughness=0.05, emission=(0.2, 0.55, 1.0), emission_strength=2.0)
    r = add_pivot("Root")
    box("Receiver", (0, 0.02, 0.03), (0.055, 0.32, 0.07), steel, r, bevel=0.006)
    cyl("Barrel", (0, 0.55, 0.04), 0.017, 0.74, steel, r, rot=(R90, 0, 0))
    box("MuzzleBrake", (0, 0.94, 0.04), (0.05, 0.07, 0.04), dark, r, bevel=0.005)
    box("Stock", (0, -0.30, -0.005), (0.05, 0.38, 0.11), wood, r, bevel=0.012)
    box("Forend", (0, 0.28, 0.008), (0.052, 0.30, 0.05), wood, r, bevel=0.01)
    cyl("ScopeTube", (0, 0.06, 0.115), 0.022, 0.36, dark, r, rot=(R90, 0, 0))
    cyl("ScopeBellF", (0, 0.26, 0.115), 0.032, 0.08, dark, r, rot=(R90, 0, 0))
    cyl("ScopeBellR", (0, -0.13, 0.115), 0.028, 0.06, dark, r, rot=(R90, 0, 0))
    cyl("Lens", (0, 0.302, 0.115), 0.027, 0.006, lens, r, rot=(R90, 0, 0), bevel=0.0)
    for y in (-0.02, 0.14):
        box("Mount", (0, y, 0.08), (0.03, 0.02, 0.05), steel, r, bevel=0.003)
    bolt = add_pivot("BoltPivot", (0.03, -0.05, 0.05), parent=r)
    cyl("BoltArm", (0.05, -0.05, 0.05), 0.006, 0.07, steel, bolt, rot=(0, R90, 0))
    ball("BoltKnob", (0.088, -0.05, 0.05), (0.013, 0.013, 0.013), steel, bolt)
    mag = add_pivot("MagPivot", (0, 0.06, -0.005), parent=r)
    box("Mag", (0, 0.06, -0.025), (0.03, 0.06, 0.06), dark, mag, bevel=0.004)
    box("Grip", (0, -0.12, -0.06), (0.034, 0.05, 0.10), wood, r, rot=(math.radians(18), 0, 0), bevel=0.006)
    mats = arm_mats()
    right_arm(r, (0.0, -0.12, -0.055), mats)
    left_arm_support(r, (0.0, 0.3, -0.012), mats)
    export_glb("vm_sniper.glb")


def build_revolver():
    clear_scene()
    steel, dark, wood, sight, brass = gun_mats("Rev")
    red = make_mat("RevSight", (1.0, 0.3, 0.2, 1), roughness=0.2, emission=(1.0, 0.3, 0.2), emission_strength=3.0)
    r = add_pivot("Root")
    box("Frame", (0, 0.02, 0.03), (0.036, 0.14, 0.06), steel, r, bevel=0.006)
    cylp = add_pivot("CylinderPivot", (0, 0.035, 0.028), parent=r)
    cyl("Cylinder", (0, 0.035, 0.028), 0.034, 0.065, steel, cylp, rot=(R90, 0, 0), bevel=0.006)
    for i in range(6):
        a = i * math.pi / 3
        cyl("Flute%d" % i, (math.cos(a) * 0.03, 0.035, 0.028 + math.sin(a) * 0.03), 0.006, 0.066, dark, cylp, rot=(R90, 0, 0), bevel=0.0)
    cyl("Barrel", (0, 0.19, 0.045), 0.015, 0.21, steel, r, rot=(R90, 0, 0))
    box("UnderLug", (0, 0.19, 0.024), (0.022, 0.20, 0.022), steel, r, bevel=0.003)
    box("Grip", (0, -0.07, -0.05), (0.034, 0.05, 0.12), wood, r, rot=(math.radians(22), 0, 0), bevel=0.008)
    hammer = add_pivot("HammerPivot", (0, -0.045, 0.05), parent=r)
    box("Hammer", (0, -0.055, 0.07), (0.01, 0.025, 0.025), dark, hammer, rot=(math.radians(-30), 0, 0), bevel=0.002)
    box("TriggerGuard", (0, 0.0, -0.015), (0.008, 0.05, 0.008), steel, r)
    box("FrontSight", (0, 0.285, 0.066), (0.006, 0.014, 0.014), red, r, bevel=0.001)
    for sx in (-0.01, 0.01):
        box("RearSight", (sx, -0.03, 0.066), (0.006, 0.01, 0.012), steel, r, bevel=0.001)
    mats = arm_mats()
    right_arm(r, (0.0, -0.07, -0.05), mats)
    left_arm_pistol(r, (-0.01, -0.065, -0.06), mats)
    export_glb("vm_revolver.glb")


def build_volt():
    clear_scene()
    dark = make_mat("VoltDark", (0.07, 0.08, 0.10, 1), metallic=0.8, roughness=0.35, tex_prefix="rusted_metal")
    copper = make_mat("VoltCopper", (0.72, 0.38, 0.18, 1), metallic=0.95, roughness=0.3)
    glow = make_mat("VoltGlow", (0.25, 0.65, 1.0, 1), roughness=0.1, emission=(0.25, 0.65, 1.0), emission_strength=1.6)
    r = add_pivot("Root")
    cyl("Body", (0, 0.10, 0.02), 0.05, 0.40, dark, r, rot=(R90, 0, 0), bevel=0.01)
    coils = add_pivot("CoilPivot", (0, 0.18, 0.02), parent=r)
    for i in range(4):
        cyl("Coil%d" % i, (0, 0.08 + i * 0.07, 0.02), 0.065, 0.02, copper if i % 2 else glow, coils, rot=(R90, 0, 0), bevel=0.003)
    add_part("Emitter", "CONE", (0, 0, 0), (0.11, 0.11, 0.14), rot=(math.radians(-90), 0, 0), mat=copper, parent=r, bevel=0.0, offset=(0, 0.36, 0.02))
    ball("EmitterTip", (0, 0.43, 0.02), (0.025, 0.025, 0.025), glow, r)
    cyl("Tube", (0, 0.08, 0.085), 0.018, 0.24, glow, r, rot=(R90, 0, 0))
    bat = add_pivot("MagPivot", (0, -0.16, 0.02), parent=r)
    box("Battery", (0, -0.16, 0.02), (0.08, 0.11, 0.09), dark, bat, bevel=0.01)
    box("BatteryCell", (0, -0.13, 0.02), (0.084, 0.03, 0.05), glow, bat, bevel=0.004)
    box("Grip", (0, -0.03, -0.07), (0.036, 0.055, 0.11), dark, r, rot=(math.radians(16), 0, 0), bevel=0.006)
    mats = arm_mats()
    right_arm(r, (0.0, -0.035, -0.065), mats)
    left_arm_support(r, (0.0, 0.17, -0.035), mats)
    export_glb("vm_volt.glb")


def build_knife_hand():
    clear_scene()
    blade = make_mat("KnifeBlade", (0.75, 0.77, 0.8, 1), metallic=0.95, roughness=0.2)
    grip = make_mat("KnifeGrip", (0.12, 0.10, 0.08, 1), roughness=0.8, tex_prefix="wood_grain")
    r = add_pivot("Root")
    # Knife held blade-forward in a fist (grip along Y)
    cyl("Handle", (0, 0.0, 0), 0.016, 0.11, grip, r, rot=(R90, 0, 0))
    box("Guard", (0, 0.06, 0), (0.06, 0.012, 0.024), blade, r)
    box("Blade", (0, 0.14, 0.002), (0.005, 0.15, 0.032), blade, r, bevel=0.0015)
    add_part("Tip", "CONE", (0, 0, 0), (0.03, 0.006, 0.05), rot=(math.radians(-90), 0, 0), mat=blade, parent=r, bevel=0.0, offset=(0, 0.235, 0.002))
    sleeve, glove, cuff = arm_mats()
    piv = add_pivot("ArmR", (0, 0, 0), parent=r)
    blob("Fist", (0.0, -0.005, -0.01), (0.07, 0.085, 0.06), glove, piv)
    seg("Thumb", (-0.03, -0.02, 0.02), (-0.015, 0.02, 0.03), 0.012, 0.009, glove, piv, verts=8)
    seg("Wrist", (0.0, -0.04, -0.01), (0.02, -0.1, -0.03), 0.032, 0.034, glove, piv)
    seg("Cuff", (0.02, -0.1, -0.03), (0.035, -0.13, -0.05), 0.04, 0.042, cuff, piv)
    seg("Forearm", (0.03, -0.12, -0.045), (0.16, -0.38, -0.24), 0.042, 0.055, sleeve, piv)
    export_glb("vm_knife.glb")


def build_grenade_hand():
    clear_scene()
    body = make_mat("NadeBody", (0.22, 0.27, 0.16, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal")
    steel = make_mat("NadeSteel", (0.6, 0.6, 0.62, 1), metallic=0.9, roughness=0.3)
    r = add_pivot("Root")
    ball("NadeBody", (0, 0.02, 0.05), (0.035, 0.035, 0.045), body, r)
    cyl("Fuze", (0, 0.02, 0.1), 0.014, 0.025, steel, r)
    box("Lever", (0.018, 0.02, 0.07), (0.008, 0.014, 0.06), steel, r)
    torus("Pin", (-0.02, 0.02, 0.105), 0.012, 0.002, steel, r, rot=(0, R90, 0), seg_major=12)
    sleeve, glove, cuff = arm_mats()
    piv = add_pivot("ArmL", (0, 0, 0), parent=r)
    blob("Fist", (0.0, 0.0, 0.0), (0.075, 0.08, 0.06), glove, piv)
    seg("Thumb", (0.03, -0.01, 0.02), (0.02, 0.03, 0.04), 0.012, 0.009, glove, piv, verts=8)
    seg("Wrist", (0.0, -0.04, -0.01), (-0.02, -0.1, -0.03), 0.032, 0.034, glove, piv)
    seg("Cuff", (-0.02, -0.1, -0.03), (-0.035, -0.13, -0.05), 0.04, 0.042, cuff, piv)
    seg("Forearm", (-0.03, -0.12, -0.045), (-0.16, -0.38, -0.24), 0.042, 0.055, sleeve, piv)
    export_glb("vm_grenade_hand.glb")


# ---------------------------------------------------------------------------
# PROPS (origin on the floor)
# ---------------------------------------------------------------------------
def props_mats():
    metal = make_mat("PropMetal", (0.4, 0.38, 0.36, 1), metallic=0.7, roughness=0.6, tex_prefix="rusted_metal")
    dark = make_mat("PropDark", (0.1, 0.1, 0.11, 1), metallic=0.5, roughness=0.6)
    wood = make_mat("PropWood", (0.45, 0.3, 0.18, 1), roughness=0.8, tex_prefix="wood_planks")
    conc = make_mat("PropConcrete", (0.55, 0.55, 0.55, 1), roughness=0.9, tex_prefix="concrete")
    return metal, dark, wood, conc


def build_lamp_post():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    bulb = make_mat("LampBulb", (1.0, 0.85, 0.6, 1), roughness=0.2, emission=(1.0, 0.85, 0.6), emission_strength=6.0)
    r = add_pivot("Root")
    cyl("Base", (0, 0, 0.15), 0.18, 0.3, conc, r)
    cyl("Pole", (0, 0, 2.3), 0.06, 4.2, metal, r)
    seg("Arm", (0, 0, 4.2), (0, 0.7, 4.45), 0.04, 0.035, metal, r)
    add_part("Shade", "CONE", (0, 0, 0), (0.5, 0.5, 0.25), mat=dark, parent=r, bevel=0.0, offset=(0, 0.75, 4.45))
    ball("Bulb", (0, 0.75, 4.32), (0.09, 0.09, 0.07), bulb, r)
    export_glb("prop_lamp_post.glb")


def build_generator():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    yellow = make_mat("GenYellow", (0.75, 0.55, 0.1, 1), metallic=0.5, roughness=0.55, tex_prefix="rusted_metal")
    red = make_mat("GenRed", (1.0, 0.15, 0.1, 1), roughness=0.2, emission=(1.0, 0.15, 0.1), emission_strength=5.0)
    r = add_pivot("Root")
    box("Skid", (0, 0, 0.1), (2.4, 1.2, 0.2), dark, r, bevel=0.02)
    box("EngineBlock", (-0.3, 0, 0.75), (1.4, 0.9, 1.1), yellow, r, bevel=0.06)
    cyl("Flywheel", (0.65, 0, 0.8), 0.45, 0.18, metal, r, rot=(0, R90, 0), bevel=0.02)
    cyl("FuelTank", (-0.3, 0, 1.5), 0.35, 1.3, yellow, r, rot=(0, R90, 0), bevel=0.03)
    seg("Exhaust", (-0.8, -0.3, 1.3), (-0.8, -0.3, 2.6), 0.08, 0.08, dark, r)
    box("ControlPanel", (0.45, 0.5, 1.0), (0.6, 0.12, 0.6), metal, r, bevel=0.02)
    for i, x in enumerate((0.3, 0.45, 0.6)):
        cyl("Gauge%d" % i, (x, 0.57, 1.1), 0.05, 0.02, dark, r, rot=(R90, 0, 0))
    ball("StatusLight", (0.45, 0.57, 1.25), (0.05, 0.03, 0.05), red, r)
    lever = add_pivot("Lever", (0.75, 0.58, 0.85), parent=r)
    seg("LeverArm", (0.75, 0.58, 0.85), (0.75, 0.62, 1.2), 0.02, 0.02, metal, lever)
    ball("LeverKnob", (0.75, 0.62, 1.22), (0.04, 0.04, 0.04), red, lever)
    for i in range(3):
        seg("Cable%d" % i, (-1.0, 0.3 - i * 0.15, 0.3), (-1.4, 0.3 - i * 0.15, 0.02), 0.025, 0.025, dark, r, verts=6)
    export_glb("prop_generator.glb")


def build_car_wreck():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    paint = make_mat("CarPaint", (0.35, 0.12, 0.1, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal")
    glass = make_mat("CarGlass", (0.06, 0.08, 0.1, 1), metallic=0.3, roughness=0.15)
    tire = make_mat("CarTire", (0.05, 0.05, 0.05, 1), roughness=0.9)
    r = add_pivot("Root")
    blob("Body", (0, 0, 0.6), (1.8, 4.3, 0.6), paint, r, subsurf=0, bevel=0.12)
    blob("Cabin", (0, -0.2, 1.1), (1.6, 2.2, 0.55), paint, r, subsurf=0, bevel=0.12)
    box("Windshield", (0, 0.85, 1.12), (1.45, 0.05, 0.45), glass, r, rot=(math.radians(-30), 0, 0))
    box("RearWindow", (0, -1.28, 1.12), (1.45, 0.05, 0.4), glass, r, rot=(math.radians(30), 0, 0))
    for y in (-0.5, 0.3):
        for sx in (-0.81, 0.81):
            box("SideWin", (sx, y, 1.15), (0.04, 0.7, 0.35), glass, r)
    for (x, y) in ((-0.85, 1.35), (0.85, 1.35), (-0.85, -1.35)):
        cyl("Tire", (x, y, 0.32), 0.32, 0.22, tire, r, rot=(0, R90, 0), bevel=0.04)
    box("Hood", (0.1, 1.6, 0.98), (1.6, 1.0, 0.06), paint, r, rot=(math.radians(18), math.radians(4), 0))
    box("BumperF", (0, 2.15, 0.45), (1.8, 0.12, 0.18), metal, r)
    box("BumperR", (0, -2.15, 0.45), (1.8, 0.12, 0.18), metal, r, rot=(0, math.radians(8), 0))
    export_glb("prop_car_wreck.glb")


def build_dead_tree():
    clear_scene()
    bark = make_mat("Bark", (0.22, 0.18, 0.14, 1), roughness=0.95, tex_prefix="wood_grain")
    r = add_pivot("Root")
    seg("Trunk", (0, 0, -0.2), (0.15, 0.1, 4.0), 0.35, 0.12, bark, r)
    seg("Trunk2", (0.15, 0.1, 4.0), (0.0, 0.3, 6.5), 0.12, 0.05, bark, r)
    branches = [((0.05, 0.05, 2.2), (1.6, 0.4, 3.6), 0.09), ((0.1, 0.08, 3.0), (-1.3, -0.5, 4.4), 0.07),
                ((0.12, 0.1, 3.6), (0.6, -1.4, 4.8), 0.06), ((0.1, 0.2, 4.8), (-0.9, 1.2, 5.9), 0.05),
                ((1.0, 0.3, 3.2), (1.8, 1.2, 3.9), 0.04), ((-0.8, -0.3, 3.9), (-1.5, 0.4, 5.0), 0.035)]
    for i, (a, b, rad) in enumerate(branches):
        seg("Branch%d" % i, a, b, rad, rad * 0.35, bark, r, verts=7)
    for i, (a, b) in enumerate((((0.2, 0, 0.1), (0.9, 0.3, -0.1)), ((-0.1, 0.1, 0.1), (-0.7, 0.6, -0.1)), ((0, -0.2, 0.1), (0.2, -0.9, -0.1)))):
        seg("Root%d" % i, a, b, 0.14, 0.04, bark, r, verts=7)
    export_glb("prop_dead_tree.glb")


def build_barbed_wire():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    wire = make_mat("Wire", (0.45, 0.42, 0.4, 1), metallic=0.8, roughness=0.5)
    r = add_pivot("Root")
    for x in (-2.0, 0.0, 2.0):
        seg("PostA", (x, -0.3, 0), (x, 0.3, 1.1), 0.04, 0.035, wood, r, verts=6)
        seg("PostB", (x, 0.3, 0), (x, -0.3, 1.1), 0.04, 0.035, wood, r, verts=6)
    for i in range(14):
        x = -2.3 + i * 0.35
        torus("Coil%d" % i, (x, 0, 0.5), 0.42, 0.008, wire, r, rot=(0, R90 + 0.25, 0), seg_major=16)
    export_glb("prop_barbed_wire.glb")


def build_rubble():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    rebar = make_mat("Rebar", (0.3, 0.18, 0.12, 1), metallic=0.6, roughness=0.7)
    r = add_pivot("Root")
    import random
    random.seed(4)
    for i in range(14):
        s = random.uniform(0.25, 0.7)
        box("Chunk%d" % i, (random.uniform(-1, 1), random.uniform(-0.8, 0.8), s * 0.35 + (0.25 if i > 9 else 0)),
            (s * random.uniform(0.8, 1.5), s, s * 0.6), conc, r,
            rot=(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0, 3.1)), bevel=0.03)
    for i in range(4):
        seg("Rebar%d" % i, (random.uniform(-0.6, 0.6), random.uniform(-0.5, 0.5), 0.2),
            (random.uniform(-1.2, 1.2), random.uniform(-1, 1), random.uniform(0.6, 1.2)), 0.015, 0.012, rebar, r, verts=5)
    export_glb("prop_rubble.glb")


def build_crate():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    r = add_pivot("Root")
    box("Core", (0, 0, 0.5), (0.96, 0.96, 0.96), wood, r, bevel=0.01)
    for z in (0.06, 0.94):
        for (cx, cy, sx, sy) in ((0, 0.49, 1.0, 0.04), (0, -0.49, 1.0, 0.04), (0.49, 0, 0.04, 1.0), (-0.49, 0, 0.04, 1.0)):
            box("Rail", (cx, cy, z), (sx, sy, 0.1), wood, r, bevel=0.008)
    for (cx, cy) in ((0.49, 0.49), (-0.49, 0.49), (0.49, -0.49), (-0.49, -0.49)):
        box("Corner", (cx, cy, 0.5), (0.1, 0.1, 1.0), metal, r, bevel=0.01)
    for (cx, cy, rz) in ((0, 0.5, 0), (0, -0.5, 0), (0.5, 0, R90), (-0.5, 0, R90)):
        box("Brace", (cx, cy, 0.5), (1.2, 0.03, 0.09), wood, r, rot=(0, math.radians(45), rz), bevel=0.006)
    export_glb("prop_crate.glb")


def build_gurney():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    sheet = make_mat("Sheet", (0.75, 0.75, 0.72, 1), roughness=0.9, tex_prefix="fabric")
    blood = make_mat("SheetBlood", (0.35, 0.03, 0.03, 1), roughness=0.4)
    r = add_pivot("Root")
    box("Frame", (0, 0, 0.75), (0.75, 2.0, 0.06), metal, r)
    for (x, y) in ((-0.32, 0.9), (0.32, 0.9), (-0.32, -0.9), (0.32, -0.9)):
        seg("Leg", (x, y, 0.08), (x, y, 0.75), 0.02, 0.02, metal, r, verts=6)
        ball("Wheel", (x, y, 0.06), (0.05, 0.05, 0.05), dark, r)
    blob("Mattress", (0, 0, 0.84), (0.7, 1.9, 0.12), sheet, r, subsurf=1)
    blob("BodyBag", (0, -0.1, 0.98), (0.45, 1.5, 0.2), make_mat("Bag", (0.05, 0.05, 0.06, 1), roughness=0.4), r, subsurf=1)
    ball("Stain", (0.1, 0.4, 0.91), (0.2, 0.25, 0.03), blood, r)
    export_glb("prop_gurney.glb")


def build_lockers():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    green = make_mat("LockerGreen", (0.28, 0.36, 0.3, 1), metallic=0.6, roughness=0.55, tex_prefix="rusted_metal")
    r = add_pivot("Root")
    for i in range(4):
        x = -0.75 + i * 0.5
        box("Locker%d" % i, (x, 0, 1.0), (0.48, 0.5, 2.0), green, r, bevel=0.01)
        for j in range(3):
            box("Vent", (x, 0.255, 1.7 - j * 0.05), (0.3, 0.01, 0.015), dark, r, bevel=0.0)
        box("Handle", (x + 0.17, 0.26, 1.0), (0.02, 0.02, 0.12), metal, r)
    box("OpenDoor", (1.12, 0.35, 1.0), (0.46, 0.02, 1.95), green, r, rot=(0, 0, math.radians(-60)))
    export_glb("prop_lockers.glb")


def build_desk():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    radio_m = make_mat("Radio", (0.25, 0.26, 0.2, 1), metallic=0.4, roughness=0.6)
    dial = make_mat("RadioDial", (1.0, 0.7, 0.2, 1), roughness=0.3, emission=(1.0, 0.65, 0.2), emission_strength=3.0)
    paper = make_mat("Paper", (0.85, 0.82, 0.72, 1), roughness=0.9)
    r = add_pivot("Root")
    box("Top", (0, 0, 0.76), (1.6, 0.8, 0.05), wood, r)
    for (x, y) in ((-0.75, 0.35), (0.75, 0.35), (-0.75, -0.35), (0.75, -0.35)):
        box("Leg", (x, y, 0.37), (0.06, 0.06, 0.74), metal, r)
    box("Drawers", (0.5, 0, 0.45), (0.5, 0.75, 0.55), metal, r)
    box("Radio", (-0.4, 0.05, 0.92), (0.5, 0.3, 0.28), radio_m, r, bevel=0.02)
    for i in range(3):
        cyl("Dial%d" % i, (-0.55 + i * 0.15, 0.21, 0.92), 0.03, 0.02, dial, r, rot=(R90, 0, 0))
    seg("Antenna", (-0.25, 0.0, 1.06), (-0.15, -0.1, 1.6), 0.006, 0.004, metal, r, verts=5)
    box("Map", (0.3, 0.05, 0.79), (0.6, 0.45, 0.005), paper, r, rot=(0, 0, 0.2), bevel=0.0)
    # Toppled chair
    box("ChairSeat", (0.2, -0.8, 0.25), (0.45, 0.45, 0.05), metal, r, rot=(math.radians(70), 0, 0.3))
    box("ChairBack", (0.25, -1.05, 0.25), (0.45, 0.05, 0.45), metal, r, rot=(math.radians(70), 0, 0.3))
    export_glb("prop_desk.glb")


def build_skull():
    clear_scene()
    bone = make_mat("SkullBone", (0.9, 0.85, 0.7, 1), roughness=0.5, emission=(0.4, 0.9, 0.5), emission_strength=0.6)
    dark = make_mat("SkullSocket", (0.02, 0.02, 0.02, 1), roughness=0.9)
    glow = make_mat("SkullGlow", (0.3, 1.0, 0.5, 1), roughness=0.2, emission=(0.3, 1.0, 0.5), emission_strength=6.0)
    r = add_pivot("Root")
    ball("Cranium", (0, 0, 0.14), (0.11, 0.13, 0.11), bone, r)
    blob("Face", (0, 0.07, 0.09), (0.15, 0.1, 0.1), bone, r)
    for sx in (-0.04, 0.04):
        ball("Socket", (sx, 0.12, 0.11), (0.028, 0.02, 0.025), dark, r)
        ball("Glow", (sx, 0.125, 0.11), (0.012, 0.01, 0.012), glow, r)
    blob("Jaw", (0, 0.08, 0.03), (0.11, 0.08, 0.04), bone, r)
    for i in range(5):
        box("Tooth%d" % i, (-0.03 + i * 0.015, 0.125, 0.055), (0.01, 0.01, 0.015), bone, r, bevel=0.002)
    export_glb("prop_skull.glb")


def build_radio_tower():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    red = make_mat("TowerLight", (1.0, 0.1, 0.05, 1), roughness=0.2, emission=(1.0, 0.1, 0.05), emission_strength=10.0)
    r = add_pivot("Root")
    h = 22.0
    legs = [(-1.5, -1.5), (1.5, -1.5), (1.5, 1.5), (-1.5, 1.5)]
    for i, (x, y) in enumerate(legs):
        seg("Leg%d" % i, (x, y, 0), (x * 0.15, y * 0.15, h), 0.08, 0.05, metal, r, verts=6)
    for k in range(8):
        z0 = k * h / 8
        z1 = (k + 1) * h / 8
        f0 = 1 - 0.85 * z0 / h
        f1 = 1 - 0.85 * z1 / h
        for i in range(4):
            a = legs[i]
            b = legs[(i + 1) % 4]
            seg("Brace%d_%d" % (k, i), (a[0] * f0, a[1] * f0, z0), (b[0] * f1, b[1] * f1, z1), 0.03, 0.03, metal, r, verts=5)
    ball("BeaconTop", (0, 0, h + 0.2), (0.25, 0.25, 0.25), red, r)
    ball("BeaconMid", (0.9, 0.9, h * 0.5), (0.18, 0.18, 0.18), red, r)
    export_glb("prop_radio_tower.glb")


def build_trap_pylon():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    copper = make_mat("PylonCopper", (0.72, 0.38, 0.18, 1), metallic=0.95, roughness=0.3)
    ins = make_mat("Insulator", (0.75, 0.75, 0.7, 1), roughness=0.3)
    r = add_pivot("Root")
    box("Base", (0, 0, 0.15), (0.45, 0.45, 0.3), metal, r, bevel=0.02)
    cyl("Mast", (0, 0, 1.4), 0.07, 2.3, metal, r)
    for i in range(6):
        cyl("Coil%d" % i, (0, 0, 0.8 + i * 0.28), 0.13, 0.06, copper, r)
    for i in range(3):
        cyl("Insulator%d" % i, (0, 0, 2.6 + i * 0.1), 0.09 - i * 0.015, 0.06, ins, r)
    ball("Electrode", (0, 0, 2.95), (0.1, 0.1, 0.1), copper, r)
    export_glb("prop_trap_pylon.glb")


def build_tire_stack():
    clear_scene()
    tire = make_mat("StackTire", (0.06, 0.06, 0.06, 1), roughness=0.85)
    r = add_pivot("Root")
    for i in range(4):
        torus("Tire%d" % i, (0.03 * (i % 2), 0.02 * i, 0.12 + i * 0.22), 0.32, 0.12, tire, r, seg_major=20)
    export_glb("prop_tire_stack.glb")


def build_fuel_tank():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    paint = make_mat("TankPaint", (0.6, 0.6, 0.55, 1), metallic=0.5, roughness=0.6, tex_prefix="rusted_metal")
    r = add_pivot("Root")
    cyl("Tank", (0, 0, 1.2), 0.85, 3.6, paint, r, rot=(R90, 0, 0), bevel=0.05)
    for y in (-1.2, 1.2):
        box("Saddle", (0, y, 0.45), (1.4, 0.25, 0.9), metal, r, bevel=0.02)
    seg("Pipe", (0.6, 1.5, 1.3), (1.3, 1.9, 0.3), 0.06, 0.06, dark, r)
    box("Ladder", (0.9, 0, 1.2), (0.05, 0.5, 2.0), metal, r, rot=(0, -0.3, 0))
    export_glb("prop_fuel_tank.glb")


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def want(name):
        return not only or name in only

    if want("zombies"):
        for st in ("walker", "soldier", "runner"):
            build_zombie(st)
    if want("guns"):
        build_pistol()
        build_smg()
        build_rifle()
        build_shotgun()
        build_lmg()
        build_sniper()
        build_revolver()
        build_volt()
        build_knife_hand()
        build_grenade_hand()
    if want("props"):
        build_lamp_post()
        build_generator()
        build_car_wreck()
        build_dead_tree()
        build_barbed_wire()
        build_rubble()
        build_crate()
        build_gurney()
        build_lockers()
        build_desk()
        build_skull()
        build_radio_tower()
        build_trap_pylon()
        build_tire_stack()
        build_fuel_tank()
    print("ALL V3 MODELS GENERATED")
