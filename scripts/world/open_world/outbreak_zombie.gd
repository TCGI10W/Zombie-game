class_name OutbreakZombie
extends ZombieEnemy
# Zombie for the open-world OUTBREAK mode. The closed map keeps the plain
# ZombieEnemy (windows, barricades); this one lives out on the land:
#   WANDER  shambles around a home point in small loops, pausing, idling
#   ALERT   chases the player who was noticed:
#           - seen (line of sight, closer at night / in fog)
#           - heard (gunfire, an engine, a shout from a pack-mate)
#           - hurt, or simply bumped into (very close)
#   LOSE    no player within reach for a while -> back to wandering where it is
# Chasing zombies take their own slot on a ring round the player instead of
# all aiming at one point (no knots), keep apart while they run in, and only
# re-plan their path when the goal has really moved (cheap on a 1 km map).

const SIGHT := 26.0        # metres, needs line of sight
const SENSE := 7.0         # metres, always noticed (smell / footsteps)
const LOSE_RANGE := 80.0   # beyond this from every player...
const LOSE_TIME := 9.0     # ...for this long, and it gives up
const PACK_CALL := 11.0    # an alerted zombie wakes the others this close

var wandering := false
var ambient := false       # part of the roaming population, not the round's count
var home := Vector3.ZERO

var _sense_t := 0.0
var _lost_t := 0.0
var _wander_goal := Vector3.INF
var _pause_t := 0.0
var _slot_angle := NAN


func start_wandering(at: Vector3) -> void:
	wandering = true
	home = at
	_wander_goal = Vector3.INF
	_pause_t = randf_range(0.0, 3.0)


func alert(by: Node3D, call_pack: bool = true) -> void:
	if not wandering or is_dead:
		return
	wandering = false
	_lost_t = 0.0
	if is_instance_valid(by):
		target_player = by
	if randf() < 0.6:
		_play_3d_roar("zombie_roar_1", randf_range(0.85, 1.1))
	if call_pack:
		for n in get_tree().get_nodes_in_group("enemies"):
			var o := n as OutbreakZombie
			if o and o != self and o.wandering and o.global_position.distance_to(global_position) < PACK_CALL:
				o.alert(by, false)


func take_damage(raw_amount: float, hit_pos: Vector3 = Vector3.ZERO, ignore_armor: bool = false, kind: String = "bullet") -> Dictionary:
	var r := super.take_damage(raw_amount, hit_pos, ignore_armor, kind)
	if wandering and not is_dead:
		alert(_nearest_player())
	return r


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node3D
		if n == null or n.get("is_dead") == true:
			continue
		var d := n.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = n
	return best


# ------------------------------------------------------------------ brain
func _physics_process(delta: float) -> void:
	if is_dead or net_puppet or is_boss:
		super._physics_process(delta)
		return
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = randf_range(0.25, 0.4)
		if wandering:
			_look_for_players()
		else:
			_check_lost(0.33)
	if wandering and stun_timer <= 0.0 and entry_stage >= 3:
		# far from everyone: tick a few times a second, and past the fog stop
		# animating altogether (a roaming horde costs almost nothing)
		_lod_acc += delta
		var d := _player_dist()
		var step := 0.0 if d < 30.0 else (0.12 if d < 70.0 else 0.3)
		if _lod_acc < step:
			return
		var dt := _lod_acc
		_lod_acc = 0.0
		# beyond 60 m the fog has it: no model, no skinning
		if is_instance_valid(visual_root):
			visual_root.visible = d < 60.0
		_skin_lod(true)
		_wander_tick(dt, d < 60.0)
		_skin_copy()
		return
	if is_instance_valid(visual_root) and not visual_root.visible:
		visual_root.visible = true
	_skin_lod(false)
	super._physics_process(delta)


# The skin adapter copies the rig onto the mesh every frame; a wanderer only
# moves its rig on its own (throttled) ticks, so copy once per tick instead.
var _skin: Node = null
var _skin_lod_on := false


func _skin_lod(on: bool) -> void:
	if on == _skin_lod_on:
		return
	_skin_lod_on = on
	if _skin == null and is_instance_valid(visual_root):
		for n in visual_root.find_children("*", "Node", true, false):
			if n is SkinRigAdapter:
				_skin = n
				break
	if is_instance_valid(_skin):
		_skin.set_process(not on)


