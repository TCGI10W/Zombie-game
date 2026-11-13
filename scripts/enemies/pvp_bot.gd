class_name PvpBot
extends CharacterBody3D

# Tactical AI combatant for 32-player PvP (TDM, Gun Game, S&D, Domination).
# Shares layer 2 collision and head_y() with RemotePlayer so hits behave identically.

const ZombieRigScript := preload("res://scripts/enemies/zombie_rig.gd")
const SkinRigAdapterScript := preload("res://scripts/enemies/skin_rig_adapter.gd")
const SURVIVOR_MODEL := "res://assets/models/player_survivor.glb"
const GUN_LENGTH := {"pistol": 0.24, "revolver": 0.30, "smg": 0.50, "rifle": 0.86, "shotgun": 0.90, "lmg": 1.00, "sniper": 1.10, "volt": 0.62, "knife": 0.18}
const BOT_MOVE_SPEED := 5.6
const BOT_SPRINT_SPEED := 7.2
const BOT_SLIDE_SPEED := 9.8

var bot_key: String = ""
var bot_index: int = 0
var display_name: String = "BOT"
var team_id: int = 0
var color: Color = Color.WHITE
var weapon_id: String = "rifle"
var primary_id: String = "rifle"
var secondary_id: String = "pistol"
var lethal_id: String = "frag"
var tactical_id: String = "flashbang"
var bot_perk: String = "flak_jacket"
var gg_tier: int = 0

var hp: float = 100.0
var max_hp: float = 100.0
var is_dead: bool = false
var crouching: bool = false
var pitch: float = 0.0

var rig = null
var _hurtboxes: Array[Area3D] = []
var model: Node3D
var gun: Node3D
var _gun_vis: Node3D
var _knife_blade: MeshInstance3D
var _team_chevron: MeshInstance3D
var _head_chevron: MeshInstance3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _nameplate: Label3D
var _nav: NavigationAgent3D
var _fire_audio: AudioStreamPlayer3D

var _target: Node3D = null
var _goal_pos: Vector3 = Vector3.ZERO
var _los_t: float = 0.0
var _repath_t: float = 0.0
var _fire_cd: float = 0.0
var _strafe_t: float = 0.0
var _strafe_dir: float = 1.0
var _flash_t: float = 0.0
var _death_hide_t: float = -1.0
var _yaw_rate: float = 0.0
var _prev_yaw: float = 0.0
var _roam_seed: int = 0
var _stuck_t: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _jump_cd: float = 0.0
var _bypass_t: float = 0.0
var _bypass_dir: Vector3 = Vector3.ZERO
var _tgt_nav_t: float = 0.0
var _mag_left: int = 30
var _reloading_t: float = 0.0
var _lethal_left: int = 1
var _tactical_left: int = 1
var _ordnance_cd: float = 2.0
var _slide_t: float = 0.0
var _slide_cd: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _crouch_t: float = 0.0
var _flashed_t: float = 0.0
var _concussed_t: float = 0.0
var _recoil_t: float = 0.0
var _throw_anim_t: float = 0.0
var _anim_crouch: float = 0.0
var _last_seen_pos: Vector3 = Vector3.ZERO
var _has_last_seen: bool = false
var _last_attacker_pos: Vector3 = Vector3.ZERO
var _retreat_t: float = 0.0
var _strafe_lean: float = 0.0


func setup(p_key: String, p_idx: int, p_name: String, p_team: int, p_weapon: String) -> void:
	bot_key = p_key
	bot_index = p_idx
	display_name = p_name
	team_id = p_team
	color = GameState.pvp_team_color(p_team)
	weapon_id = p_weapon
	name = "PvpBot_%s" % p_key
	_roam_seed = p_idx * 7919 + p_team * 131


func head_y() -> float:
	return 1.38 if crouching else 1.62


