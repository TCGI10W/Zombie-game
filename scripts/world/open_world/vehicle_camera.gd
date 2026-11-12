class_name VehicleCamera
extends Node3D
# Driving camera, grown from kashta's CameraRig. One Camera3D, four stances,
# cycled with V and blended over a short ease so a switch never pops:
#   CHASE      behind the car, sized from its length; leans its aim into
#              turns and toward where the car is heading (look-ahead)
#   FAR CHASE  higher and further back, for steering through a horde
#   BONNET     on the hood looking down the road
#   COCKPIT    the driver's eye, inside the cab
# Chase stances orbit with the mouse and drift back behind the car after a
# moment idle; collision pull-in keeps them out of hills and walls. FOV
# widens with speed; drift slip and hard landings add a small shake.
# Reversing fast swings the chase cams round to look back the way you go.

const ACTION := "vehicle_camera"
const STANCES := ["CHASE", "FAR CHASE", "BONNET", "COCKPIT"]

static var stance := 0  # remembered between rides

var car: DriveVehicle
var cam: Camera3D
var mouse_sensitivity := 0.0035
var auto_center_delay := 1.6
var auto_center_speed := 2.2

var _yaw := 0.0
var _pitch := 0.0
var _look_pitch := 0.0
var _idle := 999.0
var _pos := Vector3.ZERO
var _aim := Vector3.ZERO
var _blend := 1.0
var _from := Transform3D.IDENTITY
var _reverse_t := 0.0
var _rev_yaw := 0.0
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
	cam = Camera3D.new()
	cam.far = 900.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	if car:
		_pos = _chase_target(0.0)[0]
		_aim = car.global_position + Vector3.UP * car.body_height * 0.6
		cam.global_transform = Transform3D(Basis.IDENTITY, _pos).looking_at(_aim, Vector3.UP)
		_from = cam.global_transform


func stance_name() -> String:
	return STANCES[stance]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var sens := mouse_sensitivity * GameState.mouse_sens_mult
		_yaw -= m.relative.x * sens
		var dy: float = -m.relative.y if GameState.invert_y else m.relative.y
		_pitch = clampf(_pitch + dy * sens, -0.35, 0.9)
		_look_pitch = clampf(_look_pitch - dy * sens, -1.1, 1.1)
		_idle = 0.0
	elif event.is_action_pressed(ACTION):
		stance = (stance + 1) % STANCES.size()
		_from = cam.global_transform
		_blend = 0.0
		_yaw = 0.0
		_pitch = 0.0
		_look_pitch = 0.0


