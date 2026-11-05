class_name PlayerController
extends CharacterBody3D

signal hp_changed(hp: float, max_hp: float, overshield: float)
signal ammo_changed(weapon_name: String, mag: int, reserve: int, is_reloading: bool, pap_active: bool)
signal hitmarker_triggered(is_headshot: bool, is_kill: bool, is_ability: bool)
signal status_banner_requested(text: String, color: Color)
signal interact_prompt_changed(prompt_text: String)
signal player_died()
signal damaged(from_pos: Vector3)
signal stats_changed()
signal downed_changed(is_downed: bool)

const FragGrenadeScript := preload("res://scripts/player/frag_grenade.gd")

const MOUSE_SENS := 0.0022
const GRAVITY := 19.0
const JUMP_VEL := 6.4
const STAND_HEAD := 1.62
const CROUCH_HEAD := 1.05
const SLIDE_HEAD := 0.82
const HIP_POS := Vector3(0.19, -0.2, -0.36)
var base_fov: float = 80.0 # set from the FOV setting
const SLIDE_TIME := 0.8
const KNIFE_DAMAGE := 150.0
const MAX_GRENADES := 4
const VIEWMODEL_LAYER := 4 # render layer 3

var char_id: String = "ravager"
var base_max_hp: float = 130.0
var max_hp: float = 130.0
var hp: float = 130.0
var overshield: float = 0.0
var base_move_speed: float = 5.3
var regen_delay_timer: float = 0.0
var is_dead: bool = false

# Last stand: with a Second Wind charge, lethal damage knocks you down instead
# of killing you, and you get back up a few seconds later.
const DOWNED_TIME := 5.5
const BLEEDOUT_TIME := 30.0 # co-op: time for a teammate to reach you
var self_reviving: bool = false # down with a Second Wind charge ticking
var bleedout_timer: float = 0.0
var _head_rest_y: float = 0.0
var _ng: Node = null
var revives: int = 0
var revives_bought: int = 0
var is_downed: bool = false
var downed_timer: float = 0.0
var revive_invuln: float = 0.0

# Extraction: hoisted into the helicopter and carried away
var extracted: bool = false
var _extract_node: Node3D

# Stats bought at the Augment Furnace: stat id -> points burned
var stat_burned: Dictionary = {}

# Movement state
var stamina: float = 1.0 # 0..1
var stamina_regen_delay: float = 0.0
var is_sprinting: bool = false
var winded: bool = false
var is_crouching: bool = false
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_dir: Vector3 = Vector3.ZERO
var slide_speed: float = 0.0
var slide_cd: float = 0.0
var sprint_out: float = 0.0
var sprint_t: float = 0.0
var was_on_floor: bool = true
var land_dip: float = 0.0
var head_height: float = STAND_HEAD
var step_dist: float = 0.0
var step_index: int = 0
var strafe_input: float = 0.0
var col_shape: CollisionShape3D
var capsule: CapsuleShape3D

# Loadout (up to 2 weapons)
var weapons_owned: Array[String] = ["pistol"]
var active_slot: int = 0
var mag_ammo: Dictionary = {}
var reserve_ammo: Dictionary = {}
var upgraded: Dictionary = {} # w_id -> true once forged
var fire_cooldown: float = 0.0
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_total: float = 1.0
var is_ads: bool = false
var ads_t: float = 0.0
var bloom: float = 0.0
var swap_state: int = 0 # 0 idle, 1 lowering, 2 raising
var swap_timer: float = 0.0
var swap_dur: float = 0.2
var pending_slot: int = 0
var knife_timer: float = 0.0
var grenades: int = 2
var grenade_cd: float = 0.0
var _dry_fired: bool = false
var _hurt_sfx_cd: float = 0.0

# Ability States
# 1. Ravager (Monster Transformation + 2 Monster Skills)
var is_monster_form: bool = false
var monster_timer: float = 0.0
var monster_duration: float = 18.0
var monster_cd: float = 0.0
var monster_cd_max: float = 24.0
var monster_rend_cd: float = 0.0
var monster_slam_cd: float = 0.0
var monster_slam_cd_max: float = 5.0
var human_lunge_cd: float = 0.0

# 2. Alchemist (Pain Drug Producer for Round Bosses + Stim)
var pain_drug_charges: int = 2
var pain_drug_max: int = 3
var pain_drug_synth_progress: float = 0.0
var pain_drug_synth_time: float = 15.0
var stim_timer: float = 0.0
var stim_cd: float = 0.0
var stim_cd_max: float = 20.0

# 3. Warden (Tesla Charge + Arc Overcharge)
var tesla_cd: float = 0.0
var tesla_cd_max: float = 13.0
var pap_timer: float = 0.0
var pap_cd: float = 0.0
var pap_cd_max: float = 24.0

# Camera & Viewmodel Rig
var head_pivot: Node3D
var camera: Camera3D
var gun_rig: Node3D
var gun_model: Node3D
var grenade_rig: Node3D

# Viewmodel moving parts (from the gun GLB): name -> {node, pos, rot}
const VM_PARTS := ["SlidePivot", "BoltPivot", "PumpPivot", "MagPivot", "CylinderPivot", "CoverPivot", "HammerPivot", "ArmL", "ArmR", "CoilPivot"]
var vm_parts: Dictionary = {}
var fire_anim_t: float = 9.0
var pump_t: float = 9.0
var pump_eject: bool = false
var bolt_t: float = 9.0
var shots_fired: int = 0
var reload_was_empty: bool = false
var _mag_out_played: bool = false
var _mag_in_played: bool = false
var _bolt_rel_played: bool = false
var grenade_anim_t: float = -1.0
var grenade_spawn_t: float = -1.0
var knife_rig: Node3D
var monster_claw_rig: Node3D
var claw_arm_l: Node3D
var claw_arm_r: Node3D
var muzzle_light: OmniLight3D
var muzzle_flash: MeshInstance3D
var muzzle_flash_timer: float = 0.0
var bob_phase: float = 0.0
var recoil_kick: Vector3 = Vector3.ZERO
var recoil_view: Vector2 = Vector2.ZERO
var recoil_view_vel: Vector2 = Vector2.ZERO
# Spring state for the weapon and camera (inertia, overshoot, impacts)
var vm_vel: Vector3 = Vector3.ZERO
var vm_rot_vel: Vector3 = Vector3.ZERO
var cam_spring: Vector3 = Vector3.ZERO
var cam_spring_vel: Vector3 = Vector3.ZERO
var _vm_time: float = 0.0
var camera_shake: float = 0.0
var sway: Vector2 = Vector2.ZERO
var hurt_roll: float = 0.0
var nearby_station: Node = null


func _ready() -> void:
	add_to_group("player")
	if not InputMap.has_action("borrowed_skill"):
		InputMap.add_action("borrowed_skill")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_X
		InputMap.action_add_event("borrowed_skill", ev)
	if not InputMap.has_action("borrowed_skill_2"):
		InputMap.add_action("borrowed_skill_2")
		var ev2 := InputEventKey.new()
		ev2.physical_keycode = KEY_Z
		InputMap.action_add_event("borrowed_skill_2", ev2)
	add_to_group("net_players")
	if GameState.has_unlock("grenade"):
		grenades += 1
	if GameState.has_unlock("start_smg") and not weapons_owned.has("smg"):
		weapons_owned.append("smg")
		mag_ammo["smg"] = GameState.WEAPONS["smg"]["mag_size"]
		reserve_ammo["smg"] = GameState.WEAPONS["smg"]["reserve_max"]
	collision_layer = 2
	collision_mask = 1 | 4 | 16 # World + Enemies + Window blockers

	col_shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.40
	capsule.height = 1.82
	col_shape.shape = capsule
	col_shape.position = Vector3(0, 0.91, 0)
	add_child(col_shape)

	base_fov = GameState.fov_setting
	char_id = GameState.selected_character
	var cdata: Dictionary = GameState.CHARACTERS.get(char_id, GameState.CHARACTERS["ravager"])
	base_max_hp = cdata["max_hp"]
	max_hp = base_max_hp
	hp = max_hp
	base_move_speed = float(cdata["move_speed"]) * 0.82

	for w_id in GameState.WEAPONS:
		mag_ammo[w_id] = 0
		reserve_ammo[w_id] = 0
	var p_cfg: Dictionary = GameState.WEAPONS["pistol"]
	mag_ammo["pistol"] = p_cfg["mag_size"]
	reserve_ammo["pistol"] = p_cfg["reserve_max"]

	_build_camera_and_viewmodels()
	_equip_weapon_model(get_current_weapon_id())
	hp_changed.emit(hp, max_hp, overshield)
	_emit_ammo()


func _build_camera_and_viewmodels() -> void:
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, STAND_HEAD, 0)
	add_child(head_pivot)

	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.03
	camera.far = 180.0
	camera.current = true
	head_pivot.add_child(camera)

	gun_rig = Node3D.new()
	gun_rig.position = HIP_POS
	camera.add_child(gun_rig)

	# Soft fill light so the viewmodel reads in dark rooms
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.55
	fill.omni_range = 1.1
	fill.position = Vector3(0.1, 0.25, 0.1)
	fill.light_cull_mask = VIEWMODEL_LAYER # only lights the gun & hands, not zombies in your face
	camera.add_child(fill)

	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.72, 0.30)
	muzzle_light.light_energy = 3.6
	muzzle_light.omni_range = 7.0
	muzzle_light.visible = false
	gun_rig.add_child(muzzle_light)

	muzzle_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	muzzle_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.75, 0.35)
	if ResourceLoader.exists("res://assets/textures/fx_muzzle_flash.png"):
		fm.albedo_texture = load("res://assets/textures/fx_muzzle_flash.png")
	elif ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		fm.albedo_texture = load("res://assets/textures/soft_particle.png")
	muzzle_flash.material_override = fm
	muzzle_flash.visible = false
	gun_rig.add_child(muzzle_flash)

	grenade_rig = Node3D.new()
	grenade_rig.visible = false
	camera.add_child(grenade_rig)
	if ResourceLoader.exists("res://assets/models/vm_grenade_hand.glb"):
		grenade_rig.add_child((load("res://assets/models/vm_grenade_hand.glb") as PackedScene).instantiate())

	knife_rig = Node3D.new()
	knife_rig.visible = false
	camera.add_child(knife_rig)
	if ResourceLoader.exists("res://assets/models/vm_knife.glb"):
		knife_rig.add_child((load("res://assets/models/vm_knife.glb") as PackedScene).instantiate())

	monster_claw_rig = Node3D.new()
	monster_claw_rig.position = Vector3(0.0, -0.18, -0.36)
	monster_claw_rig.visible = false
	camera.add_child(monster_claw_rig)

	if ResourceLoader.exists("res://assets/models/vm_monster_claws.glb"):
		var packed: PackedScene = load("res://assets/models/vm_monster_claws.glb")
		var claws := packed.instantiate()
		monster_claw_rig.add_child(claws)
		_mark_viewmodel(claws)
		claw_arm_l = claws.find_child("ClawArmL", true, false)
		claw_arm_r = claws.find_child("ClawArmR", true, false)
	_mark_viewmodel(knife_rig)
	_mark_viewmodel(grenade_rig)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom_scale := 1.0
		if is_ads and not is_monster_form:
			zoom_scale = lerpf(1.0, camera.fov / base_fov, 0.85)
		var sens := MOUSE_SENS * GameState.mouse_sens_mult * zoom_scale
		rotate_y(-event.relative.x * sens)
		head_pivot.rotation.x = clampf(head_pivot.rotation.x - event.relative.y * sens, deg_to_rad(-86.0), deg_to_rad(86.0))
		sway += Vector2(event.relative.x, event.relative.y) * 0.0009
		# The gun lags behind fast turns and swings back into place
		var lag := 0.0016 * (0.35 if is_ads else 1.0)
		vm_rot_vel += Vector3(event.relative.y * lag, -event.relative.x * lag * 1.3, -event.relative.x * lag)

	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not is_monster_form and weapons_owned.size() > 1:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_begin_swap((active_slot + 1) % weapons_owned.size())


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if extracted:
		if is_instance_valid(_extract_node) and _extract_node.get_meta("riding", false):
			global_position = _extract_node.global_position + Vector3(0, 0.6, 0)
		return
	_update_timers(delta)
	_handle_movement(delta)
	_handle_combat_inputs(delta)
	_animate_viewmodels(delta)


