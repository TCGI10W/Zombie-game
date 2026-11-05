extends Node3D
# The extraction helicopter: flies in from beyond the walls, hovers over the
# landing zone with its searchlight on the ground and rotor wash kicking up
# dust, drops a rope ladder, and leaves (with or without you).

const MODEL := "res://assets/models/vehicle_helicopter.glb"
const HOVER_HEIGHT := 3.4

var rotor: Node3D
var tail_rotor: Node3D
var ladder: Node3D
var audio: AudioStreamPlayer3D
var spot: SpotLight3D
var beacon: OmniLight3D
var dust: CPUParticles3D
var rotor_speed: float = 26.0
var hover_target: Vector3 = Vector3.ZERO
var hovering: bool = false
var _t: float = 0.0


func _ready() -> void:
	if ResourceLoader.exists(MODEL):
		var m: Node3D = (load(MODEL) as PackedScene).instantiate()
		m.scale = Vector3.ONE * 0.9
		add_child(m)
		rotor = m.find_child("Rotor", true, false) as Node3D
		tail_rotor = m.find_child("TailRotor", true, false) as Node3D
		ladder = m.find_child("Ladder", true, false) as Node3D
		if ladder:
			ladder.visible = false
			ladder.scale = Vector3(1.0, 0.05, 1.0)

	spot = SpotLight3D.new()
	spot.light_color = Color(1.0, 0.96, 0.88)
	spot.light_energy = 9.0
	spot.spot_range = 30.0
	spot.spot_angle = 22.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 0.4, -2.3)
	spot.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
	add_child(spot)

	beacon = OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.1, 0.06)
	beacon.light_energy = 0.0
	beacon.omni_range = 6.0
	beacon.position = Vector3(0, 3.5, 6.8)
	add_child(beacon)

	audio = AudioStreamPlayer3D.new()
	var st := GameState.get_sfx_stream("heli_loop")
	if st is AudioStreamWAV:
		var wav: AudioStreamWAV = (st as AudioStreamWAV).duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))  # in frames, whatever the import format
		audio.stream = wav
	audio.bus = &"SFX"
	audio.unit_size = 22.0
	audio.max_distance = 260.0
	audio.volume_db = 4.0
	add_child(audio)
	audio.play()

	# Rotor wash: dust and grit blown across the ground under the chopper
	dust = CPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 1.6
	dust.emitting = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 3.5
	dust.direction = Vector3(1, 0.15, 0)
	dust.spread = 180.0
	dust.flatness = 0.85
	dust.gravity = Vector3(0, 0.3, 0)
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 7.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.6
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.45, 0.42, 0.38, 0.22)
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		dm.albedo_texture = load("res://assets/textures/soft_particle.png")
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = dm
	dust.mesh = q
	dust.top_level = true
	add_child(dust)


func _process(delta: float) -> void:
	_t += delta
	if rotor:
		rotor.rotate_y(rotor_speed * delta)
	if tail_rotor:
		tail_rotor.rotate_x(rotor_speed * 2.4 * delta)
	beacon.light_energy = 3.0 if fmod(_t, 1.2) < 0.15 else 0.0
	if hovering:
		# Slight drift and sway while holding position
		global_position = hover_target + Vector3(sin(_t * 0.7) * 0.25, sin(_t * 1.1) * 0.12, cos(_t * 0.6) * 0.2)
		rotation.z = sin(_t * 0.8) * 0.025
	var ground_h := global_position.y
	dust.global_position = Vector3(global_position.x, 0.2, global_position.z)
	dust.emitting = ground_h < 14.0


# Fly in from beyond the walls and settle into a hover over `lz`.
func fly_in(lz: Vector3, duration: float, facing_deg: float) -> void:
	hover_target = lz + Vector3(0, HOVER_HEIGHT, 0)
	var start := lz + Vector3(80.0, 42.0, 70.0)
	global_position = start
	rotation_degrees.y = facing_deg
	var approach := lz + Vector3(14.0, 16.0, 10.0)
	var tw := create_tween()
	tw.tween_property(self, "global_position", approach, duration * 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "rotation:x", -0.12, duration * 0.3)
	tw.tween_property(self, "global_position", hover_target, duration * 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation:x", 0.0, duration * 0.28)
	tw.tween_callback(func(): hovering = true)


func lower_ladder() -> void:
	if ladder == null:
		return
	ladder.visible = true
	create_tween().tween_property(ladder, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# Where the bottom of the rope ladder hangs (boarding point).
func board_point() -> Vector3:
	if ladder:
		var p := ladder.global_position
		return Vector3(p.x, 0.0, p.z)
	return Vector3(hover_target.x, 0.0, hover_target.z)


func depart() -> void:
	hovering = false
	var away := global_position + Vector3(-70.0, 46.0, -85.0)
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -0.18, 1.5)
	tw.parallel().tween_property(self, "global_position", global_position + Vector3(0, 6.0, 0), 1.5)
	tw.tween_property(self, "global_position", away, 8.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
