"""Generate brand-new v7.1 sculpted & hard-surface 3D models for all 5 Round Bosses:
  - Round 1: boss_gun_zombie.glb   (CORP. VEX — Armed Spec-Ops Remnant)
  - Round 2: boss_gorilla.glb      (SUBJECT GOLIATH — Mutated Silverback Titan)
  - Round 3: boss_necromancer.glb  (MORBUS-9 — Blight Spitter / Plague Alchemist)
  - Round 4: boss_juggernaut.glb   (PANZER-KRIEG — Dieselpunk Iron Juggernaut)
  - Round 5: boss_phantom.glb      (WRAITH-11 — The Volt Reaper)

Preserves 100% compatibility with ZombieEnemy pivots (`Root`, `Torso`, `Head`, `ArmL`,
`ArmR`, `LegL`, `LegR`), Corp. Vex muzzle/laser sight, and Panzer's Chest Power Core
weakpoint at (0, +0.34, 1.55).
"""
import math
import os
import sys
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt_kit_v7 import (  # noqa: E402
    R90,
    add_pivot,
    auto_uv,
    build_sculpted_undead_head,
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
# ROUND 1 BOSS: CORP. VEX — ARMED SPEC-OPS REMNANT (boss_gun_zombie.glb)
# ---------------------------------------------------------------------------
def build_boss_gun_zombie():
    clear_scene()
    m_skin = make_mat("VexSkin", (0.42, 0.46, 0.37, 1), roughness=0.62, tex_prefix="necrotic_flesh", contrast=1.38)
    m_coat = make_mat("VexDuster", (0.17, 0.19, 0.21, 1), roughness=0.84, tex_prefix="fabric", normal_strength=1.25, contrast=1.38)
    m_camo = make_mat("VexCamo", (0.28, 0.32, 0.25, 1), roughness=0.86, tex_prefix="camo", contrast=1.40)
    m_armor = make_mat("VexArmor", (0.28, 0.31, 0.31, 1), metallic=0.72, roughness=0.40, tex_prefix="panzer_steel", contrast=1.40)
    m_gun = make_mat("CarbineSteel", (0.22, 0.25, 0.28, 1), metallic=0.88, roughness=0.28, tex_prefix="gunmetal")
    m_poly = make_mat("CarbinePoly", (0.13, 0.13, 0.15, 1), roughness=0.60, tex_prefix="leather")
    m_leather = make_mat("VexLeather", (0.22, 0.17, 0.14, 1), roughness=0.56, tex_prefix="leather", contrast=1.35)
    m_bone = make_mat("VexBone", (0.68, 0.62, 0.48, 1), roughness=0.50)
    m_gore = make_mat("VexGore", (0.28, 0.02, 0.02, 1), roughness=0.22)
    m_red = neon_mat("TacticalRed", (1.0, 0.10, 0.06), strength=7.0, roughness=0.12)
    m_brass = make_mat("ShellBrass", (0.62, 0.48, 0.20, 1), metallic=0.88, roughness=0.32)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.02), parent=root)

    # Broad Athletic Spec-Ops Combat Torso + Pelvis
    loft_anatomical("VexCoreBody", [
        {"pos": (0, 0, 0.88), "rx": 0.205, "ry_f": 0.138, "ry_b": 0.155},
        {"pos": (0, 0, 1.04), "rx": 0.215, "ry_f": 0.145, "ry_b": 0.160},
        {"pos": (0, 0, 1.24), "rx": 0.228, "ry_f": 0.155, "ry_b": 0.165},
        {"pos": (0, 0.01, 1.46), "rx": 0.272, "ry_f": 0.172, "ry_b": 0.180},
        {"pos": (0, 0.01, 1.62), "rx": 0.180, "ry_f": 0.118, "ry_b": 0.130},
    ], mat=m_camo, parent=torso, segs=22, subsurf=1)

    # OPEN-FRONT Spec-Ops Tactical Trenchcoat Skirt (`loft_open_arc`) revealing armored legs & holsters!
    loft_open_arc("VexDusterSkirt", [
        {"pos": (0, -0.01, 1.10), "rx": 0.225, "ry_f": 0.152, "ry_b": 0.172, "gap_deg": 62.0},
        {"pos": (0, -0.02, 0.88), "rx": 0.268, "ry_f": 0.168, "ry_b": 0.212, "gap_deg": 74.0, "harmonics": [(6, 0.05, 0.4)]},
        {"pos": (0, -0.04, 0.64), "rx": 0.312, "ry_f": 0.182, "ry_b": 0.255, "gap_deg": 86.0, "harmonics": [(7, 0.07, 1.1)]},
        {"pos": (0, -0.05, 0.42), "rx": 0.348, "ry_f": 0.195, "ry_b": 0.288, "gap_deg": 96.0, "harmonics": [(8, 0.09, 1.9)]},
    ], mat=m_coat, parent=torso, segs=28, thickness=0.011, tear_end_amp=0.080, tear_lapel_amp=0.03, tear_seed=17)

    # High-Collar Coat Mantle + Heavy Ceramic Plate Carrier + Duty Belt
    loft_open_arc("VexUpperCoat", [
        {"pos": (0, 0.005, 1.12), "rx": 0.232, "ry_f": 0.168, "ry_b": 0.178, "gap_deg": 54.0},
        {"pos": (0, 0.008, 1.36), "rx": 0.262, "ry_f": 0.185, "ry_b": 0.192, "gap_deg": 48.0},
        {"pos": (0, 0.010, 1.54), "rx": 0.285, "ry_f": 0.182, "ry_b": 0.190, "gap_deg": 58.0},
        {"pos": (0, -0.005, 1.66), "rx": 0.205, "ry_f": 0.135, "ry_b": 0.158, "gap_deg": 86.0},
    ], mat=m_coat, parent=torso, segs=24, thickness=0.012)

    prim_mesh("SpecOpsBelt", "CYLINDER", (0, 0.005, 1.09), (0.465, 0.345, 0.065), mat=m_leather, parent=torso, bevel=0.008, verts=24)
    prim_mesh("BeltBuckleVex", "CUBE", (0, 0.178, 1.09), (0.075, 0.025, 0.068), mat=m_armor, parent=torso, bevel=0.005)

    # Angled Chamfered Ballistic Steel Trauma Plate + Mag Pouches + Bandolier Shells
    prim_mesh("FrontStrikePlate", "CUBE", (0, 0.198, 1.41), (0.33, 0.036, 0.27), rot=(-0.08, 0, 0), mat=m_armor, parent=torso, bevel=0.010)
    prim_mesh("ChestBeacon", "CUBE", (0.105, 0.220, 1.49), (0.048, 0.018, 0.020), mat=m_red, parent=torso, bevel=0.003)
    for pi, px in enumerate((-0.132, 0.0, 0.132)):
        prim_mesh(f"RifleMagPouch{pi}", "CUBE", (px, 0.202, 1.22), (0.088, 0.062, 0.140),
                  rot=(0.06, 0, -0.10), mat=m_leather, parent=torso, bevel=0.008)
        prim_mesh(f"SpareMagTop{pi}", "CUBE", (px + 0.006, 0.202, 1.30), (0.060, 0.032, 0.048),
                  rot=(0.06, 0, -0.10), mat=m_gun, parent=torso, bevel=0.004)
    for si in range(5):
        t = si / 4.0
        prim_mesh(f"BandolierShell{si}", "CYLINDER", (-0.15 + t * 0.13, 0.218, 1.52 - t * 0.11),
                  (0.024, 0.024, 0.058), rot=(0, 0.65, 0), mat=m_brass, parent=torso, verts=10)

    # Tactical Backpack + Radio Whip Antenna
    prim_mesh("SpecOpsPack", "CUBE", (0, -0.235, 1.41), (0.35, 0.15, 0.36), mat=m_leather, parent=torso, bevel=0.024)
    seg_limb("RadioWhip", (-0.13, -0.26, 1.58), (-0.16, -0.30, 2.06), 0.009, 0.003, mat=m_gun, parent=torso, verts=8)

    # Heavy Segmented Spec-Ops Shoulder Pauldrons
    for sx, nm in ((-1, "L"), (1, "R")):
        loft_anatomical(f"VexPauldron{nm}", [
            {"pos": (sx * 0.24, 0.0, 1.62), "rx": 0.072, "ry_f": 0.105, "ry_b": 0.105},
            {"pos": (sx * 0.34, 0.0, 1.54), "rx": 0.092, "ry_f": 0.128, "ry_b": 0.128},
            {"pos": (sx * 0.36, 0.0, 1.43), "rx": 0.080, "ry_f": 0.112, "ry_b": 0.112},
        ], mat=m_armor, parent=torso, segs=16, subsurf=1)

    # Head: Snug Low-Seated FAST Ballistic Helmet + Mandible Cheek-Guards + Panoramic Crimson NVG Visor!
    head = add_pivot("Head", (0, 0.03, 1.64), parent=torso)
    jaw_dummy = add_pivot("VexJawFixed", (0, 0.07, 1.73), parent=head)
    build_sculpted_undead_head("Vex", head, jaw_dummy, (0, 0.03, 1.64), m_skin, m_red, m_bone, m_gore, scale=1.05, gaunt=1.15)

    loft_anatomical("OpsCoreHelmet", [
        {"pos": (0, -0.018, 1.762), "rx": 0.146, "ry_f": 0.145, "ry_b": 0.168},
        {"pos": (0, 0.010, 1.820), "rx": 0.140, "ry_f": 0.156, "ry_b": 0.160},
        {"pos": (0, 0.015, 1.885), "rx": 0.122, "ry_f": 0.140, "ry_b": 0.142},
        {"pos": (0, 0.010, 1.930), "rx": 0.078, "ry_f": 0.092, "ry_b": 0.092},
    ], mat=m_armor, parent=head, segs=24, cap_start=False, cap_end=True, open_shell_thickness=0.011)

    prim_mesh("VisorHousing", "CUBE", (0, 0.152, 1.815), (0.240, 0.074, 0.068), rot=(0.06, 0, 0), mat=m_gun, parent=head, bevel=0.012)
    prim_mesh("VisorCrimsonLens", "CUBE", (0, 0.184, 1.812), (0.210, 0.024, 0.040), rot=(0.06, 0, 0), mat=m_red, parent=head, bevel=0.005)
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"NvgPod{nm}", "CYLINDER", (sx * 0.072, 0.196, 1.814), (0.038, 0.038, 0.052),
                  rot=(R90, 0, 0), mat=m_gun, parent=head, verts=14)
        prim_mesh(f"NvgEye{nm}", "CYLINDER", (sx * 0.072, 0.222, 1.814), (0.028, 0.028, 0.008),
                  rot=(R90, 0, 0), mat=m_red, parent=head, verts=14)
        prim_mesh(f"EarComms{nm}", "CYLINDER", (sx * 0.130, 0.02, 1.775), (0.074, 0.088, 0.038),
                  rot=(0, R90, 0), mat=m_poly, parent=head, verts=14)
        # Ballistic mandible cheek armor framing snarling undead jaws!
        prim_mesh(f"MandibleGuard{nm}", "CUBE", (sx * 0.095, 0.088, 1.715), (0.032, 0.105, 0.078),
                  rot=(0.18, sx * -0.22, sx * -0.25), mat=m_armor, parent=head, bevel=0.008)

    # RIGHT ARM + HIGH-DETAIL SUPPRESSED BATTLE CARBINE (Aimed level +Y at Z ~ 1.51!)
    arm_r = add_pivot("ArmR", (0.31, 0.02, 1.53), parent=torso)
    loft_anatomical("VexArmR", [
        {"pos": (0.31, 0.02, 1.53), "rx": 0.084, "ry_f": 0.084, "ry_b": 0.084},
        {"pos": (0.30, 0.18, 1.38), "rx": 0.074, "ry_f": 0.076, "ry_b": 0.076},
        {"pos": (0.23, 0.36, 1.40), "rx": 0.064, "ry_f": 0.066, "ry_b": 0.066},
        {"pos": (0.16, 0.46, 1.43), "rx": 0.052, "ry_f": 0.052, "ry_b": 0.052},
    ], mat=m_coat, parent=arm_r, segs=16, subsurf=1)
    prim_mesh("GloveR", "SPHERE", (0.15, 0.48, 1.44), (0.092, 0.102, 0.084), mat=m_leather, parent=arm_r, verts=14)

    gx, gz = 0.14, 1.51
    prim_mesh("RifleStock", "CUBE", (gx, 0.25, gz - 0.01), (0.055, 0.25, 0.120), mat=m_poly, parent=arm_r, bevel=0.008)
    prim_mesh("RifleReceiver", "CUBE", (gx, 0.50, gz), (0.068, 0.31, 0.120), mat=m_gun, parent=arm_r, bevel=0.008)
    prim_mesh("RifleHandguard", "CUBE", (gx, 0.78, gz + 0.005), (0.060, 0.27, 0.086), mat=m_gun, parent=arm_r, bevel=0.008)
    prim_mesh("RifleBarrel", "CYLINDER", (gx, 0.97, gz + 0.008), (0.030, 0.030, 0.22), rot=(R90, 0, 0), mat=m_gun, parent=arm_r, verts=14)
    prim_mesh("Suppressor", "CYLINDER", (gx, 1.14, gz + 0.008), (0.050, 0.050, 0.24), rot=(R90, 0, 0), mat=m_poly, parent=arm_r, bevel=0.005, verts=16)
    prim_mesh("PistolGrip", "CUBE", (gx, 0.45, gz - 0.098), (0.042, 0.058, 0.120), rot=(-0.26, 0, 0), mat=m_poly, parent=arm_r, bevel=0.006)
    loft_anatomical("CurvedMag", [
        {"pos": (gx, 0.56, gz - 0.05), "rx": 0.019, "ry_f": 0.040, "ry_b": 0.040},
        {"pos": (gx, 0.58, gz - 0.16), "rx": 0.019, "ry_f": 0.040, "ry_b": 0.040},
        {"pos": (gx, 0.63, gz - 0.26), "rx": 0.018, "ry_f": 0.038, "ry_b": 0.038},
    ], mat=m_poly, parent=arm_r, segs=10, subsurf=0)
    prim_mesh("LpvoScope", "CYLINDER", (gx, 0.52, gz + 0.095), (0.048, 0.048, 0.25), rot=(R90, 0, 0), mat=m_gun, parent=arm_r, verts=16)
    prim_mesh("ScopeLens", "CYLINDER", (gx, 0.648, gz + 0.095), (0.038, 0.038, 0.006), rot=(R90, 0, 0), mat=m_red, parent=arm_r, verts=14)
    prim_mesh("PeqLaserBox", "CUBE", (gx + 0.040, 0.83, gz + 0.026), (0.038, 0.100, 0.036), mat=m_poly, parent=arm_r, bevel=0.004)
    prim_mesh("PeqLaserDot", "SPHERE", (gx + 0.040, 0.884, gz + 0.026), (0.020, 0.020, 0.020), mat=m_red, parent=arm_r, verts=10)
    prim_mesh("ForeGrip", "CUBE", (gx, 0.77, gz - 0.075), (0.036, 0.044, 0.100), rot=(0.15, 0, 0), mat=m_poly, parent=arm_r, bevel=0.005)

    # LEFT SUPPORT ARM
    arm_l = add_pivot("ArmL", (-0.31, 0.02, 1.53), parent=torso)
    loft_anatomical("VexArmL", [
        {"pos": (-0.31, 0.02, 1.53), "rx": 0.084, "ry_f": 0.084, "ry_b": 0.084},
        {"pos": (-0.23, 0.28, 1.38), "rx": 0.074, "ry_f": 0.075, "ry_b": 0.075},
        {"pos": (-0.04, 0.54, 1.40), "rx": 0.062, "ry_f": 0.064, "ry_b": 0.064},
        {"pos": (0.11, 0.74, 1.43), "rx": 0.050, "ry_f": 0.050, "ry_b": 0.050},
    ], mat=m_coat, parent=arm_l, segs=16, subsurf=1)
    prim_mesh("GloveL", "SPHERE", (0.13, 0.76, 1.44), (0.088, 0.098, 0.080), mat=m_leather, parent=arm_l, verts=14)

    # LEGS: Heavy Muscular Spec-Ops Trousers + Thigh Holsters + Knee Plates + Heavy Combat Boots (+28% thicker!)
    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.155, 0, 0.98), parent=root)
        loft_anatomical(f"VexLeg{nm}", [
            {"pos": (sx * 0.155, 0, 0.98), "rx": 0.125, "ry_f": 0.128, "ry_b": 0.135},
            {"pos": (sx * 0.158, 0.012, 0.72), "rx": 0.114, "ry_f": 0.118, "ry_b": 0.116, "harmonics": [(5, 0.04, 0.4)]},
            {"pos": (sx * 0.158, 0.012, 0.52), "rx": 0.095, "ry_f": 0.098, "ry_b": 0.096},
            {"pos": (sx * 0.155, 0.0, 0.28), "rx": 0.092, "ry_f": 0.090, "ry_b": 0.098, "harmonics": [(6, 0.04, 1.1)]},
            {"pos": (sx * 0.155, 0.0, 0.12), "rx": 0.076, "ry_f": 0.076, "ry_b": 0.078},
        ], mat=m_camo, parent=leg, segs=18, subsurf=1)
        prim_mesh(f"VexKneePlate{nm}", "CUBE", (sx * 0.158, 0.102, 0.53), (0.135, 0.052, 0.150),
                  rot=(-0.08, 0, 0), mat=m_armor, parent=leg, bevel=0.018)
        prim_mesh(f"ThighRig{nm}", "CUBE", (sx * 0.272, 0.01, 0.76), (0.055, 0.140, 0.175), mat=m_leather, parent=leg, bevel=0.012)
        loft_anatomical(f"VexBoot{nm}", [
            {"pos": (sx * 0.155, -0.06, 0.055), "rx": 0.074, "ry_f": 0.076, "ry_b": 0.068},
            {"pos": (sx * 0.155, 0.06, 0.052), "rx": 0.072, "ry_f": 0.066, "ry_b": 0.058},
            {"pos": (sx * 0.155, 0.198, 0.044), "rx": 0.066, "ry_f": 0.050, "ry_b": 0.042},
        ], mat=m_leather, parent=leg, segs=16, subsurf=1)
        prim_mesh(f"VexSole{nm}", "CUBE", (sx * 0.155, 0.072, 0.015), (0.142, 0.295, 0.030), mat=m_poly, parent=leg, bevel=0.007)

    merge_per_pivot()
    export_glb("boss_gun_zombie.glb")


