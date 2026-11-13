class_name CrowFlockManager
extends Node3D

# Coordinates 3D Carrion Crows, Corpse Eating, 6s Corpse Mutations
# (Crimson Reborn / Carrion Spore Sac), CROW'S OMEN (1 kill), and
# BLOOD MURDER (3 kills -> 20s event -> 4x POINTS for 15s) in HORROR mode.

const CarrionCrowScript := preload("res://scripts/world/carrion_crow.gd")
const SporeSacScript := preload("res://scripts/world/carrion_spore_sac.gd")

const FLOCK_SIZE := 10
const CORPSE_MUTATE_TIME := 6.0
const CORPSE_WARN_TIME := 4.2
const SHUN_RADIUS := 14.0
const SHUN_DURATION := 12.0
const BLOOD_MURDER_DURATION := 20.0
const QUAD_POINTS_DURATION := 15.0

const PERCH_POINTS := [
	# Courtyard plaza lamps, sandbags & crates
	[Vector3(-7.0, 4.45, -7.0), 0.4],
	[Vector3(8.0, 4.45, -7.0), -0.4],
	[Vector3(-9.0, 4.45, 7.0), 2.5],
	[Vector3(9.0, 4.45, 7.0), -2.5],
	[Vector3(-5.0, 1.25, 0.0), 1.5],
	[Vector3(6.5, 1.25, 2.0), -1.5],
	# Church & Cemetery gates / eaves
	[Vector3(-6.0, 5.2, -18.5), 0.2],
	[Vector3(7.0, 5.2, -18.5), -0.2],
	[Vector3(31.0, 4.45, -31.0), -0.7],
	[Vector3(44.0, 4.45, -46.0), -2.2],
	[Vector3(38.0, 2.8, -42.0), -1.2],
	# Warehouse roof / yard lamps
	[Vector3(24.0, 4.45, -7.0), -1.2],
	[Vector3(34.0, 4.45, 18.0), -2.4],
	[Vector3(22.0, 3.2, 6.0), -1.6],
	# Hospital & Rail yard
	[Vector3(-23.0, 4.45, -5.0), 1.2],
	[Vector3(-39.0, 4.45, -18.0), 0.6],
	[Vector3(-19.0, 4.45, 22.0), 2.3],
	[Vector3(-36.0, 4.45, 29.0), 2.9],
	[Vector3(-30.0, 2.4, 9.0), 0.5],
	[Vector3(2.0, 4.6, 15.5), 3.1],
]

var arena: Node3D
var player: Node3D
var wave_mgr: Node
var weather: Node

var crows: Array = []
var _perches: Array = [] # Array of {pos, yaw, busy_crow}
var corpses: Array = [] # Array of Dictionaries tracking dead zombies
var _next_corpse_id: int = 1
var shunned_zones: Array = [] # Array of {pos, timer, ring}

var crows_killed_this_round: int = 0
var blood_murder_active: bool = false
var blood_murder_timer: float = 0.0
var _respawn_timers: Array[float] = []
var _swoop_cd: float = 14.0
var _assign_cd: float = 0.25


func setup(p_arena: Node3D, p_player: Node3D, p_wave: Node, p_weather: Node) -> void:
	arena = p_arena
	player = p_player
	wave_mgr = p_wave
	weather = p_weather
	add_to_group("crow_manager")
	for pt in PERCH_POINTS:
		_perches.append({"pos": pt[0], "yaw": float(pt[1]), "crow": null})
	for i in range(FLOCK_SIZE):
		_spawn_crow(i < 5)
	if wave_mgr and wave_mgr.has_signal("round_started"):
		wave_mgr.round_started.connect(func(_r: int): on_round_started())


func _spawn_crow(start_perched: bool = false) -> Node3D:
	var c := CarrionCrowScript.new()
	c.manager = self
	add_child(c)
	crows.append(c)
	if start_perched:
		var slot := _pick_free_perch()
		if slot >= 0:
			_perches[slot]["crow"] = c
			c.set_perch(_perches[slot]["pos"], float(_perches[slot]["yaw"]))
			return c
	var angle := randf() * TAU
	var spawn_center := Vector3(cos(angle) * 28.0, randf_range(10.0, 15.0), sin(angle) * 28.0)
	c.global_position = spawn_center
	c.begin_circle(Vector3(randf_range(-16.0, 16.0), 0.0, randf_range(-18.0, 14.0)), randf_range(9.0, 16.0), randf_range(9.0, 14.5))
	return c


