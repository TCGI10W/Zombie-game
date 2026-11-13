extends Node3D
# Motor-pool generator. Turning it on restores the lights in the bunker and
# lab, and powers the Weapon Forge and the field radio.

var interact_radius: float = 3.2
var _lever: Node3D
var _status: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0
var _running: bool = false


func _ready() -> void:
	add_to_group("wall_stations")
	if ResourceLoader.exists("res://assets/models/prop_generator.glb"):
		var m: Node3D = (load("res://assets/models/prop_generator.glb") as PackedScene).instantiate()
		add_child(m)
		HitboxRig.attach_ballistic_trimesh(m, "metal")
		_lever = m.find_child("Lever", true, false)
		_status = m.find_child("StatusLight", true, false) as MeshInstance3D

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.0, 1.25)
	cs.shape = bs
	cs.position.y = 1.0
	body.add_child(cs)
	add_child(body)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.1)
	_light.light_energy = 1.2
	_light.omni_range = 3.5
	_light.position = Vector3(0.45, 1.4, -0.9)
	add_child(_light)

	var lbl := Label3D.new()
	lbl.text = "GENERATOR\nPOWER: OFF"
	lbl.name = "PowerLabel"
	lbl.font_size = 36
	lbl.outline_size = 10
	lbl.pixel_size = 0.005
	lbl.modulate = Color(1.0, 0.45, 0.3)
	lbl.position = Vector3(0, 2.9, -0.2)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(lbl)


func _process(delta: float) -> void:
	_t += delta
	if _running:
		# Engine shudder
		position.y = sin(_t * 47.0) * 0.004
		_light.light_energy = 1.4 + sin(_t * 9.0) * 0.2
	else:
		_light.light_energy = 0.6 + (0.8 if fmod(_t, 1.2) < 0.6 else 0.0)


func get_prompt(_player: Node3D) -> String:
	return "[E] TURN ON THE POWER"


func try_purchase(_player: Node3D) -> void:
	if not _running:
		Net.world(self, "start")


func net_apply(action: String, _args: Array) -> void:
	if action == "start":
		_start(get_tree().get_first_node_in_group("player") as Node3D)


func _start(player: Node3D) -> void:
	if _running:
		return
	_running = true
	remove_from_group("wall_stations")
	GameState.play_sfx("power_on", 2.0, 1.0)
	if _lever:
		_lever.create_tween().tween_property(_lever, "rotation:x", deg_to_rad(-70.0), 0.35).set_trans(Tween.TRANS_BACK)
	if _status:
		_status.material_override = MaterialLib.get_emissive(Color(0.2, 1.0, 0.3), 5.0)
	_light.light_color = Color(0.3, 1.0, 0.4)
	var lbl := get_node_or_null("PowerLabel") as Label3D
	if lbl:
		lbl.text = "GENERATOR\nPOWER: ON"
		lbl.modulate = Color(0.4, 1.0, 0.5)
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.4)
	# Lights come on after the engine spins up
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func():
		get_tree().call_group("arena", "set_power", true)
		if is_instance_valid(player):
			player.status_banner_requested.emit("POWER RESTORED — WEAPON FORGE & FIELD RADIO ONLINE", Color(0.4, 1.0, 0.5))
	)
