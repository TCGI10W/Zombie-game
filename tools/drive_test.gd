extends SceneTree
# Dev helper: drives the depot truck (throttle, steer, brake), prints how it
# behaves, and saves chase + cockpit camera shots to user://drive_*.png.
var _t := 0.0
var _car: Node3D
var _start := Vector3.ZERO
var _phase := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _shot(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/drive_%s.png" % n)
func _process(delta: float) -> bool:
	_t += delta
	if _phase == 0 and _t > 6.0:
		for v in root.get_tree().get_nodes_in_group("vehicles"):
			if v.model == "truck":
				_car = v
				break
		var w0: Node3D = _car._wheel_nodes[0]
		print("parked: body y %.3f  wheel FL centre above ground %.3f (radius %.3f)" % [_car.global_position.y, w0.global_position.y - 0.0, _car.wheel_radius])
		_car.try_purchase(root.get_tree().get_first_node_in_group("player"))
		_start = _car.global_position
		_phase = 1
	elif _phase == 1 and _t > 7.5:
		_shot("chase_parked")
		Input.action_press("move_forward")
		_phase = 2
	elif _phase == 2 and _t > 11.5:
		print("4s throttle: %.1f m/s, moved %.1f m, up.y %.2f" % [_car.linear_velocity.length(), _car.global_position.distance_to(_start), _car.global_basis.y.y])
		_shot("chase_moving")
		Input.action_press("move_left")
		_phase = 3
	elif _phase == 3 and _t > 13.5:
		print("2s steer: %.1f m/s, yaw %.0f, up.y %.2f" % [_car.linear_velocity.length(), _car.rotation_degrees.y, _car.global_basis.y.y])
		Input.action_release("move_left")
		Input.action_release("move_forward")
		Input.action_press("move_back")
		var ev := InputEventAction.new()
		ev.action = "vehicle_camera"
		ev.pressed = true
		Input.parse_input_event(ev)
		_phase = 4
	elif _phase == 4 and _t > 16.0:
		print("2.5s brake: %.1f m/s" % _car.linear_velocity.length())
		_shot("cockpit")
		Input.action_release("move_back")
		quit()
	return false
