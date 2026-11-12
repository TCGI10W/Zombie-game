"""Generate brand-new v7.1 sculpted 3D models for all Dead Protocol Zombies & Blight Hound:
  - assets/models/zombie_walker_v2.glb (+ zombie_walker.glb)
  - assets/models/zombie_runner_v2.glb
  - assets/models/zombie_soldier_v2.glb
  - assets/models/zombie_bloater.glb
  - assets/models/enemy_hound.glb

Run with:
  "D:\Blender 4.5\blender.exe" -b --factory-startup -P tools/generate_zombies_v7.py
"""
import math
import os
import random
import shutil
import sys
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt_kit_v7 import (  # noqa: E402
    OUT_DIR,
    R90,
    add_pivot,
    auto_uv,
    build_sculpted_undead_head,
    build_zombie_armature_and_skin,
    chain_strand,
    clear_scene,
    export_glb,
    loft_anatomical,
    loft_open_arc,
    make_mat,
    merge_per_pivot,
    neon_mat,
    prim_mesh,
    seg_limb,
    spline_tube,
    voxel_fuse_and_sculpt,
)


# ---------------------------------------------------------------------------
# SEAMLESS CONTINUOUS ANATOMICAL HANDS, ARMS & LEGS (ZERO MANNEQUIN SEAMS!)
# ---------------------------------------------------------------------------
def build_zombie_hand_fingers(prefix, nm, sx, wr, hand_piv, m_skin, m_claw, claw_len=0.018, thin=1.0):
    wx, wy, wz = wr
    finger_specs = [
        (-0.025, 0.056, 0.0090),
        (-0.008, 0.065, 0.0096),
        (0.009, 0.061, 0.0090),
        (0.024, 0.049, 0.0080),
    ]
    for fi, (lat, flen, frad) in enumerate(finger_specs):
        fx = wx + lat * thin
        p0 = (fx, wy + 0.010, wz - 0.072)
        p1 = (fx, wy + 0.028, wz - 0.072 - flen * 0.52)
        p2 = (fx, wy + 0.016, wz - 0.072 - flen)
        loft_anatomical(f"{prefix}_Finger{nm}{fi}", [
            (p0, frad * thin, frad * thin, frad * thin),
            (p1, frad * 0.86 * thin, frad * 0.86 * thin, frad * 0.86 * thin),
            (p2, frad * 0.68 * thin, frad * 0.68 * thin, frad * 0.68 * thin),
        ], mat=m_skin, parent=hand_piv, segs=8, subsurf=0, uv_scale=4.0)
        prim_mesh(f"{prefix}_Claw{nm}{fi}", "CONE",
                  (fx, wy + 0.012, wz - 0.072 - flen - claw_len * 0.42),
                  (frad * 1.15, frad * 1.35, claw_len), rot=(math.radians(168), 0, 0),
                  mat=m_claw, parent=hand_piv, verts=6)

    # Opposable gnarled thumb
    tx0 = (wx - sx * 0.026 * thin, wy + 0.012, wz - 0.030)
    tx1 = (wx - sx * 0.038 * thin, wy + 0.038, wz - 0.064)
    tx2 = (wx - sx * 0.032 * thin, wy + 0.046, wz - 0.088)
    loft_anatomical(f"{prefix}_Thumb{nm}", [
        (tx0, 0.012 * thin, 0.012 * thin, 0.012 * thin),
        (tx1, 0.0095 * thin, 0.0095 * thin, 0.0095 * thin),
        (tx2, 0.0075 * thin, 0.0075 * thin, 0.0075 * thin),
    ], mat=m_skin, parent=hand_piv, segs=8, subsurf=0, uv_scale=4.0)


def build_zombie_arms(prefix, chest_piv, m_skin, m_sleeve_l, m_sleeve_r, m_claw, m_gore, m_bone,
                      sh_x=0.225, el_x=0.245, wr_x=0.245, thin=1.0, bulk=1.0,
                      sleeve_len_l=0.0, sleeve_len_r=0.55, claw_len=0.018,
                      bite_wound_l=False, m_glove=None):
    """Build ONE continuous shoulder-to-palm anatomical arm mesh per side so there is ZERO
    pinched ball-joint seam at the shoulder, elbow, or wrist!"""
    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * sh_x, 0.0, 1.48)
        el = (sx * el_x, 0.012, 1.20)
        wr = (sx * wr_x, 0.022, 0.95)
        s_mat = m_sleeve_l if nm == "L" else m_sleeve_r
        s_len = sleeve_len_l if nm == "L" else sleeve_len_r

        up_piv = add_pivot("UpperArm" + nm, sh, parent=chest_piv)
        fore_piv = add_pivot("Forearm" + nm, el, parent=up_piv)
        hand_piv = add_pivot("Hand" + nm, wr, parent=fore_piv)

        full_cloth = (s_len >= 1.15 and s_mat is not None)
        arm_mat = s_mat if full_cloth else m_skin
        hand_mat = m_glove if m_glove is not None else m_skin

        # Continuous Shoulder Deltoid -> Bicep/Tricep -> Elbow -> Brachioradialis Forearm -> Wrist -> Palm!
        arm_stations = [
            {"pos": (sh[0] - sx * 0.038, -0.004, sh[2] + 0.045), "rx": 0.072 * bulk, "ry_f": 0.068 * bulk, "ry_b": 0.072 * bulk},
            {"pos": (sh[0] + sx * 0.008, 0.0, sh[2] - 0.045), "rx": 0.070 * thin * bulk, "ry_f": 0.068 * bulk, "ry_b": 0.068 * bulk,
             "harmonics": [(3, 0.04, 0.2)]},
            {"pos": ((sh[0] + el[0]) * 0.5, 0.008, (sh[2] + el[2]) * 0.5 + 0.01),
             "rx": 0.058 * thin * bulk, "ry_f": 0.064 * thin * bulk, "ry_b": 0.060 * thin * bulk,
             "harmonics": [(4, 0.04 if full_cloth else 0.02, 0.6)]},
            {"pos": el, "rx": 0.050 * thin * bulk, "ry_f": 0.048 * thin * bulk, "ry_b": 0.054 * thin * bulk},
            {"pos": (el[0] * 0.68 + wr[0] * 0.32, 0.016, el[2] * 0.68 + wr[2] * 0.32),
             "rx": 0.054 * thin * bulk, "ry_f": 0.056 * thin * bulk, "ry_b": 0.050 * thin * bulk,
             "harmonics": [(3, 0.05, 0.0)]},
            {"pos": (el[0] * 0.28 + wr[0] * 0.72, 0.020, el[2] * 0.28 + wr[2] * 0.72),
             "rx": 0.041 * thin * bulk, "ry_f": 0.038 * thin * bulk, "ry_b": 0.038 * thin * bulk},
            {"pos": wr, "rx": 0.036 * thin * bulk, "ry_f": 0.024 * thin, "ry_b": 0.025 * thin},
        ]
        if m_glove is None:
            # Extend bare skin seamlessly through the metacarpal palm!
            arm_stations.extend([
                {"pos": (wr[0] + sx * 0.003, wr[1] + 0.008, wr[2] - 0.042), "rx": 0.039 * thin, "ry_f": 0.020 * thin, "ry_b": 0.018 * thin},
                {"pos": (wr[0] + sx * 0.002, wr[1] + 0.011, wr[2] - 0.076), "rx": 0.035 * thin, "ry_f": 0.016 * thin, "ry_b": 0.015 * thin},
            ])
        loft_anatomical(f"{prefix}_FullArm{nm}", arm_stations, mat=arm_mat, parent=up_piv, segs=18, subsurf=1)

        if m_glove is not None:
            loft_anatomical(f"{prefix}_GlovePalm{nm}", [
                {"pos": (wr[0], wr[1], wr[2] + 0.020), "rx": 0.042 * thin, "ry_f": 0.028 * thin, "ry_b": 0.028 * thin},
                {"pos": (wr[0] + sx * 0.003, wr[1] + 0.008, wr[2] - 0.042), "rx": 0.041 * thin, "ry_f": 0.022 * thin, "ry_b": 0.020 * thin},
                {"pos": (wr[0] + sx * 0.002, wr[1] + 0.011, wr[2] - 0.076), "rx": 0.037 * thin, "ry_f": 0.017 * thin, "ry_b": 0.016 * thin},
            ], mat=m_glove, parent=hand_piv, segs=14, subsurf=1)

        # Draped tattered cloth sleeve over bare arm if partially sleeved!
        if 0.15 < s_len < 1.05 and s_mat is not None:
            end_p = Vector(sh).lerp(Vector(el), min(s_len, 0.95)) if s_len <= 0.95 else Vector(el).lerp(Vector(wr), s_len - 0.95)
            loft_anatomical(f"{prefix}_Sleeve{nm}", [
                {"pos": (sh[0] - sx * 0.035, 0.0, sh[2] + 0.048), "rx": 0.078 * bulk, "ry_f": 0.076 * bulk, "ry_b": 0.078 * bulk},
                {"pos": (sh[0] + sx * 0.008, 0.004, sh[2] - 0.065), "rx": 0.080 * bulk, "ry_f": 0.078 * bulk, "ry_b": 0.078 * bulk,
                 "harmonics": [(4, 0.05, 0.4)]},
                {"pos": end_p, "rx": 0.072 * bulk, "ry_f": 0.072 * bulk, "ry_b": 0.072 * bulk,
                 "harmonics": [(6, 0.09, 1.1)]},
            ], mat=s_mat, parent=up_piv, segs=18, cap_start=True, cap_end=False,
               open_shell_thickness=0.006, tear_end_amp=0.038, tear_seed=3 + sx)

        if bite_wound_l and nm == "L":
            prim_mesh(f"{prefix}_ArmGash", "SPHERE",
                      (el[0] + 0.010, el[1] + 0.036, (el[2] + wr[2]) * 0.52),
                      (0.038, 0.022, 0.125), mat=m_gore, parent=fore_piv, verts=14)
            seg_limb(f"{prefix}_UlnaBone",
                     (el[0] + 0.012, el[1] + 0.042, el[2] - 0.06),
                     (wr[0] + 0.010, wr[1] + 0.038, wr[2] + 0.06),
                     0.009, 0.007, mat=m_bone, parent=fore_piv, verts=8)

        build_zombie_hand_fingers(prefix, nm, sx, wr, hand_piv, hand_mat, m_claw, claw_len=claw_len, thin=thin)


