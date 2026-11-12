class_name DriveVehicle
extends RigidBody3D
# Light arcade car for the open world (raycast suspension on a RigidBody3D):
# four spring rays hold the body up, grip is a sideways impulse at each wheel,
# throttle/brake push along the body's forward (-Z). Enter / leave with the
# interact key (it sits in the "wall_stations" group like any buyable), drive
# with the move keys, jump key = handbrake. Running zombies over hurts them.

@export var model_path := "res://art/models/vehicle_pickup.glb"
@export var title := "PICKUP"
@export var engine_force := 5200.0
@export var max_speed := 26.0  # m/s (~95 km/h)
@export var wheel_radius := 0.42

const SPRING := 32000.0
const DAMP := 2600.0
const REST := 0.55  # suspension length below the wheel pivot

var interact_radius := 3.4
var driver: Node3D = null
var _wheels: Array[Node3D] = []
var _wheel_rest: Array[Vector3] = []
var _steer := 0.0
var _spin := 0.0
var _engine: AudioStreamPlayer3D
var _hit_cd: Dictionary = {}


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("vehicles")
	mass = 1300.0
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_hit)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0)
	angular_damp = 1.5
	if ResourceLoader.exists(model_path):
		var m: Node3D = (load(model_path) as PackedScene).instantiate()
		add_child(m)
		for tag in ["FL", "FR", "RL", "RR"]:
			var w := m.find_child("Wheel_" + tag, true, false) as Node3D
			if w:
				_wheels.append(w)
				_wheel_rest.append(w.position)
	var aabb := Vector3(1.9, 1.1, 4.6) if title == "PICKUP" else Vector3(1.75, 1.0, 4.2)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = aabb
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)


# ---------------------------------------------------------------- station API
func get_prompt(_player: Node) -> String:
	if driver:
		return ""
	return "[E] DRIVE %s" % title


func try_purchase(player: Node) -> void:
	if driver or not player.has_method("enter_vehicle"):
		return
	driver = player
	player.enter_vehicle(self)
	freeze = false
	sleeping = false


func leave(player: Node) -> Vector3:
	driver = null
	# step out on the driver's side, on the ground
	var out := global_position + global_basis.x * -1.9 + Vector3(0, 1.2, 0)
	return out


func seat_position() -> Vector3:
	return global_transform * Vector3(-0.38, 1.05, 0.15)


# ---------------------------------------------------------------- driving
func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	if driver:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		throttle = -v.y
		steer_in = -v.x
		handbrake = Input.is_action_pressed("jump")
	_steer = move_toward(_steer, steer_in * 0.55, delta * 2.6)
	var space := get_world_3d().direct_space_state
	var fwd := -global_basis.z
	var speed := linear_velocity.dot(fwd)
	var grounded := 0
	var corners := [Vector3(-0.86, 0, 1.6), Vector3(0.86, 0, 1.6), Vector3(-0.86, 0, -1.6), Vector3(0.86, 0, -1.6)]
	for k in range(4):
		var local: Vector3 = corners[k] * Vector3(1, 1, -1)  # model front faces -Z
		if k < _wheel_rest.size():
			local = _wheel_rest[k]
		var origin := global_transform * (local + Vector3(0, 0.3, 0))
		var q := PhysicsRayQueryParameters3D.create(origin, origin - global_basis.y * (REST + wheel_radius + 0.3))
		q.exclude = [get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var comp := 0.0
		if hit:
			grounded += 1
			var dist: float = origin.distance_to(hit["position"]) - wheel_radius
			comp = clampf(REST + 0.3 - dist, 0.0, REST + 0.3)
			var p: Vector3 = hit["position"]
			var vel := linear_velocity + angular_velocity.cross(p - global_position)
			var up := global_basis.y
			var f := up * (comp * SPRING - vel.dot(up) * DAMP)
			# tyre grip: kill sideways slide (front wheels turn with steering)
			var side := global_basis.x
			if k < 2:
				side = side.rotated(up, _steer)
			var grip := 0.35 if handbrake and k >= 2 else 0.9
			f += -side * vel.dot(side) * mass * 0.25 * grip / delta * 0.25
			if k >= 2:  # rear-wheel drive
				var wf := fwd.rotated(up, 0.0)
				if throttle != 0.0 and absf(speed) < max_speed:
					var pushing_back := throttle < 0.0 and speed > 1.0
					f += wf * (engine_force * (2.2 if pushing_back else 1.0)) * throttle * 0.5
				if handbrake:
					f += -wf * vel.dot(wf) * mass * 0.08
			apply_force(f, p - global_position)
		if k < _wheels.size():
			var w := _wheels[k]
			w.position = _wheel_rest[k] + Vector3(0, comp - 0.25, 0)
			w.rotation = Vector3(_spin, _steer if k < 2 else 0.0, 0)
	_spin -= speed * delta / wheel_radius
	if grounded > 0:
		# rolling resistance + air drag
		apply_central_force(-linear_velocity * 45.0 - linear_velocity * linear_velocity.length() * 1.2)
		if driver == null and linear_velocity.length() < 0.6:
			linear_velocity = linear_velocity.move_toward(Vector3.ZERO, delta * 4.0)
	# self-right if flipped
	if global_basis.y.y < 0.2 and linear_velocity.length() < 1.0:
		var t := global_transform
		t.basis = Basis(Vector3.UP, global_rotation.y)
		t.origin += Vector3(0, 1.0, 0)
		global_transform = t
		angular_velocity = Vector3.ZERO
	_engine_sound(absf(speed), throttle)
	for k in _hit_cd.keys():
		_hit_cd[k] -= delta
		if _hit_cd[k] <= 0.0:
			_hit_cd.erase(k)


func _engine_sound(speed: float, throttle: float) -> void:
	if driver and _engine == null:
		_engine = AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.1
		_engine.stream = gen
		_engine.volume_db = -8.0
		add_child(_engine)
		_engine.play()
	if _engine == null:
		return
	var pb := _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	# cheap growl: pulse train whose rate follows the revs
	var rpm := 30.0 + speed * 4.0 + absf(throttle) * 18.0
	var frames := pb.get_frames_available()
	for i in range(frames):
		_phase = fmod(_phase + rpm / 22050.0, 1.0)
		var s := (0.5 if _phase < 0.18 else -0.12) * (0.25 if driver == null else 0.6)
		pb.push_frame(Vector2(s, s))


var _phase := 0.0


func _on_hit(body: Node) -> void:
	if not body.is_in_group("enemies") or _hit_cd.has(body):
		return
	var spd := linear_velocity.length()
	if spd < 4.0 or not body.has_method("take_damage"):
		return
	_hit_cd[body] = 0.6
	body.take_damage(spd * 18.0, body.global_position + Vector3(0, 1, 0), true, "vehicle")
	linear_velocity *= 0.93
