extends Node3D
# Field radio in the Command Bunker. Once the power is on and you've reached
# the extraction round, use it between rounds to call in the chopper.
# Origin on the floor; the console front faces local -Z.

const EXFIL_ROUND := 8

var interact_radius: float = 2.4
var _lamp: OmniLight3D
var _t: float = 0.0
var _static_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("wall_stations")
	if ResourceLoader.exists("res://assets/models/prop_radio_console.glb"):
		add_child((load("res://assets/models/prop_radio_console.glb") as PackedScene).instantiate())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.55, 1.45, 0.8)
	cs.shape = bs
	cs.position.y = 0.72
	body.add_child(cs)
	add_child(body)

	_lamp = OmniLight3D.new()
	_lamp.light_energy = 1.0
	_lamp.omni_range = 3.5
	_lamp.position = Vector3(0, 1.4, -0.6)
	add_child(_lamp)

	var lbl := Label3D.new()
	lbl.text = "FIELD RADIO\nEXTRACTION"
	lbl.font_size = 32
	lbl.outline_size = 10
	lbl.pixel_size = 0.0045
	lbl.modulate = Color(0.75, 1.0, 0.65)
	lbl.position = Vector3(0, 2.0, -0.2)
	lbl.rotation.y = PI
	add_child(lbl)


func _wave() -> WaveManager:
	return get_tree().current_scene.get_node_or_null("WaveManager") as WaveManager


func _powered() -> bool:
	var arena := get_tree().get_first_node_in_group("arena")
	return arena == null or arena.power_on


func _available() -> bool:
	var wm := _wave()
	return wm != null and _powered() and GameState.current_round >= EXFIL_ROUND and wm.in_intermission and wm.exfil_state == 0


func _process(delta: float) -> void:
	_t += delta
	var avail := _available()
	_lamp.light_color = Color(0.3, 1.0, 0.35) if avail else Color(1.0, 0.25, 0.15)
	_lamp.light_energy = (1.2 + sin(_t * 4.0) * 0.4) if avail else 0.6
	if avail and (_static_player == null or not _static_player.playing):
		if _static_player == null:
			_static_player = AudioStreamPlayer3D.new()
			_static_player.bus = &"SFX"
			_static_player.unit_size = 3.0
			_static_player.max_distance = 14.0
			_static_player.volume_db = -8.0
			add_child(_static_player)
			_static_player.position.y = 1.2
		if fmod(_t, 9.0) < delta:
			_static_player.stream = GameState.get_sfx_stream("radio_beep")
			_static_player.play()


func get_prompt(_player: Node3D) -> String:
	var wm := _wave()
	if wm == null:
		return ""
	if wm.exfil_state != 0:
		return "FIELD RADIO — EXTRACTION INBOUND"
	if not _powered():
		return "FIELD RADIO — NEEDS POWER (GENERATOR IN MOTOR POOL)"
	if GameState.current_round < EXFIL_ROUND:
		return "FIELD RADIO — EXTRACTION AVAILABLE FROM ROUND %d" % EXFIL_ROUND
	if not wm.in_intermission:
		return "FIELD RADIO — CALL EXTRACTION BETWEEN ROUNDS"
	return "[E] CALL EXTRACTION — SURVIVE 90s, THEN REACH THE LANDING ZONE"


func try_purchase(_player: Node3D) -> void:
	if _available():
		Net.world(self, "call")


func net_apply(action: String, _args: Array) -> void:
	if action == "call" and Net.is_host() and _available():
		_wave().start_exfil()
