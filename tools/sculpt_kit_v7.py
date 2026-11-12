"""Blender 4.5 Procedural Organic Sculpting, Anatomical Lofting, Armature Skinning
& Hard-Surface Modeling Kit (v7) for Dead Protocol Zombies, Hound & Bosses.

Coordinate Convention:
  +Y = Forward (-Z in Godot glTF)
  +Z = Up      (+Y in Godot glTF)
  -X = Left (L), +X = Right (R)
  Z = 0.0 = Ground plane
"""
import math
import os
import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(ROOT_DIR, "assets", "models")
TEX_DIR = os.path.join(ROOT_DIR, "assets", "textures")
os.makedirs(OUT_DIR, exist_ok=True)

_tint_cache = {}
_img_cache = {}
MAX_TEX = 1024
R90 = math.radians(90.0)


# ---------------------------------------------------------------------------
# SCENE, MATERIALS & EXPORT
# ---------------------------------------------------------------------------
def clear_scene():
    _tint_cache.clear()
    _img_cache.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_tex(path, non_color=False):
    img = _img_cache.get((path, non_color))
    if img is None:
        img = bpy.data.images.load(path)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        if img.size[0] > MAX_TEX:
            img.scale(MAX_TEX, max(1, MAX_TEX * img.size[1] // img.size[0]))
        _img_cache[(path, non_color)] = img
    return img


BESPOKE_TEX = {
    "necrotic_flesh",
    "bloater_flesh",
    "gorilla_fur",
    "panzer_steel",
    "plague_hazmat",
}


def srgb_to_linear(rgb):
    return tuple(max(float(c), 0.0) ** 2.2 for c in rgb[:3])


def tinted_albedo(tex_prefix, base_color, contrast=1.32, preserve_hue=None):
    """Tint a PBR albedo texture so its rendered sRGB average matches `base_color` (specified in sRGB!),
    correctly converting Blender's scene-linear `Image.pixels` <-> perceptual sRGB."""
    if preserve_hue is None:
        preserve_hue = tex_prefix in BESPOKE_TEX
    key = (tex_prefix, tuple(round(c, 3) for c in base_color[:3]), round(contrast, 2), bool(preserve_hue))
    img = _tint_cache.get(key)
    if img is None:
        src = load_tex(os.path.join(TEX_DIR, f"{tex_prefix}_albedo.png"))
        w, h = src.size
        px = np.empty(w * h * 4, np.float32)
        src.pixels.foreach_get(px)
        px = px.reshape(-1, 4)

        # `src.pixels` is scene-linear; convert to perceptual sRGB [0..1] for accurate color grading
        srgb = np.clip(px[:, :3], 0.0, 1.0) ** (1.0 / 2.2)
        target_srgb = np.array([max(float(c), 0.0) for c in base_color[:3]], np.float32)[None, :]

        if preserve_hue:
            # Keep bespoke multi-tone detail (purple veins, rust streaks, bile blotches)
            lum = 0.299 * srgb[:, 0:1] + 0.587 * srgb[:, 1:2] + 0.114 * srgb[:, 2:3]
            mean_lum = max(float(lum.mean()), 0.08)
            rel = srgb / mean_lum
            rel = 1.0 + (rel - 1.0) * contrast
        else:
            # Neutralize scanned-photo color cast (e.g. orange leather) while keeping 100% of grain/creases!
            mean_ch = np.maximum(srgb.mean(axis=0, keepdims=True), 0.08)
            rel = srgb / mean_ch
            gray_rel = rel.mean(axis=1, keepdims=True)
            rel = gray_rel * 0.80 + rel * 0.20
            rel = 1.0 + (rel - 1.0) * contrast

        out_srgb = np.clip(rel * target_srgb, 0.0, 1.0)
        # Convert back to scene-linear for Blender sRGB Image datablock!
        px[:, :3] = out_srgb ** 2.2
        img = bpy.data.images.new(f"{tex_prefix}_v71_{len(_tint_cache)}", w, h)
        img.pixels.foreach_set(px.ravel())
        img.pack()
        _tint_cache[key] = img
    return img


def make_mat(name, base_color=(0.5, 0.5, 0.5, 1.0), metallic=0.0, roughness=0.72,
             emission=None, emission_strength=0.0, tex_prefix=None, normal_strength=1.0,
             contrast=1.32, srgb_input=True):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    lin_rgb = srgb_to_linear(base_color[:3]) if srgb_input else tuple(base_color[:3])
    alpha = base_color[3] if len(base_color) > 3 else 1.0
    bsdf.inputs["Base Color"].default_value = (*lin_rgb, alpha)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    if tex_prefix:
        albedo_p = os.path.join(TEX_DIR, f"{tex_prefix}_albedo.png")
        rough_p = os.path.join(TEX_DIR, f"{tex_prefix}_rough.png")
        normal_p = os.path.join(TEX_DIR, f"{tex_prefix}_normal.png")
        if os.path.exists(albedo_p):
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = tinted_albedo(tex_prefix, base_color, contrast=contrast)
            links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if os.path.exists(rough_p):
            tr = nodes.new("ShaderNodeTexImage")
            tr.image = load_tex(rough_p, non_color=True)
            links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
        if os.path.exists(normal_p):
            tn = nodes.new("ShaderNodeTexImage")
            tn.image = load_tex(normal_p, non_color=True)
            nm = nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = normal_strength
            links.new(tn.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    if emission is not None and emission_strength > 0.0:
        ekey = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[ekey].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def neon_mat(name, rgb, strength=5.0, roughness=0.18):
    return make_mat(name, (*rgb, 1.0), metallic=0.0, roughness=roughness,
                    emission=rgb, emission_strength=strength, srgb_input=False)


def add_pivot(name, loc=(0, 0, 0), parent=None):
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.location = loc
    if parent:
        empty.parent = parent
        empty.matrix_parent_inverse = parent.matrix_world.inverted()
    return empty


def parent_keep_world(obj, parent):
    if parent is not None:
        bpy.context.view_layer.update()
        mw = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
        obj.matrix_world = mw
    return obj


def assign_mat(obj, mat):
    if mat is None:
        return obj
    if len(obj.data.materials) == 0:
        obj.data.materials.append(mat)
    else:
        obj.data.materials[0] = mat
    return obj


def auto_uv(obj, uv_scale=2.2):
    """Metric triplanar / box UV projection aligned to world axes so vertical fur,
    cloth weaves, and skin pores never suffer scrambled triangles or stretching."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.verify()
    mw = obj.matrix_world
    rot_m = mw.to_3x3()
    for f in bm.faces:
        wn = (rot_m @ f.normal).normalized()
        ax, ay, az = abs(wn.x), abs(wn.y), abs(wn.z)
        for loop in f.loops:
            wp = mw @ loop.vert.co
            if ax >= ay and ax >= az:
                u, v = wp.y * uv_scale, wp.z * uv_scale
            elif ay >= ax and ay >= az:
                u, v = wp.x * uv_scale, wp.z * uv_scale
            else:
                u, v = wp.x * uv_scale, wp.y * uv_scale
            loop[uv_layer].uv = (u, v)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    return obj


def export_glb(filename):
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="WEBP",
        export_image_quality=90,
    )
    print("Exported:", path)


def merge_per_pivot(keep=()):
    """Merge all mesh children directly under each Empty pivot into a single multi-material mesh,
    keeping the pivot Empty's exact transform & origin intact!"""
    bpy.context.view_layer.update()
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


# ---------------------------------------------------------------------------
# ANATOMICAL MULTI-STATION LOFTING ENGINE
# ---------------------------------------------------------------------------
def _frame_along_spine(pts):
    """Compute twist-free parallel-transport frames (T, X_axis, Y_axis) along 3D spine points."""
    n = len(pts)
    tangents = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        if t.length < 1e-6:
            t = Vector((0, 0, 1))
        tangents.append(t.normalized())

    # Choose initial reference axis: if spine is mostly vertical, X_axis = +X, Y_axis = +Y (forward)
    t0 = tangents[0]
    if abs(t0.y) < 0.88:
        # Use +Y (forward) projected perpendicular to t0 as local anterior (+Y_axis)
        y0 = (Vector((0, 1, 0)) - t0 * t0.dot(Vector((0, 1, 0)))).normalized()
        x0 = y0.cross(t0).normalized()
        # Wait: if t0 = (0,0,1) and y0 = (0,1,0), y0.cross(t0) = (1,0,0) = +X!
    else:
        # Spine runs mostly along Y (e.g. hound snout/body or gun barrel): use +Z as local dorsal
        y0 = (Vector((0, 0, 1)) - t0 * t0.dot(Vector((0, 0, 1)))).normalized()
        x0 = y0.cross(t0).normalized()

    frames = [(t0, x0, y0)]
    for i in range(1, n):
        tp, xp, yp = frames[-1]
        ti = tangents[i]
        q = tp.rotation_difference(ti)
        xi = (q @ xp).normalized()
        yi = (q @ yp).normalized()
        frames.append((ti, xi, yi))
    return frames


def loft_anatomical(name, stations, mat=None, parent=None, segs=20, cap_start=True, cap_end=True,
                    open_shell_thickness=0.0, tear_end_amp=0.0, tear_seed=1, subsurf=1, uv_scale=2.2):
    """Build a contiguous organic or garment mesh from cross-section stations.

    Each station is a dict or tuple:
      (pos, rx, ry_front, ry_back)  OR
      dict(pos=(x,y,z), rx=0.1, ry_f=0.1, ry_b=0.1, off_x=0.0, off_y=0.0,
           pinch_x=0.0, harmonics=[(freq, amp, phase), ...])
    where theta=0 is +X (Right), theta=pi/2 is +Y_local (Anterior/Front),
    theta=pi is -X (Left), theta=3*pi/2 is -Y_local (Posterior/Back).
    """
    parsed = []
    for st in stations:
        if isinstance(st, dict):
            p = Vector(st["pos"])
            rx = float(st.get("rx", 0.1))
            ry_f = float(st.get("ry_f", st.get("ry", rx)))
            ry_b = float(st.get("ry_b", st.get("ry", rx)))
            ox = float(st.get("off_x", 0.0))
            oy = float(st.get("off_y", 0.0))
            harm = st.get("harmonics", ())
        else:
            p = Vector(st[0])
            rx = float(st[1])
            ry_f = float(st[2])
            ry_b = float(st[3]) if len(st) > 3 else ry_f
            ox, oy = 0.0, 0.0
            harm = st[4] if len(st) > 4 else ()
        parsed.append((p, rx, ry_f, ry_b, ox, oy, harm))

    pts = [s[0] for s in parsed]
    frames = _frame_along_spine(pts)

    bm = bmesh.new()
    rings = []
    n_st = len(parsed)

    for si, (p, rx, ry_f, ry_b, ox, oy, harm) in enumerate(parsed):
        t_vec, x_ax, y_ax = frames[si]
        ring = []
        is_end = (si == n_st - 1)
        for j in range(segs):
            th = (j / segs) * math.tau
            ct, st_sin = math.cos(th), math.sin(th)
            ry = ry_f if st_sin >= 0.0 else ry_b
            mod = 1.0
            for freq, amp, ph in harm:
                mod += amp * math.cos(freq * th + ph)
            lx = ox + ct * rx * mod
            ly = oy + st_sin * ry * mod
            wp = p + x_ax * lx + y_ax * ly
            if tear_end_amp > 0.0 and si >= n_st - 2:
                frac = 1.0 if is_end else 0.45
                jag = (math.sin(th * 5.0 + tear_seed) * 0.5
                       + math.sin(th * 11.0 + tear_seed * 2.3) * 0.32
                       + math.cos(th * 17.0 - tear_seed * 1.7) * 0.18)
                wp = wp + t_vec * (jag * tear_end_amp * frac)
            ring.append(bm.verts.new(wp))
        rings.append(ring)

    for si in range(n_st - 1):
        r0, r1 = rings[si], rings[si + 1]
        for j in range(segs):
            jn = (j + 1) % segs
            bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))

    if cap_start and open_shell_thickness <= 0.0:
        p0, rx0, ryf0, ryb0, ox0, oy0, _ = parsed[0]
        t0, x0, y0 = frames[0]
        c0 = bm.verts.new(p0 + x0 * ox0 + y0 * oy0 - t0 * (min(rx0, ryf0) * 0.32))
        for j in range(segs):
            jn = (j + 1) % segs
            bm.faces.new((rings[0][jn], rings[0][j], c0))

    if cap_end and open_shell_thickness <= 0.0:
        p1, rx1, ryf1, ryb1, ox1, oy1, _ = parsed[-1]
        t1, x1, y1 = frames[-1]
        c1 = bm.verts.new(p1 + x1 * ox1 + y1 * oy1 + t1 * (min(rx1, ryf1) * 0.32))
        for j in range(segs):
            jn = (j + 1) % segs
            bm.faces.new((rings[-1][j], rings[-1][jn], c1))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    if open_shell_thickness > 0.0:
        sol = obj.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = open_shell_thickness
        sol.offset = 1.0
        bpy.ops.object.modifier_apply(modifier=sol.name)

    if subsurf > 0:
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = subsurf
        sub.render_levels = subsurf
        bpy.ops.object.modifier_apply(modifier=sub.name)

    assign_mat(obj, mat)
    auto_uv(obj, uv_scale=uv_scale)
    parent_keep_world(obj, parent)
    return obj


def loft_open_arc(name, stations, default_gap_deg=76.0, gap_offset_deg=0.0, mat=None, parent=None,
                  segs=22, thickness=0.008, tear_end_amp=0.0, tear_lapel_amp=0.0, tear_seed=1,
                  subsurf=1, uv_scale=2.2):
    """Build an OPEN-FRONT garment, tattered shirt, trenchcoat/duster, or shadowed hood/cowl!
    Sweeps around the sides & back while leaving an open front aperture centered at +Y_local
    (`theta = 90 deg + gap_offset_deg`) of angular width `gap_deg` (customizable per station!)."""
    parsed = []
    for st in stations:
        p = Vector(st["pos"])
        rx = float(st.get("rx", 0.1))
        ry_f = float(st.get("ry_f", st.get("ry", rx)))
        ry_b = float(st.get("ry_b", st.get("ry", rx)))
        ox = float(st.get("off_x", 0.0))
        oy = float(st.get("off_y", 0.0))
        gap_d = float(st.get("gap_deg", default_gap_deg))
        goff_d = float(st.get("gap_offset_deg", gap_offset_deg))
        harm = st.get("harmonics", ())
        parsed.append((p, rx, ry_f, ry_b, ox, oy, gap_d, goff_d, harm))

    pts = [s[0] for s in parsed]
    frames = _frame_along_spine(pts)

    bm = bmesh.new()
    rings = []
    n_st = len(parsed)

    for si, (p, rx, ry_f, ry_b, ox, oy, gap_d, goff_d, harm) in enumerate(parsed):
        t_vec, x_ax, y_ax = frames[si]
        ring = []
        is_end = (si == n_st - 1)
        half_gap = math.radians(max(4.0, min(170.0, gap_d * 0.5)))
        center_ang = math.pi * 0.5 + math.radians(goff_d)
        th_start = center_ang + half_gap
        th_end = center_ang + math.tau - half_gap

        for j in range(segs + 1):
            u = j / segs
            th = th_start + u * (th_end - th_start)
            ct, st_sin = math.cos(th), math.sin(th)
            ry = ry_f if st_sin >= 0.0 else ry_b
            mod = 1.0
            for freq, amp, ph in harm:
                mod += amp * math.cos(freq * th + ph)
            if tear_lapel_amp > 0.0 and (j <= 1 or j >= segs - 1):
                edge_f = 1.0 if (j == 0 or j == segs) else 0.45
                mod += tear_lapel_amp * edge_f * math.sin(si * 2.7 + j * 1.9 + tear_seed)
            lx = ox + ct * rx * mod
            ly = oy + st_sin * ry * mod
            wp = p + x_ax * lx + y_ax * ly
            if tear_end_amp > 0.0 and si >= n_st - 2:
                frac = 1.0 if is_end else 0.45
                jag = (math.sin(th * 5.0 + tear_seed) * 0.5
                       + math.sin(th * 11.0 + tear_seed * 2.3) * 0.32
                       + math.cos(th * 17.0 - tear_seed * 1.7) * 0.18)
                wp = wp + t_vec * (jag * tear_end_amp * frac)
            ring.append(bm.verts.new(wp))
        rings.append(ring)

    for si in range(n_st - 1):
        r0, r1 = rings[si], rings[si + 1]
        for j in range(segs):
            bm.faces.new((r0[j], r0[j + 1], r1[j + 1], r1[j]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    if thickness > 0.0:
        sol = obj.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = thickness
        sol.offset = 0.0
        sol.use_rim = True
        bpy.ops.object.modifier_apply(modifier=sol.name)

    if subsurf > 0:
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = subsurf
        sub.render_levels = subsurf
        bpy.ops.object.modifier_apply(modifier=sub.name)

    assign_mat(obj, mat)
    auto_uv(obj, uv_scale=uv_scale)
    parent_keep_world(obj, parent)
    return obj


# ---------------------------------------------------------------------------
# OPENVDB VOXEL SCULPTING & VECTORIZED 3D SCULPT BRUSHES
# ---------------------------------------------------------------------------
def voxel_fuse_and_sculpt(name, objs, voxel_size=0.008, sculpt_ops=(), smooth_iters=3,
                          decimate_ratio=0.55, mat=None, parent=None, uv_scale=2.4):
    """Fuse multiple base primitive/lofted forms into ONE seamless manifold organic sculpture
    via OpenVDB Voxel Remesh, apply 3D Gaussian/Crease sculpt brushes directly on vertices,
    apply Laplacian/Corrective smoothing, and decimate cleanly."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = objs[0]
    obj.name = name

    # Apply any transform so voxel grid is isotropic in world meters
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.remesh_voxel_size = voxel_size
    obj.data.use_remesh_fix_poles = True
    bpy.ops.object.voxel_remesh()

    # Vectorized numpy sculpt operations in world space!
    if sculpt_ops:
        me = obj.data
        mw = obj.matrix_world
        mwi = mw.inverted()
        n_v = len(me.vertices)
        co = np.empty(n_v * 3, np.float32)
        no = np.empty(n_v * 3, np.float32)
        me.vertices.foreach_get("co", co)
        me.vertices.foreach_get("normal", no)
        co = co.reshape(-1, 3)
        no = no.reshape(-1, 3)

        # Transform to world coordinates
        R = np.array(mw.to_3x3(), np.float32)
        T = np.array(mw.translation, np.float32)
        wco = co @ R.T + T
        wno = no @ R.T
        wno /= np.maximum(np.linalg.norm(wno, axis=1, keepdims=True), 1e-6)

        for op in sculpt_ops:
            kind = op[0]
            if kind == "carve":
                # ("carve", (cx, cy, cz), (rx, ry, rz), depth) -> pushes along -normal (or inward)
                _, center, radii, depth = op
                c = np.array(center, np.float32)
                r = np.maximum(np.array(radii, np.float32), 1e-4)
                d2 = np.sum(((wco - c) / r) ** 2, axis=1)
                mask = d2 < 2.25
                if np.any(mask):
                    w = np.exp(-d2[mask] * 1.35)[:, None]
                    wco[mask] -= wno[mask] * (depth * w)

            elif kind == "inflate":
                # ("inflate", (cx, cy, cz), (rx, ry, rz), amount)
                _, center, radii, amount = op
                c = np.array(center, np.float32)
                r = np.maximum(np.array(radii, np.float32), 1e-4)
                d2 = np.sum(((wco - c) / r) ** 2, axis=1)
                mask = d2 < 2.25
                if np.any(mask):
                    w = np.exp(-d2[mask] * 1.35)[:, None]
                    wco[mask] += wno[mask] * (amount * w)

            elif kind == "grab":
                # ("grab", (cx, cy, cz), radius, (dx, dy, dz))
                _, center, radius, delta = op
                c = np.array(center, np.float32)
                dl = np.array(delta, np.float32)
                d2 = np.sum((wco - c) ** 2, axis=1) / max(radius * radius, 1e-6)
                mask = d2 < 2.5
                if np.any(mask):
                    w = np.exp(-d2[mask] * 1.25)[:, None]
                    wco[mask] += dl[None, :] * w

            elif kind == "crease":
                # ("crease", p0, p1, radius, depth) -> sharp anatomical muscle/scar/brow groove along segment!
                _, p0, p1, radius, depth = op
                a = np.array(p0, np.float32)
                b = np.array(p1, np.float32)
                ab = b - a
                ab_len2 = max(float(np.dot(ab, ab)), 1e-6)
                t_proj = np.clip(np.sum((wco - a) * ab, axis=1) / ab_len2, 0.0, 1.0)
                closest = a[None, :] + t_proj[:, None] * ab[None, :]
                d2 = np.sum((wco - closest) ** 2, axis=1) / max(radius * radius, 1e-6)
                mask = d2 < 2.0
                if np.any(mask):
                    # Sharp V/Gaussian crease profile + subtle pinch ridges on flanks
                    u = d2[mask]
                    profile = (np.exp(-u * 2.8) - 0.22 * np.exp(-u * 0.85))[:, None]
                    wco[mask] -= wno[mask] * (depth * profile)

            elif kind == "noise":
                # ("noise", freq, amp, seed) -> organic lumpy surface displacement
                _, freq, amp, seed = op
                p = wco * freq
                nval = (np.sin(p[:, 0] * 1.7 + seed) * np.cos(p[:, 1] * 1.9 - seed * 0.7) * np.sin(p[:, 2] * 1.5 + seed * 1.3)
                        + 0.5 * np.cos(p[:, 0] * 3.7 - p[:, 2] * 2.9 + seed * 2.1))
                wco += wno * (nval[:, None] * amp)

        # Convert back to object space
        Ri = np.array(mwi.to_3x3(), np.float32)
        Ti = np.array(mwi.translation, np.float32)
        lco = wco @ Ri.T + Ti
        me.vertices.foreach_set("co", lco.ravel())
        me.update()

    if smooth_iters > 0:
        sm = obj.modifiers.new("Smooth", "SMOOTH")
        sm.factor = 0.55
        sm.iterations = smooth_iters
        bpy.ops.object.modifier_apply(modifier=sm.name)

    if 0.05 < decimate_ratio < 0.99:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = decimate_ratio
        bpy.ops.object.modifier_apply(modifier=dec.name)

    assign_mat(obj, mat)
    auto_uv(obj, uv_scale=uv_scale)
    parent_keep_world(obj, parent)
    return obj


# ---------------------------------------------------------------------------
# HARD-SURFACE, SPLINE HOSES, CHAINS & SCULPTED SKULL/HEAD HELPERS
# ---------------------------------------------------------------------------
def prim_mesh(name, kind="CUBE", center=(0, 0, 0), size=(0.1, 0.1, 0.1), rot=(0, 0, 0),
              mat=None, parent=None, bevel=0.0, subsurf=0, verts=16, uv_scale=2.2):
    """Clean hard-surface / base primitive positioned at `center` (world space)."""
    if kind == "CUBE":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    elif kind == "SPHERE":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=max(12, verts), ring_count=max(8, verts * 3 // 4), radius=0.5, location=(0, 0, 0))
    elif kind == "CYLINDER":
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=0.5, depth=1.0, location=(0, 0, 0))
    elif kind == "CONE":
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=0.5, radius2=0.06, depth=1.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if rot != (0, 0, 0):
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot, "XYZ").to_matrix(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    bm.to_mesh(obj.data)
    bm.free()

    if bevel > 0.0:
        bev = obj.modifiers.new("Bevel", "BEVEL")
        bev.width = bevel
        bev.segments = 2
        bev.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=bev.name)
    if subsurf > 0:
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = subsurf
        sub.render_levels = subsurf
        bpy.ops.object.modifier_apply(modifier=sub.name)

    assign_mat(obj, mat)
    auto_uv(obj, uv_scale=uv_scale)
    parent_keep_world(obj, parent)
    return obj


def seg_limb(name, p0, p1, r0, r1, mat=None, parent=None, verts=12, subsurf=0):
    """Tapered segment between two 3D points."""
    v0, v1 = Vector(p0), Vector(p1)
    if (v1 - v0).length < 1e-4:
        v1 = v0 + Vector((0, 0, 0.01))
    return loft_anatomical(name, [(v0, r0, r0, r0), (v1, r1, r1, r1)],
                           mat=mat, parent=parent, segs=verts, subsurf=subsurf)


def spline_tube(name, points, radius=0.02, mat=None, parent=None, ribbed=False, rib_amp=0.22, segs=12):
    """Smooth 3D Catmull-Rom / interpolated tube or corrugated hose along control points!"""
    pts = [Vector(p) for p in points]
    # Subdivide control points smoothly via Catmull-Rom spline
    dense = []
    steps_per_seg = 8 if ribbed else 5
    ext = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(steps_per_seg):
            t = s / steps_per_seg
            t2, t3 = t * t, t * t * t
            pos = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            dense.append(pos)
    dense.append(pts[-1])

    stations = []
    for idx, p in enumerate(dense):
        r = radius * (1.0 + rib_amp * (1.0 if idx % 2 == 0 else -0.65)) if ribbed else radius
        stations.append((p, r, r, r))
    return loft_anatomical(name, stations, mat=mat, parent=parent, segs=segs, subsurf=0 if ribbed else 1, uv_scale=4.0)


def chain_strand(name, points, link_major=0.036, link_minor=0.010, mat=None, parent=None):
    """Create real interlocking 3D torus iron chain links along a 3D path!"""
    pts = [Vector(p) for p in points]
    # Sample arc-length every 1.45 * link_major
    samples = [pts[0]]
    step = link_major * 1.42
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        seg_v = b - a
        L = seg_v.length
        if L < 1e-5:
            continue
        d = seg_v.normalized()
        cur = samples[-1]
        t_left = step - (cur - a).length if i > 0 else step
        dist = 0.0
        while dist + step <= L + 1e-4:
            dist += step
            samples.append(a + d * dist)

    links = []
    for idx in range(len(samples) - 1):
        p0, p1 = samples[idx], samples[idx + 1]
        mid = (p0 + p1) * 0.5
        tangent = (p1 - p0).normalized()
        bpy.ops.mesh.primitive_torus_add(
            major_radius=link_major, minor_radius=link_minor,
            major_segments=14, minor_segments=6, location=(0, 0, 0)
        )
        lk = bpy.context.active_object
        bm = bmesh.new()
        bm.from_mesh(lk.data)
        # Elongate oval chain link along X, then align X with tangent & alternate 90 deg twist!
        bmesh.ops.scale(bm, vec=(1.35, 0.85, 1.0), verts=bm.verts)
        q = Vector((1, 0, 0)).rotation_difference(tangent)
        twist = Quaternion(tangent, math.radians(90.0 if idx % 2 == 1 else 0.0))
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=(twist @ q).to_matrix(), verts=bm.verts)
        bmesh.ops.translate(bm, vec=mid, verts=bm.verts)
        bm.to_mesh(lk.data)
        bm.free()
        links.append(lk)

    if not links:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for lk in links:
        lk.select_set(True)
    bpy.context.view_layer.objects.active = links[0]
    if len(links) > 1:
        bpy.ops.object.join()
    obj = links[0]
    obj.name = name
    assign_mat(obj, mat)
    auto_uv(obj, uv_scale=4.0)
    parent_keep_world(obj, parent)
    return obj


def build_sculpted_undead_head(prefix, head_pivot, jaw_pivot, head_pos, m_skin, m_eye, m_bone, m_gore,
                               scale=1.0, gaunt=1.0, rabid=False, bloated=False):
    """Build a true OpenVDB voxel-sculpted undead cranium + face with carved orbital sockets,
    piriform nasal cavity, gaunt sub-malar cheek hollows, snarling upper teeth, and a separate
    hinged sculpted mandible under `jaw_pivot`!"""
    hx, hy, hz = head_pos
    s = scale

    # Base forms to fuse for cranium + upper face + neck
    neck = loft_anatomical(f"{prefix}_NeckBase", [
        {"pos": (hx, hy - 0.015 * s, hz - 0.07 * s), "rx": 0.064 * s * (1.25 if bloated else 1.0), "ry_f": 0.058 * s, "ry_b": 0.064 * s,
         "harmonics": [(2, 0.12, 0.0)]},
        {"pos": (hx, hy + 0.008 * s, hz + 0.05 * s), "rx": 0.055 * s * (1.22 if bloated else 1.0), "ry_f": 0.052 * s, "ry_b": 0.058 * s},
        {"pos": (hx, hy + 0.018 * s, hz + 0.13 * s), "rx": 0.068 * s, "ry_f": 0.062 * s, "ry_b": 0.068 * s},
    ], segs=16, subsurf=0)

    cranium = prim_mesh(f"{prefix}_CranBase", "SPHERE",
                        (hx, hy + 0.015 * s, hz + 0.175 * s),
                        (0.195 * s, 0.228 * s, 0.225 * s), verts=20)
    brow = prim_mesh(f"{prefix}_BrowBase", "CUBE",
                     (hx, hy + 0.105 * s, hz + 0.200 * s),
                     (0.155 * s, 0.060 * s, 0.036 * s), bevel=0.014 * s)
    zygoma = prim_mesh(f"{prefix}_ZygoBase", "CUBE",
                       (hx, hy + 0.088 * s, hz + 0.148 * s),
                       (0.162 * s * (1.14 if bloated else 1.0), 0.075 * s, 0.048 * s), bevel=0.018 * s)
    maxilla = prim_mesh(f"{prefix}_MaxillaBase", "SPHERE",
                        (hx, hy + 0.108 * s, hz + 0.118 * s),
                        (0.112 * s, 0.095 * s, 0.082 * s), verts=16)
    nose_bridge = prim_mesh(f"{prefix}_NoseBase", "CONE",
                            (hx, hy + 0.138 * s, hz + 0.162 * s),
                            (0.036 * s, 0.042 * s, 0.055 * s), rot=(-0.35, 0, 0), verts=10)
    parts = [neck, cranium, brow, zygoma, maxilla, nose_bridge]

    if bloated:
        jowl_l = prim_mesh(f"{prefix}_JowlL", "SPHERE", (hx - 0.068 * s, hy + 0.075 * s, hz + 0.095 * s), (0.095 * s, 0.095 * s, 0.090 * s))
        jowl_r = prim_mesh(f"{prefix}_JowlR", "SPHERE", (hx + 0.075 * s, hy + 0.080 * s, hz + 0.098 * s), (0.110 * s, 0.105 * s, 0.100 * s))
        parts.extend([jowl_l, jowl_r])

    for sx, nm in ((-1, "L"), (1, "R")):
        if not (nm == "L" and rabid):  # rabid runner has one torn-off ear!
            ear = prim_mesh(f"{prefix}_Ear{nm}", "SPHERE",
                            (hx + sx * 0.098 * s, hy + 0.008 * s, hz + 0.155 * s),
                            (0.024 * s, 0.038 * s, 0.058 * s), rot=(0, sx * 0.25, 0), verts=12)
            parts.append(ear)

    ops = [
        # Deep sunken orbital eye sockets!
        ("carve", (hx - 0.040 * s, hy + 0.118 * s, hz + 0.172 * s), (0.030 * s, 0.032 * s, 0.025 * s), 0.026 * s),
        ("carve", (hx + 0.040 * s, hy + 0.118 * s, hz + 0.172 * s), (0.030 * s, 0.032 * s, 0.025 * s), 0.026 * s),
        # Skeletal piriform nasal cavity (rotted nose tip!)
        ("carve", (hx, hy + 0.146 * s, hz + 0.144 * s), (0.018 * s, 0.024 * s, 0.022 * s), 0.022 * s),
        # Temple concavities
        ("carve", (hx - 0.086 * s, hy + 0.055 * s, hz + 0.195 * s), (0.035 * s, 0.048 * s, 0.038 * s), 0.012 * s * gaunt),
        ("carve", (hx + 0.086 * s, hy + 0.055 * s, hz + 0.195 * s), (0.035 * s, 0.048 * s, 0.038 * s), 0.012 * s * gaunt),
        # Open oral cavity under maxilla
        ("carve", (hx, hy + 0.125 * s, hz + 0.092 * s), (0.046 * s, 0.042 * s, 0.026 * s), 0.026 * s),
        # Angry furrowed glabella & nasolabial snarl creases
        ("crease", (hx - 0.012 * s, hy + 0.132 * s, hz + 0.188 * s), (hx - 0.022 * s, hy + 0.128 * s, hz + 0.215 * s), 0.010 * s, 0.008 * s),
        ("crease", (hx + 0.012 * s, hy + 0.132 * s, hz + 0.188 * s), (hx + 0.022 * s, hy + 0.128 * s, hz + 0.215 * s), 0.010 * s, 0.008 * s),
        ("crease", (hx - 0.025 * s, hy + 0.132 * s, hz + 0.145 * s), (hx - 0.052 * s, hy + 0.105 * s, hz + 0.105 * s), 0.012 * s, 0.009 * s),
        ("crease", (hx + 0.025 * s, hy + 0.132 * s, hz + 0.145 * s), (hx + 0.052 * s, hy + 0.105 * s, hz + 0.105 * s), 0.012 * s, 0.009 * s),
        # Sternocleidomastoid taut neck tendons
        ("inflate", (hx - 0.032 * s, hy + 0.028 * s, hz + 0.03 * s), (0.016 * s, 0.020 * s, 0.065 * s), 0.008 * s),
        ("inflate", (hx + 0.032 * s, hy + 0.028 * s, hz + 0.03 * s), (0.016 * s, 0.020 * s, 0.065 * s), 0.008 * s),
    ]
    if not bloated:
        ops.extend([
            ("carve", (hx - 0.065 * s, hy + 0.072 * s, hz + 0.118 * s), (0.032 * s, 0.042 * s, 0.032 * s), 0.016 * s * gaunt),
            ("carve", (hx + 0.065 * s, hy + 0.072 * s, hz + 0.118 * s), (0.032 * s, 0.042 * s, 0.032 * s), 0.016 * s * gaunt),
        ])

    skull_obj = voxel_fuse_and_sculpt(
        f"{prefix}_SculptHead", parts, voxel_size=0.0065 * s,
        sculpt_ops=ops, smooth_iters=3, decimate_ratio=0.45,
        mat=m_skin, parent=head_pivot, uv_scale=2.8
    )

    # Dark inner eye socket shadow + small menacing glowing irises recessed inside sockets!
    m_sock = make_mat(f"{prefix}_SocketDark", (0.02, 0.015, 0.018, 1), roughness=0.92)
    for sx, nm in ((-1, "L"), (1, "R")):
        prim_mesh(f"{prefix}_EyeSock{nm}", "SPHERE",
                  (hx + sx * 0.040 * s, hy + 0.106 * s, hz + 0.172 * s),
                  (0.032 * s, 0.022 * s, 0.026 * s), mat=m_sock, parent=head_pivot, verts=12)
        prim_mesh(f"{prefix}_EyeGlow{nm}", "SPHERE",
                  (hx + sx * 0.040 * s, hy + 0.116 * s, hz + 0.172 * s),
                  (0.015 * s, 0.012 * s, 0.014 * s), mat=m_eye, parent=head_pivot, verts=12)

    # Upper crooked teeth anchored in maxilla
    for i in range(6):
        ang = -0.52 + i * 0.208
        tx = hx + math.sin(ang) * 0.038 * s
        ty = hy + 0.095 * s + math.cos(ang) * 0.038 * s
        tlen = (0.022 if (i in (0, 5) and rabid) else 0.015) * s
        prim_mesh(f"{prefix}_UTooth{i}", "CONE",
                  (tx, ty, hz + 0.092 * s),
                  (0.010 * s, 0.008 * s, tlen), rot=(math.pi, 0, 0),
                  mat=m_bone, parent=head_pivot, verts=6)

    # Sculpted hinged mandible under jaw_pivot
    jx, jy, jz = jaw_pivot.location
    jaw_arch = loft_anatomical(f"{prefix}_JawMandible", [
        {"pos": (hx - 0.056 * s, hy + 0.045 * s, jz + 0.018 * s), "rx": 0.018 * s, "ry_f": 0.022 * s, "ry_b": 0.020 * s},
        {"pos": (hx - 0.042 * s, hy + 0.088 * s, jz - 0.025 * s), "rx": 0.020 * s, "ry_f": 0.024 * s, "ry_b": 0.020 * s},
        {"pos": (hx, hy + 0.122 * s, jz - 0.034 * s), "rx": 0.026 * s, "ry_f": 0.028 * s, "ry_b": 0.022 * s},
        {"pos": (hx + 0.042 * s, hy + 0.088 * s, jz - 0.025 * s), "rx": 0.020 * s, "ry_f": 0.024 * s, "ry_b": 0.020 * s},
        {"pos": (hx + 0.056 * s, hy + 0.045 * s, jz + 0.018 * s), "rx": 0.018 * s, "ry_f": 0.022 * s, "ry_b": 0.020 * s},
    ], mat=m_skin, parent=jaw_pivot, segs=12, subsurf=1, uv_scale=2.8)

    # Dark oral floor + lower teeth
    prim_mesh(f"{prefix}_OralFloor", "SPHERE",
              (hx, hy + 0.092 * s, jz - 0.020 * s),
              (0.068 * s, 0.068 * s, 0.022 * s), mat=m_gore, parent=jaw_pivot, verts=12)
    for i in range(5):
        ang = -0.46 + i * 0.23
        tx = hx + math.sin(ang) * 0.034 * s
        ty = hy + 0.088 * s + math.cos(ang) * 0.034 * s
        tlen = (0.020 if (i in (0, 4) and rabid) else 0.014) * s
        prim_mesh(f"{prefix}_LTooth{i}", "CONE",
                  (tx, ty, jz - 0.012 * s),
                  (0.009 * s, 0.008 * s, tlen), rot=(0, 0, 0),
                  mat=m_bone, parent=jaw_pivot, verts=6)

    return skull_obj, jaw_arch


# ---------------------------------------------------------------------------
# 17-BONE HUMANOID ARMATURE & SMOOTH SKINNING (SkinRigAdapter + ZombieRig)
# ---------------------------------------------------------------------------
def build_zombie_armature_and_skin(name, sh_x=0.23, el_x=0.25, wr_x=0.25, hip_x=0.115, knee_x=0.12, ankle_x=0.12,
                                   jaw_pos=(0.0, 0.06, 1.67), head_pos=(0.0, 0.02, 1.57)):
    """Join all visible meshes in the scene into a single multi-material character `Body` mesh
    and skin it smoothly to the exact 17-bone `Skeleton3D` expected by `SkinRigAdapter` & `ZombieRig`!
    Vertices originally parented to `Head` or `Jaw` Empties get crisp anatomical head/jaw weights
    so headshots and jaw-snapping deform cleanly with zero stretching!"""
    bpy.context.view_layer.update()

    # Tag vertices by their source pivot Empty BEFORE joining so Jaw vs Head, Thigh vs Pelvis,
    # and Arms vs Ribcage never cross-bleed across tight gaps!
    bone_defs = [
        ("Hips", None, (0.0, 0.0, 0.98), (0.0, 0.0, 1.07)),
        ("Spine", "Hips", (0.0, 0.0, 1.07), (0.0, 0.0, 1.25)),
        ("Chest", "Spine", (0.0, 0.0, 1.25), head_pos),
        ("Head", "Chest", head_pos, (head_pos[0], head_pos[1] + 0.01, head_pos[2] + 0.25)),
        ("Jaw", "Head", jaw_pos, (jaw_pos[0], jaw_pos[1] + 0.08, jaw_pos[2] - 0.04)),
    ]
    for sx, nm in ((-1, "L"), (1, "R")):
        sh = (sx * sh_x, 0.0, 1.48)
        el = (sx * el_x, 0.01, 1.20)
        wr = (sx * wr_x, 0.02, 0.95)
        fn = (sx * wr_x, 0.04, 0.78)
        hp = (sx * hip_x, 0.0, 0.94)
        kn = (sx * knee_x, 0.01, 0.52)
        an = (sx * ankle_x, 0.0, 0.10)
        to = (sx * ankle_x, 0.15, 0.02)
        bone_defs += [
            ("UpperArm" + nm, "Chest", sh, el),
            ("Forearm" + nm, "UpperArm" + nm, el, wr),
            ("Hand" + nm, "Forearm" + nm, wr, fn),
            ("Thigh" + nm, "Hips", hp, kn),
            ("Shin" + nm, "Thigh" + nm, kn, an),
            ("Foot" + nm, "Shin" + nm, an, to),
        ]

    bone_names = [b[0] for b in bone_defs]
    bone_idx = {bn: i for i, bn in enumerate(bone_names)}
    segs_a = np.array([b[2] for b in bone_defs], np.float32)
    segs_b = np.array([b[3] for b in bone_defs], np.float32)

    # Pre-assign allowed bone subsets per object based on its parent Empty hierarchy!
    mesh_objs = [o for o in list(bpy.data.objects) if o.type == "MESH"]
    empties = [o for o in list(bpy.data.objects) if o.type == "EMPTY"]

    def ancestor_bone_name(obj):
        p = obj.parent
        while p is not None:
            if p.name in bone_idx:
                return p.name
            p = p.parent
        return ""

    # Compute smooth weights per object BEFORE joining so Jaw never pulls Maxilla,
    # Arms never pull Ribs, and Left Leg never pulls Right Leg!
    torso_chain = ["Hips", "Spine", "Chest"]
    allowed_map = {
        "Hips": ["Hips", "Spine"],
        "Spine": ["Hips", "Spine", "Chest"],
        "Chest": ["Spine", "Chest"],
        "Head": ["Chest", "Head"],
        "Jaw": ["Jaw"],
        "UpperArmL": ["UpperArmL", "ForearmL", "HandL"],
        "ForearmL": ["UpperArmL", "ForearmL", "HandL"],
        "HandL": ["ForearmL", "HandL"],
        "UpperArmR": ["UpperArmR", "ForearmR", "HandR"],
        "ForearmR": ["UpperArmR", "ForearmR", "HandR"],
        "HandR": ["ForearmR", "HandR"],
        "ThighL": ["ThighL", "ShinL", "FootL"],
        "ShinL": ["ThighL", "ShinL", "FootL"],
        "FootL": ["ShinL", "FootL"],
        "ThighR": ["ThighR", "ShinR", "FootR"],
        "ShinR": ["ThighR", "ShinR", "FootR"],
        "FootR": ["ShinR", "FootR"],
    }
    # Note: for Crawler mode (`ZombieRig.hide_legs()` scales `ThighL`/`ThighR` to 0.001!),
    # vertices of Thigh/Shin/Foot MUST ONLY weight to Thigh/Shin/Foot (NOT Hips!), otherwise
    # scaling ThighL to 0.001 would leave half-weighted vertices stretched up to Hips!
    # Similarly, `Head` scales to 0.001 on headshot kill — keep Head vertices strictly on Head!
    allowed_map["Head"] = ["Head"]

    obj_tags = {o: ancestor_bone_name(o) for o in mesh_objs}

    for o in mesh_objs:
        tag = obj_tags[o]
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

        # Create vertex groups on this mesh and blend smoothly across its allowed bone chain
        allowed = allowed_map.get(tag, torso_chain)
        for bn in bone_names:
            if bn not in o.vertex_groups:
                o.vertex_groups.new(name=bn)

        if len(allowed) == 1:
            vg = o.vertex_groups[allowed[0]]
            vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        else:
            idxs = [bone_idx[bn] for bn in allowed]
            A = segs_a[idxs]  # (K, 3)
            B = segs_b[idxs]  # (K, 3)
            AB = B - A
            AB_len2 = np.maximum(np.sum(AB * AB, axis=1), 1e-6)

            nv = len(o.data.vertices)
            vco = np.empty(nv * 3, np.float32)
            o.data.vertices.foreach_get("co", vco)
            vco = vco.reshape(-1, 3)  # (N, 3)

            # Distance from each vertex (N, 1, 3) to each allowed bone segment (1, K, 3)
            diff = vco[:, None, :] - A[None, :, :]
            t = np.clip(np.sum(diff * AB[None, :, :], axis=2) / AB_len2[None, :], 0.0, 1.0)
            closest = A[None, :, :] + t[:, :, None] * AB[None, :, :]
            dist = np.linalg.norm(vco[:, None, :] - closest, axis=2)  # (N, K)

            # Sharp Gaussian falloff (sigma = 0.065m) for smooth joint bending without rigid seams!
            weights = np.exp(-((dist / 0.068) ** 2))
            w_sum = np.maximum(np.sum(weights, axis=1, keepdims=True), 1e-8)
            weights /= w_sum

            for k_local, bn in enumerate(allowed):
                vg = o.vertex_groups[bn]
                w_col = weights[:, k_local]
                for vi in np.where(w_col > 0.01)[0]:
                    vg.add([int(vi)], float(w_col[vi]), "REPLACE")

    # Join all meshes into single skinned `Body`
    bpy.ops.object.select_all(action="DESELECT")
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    if len(mesh_objs) > 1:
        bpy.ops.object.join()
    body = mesh_objs[0]
    body.name = "Body"

    # Remove helper Empty pivots so only Armature + Body export
    for emp in empties:
        bpy.data.objects.remove(emp, do_unlink=True)

    # Build the 17-bone Armature
    arm_data = bpy.data.armatures.new(name + "_Armature")
    rig_obj = bpy.data.objects.new(name, arm_data)
    bpy.context.collection.objects.link(rig_obj)
    bpy.context.view_layer.objects.active = rig_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for bname, pname, head, tail in bone_defs:
        b = eb.new(bname)
        b.head = head
        b.tail = tail
        b.use_connect = False
        if pname:
            b.parent = eb[pname]
    bpy.ops.object.mode_set(mode="OBJECT")

    body.parent = rig_obj
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig_obj
    return rig_obj, body
