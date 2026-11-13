class_name DefensePad
extends Node3D

# Courtyard Defense Grid pad for OVERDRIVE mode.
# Supports two permanent upgradeable pad types (MK-I .. MK-III):
#   "turret" -> Auto-aiming twin-barrel sentry turret
#   "shock"  -> Proximity Arc Shock-Trap pylon (AoE shock + stun pulse)

const TURRET_COSTS := [900, 1300, 1900]
const SHOCK_COSTS := [750, 1150, 1650]

var pad_kind: String = "turret" # "turret" or "shock"
var pad_title: String = "TURRET PAD"
var tier: int = 0 # 0 = unbuilt, 1..3 = MK-I .. MK-III
var interact_radius: float = 2.6
var owner_player: Node3D = null
var kills: int = 0

var _head: Node3D = null
var _light: OmniLight3D = null
var _ring_mesh: MeshInstance3D = null
var _label: Label3D = null
var _pip_meshes: Array[MeshInstance3D] = []
var _cooldown: float = 0.0
var _search_t: float = 0.0
var _target: ZombieEnemy = null
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group("wall_stations")
	add_to_group("defense_pads")
	_build_pad_visuals()
	_refresh_visuals()


func setup(kind: String, title: String) -> void:
	pad_kind = kind
	pad_title = title
	if is_inside_tree():
		_refresh_visuals()


func next_cost() -> int:
	if tier >= 3:
		return 0
	var table := TURRET_COSTS if pad_kind == "turret" else SHOCK_COSTS
	return table[tier]


func _tier_roman() -> String:
	match tier:
		1:
			return "MK-I"
		2:
			return "MK-II"
		3:
			return "MK-III"
	return "OFFLINE"


func get_prompt(_p: Node3D) -> String:
	if tier <= 0:
		return "[E] BUILD %s MK-I (%d PTS)" % [pad_title, next_cost()]
	if tier < 3:
		var nxt := "MK-II" if tier == 1 else "MK-III"
		return "[E] UPGRADE %s -> %s (%d PTS)" % [pad_title, nxt, next_cost()]
	return "%s MK-III [MAXED]" % pad_title


func try_purchase(p: Node3D) -> void:
	if tier >= 3:
		return
	var cost := next_cost()
	if not GameState.try_pay(p, cost):
		return
	owner_player = p
	tier += 1
	_cooldown = 0.0
	_refresh_visuals()
	GameState.play_sfx("crate_open", -4.0, 1.0 + float(tier) * 0.12)
	if pad_kind == "shock":
		_trigger_shock_pulse()
	if is_instance_valid(p) and p.has_signal("status_banner_requested"):
		p.status_banner_requested.emit("%s ONLINE — %s" % [pad_title, _tier_roman()], Color(0.35, 0.95, 1.0) if pad_kind == "turret" else Color(1.0, 0.85, 0.25))


func _physics_process(delta: float) -> void:
	_pulse_t += delta
	if _light != null and pad_kind == "turret":
		_light.light_energy = maxf(0.4 * float(tier), _light.light_energy - delta * 36.0)
	elif _light != null:
		var ready_pulse := 1.4 if _cooldown <= 0.05 else 0.35
		_light.light_energy = lerpf(_light.light_energy, float(tier) * 0.55 * ready_pulse, delta * 8.0)

	if tier <= 0:
		if _ring_mesh != null:
			_ring_mesh.rotation.y += delta * 0.8
		return

	if owner_player == null or not is_instance_valid(owner_player):
		var ps := get_tree().get_nodes_in_group("net_players")
		if not ps.is_empty():
			owner_player = ps[0] as Node3D
		else:
			var p1 := get_tree().get_first_node_in_group("player")
			if p1 != null:
				owner_player = p1 as Node3D

	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)

	if pad_kind == "turret":
		_process_turret(delta)
	else:
		_process_shock_trap(delta)


func _overclock_mult() -> float:
	if is_instance_valid(owner_player) and owner_player.has_method("od_mut_stacks"):
		return 1.0 + 0.35 * float(owner_player.od_mut_stacks("turret_overclock"))
	return 1.0