func _skin_copy() -> void:
	if is_instance_valid(_skin) and visual_root.visible:
		_skin.set("_last_phys", -1)
		_skin.set("_skip", 0)
		_skin._process(0.0)


var _lod_acc := 0.0


func _player_dist() -> float:
	var best := INF
	for p in get_tree().get_nodes_in_group("player"):
		best = minf(best, (p as Node3D).global_position.distance_to(global_position))
	return best


func _look_for_players() -> void:
	var space := get_world_3d().direct_space_state
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node3D
		if n == null or n.get("is_dead") == true:
			continue
		var d := n.global_position.distance_to(global_position)
		if d < SENSE:
			alert(n)
			return
		if d < SIGHT:
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), n.global_position + Vector3(0, 1.4, 0), 1)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["collider"] as Node) == n:
				alert(n)
				return


func _check_lost(step: float) -> void:
	var near := false
	for p in get_tree().get_nodes_in_group("player"):
		var n := p as Node3D
		if n and n.get("is_dead") != true and n.global_position.distance_to(global_position) < LOSE_RANGE:
			near = true
			break
	_lost_t = 0.0 if near else _lost_t + step
	if _lost_t > LOSE_TIME:
		start_wandering(global_position)


func _wander_tick(delta: float, animate: bool = true) -> void:
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	if _pause_t > 0.0:
		_pause_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if animate:
			_animate_walk(delta, 0.0)
		move_and_slide()
		return
	if _wander_goal == Vector3.INF or global_position.distance_to(_wander_goal) < 1.5:
		var ang := randf() * TAU
		var r := randf_range(5.0, 18.0)
		var c := home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		_wander_goal = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, c)
		_pause_t = randf_range(1.5, 5.0) if randf() < 0.6 else 0.0
		return
	# short open-ground hops: straight at the goal, no path query needed
	var dir := _wander_goal - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	var spd := base_speed * 0.32
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	_face_direction(dir, clampf(delta * 4.0, 0.0, 1.0))
	if animate:
		_animate_walk(delta, spd)
	move_and_slide()
	if get_slide_collision_count() > 0 and get_real_velocity().length() < spd * 0.3:
		_wander_goal = Vector3.INF  # walked into something: pick another way


# ------------------------------------------------------------------ pathing
func _get_nav_dir(dest: Vector3) -> Vector3:
	var goal := dest
	var chasing := not wandering and is_instance_valid(target_player) and dest.distance_to(target_player.global_position) < 0.05
	var flat := Vector2(dest.x - global_position.x, dest.z - global_position.z).length()
	if chasing and flat < 10.0:
		goal += _surround_offset(flat)
	var dir := Vector3.ZERO
	if nav_agent:
		if nav_agent.target_position.distance_to(goal) > 0.6:
			nav_agent.target_position = goal
		if not nav_agent.is_navigation_finished():
			var d := nav_agent.get_next_path_position() - global_position
			d.y = 0.0
			if d.length_squared() > 0.001:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		var f := goal - global_position
		f.y = 0.0
		dir = f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD
	if chasing and flat < 30.0:
		dir = (dir + _spacing() * (1.1 if flat < 8.0 else 0.6)).normalized()
	return dir


# This zombie's own bearing on a ring round the player, drifting toward the
# side it already comes from so it never runs a lap to get there.
func _surround_offset(flat_dist: float) -> Vector3:
	var from_p := global_position - target_player.global_position
	var here := atan2(from_p.z, from_p.x)
	if is_nan(_slot_angle):
		_slot_angle = here + randf_range(-1.2, 1.2)
	_slot_angle = lerp_angle(_slot_angle, here, 0.02)
	return Vector3(cos(_slot_angle), 0.0, sin(_slot_angle)) * clampf(flat_dist * 0.35, 1.15, 2.4)


func _spacing() -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self:
			continue
		var off := global_position - (n as Node3D).global_position
		off.y = 0.0
		var d := off.length()
		if d < 0.01:
			off = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			d = 0.01
		if d < 1.6:
			push += off.normalized() * (1.6 - d) * 1.4
	return push