# ---------------------------------------------------------------------------
# STATS (Augment Furnace)
# ---------------------------------------------------------------------------
func stat_level(id: String) -> int:
	return GameState.stat_progress(int(stat_burned.get(id, 0)))["level"]


func stat_room(id: String) -> int:
	return maxi(0, GameState.stat_total_cost() - int(stat_burned.get(id, 0)))


# Burns points into a stat. Returns how many levels were gained.
func burn_into_stat(id: String, amount: int) -> int:
	var before := stat_level(id)
	stat_burned[id] = int(stat_burned.get(id, 0)) + amount
	var after := stat_level(id)
	_apply_stats()
	stats_changed.emit()
	return after - before


func _apply_stats() -> void:
	var new_max := base_max_hp + 15.0 * stat_level("endurance")
	if new_max > max_hp:
		hp += new_max - max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)
	GameState.points_mult = 1.0 + 0.06 * stat_level("fortune")
	hp_changed.emit(hp, max_hp, overshield)


func dmg_mult() -> float:
	return (1.0 + 0.08 * stat_level("strength")) * (1.06 if GameState.has_unlock("damage") else 1.0)


func speed_mult() -> float:
	return 1.0 + 0.04 * stat_level("speed")


func dex_mult() -> float:
	return 1.0 + 0.07 * stat_level("dexterity")


func stamina_duration() -> float:
	return 3.4 * (1.0 + 0.2 * stat_level("stamina"))


func stamina_recover_time() -> float:
	return 2.6 / (1.0 + 0.12 * stat_level("stamina"))


