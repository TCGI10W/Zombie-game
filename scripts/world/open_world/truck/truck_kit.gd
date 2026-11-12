class_name TruckKit
extends RefCounted
## The crew's truck, the salvage beacon and the exit marker (METRO 9 M9): their Blender pieces
## (assets/models/vehicles/truck, built by _src/run_truck.py) with the game's PS1 materials. Like
## Slip7Kit: a material `trk_<name>` takes assets/models/vehicles/truck/tex/<name>.png and a finish of its
## own; lenses and screens glow; glass and the cab's welded mesh are see-through. The manifest
## (truck.json) carries each piece's named points and the hull's collision boxes in Godot space.

const DIR := "res://art/models/vehicles/truck/"
const TEX_DIR := "res://art/models/vehicles/truck/tex/"
const PS1_SHADER: Shader = preload("res://shaders/ps1.gdshader")
const GLASS_SHADER: Shader = preload("res://shaders/ps1_glass.gdshader")
const CUTOUT_SHADER: Shader = preload("res://shaders/ps1_cutout.gdshader")
## The truck lives in both places: SLIP 7 (render layer 1) and METRO 9 (layer 5, its moon's).
const LAYERS: int = 1 | (1 << 4)
## Render layer 17 (M9 with M5, the 800 draw budget): lit as ever, never a shadow caster for METRO 9's moon (its
## shadow_caster_mask leaves this and layer 5 out). With layer 5 for the moon's light (its cull mask is layers 1
## and 5) and this for SLIP 7's (its cull mask leaves layer 5 out): an instance on both is lit everywhere and
## casts for lamps (all-caster masks) but not for the moon's two splits.
const NO_SUN: int = 1 << 16
const NO_SUN_LAYERS: int = (1 << 4) | NO_SUN
static var _sun_proxies: Dictionary = {}
## [roughness, metallic, specular] per surface.
const FINISH: Dictionary = {
	"paint": [0.55, 0.05, 0.3], "paint_worn": [0.75, 0.04, 0.25], "black": [0.7, 0.0, 0.2], "tread": [0.62, 0.12, 0.35],
	"steel": [0.5, 0.1, 0.3], "rust": [0.92, 0.0, 0.3], "soot": [0.95, 0.0, 0.15], "rubber": [0.85, 0.0, 0.2],
	"seat": [0.6, 0.0, 0.3], "dash": [0.7, 0.0, 0.25], "hazard": [0.55, 0.0, 0.3], "mag": [0.5, 0.2, 0.35],
	"relay": [0.6, 0.0, 0.3], "can": [0.5, 0.03, 0.3], "chevron": [0.55, 0.0, 0.3], "gauges": [0.45, 0.0, 0.3],
	"reflector": [0.25, 0.6, 0.8], "rim": [0.6, 0.05, 0.25], "steer_steel": [0.8, 0.12, 0.18],
	"sand": [0.62, 0.04, 0.28], "sand_worn": [0.78, 0.03, 0.24], "plastic": [0.75, 0.0, 0.22], "liner": [0.95, 0.0, 0.03],
}
## Lenses: [texture, glow colour, glow strength when lit]. A lens is drawn lit or dark by `lit`.
const LENS: Dictionary = {
	"lens_head": ["lens_head", Color(1.0, 0.86, 0.62), 2.2], "lens_tail": ["lens_tail", Color(1.0, 0.16, 0.08), 1.6],
	"lens_amber": ["lens_amber", Color(1.0, 0.6, 0.16), 2.2], "lens_white": ["lens_head", Color(1.0, 0.95, 0.85), 1.6],
	"lens_dead": ["lens_dead", Color.BLACK, 0.0], "maglow": ["lens_amber", Color(1.0, 0.55, 0.12), 1.3],
	"pip": ["lens_amber", Color(1.0, 0.58, 0.14), 2.0], "bulb": ["lens_amber", Color(1.0, 0.7, 0.3), 3.0],
}
## Tints over a shared tile: the wheels' dull painted steel (the bare steel tile read as white plastic
## at a metre); the mag strips' copper, dark until they glow (it read as lit lines when off).
## The steering wheel's spoke and hub: dark worn metal (the bare tile under the cab light read as a bright
## pink-white bar, out of the rust and oily-black palette: the director's walk5 check).
const TINT: Dictionary = {"rim": Color(0.5, 0.48, 0.45), "mag": Color(0.55, 0.5, 0.48), "steer_steel": Color(0.2, 0.17, 0.15)}
## Plain colours (no texture): recesses and voids.
const PLAIN: Dictionary = {"dark": Color(0.02, 0.02, 0.02)}

static var _mats: Dictionary = {}
static var _manifest: Dictionary = {}


