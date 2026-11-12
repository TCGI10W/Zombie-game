extends SceneTree
# Dev helper: round 1 with the player standing on the depot lot. Logs how
# spread out the horde is (closest zombie pairs, how many in reach) and saves
# a screenshot looking at them to user://horde.png.
var _t := 0.0
var _next := 10.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	var pl := root.get_tree().get_first_node_in_group("player") as Node3D
	if pl and _t > 5.0:
		pl.global_position = Vector3(0, 0.3, 2)
		pl.set("hp", 9999.0)
	if _t > _next:
		_next += 5.0
		var zs: Array = []
		for z in root.get_tree().get_nodes_in_group("enemies"):
			if z.get("is_dead") != true:
				zs.append(z)
		var pair_min := 99.0
		var close_pairs := 0
		var in_reach := 0
		for i in range(zs.size()):
			var a: Vector3 = zs[i].global_position
			if Vector2(a.x - pl.global_position.x, a.z - pl.global_position.z).length() < 1.6:
				in_reach += 1
			for j in range(i + 1, zs.size()):
				var d := Vector2(a.x - zs[j].global_position.x, a.z - zs[j].global_position.z).length()
				pair_min = minf(pair_min, d)
				if d < 0.8:
					close_pairs += 1
		print("fps=%d t=%d alive=%d in_reach=%d closest_pair=%.2f pairs<0.8m=%d" % [Engine.get_frames_per_second(), int(_t), zs.size(), in_reach, pair_min, close_pairs])
		if _t > 28.0 and _t < 34.0 and zs.size() > 0:
			var c := Vector3.ZERO
			for z in zs:
				c += z.global_position
			c /= zs.size()
			var to := c - pl.global_position
			pl.rotation.y = atan2(-to.x, -to.z)
	if _t > 34.0 and _t < 34.3:
		root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/horde.png")
	if _t > 36.0:
		quit()
	return false