func _ready() -> void:
	add_to_group("pvp_combatants")
	add_to_group("pvp_bots")
	collision_layer = 2
	collision_mask = 1 | 16

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)

	model = Node3D.new()
	add_child(model)
	if ResourceLoader.exists(SURVIVOR_MODEL):
		var inst: Node3D = (load(SURVIVOR_MODEL) as PackedScene).instantiate()
		model.add_child(inst)
		rig = ZombieRigScript.new()
		var proxies := SkinRigAdapterScript.attach(inst)
		if rig.bind(proxies if proxies else inst):
			rig.limp = 0.0
			rig.hunch = 0.0
			rig.arm_style = 2
			rig.sway = 0.25
			rig.head_tilt = 0.0
			rig.stride_mult = 1.0
			rig.gait_mult = 1.0
			_hurtboxes = HitboxRig.attach_humanoid(self, rig.nodes, false)
		else:
			rig = null

	# Emissive shoulder + helmet chevron (zero shadow-casting lights across 32 players)
	var badge_mat := MaterialLib.get_emissive(color, 1.8)
	_team_chevron = MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.36, 0.06, 0.26)
	_team_chevron.mesh = sbm
	_team_chevron.position = Vector3(0.0, 1.44, 0.0)
	_team_chevron.material_override = badge_mat
	model.add_child(_team_chevron)

	_head_chevron = MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.18, 0.04, 0.18)
	_head_chevron.mesh = hbm
	_head_chevron.position = Vector3(0.0, 1.79, 0.0)
	_head_chevron.material_override = badge_mat
	model.add_child(_head_chevron)

	_build_weapon_visuals()

	_nameplate = Label3D.new()
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = true
	_nameplate.fixed_size = true
	_nameplate.pixel_size = 0.00105
	_nameplate.font_size = 24
	_nameplate.outline_size = 7
	_nameplate.modulate = color
	_nameplate.position.y = 2.12
	_nameplate.text = display_name
	add_child(_nameplate)

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.9
	_nav.target_desired_distance = 1.35
	_nav.radius = 0.35
	_nav.avoidance_enabled = false
	add_child(_nav)

	_fire_audio = AudioStreamPlayer3D.new()
	_fire_audio.bus = &"SFX"
	_fire_audio.unit_size = 8.0
	_fire_audio.max_distance = 62.0
	_fire_audio.position.y = 1.4
	add_child(_fire_audio)

	_los_t = 0.05 * float(bot_index % 6)
	_repath_t = 0.08 * float(bot_index % 5)
	_last_pos = global_position
	set_weapon(weapon_id)


func _build_weapon_visuals() -> void:
	gun = Node3D.new()
	_gun_vis = Node3D.new()
	gun.add_child(_gun_vis)

	_knife_blade = MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.02, 0.04, 0.24)
	_knife_blade.mesh = km
	_knife_blade.material_override = MaterialLib.get_pbr("gunmetal", 2.0, Color(0.75, 0.80, 0.86), 0.25, 0.9, false)
	_knife_blade.position = Vector3(0.08, 0.0, -0.14)
	_knife_blade.visible = false
	gun.add_child(_knife_blade)

	_muzzle = Node3D.new()
	gun.add_child(_muzzle)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.42)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 4.5
	_flash_light.visible = false
	_muzzle.add_child(_flash_light)

	add_child(gun)
	gun.position = Vector3(0.14, 1.24, -0.24)


func set_loadout_kit(pri: String, sec: String, let_id: String, tac_id: String, perk_id: String) -> void:
	primary_id = pri
	secondary_id = sec
	lethal_id = let_id
	tactical_id = tac_id
	bot_perk = perk_id


func set_weapon(wid: String) -> void:
	weapon_id = wid
	var cfg: Dictionary = GameState.WEAPONS.get(wid, {})
	_mag_left = maxi(1, int(cfg.get("mag_size", 24)))
	_reloading_t = 0.0
	if _gun_vis == null:
		return
	var is_knife: bool = (wid == "knife")
	_gun_vis.visible = not is_knife
	_knife_blade.visible = is_knife
	if is_knife:
		_muzzle.position = Vector3(0.0, 0.0, -0.25)
		return
	var mz: Vector3 = WeaponRigBuilder.build_world_gun(_gun_vis, wid)
	_muzzle.position = mz


func spawn_at(pos: Vector3, yaw: float) -> void:
	is_dead = false
	hp = max_hp
	crouching = false
	_death_hide_t = -1.0
	_target = null
	_goal_pos = pos
	_fire_cd = 0.45
	_jump_cd = 0.0
	_bypass_t = 0.0
	_stuck_t = 0.0
	_tgt_nav_t = 0.0
	_slide_t = 0.0
	_slide_cd = randf_range(1.2, 2.6)
	_crouch_t = 0.0
	_flashed_t = 0.0
	_concussed_t = 0.0
	_recoil_t = 0.0
	_throw_anim_t = 0.0
	_retreat_t = 0.0
	_has_last_seen = false
	_reloading_t = 0.0
	_lethal_left = 1
	_tactical_left = 1
	_ordnance_cd = randf_range(2.2, 5.0)
	if GameState.pvp_mode != "gungame" and primary_id != "":
		set_weapon(primary_id)
	else:
		var cfg: Dictionary = GameState.WEAPONS.get(weapon_id, {})
		_mag_left = maxi(1, int(cfg.get("mag_size", 24)))
	collision_layer = 2
	HitboxRig.set_enabled(_hurtboxes, true)
	visible = true
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	_last_pos = pos
	if _nav:
		_nav.target_position = pos


func mark_dead() -> void:
	if is_dead:
		return
	is_dead = true
	HitboxRig.set_enabled(_hurtboxes, false)
	collision_layer = 0
	velocity = Vector3.ZERO
	_death_hide_t = 0.65
	if _flash_light:
		_flash_light.visible = false


