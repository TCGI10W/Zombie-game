extends RigidBody3D
# Thrown frag grenade: bounces around, then explodes after a short fuse.

const FUSE := 2.0
const RADIUS := 6.5
const DAMAGE := 460.0

var thrower: Node = null
var lethal_kind: String = "frag" # "frag", "semtex", "thermite", "impact"
# Shared by every explosion (no new mesh/material per blast)
static var _ball_mesh: SphereMesh
static var _smoke_quad: QuadMesh
var _fuse: float = FUSE
var radius: float = RADIUS
var damage: float = DAMAGE
var pvp_damage: float = 125.0
var _lethal_stuck: bool = false
var _lethal_stuck_target: Node3D = null
var _lethal_stuck_offset: Vector3 = Vector3.ZERO
var _lethal_burning: bool = false
var _lethal_burn_time: float = 0.0
var _lethal_burn_tick: float = 0.0
var _lethal_blink: OmniLight3D


func setup(p_kind: String, p_thrower: Node) -> void:
	lethal_kind = p_kind
	thrower = p_thrower
	var cfg: Dictionary = GameState.LETHALS.get(p_kind, GameState.LETHALS["frag"])
	_fuse = float(cfg.get("fuse", FUSE))
	radius = float(cfg.get("radius", RADIUS))
	damage = float(cfg.get("damage", DAMAGE))
	pvp_damage = float(cfg.get("pvp_damage", 125.0))


func _ready() -> void:
	if not ("mode" in self): # thrown grenades only; zombies don't see placed C4 / mines
		add_to_group("live_explosives")
	collision_layer = 0
	collision_mask = HitboxRig.BALLISTIC_WORLD_LAYER
	mass = 0.4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var cfg: Dictionary = GameState.LETHALS.get(lethal_kind, GameState.LETHALS["frag"])
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0 if bool(cfg.get("sticky", false)) or bool(cfg.get("impact", false)) else 0.35
	pm.friction = 0.9 if bool(cfg.get("sticky", false)) else 0.8
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

	_lethal_blink = OmniLight3D.new()
	_lethal_blink.light_color = cfg.get("color", Color(1.0, 0.25, 0.15)) if lethal_kind != "frag" else Color(1.0, 0.25, 0.15)
	_lethal_blink.light_energy = 1.6 if lethal_kind != "frag" else 0.8
	_lethal_blink.omni_range = 2.0
	add_child(_lethal_blink)


func _physics_process(delta: float) -> void:
	if _lethal_burning:
		if is_instance_valid(_lethal_stuck_target):
			global_position = _lethal_stuck_target.global_position + _lethal_stuck_offset
		_lethal_burn_time -= delta
		_lethal_burn_tick -= delta
		if _lethal_burn_tick <= 0.0:
			_lethal_burn_tick = 0.45
			_apply_thermite_pulse()
		if _lethal_burn_time <= 0.0:
			queue_free()
		return

	if not ("mode" in self):
		if _lethal_stuck and is_instance_valid(_lethal_stuck_target):
			global_position = _lethal_stuck_target.global_position + _lethal_stuck_offset
		elif not _lethal_stuck and get_contact_count() > 0:
			if lethal_kind == "impact":
				_explode()
				return
			elif lethal_kind == "semtex" or lethal_kind == "thermite":
				_lethal_stuck = true
				freeze = true
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO

	_fuse -= delta
	if _fuse <= 0.0:
		if lethal_kind == "thermite":
			_start_thermite_burn()
		else:
			_explode()