## A material by its Blender name (without the trk_ prefix); `lit` picks a lens's glowing twin.
static func material(name: String, lit: bool = false) -> Material:
	var key := name + ("|lit" if lit else "")
	if _mats.has(key):
		return _mats[key]
	if name == "crt":
		# the map screen, as every CRT in the game (CrtScreen): unshaded and point-filtered, so its own
		# picture is what shows in the dark cab (the PS1 shader's emission is one flat colour)
		var screen := StandardMaterial3D.new()
		screen.resource_name = "trk_crt"
		screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		screen.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		screen.albedo_texture = _tex("crt")
		_mats[key] = screen
		return screen
	var mat := ShaderMaterial.new()
	mat.resource_name = "trk_" + key
	if name in ["glass", "glass_cracked", "dome_amber"]:
		mat.shader = GLASS_SHADER
		if name == "dome_amber":
			mat.set_shader_parameter("albedo_texture", _tex("lens_amber"))
			mat.set_shader_parameter("albedo_color", Color(1.0, 0.72, 0.3, 0.55))
			if lit:
				mat.set_shader_parameter("emission_color", Color(1.0, 0.55, 0.12))
				mat.set_shader_parameter("emission_strength", 1.2)
		else:
			mat.set_shader_parameter("albedo_texture", _tex(name))
			mat.set_shader_parameter("albedo_color", Color(0.75, 0.85, 0.82, 0.32 if name == "glass" else 0.4))
		mat.set_shader_parameter("surface_roughness", 0.1)
		mat.set_shader_parameter("surface_specular", 0.8)
	elif name in ["mesh", "stencil_tailgate", "stencil_beacon", "stencil_plate", "stripes"]:
		mat.shader = CUTOUT_SHADER
		mat.set_shader_parameter("albedo_texture", _tex(name))
		mat.set_shader_parameter("surface_roughness", 0.6)
		mat.set_shader_parameter("surface_specular", 0.25)
	elif LENS.has(name):
		var l: Array = LENS[name]
		mat.shader = PS1_SHADER
		mat.set_shader_parameter("albedo_texture", _tex(String(l[0])))
		mat.set_shader_parameter("surface_roughness", 0.35)
		mat.set_shader_parameter("surface_specular", 0.5)
		if lit and float(l[2]) > 0.0:
			mat.set_shader_parameter("emission_color", l[1])
			mat.set_shader_parameter("emission_strength", float(l[2]))
		elif name in ["maglow", "pip", "bulb"]:
			mat.set_shader_parameter("albedo_color", Color(0.3, 0.27, 0.24))  # dark until it's switched on
	elif PLAIN.has(name):
		mat.shader = PS1_SHADER
		mat.set_shader_parameter("albedo_color", PLAIN[name])
		mat.set_shader_parameter("surface_roughness", 1.0)
		mat.set_shader_parameter("surface_specular", 0.0)
	else:
		mat.shader = PS1_SHADER
		mat.set_shader_parameter("albedo_texture", _tex("steel" if name in ["reflector", "rim", "steer_steel"] else name))
		if TINT.has(name):
			mat.set_shader_parameter("albedo_color", TINT[name])
		var f: Array = FINISH.get(name, [0.6, 0.0, 0.3])
		mat.set_shader_parameter("surface_roughness", float(f[0]))
		mat.set_shader_parameter("surface_metallic", float(f[1]))
		mat.set_shader_parameter("surface_specular", float(f[2]))
	_mats[key] = mat
	return mat


static func _tex(name: String) -> Texture2D:
	return load(TEX_DIR + name + ".png") as Texture2D


## A piece's instance with the kit's materials on every surface; `lit` lights its lenses.
static func piece(name: String, lit: bool = false) -> Node3D:
	var root := (load(DIR + name + ".glb") as PackedScene).instantiate() as Node3D
	root.name = name.capitalize().replace(" ", "")
	dress(root, lit)
	return root


## A truck piece's shadow for METRO 9's moon (M5's draw census: its two splits drew the truck's ~98 surfaces twice):
## its real meshes on NO_SUN_LAYERS (lit as ever, cast for lamps only); with `proxy`, one merged shadow-only
## copy of its own shape on layer 1 casts for the moon (glass, the screen and lenses left out, so moonlight still
## comes in through the windows): one draw a split. Without, the piece casts no moon shadow (small parts).
static func sun_shadow(root: Node3D, name: String, proxy: bool) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = NO_SUN_LAYERS
		if proxy and mi.mesh != null:
			var shadow := MeshInstance3D.new()
			shadow.name = "SunShadow"
			shadow.mesh = _sun_proxy(name, mi.mesh)
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shadow.layers = 1
			mi.add_child(shadow)


## Piece `name`'s surfaces merged into one (positions and normals only), made once and shared by every truck.
static func _sun_proxy(name: String, src: Mesh) -> ArrayMesh:
	if _sun_proxies.has(name):
		return _sun_proxies[name]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in src.get_surface_count():
		var m := src.surface_get_material(i)
		var nm := m.resource_name.trim_prefix("trk_") if m else ""
		if nm.begins_with("glass") or nm == "crt" or LENS.has(nm) or nm == "dome_amber":
			continue
		var a := src.surface_get_arrays(i)
		if a.is_empty():
			continue  # (headless: the dummy renderer keeps no arrays)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var base := verts.size()
		verts.append_array(v)
		if nrm.size() == v.size():
			norms.append_array(nrm)
		else:
			for k in v.size():
				norms.append(Vector3.UP)
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			for k in ix:
				idx.append(base + k)
	var am := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_sun_proxies[name] = am
	return am


## The kit's materials on every surface under `root` (by the imported material's name).
static func dress(root: Node, lit: bool = false) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.layers = LAYERS
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var name := m.resource_name.trim_prefix("trk_") if m else ""
			if not name.is_empty():
				mi.set_surface_override_material(i, material(name, lit))


## Re-light the lenses of one dressed instance (the headlights on, a beacon waking).
static func set_lit(root: Node, lit: bool, only: PackedStringArray = PackedStringArray()) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var name := m.resource_name.trim_prefix("trk_") if m else ""
			if (LENS.has(name) or name == "dome_amber") and (only.is_empty() or name in only):
				mi.set_surface_override_material(i, material(name, lit))


## The manifest's entry for a piece: {"tris", "aabb", "boxes", "points", ...}.
static func info(name: String) -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(DIR + "truck.json", FileAccess.READ)
		if f:
			_manifest = (JSON.parse_string(f.get_as_text()) as Dictionary).get("pieces", {})
	return _manifest.get(name, {})


## A named point of a piece (Godot space, the piece's own frame).
static func point(piece_name: String, point_name: String) -> Vector3:
	var p: Array = (info(piece_name).get("points", {}) as Dictionary).get(point_name, [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
