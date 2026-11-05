extends Node3D
# Medical cabinet that sells Second Wind: a self-revive charge. With one held,
# lethal damage knocks you down instead of killing you, and you get back up a
# few seconds later. Hold one at a time; three per game, each pricier.
# Origin on the floor; the cabinet front faces local -Z.

const COSTS := [1500, 2500, 4000]

var interact_radius: float = 2.6
var _light: OmniLight3D
var _label: Label3D
var _t: float = 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	if ResourceLoader.exists("res://assets/models/prop_med_station.glb"):
		add_child((load("res://assets/models/prop_med_station.glb") as PackedScene).instantiate())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 2.1, 0.6)
	cs.shape = bs
	cs.position.y = 1.05
	body.add_child(cs)
	add_child(body)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 1.0, 0.6)
	_light.light_energy = 1.3
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.3, -0.6)
	add_child(_light)

	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.15, 0.1)
	red.light_energy = 1.2
	red.omni_range = 3.0
	red.position = Vector3(0, 2.3, -0.3)
	add_child(red)

	_label = Label3D.new()
	_label.text = "SECOND WIND\nSELF-REVIVE"
	_label.font_size = 34
	_label.outline_size = 10
	_label.pixel_size = 0.0045
	_label.modulate = Color(0.55, 1.0, 0.7)
	_label.position = Vector3(0, 2.55, -0.2)
	_label.rotation.y = PI
	add_child(_label)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 1.2 + sin(_t * 2.2) * 0.25


func get_prompt(player: Node3D) -> String:
	if player.revives > 0:
		return "SECOND WIND READY — YOU WILL GET BACK UP ONCE"
	if player.revives_bought >= COSTS.size():
		return "SECOND WIND — CABINET EMPTY"
	return "[E] SECOND WIND (SELF-REVIVE)  —  %d PTS" % COSTS[player.revives_bought]


func try_purchase(player: Node3D) -> void:
	if player.is_monster_form or player.revives > 0 or player.revives_bought >= COSTS.size():
		return
	if GameState.try_pay(player, COSTS[player.revives_bought]):
		player.revives_bought += 1
		player.revives = 1
		GameState.play_sfx("second_wind", -6.0, 1.25)
		player.status_banner_requested.emit("SECOND WIND ACQUIRED — YOU WILL GET BACK UP ONCE", Color(0.4, 1.0, 0.6))
		player.stats_changed.emit()