func _explode() -> void:
	set_physics_process(false)
	var center := global_position
	var mult := 1.0
	if is_instance_valid(thrower) and thrower.has_method("dmg_mult"):
		mult = thrower.dmg_mult()

	GameState.play_sfx("grenade_explode", 2.0, randf_range(0.92, 1.05))
	if GameState.is_horror_mode() and is_inside_tree():
		ZombieEnemy.broadcast_sound(get_tree(), center, 44.0, true, "explosion")
	var any_hit := false
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(center)
		if d > radius:
			continue
		var dmg := damage * mult * (1.0 - 0.6 * d / radius)
		var res := z.take_damage(dmg, z.global_position + Vector3(0, 1.0, 0), false, "explosive")
		if res["dealt"] > 0.0:
			any_hit = true
			if res["killed"]:
				any_kill = true
				if is_instance_valid(thrower):
					thrower._on_enemy_killed_by_player(z, false)
	if GameState.is_pvp():
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir:
			var att_key: String = pvp_dir.node_to_key(thrower) if is_instance_valid(thrower) else ""
			var att_team: int = int(thrower.team_id) if (is_instance_valid(thrower) and "team_id" in thrower) else -1
			for c in get_tree().get_nodes_in_group("pvp_combatants"):
				var cn := c as Node3D
				if cn == null or not is_instance_valid(cn) or ("is_dead" in cn and cn.is_dead):
					continue
				if "team_id" in cn and int(cn.team_id) == att_team:
					continue
				var dc: float = cn.global_position.distance_to(center)
				if dc > radius:
					continue
				var tkey: String = pvp_dir.node_to_key(cn)
				if tkey == "":
					continue
				var pdmg: float = pvp_damage * (1.0 - 0.65 * dc / radius)
				var ng := get_tree().get_first_node_in_group("net_game")
				if ng and Net.is_online():
					ng.request_pvp_hit(tkey, pdmg, false, lethal_kind, center)
				else:
					pvp_dir.apply_pvp_hit(att_key, tkey, pdmg, false, lethal_kind, center)
				any_hit = true
				if bool(pvp_dir.roster.get(tkey, {}).get("dead", false)):
					any_kill = true
	if is_instance_valid(thrower):
		if any_hit:
			thrower.hitmarker_triggered.emit(false, any_kill, true)
		var pd: float = thrower.global_position.distance_to(center)
		if pd < 14.0:
			thrower.add_camera_shake(clampf(0.6 - pd * 0.04, 0.1, 0.6))

	_spawn_fx(center)
	for tr in get_tree().get_nodes_in_group("zombie_traps"):
		tr.blast(center, radius)
	for hb in get_tree().get_nodes_in_group("hazard_barrels"):
		if is_instance_valid(hb) and (hb as Node3D).global_position.distance_to(center) < radius and hb.has_method("trigger_chain"):
			hb.trigger_chain(thrower, 0.12)
	var ng := get_tree().get_first_node_in_group("net_game")
	if ng and Net.is_online():
		ng.broadcast_explosion(center)
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
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 1.0
		_ball_mesh.height = 2.0
	ball.mesh = _ball_mesh
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if _smoke_quad == null:
		_smoke_quad = QuadMesh.new()
		_smoke_quad.size = Vector2(0.4, 0.4)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.albedo_color = Color(0.25, 0.22, 0.2, 0.55)
		if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
			qm.albedo_texture = load("res://assets/textures/soft_particle.png")
		_smoke_quad.material = qm
	smoke.mesh = _smoke_quad
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(smoke)
	smoke.global_position = center + Vector3(0, 0.3, 0)
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)


func _start_thermite_burn() -> void:
	_lethal_burning = true
	freeze = true
	linear_velocity = Vector3.ZERO
	var cfg: Dictionary = GameState.LETHALS.get("thermite", {})
	_lethal_burn_time = float(cfg.get("burn_duration", 5.2))
	_lethal_burn_tick = 0.0
	GameState.play_sfx("grenade_explode", -5.0, 1.45)
	if is_instance_valid(_lethal_blink):
		_lethal_blink.light_color = Color(1.0, 0.48, 0.14)
		_lethal_blink.light_energy = 7.0
		_lethal_blink.omni_range = 6.5


func _apply_thermite_pulse() -> void:
	var center := global_position
	var mult := 1.0
	if is_instance_valid(thrower) and thrower.has_method("dmg_mult"):
		mult = thrower.dmg_mult()
	var any_hit := false
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead or z.global_position.distance_to(center) > radius:
			continue
		var res := z.take_damage(damage * 0.45 * mult, z.global_position + Vector3(0, 1.0, 0), false, "explosive")
		if res["dealt"] > 0.0:
			any_hit = true
			if res["killed"]:
				any_kill = true
				if is_instance_valid(thrower):
					thrower._on_enemy_killed_by_player(z, false)
	if GameState.is_pvp():
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir:
			var att_key: String = pvp_dir.node_to_key(thrower) if is_instance_valid(thrower) else ""
			var att_team: int = int(thrower.team_id) if (is_instance_valid(thrower) and "team_id" in thrower) else -1
			for c in get_tree().get_nodes_in_group("pvp_combatants"):
				var cn := c as Node3D
				if cn == null or not is_instance_valid(cn) or ("is_dead" in cn and cn.is_dead):
					continue
				if "team_id" in cn and int(cn.team_id) == att_team:
					continue
				if cn.global_position.distance_to(center) > radius:
					continue
				var tkey: String = pvp_dir.node_to_key(cn)
				if tkey == "":
					continue
				pvp_dir.apply_pvp_hit(att_key, tkey, pvp_damage * 0.42, false, "thermite", center)
				any_hit = true
				if bool(pvp_dir.roster.get(tkey, {}).get("dead", false)):
					any_kill = true
	if is_instance_valid(thrower) and any_hit and thrower.has_signal("hitmarker_triggered"):
		thrower.hitmarker_triggered.emit(false, any_kill, false)