func _pick_free_perch() -> int:
	var free_ids: Array[int] = []
	for i in range(_perches.size()):
		var holder = _perches[i]["crow"]
		if holder == null or not is_instance_valid(holder) or holder.is_dead:
			_perches[i]["crow"] = null
			free_ids.append(i)
	if free_ids.is_empty():
		return -1
	return free_ids[randi() % free_ids.size()]


func try_perch_crow(crow: Node3D) -> void:
	_clear_perch_holder(crow)
	if blood_murder_active or randf() < 0.35:
		release_to_circle(crow)
		return
	var slot := _pick_free_perch()
	if slot >= 0:
		_perches[slot]["crow"] = crow
		crow.set_perch(_perches[slot]["pos"], float(_perches[slot]["yaw"]))
	else:
		release_to_circle(crow)


func release_to_circle(crow: Node3D) -> void:
	_clear_perch_holder(crow)
	var center := Vector3(randf_range(-18.0, 18.0), 0.0, randf_range(-20.0, 14.0))
	if is_instance_valid(player) and randf() < 0.65:
		center = player.global_position + Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-8.0, 8.0))
	crow.begin_circle(center, randf_range(8.5, 16.0), randf_range(8.5, 14.0))


func _clear_perch_holder(crow: Node3D) -> void:
	for p_slot in _perches:
		if p_slot["crow"] == crow:
			p_slot["crow"] = null


func on_round_started() -> void:
	if not blood_murder_active:
		crows_killed_this_round = 0


func is_player_sheltered() -> bool:
	if not is_instance_valid(player):
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := player.global_position + Vector3(0.0, 1.8, 0.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 12.0, 0.0), 1))
	return not hit.is_empty()


# ---------------------------------------------------------------------------
# CORPSE REGISTRATION, FEEDING, AND 6s MUTATIONS
# ---------------------------------------------------------------------------
func register_corpse(zombie: Node3D, was_headshot: bool, ragdoll: Node3D = null) -> int:
	if not is_instance_valid(zombie):
		return -1
	var cid := _next_corpse_id
	_next_corpse_id += 1
	var pos := zombie.global_position
	if is_instance_valid(ragdoll) and ragdoll.has_method("corpse_center"):
		pos = ragdoll.corpse_center()
	pos.y = maxf(0.05, pos.y)
	var entry := {
		"id": cid,
		"zombie": zombie,
		"ragdoll": ragdoll,
		"pos": pos,
		"was_headshot": was_headshot,
		"uneaten_timer": 0.0,
		"eaten_progress": 0.0,
		"warned": false,
		"crows": [],
	}
	corpses.append(entry)
	_assign_crows_to_corpse(entry)
	return cid


func _is_shunned(pos: Vector3) -> bool:
	for sz in shunned_zones:
		var sp: Vector3 = sz["pos"]
		if Vector2(sp.x - pos.x, sp.z - pos.z).length() <= SHUN_RADIUS:
			return true
	return false


func _assign_crows_to_corpse(entry: Dictionary) -> void:
	if blood_murder_active or _is_shunned(entry["pos"]):
		return
	var attached: Array = entry["crows"]
	var clean_att: Array = []
	for c in attached:
		if is_instance_valid(c) and not c.is_dead and c.target_corpse_id == int(entry["id"]):
			clean_att.append(c)
	entry["crows"] = clean_att
	var want := 2 if clean_att.is_empty() else 0
	if want == 0:
		return
	# Prefer circling or perched crows not busy swooping/eating/tattletaling
	var candidates: Array = []
	for c in crows:
		if not is_instance_valid(c) or c.is_dead:
			continue
		if c.target_corpse_id >= 0:
			continue
		if c.state in [CarrionCrow.State.CIRCLE, CarrionCrow.State.PERCH]:
			candidates.append(c)
	var cpos: Vector3 = entry["pos"]
	candidates.sort_custom(func(a, b): return a.global_position.distance_squared_to(cpos) < b.global_position.distance_squared_to(cpos))
	var offsets := [Vector3(-0.32, 0.0, 0.16), Vector3(0.30, 0.0, -0.18), Vector3(0.05, 0.0, 0.34)]
	for i in range(mini(want, candidates.size())):
		var crow = candidates[i]
		_clear_perch_holder(crow)
		var off: Vector3 = offsets[(clean_att.size() + i) % offsets.size()]
		crow.assign_corpse(int(entry["id"]), cpos, off)
		clean_att.append(crow)
	entry["crows"] = clean_att


