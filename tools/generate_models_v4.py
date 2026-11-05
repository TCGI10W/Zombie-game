"""Fourth batch of Blender models:
- Blight hound: jointed quadruped for the hound raid rounds.
- Bloater zombie: same joints as the v2 zombies, so the zombie rig drives it.
- Extraction helicopter with Rotor / TailRotor pivots and a rope Ladder.
- Second Wind medical station and the field radio console.
- Re-exports the v2 zombies with their parts merged per joint (far fewer
  draw calls, same look).

Run with:
  blender -b --factory-startup -P tools/generate_models_v4.py -- [hound bloater heli props zombies]
Convention: +Y forward (-Z in Godot), +Z up. Pivots sit on joints.
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_models_v3 as v3  # noqa: E402
from generate_models import add_part, add_pivot, export_glb  # noqa: E402
from generate_models_v3 import R90, add, ball, blob, box, clear_scene, cyl, make_mat, props_mats, seg, torus  # noqa: E402


def merge_per_pivot(keep=()):
    """Merge each pivot's mesh children into one mesh: one node per joint."""
    groups = {}
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or obj.name in keep:
            continue
        key = obj.parent.name if obj.parent else ""
        groups.setdefault(key, []).append(obj)
    for key, objs in groups.items():
        if len(objs) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        objs[0].name = (key or "Root") + "_Geo"


def build_zombies_merged():
    orig = v3.export_glb

    def export_merged(filename):
        merge_per_pivot()
        orig(filename)

    v3.export_glb = export_merged
    try:
        for st in ("walker", "soldier", "runner"):
            v3.build_zombie(st)
    finally:
        v3.export_glb = orig


