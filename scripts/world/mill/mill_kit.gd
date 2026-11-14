class_name MillKit
extends RefCounted
## Halloway Mill building kit (art/blender/build_mill_kit.py -> art/models/mill/mk_*.glb).
## Each glb surface is one named material (M_<kind>); it is swapped for the METRO 9 scan
## material of that kind, so the kit and the greybox share one set of textures.

## kind -> [ms_ texture, tile metres, metallic, tint]
const MATS := {
	"brick": ["ms_brick", 1.5, 0.0, Color.WHITE],
	"plaster": ["ms_plaster", 2.0, 0.0, Color.WHITE],
	"concrete": ["ms_screed", 2.0, 0.0, Color(1.15, 1.15, 1.13)],
	"screed": ["ms_screed", 3.0, 0.0, Color.WHITE],
	"corrugated": ["ms_corrugated", 1.5, 0.1, Color.WHITE],
	"rust": ["ms_rust", 2.0, 0.08, Color.WHITE],
	"steel": ["ms_steel", 1.0, 0.15, Color.WHITE],
	"wood": ["ms_wood", 1.5, 0.0, Color.WHITE],
}
static var _scenes := {}


static func material(kind: String) -> Material:
	var s: Array = MATS.get(kind, MATS["concrete"])
	return MaterialLib.get_world(s[0], 1.0 / float(s[1]), s[3], float(s[2]), 1.0, 0.0, 0.3)


## An instance of `piece` with the METRO 9 materials applied.
static func make(piece: String) -> Node3D:
	if not _scenes.has(piece):
		_scenes[piece] = load("res://art/models/mill/%s.glb" % piece)
	var n: Node3D = (_scenes[piece] as PackedScene).instantiate()
	_apply(n)
	return n


static func _apply(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var kind := m.resource_name.trim_prefix("M_") if m else "concrete"
			mi.set_surface_override_material(i, material(kind))
	for c in n.get_children():
		_apply(c)