func trigger_muzzle_fx(w_id: String, cam_pos: Vector3) -> void:
	_recoil_t = 1.0
	var dist: float = global_position.distance_to(cam_pos)
	if dist <= 32.0:
		_flash_t = 0.05
	if dist <= 55.0 and _fire_audio:
		var cfg: Dictionary = GameState.WEAPONS.get(w_id, {})
		var sfx_id: String = String(cfg.get("sfx", "knife_swing" if w_id == "knife" else ("gun_" + w_id)))
		var st: AudioStream = GameState.get_sfx_stream(sfx_id)
		if st == null:
			st = GameState.get_sfx_stream("gun_rifle")
		if st:
			_fire_audio.stream = st
			var base_pitch: float = float(cfg.get("sfx_pitch", 1.0))
			_fire_audio.pitch_scale = base_pitch * randf_range(0.95, 1.05)
			_fire_audio.volume_db = -7.0 if dist > 25.0 else -3.0
			_fire_audio.play()


func get_accuracy_spread_mult() -> float:
	var m: float = 1.0
	if crouching:
		m *= 0.72
	if _slide_t > 0.0:
		m *= 1.38
	if not is_on_floor():
		m *= 1.55
	if _flashed_t > 0.0:
		m *= 3.0
	if _concussed_t > 0.0:
		m *= 1.85
	return m


func notify_damaged_from(attacker_pos: Vector3) -> void:
	if is_dead:
		return
	_last_attacker_pos = attacker_pos
	_last_seen_pos = attacker_pos
	_has_last_seen = true
	if _target == null:
		var vec := attacker_pos - global_position
		if Vector2(vec.x, vec.z).length_squared() > 0.2:
			rotation.y = lerp_angle(rotation.y, atan2(-vec.x, -vec.z), 0.55)
			_acquire_target()
	# Tactical evade / cover reaction under heavy fire
	if hp <= 42.0:
		_retreat_t = maxf(_retreat_t, 2.1)
	if _slide_cd <= 0.0 and is_on_floor() and _slide_t <= 0.0:
		var away := global_position - attacker_pos
		away.y = 0.0
		if away.length_squared() > 0.04:
			var perp := Vector3(-away.z, 0.0, away.x).normalized() * _strafe_dir
			_slide_dir = (away.normalized() * 0.45 + perp * 0.85).normalized()
			_slide_t = 0.52
			_slide_cd = 3.2


func apply_tactical_effect(kind: String, dur: float) -> void:
	if is_dead:
		return
	var mult: float = 0.35 if bot_perk == "tactical_mask" else 1.0
	if kind == "flashbang" or kind == "flash":
		_flashed_t = maxf(_flashed_t, dur * mult)
		_target = null
	elif kind == "concussion":
		_concussed_t = maxf(_concussed_t, dur * mult)


func muzzle_world_pos() -> Vector3:
	return _muzzle.global_position if _muzzle else (global_position + Vector3(0.0, 1.32, 0.0))


