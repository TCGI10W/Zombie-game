extends SceneTree
# Dev helper: walks the player up to a wandering ambient zombie (does it
# notice and call its pack?), then moves far away (does it give up and get
# recycled near the player instead of being lost on the map?).
var _t := 0.0
var _booted := false
var _z: Node3D
var _phase := 0
func _process(delta: float) -> bool:
	if not _booted:
		_booted = true
		root.get_node("GameState").map_mode = "outbreak"
		change_scene_to_file("res://scenes/game.tscn")
		return false
	_t += delta
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	if pl and _t > 3.0:
		pl.set("hp", 9999.0)
	if _phase == 0 and _t > 9.0:
		for z in root.get_tree().get_nodes_in_group("enemies"):
			if z.get("ambient") == true and z.get("wandering") == true:
				_z = z
				break
		var to: Vector3 = (pl.global_position - _z.global_position)
		to.y = 0
		var stand: Vector3 = _z.global_position + to.normalized() * 15.0
		pl.global_position = stand + Vector3(0, 2, 0)
		print("placed player 15 m from a wandering zombie (pack nearby: %d)" % _pack())
		_phase = 1
	elif _phase == 1 and _t > 12.0:
		print("after 3 s: wandering=%s target=%s  pack still wandering: %d" % [str(_z.get("wandering")), str(_z.get("target_player") == pl), _pack()])
		pl.global_position = Vector3(260, 2, 220)  # off to the village, ~250 m away
		_phase = 2
	elif _phase == 2 and _t > 26.0:
		var d := _z.global_position.distance_to(pl.global_position) if is_instance_valid(_z) else -1.0
		print("14 s after leaving: zombie now %.0f m from player, wandering=%s" % [d, str(_z.get("wandering"))])
		quit()
	return false
func _pack() -> int:
	var n := 0
	for z in root.get_tree().get_nodes_in_group("enemies"):
		if z != _z and z.get("wandering") == true and (z as Node3D).global_position.distance_to(_z.global_position) < 11.0:
			n += 1
	return n
