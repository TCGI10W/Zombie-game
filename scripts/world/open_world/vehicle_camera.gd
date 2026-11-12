class_name VehicleCamera
extends Node3D
# Driving camera, ported from kashta's CameraRig: a third-person CHASE cam
# that orbits with the mouse and drifts back behind the car when the mouse is
# idle (collision pull-in so it never clips into hills or walls, FOV kick with
# speed, drift + landing shake), and a COCKPIT cam at the driver's eye.
# V switches between them. Created when the player gets in, freed on exit.

const ACTION := "vehicle_camera"

var chase_distance := 7.5
var chase_height := 2.6
var position_smooth := 6.0
var look_smooth := 8.0
var chase_fov := 70.0
var fov_kick := 10.0
var fov_kick_speed := 30.0
var mouse_sensitivity := 0.0035
var pitch_min := -0.25
var pitch_max := 1.1
var default_pitch := 0.22
var auto_center_delay := 2.0
var auto_center_speed := 2.5
var drift_threshold := 0.35
var drift_amount := 0.08
var land_min := 3.0
var land_full := 8.0
var land_amount := 0.18
var land_time := 0.35

static var use_chase := true  # remembered between rides

var car: DriveVehicle
var _chase: Camera3D
var _cockpit: Camera3D
var _yaw := 0.0
var _pitch := 0.22
var _cockpit_pitch := 0.0
var _idle := 999.0
var _look := Vector3.ZERO
var _last_shake := Vector3.ZERO
var _shake_t := 0.0
var _was_grounded := true
var _fall := 0.0
var _land_left := 0.0
var _land_peak := 0.0


func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event(ACTION, ev)
	top_level = true
	_chase = Camera3D.new()
	_chase.fov = chase_fov
	_chase.far = 900.0
	add_child(_chase)
	_cockpit = Camera3D.new()
	_cockpit.fov = 75.0
	_cockpit.near = 0.05
	add_child(_cockpit)
	_pitch = default_pitch
	if car:
		var behind := car.global_position + car.global_basis.z * chase_distance + Vector3.UP * chase_height
		_chase.global_position = behind
		_look = car.global_position + Vector3.UP * 1.2
	_apply()


func _apply() -> void:
	_chase.current = use_chase
	_cockpit.current = not use_chase
	_last_shake = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var sens := mouse_sensitivity * GameState.mouse_sens_mult
		_yaw -= m.relative.x * sens
		var dy: float = -m.relative.y if GameState.invert_y else m.relative.y
		_pitch = clampf(_pitch + dy * sens, pitch_min, pitch_max)
		_cockpit_pitch = clampf(_cockpit_pitch - dy * sens, -1.2, 1.2)
		_idle = 0.0
	elif event.is_action_pressed(ACTION):
		use_chase = not use_chase
		_apply()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car):
		return
	_idle += delta
	if _idle > auto_center_delay:
		var t := clampf(auto_center_speed * delta, 0.0, 1.0)
		_yaw = lerpf(_yaw, 0.0, t)
		_pitch = lerpf(_pitch, default_pitch, t)
		_cockpit_pitch = lerpf(_cockpit_pitch, 0.0, t)
	var land := _landing(delta)
	var spd := car.linear_velocity.length()
	# cockpit: the driver's eye, mouse look on top of the car's heading
	var eye := car.eye_transform()
	var look_b := Basis.from_euler(Vector3(_cockpit_pitch, _yaw, 0.0), EULER_ORDER_YXZ)
	_cockpit.global_transform = Transform3D(eye.basis * look_b, eye.origin + land)
	_cockpit.fov = lerpf(_cockpit.fov, 75.0 + clampf(spd / 30.0, 0.0, 1.0) * 8.0, clampf(4.0 * delta, 0.0, 1.0))
	if not use_chase:
		return
	# chase: orbit behind the car, smoothed, pulled in front of obstacles
	var behind := car.global_basis.z
	behind.y = 0.0
	behind = behind.normalized() if behind.length() > 0.01 else Vector3.BACK
	var dir := behind.rotated(Vector3.UP, _yaw)
	var desired := car.global_position + dir * cos(_pitch) * chase_distance + Vector3.UP * (chase_height + sin(_pitch) * chase_distance)
	desired = _avoid(desired)
	_chase.global_position -= _last_shake
	_chase.global_position = _chase.global_position.lerp(desired, clampf(position_smooth * delta, 0.0, 1.0))
	var shake := _drift(delta) + land
	_chase.global_position += shake
	_last_shake = shake
	_look = _look.lerp(car.global_position + Vector3.UP * 1.2, clampf(look_smooth * delta, 0.0, 1.0))
	if _chase.global_position.distance_to(_look) > 0.1:
		_chase.look_at(_look, Vector3.UP)
	_chase.fov = lerpf(_chase.fov, chase_fov + clampf(spd / fov_kick_speed, 0.0, 1.0) * fov_kick, clampf(4.0 * delta, 0.0, 1.0))


func _drift(delta: float) -> Vector3:
	if car.slip <= drift_threshold:
		_shake_t = 0.0
		return Vector3.ZERO
	var amt := drift_amount * clampf((car.slip - drift_threshold) / (1.0 - drift_threshold), 0.0, 1.0)
	_shake_t += delta
	var w := _shake_t * 25.0 * TAU
	return Vector3(sin(w) + randf_range(-1, 1), sin(w * 1.3 + 1.7) + randf_range(-1, 1), sin(w * 0.7 + 3.1) + randf_range(-1, 1)) * 0.5 * amt


func _landing(delta: float) -> Vector3:
	if car.grounded and not _was_grounded:
		var k := clampf((absf(_fall) - land_min) / (land_full - land_min), 0.0, 1.0)
		if k > 0.0:
			_land_peak = land_amount * k
			_land_left = land_time
		_fall = 0.0
	elif not car.grounded:
		_fall = minf(_fall, car.linear_velocity.y)
	_was_grounded = car.grounded
	if _land_left <= 0.0:
		return Vector3.ZERO
	_land_left = maxf(_land_left - delta, 0.0)
	var life := _land_left / land_time
	var w := (land_time - _land_left) * 28.0 * TAU
	return Vector3(sin(w) + randf_range(-1, 1), sin(w * 1.5 + 0.7) + randf_range(-1, 1), sin(w * 0.9 + 2.3)) * 0.5 * _land_peak * life * life


func _avoid(desired: Vector3) -> Vector3:
	var pivot := car.global_position + Vector3.UP * 1.6
	var to := desired - pivot
	var d := to.length()
	if d < 0.01:
		return desired
	var q := PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	q.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return desired
	return pivot + to / d * maxf(pivot.distance_to(hit["position"]) - 0.3, 0.8)