def build_zombie_foot(prefix, nm, sx, an, foot_piv, m_boot, m_skin, is_boot=True, tall_boot=False):
    ax, ay, az = an
    if is_boot:
        shaft_top = 0.245 if tall_boot else 0.155
        loft_anatomical(f"{prefix}_BootShaft{nm}", [
            {"pos": (ax, ay - 0.008, 0.042), "rx": 0.056, "ry_f": 0.062, "ry_b": 0.058},
            {"pos": (ax, ay - 0.004, shaft_top), "rx": 0.060, "ry_f": 0.064, "ry_b": 0.062},
        ], mat=m_boot, parent=foot_piv, segs=16, subsurf=1)
        loft_anatomical(f"{prefix}_Boot{nm}", [
            {"pos": (ax, ay - 0.052, 0.046), "rx": 0.056, "ry_f": 0.058, "ry_b": 0.050},
            {"pos": (ax, ay + 0.038, 0.045), "rx": 0.054, "ry_f": 0.052, "ry_b": 0.044},
            {"pos": (ax, ay + 0.120, 0.043), "rx": 0.060, "ry_f": 0.048, "ry_b": 0.040},
            {"pos": (ax, ay + 0.188, 0.038), "rx": 0.052, "ry_f": 0.038, "ry_b": 0.032},
        ], mat=m_boot, parent=foot_piv, segs=16, subsurf=1)
        m_sole = make_mat(f"{prefix}_Sole{nm}", (0.09, 0.085, 0.08, 1), roughness=0.92)
        prim_mesh(f"{prefix}_BootSole{nm}", "CUBE",
                  (ax, ay + 0.068, 0.013), (0.116, 0.268, 0.026),
                  mat=m_sole, parent=foot_piv, bevel=0.006)
    else:
        loft_anatomical(f"{prefix}_BareFoot{nm}", [
            {"pos": (ax, ay - 0.045, 0.048), "rx": 0.042, "ry_f": 0.042, "ry_b": 0.038},
            {"pos": (ax, ay + 0.035, 0.034), "rx": 0.046, "ry_f": 0.034, "ry_b": 0.028},
            {"pos": (ax, ay + 0.118, 0.026), "rx": 0.052, "ry_f": 0.025, "ry_b": 0.020},
        ], mat=m_skin, parent=foot_piv, segs=14, subsurf=1)
        for ti in range(5):
            tx = ax + (ti - 2.0) * 0.019 * (-sx)
            tlen = 0.042 - ti * 0.004
            seg_limb(f"{prefix}_Toe{nm}{ti}",
                     (tx, ay + 0.115, 0.022), (tx, ay + 0.115 + tlen, 0.010),
                     0.010 - ti * 0.0008, 0.007 - ti * 0.0006, mat=m_skin, parent=foot_piv, verts=8)


