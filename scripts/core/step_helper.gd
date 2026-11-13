class_name StepHelper
extends RefCounted

# Shared ledge step-up, low-cover jump/vault, and obstacle bypass steering helpers
# used by PlayerController, PvpBot, ZombieEnemy, and HoundEnemy.


static func try_step_up(body: CharacterBody3D, horiz_vel: Vector3, delta: float, max_step: float = 0.34) -> float:
	if body == null or not body.is_inside_tree() or horiz_vel.length_squared() < 0.04:
		return 0.0
	var flat := Vector3(horiz_vel.x, 0.0, horiz_vel.z)
	var probe := flat.normalized() * maxf(flat.length() * delta, 0.16)
	if not body.test_move(body.global_transform, probe):
		return 0.0

	var up_vec := Vector3(0.0, max_step, 0.0)
	var col_up := KinematicCollision3D.new()
	if body.test_move(body.global_transform, up_vec, col_up):
		up_vec.y = col_up.get_travel().y
	if up_vec.y < 0.03:
		return 0.0

	var raised_xf := body.global_transform.translated(up_vec)
	var col_fwd := KinematicCollision3D.new()
	var fwd := probe
	if body.test_move(raised_xf, fwd, col_fwd):
		if col_fwd.get_travel().length() < 0.05:
			return 0.0
		fwd = col_fwd.get_travel()

	var fwd_xf := raised_xf.translated(fwd)
	var col_dn := KinematicCollision3D.new()
	if not body.test_move(fwd_xf, Vector3(0.0, -(up_vec.y + 0.05), 0.0), col_dn):
		return 0.0
	if col_dn.get_normal().y < 0.72:
		return 0.0

	var step_h: float = up_vec.y + col_dn.get_travel().y
	if step_h <= 0.015 or step_h > max_step + 0.02:
		return 0.0

	body.global_position += Vector3(fwd.x * 0.55, step_h + 0.01, fwd.z * 0.55)
	return step_h


static func probe_jumpable_obstacle(body: CharacterBody3D, flat_dir: Vector3, max_jump_h: float = 1.25) -> bool:
	if body == null or not body.is_inside_tree() or body.get_world_3d() == null:
		return false
	var dir := Vector3(flat_dir.x, 0.0, flat_dir.z)
	if dir.length_squared() < 0.001:
		return false
	dir = dir.normalized()

	var space := body.get_world_3d().direct_space_state
	var pos := body.global_position
	var excl: Array[RID] = [body.get_rid()]
	var mask := 1 | 16

	# 1. Low obstacle directly ahead
	var low_q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 0.46, 0.0), pos + Vector3(0.0, 0.46, 0.0) + dir * 0.98, mask, excl)
	var hit_low := space.intersect_ray(low_q)
	if hit_low.is_empty():
		return false
	if absf((hit_low["normal"] as Vector3).y) >= 0.55:
		return false

	# 2. Clear just above max_jump_h (rejects walls, fences, wagons, truck, crypt, racks, window blockers, doors)
	var mid_y: float = max_jump_h + 0.22
	var mid_q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, mid_y, 0.0), pos + Vector3(0.0, mid_y, 0.0) + dir * 1.25, mask, excl)
	if not space.intersect_ray(mid_q).is_empty():
		return false

	# 3. Clear at jump apex height
	var top_q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 2.15, 0.0), pos + Vector3(0.0, 2.15, 0.0) + dir * 1.25, mask, excl)
	if not space.intersect_ray(top_q).is_empty():
		return false

	# 4. Headroom above self before jumping
	var ceil_q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 1.15, 0.0), pos + Vector3(0.0, 2.65, 0.0), mask, excl)
	if not space.intersect_ray(ceil_q).is_empty():
		return false

	return true


static func is_blocked_ahead(body: CharacterBody3D, flat_dir: Vector3, dist: float = 1.0) -> bool:
	if body == null or not body.is_inside_tree() or body.get_world_3d() == null:
		return false
	var dir := Vector3(flat_dir.x, 0.0, flat_dir.z)
	if dir.length_squared() < 0.001:
		return false
	dir = dir.normalized()
	var space := body.get_world_3d().direct_space_state
	var origin := body.global_position + Vector3(0.0, 0.52, 0.0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * dist, 1 | 16, [body.get_rid()])
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.6


static func pick_bypass_dir(body: CharacterBody3D, want_dir: Vector3) -> Vector3:
	var dir := Vector3(want_dir.x, 0.0, want_dir.z)
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	if body == null or not body.is_inside_tree() or body.get_world_3d() == null:
		return Vector3(-dir.z, 0.0, dir.x).normalized()

	var space := body.get_world_3d().direct_space_state
	var origin := body.global_position + Vector3(0.0, 0.65, 0.0)
	var excl: Array[RID] = [body.get_rid()]
	var best_dir := Vector3(-dir.z, 0.0, dir.x).normalized()
	var best_score := -999.0
	var probe_dist := 2.5

	for ang_deg in [38.0, -38.0, 68.0, -68.0, 92.0, -92.0, 135.0, -135.0]:
		var cand := dir.rotated(Vector3.UP, deg_to_rad(float(ang_deg)))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + cand * probe_dist, 1 | 16, excl)
		var hit := space.intersect_ray(q)
		var clearance := probe_dist if hit.is_empty() else origin.distance_to(hit["position"] as Vector3)
		var score := clearance - absf(deg_to_rad(float(ang_deg))) * 0.35
		if score > best_score:
			best_score = score
			best_dir = cand

	return best_dir.normalized()