func _physics_process(delta: float) -> void:
	# Remote clients only play interpolated/dead state when synced, bots run on host or offline.
	if Net.is_online() and not Net.is_host():
		return

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_light:
			_flash_light.visible = true
			_flash_light.light_energy = 2.6
	elif _flash_light and _flash_light.visible:
		_flash_light.visible = false

	if is_dead:
		if _death_hide_t > 0.0:
			_death_hide_t -= delta
			if rig:
				rig.update(delta, "dead", 0.0, {"vel": Vector3.ZERO, "yaw_rate": 0.0})
			if _death_hide_t <= 0.0:
				visible = false
		return

	var pvp_dir := get_tree().get_first_node_in_group("pvp_director")
	if pvp_dir == null or not pvp_dir.match_active():
		_update_presentation(delta, Vector3.ZERO)
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0

	_fire_cd = maxf(0.0, _fire_cd - delta)
	_jump_cd = maxf(0.0, _jump_cd - delta)
	_bypass_t = maxf(0.0, _bypass_t - delta)
	_tgt_nav_t = maxf(0.0, _tgt_nav_t - delta)
	_slide_cd = maxf(0.0, _slide_cd - delta)
	_ordnance_cd = maxf(0.0, _ordnance_cd - delta)
	_flashed_t = maxf(0.0, _flashed_t - delta)
	_concussed_t = maxf(0.0, _concussed_t - delta)
	_recoil_t = maxf(0.0, _recoil_t - delta * 6.5)
	_throw_anim_t = maxf(0.0, _throw_anim_t - delta)
	_retreat_t = maxf(0.0, _retreat_t - delta)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.75, 1.55)
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0

	if _reloading_t > 0.0:
		_reloading_t = maxf(0.0, _reloading_t - delta)
		if _reloading_t <= 0.0:
			var cfg_r: Dictionary = GameState.WEAPONS.get(weapon_id, {})
			_mag_left = maxi(1, int(cfg_r.get("mag_size", 24)))

	if _slide_t > 0.0:
		_slide_t = maxf(0.0, _slide_t - delta)
	if _crouch_t > 0.0:
		_crouch_t = maxf(0.0, _crouch_t - delta)
	crouching = (_crouch_t > 0.0) or (_slide_t > 0.0)

	# Staggered target / LOS check
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.22 + 0.02 * float(bot_index % 5)
		_acquire_target()

	# Staggered objective / roam waypoint update
	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = 0.60 + 0.1 * float(bot_index % 4)
		_update_goal(pvp_dir)
		if _nav:
			_nav.target_position = _goal_pos

	# S&D Plant / Defuse channel if near objective without immediate point-blank duel
	var channeling_site: bool = _try_objective_channel(pvp_dir, delta)

	# Movement + Aim + Tactical Kit Decisions
	var desired_dir := Vector3.ZERO
	var move_speed: float = BOT_MOVE_SPEED
	var has_target: bool = (_flashed_t <= 0.0) and is_instance_valid(_target) and not _target.is_dead

	if GameState.pvp_mode != "gungame" and primary_id != "" and secondary_id != "":
		if has_target:
			var td: float = global_position.distance_to(_target.global_position)
			var sec_cls: String = String(GameState.WEAPONS.get(secondary_id, {}).get("class", "pistol"))
			if weapon_id == primary_id and _mag_left <= 0 and td < 18.0 and sec_cls != "launcher":
				set_weapon(secondary_id)
			elif weapon_id == primary_id and sec_cls == "launcher" and td >= 13.0 and td <= 36.0 and randf() < 0.02:
				set_weapon(secondary_id)
		elif weapon_id == secondary_id and _mag_left <= 0:
			set_weapon(primary_id)

	if has_target:
		_last_seen_pos = _target.global_position
		_has_last_seen = true
	elif _has_last_seen and global_position.distance_to(_last_seen_pos) < 2.2:
		_has_last_seen = false

	if not channeling_site:
		if _flashed_t > 0.0:
			# Flashed: stagger backward / sideways blindly
			var back := global_basis.z * 0.5 + global_basis.x * _strafe_dir * 0.7
			back.y = 0.0
			desired_dir = back.normalized() if back.length_squared() > 0.01 else Vector3.ZERO
			move_speed = 3.1
		elif _slide_t > 0.0 and _slide_dir.length_squared() > 0.04:
			desired_dir = _slide_dir
			move_speed = BOT_SLIDE_SPEED
		elif has_target:
			var to_tgt: Vector3 = _target.global_position - global_position
			var dist: float = Vector2(to_tgt.x, to_tgt.z).length()
			var flat_dir: Vector3 = Vector3(to_tgt.x, 0.0, to_tgt.z).normalized() if dist > 0.05 else -global_basis.z
			var right_dir: Vector3 = Vector3(-flat_dir.z, 0.0, flat_dir.x)
			var wcls: String = String(GameState.WEAPONS.get(weapon_id, {}).get("class", "ar"))

			# Opportunistic tactical crouch / slide / jump-peek
			if is_on_floor():
				if _retreat_t > 0.0:
					desired_dir = (-flat_dir * 0.75 + right_dir * _strafe_dir * 0.65).normalized()
					move_speed = BOT_SPRINT_SPEED
				elif weapon_id == "knife":
					desired_dir = flat_dir
					move_speed = BOT_SPRINT_SPEED
				elif dist > 10.0 and dist < 24.0 and _slide_cd <= 0.0 and randf() < 0.025 and (wcls == "smg" or wcls == "shotgun"):
					_slide_dir = (flat_dir * 0.78 + right_dir * _strafe_dir * 0.55).normalized()
					_slide_t = 0.54
					_slide_cd = 3.6
					desired_dir = _slide_dir
					move_speed = BOT_SLIDE_SPEED
				else:
					if _crouch_t <= 0.0 and dist >= 9.0 and dist <= 34.0 and randf() < 0.014:
						_crouch_t = randf_range(0.65, 1.35)
					elif _jump_cd <= 0.0 and dist >= 6.0 and dist <= 16.0 and wcls != "sniper" and randf() < 0.008:
						velocity.y = 6.5
						_jump_cd = 1.6
					if dist > 22.0 or wcls == "shotgun" and dist > 11.0:
						desired_dir = (flat_dir + right_dir * _strafe_dir * 0.35).normalized()
					elif dist < 6.5:
						desired_dir = (-flat_dir * 0.45 + right_dir * _strafe_dir).normalized()
					else:
						desired_dir = right_dir * _strafe_dir * (0.55 if crouching else 0.90)
					if crouching:
						move_speed = 3.2
			else:
				desired_dir = right_dir * _strafe_dir * 0.85

			if desired_dir.length_squared() > 0.04 and StepHelper.is_blocked_ahead(self, desired_dir, 1.05):
				if is_on_floor() and _jump_cd <= 0.0 and StepHelper.probe_jumpable_obstacle(self, desired_dir, 1.25):
					velocity.y = 6.9
					_jump_cd = 0.85
				elif dist > 14.0 and _nav:
					if _tgt_nav_t <= 0.0:
						_nav.target_position = _target.global_position
						_tgt_nav_t = 0.25
					if not _nav.is_navigation_finished():
						var npt: Vector3 = _nav.get_next_path_position() - global_position
						npt.y = 0.0
						if npt.length_squared() > 0.04:
							desired_dir = npt.normalized()
				else:
					_strafe_dir = -_strafe_dir
					_strafe_t = 1.1
					desired_dir = StepHelper.pick_bypass_dir(self, desired_dir)
		elif _has_last_seen:
			var lvec := _last_seen_pos - global_position
			lvec.y = 0.0
			if lvec.length_squared() > 0.16:
				desired_dir = lvec.normalized()
				move_speed = BOT_SPRINT_SPEED
		elif _nav and not _nav.is_navigation_finished():
			var next_pt: Vector3 = _nav.get_next_path_position()
			var step_v: Vector3 = next_pt - global_position
			step_v.y = 0.0
			if step_v.length_squared() > 0.04:
				desired_dir = step_v.normalized()
				move_speed = BOT_SPRINT_SPEED
		elif _goal_pos.distance_to(global_position) > 1.8:
			var direct_v := _goal_pos - global_position
			direct_v.y = 0.0
			if direct_v.length_squared() > 0.04:
				desired_dir = direct_v.normalized()
				move_speed = BOT_SPRINT_SPEED

	if _concussed_t > 0.0:
		move_speed *= 0.55

	if desired_dir.length_squared() > 0.01:
		var st: Dictionary = StepHelper.steer_around_obstacles(self, desired_dir, 1.95, _strafe_dir)
		desired_dir = st["dir"] as Vector3
		var sep := _bot_separation() * 0.65
		if sep.length_squared() > 0.001:
			desired_dir = (desired_dir + sep).normalized()
		if _bypass_t > 0.0:
			desired_dir = (desired_dir * 0.35 + _bypass_dir * 0.65).normalized()

	# Unified stuck recovery (works both with and without active combat target)
	if desired_dir.length_squared() > 0.04:
		_stuck_t += delta
		if _stuck_t >= 0.70:
			_stuck_t = 0.0
			var moved_2d := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
			_last_pos = global_position
			if moved_2d < 0.32:
				if is_on_floor() and _jump_cd <= 0.0 and StepHelper.probe_jumpable_obstacle(self, desired_dir, 1.25):
					velocity.y = 7.0
					_jump_cd = 0.85
				else:
					_strafe_dir = -_strafe_dir
					_bypass_dir = StepHelper.pick_bypass_dir(self, desired_dir)
					_bypass_t = 0.65
					if not has_target:
						_update_goal(pvp_dir)
						if _nav:
							_nav.target_position = _goal_pos
	else:
		_stuck_t = 0.0
		_last_pos = global_position

	velocity.x = lerpf(velocity.x, desired_dir.x * move_speed, clampf(delta * 10.0, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, desired_dir.z * move_speed, clampf(delta * 10.0, 0.0, 1.0))
	if is_on_floor() and velocity.y <= 0.5 and desired_dir.length_squared() > 0.04:
		var stepped := StepHelper.try_step_up(self, Vector3(velocity.x, 0.0, velocity.z), delta, 0.34)
		if stepped == 0.0 and is_on_wall() and _jump_cd <= 0.0 and StepHelper.probe_jumpable_obstacle(self, desired_dir, 1.25):
			velocity.y = 6.9
			_jump_cd = 0.85
	move_and_slide()

	# Facing, Ordnance & Firing
	var aim_dir_3d: Vector3 = -global_basis.z
	if has_target:
		var ty: float = _target.head_y() if _target.has_method("head_y") else 1.55
		var aim_pt: Vector3 = _target.global_position + Vector3(0.0, ty * 0.82, 0.0)
		var eye: Vector3 = global_position + Vector3(0.0, head_y(), 0.0)
		var vec: Vector3 = aim_pt - eye
		var flat_len: float = maxf(0.1, Vector2(vec.x, vec.z).length())
		var want_yaw: float = atan2(-vec.x, -vec.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 12.0, 0.0, 1.0))
		pitch = lerpf(pitch, clampf(atan2(vec.y, flat_len), -0.9, 0.9), clampf(delta * 12.0, 0.0, 1.0))
		aim_dir_3d = vec.normalized()
		var dist_t: float = eye.distance_to(aim_pt)

		# Ordnance throw logic (tactical flash/smoke/concussion or frag/semtex/thermite)
		if _ordnance_cd <= 0.0 and dist_t >= 7.0 and dist_t <= 26.0 and GameState.pvp_mode != "gungame":
			if hp <= 48.0 and tactical_id == "smoke" and _tactical_left > 0 and pvp_dir.has_method("bot_throw_ordnance"):
				_tactical_left -= 1
				_ordnance_cd = 7.0
				_throw_anim_t = 0.42
				pvp_dir.bot_throw_ordnance(self, global_position.lerp(_target.global_position, 0.35), true)
			elif _tactical_left > 0 and randf() < 0.015 and pvp_dir.has_method("bot_throw_ordnance"):
				_tactical_left -= 1
				_ordnance_cd = 6.5
				_throw_anim_t = 0.42
				pvp_dir.bot_throw_ordnance(self, _target.global_position, true)
			elif _lethal_left > 0 and randf() < 0.014 and pvp_dir.has_method("bot_throw_ordnance"):
				_lethal_left -= 1
				_ordnance_cd = 6.5
				_throw_anim_t = 0.42
				pvp_dir.bot_throw_ordnance(self, _target.global_position, false)

		if _reloading_t <= 0.0 and _fire_cd <= 0.0:
			var cfg_w: Dictionary = GameState.WEAPONS.get(weapon_id, {})
			var max_range: float = 2.35 if weapon_id == "knife" else (24.0 if String(cfg_w.get("class", "")) == "shotgun" else 56.0)
			if dist_t <= max_range:
				_fire_cd = _weapon_interval(weapon_id)
				pvp_dir.bot_attempt_fire(self, _target, eye, aim_dir_3d, weapon_id)
				if weapon_id != "knife":
					_mag_left -= 1
					if _mag_left <= 0:
						var rel_t: float = float(cfg_w.get("reload_time", 1.85))
						if bot_perk == "fast_hands":
							rel_t *= 0.72
						_reloading_t = rel_t
	elif desired_dir.length_squared() > 0.05:
		var move_yaw: float = atan2(-desired_dir.x, -desired_dir.z)
		rotation.y = lerp_angle(rotation.y, move_yaw, clampf(delta * 8.0, 0.0, 1.0))
		pitch = lerpf(pitch, 0.0, clampf(delta * 8.0, 0.0, 1.0))

	_update_presentation(delta, velocity)


