"""Second batch of Blender models: new guns, knife, grenade, Augment Furnace,
mystery crate, weapon forge and a wrecked truck.

Run with:  blender -b -P tools/generate_models_v2.py

Convention (same as generate_models.py): +Y is forward (-Z in Godot), +Z is up.
Gun sights sit on a common sight line so ADS offsets stay simple.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_models import add_part, add_pivot, clear_scene, export_glb, make_mat  # noqa: E402

R90 = math.radians(90)


def gun_mats(prefix):
    steel = make_mat(prefix + "Steel", (0.17, 0.18, 0.20, 1), metallic=0.86, roughness=0.32, tex_prefix="rusted_metal")
    dark = make_mat(prefix + "Dark", (0.08, 0.085, 0.095, 1), metallic=0.7, roughness=0.45)
    wood = make_mat(prefix + "Wood", (0.32, 0.17, 0.09, 1), roughness=0.66, tex_prefix="wood_planks")
    sight = make_mat(prefix + "Sight", (0.25, 1.0, 0.45, 1), roughness=0.2, emission=(0.25, 1.0, 0.45), emission_strength=4.0)
    return steel, dark, wood, sight


def build_smg():
    clear_scene()
    steel, dark, wood, sight = gun_mats("Smg")
    r = add_pivot("Root")
    add_part("Receiver", "CUBE", scale=(0.05, 0.30, 0.07), mat=steel, parent=r, bevel=0.006, offset=(0, 0.06, 0.03))
    add_part("Shroud", "CYLINDER", scale=(0.056, 0.056, 0.16), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.004, offset=(0, 0.28, 0.035))
    add_part("Barrel", "CYLINDER", scale=(0.024, 0.024, 0.10), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.002, offset=(0, 0.39, 0.035))
    add_part("Magazine", "CUBE", scale=(0.03, 0.05, 0.20), rot=(math.radians(8), 0, 0), mat=dark, parent=r, bevel=0.004, offset=(0, 0.11, -0.10))
    add_part("Grip", "CUBE", scale=(0.034, 0.055, 0.11), rot=(math.radians(16), 0, 0), mat=dark, parent=r, bevel=0.006, offset=(0, -0.05, -0.05))
    for sx in (-0.018, 0.018):
        add_part("StockRod", "CUBE", scale=(0.008, 0.24, 0.012), mat=steel, parent=r, bevel=0.002, offset=(sx, -0.21, 0.03))
    add_part("ButtPlate", "CUBE", scale=(0.05, 0.012, 0.08), mat=dark, parent=r, bevel=0.003, offset=(0, -0.33, 0.02))
    add_part("ChargingHandle", "CUBE", scale=(0.03, 0.02, 0.012), mat=steel, parent=r, bevel=0.002, offset=(0.03, 0.12, 0.05))
    for sx in (-0.012, 0.012):
        add_part("RearSight", "CUBE", scale=(0.007, 0.012, 0.014), mat=sight, parent=r, bevel=0.001, offset=(sx, -0.06, 0.068))
    add_part("FrontSight", "CUBE", scale=(0.006, 0.012, 0.018), mat=sight, parent=r, bevel=0.001, offset=(0, 0.30, 0.066))
    export_glb("vm_smg.glb")


def build_lmg():
    clear_scene()
    steel, dark, wood, sight = gun_mats("Lmg")
    ammo = make_mat("LmgBrass", (0.75, 0.55, 0.2, 1), metallic=0.9, roughness=0.3)
    r = add_pivot("Root")
    add_part("Receiver", "CUBE", scale=(0.07, 0.42, 0.09), mat=steel, parent=r, bevel=0.008, offset=(0, 0.05, 0.03))
    add_part("FeedCover", "CUBE", scale=(0.074, 0.20, 0.024), mat=dark, parent=r, bevel=0.004, offset=(0, 0.0, 0.086))
    add_part("Barrel", "CYLINDER", scale=(0.04, 0.04, 0.52), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.003, offset=(0, 0.52, 0.04))
    add_part("HeatShield", "CYLINDER", scale=(0.066, 0.066, 0.30), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.004, offset=(0, 0.40, 0.04))
    add_part("BoxMag", "CUBE", scale=(0.12, 0.12, 0.13), mat=dark, parent=r, bevel=0.01, offset=(-0.02, 0.06, -0.09))
    for i in range(4):
        add_part("Belt%d" % i, "CYLINDER", scale=(0.014, 0.014, 0.05), rot=(0, R90, 0), mat=ammo, parent=r, bevel=0.002, offset=(0.05, 0.02 + i * 0.022, 0.03 - i * 0.01))
    add_part("CarryHandle", "CUBE", scale=(0.014, 0.16, 0.012), mat=dark, parent=r, bevel=0.003, offset=(0, 0.24, 0.13))
    for y in (0.17, 0.31):
        add_part("HandlePost", "CUBE", scale=(0.014, 0.014, 0.05), mat=dark, parent=r, bevel=0.002, offset=(0, y, 0.105))
    for sx in (-0.02, 0.02):
        add_part("Bipod", "CYLINDER", scale=(0.012, 0.012, 0.28), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.001, offset=(sx, 0.58, 0.0))
    add_part("Stock", "CUBE", scale=(0.05, 0.26, 0.10), mat=dark, parent=r, bevel=0.01, offset=(0, -0.28, 0.01))
    add_part("Grip", "CUBE", scale=(0.036, 0.055, 0.11), rot=(math.radians(16), 0, 0), mat=dark, parent=r, bevel=0.006, offset=(0, -0.10, -0.06))
    for sx in (-0.012, 0.012):
        add_part("RearSight", "CUBE", scale=(0.007, 0.012, 0.016), mat=sight, parent=r, bevel=0.001, offset=(sx, -0.08, 0.104))
    add_part("FrontPost", "CUBE", scale=(0.014, 0.014, 0.07), mat=dark, parent=r, bevel=0.002, offset=(0, 0.74, 0.075))
    add_part("FrontSight", "CUBE", scale=(0.006, 0.012, 0.016), mat=sight, parent=r, bevel=0.001, offset=(0, 0.74, 0.104))
    export_glb("vm_lmg.glb")


def build_sniper():
    clear_scene()
    steel, dark, wood, sight = gun_mats("Snp")
    lens = make_mat("SnpLens", (0.2, 0.55, 1.0, 1), roughness=0.05, emission=(0.2, 0.55, 1.0), emission_strength=2.5)
    r = add_pivot("Root")
    add_part("Receiver", "CUBE", scale=(0.055, 0.32, 0.07), mat=steel, parent=r, bevel=0.006, offset=(0, 0.02, 0.03))
    add_part("Barrel", "CYLINDER", scale=(0.034, 0.034, 0.74), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.002, offset=(0, 0.55, 0.04))
    add_part("MuzzleBrake", "CUBE", scale=(0.05, 0.07, 0.04), mat=dark, parent=r, bevel=0.005, offset=(0, 0.94, 0.04))
    add_part("Stock", "CUBE", scale=(0.05, 0.38, 0.11), mat=wood, parent=r, bevel=0.012, offset=(0, -0.30, -0.005))
    add_part("Forend", "CUBE", scale=(0.052, 0.30, 0.05), mat=wood, parent=r, bevel=0.01, offset=(0, 0.28, 0.008))
    add_part("ScopeTube", "CYLINDER", scale=(0.044, 0.044, 0.36), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.003, offset=(0, 0.06, 0.115))
    add_part("ScopeBellF", "CYLINDER", scale=(0.064, 0.064, 0.08), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.004, offset=(0, 0.26, 0.115))
    add_part("ScopeBellR", "CYLINDER", scale=(0.056, 0.056, 0.06), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.004, offset=(0, -0.13, 0.115))
    add_part("Lens", "CYLINDER", scale=(0.054, 0.054, 0.006), rot=(R90, 0, 0), mat=lens, parent=r, bevel=0.0, offset=(0, 0.302, 0.115))
    for y in (-0.02, 0.14):
        add_part("Mount", "CUBE", scale=(0.03, 0.02, 0.05), mat=steel, parent=r, bevel=0.003, offset=(0, y, 0.08))
    add_part("BoltArm", "CYLINDER", scale=(0.012, 0.012, 0.07), rot=(0, R90, 0), mat=steel, parent=r, bevel=0.001, offset=(0.05, -0.05, 0.05))
    add_part("BoltKnob", "SPHERE", scale=(0.026, 0.026, 0.026), mat=steel, parent=r, bevel=0.0, offset=(0.088, -0.05, 0.05))
    add_part("Mag", "CUBE", scale=(0.03, 0.06, 0.06), mat=dark, parent=r, bevel=0.004, offset=(0, 0.06, -0.025))
    add_part("Grip", "CUBE", scale=(0.034, 0.05, 0.10), rot=(math.radians(18), 0, 0), mat=wood, parent=r, bevel=0.006, offset=(0, -0.12, -0.06))
    export_glb("vm_sniper.glb")


def build_revolver():
    clear_scene()
    steel, dark, wood, sight = gun_mats("Rev")
    red = make_mat("RevSight", (1.0, 0.3, 0.2, 1), roughness=0.2, emission=(1.0, 0.3, 0.2), emission_strength=4.0)
    r = add_pivot("Root")
    add_part("Frame", "CUBE", scale=(0.036, 0.14, 0.06), mat=steel, parent=r, bevel=0.006, offset=(0, 0.02, 0.03))
    add_part("Cylinder", "CYLINDER", scale=(0.068, 0.068, 0.065), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.006, offset=(0, 0.035, 0.028))
    add_part("Barrel", "CYLINDER", scale=(0.03, 0.03, 0.21), rot=(R90, 0, 0), mat=steel, parent=r, bevel=0.002, offset=(0, 0.19, 0.045))
    add_part("UnderLug", "CUBE", scale=(0.022, 0.20, 0.022), mat=steel, parent=r, bevel=0.003, offset=(0, 0.19, 0.024))
    add_part("Grip", "CUBE", scale=(0.034, 0.05, 0.12), rot=(math.radians(22), 0, 0), mat=wood, parent=r, bevel=0.008, offset=(0, -0.07, -0.05))
    add_part("Hammer", "CUBE", scale=(0.01, 0.025, 0.025), rot=(math.radians(-30), 0, 0), mat=dark, parent=r, bevel=0.002, offset=(0, -0.055, 0.07))
    add_part("TriggerGuard", "CUBE", scale=(0.008, 0.05, 0.008), mat=steel, parent=r, bevel=0.002, offset=(0, 0.0, -0.015))
    add_part("FrontSight", "CUBE", scale=(0.006, 0.014, 0.014), mat=red, parent=r, bevel=0.001, offset=(0, 0.285, 0.066))
    for sx in (-0.01, 0.01):
        add_part("RearSight", "CUBE", scale=(0.006, 0.01, 0.012), mat=steel, parent=r, bevel=0.001, offset=(sx, -0.03, 0.066))
    export_glb("vm_revolver.glb")


def build_volt():
    clear_scene()
    dark = make_mat("VoltDark", (0.07, 0.08, 0.10, 1), metallic=0.8, roughness=0.35, tex_prefix="rusted_metal")
    copper = make_mat("VoltCopper", (0.72, 0.38, 0.18, 1), metallic=0.95, roughness=0.3)
    glow = make_mat("VoltGlow", (0.25, 0.65, 1.0, 1), roughness=0.1, emission=(0.25, 0.65, 1.0), emission_strength=1.6)
    r = add_pivot("Root")
    add_part("Body", "CYLINDER", scale=(0.10, 0.10, 0.40), rot=(R90, 0, 0), mat=dark, parent=r, bevel=0.01, offset=(0, 0.10, 0.02))
    for i in range(4):
        add_part("Coil%d" % i, "CYLINDER", scale=(0.13, 0.13, 0.02), rot=(R90, 0, 0), mat=copper if i % 2 else glow, parent=r, bevel=0.003, offset=(0, 0.08 + i * 0.07, 0.02))
    add_part("Emitter", "CONE", scale=(0.11, 0.11, 0.14), rot=(math.radians(-90), 0, 0), mat=copper, parent=r, bevel=0.0, offset=(0, 0.36, 0.02))
    add_part("EmitterTip", "SPHERE", scale=(0.05, 0.05, 0.05), mat=glow, parent=r, bevel=0.0, offset=(0, 0.43, 0.02))
    add_part("Tube", "CYLINDER", scale=(0.036, 0.036, 0.24), rot=(R90, 0, 0), mat=glow, parent=r, bevel=0.002, offset=(0, 0.08, 0.085))
    add_part("Battery", "CUBE", scale=(0.08, 0.11, 0.09), mat=dark, parent=r, bevel=0.01, offset=(0, -0.16, 0.02))
    add_part("BatteryCell", "CUBE", scale=(0.084, 0.03, 0.05), mat=glow, parent=r, bevel=0.004, offset=(0, -0.13, 0.02))
    add_part("Grip", "CUBE", scale=(0.036, 0.055, 0.11), rot=(math.radians(16), 0, 0), mat=dark, parent=r, bevel=0.006, offset=(0, -0.03, -0.07))
    add_part("SightRing", "CYLINDER", scale=(0.02, 0.02, 0.01), rot=(R90, 0, 0), mat=glow, parent=r, bevel=0.0, offset=(0, 0.28, 0.1))
    export_glb("vm_volt.glb")


def build_knife():
    clear_scene()
    blade = make_mat("KnifeBlade", (0.75, 0.77, 0.8, 1), metallic=0.95, roughness=0.2)
    grip = make_mat("KnifeGrip", (0.12, 0.10, 0.08, 1), roughness=0.8, tex_prefix="wood_planks")
    r = add_pivot("Root")
    add_part("Handle", "CYLINDER", scale=(0.032, 0.032, 0.11), rot=(R90, 0, 0), mat=grip, parent=r, bevel=0.003, offset=(0, 0.0, 0))
    add_part("Guard", "CUBE", scale=(0.06, 0.012, 0.024), mat=blade, parent=r, bevel=0.003, offset=(0, 0.06, 0))
    add_part("Blade", "CUBE", scale=(0.005, 0.15, 0.032), mat=blade, parent=r, bevel=0.0015, offset=(0, 0.14, 0.002))
    add_part("Tip", "CONE", scale=(0.03, 0.006, 0.05), rot=(math.radians(-90), 0, 0), mat=blade, parent=r, bevel=0.0, offset=(0, 0.235, 0.002))
    export_glb("vm_knife.glb")


def build_grenade():
    clear_scene()
    body = make_mat("NadeBody", (0.22, 0.27, 0.16, 1), metallic=0.4, roughness=0.6, tex_prefix="rusted_metal")
    steel = make_mat("NadeSteel", (0.6, 0.6, 0.62, 1), metallic=0.9, roughness=0.3)
    r = add_pivot("Root")
    add_part("Body", "SPHERE", scale=(0.07, 0.07, 0.09), mat=body, parent=r, bevel=0.0, offset=(0, 0, 0))
    add_part("Fuze", "CYLINDER", scale=(0.03, 0.03, 0.03), mat=steel, parent=r, bevel=0.002, offset=(0, 0, 0.055))
    add_part("Lever", "CUBE", scale=(0.012, 0.016, 0.08), mat=steel, parent=r, bevel=0.002, offset=(0.03, 0, 0.03))
    export_glb("prop_grenade.glb")


def build_augment_furnace():
    """Stat upgrade machine. Front faces +Y (-Z in Godot). Origin on the floor."""
    clear_scene()
    iron = make_mat("FurnIron", (0.22, 0.2, 0.2, 1), metallic=0.75, roughness=0.55, tex_prefix="rusted_metal")
    brick = make_mat("FurnBrick", (0.45, 0.25, 0.2, 1), roughness=0.85, tex_prefix="concrete")
    fire = make_mat("FurnFire", (1.0, 0.45, 0.1, 1), roughness=0.3, emission=(1.0, 0.42, 0.08), emission_strength=7.0)
    blood = make_mat("FurnSerum", (0.95, 0.12, 0.1, 1), roughness=0.1, emission=(0.95, 0.12, 0.08), emission_strength=4.0)
    brass = make_mat("FurnBrass", (0.8, 0.6, 0.25, 1), metallic=0.95, roughness=0.3)
    r = add_pivot("Root")
    add_part("Base", "CUBE", scale=(1.6, 1.0, 0.25), mat=iron, parent=r, bevel=0.03, offset=(0, 0, 0.125))
    add_part("Body", "CUBE", scale=(1.4, 0.9, 1.5), mat=brick, parent=r, bevel=0.04, offset=(0, 0, 1.0))
    add_part("Mouth", "CUBE", scale=(0.8, 0.06, 0.5), mat=fire, parent=r, bevel=0.02, offset=(0, 0.44, 0.75))
    add_part("MouthFrame", "CUBE", scale=(0.95, 0.05, 0.08), mat=iron, parent=r, bevel=0.01, offset=(0, 0.47, 1.04))
    for i in range(5):
        add_part("Grate%d" % i, "CUBE", scale=(0.03, 0.04, 0.5), mat=iron, parent=r, bevel=0.004, offset=(-0.3 + i * 0.15, 0.48, 0.75))
    add_part("CoinSlot", "CUBE", scale=(0.3, 0.08, 0.05), mat=brass, parent=r, bevel=0.01, offset=(0, 0.47, 1.35))
    add_part("Hood", "CUBE", scale=(1.55, 1.0, 0.18), mat=iron, parent=r, bevel=0.03, offset=(0, 0, 1.84))
    add_part("Stack", "CYLINDER", scale=(0.32, 0.32, 1.1), mat=iron, parent=r, bevel=0.01, offset=(0.35, -0.1, 2.45))
    add_part("StackCap", "CYLINDER", scale=(0.42, 0.42, 0.08), mat=iron, parent=r, bevel=0.01, offset=(0.35, -0.1, 3.0))
    for i, x in enumerate((-0.55, -0.35, -0.15)):
        add_part("Vial%d" % i, "CYLINDER", scale=(0.12, 0.12, 0.42), mat=blood, parent=r, bevel=0.01, offset=(x, 0.15, 2.15))
        add_part("VialCap%d" % i, "CYLINDER", scale=(0.15, 0.15, 0.05), mat=brass, parent=r, bevel=0.005, offset=(x, 0.15, 2.38))
    for i, x in enumerate((-0.45, 0.45)):
        add_part("Gauge%d" % i, "CYLINDER", scale=(0.2, 0.2, 0.04), rot=(R90, 0, 0), mat=brass, parent=r, bevel=0.005, offset=(x, 0.46, 1.4))
        add_part("GaugeFace%d" % i, "CYLINDER", scale=(0.16, 0.16, 0.01), rot=(R90, 0, 0), mat=fire, parent=r, bevel=0.0, offset=(x, 0.485, 1.4))
    for sx in (-0.72, 0.72):
        add_part("Pipe", "CYLINDER", scale=(0.08, 0.08, 1.6), mat=brass, parent=r, bevel=0.005, offset=(sx, 0.3, 1.0))
    export_glb("prop_augment_furnace.glb")


def build_mystery_crate():
    """Origin on the floor, front faces +Y. Lid hinges on 'LidPivot' at the back top edge."""
    clear_scene()
    wood = make_mat("CrateWood", (0.42, 0.26, 0.14, 1), roughness=0.75, tex_prefix="wood_planks")
    iron = make_mat("CrateIron", (0.2, 0.2, 0.22, 1), metallic=0.8, roughness=0.45, tex_prefix="rusted_metal")
    glow = make_mat("CrateGlyph", (0.4, 0.75, 1.0, 1), roughness=0.2, emission=(0.4, 0.75, 1.0), emission_strength=5.0)
    r = add_pivot("Root")
    add_part("Body", "CUBE", scale=(1.6, 0.72, 0.62), mat=wood, parent=r, bevel=0.02, offset=(0, 0, 0.31))
    for x in (-0.7, 0.0, 0.7):
        add_part("Band", "CUBE", scale=(0.06, 0.74, 0.64), mat=iron, parent=r, bevel=0.005, offset=(x, 0, 0.31))
    # Glowing glyphs on the front
    for i, (x, z, sx, sz) in enumerate([(-0.35, 0.42, 0.14, 0.03), (-0.29, 0.36, 0.03, 0.09), (-0.35, 0.3, 0.1, 0.03), (-0.35, 0.18, 0.03, 0.03),
                                        (0.35, 0.42, 0.14, 0.03), (0.41, 0.36, 0.03, 0.09), (0.35, 0.3, 0.1, 0.03), (0.35, 0.18, 0.03, 0.03)]):
        add_part("Glyph%d" % i, "CUBE", scale=(sx, 0.02, sz), mat=glow, parent=r, bevel=0.002, offset=(x, 0.365, z))
    lid = add_pivot("LidPivot", (0, -0.36, 0.62), parent=r)
    add_part("Lid", "CUBE", (0, -0.36, 0.62), scale=(1.62, 0.74, 0.1), mat=wood, parent=lid, bevel=0.02, offset=(0, 0.36, 0.05))
    for x in (-0.7, 0.0, 0.7):
        add_part("LidBand", "CUBE", (0, -0.36, 0.62), scale=(0.06, 0.76, 0.11), mat=iron, parent=lid, bevel=0.005, offset=(x, 0.36, 0.05))
    export_glb("prop_mystery_crate.glb")


def build_weapon_forge():
    clear_scene()
    iron = make_mat("ForgeIron", (0.18, 0.18, 0.2, 1), metallic=0.85, roughness=0.4, tex_prefix="rusted_metal")
    core = make_mat("ForgeCore", (0.7, 0.3, 1.0, 1), roughness=0.1, emission=(0.7, 0.3, 1.0), emission_strength=6.0)
    brass = make_mat("ForgeBrass", (0.8, 0.6, 0.25, 1), metallic=0.95, roughness=0.3)
    r = add_pivot("Root")
    add_part("Base", "CUBE", scale=(1.8, 1.0, 0.9), mat=iron, parent=r, bevel=0.04, offset=(0, 0, 0.45))
    add_part("Feeder", "CUBE", scale=(0.9, 0.5, 0.06), mat=brass, parent=r, bevel=0.01, offset=(0, 0.3, 0.92))
    for x in (-0.55, 0.55):
        add_part("Roller", "CYLINDER", scale=(0.3, 0.3, 0.95), rot=(R90, 0, 0), mat=iron, parent=r, bevel=0.01, offset=(x, 0, 1.15))
    add_part("Core", "SPHERE", scale=(0.5, 0.5, 0.5), mat=core, parent=r, bevel=0.0, offset=(0, -0.1, 1.35))
    add_part("Tower", "CUBE", scale=(0.7, 0.5, 1.2), mat=iron, parent=r, bevel=0.03, offset=(0, -0.3, 1.9))
    add_part("Vent", "CUBE", scale=(0.5, 0.04, 0.6), mat=core, parent=r, bevel=0.01, offset=(0, -0.04, 2.0))
    add_part("Chimney", "CYLINDER", scale=(0.22, 0.22, 0.6), mat=brass, parent=r, bevel=0.01, offset=(0, -0.3, 2.75))
    export_glb("prop_weapon_forge.glb")


def build_truck():
    """Wrecked army truck for the motor pool. Long axis along +Y. Origin on the floor."""
    clear_scene()
    paint = make_mat("TruckPaint", (0.24, 0.28, 0.18, 1), metallic=0.5, roughness=0.6, tex_prefix="rusted_metal")
    tire = make_mat("TruckTire", (0.05, 0.05, 0.05, 1), roughness=0.9)
    canvas = make_mat("TruckCanvas", (0.35, 0.33, 0.24, 1), roughness=0.95, tex_prefix="fabric")
    glass = make_mat("TruckGlass", (0.1, 0.12, 0.14, 1), metallic=0.2, roughness=0.1)
    r = add_pivot("Root")
    add_part("Chassis", "CUBE", scale=(2.2, 6.4, 0.4), mat=paint, parent=r, bevel=0.03, offset=(0, 0, 0.9))
    add_part("Cab", "CUBE", scale=(2.2, 1.8, 1.4), mat=paint, parent=r, bevel=0.06, offset=(0, 2.2, 1.8))
    add_part("Hood", "CUBE", scale=(2.0, 1.2, 0.8), mat=paint, parent=r, bevel=0.06, offset=(0, 3.4, 1.5))
    add_part("Windshield", "CUBE", scale=(1.9, 0.05, 0.6), mat=glass, parent=r, bevel=0.01, offset=(0, 3.1, 2.2))
    add_part("Bed", "CUBE", scale=(2.3, 4.0, 0.6), mat=paint, parent=r, bevel=0.03, offset=(0, -1.2, 1.4))
    add_part("Canvas", "CYLINDER", scale=(2.2, 3.8, 1.6), rot=(R90, 0, 0), mat=canvas, parent=r, bevel=0.0, offset=(0, -1.2, 1.9))
    for y in (2.6, -0.4, -2.4):
        for sx in (-1.05, 1.05):
            add_part("Tire", "CYLINDER", scale=(1.0, 1.0, 0.35), rot=(0, R90, 0), mat=tire, parent=r, bevel=0.03, offset=(sx, y, 0.5))
    export_glb("prop_truck.glb")


if __name__ == "__main__":
    build_smg()
    build_lmg()
    build_sniper()
    build_revolver()
    build_volt()
    build_knife()
    build_grenade()
    build_augment_furnace()
    build_mystery_crate()
    build_weapon_forge()
    build_truck()
    print("ALL V2 MODELS GENERATED")