# ---------------------------------------------------------------------------
# TIMERS
# ---------------------------------------------------------------------------
func _update_timers(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	monster_rend_cd = maxf(0.0, monster_rend_cd - delta)
	monster_slam_cd = maxf(0.0, monster_slam_cd - delta)
	human_lunge_cd = maxf(0.0, human_lunge_cd - delta)
	monster_cd = maxf(0.0, monster_cd - delta)
	stim_cd = maxf(0.0, stim_cd - delta)
	tesla_cd = maxf(0.0, tesla_cd - delta)
	pap_cd = maxf(0.0, pap_cd - delta)
	slide_cd = maxf(0.0, slide_cd - delta)
	sprint_out = maxf(0.0, sprint_out - delta)
	grenade_cd = maxf(0.0, grenade_cd - delta)
	_hurt_sfx_cd = maxf(0.0, _hurt_sfx_cd - delta)
	revive_invuln = maxf(0.0, revive_invuln - delta)
	borrowed_cd = maxf(0.0, borrowed_cd - delta)
	borrowed_cd2 = maxf(0.0, borrowed_cd2 - delta)
	if pending_skill_t > 0.0:
		pending_skill_t -= delta
		if pending_skill_t <= 0.0:
			status_banner_requested.emit("KEPT YOUR SKILLS", Color(0.7, 0.7, 0.75))
	if is_downed:
		if self_reviving:
			downed_timer -= delta
			if downed_timer <= 0.0:
				_second_wind_revive()
		else:
			bleedout_timer -= delta
			if bleedout_timer <= 0.0:
				die()
	bloom = maxf(0.0, bloom - delta * 7.0)

	if knife_timer > 0.0:
		knife_timer -= delta
		if knife_timer <= 0.0:
			knife_rig.visible = false

	if grenade_spawn_t > 0.0:
		grenade_spawn_t -= delta
		if grenade_spawn_t <= 0.0:
			_release_grenade()

	if muzzle_flash_timer > 0.0:
		muzzle_flash_timer -= delta
		if muzzle_flash_timer <= 0.0:
			muzzle_light.visible = false
			muzzle_flash.visible = false

	if is_monster_form:
		monster_timer -= delta
		if monster_timer <= 0.0:
			_exit_monster_form()

	if char_id == "alchemist" and pain_drug_charges < pain_drug_max:
		pain_drug_synth_progress += delta
		if pain_drug_synth_progress >= pain_drug_synth_time:
			pain_drug_synth_progress = 0.0
			pain_drug_charges += 1
			status_banner_requested.emit("NOCICEPT-X PAIN DRUG SYNTHESIZED (%d/%d)" % [pain_drug_charges, pain_drug_max], Color(0.16, 0.95, 0.82))

	if stim_timer > 0.0:
		stim_timer = maxf(0.0, stim_timer - delta)
	if pap_timer > 0.0:
		pap_timer = maxf(0.0, pap_timer - delta)
		if pap_timer <= 0.0:
			_emit_ammo()

	# Weapon swap: lower the old gun, then raise the new one
	if swap_state == 1:
		swap_timer -= delta
		if swap_timer <= 0.0:
			active_slot = pending_slot
			_equip_weapon_model(get_current_weapon_id())
			_emit_ammo()
			swap_state = 2
			swap_dur = 0.26 / dex_mult()
			swap_timer = swap_dur
	elif swap_state == 2:
		swap_timer -= delta
		if swap_timer <= 0.0:
			swap_state = 0

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_reload_step()

	# Health regen
	var vit := stat_level("vitality")
	if regen_delay_timer > 0.0:
		regen_delay_timer -= delta
	elif hp < max_hp and not is_downed:
		hp = minf(max_hp, hp + 26.0 * (1.0 + 0.15 * vit) * delta)
		hp_changed.emit(hp, max_hp, overshield)

	if overshield > 0.0 and stim_timer <= 0.0:
		overshield = maxf(0.0, overshield - 6.0 * delta)
		hp_changed.emit(hp, max_hp, overshield)


# ---------------------------------------------------------------------------
# MOVEMENT: walk, stamina sprint, crouch, slide, jump, landing
# ---------------------------------------------------------------------------
func _handle_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	var inp := Vector2.ZERO if _input_blocked() else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	strafe_input = inp.x
	var wish := transform.basis * Vector3(inp.x, 0, inp.y)
	wish.y = 0.0
	wish = wish.normalized() if wish.length_squared() > 0.001 else Vector3.ZERO

	var cfg := get_weapon_cfg(get_current_weapon_id())
	var weapon_mult: float = 1.0 if is_monster_form else float(cfg.get("move_mult", 1.0))
	var walk_speed := base_move_speed * speed_mult() * weapon_mult
	if stim_timer > 0.0:
		walk_speed *= 1.15
	var sprint_speed := walk_speed * 1.5

	# --- Sprint & stamina ---
	var was_sprinting := is_sprinting
	var want_sprint := Input.is_action_pressed("sprint") and inp.y < -0.3 and not Input.is_action_pressed("fire") \
		and not Input.is_action_pressed("aim") and knife_timer <= 0.0 and not is_sliding and not is_monster_form and not is_downed
	if winded and stamina >= 0.35:
		winded = false
	is_sprinting = want_sprint and not winded and stamina > 0.0
	if is_sprinting:
		is_crouching = false
		stamina -= delta / stamina_duration()
		stamina_regen_delay = 0.7
		if stamina <= 0.0:
			stamina = 0.0
			winded = true
			is_sprinting = false
	else:
		stamina_regen_delay -= delta
		if stamina_regen_delay <= 0.0:
			stamina = minf(1.0, stamina + delta / stamina_recover_time())
	if was_sprinting and not is_sprinting:
		sprint_out = 0.16 / dex_mult()

	# --- Crouch toggle / slide ---
	if Input.is_action_just_pressed("crouch") and not is_monster_form and not is_downed:
		if was_sprinting and on_floor and slide_cd <= 0.0:
			_start_slide(wish if wish != Vector3.ZERO else -transform.basis.z, sprint_speed * 1.3)
		elif not is_sliding:
			is_crouching = not is_crouching

	# --- Jump ---
	if on_floor and Input.is_action_just_pressed("jump") and not is_downed:
		if is_crouching and not is_sliding:
			is_crouching = false
		else:
			velocity.y = JUMP_VEL
			vm_vel.y -= 0.32
			cam_spring_vel.y -= 0.25
			if is_sliding:
				is_sliding = false
				slide_cd = 0.45

	if not on_floor:
		velocity.y -= GRAVITY * delta

	if is_sliding:
		slide_timer -= delta
		var t := clampf(slide_timer / SLIDE_TIME, 0.0, 1.0)
		if wish != Vector3.ZERO:
			slide_dir = slide_dir.slerp(wish, clampf(1.2 * delta, 0.0, 1.0)).normalized()
		var spd := lerpf(walk_speed * 0.55, slide_speed, t * t)
		velocity.x = slide_dir.x * spd
		velocity.z = slide_dir.z * spd
		bob_phase += delta * 2.0
		if slide_timer <= 0.0:
			is_sliding = false
			is_crouching = Input.is_action_pressed("crouch")
			slide_cd = 0.45
	else:
		var speed := walk_speed
		if is_monster_form:
			speed = base_move_speed * speed_mult() * 1.45
		elif is_sprinting:
			speed = sprint_speed
		elif is_crouching:
			speed = walk_speed * 0.55
		elif is_ads:
			speed = walk_speed * 0.62
		if is_downed:
			speed = walk_speed * 0.24 # dragging yourself along the ground
		var accel := 13.0 if on_floor else 2.5
		if wish != Vector3.ZERO:
			velocity.x = lerpf(velocity.x, wish.x * speed, clampf(accel * delta, 0.0, 1.0))
			velocity.z = lerpf(velocity.z, wish.z * speed, clampf(accel * delta, 0.0, 1.0))
		elif on_floor:
			velocity.x = move_toward(velocity.x, 0.0, 32.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 32.0 * delta)

	var fall_speed := -velocity.y
	move_and_slide()

	# Landing dip + thud
	var now_floor := is_on_floor()
	if now_floor and not was_on_floor and fall_speed > 3.0:
		land_dip = clampf(fall_speed * 0.012, 0.03, 0.13)
		vm_vel.y -= clampf(fall_speed * 0.07, 0.15, 0.8)
		vm_rot_vel.x -= clampf(fall_speed * 0.25, 0.4, 2.5)
		cam_spring_vel.y -= clampf(fall_speed * 0.09, 0.2, 1.1)
		GameState.play_sfx("player_step_1", -6.0, 0.8)
	was_on_floor = now_floor

	# Footsteps & view bob
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if now_floor and h_speed > 1.0 and not is_sliding:
		bob_phase += delta * h_speed * 1.55
		step_dist += h_speed * delta
		var stride := 2.3 if is_sprinting else 1.75
		if step_dist >= stride:
			step_dist = 0.0
			step_index += 1
			var side := 1.0 if step_index % 2 == 0 else -1.0
			var hard := 1.6 if is_sprinting else (0.6 if is_crouching else 1.0)
			vm_vel.y -= 0.09 * hard
			vm_rot_vel.z += 0.35 * side * hard
			cam_spring_vel.y -= 0.16 * hard
			cam_spring_vel.x += 0.05 * side * hard
			var vol := -13.0 if is_crouching else (-8.0 if is_sprinting else -11.0)
			GameState.play_sfx("player_step_1" if step_index % 2 == 0 else "player_step_2", vol, randf_range(0.9, 1.1))

	# Head height & collision shape for crouch / slide
	var low := is_crouching or is_sliding or is_downed
	var target_h := SLIDE_HEAD if is_sliding else (CROUCH_HEAD if is_crouching else STAND_HEAD)
	if is_downed:
		target_h = 0.42
	head_height = lerpf(head_height, target_h, clampf(12.0 * delta, 0.0, 1.0))
	capsule.height = 1.2 if low else 1.82
	col_shape.position.y = capsule.height * 0.5
	land_dip = lerpf(land_dip, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	head_pivot.position.y = head_height - land_dip

	sprint_t = move_toward(sprint_t, 1.0 if is_sprinting else 0.0, delta * 6.0)

	# Field of view
	var target_fov := base_fov
	if is_monster_form:
		target_fov = 92.0
	elif is_sliding:
		target_fov = base_fov + 8.0
	elif is_sprinting:
		target_fov = base_fov + 6.0
	var ads_fov: float = cfg.get("ads_fov", 60.0)
	target_fov = lerpf(target_fov, ads_fov, _ease_ads())
	camera.fov = lerpf(camera.fov, target_fov, clampf(14.0 * delta, 0.0, 1.0))


func _start_slide(dir: Vector3, speed: float) -> void:
	is_sliding = true
	is_sprinting = false
	is_crouching = false
	slide_timer = SLIDE_TIME
	slide_dir = dir.normalized()
	slide_speed = speed
	GameState.play_sfx("slide", -4.0, randf_range(0.95, 1.05))


func _ease_ads() -> float:
	return ads_t * ads_t * (3.0 - 2.0 * ads_t)


func is_scoped() -> bool:
	return not is_monster_form and bool(get_weapon_cfg(get_current_weapon_id()).get("scoped", false)) and ads_t > 0.92


# ---------------------------------------------------------------------------
# COMBAT INPUT
# ---------------------------------------------------------------------------
func _handle_combat_inputs(delta: float) -> void:
	if _input_blocked():
		return
	if is_downed:
		nearby_station = null
		interact_prompt_changed.emit("")
	else:
		_scan_interactables()
	if is_instance_valid(nearby_station):
		if Input.is_action_just_pressed("interact"):
			nearby_station.try_purchase(self)
			return
		if Input.is_action_pressed("interact") and nearby_station.has_method("interact_hold"):
			nearby_station.interact_hold(self, delta)

	if not is_monster_form:
		if Input.is_action_just_pressed("weapon_1"):
			_begin_swap(0)
		elif Input.is_action_just_pressed("weapon_2"):
			_begin_swap(1)

	# --- MONSTER FORM CONTROLS (Viktor) ---
	if is_monster_form:
		is_ads = false
		ads_t = 0.0
		if Input.is_action_pressed("fire") and monster_rend_cd <= 0.0:
			_perform_monster_rend()
		if (Input.is_action_just_pressed("aim") or Input.is_action_just_pressed("skill_1")) and monster_slam_cd <= 0.0:
			_perform_monster_seismic_slam()
		return

	if Input.is_action_just_pressed("melee") and knife_timer <= 0.0 and swap_state == 0 and not is_downed:
		_do_knife()
	if Input.is_action_just_pressed("grenade") and grenades > 0 and grenade_cd <= 0.0 and knife_timer <= 0.0 and not is_downed:
		_throw_grenade()

	var w_id := get_current_weapon_id()
	var w_cfg := get_weapon_cfg(w_id)

	# --- Aim down sights ---
	is_ads = Input.is_action_pressed("aim") and not is_sprinting and swap_state == 0 and knife_timer <= 0.0 \
		and not (is_reloading and w_cfg["reload_type"] == "mag")
	var ads_speed := dex_mult() / float(w_cfg.get("ads_time", 0.2))
	ads_t = move_toward(ads_t, 1.0 if is_ads else 0.0, delta * ads_speed)

	# --- Fire ---
	var trigger := Input.is_action_pressed("fire") if w_cfg["automatic"] else Input.is_action_just_pressed("fire")
	if not Input.is_action_pressed("fire"):
		_dry_fired = false
	if trigger:
		# Firing interrupts a shell-by-shell reload if there is a round loaded
		if is_reloading and w_cfg["reload_type"] == "shell" and int(mag_ammo[w_id]) > 0:
			is_reloading = false
			_emit_ammo()
		_try_fire_weapon(w_id, w_cfg)

	if Input.is_action_just_pressed("reload"):
		_start_reload()

	if Input.is_action_just_pressed("skill_1") and not is_downed:
		_trigger_skill_q()
	if Input.is_action_just_pressed("skill_2") and not is_downed:
		_trigger_skill_f()
	if pending_skill_t > 0.0:
		if Input.is_action_just_pressed("borrowed_skill"):
			_place_pending_skill(1)
		elif Input.is_action_just_pressed("borrowed_skill_2") and GameState.has_unlock("skill_slot"):
			_place_pending_skill(2)
	elif Input.is_action_just_pressed("borrowed_skill") and not is_downed:
		_use_borrowed_skill(1)
	elif Input.is_action_just_pressed("borrowed_skill_2") and not is_downed:
		_use_borrowed_skill(2)


func _can_shoot() -> bool:
	return not is_sprinting and sprint_out <= 0.0 and swap_state == 0 and knife_timer <= 0.0 and fire_cooldown <= 0.0 and grenade_anim_t < 0.0


func current_spread_deg() -> float:
	var cfg := get_weapon_cfg(get_current_weapon_id())
	var hip: float = cfg["spread_deg"]
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if h_speed > 1.0:
		hip *= 1.45
	if is_crouching:
		hip *= 0.75
	if not is_on_floor():
		hip *= 1.9
	hip += bloom
	return lerpf(hip, float(cfg["ads_spread_deg"]) + bloom * 0.25, _ease_ads())


func _try_fire_weapon(w_id: String, w_cfg: Dictionary) -> void:
	if not _can_shoot() or (is_reloading and w_cfg["reload_type"] == "mag"):
		return

	var cur_mag: int = mag_ammo[w_id]
	if cur_mag <= 0 and pap_timer <= 0.0:
		if reserve_ammo[w_id] > 0:
			_start_reload()
		elif not _dry_fired:
			_dry_fired = true
			GameState.play_sfx("dry_fire", -4.0, 1.0)
		return

	var rate_mult := 1.0 + 0.04 * stat_level("reflexes")
	if stim_timer > 0.0:
		rate_mult *= 1.35
	if pap_timer > 0.0:
		rate_mult *= 1.20

	fire_cooldown = float(w_cfg["fire_rate"]) / rate_mult
	if pap_timer <= 0.0:
		mag_ammo[w_id] = maxi(0, cur_mag - 1)
	_emit_ammo()

	var pitch_s := randf_range(0.95, 1.05)
	if pap_timer > 0.0:
		pitch_s *= 1.2
	elif upgraded.has(w_id):
		pitch_s *= 0.9
	GameState.play_sfx(w_cfg["sfx"], -2.0, pitch_s)
	fire_anim_t = 0.0
	shots_fired += 1
	match w_id:
		"shotgun":
			pump_t = -0.14
			pump_eject = true
		"sniper":
			bolt_t = -0.22
		"revolver", "volt":
			pass
		_:
			_eject_casing(false)

	# Muzzle flash
	var flash_col := Color(1.0, 0.72, 0.30)
	if pap_timer > 0.0 or upgraded.has(w_id):
		flash_col = Color(0.8, 0.4, 1.0)
	if w_cfg["class"] == "wonder":
		flash_col = Color(0.4, 0.8, 1.0)
	muzzle_light.light_color = flash_col
	muzzle_light.visible = true
	muzzle_flash.visible = not is_scoped()
	(muzzle_flash.material_override as StandardMaterial3D).albedo_color = flash_col
	muzzle_flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * (1.6 if w_cfg["class"] in ["shotgun", "sniper", "lmg"] else 1.0)
	muzzle_flash.rotation.z = randf() * TAU
	muzzle_flash_timer = 0.045

	# Recoil: part of the kick stays (aim climbs), part recovers
	var ads_k := lerpf(1.0, 0.6, _ease_ads()) * (0.75 if is_crouching else 1.0)
	var kick := deg_to_rad(float(w_cfg["recoil_pitch"])) * ads_k
	var yaw := deg_to_rad(randf_range(-1.0, 1.0) * float(w_cfg["recoil_yaw"])) * ads_k
	head_pivot.rotation.x = clampf(head_pivot.rotation.x + kick * 0.35, deg_to_rad(-86.0), deg_to_rad(86.0))
	rotate_y(yaw * 0.35)
	recoil_view += Vector2(kick * 0.65, yaw * 0.65)
	recoil_kick.z += 0.03 + kick * 0.6
	recoil_kick.x += kick * 0.9
	vm_rot_vel += Vector3(kick * 14.0, yaw * 8.0, randf_range(-1.0, 1.0) * kick * 10.0)
	vm_vel += Vector3(randf_range(-0.04, 0.04), 0.05, 0.25) * (0.5 + kick * 6.0)

	var spread_deg := current_spread_deg()
	bloom = minf(bloom + float(w_cfg["bloom"]), 4.5)

	var pellets: int = w_cfg["pellets"]
	var base_dmg: float = float(w_cfg["damage"]) * dmg_mult() * (2.2 if pap_timer > 0.0 else 1.0)
	var any_hit := false
	var any_hs := false
	var any_kill := false

	var cam_xf := camera.global_transform
	var cam_origin := cam_xf.origin
	var cam_fwd := -cam_xf.basis.z
	var muzzle_world := gun_rig.to_global(Vector3(0, w_cfg["muzzle"].x, -w_cfg["muzzle"].y))

	for i in range(pellets):
		var ang := randf() * TAU
		var r := sqrt(randf()) * deg_to_rad(spread_deg)
		var dir := (cam_fwd + cam_xf.basis.x * cos(ang) * r + cam_xf.basis.y * sin(ang) * r).normalized()
		var res := _fire_ray(cam_origin, dir, w_cfg, base_dmg, i == 0)
		any_hit = any_hit or res["hit"]
		any_hs = any_hs or res["headshot"]
		any_kill = any_kill or res["killed"]
		if pellets == 1 or i % 2 == 0:
			var t_col := Color(1.0, 0.82, 0.38)
			if pap_timer > 0.0:
				t_col = Color(0.92, 0.28, 1.0)
			elif upgraded.has(w_id):
				t_col = Color(0.62, 0.42, 1.0)
			if w_cfg["class"] == "wonder":
				t_col = Color(0.4, 0.85, 1.0)
			_spawn_bullet_tracer(muzzle_world, res["end"], t_col, 0.03 if w_cfg["class"] == "wonder" else 0.012)

	if any_hit:
		hitmarker_triggered.emit(any_hs, any_kill, false)

	if mag_ammo[w_id] <= 0 and reserve_ammo[w_id] > 0 and pap_timer <= 0.0:
		_start_reload()


# One bullet. Passes through up to `penetration` zombies, losing damage each time.
func _fire_ray(origin: Vector3, dir: Vector3, cfg: Dictionary, dmg: float, give_points: bool) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var max_range: float = cfg["range"]
	var to_pt := origin + dir * max_range
	var exclude: Array[RID] = [get_rid()]
	var pierces_left: int = int(cfg.get("penetration", 0)) + 1
	var from := origin
	var out := {"hit": false, "headshot": false, "killed": false, "end": to_pt}
	var dmg_now := dmg
	while pierces_left > 0:
		var q := PhysicsRayQueryParameters3D.create(from, to_pt, 1 | 4)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var pt: Vector3 = hit["position"]
		out["end"] = pt
		var collider: Object = hit["collider"]
		if collider is ZombieEnemy:
			var z: ZombieEnemy = collider
			var final_dmg := dmg_now
			var head_y := z.head_y()
			if pt.y >= head_y and not z.is_crawler:
				final_dmg *= float(cfg["headshot_mult"])
			var res := z.take_damage(final_dmg, pt, pap_timer > 0.0)
			if res["dealt"] > 0.0:
				out["hit"] = true
				if give_points:
					GameState.add_points(10)
				if res["headshot"]:
					out["headshot"] = true
				if res["killed"]:
					out["killed"] = true
					_on_enemy_killed_by_player(z, res["headshot"])
			if cfg.get("chain", 0) > 0:
				_chain_lightning(z, int(cfg["chain"]), dmg * 0.6)
				break
			exclude.append(z.get_rid())
			pierces_left -= 1
			dmg_now *= 0.72
			from = pt
		else:
			_spawn_impact_spark(pt, false)
			FX.impact(pt, hit["normal"])
			if randf() < 0.12:
				GameState.play_sfx("ricochet", -16.0, randf_range(0.8, 1.3))
			if collider and collider.has_method("on_shot"):
				collider.on_shot(self)
			if cfg.get("chain", 0) > 0:
				_volt_burst(pt, dmg * 0.4)
			break
	return out


# Volt Cannon: arcs from the first target to nearby zombies.
func _chain_lightning(first: ZombieEnemy, jumps: int, dmg: float) -> void:
	var hit_set := {first: true}
	var cur: Node3D = first
	for i in range(jumps):
		var best: ZombieEnemy = null
		var best_d := 7.0
		for node in get_tree().get_nodes_in_group("enemies"):
			var z := node as ZombieEnemy
			if z and not z.is_dead and not hit_set.has(z):
				var d := z.global_position.distance_to(cur.global_position)
				if d < best_d:
					best_d = d
					best = z
		if best == null:
			break
		hit_set[best] = true
		var a := cur.global_position + Vector3(0, 1.2, 0)
		var b := best.global_position + Vector3(0, 1.2, 0)
		_spawn_bullet_tracer(a, b, Color(0.45, 0.85, 1.0), 0.025)
		var res := best.take_damage(dmg, b, true, "electric")
		best.apply_stun(1.2)
		if res["killed"]:
			_on_enemy_killed_by_player(best, false)
		cur = best
		dmg *= 0.85
	_spawn_aoe_ring(first.global_position, 2.5, Color(0.4, 0.85, 1.0))


func _volt_burst(pt: Vector3, dmg: float) -> void:
	_spawn_aoe_ring(pt, 3.0, Color(0.4, 0.85, 1.0))
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z and not z.is_dead and z.global_position.distance_to(pt) < 3.2:
			var res := z.take_damage(dmg, z.global_position + Vector3(0, 1.0, 0), true, "electric")
			if res["killed"]:
				_on_enemy_killed_by_player(z, false)


# ---------------------------------------------------------------------------
# RELOAD & SWAP
# ---------------------------------------------------------------------------
func _start_reload() -> void:
	if is_reloading or is_monster_form or swap_state != 0:
		return
	var w_id := get_current_weapon_id()
	var w_cfg := get_weapon_cfg(w_id)
	if mag_ammo[w_id] >= w_cfg["mag_size"] or reserve_ammo[w_id] <= 0:
		return
	is_reloading = true
	is_ads = false
	reload_was_empty = int(mag_ammo[w_id]) == 0
	_mag_out_played = false
	_mag_in_played = false
	_bolt_rel_played = false
	var speed := dex_mult() * (1.35 if stim_timer > 0.0 else 1.0)
	if w_cfg["reload_type"] == "shell":
		reload_total = 0.3 / speed # bring the gun up to the loading port
	else:
		var empty_mult := 1.18 if int(mag_ammo[w_id]) == 0 else 1.0
		reload_total = float(w_cfg["reload_time"]) * empty_mult / speed
		GameState.play_sfx("reload", -2.0, clampf(speed, 0.8, 1.6))
	reload_timer = reload_total
	_emit_ammo()


func _reload_step() -> void:
	var w_id := get_current_weapon_id()
	var w_cfg := get_weapon_cfg(w_id)
	if w_cfg["reload_type"] == "shell":
		if int(mag_ammo[w_id]) < int(w_cfg["mag_size"]) and int(reserve_ammo[w_id]) > 0:
			mag_ammo[w_id] += 1
			reserve_ammo[w_id] -= 1
			GameState.play_sfx("shell_insert", -3.0, randf_range(0.95, 1.05))
			recoil_kick.z -= 0.03
		if int(mag_ammo[w_id]) >= int(w_cfg["mag_size"]) or int(reserve_ammo[w_id]) <= 0:
			is_reloading = false
			if reload_was_empty:
				pump_t = 0.0
				pump_eject = false
		else:
			var speed := dex_mult() * (1.35 if stim_timer > 0.0 else 1.0)
			reload_total = float(w_cfg["reload_time"]) / speed
			reload_timer = reload_total
		_emit_ammo()
		return
	is_reloading = false
	var needed: int = int(w_cfg["mag_size"]) - int(mag_ammo[w_id])
	var take: int = mini(needed, int(reserve_ammo[w_id]))
	mag_ammo[w_id] += take
	reserve_ammo[w_id] -= take
	_emit_ammo()


func _begin_swap(new_slot: int) -> void:
	if new_slot == active_slot or new_slot < 0 or new_slot >= weapons_owned.size() or swap_state != 0:
		return
	pending_slot = new_slot
	swap_state = 1
	swap_dur = 0.16 / dex_mult()
	swap_timer = swap_dur
	is_reloading = false
	is_ads = false
	GameState.play_sfx("weapon_swap", -5.0, 1.0)


# ---------------------------------------------------------------------------
# KNIFE & GRENADES
# ---------------------------------------------------------------------------
func _do_knife() -> void:
	knife_timer = 0.5 / dex_mult()
	is_reloading = false
	is_ads = false
	GameState.play_sfx("knife_swing", -2.0, randf_range(0.95, 1.1))

	knife_rig.visible = true
	knife_rig.position = Vector3(0.35, -0.2, -0.3)
	knife_rig.rotation = Vector3(deg_to_rad(-10), deg_to_rad(40), deg_to_rad(-70))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(knife_rig, "position", Vector3(-0.2, -0.16, -0.42), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(knife_rig, "rotation", Vector3(deg_to_rad(-20), deg_to_rad(-30), deg_to_rad(-100)), 0.16)

	var target := _find_single_melee_target(2.6, 0.55)
	if target == null:
		# Lunge at a zombie a bit further away, like a classic knife lunge
		target = _find_single_melee_target(4.2, 0.8)
		if target:
			var to_t := target.global_position - global_position
			to_t.y = 0.0
			var d := to_t.normalized() * 10.0
			velocity.x = d.x
			velocity.z = d.z
	if target:
		var hit_pt := target.global_position + Vector3(0, 1.2 * target.model_scale, 0)
		var res := target.take_damage(KNIFE_DAMAGE * dmg_mult(), hit_pt, false, "melee")
		GameState.play_sfx("knife_hit", -1.0, randf_range(0.9, 1.1))
		add_camera_shake(0.12)
		if res["dealt"] > 0.0:
			GameState.add_points(10)
		if res["killed"]:
			GameState.add_points(70) # knife kill bonus
			_on_enemy_killed_by_player(target, false)
		hitmarker_triggered.emit(false, res["killed"], false)


func _throw_grenade() -> void:
	grenades -= 1
	grenade_cd = 0.7
	GameState.play_sfx("grenade_pin", -3.0, 1.0)
	grenade_anim_t = 0.0
	grenade_spawn_t = 0.2
	is_reloading = false


func _release_grenade() -> void:
	var g: RigidBody3D = FragGrenadeScript.new()
	g.thrower = self
	get_tree().current_scene.add_child(g)
	var fwd := -camera.global_transform.basis.z
	g.global_position = camera.global_position + fwd * 0.5 + camera.global_transform.basis.x * 0.15
	g.linear_velocity = fwd * 15.0 + Vector3.UP * 3.5 + Vector3(velocity.x, 0, velocity.z) * 0.5
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	recoil_kick.z += 0.05


func add_grenades(n: int) -> void:
	grenades = mini(MAX_GRENADES, grenades + n)


# ---------------------------------------------------------------------------
# HERO SKILLS
# ---------------------------------------------------------------------------
func _trigger_skill_q() -> void:
	match char_id:
		"ravager":
			if human_lunge_cd <= 0.0:
				human_lunge_cd = 6.5
				_perform_human_feral_slash()
		"alchemist":
			_fire_pain_drug_dart()
		"warden":
			if tesla_cd <= 0.0:
				tesla_cd = tesla_cd_max
				_fire_tesla_charge()


func _trigger_skill_f() -> void:
	match char_id:
		"ravager":
			if not is_monster_form and monster_cd <= 0.0:
				_enter_monster_form()
		"alchemist":
			if stim_cd <= 0.0:
				stim_cd = stim_cd_max
				stim_timer = 10.0
				hp = max_hp
				overshield = 50.0
				pain_drug_charges = mini(pain_drug_max, pain_drug_charges + 1)
				hp_changed.emit(hp, max_hp, overshield)
				GameState.play_sfx("pain_drug", 0.0, 1.25)
				status_banner_requested.emit("ADRENALINE STIM ACTIVE! FULL HP +50 SHIELD & +1 PAIN DRUG!", Color(0.16, 0.96, 0.80))
		"warden":
			if pap_cd <= 0.0:
				pap_cd = pap_cd_max
				pap_timer = 12.0
				is_reloading = false
				var w_id := get_current_weapon_id()
				mag_ammo[w_id] = get_weapon_cfg(w_id)["mag_size"]
				_emit_ammo()
				GameState.play_sfx("buy_ching", 0.0, 0.85)
				status_banner_requested.emit("ARC OVERCHARGE! 2.2x PLASMA DMG & INFINITE CLIP (12s)!", Color(0.92, 0.38, 1.0))


# --- VIKTOR: MONSTER TRANSFORMATION & 2 MONSTER SKILLS ---
func _enter_monster_form() -> void:
	is_monster_form = true
	is_reloading = false
	is_ads = false
	is_sliding = false
	is_crouching = false
	monster_timer = monster_duration
	monster_cd = monster_cd_max
	gun_rig.visible = false
	knife_rig.visible = false
	monster_claw_rig.visible = true
	add_camera_shake(0.35)
	GameState.play_sfx("monster_roar", 1.5, 0.95)
	status_banner_requested.emit("RAVAGER MONSTER UNLEASHED! [LMB] 1-TARGET 480 DMG | [RMB / Q] AOE + 4s STUN!", Color(1.0, 0.25, 0.14))


func _exit_monster_form() -> void:
	is_monster_form = false
	monster_claw_rig.visible = false
	gun_rig.visible = true
	status_banner_requested.emit("HUMAN FORM RESTORED — KILL ZOMBIES TO RECHARGE BEAST BLOOD", Color(0.85, 0.65, 0.55))


func _perform_monster_rend() -> void:
	monster_rend_cd = 0.52
	GameState.play_sfx("monster_rend", 0.5, randf_range(0.92, 1.08))

	if claw_arm_l and claw_arm_r:
		var use_right := (int(Time.get_ticks_msec() / 100) % 2 == 0)
		var arm := claw_arm_r if use_right else claw_arm_l
		var tw := create_tween()
		tw.tween_property(arm, "position:z", -0.34, 0.09)
		tw.parallel().tween_property(arm, "rotation:x", deg_to_rad(-32.0), 0.09)
		tw.tween_property(arm, "position:z", 0.0, 0.18)
		tw.parallel().tween_property(arm, "rotation:x", 0.0, 0.18)

	var fwd := -transform.basis.z
	velocity.x += fwd.x * 5.2
	velocity.z += fwd.z * 5.2

	var best_enemy: ZombieEnemy = _find_single_melee_target(5.0, 0.42)
	if best_enemy:
		var hit_pt := best_enemy.global_position + Vector3(0, 1.25, 0)
		var res := best_enemy.take_damage(480.0 * dmg_mult(), hit_pt, true, "melee")
		_spawn_slash_burst(hit_pt, Color(1.0, 0.16, 0.10))
		hp = minf(max_hp, hp + 12.0)
		hp_changed.emit(hp, max_hp, overshield)
		GameState.add_points(20)
		if res["killed"]:
			_on_enemy_killed_by_player(best_enemy, false)
		hitmarker_triggered.emit(true, res["killed"], true)


func _perform_monster_seismic_slam() -> void:
	monster_slam_cd = monster_slam_cd_max
	GameState.play_sfx("monster_slam", 1.5, 1.0)
	add_camera_shake(0.50)

	if claw_arm_l and claw_arm_r:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(claw_arm_l, "rotation:x", deg_to_rad(-48.0), 0.12)
		tw.tween_property(claw_arm_r, "rotation:x", deg_to_rad(-48.0), 0.12)
		tw.chain().set_parallel(true)
		tw.tween_property(claw_arm_l, "rotation:x", 0.0, 0.25)
		tw.tween_property(claw_arm_r, "rotation:x", 0.0, 0.25)

	_spawn_aoe_ring(global_position, 8.0, Color(1.0, 0.65, 0.12))

	var stunned_count := 0
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z_node := node as ZombieEnemy
		if z_node and not z_node.is_dead:
			var d := global_position.distance_to(z_node.global_position)
			if d <= 8.0:
				var res: Dictionary = z_node.take_damage(35.0 * dmg_mult(), z_node.global_position + Vector3(0, 1.0, 0), true)
				z_node.apply_stun(4.0)
				stunned_count += 1
				if res["killed"]:
					any_kill = true
					_on_enemy_killed_by_player(z_node, false)

	if stunned_count > 0:
		GameState.add_points(stunned_count * 15)
		hitmarker_triggered.emit(false, any_kill, true)
		status_banner_requested.emit("SEISMIC SLAM! %d TARGETS STUNNED FOR 4.0 SECONDS!" % stunned_count, Color(1.0, 0.78, 0.18))


func _perform_human_feral_slash() -> void:
	GameState.play_sfx("monster_rend", -1.0, 1.15)
	recoil_kick.z -= 0.12
	var target := _find_single_melee_target(4.2, 0.45)
	if target:
		var res := target.take_damage(175.0 * dmg_mult(), target.global_position + Vector3(0, 1.2, 0), true)
		monster_cd = maxf(0.0, monster_cd - 4.0)
		_spawn_slash_burst(target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.25, 0.15))
		if res["killed"]:
			_on_enemy_killed_by_player(target, false)
		hitmarker_triggered.emit(true, res["killed"], true)


func _find_single_melee_target(max_dist: float, min_dot: float) -> ZombieEnemy:
	var cam_pos := camera.global_position
	var cam_fwd := -camera.global_transform.basis.z
	var best: ZombieEnemy = null
	var best_score := -999.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var z_node := node as ZombieEnemy
		if z_node and not z_node.is_dead:
			var center: Vector3 = z_node.global_position + Vector3(0, 1.1 * z_node.model_scale, 0)
			var to_e := center - cam_pos
			var dist := to_e.length()
			if dist <= max_dist:
				var d_dot := cam_fwd.dot(to_e.normalized())
				if d_dot >= min_dot:
					var score := d_dot * 4.0 - dist * 0.35 + (0.6 if z_node.is_boss else 0.0)
					if score > best_score:
						best_score = score
						best = z_node
	return best


# --- DR. ELENA VANCE: PAIN DRUG DART FOR ROUND BOSSES ---
func _fire_pain_drug_dart() -> void:
	if pain_drug_charges <= 0:
		status_banner_requested.emit("SYNTHESIZING PAIN DRUG... (%ds)" % ceili(pain_drug_synth_time - pain_drug_synth_progress), Color(0.95, 0.45, 0.35))
		return

	pain_drug_charges -= 1
	GameState.play_sfx("pain_drug", 0.5, 1.0)
	recoil_kick.z += 0.06

	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var end_pt := origin + fwd * 52.0

	var hit_boss: ZombieEnemy = null
	var best_dot := 0.94
	for node in get_tree().get_nodes_in_group("enemies"):
		var z_node := node as ZombieEnemy
		if z_node and not z_node.is_dead and z_node.is_boss:
			var b_center: Vector3 = z_node.global_position + Vector3(0, 1.35 * z_node.model_scale, 0)
			var to_b := b_center - origin
			if to_b.length() <= 52.0:
				var d := fwd.dot(to_b.normalized())
				if d > best_dot:
					best_dot = d
					hit_boss = z_node

	if hit_boss:
		end_pt = hit_boss.global_position + Vector3(0, 1.35 * hit_boss.model_scale, 0)
		hit_boss.apply_pain_drug(12.0)
		hit_boss.take_damage(85.0, end_pt, true)
		_spawn_aoe_ring(hit_boss.global_position, 3.2, Color(0.14, 0.98, 0.82))
		hitmarker_triggered.emit(true, false, true)
		GameState.add_points(75)
		status_banner_requested.emit(
			"PAIN DRUG GIVEN TO %s! (-55%% ATK | -45%% SPD | +60%% VULN - 12s)" % hit_boss.display_name,
			Color(0.15, 0.98, 0.82)
		)
	else:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(origin, end_pt, 1 | 4)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			end_pt = hit["position"]
			_spawn_aoe_ring(end_pt, 4.2, Color(0.14, 0.98, 0.82))
			var affected := 0
			for node in get_tree().get_nodes_in_group("enemies"):
				var z_node := node as ZombieEnemy
				if z_node and not z_node.is_dead:
					if z_node.global_position.distance_to(end_pt) <= 4.5:
						z_node.apply_pain_drug(12.0 if z_node.is_boss else 7.5)
						z_node.take_damage(65.0, end_pt, true)
						affected += 1
			if affected > 0:
				hitmarker_triggered.emit(false, false, true)
				status_banner_requested.emit("NOCICEPT-X SEDATIVE CLOUD HIT %d TARGETS!" % affected, Color(0.15, 0.98, 0.82))

	_spawn_bullet_tracer(gun_rig.global_position, end_pt, Color(0.14, 1.0, 0.82), 0.014)


# --- SGT. MARCUS COLE: TESLA CONCUSSION CHARGE ---
func _fire_tesla_charge() -> void:
	GameState.play_sfx("monster_slam", -1.0, 1.45)
	var origin := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 36.0, 1 | 4)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var blast_pt := origin + fwd * 14.0
	if not hit.is_empty():
		blast_pt = hit["position"]

	_spawn_bullet_tracer(gun_rig.global_position, blast_pt, Color(0.35, 0.82, 1.0), 0.02)
	_spawn_aoe_ring(blast_pt, 6.0, Color(0.35, 0.82, 1.0))

	var hit_cnt := 0
	var any_kill := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var z_node := node as ZombieEnemy
		if z_node and not z_node.is_dead:
			if z_node.global_position.distance_to(blast_pt) <= 6.2:
				var res: Dictionary = z_node.take_damage(150.0 * dmg_mult(), z_node.global_position + Vector3(0, 1.1, 0), true, "electric")
				z_node.apply_stun(2.5)
				hit_cnt += 1
				if res["killed"]:
					any_kill = true
					_on_enemy_killed_by_player(z_node, false)
	if hit_cnt > 0:
		hitmarker_triggered.emit(false, any_kill, true)
		status_banner_requested.emit("TESLA ARC SHOCKED %d HOSTILES!" % hit_cnt, Color(0.42, 0.85, 1.0))


# ---------------------------------------------------------------------------
# DAMAGE, REWARDS & LOADOUT
# ---------------------------------------------------------------------------
func _on_enemy_killed_by_player(z: ZombieEnemy, was_headshot: bool) -> void:
	var pts := z.point_reward + (40 if was_headshot else 0)
	GameState.add_points(pts)
	GameState.total_kills += 1
	if was_headshot:
		GameState.headshots += 1
		GameState.play_sfx("headshot_ding", -2.5, randf_range(0.96, 1.05))
	if char_id == "ravager" and not is_monster_form:
		monster_cd = maxf(0.0, monster_cd - 1.8)
	elif char_id == "alchemist" and pain_drug_charges < pain_drug_max:
		pain_drug_synth_progress += 1.6


func take_damage(amount: float, _from_pos: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_downed or revive_invuln > 0.0:
		return
	var dmg := amount * (1.0 - 0.025 * stat_level("endurance"))
	if is_monster_form:
		dmg *= 0.60
	if stim_timer > 0.0:
		dmg *= 0.65

	regen_delay_timer = maxf(1.6, 3.8 - 0.22 * stat_level("vitality"))
	add_camera_shake(0.22)
	hurt_roll = randf_range(-1.0, 1.0) * deg_to_rad(4.0)
	damaged.emit(_from_pos)
	if _hurt_sfx_cd <= 0.0:
		_hurt_sfx_cd = 0.6
		GameState.play_sfx("player_hurt", -3.0, randf_range(0.9, 1.1))

	if overshield > 0.0:
		var absorbed := minf(overshield, dmg)
		overshield -= absorbed
		dmg -= absorbed

	hp = maxf(0.0, hp - dmg)
	hp_changed.emit(hp, max_hp, overshield)

	if hp <= 0.0:
		if revives > 0:
			_go_down(true)
		elif Net.is_online() and _net_game() and _net_game().any_teammate_standing():
			_go_down(false)
		else:
			die()


# Climb the ladder into the chopper and ride out with it.
func extract_to(heli: Node3D) -> void:
	extracted = true
	revive_invuln = 9999.0
	is_ads = false
	is_downed = false
	gun_rig.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_extract_node = heli
	var dest := heli.global_position + Vector3(0, 0.6, 0) if heli else global_position + Vector3(0, 4.0, 0)
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(head_pivot, "rotation:x", deg_to_rad(-25.0), 2.0)
	tw.tween_callback(func():
		if is_instance_valid(heli):
			heli.set_meta("riding", true)
	)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_downed = false
	self_reviving = false
	_head_rest_y = head_pivot.position.y
	var ng := _net_game()
	if Net.is_online() and ng and not ng.game_over:
		collision_layer = 0 # spectating: zombies and bullets ignore the body
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_death_camera()
	player_died.emit()


func _go_down(self_revive: bool = true) -> void:
	if self_revive:
		revives -= 1
	self_reviving = self_revive
	is_downed = true
	downed_timer = DOWNED_TIME
	bleedout_timer = BLEEDOUT_TIME
	if is_monster_form:
		_exit_monster_form()
	is_sprinting = false
	is_sliding = false
	is_crouching = false
	hp = 0.0
	add_camera_shake(0.5)
	hurt_roll = deg_to_rad(18.0)
	GameState.play_sfx("player_downed", 0.0, 1.0)
	if self_revive:
		status_banner_requested.emit("DOWNED! HOLD ON — SECOND WIND IN %ds" % int(DOWNED_TIME), Color(1.0, 0.3, 0.25))
	else:
		status_banner_requested.emit("DOWNED! KEEP SHOOTING — A TEAMMATE CAN REVIVE YOU", Color(1.0, 0.3, 0.25))
	downed_changed.emit(true)
	hp_changed.emit(hp, max_hp, overshield)


func _second_wind_revive() -> void:
	is_downed = false
	self_reviving = false
	hp = max_hp * 0.6
	revive_invuln = 2.5
	regen_delay_timer = 0.0
	GameState.play_sfx("second_wind", 0.0, 1.0)
	# A shockwave throws back and stuns everything close by
	for node in get_tree().get_nodes_in_group("enemies"):
		var z := node as ZombieEnemy
		if z == null or z.is_dead:
			continue
		var off := z.global_position - global_position
		off.y = 0.0
		if off.length() < 5.5:
			if not z.is_boss:
				z.apply_stun(1.6)
			z.velocity += off.normalized() * (7.0 if not z.is_boss else 2.0)
	_spawn_aoe_ring(global_position, 5.5, Color(0.35, 1.0, 0.6))
	add_camera_shake(0.4)
	status_banner_requested.emit("SECOND WIND! BACK ON YOUR FEET", Color(0.35, 1.0, 0.6))
	downed_changed.emit(false)
	hp_changed.emit(hp, max_hp, overshield)
	stats_changed.emit()


func grant_or_refill_weapon(w_id: String) -> void:
	if weapons_owned.has(w_id):
		var cfg := get_weapon_cfg(w_id)
		mag_ammo[w_id] = cfg["mag_size"]
		reserve_ammo[w_id] = cfg["reserve_max"]
		active_slot = weapons_owned.find(w_id)
	else:
		if weapons_owned.size() < 2:
			weapons_owned.append(w_id)
			active_slot = weapons_owned.size() - 1
		else:
			upgraded.erase(weapons_owned[active_slot])
			weapons_owned[active_slot] = w_id
		var cfg2 := get_weapon_cfg(w_id)
		mag_ammo[w_id] = cfg2["mag_size"]
		reserve_ammo[w_id] = cfg2["reserve_max"]
	is_reloading = false
	swap_state = 2
	swap_dur = 0.3 / dex_mult()
	swap_timer = swap_dur
	_equip_weapon_model(get_current_weapon_id())
	_emit_ammo()


func refill_all_ammo() -> void:
	for w_id in weapons_owned:
		var cfg := get_weapon_cfg(w_id)
		mag_ammo[w_id] = cfg["mag_size"]
		reserve_ammo[w_id] = cfg["reserve_max"]
	is_reloading = false
	grenades = MAX_GRENADES
	_emit_ammo()
	status_banner_requested.emit("MAX AMMO! ALL WEAPONS & GRENADES REFILLED!", Color(1.0, 0.85, 0.25))


# Returns the weapon's stats with any forge upgrade applied.
func get_weapon_cfg(w_id: String) -> Dictionary:
	var base: Dictionary = GameState.WEAPONS[w_id]
	if not upgraded.has(w_id):
		return base
	var cfg := base.duplicate()
	cfg["name"] = "%s  MK-II" % base["name"]
	cfg["damage"] = float(base["damage"]) * 2.1
	cfg["mag_size"] = int(ceil(float(base["mag_size"]) * 1.5))
	cfg["reserve_max"] = int(base["reserve_max"]) * 2
	cfg["reload_time"] = float(base["reload_time"]) * 0.85
	cfg["penetration"] = int(base.get("penetration", 0)) + 1
	return cfg


func can_upgrade_weapon() -> bool:
	return not is_monster_form and not upgraded.has(get_current_weapon_id())


func upgrade_current_weapon() -> void:
	var w_id := get_current_weapon_id()
	upgraded[w_id] = true
	var cfg := get_weapon_cfg(w_id)
	mag_ammo[w_id] = cfg["mag_size"]
	reserve_ammo[w_id] = cfg["reserve_max"]
	is_reloading = false
	_equip_weapon_model(w_id)
	_emit_ammo()
	add_camera_shake(0.25)
	status_banner_requested.emit("FORGED: %s! 2.1x DAMAGE, BIGGER MAGS, EXTRA PIERCE" % cfg["name"], Color(0.78, 0.45, 1.0))


func get_current_weapon_id() -> String:
	return weapons_owned[clampi(active_slot, 0, weapons_owned.size() - 1)]


func _equip_weapon_model(w_id: String) -> void:
	if is_instance_valid(gun_model):
		gun_rig.remove_child(gun_model)
		gun_model.queue_free()
		gun_model = null
	var cfg := get_weapon_cfg(w_id)
	var path: String = cfg["model"]
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		gun_model = packed.instantiate()
		gun_rig.add_child(gun_model)
		vm_parts.clear()
		for pn in VM_PARTS:
			var n := gun_model.find_child(pn, true, false) as Node3D
			if n:
				vm_parts[pn] = {"node": n, "pos": n.position, "rot": n.rotation}
		_mark_viewmodel(gun_model)
		if upgraded.has(w_id):
			var sheen := MaterialLib.get_emissive(Color(0.55, 0.25, 1.0), 1.6, 0.28)
			for m in gun_model.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).material_overlay = sheen
	var muzzle: Vector2 = cfg["muzzle"]
	muzzle_flash.position = Vector3(0, muzzle.x, -muzzle.y - 0.04)
	muzzle_light.position = muzzle_flash.position
	bloom = 0.0


func _emit_ammo() -> void:
	var w_id := get_current_weapon_id()
	var cfg := get_weapon_cfg(w_id)
	ammo_changed.emit(cfg["name"], mag_ammo[w_id], reserve_ammo[w_id], is_reloading, pap_timer > 0.0)


func _scan_interactables() -> void:
	var found: Node = null
	var best_d := 99.0
	for st in get_tree().get_nodes_in_group("wall_stations"):
		var st_node := st as Node3D
		if st_node == null or not st_node.is_inside_tree():
			continue
		var radius: float = st_node.get("interact_radius") if "interact_radius" in st_node else 3.1
		var d := global_position.distance_to(st_node.global_position)
		if d < radius and d < best_d:
			# Skip things with nothing to offer right now (e.g. a fully boarded window)
			if st_node.has_method("get_prompt") and st_node.get_prompt(self) == "":
				continue
			best_d = d
			found = st_node
	nearby_station = found
	if nearby_station and nearby_station.has_method("get_prompt"):
		interact_prompt_changed.emit(nearby_station.get_prompt(self))
	else:
		interact_prompt_changed.emit("")


# ---------------------------------------------------------------------------
# VIEWMODEL & CAMERA ANIMATION
# ---------------------------------------------------------------------------
func _animate_viewmodels(delta: float) -> void:
	var cfg := get_weapon_cfg(get_current_weapon_id())
	var ads_e := _ease_ads()
	_vm_time += delta
	recoil_kick = recoil_kick.lerp(Vector3.ZERO, clampf(14.0 * delta, 0.0, 1.0))
	# View recoil springs back with a slight overshoot
	recoil_view_vel += (-recoil_view * 95.0 - recoil_view_vel * 12.5) * delta
	recoil_view += recoil_view_vel * delta

	var move_amt := clampf(Vector2(velocity.x, velocity.z).length() / 6.0, 0.0, 1.4) if is_on_floor() and not is_sliding else 0.0
	var bob_amp := (1.0 - ads_e * 0.85) * move_amt
	var bob_x := cos(bob_phase * 0.5) * 0.014 * bob_amp
	var bob_y := absf(sin(bob_phase)) * 0.018 * bob_amp

	var ads_pos: Vector3 = cfg.get("ads_pos", Vector3(0, -0.075, -0.32))
	var target_pos := HIP_POS.lerp(ads_pos, ads_e) + Vector3(bob_x, -bob_y, 0.0)
	var target_rot := Vector3.ZERO

	# Sprint pose: gun swung low and to the side
	target_pos += Vector3(-0.05, -0.05, 0.05) * sprint_t
	target_rot += Vector3(-0.32, 0.75, 0.32) * sprint_t

	# Sliding tilt
	if is_sliding:
		target_rot.z += 0.25

	# Reload: dip and roll the gun
	if is_reloading:
		var p := 1.0 - clampf(reload_timer / maxf(0.01, reload_total), 0.0, 1.0)
		var dip := sin(p * PI)
		if cfg["reload_type"] == "shell":
			dip = 0.6
		target_pos += Vector3(0.03, -0.12, 0.05) * dip
		target_rot += Vector3(-0.35, 0.15, 0.55) * dip

	# Swap & knife: lower the gun out of view
	var lower := 0.0
	if swap_state == 1:
		lower = 1.0 - swap_timer / maxf(0.01, swap_dur)
	elif swap_state == 2:
		lower = swap_timer / maxf(0.01, swap_dur)
	if knife_timer > 0.0:
		lower = maxf(lower, 0.85)
	target_pos += Vector3(0, -0.3, 0.05) * lower
	target_rot += Vector3(-0.9, 0, 0) * lower

	sway = sway.lerp(Vector2.ZERO, clampf(9.0 * delta, 0.0, 1.0)).limit_length(0.12)
	var sway_scale := 0.3 if ads_e > 0.5 else 1.0
	target_pos += Vector3(-sway.x, sway.y, 0.0) * 0.25 * sway_scale
	target_rot += Vector3(sway.y, -sway.x * 1.2, -sway.x * 0.8) * sway_scale

	if grenade_anim_t >= 0.0:
		lower = maxf(lower, 0.9)
		target_pos += Vector3(0, -0.3 * 0.9, 0)

	# Breathing drift and strafe tilt
	var breathe := 1.0 - ads_e * 0.65
	target_pos += Vector3(sin(_vm_time * 0.9) * 0.0016, sin(_vm_time * 1.8) * 0.0022, 0.0) * breathe
	target_rot.z += -strafe_input * 0.07 * (1.0 - ads_e * 0.7)

	_animate_gun_parts(delta, cfg)
	_animate_grenade_hand(delta)
	# Weapon rides on a slightly under-damped spring: inertia, overshoot, settle
	var k_spring := lerpf(240.0, 420.0, ads_e)
	var d_spring := 2.0 * sqrt(k_spring) * 0.74
	var want_pos := target_pos + Vector3(0, 0, recoil_kick.z)
	var want_rot := target_rot + Vector3(recoil_kick.x, 0, 0)
	vm_vel += ((want_pos - gun_rig.position) * k_spring - vm_vel * d_spring) * delta
	gun_rig.position += vm_vel * delta
	vm_rot_vel += ((want_rot - gun_rig.rotation) * k_spring - vm_rot_vel * d_spring) * delta
	gun_rig.rotation += vm_rot_vel * delta
	gun_rig.visible = not is_monster_form and not is_scoped()

	if is_monster_form:
		monster_claw_rig.position = Vector3(bob_x * 1.4, -0.18 - bob_y * 1.2, -0.36)

	# Camera: recoil, strafe lean, hurt roll, head bob, shake
	hurt_roll = lerpf(hurt_roll, 0.0, clampf(7.0 * delta, 0.0, 1.0))
	var lean := -strafe_input * deg_to_rad(1.2) + (deg_to_rad(-4.0) if is_sliding else 0.0)
	# Aim sway while looking down sights (stronger through a scope)
	var aim_sway := ads_e * (2.6 if is_scoped() else 1.0) * (0.6 if is_crouching else 1.0)
	var sway_x := (sin(_vm_time * 1.1) * 0.0011 + sin(_vm_time * 2.3) * 0.0004) * aim_sway
	var sway_y := sin(_vm_time * 0.7 + 1.3) * 0.0012 * aim_sway
	camera.rotation = Vector3(recoil_view.x + sway_x, recoil_view.y + sway_y, lerpf(camera.rotation.z, lean + hurt_roll + cam_spring.x * 0.5, clampf(10.0 * delta, 0.0, 1.0)))
	var cam_bob := Vector3(cos(bob_phase * 0.5) * 0.02, absf(sin(bob_phase)) * 0.025, 0.0) * move_amt * (1.0 - ads_e)

	if camera_shake > 0.0:
		camera_shake = maxf(0.0, camera_shake - delta * 1.8)
		cam_bob += Vector3(randf_range(-0.06, 0.06), randf_range(-0.06, 0.06), 0.0) * camera_shake
	# Footfalls and landings jolt the head on a spring
	cam_spring_vel += (-cam_spring * 150.0 - cam_spring_vel * 15.0) * delta
	cam_spring += cam_spring_vel * delta
	camera.position = cam_bob + Vector3(cam_spring.x * 0.3, cam_spring.y * 0.35, 0.0)


func _mark_viewmodel(n: Node) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | VIEWMODEL_LAYER


func _eject_casing(is_shell: bool) -> void:
	if not is_instance_valid(gun_rig) or not gun_rig.visible:
		return
	var origin := gun_rig.to_global(Vector3(0.035, 0.045, -0.06))
	FX.casing(origin, gun_rig.global_basis.x, gun_rig.global_basis.y, is_shell)


func _part(name: String) -> Dictionary:
	return vm_parts.get(name, {})


func _set_part(name: String, pos_off: Vector3, rot_off: Vector3) -> void:
	var d: Dictionary = vm_parts.get(name, {})
	if d.is_empty() or not is_instance_valid(d["node"]):
		return
	var n: Node3D = d["node"]
	n.position = d["pos"] + pos_off
	n.rotation = d["rot"] + rot_off


# Slides, bolts, pumps, cylinders, magazines and the left hand.
func _animate_gun_parts(delta: float, cfg: Dictionary) -> void:
	if vm_parts.is_empty():
		return
	var w_id := get_current_weapon_id()
	fire_anim_t += delta
	var k_fire := clampf(1.0 - fire_anim_t / 0.075, 0.0, 1.0)
	var empty := int(mag_ammo[w_id]) <= 0 and pap_timer <= 0.0

	var slide_off := Vector3(0, 0, 0.032 * k_fire)
	var bolt_off := Vector3(0, 0, 0.03 * k_fire)
	var bolt_rot := Vector3.ZERO
	var mag_off := Vector3.ZERO
	var arm_l_off := Vector3.ZERO
	var arm_l_rot := Vector3.ZERO
	var pump_off := Vector3.ZERO
	var cyl_off := Vector3.ZERO
	var cover_rot := Vector3.ZERO
	var hammer_rot := Vector3(0.6 * clampf(1.0 - fire_anim_t / 0.25, 0.0, 1.0), 0, 0)

	if empty and not is_reloading and w_id == "pistol":
		slide_off.z = 0.032 # slide locks back on an empty pistol

	# Pump-action cycle
	var prev_pump := pump_t
	pump_t += delta
	if pump_t >= 0.0 and pump_t <= 0.36:
		pump_off.z = 0.085 * sin(pump_t / 0.36 * PI)
	if prev_pump < 0.0 and pump_t >= 0.0:
		GameState.play_sfx("pump_rack", -4.0, 1.0)
	if prev_pump < 0.16 and pump_t >= 0.16 and pump_eject:
		pump_eject = false
		_eject_casing(true)

	# Bolt-action cycle
	var prev_bolt := bolt_t
	bolt_t += delta
	if bolt_t >= 0.0 and bolt_t <= 0.62:
		var b := bolt_t / 0.62
		var lift := smoothstep(0.0, 0.18, b) * (1.0 - smoothstep(0.82, 1.0, b))
		var pull := smoothstep(0.2, 0.42, b) * (1.0 - smoothstep(0.55, 0.78, b))
		bolt_rot.z = 1.1 * lift
		bolt_off.z += 0.09 * pull
	if prev_bolt < 0.0 and bolt_t >= 0.0:
		GameState.play_sfx("bolt_cycle", -4.0, 1.0)
	if prev_bolt < 0.28 and bolt_t >= 0.28:
		_eject_casing(false)

	# Reload choreography
	if is_reloading:
		var pr := 1.0 - clampf(reload_timer / maxf(0.01, reload_total), 0.0, 1.0)
		if cfg["reload_type"] == "shell":
			# Left hand travels from the pump to the loading port for each shell
			var reach := sin(pr * PI)
			arm_l_off = Vector3(0.01, -0.045, 0.3) * reach
			arm_l_rot = Vector3(0.0, 0.0, -0.5) * reach
		else:
			var drop := smoothstep(0.12, 0.3, pr) * (1.0 - smoothstep(0.52, 0.72, pr))
			var hand := smoothstep(0.1, 0.38, pr) * (1.0 - smoothstep(0.62, 0.85, pr))
			if w_id == "volt":
				mag_off = Vector3(0, -0.06, 0.16) * drop
			elif w_id == "revolver":
				cyl_off = Vector3(-0.045, 0, 0) * smoothstep(0.08, 0.2, pr) * (1.0 - smoothstep(0.8, 0.92, pr))
			else:
				mag_off = Vector3(0, -0.3, 0.02) * drop
			arm_l_off = Vector3(-0.03, -0.17, 0.12) * hand
			arm_l_rot = Vector3(-0.4, 0.0, 0.3) * hand
			if w_id == "lmg":
				cover_rot.x = 0.75 * smoothstep(0.04, 0.14, pr) * (1.0 - smoothstep(0.84, 0.94, pr))
			if not _mag_out_played and pr >= 0.15:
				_mag_out_played = true
				GameState.play_sfx("mag_out", -4.0, randf_range(0.95, 1.05))
			if not _mag_in_played and pr >= 0.68:
				_mag_in_played = true
				vm_vel.y += 0.22
				vm_rot_vel.x += 1.6
				GameState.play_sfx("mag_in", -3.0, randf_range(0.95, 1.05))
			if reload_was_empty and pr > 0.8:
				if not _bolt_rel_played:
					_bolt_rel_played = true
					vm_rot_vel.x -= 1.4
					vm_vel.z += 0.15
					GameState.play_sfx("pump_rack", -5.0, 1.32)
				var charge := sin(clampf((pr - 0.8) / 0.15, 0.0, 1.0) * PI)
				slide_off.z = maxf(slide_off.z, 0.032 * charge)
				bolt_off.z = maxf(bolt_off.z, 0.05 * charge)
	elif empty and w_id == "pistol":
		slide_off.z = 0.032

	_set_part("SlidePivot", slide_off, Vector3.ZERO)
	_set_part("BoltPivot", bolt_off, bolt_rot)
	_set_part("MagPivot", mag_off, Vector3.ZERO)
	_set_part("PumpPivot", pump_off, Vector3.ZERO)
	_set_part("ArmL", arm_l_off, arm_l_rot)
	_set_part("CoverPivot", Vector3.ZERO, cover_rot)
	_set_part("HammerPivot", Vector3.ZERO, hammer_rot)
	var cyl: Dictionary = _part("CylinderPivot")
	if not cyl.is_empty():
		var n: Node3D = cyl["node"]
		n.position = cyl["pos"] + cyl_off
		var target_spin := float(shots_fired) * PI / 3.0 + (TAU if is_reloading else 0.0)
		n.rotation.z = lerpf(n.rotation.z, target_spin, clampf(14.0 * delta, 0.0, 1.0))
	var coil: Dictionary = _part("CoilPivot")
	if not coil.is_empty():
		(coil["node"] as Node3D).rotation.z += delta * (1.5 + 25.0 * k_fire)
	var mag: Dictionary = _part("MagPivot")
	if not mag.is_empty():
		(mag["node"] as Node3D).visible = mag_off.y > -0.27


func _animate_grenade_hand(delta: float) -> void:
	if grenade_anim_t < 0.0:
		return
	grenade_anim_t += delta
	var a := grenade_anim_t / 0.5
	grenade_rig.visible = a < 1.0
	if a >= 1.0:
		grenade_anim_t = -1.0
		return
	var low := Vector3(-0.22, -0.5, -0.25)
	var cocked := Vector3(-0.2, -0.12, -0.32)
	var thrown := Vector3(-0.05, -0.08, -0.7)
	var pos: Vector3
	var rot: Vector3
	if a < 0.38:
		var k := smoothstep(0.0, 0.38, a)
		pos = low.lerp(cocked, k)
		rot = Vector3(0.6 * k, 0.3, 0)
	else:
		var k2 := smoothstep(0.38, 0.62, a)
		pos = cocked.lerp(thrown, k2)
		rot = Vector3(0.6 - 1.6 * k2, 0.3, 0)
	grenade_rig.position = pos
	grenade_rig.rotation = rot
	# The grenade leaves the hand on release
	var nade := grenade_rig.find_child("NadeBody", true, false) as Node3D
	if nade:
		var holding := a < 0.42
		nade.visible = holding
		for nm in ["Fuze", "Lever", "Pin"]:
			var part := grenade_rig.find_child(nm, true, false) as Node3D
			if part:
				part.visible = holding


func _play_death_camera() -> void:
	gun_rig.visible = false
	monster_claw_rig.visible = false
	knife_rig.visible = false
	camera.position = Vector3.ZERO
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(head_pivot, "position:y", 0.35, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(camera, "rotation:z", deg_to_rad(72.0), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func add_camera_shake(amount: float) -> void:
	camera_shake = minf(1.0, camera_shake + amount)


func _spawn_bullet_tracer(from_pt: Vector3, to_pt: Vector3, col: Color, radius: float = 0.012) -> void:
	if Net.is_online() and _net_game():
		_ng.local_shot(get_current_weapon_id(), to_pt)
	var dist := from_pt.distance_to(to_pt)
	if dist < 0.3:
		return
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = dist
	cm.radial_segments = 6
	beam.mesh = cm
	beam.material_override = MaterialLib.get_emissive(col, 5.5, 0.82)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from_pt + to_pt) * 0.5
	beam.look_at(to_pt, Vector3.UP if absf((to_pt - from_pt).normalized().y) < 0.99 else Vector3.RIGHT)
	beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	var tw := beam.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(beam.queue_free)


func _spawn_impact_spark(pt: Vector3, is_blood: bool) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11 if is_blood else 0.06
	sm.height = sm.radius * 2.0
	s.mesh = sm
	var col := Color(0.85, 0.08, 0.08) if is_blood else Color(1.0, 0.78, 0.30)
	s.material_override = MaterialLib.get_emissive(col, 4.0, 0.85)
	get_tree().current_scene.add_child(s)
	s.global_position = pt
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ZERO, 0.14)
	tw.tween_callback(s.queue_free)


func _spawn_slash_burst(pt: Vector3, col: Color) -> void:
	var arc := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.08, 0.25)
	arc.mesh = bm
	arc.material_override = MaterialLib.get_emissive(col, 6.5, 0.88)
	get_tree().current_scene.add_child(arc)
	arc.global_position = pt
	arc.rotation = Vector3(0, rotation.y, deg_to_rad(-28.0))
	var tw := arc.create_tween()
	tw.tween_property(arc, "scale", Vector3(1.4, 0.1, 1.4), 0.16)
	tw.tween_callback(arc.queue_free)


