extends SceneTree
# Dev helper: boots the game scene, turns the camera, saves screenshots to user://.
var _t := 0.0
var _n := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _t > 6.0 + _n * 1.0:
		root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%d.png" % _n)
		_n += 1
		var cam := root.get_viewport().get_camera_3d()
		if cam:
			var p := cam.get_parent() as Node3D
			if p and p is CharacterBody3D:
				p.rotation.y += deg_to_rad(90.0)
			else:
				cam.rotation.y += deg_to_rad(90.0)
		if _n >= 4:
			quit()
	return false