# ---------------------------------------------------------------------------
# 1. ZOMBIE WALKER V2 (+ ZOMBIE WALKER) — DECAY CIVILIAN SHAMBLER
# ---------------------------------------------------------------------------
def build_walker():
    clear_scene()
    m_skin = make_mat("WalkerSkin", (0.46, 0.50, 0.40, 1), roughness=0.66, tex_prefix="necrotic_flesh", normal_strength=1.25, contrast=1.38)
    # CRITICAL: material MUST be named "Shirt" so ZombieEnemy._tint_shirt() randomizes horde shirts!
    m_shirt = make_mat("Shirt", (0.48, 0.47, 0.44, 1), roughness=0.88, tex_prefix="fabric", normal_strength=1.15, contrast=1.35)
    m_blood_cloth = make_mat("BloodSoakedCloth", (0.22, 0.05, 0.04, 1), roughness=0.72, tex_prefix="fabric")
    m_jeans = make_mat("WalkerJeans", (0.28, 0.35, 0.46, 1), roughness=0.88, tex_prefix="denim", normal_strength=1.25, contrast=1.40)
    m_boot = make_mat("WalkerBoot", (0.24, 0.17, 0.13, 1), roughness=0.68, tex_prefix="leather", contrast=1.35)
    m_belt = make_mat("WalkerBelt", (0.10, 0.08, 0.07, 1), roughness=0.52, tex_prefix="leather")
    m_brass = make_mat("BeltBuckle", (0.50, 0.42, 0.24, 1), metallic=0.82, roughness=0.38)
    m_gore = make_mat("WalkerGore", (0.28, 0.03, 0.025, 1), roughness=0.20)
    m_bone = make_mat("WalkerBone", (0.68, 0.63, 0.50, 1), roughness=0.50)
    m_claw = make_mat("WalkerClaw", (0.12, 0.10, 0.08, 1), roughness=0.42)
    m_hair = make_mat("WalkerHair", (0.09, 0.08, 0.07, 1), roughness=0.92, tex_prefix="gorilla_fur")
    m_eye = neon_mat("WalkerEye", (1.0, 0.68, 0.12), strength=3.8, roughness=0.15)

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    spine = add_pivot("Spine", (0, 0, 1.07), parent=hips)
    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    head = add_pivot("Head", (0, 0.03, 1.56), parent=chest)
    jaw = add_pivot("Jaw", (0, 0.07, 1.66), parent=head)

    # Sculpted Pelvis & Belt
    loft_anatomical("WalkerPelvis", [
        {"pos": (0, 0, 0.88), "rx": 0.162, "ry_f": 0.110, "ry_b": 0.128},
        {"pos": (0, 0, 0.98), "rx": 0.182, "ry_f": 0.122, "ry_b": 0.136},
        {"pos": (0, 0, 1.06), "rx": 0.168, "ry_f": 0.114, "ry_b": 0.122},
    ], mat=m_jeans, parent=hips, segs=20, subsurf=1)
    prim_mesh("BeltRing", "CYLINDER", (0, 0.004, 1.045), (0.355, 0.252, 0.044), mat=m_belt, parent=hips, bevel=0.006, verts=24)
    prim_mesh("Buckle", "CUBE", (0, 0.130, 1.045), (0.058, 0.018, 0.048), mat=m_brass, parent=hips, bevel=0.004)

    # Voxel-sculpted Gaunt Undead Flesh Torso with CARVED Left Pectoral Bite Cavity!
    torso_base = loft_anatomical("WalkerTorsoBase", [
        {"pos": (0, 0, 1.02), "rx": 0.155, "ry_f": 0.102, "ry_b": 0.112},
        {"pos": (0, -0.008, 1.16), "rx": 0.142, "ry_f": 0.092, "ry_b": 0.108},
        {"pos": (0, 0.006, 1.31), "rx": 0.182, "ry_f": 0.122, "ry_b": 0.126},
        {"pos": (0, 0.012, 1.45), "rx": 0.212, "ry_f": 0.126, "ry_b": 0.132},
        {"pos": (0, 0.018, 1.56), "rx": 0.138, "ry_f": 0.092, "ry_b": 0.102},
    ], segs=22, subsurf=1)
    torso_ops = [
        # Deep irregular claw/bite cavity carved right INTO left chest!
        ("carve", (-0.068, 0.125, 1.355), (0.085, 0.065, 0.095), 0.058),
        ("crease", (0, 0.125, 1.24), (0, 0.128, 1.48), 0.018, 0.010),  # sternum hollow
        ("crease", (-0.02, 0.115, 1.49), (-0.17, 0.06, 1.48), 0.016, 0.009),  # clavicle L
        ("crease", (0.02, 0.115, 1.49), (0.17, 0.06, 1.48), 0.016, 0.009),   # clavicle R
    ]
    for ri in range(3):
        rz = 1.24 + ri * 0.042
        torso_ops.append(("crease", (0.03, 0.12, rz), (0.15, 0.05, rz - 0.02), 0.014, 0.008))
    voxel_fuse_and_sculpt("WalkerTorsoFlesh", [torso_base], voxel_size=0.009,
                          sculpt_ops=torso_ops, smooth_iters=2, decimate_ratio=0.48,
                          mat=m_skin, parent=chest, uv_scale=2.4)

    # Wet dark gore + curved anatomical ribs recessed INSIDE the carved pectoral wound!
    prim_mesh("ChestGoreCavity", "SPHERE", (-0.065, 0.096, 1.355), (0.125, 0.055, 0.145),
              rot=(0, -0.22, 0.18), mat=m_gore, parent=chest, verts=16)
    for ri in range(3):
        rz = 1.395 - ri * 0.036
        spline_tube(f"ExposedRib{ri}", [
            (-0.015, 0.118, rz),
            (-0.068, 0.122, rz - 0.006),
            (-0.122, 0.100, rz - 0.015),
        ], radius=0.0075, mat=m_bone, parent=chest, segs=8)

    # OPEN-FRONT Ragged Button-Down "Shirt" (`loft_open_arc`) parted asymmetrically over the chest wound!
    loft_open_arc("WalkerShirtShell", [
        {"pos": (0, 0.015, 1.54), "rx": 0.158, "ry_f": 0.104, "ry_b": 0.112, "gap_deg": 78.0, "gap_offset_deg": 12.0},
        {"pos": (0, 0.010, 1.44), "rx": 0.226, "ry_f": 0.138, "ry_b": 0.144, "gap_deg": 72.0, "gap_offset_deg": 18.0, "harmonics": [(5, 0.04, 0.5)]},
        {"pos": (0, 0.004, 1.29), "rx": 0.198, "ry_f": 0.134, "ry_b": 0.138, "gap_deg": 56.0, "gap_offset_deg": 22.0, "harmonics": [(7, 0.05, 1.2)]},
        {"pos": (0, 0.002, 1.13), "rx": 0.184, "ry_f": 0.128, "ry_b": 0.132, "gap_deg": 34.0, "gap_offset_deg": 10.0, "harmonics": [(8, 0.06, 2.0)]},
        {"pos": (0, 0.004, 0.99), "rx": 0.194, "ry_f": 0.136, "ry_b": 0.140, "gap_deg": 48.0, "gap_offset_deg": 6.0, "harmonics": [(9, 0.07, 0.7)]},
    ], mat=m_shirt, parent=chest, segs=26, thickness=0.008, tear_end_amp=0.060, tear_lapel_amp=0.045, tear_seed=11)

    # Coagulated bloodstain soaking right shirt lapel & collar flaps
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"Collar{nm}", "CUBE", (sx * 0.078, 0.058, 1.54), (0.068, 0.088, 0.042),
                  rot=(0.28, sx * 0.45, sx * -0.28), mat=m_shirt, parent=chest, bevel=0.006)
    prim_mesh("BloodDripChest", "SPHERE", (-0.055, 0.118, 1.24), (0.065, 0.020, 0.115), mat=m_blood_cloth, parent=chest, verts=12)

    # Voxel-sculpted Decay Head + Hinged Jaw + Stringy Hair wisps
    build_sculpted_undead_head("Walker", head, jaw, (0, 0.03, 1.56), m_skin, m_eye, m_bone, m_gore, scale=1.0, gaunt=1.15)
    prim_mesh("CheekTearR", "SPHERE", (0.062, 0.120, 1.665), (0.036, 0.026, 0.042), mat=m_gore, parent=head, verts=12)
    for hi, ang in enumerate((-2.5, -2.0, -1.4, -0.8, 0.9, 1.5, 2.1, 2.6)):
        hx0 = math.sin(ang) * 0.078
        hy0 = 0.035 + math.cos(ang) * 0.078
        spline_tube(f"HairStrand{hi}", [
            (hx0 * 0.5, hy0 * 0.5 + 0.01, 1.785),
            (hx0 * 1.08, hy0 * 1.02, 1.745),
            (hx0 * 1.18, hy0 * 1.06, 1.675 - (hi % 3) * 0.022),
        ], radius=0.011, mat=m_hair, parent=head, segs=6)

    # Continuous Seamless Arms
    build_zombie_arms("Walker", chest, m_skin, m_shirt, m_shirt, m_claw, m_gore, m_bone,
                      sh_x=0.232, el_x=0.252, wr_x=0.252, sleeve_len_l=0.35, sleeve_len_r=0.82,
                      claw_len=0.018, bite_wound_l=True)

    # Continuous Seamless Legs (NO knee ball-joint seams!)
    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.115, 0.0, 0.94)
        kn = (sx * 0.120, 0.012, 0.52)
        an = (sx * 0.120, 0.0, 0.10)
        th_piv = add_pivot("Thigh" + nm, hp, parent=hips)
        sh_piv = add_pivot("Shin" + nm, kn, parent=th_piv)
        ft_piv = add_pivot("Foot" + nm, an, parent=sh_piv)

        if nm == "L":
            # Continuous bare left leg underneath torn shredded denim thigh/knee!
            loft_anatomical("WalkerFullLegFleshL", [
                {"pos": (hp[0], 0.0, 0.95), "rx": 0.080, "ry_f": 0.082, "ry_b": 0.088},
                {"pos": (hp[0] * 0.6 + kn[0] * 0.4, 0.012, 0.72), "rx": 0.070, "ry_f": 0.074, "ry_b": 0.072},
                {"pos": kn, "rx": 0.056, "ry_f": 0.056, "ry_b": 0.058},
                {"pos": (kn[0], 0.0, 0.36), "rx": 0.052, "ry_f": 0.046, "ry_b": 0.062},
                {"pos": an, "rx": 0.038, "ry_f": 0.038, "ry_b": 0.042},
            ], mat=m_skin, parent=th_piv, segs=18, subsurf=1)
            loft_anatomical("WalkerTornJeansL", [
                {"pos": (hp[0], 0.0, 0.96), "rx": 0.094, "ry_f": 0.094, "ry_b": 0.100},
                {"pos": (hp[0] * 0.5 + kn[0] * 0.5, 0.012, 0.68), "rx": 0.084, "ry_f": 0.086, "ry_b": 0.086, "harmonics": [(4, 0.04, 0.3)]},
                {"pos": (kn[0], 0.010, 0.42), "rx": 0.076, "ry_f": 0.076, "ry_b": 0.076, "harmonics": [(6, 0.09, 0.8)]},
            ], mat=m_jeans, parent=th_piv, segs=18, cap_start=True, cap_end=False,
               open_shell_thickness=0.006, tear_end_amp=0.045, tear_seed=19)
            prim_mesh("ShinWoundL", "SPHERE", (kn[0] + 0.008, 0.040, 0.30), (0.034, 0.022, 0.115), mat=m_gore, parent=sh_piv, verts=12)
            seg_limb("TibiaBoneL", (kn[0] + 0.008, 0.046, 0.35), (an[0] + 0.008, 0.040, 0.23), 0.010, 0.008, mat=m_bone, parent=sh_piv, verts=8)
            build_zombie_foot("Walker", nm, sx, an, ft_piv, m_boot, m_skin, is_boot=False)
        else:
            # Continuous hip-to-boot denim leg!
            loft_anatomical("WalkerFullJeansR", [
                {"pos": (hp[0], 0.0, 0.96), "rx": 0.094, "ry_f": 0.094, "ry_b": 0.100},
                {"pos": (hp[0] * 0.6 + kn[0] * 0.4, 0.012, 0.73), "rx": 0.084, "ry_f": 0.088, "ry_b": 0.086, "harmonics": [(4, 0.04, 0.3)]},
                {"pos": kn, "rx": 0.070, "ry_f": 0.072, "ry_b": 0.072, "harmonics": [(5, 0.04, 1.1)]},
                {"pos": (kn[0], 0.0, 0.33), "rx": 0.066, "ry_f": 0.062, "ry_b": 0.072, "harmonics": [(5, 0.04, 0.7)]},
                {"pos": (an[0], 0.0, 0.13), "rx": 0.068, "ry_f": 0.068, "ry_b": 0.068, "harmonics": [(6, 0.06, 1.5)]},
            ], mat=m_jeans, parent=th_piv, segs=18, subsurf=1)
            build_zombie_foot("Walker", nm, sx, an, ft_piv, m_boot, m_skin, is_boot=True, tall_boot=False)

    build_zombie_armature_and_skin("ZombieWalker", sh_x=0.232, el_x=0.252, wr_x=0.252)
    export_glb("zombie_walker_v2.glb")
    shutil.copy2(os.path.join(OUT_DIR, "zombie_walker_v2.glb"), os.path.join(OUT_DIR, "zombie_walker.glb"))