func _spawn_aoe_ring(center: Vector3, max_radius: float, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.78
	tm.outer_radius = 1.0
	ring.mesh = tm
	ring.material_override = MaterialLib.get_emissive(col, 6.5, 0.85)
	get_tree().current_scene.add_child(ring)
	ring.global_position = Vector3(center.x, center.y + 0.14, center.z)
	ring.scale = Vector3(0.25, 1.0, 0.25)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free)


# ---------------------------------------------------------------------------
# CO-OP
# ---------------------------------------------------------------------------
func _net_game() -> Node:
	if not is_instance_valid(_ng):
		_ng = get_tree().get_first_node_in_group("net_game")
	return _ng


# Zombies go after players who are standing.
func is_valid_target() -> bool:
	return not is_dead and not is_downed and not extracted


# Online, the game keeps running behind the pause menu: just stop acting.
func _input_blocked() -> bool:
	return Net.is_online() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


func revive_by_teammate(by_name: String) -> void:
	if not is_downed or is_dead:
		return
	is_downed = false
	self_reviving = false
	hp = max_hp * 0.5
	revive_invuln = 2.0
	regen_delay_timer = 0.0
	GameState.play_sfx("second_wind", -3.0, 1.15)
	status_banner_requested.emit("REVIVED BY %s — BACK ON YOUR FEET" % by_name, Color(0.4, 1.0, 0.6))
	downed_changed.emit(false)
	hp_changed.emit(hp, max_hp, overshield)


