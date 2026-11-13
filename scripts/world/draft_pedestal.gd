class_name DraftPedestal
extends Node3D

# 3-Pedestal Colosseum Boss Draft stand in OVERDRIVE mode.
# After each boss dies, 3 pedestals rise in Town Plaza offering 1 free pick.

var pedestal_index: int = 0
var category: String = "weapon" # "weapon", "perk", "mutation"
var title_text: String = "DRAFT REWARD"
var detail_text: String = ""
var offer: Dictionary = {}
var accent: Color = Color(1.0, 0.85, 0.25)
var interact_radius: float = 2.6
var director: Node = null

var _prism: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _ring2: MeshInstance3D = null
var _weapon_preview: Node3D = null
var _label: Label3D = null
var _t: float = 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("draft_pedestals")
	_build_visuals()


func configure(idx: int, cat: String, title: String, detail: String, data: Dictionary, col: Color, owner_dir: Node) -> void:
	pedestal_index = idx
	category = cat
	title_text = title
	detail_text = detail
	offer = data
	accent = col
	director = owner_dir
	if is_inside_tree():
		_apply_label_and_color()


func get_prompt(_p: Node3D) -> String:
	return "[E] DRAFT: %s — %s (FREE)" % [title_text, detail_text]


func try_purchase(p: Node3D) -> void:
	if director != null and is_instance_valid(director) and director.has_method("claim_pedestal"):
		director.claim_pedestal(p, self)
	else:
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	var bob_y: float = 1.48 + sin(_t * 3.0 + float(pedestal_index)) * 0.09
	if _prism != null:
		_prism.rotation.y += delta * 2.0
		_prism.position.y = bob_y
	if _weapon_preview != null and is_instance_valid(_weapon_preview):
		_weapon_preview.rotation.y += delta * 1.45
		_weapon_preview.position.y = bob_y
	if _ring != null:
		_ring.rotation.y -= delta * 1.4
	if _ring2 != null:
		_ring2.rotation.y += delta * 2.2


func _build_visuals() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.16, 0.18, 0.22)
	stone.metallic = 0.55
	stone.roughness = 0.35

	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.58
	cm.height = 0.96
	cm.radial_segments = 12
	base.mesh = cm
	base.material_override = stone
	base.position.y = 0.48
	add_child(base)

	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.52
	tm.outer_radius = 0.62
	_ring.mesh = tm
	_ring.position.y = 0.98
	add_child(_ring)

	_ring2 = MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 0.38
	tm2.outer_radius = 0.43
	_ring2.mesh = tm2
	_ring2.position.y = 1.48
	_ring2.rotation_degrees = Vector3(18.0, 0.0, 28.0)
	add_child(_ring2)

	_prism = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.32, 0.32)
	_prism.mesh = bm
	_prism.rotation_degrees = Vector3(35.0, 0.0, 45.0)
	_prism.position.y = 1.48
	add_child(_prism)

	var light := OmniLight3D.new()
	light.name = "Glow"
	light.omni_range = 6.0
	light.light_energy = 2.4
	light.position.y = 1.5
	add_child(light)

	_label = Label3D.new()
	_label.font_size = 28
	_label.outline_size = 9
	_label.pixel_size = 0.0040
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = true
	_label.position.y = 2.58
	add_child(_label)
	_apply_label_and_color()


func _apply_label_and_color() -> void:
	if _weapon_preview != null and is_instance_valid(_weapon_preview):
		_weapon_preview.queue_free()
		_weapon_preview = null
	if _prism != null:
		_prism.visible = true
		_prism.material_override = MaterialLib.get_emissive(accent, 4.5, 0.95)
	if _ring != null:
		_ring.material_override = MaterialLib.get_emissive(accent, 3.2, 0.95)
	if _ring2 != null:
		_ring2.material_override = MaterialLib.get_emissive(accent, 2.4, 0.85)
	var light := get_node_or_null("Glow") as OmniLight3D
	if light != null:
		light.light_color = accent

	if category == "weapon":
		var wid: String = String(offer.get("weapon_id", ""))
		var w_def: Dictionary = GameState.WEAPONS.get(wid, {})
		var mpath: String = String(w_def.get("model", ""))
		if mpath != "" and ResourceLoader.exists(mpath):
			var packed := load(mpath) as PackedScene
			if packed != null:
				_weapon_preview = packed.instantiate() as Node3D
				if _weapon_preview != null:
					_strip_arms_and_layers(_weapon_preview)
					_weapon_preview.position = Vector3(0.0, 1.48, 0.0)
					_weapon_preview.scale = Vector3.ONE * 1.45
					add_child(_weapon_preview)
					if _prism != null:
						_prism.visible = false

	if _label != null:
		_label.modulate = accent
		var cat_tag: String = "[ WEAPON DRAFT ]" if category == "weapon" else ("[ STAT SURGE ]" if category == "perk" else "[ MUTATION ]")
		_label.text = "%s\n%s\n%s" % [cat_tag, title_text, detail_text]


func _strip_arms_and_layers(node: Node) -> void:
	if node.name.begins_with("Arm"):
		if node is Node3D:
			(node as Node3D).visible = false
		return
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		vi.layers = 1
		vi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_strip_arms_and_layers(c)
