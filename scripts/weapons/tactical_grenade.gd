class_name TacticalGrenade
extends RigidBody3D

# Hand-thrown tactical ordnance: Flashbang (blinds players/bots) & Smoke (spawns LOS-blocking smoke_clouds).

var kind: String = "flashbang" # "flashbang", "smoke", "concussion"
var thrower: Node = null
var thrower_team: int = -1
var fuse: float = 1.15
var radius: float = 11.0
var duration: float = 3.4
var _detonated: bool = false
var _mat_band: StandardMaterial3D


func setup(p_kind: String, p_thrower: Node, p_team: int = -1) -> void:
	kind = p_kind
	thrower = p_thrower
	thrower_team = p_team
	var cfg: Dictionary = GameState.TACTICALS.get(p_kind, GameState.TACTICALS["flashbang"])
	fuse = float(cfg.get("fuse", 1.15))
	radius = float(cfg.get("radius", 10.0))
	duration = float(cfg.get("duration", 3.4))


func _ready() -> void:
	mass = 0.45
	collision_layer = 0
	collision_mask = HitboxRig.BALLISTIC_WORLD_LAYER
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.48
	pm.friction = 0.65
	physics_material_override = pm

	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.09
	col.shape = sh
	add_child(col)

	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.042; cm.bottom_radius = 0.042; cm.height = 0.14
	body.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.24, 0.26, 0.28)
	bm.roughness = 0.45; bm.metallic = 0.6
	body.material_override = bm
	add_child(body)

	var cfg: Dictionary = GameState.TACTICALS.get(kind, GameState.TACTICALS["flashbang"])
	_mat_band = StandardMaterial3D.new()
	var bcol: Color = cfg.get("color", Color(0.25, 0.55, 0.95))
	_mat_band.albedo_color = bcol
	_mat_band.emission_enabled = true
	_mat_band.emission = bcol
	_mat_band.emission_energy_multiplier = 2.4
	var band := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.045; bmesh.bottom_radius = 0.045; bmesh.height = 0.03
	band.mesh = bmesh
	band.material_override = _mat_band
	add_child(band)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	fuse -= delta
	if fuse <= 0.0:
		_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	var pos := global_position

	if kind == "smoke":
		GameState.play_sfx("dash", -2.0, 0.72)
		_spawn_smoke_cloud(pos)
		queue_free()
		return

	# Flashbang or Concussion
	GameState.play_sfx("grenade_explode", -5.0, 1.95 if kind == "flashbang" else 1.50)
	var flash_light := OmniLight3D.new()
	get_tree().current_scene.add_child(flash_light)
	flash_light.global_position = pos + Vector3(0, 0.4, 0)
	flash_light.light_color = Color(0.92, 0.96, 1.0) if kind == "flashbang" else Color(1.0, 0.80, 0.35)
	flash_light.light_energy = 14.0
	flash_light.omni_range = radius * 1.4
	var tw := flash_light.create_tween()
	tw.tween_property(flash_light, "light_energy", 0.0, 0.42)
	tw.tween_callback(flash_light.queue_free)

	# Apply to Player
	var pl := get_tree().get_first_node_in_group("player")
	if is_instance_valid(pl):
		var d_pl := (pl as Node3D).global_position.distance_to(pos)
		if d_pl <= radius and _has_clear_flash_los(pos, (pl as Node3D).global_position + Vector3(0, 1.45, 0)):
			var scale_d := clampf(1.0 - (d_pl / radius) * 0.65, 0.3, 1.0)
			if pl == thrower:
				scale_d *= 0.45
			if kind == "flashbang" and pl.has_method("apply_flashbang"):
				pl.call("apply_flashbang", duration * scale_d)
			elif kind == "concussion" and pl.has_method("apply_concussion"):
				pl.call("apply_concussion", duration * scale_d)

	# Apply to PvP bots
	var any_bot_hit := false
	for b in get_tree().get_nodes_in_group("pvp_combatants"):
		if not is_instance_valid(b) or b == pl:
			continue
		if "is_dead" in b and b.is_dead:
			continue
		var same_team := thrower_team >= 0 and ("team_id" in b) and int(b.team_id) == thrower_team
		if same_team:
			continue
		var d_b := (b as Node3D).global_position.distance_to(pos)
		if d_b <= radius and _has_clear_flash_los(pos, (b as Node3D).global_position + Vector3(0, 1.45, 0)):
			var sc := clampf(1.0 - (d_b / radius) * 0.6, 0.35, 1.0)
			if b.has_method("apply_tactical_effect"):
				b.call("apply_tactical_effect", kind, duration * sc)
				any_bot_hit = true

	# Briefly stagger/damage nearby PvE zombies too
	if kind == "flashbang" or kind == "concussion":
		for node in get_tree().get_nodes_in_group("enemies"):
			var z := node as ZombieEnemy
			if z != null and not z.is_dead and z.global_position.distance_to(pos) <= radius * 0.75:
				z.take_damage(25.0, z.global_position + Vector3(0, 1.0, 0), false, "explosive")
				any_bot_hit = true

	if any_bot_hit and is_instance_valid(thrower) and thrower.has_signal("hitmarker_triggered"):
		thrower.hitmarker_triggered.emit(false, false, false)

	queue_free()


func _has_clear_flash_los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.2, 0), to)
	q.collision_mask = HitboxRig.BALLISTIC_WORLD_LAYER
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _spawn_smoke_cloud(pos: Vector3) -> void:
	var cloud := Node3D.new()
	cloud.name = "SmokeCloud"
	cloud.add_to_group("smoke_clouds")
	cloud.set_meta("radius", radius)
	get_tree().current_scene.add_child(cloud)
	cloud.global_position = pos

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.68, 0.71, 0.75, 0.68)
	mat.roughness = 0.98
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

	var puffs: Array[MeshInstance3D] = []
	for i in range(7):
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * (0.42 if i == 0 else 0.34)
		sm.height = sm.radius * 1.45
		mi.mesh = sm
		mi.material_override = mat
		var ang := float(i - 1) * TAU / 6.0
		mi.position = Vector3.ZERO if i == 0 else Vector3(cos(ang) * radius * 0.36, 0.5 + (i % 2) * 0.7, sin(ang) * radius * 0.36)
		mi.scale = Vector3.ONE * 0.12
		cloud.add_child(mi)
		puffs.append(mi)

	var tw := cloud.create_tween()
	tw.set_parallel(true)
	for p in puffs:
		tw.tween_property(p, "scale", Vector3.ONE, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(2.0, duration - 1.6))
	tw.chain().tween_property(mat, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(cloud.queue_free)