# Co-op: back in at the start of the next round.
func net_respawn(pos: Vector3) -> void:
	is_dead = false
	is_downed = false
	self_reviving = false
	extracted = false
	hp = max_hp
	overshield = 0.0
	revive_invuln = 3.0
	collision_layer = 2
	global_position = pos
	velocity = Vector3.ZERO
	head_pivot.position.y = _head_rest_y
	head_pivot.rotation.x = 0.0
	camera.rotation.z = 0.0
	camera.position = Vector3.ZERO
	gun_rig.visible = true
	refill_all_ammo()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.play_sfx("second_wind", -2.0, 0.9)
	status_banner_requested.emit("BACK IN THE FIGHT!", Color(0.4, 1.0, 0.6))
	downed_changed.emit(false)
	hp_changed.emit(hp, max_hp, overshield)


# ---------------------------------------------------------------------------
# BOSS RELICS
# ---------------------------------------------------------------------------
# Skills of the other operators a relic can lend you (used with [X]).
const BORROWED_SKILLS := {
	"feral_slash": {"name": "FERAL LUNGE SLASH", "owner": "ravager", "cd": 8.0},
	"pain_dart": {"name": "PAIN DRUG DART", "owner": "alchemist", "cd": 14.0},
	"stim": {"name": "ADRENALINE STIM", "owner": "alchemist", "cd": 45.0},
	"tesla": {"name": "TESLA CHARGE", "owner": "warden", "cd": 12.0},
	"overcharge": {"name": "ARC OVERCHARGE", "owner": "warden", "cd": 40.0},
}
var borrowed_skill: String = ""
var borrowed_cd: float = 0.0
var borrowed_cd_max: float = 0.0
var borrowed_skill2: String = "" # second slot [Z], a career unlock
var borrowed_cd2: float = 0.0
var borrowed_cd_max2: float = 0.0
var pending_skill: String = ""
var pending_mult: float = 1.0
var pending_skill_t: float = 0.0


