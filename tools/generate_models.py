import bpy
import bmesh
from mathutils import Euler
import math
import os

import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "assets", "models")
TEX_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "assets", "textures")
os.makedirs(OUT_DIR, exist_ok=True)


_tint_cache = {}
_img_cache = {}
MAX_TEX = 1024  # models stay at 1K even where the source map is a 2K scan


def clear_scene():
    _tint_cache.clear()  # images die with the old scene
    _img_cache.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_tex(path, non_color=False):
    """Load a texture map once per scene, scaled down to MAX_TEX."""
    img = _img_cache.get(path)
    if img is None:
        img = bpy.data.images.load(path)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        if img.size[0] > MAX_TEX:
            img.scale(MAX_TEX, MAX_TEX * img.size[1] // img.size[0])
        _img_cache[path] = img
    return img


def tinted_albedo(tex_prefix, base_color):
    """The albedo map with the material's tint baked in. (The glTF exporter
    drops a Multiply node, which left tinted parts showing the raw texture.)"""
    key = (tex_prefix, tuple(round(c, 3) for c in base_color[:3]))
    img = _tint_cache.get(key)
    if img is None:
        src = load_tex(os.path.join(TEX_DIR, f"{tex_prefix}_albedo.png"))
        w, h = src.size
        px = np.empty(w * h * 4, np.float32)
        src.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        tint = np.array([c ** (1 / 2.2) for c in base_color[:3]], np.float32)
        if max(base_color[:3]) - min(base_color[:3]) < 0.06:
            # Near-gray tint (steel, concrete): mostly drop the texture's hue
            gray = px[:, :3].mean(axis=1, keepdims=True)
            px[:, :3] = gray * 0.75 + px[:, :3] * 0.25
        px[:, :3] = px[:, :3] * tint * 1.15
        np.clip(px, 0, 1, out=px)
        img = bpy.data.images.new("%s_tint%d" % (tex_prefix, len(_tint_cache)), w, h)
        img.pixels.foreach_set(px.ravel())
        img.pack()
        _tint_cache[key] = img
    return img


def make_mat(name, base_color=(0.5, 0.5, 0.5, 1.0), metallic=0.0, roughness=0.7, emission=None, emission_strength=0.0, tex_prefix=None):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if tex_prefix:
        albedo_p = os.path.join(TEX_DIR, f"{tex_prefix}_albedo.png")
        rough_p = os.path.join(TEX_DIR, f"{tex_prefix}_rough.png")
        normal_p = os.path.join(TEX_DIR, f"{tex_prefix}_normal.png")
        if os.path.exists(albedo_p):
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = tinted_albedo(tex_prefix, base_color)
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if os.path.exists(rough_p):
            tr = nodes.new("ShaderNodeTexImage")
            tr.image = load_tex(rough_p, non_color=True)
            links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
        if os.path.exists(normal_p):
            tn = nodes.new("ShaderNodeTexImage")
            tn.image = load_tex(normal_p, non_color=True)
            nm = nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 1.0
            links.new(tn.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None and emission_strength > 0.0:
        key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[key].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_part(name, prim="CUBE", loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat=None, parent=None, bevel=0.04, subsurf=0, offset=(0, 0, 0)):
    """Create a mesh object at `loc` (pivot), rotating around its own center before applying world-space `offset`."""
    if prim == "CUBE":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=(0, 0, 0))
    elif prim == "SPHERE":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12, radius=0.5, location=loc, rotation=(0, 0, 0))
    elif prim == "CYLINDER":
        bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.5, depth=1.0, location=loc, rotation=(0, 0, 0))
    elif prim == "CONE":
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.5, radius2=0.04, depth=1.0, location=loc, rotation=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name

    # Scale -> Rotate around part center -> Translate by offset so `offset` is ALWAYS in parent axes!
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    if rot != (0, 0, 0):
        bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Euler(rot, "XYZ").to_matrix(), verts=bm.verts)
    if offset != (0, 0, 0):
        bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    bm.to_mesh(obj.data)
    bm.free()

    if bevel > 0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel
        bev.segments = 2
        bev.limit_method = "ANGLE"
    if subsurf > 0:
        sub = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        sub.levels = subsurf
        sub.render_levels = subsurf

    # Apply modifiers & smart UV project
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


def add_pivot(name, loc=(0, 0, 0), parent=None):
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.location = loc
    if parent:
        empty.parent = parent
        empty.matrix_parent_inverse = parent.matrix_world.inverted()
    return empty


def export_glb(filename):
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="WEBP",
        export_image_quality=90,
    )
    print("Exported:", path)


