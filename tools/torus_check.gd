extends SceneTree
# Dev helper: counts swinging chandeliers (TorusMesh) in the running map.
var _t := 0.0
var _booted := false
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		var a := OS.get_cmdline_user_args()
		root.get_node("GameState").map_mode = a[0] if a.size() > 0 else "outbreak"
		change_scene_to_file("res://scenes/game.tscn")
		return false
	_t += delta
	if _t > 7.0:
		var n := 0
		for m in root.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).mesh is TorusMesh and (m as Node3D).global_position.y > 5.0:
				n += 1
		print("hanging rings in the air: ", n)
		quit()
	return false