func _process(delta: float) -> void:
	# Clean dead crow refs & process respawns
	var live_crows: Array = []
	for c in crows:
		if is_instance_valid(c) and not c.is_dead:
			live_crows.append(c)
	crows = live_crows

	for i in range(_respawn_timers.size() - 1, -1, -1):
		_respawn_timers[i] -= delta
		if _respawn_timers[i] <= 0.0:
			_respawn_timers.remove_at(i)
			if crows.size() < FLOCK_SIZE:
				_spawn_crow(false)

	# Shunned zones countdown
	for i in range(shunned_zones.size() - 1, -1, -1):
		shunned_zones[i]["timer"] -= delta
		if shunned_zones[i]["timer"] <= 0.0:
			var ring: Node3D = shunned_zones[i].get("ring", null)
			if is_instance_valid(ring):
				ring.queue_free()
			shunned_zones.remove_at(i)

	# Blood Murder countdown & 4x POINTS completion reward
	if blood_murder_active:
		blood_murder_timer -= delta
		if blood_murder_timer <= 0.0:
			_finish_blood_murder(true)

	# Corpse feeding & 6.0s mutation loop
	_assign_cd -= delta
	var do_reassign := _assign_cd <= 0.0
	if do_reassign:
		_assign_cd = 0.45
	var post_wave := wave_mgr != null and int(wave_mgr.get("alive_enemies")) <= 0 and int(wave_mgr.get("zombies_to_spawn")) <= 0 and int(wave_mgr.get("hounds_to_spawn")) <= 0

	for i in range(corpses.size() - 1, -1, -1):
		var c: Dictionary = corpses[i]
		var z: Node3D = c["zombie"]
		var rd: Node3D = c["ragdoll"]
		if not is_instance_valid(z):
			_release_corpse_crows(int(c["id"]))
			corpses.remove_at(i)
			continue
		if is_instance_valid(rd) and rd.has_method("corpse_center"):
			var center := rd.corpse_center() as Vector3
			center.y = maxf(0.05, center.y)
			c["pos"] = center
		else:
			c["pos"] = Vector3(z.global_position.x, maxf(0.05, z.global_position.y + 0.16), z.global_position.z)

		var eating_now := 0
		var assigned_now := 0
		for crow in crows:
			if crow.target_corpse_id == int(c["id"]):
				crow.corpse_pos = c["pos"]
				assigned_now += 1
				if crow.state == CarrionCrow.State.EAT:
					eating_now += 1
				elif crow.state == CarrionCrow.State.DESCEND and (_is_shunned(c["pos"]) or blood_murder_active):
					crow.scatter_away(c["pos"], false)

		if do_reassign and assigned_now == 0 and not blood_murder_active and not _is_shunned(c["pos"]):
			_assign_crows_to_corpse(c)

		if eating_now > 0 and not blood_murder_active and not _is_shunned(c["pos"]):
			# Pause 6s mutation timer while actively devoured
			var eat_rate := (0.29 + 0.11 * float(mini(eating_now - 1, 2))) * (2.0 if post_wave else 1.0)
			c["eaten_progress"] = float(c["eaten_progress"]) + eat_rate * delta
			if is_instance_valid(rd) and rd.has_method("twitch_corpse") and randf() < delta * 3.0:
				rd.twitch_corpse(0.35)
			if float(c["eaten_progress"]) >= 1.0:
				_devour_corpse(c)
				corpses.remove_at(i)
		else:
			c["uneaten_timer"] = float(c["uneaten_timer"]) + delta
			var ut := float(c["uneaten_timer"])
			if ut >= CORPSE_WARN_TIME and not bool(c["warned"]):
				c["warned"] = true
				if z.has_method("start_mutation_telegraph"):
					z.start_mutation_telegraph()
				if is_instance_valid(rd) and rd.has_method("twitch_corpse"):
					rd.twitch_corpse(1.0)
			if ut >= CORPSE_MUTATE_TIME:
				_mutate_corpse(c)
				corpses.remove_at(i)

	# Scare swoop scheduler (prods player into panic shots or sprinting)
	if is_instance_valid(player) and not player.get("is_dead") and not player.get("is_downed"):
		_swoop_cd -= delta
		if _swoop_cd <= 0.0:
			_swoop_cd = randf_range(5.5, 8.5) if blood_murder_active else randf_range(14.0, 22.0)
			force_scare_swoop()