# ---------------------------------------------------------------------------
# 1. STANDARD ZOMBIE WALKER (Facing +Y in Blender -> -Z in Godot)
# ---------------------------------------------------------------------------
def build_zombie_walker():
    clear_scene()
    m_skin = make_mat("ZombieSkin", (0.58, 0.64, 0.50, 1), roughness=0.72, tex_prefix="zombie_skin")
    m_coat = make_mat("TatteredCoat", (0.20, 0.22, 0.19, 1), roughness=0.88, tex_prefix="fabric")
    m_pants = make_mat("TornPants", (0.15, 0.16, 0.18, 1), roughness=0.90)
    m_blood = make_mat("DriedBlood", (0.38, 0.05, 0.05, 1), roughness=0.38)
    m_eye = make_mat("ZombieEye", (1.0, 0.68, 0.1, 1), roughness=0.2, emission=(1.0, 0.62, 0.08), emission_strength=4.5)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 0.96), parent=root)
    add_part("ChestMesh", "CUBE", (0, 0, 0.96), (0.46, 0.27, 0.54), mat=m_coat, parent=torso, bevel=0.06, offset=(0, 0.02, 0.24))
    add_part("PelvisMesh", "CUBE", (0, 0, 0.96), (0.40, 0.24, 0.18), mat=m_pants, parent=torso, bevel=0.04, offset=(0, 0, -0.04))
    add_part("ChestWound", "SPHERE", (0, 0, 0.96), (0.22, 0.10, 0.20), mat=m_blood, parent=torso, bevel=0.0, offset=(0.06, 0.13, 0.26))

    head = add_pivot("Head", (0, 0.05, 1.54), parent=torso)
    add_part("Skull", "SPHERE", (0, 0.05, 1.54), (0.27, 0.30, 0.32), mat=m_skin, parent=head, bevel=0.0, subsurf=1, offset=(0, 0.01, 0.13))
    add_part("Jaw", "CUBE", (0, 0.05, 1.54), (0.17, 0.18, 0.11), mat=m_skin, parent=head, bevel=0.03, offset=(0, 0.05, 0.0))
    add_part("EyeL", "SPHERE", (0, 0.05, 1.54), (0.045, 0.045, 0.035), mat=m_eye, parent=head, bevel=0, offset=(-0.06, 0.14, 0.15))
    add_part("EyeR", "SPHERE", (0, 0.05, 1.54), (0.045, 0.045, 0.035), mat=m_eye, parent=head, bevel=0, offset=(0.06, 0.14, 0.15))

    # Outstretched zombie arms (pivoted at shoulders)
    for side, sx in [("L", -1), ("R", 1)]:
        arm = add_pivot(f"Arm{side}", (sx * 0.29, 0.02, 1.42), parent=torso)
        add_part(f"UpperArm{side}", "CUBE", (sx * 0.29, 0.02, 1.42), (0.14, 0.34, 0.14), mat=m_coat, parent=arm, bevel=0.04, offset=(0, 0.16, -0.05))
        add_part(f"Forearm{side}", "CUBE", (sx * 0.29, 0.02, 1.42), (0.11, 0.34, 0.11), mat=m_skin, parent=arm, bevel=0.03, offset=(0, 0.44, -0.08))
        add_part(f"ClawHand{side}", "CUBE", (sx * 0.29, 0.02, 1.42), (0.12, 0.14, 0.07), mat=m_blood, parent=arm, bevel=0.02, offset=(0, 0.64, -0.10))

    for side, sx in [("L", -1), ("R", 1)]:
        leg = add_pivot(f"Leg{side}", (sx * 0.13, 0, 0.90), parent=root)
        add_part(f"Thigh{side}", "CUBE", (sx * 0.13, 0, 0.90), (0.17, 0.18, 0.44), mat=m_pants, parent=leg, bevel=0.04, offset=(0, 0, -0.22))
        add_part(f"Shin{side}", "CUBE", (sx * 0.13, 0, 0.90), (0.14, 0.15, 0.44), mat=m_pants, parent=leg, bevel=0.03, offset=(0, -0.01, -0.64))
        add_part(f"Boot{side}", "CUBE", (sx * 0.13, 0, 0.90), (0.15, 0.25, 0.11), mat=m_coat, parent=leg, bevel=0.03, offset=(0, 0.05, -0.85))

    export_glb("zombie_walker.glb")


