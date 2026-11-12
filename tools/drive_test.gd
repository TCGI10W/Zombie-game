extends SceneTree
# Dev helper: drives the depot truck, cycles all four camera stances (V),
# saves a shot of each to user://drive_<n>.png and prints how the car moves.
var _t := 0.0
var _car: Node3D
var _phase := 0
var _next := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")
func _shot(n: int) -> void:
	root.get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/drive_%d.png" % n)
func _cam_key() -> void:
	var ev := InputEventAction.new()
	ev.action = "vehicle_camera"
	ev.pressed = true
	Input.parse_input_event(ev)
func _process(delta: float) -> bool:
	_t += delta
	if _phase == 0 and _t > 6.0:
		for v in root.get_tree().get_nodes_in_group("vehicles"):
			if v.model == "truck":
				_car = v
				break
		_car.try_purchase(root.get_tree().get_first_node_in_group("player"))
		Input.action_press("move_forward")
		_phase = 1
		_next = _t + 3.5
	elif _phase >= 1 and _phase <= 4 and _t > _next:
		if _phase == 2:
			Input.action_press("move_left")
		if _phase == 3:
			Input.action_release("move_left")
		_shot(_phase - 1)
		print("stance %d shot: %.0f km/h" % [_phase - 1, _car.linear_velocity.length() * 3.6])
		_cam_key()
		_phase += 1
		_next = _t + 1.6
	elif _phase == 5:
		var pl := root.get_tree().get_first_node_in_group("player")
		pl.exit_vehicle()
		print("left the truck; driving=", pl.driving, " cam current=", pl.camera.current)
		quit()
	return false