# ---------------------------------------------------------------------------
# BLIGHT HOUND
# ---------------------------------------------------------------------------
def build_hound():
    clear_scene()
    m_fur = make_mat("HoundFur", (0.24, 0.2, 0.17, 1), roughness=0.95, tex_prefix="gorilla_hide")
    m_hide = make_mat("HoundHide", (0.42, 0.22, 0.2, 1), roughness=0.7, tex_prefix="zombie_skin")
    m_bone = make_mat("HoundBone", (0.3, 0.25, 0.18, 1), roughness=0.6)
    m_gore = make_mat("HoundGore", (0.09, 0.008, 0.006, 1), roughness=0.3)
    m_claw = make_mat("HoundClaw", (0.04, 0.035, 0.03, 1), roughness=0.5)
    m_teeth = make_mat("HoundTeeth", (0.62, 0.56, 0.42, 1), roughness=0.45)
    m_ember = make_mat("HoundEmber", (1.0, 0.38, 0.06, 1), roughness=0.4, emission=(1.0, 0.34, 0.05), emission_strength=4.0)
    m_eye = make_mat("HoundEye", (1.0, 0.55, 0.1, 1), roughness=0.2, emission=(1.0, 0.5, 0.08), emission_strength=6.0)

    root = add_pivot("Root", (0, 0, 0))
    body = add_pivot("Body", (0, 0, 0.66), parent=root)
    # Deep chest, starved waist, heavy haunches (ellipsoids read as muscle)
    ball("ChestMesh", (0, 0.24, 0.68), (0.165, 0.24, 0.2), m_fur, body)
    ball("Rump", (0, -0.4, 0.69), (0.15, 0.2, 0.16), m_fur, body)
    ball("Waist", (0, -0.08, 0.68), (0.11, 0.25, 0.13), m_hide, body)
    ball("Brisket", (0, 0.36, 0.56), (0.11, 0.12, 0.1), m_fur, body)
    for sx, nm in ((-1, "L"), (1, "R")):
        for i in range(4):
            y = -0.2 + i * 0.075
            seg("Rib%s%d" % (nm, i), (sx * 0.095, y, 0.76), (sx * 0.112, y + 0.02, 0.6), 0.01, 0.008, m_bone, body, verts=6)
        seg("Vein%s" % nm, (sx * 0.135, -0.5, 0.74), (sx * 0.12, -0.28, 0.66), 0.008, 0.005, m_ember, body, verts=6)
        seg("VeinB%s" % nm, (sx * 0.16, 0.14, 0.74), (sx * 0.15, 0.34, 0.6), 0.007, 0.005, m_ember, body, verts=6)
        ball("Gash%s" % nm, (sx * 0.15, 0.06, 0.66), (0.025, 0.08, 0.045), m_gore, body)
    for i in range(4):
        ball("Vertebra%d" % i, (0, -0.24 + i * 0.09, 0.805), (0.018, 0.026, 0.018), m_bone, body)

    # Neck, head and snapping jaw
    neck = add_pivot("Neck", (0, 0.4, 0.78), parent=body)
    seg("NeckMesh", (0, 0.36, 0.74), (0, 0.6, 0.9), 0.12, 0.085, m_fur, neck)
    seg("NeckSinew", (0, 0.42, 0.7), (0, 0.62, 0.84), 0.05, 0.035, m_hide, neck)
    head = add_pivot("Head", (0, 0.6, 0.9), parent=neck)
    ball("Cranium", (0, 0.66, 0.93), (0.115, 0.13, 0.1), m_fur, head)
    blob("Muzzle", (0, 0.83, 0.895), (0.11, 0.22, 0.085), m_hide, head, subsurf=2)
    ball("NoseTip", (0, 0.94, 0.905), (0.032, 0.026, 0.024), m_claw, head)
    blob("Brow", (0, 0.74, 0.965), (0.17, 0.06, 0.035), m_fur, head, subsurf=2)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Eye" + nm, (sx * 0.056, 0.755, 0.95), (0.019, 0.014, 0.014), m_eye, head)
        seg("Ear" + nm, (sx * 0.07, 0.62, 0.99), (sx * 0.11, 0.56, 1.13), 0.04, 0.006, m_fur, head, verts=6)
        for i in range(4):
            y = 0.79 + i * 0.035
            seg("UTooth%s%d" % (nm, i), (sx * 0.045, y, 0.865), (sx * 0.043, y, 0.83), 0.008, 0.0015, m_teeth, head, verts=5)
        seg("Fang" + nm, (sx * 0.035, 0.915, 0.875), (sx * 0.033, 0.92, 0.82), 0.011, 0.002, m_teeth, head, verts=5)
    ball("MouthGlow", (0, 0.8, 0.858), (0.045, 0.11, 0.02), m_ember, head)
    jaw = add_pivot("Jaw", (0, 0.68, 0.86), parent=head)
    blob("JawMesh", (0, 0.8, 0.825), (0.09, 0.2, 0.045), m_hide, jaw, subsurf=2)
    for sx, nm in ((-1, "L"), (1, "R")):
        for i in range(3):
            y = 0.8 + i * 0.04
            seg("LTooth%s%d" % (nm, i), (sx * 0.04, y, 0.84), (sx * 0.039, y, 0.866), 0.007, 0.0015, m_teeth, jaw, verts=5)

    # Legs: shoulder/elbow/wrist at the front, hip/stifle/hock at the back
    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * 0.13, 0.3, 0.68)
        el = (sx * 0.14, 0.33, 0.36)
        wr = (sx * 0.13, 0.36, 0.1)
        up = add_pivot("FrontUpper" + nm, sh, parent=body)
        ball("Shoulder" + nm, (sx * 0.125, 0.3, 0.6), (0.07, 0.12, 0.15), m_fur, up)
        seg("FrontUpperMesh" + nm, sh, el, 0.075, 0.055, m_fur, up)
        lo = add_pivot("FrontLower" + nm, el, parent=up)
        seg("FrontLowerMesh" + nm, el, wr, 0.048, 0.034, m_hide, lo)
        paw = add_pivot("FrontPaw" + nm, wr, parent=lo)
        seg("FrontPastern" + nm, wr, (sx * 0.13, 0.4, 0.04), 0.03, 0.028, m_hide, paw)
        blob("FrontPawMesh" + nm, (sx * 0.13, 0.43, 0.035), (0.075, 0.11, 0.05), m_hide, paw)
        for i in range(3):
            cx = sx * 0.13 + (i - 1) * 0.022
            seg("FClaw%s%d" % (nm, i), (cx, 0.48, 0.03), (cx, 0.515, 0.0), 0.008, 0.002, m_claw, paw, verts=5)

        hp = (sx * 0.14, -0.42, 0.66)
        kn = (sx * 0.15, -0.3, 0.42)
        hk = (sx * 0.15, -0.52, 0.2)
        th = add_pivot("HindUpper" + nm, hp, parent=body)
        ball("Haunch" + nm, (sx * 0.125, -0.4, 0.6), (0.085, 0.16, 0.17), m_fur, th)
        seg("HindUpperMesh" + nm, hp, kn, 0.08, 0.058, m_fur, th)
        sk = add_pivot("HindLower" + nm, kn, parent=th)
        seg("HindLowerMesh" + nm, kn, hk, 0.05, 0.036, m_hide, sk)
        if nm == "L":
            seg("ExposedBone", add(kn, (-0.03, -0.02, -0.03)), add(hk, (-0.03, 0.02, 0.04)), 0.012, 0.01, m_bone, sk, verts=6)
        ft = add_pivot("HindPaw" + nm, hk, parent=sk)
        seg("HindMeta" + nm, hk, (sx * 0.15, -0.46, 0.05), 0.03, 0.026, m_hide, ft)
        blob("HindPawMesh" + nm, (sx * 0.15, -0.43, 0.035), (0.075, 0.11, 0.05), m_hide, ft)
        for i in range(3):
            cx = sx * 0.15 + (i - 1) * 0.022
            seg("HClaw%s%d" % (nm, i), (cx, -0.38, 0.03), (cx, -0.345, 0.0), 0.008, 0.002, m_claw, ft, verts=5)

    # Skeletal tail
    tail = add_pivot("Tail", (0, -0.56, 0.76), parent=body)
    seg("TailBase", (0, -0.56, 0.76), (0, -0.76, 0.72), 0.045, 0.03, m_fur, tail)
    tip = add_pivot("TailTip", (0, -0.76, 0.72), parent=tail)
    for i in range(5):
        r = 0.016 - i * 0.002
        ball("TailBone%d" % i, (0, -0.79 - i * 0.05, 0.71 - i * 0.022), (r, 0.02, r), m_bone, tip)

    merge_per_pivot()
    export_glb("enemy_hound.glb")


