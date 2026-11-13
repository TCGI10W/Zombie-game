class_name OverdriveBlitzZone
extends Node3D

# Mid-round dynamic King-of-the-Hill objective for OVERDRIVE mode.
# Standing inside charges the pod; killing enemies inside adds +20% burst charge.
# Completing it unleashes an arc shockwave, refills ammo, grants +50 Overshield,
# triggers 6s of ★ OVERDRIVE ★, +750 PTS, and upgrades the held weapon.

const GOLD := Color(1.0, 0.85, 0.22)
const CYAN_GOLD := Color(0.35, 1.0, 0.78)

var director: Node = null
var radius: float = 4.2
var progress: float = 0.0
var time_left: float = 28.0
var max_time: float = 28.0
var players_inside: int = 0
var _completed: bool = false

var _core: MeshInstance3D = null
var _outer_ring: MeshInstance3D = null
var _inner_ring: MeshInstance3D = null
var _beam: MeshInstance3D = null
var _light: OmniLight3D = null
var _label: Label3D = null
var _t: float = 0.0


func _ready() -> void:
	add_to_group("blitz_zones")
	_build_visuals()


func _build_visuals() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.14, 0.16, 0.20)
	steel.metallic = 0.75
	steel.roughness = 0.30

	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 1.05
	cm.height = 0.24
	cm.radial_segments = 16
	base.mesh = cm
	base.material_override = steel
	base.position.y = 0.12
	add_child(base)

	if ResourceLoader.exists("res://assets/models/prop_crate.glb"):
		var crate := (load("res://assets/models/prop_crate.glb") as PackedScene).instantiate() as Node3D
		crate.scale = Vector3.ONE * 0.82
		crate.position.y = 0.22
		add_child(crate)

	_core = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.36, 0.36)
	_core.mesh = bm
	_core.material_override = MaterialLib.get_emissive(GOLD, 4.8, 0.95)
	_core.rotation_degrees = Vector3(35.0, 0.0, 45.0)
	_core.position.y = 1.55
	add_child(_core)

	_outer_ring = MeshInstance3D.new()
	var om := TorusMesh.new()
	om.inner_radius = radius - 0.14
	om.outer_radius = radius
	om.rings = 48
	om.ring_segments = 10
	_outer_ring.mesh = om
	_outer_ring.material_override = MaterialLib.get_emissive(GOLD, 2.8, 0.95)
	_outer_ring.position.y = 0.06
	add_child(_outer_ring)

	_inner_ring = MeshInstance3D.new()
	var im := TorusMesh.new()
	im.inner_radius = 2.05
	im.outer_radius = 2.18
	im.rings = 36
	im.ring_segments = 8
	_inner_ring.mesh = im
	_inner_ring.material_override = MaterialLib.get_emissive(Color(0.4, 0.92, 1.0), 2.4, 0.9)
	_inner_ring.position.y = 0.08
	add_child(_inner_ring)

	_beam = MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.14
	bmesh.bottom_radius = 0.28
	bmesh.height = 18.0
	bmesh.radial_segments = 12
	_beam.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	bmat.albedo_color = Color(1.0, 0.84, 0.24, 0.20)
	_beam.material_override = bmat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 9.0
	add_child(_beam)

	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.light_energy = 2.8
	_light.omni_range = 9.0
	_light.position.y = 1.8
	add_child(_light)

	_label = Label3D.new()
	_label.font_size = 30
	_label.outline_size = 9
	_label.pixel_size = 0.0042
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = true
	_label.position.y = 2.6
	_label.modulate = GOLD
	add_child(_label)
	_update_label()


func _living_players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var nodes := get_tree().get_nodes_in_group("net_players")
	if nodes.is_empty():
		var single := get_tree().get_first_node_in_group("player")
		if single != null:
			nodes = [single]
	for n in nodes:
		var p := n as Node3D
		if p != null and is_instance_valid(p):
			if p.get("is_dead") == true or p.get("is_downed") == true:
				continue
			out.append(p)
	return out


