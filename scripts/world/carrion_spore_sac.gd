class_name CarrionSporeSac
extends Node3D

# Spawned when a headshot zombie corpse goes uneaten by Carrion Crows for 6s
# in HORROR mode. Stepping near it bursts blinding spores & alerts zombies;
# shooting it from afar pops it as a 22m noisy decoy lure (+25 pts).

var hp: float = 25.0
var _t: float = 0.0
var _life: float = 45.0
var _burst_done: bool = false
var _hurtboxes: Array[Area3D] = []
var _pods: Array[MeshInstance3D] = []
var _glow: OmniLight3D


func _ready() -> void:
	add_to_group("shootable_horror")
	_build_visuals()
	_build_hurtbox()


func _exit_tree() -> void:
	HitboxRig.release_and_free(_hurtboxes)


func _build_visuals() -> void:
	var base := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.42
	bsm.height = 0.28
	base.mesh = bsm
	base.position.y = 0.09
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.14, 0.04, 0.05)
	dark_mat.roughness = 0.65
	dark_mat.emission_enabled = true
	dark_mat.emission = Color(0.28, 0.03, 0.03)
	dark_mat.emission_energy_multiplier = 0.45
	base.material_override = dark_mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)

	var pod_mat := MaterialLib.get_emissive(Color(0.95, 0.16, 0.14), 1.45, 0.92)
	var specs := [
		[Vector3(0.0, 0.26, 0.0), 0.24],
		[Vector3(-0.20, 0.20, 0.14), 0.17],
		[Vector3(0.19, 0.18, -0.15), 0.16],
	]
	for sp in specs:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(sp[1])
		sm.height = float(sp[1]) * 1.95
		sm.radial_segments = 10
		sm.rings = 6
		m.mesh = sm
		m.position = sp[0]
		m.material_override = pod_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_pods.append(m)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.18, 0.14)
	_glow.light_energy = 0.95
	_glow.omni_range = 3.8
	_glow.position.y = 0.38
	add_child(_glow)


func _build_hurtbox() -> void:
	var area := Area3D.new()
	area.collision_layer = HitboxRig.HITBOX_LAYER
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.56
	cs.shape = sh
	cs.position.y = 0.26
	area.add_child(cs)
	add_child(area)
	HitboxRig.register_hurtbox(area, self, "torso", 1.0)
	_hurtboxes.append(area)


func _process(delta: float) -> void:
	if _burst_done:
		return
	_t += delta
	if _t >= _life:
		HitboxRig.release_and_free(_hurtboxes)
		queue_free()
		return
	var beat := 1.0 + 0.14 * absf(sin(_t * 4.4))
	for i in range(_pods.size()):
		if is_instance_valid(_pods[i]):
			var s := beat + 0.06 * sin(_t * 6.5 + float(i) * 1.7)
			_pods[i].scale = Vector3(s, s * 1.05, s)
	if is_instance_valid(_glow):
		_glow.light_energy = 0.7 + 0.65 * absf(sin(_t * 4.4))

	var p := get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(p) and not p.get("is_dead") and not p.get("is_downed"):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d < 2.4:
			trigger_burst(false)


func take_bullet_hit(dmg: float, hit_pos: Vector3, shooter: Node3D) -> Dictionary:
	if _burst_done:
		return {"hit": false, "killed": false}
	hp -= maxf(1.0, dmg)
	FX.gore_burst(hit_pos if hit_pos != Vector3.ZERO else global_position + Vector3(0, 0.25, 0), 3, 2.2)
	if hp <= 0.0:
		if is_instance_valid(shooter) and shooter.is_in_group("player"):
			GameState.add_points(25)
		trigger_burst(true)
		return {"hit": true, "killed": true}
	return {"hit": true, "killed": false}


func trigger_burst(as_decoy: bool) -> void:
	if _burst_done:
		return
	_burst_done = true
	HitboxRig.release_and_free(_hurtboxes)

	var center := global_position + Vector3(0, 0.35, 0)
	FX.gore_burst(center, 12, 4.8)
	FX.splat(global_position + Vector3(0, 0.02, 0), 2.1, Color(0.28, 0.04, 0.06, 0.92))
	GameState.play_sfx("bloater_pop", -1.5, randf_range(0.95, 1.15))

	_spawn_spore_mist(center)
	ZombieEnemy.broadcast_sound(get_tree(), global_position, 22.0, true, "decoy" if as_decoy else "player")

	if not as_decoy:
		var p := get_tree().get_first_node_in_group("player")
		if is_instance_valid(p) and not p.get("is_dead"):
			var d := (p as Node3D).global_position.distance_to(global_position)
			if d < 3.4:
				if p.has_method("take_damage"):
					p.take_damage(15.0, global_position)
				if p.has_method("apply_concussion"):
					p.apply_concussion(2.2)
				if p.has_method("add_camera_shake"):
					p.add_camera_shake(0.28)
				GameState.play_sfx("player_cough", -3.0, randf_range(0.92, 1.06))

	visible = false
	create_tween().tween_callback(queue_free).set_delay(0.15)


func _spawn_spore_mist(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cloud := CPUParticles3D.new()
	cloud.position = pos
	cloud.amount = 26
	cloud.lifetime = 1.6
	cloud.one_shot = true
	cloud.explosiveness = 0.88
	cloud.direction = Vector3.UP
	cloud.spread = 75.0
	cloud.gravity = Vector3(0, -0.35, 0)
	cloud.initial_velocity_min = 1.4
	cloud.initial_velocity_max = 3.8
	cloud.scale_amount_min = 0.55
	cloud.scale_amount_max = 1.25
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.20, 0.04, 0.05, 0.72)
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		mat.albedo_texture = load("res://assets/textures/soft_particle.png")
	q.material = mat
	cloud.mesh = q
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(cloud)
	cloud.emitting = true
	cloud.create_tween().tween_callback(cloud.queue_free).set_delay(2.2)
