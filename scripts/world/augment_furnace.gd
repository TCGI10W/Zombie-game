extends Node3D
# The stat upgrade machine. Feed it points and it permanently boosts a stat
# for the rest of the run. Opens the Augment menu on the HUD.
# Origin on the floor; the furnace mouth faces local -Z.

var interact_radius: float = 3.0
var _fire_light: OmniLight3D
var _t: float = 0.0
var _flare: float = 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("augment_furnace")
	if ResourceLoader.exists("res://assets/models/prop_augment_furnace.glb"):
		var af := (load("res://assets/models/prop_augment_furnace.glb") as PackedScene).instantiate() as Node3D
		add_child(af)
		HitboxRig.attach_ballistic_trimesh(af, "metal")

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 2.2, 1.0)
	cs.shape = bs
	cs.position.y = 1.1
	body.add_child(cs)
	add_child(body)

	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.45, 0.12)
	_fire_light.light_energy = 2.2
	_fire_light.omni_range = 6.5
	_fire_light.position = Vector3(0, 0.9, -1.0)
	add_child(_fire_light)

	var embers := CPUParticles3D.new()
	embers.position = Vector3(0.35, 3.0, 0.1)
	embers.amount = 20
	embers.lifetime = 2.0
	embers.direction = Vector3.UP
	embers.spread = 18.0
	embers.gravity = Vector3(0, 1.5, 0)
	embers.initial_velocity_min = 0.6
	embers.initial_velocity_max = 1.6
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(1.0, 0.5, 0.15)
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		qm.albedo_texture = load("res://assets/textures/soft_particle.png")
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = qm
	embers.mesh = quad
	add_child(embers)

	var lbl := Label3D.new()
	lbl.text = "AUGMENT FURNACE\nBURN POINTS • UPGRADE STATS"
	lbl.font_size = 36
	lbl.outline_size = 10
	lbl.pixel_size = 0.005
	lbl.modulate = Color(1.0, 0.6, 0.3)
	lbl.position = Vector3(0, 2.45, -0.55)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lbl)


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 2.0)
	_fire_light.light_energy = 2.2 + sin(_t * 9.0) * 0.35 + cos(_t * 13.0) * 0.2 + _flare * 6.0


# Called by the HUD after points are burned
func flare() -> void:
	_flare = 1.0


func get_prompt(player: Node3D) -> String:
	if player.is_monster_form:
		return "AUGMENT FURNACE: RETURN TO HUMAN FORM FIRST"
	return "[E] AUGMENT FURNACE — BURN POINTS TO UPGRADE YOUR STATS"


func try_purchase(player: Node3D) -> void:
	if player.is_monster_form:
		return
	get_tree().call_group("hud", "open_augment_menu")