# ---------------------------------------------------------------------------
# 2. ZOMBIE RUNNER V2 — FERAL PREDATORY SPRINTER
# ---------------------------------------------------------------------------
def build_runner():
    clear_scene()
    m_skin = make_mat("RunnerSkin", (0.42, 0.39, 0.38, 1), roughness=0.55, tex_prefix="necrotic_flesh", normal_strength=1.40, contrast=1.42)
    m_rags = make_mat("RunnerRags", (0.24, 0.11, 0.10, 1), roughness=0.90, tex_prefix="fabric", contrast=1.35)
    m_shorts = make_mat("RunnerShorts", (0.22, 0.20, 0.19, 1), roughness=0.90, tex_prefix="burlap", contrast=1.35)
    m_gore = make_mat("RunnerGore", (0.28, 0.02, 0.02, 1), roughness=0.18)
    m_bone = make_mat("RunnerBone", (0.66, 0.60, 0.46, 1), roughness=0.48)
    m_claw = make_mat("RunnerClaw", (0.06, 0.05, 0.05, 1), roughness=0.32)
    m_hair = make_mat("RunnerHair", (0.07, 0.06, 0.06, 1), roughness=0.92, tex_prefix="gorilla_fur")
    m_eye = neon_mat("RunnerEye", (1.0, 0.14, 0.05), strength=5.2, roughness=0.12)

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    spine = add_pivot("Spine", (0, 0, 1.07), parent=hips)
    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    head = add_pivot("Head", (0, 0.05, 1.55), parent=chest)
    jaw = add_pivot("Jaw", (0, 0.09, 1.65), parent=head)

    # Lean pelvis + tattered dark shorts
    loft_anatomical("RunnerPelvis", [
        {"pos": (0, 0, 0.89), "rx": 0.142, "ry_f": 0.095, "ry_b": 0.112},
        {"pos": (0, 0, 0.99), "rx": 0.156, "ry_f": 0.102, "ry_b": 0.116},
        {"pos": (0, 0, 1.06), "rx": 0.140, "ry_f": 0.092, "ry_b": 0.102},
    ], mat=m_shorts, parent=hips, segs=18, subsurf=1)

    # Voxel-sculpted Hunched Starved Ribcage & Diagonal Abdominal Slash Cavity (NO red ball, NO tube-bra!)
    torso_base = loft_anatomical("RunnerTorsoBase", [
        {"pos": (0, 0, 1.02), "rx": 0.135, "ry_f": 0.086, "ry_b": 0.098},
        {"pos": (0, -0.010, 1.15), "rx": 0.118, "ry_f": 0.072, "ry_b": 0.095},
        {"pos": (0, 0.012, 1.30), "rx": 0.168, "ry_f": 0.112, "ry_b": 0.118},
        {"pos": (0, 0.028, 1.44), "rx": 0.195, "ry_f": 0.116, "ry_b": 0.125},
        {"pos": (0, 0.040, 1.54), "rx": 0.125, "ry_f": 0.084, "ry_b": 0.094},
    ], segs=22, subsurf=1)

    rib_ops = [
        # Deep starved sub-costal hollow + diagonal evisceration gash carved INTO stomach!
        ("carve", (0, 0.082, 1.16), (0.090, 0.055, 0.095), 0.028),
        ("crease", (-0.065, 0.085, 1.21), (0.065, 0.075, 1.12), 0.028, 0.036),
        ("crease", (0, 0.118, 1.26), (0, 0.132, 1.49), 0.016, 0.010),  # sternum
        ("crease", (0, -0.11, 1.08), (0, -0.10, 1.50), 0.022, 0.012),
    ]
    for ri in range(5):
        rz = 1.25 + ri * 0.038
        rib_ops.append(("crease", (-0.025, 0.115, rz), (-0.16, 0.04, rz - 0.025), 0.013, 0.011))
        rib_ops.append(("crease", (0.025, 0.115, rz), (0.16, 0.04, rz - 0.025), 0.013, 0.011))

    voxel_fuse_and_sculpt("RunnerSculptTorso", [torso_base], voxel_size=0.0085,
                          sculpt_ops=rib_ops, smooth_iters=2, decimate_ratio=0.48,
                          mat=m_skin, parent=chest, uv_scale=2.4)

    # Recessed glistening viscera & jagged lower rib tips tucked inside the carved diagonal abdominal slash!
    prim_mesh("GutSlashGore", "SPHERE", (0.004, 0.032, 1.162), (0.108, 0.028, 0.064),
              rot=(0, 0, -0.55), mat=m_gore, parent=spine, verts=14)
    for gi, (gx0, gz0, gx1, gz1) in enumerate(((-0.052, 1.215, -0.018, 1.185), (0.052, 1.155, 0.018, 1.148))):
        spline_tube(f"SlashRibTip{gi}", [(gx0, 0.072, gz0), (gx1, 0.076, gz1)],
                    radius=0.0065, mat=m_bone, parent=spine, segs=6)
    # Blood trail from jaw/neck down sternum
    prim_mesh("SternumBlood", "SPHERE", (0.008, 0.118, 1.42), (0.042, 0.014, 0.118), mat=m_gore, parent=chest, verts=12)

    # Asymmetrical torn dark bloodstained rag draped over right shoulder ONLY (leaving starved left ribs exposed!)
    loft_open_arc("RunnerTornSash", [
        {"pos": (0.02, 0.012, 1.29), "rx": 0.188, "ry_f": 0.124, "ry_b": 0.130, "gap_deg": 152.0, "gap_offset_deg": 44.0, "harmonics": [(7, 0.09, 1.4)]},
        {"pos": (0.025, 0.024, 1.41), "rx": 0.212, "ry_f": 0.132, "ry_b": 0.138, "gap_deg": 136.0, "gap_offset_deg": 40.0, "harmonics": [(6, 0.07, 0.6)]},
        {"pos": (0.03, 0.036, 1.51), "rx": 0.175, "ry_f": 0.112, "ry_b": 0.118, "gap_deg": 124.0, "gap_offset_deg": 36.0},
    ], mat=m_rags, parent=chest, segs=18, thickness=0.006, tear_end_amp=0.045, tear_lapel_amp=0.045, tear_seed=31)

    # Protruding spinous dorsal vertebrae spikes erupting along hunched spine!
    for vi in range(7):
        vz = 1.10 + vi * 0.062
        vy = -0.092 - 0.022 * math.sin(vi * 0.45)
        prim_mesh(f"SpineSpike{vi}", "CONE", (0, vy, vz), (0.022, 0.032, 0.046),
                  rot=(-math.radians(108), 0, 0), mat=m_bone, parent=chest, verts=6)

    # Rabid crane-necked skull with long fangs, crimson eyes & wild stringy hair!
    build_sculpted_undead_head("Runner", head, jaw, (0, 0.05, 1.55), m_skin, m_eye, m_bone, m_gore,
                               scale=0.97, gaunt=1.38, rabid=True)
    prim_mesh("RabidBloodChin", "SPHERE", (0, 0.135, 1.60), (0.052, 0.032, 0.038), mat=m_gore, parent=jaw, verts=12)
    for hi, ang in enumerate((-2.7, -2.1, -1.5, 1.5, 2.1, 2.7)):
        hx0 = math.sin(ang) * 0.075
        hy0 = 0.05 + math.cos(ang) * 0.075
        spline_tube(f"FeralHair{hi}", [
            (hx0 * 0.5, hy0 * 0.5 + 0.02, 1.77),
            (hx0 * 1.12, hy0 * 1.0, 1.72),
            (hx0 * 1.28, hy0 * 0.95, 1.63),
        ], radius=0.010, mat=m_hair, parent=head, segs=6)

    # Continuous Sinewy Long-Clawed Sprinter Arms (zero elbow/wrist doll seams!) + forearm rag wrap
    build_zombie_arms("Runner", chest, m_skin, None, None, m_claw, m_gore, m_bone,
                      sh_x=0.205, el_x=0.225, wr_x=0.225, thin=0.88, bulk=0.98,
                      sleeve_len_l=0.0, sleeve_len_r=0.0, claw_len=0.036, bite_wound_l=True)

    # Continuous Sinewy Sprinter Legs (single hip-to-ankle anatomical muscle loft!)
    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.105, 0.0, 0.94)
        kn = (sx * 0.112, 0.015, 0.52)
        an = (sx * 0.112, 0.0, 0.10)
        th_piv = add_pivot("Thigh" + nm, hp, parent=hips)
        sh_piv = add_pivot("Shin" + nm, kn, parent=th_piv)
        ft_piv = add_pivot("Foot" + nm, an, parent=sh_piv)

        short_end = 0.66 if nm == "L" else 0.74
        loft_anatomical(f"RunnerShortLeg{nm}", [
            {"pos": (hp[0], 0, 0.96), "rx": 0.084, "ry_f": 0.084, "ry_b": 0.090},
            {"pos": (hp[0], 0.010, short_end), "rx": 0.078, "ry_f": 0.080, "ry_b": 0.080, "harmonics": [(6, 0.09, 1.2)]},
        ], mat=m_shorts, parent=th_piv, segs=16, cap_start=True, cap_end=False,
           open_shell_thickness=0.005, tear_end_amp=0.048, tear_seed=40 + sx)

        loft_anatomical(f"RunnerFullLeg{nm}", [
            {"pos": (hp[0], 0, 0.95), "rx": 0.076, "ry_f": 0.078, "ry_b": 0.084},
            {"pos": (hp[0], 0.014, 0.72), "rx": 0.068, "ry_f": 0.076, "ry_b": 0.072, "harmonics": [(3, 0.06, 0.0)]},
            {"pos": kn, "rx": 0.053, "ry_f": 0.056, "ry_b": 0.055},
            {"pos": (kn[0], 0.004, 0.36), "rx": 0.048, "ry_f": 0.042, "ry_b": 0.062},
            {"pos": an, "rx": 0.035, "ry_f": 0.036, "ry_b": 0.040},
        ], mat=m_skin, parent=th_piv, segs=18, subsurf=1)
        build_zombie_foot("Runner", nm, sx, an, ft_piv, None, m_skin, is_boot=False)

    build_zombie_armature_and_skin("ZombieRunner", sh_x=0.205, el_x=0.225, wr_x=0.225,
                                   hip_x=0.105, knee_x=0.112, ankle_x=0.112,
                                   jaw_pos=(0, 0.09, 1.65), head_pos=(0, 0.05, 1.55))
    export_glb("zombie_runner_v2.glb")