func _devour_corpse(entry: Dictionary) -> void:
	var cid := int(entry["id"])
	_release_corpse_crows(cid)
	var pos: Vector3 = entry["pos"]
	FX.gore_burst(pos + Vector3(0, 0.15, 0), 3, 2.0)
	var z: Node3D = entry["zombie"]
	if is_instance_valid(z) and z.has_method("despawn_corpse"):
		z.despawn_corpse(0.35)


func _mutate_corpse(entry: Dictionary) -> void:
	var cid := int(entry["id"])
	_release_corpse_crows(cid)
	var pos: Vector3 = entry["pos"]
	var z: Node3D = entry["zombie"]
	var was_hs: bool = bool(entry["was_headshot"])

	if was_hs:
		var sac := SporeSacScript.new()
		var parent_node := get_tree().current_scene if get_tree().current_scene else get_parent()
		parent_node.add_child(sac)
		sac.global_position = Vector3(pos.x, 0.02, pos.z)
		FX.gore_burst(pos + Vector3(0, 0.25, 0), 6, 3.0)
		GameState.play_sfx("bloater_pop", -4.0, 0.72)
	else:
		if wave_mgr and wave_mgr.has_method("spawn_crimson_reborn"):
			wave_mgr.spawn_crimson_reborn(pos)
		FX.gore_burst(pos + Vector3(0, 0.4, 0), 8, 3.6)
		GameState.play_sfx("zombie_attack_roar", -3.0, 1.24)

	if is_instance_valid(z) and z.has_method("despawn_corpse"):
		z.despawn_corpse(0.08)


func _release_corpse_crows(cid: int) -> void:
	for crow in crows:
		if is_instance_valid(crow) and crow.target_corpse_id == cid:
			crow.target_corpse_id = -1
			if crow.state in [CarrionCrow.State.DESCEND, CarrionCrow.State.EAT]:
				release_to_circle(crow)


func force_scare_swoop() -> bool:
	if not is_instance_valid(player) or player.get("is_dead"):
		return false
	var ppos := player.global_position
	var cam: Camera3D = player.get("camera") as Camera3D
	var fwd := -cam.global_basis.z if is_instance_valid(cam) else -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD

	var best = null
	var best_d := 26.0
	for c in crows:
		if not is_instance_valid(c) or c.is_dead:
			continue
		if c.state in [CarrionCrow.State.CIRCLE, CarrionCrow.State.PERCH]:
			var d: float = c.global_position.distance_to(ppos)
			if d < best_d and d > 4.0:
				best_d = d
				best = c
	if best == null:
		return false
	_clear_perch_holder(best)
	best.start_scare_swoop(ppos, fwd)
	return true


# ---------------------------------------------------------------------------
# ACOUSTIC REACTIONS & CROW DEATH CURSES ("THE MURDER'S CURSE")
# ---------------------------------------------------------------------------
func on_world_sound(pos: Vector3, radius: float, urgent: bool, source: String) -> void:
	if source == "crow":
		return
	var scatter_r := 14.0 if (urgent and radius >= 24.0) else (6.5 if urgent else 2.6)
	for c in crows:
		if not is_instance_valid(c) or c.is_dead:
			continue
		if c.state in [CarrionCrow.State.PERCH, CarrionCrow.State.DESCEND, CarrionCrow.State.EAT]:
			if c.global_position.distance_to(pos) <= scatter_r:
				_clear_perch_holder(c)
				c.scatter_away(pos, source != "decoy")


