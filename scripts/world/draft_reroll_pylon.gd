class_name DraftRerollPylon
extends Node3D

# Interactive console placed in front of the 3 Boss Draft pedestals in OVERDRIVE.
# Lets the player spend points to roll fresh weapon/stat/mutation rewards.

var interact_radius: float = 2.2
var director: Node = null

var _cube: MeshInstance3D = null
var _label: Label3D = null
var _t: float = 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("draft_pedestals")
	_build_visuals()


func get_prompt(_p: Node3D) -> String:
	var cost: int = 500
	if director != null and is_instance_valid(director) and director.has_method("get_reroll_cost"):
		cost = int(director.get_reroll_cost())
	return "[E] REROLL ALL 3 DRAFT PEDESTALS (%d PTS)" % cost


func try_purchase(p: Node3D) -> void:
	if director != null and is_instance_valid(director) and director.has_method("reroll_boss_draft"):
		director.reroll_boss_draft(p)


func _process(delta: float) -> void:
	_t += delta
	if _cube != null:
		_cube.rotation.y += delta * 2.8
		_cube.position.y = 1.08 + sin(_t * 4.0) * 0.05


func _build_visuals() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.14, 0.16, 0.21)
	stone.metallic = 0.65
	stone.roughness = 0.32

	var plinth := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.36
	cm.height = 0.78
	cm.radial_segments = 8
	plinth.mesh = cm
	plinth.material_override = stone
	plinth.position.y = 0.39
	add_child(plinth)

	_cube = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 0.22)
	_cube.mesh = bm
	_cube.material_override = MaterialLib.get_emissive(Color(1.0, 0.65, 0.18), 4.2, 0.95)
	_cube.rotation_degrees = Vector3(35.0, 0.0, 45.0)
	_cube.position.y = 1.08
	add_child(_cube)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.2)
	light.light_energy = 1.6
	light.omni_range = 4.5
	light.position.y = 1.15
	add_child(light)

	_label = Label3D.new()
	_label.font_size = 24
	_label.outline_size = 8
	_label.pixel_size = 0.0038
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = true
	_label.position.y = 1.52
	_label.modulate = Color(1.0, 0.78, 0.32)
	add_child(_label)
	refresh_label()


func refresh_label() -> void:
	if _label == null:
		return
	var cost: int = 500
	if director != null and is_instance_valid(director) and director.has_method("get_reroll_cost"):
		cost = int(director.get_reroll_cost())
	_label.text = "[ REROLL DRAFT ]\n%d PTS" % cost