func _process_turret(delta: float) -> void:
	_search_t -= delta
	var max_range := 17.0 + float(tier) * 3.0
	if _search_t <= 0.0 or not is_instance_valid(_target) or _target.is_dead:
		_search_t = 0.22
		_target = _pick_target(max_range)
	if _target == null:
		if _head != null:
			_head.rotation.y += delta * 0.65
		return
	var aim := _target.global_position + Vector3(0.0, 1.1, 0.0)
	if _head != null:
		var flat := Vector3(aim.x, _head.global_position.y, aim.z)
		if flat.distance_to(_head.global_position) > 0.05:
			_head.look_at(flat, Vector3.UP)
	if _cooldown > 0.0:
		return
	var oc := _overclock_mult()
	_cooldown = maxf(0.08, (0.25 - float(tier - 1) * 0.048) / oc)
	var mult := oc
	if is_instance_valid(owner_player) and owner_player.has_method("dmg_mult"):
		mult *= 0.65 + 0.35 * float(owner_player.dmg_mult())
	var dmg := (36.0 + float(tier) * 20.0) * (1.0 + float(GameState.current_round) * 0.05) * mult
	var res: Dictionary = _target.take_damage(dmg, aim, false, "bullet")
	if res.get("killed", false):
		kills += 1
		_refresh_visuals()
		if is_instance_valid(owner_player):
			owner_player._on_enemy_killed_by_player(_target, false)
	if tier >= 3:
		var arc_tgt: ZombieEnemy = null
		var arc_d: float = 4.6
		for n in get_tree().get_nodes_in_group("enemies"):
			var z2 := n as ZombieEnemy
			if z2 == null or z2.is_dead or z2 == _target:
				continue
			var d2 := z2.global_position.distance_to(_target.global_position)
			if d2 < arc_d:
				arc_d = d2
				arc_tgt = z2
		if arc_tgt != null:
			var aim2 := arc_tgt.global_position + Vector3(0.0, 1.05, 0.0)
			var res2: Dictionary = arc_tgt.take_damage(dmg * 0.55, aim2, true, "shock")
			if res2.get("killed", false):
				kills += 1
				_refresh_visuals()
				if is_instance_valid(owner_player):
					owner_player._on_enemy_killed_by_player(arc_tgt, false)
			_spawn_beam(aim, aim2, Color(0.42, 0.92, 1.0), 0.022)
	if _light != null:
		_light.light_energy = 3.2
	var start_pos := (_head.global_position if _head != null else global_position + Vector3(0, 1.25, 0)) + (-_head.global_basis.z if _head != null else Vector3.FORWARD) * 0.55
	_spawn_beam(start_pos, aim, Color(0.45, 0.95, 1.0) if tier < 3 else Color(1.0, 0.85, 0.25), 0.018)
	GameState.play_sfx("gun_smg", -15.0, randf_range(1.18, 1.35))


func _process_shock_trap(_delta: float) -> void:
	if _ring_mesh != null:
		_ring_mesh.rotation.y += 0.05 * float(tier)
	if _cooldown > 0.0:
		return
	var radius := 4.8 + float(tier) * 1.15
	var r2 := radius * radius
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as ZombieEnemy
		if z == null or z.is_dead:
			continue
		if z.global_position.distance_squared_to(global_position) <= r2:
			_trigger_shock_pulse()
			return


func _trigger_shock_pulse() -> void:
	var radius := 4.8 + float(tier) * 1.15
	var oc := _overclock_mult()
	_cooldown = maxf(1.4, (4.4 - float(tier - 1) * 0.95) / oc)
	var max_targets := 4 + tier * 3
	var hits := 0
	var dmg := (55.0 + float(tier) * 38.0) * (1.0 + float(GameState.current_round) * 0.06) * oc
	var origin := global_position + Vector3(0.0, 1.05, 0.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		if hits >= max_targets:
			break
		var z := n as ZombieEnemy
		if z == null or z.is_dead:
			continue
		if z.global_position.distance_to(global_position) <= radius:
			hits += 1
			z.apply_stun(1.1 + float(tier) * 0.45, true)
			var tgt_pos := z.global_position + Vector3(0.0, 1.0, 0.0)
			var res: Dictionary = z.take_damage(dmg, tgt_pos, true, "shock")
			if res.get("killed", false):
				kills += 1
				_refresh_visuals()
				if is_instance_valid(owner_player):
					owner_player._on_enemy_killed_by_player(z, false)
			_spawn_beam(origin, tgt_pos, Color(0.4, 0.85, 1.0), 0.032)
	if _light != null:
		_light.light_energy = 5.5
	_spawn_ring_flash(radius)
	GameState.play_sfx("bolt_cycle", -8.0, randf_range(1.35, 1.65))


func _pick_target(max_range: float) -> ZombieEnemy:
	var best: ZombieEnemy = null
	var best_d := max_range
	var space := get_world_3d().direct_space_state
	var from := _head.global_position if _head != null else global_position + Vector3(0.0, 1.3, 0.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, z.global_position + Vector3(0.0, 1.1, 0.0), 1)
		if not space.intersect_ray(q).is_empty():
			continue
		best = z
		best_d = d
	return best


func _spawn_beam(a: Vector3, b: Vector3, col: Color, width: float) -> void:
	var host := get_parent() if get_parent() != null else self
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var dist := a.distance_to(b)
	bm.size = Vector3(width, width, dist)
	m.mesh = bm
	m.material_override = MaterialLib.get_emissive(col, 6.0, 0.85)
	host.add_child(m)
	m.global_position = (a + b) * 0.5
	if dist > 0.05:
		m.look_at(b, Vector3.UP)
	var tw := m.create_tween()
	tw.tween_interval(0.065)
	tw.tween_callback(m.queue_free)


func _spawn_ring_flash(radius: float) -> void:
	var host := get_parent() if get_parent() != null else self
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	m.mesh = tm
	m.material_override = MaterialLib.get_emissive(Color(0.35, 0.9, 1.0), 5.0, 0.9)
	host.add_child(m)
	m.global_position = global_position + Vector3(0.0, 0.14, 0.0)
	m.scale = Vector3(0.5, 1.0, 0.5)
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(radius, 1.0, radius), 0.24)
	tw.parallel().tween_property(m, "position:y", m.position.y + 0.18, 0.24)
	tw.tween_callback(m.queue_free)


