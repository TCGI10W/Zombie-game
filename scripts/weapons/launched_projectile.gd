class_name LaunchedProjectile
extends Node3D

# Unified physical projectile for RPG-7V2 rockets, M79 / M32 40mm HE grenades,
# and Fury Explosive Crossbow bolts across both PvE & PvP modes.

var kind: String = "rocket" # "rocket", "gl_he", "xbow_bolt"
var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var damage: float = 200.0
var pvp_damage: float = 130.0
var blast_radius: float = 5.5
var shooter: Node = null
var shooter_team: int = -1
var weapon_id: String = "rpg7"

var _age: float = 0.0
var _max_age: float = 5.5
var _stuck: bool = false
var _stuck_fuse: float = 0.0
var _detonated: bool = false
var _trail_acc: float = 0.0
var _init_origin: Vector3 = Vector3.ZERO
var _mat_ember: StandardMaterial3D


func setup(p_kind: String, origin: Vector3, dir: Vector3, p_speed: float, p_dmg: float, p_pvp_dmg: float, p_radius: float, p_shooter: Node, p_weapon_id: String, p_team: int = -1) -> void:
	kind = p_kind
	_init_origin = origin
	if is_inside_tree():
		global_position = origin
	velocity = dir.normalized() * p_speed
	damage = p_dmg
	pvp_damage = p_pvp_dmg
	blast_radius = p_radius
	shooter = p_shooter
	weapon_id = p_weapon_id
	shooter_team = p_team
	match kind:
		"rocket":
			gravity = 1.6
			_max_age = 5.0
		"gl_he":
			gravity = 14.5
			_max_age = 4.5
		"xbow_bolt":
			gravity = 7.5
			_max_age = 6.0


func _ready() -> void:
	global_position = _init_origin
	var root := Node3D.new()
	add_child(root)
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity.normalized(), Vector3.UP)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.32, 0.38, 0.24) if kind == "rocket" else (Color(0.75, 0.58, 0.16) if kind == "gl_he" else Color(0.22, 0.24, 0.26))
	body_mat.roughness = 0.42
	body_mat.metallic = 0.55

	if kind == "rocket":
		var tube := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.036; cm.bottom_radius = 0.024; cm.height = 0.34
		tube.mesh = cm
		tube.rotation.x = PI * 0.5
		tube.material_override = body_mat
		root.add_child(tube)
	elif kind == "gl_he":
		var shell := MeshInstance3D.new()
		var sm := CapsuleMesh.new()
		sm.radius = 0.04; sm.height = 0.14
		shell.mesh = sm
		shell.rotation.x = PI * 0.5
		shell.material_override = body_mat
		root.add_child(shell)
	else:
		var bolt := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.010; bm.bottom_radius = 0.012; bm.height = 0.36
		bolt.mesh = bm
		bolt.rotation.x = PI * 0.5
		bolt.material_override = body_mat
		root.add_child(bolt)

	_mat_ember = StandardMaterial3D.new()
	_mat_ember.albedo_color = Color(1.0, 0.45, 0.12)
	_mat_ember.emission_enabled = true
	_mat_ember.emission = Color(1.0, 0.38, 0.08) if kind != "xbow_bolt" else Color(1.0, 0.16, 0.12)
	_mat_ember.emission_energy_multiplier = 4.5
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.032 if kind != "xbow_bolt" else 0.018
	gm.height = gm.radius * 2.0
	glow.mesh = gm
	glow.position = Vector3(0.0, 0.0, 0.14 if kind != "gl_he" else 0.06)
	glow.material_override = _mat_ember
	root.add_child(glow)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_age += delta
	if _age >= _max_age:
		_detonate(global_position)
		return

	if _stuck:
		_stuck_fuse -= delta
		if _mat_ember:
			var pulse := 1.0 if fmod(_stuck_fuse * 8.0, 1.0) < 0.5 else 0.15
			_mat_ember.emission_energy_multiplier = 6.0 * pulse
		if _stuck_fuse <= 0.0:
			_detonate(global_position)
		return

	velocity.y -= gravity * delta
	var prev_pos := global_position
	var next_pos := prev_pos + velocity * delta
	if velocity.length_squared() > 0.04:
		look_at(next_pos, Vector3.UP)

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(prev_pos, next_pos)
	q.collision_mask = HitboxRig.BULLET_MASK
	q.collide_with_areas = true
	var exclude: Array[RID] = []
	if is_instance_valid(shooter):
		if shooter is CollisionObject3D:
			exclude.append((shooter as CollisionObject3D).get_rid())
		if "_hurtboxes" in shooter:
			for hb_area in shooter._hurtboxes:
				if is_instance_valid(hb_area):
					exclude.append((hb_area as Area3D).get_rid())
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		global_position = hit_pos
		if kind == "xbow_bolt" and not _is_actor(collider):
			_stuck = true
			_stuck_fuse = 0.65
			GameState.play_sfx("hitmark", -6.0, 1.35)
			return
		# Direct impact bonus for crossbow / RPG / GL
		_detonate(hit_pos, collider)
		return

	global_position = next_pos
	_trail_acc += delta
	if (kind == "rocket" or kind == "gl_he") and _trail_acc >= 0.025:
		_trail_acc = 0.0
		_spawn_smoke_puff()