# ---------------------------------------------------------------------------
# ROUND 2 BOSS: SUBJECT GOLIATH — MUTATED SILVERBACK TITAN (boss_gorilla.glb)
# ---------------------------------------------------------------------------
def build_boss_gorilla():
    clear_scene()
    m_fur = make_mat("GoliathFur", (0.16, 0.155, 0.165, 1), roughness=0.84, tex_prefix="gorilla_fur", normal_strength=1.65, contrast=1.42)
    m_silver = make_mat("SilverbackSaddle", (0.56, 0.58, 0.61, 1), roughness=0.76, tex_prefix="gorilla_fur", normal_strength=1.55, contrast=1.38)
    # Dark scarred charcoal-slate gorilla hide (NO orange!)
    m_chest = make_mat("ApeHide", (0.23, 0.215, 0.225, 1), roughness=0.48, tex_prefix="leather", normal_strength=1.40, contrast=1.45)
    m_iron = make_mat("LabIron", (0.28, 0.27, 0.26, 1), metallic=0.86, roughness=0.38, tex_prefix="panzer_steel", contrast=1.40)
    m_bone = make_mat("ApeIvory", (0.76, 0.70, 0.54, 1), roughness=0.40)
    m_gore = make_mat("ApeMaw", (0.30, 0.035, 0.035, 1), roughness=0.22)
    m_rage = neon_mat("MagmaRage", (1.0, 0.34, 0.05), strength=7.0, roughness=0.16)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.08), parent=root)

    # 1. Seamless OpenVDB Voxel-Sculpted Silverback Barrel Ribcage, Pelvis, Latissimus Wings & Trapezius Mountain!
    core_loft = loft_anatomical("GorillaCoreBase", [
        {"pos": (0, -0.08, 0.90), "rx": 0.36, "ry_f": 0.25, "ry_b": 0.28},
        {"pos": (0, -0.02, 1.14), "rx": 0.40, "ry_f": 0.30, "ry_b": 0.30},
        {"pos": (0, 0.06, 1.38), "rx": 0.53, "ry_f": 0.38, "ry_b": 0.38},
        {"pos": (0, 0.11, 1.62), "rx": 0.59, "ry_f": 0.40, "ry_b": 0.42},
        {"pos": (0, 0.14, 1.82), "rx": 0.46, "ry_f": 0.32, "ry_b": 0.38},
    ], segs=26, subsurf=0)
    trap_mtn = prim_mesh("TrapeziusMtn", "SPHERE", (0, -0.02, 1.86), (0.82, 0.62, 0.48), verts=20)
    lat_l = prim_mesh("LatWingL", "SPHERE", (-0.45, 0.03, 1.52), (0.46, 0.50, 0.58), verts=18)
    lat_r = prim_mesh("LatWingR", "SPHERE", (0.45, 0.03, 1.52), (0.46, 0.50, 0.58), verts=18)

    torso_ops = [
        ("crease", (0, -0.36, 1.12), (0, -0.30, 1.86), 0.058, 0.034),
        ("crease", (-0.50, 0.18, 1.32), (-0.34, 0.30, 1.22), 0.038, 0.022),
        ("crease", (0.50, 0.18, 1.32), (0.34, 0.30, 1.22), 0.038, 0.022),
        ("noise", 8.0, 0.014, 13),
    ]
    voxel_fuse_and_sculpt("GorillaSculptTorso", [core_loft, trap_mtn, lat_l, lat_r],
                          voxel_size=0.015, sculpt_ops=torso_ops, smooth_iters=3,
                          decimate_ratio=0.45, mat=m_fur, parent=torso, uv_scale=1.8)

    # 2. Frosty Silverback Fur Saddle Mantle across upper back, lats & shoulders!
    loft_open_arc("SilverSaddle", [
        {"pos": (0, -0.06, 1.18), "rx": 0.41, "ry_f": 0.24, "ry_b": 0.31, "gap_deg": 175.0},
        {"pos": (0, 0.02, 1.44), "rx": 0.55, "ry_f": 0.32, "ry_b": 0.39, "gap_deg": 160.0, "harmonics": [(6, 0.04, 0.0)]},
        {"pos": (0, 0.08, 1.72), "rx": 0.58, "ry_f": 0.34, "ry_b": 0.43, "gap_deg": 145.0, "harmonics": [(7, 0.05, 0.8)]},
        {"pos": (0, 0.06, 1.94), "rx": 0.38, "ry_f": 0.26, "ry_b": 0.34, "gap_deg": 135.0},
    ], mat=m_silver, parent=torso, segs=24, thickness=0.018, tear_end_amp=0.045, tear_seed=21, uv_scale=1.8)

    # 3. Seamlessly Embedded Muscular Gorilla Pectoral & Abdominal Plastron (contoured flush into barrel chest!)
    plastron_base = loft_anatomical("PlastronBase", [
        {"pos": (0, 0.18, 1.04), "rx": 0.26, "ry_f": 0.14, "ry_b": 0.08},
        {"pos": (0, 0.27, 1.24), "rx": 0.34, "ry_f": 0.16, "ry_b": 0.08},
        {"pos": (0, 0.33, 1.46), "rx": 0.44, "ry_f": 0.17, "ry_b": 0.10},
        {"pos": (0, 0.32, 1.66), "rx": 0.42, "ry_f": 0.15, "ry_b": 0.10},
    ], segs=22, subsurf=0)
    pec_l = prim_mesh("PecL", "SPHERE", (-0.20, 0.38, 1.56), (0.42, 0.22, 0.28), rot=(0, 0.15, -0.08), verts=18)
    pec_r = prim_mesh("PecR", "SPHERE", (0.20, 0.38, 1.56), (0.42, 0.22, 0.28), rot=(0, -0.15, 0.08), verts=18)
    chest_ops = [
        ("crease", (0, 0.49, 1.08), (0, 0.50, 1.70), 0.032, 0.032),  # deep sternal linea alba
        ("crease", (-0.38, 0.38, 1.43), (0.0, 0.48, 1.44), 0.030, 0.026),  # lower pectoral crease L
        ("crease", (0.38, 0.38, 1.43), (0.0, 0.48, 1.44), 0.030, 0.026),   # lower pectoral crease R
        ("crease", (-0.24, 0.41, 1.28), (0.24, 0.41, 1.28), 0.024, 0.018),
        ("crease", (-0.22, 0.38, 1.15), (0.22, 0.38, 1.15), 0.024, 0.016),
    ]
    voxel_fuse_and_sculpt("GorillaChestHide", [plastron_base, pec_l, pec_r],
                          voxel_size=0.012, sculpt_ops=chest_ops, smooth_iters=3,
                          decimate_ratio=0.48, mat=m_chest, parent=torso, uv_scale=2.2)

    # Glowing Magma Surgical Rage Fissures across scarred pectorals & shoulders!
    spline_tube("ChestRageFissureL", [(-0.28, 0.44, 1.63), (-0.13, 0.49, 1.54), (-0.02, 0.48, 1.44)],
                radius=0.014, mat=m_rage, parent=torso, segs=8)
    spline_tube("ChestRageFissureR", [(0.26, 0.44, 1.61), (0.11, 0.49, 1.52), (0.03, 0.45, 1.35)],
                radius=0.013, mat=m_rage, parent=torso, segs=8)

    # Compact Heavy Lab Containment Neck-Collar (snug around neck — NO giant horn protrusions!) + Iron Chains + Spine Clamps!
    bpy.ops.mesh.primitive_torus_add(major_radius=0.225, minor_radius=0.036, major_segments=24, minor_segments=10,
                                     location=(0, 0.25, 1.76), rotation=(math.radians(34), 0, 0))
    collar = bpy.context.active_object
    collar.name = "TitanCollar"
    collar.data.materials.append(m_iron)
    auto_uv(collar, 2.5)
    collar.parent = torso
    collar.matrix_parent_inverse = torso.matrix_world.inverted()

    chain_strand("BrokenChainL", [(-0.23, 0.26, 1.72), (-0.36, 0.34, 1.54), (-0.42, 0.36, 1.32), (-0.41, 0.35, 1.12)],
                 link_major=0.040, link_minor=0.012, mat=m_iron, parent=torso)
    chain_strand("BrokenChainR", [(0.23, 0.26, 1.72), (0.35, 0.34, 1.54), (0.39, 0.36, 1.34)],
                 link_major=0.040, link_minor=0.012, mat=m_iron, parent=torso)

    for si in range(5):
        sz = 1.78 - si * 0.14
        sy = -0.38 - 0.04 * math.sin(si * 0.7)
        prim_mesh(f"NeuralSpineClamp{si}", "CUBE", (0, sy, sz), (0.16 - si * 0.012, 0.095, 0.080),
                  rot=(-0.22, 0, 0), mat=m_iron, parent=torso, bevel=0.012)
        prim_mesh(f"SpineNodeGlow{si}", "SPHERE", (0, sy - 0.045, sz), (0.038, 0.026, 0.038),
                  mat=m_rage, parent=torso, verts=10)

    # 4. Larger, Low-Seated Ferocious Roaring Silverback Skull (`Head` at (0, 0.35, 1.77), +20% scale!)
    head = add_pivot("Head", (0, 0.35, 1.77), parent=torso)
    hx, hy, hz = 0.0, 0.35, 1.77
    hs = 1.20
    ape_dome = prim_mesh("ApeCranium", "SPHERE", (hx, hy + 0.02 * hs, hz + 0.12 * hs), (0.35 * hs, 0.39 * hs, 0.34 * hs), verts=20)
    sag_crest = prim_mesh("SagittalCrest", "SPHERE", (hx, hy - 0.04 * hs, hz + 0.24 * hs), (0.19 * hs, 0.33 * hs, 0.22 * hs), verts=16)
    ape_brow = prim_mesh("SupraOrbitalBrow", "CUBE", (hx, hy + 0.20 * hs, hz + 0.15 * hs), (0.31 * hs, 0.13 * hs, 0.080 * hs), bevel=0.030 * hs)
    ape_muzzle = prim_mesh("ApeMaxilla", "SPHERE", (hx, hy + 0.22 * hs, hz + 0.02 * hs), (0.28 * hs, 0.25 * hs, 0.21 * hs), verts=18)
    ape_jaw = loft_anatomical("ApeRoarJaw", [
        {"pos": (hx, hy + 0.07 * hs, hz - 0.05 * hs), "rx": 0.15 * hs, "ry_f": 0.09 * hs, "ry_b": 0.09 * hs},
        {"pos": (hx, hy + 0.20 * hs, hz - 0.14 * hs), "rx": 0.12 * hs, "ry_f": 0.085 * hs, "ry_b": 0.075 * hs},
        {"pos": (hx, hy + 0.29 * hs, hz - 0.16 * hs), "rx": 0.10 * hs, "ry_f": 0.070 * hs, "ry_b": 0.065 * hs},
    ], segs=16, subsurf=0)

    head_ops = [
        ("carve", (hx, hy + 0.28 * hs, hz - 0.05 * hs), (0.105 * hs, 0.115 * hs, 0.088 * hs), 0.115 * hs),
        ("carve", (hx - 0.080 * hs, hy + 0.21 * hs, hz + 0.115 * hs), (0.044 * hs, 0.050 * hs, 0.036 * hs), 0.038 * hs),
        ("carve", (hx + 0.080 * hs, hy + 0.21 * hs, hz + 0.115 * hs), (0.044 * hs, 0.050 * hs, 0.036 * hs), 0.038 * hs),
        ("carve", (hx - 0.034 * hs, hy + 0.31 * hs, hz + 0.055 * hs), (0.024 * hs, 0.026 * hs, 0.024 * hs), 0.024 * hs),
        ("carve", (hx + 0.034 * hs, hy + 0.31 * hs, hz + 0.055 * hs), (0.024 * hs, 0.026 * hs, 0.024 * hs), 0.024 * hs),
        ("crease", (hx - 0.12 * hs, hy + 0.25 * hs, hz + 0.16 * hs), (hx + 0.12 * hs, hy + 0.25 * hs, hz + 0.16 * hs), 0.022 * hs, 0.016 * hs),
        ("crease", (hx - 0.05 * hs, hy + 0.28 * hs, hz + 0.06 * hs), (hx - 0.12 * hs, hy + 0.20 * hs, hz - 0.04 * hs), 0.022 * hs, 0.016 * hs),
        ("crease", (hx + 0.05 * hs, hy + 0.28 * hs, hz + 0.06 * hs), (hx + 0.12 * hs, hy + 0.20 * hs, hz - 0.04 * hs), 0.022 * hs, 0.016 * hs),
    ]
    voxel_fuse_and_sculpt("GorillaSculptHead", [ape_dome, sag_crest, ape_brow, ape_muzzle, ape_jaw],
                          voxel_size=0.010, sculpt_ops=head_ops, smooth_iters=3,
                          decimate_ratio=0.48, mat=m_chest, parent=head, uv_scale=2.4)

    # Obsidian fur hood wrapping the back, cheeks, and sagittal crest of the gorilla skull!
    loft_open_arc("ApeCrownFur", [
        {"pos": (hx, hy - 0.04 * hs, hz - 0.02 * hs), "rx": 0.195 * hs, "ry_f": 0.14 * hs, "ry_b": 0.19 * hs, "gap_deg": 115.0},
        {"pos": (hx, hy - 0.02 * hs, hz + 0.14 * hs), "rx": 0.185 * hs, "ry_f": 0.16 * hs, "ry_b": 0.20 * hs, "gap_deg": 122.0},
        {"pos": (hx, hy + 0.01 * hs, hz + 0.28 * hs), "rx": 0.125 * hs, "ry_f": 0.16 * hs, "ry_b": 0.18 * hs, "gap_deg": 75.0},
    ], mat=m_fur, parent=head, segs=20, thickness=0.016)

    prim_mesh("RoarMawInterior", "SPHERE", (hx, hy + 0.22 * hs, hz - 0.05 * hs), (0.17 * hs, 0.15 * hs, 0.12 * hs), mat=m_gore, parent=head, verts=14)
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"GoliathEye{nm}", "SPHERE", (hx + sx * 0.078 * hs, hy + 0.205 * hs, hz + 0.115 * hs),
                  (0.034 * hs, 0.028 * hs, 0.026 * hs), mat=m_rage, parent=head, verts=12)
        prim_mesh(f"ApeCanineU{nm}", "CONE", (hx + sx * 0.070 * hs, hy + 0.285 * hs, hz - 0.025 * hs),
                  (0.028 * hs, 0.032 * hs, 0.078 * hs), rot=(math.radians(170), 0, sx * -0.08), mat=m_bone, parent=head, verts=10)
        prim_mesh(f"ApeCanineL{nm}", "CONE", (hx + sx * 0.060 * hs, hy + 0.275 * hs, hz - 0.118 * hs),
                  (0.026 * hs, 0.030 * hs, 0.068 * hs), rot=(math.radians(-12), 0, sx * 0.08), mat=m_bone, parent=head, verts=10)
    for ti in range(4):
        tx = (-0.036 + ti * 0.024) * hs
        prim_mesh(f"ApeIncisorU{ti}", "CUBE", (tx, hy + 0.302 * hs, hz - 0.005 * hs), (0.018 * hs, 0.014 * hs, 0.024 * hs), mat=m_bone, parent=head, bevel=0.003)
        prim_mesh(f"ApeIncisorL{ti}", "CUBE", (tx, hy + 0.292 * hs, hz - 0.132 * hs), (0.016 * hs, 0.014 * hs, 0.022 * hs), mat=m_bone, parent=head, bevel=0.003)

    # 5. COLOSSAL SCULPTED CRUSHER ARMS (`ArmL` & `ArmR` at (±0.64, 0.10, 1.74))
    for sx, nm in ((-1, "L"), (1, "R")):
        arm = add_pivot("Arm" + nm, (sx * 0.64, 0.10, 1.74), parent=torso)

        loft_anatomical(f"GoliathArm{nm}", [
            {"pos": (sx * 0.56, 0.08, 1.85), "rx": 0.22, "ry_f": 0.23, "ry_b": 0.24},
            {"pos": (sx * 0.69, 0.10, 1.66), "rx": 0.25, "ry_f": 0.25, "ry_b": 0.26, "harmonics": [(3, 0.05, 0.0)]},
            {"pos": (sx * 0.76, 0.15, 1.38), "rx": 0.20, "ry_f": 0.22, "ry_b": 0.21},
            {"pos": (sx * 0.78, 0.20, 1.18), "rx": 0.18, "ry_f": 0.19, "ry_b": 0.19},
            {"pos": (sx * 0.81, 0.27, 0.94), "rx": 0.23, "ry_f": 0.24, "ry_b": 0.22, "harmonics": [(4, 0.05, 0.5)]},
            {"pos": (sx * 0.80, 0.34, 0.62), "rx": 0.17, "ry_f": 0.15, "ry_b": 0.15},
        ], mat=m_fur, parent=arm, segs=22, subsurf=1, uv_scale=1.8)

        loft_open_arc(f"DeltoidSilver{nm}", [
            {"pos": (sx * 0.57, 0.06, 1.86), "rx": 0.225, "ry_f": 0.20, "ry_b": 0.23, "gap_deg": 140.0, "gap_offset_deg": sx * -55.0},
            {"pos": (sx * 0.71, 0.08, 1.64), "rx": 0.255, "ry_f": 0.22, "ry_b": 0.24, "gap_deg": 150.0, "gap_offset_deg": sx * -55.0},
        ], mat=m_silver, parent=arm, segs=16, thickness=0.014)

        prim_mesh(f"WristShackle{nm}", "CYLINDER", (sx * 0.80, 0.34, 0.64),
                  (0.37, 0.34, 0.12), rot=(-0.18, 0, 0), mat=m_iron, parent=arm, bevel=0.012, verts=20)
        chain_strand(f"WristChain{nm}", [
            (sx * 0.97, 0.34, 0.62), (sx * 1.01, 0.32, 0.45), (sx * 0.99, 0.30, 0.28)
        ], link_major=0.038, link_minor=0.012, mat=m_iron, parent=arm)

        spline_tube(f"ArmRageVein{nm}", [
            (sx * 0.88, 0.22, 1.48), (sx * 0.96, 0.28, 1.12), (sx * 0.96, 0.36, 0.74)
        ], radius=0.016, mat=m_rage, parent=arm, segs=8)

        # Dark Scarred Slate Knuckle-Walking Gorilla Fist + Bone Knuckle Spurs!
        loft_anatomical(f"ApeMetacarpal{nm}", [
            {"pos": (sx * 0.80, 0.34, 0.60), "rx": 0.165, "ry_f": 0.125, "ry_b": 0.115},
            {"pos": (sx * 0.80, 0.43, 0.44), "rx": 0.195, "ry_f": 0.135, "ry_b": 0.120},
            {"pos": (sx * 0.80, 0.49, 0.30), "rx": 0.185, "ry_f": 0.120, "ry_b": 0.105},
        ], mat=m_chest, parent=arm, segs=18, subsurf=1)

        for fi in range(4):
            fx = sx * (0.665 + fi * 0.088)
            loft_anatomical(f"CurledFinger{nm}{fi}", [
                {"pos": (fx, 0.51, 0.32), "rx": 0.046, "ry_f": 0.048, "ry_b": 0.046},
                {"pos": (fx, 0.58, 0.20), "rx": 0.048, "ry_f": 0.050, "ry_b": 0.048},
                {"pos": (fx, 0.47, 0.15), "rx": 0.042, "ry_f": 0.042, "ry_b": 0.042},
                {"pos": (fx, 0.36, 0.22), "rx": 0.036, "ry_f": 0.036, "ry_b": 0.036},
            ], mat=m_chest, parent=arm, segs=12, subsurf=1)
            prim_mesh(f"KnuckleBoneSpur{nm}{fi}", "CONE", (fx, 0.61, 0.27),
                      (0.040, 0.044, 0.068), rot=(-math.radians(72), 0, 0), mat=m_bone, parent=arm, verts=8)

        loft_anatomical(f"ApeThumb{nm}", [
            {"pos": (sx * 0.64, 0.41, 0.46), "rx": 0.050, "ry_f": 0.050, "ry_b": 0.050},
            {"pos": (sx * 0.60, 0.49, 0.34), "rx": 0.044, "ry_f": 0.044, "ry_b": 0.044},
            {"pos": (sx * 0.63, 0.47, 0.24), "rx": 0.036, "ry_f": 0.036, "ry_b": 0.036},
        ], mat=m_chest, parent=arm, segs=10, subsurf=1)

    # 6. MASSIVE STOUT MUSCULAR APE HIND LEGS (+30% thicker quads/glutes/calves!)
    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.36, -0.06, 1.02), parent=root)
        loft_anatomical(f"GoliathLeg{nm}", [
            {"pos": (sx * 0.33, -0.06, 1.06), "rx": 0.24, "ry_f": 0.25, "ry_b": 0.27},
            {"pos": (sx * 0.40, 0.0, 0.74), "rx": 0.23, "ry_f": 0.24, "ry_b": 0.25, "harmonics": [(3, 0.04, 0.0)]},
            {"pos": (sx * 0.42, 0.04, 0.48), "rx": 0.18, "ry_f": 0.19, "ry_b": 0.19},
            {"pos": (sx * 0.40, -0.03, 0.25), "rx": 0.17, "ry_f": 0.16, "ry_b": 0.19},
            {"pos": (sx * 0.39, -0.05, 0.09), "rx": 0.13, "ry_f": 0.13, "ry_b": 0.14},
        ], mat=m_fur, parent=leg, segs=20, subsurf=1)

        loft_anatomical(f"GoliathFoot{nm}", [
            {"pos": (sx * 0.39, -0.15, 0.055), "rx": 0.120, "ry_f": 0.072, "ry_b": 0.060},
            {"pos": (sx * 0.39, 0.02, 0.052), "rx": 0.140, "ry_f": 0.065, "ry_b": 0.052},
            {"pos": (sx * 0.39, 0.20, 0.040), "rx": 0.150, "ry_f": 0.048, "ry_b": 0.036},
        ], mat=m_chest, parent=leg, segs=16, subsurf=1)
        for ti in range(4):
            tx = sx * 0.39 + (ti - 1.5) * 0.064
            seg_limb(f"ApeToe{nm}{ti}", (tx, 0.20, 0.034), (tx, 0.30, 0.018), 0.028, 0.020, mat=m_chest, parent=leg, verts=8)
            prim_mesh(f"ApeToeClaw{nm}{ti}", "CONE", (tx, 0.325, 0.015), (0.024, 0.024, 0.046),
                      rot=(-math.radians(82), 0, 0), mat=m_bone, parent=leg, verts=6)

    merge_per_pivot()
    export_glb("boss_gorilla.glb")


