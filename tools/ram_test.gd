extends SceneTree
# Dev helper: lines zombies up in front of the depot truck, floors it and
# reports how many were run down and what the truck's speed did.
var _t := 0.0
var _car: RigidBody3D
var _zs: Array = []
var _phase := 0
var _top := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _phase == 0 and _t > 6.0:
		for v in root.get_tree().get_nodes_in_group("vehicles"):
			_car = v
			break
		var pl := root.get_tree().get_first_node_in_group("player")
		pl.set("hp", 9999.0)
		_car.try_purchase(pl)
		var wm := root.get_tree().current_scene.get_node("WaveManager")
		var fwd := -_car.global_basis.z
		for i in range(6):
			var p := _car.global_position + fwd * (30.0 + i * 4.0) + _car.global_basis.x * (i % 3 - 1) * 1.0
			var arena := root.get_tree().get_first_node_in_group("arena")
			p.y = arena.terrain.height_at(p.x, p.z) + 0.3
			_zs.append(wm._spawn_regular_zombie(1, p, "walker"))
		Input.action_press("move_forward")
		_phase = 1
	elif _phase == 1:
		_top = maxf(_top, _car.linear_velocity.length())
		if _t > 16.0:
			var dead := 0
			for z in _zs:
				if not is_instance_valid(z) or z.get("is_dead") == true:
					dead += 1
			for z in _zs:
				if is_instance_valid(z) and z.get("is_dead") != true:
					var l: Vector3 = _car.global_transform.affine_inverse() * z.global_position
					print("  survivor local %s  dist %.1f  stun %.1f" % [str(l.snapped(Vector3.ONE * 0.1)), l.length(), z.get("stun_timer")])
			print("ram test: %d/%d zombies down, top speed %.0f km/h, now %.0f km/h, up.y %.2f" % [dead, _zs.size(), _top * 3.6, _car.linear_velocity.length() * 3.6, _car.global_basis.y.y])
			quit()
	return false