func _is_actor(obj: Object) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var hb := HitboxRig.resolve_hit(obj)
	if String(hb.get("zone", "")) != "":
		var ow: Object = hb.get("owner", null)
		if ow is Node and ((ow as Node).is_in_group("enemies") or (ow as Node).is_in_group("pvp_combatants") or (ow as Node).is_in_group("player")):
			return true
	if obj is Area3D:
		var p := (obj as Area3D).get_parent()
		if p and (p.is_in_group("enemies") or p.is_in_group("pvp_combatants") or p.is_in_group("player")):
			return true
	if obj is Node:
		var n := obj as Node
		return n.is_in_group("enemies") or n.is_in_group("pvp_combatants") or n.is_in_group("player")
	return false


func _spawn_smoke_puff() -> void:
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06 if kind == "gl_he" else 0.09
	sm.height = sm.radius * 2.0
	puff.mesh = sm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.88, 0.85, 0.80, 0.42)
	m.roughness = 0.95
	puff.material_override = m
	get_tree().current_scene.add_child(puff)
	puff.global_position = global_position
	var tw := puff.create_tween()
	tw.set_parallel(true)
	tw.tween_property(puff, "scale", Vector3.ONE * 2.8, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(puff.queue_free)


func _detonate(pos: Vector3, direct_col: Object = null) -> void:
	if _detonated:
		return
	_detonated = true
	GameState.play_sfx("grenade_explode", 1.5, 0.92 if kind == "rocket" else 1.12)
	FX.scorch(pos + Vector3(0, 0.04, 0), 2.4 if kind == "rocket" else 1.6)
	_spawn_explosion_vfx(pos)

	for tr in get_tree().get_nodes_in_group("zombie_traps"):
		if is_instance_valid(tr) and tr.has_method("blast"):
			tr.blast(pos, blast_radius)
	for hb in get_tree().get_nodes_in_group("hazard_barrels"):
		if is_instance_valid(hb) and (hb as Node3D).global_position.distance_to(pos) <= blast_radius + 0.8 and hb.has_method("trigger_chain"):
			hb.trigger_chain(shooter, 0.10)

	var any_hit := false
	var any_kill := false
	var direct_target: Node = null
	if is_instance_valid(direct_col):
		var hb := HitboxRig.resolve_hit(direct_col)
		var ow: Object = hb.get("owner", direct_col)
		if ow is Node:
			direct_target = ow as Node

	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var d := z.global_position.distance_to(pos)
		if d > blast_radius and z != direct_target:
			continue
		var falloff := clampf(1.0 - (d / blast_radius) * 0.65, 0.25, 1.0)
		var dmg := damage * falloff + (damage * 0.45 if z == direct_target else 0.0)
		var res := z.take_damage(dmg, pos, false, "explosive")
		if res["dealt"] > 0.0:
			any_hit = true
			if res["killed"]:
				any_kill = true
				if is_instance_valid(shooter) and shooter.has_method("_on_enemy_killed_by_player"):
					shooter._on_enemy_killed_by_player(z, false)

	if GameState.is_pvp():
		var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
		if pvp_dir:
			var att_key: String = pvp_dir.node_to_key(shooter) if is_instance_valid(shooter) else ""
			for c in get_tree().get_nodes_in_group("pvp_combatants"):
				var cn := c as Node3D
				if cn == null or not is_instance_valid(cn) or ("is_dead" in cn and cn.is_dead):
					continue
				if cn == shooter and kind != "rocket" and kind != "gl_he":
					continue
				var dc := cn.global_position.distance_to(pos)
				if dc > blast_radius and cn != direct_target:
					continue
				if "team_id" in cn and shooter_team >= 0 and int(cn.team_id) == shooter_team and cn != shooter:
					continue
				var tkey: String = pvp_dir.node_to_key(cn)
				if tkey == "":
					continue
				var falloff := clampf(1.0 - (dc / blast_radius) * 0.68, 0.24, 1.0)
				if cn == shooter:
					falloff *= 0.45
				var pdmg: float = pvp_damage * falloff + (28.0 if cn == direct_target and cn != shooter else 0.0)
				var ng := get_tree().get_first_node_in_group("net_game")
				if ng and Net.is_online():
					ng.request_pvp_hit(tkey, pdmg, false, weapon_id, pos)
				else:
					pvp_dir.apply_pvp_hit(att_key, tkey, pdmg, false, weapon_id, pos)
				if cn != shooter:
					any_hit = true
					if bool(pvp_dir.roster.get(tkey, {}).get("dead", false)):
						any_kill = true

	if is_instance_valid(shooter) and shooter.is_in_group("player"):
		var sd := (shooter as Node3D).global_position.distance_to(pos)
		if sd < 18.0 and shooter.has_method("add_camera_shake"):
			shooter.call("add_camera_shake", clampf(1.0 - sd / 18.0, 0.0, 0.65))
		if any_hit and shooter.has_signal("hitmarker_triggered"):
			shooter.hitmarker_triggered.emit(false, any_kill, true)

	queue_free()


func _spawn_explosion_vfx(pos: Vector3) -> void:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = pos + Vector3(0, 0.25, 0)

	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.22)
	l.light_energy = 10.0
	l.omni_range = 14.0
	root.add_child(l)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.56, 0.16, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.10)
	mat.emission_energy_multiplier = 4.0

	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	ball.mesh = sm
	ball.material_override = mat
	root.add_child(ball)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * (blast_radius * 0.72), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.34)
	tw.tween_property(l, "light_energy", 0.0, 0.28)
	tw.chain().tween_callback(root.queue_free)