# ---------------------------------------------------------------------------
# 2. ROUND 1 BOSS: ARMED ZOMBIE COMMANDO WITH GUN ("CORP. VEX")
# ---------------------------------------------------------------------------
def build_boss_gun_zombie():
    clear_scene()
    m_skin = make_mat("CommandoSkin", (0.52, 0.58, 0.48, 1), roughness=0.7, tex_prefix="zombie_skin")
    m_armor = make_mat("TacticalArmor", (0.16, 0.19, 0.16, 1), metallic=0.35, roughness=0.55, tex_prefix="rusted_metal")
    m_steel = make_mat("GunMetal", (0.14, 0.15, 0.17, 1), metallic=0.85, roughness=0.32, tex_prefix="rusted_metal")
    m_visor = make_mat("RedVisor", (1.0, 0.12, 0.10, 1), roughness=0.15, emission=(1.0, 0.10, 0.08), emission_strength=6.0)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.02), parent=root)
    add_part("VestTorso", "CUBE", (0, 0, 1.02), (0.56, 0.34, 0.62), mat=m_armor, parent=torso, bevel=0.06, offset=(0, 0, 0.28))
    add_part("ChestPlate", "CUBE", (0, 0, 1.02), (0.44, 0.09, 0.38), mat=m_steel, parent=torso, bevel=0.03, offset=(0, 0.18, 0.30))
    add_part("PauldronL", "SPHERE", (0, 0, 1.02), (0.24, 0.26, 0.22), mat=m_armor, parent=torso, bevel=0, offset=(-0.34, 0.0, 0.52))
    add_part("PauldronR", "SPHERE", (0, 0, 1.02), (0.24, 0.26, 0.22), mat=m_armor, parent=torso, bevel=0, offset=(0.34, 0.0, 0.52))

    head = add_pivot("Head", (0, 0.02, 1.66), parent=torso)
    add_part("Face", "SPHERE", (0, 0.02, 1.66), (0.28, 0.30, 0.32), mat=m_skin, parent=head, subsurf=1, bevel=0, offset=(0, 0, 0.14))
    add_part("Helmet", "SPHERE", (0, 0.02, 1.66), (0.35, 0.36, 0.26), mat=m_armor, parent=head, bevel=0, offset=(0, -0.01, 0.22))
    add_part("TacticalVisor", "CUBE", (0, 0.02, 1.66), (0.24, 0.08, 0.07), mat=m_visor, parent=head, bevel=0.02, offset=(0, 0.14, 0.17))

    # Left support arm & Right rifle-holding arm
    arm_l = add_pivot("ArmL", (-0.34, 0.04, 1.50), parent=torso)
    add_part("ArmMeshL", "CUBE", (-0.34, 0.04, 1.50), (0.16, 0.55, 0.16), mat=m_armor, parent=arm_l, bevel=0.04, offset=(0.12, 0.26, -0.08))

    arm_r = add_pivot("ArmR", (0.34, 0.04, 1.50), parent=torso)
    add_part("ArmMeshR", "CUBE", (0.34, 0.04, 1.50), (0.16, 0.48, 0.16), mat=m_armor, parent=arm_r, bevel=0.04, offset=(-0.06, 0.22, -0.08))
    # Assault Carbine attached to ArmR pointing +Y
    add_part("BossRifleBody", "CUBE", (0.34, 0.04, 1.50), (0.09, 0.68, 0.14), mat=m_steel, parent=arm_r, bevel=0.02, offset=(-0.10, 0.56, -0.06))
    add_part("BossRifleBarrel", "CYLINDER", (0.34, 0.04, 1.50), (0.04, 0.04, 0.42), rot=(math.radians(90), 0, 0), mat=m_steel, parent=arm_r, bevel=0.0, offset=(-0.10, 0.96, -0.04))
    add_part("BossRifleMag", "CUBE", (0.34, 0.04, 1.50), (0.06, 0.11, 0.22), mat=m_steel, parent=arm_r, bevel=0.015, offset=(-0.10, 0.58, -0.20))
    add_part("BossLaserModule", "CUBE", (0.34, 0.04, 1.50), (0.05, 0.10, 0.05), mat=m_visor, parent=arm_r, bevel=0.01, offset=(-0.10, 0.85, 0.01))

    for side, sx in [("L", -1), ("R", 1)]:
        leg = add_pivot(f"Leg{side}", (sx * 0.16, 0, 1.00), parent=root)
        add_part(f"LegUpper{side}", "CUBE", (sx * 0.16, 0, 1.00), (0.21, 0.22, 0.50), mat=m_armor, parent=leg, bevel=0.04, offset=(0, 0, -0.25))
        add_part(f"LegLower{side}", "CUBE", (sx * 0.16, 0, 1.00), (0.18, 0.20, 0.50), mat=m_steel, parent=leg, bevel=0.03, offset=(0, 0, -0.72))

    export_glb("boss_gun_zombie.glb")