# ---------------------------------------------------------------------------
# BLOATER (uses the same joint names as the v2 zombies)
# ---------------------------------------------------------------------------
def build_bloater():
    clear_scene()
    rnd = random.Random(7)
    m_skin = make_mat("BloatSkin", (0.62, 0.66, 0.4, 1), roughness=0.55, tex_prefix="zombie_skin")
    m_belly = make_mat("BloatBelly", (0.74, 0.64, 0.46, 1), roughness=0.3, tex_prefix="zombie_skin")
    m_pus = make_mat("Pustule", (0.45, 0.85, 0.12, 1), roughness=0.25, emission=(0.4, 0.9, 0.08), emission_strength=0.9)
    m_vein = make_mat("Vein", (0.14, 0.05, 0.08, 1), roughness=0.5)
    m_bone = make_mat("Bone", (0.32, 0.27, 0.18, 1), roughness=0.6)
    m_dark = make_mat("Socket", (0.03, 0.02, 0.02, 1), roughness=0.9)
    m_eye = make_mat("Eye", (0.6, 1.0, 0.2, 1), roughness=0.2, emission=(0.55, 1.0, 0.15), emission_strength=1.6)
    m_rags = make_mat("Rags", (0.17, 0.15, 0.11, 1), roughness=0.95, tex_prefix="fabric")
    m_pants = make_mat("Trousers", (0.22, 0.2, 0.18, 1), roughness=0.9, tex_prefix="denim")

    def pustules(parent, center, radii, count, front_only=True):
        for i in range(count):
            th = rnd.uniform(-1.3, 1.3) if front_only else rnd.uniform(-math.pi, math.pi)
            ph = rnd.uniform(-0.7, 0.85)
            d = (math.sin(th) * math.cos(ph), math.cos(th) * math.cos(ph), math.sin(ph))
            p = (center[0] + radii[0] * d[0] * 0.97, center[1] + radii[1] * d[1] * 0.97, center[2] + radii[2] * d[2] * 0.97)
            r = rnd.uniform(0.022, 0.05)
            ball("Pus%d" % rnd.randint(0, 99999), p, (r, r, r * 0.8), m_pus, parent)

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    blob("Pelvis", (0, 0, 0.95), (0.5, 0.32, 0.26), m_pants, hips)
    spine = add_pivot("Spine", (0, 0, 1.06), parent=hips)
    belly_c, belly_r = (0, 0.12, 1.13), (0.38, 0.4, 0.36)
    ball("Belly", belly_c, belly_r, m_belly, spine)
    pustules(spine, belly_c, belly_r, 10)
    for i in range(6):
        a = -1.0 + i * 0.4
        p0 = (math.sin(a) * 0.36, 0.12 + math.cos(a) * 0.37, 1.32)
        p1 = (math.sin(a + 0.2) * 0.38, 0.12 + math.cos(a + 0.2) * 0.39, 1.02)
        seg("BellyVein%d" % i, p0, p1, 0.008, 0.006, m_vein, spine, verts=5)
    blob("Navel", (0.03, 0.51, 1.08), (0.07, 0.03, 0.05), m_dark, spine)

    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    blob("ChestMesh", (0, 0.0, 1.42), (0.64, 0.42, 0.36), m_skin, chest)
    ball("Hump", (0.06, -0.17, 1.5), (0.22, 0.16, 0.18), m_skin, chest)
    pustules(chest, (0.06, -0.17, 1.5), (0.22, 0.16, 0.18), 4, front_only=False)
    blob("RagL", (-0.24, 0.04, 1.5), (0.2, 0.42, 0.16), m_rags, chest)
    blob("RagStrap", (0.12, 0.2, 1.45), (0.08, 0.04, 0.3), m_rags, chest, rot=(0, 0.5, 0))

    head = add_pivot("Head", (0, 0.02, 1.57), parent=chest)
    seg("Neck", (0, 0.02, 1.5), (0, 0.04, 1.63), 0.11, 0.085, m_skin, head)
    ball("Skull", (0, 0.05, 1.72), (0.1, 0.115, 0.115), m_skin, head)
    ball("CheekL", (-0.07, 0.1, 1.67), (0.055, 0.05, 0.05), m_skin, head)
    ball("CheekR", (0.075, 0.1, 1.675), (0.07, 0.06, 0.06), m_belly, head)
    ball("PusHead", (0.08, 0.05, 1.8), (0.035, 0.035, 0.03), m_pus, head)
    blob("Brow", (0, 0.12, 1.76), (0.15, 0.045, 0.03), m_skin, head, subsurf=2)
    for sx, nm in ((-1, "L"), (1, "R")):
        ball("Socket" + nm, (sx * 0.042, 0.125, 1.738), (0.024, 0.014, 0.016), m_dark, head)
        ball("Eye" + nm, (sx * 0.042, 0.133, 1.738), (0.009, 0.007, 0.008), m_eye, head)
    jaw = add_pivot("Jaw", (0, 0.06, 1.67), parent=head)
    blob("JawMesh", (0, 0.11, 1.63), (0.12, 0.1, 0.05), m_skin, jaw, subsurf=2)
    seg("Drool", (0.0, 0.15, 1.61), (0.01, 0.17, 1.47), 0.012, 0.004, m_pus, jaw, verts=6)
    for i in range(4):
        box("Tooth%d" % i, (-0.025 + i * 0.017, 0.155, 1.65), (0.01, 0.008, 0.016), m_bone, jaw, bevel=0.002)

    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * 0.34, 0.0, 1.5)
        el = (sx * 0.38, 0.02, 1.2)
        wr = (sx * 0.37, 0.04, 0.95)
        upper = add_pivot("UpperArm" + nm, sh, parent=chest)
        ball("Shoulder" + nm, sh, (0.1, 0.1, 0.09), m_skin, upper)
        seg("UpperArmMesh" + nm, sh, el, 0.095, 0.08, m_skin, upper)
        ball("ArmPus" + nm, add(sh, (sx * 0.07, 0.04, -0.12)), (0.04, 0.04, 0.035), m_pus, upper)
        fore = add_pivot("Forearm" + nm, el, parent=upper)
        ball("Elbow" + nm, el, (0.075, 0.075, 0.07), m_skin, fore)
        seg("ForearmMesh" + nm, el, wr, 0.075, 0.058, m_skin, fore)
        hand = add_pivot("Hand" + nm, wr, parent=fore)
        blob("Palm" + nm, add(wr, (0, 0.01, -0.07)), (0.085, 0.05, 0.11), m_skin, hand)
        for i in range(4):
            f0 = add(wr, ((i - 1.5) * 0.02, 0.025, -0.12))
            seg("Finger%s%d" % (nm, i), f0, add(f0, (0, 0.03, -0.06)), 0.014, 0.01, m_skin, hand, verts=6)

    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.17, 0.0, 0.94)
        kn = (sx * 0.18, 0.02, 0.52)
        an = (sx * 0.17, 0.0, 0.1)
        thigh = add_pivot("Thigh" + nm, hp, parent=hips)
        seg("ThighMesh" + nm, hp, kn, 0.13, 0.1, m_pants, thigh)
        shin = add_pivot("Shin" + nm, kn, parent=thigh)
        ball("Knee" + nm, kn, (0.095, 0.095, 0.09), m_pants, shin)
        seg("ShinMesh" + nm, kn, an, 0.095, 0.07, m_skin if nm == "L" else m_pants, shin)
        foot = add_pivot("Foot" + nm, an, parent=shin)
        blob("FootMesh" + nm, add(an, (0, 0.06, -0.05)), (0.13, 0.26, 0.09), m_skin, foot)

    merge_per_pivot()
    export_glb("zombie_bloater.glb")


