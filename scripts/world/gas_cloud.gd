extends Node3D
# Toxic cloud left behind when a bloater bursts. Hurts the player (with a
# coughing fit) and eats away at zombies standing in it, then thins out.

const RADIUS := 3.1
const LIFETIME := 7.0
const PLAYER_DPS := 9.0
const ZOMBIE_DPS := 22.0

var _t: float = 0.0
var _tick: float = 0.0
var _cough_cd: float = 0.0
var _light: OmniLight3D
var _particles: CPUParticles3D
static var _gas_mat: StandardMaterial3D


func _ready() -> void:
	if _gas_mat == null:
		_gas_mat = StandardMaterial3D.new()
		_gas_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_gas_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_gas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gas_mat.vertex_color_use_as_albedo = true
		_gas_mat.albedo_color = Color(0.5, 0.85, 0.2, 0.35)
		if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
			_gas_mat.albedo_texture = load("res://assets/textures/soft_particle.png")
	_particles = CPUParticles3D.new()
	_particles.amount = 40
	_particles.lifetime = 2.6
	_particles.preprocess = 1.0
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = RADIUS * 0.75
	_particles.direction = Vector3.UP
	_particles.spread = 60.0
	_particles.gravity = Vector3(0, 0.15, 0)
	_particles.initial_velocity_min = 0.1
	_particles.initial_velocity_max = 0.45
	_particles.scale_amount_min = 1.6
	_particles.scale_amount_max = 3.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 0.8))
	_particles.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.9, 0.2, 0.0))
	grad.set_color(1, Color(0.4, 0.7, 0.15, 0.0))
	grad.add_point(0.25, Color(0.55, 0.9, 0.22, 0.42))
	grad.add_point(0.7, Color(0.42, 0.72, 0.18, 0.3))
	_particles.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _gas_mat
	_particles.mesh = quad
	_particles.position.y = 0.9
	add_child(_particles)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 1.0, 0.25)
	_light.light_energy = 1.4
	_light.omni_range = RADIUS * 2.0
	_light.position.y = 1.0
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_cough_cd = maxf(0.0, _cough_cd - delta)
	var fade := clampf((LIFETIME - _t) / 1.5, 0.0, 1.0)
	_light.light_energy = 1.4 * fade
	if _t > LIFETIME - 1.6:
		_particles.emitting = false
	if _t > LIFETIME + 1.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0 or fade <= 0.0:
		return
	_tick = 0.25
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(global_position) < RADIUS and player.has_method("take_damage") and not player.is_dead:
		player.take_damage(PLAYER_DPS * 0.25, global_position)
		if _cough_cd <= 0.0:
			_cough_cd = 1.4
			GameState.play_sfx("player_cough", -3.0, randf_range(0.95, 1.08))
	for node in (get_tree().get_nodes_in_group("enemies") if Net.is_host() else []):
		var z := node as ZombieEnemy
		if z and not z.is_dead and not z.is_boss and z.global_position.distance_to(global_position) < RADIUS:
			z.take_damage(ZOMBIE_DPS * 0.25, Vector3.ZERO, true, "gas")