# ---------------------------------------------------------------------------
# 3. ROUND 2 BOSS: MUTATED SILVERBACK GORILLA ("SUBJECT GOLIATH")
# ---------------------------------------------------------------------------
def build_boss_gorilla():
    clear_scene()
    m_fur = make_mat("GorillaFur", (0.26, 0.26, 0.29, 1), roughness=0.82, tex_prefix="gorilla_hide")
    m_silver = make_mat("SilverBack", (0.62, 0.65, 0.70, 1), roughness=0.68, tex_prefix="gorilla_hide")
    m_skin = make_mat("GorillaChest", (0.16, 0.15, 0.17, 1), roughness=0.58, tex_prefix="monster_scales")
    m_rage = make_mat("RageVeins", (1.0, 0.35, 0.06, 1), roughness=0.2, emission=(1.0, 0.32, 0.05), emission_strength=5.5)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.15), parent=root)
    # Massive hunched barrel chest + silverback hump
    add_part("BarrelChest", "SPHERE", (0, 0, 1.15), (1.28, 0.98, 1.18), mat=m_fur, parent=torso, subsurf=1, bevel=0, offset=(0, 0.08, 0.42))
    add_part("SilverHump", "SPHERE", (0, 0, 1.15), (1.08, 0.78, 0.85), mat=m_silver, parent=torso, subsurf=1, bevel=0, offset=(0, -0.18, 0.62))
    add_part("PectoralPlate", "CUBE", (0, 0, 1.15), (0.88, 0.32, 0.56), mat=m_skin, parent=torso, bevel=0.09, offset=(0, 0.36, 0.42))
    add_part("CoreScar", "CUBE", (0, 0, 1.15), (0.34, 0.08, 0.18), mat=m_rage, parent=torso, bevel=0.02, offset=(0, 0.51, 0.46))

    head = add_pivot("Head", (0, 0.34, 1.88), parent=torso)
    add_part("Cranium", "SPHERE", (0, 0.34, 1.88), (0.54, 0.58, 0.56), mat=m_fur, parent=head, subsurf=1, bevel=0, offset=(0, 0.06, 0.14))
    add_part("HeavyJaw", "CUBE", (0, 0.34, 1.88), (0.42, 0.44, 0.28), mat=m_skin, parent=head, bevel=0.06, offset=(0, 0.18, -0.04))
    add_part("BrowRidge", "CUBE", (0, 0.34, 1.88), (0.46, 0.22, 0.12), mat=m_silver, parent=head, bevel=0.04, offset=(0, 0.26, 0.22))
    add_part("RageEyes", "CUBE", (0, 0.34, 1.88), (0.30, 0.08, 0.06), mat=m_rage, parent=head, bevel=0.01, offset=(0, 0.31, 0.16))

    # Giant knuckle-dragging crusher arms pivoted at high shoulders
    for side, sx in [("L", -1), ("R", 1)]:
        arm = add_pivot(f"Arm{side}", (sx * 0.74, 0.12, 1.78), parent=torso)
        add_part(f"Deltoid{side}", "SPHERE", (sx * 0.74, 0.12, 1.78), (0.56, 0.54, 0.56), mat=m_silver, parent=arm, bevel=0, offset=(sx * 0.06, 0, -0.06))
        add_part(f"UpperArm{side}", "CUBE", (sx * 0.74, 0.12, 1.78), (0.38, 0.40, 0.72), mat=m_fur, parent=arm, bevel=0.08, offset=(sx * 0.08, 0.06, -0.46))
        add_part(f"MassiveForearm{side}", "CUBE", (sx * 0.74, 0.12, 1.78), (0.48, 0.50, 0.78), mat=m_fur, parent=arm, bevel=0.09, offset=(sx * 0.10, 0.18, -1.08))
        add_part(f"CrusherFist{side}", "CUBE", (sx * 0.74, 0.12, 1.78), (0.54, 0.56, 0.42), mat=m_skin, parent=arm, bevel=0.10, offset=(sx * 0.10, 0.24, -1.52))
        add_part(f"KnuckleGlow{side}", "CUBE", (sx * 0.74, 0.12, 1.78), (0.42, 0.12, 0.14), mat=m_rage, parent=arm, bevel=0.02, offset=(sx * 0.10, 0.50, -1.56))

    for side, sx in [("L", -1), ("R", 1)]:
        leg = add_pivot(f"Leg{side}", (sx * 0.36, -0.08, 1.05), parent=root)
        add_part(f"Haunch{side}", "CUBE", (sx * 0.36, -0.08, 1.05), (0.42, 0.46, 0.58), mat=m_fur, parent=leg, bevel=0.08, offset=(0, 0, -0.30))
        add_part(f"Calf{side}", "CUBE", (sx * 0.36, -0.08, 1.05), (0.36, 0.42, 0.52), mat=m_skin, parent=leg, bevel=0.07, offset=(0, 0.04, -0.78))

    export_glb("boss_gorilla.glb")