# ---------------------------------------------------------------------------
# ROUND 3 BOSS: MORBUS-9 — BLIGHT SPITTER / PLAGUE ALCHEMIST (boss_necromancer.glb)
# ---------------------------------------------------------------------------
def build_boss_necromancer():
    clear_scene()
    m_hazmat = make_mat("PlagueHazmat", (0.40, 0.37, 0.22, 1), roughness=0.62, tex_prefix="plague_hazmat", normal_strength=1.35, contrast=1.45)
    m_apron = make_mat("ChemRubber", (0.19, 0.19, 0.18, 1), roughness=0.42, tex_prefix="leather", contrast=1.38)
    m_leather = make_mat("HarnessLeather", (0.25, 0.19, 0.13, 1), roughness=0.56, tex_prefix="leather")
    m_flesh = make_mat("MutantSporeFlesh", (0.38, 0.46, 0.28, 1), roughness=0.45, tex_prefix="bloater_flesh", contrast=1.45)
    m_steel = make_mat("ReactorSteel", (0.33, 0.36, 0.35, 1), metallic=0.84, roughness=0.38, tex_prefix="panzer_steel", contrast=1.40)
    m_brass = make_mat("ValveBrass", (0.56, 0.42, 0.18, 1), metallic=0.84, roughness=0.34)
    m_hose = make_mat("RibbedHose", (0.08, 0.09, 0.08, 1), roughness=0.72)
    m_void = make_mat("CowlShadow", (0.02, 0.025, 0.02, 1), roughness=0.95)
    m_bone = make_mat("PlagueBone", (0.68, 0.64, 0.48, 1), roughness=0.50)
    m_acid = neon_mat("BioAcidBright", (0.28, 1.0, 0.18), strength=6.5, roughness=0.12)
    m_vat = make_mat("BioVatFluid", (0.32, 0.92, 0.20, 1), roughness=0.14, emission=(0.26, 0.95, 0.16), emission_strength=3.6, srgb_input=False)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.06), parent=root)

    # Inner Hunched Bio-Alchemist Core + Vulcanized Dark Rubber Suit
    loft_anatomical("MorbusInnerBody", [
        {"pos": (0, 0, 0.90), "rx": 0.20, "ry_f": 0.14, "ry_b": 0.16},
        {"pos": (0, 0.01, 1.20), "rx": 0.21, "ry_f": 0.16, "ry_b": 0.17},
        {"pos": (0, 0.03, 1.48), "rx": 0.25, "ry_f": 0.17, "ry_b": 0.19},
        {"pos": (0, 0.05, 1.72), "rx": 0.22, "ry_f": 0.15, "ry_b": 0.19},
        {"pos": (0, 0.06, 1.84), "rx": 0.15, "ry_f": 0.11, "ry_b": 0.13},
    ], mat=m_apron, parent=torso, segs=20, subsurf=1)

    # OPEN-FRONT Tattered Plague-Hazmat Greatcoat (`loft_open_arc`) parted over dark chemical vest & glowing bio-pump!
    loft_open_arc("MorbusHazmatRobe", [
        {"pos": (0, 0.05, 1.83), "rx": 0.18, "ry_f": 0.13, "ry_b": 0.16, "gap_deg": 78.0},
        {"pos": (0, 0.03, 1.66), "rx": 0.28, "ry_f": 0.19, "ry_b": 0.22, "gap_deg": 56.0, "harmonics": [(5, 0.04, 0.2)]},
        {"pos": (0, 0.01, 1.38), "rx": 0.25, "ry_f": 0.19, "ry_b": 0.21, "gap_deg": 48.0, "harmonics": [(6, 0.05, 0.9)]},
        {"pos": (0, 0.0, 1.08), "rx": 0.24, "ry_f": 0.18, "ry_b": 0.20, "gap_deg": 52.0, "harmonics": [(6, 0.05, 1.4)]},
        {"pos": (0, -0.02, 0.72), "rx": 0.30, "ry_f": 0.20, "ry_b": 0.25, "gap_deg": 74.0, "harmonics": [(8, 0.07, 0.5)]},
        {"pos": (0, -0.03, 0.36), "rx": 0.36, "ry_f": 0.22, "ry_b": 0.29, "gap_deg": 92.0, "harmonics": [(9, 0.09, 1.8)]},
    ], mat=m_hazmat, parent=torso, segs=28, thickness=0.011, tear_end_amp=0.088, tear_lapel_amp=0.035, tear_seed=29)

    # Chest Bio-Pump Manifold + Glowing Specimen Vials + Heavy Leather Harness Belt!
    prim_mesh("ChestPumpManifold", "CUBE", (0, 0.185, 1.46), (0.22, 0.065, 0.24), rot=(-0.08, 0, 0), mat=m_steel, parent=torso, bevel=0.012)
    prim_mesh("ChestCoreChamber", "CYLINDER", (0, 0.218, 1.46), (0.095, 0.095, 0.16), mat=m_vat, parent=torso, verts=16)
    prim_mesh("ChemBelt", "CYLINDER", (0, 0.01, 1.12), (0.51, 0.40, 0.068), mat=m_leather, parent=torso, bevel=0.008, verts=24)
    prim_mesh("ChemBuckle", "CUBE", (0, 0.208, 1.12), (0.080, 0.028, 0.072), mat=m_brass, parent=torso, bevel=0.006)

    for vi in range(4):
        vx = -0.15 + vi * 0.10
        prim_mesh(f"BeltVial{vi}", "CYLINDER", (vx, 0.205, 1.24), (0.038, 0.038, 0.120),
                  rot=(0.10, 0, (vi - 1.5) * 0.08), mat=m_vat, parent=torso, verts=12)
        prim_mesh(f"VialCap{vi}", "CYLINDER", (vx, 0.212, 1.30), (0.044, 0.044, 0.024),
                  rot=(0.10, 0, (vi - 1.5) * 0.08), mat=m_brass, parent=torso, verts=12)

    # Twin Dorsal Pressurized Biotoxin Vat Reactors + Steel Cage + Gauges + Ribbed Hoses!
    prim_mesh("ReactorFrame", "CUBE", (0, -0.24, 1.52), (0.50, 0.09, 0.54), mat=m_steel, parent=torso, bevel=0.012)
    for sx, nm in ((-1, "L"), (1, "R")):
        tx, ty, tz = sx * 0.19, -0.34, 1.54
        prim_mesh(f"BioTankFluid{nm}", "CYLINDER", (tx, ty, tz), (0.22, 0.22, 0.58),
                  rot=(0.08, 0, 0), mat=m_vat, parent=torso, verts=20)
        prim_mesh(f"TankDomeTop{nm}", "SPHERE", (tx, ty - 0.02, tz + 0.29), (0.24, 0.24, 0.15), mat=m_steel, parent=torso, verts=18)
        prim_mesh(f"TankDomeBot{nm}", "SPHERE", (tx, ty + 0.02, tz - 0.29), (0.24, 0.24, 0.15), mat=m_steel, parent=torso, verts=18)
        prim_mesh(f"TankStrapMid{nm}", "CYLINDER", (tx, ty, tz), (0.245, 0.245, 0.048), rot=(0.08, 0, 0), mat=m_steel, parent=torso, verts=20)
        for ci in range(4):
            ca = ci * math.tau / 4.0 + 0.4
            seg_limb(f"CageBar{nm}{ci}",
                     (tx + math.cos(ca) * 0.12, ty + math.sin(ca) * 0.12 - 0.02, tz + 0.28),
                     (tx + math.cos(ca) * 0.12, ty + math.sin(ca) * 0.12 + 0.02, tz - 0.28),
                     0.011, 0.011, mat=m_steel, parent=torso, verts=8)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.058, minor_radius=0.011, major_segments=16, minor_segments=6,
                                         location=(tx, ty - 0.03, tz + 0.38))
        vw = bpy.context.active_object
        vw.name = f"ValveWheel{nm}"
        vw.data.materials.append(m_brass)
        auto_uv(vw, 3.0)
        vw.parent = torso
        vw.matrix_parent_inverse = torso.matrix_world.inverted()
        prim_mesh(f"TankGauge{nm}", "CYLINDER", (tx + sx * 0.125, ty + 0.02, tz + 0.16),
                  (0.068, 0.068, 0.028), rot=(0, R90, 0), mat=m_brass, parent=torso, verts=14)
        prim_mesh(f"GaugeFace{nm}", "CYLINDER", (tx + sx * 0.142, ty + 0.02, tz + 0.16),
                  (0.050, 0.050, 0.008), rot=(0, R90, 0), mat=m_acid, parent=torso, verts=14)

        spline_tube(f"RespiratorHose{nm}", [
            (tx, ty - 0.02, tz + 0.33),
            (sx * 0.24, -0.05, 1.93),
            (sx * 0.13, 0.16, 1.81),
        ], radius=0.024, mat=m_hose, parent=torso, ribbed=True, segs=10)

    # Head: OPEN-FRONT Shadowed Plague Cowl (`loft_open_arc`) revealing Full Plague-Respirator Gas Mask!
    head = add_pivot("Head", (0, 0.07, 1.84), parent=torso)
    hx, hy, hz = 0.0, 0.07, 1.84
    # Dark inner head skull/hood shadow behind the gas mask
    prim_mesh("InnerCowlShadow", "SPHERE", (hx, hy + 0.01, hz + 0.09), (0.24, 0.25, 0.26), mat=m_void, parent=head, verts=16)

    loft_open_arc("PlagueCowl", [
        {"pos": (hx, hy - 0.03, hz - 0.05), "rx": 0.185, "ry_f": 0.165, "ry_b": 0.185, "gap_deg": 86.0},
        {"pos": (hx, hy - 0.01, hz + 0.09), "rx": 0.178, "ry_f": 0.175, "ry_b": 0.195, "gap_deg": 118.0, "harmonics": [(4, 0.04, 0.0)]},
        {"pos": (hx, hy + 0.02, hz + 0.21), "rx": 0.145, "ry_f": 0.175, "ry_b": 0.185, "gap_deg": 92.0},
        {"pos": (hx, hy - 0.06, hz + 0.29), "rx": 0.065, "ry_f": 0.085, "ry_b": 0.135, "gap_deg": 28.0},
    ], mat=m_hazmat, parent=head, segs=24, thickness=0.012, tear_lapel_amp=0.025, tear_seed=33)

    # Dark Vulcanized Plague-Respirator Faceplate & Curved Snout + Brass Goggles + Twin Filter Canisters!
    loft_anatomical("PlagueMaskFace", [
        {"pos": (hx, hy + 0.04, hz + 0.10), "rx": 0.118, "ry_f": 0.118, "ry_b": 0.095},
        {"pos": (hx, hy + 0.15, hz + 0.05), "rx": 0.085, "ry_f": 0.088, "ry_b": 0.075},
        {"pos": (hx, hy + 0.26, hz - 0.03), "rx": 0.048, "ry_f": 0.052, "ry_b": 0.048},
        {"pos": (hx, hy + 0.34, hz - 0.11), "rx": 0.024, "ry_f": 0.026, "ry_b": 0.024},
    ], mat=m_apron, parent=head, segs=16, subsurf=1)
    prim_mesh("ForeheadValve", "CYLINDER", (hx, hy + 0.135, hz + 0.165), (0.046, 0.046, 0.024), rot=(R90, 0, 0), mat=m_brass, parent=head, verts=12)

    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"LensRim{nm}", "CYLINDER", (hx + sx * 0.058, hy + 0.145, hz + 0.102),
                  (0.072, 0.072, 0.036), rot=(math.radians(82), 0, sx * -0.22), mat=m_brass, parent=head, verts=16)
        prim_mesh(f"PlagueLens{nm}", "CYLINDER", (hx + sx * 0.060, hy + 0.162, hz + 0.102),
                  (0.054, 0.054, 0.012), rot=(math.radians(82), 0, sx * -0.22), mat=m_acid, parent=head, verts=16)
        prim_mesh(f"FilterCan{nm}", "CYLINDER", (hx + sx * 0.112, hy + 0.140, hz - 0.028),
                  (0.088, 0.088, 0.090), rot=(math.radians(65), 0, sx * -0.45), mat=m_steel, parent=head, bevel=0.006, verts=16)

    # Mutated Acid-Sprayer & Bone-Talon Arms (bent menacingly at elbow!)
    for sx, nm in ((-1, "L"), (1, "R")):
        arm = add_pivot("Arm" + nm, (sx * 0.32, 0.04, 1.68), parent=torso)
        loft_anatomical(f"MorbusPauldron{nm}", [
            {"pos": (sx * 0.26, 0.03, 1.75), "rx": 0.065, "ry_f": 0.092, "ry_b": 0.092},
            {"pos": (sx * 0.36, 0.04, 1.67), "rx": 0.082, "ry_f": 0.112, "ry_b": 0.112},
            {"pos": (sx * 0.38, 0.04, 1.57), "rx": 0.070, "ry_f": 0.096, "ry_b": 0.096},
        ], mat=m_steel, parent=arm, segs=14, subsurf=1)

        # Continuous bent arm: upper hazmat sleeve -> ruptured elbow -> spore-mutated forearm!
        loft_anatomical(f"MutantFullArm{nm}", [
            {"pos": (sx * 0.32, 0.04, 1.68), "rx": 0.072, "ry_f": 0.072, "ry_b": 0.072},
            {"pos": (sx * 0.39, 0.14, 1.42), "rx": 0.068, "ry_f": 0.070, "ry_b": 0.070},
            {"pos": (sx * 0.35, 0.36, 1.32), "rx": 0.078, "ry_f": 0.082, "ry_b": 0.076},
            {"pos": (sx * 0.30, 0.54, 1.24), "rx": 0.056, "ry_f": 0.058, "ry_b": 0.055},
        ], mat=m_flesh, parent=arm, segs=16, subsurf=1)

        loft_anatomical(f"MorbusSleeve{nm}", [
            {"pos": (sx * 0.32, 0.04, 1.69), "rx": 0.084, "ry_f": 0.084, "ry_b": 0.084},
            {"pos": (sx * 0.39, 0.14, 1.41), "rx": 0.086, "ry_f": 0.086, "ry_b": 0.086, "harmonics": [(6, 0.09, 0.4)]},
        ], mat=m_hazmat, parent=arm, segs=16, cap_start=True, cap_end=False,
           open_shell_thickness=0.008, tear_end_amp=0.042, tear_seed=80 + sx)

        prim_mesh(f"VenomGland{nm}", "SPHERE", (sx * 0.37, 0.36, 1.35), (0.120, 0.155, 0.110), mat=m_vat, parent=arm, verts=14)
        prim_mesh(f"SprayerBarrel{nm}", "CYLINDER", (sx * 0.37, 0.52, 1.28),
                  (0.044, 0.044, 0.22), rot=(math.radians(66), 0, sx * -0.15), mat=m_brass, parent=arm, verts=12)
        prim_mesh(f"SprayerTip{nm}", "SPHERE", (sx * 0.35, 0.62, 1.23), (0.038, 0.038, 0.038), mat=m_acid, parent=arm, verts=10)
        spline_tube(f"ArmFeedHose{nm}", [
            (sx * 0.34, 0.06, 1.62), (sx * 0.46, 0.18, 1.46), (sx * 0.41, 0.34, 1.38)
        ], radius=0.017, mat=m_hose, parent=arm, ribbed=True, segs=8)

        for fi in range(4):
            fx = sx * 0.30 + (fi - 1.5) * 0.026
            loft_anatomical(f"PlagueTalon{nm}{fi}", [
                ((fx, 0.54, 1.24), 0.016, 0.016, 0.016),
                ((fx, 0.64, 1.18), 0.012, 0.012, 0.012),
                ((fx, 0.70, 1.07), 0.005, 0.005, 0.005),
            ], mat=m_bone, parent=arm, segs=8, subsurf=0)

    # Legs: Heavy Dark Vulcanized Hazmat Waders & Steel-Toe Chemical Boots (NO orange!)
    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.16, 0, 1.00), parent=root)
        loft_anatomical(f"MorbusLeg{nm}", [
            {"pos": (sx * 0.16, 0, 1.00), "rx": 0.118, "ry_f": 0.122, "ry_b": 0.128},
            {"pos": (sx * 0.162, 0.01, 0.54), "rx": 0.098, "ry_f": 0.100, "ry_b": 0.102, "harmonics": [(5, 0.04, 0.6)]},
            {"pos": (sx * 0.160, 0.0, 0.12), "rx": 0.084, "ry_f": 0.086, "ry_b": 0.088},
        ], mat=m_apron, parent=leg, segs=18, subsurf=1)
        loft_anatomical(f"WaderBoot{nm}", [
            {"pos": (sx * 0.160, -0.055, 0.055), "rx": 0.076, "ry_f": 0.076, "ry_b": 0.068},
            {"pos": (sx * 0.160, 0.065, 0.052), "rx": 0.074, "ry_f": 0.066, "ry_b": 0.058},
            {"pos": (sx * 0.160, 0.195, 0.044), "rx": 0.068, "ry_f": 0.052, "ry_b": 0.042},
        ], mat=m_steel, parent=leg, segs=16, subsurf=1)
        prim_mesh(f"WaderSole{nm}", "CUBE", (sx * 0.160, 0.070, 0.015), (0.145, 0.29, 0.030), mat=m_hose, parent=leg, bevel=0.006)

    merge_per_pivot()
    export_glb("boss_necromancer.glb")


