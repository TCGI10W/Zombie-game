extends SceneTree
# Dev helper: lets round 1 run with the player parked on the depot lot and
# logs how close zombies get over time (are they pathing in, or stuck?).
var _t := 0.0
var _next := 8.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	if pl and _t > 5.0:
		pl.global_position = Vector3(0, 0.3, 2)
		pl.set("hp", 9999.0)
	if _t > _next:
		_next += 4.0
		var ds: Array = []
		for z in root.get_tree().get_nodes_in_group("enemies"):
			if z.get("is_dead") != true:
				ds.append(snappedf((z as Node3D).global_position.distance_to(pl.global_position), 0.1))
		ds.sort()
		print("t=%d alive=%d nearest=%s" % [int(_t), ds.size(), str(ds.slice(0, 8))])
	if _t > 44.0:
		quit()
	return false
