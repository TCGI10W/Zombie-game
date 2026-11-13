class_name CarrionCrow
extends Node3D

# 3D Carrion Crow for HORROR mode: circles overhead, perches on eaves/posts,
# descends to eat zombie corpses before their 6s mutation timer expires, and
# swoops past players to provoke panic shots & sprint noise. Can be shot down!

enum State {
	CIRCLE,
	PERCH,
	DESCEND,
	EAT,
	SWOOP_WARN,
	SWOOP_DIVE,
	SCATTER,
	TATTLETALE,
}

var state: int = State.CIRCLE
var manager: Node = null
var target_corpse_id: int = -1
var hp: float = 18.0
var is_dead: bool = false

# Orbit / Perch / Swoop kinematics
var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 11.0
var orbit_height: float = 10.5
var orbit_angle: float = 0.0
var orbit_dir: float = 1.0
var perch_pos: Vector3 = Vector3(0.0, 4.4, 0.0)
var perch_yaw: float = 0.0
var corpse_pos: Vector3 = Vector3.ZERO
var corpse_offset: Vector3 = Vector3.ZERO

var _t: float = 0.0
var _state_t: float = 0.0
var _wing_phase: float = 0.0
var _flap_amp: float = 0.0
var _wing_fold: float = 0.0
var _peck_phase: float = 0.0
var _peck_sfx_cd: float = 0.0
var _caw_cd: float = 3.0
var _flash_blind_t: float = 0.0
var _scatter_dir: Vector3 = Vector3(0.4, 0.9, 0.3)
var _swoop_start: Vector3 = Vector3.ZERO
var _swoop_pass: Vector3 = Vector3.ZERO
var _swoop_exit: Vector3 = Vector3.ZERO
var _swoop_scared_player: bool = false
var _tattletale_left: float = 0.0
var _tattletale_caw_cd: float = 0.6
var _vel: Vector3 = Vector3.ZERO

# Rig pivots
var _body_root: Node3D
var _head_piv: Node3D
var _tail_piv: Node3D
var _wing_l_inner: Node3D
var _wing_l_outer: Node3D
var _wing_r_inner: Node3D
var _wing_r_outer: Node3D
var _eye_mats: Array[StandardMaterial3D] = []
var _audio_3d: AudioStreamPlayer3D
var _hurtboxes: Array[Area3D] = []

static var _feather_mat: StandardMaterial3D
static var _beak_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("shootable_horror")
	add_to_group("carrion_crows")
	_wing_phase = randf() * TAU
	_caw_cd = randf_range(3.5, 9.5)
	_build_crow_mesh()
	_build_hurtbox()
	_build_audio()


func _exit_tree() -> void:
	HitboxRig.release_and_free(_hurtboxes)


func _ensure_mats() -> void:
	if _feather_mat == null:
		_feather_mat = StandardMaterial3D.new()
		_feather_mat.albedo_color = Color(0.028, 0.032, 0.044)
		_feather_mat.metallic = 0.28
		_feather_mat.roughness = 0.34
		_feather_mat.rim_enabled = true
		_feather_mat.rim = 0.28
		_feather_mat.rim_tint = 0.65
	if _beak_mat == null:
		_beak_mat = StandardMaterial3D.new()
		_beak_mat.albedo_color = Color(0.11, 0.11, 0.13)
		_beak_mat.roughness = 0.45


