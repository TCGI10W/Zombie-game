extends RigidBody3D
# Thrown frag grenade: bounces around, then explodes after a short fuse.

const FUSE := 2.0
const RADIUS := 6.5
const DAMAGE := 460.0

var thrower: Node = null
var _fuse: float = FUSE


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 # World only
	mass = 0.4
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	linear_damp = 0.4
	angular_damp = 1.5

	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	cs.shape = sphere
	add_child(cs)

	if ResourceLoader.exists("res://assets/models/prop_grenade.glb"):
		var m: Node3D = (load("res://assets/models/prop_grenade.glb") as PackedScene).instantiate()
		m.scale = Vector3.ONE * 1.3
		add_child(m)

	var blink := OmniLight3D.new()
	blink.light_color = Color(1.0, 0.25, 0.15)
	blink.light_energy = 0.8
	blink.omni_range = 1.5
	add_child(blink)


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0:
		_explode()


func _explode() -> void:
	set_physics_process(false)
	var center := global_position
	var mult := 1.0
	if is_instance_valid(thrower) and thrower.has_method("dmg_mult"):
		mult = thrower.dmg_mult()

	GameState.play_sfx("grenade_explode", 2.0, randf_range(0.92, 1.05))
	var any_hit := false
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(center)
		if d > RADIUS:
			continue
		var dmg := DAMAGE * mult * (1.0 - 0.6 * d / RADIUS)
		var res := z.take_damage(dmg, z.global_position + Vector3(0, 1.0, 0), false, "explosive")
		if res["dealt"] > 0.0:
			any_hit = true
			if res["killed"]:
				any_kill = true
				if is_instance_valid(thrower):
					thrower._on_enemy_killed_by_player(z, false)
	if is_instance_valid(thrower):
		if any_hit:
			thrower.hitmarker_triggered.emit(false, any_kill, true)
		var pd: float = thrower.global_position.distance_to(center)
		if pd < 14.0:
			thrower.add_camera_shake(clampf(0.6 - pd * 0.04, 0.1, 0.6))

	_spawn_fx(center)
	queue_free()


func _spawn_fx(center: Vector3) -> void:
	var scene := get_tree().current_scene
	FX.scorch(Vector3(center.x, 0.02, center.z), 3.4)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.light_energy = 8.0
	flash.omni_range = 10.0
	scene.add_child(flash)
	flash.global_position = center + Vector3(0, 0.6, 0)
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "light_energy", 0.0, 0.35)
	ftw.tween_callback(flash.queue_free)

	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	ball.material_override = MaterialLib.get_emissive(Color(1.0, 0.55, 0.15), 6.0, 0.8)
	scene.add_child(ball)
	ball.global_position = center + Vector3(0, 0.4, 0)
	ball.scale = Vector3.ONE * 0.3
	var btw := ball.create_tween()
	btw.tween_property(ball, "scale", Vector3.ONE * 2.6, 0.18).set_ease(Tween.EASE_OUT)
	btw.tween_property(ball, "scale", Vector3.ZERO, 0.15)
	btw.tween_callback(ball.queue_free)

	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.amount = 24
	smoke.lifetime = 1.6
	smoke.direction = Vector3.UP
	smoke.spread = 80.0
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 5.0
	smoke.scale_amount_min = 3.0
	smoke.scale_amount_max = 6.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.25, 0.22, 0.2, 0.55)
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		qm.albedo_texture = load("res://assets/textures/soft_particle.png")
	quad.material = qm
	smoke.mesh = quad
	scene.add_child(smoke)
	smoke.global_position = center + Vector3(0, 0.3, 0)
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)
