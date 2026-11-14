extends SceneTree
# Dev helper: renders Halloway Mill zone by zone to user://jx_<n>.png
# (HUD hidden, zombies cleared, a free camera per view).
const VIEWS := [
	[Vector3(6, 75, 2), Vector3(6, 0, 1.9), "overhead off", false, true],
	[Vector3(-6, 1.8, 25), Vector3(6, 1, 15), "office", false, false],
	[Vector3(-10, 4, 12), Vector3(20, 0.5, 2), "yard", false, false],
	[Vector3(-6, 2.2, -4), Vector3(22, 1, -17), "mill", false, false],
	[Vector3(-26, 2.0, 4), Vector3(-14, 1, -7), "store", false, false],
	[Vector3(-4, 2.2, -22), Vector3(22, 1, -34), "kiln", false, false],
	[Vector3(-13, 2.0, -23), Vector3(-29, 1, -35), "house", false, false],
	[Vector3(30, 3, 32), Vector3(40, 1, 2), "power+landing", false, false],
	[Vector3(-20, 30, 60), Vector3(6, 0, 0), "outside", false, false],
	[Vector3(6, 75, 2), Vector3(6, 0, 1.9), "overhead on", true, true],
	[Vector3(-10, 4, 12), Vector3(20, 0.5, 2), "yard on", true, false],
	[Vector3(-6, 2.2, -4), Vector3(22, 1, -17), "mill on", true, false],
]
var _t := 0.0
var _booted := false
var _i := 0
var _cam: Camera3D
var _wait := 0.0
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("GameState").map_mode = "mill"
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
			root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mill_%d.png" % (_i - 1))
		return false
	if _i >= VIEWS.size():
		print("MILL SHOTS DONE")
		quit()
		return false
	var v: Array = VIEWS[_i]
	var ar := scene.get_node("BunkerArena")
	if v[3] and not ar.power_on:
		ar.set_power(true)
	for r in ar.roofs:
		r.visible = not v[4]
	_cam.global_position = v[0]
	_cam.look_at(v[1], Vector3.UP)
	_cam.current = true
	_i += 1
	_wait = 1.0
	return false