# ---------------------------------------------------------------------------
# 3. ZOMBIE SOLDIER V2 — UNDEAD BUNKER TROOPER (ARMORED / RIOT HUSK)
# ---------------------------------------------------------------------------
def build_soldier():
    clear_scene()
    m_skin = make_mat("SoldierSkin", (0.44, 0.48, 0.38, 1), roughness=0.65, tex_prefix="necrotic_flesh", contrast=1.35)
    m_camo = make_mat("SoldierCamo", (0.31, 0.35, 0.26, 1), roughness=0.88, tex_prefix="camo", normal_strength=1.2, contrast=1.40)
    m_vest = make_mat("FlakVest", (0.22, 0.24, 0.19, 1), roughness=0.80, tex_prefix="burlap", contrast=1.35)
    m_steel = make_mat("StahlSteel", (0.32, 0.35, 0.34, 1), metallic=0.78, roughness=0.40, tex_prefix="panzer_steel", contrast=1.40)
    m_boot = make_mat("CombatBoot", (0.14, 0.13, 0.12, 1), roughness=0.55, tex_prefix="leather")
    m_webbing = make_mat("Webbing", (0.32, 0.28, 0.20, 1), roughness=0.74, tex_prefix="leather", contrast=1.35)
    m_gore = make_mat("SoldierGore", (0.26, 0.02, 0.018, 1), roughness=0.22)
    m_bone = make_mat("SoldierBone", (0.68, 0.62, 0.48, 1), roughness=0.50)
    m_eye = neon_mat("SoldierEye", (1.0, 0.52, 0.08), strength=4.5, roughness=0.14)

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    spine = add_pivot("Spine", (0, 0, 1.07), parent=hips)
    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    head = add_pivot("Head", (0, 0.02, 1.57), parent=chest)
    jaw = add_pivot("Jaw", (0, 0.06, 1.67), parent=head)

    # Tactical pelvis, web belt, side canteen & holster
    loft_anatomical("SoldierPelvis", [
        {"pos": (0, 0, 0.88), "rx": 0.178, "ry_f": 0.122, "ry_b": 0.140},
        {"pos": (0, 0, 0.99), "rx": 0.198, "ry_f": 0.132, "ry_b": 0.146},
        {"pos": (0, 0, 1.07), "rx": 0.184, "ry_f": 0.125, "ry_b": 0.132},
    ], mat=m_camo, parent=hips, segs=20, subsurf=1)
    prim_mesh("TacBelt", "CYLINDER", (0, 0.005, 1.05), (0.398, 0.282, 0.058), mat=m_webbing, parent=hips, bevel=0.008, verts=24)
    prim_mesh("SideHolsterR", "CUBE", (0.208, 0.02, 0.93), (0.058, 0.115, 0.17), rot=(0.12, 0, -0.08), mat=m_boot, parent=hips, bevel=0.01)
    prim_mesh("CanteenL", "CYLINDER", (-0.185, -0.08, 0.97), (0.088, 0.068, 0.145), mat=m_vest, parent=hips, bevel=0.012, verts=14)

    # Camo uniform tunic + Heavy Ballistic Flak Vest, Collar Guard & Trauma Plate
    loft_anatomical("SoldierTunic", [
        {"pos": (0, 0, 1.04), "rx": 0.180, "ry_f": 0.122, "ry_b": 0.128},
        {"pos": (0, 0, 1.24), "rx": 0.202, "ry_f": 0.136, "ry_b": 0.142},
        {"pos": (0, 0.008, 1.44), "rx": 0.232, "ry_f": 0.144, "ry_b": 0.150},
        {"pos": (0, 0.010, 1.55), "rx": 0.150, "ry_f": 0.100, "ry_b": 0.110},
    ], mat=m_camo, parent=chest, segs=22, subsurf=1)

    loft_anatomical("BallisticVest", [
        {"pos": (0, 0.005, 1.13), "rx": 0.212, "ry_f": 0.152, "ry_b": 0.156},
        {"pos": (0, 0.008, 1.32), "rx": 0.228, "ry_f": 0.166, "ry_b": 0.166},
        {"pos": (0, 0.010, 1.49), "rx": 0.238, "ry_f": 0.156, "ry_b": 0.162},
        {"pos": (0, 0.008, 1.56), "rx": 0.182, "ry_f": 0.122, "ry_b": 0.132},
    ], mat=m_vest, parent=chest, segs=20, cap_start=False, cap_end=False, open_shell_thickness=0.014)

    # Steel front trauma plate + shrapnel crater + 3 angled mag pouches + frag grenades + backpack
    prim_mesh("TraumaPlate", "CUBE", (0, 0.172, 1.38), (0.27, 0.028, 0.23), rot=(-0.08, 0, 0), mat=m_steel, parent=chest, bevel=0.009)
    prim_mesh("ShrapnelScar", "SPHERE", (-0.068, 0.182, 1.40), (0.072, 0.024, 0.062), mat=m_gore, parent=chest, verts=12)
    for pi, px in enumerate((-0.118, 0.0, 0.118)):
        prim_mesh(f"MagPouch{pi}", "CUBE", (px, 0.178, 1.21), (0.084, 0.055, 0.128),
                  rot=(0.05, 0, -0.06), mat=m_webbing, parent=chest, bevel=0.008)
    for gi, gx in enumerate((-0.135, 0.135)):
        prim_mesh(f"FragGrenade{gi}", "SPHERE", (gx, 0.178, 1.46), (0.052, 0.052, 0.068), mat=m_steel, parent=chest, verts=12)
    prim_mesh("BackPack", "CUBE", (0, -0.20, 1.36), (0.29, 0.12, 0.30), mat=m_vest, parent=chest, bevel=0.022)

    for sx, nm in ((-1, "L"), (1, "R")):
        loft_anatomical(f"SoldierPauldron{nm}", [
            {"pos": (sx * 0.20, 0.0, 1.55), "rx": 0.058, "ry_f": 0.080, "ry_b": 0.080},
            {"pos": (sx * 0.28, 0.0, 1.49), "rx": 0.074, "ry_f": 0.102, "ry_b": 0.102},
            {"pos": (sx * 0.30, 0.0, 1.40), "rx": 0.062, "ry_f": 0.088, "ry_b": 0.088},
        ], mat=m_steel, parent=chest, segs=16, subsurf=1)

    # Voxel-sculpted undead face + LOW-SEATED Menacing Flared Steel Stahlhelm (rim shadows brow!)
    build_sculpted_undead_head("Soldier", head, jaw, (0, 0.02, 1.57), m_skin, m_eye, m_bone, m_gore, scale=1.0, gaunt=1.08)
    loft_anatomical("Stahlhelm", [
        {"pos": (0, -0.016, 1.682), "rx": 0.148, "ry_f": 0.146, "ry_b": 0.172, "harmonics": [(2, -0.05, 0.0)]},
        {"pos": (0, 0.006, 1.728), "rx": 0.132, "ry_f": 0.154, "ry_b": 0.158},
        {"pos": (0, 0.012, 1.790), "rx": 0.120, "ry_f": 0.138, "ry_b": 0.140},
        {"pos": (0, 0.010, 1.835), "rx": 0.080, "ry_f": 0.094, "ry_b": 0.094},
    ], mat=m_steel, parent=head, segs=26, cap_start=False, cap_end=True, open_shell_thickness=0.009)
    spline_tube("ChinStrap", [
        (-0.112, 0.02, 1.69), (-0.078, 0.08, 1.64), (0.0, 0.118, 1.608), (0.078, 0.08, 1.64), (0.112, 0.02, 1.69)
    ], radius=0.006, mat=m_boot, parent=head, segs=6)

    # Continuous Arms (left sleeve battle-ripped at elbow exposing undead forearm + blood, right full camo sleeve + tactical glove!)
    build_zombie_arms("Soldier", chest, m_skin, m_camo, m_camo, m_boot, m_gore, m_bone,
                      sh_x=0.252, el_x=0.272, wr_x=0.270, thin=1.0, bulk=1.16,
                      sleeve_len_l=0.88, sleeve_len_r=1.25, claw_len=0.014, bite_wound_l=True, m_glove=m_boot)

    # Continuous Bloused Camo Cargo Trousers + Strapped Steel Kneepads + Tall Combat Boots!
    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.125, 0.0, 0.94)
        kn = (sx * 0.130, 0.012, 0.52)
        an = (sx * 0.126, 0.0, 0.10)
        th_piv = add_pivot("Thigh" + nm, hp, parent=hips)
        sh_piv = add_pivot("Shin" + nm, kn, parent=th_piv)
        ft_piv = add_pivot("Foot" + nm, an, parent=sh_piv)

        loft_anatomical(f"SoldierFullLeg{nm}", [
            {"pos": (hp[0], 0, 0.97), "rx": 0.104, "ry_f": 0.104, "ry_b": 0.110},
            {"pos": (hp[0], 0.010, 0.72), "rx": 0.098, "ry_f": 0.100, "ry_b": 0.098, "harmonics": [(5, 0.04, 0.5)]},
            {"pos": kn, "rx": 0.080, "ry_f": 0.082, "ry_b": 0.082},
            {"pos": (kn[0], 0.0, 0.35), "rx": 0.082, "ry_f": 0.078, "ry_b": 0.086, "harmonics": [(6, 0.05, 1.0)]},
            {"pos": (an[0], 0.0, 0.21), "rx": 0.062, "ry_f": 0.062, "ry_b": 0.062},
        ], mat=m_camo, parent=th_piv, segs=18, subsurf=1)

        prim_mesh(f"CargoPocket{nm}", "CUBE", (sx * 0.215, 0.01, 0.73), (0.036, 0.115, 0.145), mat=m_camo, parent=th_piv, bevel=0.008)
        prim_mesh(f"KneePad{nm}", "CUBE", (kn[0], 0.082, 0.525), (0.112, 0.045, 0.125),
                  rot=(-0.08, 0, 0), mat=m_steel, parent=sh_piv, bevel=0.016)
        build_zombie_foot("Soldier", nm, sx, an, ft_piv, m_boot, m_skin, is_boot=True, tall_boot=True)

    build_zombie_armature_and_skin("ZombieSoldier", sh_x=0.252, el_x=0.272, wr_x=0.270,
                                   hip_x=0.125, knee_x=0.130, ankle_x=0.126)
    export_glb("zombie_soldier_v2.glb")