func _build_crow_mesh() -> void:
	_ensure_mats()
	_body_root = Node3D.new()
	add_child(_body_root)

	# Torso oval
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.13
	tm.height = 0.44
	tm.radial_segments = 10
	torso.mesh = tm
	torso.material_override = _feather_mat
	torso.rotation.x = deg_to_rad(68.0)
	_body_root.add_child(torso)

	# Head + Beak + Eyes
	_head_piv = Node3D.new()
	_head_piv.position = Vector3(0.0, 0.14, -0.22)
	_body_root.add_child(_head_piv)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.088
	hm.height = 0.175
	hm.radial_segments = 10
	head.mesh = hm
	head.material_override = _feather_mat
	_head_piv.add_child(head)

	var beak := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.005
	bm.bottom_radius = 0.032
	bm.height = 0.145
	bm.radial_segments = 6
	beak.mesh = bm
	beak.material_override = _beak_mat
	beak.rotation.x = deg_to_rad(-82.0)
	beak.position = Vector3(0.0, -0.015, -0.12)
	_head_piv.add_child(beak)

	var eye_sm := SphereMesh.new()
	eye_sm.radius = 0.014
	eye_sm.height = 0.028
	var eye_mat := MaterialLib.get_emissive(Color(0.95, 0.24, 0.18), 1.4).duplicate() as StandardMaterial3D
	_eye_mats.append(eye_mat)
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_sm
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(0.048 * sx, 0.025, -0.068)
		_head_piv.add_child(eye)

	# Fanned Tail Feathers (3 overlapping dark blades)
	_tail_piv = Node3D.new()
	_tail_piv.position = Vector3(0.0, -0.06, 0.20)
	_body_root.add_child(_tail_piv)
	for ti in [-1, 0, 1]:
		var tf := MeshInstance3D.new()
		var tfm := BoxMesh.new()
		tfm.size = Vector3(0.065, 0.012, 0.26)
		tf.mesh = tfm
		tf.material_override = _feather_mat
		tf.position = Vector3(float(ti) * 0.045, 0.0, 0.11)
		tf.rotation.y = deg_to_rad(-float(ti) * 14.0)
		tf.rotation.x = deg_to_rad(-10.0)
		_tail_piv.add_child(tf)

	# Two-segment Articulated Wings (Inner + Outer)
	_wing_l_inner = _make_wing_side(-1.0)
	_wing_l_outer = _wing_l_inner.get_node("Outer") as Node3D
	_wing_r_inner = _make_wing_side(1.0)
	_wing_r_outer = _wing_r_inner.get_node("Outer") as Node3D


func _make_wing_side(sx: float) -> Node3D:
	var inner := Node3D.new()
	inner.position = Vector3(0.11 * sx, 0.07, -0.04)
	_body_root.add_child(inner)

	var in_mesh := MeshInstance3D.new()
	var ib := BoxMesh.new()
	ib.size = Vector3(0.32, 0.018, 0.20)
	in_mesh.mesh = ib
	in_mesh.material_override = _feather_mat
	in_mesh.position = Vector3(0.16 * sx, 0.0, 0.03)
	inner.add_child(in_mesh)

	var outer := Node3D.new()
	outer.name = "Outer"
	outer.position = Vector3(0.31 * sx, 0.0, 0.01)
	inner.add_child(outer)

	var out_mesh := MeshInstance3D.new()
	var ob := BoxMesh.new()
	ob.size = Vector3(0.30, 0.014, 0.16)
	out_mesh.mesh = ob
	out_mesh.material_override = _feather_mat
	out_mesh.position = Vector3(0.14 * sx, 0.0, 0.03)
	outer.add_child(out_mesh)

	# Wingtip primary feather fan
	var tip := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.16, 0.010, 0.10)
	tip.mesh = tb
	tip.material_override = _feather_mat
	tip.position = Vector3(0.31 * sx, 0.0, 0.05)
	tip.rotation.y = deg_to_rad(-16.0 * sx)
	outer.add_child(tip)

	return inner


func _build_hurtbox() -> void:
	var area := Area3D.new()
	area.collision_layer = HitboxRig.HITBOX_LAYER
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.42
	cs.shape = sh
	area.add_child(cs)
	add_child(area)
	HitboxRig.register_hurtbox(area, self, "torso", 1.0)
	_hurtboxes.append(area)


func _build_audio() -> void:
	_audio_3d = AudioStreamPlayer3D.new()
	_audio_3d.bus = &"SFX"
	_audio_3d.unit_size = 7.0
	_audio_3d.max_distance = 42.0
	add_child(_audio_3d)


