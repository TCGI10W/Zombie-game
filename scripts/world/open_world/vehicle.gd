class_name DriveVehicle
extends RigidBody3D
# Light arcade car for the open world (raycast suspension on a RigidBody3D).
# Each wheel casts a ray; the spring is PRELOADED with a quarter of the car's
# weight, so at rest every wheel sits exactly one radius above the ground and
# the body never floats. Grip is a sideways force per wheel, rear-wheel drive.
# Enter / leave with interact (it sits in "wall_stations" like any buyable),
# move keys drive, jump = handbrake, V = chase / cockpit camera.
# model "truck" = SS-07 from scrap-shift (full cab interior, opening doors,
# steering wheel) via TruckModel; any other value is a world-kit glb car.

@export var model := "truck"
@export var title := "SS-07 TRUCK"
@export var engine_force := 9000.0
@export var max_speed := 24.0  # m/s (~86 km/h)

const SPRING := 42000.0
const DAMP := 3800.0
const TRAVEL := 0.22  # suspension up-travel above the rest point
const DROOP := 0.3    # how far a wheel can hang below rest before it leaves the ground

var interact_radius := 4.2
var driver: Node3D = null
var grounded := false
var slip := 0.0
var wheel_radius := 0.42
var seat_local := Vector3(-0.38, 1.05, 0.15)
var eye_local := Vector3(-0.38, 1.6, 0.15)
var bonnet_local := Vector3(0, 1.3, -1.4)
var body_length := 4.4  # camera framing
var body_height := 1.9
var _truck: Node3D = null  # TruckModel when model == "truck"
var _wheel_nodes: Array[Node3D] = []  # pivots (steer + height)
var _spin_nodes: Array[Node3D] = []   # roll
var _wheel_rest: Array[Vector3] = []
var _steer := 0.0
var _spin := 0.0
var _hit_cd: Dictionary = {}
var _engine: AudioStreamPlayer3D
var _phase := 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("vehicles")
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_hit)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	angular_damp = 1.2
	if model == "truck":
		_setup_truck()
	else:
		_setup_kit_car()


func _setup_truck() -> void:
	mass = 2200.0
	center_of_mass = Vector3(0, 0.75, 0)
	_truck = TruckModel.new()
	add_child(_truck)
	wheel_radius = 0.537
	for i in range(4):
		_wheel_nodes.append(_truck.wheels[i])
		_spin_nodes.append(_truck.spins[i])
		_wheel_rest.append(_truck.wheels[i].position)
	seat_local = TruckKit.point("body", "seat") + Vector3(0, 0.1, 0)
	bonnet_local = Vector3(0.0, 2.32, -2.6)
	body_length = 8.3
	body_height = 3.05
	eye_local = TruckKit.point("body", "eye")
	for b: Array in TruckKit.info("body").get("boxes", []):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(b[3]), float(b[4]), float(b[5]))
		cs.shape = bs
		cs.position = Vector3(float(b[0]), float(b[1]), float(b[2]))
		add_child(cs)


func _setup_kit_car() -> void:
	mass = 1300.0
	engine_force = 5200.0
	max_speed = 26.0
	center_of_mass = Vector3(0, 0.45, 0)
	var path := "res://art/models/%s.glb" % model
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		add_child(m)
		for tag in ["FL", "FR", "RL", "RR"]:
			var w := m.find_child("Wheel_" + tag, true, false) as Node3D
			if w:
				_wheel_nodes.append(w)
				_spin_nodes.append(w)
				_wheel_rest.append(w.position)
		if not _wheel_rest.is_empty():
			wheel_radius = _wheel_rest[0].y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.9, 4.3)
	cs.shape = bs
	cs.position = Vector3(0, wheel_radius + 0.55, 0)
	add_child(cs)
	seat_local = Vector3(-0.4, wheel_radius + 0.55, 0.1)
	eye_local = seat_local + Vector3(0, 0.6, 0)
	bonnet_local = Vector3(0, wheel_radius + 1.05, -1.3)


# ---------------------------------------------------------------- station API
func get_prompt(_player: Node) -> String:
	return "" if driver else "[E] DRIVE %s" % title


func try_purchase(player: Node) -> void:
	if driver or not player.has_method("enter_vehicle"):
		return
	driver = player
	_swing_door()
	player.enter_vehicle(self)
	sleeping = false
	if _truck:
		_truck.lights_on = true


func leave(_player: Node) -> Vector3:
	driver = null
	_swing_door()
	if _truck:
		_truck.lights_on = false
	return global_transform * Vector3(-2.3, 0.4, -0.6)


func _swing_door() -> void:
	if _truck == null:
		return
	var tw := create_tween()
	tw.tween_method(func(a: float): _truck.set_door("door_fl", a), 0.0, 1.1, 0.25)
	tw.tween_interval(0.35)
	tw.tween_method(func(a: float): _truck.set_door("door_fl", a), 1.1, 0.0, 0.3)


func seat_position() -> Vector3:
	return global_transform * seat_local


