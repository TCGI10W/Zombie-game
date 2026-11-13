extends SceneTree
# Dev helper: renders Kessler Junction zone by zone to user://jx_<n>.png
# (HUD hidden, zombies cleared, a free camera per view).
const VIEWS := [
	[Vector3(-12, 3.2, 10), Vector3(6, 1, -8), "courtyard"],
	[Vector3(12, 2.0, -14.5), Vector3(-12, 1.2, -14.5), "motel corridor"],
	[Vector3(-4, 1.7, -18), Vector3(-6, 1.0, -24), "motel room"],
	[Vector3(17.5, 1.8, 10), Vector3(30, 1.0, -9), "diner"],
	[Vector3(-17.5, 2.2, 10), Vector3(-30, 1.0, -8), "garage"],
	[Vector3(-17.5, 1.8, -13), Vector3(-30, 1.0, -22), "office"],
	[Vector3(18, 2.2, 13), Vector3(30, 1.0, 32), "warehouse"],
	[Vector3(-17.5, 2.5, 13), Vector3(-30, 1.0, 32), "yard"],
	[Vector3(-40, 14, 56), Vector3(0, 0, 0), "outside"],
]
var _t := 0.0
var _booted := false
var _i := 0
var _cam: Camera3D
var _wait := 0.0
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("GameState").map_mode = "junction"
		change_scene_to_file("res://scenes/game.tscn")
		return false
	_t += delta
	if _t < 6.0:
		return false
	var scene := root.get_tree().current_scene
	if _cam == null:
		var hud := scene.get_node_or_null("GameHUD")
		if hud:
			for c in hud.get_children():
				if c is CanvasItem:
					c.visible = false
		_cam = Camera3D.new()
		_cam.fov = 75
		scene.add_child(_cam)
	for e in root.get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	root.get_tree().get_first_node_in_group("player").set("hp", 99999.0)
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/jx_%d.png" % (_i - 1))
		return false
	if _i >= VIEWS.size():
		print("JUNCTION SHOTS DONE")
		quit()
		return false
	var v: Array = VIEWS[_i]
	_cam.global_position = v[0]
	_cam.look_at(v[1], Vector3.UP)
	_cam.current = true
	_i += 1
	_wait = 1.0
	return false