func _play_crow_sfx(vol_db: float = -4.0, pitch: float = 1.0) -> void:
	if is_dead or not is_instance_valid(_audio_3d):
		return
	var st := GameState.get_sfx_stream("crow")
	if st == null:
		return
	_audio_3d.stream = st
	_audio_3d.volume_db = vol_db
	_audio_3d.pitch_scale = pitch
	_audio_3d.play()


func set_perch(pos: Vector3, yaw: float) -> void:
	state = State.PERCH
	perch_pos = pos
	perch_yaw = yaw
	global_position = pos
	target_corpse_id = -1
	_state_t = randf_range(6.0, 14.0)


func begin_circle(center: Vector3, rad: float, h: float) -> void:
	state = State.CIRCLE
	orbit_center = center
	orbit_radius = rad
	orbit_height = h
	orbit_angle = randf() * TAU
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	target_corpse_id = -1
	_state_t = randf_range(7.0, 15.0)


func assign_corpse(cid: int, pos: Vector3, off: Vector3) -> void:
	target_corpse_id = cid
	corpse_pos = pos
	corpse_offset = off
	state = State.DESCEND
	_state_t = 0.0


func start_tattletale(dur: float) -> void:
	state = State.TATTLETALE
	target_corpse_id = -1
	_tattletale_left = dur
	_tattletale_caw_cd = 0.45
	_state_t = 0.0


func start_scare_swoop(player_pos: Vector3, player_fwd: Vector3) -> void:
	if is_dead or state == State.EAT or state == State.SWOOP_WARN or state == State.SWOOP_DIVE:
		return
	target_corpse_id = -1
	state = State.SWOOP_WARN
	_state_t = 0.0
	_swoop_scared_player = false
	var side := 1.0 if randf() < 0.5 else -1.0
	var right := player_fwd.cross(Vector3.UP).normalized()
	_swoop_start = global_position
	_swoop_pass = player_pos + Vector3(0.0, 1.58, 0.0) + right * (0.95 * side) - player_fwd * 0.35
	_swoop_exit = _swoop_pass - player_fwd * 7.5 + Vector3(right.x * 5.0 * side, 6.5, right.z * 5.0 * side)
	_play_crow_sfx(-5.0, randf_range(0.74, 0.86))


func scatter_away(from_pos: Vector3, emit_alarm: bool = true) -> void:
	if is_dead:
		return
	target_corpse_id = -1
	state = State.SCATTER
	_state_t = 0.0
	var away := global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()
	_scatter_dir = (away * 0.72 + Vector3.UP * 0.95).normalized()
	_vel = _scatter_dir * 11.5
	FX.gore_burst(global_position, 2, 1.5) # dark feather burst via _spawn_feathers
	_spawn_feathers(6, global_position)
	if emit_alarm:
		_play_crow_sfx(-1.0, randf_range(1.16, 1.32))
		ZombieEnemy.broadcast_sound(get_tree(), global_position, 26.0, true, "crow")


func lit_by_flashlight(p: Node3D) -> bool:
	if not is_instance_valid(p) or not p.has_method("flashlight_lit"):
		return false
	if not p.flashlight_lit():
		return false
	var fl: Node3D = p.get("flashlight") as Node3D
	if not is_instance_valid(fl):
		return false
	var to_me := global_position - fl.global_position
	var d := to_me.length()
	if d > 22.0 or d < 0.3:
		return false
	return (-fl.global_basis.z).dot(to_me / d) > 0.89