# ---------------------------------------------------------------------------
# 4. ZOMBIE BLOATER — PUTRID GAS-SWOLLEN ABOMINATION (OPENVDB VOXEL SCULPTED!)
# ---------------------------------------------------------------------------
def build_bloater():
    clear_scene()
    rnd = random.Random(77)
    m_skin = make_mat("BloatSkin", (0.40, 0.43, 0.27, 1), roughness=0.42, tex_prefix="bloater_flesh", normal_strength=1.45, contrast=1.45)
    m_pus = neon_mat("BilePustule", (0.64, 1.0, 0.16), strength=4.6, roughness=0.14)
    m_pus_dim = make_mat("BileSac", (0.54, 0.72, 0.20, 1), roughness=0.20, emission=(0.48, 0.88, 0.14), emission_strength=2.4, srgb_input=False)
    m_crater = make_mat("InflamedRim", (0.24, 0.07, 0.06, 1), roughness=0.35, tex_prefix="necrotic_flesh")
    m_vein = make_mat("ToxicVein", (0.15, 0.22, 0.10, 1), roughness=0.36)
    m_gore = make_mat("BloatViscera", (0.28, 0.03, 0.025, 1), roughness=0.16)
    m_bone = make_mat("BloatBone", (0.68, 0.64, 0.46, 1), roughness=0.50)
    m_pants = make_mat("BurstTrousers", (0.25, 0.23, 0.20, 1), roughness=0.90, tex_prefix="burlap", contrast=1.38)
    m_rags = make_mat("BloatRags", (0.22, 0.20, 0.16, 1), roughness=0.92, tex_prefix="fabric")
    m_eye = neon_mat("BloatEye", (0.65, 1.0, 0.18), strength=4.8, roughness=0.14)

    root = add_pivot("Root", (0, 0, 0))
    hips = add_pivot("Hips", (0, 0, 0.98), parent=root)
    spine = add_pivot("Spine", (0, 0, 1.07), parent=hips)
    chest = add_pivot("Chest", (0, 0, 1.25), parent=spine)
    head = add_pivot("Head", (0, 0.05, 1.56), parent=chest)
    jaw = add_pivot("Jaw", (0, 0.10, 1.65), parent=head)

    # Wide heavy pelvis seamlessly overlapping the overhanging gut!
    loft_anatomical("BloatPelvis", [
        {"pos": (0, 0, 0.84), "rx": 0.255, "ry_f": 0.195, "ry_b": 0.215},
        {"pos": (0, 0.02, 0.96), "rx": 0.295, "ry_f": 0.245, "ry_b": 0.235},
        {"pos": (0, 0.04, 1.06), "rx": 0.285, "ry_f": 0.255, "ry_b": 0.225},
    ], mat=m_pants, parent=hips, segs=22, subsurf=1)

    # Seamless OpenVDB Voxel-Sculpted Grotesque Swollen Torso + Deeply-Embedded Tumor Humps + Shoulder Fat!
    gut_core = loft_anatomical("BloatBaseTorso", [
        {"pos": (0, 0.04, 0.93), "rx": 0.275, "ry_f": 0.265, "ry_b": 0.215},
        {"pos": (0, 0.11, 1.10), "rx": 0.375, "ry_f": 0.385, "ry_b": 0.265},
        {"pos": (0, 0.09, 1.28), "rx": 0.365, "ry_f": 0.355, "ry_b": 0.285},
        {"pos": (0, 0.04, 1.46), "rx": 0.355, "ry_f": 0.265, "ry_b": 0.295},
        {"pos": (0, 0.03, 1.59), "rx": 0.215, "ry_f": 0.165, "ry_b": 0.185},
    ], segs=24, subsurf=0)
    # Embed humps & shoulder fat deeply into `gut_core` so they fuse into ONE organic tumorous back (no broccoli sphere!)
    hump_l = prim_mesh("TumorHumpL", "SPHERE", (-0.14, -0.05, 1.47), (0.40, 0.36, 0.30), verts=18)
    hump_r = prim_mesh("TumorHumpR", "SPHERE", (0.17, -0.03, 1.52), (0.38, 0.34, 0.32), verts=18)
    gut_lobe = prim_mesh("GutLobeR", "SPHERE", (0.13, 0.24, 1.08), (0.40, 0.38, 0.32), verts=18)
    delt_fat_l = prim_mesh("DeltFatL", "SPHERE", (-0.30, 0.01, 1.47), (0.24, 0.24, 0.24), verts=16)
    delt_fat_r = prim_mesh("DeltFatR", "SPHERE", (0.30, 0.01, 1.47), (0.24, 0.24, 0.24), verts=16)

    bloat_ops = [
        # Irregular diagonal ruptured gut chasm!
        ("carve", (-0.06, 0.39, 1.15), (0.16, 0.13, 0.16), 0.115),
        ("carve", (-0.14, 0.35, 1.21), (0.10, 0.10, 0.10), 0.075),
        # Deep sagging fat-roll creases!
        ("crease", (-0.26, 0.25, 0.98), (0.26, 0.25, 0.98), 0.038, 0.028),
        ("crease", (-0.25, 0.26, 1.35), (-0.03, 0.30, 1.32), 0.030, 0.022),
        ("crease", (0.25, 0.26, 1.35), (0.03, 0.30, 1.32), 0.030, 0.022),
        ("noise", 9.0, 0.016, 5),
    ]
    bloat_torso = voxel_fuse_and_sculpt(
        "BloatSculptTorso", [gut_core, hump_l, hump_r, gut_lobe, delt_fat_l, delt_fat_r],
        voxel_size=0.012, sculpt_ops=bloat_ops, smooth_iters=3,
        decimate_ratio=0.45, mat=m_skin, parent=chest, uv_scale=2.0
    )
    bpy.context.view_layer.update()
    bt_mw = bloat_torso.matrix_world.copy()
    bt_inv = bt_mw.inverted()

    # Glistening coiled intestines/viscera + jagged crooked broken ribs inside the ruptured gut chasm!
    prim_mesh("RuptureViscera", "SPHERE", (-0.07, 0.32, 1.16), (0.23, 0.10, 0.23), mat=m_gore, parent=spine, verts=16)
    spline_tube("CoiledGut", [
        (-0.12, 0.35, 1.20), (-0.03, 0.37, 1.16), (-0.10, 0.36, 1.11), (-0.04, 0.34, 1.07)
    ], radius=0.022, mat=m_crater, parent=spine, segs=10)
    for ri, (rz, tilt) in enumerate(((1.24, 0.22), (1.18, -0.15), (1.11, 0.30))):
        spline_tube(f"BloatRibL{ri}", [(-0.19, 0.30, rz), (-0.14, 0.38, rz + 0.015 * tilt), (-0.10, 0.39, rz - 0.01)],
                    radius=0.009, mat=m_bone, parent=spine, segs=8)
        spline_tube(f"BloatRibR{ri}", [(0.04, 0.32, rz - 0.01), (-0.01, 0.38, rz + 0.01), (-0.035, 0.39, rz)],
                    radius=0.009, mat=m_bone, parent=spine, segs=8)

    # Glowing Bioluminescent Bile Pustules raycast-snapped right onto the sculpted Bloater skin surface!
    blister_spots = [
        (0.16, 0.37, 1.15, 0.078, True), (0.24, 0.30, 1.24, 0.056, False), (0.11, 0.40, 1.05, 0.062, True),
        (0.30, 0.18, 1.34, 0.068, True), (-0.28, 0.16, 1.31, 0.058, True), (-0.16, -0.22, 1.50, 0.082, True),
        (-0.08, -0.25, 1.42, 0.058, False), (0.19, -0.18, 1.55, 0.078, True), (0.26, 0.04, 1.55, 0.062, True),
        (-0.23, 0.26, 1.06, 0.056, True), (0.10, -0.24, 1.28, 0.062, False), (0.06, 0.32, 1.40, 0.054, True),
    ]
    for bi, (bx, by, bz, br, bright) in enumerate(blister_spots):
        rad_dir = Vector((bx, by, 0.0)).normalized()
        ray_orig_w = Vector((0.0, 0.0, bz)) + rad_dir * 0.95
        ray_dir_w = -rad_dir
        ok, hit_l, norm_l, _ = bloat_torso.ray_cast(bt_inv @ ray_orig_w, (bt_inv.to_3x3() @ ray_dir_w).normalized())
        if ok:
            surf_w = bt_mw @ hit_l
            nw = (bt_mw.to_3x3() @ norm_l).normalized()
        else:
            surf_w = Vector((bx, by, bz))
            nw = rad_dir
        c_pos = surf_w - nw * (br * 0.30)
        b_pos = surf_w + nw * (br * 0.10)
        prim_mesh(f"BlisterCrater{bi}", "SPHERE", tuple(c_pos),
                  (br * 1.65, br * 1.55, br * 1.55), mat=m_crater, parent=chest, verts=12)
        prim_mesh(f"BileBlister{bi}", "SPHERE", tuple(b_pos),
                  (br * 1.32, br * 1.32, br * 1.24),
                  rot=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), 0),
                  mat=m_pus if bright else m_pus_dim, parent=chest, verts=14)

    for vi, pts in enumerate([
        [(0.16, 0.37, 1.15), (0.23, 0.32, 1.27), (0.21, 0.24, 1.41)],
        [(0.11, 0.40, 1.06), (0.04, 0.41, 0.99), (-0.04, 0.35, 0.95)],
        [(-0.16, -0.20, 1.50), (-0.27, -0.10, 1.42), (-0.32, 0.04, 1.36)],
    ]):
        spline_tube(f"BloatVein{vi}", pts, radius=0.010, mat=m_vein, parent=chest, segs=8)

    # Tattered open shoulder rag (`loft_open_arc`)
    loft_open_arc("BloatShoulderRag", [
        {"pos": (0.10, 0.02, 1.56), "rx": 0.24, "ry_f": 0.17, "ry_b": 0.19, "gap_deg": 150.0, "gap_offset_deg": -55.0},
        {"pos": (0.14, 0.03, 1.39), "rx": 0.28, "ry_f": 0.21, "ry_b": 0.22, "gap_deg": 165.0, "gap_offset_deg": -50.0, "harmonics": [(5, 0.10, 0.5)]},
    ], mat=m_rags, parent=chest, segs=18, thickness=0.006, tear_end_amp=0.055, tear_seed=61)

    # Bloated jowl head sunk deep into swollen neck + toxic drool strands
    build_sculpted_undead_head("Bloater", head, jaw, (0, 0.05, 1.56), m_skin, m_eye, m_bone, m_gore,
                               scale=1.10, gaunt=0.35, bloated=True)
    spline_tube("ToxicDrool", [(0.01, 0.18, 1.60), (0.02, 0.20, 1.51), (0.015, 0.19, 1.43)],
                radius=0.009, mat=m_pus, parent=jaw, segs=8)

    # Heavy Continuous Swollen Arms blended smoothly into shoulder fat!
    build_zombie_arms("Bloater", chest, m_skin, None, None, m_vein, m_gore, m_bone,
                      sh_x=0.32, el_x=0.36, wr_x=0.35, thin=1.0, bulk=1.48,
                      sleeve_len_l=0.0, sleeve_len_r=0.0, claw_len=0.020, bite_wound_l=False)

    # Continuous Swollen Pillar Legs + Burst Trousers (ZERO knee or ankle seams!)
    for sx, nm in ((-1, "L"), (1, "R")):
        hp = (sx * 0.165, 0.0, 0.94)
        kn = (sx * 0.175, 0.015, 0.52)
        an = (sx * 0.165, 0.0, 0.10)
        th_piv = add_pivot("Thigh" + nm, hp, parent=hips)
        sh_piv = add_pivot("Shin" + nm, kn, parent=th_piv)
        ft_piv = add_pivot("Foot" + nm, an, parent=sh_piv)

        loft_anatomical(f"BloatFullLegFlesh{nm}", [
            {"pos": (hp[0], 0, 0.96), "rx": 0.125, "ry_f": 0.128, "ry_b": 0.135},
            {"pos": (hp[0], 0.015, 0.72), "rx": 0.115, "ry_f": 0.120, "ry_b": 0.118},
            {"pos": kn, "rx": 0.095, "ry_f": 0.095, "ry_b": 0.098},
            {"pos": (kn[0], 0.0, 0.32), "rx": 0.088, "ry_f": 0.084, "ry_b": 0.096},
            {"pos": an, "rx": 0.068, "ry_f": 0.068, "ry_b": 0.072},
        ], mat=m_skin, parent=th_piv, segs=18, subsurf=1)

        loft_anatomical(f"BloatBurstPants{nm}", [
            {"pos": (hp[0], 0, 0.98), "rx": 0.138, "ry_f": 0.140, "ry_b": 0.148},
            {"pos": (hp[0], 0.015, 0.68), "rx": 0.126, "ry_f": 0.130, "ry_b": 0.128},
            {"pos": (kn[0], 0.010, 0.36), "rx": 0.106, "ry_f": 0.106, "ry_b": 0.108, "harmonics": [(6, 0.09, 0.5)]},
        ], mat=m_pants, parent=th_piv, segs=18, cap_start=True, cap_end=False,
           open_shell_thickness=0.007, tear_end_amp=0.052, tear_seed=70 + sx)

        build_zombie_foot("Bloater", nm, sx, an, ft_piv, None, m_skin, is_boot=False)

    build_zombie_armature_and_skin("ZombieBloater", sh_x=0.32, el_x=0.36, wr_x=0.35,
                                   hip_x=0.165, knee_x=0.175, ankle_x=0.165,
                                   jaw_pos=(0, 0.10, 1.65), head_pos=(0, 0.05, 1.56))
    export_glb("zombie_bloater.glb")