# ---------------------------------------------------------------------------
# 4. ROUND 3 BOSS: BLIGHT NECROMANCER (TOXIC HAZMAT MUTANT)
# ---------------------------------------------------------------------------
def build_boss_necromancer():
    clear_scene()
    m_suit = make_mat("HazmatSuit", (0.42, 0.40, 0.18, 1), roughness=0.65, tex_prefix="fabric")
    m_flesh = make_mat("MutantFlesh", (0.24, 0.32, 0.22, 1), roughness=0.55, tex_prefix="zombie_skin")
    m_acid = make_mat("AcidGlow", (0.25, 1.0, 0.18, 1), roughness=0.15, emission=(0.22, 1.0, 0.16), emission_strength=6.0)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.12), parent=root)
    add_part("HazmatBody", "CUBE", (0, 0, 1.12), (0.52, 0.34, 0.74), mat=m_suit, parent=torso, bevel=0.06, offset=(0, 0, 0.36))
    # Glowing dorsal toxic bio-tanks on back
    add_part("AcidTankL", "CYLINDER", (0, 0, 1.12), (0.22, 0.22, 0.62), mat=m_acid, parent=torso, bevel=0.03, offset=(-0.16, -0.24, 0.44))
    add_part("AcidTankR", "CYLINDER", (0, 0, 1.12), (0.22, 0.22, 0.62), mat=m_acid, parent=torso, bevel=0.03, offset=(0.16, -0.24, 0.44))

    head = add_pivot("Head", (0, 0.06, 1.88), parent=torso)
    add_part("GasMask", "SPHERE", (0, 0.06, 1.88), (0.32, 0.36, 0.36), mat=m_suit, parent=head, bevel=0, offset=(0, 0.02, 0.14))
    add_part("FilterSnout", "CYLINDER", (0, 0.06, 1.88), (0.14, 0.14, 0.20), rot=(math.radians(75), 0, 0), mat=m_flesh, parent=head, bevel=0.02, offset=(0, 0.20, 0.06))
    add_part("Goggles", "CUBE", (0, 0.06, 1.88), (0.24, 0.08, 0.09), mat=m_acid, parent=head, bevel=0.02, offset=(0, 0.16, 0.18))

    for side, sx in [("L", -1), ("R", 1)]:
        arm = add_pivot(f"Arm{side}", (sx * 0.34, 0.02, 1.74), parent=torso)
        add_part(f"TendrilArm{side}", "CUBE", (sx * 0.34, 0.02, 1.74), (0.15, 0.65, 0.15), mat=m_flesh, parent=arm, bevel=0.04, offset=(0, 0.30, -0.14))
        add_part(f"AcidSac{side}", "SPHERE", (sx * 0.34, 0.02, 1.74), (0.20, 0.22, 0.20), mat=m_acid, parent=arm, bevel=0, offset=(0, 0.62, -0.18))

    for side, sx in [("L", -1), ("R", 1)]:
        leg = add_pivot(f"Leg{side}", (sx * 0.16, 0, 1.10), parent=root)
        add_part(f"StiltLeg{side}", "CUBE", (sx * 0.16, 0, 1.10), (0.18, 0.20, 1.08), mat=m_suit, parent=leg, bevel=0.04, offset=(0, 0, -0.54))

    export_glb("boss_necromancer.glb")