func _process(delta: float) -> void:
	if is_dead:
		return
	_t += delta
	_state_t += delta
	_caw_cd -= delta
	if _caw_cd <= 0.0:
		_caw_cd = randf_range(6.0, 14.0)
		if state in [State.CIRCLE, State.PERCH] and randf() < 0.45:
			_play_crow_sfx(-8.5, randf_range(0.88, 1.12))

	var p := get_tree().get_first_node_in_group("player") as Node3D
	# Flashlight counterplay: hold beam on perched/warning/diving crow to shoo it away silently!
	if is_instance_valid(p) and state in [State.PERCH, State.SWOOP_WARN, State.SWOOP_DIVE]:
		if lit_by_flashlight(p):
			_flash_blind_t += delta
			if _flash_blind_t >= 0.45:
				_flash_blind_t = 0.0
				scatter_away(p.global_position, false)
				return
		else:
			_flash_blind_t = maxf(0.0, _flash_blind_t - delta * 1.4)
	else:
		_flash_blind_t = 0.0

	var eye_em := 1.1
	var flap_rate := 5.5
	var target_fold := 0.0

	match state:
		State.CIRCLE:
			orbit_angle += orbit_dir * delta * (7.2 / maxf(4.0, orbit_radius))
			var tgt := orbit_center + Vector3(cos(orbit_angle) * orbit_radius, orbit_height + sin(_t * 1.3 + orbit_angle) * 0.7, sin(orbit_angle) * orbit_radius)
			var delta_p := tgt - global_position
			var dir := delta_p.normalized() if delta_p.length_squared() > 0.01 else -global_basis.z
			_vel = _vel.lerp(dir * 7.8, clampf(delta * 4.0, 0.0, 1.0))
			global_position += _vel * delta
			_face_fly(_vel, delta * 5.0, -0.32 * orbit_dir)
			flap_rate = 3.2 if sin(_t * 1.1 + orbit_angle) > -0.2 else 0.4 # alternating wingbeat & glide
			if _state_t >= 11.0 and manager and manager.has_method("try_perch_crow"):
				_state_t = 0.0
				manager.try_perch_crow(self)

		State.PERCH:
			global_position = global_position.lerp(perch_pos, clampf(delta * 8.0, 0.0, 1.0))
			_vel = Vector3.ZERO
			target_fold = 1.0
			flap_rate = 0.0
			rotation.x = lerpf(rotation.x, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			rotation.z = lerpf(rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))
			if is_instance_valid(p) and global_position.distance_to(p.global_position) < 22.0:
				var look := p.global_position - global_position
				look.y = 0.0
				if look.length_squared() > 0.01:
					rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), clampf(delta * 4.0, 0.0, 1.0))
			else:
				rotation.y = lerp_angle(rotation.y, perch_yaw, clampf(delta * 4.0, 0.0, 1.0))
			if _head_piv:
				_head_piv.rotation.y = sin(_t * 2.1) * 0.35
				_head_piv.rotation.z = sin(_t * 1.3) * 0.16
			if _state_t >= 14.0 and manager and manager.has_method("release_to_circle"):
				manager.release_to_circle(self)

		State.DESCEND:
			var goal := corpse_pos + corpse_offset + Vector3(0.0, 0.22, 0.0)
			var to_g := goal - global_position
			var dist := to_g.length()
			flap_rate = 7.4 if dist > 2.2 else 10.5
			if dist < 0.38:
				state = State.EAT
				_state_t = 0.0
				_vel = Vector3.ZERO
				global_position = goal
			else:
				var spd := clampf(dist * 3.8, 5.0, 11.5)
				_vel = to_g.normalized() * spd
				global_position += _vel * delta
				_face_fly(_vel, delta * 8.0, 0.0)

		State.EAT:
			global_position = global_position.lerp(corpse_pos + corpse_offset + Vector3(0.0, 0.20, 0.0), clampf(delta * 10.0, 0.0, 1.0))
			target_fold = 0.72
			flap_rate = 0.0
			_peck_phase += delta * 9.0
			var to_c := corpse_pos - global_position
			to_c.y = 0.0
			if to_c.length_squared() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(-to_c.x, -to_c.z), clampf(delta * 8.0, 0.0, 1.0))
			rotation.x = deg_to_rad(-18.0 + sin(_peck_phase) * 26.0)
			rotation.z = lerpf(rotation.z, sin(_peck_phase * 0.5) * 0.12, clampf(delta * 8.0, 0.0, 1.0))
			if _head_piv:
				_head_piv.rotation.x = deg_to_rad(-22.0 + sin(_peck_phase * 1.2) * 28.0)
			_peck_sfx_cd -= delta
			if _peck_sfx_cd <= 0.0:
				_peck_sfx_cd = randf_range(0.55, 0.95)
				_play_crow_sfx(-11.0, randf_range(1.18, 1.42))
				FX.gore_burst(corpse_pos + Vector3(0, 0.18, 0), 1, 1.4)

		State.SWOOP_WARN:
			eye_em = 4.2
			flap_rate = 8.5
			global_position = global_position.lerp(_swoop_start + Vector3(0, 0.5, 0), clampf(delta * 3.0, 0.0, 1.0))
			if is_instance_valid(p):
				var to_p := (p.global_position + Vector3(0, 1.5, 0)) - global_position
				_face_fly(to_p, delta * 10.0, 0.0)
			if _state_t >= 0.85:
				state = State.SWOOP_DIVE
				_state_t = 0.0
				_swoop_start = global_position
				_play_crow_sfx(-0.5, randf_range(1.12, 1.30))

		State.SWOOP_DIVE:
			eye_em = 5.0
			flap_rate = 11.0
			var u := clampf(_state_t / 0.95, 0.0, 1.0)
			if u < 0.55:
				var k := u / 0.55
				global_position = _swoop_start.lerp(_swoop_pass, k * k * (3.0 - 2.0 * k))
				if k > 0.82 and not _swoop_scared_player:
					_swoop_scared_player = true
					_spawn_feathers(10, _swoop_pass)
					if is_instance_valid(p):
						if p.has_method("add_camera_shake"):
							p.add_camera_shake(0.24)
						if p.get("stress") != null:
							p.set("stress", clampf(float(p.get("stress")) + 0.32, 0.0, 1.0))
						ZombieEnemy.broadcast_sound(get_tree(), _swoop_pass, 10.5, false, "crow")
			else:
				var k2 := (u - 0.55) / 0.45
				global_position = _swoop_pass.lerp(_swoop_exit, k2)
			_face_fly((_swoop_pass - _swoop_start) if u < 0.55 else (_swoop_exit - _swoop_pass), delta * 14.0, 0.35 if u < 0.55 else -0.25)
			if u >= 1.0:
				if manager and manager.has_method("release_to_circle"):
					manager.release_to_circle(self)
				else:
					begin_circle(Vector3.ZERO, 14.0, 10.5)

		State.SCATTER:
			flap_rate = 11.5
			global_position += _vel * delta
			_face_fly(_vel, delta * 9.0, 0.0)
			if _state_t >= 2.3:
				if manager and manager.has_method("release_to_circle"):
					manager.release_to_circle(self)
				else:
					begin_circle(Vector3.ZERO, 14.0, 11.0)

		State.TATTLETALE:
			eye_em = 3.8
			flap_rate = 6.2
			_tattletale_left -= delta
			var focus := p.global_position if is_instance_valid(p) else Vector3.ZERO
			orbit_angle += delta * 2.2 * orbit_dir
			var tgt := focus + Vector3(cos(orbit_angle) * 5.2, 6.2, sin(orbit_angle) * 5.2)
			var dv := tgt - global_position
			_vel = _vel.lerp(dv.normalized() * clampf(dv.length() * 2.6, 5.0, 12.0), clampf(delta * 5.0, 0.0, 1.0))
			global_position += _vel * delta
			_face_fly(_vel, delta * 8.0, -0.35 * orbit_dir)
			_tattletale_caw_cd -= delta
			if _tattletale_caw_cd <= 0.0:
				_tattletale_caw_cd = 2.1
				var sheltered: bool = manager != null and manager.has_method("is_player_sheltered") and bool(manager.is_player_sheltered())
				if not sheltered:
					_play_crow_sfx(-2.0, randf_range(1.04, 1.24))
					ZombieEnemy.broadcast_sound(get_tree(), focus, 15.0, true, "crow")
			if _tattletale_left <= 0.0:
				if manager and manager.has_method("release_to_circle"):
					manager.release_to_circle(self)
				else:
					begin_circle(Vector3.ZERO, 12.0, 10.0)

	_animate_wings(delta, flap_rate, target_fold)
	for em in _eye_mats:
		em.emission_energy_multiplier = eye_em