# ---------------------------------------------------------------------------
# ROUND 4 BOSS: PANZER-KRIEG — DIESELPUNK IRON JUGGERNAUT (boss_juggernaut.glb)
# CRITICAL WEAKPOINT: Chest Power Core at (0, +0.34, 1.55)!
# ---------------------------------------------------------------------------
def build_boss_juggernaut():
    clear_scene()
    m_steel = make_mat("PanzerArmor", (0.37, 0.40, 0.43, 1), metallic=0.84, roughness=0.36, tex_prefix="panzer_steel", normal_strength=1.35, contrast=1.45)
    m_dark_steel = make_mat("PanzerChassis", (0.21, 0.23, 0.25, 1), metallic=0.88, roughness=0.32, tex_prefix="gunmetal", contrast=1.38)
    m_olive = make_mat("PanzerOlive", (0.29, 0.32, 0.24, 1), metallic=0.62, roughness=0.44, tex_prefix="panzer_steel", contrast=1.40)
    m_brass = make_mat("PanzerBrass", (0.68, 0.50, 0.22, 1), metallic=0.88, roughness=0.30)
    m_hazard = make_mat("HazardYellow", (0.78, 0.58, 0.10, 1), metallic=0.30, roughness=0.46)
    m_hose = make_mat("FuelBraidedHose", (0.08, 0.08, 0.08, 1), roughness=0.72)
    m_core = neon_mat("PanzerPowerCore", (1.0, 0.72, 0.14), strength=8.5, roughness=0.12)
    m_furnace = neon_mat("FurnaceHeat", (1.0, 0.36, 0.05), strength=6.0, roughness=0.18)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.12), parent=root)

    # 1. Contoured Faceted Dieselpunk Siege Cuirass
    loft_anatomical("PanzerCuirass", [
        {"pos": (0, 0.0, 1.00), "rx": 0.33, "ry_f": 0.25, "ry_b": 0.26},
        {"pos": (0, 0.0, 1.20), "rx": 0.37, "ry_f": 0.28, "ry_b": 0.29},
        {"pos": (0, 0.02, 1.48), "rx": 0.46, "ry_f": 0.33, "ry_b": 0.34, "harmonics": [(4, 0.04, 0.0)]},
        {"pos": (0, 0.02, 1.78), "rx": 0.49, "ry_f": 0.33, "ry_b": 0.35, "harmonics": [(4, 0.04, 0.0)]},
        {"pos": (0, 0.01, 1.98), "rx": 0.37, "ry_f": 0.26, "ry_b": 0.28},
    ], mat=m_olive, parent=torso, segs=16, subsurf=0, uv_scale=1.8)

    # Layered Chamfered Front Glacis Plates + Glowing Furnace Vents + Siege Gorget!
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"UpperGlacis{nm}", "CUBE", (sx * 0.25, 0.29, 1.76), (0.28, 0.08, 0.30),
                  rot=(-0.18, 0, sx * -0.22), mat=m_steel, parent=torso, bevel=0.016)
        prim_mesh(f"FurnaceVent{nm}", "CUBE", (sx * 0.27, 0.325, 1.78), (0.12, 0.025, 0.045),
                  rot=(-0.18, 0, sx * -0.22), mat=m_furnace, parent=torso, bevel=0.004)
        prim_mesh(f"HipTasset{nm}", "CUBE", (sx * 0.37, 0.02, 1.02), (0.075, 0.39, 0.27),
                  rot=(0, sx * -0.18, 0), mat=m_steel, parent=torso, bevel=0.014)
        prim_mesh(f"TassetHazard{nm}", "CUBE", (sx * 0.41, 0.02, 0.94), (0.022, 0.34, 0.055),
                  rot=(0, sx * -0.18, 0), mat=m_hazard, parent=torso, bevel=0.004)

    loft_anatomical("SiegeGorget", [
        {"pos": (0, 0.02, 1.92), "rx": 0.29, "ry_f": 0.25, "ry_b": 0.25},
        {"pos": (0, 0.03, 2.05), "rx": 0.26, "ry_f": 0.23, "ry_b": 0.23},
    ], mat=m_steel, parent=torso, segs=16, cap_start=False, cap_end=False, open_shell_thickness=0.024)

    prim_mesh("SiegeBelt", "CYLINDER", (0, 0.0, 1.14), (0.76, 0.58, 0.13), mat=m_dark_steel, parent=torso, bevel=0.015, verts=18)
    prim_mesh("GroinArmor", "CUBE", (0, 0.28, 1.02), (0.27, 0.07, 0.25), rot=(0.12, 0, 0), mat=m_steel, parent=torso, bevel=0.014)

    # 2. EXACT CHEST POWER CORE WEAKPOINT AT (0, +0.34, 1.55)!
    prim_mesh("CoreArmorHousing", "CYLINDER", (0, 0.31, 1.55), (0.37, 0.37, 0.11), rot=(R90, 0, 0), mat=m_dark_steel, parent=torso, bevel=0.012, verts=24)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.175, minor_radius=0.034, major_segments=24, minor_segments=10,
                                     location=(0, 0.34, 1.55), rotation=(R90, 0, 0))
    bezel = bpy.context.active_object
    bezel.name = "CoreBrassBezel"
    bezel.data.materials.append(m_brass)
    auto_uv(bezel, 3.0)
    bezel.parent = torso
    bezel.matrix_parent_inverse = torso.matrix_world.inverted()

    prim_mesh("PowerCoreOrb", "SPHERE", (0, 0.35, 1.55), (0.26, 0.12, 0.26), mat=m_core, parent=torso, verts=20)
    for bi in range(8):
        ba = bi * math.tau / 8.0
        prim_mesh(f"BezelBolt{bi}", "CYLINDER", (math.cos(ba) * 0.175, 0.374, 1.55 + math.sin(ba) * 0.175),
                  (0.026, 0.026, 0.022), rot=(R90, 0, 0), mat=m_steel, parent=torso, verts=8)
    for ci in (-0.065, 0.065):
        prim_mesh(f"CoreCageBar{ci:+.2f}", "CUBE", (ci, 0.395, 1.55), (0.016, 0.018, 0.30), mat=m_dark_steel, parent=torso, bevel=0.003)

    # 3. Twin Dorsal Napalm Fuel Tanks + Furnace Exhaust Smokestacks!
    for sx, nm in ((-1, "L"), (1, "R")):
        fx, fy, fz = sx * 0.23, -0.41, 1.58
        prim_mesh(f"NapalmTank{nm}", "CYLINDER", (fx, fy, fz), (0.27, 0.27, 0.64), rot=(0.06, 0, 0), mat=m_steel, parent=torso, bevel=0.010, verts=20)
        prim_mesh(f"NapalmCapTop{nm}", "SPHERE", (fx, fy - 0.02, fz + 0.32), (0.27, 0.27, 0.16), mat=m_brass, parent=torso, verts=18)
        prim_mesh(f"NapalmCapBot{nm}", "SPHERE", (fx, fy + 0.02, fz - 0.32), (0.27, 0.27, 0.16), mat=m_dark_steel, parent=torso, verts=18)
        prim_mesh(f"SmokeStack{nm}", "CYLINDER", (sx * 0.30, -0.27, 2.08), (0.100, 0.100, 0.38),
                  rot=(-0.18, sx * 0.12, 0), mat=m_dark_steel, parent=torso, bevel=0.006, verts=14)
        prim_mesh(f"StackEmber{nm}", "CYLINDER", (sx * 0.32, -0.30, 2.26), (0.076, 0.076, 0.03),
                  rot=(-0.18, sx * 0.12, 0), mat=m_furnace, parent=torso, verts=12)

    # 4. Iconic COD-Origins Riveted Bunker / Diving Dome Helmet (`Head` at (0, 0.04, 1.98))
    head = add_pivot("Head", (0, 0.04, 1.98), parent=torso)
    hx, hy, hz = 0.0, 0.04, 1.98
    loft_anatomical("PanzerDomeHelmet", [
        {"pos": (hx, hy, hz - 0.02), "rx": 0.21, "ry_f": 0.22, "ry_b": 0.22},
        {"pos": (hx, hy, hz + 0.16), "rx": 0.22, "ry_f": 0.23, "ry_b": 0.23},
        {"pos": (hx, hy, hz + 0.30), "rx": 0.185, "ry_f": 0.195, "ry_b": 0.195},
        {"pos": (hx, hy, hz + 0.39), "rx": 0.105, "ry_f": 0.115, "ry_b": 0.115},
    ], mat=m_steel, parent=head, segs=22, subsurf=1)

    prim_mesh("HelmetCrest", "CUBE", (hx, hy - 0.02, hz + 0.37), (0.052, 0.29, 0.080), mat=m_dark_steel, parent=head, bevel=0.010)
    prim_mesh("VisorBrowPlate", "CUBE", (hx, hy + 0.205, hz + 0.21), (0.34, 0.09, 0.090), rot=(0.18, 0, 0), mat=m_dark_steel, parent=head, bevel=0.012)
    prim_mesh("FurnaceVisorSlit", "CUBE", (hx, hy + 0.225, hz + 0.155), (0.27, 0.038, 0.044), mat=m_core, parent=head, bevel=0.005)
    prim_mesh("VisorBarL", "CUBE", (hx - 0.055, hy + 0.242, hz + 0.155), (0.016, 0.016, 0.052), mat=m_dark_steel, parent=head)
    prim_mesh("VisorBarR", "CUBE", (hx + 0.055, hy + 0.242, hz + 0.155), (0.016, 0.016, 0.052), mat=m_dark_steel, parent=head)
    prim_mesh("HelmetJawGrille", "CUBE", (hx, hy + 0.195, hz + 0.055), (0.27, 0.13, 0.125), mat=m_olive, parent=head, bevel=0.015)
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"BreatherDrum{nm}", "CYLINDER", (hx + sx * 0.145, hy + 0.205, hz + 0.04),
                  (0.088, 0.088, 0.078), rot=(math.radians(70), 0, sx * -0.45), mat=m_brass, parent=head, bevel=0.006, verts=14)

    # 5. LEFT ARM: Connected Hydraulic Forearm -> Riot Buckler -> Superheated 3-Prong Hydraulic Siege Claw!
    arm_l = add_pivot("ArmL", (-0.52, 0.02, 1.78), parent=torso)
    for li in range(3):
        prim_mesh(f"PauldronLameL{li}", "SPHERE", (-0.56 - li * 0.03, 0.02, 1.82 - li * 0.09),
                  (0.30, 0.36, 0.19), rot=(0, 0.35 + li * 0.12, 0), mat=m_steel if li % 2 == 0 else m_olive, parent=arm_l, verts=16)
    loft_anatomical("PanzerArmHousingL", [
        {"pos": (-0.54, 0.02, 1.74), "rx": 0.14, "ry_f": 0.14, "ry_b": 0.14},
        {"pos": (-0.58, 0.18, 1.44), "rx": 0.135, "ry_f": 0.135, "ry_b": 0.135},
        {"pos": (-0.56, 0.38, 1.25), "rx": 0.15, "ry_f": 0.15, "ry_b": 0.15},
        {"pos": (-0.55, 0.52, 1.15), "rx": 0.13, "ry_f": 0.13, "ry_b": 0.13},
    ], mat=m_dark_steel, parent=arm_l, segs=14, subsurf=0)

    prim_mesh("SiegeBuckler", "CUBE", (-0.70, 0.38, 1.28), (0.060, 0.40, 0.48),
              rot=(0.25, -0.18, 0.15), mat=m_steel, parent=arm_l, bevel=0.016)
    prim_mesh("BucklerHazard", "CUBE", (-0.73, 0.40, 1.14), (0.020, 0.35, 0.065),
              rot=(0.25, -0.18, 0.15), mat=m_hazard, parent=arm_l, bevel=0.004)
    prim_mesh("ClawCollar", "CYLINDER", (-0.55, 0.52, 1.15), (0.26, 0.26, 0.14), rot=(math.radians(60), 0, 0), mat=m_brass, parent=arm_l, bevel=0.008, verts=16)
    for ci, ang in enumerate((0.0, 2.1, 4.2)):
        cx = -0.55 + math.cos(ang) * 0.095
        cz = 1.15 + math.sin(ang) * 0.095
        prim_mesh(f"SiegeProng{ci}", "CONE", (cx, 0.68, cz - 0.08),
                  (0.060, 0.036, 0.28), rot=(-math.radians(65), 0, 0), mat=m_steel, parent=arm_l, verts=8)
        prim_mesh(f"ProngHeat{ci}", "CONE", (cx, 0.74, cz - 0.12),
                  (0.035, 0.020, 0.17), rot=(-math.radians(65), 0, 0), mat=m_furnace, parent=arm_l, verts=6)

    # 6. RIGHT ARM: Heavy Twin-Barrel Industrial Flamethrower Cannon!
    arm_r = add_pivot("ArmR", (0.52, 0.02, 1.78), parent=torso)
    for li in range(3):
        prim_mesh(f"PauldronLameR{li}", "SPHERE", (0.56 + li * 0.03, 0.02, 1.82 - li * 0.09),
                  (0.30, 0.36, 0.19), rot=(0, -0.35 - li * 0.12, 0), mat=m_steel if li % 2 == 0 else m_olive, parent=arm_r, verts=16)
    loft_anatomical("PanzerArmHousingR", [
        {"pos": (0.54, 0.02, 1.74), "rx": 0.14, "ry_f": 0.14, "ry_b": 0.14},
        {"pos": (0.54, 0.26, 1.50), "rx": 0.14, "ry_f": 0.14, "ry_b": 0.14},
        {"pos": (0.52, 0.44, 1.48), "rx": 0.13, "ry_f": 0.13, "ry_b": 0.13},
    ], mat=m_dark_steel, parent=arm_r, segs=14, subsurf=0)

    prim_mesh("FlamerBody", "CUBE", (0.52, 0.50, 1.48), (0.22, 0.44, 0.24), mat=m_dark_steel, parent=arm_r, bevel=0.018)
    prim_mesh("FlamerDrum", "CYLINDER", (0.52, 0.50, 1.31), (0.16, 0.16, 0.28), rot=(R90, 0, 0), mat=m_hazard, parent=arm_r, bevel=0.008, verts=16)
    for bz in (1.535, 1.435):
        prim_mesh(f"FlamerBarrel_{bz:.2f}", "CYLINDER", (0.52, 0.84, bz), (0.072, 0.072, 0.44), rot=(R90, 0, 0), mat=m_steel, parent=arm_r, verts=14)
    prim_mesh("BrassHeatShroud", "CYLINDER", (0.52, 0.90, 1.485), (0.22, 0.22, 0.28), rot=(R90, 0, 0), mat=m_brass, parent=arm_r, bevel=0.008, verts=18)
    prim_mesh("PilotIgniter", "SPHERE", (0.52, 1.07, 1.485), (0.115, 0.095, 0.115), mat=m_furnace, parent=arm_r, verts=14)
    spline_tube("FlamerFeedHose", [(0.56, 0.36, 1.54), (0.66, 0.04, 1.56), (0.36, -0.30, 1.56)],
                radius=0.032, mat=m_hose, parent=arm_r, ribbed=True, segs=10)

    # 7. HEAVY HYDRAULIC SIEGE LEGS & STOMPER SABATONS (`LegL` & `LegR` at (±0.26, 0, 1.04))
    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.26, 0, 1.04), parent=root)
        loft_anatomical(f"PanzerThigh{nm}", [
            {"pos": (sx * 0.26, 0, 1.04), "rx": 0.17, "ry_f": 0.18, "ry_b": 0.18},
            {"pos": (sx * 0.26, 0.01, 0.60), "rx": 0.15, "ry_f": 0.16, "ry_b": 0.16},
        ], mat=m_olive, parent=leg, segs=14, subsurf=0)
        prim_mesh(f"PanzerKnee{nm}", "CUBE", (sx * 0.26, 0.15, 0.58), (0.25, 0.11, 0.23), rot=(-0.12, 0, 0), mat=m_steel, parent=leg, bevel=0.020)
        loft_anatomical(f"PanzerGreave{nm}", [
            {"pos": (sx * 0.26, 0.0, 0.56), "rx": 0.15, "ry_f": 0.16, "ry_b": 0.16},
            {"pos": (sx * 0.26, 0.0, 0.16), "rx": 0.17, "ry_f": 0.18, "ry_b": 0.18},
        ], mat=m_steel, parent=leg, segs=14, subsurf=0)
        for py_off in (-0.13, 0.12):
            prim_mesh(f"HydraulicRod{nm}_{py_off:+.2f}", "CYLINDER", (sx * 0.40, py_off, 0.42),
                      (0.058, 0.058, 0.44), mat=m_brass, parent=leg, verts=12)
        loft_anatomical(f"PanzerSabaton{nm}", [
            {"pos": (sx * 0.26, -0.11, 0.075), "rx": 0.16, "ry_f": 0.095, "ry_b": 0.085},
            {"pos": (sx * 0.26, 0.08, 0.068), "rx": 0.17, "ry_f": 0.090, "ry_b": 0.080},
            {"pos": (sx * 0.26, 0.27, 0.052), "rx": 0.15, "ry_f": 0.070, "ry_b": 0.058},
        ], mat=m_dark_steel, parent=leg, segs=14, subsurf=0)
        prim_mesh(f"SabatonSole{nm}", "CUBE", (sx * 0.26, 0.08, 0.018), (0.32, 0.45, 0.036), mat=m_steel, parent=leg, bevel=0.008)

    merge_per_pivot()
    export_glb("boss_juggernaut.glb")