# ---------------------------------------------------------------------------
# 5. ROUND 4 BOSS: PANZER IRON JUGGERNAUT
# ---------------------------------------------------------------------------
def build_boss_juggernaut():
    clear_scene()
    m_iron = make_mat("PanzerIron", (0.22, 0.20, 0.19, 1), metallic=0.82, roughness=0.42, tex_prefix="rusted_metal")
    m_brass = make_mat("PanzerBrass", (0.48, 0.36, 0.18, 1), metallic=0.75, roughness=0.38)
    m_core = make_mat("PanzerCore", (1.0, 0.72, 0.12, 1), roughness=0.15, emission=(1.0, 0.68, 0.10), emission_strength=7.0)

    root = add_pivot("Root", (0, 0, 0))
    torso = add_pivot("Torso", (0, 0, 1.18), parent=root)
    add_part("Chassis", "CUBE", (0, 0, 1.18), (0.92, 0.66, 0.86), mat=m_iron, parent=torso, bevel=0.08, offset=(0, 0, 0.42))
    add_part("PowerCoreRim", "CYLINDER", (0, 0, 1.18), (0.34, 0.34, 0.14), rot=(math.radians(90), 0, 0), mat=m_brass, parent=torso, bevel=0.02, offset=(0, 0.33, 0.46))
    add_part("PowerCore", "SPHERE", (0, 0, 1.18), (0.26, 0.16, 0.26), mat=m_core, parent=torso, bevel=0, offset=(0, 0.36, 0.46))

    head = add_pivot("Head", (0, 0.04, 2.04), parent=torso)
    add_part("DomeHelmet", "CYLINDER", (0, 0.04, 2.04), (0.42, 0.42, 0.38), mat=m_iron, parent=head, bevel=0.06, offset=(0, 0, 0.16))
    add_part("SlitVisor", "CUBE", (0, 0.04, 2.04), (0.30, 0.10, 0.08), mat=m_core, parent=head, bevel=0.01, offset=(0, 0.19, 0.18))

    arm_l = add_pivot("ArmL", (-0.58, 0, 1.82), parent=torso)
    add_part("ClawArmL", "CUBE", (-0.58, 0, 1.82), (0.32, 0.72, 0.32), mat=m_iron, parent=arm_l, bevel=0.06, offset=(0, 0.32, -0.18))

    arm_r = add_pivot("ArmR", (0.58, 0, 1.82), parent=torso)
    add_part("CannonShoulderR", "CUBE", (0.58, 0, 1.82), (0.34, 0.56, 0.34), mat=m_iron, parent=arm_r, bevel=0.06, offset=(0, 0.24, -0.14))
    add_part("FlameBarrel", "CYLINDER", (0.58, 0, 1.82), (0.18, 0.18, 0.65), rot=(math.radians(90), 0, 0), mat=m_brass, parent=arm_r, bevel=0.02, offset=(0, 0.68, -0.16))
    add_part("PilotTip", "SPHERE", (0.58, 0, 1.82), (0.14, 0.14, 0.14), mat=m_core, parent=arm_r, bevel=0, offset=(0, 1.02, -0.16))

    for side, sx in [("L", -1), ("R", 1)]:
        leg = add_pivot(f"Leg{side}", (sx * 0.28, 0, 1.15), parent=root)
        add_part(f"PistonLeg{side}", "CUBE", (sx * 0.28, 0, 1.15), (0.34, 0.38, 1.12), mat=m_iron, parent=leg, bevel=0.06, offset=(0, 0, -0.56))

    export_glb("boss_juggernaut.glb")


