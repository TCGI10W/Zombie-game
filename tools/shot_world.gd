extends SceneTree
# Dev helper: boots the game, then teleports the player to each open-world
# location and saves a screenshot of each to user://world_<n>.png.
var _t := 0.0
var _n := 0
var _t0 := 0
const SPOTS := [
	[Vector3(-4, 1.2, -22), 200.0, -5.0],     # depot lot looking at diner/garage
	[Vector3(-262, 1.2, 140), 160.0, -4.0],   # farm yard
	[Vector3(262, 1.2, 214), 0.0, -4.0],      # village street
	[Vector3(236, 1.2, -238), -90.0, -3.0],   # town main street
	[Vector3(-262, 1.2, -238), 0.0, -4.0],    # power plant
	[Vector3(120, 1.5, 100), 210.0, -2.0],    # road through the wilds
]
func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _n == 0 and _t < 0.05:
		return false
	if _t > 7.0 + _n * 2.0:
		if _n > 0:
			root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/world_%d.png" % (_n - 1))
		if _n >= SPOTS.size():
			print("SHOTS DONE, boot+tour ms: ", Time.get_ticks_msec() - _t0)
			quit()
			return false
		var pl := root.get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			var s: Array = SPOTS[_n]
			pl.global_position = s[0]
			pl.rotation_degrees.y = s[1]
		_n += 1
	return false