func _bot_separation() -> Vector3:
	var push := Vector3.ZERO
	for b in get_tree().get_nodes_in_group("pvp_bots"):
		if b == self:
			continue
		var other := b as Node3D
		if other == null or not is_instance_valid(other):
			continue
		if "is_dead" in other and other.is_dead:
			continue
		var off := global_position - other.global_position
		off.y = 0.0
		var d := off.length()
		if d > 0.01 and d < 1.05:
			push += (off / d) * (1.05 - d)
	return push


func _weapon_interval(wid: String) -> float:
	if wid == "knife":
		return 0.55
	var cfg: Dictionary = GameState.WEAPONS.get(wid, {})
	if not cfg.is_empty():
		var base_rate: float = maxf(0.11, float(cfg.get("fire_rate", 0.14)))
		var cls: String = String(cfg.get("class", "rifle"))
		match cls:
			"smg": return randf_range(base_rate * 1.15, base_rate * 1.85)
			"rifle", "br", "lmg": return randf_range(maxf(0.15, base_rate * 1.25), maxf(0.24, base_rate * 2.15))
			"shotgun": return randf_range(maxf(0.55, base_rate * 1.05), maxf(0.85, base_rate * 1.35))
			"sniper": return randf_range(maxf(0.80, base_rate * 1.05), maxf(1.25, base_rate * 1.35))
			"launcher", "special": return randf_range(maxf(1.05, base_rate * 1.1), maxf(1.55, base_rate * 1.4))
			"wonder": return randf_range(0.28, 0.45)
			_: return randf_range(maxf(0.22, base_rate * 1.2), maxf(0.38, base_rate * 1.6))
	return randf_range(0.24, 0.40)