# ---------------------------------------------------------------------------
# ROUND 5+ BOSS: WRAITH-11 — THE VOLT REAPER (boss_phantom.glb)
# ---------------------------------------------------------------------------
def build_boss_phantom():
    clear_scene()
    m_coat = make_mat("WraithGreatcoat", (0.14, 0.17, 0.24, 1), roughness=0.82, tex_prefix="fabric", normal_strength=1.25, contrast=1.40)
    m_trim = make_mat("WraithLeather", (0.19, 0.21, 0.27, 1), roughness=0.48, tex_prefix="leather", contrast=1.35)
    m_steel = make_mat("ReaperSteel", (0.35, 0.39, 0.45, 1), metallic=0.86, roughness=0.28, tex_prefix="gunmetal", contrast=1.40)
    m_copper = make_mat("TeslaCopper", (0.68, 0.38, 0.19, 1), metallic=0.88, roughness=0.28)
    m_bone = make_mat("WraithSkull", (0.68, 0.70, 0.68, 1), roughness=0.44, tex_prefix="necrotic_flesh", contrast=1.25)
    m_void = make_mat("HoodVoid", (0.015, 0.02, 0.03, 1), roughness=0.95)
    m_volt = neon_mat("VoltArc", (0.30, 0.85, 1.0), strength=8.0, roughness=0.10)
    m_core = neon_mat("TeslaHeart", (0.16, 0.62, 1.0), strength=5.5, roughness=0.14)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.08), parent=root)

    # 1. Gaunt Undead Core + Exposed Skeletal Ribcage Caging a Multi-Ring Tesla Volt Heart!
    loft_anatomical("WraithSpineCore", [
        {"pos": (0, -0.02, 0.94), "rx": 0.16, "ry_f": 0.11, "ry_b": 0.13},
        {"pos": (0, -0.02, 1.24), "rx": 0.14, "ry_f": 0.09, "ry_b": 0.11},
        {"pos": (0, -0.01, 1.54), "rx": 0.17, "ry_f": 0.11, "ry_b": 0.13},
        {"pos": (0, 0.01, 1.78), "rx": 0.13, "ry_f": 0.09, "ry_b": 0.11},
    ], mat=m_void, parent=torso, segs=16, subsurf=1)

    prim_mesh("TeslaHeartOrb", "SPHERE", (0, 0.08, 1.46), (0.15, 0.13, 0.17), mat=m_volt, parent=torso, verts=16)
    for ri, rot_r in enumerate(((0.4, 0.2, 0), (-0.5, 0.4, 0.3), (1.1, -0.3, 0.2))):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.11 + ri * 0.024, minor_radius=0.009,
                                         major_segments=20, minor_segments=6,
                                         location=(0, 0.08, 1.46), rotation=rot_r)
        ring = bpy.context.active_object
        ring.name = f"HeartGyroRing{ri}"
        ring.data.materials.append(m_core)
        auto_uv(ring, 3.0)
        ring.parent = torso
        ring.matrix_parent_inverse = torso.matrix_world.inverted()

    for sx, nm in ((-1, "L"), (1, "R")):
        for ri in range(6):
            rz = 1.60 - ri * 0.056
            w_rib = 0.185 - abs(ri - 2.0) * 0.014
            spline_tube(f"WraithRib{nm}{ri}", [
                (sx * 0.03, -0.08, rz + 0.01),
                (sx * w_rib, 0.04, rz),
                (sx * 0.058, 0.172, rz - 0.015),
            ], radius=0.011, mat=m_bone, parent=torso, segs=8)

    # 2. OPEN-FRONT High-Collar Officer Greatcoat (`loft_open_arc`) revealing Tesla Heart AND Armored Legs!
    loft_open_arc("WraithGreatcoatBody", [
        {"pos": (0, -0.02, 1.84), "rx": 0.20, "ry_f": 0.13, "ry_b": 0.16, "gap_deg": 92.0},
        {"pos": (0, -0.01, 1.68), "rx": 0.28, "ry_f": 0.17, "ry_b": 0.19, "gap_deg": 84.0},
        {"pos": (0, -0.02, 1.42), "rx": 0.23, "ry_f": 0.16, "ry_b": 0.17, "gap_deg": 82.0, "harmonics": [(5, 0.04, 0.2)]},
        {"pos": (0, -0.03, 1.14), "rx": 0.20, "ry_f": 0.14, "ry_b": 0.16, "gap_deg": 56.0},
        {"pos": (0, -0.05, 0.88), "rx": 0.26, "ry_f": 0.16, "ry_b": 0.22, "gap_deg": 68.0, "harmonics": [(6, 0.05, 0.4)]},
        {"pos": (0, -0.07, 0.58), "rx": 0.34, "ry_f": 0.19, "ry_b": 0.29, "gap_deg": 84.0, "harmonics": [(8, 0.08, 1.1)]},
        {"pos": (0, -0.09, 0.26), "rx": 0.41, "ry_f": 0.21, "ry_b": 0.36, "gap_deg": 98.0, "harmonics": [(9, 0.11, 2.0)]},
    ], mat=m_coat, parent=torso, segs=30, thickness=0.011, tear_end_amp=0.110, tear_lapel_amp=0.03, tear_seed=43)

    for sx, nm in ((-1, "L"), (1, "R")):
        spline_tube(f"LapelSteelTrim{nm}", [
            (sx * 0.095, 0.135, 1.14), (sx * 0.155, 0.155, 1.44), (sx * 0.185, 0.125, 1.72)
        ], radius=0.011, mat=m_steel, parent=torso, segs=8)

    prim_mesh("WraithBelt", "CYLINDER", (0, -0.02, 1.14), (0.42, 0.33, 0.068), mat=m_trim, parent=torso, bevel=0.008, verts=24)
    prim_mesh("WraithBuckle", "CUBE", (0, 0.150, 1.14), (0.080, 0.026, 0.076), mat=m_steel, parent=torso, bevel=0.006)

    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"OfficerPauldron{nm}", "CUBE", (sx * 0.30, 0.0, 1.72), (0.21, 0.25, 0.070),
                  rot=(0, sx * 0.28, 0), mat=m_steel, parent=torso, bevel=0.012)
        cx, cy, cz = sx * 0.29, -0.04, 1.83
        seg_limb(f"TeslaRod{nm}", (cx, cy, cz - 0.06), (cx + sx * 0.045, cy - 0.02, cz + 0.18),
                 0.024, 0.016, mat=m_steel, parent=torso, verts=10)
        for ci in range(4):
            frac = ci / 3.0
            rx_p = cx + sx * 0.045 * frac
            rz_p = cz - 0.01 + 0.16 * frac
            bpy.ops.mesh.primitive_torus_add(major_radius=0.048 - ci * 0.004, minor_radius=0.0085,
                                             major_segments=16, minor_segments=6,
                                             location=(rx_p, cy - 0.02 * frac, rz_p),
                                             rotation=(0, sx * 0.24, 0))
            tr = bpy.context.active_object
            tr.name = f"TeslaRing{nm}{ci}"
            tr.data.materials.append(m_copper if ci % 2 == 0 else m_volt)
            auto_uv(tr, 3.0)
            tr.parent = torso
            tr.matrix_parent_inverse = torso.matrix_world.inverted()
        prim_mesh(f"TeslaTerminal{nm}", "SPHERE", (cx + sx * 0.050, cy - 0.025, cz + 0.20),
                  (0.050, 0.050, 0.050), mat=m_volt, parent=torso, verts=12)
        # Crackling jagged cyan lightning arc leaping from Tesla terminal to collar!
        spline_tube(f"ShoulderVoltArc{nm}", [
            (cx + sx * 0.050, cy - 0.025, cz + 0.20),
            (sx * 0.22, 0.02, cz + 0.14),
            (sx * 0.17, -0.02, cz + 0.06),
        ], radius=0.006, mat=m_volt, parent=torso, segs=6)

    # 3. HEAD: OPEN-FRONT Pointed Reaper Hood (`loft_open_arc`) revealing Pale Skull, Blazing Cyan Eyes & Steel Jaw!
    head = add_pivot("Head", (0, 0.03, 1.84), parent=torso)
    hx, hy, hz = 0.0, 0.03, 1.84
    jaw_fixed = add_pivot("WraithJawFixed", (hx, hy + 0.04, hz + 0.08), parent=head)
    build_sculpted_undead_head("Wraith", head, jaw_fixed, (hx, hy, hz), m_bone, m_volt, m_bone, m_void, scale=1.00, gaunt=1.45)

    # Slotted Steel Respirator Jaw Mask over lower skull
    prim_mesh("WraithJawMask", "CUBE", (hx, hy + 0.128, hz + 0.085), (0.122, 0.088, 0.078),
              rot=(0.15, 0, 0), mat=m_steel, parent=head, bevel=0.012)
    for vi in (-0.032, 0.0, 0.032):
        prim_mesh(f"JawSlot_{vi:+.2f}", "CUBE", (hx + vi, hy + 0.172, hz + 0.085), (0.010, 0.012, 0.042),
                  rot=(0.15, 0, 0), mat=m_volt, parent=head)

    # Dark inner shadow sphere behind cranium + OPEN-FRONT Pointed Reaper Hood!
    prim_mesh("HoodShadowBack", "SPHERE", (hx, hy - 0.02, hz + 0.15), (0.24, 0.24, 0.26), mat=m_void, parent=head, verts=16)
    loft_open_arc("ReaperHood", [
        {"pos": (hx, hy - 0.03, hz - 0.03), "rx": 0.185, "ry_f": 0.155, "ry_b": 0.185, "gap_deg": 92.0},
        {"pos": (hx, hy - 0.01, hz + 0.12), "rx": 0.175, "ry_f": 0.165, "ry_b": 0.195, "gap_deg": 124.0, "harmonics": [(4, 0.05, 0.0)]},
        {"pos": (hx, hy + 0.03, hz + 0.24), "rx": 0.135, "ry_f": 0.185, "ry_b": 0.185, "gap_deg": 88.0},
        {"pos": (hx, hy - 0.05, hz + 0.33), "rx": 0.052, "ry_f": 0.085, "ry_b": 0.135, "gap_deg": 24.0},
    ], mat=m_coat, parent=head, segs=24, thickness=0.012, tear_lapel_amp=0.02, tear_seed=51)

    # 4. TWIN CURVED HIGH-VOLTAGE ARC REAPER KATANAS (`ArmL` & `ArmR` at (±0.32, 0.03, 1.68))!
    for sx, nm in ((-1, "L"), (1, "R")):
        arm = add_pivot("Arm" + nm, (sx * 0.32, 0.03, 1.68), parent=torso)
        loft_anatomical(f"WraithArm{nm}", [
            {"pos": (sx * 0.32, 0.03, 1.68), "rx": 0.080, "ry_f": 0.080, "ry_b": 0.080},
            {"pos": (sx * 0.35, 0.18, 1.42), "rx": 0.070, "ry_f": 0.070, "ry_b": 0.070},
            {"pos": (sx * 0.32, 0.40, 1.24), "rx": 0.056, "ry_f": 0.058, "ry_b": 0.058},
        ], mat=m_coat, parent=arm, segs=16, subsurf=1)

        for ci in range(3):
            frac = ci / 2.0
            bpy.ops.mesh.primitive_torus_add(
                major_radius=0.062 - ci * 0.003, minor_radius=0.008, major_segments=14, minor_segments=6,
                location=(sx * (0.345 - 0.018 * frac), 0.26 + 0.11 * frac, 1.36 - 0.09 * frac),
                rotation=(math.radians(52), 0, 0)
            )
            br = bpy.context.active_object
            br.name = f"WristCoil{nm}{ci}"
            br.data.materials.append(m_volt if ci == 1 else m_copper)
            auto_uv(br, 3.0)
            br.parent = arm
            br.matrix_parent_inverse = arm.matrix_world.inverted()

        prim_mesh(f"WraithGauntlet{nm}", "SPHERE", (sx * 0.315, 0.44, 1.20), (0.090, 0.105, 0.086), mat=m_steel, parent=arm, verts=14)

        hx_b = sx * 0.315
        seg_limb(f"KatanaHilt{nm}", (hx_b, 0.34, 1.24), (hx_b, 0.52, 1.17), 0.022, 0.024, mat=m_trim, parent=arm, verts=10)
        prim_mesh(f"KatanaPommel{nm}", "SPHERE", (hx_b, 0.33, 1.245), (0.048, 0.048, 0.048), mat=m_volt, parent=arm, verts=12)
        prim_mesh(f"KatanaGuard{nm}", "CUBE", (hx_b, 0.53, 1.165), (0.105, 0.034, 0.135), rot=(0.35, 0, 0), mat=m_steel, parent=arm, bevel=0.008)

        blade_pts = [
            ((hx_b, 0.54, 1.165), 0.009, 0.040, 0.024),
            ((hx_b - sx * 0.008, 0.78, 1.10), 0.008, 0.044, 0.024),
            ((hx_b - sx * 0.015, 1.04, 1.06), 0.007, 0.040, 0.020),
            ((hx_b - sx * 0.020, 1.24, 1.05), 0.005, 0.026, 0.014),
            ((hx_b - sx * 0.022, 1.36, 1.075), 0.0015, 0.004, 0.004),
        ]
        loft_anatomical(f"ArcBladeSteel{nm}", blade_pts, mat=m_steel, parent=arm, segs=8, subsurf=0)

        edge_pts = [
            ((hx_b, 0.55, 1.128), 0.0045, 0.015, 0.015),
            ((hx_b - sx * 0.008, 0.79, 1.060), 0.0045, 0.016, 0.016),
            ((hx_b - sx * 0.015, 1.05, 1.022), 0.004, 0.014, 0.014),
            ((hx_b - sx * 0.020, 1.25, 1.020), 0.003, 0.011, 0.011),
            ((hx_b - sx * 0.022, 1.37, 1.070), 0.001, 0.003, 0.003),
        ]
        loft_anatomical(f"ArcBladePlasma{nm}", edge_pts, mat=m_volt, parent=arm, segs=8, subsurf=0)

    # 5. LEGS: Thicker Officer Breeches, Armored Thigh/Shin Greaves & Volt-Spur Jackboots!
    for sx, nm in ((-1, "L"), (1, "R")):
        leg = add_pivot("Leg" + nm, (sx * 0.155, 0, 1.00), parent=root)
        loft_anatomical(f"WraithLeg{nm}", [
            {"pos": (sx * 0.155, 0, 1.00), "rx": 0.118, "ry_f": 0.122, "ry_b": 0.128},
            {"pos": (sx * 0.155, 0.01, 0.54), "rx": 0.092, "ry_f": 0.095, "ry_b": 0.095},
            {"pos": (sx * 0.155, 0.0, 0.12), "rx": 0.074, "ry_f": 0.076, "ry_b": 0.078},
        ], mat=m_trim, parent=leg, segs=18, subsurf=1)
        prim_mesh(f"KneeArmor{nm}", "CUBE", (sx * 0.155, 0.092, 0.55), (0.120, 0.048, 0.135), mat=m_steel, parent=leg, bevel=0.015)
        prim_mesh(f"ShinGreave{nm}", "CUBE", (sx * 0.155, 0.076, 0.34), (0.105, 0.042, 0.28), mat=m_steel, parent=leg, bevel=0.014)
        loft_anatomical(f"JackBoot{nm}", [
            {"pos": (sx * 0.155, -0.055, 0.055), "rx": 0.072, "ry_f": 0.074, "ry_b": 0.066},
            {"pos": (sx * 0.155, 0.065, 0.050), "rx": 0.070, "ry_f": 0.064, "ry_b": 0.056},
            {"pos": (sx * 0.155, 0.198, 0.040), "rx": 0.060, "ry_f": 0.046, "ry_b": 0.038},
        ], mat=m_steel, parent=leg, segs=16, subsurf=1)
        prim_mesh(f"BootSole{nm}", "CUBE", (sx * 0.155, 0.070, 0.015), (0.135, 0.285, 0.030), mat=m_void, parent=leg, bevel=0.006)
        prim_mesh(f"VoltSpur{nm}", "CUBE", (sx * 0.155, -0.105, 0.058), (0.050, 0.048, 0.024), mat=m_volt, parent=leg, bevel=0.004)

    merge_per_pivot()
    export_glb("boss_phantom.glb")


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    builders = {
        "gun": build_boss_gun_zombie,
        "gorilla": build_boss_gorilla,
        "necro": build_boss_necromancer,
        "panzer": build_boss_juggernaut,
        "phantom": build_boss_phantom,
    }
    for k in (only or list(builders.keys())):
        builders[k]()
        print("FINISHED BOSS MODEL:", k)
    print("ALL V7.1 BOSS MODELS GENERATED!")
