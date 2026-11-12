extends SceneTree
# Dev helper: renders every open-world location (or one) from its review
# views and saves user://loc_<id>_<n>.png. HUD hidden, a free camera per view.
#   godot -s tools/location_shots.gd -- [location_id]
var _t := 0.0
var _booted := false
var _queue: Array = []
var _cam: Camera3D
var _wait := 0.0
var _cur := ""
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("GameState").map_mode = "outbreak"
		change_scene_to_file("res://scenes/game.tscn")
		return false
	_t += delta
	if _t < 6.0:
		return false
	var scene := root.get_tree().current_scene
	if _cam == null:
		var only := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
		var world := root.get_tree().get_first_node_in_group("arena")
		for loc in world._locs:
			if only != "" and loc.id != only:
				continue
			for i in range(loc.views.size()):
				_queue.append([loc.id, i, loc.views[i][0], loc.views[i][1]])
		var hud := scene.get_node_or_null("GameHUD")
		if hud:
			hud.visible = false
			for c in hud.get_children():
				if c is CanvasItem:
					c.visible = false
		for e in root.get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
		root.get_tree().get_first_node_in_group("player").set("hp", 99999.0)
		_cam = Camera3D.new()
		_cam.fov = 70
		scene.add_child(_cam)
		_wait = 0.0
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/loc_%s.png" % _cur)
		return false
	if _queue.is_empty():
		print("LOCATION SHOTS DONE")
		quit()
		return false
	var v: Array = _queue.pop_front()
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	pl.global_position = v[2] + Vector3(0, 40, 0)  # stream navmesh / keep near
	_cam.global_position = v[2]
	_cam.look_at(v[3], Vector3.UP)
	_cam.current = true
	_cur = "%s_%d" % [v[0], v[1]]
	_wait = 1.2
	return false