# Raise a stat by whole levels (as if that many points went into the furnace).
func grant_stat_levels(id: String, levels: int) -> int:
	var gained := 0
	for i in range(levels):
		var prog: Dictionary = GameState.stat_progress(int(stat_burned.get(id, 0)))
		if int(prog["level"]) >= GameState.STAT_MAX_LEVEL:
			break
		gained += burn_into_stat(id, int(prog["need"]) - int(prog["into"]))
	return gained


func can_borrow(skill_id: String) -> bool:
	return BORROWED_SKILLS.has(skill_id) and BORROWED_SKILLS[skill_id]["owner"] != char_id


func grant_borrowed_skill(skill_id: String, cd_mult: float) -> void:
	var sk_name: String = BORROWED_SKILLS[skill_id]["name"]
	if borrowed_skill == "" or borrowed_skill == skill_id:
		_set_slot(1, skill_id, cd_mult)
		status_banner_requested.emit("NEW SKILL [X]: %s" % sk_name, Color(0.75, 0.5, 1.0))
	elif GameState.has_unlock("skill_slot") and (borrowed_skill2 == "" or borrowed_skill2 == skill_id):
		_set_slot(2, skill_id, cd_mult)
		status_banner_requested.emit("NEW SKILL [Z]: %s" % sk_name, Color(0.75, 0.5, 1.0))
	else:
		# Slots full: let the player choose (8 seconds, ignore to keep)
		pending_skill = skill_id
		pending_mult = cd_mult
		pending_skill_t = 8.0
		var choice := "[X] REPLACE %s" % BORROWED_SKILLS[borrowed_skill]["name"]
		if GameState.has_unlock("skill_slot"):
			choice += "   [Z] REPLACE %s" % BORROWED_SKILLS[borrowed_skill2]["name"]
		status_banner_requested.emit("NEW SKILL: %s — %s — OR IGNORE TO KEEP" % [sk_name, choice], Color(0.75, 0.5, 1.0))


