extends SceneTree
# Dev helper: boots the game scene, waits, saves screenshots to user://.
var _t := 0.0
var _n := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _t > 6.0 + _n * 1.5:
		var cam := root.get_viewport().get_camera_3d()
		if cam and _n > 0:
			cam.global_rotation.y += deg_to_rad(120.0)
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_%d.png" % _n)
		_n += 1
		if _n >= 3:
			quit()
	return false