# [position, aim point] for a chase stance.
func _chase_target(delta: float) -> Array:
	var far := stance == 1
	var L := car.body_length
	var dist := L * (1.35 if far else 0.95) + (4.0 if far else 2.2)
	var height := car.body_height * (1.7 if far else 1.05) + (1.5 if far else 0.4)
	var flat_back := car.global_basis.z
	flat_back.y = 0.0
	flat_back = flat_back.normalized() if flat_back.length() > 0.01 else Vector3.BACK
	var speed := car.linear_velocity.dot(-car.global_basis.z)
	# reversing for a while: swing round to watch where the car is going
	if speed < -3.0:
		_reverse_t += delta
	else:
		_reverse_t = maxf(_reverse_t - delta * 2.0, 0.0)
	_rev_yaw = lerpf(_rev_yaw, PI if _reverse_t > 0.8 else 0.0, clampf(delta * 2.5, 0.0, 1.0))
	var dir := flat_back.rotated(Vector3.UP, _yaw + _rev_yaw)
	var p := _pitch + (0.12 if far else 0.0)
	var pos := car.global_position + dir * cos(p) * dist + Vector3.UP * (height + sin(p) * dist)
	# aim a little ahead of the car along its motion, and into the turn
	var vel := car.linear_velocity
	vel.y = 0.0
	var ahead := vel.limit_length(18.0) * 0.35
	var aim := car.global_position + Vector3.UP * car.body_height * 0.55 + ahead
	return [_avoid(pos, aim), aim]


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car):
		return
	_idle += delta
	if _idle > auto_center_delay:
		var t := clampf(auto_center_speed * delta, 0.0, 1.0)
		_yaw = lerpf(_yaw, 0.0, t)
		_pitch = lerpf(_pitch, 0.0, t)
		_look_pitch = lerpf(_look_pitch, 0.0, t)
	var spd := car.linear_velocity.length()
	var land := _landing(delta)
	var target: Transform3D
	var base_fov := 70.0
	if stance <= 1:
		var ct := _chase_target(delta)
		cam.global_position -= _last_shake
		_pos = _pos.lerp(ct[0], clampf(7.0 * delta, 0.0, 1.0))
		_aim = _aim.lerp(ct[1], clampf(9.0 * delta, 0.0, 1.0))
		target = Transform3D(Basis.IDENTITY, _pos).looking_at(_aim, Vector3.UP)
		base_fov = 68.0 if stance == 0 else 62.0
	else:
		var anchor := car.eye_transform() if stance == 3 else car.bonnet_transform()
		var look := Basis.from_euler(Vector3(_look_pitch - (0.06 if stance == 2 else 0.0), _yaw, 0.0), EULER_ORDER_YXZ)
		target = Transform3D(anchor.basis * look, anchor.origin)
		# keep the horizon level-ish over bumps (less nausea, more PS1 racer)
		var level := Basis.looking_at(-target.basis.z, Vector3.UP)
		target.basis = target.basis.slerp(level, 0.6)
		base_fov = 78.0 if stance == 3 else 74.0
		_pos = target.origin
		_aim = target.origin - target.basis.z * 10.0
	# ease from wherever the camera was when the stance changed
	if _blend < 1.0:
		_blend = minf(_blend + delta / 0.45, 1.0)
		var e := _blend * _blend * (3.0 - 2.0 * _blend)
		target = _from.interpolate_with(target, e)
	var shake := (_drift(delta) if stance <= 1 else Vector3.ZERO) + land
	cam.global_transform = target
	cam.global_position += shake
	_last_shake = shake
	var kick := clampf(spd / 28.0, 0.0, 1.0) * (11.0 if stance <= 1 else 7.0)
	cam.fov = lerpf(cam.fov, base_fov + kick, clampf(4.0 * delta, 0.0, 1.0))


func _drift(delta: float) -> Vector3:
	if car.slip <= 0.35:
		_shake_t = 0.0
		return Vector3.ZERO
	var amt := 0.08 * clampf((car.slip - 0.35) / 0.65, 0.0, 1.0)
	_shake_t += delta
	var w := _shake_t * 25.0 * TAU
	return Vector3(sin(w) + randf_range(-1, 1), sin(w * 1.3 + 1.7) + randf_range(-1, 1), sin(w * 0.7 + 3.1) + randf_range(-1, 1)) * 0.5 * amt


func _landing(delta: float) -> Vector3:
	if car.grounded and not _was_grounded:
		var k := clampf((absf(_fall) - 3.0) / 5.0, 0.0, 1.0)
		if k > 0.0:
			_land_peak = 0.18 * k
			_land_left = 0.35
		_fall = 0.0
	elif not car.grounded:
		_fall = minf(_fall, car.linear_velocity.y)
	_was_grounded = car.grounded
	if _land_left <= 0.0:
		return Vector3.ZERO
	_land_left = maxf(_land_left - delta, 0.0)
	var life := _land_left / 0.35
	var w := (0.35 - _land_left) * 28.0 * TAU
	return Vector3(sin(w) + randf_range(-1, 1), sin(w * 1.5 + 0.7) + randf_range(-1, 1), sin(w * 0.9 + 2.3)) * 0.5 * _land_peak * life * life


func _avoid(desired: Vector3, _aim_pt: Vector3) -> Vector3:
	var pivot := car.global_position + Vector3.UP * car.body_height * 0.8
	var to := desired - pivot
	var d := to.length()
	if d < 0.01:
		return desired
	var q := PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	q.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return desired
	var safe: Vector3 = pivot + to / d * maxf(pivot.distance_to(hit["position"]) - 0.4, 1.0)
	return safe + Vector3.UP * 0.6  # rise over what's blocking, so the car stays in shot