func bonnet_transform() -> Transform3D:
	return Transform3D(global_basis, global_transform * bonnet_local)


func eye_transform() -> Transform3D:
	return Transform3D(global_basis, global_transform * eye_local)


# ---------------------------------------------------------------- driving
func _physics_process(delta: float) -> void:
	if _wheel_rest.size() < 4:
		return
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver and not (Net.is_online() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		throttle = -v.y
		steer_in = -v.x
		handbrake = Input.is_action_pressed("jump")
	var fwd := -global_basis.z
	var up := global_basis.y
	var speed := linear_velocity.dot(fwd)
	# less steering lock at speed keeps the truck stable on the road
	var lock := lerpf(0.6, 0.22, clampf(absf(speed) / max_speed, 0.0, 1.0))
	_steer = move_toward(_steer, steer_in * lock, delta * 2.2)
	var space := get_world_3d().direct_space_state
	var preload_force := mass * 9.8 / 4.0
	var touching := 0
	var side_slip := 0.0
	for k in range(4):
		var rest := _wheel_rest[k]
		var origin := global_transform * (rest + Vector3(0, TRAVEL, 0))
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * (TRAVEL + DROOP + wheel_radius))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var comp := -DROOP  # positive = pushed up into the arch
		if hit:
			var dist: float = origin.distance_to(hit["position"]) - wheel_radius  # origin -> wheel centre
			comp = TRAVEL - dist
		if hit and comp > -DROOP:
			touching += 1
			var p: Vector3 = hit["position"]
			var arm := p - global_position
			var vel := linear_velocity + angular_velocity.cross(arm)
			var spring := maxf(preload_force + comp * SPRING - vel.dot(up) * DAMP, 0.0)
			var f := up * spring
			var side := global_basis.x
			if k < 2:
				side = side.rotated(up, _steer)
			var lat := vel.dot(side)
			side_slip += absf(lat)
			var grip := 0.3 if handbrake and k >= 2 else 1.0
			f -= side * clampf(lat * mass * 0.25 / delta * 0.2 * grip, -spring * 1.4, spring * 1.4)
			if k >= 2:
				if throttle != 0.0 and absf(speed) < max_speed:
					var braking := (throttle < 0.0 and speed > 1.0) or (throttle > 0.0 and speed < -1.0)
					f += fwd * engine_force * 0.5 * throttle * (1.8 if braking else 1.0)
				if handbrake:
					f -= fwd * vel.dot(fwd) * mass * 0.1
			apply_force(f, arm)
		var vis := clampf(comp, -DROOP, TRAVEL)
		_wheel_nodes[k].position = rest + Vector3(0, vis, 0)
		if _truck:
			_wheel_nodes[k].rotation.y = _steer if k < 2 else 0.0
			_spin_nodes[k].rotation.x = _spin
		else:
			_wheel_nodes[k].rotation = Vector3(_spin, _steer if k < 2 else 0.0, 0)
	grounded = touching > 0
	slip = clampf(side_slip / 4.0 / maxf(linear_velocity.length(), 4.0), 0.0, 1.0)
	_spin -= speed * delta / wheel_radius
	if _truck and _truck.steer:
		_truck.steer.rotation.z = -_steer * 4.0
	if grounded:
		apply_central_force(-linear_velocity * 60.0 - linear_velocity * linear_velocity.length() * 1.6)
		if driver == null and throttle == 0.0:
			linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 3.0)
	# right itself if it ends up on its side
	if up.y < 0.25 and linear_velocity.length() < 1.5:
		var t := global_transform
		t.basis = Basis(Vector3.UP, global_rotation.y)
		t.origin += Vector3(0, 1.2, 0)
		global_transform = t
		angular_velocity = Vector3.ZERO
	_engine_sound(absf(speed), throttle)
	for b in _hit_cd.keys():
		_hit_cd[b] -= delta
		if _hit_cd[b] <= 0.0:
			_hit_cd.erase(b)


func _engine_sound(speed: float, throttle: float) -> void:
	if driver and _engine == null:
		_engine = AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.1
		_engine.stream = gen
		_engine.volume_db = -6.0
		add_child(_engine)
		_engine.play()
	if _engine == null:
		return
	var pb := _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var rpm := 26.0 + speed * 3.2 + absf(throttle) * 16.0
	for i in range(pb.get_frames_available()):
		_phase = fmod(_phase + rpm / 22050.0, 1.0)
		var s := (0.5 if _phase < 0.2 else -0.13) * (0.2 if driver == null else 0.55)
		pb.push_frame(Vector2(s, s))


func _on_hit(body: Node) -> void:
	if not body.is_in_group("enemies") or _hit_cd.has(body):
		return
	var spd := linear_velocity.length()
	if spd < 4.0 or not body.has_method("take_damage"):
		return
	_hit_cd[body] = 0.6
	body.take_damage(spd * 20.0, body.global_position + Vector3(0, 1, 0), true, "vehicle")
	linear_velocity *= 0.94
