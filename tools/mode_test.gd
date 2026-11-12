extends SceneTree
# Dev helper: boots one mode and reports the zombie population over time.
#   godot -s tools/mode_test.gd -- classic|outbreak
var _t := 0.0
var _next := 8.0
var _mode := "outbreak"
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_mode = a[0]
var _booted := false
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("GameState").map_mode = _mode  # after the save has loaded
		change_scene_to_file("res://scenes/game.tscn")
		return false
	_t += delta
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	if pl and _t > 5.0:
		pl.set("hp", 9999.0)
	if _t > _next:
		_next += 6.0
		var arena := root.get_tree().get_first_node_in_group("arena")
		var wm := root.get_tree().current_scene.get_node("WaveManager")
		var n := 0; var amb := 0; var wander := 0; var chase := 0; var near := 99.0
		for z in root.get_tree().get_nodes_in_group("enemies"):
			if z.get("is_dead") == true:
				continue
			n += 1
			if z.get("ambient") == true: amb += 1
			if z.get("wandering") == true: wander += 1
			else: chase += 1
			near = minf(near, (z as Node3D).global_position.distance_to(pl.global_position))
		print("[%s] t=%d arena=%s wm=%s alive=%d ambient=%d wandering=%d hunting=%d nearest=%.1f round_alive=%d to_spawn=%d fps=%d proc=%.1fms phys=%.1fms draws=%d" % [_mode, int(_t), arena.get_class() if arena.get_script() == null else arena.get_script().get_global_name(), wm.get_script().get_global_name(), n, amb, wander, chase, near, wm.alive_enemies, wm.zombies_to_spawn, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _t > 40.0:
		quit()
	return false