# ---------------------------------------------------------------------------
# 5. BLIGHT HOUND — VOXEL-SCULPTED FLAYED HELLHOUND (18 EXACT PIVOTS!)
# ---------------------------------------------------------------------------
def build_hound():
    clear_scene()
    m_fur = make_mat("HoundFur", (0.10, 0.095, 0.095, 1), roughness=0.84, tex_prefix="gorilla_fur", normal_strength=1.5, contrast=1.40)
    m_flayed = make_mat("HoundFlayed", (0.25, 0.055, 0.05, 1), roughness=0.36, tex_prefix="necrotic_flesh", contrast=1.45)
    m_bone = make_mat("HoundBone", (0.66, 0.58, 0.44, 1), roughness=0.50)
    m_claw = make_mat("HoundClaw", (0.05, 0.045, 0.045, 1), roughness=0.32)
    m_iron = make_mat("CollarIron", (0.18, 0.17, 0.16, 1), metallic=0.85, roughness=0.40, tex_prefix="panzer_steel")
    m_ember = neon_mat("HellEmber", (1.0, 0.34, 0.04), strength=6.5, roughness=0.18)
    m_eye = neon_mat("HoundEye", (1.0, 0.56, 0.06), strength=7.5, roughness=0.12)

    root = add_pivot("Root", (0, 0, 0))
    body = add_pivot("Body", (0, 0, 0.66), parent=root)

    # Voxel-Sculpted Predatory Lupine Torso (broad deep ribcage -> tucked waist -> muscular croup)
    torso_loft = loft_anatomical("HoundTorsoBase", [
        {"pos": (0, -0.58, 0.72), "rx": 0.095, "ry_f": 0.105, "ry_b": 0.095},
        {"pos": (0, -0.40, 0.70), "rx": 0.160, "ry_f": 0.170, "ry_b": 0.170},
        {"pos": (0, -0.14, 0.68), "rx": 0.122, "ry_f": 0.145, "ry_b": 0.125},
        {"pos": (0, 0.14, 0.67), "rx": 0.182, "ry_f": 0.205, "ry_b": 0.235},
        {"pos": (0, 0.36, 0.71), "rx": 0.165, "ry_f": 0.182, "ry_b": 0.205},
        {"pos": (0, 0.47, 0.77), "rx": 0.122, "ry_f": 0.132, "ry_b": 0.132},
    ], segs=22, subsurf=0)

    body_ops = [
        ("carve", (-0.165, 0.08, 0.66), (0.065, 0.23, 0.15), 0.062),
        ("carve", (0.165, 0.08, 0.66), (0.065, 0.23, 0.15), 0.062),
        ("crease", (0, -0.50, 0.86), (0, 0.38, 0.88), 0.026, 0.014),
    ]
    voxel_fuse_and_sculpt("HoundSculptBody", [torso_loft], voxel_size=0.009,
                          sculpt_ops=body_ops, smooth_iters=3, decimate_ratio=0.50,
                          mat=m_fur, parent=body, uv_scale=2.4)

    # Blazing Hellfire Core + Flayed Muscle Lining + Curved Anatomical Ribs + Magma Fissures!
    prim_mesh("HellHeart", "SPHERE", (0, 0.10, 0.66), (0.21, 0.32, 0.19), mat=m_ember, parent=body, verts=16)
    for sx, nm in ((-1, "L"), (1, "R")):
        for ri in range(6):
            ry = -0.10 + ri * 0.068
            spline_tube(f"HoundRib{nm}{ri}", [
                (sx * 0.06, ry, 0.81),
                (sx * 0.174, ry + 0.015, 0.68),
                (sx * 0.105, ry + 0.025, 0.52),
            ], radius=0.011, mat=m_bone, parent=body, segs=8)
        # Glowing magma crack creeping across shoulder!
        spline_tube(f"ShoulderMagma{nm}", [
            (sx * 0.15, 0.18, 0.78), (sx * 0.18, 0.30, 0.74), (sx * 0.16, 0.38, 0.66)
        ], radius=0.009, mat=m_ember, parent=body, segs=6)

    # Jagged dorsal spine spikes + charred shoulder hackle fur!
    for si in range(9):
        sy = -0.40 + si * 0.10
        sz = 0.84 + 0.045 * math.sin(si * 0.42)
        prim_mesh(f"BackSpike{si}", "CONE", (0, sy, sz + 0.028),
                  (0.026, 0.042, 0.075), rot=(-math.radians(40), 0, 0), mat=m_bone, parent=body, verts=6)

    # Muscular Neck + Hackle Ruff + Spiked Iron Lab Collar + Broken Chain!
    neck = add_pivot("Neck", (0, 0.40, 0.78), parent=body)
    loft_anatomical("HoundNeckMesh", [
        {"pos": (0, 0.34, 0.72), "rx": 0.145, "ry_f": 0.155, "ry_b": 0.165, "harmonics": [(5, 0.06, 0.0)]},
        {"pos": (0, 0.49, 0.82), "rx": 0.122, "ry_f": 0.132, "ry_b": 0.136, "harmonics": [(6, 0.05, 0.5)]},
        {"pos": (0, 0.62, 0.90), "rx": 0.104, "ry_f": 0.110, "ry_b": 0.115},
    ], mat=m_fur, parent=neck, segs=18, subsurf=1)

    bpy.ops.mesh.primitive_torus_add(major_radius=0.132, minor_radius=0.022, major_segments=20, minor_segments=8,
                                     location=(0, 0.48, 0.81), rotation=(math.radians(52), 0, 0))
    collar = bpy.context.active_object
    collar.name = "SpikedCollar"
    collar.data.materials.append(m_iron)
    auto_uv(collar, 3.0)
    collar.parent = neck
    collar.matrix_parent_inverse = neck.matrix_world.inverted()
    for ci in range(6):
        ang = ci * math.tau / 6.0
        cx = math.cos(ang) * 0.152
        cz = 0.81 + math.sin(ang) * 0.125
        cy = 0.48 - math.sin(ang) * 0.070
        prim_mesh(f"CollarSpike{ci}", "CONE", (cx, cy, cz), (0.022, 0.022, 0.052),
                  rot=(0, math.atan2(cx, max(0.01, cz - 0.81)), 0), mat=m_iron, parent=neck, verts=6)
    chain_strand("CollarChain", [(0, 0.49, 0.68), (0.02, 0.51, 0.56), (0.04, 0.50, 0.44)],
                 link_major=0.025, link_minor=0.0075, mat=m_iron, parent=neck)

    # Voxel-Sculpted Wolf Skull & Snarling Muzzle (`Head` at (0, 0.60, 0.90))
    head = add_pivot("Head", (0, 0.60, 0.90), parent=neck)
    skull_b = prim_mesh("WolfCranium", "SPHERE", (0, 0.65, 0.935), (0.225, 0.25, 0.20), verts=18)
    snout_b = loft_anatomical("WolfSnout", [
        {"pos": (0, 0.68, 0.92), "rx": 0.096, "ry_f": 0.078, "ry_b": 0.070},
        {"pos": (0, 0.82, 0.905), "rx": 0.072, "ry_f": 0.060, "ry_b": 0.052},
        {"pos": (0, 0.95, 0.895), "rx": 0.055, "ry_f": 0.046, "ry_b": 0.042},
    ], segs=16, subsurf=0)
    brow_b = prim_mesh("WolfBrow", "CUBE", (0, 0.72, 0.98), (0.175, 0.080, 0.045), bevel=0.016)

    head_ops = [
        ("carve", (-0.065, 0.735, 0.955), (0.034, 0.040, 0.030), 0.024),
        ("carve", (0.065, 0.735, 0.955), (0.034, 0.040, 0.030), 0.024),
        ("crease", (-0.028, 0.76, 0.945), (-0.038, 0.91, 0.91), 0.015, 0.009),
        ("crease", (0.028, 0.76, 0.945), (0.038, 0.91, 0.91), 0.015, 0.009),
    ]
    voxel_fuse_and_sculpt("HoundSculptHead", [skull_b, snout_b, brow_b], voxel_size=0.007,
                          sculpt_ops=head_ops, smooth_iters=2, decimate_ratio=0.50,
                          mat=m_fur, parent=head, uv_scale=2.8)

    prim_mesh("WolfNose", "SPHERE", (0, 0.962, 0.908), (0.052, 0.040, 0.036), mat=m_claw, parent=head, verts=12)
    prim_mesh("MawHellfire", "SPHERE", (0, 0.81, 0.868), (0.082, 0.17, 0.036), mat=m_ember, parent=head, verts=12)

    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"WolfEye{nm}", "SPHERE", (sx * 0.062, 0.742, 0.955), (0.030, 0.026, 0.024), mat=m_eye, parent=head, verts=12)
        loft_anatomical(f"WolfEar{nm}", [
            {"pos": (sx * 0.076, 0.62, 0.99), "rx": 0.032, "ry_f": 0.024, "ry_b": 0.038},
            {"pos": (sx * 0.104, 0.55, 1.08), "rx": 0.024, "ry_f": 0.018, "ry_b": 0.028},
            {"pos": (sx * 0.122, 0.49, 1.15), "rx": 0.008, "ry_f": 0.008, "ry_b": 0.010},
        ], mat=m_fur, parent=head, segs=10, subsurf=1)
        prim_mesh(f"SaberFangU{nm}", "CONE", (sx * 0.042, 0.92, 0.855), (0.019, 0.024, 0.056),
                  rot=(math.radians(172), 0, 0), mat=m_bone, parent=head, verts=8)
        for ti in range(4):
            ty = 0.77 + ti * 0.035
            prim_mesh(f"UTooth{nm}{ti}", "CONE", (sx * 0.046, ty, 0.868), (0.013, 0.016, 0.028),
                      rot=(math.pi, 0, 0), mat=m_bone, parent=head, verts=6)

    jaw = add_pivot("Jaw", (0, 0.68, 0.86), parent=head)
    loft_anatomical("WolfJawMesh", [
        {"pos": (0, 0.67, 0.855), "rx": 0.074, "ry_f": 0.034, "ry_b": 0.038},
        {"pos": (0, 0.80, 0.835), "rx": 0.056, "ry_f": 0.028, "ry_b": 0.032},
        {"pos": (0, 0.93, 0.825), "rx": 0.040, "ry_f": 0.024, "ry_b": 0.026},
    ], mat=m_flayed, parent=jaw, segs=14, subsurf=1)
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"SaberFangL{nm}", "CONE", (sx * 0.035, 0.91, 0.852), (0.016, 0.020, 0.045),
                  rot=(math.radians(-8), 0, 0), mat=m_bone, parent=jaw, verts=8)
        for ti in range(3):
            prim_mesh(f"LTooth{nm}{ti}", "CONE", (sx * 0.040, 0.78 + ti * 0.038, 0.850),
                      (0.011, 0.014, 0.024), mat=m_bone, parent=jaw, verts=6)

    # 4 Articulated Muscular Digitigrade Wolf Legs (18 exact pivots preserved!)
    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * 0.15, 0.30, 0.68)
        el = (sx * 0.16, 0.33, 0.36)
        wr = (sx * 0.15, 0.36, 0.10)
        f_up = add_pivot("FrontUpper" + nm, sh, parent=body)
        f_lo = add_pivot("FrontLower" + nm, el, parent=f_up)
        f_pw = add_pivot("FrontPaw" + nm, wr, parent=f_lo)

        loft_anatomical(f"FrontUpperMesh{nm}", [
            {"pos": (sh[0] - sx * 0.02, sh[1] - 0.02, sh[2] + 0.09), "rx": 0.072, "ry_f": 0.110, "ry_b": 0.122},
            {"pos": (sh[0] + sx * 0.01, sh[1], sh[2] - 0.06), "rx": 0.076, "ry_f": 0.102, "ry_b": 0.112},
            {"pos": ((sh[0] + el[0]) * 0.5, 0.31, 0.49), "rx": 0.062, "ry_f": 0.076, "ry_b": 0.086},
            {"pos": (el[0], el[1], el[2] - 0.02), "rx": 0.050, "ry_f": 0.054, "ry_b": 0.060},
        ], mat=m_fur, parent=f_up, segs=14, subsurf=1)

        loft_anatomical(f"FrontLowerMesh{nm}", [
            {"pos": (el[0], el[1], el[2] + 0.03), "rx": 0.048, "ry_f": 0.052, "ry_b": 0.056},
            {"pos": (wr[0], 0.35, 0.22), "rx": 0.040, "ry_f": 0.042, "ry_b": 0.045},
            {"pos": (wr[0], wr[1], wr[2] - 0.01), "rx": 0.036, "ry_f": 0.038, "ry_b": 0.038},
        ], mat=m_flayed, parent=f_lo, segs=12, subsurf=1)

        loft_anatomical(f"FrontPawMesh{nm}", [
            {"pos": (wr[0], wr[1], wr[2] + 0.02), "rx": 0.036, "ry_f": 0.038, "ry_b": 0.036},
            {"pos": (wr[0], 0.41, 0.038), "rx": 0.048, "ry_f": 0.054, "ry_b": 0.040},
            {"pos": (wr[0], 0.48, 0.022), "rx": 0.044, "ry_f": 0.040, "ry_b": 0.028},
        ], mat=m_fur, parent=f_pw, segs=12, subsurf=1)
        for ci in range(4):
            cx = wr[0] + (ci - 1.5) * 0.022
            prim_mesh(f"FClaw{nm}{ci}", "CONE", (cx, 0.515, 0.016), (0.016, 0.018, 0.046),
                      rot=(-math.radians(78), 0, 0), mat=m_claw, parent=f_pw, verts=6)

        hp = (sx * 0.16, -0.42, 0.66)
        kn = (sx * 0.17, -0.30, 0.42)
        hk = (sx * 0.17, -0.52, 0.20)
        h_up = add_pivot("HindUpper" + nm, hp, parent=body)
        h_lo = add_pivot("HindLower" + nm, kn, parent=h_up)
        h_pw = add_pivot("HindPaw" + nm, hk, parent=h_lo)

        loft_anatomical(f"HindUpperMesh{nm}", [
            {"pos": (hp[0] - sx * 0.02, hp[1] - 0.02, hp[2] + 0.09), "rx": 0.082, "ry_f": 0.132, "ry_b": 0.142},
            {"pos": (hp[0] + sx * 0.01, -0.38, 0.55), "rx": 0.086, "ry_f": 0.118, "ry_b": 0.128},
            {"pos": (kn[0], kn[1], kn[2] - 0.02), "rx": 0.054, "ry_f": 0.060, "ry_b": 0.065},
        ], mat=m_fur, parent=h_up, segs=14, subsurf=1)

        loft_anatomical(f"HindLowerMesh{nm}", [
            {"pos": (kn[0], kn[1], kn[2] + 0.03), "rx": 0.052, "ry_f": 0.055, "ry_b": 0.062},
            {"pos": (hk[0], -0.42, 0.30), "rx": 0.042, "ry_f": 0.044, "ry_b": 0.050},
            {"pos": (hk[0], hk[1], hk[2] - 0.01), "rx": 0.038, "ry_f": 0.038, "ry_b": 0.044},
        ], mat=m_flayed, parent=h_lo, segs=12, subsurf=1)

        loft_anatomical(f"HindPawMesh{nm}", [
            {"pos": (hk[0], hk[1], hk[2] + 0.02), "rx": 0.036, "ry_f": 0.036, "ry_b": 0.040},
            {"pos": (hk[0], -0.46, 0.042), "rx": 0.044, "ry_f": 0.048, "ry_b": 0.036},
            {"pos": (hk[0], -0.38, 0.022), "rx": 0.046, "ry_f": 0.046, "ry_b": 0.028},
        ], mat=m_fur, parent=h_pw, segs=12, subsurf=1)
        for ci in range(4):
            cx = hk[0] + (ci - 1.5) * 0.022
            prim_mesh(f"HClaw{nm}{ci}", "CONE", (cx, -0.345, 0.016), (0.016, 0.018, 0.046),
                      rot=(-math.radians(78), 0, 0), mat=m_claw, parent=h_pw, verts=6)

    tail = add_pivot("Tail", (0, -0.56, 0.76), parent=body)
    loft_anatomical("TailBaseMesh", [
        {"pos": (0, -0.55, 0.76), "rx": 0.048, "ry_f": 0.048, "ry_b": 0.048},
        {"pos": (0, -0.67, 0.74), "rx": 0.036, "ry_f": 0.036, "ry_b": 0.036},
        {"pos": (0, -0.78, 0.72), "rx": 0.026, "ry_f": 0.026, "ry_b": 0.026},
    ], mat=m_fur, parent=tail, segs=10, subsurf=1)

    tip = add_pivot("TailTip", (0, -0.78, 0.72), parent=tail)
    spline_tube("TailBoneWhip", [(0, -0.78, 0.72), (0, -0.92, 0.67), (0, -1.06, 0.60)],
                radius=0.016, mat=m_bone, parent=tip, ribbed=True, rib_amp=0.35, segs=8)
    prim_mesh("TailBarb", "CONE", (0, -1.10, 0.58), (0.032, 0.020, 0.082),
              rot=(math.radians(112), 0, 0), mat=m_bone, parent=tip, verts=6)

    merge_per_pivot()
    export_glb("enemy_hound.glb")


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    builders = {
        "walker": build_walker,
        "runner": build_runner,
        "soldier": build_soldier,
        "bloater": build_bloater,
        "hound": build_hound,
    }
    for k in (only or list(builders.keys())):
        builders[k]()
        print("FINISHED ZOMBIE MODEL:", k)
    print("ALL V7.1 ZOMBIE & HOUND MODELS GENERATED!")