func _process(delta: float) -> void:
	if _completed:
		return
	_t += delta
	if _core != null:
		_core.rotation.y += delta * 2.6
		_core.position.y = 1.55 + sin(_t * 3.4) * 0.10
	if _outer_ring != null:
		_outer_ring.rotation.y += delta * (1.2 if players_inside > 0 else 0.5)
	if _inner_ring != null:
		_inner_ring.rotation.y -= delta * (2.2 if players_inside > 0 else 0.9)

	var inside_count: int = 0
	var hero: Node3D = null
	var p_pos := Vector2(global_position.x, global_position.z)
	for p in _living_players():
		var d := Vector2(p.global_position.x, p.global_position.z).distance_to(p_pos)
		if d <= radius:
			inside_count += 1
			if hero == null:
				hero = p
	players_inside = inside_count

	var col := CYAN_GOLD if players_inside > 0 else GOLD
	if _outer_ring != null:
		_outer_ring.material_override = MaterialLib.get_emissive(col, 4.0 if players_inside > 0 else 2.8, 0.95)
	if _light != null:
		_light.light_color = col
		_light.light_energy = 3.8 if players_inside > 0 else 2.4

	if players_inside > 0:
		progress = minf(1.0, progress + delta * (0.18 + 0.05 * float(players_inside - 1)))
		if progress >= 1.0:
			complete_blitz(hero)
			return

	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_expire()
		return
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var pct: int = clampi(roundi(progress * 100.0), 0, 100)
	var sub: String = "HOLDING RING (KILLS = +20%%)  •  %.0fs" % time_left if players_inside > 0 else "ENTER GOLD RING FOR FREE MOD + OVERDRIVE  •  %.0fs" % time_left
	_label.modulate = CYAN_GOLD if players_inside > 0 else GOLD
	_label.text = "BLITZ POD — %d%%\n%s" % [pct, sub]


func on_enemy_killed(enemy_pos: Vector3, killer: Node3D) -> void:
	if _completed:
		return
	var center_2d := Vector2(global_position.x, global_position.z)
	var e_near: bool = Vector2(enemy_pos.x, enemy_pos.z).distance_to(center_2d) <= radius + 1.8
	var k_inside: bool = killer != null and is_instance_valid(killer) and Vector2(killer.global_position.x, killer.global_position.z).distance_to(center_2d) <= radius + 0.5
	if not e_near and not k_inside:
		return
	progress = minf(1.0, progress + 0.20)
	GameState.play_sfx("hit_tick", -6.0, 1.35)
	_update_label()
	if progress >= 1.0:
		complete_blitz(killer)


func complete_blitz(hero: Node3D = null) -> void:
	if _completed:
		return
	_completed = true
	progress = 1.0
	GameState.play_sfx("power_on", -1.5, 1.18)
	GameState.play_sfx("level_up", -1.0, 1.15)
	GameState.play_sfx("buy_ching", -2.5, 1.25)

	_spawn_shockwave_ring(global_position + Vector3(0.0, 0.22, 0.0), 6.8, GOLD)
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		if z.global_position.distance_to(global_position) <= 6.8:
			z.apply_stun(2.4, true)
			var res: Dictionary = z.take_damage(220.0, z.global_position + Vector3(0.0, 1.0, 0.0), true, "shock")
			if bool(res.get("killed", false)) and hero != null and is_instance_valid(hero) and hero.has_method("_on_enemy_killed_by_player"):
				hero._on_enemy_killed_by_player(z, false)

	GameState.add_points(750)
	var target: Node3D = hero if (hero != null and is_instance_valid(hero)) else (get_tree().get_first_node_in_group("player") as Node3D)
	if target != null and is_instance_valid(target):
		if target.has_method("refill_all_ammo"):
			target.refill_all_ammo()
		if "overshield" in target and "hp" in target and "max_hp" in target:
			target.overshield = minf(100.0, float(target.overshield) + 50.0)
			if target.has_signal("hp_changed"):
				target.hp_changed.emit(float(target.hp), float(target.max_hp), float(target.overshield))
		if "od_overdrive_t" in target:
			target.od_overdrive_t = maxf(float(target.od_overdrive_t), 6.0)
		var boost_msg: String = "+MAX AMMO"
		if target.has_method("grant_blitz_weapon_boost"):
			boost_msg = String(target.grant_blitz_weapon_boost())
		if target.has_signal("status_banner_requested"):
			target.status_banner_requested.emit("BLITZ CAPTURED! +750 PTS • +50 SHIELD • 6s OVERDRIVE • %s" % boost_msg, GOLD)

	if director != null and is_instance_valid(director) and "active_blitz_zone" in director:
		if director.active_blitz_zone == self:
			director.active_blitz_zone = null
	queue_free()


func _expire() -> void:
	if _completed:
		return
	_completed = true
	GameState.play_sfx("dry_fire", -4.0, 0.85)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p.has_signal("status_banner_requested"):
		p.status_banner_requested.emit("BLITZ POD SIGNAL LOST", Color(0.85, 0.55, 0.25))
	if director != null and is_instance_valid(director) and "active_blitz_zone" in director:
		if director.active_blitz_zone == self:
			director.active_blitz_zone = null
	queue_free()


func _spawn_shockwave_ring(center: Vector3, max_radius: float, col: Color) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.78
	tm.outer_radius = 1.0
	ring.mesh = tm
	ring.material_override = MaterialLib.get_emissive(col, 6.0, 0.9)
	host.add_child(ring)
	ring.global_position = center
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free)