func _build_pad_visuals() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.18, 0.20, 0.24)
	steel.metallic = 0.7
	steel.roughness = 0.35

	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.92
	bm.bottom_radius = 1.05
	bm.height = 0.14
	bm.radial_segments = 16
	base.mesh = bm
	base.material_override = steel
	base.position.y = 0.07
	add_child(base)

	_ring_mesh = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.78
	tm.outer_radius = 0.88
	_ring_mesh.mesh = tm
	_ring_mesh.position.y = 0.14
	add_child(_ring_mesh)

	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.12
	pm.bottom_radius = 0.18
	pm.height = 1.05
	post.mesh = pm
	post.material_override = steel
	post.position.y = 0.56
	add_child(post)

	_head = Node3D.new()
	_head.position.y = 1.16
	add_child(_head)

	if pad_kind == "turret":
		var housing := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.38, 0.24, 0.52)
		housing.mesh = hm
		housing.material_override = steel
		_head.add_child(housing)
		for side in [-0.11, 0.11]:
			var barrel := MeshInstance3D.new()
			var brm := CylinderMesh.new()
			brm.top_radius = 0.032
			brm.bottom_radius = 0.036
			brm.height = 0.62
			barrel.mesh = brm
			barrel.material_override = steel
			barrel.rotation.x = PI * 0.5
			barrel.position = Vector3(side, -0.01, -0.45)
			_head.add_child(barrel)
	else:
		var coil := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.28
		cm.height = 0.34
		coil.mesh = cm
		coil.material_override = steel
		_head.add_child(coil)
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.20
		orb.mesh = sm
		orb.position.y = 0.26
		orb.material_override = MaterialLib.get_emissive(Color(0.35, 0.9, 1.0), 3.0, 0.9)
		_head.add_child(orb)

	_light = OmniLight3D.new()
	_light.omni_range = 6.5
	_light.light_energy = 0.0
	_light.position.y = 1.35
	add_child(_light)

	_pip_meshes.clear()
	for i in range(3):
		var pip := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.14, 0.08, 0.08)
		pip.mesh = pmesh
		pip.position = Vector3((i - 1) * 0.22, 0.22, 0.62)
		add_child(pip)
		_pip_meshes.append(pip)

	_label = Label3D.new()
	_label.font_size = 28
	_label.outline_size = 8
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = true
	_label.position.y = 1.78
	add_child(_label)


func _refresh_visuals() -> void:
	var accent := Color(0.3, 0.9, 1.0) if pad_kind == "turret" else Color(1.0, 0.82, 0.2)
	if tier == 0:
		accent = Color(0.65, 0.72, 0.8)
	elif tier >= 3:
		accent = Color(1.0, 0.85, 0.22)
	if _ring_mesh != null:
		_ring_mesh.material_override = MaterialLib.get_emissive(accent, 1.2 + float(tier) * 1.4, 0.9)
	if _light != null:
		_light.light_color = accent
	if _head != null:
		_head.visible = tier > 0
	for i in range(_pip_meshes.size()):
		var active := i < tier
		_pip_meshes[i].material_override = MaterialLib.get_emissive(accent if active else Color(0.15, 0.16, 0.18), 3.5 if active else 0.1, 0.95)
	if _label != null:
		_label.modulate = accent
		var k_txt: String = ("  •  KILLS: %d" % kills) if tier > 0 else ""
		_label.text = "%s\n%s%s" % [pad_title, _tier_roman(), k_txt]
