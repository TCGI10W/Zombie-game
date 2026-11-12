extends SceneTree
# Dev helper: puts the player in the depot pickup, holds throttle + steer,
# and reports how the car moved (speed, upright, distance).
var _t := 0.0
var _car: Node3D
var _start := Vector3.ZERO
var _phase := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _phase == 0 and _t > 6.0:
		var pl := root.get_tree().get_first_node_in_group("player")
		for v in root.get_tree().get_nodes_in_group("vehicles"):
			if v.title == "PICKUP":
				_car = v
				break
		_car.try_purchase(pl)
		_start = _car.global_position
		print("start ", _start, " rest y basis ", _car.global_basis.y)
		Input.action_press("move_forward")
		_phase = 1
	elif _phase == 1 and _t > 10.0:
		print("after 4s throttle: speed %.1f m/s  moved %.1f m  up.y %.2f" % [_car.linear_velocity.length(), _car.global_position.distance_to(_start), _car.global_basis.y.y])
		Input.action_press("move_left")
		_phase = 2
	elif _phase == 2 and _t > 12.0:
		print("after 2s steer: speed %.1f  yaw %.0f deg  up.y %.2f" % [_car.linear_velocity.length(), _car.rotation_degrees.y, _car.global_basis.y.y])
		Input.action_release("move_left")
		Input.action_release("move_forward")
		Input.action_press("move_back")
		_phase = 3
	elif _phase == 3 and _t > 15.0:
		print("after 3s brake: speed %.1f  up.y %.2f" % [_car.linear_velocity.length(), _car.global_basis.y.y])
		var pl := root.get_tree().get_first_node_in_group("player")
		print("player rides at ", pl.global_position.distance_to(_car.global_position), " m from car")
		quit()
	return false