static func steer_around_obstacles(body: CharacterBody3D, wish_dir: Vector3, probe_dist: float = 1.85, prefer_side: float = 1.0, mask: int = 1 | 16) -> Dictionary:
	var dir := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if dir.length_squared() < 0.001:
		return {"dir": Vector3.ZERO, "blocked": false, "side": prefer_side}
	dir = dir.normalized()
	if body == null or not body.is_inside_tree() or body.get_world_3d() == null:
		return {"dir": dir, "blocked": false, "side": prefer_side}

	var space := body.get_world_3d().direct_space_state
	var origin := body.global_position + Vector3(0.0, 0.58, 0.0)
	var excl: Array[RID] = [body.get_rid()]

	# Fast path: check center + narrow shoulder whiskers first
	var q_c := PhysicsRayQueryParameters3D.create(origin, origin + dir * probe_dist, mask, excl)
	var hit_c: Dictionary = space.intersect_ray(q_c)
	var shoulder_len: float = probe_dist * 0.78
	var hit_l: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir.rotated(Vector3.UP, 0.38) * shoulder_len, mask, excl))
	var hit_r: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir.rotated(Vector3.UP, -0.38) * shoulder_len, mask, excl))
	if hit_c.is_empty() and hit_l.is_empty() and hit_r.is_empty():
		return {"dir": dir, "blocked": false, "side": prefer_side}

	# Ignore flat walkable ramps
	var center_wall: bool = not hit_c.is_empty() and absf((hit_c["normal"] as Vector3).y) < 0.62
	var left_wall: bool = not hit_l.is_empty() and absf((hit_l["normal"] as Vector3).y) < 0.62
	var right_wall: bool = not hit_r.is_empty() and absf((hit_r["normal"] as Vector3).y) < 0.62
	if not center_wall and not left_wall and not right_wall:
		return {"dir": dir, "blocked": false, "side": prefer_side}

	var pref_sign: float = 1.0 if prefer_side >= 0.0 else -1.0
	var wall_slide := Vector3.ZERO
	if center_wall:
		var n: Vector3 = hit_c["normal"] as Vector3
		wall_slide = dir - n * dir.dot(n)
		wall_slide.y = 0.0
		if wall_slide.length_squared() < 0.04:
			# Head-on against flat obstacle: pick wall-parallel tangent with better clearance (tie-broken by pref_sign)
			var tang_pos := dir.rotated(Vector3.UP, PI * 0.5)
			tang_pos.y = 0.0
			tang_pos = tang_pos.normalized()
			var tang_neg := -tang_pos
			var hp: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + tang_pos * probe_dist, mask, excl))
			var hn: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + tang_neg * probe_dist, mask, excl))
			var dp: float = probe_dist if hp.is_empty() else origin.distance_to(hp["position"] as Vector3)
			var dn: float = probe_dist if hn.is_empty() else origin.distance_to(hn["position"] as Vector3)
			if absf(dp - dn) > 0.20:
				wall_slide = tang_pos if dp > dn else tang_neg
			else:
				wall_slide = tang_pos if pref_sign >= 0.0 else tang_neg
		else:
			wall_slide = wall_slide.normalized()

	var center_dist: float = probe_dist if not center_wall else origin.distance_to(hit_c["position"] as Vector3)
	var best_dir := dir
	var best_score: float = -999.0
	var chosen_ang: float = 0.0

	for ang_v in [-95.0, -68.0, -42.0, -22.0, 0.0, 22.0, 42.0, 68.0, 95.0]:
		var ang_deg: float = float(ang_v)
		var cand := dir.rotated(Vector3.UP, deg_to_rad(ang_deg))
		var free_frac: float = 1.0
		if absf(ang_deg) < 1.0:
			free_frac = clampf(center_dist / probe_dist, 0.0, 1.0)
		else:
			var h: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + cand * probe_dist, mask, excl))
			if not h.is_empty() and absf((h["normal"] as Vector3).y) < 0.62:
				free_frac = clampf(origin.distance_to(h["position"] as Vector3) / probe_dist, 0.0, 1.0)
		var close_pen: float = 0.85 if free_frac < 0.34 else 0.0
		var goal_align: float = cand.dot(dir)
		var slide_bonus: float = maxf(0.0, cand.dot(wall_slide)) * 0.42 if wall_slide != Vector3.ZERO else 0.0
		var side_sign: float = 0.0 if absf(ang_deg) < 1.0 else (1.0 if ang_deg > 0.0 else -1.0)
		var hyst: float = 0.16 if side_sign == pref_sign else 0.0
		var score: float = free_frac * 1.45 + goal_align * 0.72 + slide_bonus + hyst - close_pen
		if score > best_score:
			best_score = score
			best_dir = cand
			chosen_ang = ang_deg

	var out_side: float = pref_sign if absf(chosen_ang) < 1.0 else (1.0 if chosen_ang > 0.0 else -1.0)
	var blend_w: float = clampf(1.35 - (center_dist / probe_dist) * 0.70, 0.68, 1.0) if center_wall else 0.65
	var out_dir: Vector3 = (dir.lerp(best_dir, blend_w)).normalized()
	return {"dir": out_dir, "blocked": center_wall and center_dist < 0.95, "side": out_side}