# ---------------------------------------------------------------------------
# 6. FIRST-PERSON WEAPONS & MONSTER CLAW VIEWMODEL (Facing +Y -> -Z in Godot)
# ---------------------------------------------------------------------------
def build_weapons():
    # --- M1911 Pistol ---
    clear_scene()
    m_steel = make_mat("SlideSteel", (0.20, 0.22, 0.25, 1), metallic=0.88, roughness=0.28, tex_prefix="rusted_metal")
    m_dark = make_mat("FrameDark", (0.10, 0.11, 0.13, 1), metallic=0.75, roughness=0.42)
    m_wood = make_mat("GripWood", (0.34, 0.18, 0.09, 1), roughness=0.65, tex_prefix="wood_planks")
    m_sight = make_mat("TritiumSight", (0.2, 1.0, 0.45, 1), roughness=0.2, emission=(0.2, 1.0, 0.45), emission_strength=4.0)

    root = add_pivot("Root", (0, 0, 0))
    add_part("Slide", "CUBE", (0, 0, 0), (0.042, 0.26, 0.046), mat=m_steel, parent=root, bevel=0.006, offset=(0, 0.08, 0.04))
    add_part("Frame", "CUBE", (0, 0, 0), (0.038, 0.22, 0.028), mat=m_dark, parent=root, bevel=0.004, offset=(0, 0.06, 0.008))
    add_part("Barrel", "CYLINDER", (0, 0, 0), (0.018, 0.018, 0.06), rot=(math.radians(90), 0, 0), mat=m_dark, parent=root, bevel=0.002, offset=(0, 0.22, 0.042))
    add_part("Grip", "CUBE", (0, 0, 0), (0.036, 0.062, 0.125), rot=(math.radians(16), 0, 0), mat=m_wood, parent=root, bevel=0.006, offset=(0, -0.02, -0.055))
    add_part("RearSightL", "CUBE", (0, 0, 0), (0.008, 0.012, 0.012), mat=m_sight, parent=root, bevel=0.001, offset=(-0.011, -0.035, 0.068))
    add_part("RearSightR", "CUBE", (0, 0, 0), (0.008, 0.012, 0.012), mat=m_sight, parent=root, bevel=0.001, offset=(0.011, -0.035, 0.068))
    add_part("FrontSight", "CUBE", (0, 0, 0), (0.006, 0.012, 0.013), mat=m_sight, parent=root, bevel=0.001, offset=(0, 0.195, 0.068))
    export_glb("vm_pistol.glb")

    # --- M14 / Commando Rifle ---
    clear_scene()
    m_steel = make_mat("RifleSteel", (0.17, 0.19, 0.21, 1), metallic=0.86, roughness=0.30, tex_prefix="rusted_metal")
    m_poly = make_mat("RifleStock", (0.28, 0.17, 0.10, 1), roughness=0.68, tex_prefix="wood_planks")
    m_sight = make_mat("RifleSight", (0.25, 1.0, 0.45, 1), roughness=0.2, emission=(0.25, 1.0, 0.45), emission_strength=4.0)

    root = add_pivot("Root", (0, 0, 0))
    add_part("Receiver", "CUBE", (0, 0, 0), (0.054, 0.34, 0.068), mat=m_steel, parent=root, bevel=0.007, offset=(0, 0.06, 0.03))
    add_part("Handguard", "CUBE", (0, 0, 0), (0.050, 0.32, 0.054), mat=m_poly, parent=root, bevel=0.008, offset=(0, 0.36, 0.026))
    add_part("Barrel", "CYLINDER", (0, 0, 0), (0.022, 0.022, 0.34), rot=(math.radians(90), 0, 0), mat=m_steel, parent=root, bevel=0.002, offset=(0, 0.62, 0.036))
    add_part("Stock", "CUBE", (0, 0, 0), (0.046, 0.28, 0.095), mat=m_poly, parent=root, bevel=0.009, offset=(0, -0.22, 0.0))
    add_part("Magazine", "CUBE", (0, 0, 0), (0.034, 0.075, 0.17), rot=(math.radians(-14), 0, 0), mat=m_steel, parent=root, bevel=0.004, offset=(0, 0.14, -0.075))
    add_part("RearAperture", "CUBE", (0, 0, 0), (0.028, 0.022, 0.022), mat=m_steel, parent=root, bevel=0.003, offset=(0, -0.06, 0.074))
    add_part("FrontPost", "CUBE", (0, 0, 0), (0.007, 0.012, 0.024), mat=m_sight, parent=root, bevel=0.001, offset=(0, 0.72, 0.064))
    export_glb("vm_rifle.glb")

    # --- Trench Combat Shotgun ---
    clear_scene()
    m_steel = make_mat("ShotgunSteel", (0.22, 0.23, 0.25, 1), metallic=0.88, roughness=0.34, tex_prefix="rusted_metal")
    m_wood = make_mat("ShotgunWood", (0.32, 0.16, 0.08, 1), roughness=0.65, tex_prefix="wood_planks")
    m_shell = make_mat("ShotgunShells", (0.78, 0.12, 0.12, 1), roughness=0.40)

    root = add_pivot("Root", (0, 0, 0))
    add_part("Receiver", "CUBE", (0, 0, 0), (0.060, 0.28, 0.074), mat=m_steel, parent=root, bevel=0.008, offset=(0, 0.04, 0.03))
    add_part("HeavyBarrel", "CYLINDER", (0, 0, 0), (0.030, 0.030, 0.56), rot=(math.radians(90), 0, 0), mat=m_steel, parent=root, bevel=0.003, offset=(0, 0.44, 0.048))
    add_part("MagTube", "CYLINDER", (0, 0, 0), (0.025, 0.025, 0.48), rot=(math.radians(90), 0, 0), mat=m_steel, parent=root, bevel=0.002, offset=(0, 0.40, 0.014))
    add_part("PumpForend", "CYLINDER", (0, 0, 0), (0.042, 0.042, 0.22), rot=(math.radians(90), 0, 0), mat=m_wood, parent=root, bevel=0.005, offset=(0, 0.36, 0.012))
    add_part("Stock", "CUBE", (0, 0, 0), (0.050, 0.28, 0.10), mat=m_wood, parent=root, bevel=0.01, offset=(0, -0.22, -0.008))
    for i in range(4):
        add_part(f"SideShell{i}", "CYLINDER", (0, 0, 0), (0.013, 0.013, 0.048), mat=m_shell, parent=root, bevel=0.002, offset=(0.034, 0.0 + i * 0.032, 0.032))
    export_glb("vm_shotgun.glb")

    # --- Monster First-Person Claws (Viktor's Monster Form!) ---
    clear_scene()
    m_hide = make_mat("MonsterHide", (0.15, 0.07, 0.09, 1), roughness=0.50, tex_prefix="monster_scales")
    m_talon = make_mat("RazorTalon", (0.85, 0.16, 0.10, 1), metallic=0.45, roughness=0.22, emission=(0.95, 0.16, 0.08), emission_strength=2.2)
    m_vein = make_mat("MonsterVein", (1.0, 0.24, 0.08, 1), roughness=0.2, emission=(1.0, 0.22, 0.06), emission_strength=3.2)

    root = add_pivot("Root", (0, 0, 0))
    for side, sx in [("L", -1), ("R", 1)]:
        arm = add_pivot(f"ClawArm{side}", (sx * 0.30, 0.04, -0.18), parent=root)
        add_part(f"Forearm{side}", "CUBE", (sx * 0.30, 0.04, -0.18), (0.12, 0.40, 0.11), rot=(math.radians(12), 0, sx * math.radians(16)), mat=m_hide, parent=arm, bevel=0.035, offset=(-sx * 0.04, 0.20, 0.02))
        add_part(f"VeinRidge{side}", "CUBE", (sx * 0.30, 0.04, -0.18), (0.016, 0.30, 0.018), rot=(math.radians(12), 0, sx * math.radians(16)), mat=m_vein, parent=arm, bevel=0.005, offset=(-sx * 0.04, 0.20, 0.078))
        add_part(f"Palm{side}", "SPHERE", (sx * 0.30, 0.04, -0.18), (0.16, 0.16, 0.10), mat=m_hide, parent=arm, bevel=0, offset=(-sx * 0.08, 0.41, 0.06))
        # Point 4 wicked curved talons forward (+Y in Blender -> -Z forward in Godot) & slightly upward/inward!
        for ti, tx in enumerate([-0.054, -0.018, 0.018, 0.054]):
            add_part(
                f"Talon{side}{ti}",
                "CONE",
                (sx * 0.30, 0.04, -0.18),
                (0.032, 0.032, 0.24),
                rot=(math.radians(-72), 0, sx * math.radians(12)),
                mat=m_talon,
                parent=arm,
                bevel=0.0,
                offset=(-sx * 0.08 + tx, 0.54, 0.09),
            )
    export_glb("vm_monster_claws.glb")