func _set_slot(slot: int, skill_id: String, cd_mult: float) -> void:
	if slot == 1:
		borrowed_skill = skill_id
		borrowed_cd_max = float(BORROWED_SKILLS[skill_id]["cd"]) * cd_mult
		borrowed_cd = 0.0
	else:
		borrowed_skill2 = skill_id
		borrowed_cd_max2 = float(BORROWED_SKILLS[skill_id]["cd"]) * cd_mult
		borrowed_cd2 = 0.0
	stats_changed.emit()


func _place_pending_skill(slot: int) -> void:
	_set_slot(slot, pending_skill, pending_mult)
	status_banner_requested.emit("SKILL %s: %s" % ["[X]" if slot == 1 else "[Z]", BORROWED_SKILLS[pending_skill]["name"]], Color(0.75, 0.5, 1.0))
	pending_skill = ""
	pending_skill_t = 0.0


func _use_borrowed_skill(slot: int = 1) -> void:
	var skill := borrowed_skill if slot == 1 else borrowed_skill2
	var cd := borrowed_cd if slot == 1 else borrowed_cd2
	if skill == "" or cd > 0.0 or is_monster_form:
		return
	if slot == 1:
		borrowed_cd = borrowed_cd_max
	else:
		borrowed_cd2 = borrowed_cd_max2
	match skill:
		"feral_slash":
			_perform_human_feral_slash()
		"pain_dart":
			pain_drug_charges = maxi(pain_drug_charges, 1)
			_fire_pain_drug_dart()
		"stim":
			stim_timer = 10.0
			hp = max_hp
			overshield = 50.0
			hp_changed.emit(hp, max_hp, overshield)
			GameState.play_sfx("pain_drug", 0.0, 1.25)
			status_banner_requested.emit("ADRENALINE STIM! FULL HP +50 SHIELD", Color(0.16, 0.96, 0.80))
		"tesla":
			_fire_tesla_charge()
		"overcharge":
			pap_timer = 12.0
			is_reloading = false
			var w_id := get_current_weapon_id()
			mag_ammo[w_id] = get_weapon_cfg(w_id)["mag_size"]
			_emit_ammo()
			GameState.play_sfx("buy_ching", 0.0, 0.85)
			status_banner_requested.emit("ARC OVERCHARGE! 2.2x DAMAGE & INFINITE CLIP (12s)!", Color(0.92, 0.38, 1.0))