func _is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	var ab: Vector3 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 < 0.01:
		return false
	for sc in get_tree().get_nodes_in_group("smoke_clouds"):
		var s := sc as Node3D
		if s == null or not is_instance_valid(s):
			continue
		var r: float = float(s.get_meta("radius", s.get_meta("cloud_radius", 6.2)))
		var t: float = clampf((s.global_position - a).dot(ab) / ab_len2, 0.0, 1.0)
		var closest: Vector3 = a + ab * t
		if closest.distance_to(s.global_position) <= r:
			return true
	return false


func _acquire_target() -> void:
	if _flashed_t > 0.0:
		_target = null
		return
	var best: Node3D = null
	var best_d: float = 52.0
	var eye: Vector3 = global_position + Vector3(0.0, head_y(), 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var self_rid: RID = get_rid()

	for c in get_tree().get_nodes_in_group("pvp_combatants"):
		var n := c as Node3D
		if n == null or n == self or not is_instance_valid(n):
			continue
		if "is_dead" in n and n.is_dead:
			continue
		var t_id: int = int(n.team_id) if "team_id" in n else -1
		if t_id == team_id:
			continue
		var tgt_eye: Vector3 = n.global_position + Vector3(0.0, 1.35, 0.0)
		var d: float = eye.distance_to(tgt_eye)
		if d > best_d:
			continue
		if _is_blocked_by_smoke(eye, tgt_eye):
			continue
		# LOS check against world geometry (layer 1 + 4)
		var q := PhysicsRayQueryParameters3D.create(eye, tgt_eye, 1 | 4, [self_rid])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			best_d = d
			best = n
	_target = best


func _update_goal(pvp_dir: Node) -> void:
	if is_instance_valid(_target) and not _target.is_dead:
		_goal_pos = _target.global_position
		return

	# Check objective zones
	var zones: Array = get_tree().get_nodes_in_group("pvp_objectives")
	if GameState.pvp_mode == "snd" and not zones.is_empty():
		# If any site is planted and my team didn't plant it -> rush to defuse!
		for z in zones:
			var oz := z as PvpObjectiveZone
			if oz and oz.is_planted and not oz.is_defused and pvp_dir.can_team_defuse(oz.zone_id, team_id):
				_goal_pos = oz.global_position + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
				return
		# If my team can plant -> pick site A or B deterministically
		var cand: Array = []
		for z in zones:
			var oz := z as PvpObjectiveZone
			if oz and not oz.is_planted and pvp_dir.can_team_plant(oz.zone_id, team_id):
				cand.append(oz)
		if not cand.is_empty():
			var pick: PvpObjectiveZone = cand[(_roam_seed / 7) % cand.size()]
			_goal_pos = pick.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			return
		# Otherwise patrol around sites
		var patrol_z: PvpObjectiveZone = zones[bot_index % zones.size()] as PvpObjectiveZone
		if patrol_z:
			_goal_pos = patrol_z.global_position + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
			return

	if GameState.pvp_mode == "dom" and not zones.is_empty():
		var best_z: PvpObjectiveZone = null
		var best_score: float = 99999.0
		for z in zones:
			var oz := z as PvpObjectiveZone
			if oz == null:
				continue
			var sc: float = global_position.distance_to(oz.global_position)
			if oz.owner_team == team_id and not oz.contested:
				sc += 42.0 # prioritize neutral / enemy flags
			if sc < best_score:
				best_score = sc
				best_z = oz
		if best_z:
			_goal_pos = best_z.global_position + Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
			return

	# TDM / Gun Game tactical waypoints across all arena sectors
	var arena := get_tree().get_first_node_in_group("arena")
	var hotspots: Array = arena.get_pvp_hotspots() if (arena and arena.has_method("get_pvp_hotspots")) else [
		Vector3(0.0, 0.0, 8.5),
		Vector3(-8.5, 0.0, -9.0),
		Vector3(14.0, 0.0, -6.5),
		Vector3(-24.0, 0.22, 25.2),
		Vector3(1.0, 0.0, -32.0),
		Vector3(34.0, 0.0, 8.0),
		Vector3(-26.5, 0.0, -2.5),
		Vector3(34.5, 0.0, -44.0),
	]
	_roam_seed = (_roam_seed * 1103515245 + 12345) & 0x7fffffff
	var base: Vector3 = hotspots[_roam_seed % hotspots.size()]
	_goal_pos = base + Vector3(randf_range(-5.0, 5.0), 0.0, randf_range(-5.0, 5.0))
	if arena and arena.has_method("zone_at") and arena.zone_at(_goal_pos) == "":
		_goal_pos = base


func _try_objective_channel(pvp_dir: Node, delta: float) -> bool:
	if GameState.pvp_mode != "snd":
		return false
	if is_instance_valid(_target) and _target.global_position.distance_to(global_position) < 9.0:
		return false
	for z in get_tree().get_nodes_in_group("pvp_objectives"):
		var oz := z as PvpObjectiveZone
		if oz == null or oz.zone_kind != "bomb_site":
			continue
		if global_position.distance_to(oz.global_position) <= 2.9:
			if pvp_dir.can_team_defuse(oz.zone_id, team_id):
				pvp_dir.advance_bot_site_hold(oz.zone_id, bot_key, team_id, "defuse", delta)
				return true
			if pvp_dir.can_team_plant(oz.zone_id, team_id):
				pvp_dir.advance_bot_site_hold(oz.zone_id, bot_key, team_id, "plant", delta)
				return true
	return false


func _update_presentation(delta: float, vel: Vector3) -> void:
	# Hide enemy nameplates so bots do not glow through walls
	if _nameplate:
		var cam := get_viewport().get_camera_3d()
		var d: float = cam.global_position.distance_to(global_position) if cam else 0.0
		_nameplate.visible = (not is_dead) and (team_id == Net.my_team) and (d <= 28.0)

	_yaw_rate = lerpf(_yaw_rate, wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001), clampf(10.0 * delta, 0.0, 1.0))
	_prev_yaw = rotation.y
	if rig == null:
		return
	var ground: float = Vector2(vel.x, vel.z).length()
	var is_sliding: bool = _slide_t > 0.0
	var is_air: bool = not is_on_floor()
	var mode: String = "idle"
	if is_dead:
		mode = "dead"
	elif is_sliding:
		mode = "idle"
	elif ground > 4.2:
		mode = "run"
	elif ground > 0.3:
		mode = "walk"
	var local_vel: Vector3 = global_basis.inverse() * vel
	rig.update(delta, mode, ground, {"vel": local_vel, "yaw_rate": _yaw_rate})

	var target_crouch: float = 1.0 if is_sliding else (0.55 if crouching else 0.0)
	_anim_crouch = lerpf(_anim_crouch, target_crouch, clampf(delta * 12.0, 0.0, 1.0))
	model.position.y = -0.46 * _anim_crouch
	_strafe_lean = lerpf(_strafe_lean, clampf(-local_vel.x * 0.028, -0.14, 0.14), clampf(delta * 9.0, 0.0, 1.0))

	var sprinting_no_tgt: bool = (not is_dead) and (not is_sliding) and (not crouching) and ground > 5.8 and _target == null
	var engage_w: float = 1.0 if (is_instance_valid(_target) and not sprinting_no_tgt and _reloading_t <= 0.0) else 0.0
	var n: Dictionary = rig.nodes
	var p: float = clampf(pitch, -1.2, 1.2)
	var kick: float = _recoil_t * 0.09
	var rel_tilt: float = sin(Time.get_ticks_msec() * 0.014) * 0.18 if _reloading_t > 0.0 else 0.0
	var throw_lean: float = sin(clampf(_throw_anim_t / 0.42, 0.0, 1.0) * PI) * 0.38
	var flash_sway: float = sin(Time.get_ticks_msec() * 0.018) * 0.24 if _flashed_t > 0.0 else 0.0

	if gun:
		var base_gun_y: float = 1.24 + model.position.y + 0.04 * engage_w
		var sprint_drop: float = -0.09 if sprinting_no_tgt else 0.0
		var reload_drop: float = -0.10 if _reloading_t > 0.0 else 0.0
		gun.position = Vector3(0.14 + (0.04 if sprinting_no_tgt else 0.0) - 0.02 * engage_w, base_gun_y + sprint_drop + reload_drop, -0.24 + kick * 0.55)
		gun.rotation = Vector3(
			p * 0.8 + kick * 1.4 - (0.34 if sprinting_no_tgt else 0.0) + rel_tilt,
			(0.45 if sprinting_no_tgt else 0.0) + flash_sway * 0.5,
			(0.28 if is_sliding else 0.0) + (-0.35 if _reloading_t > 0.0 else 0.0) + _strafe_lean * 0.45
		)
		gun.visible = not is_dead

	if n.has("Spine"):
		var sp_x: float = (-0.34 if is_sliding else (0.14 if sprinting_no_tgt else 0.0)) + throw_lean
		n["Spine"].rotation.x += sp_x
		n["Spine"].rotation.z += (0.12 if is_sliding else 0.0) + flash_sway * 0.35 + _strafe_lean * 0.6
	if n.has("Chest"):
		n["Chest"].rotation.x = p * 0.45 + (0.16 if crouching else 0.0) + kick * 0.6 + throw_lean * 0.5
		n["Chest"].rotation.z = rel_tilt * 0.4 + flash_sway * 0.35 + _strafe_lean * 0.45
	if n.has("Head"):
		n["Head"].rotation.x = p * 0.45 - (0.12 if is_sliding else 0.0) + (0.15 if _flashed_t > 0.0 else 0.0)
		n["Head"].rotation.y += flash_sway
	if is_sliding:
		if n.has("ThighL"):
			n["ThighL"].rotation.x = -1.15
		if n.has("ShinL"):
			n["ShinL"].rotation.x = 0.25
		if n.has("ThighR"):
			n["ThighR"].rotation.x = -0.45
		if n.has("ShinR"):
			n["ShinR"].rotation.x = 1.45
	elif crouching and not is_air:
		if n.has("ThighL"):
			n["ThighL"].rotation.x -= 0.55
		if n.has("ShinL"):
			n["ShinL"].rotation.x += 0.85
		if n.has("ThighR"):
			n["ThighR"].rotation.x -= 0.45
		if n.has("ShinR"):
			n["ShinR"].rotation.x += 0.75
	elif is_air:
		if n.has("ThighL"):
			n["ThighL"].rotation.x -= 0.42
		if n.has("ShinL"):
			n["ShinL"].rotation.x += 0.68
		if n.has("ThighR"):
			n["ThighR"].rotation.x -= 0.24
		if n.has("ShinR"):
			n["ShinR"].rotation.x += 0.42

	# Lock arm sleeves to zero so ShirtMesh skin never clips through sleeves
	for arm_name in ["UpperArmR", "ForearmR", "HandR", "UpperArmL", "ForearmL", "HandL"]:
		if n.has(arm_name):
			n[arm_name].rotation = Vector3.ZERO