func _face_fly(vel_dir: Vector3, weight: float, bank: float) -> void:
	if vel_dir.length_squared() < 0.001:
		return
	var flat := Vector3(vel_dir.x, 0.0, vel_dir.z)
	if flat.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), clampf(weight, 0.0, 1.0))
	var pitch := clampf(vel_dir.y / maxf(vel_dir.length(), 0.5) * 0.65, -0.65, 0.65)
	rotation.x = lerpf(rotation.x, pitch, clampf(weight, 0.0, 1.0))
	rotation.z = lerpf(rotation.z, bank, clampf(weight * 0.7, 0.0, 1.0))


func _animate_wings(delta: float, flap_rate: float, target_fold: float) -> void:
	_wing_fold = lerpf(_wing_fold, target_fold, clampf(delta * 7.5, 0.0, 1.0))
	if flap_rate > 0.05:
		_wing_phase += delta * flap_rate * TAU
		_flap_amp = lerpf(_flap_amp, 1.0, clampf(delta * 8.0, 0.0, 1.0))
	else:
		_flap_amp = lerpf(_flap_amp, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var spread := 1.0 - _wing_fold
	var flap := sin(_wing_phase) * 0.78 * _flap_amp * spread
	var outer_lag := sin(_wing_phase - 0.65) * 0.58 * _flap_amp * spread
	if _wing_l_inner:
		_wing_l_inner.rotation.z = lerpf(flap, -1.15, _wing_fold)
		_wing_l_inner.rotation.y = lerpf(0.08, -1.15, _wing_fold)
		_wing_l_outer.rotation.z = lerpf(outer_lag, 0.55, _wing_fold)
	if _wing_r_inner:
		_wing_r_inner.rotation.z = lerpf(-flap, 1.15, _wing_fold)
		_wing_r_inner.rotation.y = lerpf(-0.08, 1.15, _wing_fold)
		_wing_r_outer.rotation.z = lerpf(-outer_lag, -0.55, _wing_fold)
	if _tail_piv:
		_tail_piv.rotation.x = sin(_wing_phase * 0.5) * 0.08 * spread


func take_bullet_hit(dmg: float, hit_pos: Vector3, shooter: Node3D) -> Dictionary:
	if is_dead:
		return {"hit": false, "killed": false}
	hp -= maxf(1.0, dmg)
	var impact := hit_pos if hit_pos != Vector3.ZERO else global_position
	_spawn_feathers(7, impact)
	if hp <= 0.0:
		is_dead = true
		HitboxRig.release_and_free(_hurtboxes)
		_spawn_feathers(16, global_position)
		FX.gore_burst(global_position, 5, 3.2)
		GameState.play_sfx("crow", 1.5, randf_range(1.25, 1.48))
		if is_instance_valid(shooter) and shooter.is_in_group("player"):
			GameState.add_points(50)
		if manager and manager.has_method("on_crow_killed"):
			manager.on_crow_killed(self, global_position, shooter)
		queue_free()
		return {"hit": true, "killed": true}
	return {"hit": true, "killed": false}


func _spawn_feathers(count: int, pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = count
	p.lifetime = 1.45
	p.one_shot = true
	p.explosiveness = 0.88
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -1.6, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.6
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.04, 0.045, 0.06)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.emitting = true
	p.create_tween().tween_callback(p.queue_free).set_delay(1.8)