# ---------------------------------------------------------------------------
# RUN SAVE
# ---------------------------------------------------------------------------
func export_state() -> Dictionary:
	return {
		"run_id": GameState.run_id, "char": char_id, "points": GameState.points,
		"kills": GameState.total_kills, "headshots": GameState.headshots, "bosses": GameState.bosses_slain,
		"weapons": Array(weapons_owned), "slot": active_slot, "mag": mag_ammo.duplicate(),
		"reserve": reserve_ammo.duplicate(), "upgraded": upgraded.duplicate(), "stats": stat_burned.duplicate(),
		"revives": revives, "grenades": grenades,
		"skill1": borrowed_skill, "skill1_cd": borrowed_cd_max, "skill2": borrowed_skill2, "skill2_cd": borrowed_cd_max2,
	}


func import_state(d: Dictionary) -> void:
	if d.is_empty() or String(d.get("char", char_id)) != char_id:
		return
	GameState.points = int(d.get("points", GameState.points))
	GameState.total_kills = int(d.get("kills", 0))
	GameState.headshots = int(d.get("headshots", 0))
	GameState.bosses_slain = int(d.get("bosses", 0))
	GameState.points_changed.emit(GameState.points, 0)
	var ws: Array[String] = []
	for w in d.get("weapons", ["pistol"]):
		if GameState.WEAPONS.has(String(w)):
			ws.append(String(w))
	if not ws.is_empty():
		weapons_owned = ws
	mag_ammo = d.get("mag", mag_ammo)
	reserve_ammo = d.get("reserve", reserve_ammo)
	upgraded = d.get("upgraded", upgraded)
	stat_burned = d.get("stats", stat_burned)
	revives = int(d.get("revives", revives))
	grenades = int(d.get("grenades", grenades))
	borrowed_skill = String(d.get("skill1", ""))
	borrowed_cd_max = float(d.get("skill1_cd", 0.0))
	borrowed_skill2 = String(d.get("skill2", ""))
	borrowed_cd_max2 = float(d.get("skill2_cd", 0.0))
	active_slot = clampi(int(d.get("slot", 0)), 0, weapons_owned.size() - 1)
	_apply_stats()
	hp = max_hp
	_equip_weapon_model(get_current_weapon_id())
	_emit_ammo()
	stats_changed.emit()
	hp_changed.emit(hp, max_hp, overshield)
	status_banner_requested.emit("RUN RESTORED — YOUR LOADOUT IS BACK", Color(0.55, 0.9, 1.0))