func on_crow_killed(crow: Node3D, pos: Vector3, _shooter: Node3D) -> void:
	_clear_perch_holder(crow)
	_respawn_timers.append(11.0)
	ZombieEnemy.broadcast_sound(get_tree(), pos, 32.0, true, "crow")

	if blood_murder_active:
		return

	crows_killed_this_round += 1
	if crows_killed_this_round < 3:
		_trigger_crows_omen(pos, crows_killed_this_round)
	else:
		_trigger_blood_murder()


func _trigger_crows_omen(pos: Vector3, count: int) -> void:
	var ring := _spawn_shun_ring(Vector3(pos.x, 0.04, pos.z))
	shunned_zones.append({"pos": Vector3(pos.x, 0.0, pos.z), "timer": SHUN_DURATION, "ring": ring})

	# Scatter any crows eating corpses inside this newly shunned zone
	for c in crows:
		if is_instance_valid(c) and not c.is_dead and c.target_corpse_id >= 0:
			if Vector2(c.corpse_pos.x - pos.x, c.corpse_pos.z - pos.z).length() <= SHUN_RADIUS:
				c.scatter_away(pos, false)

	# Assign up to 2 tattletale crows to caw overhead for 8s
	var assigned := 0
	for c in crows:
		if assigned >= 2:
			break
		if is_instance_valid(c) and not c.is_dead and c.state in [CarrionCrow.State.CIRCLE, CarrionCrow.State.PERCH]:
			_clear_perch_holder(c)
			c.start_tattletale(8.0)
			assigned += 1

	if is_instance_valid(player) and player.has_signal("status_banner_requested"):
		player.status_banner_requested.emit("CROW'S OMEN — FLOCK SHUNS THIS GROUND (12S) [%d/3]" % count, Color(0.92, 0.36, 0.28))


func _trigger_blood_murder() -> void:
	crows_killed_this_round = 0
	blood_murder_active = true
	blood_murder_timer = BLOOD_MURDER_DURATION
	_swoop_cd = 2.0
	if weather and weather.has_method("flash_sky"):
		weather.flash_sky(1.0)
	GameState.play_sfx("crow", 2.0, 0.72)

	if is_instance_valid(player) and player.has_signal("status_banner_requested"):
		player.status_banner_requested.emit("THE MURDER REMEMBERS — SURVIVE 20S FOR 4X POINTS!", Color(0.98, 0.16, 0.14))

	# All currently uneaten corpses immediately mutate!
	for i in range(corpses.size() - 1, -1, -1):
		_mutate_corpse(corpses[i])
		corpses.remove_at(i)


func _finish_blood_murder(survived: bool) -> void:
	blood_murder_active = false
	blood_murder_timer = 0.0
	if not survived or not is_instance_valid(player) or player.get("is_dead"):
		return
	GameState.activate_powerup("quad_points", QUAD_POINTS_DURATION)
	GameState.play_sfx("level_up", 0.0, 1.22)
	if player.has_signal("status_banner_requested"):
		player.status_banner_requested.emit("BLOOD MURDER SURVIVED! 4X POINTS ACTIVE (15S)!", Color(1.0, 0.85, 0.22))


func _spawn_shun_ring(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var disc := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = SHUN_RADIUS - 0.18
	tor.outer_radius = SHUN_RADIUS
	tor.rings = 48
	tor.ring_segments = 6
	disc.mesh = tor
	disc.material_override = MaterialLib.get_emissive(Color(0.85, 0.14, 0.12), 1.4, 0.52)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	return root


func has_imminent_mutations() -> bool:
	if blood_murder_active:
		return true
	for c in corpses:
		if not bool(c["was_headshot"]):
			if _is_shunned(c["pos"]) or crows.is_empty():
				return true
			if float(c["uneaten_timer"]) >= 4.0:
				return true
	return false