# ---------------------------------------------------------------------------
# EXTRACTION HELICOPTER
# ---------------------------------------------------------------------------
def build_helicopter():
    clear_scene()
    paint = make_mat("HeliPaint", (0.3, 0.33, 0.23, 1), metallic=0.35, roughness=0.55, tex_prefix="rusted_metal")
    dark = make_mat("HeliDark", (0.06, 0.06, 0.07, 1), metallic=0.4, roughness=0.5)
    glass = make_mat("HeliGlass", (0.05, 0.07, 0.09, 1), metallic=0.5, roughness=0.08)
    metal = make_mat("HeliMetal", (0.45, 0.45, 0.45, 1), metallic=0.8, roughness=0.4, tex_prefix="rusted_metal")
    stripe = make_mat("HeliStripe", (0.33, 0.31, 0.25, 1), roughness=0.8)
    tip = make_mat("RotorTip", (0.9, 0.7, 0.1, 1), roughness=0.5)
    red = make_mat("NavRed", (1.0, 0.1, 0.08, 1), emission=(1.0, 0.1, 0.06), emission_strength=3.0)
    green = make_mat("NavGreen", (0.1, 1.0, 0.2, 1), emission=(0.1, 1.0, 0.2), emission_strength=3.0)
    lens = make_mat("SearchLens", (1.0, 0.95, 0.85, 1), emission=(1.0, 0.95, 0.85), emission_strength=4.0)
    rope = make_mat("Rope", (0.42, 0.34, 0.22, 1), roughness=0.95, tex_prefix="burlap")
    interior = make_mat("Interior", (0.02, 0.02, 0.025, 1), roughness=0.95)

    r = add_pivot("Root")
    blob("Cabin", (0, 0.1, 1.75), (2.1, 4.2, 1.9), paint, r, subsurf=2, bevel=0.45)
    ball("Nose", (0, 2.2, 1.5), (0.98, 1.35, 0.8), paint, r)
    ball("Canopy", (0, 2.55, 1.98), (0.86, 1.05, 0.62), glass, r)
    box("CanopyFrame", (0, 2.75, 2.15), (0.06, 1.1, 0.5), dark, r, rot=(math.radians(-30), 0, 0))
    for sx in (-1, 1):
        box("DoorOpening", (sx * 1.03, -0.1, 1.6), (0.06, 1.7, 1.3), interior, r)
        box("DoorRail", (sx * 1.07, -0.1, 2.3), (0.05, 2.1, 0.06), metal, r)
        box("SideWindow", (sx * 1.02, 1.35, 2.05), (0.05, 0.7, 0.5), glass, r)
        # Skids and struts
        cyl("Skid", (sx * 1.0, 0.3, 0.1), 0.07, 4.8, dark, r, rot=(R90, 0, 0))
        seg("SkidTipF", (sx * 1.0, 2.7, 0.1), (sx * 1.0, 2.95, 0.3), 0.07, 0.06, dark, r)
        for y in (-0.9, 1.4):
            seg("Strut", (sx * 0.72, y, 0.85), (sx * 1.0, y, 0.12), 0.06, 0.06, dark, r)
        # Stub wing with rocket pod
        box("StubWing", (sx * 1.45, -0.5, 1.55), (0.9, 0.7, 0.1), paint, r)
        cyl("RocketPod", (sx * 1.75, -0.4, 1.35), 0.2, 1.3, dark, r, rot=(R90, 0, 0))
    blob("Engine", (0, -0.5, 2.95), (1.25, 2.6, 0.75), paint, r, subsurf=1, bevel=0.2)
    for sx in (-1, 1):
        cyl("Exhaust", (sx * 0.5, -1.85, 3.0), 0.17, 0.5, dark, r, rot=(math.radians(110), 0, 0))
        box("Intake", (sx * 0.62, 0.55, 3.05), (0.08, 0.6, 0.35), dark, r)
    cyl("Mast", (0, 0.2, 3.55), 0.13, 0.55, dark, r)
    seg("TailBoom", (0, -1.9, 2.1), (0, -7.6, 2.5), 0.45, 0.2, paint, r, verts=12)
    torus("BoomStripe", (0, -3.7, 2.24), 0.36, 0.035, stripe, r, rot=(R90, 0, 0))
    torus("BoomStripe2", (0, -4.2, 2.27), 0.345, 0.035, stripe, r, rot=(R90, 0, 0))
    box("TailFin", (0, -7.5, 3.15), (0.12, 0.9, 1.5), paint, r, rot=(math.radians(-15), 0, 0))
    box("Stabilizer", (0, -6.6, 2.42), (2.1, 0.5, 0.08), paint, r)
    ball("BeaconRed", (0, -7.62, 3.92), (0.08, 0.08, 0.08), red, r)
    ball("NavL", (-1.06, -6.6, 2.42), (0.06, 0.06, 0.06), red, r)
    ball("NavR", (1.06, -6.6, 2.42), (0.06, 0.06, 0.06), green, r)
    cyl("SearchHousing", (0, 2.6, 0.72), 0.17, 0.24, dark, r)
    cyl("SearchLensMesh", (0, 2.6, 0.59), 0.13, 0.03, lens, r)
    box("Antenna", (0, 1.2, 3.0), (0.03, 0.03, 0.5), metal, r)

    rotor = add_pivot("Rotor", (0, 0.2, 3.85), parent=r)
    cyl("Hub", (0, 0.2, 3.85), 0.3, 0.22, metal, rotor)
    for k in range(4):
        a = k * math.pi * 0.5
        c = (-2.95 * math.sin(a), 0.2 + 2.95 * math.cos(a), 3.88)
        box("Blade%d" % k, c, (0.4, 5.5, 0.05), dark, rotor, rot=(0, 0, a), bevel=0.01)
        t = (-5.6 * math.sin(a), 0.2 + 5.6 * math.cos(a), 3.885)
        box("BladeTip%d" % k, t, (0.41, 0.25, 0.055), tip, rotor, rot=(0, 0, a), bevel=0.005)

    trot = add_pivot("TailRotor", (0.26, -7.62, 3.2), parent=r)
    cyl("TailHub", (0.26, -7.62, 3.2), 0.1, 0.12, metal, trot, rot=(0, R90, 0))
    box("TailBladeA", (0.3, -7.62, 3.2), (0.03, 0.16, 1.5), dark, trot)
    box("TailBladeB", (0.3, -7.62, 3.2), (0.03, 1.5, 0.16), dark, trot)

    # Rope ladder hanging from the right door (Godot unrolls it on landing)
    ladder = add_pivot("Ladder", (1.12, -0.1, 0.95), parent=r)
    for y in (-0.4, 0.2):
        seg("LadderRope", (1.12, -0.1 + y, 0.95), (1.12, -0.1 + y, -2.9), 0.022, 0.022, rope, ladder, verts=6)
    for i in range(12):
        z = 0.75 - i * 0.32
        cyl("Rung%d" % i, (1.12, -0.2, z), 0.025, 0.62, rope, ladder, rot=(R90, 0, 0))

    merge_per_pivot()
    export_glb("vehicle_helicopter.glb")