# ---------------------------------------------------------------------------
# 7. COURTYARD PROPS (FIRE BARREL & SANDBAGS)
# ---------------------------------------------------------------------------
def build_props():
    clear_scene()
    m_rust = make_mat("BarrelRust", (0.42, 0.22, 0.14, 1), metallic=0.65, roughness=0.62, tex_prefix="rusted_metal")
    root = add_pivot("Root", (0, 0, 0))
    add_part("Drum", "CYLINDER", (0, 0, 0), (0.62, 0.62, 0.96), mat=m_rust, parent=root, bevel=0.02, offset=(0, 0, 0.48))
    add_part("Rib1", "CYLINDER", (0, 0, 0), (0.65, 0.65, 0.05), mat=m_rust, parent=root, bevel=0.01, offset=(0, 0, 0.32))
    add_part("Rib2", "CYLINDER", (0, 0, 0), (0.65, 0.65, 0.05), mat=m_rust, parent=root, bevel=0.01, offset=(0, 0, 0.66))
    export_glb("prop_barrel.glb")

    clear_scene()
    m_burlap = make_mat("Burlap", (0.46, 0.40, 0.28, 1), roughness=0.92, tex_prefix="burlap")
    root = add_pivot("Root", (0, 0, 0))
    rows = [(0.16, [(-0.55, 0), (0.0, 0), (0.55, 0)]), (0.42, [(-0.30, 0.02), (0.30, -0.02)]), (0.66, [(0.0, 0)])]
    idx = 0
    for z, xs in rows:
        for x, y in xs:
            add_part(f"Bag{idx}", "CUBE", (0, 0, 0), (0.56, 0.34, 0.26), mat=m_burlap, parent=root, bevel=0.09, subsurf=1, offset=(x, y, z))
            idx += 1
    export_glb("prop_sandbags.glb")


if __name__ == "__main__":
    build_zombie_walker()
    build_boss_gun_zombie()
    build_boss_gorilla()
    build_boss_necromancer()
    build_boss_juggernaut()
    build_weapons()
    build_props()
    print("ALL BLENDER GLB MODELS GENERATED SUCCESSFULLY!")