# ---------------------------------------------------------------------------
# STATIONS
# ---------------------------------------------------------------------------
def build_med_station():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    white = make_mat("MedPaint", (0.78, 0.78, 0.74, 1), metallic=0.3, roughness=0.6, tex_prefix="rusted_metal")
    glass = make_mat("MedGlass", (0.2, 0.3, 0.32, 1), metallic=0.3, roughness=0.05)
    cross = make_mat("MedCross", (0.9, 0.06, 0.04, 1), emission=(1.0, 0.05, 0.03), emission_strength=1.2)
    serum = make_mat("Serum", (0.2, 0.9, 0.5, 1), emission=(0.2, 1.0, 0.5), emission_strength=1.6)
    steel = make_mat("Needle", (0.8, 0.8, 0.82, 1), metallic=0.9, roughness=0.25)
    tank = make_mat("O2Tank", (0.15, 0.4, 0.2, 1), metallic=0.5, roughness=0.45, tex_prefix="rusted_metal")
    r = add_pivot("Root")
    box("Plinth", (0, 0, 0.08), (1.2, 0.55, 0.16), dark, r)
    # Open-front cabinet shell so the serum syringes on the shelves show
    box("Back", (0, -0.2, 1.08), (1.1, 0.06, 1.84), white, r)
    for sx in (-1, 1):
        box("Side", (sx * 0.53, 0.0, 1.08), (0.04, 0.46, 1.84), white, r)
    box("Top", (0, 0.0, 1.98), (1.1, 0.46, 0.05), white, r)
    box("Drawer", (0, 0.0, 0.4), (1.02, 0.42, 0.44), white, r, bevel=0.02)
    box("DrawerHandle", (0, 0.22, 0.42), (0.3, 0.03, 0.04), steel, r)
    box("InsideBack", (0, -0.16, 1.2), (1.0, 0.02, 1.5), dark, r)
    for z in (0.66, 1.1, 1.54):
        box("Shelf", (0, 0.02, z), (1.0, 0.36, 0.025), metal, r)
    for i, (x, z) in enumerate(((-0.28, 0.66), (0.0, 0.66), (0.28, 0.66), (-0.14, 1.1), (0.16, 1.1), (0.0, 1.54))):
        c = z + 0.15
        cyl("SyringeBody%d" % i, (x, 0.06, c), 0.04, 0.24, glass, r)
        cyl("SyringeSerum%d" % i, (x, 0.06, c - 0.01), 0.033, 0.17, serum, r)
        cyl("SyringePlunger%d" % i, (x, 0.06, c + 0.16), 0.012, 0.1, steel, r)
        cyl("SyringeNeedle%d" % i, (x, 0.06, c - 0.15), 0.004, 0.07, steel, r)
    box("CrossH", (0, 0.24, 2.02), (0.36, 0.03, 0.11), cross, r)
    box("CrossV", (0, 0.24, 2.02), (0.11, 0.03, 0.36), cross, r)
    box("Sign", (0, 0.22, 2.02), (0.8, 0.02, 0.3), white, r)
    cyl("Tank", (0.72, 0.0, 0.62), 0.14, 1.1, tank, r)
    ball("TankTop", (0.72, 0.0, 1.2), (0.12, 0.12, 0.1), tank, r)
    seg("Hose", (0.72, 0.05, 1.25), (0.5, 0.22, 0.6), 0.02, 0.02, dark, r, verts=6)
    ball("Beacon", (0, 0.0, 2.08), (0.09, 0.09, 0.07), cross, r)
    merge_per_pivot()
    export_glb("prop_med_station.glb")


def build_radio_console():
    clear_scene()
    metal, dark, wood, conc = props_mats()
    olive = make_mat("RadioOlive", (0.3, 0.33, 0.22, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal")
    panel = make_mat("RadioPanel", (0.08, 0.08, 0.09, 1), metallic=0.3, roughness=0.5)
    amber = make_mat("DialAmber", (1.0, 0.65, 0.15, 1), emission=(1.0, 0.6, 0.12), emission_strength=4.0)
    green = make_mat("DialGreen", (0.3, 1.0, 0.35, 1), emission=(0.25, 1.0, 0.3), emission_strength=4.0)
    red = make_mat("TipRed", (1.0, 0.1, 0.08, 1), emission=(1.0, 0.08, 0.05), emission_strength=6.0)
    r = add_pivot("Root")
    box("TableTop", (0, 0, 0.84), (1.5, 0.75, 0.06), wood, r)
    for x in (-0.68, 0.68):
        for y in (-0.3, 0.3):
            box("TableLeg", (x, y, 0.41), (0.06, 0.06, 0.82), metal, r)
    box("RadioCase", (0, -0.05, 1.15), (1.15, 0.45, 0.56), olive, r, bevel=0.02)
    box("FrontPanel", (0, 0.18, 1.15), (1.05, 0.02, 0.48), panel, r)
    for i, x in enumerate((-0.38, -0.12, 0.14)):
        cyl("Dial%d" % i, (x, 0.2, 1.08), 0.055, 0.04, metal, r, rot=(R90, 0, 0))
    for i, x in enumerate((-0.35, -0.05)):
        box("Meter%d" % i, (x, 0.195, 1.3), (0.2, 0.01, 0.1), amber, r)
    box("FreqDisplay", (0.32, 0.195, 1.3), (0.3, 0.01, 0.08), green, r)
    for i in range(4):
        box("Switch%d" % i, (0.24 + i * 0.07, 0.2, 1.05), (0.02, 0.04, 0.06), metal, r)
    ball("StatusLamp", (0.45, 0.195, 1.05), (0.03, 0.02, 0.03), green, r)
    blob("Handset", (-0.5, 0.15, 0.92), (0.1, 0.32, 0.08), panel, r)
    seg("Cord", (-0.5, 0.0, 0.9), (-0.45, -0.2, 1.0), 0.012, 0.012, panel, r, verts=5)
    seg("Antenna", (0.45, -0.2, 1.43), (0.45, -0.2, 3.1), 0.015, 0.008, metal, r, verts=6)
    ball("AntennaTip", (0.45, -0.2, 3.12), (0.035, 0.035, 0.035), red, r)
    box("Battery", (-0.4, -0.2, 0.98), (0.3, 0.22, 0.22), olive, r)
    for i in range(3):
        box("Paper%d" % i, (0.35 + i * 0.05, 0.2, 0.875), (0.22, 0.28, 0.004), make_mat("Paper", (0.7, 0.66, 0.55, 1), roughness=0.9), r, rot=(0, 0, 0.2 * i))
    merge_per_pivot()
    export_glb("prop_radio_console.glb")


# Co-op teammates: the soldier body as a living survivor (no wounds, human
# skin, plain eyes), same joints so the zombie rig can animate it.
SURVIVOR_STRIP = ("Wound", "Rib", "ScalpWound", "Guts", "SpineBone", "ExposedBone", "ArmWound", "Claw", "Tooth")


def build_survivor():
    orig = v3.export_glb

    def export_survivor(_filename):
        skin = make_mat("SurvivorSkin", (0.6, 0.43, 0.34, 1), roughness=0.55)
        eye = make_mat("SurvivorEye", (0.05, 0.04, 0.035, 1), roughness=0.15)
        for obj in list(bpy.data.objects):
            if obj.type != "MESH":
                continue
            if obj.name.startswith(SURVIVOR_STRIP):
                bpy.data.objects.remove(obj, do_unlink=True)
                continue
            for slot in obj.material_slots:
                m = slot.material
                if m is None:
                    continue
                if m.name.startswith("Skin") or m.name.startswith("Socket"):
                    slot.material = skin
                elif m.name.startswith("Eye"):
                    slot.material = eye
        merge_per_pivot()
        orig("player_survivor.glb")

    v3.export_glb = export_survivor
    try:
        v3.build_zombie("soldier")
    finally:
        v3.export_glb = orig


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def want(name):
        return not only or name in only

    if want("hound"):
        build_hound()
    if want("bloater"):
        build_bloater()
    if want("heli"):
        build_helicopter()
    if want("props"):
        build_med_station()
        build_radio_console()
    if want("zombies"):
        build_zombies_merged()
    if want("survivor"):
        build_survivor()
    print("ALL V4 MODELS GENERATED")
