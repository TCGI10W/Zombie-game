class_name ZombieEnemy
extends CharacterBody3D

signal died(enemy: ZombieEnemy, was_headshot: bool)
signal boss_damaged(enemy: ZombieEnemy)
signal spawn_minion_requested(pos: Vector3)

@export var is_boss: bool = false
var boss_type: String = ""
var display_name: String = "ZOMBIE"
var boss_subtitle: String = ""

var max_hp: float = 100.0
var hp: float = 100.0
var endurance: float = 0.0 # Damage reduction [0.0 .. 0.75]
var base_speed: float = 3.2
var base_damage: float = 22.0
var point_reward: int = 60
var model_scale: float = 1.0
var _pre_hit_hp: float = 0.0

# --- TIERS: 1-2 normal horde, 3+ commanders that think, talk and give orders
const TIER_COLORS := [Color(0, 0, 0), Color(0.9, 0.9, 0.9), Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.1), Color(1.0, 0.15, 0.12), Color(0.75, 0.25, 1.0)]
const TIER_HP := [1.0, 1.0, 1.35, 2.4, 3.2, 4.2]
const TIER_DMG := [1.0, 1.0, 1.2, 1.5, 1.8, 2.2]
const TIER_SPEED := [1.0, 1.0, 1.06, 1.1, 1.15, 1.2]
const TIER_NAMES := ["", "ROTTER", "STALKER", "COMMANDER", "WARLORD", "OVERLORD"]
const TIER_GUARD_DR := [1.0, 1.0, 1.0, 0.5, 0.4, 0.3] # damage taken while bodyguards stand near
const CommanderBrain := preload("res://scripts/enemies/commander_brain.gd")
var tier: int = 1
var commander_name: String = ""
var commander: Node = null # CommanderBrain, tier 3+
# Orders (from a commander or the brain feast): walk to order_pos instead of hunting
var order_kind: String = ""
var order_pos: Vector3 = Vector3.ZERO
var order_t: float = 0.0
var order_from: Node3D = null
var buff_t: float = 0.0 # rally: faster and harder hitting
var _tier_light: OmniLight3D
var _tier_label: Label3D
var stolen_skill: String = "" # the operator skill a commander took from a brain
var is_nemesis: bool = false # the commander that killed you in an earlier run
var blood_hits: int = 0 # hits landed on players (taste of blood -> rank up)
var aura_t: float = 0.0 # near a commander: faster, hits harder
var aura_mult: float = 1.0
var shield_on: bool = false # commander with bodyguards: damage shield
var _shield_mesh: MeshInstance3D
var _aura_ring: MeshInstance3D
var _warn_node: Node3D
var _base_vscale: Vector3 = Vector3.ZERO
var _dodge_cd: float = 1.0
var _dodge_t: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _lunge_cd: float = 2.5
var _lunge_t: float = 0.0
var _shield_hint_cd: float = 0.0
var fx_cast: String = "" # skill being wound up right now (shown on the HUD)
var fx_cast_t: float = 0.0
var fx_enraged: bool = false
# How it moves (host): "" plain, "lurch" drag-step, "burst" stands then
# sprints, "lurker" freezes while you look at it and rushes when you don't
var move_style: String = ""
var _style_t: float = 0.0
var _sleeper_awake: bool = true
var _flash_lit_t: float = 0.0
var _eye_nodes: Array[MeshInstance3D] = []
var _spitter_tinted: bool = false
static var _shield_tip_t: float = -100.0
var _zig: float = 0.0
var is_sprinter: bool = false
var is_crawler: bool = false
var is_bloater: bool = false
var is_shielded: bool = false
var is_spitter: bool = false
var voice_pitch: float = 1.0
const GasCloudScript := preload("res://scripts/world/gas_cloud.gd")

# Status Effects
var stun_timer: float = 0.0
var pain_drug_timer: float = 0.0
var pain_drug_duration: float = 12.0
var hit_flash_timer: float = 0.0

# AI & Animation Nodes
var target_player: Node3D = null
var nav_agent: NavigationAgent3D = null
var visual_root: Node3D = null
var node_torso: Node3D = null
var node_head: Node3D = null
var node_arm_l: Node3D = null
var node_arm_r: Node3D = null
var node_leg_l: Node3D = null
var node_leg_r: Node3D = null

# Visual Status Indicators
var stun_halo: Node3D = null
var drug_aura: Node3D = null
var drug_light: OmniLight3D = null
var laser_beam: MeshInstance3D = null
var telegraph_ring: MeshInstance3D = null
var flame_cone: MeshInstance3D = null

# Combat state machine
enum BossAction { CHASE, WINDUP, FIRING, RECOVER }
var action_state: BossAction = BossAction.CHASE
var state_timer: float = 0.0
var attack_cooldown: float = 1.2
var burst_shots_left: int = 0
var burst_shot_delay: float = 0.0
var strafe_dir: float = 1.0
var strafe_switch_timer: float = 2.0
var anim_phase: float = 0.0
var _last_step_half: int = 0
var roar_timer: float = 1.5
var step_audio_3d: AudioStreamPlayer3D = null
var roar_audio_3d: AudioStreamPlayer3D = null
var slam_target_pos: Vector3 = Vector3.ZERO
var is_dead: bool = false

# Window entry: spawn outside, tear boards, climb in, then hunt.
# entry_stage: 0 walk to window, 1 tearing boards, 2 climbing in, 3 inside
var entry_window: Node3D = null
var entry_stage: int = 3
var tear_timer: float = 0.0

# Jointed-model animation (new zombies); bosses keep the simple pivots
const ZombieRigScript := preload("res://scripts/enemies/zombie_rig.gd")
const SHIRT_COLORS := [Color(0.16, 0.18, 0.22), Color(0.35, 0.12, 0.1), Color(0.22, 0.28, 0.18),
	Color(0.4, 0.38, 0.33), Color(0.12, 0.12, 0.13), Color(0.3, 0.24, 0.35)]
static var _shirt_mats: Dictionary = {}
var rig = null
var pending_hit_t: float = -1.0
var last_damage_kind: String = "bullet"
var last_hit_from: Vector3 = Vector3.ZERO
var _flesh_sfx_cd: float = 0.0
var _step_count: int = 0
var ragdolled: bool = false
var last_hit_point: Vector3 = Vector3.ZERO
var last_damage_amount: float = 0.0
var _prev_yaw: float = 0.0
var _yaw_rate: float = 0.0
const RagdollScript := preload("res://scripts/enemies/ragdoll.gd")

# Hit feedback & spawn animation
var _meshes: Array[MeshInstance3D] = []
var rise_timer: float = 0.0

# --- Co-op: the host runs the AI; clients show "puppets" driven by snapshots
const NET_MODES := ["walk", "run", "idle", "crawl", "stunned", "rise", "climb", "dead"]
var net_id: int = 0
var net_puppet: bool = false
var net_buf: NetBuffer = null
var _net_anim: int = 0
var _net_speed: float = 0.0
var _net_attack_seen: bool = false
var _net_hit_t: float = -10.0
var _net_attacker: int = 1
var dmg_by: Dictionary = {} # host, co-op: peer id -> damage dealt (assists)
var _retarget_t: float = 0.0
var _ng_cache: Node = null
static var _flash_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D


func setup_regular(round_num: int, variant: String = "walker") -> void:
	is_boss = false
	boss_type = ""
	display_name = "UNDEAD SHAMBLER"
	max_hp = 95.0 + float(round_num - 1) * 38.0
	base_speed = 2.9 + minf(2.2, float(round_num - 1) * 0.25)
	base_damage = 20.0 + float(round_num - 1) * 3.0
	point_reward = 60
	model_scale = 1.0

	var model := "res://assets/models/zombie_walker_v2.glb"
	if variant == "sprinter":
		is_sprinter = true
		display_name = "FERAL SPRINTER"
		max_hp *= 0.82
		base_speed += 1.85
		point_reward = 80
		model = "res://assets/models/zombie_runner_v2.glb"
	elif variant == "crawler":
		is_crawler = true
		display_name = "BLIGHT CRAWLER"
		max_hp *= 0.55
		base_speed += 0.6
		point_reward = 50
	elif variant == "bloater":
		is_bloater = true
		display_name = "BLOATER"
		max_hp *= 2.3
		base_speed *= 0.72
		base_damage *= 1.3
		point_reward = 130
		model_scale = 1.05
		voice_pitch = 0.74
		model = "res://assets/models/zombie_bloater.glb"
	elif variant == "shielded":
		is_shielded = true
		display_name = "RIOT HUSK"
		max_hp *= 1.4
		base_speed -= 0.35
		point_reward = 120
		model = "res://assets/models/zombie_soldier_v2.glb"
	elif variant == "spitter":
		is_spitter = true
		display_name = "ACID SPITTER"
		max_hp *= 0.9
		point_reward = 110
		voice_pitch = 1.25
		model = "res://assets/models/zombie_runner_v2.glb"
	elif variant == "armored":
		display_name = "BUNKER TROOPER"
		max_hp *= 1.55
		endurance = 0.25
		model_scale = 1.06
		point_reward = 100
		model = "res://assets/models/zombie_soldier_v2.glb"
	elif randf() < 0.25:
		model = "res://assets/models/zombie_soldier_v2.glb"
	model_scale *= randf_range(0.95, 1.05)
	if not ResourceLoader.exists(model):
		model = "res://assets/models/zombie_walker.glb"

	hp = max_hp
	_build_body(model, Color(1, 0.3, 0.2))
	if is_shielded:
		_add_riot_shield()
	if is_spitter:
		_tint_spitter()
	if rig:
		rig.twitch_amt = maxf(rig.twitch_amt, randf_range(0.32, 0.78))
	_style_t = randf() * 10.0


# True while the target is looking this way (lurkers freeze)
func _looked_at() -> bool:
	var p := target_player
	if not is_instance_valid(p):
		return false
	var fwd: Vector3 = -p.global_basis.z
	if p is PlayerController and is_instance_valid((p as PlayerController).camera):
		fwd = -(p as PlayerController).camera.global_basis.z
	var to_me := global_position + Vector3(0, 1.2, 0) - (p.global_position + Vector3(0, 1.6, 0))
	var d := to_me.length()
	return d < 32.0 and fwd.dot(to_me / maxf(d, 0.01)) > 0.8


# Speed factor of this zombie's way of moving (0 = standing still)
func _style_mult(delta: float, flat_dist: float) -> float:
	if move_style == "" or flat_dist < 3.5 or buff_t > 0.0:
		return 1.0
	_style_t += delta
	match move_style:
		"lurch":
			return 0.4 + 1.25 * maxf(0.0, sin(_style_t * 2.7))
		"burst":
			return 0.0 if fmod(_style_t, 4.2) < 1.7 else 1.75
		"lurker":
			if flat_dist > 6.0 and _looked_at():
				return 0.0
			return 1.7
	return 1.0


func setup_boss(config: Dictionary) -> void:
	is_boss = true
	boss_type = config.get("type", "gun_zombie")
	display_name = config.get("name", "ROUND BOSS")
	boss_subtitle = config.get("subtitle", "")
	max_hp = config.get("max_hp", 800.0)
	hp = max_hp
	endurance = config.get("endurance", 0.2)
	base_speed = config.get("speed", 3.5)
	base_damage = config.get("damage", 35.0)
	point_reward = config.get("reward", 600)
	model_scale = config.get("scale", 1.2)
	var accent: Color = config.get("color", Color(1.0, 0.3, 0.15))
	var model_path: String = config.get("model", "res://assets/models/boss_gun_zombie.glb")
	_build_body(model_path, accent)


func _build_body(model_path: String, accent_color: Color) -> void:
	collision_layer = 4 # Enemy layer
	collision_mask = 1 | 2 | 4 # World + Player + Enemies

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = (0.48 if is_boss else 0.36) * model_scale
	cap.height = (2.15 if is_boss else 1.82) * model_scale
	if is_crawler:
		cap.height = 1.15
	col.shape = cap
	col.position = Vector3(0, cap.height * 0.5, 0)
	add_child(col)

	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.75
	nav_agent.target_desired_distance = 1.2
	nav_agent.radius = cap.radius
	add_child(nav_agent)

	visual_root = Node3D.new()
	visual_root.scale = Vector3.ONE * model_scale
	add_child(visual_root)

	if ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path)
		var inst := packed.instantiate()
		visual_root.add_child(inst)
		if not is_boss:
			rig = ZombieRigScript.new()
			var proxies := SkinRigAdapter.attach(inst)
			if not rig.bind(proxies if proxies else inst):
				rig = null
		if rig:
			if is_crawler:
				rig.hide_legs()
			_tint_shirt(inst)
		elif is_crawler:
			visual_root.scale = Vector3(0.85, 0.56, 0.95)
		node_torso = inst.find_child("Torso", true, false)
		node_head = inst.find_child("Head", true, false)
		node_arm_l = inst.find_child("ArmL", true, false)
		node_arm_r = inst.find_child("ArmR", true, false)
		node_leg_l = inst.find_child("LegL", true, false)
		node_leg_r = inst.find_child("LegR", true, false)
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(m as MeshInstance3D)
			(m as MeshInstance3D).layers = 2 # keep decals off zombies

	# Regular zombies claw their way up out of the ground when they spawn.
	if not is_boss:
		rise_timer = 0.7
		visual_root.position.y = -1.7 * visual_root.scale.y
		var rise_tw := create_tween()
		rise_tw.tween_property(visual_root, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_build_status_vfx(cap.height, accent_color)
	_attach_pinprick_eyes(accent_color if is_boss else Color(0.85, 0.72, 0.32))
	_build_3d_audio(cap.height)
	anim_phase = randf() * TAU
	_last_step_half = int(floor(anim_phase / PI))
	roar_timer = randf_range(0.8, 2.2) if is_boss else randf_range(2.2, 7.5)


func _attach_pinprick_eyes(col: Color) -> void:
	var anchor: Node3D = null
	if rig and rig.nodes.has("Head") and is_instance_valid(rig.nodes["Head"]):
		anchor = rig.nodes["Head"] as Node3D
	elif is_instance_valid(node_head):
		anchor = node_head
	elif is_instance_valid(visual_root):
		anchor = visual_root
	if anchor == null:
		return
	var mat := MaterialLib.get_emissive(col, 1.35 if is_boss else 0.85)
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.013
	eye_mesh.height = 0.026
	eye_mesh.radial_segments = 6
	eye_mesh.rings = 4
	var y_off := 0.11 if anchor != visual_root else 1.58
	var z_off := -0.105 if anchor != visual_root else -0.14
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.layers = 2
		eye.position = Vector3(0.044 * sx, y_off, z_off)
		anchor.add_child(eye)
		_eye_nodes.append(eye)


func make_sleeper() -> void:
	if is_boss or is_crawler or is_bloater:
		return
	move_style = "sleeper"
	_sleeper_awake = false
	rise_timer = 0.0
	if is_instance_valid(visual_root):
		visual_root.rotation.x = deg_to_rad(80.0)
		visual_root.position.y = 0.14
	for eye in _eye_nodes:
		if is_instance_valid(eye):
			eye.visible = false


func _lit_by_flashlight() -> bool:
	if not is_instance_valid(target_player) or not (target_player is PlayerController):
		return false
	var pc := target_player as PlayerController
	if not pc.flashlight_lit() or not is_instance_valid(pc.flashlight):
		return false
	var to_me := (global_position + Vector3(0, 0.9, 0)) - pc.flashlight.global_position
	var d := to_me.length()
	if d > 20.0 or d < 0.1:
		return false
	return (-pc.flashlight.global_basis.z).dot(to_me / d) > 0.88


func _wake_sleeper() -> void:
	if _sleeper_awake:
		return
	_sleeper_awake = true
	for eye in _eye_nodes:
		if is_instance_valid(eye):
			eye.visible = true
	_play_3d_roar("zombie_attack_roar", randf_range(1.08, 1.28))
	rise_timer = 0.32
	if is_instance_valid(visual_root):
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(visual_root, "rotation:x", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual_root, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _tint_shirt(inst: Node) -> void:
	var idx := randi() % SHIRT_COLORS.size()
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(si)
			if mat and mat.resource_name == "Shirt":
				if not _shirt_mats.has(idx):
					var dup := mat.duplicate() as StandardMaterial3D
					dup.albedo_color = SHIRT_COLORS[idx] * 1.7
					_shirt_mats[idx] = dup
				mi.set_surface_override_material(si, _shirt_mats[idx])


func head_y() -> float:
	if is_boss:
		return global_position.y + 1.62 * model_scale
	return global_position.y + (1.52 if rig else 1.46) * model_scale


func _build_3d_audio(height: float) -> void:
	step_audio_3d = AudioStreamPlayer3D.new()
	step_audio_3d.bus = &"Zombies"
	step_audio_3d.position = Vector3(0, 0.15, 0)
	step_audio_3d.max_polyphony = 2
	# Footsteps tell you WHERE zombies are: loud and crisp right next to you,
	# quickly quieter and muffled with distance (inverse-square, like real sound)
	step_audio_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	step_audio_3d.unit_size = 5.0 if is_boss else 3.0
	step_audio_3d.max_distance = 40.0 if is_boss else 24.0
	step_audio_3d.volume_db = 12.0 if is_boss else 10.0
	step_audio_3d.attenuation_filter_cutoff_hz = 2200.0
	step_audio_3d.attenuation_filter_db = -30.0
	step_audio_3d.panning_strength = 1.4
	step_audio_3d.max_polyphony = 2
	add_child(step_audio_3d)

	roar_audio_3d = AudioStreamPlayer3D.new()
	roar_audio_3d.bus = &"Zombies"
	roar_audio_3d.position = Vector3(0, height * 0.78, 0)
	roar_audio_3d.unit_size = 12.5 if is_boss else 5.8
	roar_audio_3d.max_distance = 44.0 if is_boss else 26.0
	roar_audio_3d.volume_db = 2.5 if is_boss else -2.2
	roar_audio_3d.attenuation_filter_cutoff_hz = 4800.0 if is_boss else 3400.0
	roar_audio_3d.attenuation_filter_db = -10.0 if is_boss else -16.0
	add_child(roar_audio_3d)


func _play_3d_roar(clip_name: String, pitch: float = 1.0) -> void:
	if not roar_audio_3d or is_dead:
		return
	var stream := GameState.get_sfx_stream(clip_name)
	if stream:
		roar_audio_3d.stream = stream
		roar_audio_3d.pitch_scale = pitch * voice_pitch
		roar_audio_3d.play()


func _play_3d_footstep(step_index: int) -> void:
	if not step_audio_3d or is_dead or not is_on_floor():
		return
	# Far-away zombies only play some of their steps, so the close ones stand out
	if not is_boss:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(global_position)
			if (d > 10.0 and step_index % 2 == 1) or (d > 16.0 and step_index % 4 != 0):
				return
	var clip := "boss_step" if is_boss else ("zombie_step_1" if (step_index % 2 == 0) else "zombie_step_2")
	var stream := GameState.get_sfx_stream(clip)
	if stream:
		step_audio_3d.stream = stream
		var base_p := 0.88 if is_boss else (1.0 if is_sprinter else 0.86) # lower = heavier, dragging walk
		step_audio_3d.pitch_scale = base_p * randf_range(0.92, 1.08)
		if GameState.step_volume <= 0.001:
			return
		step_audio_3d.volume_db = (12.0 if is_boss else 10.0) + linear_to_db(GameState.step_volume)
		step_audio_3d.play()
	if is_boss and (boss_type == "gorilla" or boss_type == "juggernaut") and is_instance_valid(target_player):
		if global_position.distance_to(target_player.global_position) < 9.5 and target_player.has_method("add_camera_shake"):
			target_player.add_camera_shake(0.06)


func _build_status_vfx(height: float, accent_color: Color) -> void:
	# 1. Stun Halo (4-second Stun visual above head!)
	stun_halo = Node3D.new()
	stun_halo.position = Vector3(0, height + 0.32, 0)
	stun_halo.visible = false
	add_child(stun_halo)

	var stun_mat := MaterialLib.get_emissive(Color(1.0, 0.85, 0.18), 5.0)
	for i in range(3):
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09 * model_scale
		sm.height = 0.18 * model_scale
		orb.mesh = sm
		orb.material_override = stun_mat
		var ang := float(i) * TAU / 3.0
		orb.position = Vector3(cos(ang) * 0.38 * model_scale, 0, sin(ang) * 0.38 * model_scale)
		stun_halo.add_child(orb)

	# 2. Pain Drug Sedation Aura (Dual orbiting cyan bio-rings + light so Boss model stays 100% visible!)
	drug_aura = Node3D.new()
	drug_aura.position = Vector3(0, height * 0.52, 0)
	drug_aura.visible = false
	add_child(drug_aura)

	var drug_mat := MaterialLib.get_emissive(Color(0.12, 0.98, 0.84), 4.2, 0.78)
	for ri in range(2):
		var ring_mi := MeshInstance3D.new()
		var tmesh := TorusMesh.new()
		tmesh.inner_radius = (0.68 + float(ri) * 0.14) * model_scale
		tmesh.outer_radius = tmesh.inner_radius + 0.055 * model_scale
		ring_mi.mesh = tmesh
		ring_mi.material_override = drug_mat
		ring_mi.position.y = (-0.28 + float(ri) * 0.56) * model_scale
		ring_mi.rotation_degrees = Vector3(16.0 if ri == 0 else -16.0, 0.0, 12.0 if ri == 0 else -12.0)
		drug_aura.add_child(ring_mi)

	drug_light = OmniLight3D.new()
	drug_light.light_color = Color(0.12, 0.96, 0.82)
	drug_light.light_energy = 1.8
	drug_light.omni_range = 4.2
	drug_light.position = Vector3(0, height * 0.6, 0)
	drug_light.visible = false
	add_child(drug_light)

	# 3. Boss-specific VFX
	if is_boss:
		var boss_glow := OmniLight3D.new()
		boss_glow.light_color = accent_color
		boss_glow.light_energy = 1.8
		boss_glow.omni_range = 4.8
		boss_glow.position = Vector3(0, height * 0.65, 0.3)
		add_child(boss_glow)

		if boss_type == "gun_zombie":
			# Crisp Tactical Targeting Laser Sight
			laser_beam = MeshInstance3D.new()
			var lmesh := CylinderMesh.new()
			lmesh.top_radius = 0.006
			lmesh.bottom_radius = 0.006
			lmesh.height = 1.0
			laser_beam.mesh = lmesh
			laser_beam.material_override = MaterialLib.get_emissive(Color(1.0, 0.12, 0.10), 6.0, 0.62)
			laser_beam.visible = false
			add_child(laser_beam)

		elif boss_type == "gorilla":
			# Ground-pound danger ring telegraph!
			telegraph_ring = MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 4.55
			torus.outer_radius = 4.95
			torus.rings = 28
			telegraph_ring.mesh = torus
			telegraph_ring.material_override = MaterialLib.get_emissive(Color(1.0, 0.22, 0.08), 5.5, 0.72)
			telegraph_ring.top_level = true
			telegraph_ring.visible = false
			add_child(telegraph_ring)

		elif boss_type == "juggernaut":
			flame_cone = MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.14
			cone.bottom_radius = 1.65
			cone.height = 6.2
			flame_cone.mesh = cone
			flame_cone.material_override = MaterialLib.get_emissive(Color(1.0, 0.45, 0.08), 5.0, 0.42)
			flame_cone.rotation.x = deg_to_rad(90.0)
			flame_cone.position = Vector3(0.45, 1.45, -3.4)
			flame_cone.visible = false
			add_child(flame_cone)


func _physics_process(delta: float) -> void:
	if is_dead:
		if rig and not ragdolled and is_instance_valid(visual_root) and visual_root.visible:
			rig.update(delta, "dead", 0.0)
		return
	if net_puppet:
		_puppet_process(delta)
		return
	if is_boss and Net.is_online():
		_net_sync_fx()
	_flesh_sfx_cd = maxf(0.0, _flesh_sfx_cd - delta)
	_yaw_rate = lerpf(_yaw_rate, wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001), clampf(10.0 * delta, 0.0, 1.0))
	_prev_yaw = rotation.y
	if pending_hit_t > 0.0:
		pending_hit_t -= delta
		if pending_hit_t <= 0.0:
			_resolve_melee_hit()

	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0.0

	# Update status timers
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		stun_halo.visible = stun_timer > 0.0
		stun_halo.rotate_y(delta * 5.8)
	else:
		stun_halo.visible = false

	if pain_drug_timer > 0.0:
		pain_drug_timer = maxf(0.0, pain_drug_timer - delta)
		drug_aura.visible = pain_drug_timer > 0.0
		drug_light.visible = pain_drug_timer > 0.0
		drug_aura.rotate_y(delta * 2.2)
		if is_boss:
			boss_damaged.emit(self)
	else:
		drug_aura.visible = false
		drug_light.visible = false

	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)

	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			_set_flash(false)

	if rise_timer > 0.0:
		rise_timer -= delta
		if rig:
			rig.update(delta, "rise", 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# If STUNNED (e.g. 4.0s from Monster Skill 2!), freeze AI & slump!
	if stun_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		if laser_beam:
			laser_beam.visible = false
		if telegraph_ring:
			telegraph_ring.visible = false
		if flame_cone:
			flame_cone.visible = false
		_animate_stunned(delta)
		move_and_slide()
		return

	if Net.is_online():
		_retarget_t -= delta
		if _retarget_t <= 0.0 or not _valid_target(target_player):
			_retarget_t = 0.5
			_retarget()
	if not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
		if not is_instance_valid(target_player):
			return

	var speed_mult := 0.55 if pain_drug_timer > 0.0 else 1.0
	var rate_mult := 0.55 if pain_drug_timer > 0.0 else 1.0
	if is_boss:
		rate_mult *= 1.2 # bosses attack 20% more often

	# Periodic 3D Zombie & Boss Roars while hunting the player!
	roar_timer -= delta
	if roar_timer <= 0.0:
		if is_boss:
			roar_timer = randf_range(4.5, 7.5)
			_play_3d_roar("boss_roar", randf_range(0.88, 1.06))
		else:
			var dist_to_p := global_position.distance_to(target_player.global_position)
			if dist_to_p <= 24.0 and GameState.request_zombie_vocal(1.05):
				roar_timer = randf_range(4.8, 9.5)
				var clips := ["zombie_roar_1", "zombie_roar_2", "zombie_groan"]
				var chosen: String = "zombie_roar_2" if is_sprinter and randf() < 0.6 else clips[randi() % clips.size()]
				_play_3d_roar(chosen, randf_range(0.88, 1.14))
			else:
				roar_timer = randf_range(1.6, 3.4)

	if is_boss:
		_process_boss_ai(delta, speed_mult, rate_mult)
	else:
		_process_regular_zombie_ai(delta, speed_mult)

	move_and_slide()


func set_entry_window(w: Node3D) -> void:
	entry_window = w
	entry_stage = 0


func is_outside() -> bool:
	return entry_window != null and entry_stage < 2


func _process_window_entry(delta: float, speed_mult: float) -> void:
	var spd := base_speed * speed_mult * _stagger_mult()
	match entry_stage:
		0:
			var tgt: Vector3 = entry_window.attack_pos()
			var to_t := tgt - global_position
			to_t.y = 0.0
			if entry_window.boards <= 0 and to_t.length() < 1.8:
				entry_stage = 2
			elif to_t.length() < 0.45:
				entry_stage = 1
				tear_timer = 0.9
			else:
				var dir := to_t.normalized()
				velocity.x = lerp(velocity.x, dir.x * spd, 8.0 * delta)
				velocity.z = lerp(velocity.z, dir.z * spd, 8.0 * delta)
				_face_direction(dir, delta * 8.0)
				_animate_walk(delta, spd)
		1:
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
			_face_direction(-entry_window.global_basis.z, delta * 8.0)
			_animate_melee_swipe(delta)
			# Swipe through the window at a player standing right there
			var flat := Vector2(target_player.global_position.x - global_position.x, target_player.global_position.z - global_position.z).length()
			if flat < 1.9 and attack_cooldown <= 0.0:
				attack_cooldown = 1.2 / (0.55 if pain_drug_timer > 0.0 else 1.0)
				_play_3d_roar("zombie_attack_roar", randf_range(0.92, 1.12))
				_begin_melee()
			if entry_window.boards <= 0:
				entry_stage = 2
			else:
				tear_timer -= delta * (0.55 if pain_drug_timer > 0.0 else 1.0)
				if tear_timer <= 0.0:
					entry_window.tear_board()
					tear_timer = 0.75 if is_sprinter else 1.0
		2:
			# A board was rebuilt while climbing: back to tearing
			if entry_window.boards > 0 and global_position.distance_to(entry_window.attack_pos()) < 0.8:
				entry_stage = 1
				return
			var tgt2: Vector3 = entry_window.inside_pos()
			var to_t2 := tgt2 - global_position
			to_t2.y = 0.0
			if to_t2.length() < 0.5:
				entry_stage = 3
			else:
				var dir2 := to_t2.normalized()
				velocity.x = lerp(velocity.x, dir2.x * spd * 0.8, 10.0 * delta)
				velocity.z = lerp(velocity.z, dir2.z * spd * 0.8, 10.0 * delta)
				_face_direction(dir2, delta * 10.0)
				if rig:
					if rig.update(delta, "climb", spd):
						_step_count += 1
						_play_3d_footstep(_step_count)
				else:
					_animate_walk(delta, spd)


func _process_regular_zombie_ai(delta: float, speed_mult: float) -> void:
	if entry_window and entry_stage < 3:
		_process_window_entry(delta, speed_mult)
		return
	if not _sleeper_awake:
		if _lit_by_flashlight():
			_flash_lit_t += delta
		else:
			_flash_lit_t = maxf(0.0, _flash_lit_t - delta * 0.5)
		var dist_p := global_position.distance_to(target_player.global_position)
		var gunshot_near := target_player is PlayerController and (target_player as PlayerController).sensor_flash > 0.2 and dist_p < 13.0
		if dist_p < 5.2 or _flash_lit_t > 0.25 or gunshot_near:
			_wake_sleeper()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			return
	if buff_t > 0.0:
		buff_t -= delta
		speed_mult *= 1.15
	if aura_t > 0.0:
		aura_t -= delta
		speed_mult *= 1.0 + (aura_mult - 1.0) * 0.5
	if tier >= 2:
		_update_tier_fx(delta)
		_dodge_cd -= delta
		_lunge_cd -= delta
		_lunge_t -= delta
		if _dodge_t > 0.0:
			# Quick sidestep out of the line of fire
			_dodge_t -= delta
			velocity.x = _dodge_dir.x * 8.5
			velocity.z = _dodge_dir.z * 8.5
			_animate_walk(delta, 6.0)
			return
	if commander and commander.casting != "":
		# Winding up a skill: stands still and channels it
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		var look := target_player.global_position - global_position
		look.y = 0.0
		_face_direction(look.normalized(), delta * 8.0)
		_animate_melee_swipe(delta)
		return
	if order_t > 0.0:
		order_t -= delta
		if _process_order(delta, speed_mult):
			return
	if is_spitter:
		_process_spitter(delta, speed_mult)
		return
	var to_p := target_player.global_position - global_position
	var flat_dist := Vector2(to_p.x, to_p.z).length()

	if commander and flat_dist > 2.3 and commander.wants_distance():
		_commander_move(delta, speed_mult, to_p, flat_dist)
		return
	if flat_dist > 1.55:
		var move_dir := _get_nav_dir(target_player.global_position)
		if flat_dist < 6.0:
			move_dir = (move_dir + _separation_push() * 0.9).normalized()
		if tier >= 2:
			move_dir = _smart_dir(move_dir, flat_dist, delta)
			# Stalkers leap the last few metres
			if tier == 2 and _lunge_cd <= 0.0 and flat_dist > 3.2 and flat_dist < 6.5 and is_on_floor() and not is_crawler and not is_bloater:
				_lunge_cd = randf_range(5.0, 8.0)
				_lunge_t = 0.45
				velocity.y = 3.4
				_play_3d_roar("zombie_attack_roar", 1.25)
		var style := _style_mult(delta, flat_dist)
		if style <= 0.01:
			# Standing in the dark, watching: only the head twitches
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
			_face_direction(to_p.normalized(), delta * 3.0)
			if rig:
				rig.update(delta, "idle", 0.0)
			return
		var spd := base_speed * speed_mult * _stagger_mult() * (1.35 if order_kind == "flank_run" else 1.0) * (2.3 if _lunge_t > 0.0 else 1.0) * style
		velocity.x = lerp(velocity.x, move_dir.x * spd, 8.0 * delta)
		velocity.z = lerp(velocity.z, move_dir.z * spd, 8.0 * delta)
		_face_direction(move_dir, delta * 8.0)
		_animate_walk(delta, spd)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		_face_direction(to_p.normalized(), delta * 10.0)
		_animate_melee_swipe(delta)
		if attack_cooldown <= 0.0:
			attack_cooldown = 1.05 / (0.55 if pain_drug_timer > 0.0 else 1.0)
			_play_3d_roar("zombie_attack_roar", randf_range(0.92, 1.12))
			_begin_melee()


func _begin_melee() -> void:
	if rig:
		rig.start_attack(0.7 if not is_sprinter else 0.55)
		pending_hit_t = 0.31 if not is_sprinter else 0.25
	else:
		pending_hit_t = 0.01


func _resolve_melee_hit() -> void:
	if is_dead or stun_timer > 0.0 or not is_instance_valid(target_player):
		return
	var flat := Vector2(target_player.global_position.x - global_position.x, target_player.global_position.z - global_position.z).length()
	if flat < 2.15 and target_player.has_method("take_damage"):
		target_player.take_damage(base_damage * (0.45 if pain_drug_timer > 0.0 else 1.0) * (1.25 if buff_t > 0.0 else 1.0) * (aura_mult if aura_t > 0.0 else 1.0), global_position)
		if not is_boss and tier < 3:
			_taste_blood()


func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		var other := node as Node3D
		var off := global_position - other.global_position
		off.y = 0.0
		var d := off.length()
		if d > 0.01 and d < 1.3:
			push += off / d * (1.3 - d)
	return push


func _process_boss_ai(delta: float, speed_mult: float, rate_mult: float) -> void:
	var p_pos := target_player.global_position
	var to_p := p_pos - global_position
	var flat_dist := Vector2(to_p.x, to_p.z).length()
	var dir_to_p := Vector3(to_p.x, 0, to_p.z).normalized()

	match boss_type:
		"gun_zombie":
			_boss_gun_zombie(delta, flat_dist, dir_to_p, speed_mult, rate_mult)
		"gorilla":
			_boss_gorilla(delta, flat_dist, dir_to_p, speed_mult, rate_mult)
		"necromancer":
			_boss_necromancer(delta, flat_dist, dir_to_p, speed_mult, rate_mult)
		"juggernaut":
			_boss_juggernaut(delta, flat_dist, dir_to_p, speed_mult, rate_mult)
		"phantom":
			_boss_phantom(delta, flat_dist, dir_to_p, speed_mult, rate_mult)


# --- ROUND 1 BOSS: ARMED ZOMBIE WITH GUN ---
func _boss_gun_zombie(delta: float, dist: float, dir_to_p: Vector3, speed_mult: float, rate_mult: float) -> void:
	_face_direction(dir_to_p, delta * 9.0)
	strafe_switch_timer -= delta
	if strafe_switch_timer <= 0.0:
		strafe_dir = -strafe_dir
		strafe_switch_timer = randf_range(1.6, 3.0)

	match action_state:
		BossAction.CHASE:
			laser_beam.visible = false
			var desired_vel := Vector3.ZERO
			if dist > 13.5:
				desired_vel = _get_nav_dir(target_player.global_position) * base_speed * speed_mult
			elif dist < 6.5:
				desired_vel = -dir_to_p * base_speed * 0.75 * speed_mult
			else:
				var right := Vector3(-dir_to_p.z, 0, dir_to_p.x) * strafe_dir
				desired_vel = right * base_speed * 0.72 * speed_mult

			velocity.x = lerp(velocity.x, desired_vel.x, 7.0 * delta)
			velocity.z = lerp(velocity.z, desired_vel.z, 7.0 * delta)
			_animate_walk(delta, desired_vel.length())
			if node_arm_r:
				node_arm_r.rotation.x = lerp(node_arm_r.rotation.x, deg_to_rad(6.0), 8.0 * delta)

			if attack_cooldown <= 0.0 and dist < 26.0:
				action_state = BossAction.WINDUP
				# Aims laser before shooting! Slower aim lock if Pain-Drugged!
				state_timer = 0.68 / rate_mult

		BossAction.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if node_arm_r:
				node_arm_r.rotation.x = lerp(node_arm_r.rotation.x, 0.0, 12.0 * delta)
			_update_laser_sight()
			state_timer -= delta
			if state_timer <= 0.0:
				action_state = BossAction.FIRING
				burst_shots_left = 3
				burst_shot_delay = 0.0

		BossAction.FIRING:
			_update_laser_sight()
			burst_shot_delay -= delta
			if burst_shot_delay <= 0.0 and burst_shots_left > 0:
				burst_shots_left -= 1
				burst_shot_delay = 0.16 / rate_mult
				_fire_boss_bullet()
			if burst_shots_left <= 0 and burst_shot_delay <= 0.0:
				laser_beam.visible = false
				action_state = BossAction.CHASE
				attack_cooldown = 1.75 / rate_mult


func _update_laser_sight() -> void:
	if not laser_beam or not is_instance_valid(target_player):
		return
	laser_beam.visible = true
	var start_pos := global_position + Vector3(0, 1.52 * model_scale, 0) - global_transform.basis.z * 0.85
	var end_pos := target_player.global_position + Vector3(0.16, 1.15, 0)
	var mid := (start_pos + end_pos) * 0.5
	var length := start_pos.distance_to(end_pos)
	laser_beam.top_level = true
	laser_beam.global_position = mid
	laser_beam.look_at(end_pos, Vector3.UP)
	laser_beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	laser_beam.scale = Vector3(1.0, length, 1.0)


func _fire_boss_bullet() -> void:
	GameState.play_sfx("enemy_gunshot", -3.0, randf_range(0.94, 1.06))
	if node_arm_r:
		node_arm_r.rotation.x = deg_to_rad(14.0)

	var muzzle := global_position + Vector3(0, 1.52 * model_scale, 0) - global_transform.basis.z * 0.9
	var aim_pos := target_player.global_position + Vector3(0, 1.25, 0)
	# Slight spread (much wider if Pain-Drugged!)
	var spread := 0.16 if pain_drug_timer > 0.0 else 0.055
	var shot_dir := (aim_pos - muzzle).normalized()
	shot_dir = (shot_dir + Vector3(randf_range(-spread, spread), randf_range(-spread * 0.5, spread * 0.5), randf_range(-spread, spread))).normalized()

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + shot_dir * 45.0, 1 | 2)
	var hit := space.intersect_ray(q)
	var end_pt := muzzle + shot_dir * 40.0
	if not hit.is_empty():
		end_pt = hit.position
		if hit.collider == target_player and target_player.has_method("take_damage"):
			var dmg := base_damage * (0.45 if pain_drug_timer > 0.0 else 1.0)
			target_player.take_damage(dmg, global_position)

	_spawn_tracer(muzzle, end_pt, Color(1.0, 0.35, 0.12))


# --- ROUND 2 BOSS: TITAN GORILLA (High Endurance & Damage, Slow Telegraphed Attacks!) ---
func _boss_gorilla(delta: float, dist: float, dir_to_p: Vector3, speed_mult: float, rate_mult: float) -> void:
	match action_state:
		BossAction.CHASE:
			if telegraph_ring:
				telegraph_ring.visible = false
			var nav_dir := _get_nav_dir(target_player.global_position)
			var spd := base_speed * speed_mult
			velocity.x = lerp(velocity.x, nav_dir.x * spd, 6.0 * delta)
			velocity.z = lerp(velocity.z, nav_dir.z * spd, 6.0 * delta)
			_face_direction(nav_dir, delta * 6.5)
			_animate_gorilla_walk(delta, spd)

			if dist <= 4.65 and attack_cooldown <= 0.0:
				action_state = BossAction.WINDUP
				# Slow heavy 1.45s windup (even slower when Pain-Drugged!)
				state_timer = 1.45 / rate_mult
				slam_target_pos = global_position - global_transform.basis.z * 1.6
				slam_target_pos.y = global_position.y + 0.06
				GameState.play_sfx("monster_roar", -2.0, 0.72)

		BossAction.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
			_face_direction(dir_to_p, delta * 2.2) # Slow turn during windup so player can dodge!
			state_timer -= delta

			# Raise both giant gorilla crusher arms high overhead!
			if node_arm_l and node_arm_r:
				node_arm_l.rotation.x = lerp(node_arm_l.rotation.x, deg_to_rad(155.0), 5.5 * delta)
				node_arm_r.rotation.x = lerp(node_arm_r.rotation.x, deg_to_rad(155.0), 5.5 * delta)
			if node_torso:
				node_torso.rotation.x = lerp(node_torso.rotation.x, deg_to_rad(-18.0), 5.0 * delta)

			if telegraph_ring:
				telegraph_ring.visible = true
				telegraph_ring.global_position = Vector3(slam_target_pos.x, global_position.y + 0.08, slam_target_pos.z)
				var pulse := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.02)
				telegraph_ring.scale = Vector3(pulse, 1.0, pulse)

			if state_timer <= 0.0:
				_execute_gorilla_slam()
				action_state = BossAction.RECOVER
				state_timer = 0.85 / rate_mult

		BossAction.RECOVER:
			if telegraph_ring:
				telegraph_ring.visible = false
			if node_arm_l and node_arm_r:
				node_arm_l.rotation.x = lerp(node_arm_l.rotation.x, deg_to_rad(58.0), 16.0 * delta)
				node_arm_r.rotation.x = lerp(node_arm_r.rotation.x, deg_to_rad(58.0), 16.0 * delta)
			if node_torso:
				node_torso.rotation.x = lerp(node_torso.rotation.x, deg_to_rad(22.0), 12.0 * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				if node_torso:
					node_torso.rotation.x = 0.0
				action_state = BossAction.CHASE
				attack_cooldown = 1.65 / rate_mult


func _execute_gorilla_slam() -> void:
	GameState.play_sfx("gorilla_slam", 0.0, 0.92)
	_spawn_shockwave_ring(slam_target_pos, 5.0, Color(1.0, 0.36, 0.10))
	if is_instance_valid(target_player):
		var d := Vector2(target_player.global_position.x - slam_target_pos.x, target_player.global_position.z - slam_target_pos.z).length()
		if d <= 5.0 and not ZombieEnemy.is_airborne(target_player):
			var dmg := base_damage * (0.45 if pain_drug_timer > 0.0 else 1.0)
			if target_player.has_method("take_damage"):
				target_player.take_damage(dmg, slam_target_pos)
		if target_player.has_method("add_camera_shake"):
			target_player.add_camera_shake(0.45)


# --- ROUND 3 BOSS: BLIGHT NECROMANCER ---
func _boss_necromancer(delta: float, dist: float, dir_to_p: Vector3, speed_mult: float, rate_mult: float) -> void:
	_face_direction(dir_to_p, delta * 8.0)
	var desired := Vector3.ZERO
	if dist > 14.5:
		desired = _get_nav_dir(target_player.global_position) * base_speed * speed_mult
	elif dist < 7.5:
		desired = -dir_to_p * base_speed * 0.7 * speed_mult
	velocity.x = lerp(velocity.x, desired.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, desired.z, 6.0 * delta)
	_animate_walk(delta, desired.length())

	if attack_cooldown <= 0.0:
		attack_cooldown = 2.6 / rate_mult
		_launch_acid_pool(target_player.global_position)
		if randf() < 0.45:
			spawn_minion_requested.emit(global_position + Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2)))


func _launch_acid_pool(target_pos: Vector3) -> void:
	var dmg_per_tick := (base_damage * 0.35) * (0.45 if pain_drug_timer > 0.0 else 1.0)
	if Net.is_online():
		var ng := _net_game()
		if ng:
			ng.boss_fx(self, "acid", true, target_pos, dmg_per_tick)
	_spawn_acid_pool(target_pos, dmg_per_tick)


# Every machine shows the pool and hurts its own player standing in it.
func _spawn_acid_pool(target_pos: Vector3, dmg_per_tick: float, radius: float = 2.8) -> void:
	GameState.play_sfx("pain_drug", -2.0, 0.65)
	var pool := Area3D.new()
	pool.collision_layer = 0
	pool.collision_mask = 2
	var cs := CollisionShape3D.new()
	var cyl_s := CylinderShape3D.new()
	cyl_s.radius = radius
	cyl_s.height = 1.2
	cs.shape = cyl_s
	pool.add_child(cs)

	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.08
	disc.mesh = cm
	disc.material_override = MaterialLib.get_emissive(Color(0.24, 1.0, 0.16), 3.8, 0.52)
	pool.add_child(disc)

	get_parent().add_child(pool)
	pool.global_position = Vector3(target_pos.x, 0.06, target_pos.z)

	var victim := get_tree().get_first_node_in_group("player") as Node3D
	var tw := pool.create_tween()
	for i in range(10):
		tw.tween_callback(func():
			if is_instance_valid(pool) and is_instance_valid(victim):
				var flat := Vector2(victim.global_position.x - pool.global_position.x, victim.global_position.z - pool.global_position.z).length()
				# Jumping over the acid dodges it
				if flat < radius + 0.05 and not ZombieEnemy.is_airborne(victim):
					victim.take_damage(dmg_per_tick, pool.global_position)
		)
		tw.tween_interval(0.55)
	tw.tween_callback(pool.queue_free)


# --- ROUND 4 BOSS: PANZER JUGGERNAUT ---
func _boss_juggernaut(delta: float, dist: float, dir_to_p: Vector3, speed_mult: float, rate_mult: float) -> void:
	var nav_dir := _get_nav_dir(target_player.global_position)
	_face_direction(dir_to_p, delta * 5.5)
	if dist > 5.2:
		var spd := base_speed * speed_mult
		velocity.x = lerp(velocity.x, nav_dir.x * spd, 5.5 * delta)
		velocity.z = lerp(velocity.z, nav_dir.z * spd, 5.5 * delta)
		if flame_cone:
			flame_cone.visible = false
		_animate_walk(delta, spd)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if flame_cone:
			flame_cone.visible = true
		if attack_cooldown <= 0.0:
			attack_cooldown = 0.45 / rate_mult
			var dmg := (base_damage * 0.38) * (0.45 if pain_drug_timer > 0.0 else 1.0)
			if target_player.has_method("take_damage"):
				target_player.take_damage(dmg, global_position)


# --- ROUND 5+ BOSS: VOLT PHANTOM ---
func _boss_phantom(delta: float, dist: float, dir_to_p: Vector3, speed_mult: float, rate_mult: float) -> void:
	_face_direction(dir_to_p, delta * 11.0)
	if dist > 8.5 and attack_cooldown <= 0.0:
		# Phase blink half the distance!
		attack_cooldown = 2.4 / rate_mult
		_spawn_shockwave_ring(global_position, 2.0, Color(0.35, 0.75, 1.0))
		var blink_to := global_position.lerp(target_player.global_position, 0.55)
		global_position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, blink_to)
		_spawn_shockwave_ring(global_position, 2.0, Color(0.35, 0.75, 1.0))
		GameState.play_sfx("pain_drug", -1.0, 1.45)

	if dist > 2.1:
		var spd := base_speed * speed_mult
		var nav_dir := _get_nav_dir(target_player.global_position)
		velocity.x = lerp(velocity.x, nav_dir.x * spd, 9.0 * delta)
		velocity.z = lerp(velocity.z, nav_dir.z * spd, 9.0 * delta)
		_animate_walk(delta, spd)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		_animate_melee_swipe(delta)
		if attack_cooldown <= 0.0:
			attack_cooldown = 0.85 / rate_mult
			var dmg := base_damage * (0.45 if pain_drug_timer > 0.0 else 1.0)
			if target_player.has_method("take_damage"):
				target_player.take_damage(dmg, global_position)


# --- NAVIGATION & PROCEDURAL ANIMATION ---
func _get_nav_dir(dest: Vector3) -> Vector3:
	if nav_agent:
		nav_agent.target_position = dest
		if not nav_agent.is_navigation_finished():
			var next_pt := nav_agent.get_next_path_position()
			var d := next_pt - global_position
			d.y = 0.0
			if d.length_squared() > 0.001:
				return d.normalized()
	var fallback := dest - global_position
	fallback.y = 0.0
	return fallback.normalized() if fallback.length_squared() > 0.001 else Vector3.FORWARD


func _face_direction(dir: Vector3, weight: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


func _stagger_mult() -> float:
	return 1.0 - 0.55 * rig.stagger if rig else 1.0


func _animate_walk(delta: float, spd: float) -> void:
	if rig:
		var mode := "walk"
		if is_crawler:
			mode = "crawl"
		elif (is_sprinter and spd > 3.0) or spd > 3.9:
			mode = "run" # late-round walkers break into a jog
		# Drive the gait from the real ground speed so planted feet don't slide
		var ground := Vector2(velocity.x, velocity.z).length() / maxf(0.1, model_scale)
		var local_vel: Vector3 = (global_basis.inverse() * velocity) / maxf(0.1, model_scale)
		var anim_speed: float = ground if mode != "crawl" else spd
		if rig.update(delta, mode, anim_speed, {"vel": local_vel, "yaw_rate": _yaw_rate}):
			_step_count += 1
			if not is_crawler:
				_play_3d_footstep(_step_count)
		return
	anim_phase += delta * maxf(2.0, spd * 2.4)
	var cur_half := int(floor(anim_phase / PI))
	if cur_half != _last_step_half:
		_last_step_half = cur_half
		if spd > 0.45:
			_play_3d_footstep(cur_half)
	var swing := sin(anim_phase) * 0.52
	if node_leg_l:
		node_leg_l.rotation.x = swing
	if node_leg_r:
		node_leg_r.rotation.x = -swing
	if node_arm_l and boss_type != "gun_zombie":
		node_arm_l.rotation.x = deg_to_rad(8.0) - swing * 0.25
	if node_arm_r and boss_type != "gun_zombie":
		node_arm_r.rotation.x = deg_to_rad(8.0) + swing * 0.25
	if node_torso:
		node_torso.rotation.z = sin(anim_phase * 0.5) * 0.06


func _animate_gorilla_walk(delta: float, spd: float) -> void:
	anim_phase += delta * maxf(2.0, spd * 2.1)
	var cur_half := int(floor(anim_phase / PI))
	if cur_half != _last_step_half:
		_last_step_half = cur_half
		if spd > 0.45:
			_play_3d_footstep(cur_half)
	var swing := sin(anim_phase) * 0.45
	if node_leg_l:
		node_leg_l.rotation.x = swing
	if node_leg_r:
		node_leg_r.rotation.x = -swing
	if node_arm_l:
		node_arm_l.rotation.x = -swing * 0.55
	if node_arm_r:
		node_arm_r.rotation.x = swing * 0.55
	if node_torso:
		node_torso.rotation.x = lerp(node_torso.rotation.x, deg_to_rad(10.0), 6.0 * delta)


func _animate_melee_swipe(delta: float) -> void:
	if rig:
		if not rig.is_attacking() and entry_stage == 1:
			rig.start_attack(0.9) # clawing at the boards
		rig.update(delta, "crawl" if is_crawler else "idle", 0.0)
		return
	anim_phase += delta * 9.0
	var swipe := sin(anim_phase) * 0.85
	if node_arm_l:
		node_arm_l.rotation.x = swipe
	if node_arm_r:
		node_arm_r.rotation.x = -swipe


func _animate_stunned(delta: float) -> void:
	if rig:
		rig.update(delta, "crawl" if is_crawler else "stunned", 0.0)
		return
	anim_phase += delta * 4.5
	if node_torso:
		node_torso.rotation.x = lerp(node_torso.rotation.x, deg_to_rad(24.0), 8.0 * delta)
		node_torso.rotation.z = sin(anim_phase) * 0.14
	if node_head:
		node_head.rotation.z = cos(anim_phase) * 0.22


# --- DAMAGE, HEADSHOTS, STUN & PAIN DRUG ---
func take_damage(raw_amount: float, hit_pos: Vector3 = Vector3.ZERO, ignore_armor: bool = false, kind: String = "bullet") -> Dictionary:
	if is_dead:
		return {"dealt": 0.0, "headshot": false, "killed": false}
	if not _sleeper_awake:
		_wake_sleeper()
	_pre_hit_hp = hp
	last_damage_kind = kind
	last_hit_point = hit_pos if hit_pos != Vector3.ZERO else global_position + Vector3(0, 1.1 * model_scale, 0)

	var is_headshot := false
	if hit_pos != Vector3.ZERO and hit_pos.y >= head_y() and not is_crawler:
		is_headshot = true

	var dmg := raw_amount
	# Panzer chest core weakpoint bonus
	if boss_type == "juggernaut" and hit_pos != Vector3.ZERO:
		var core_pos := global_position + Vector3(0, 1.55 * model_scale, 0) - global_transform.basis.z * 0.35
		if hit_pos.distance_to(core_pos) < 0.52:
			is_headshot = true
			ignore_armor = true

	# Riot shield: frontal body shots barely scratch it
	if is_shielded and not is_headshot and (kind == "bullet" or kind == "melee"):
		var to_s := _shooter_pos() - global_position
		to_s.y = 0.0
		if to_s.length() > 0.1 and (-global_basis.z).dot(to_s.normalized()) > 0.45:
			dmg *= 0.15
			if hit_pos != Vector3.ZERO:
				FX.impact(hit_pos, to_s.normalized())
				GameState.play_sfx("ricochet", -8.0, randf_range(0.9, 1.15))

	# Pain Drug strips Boss Endurance AND grants +60% bonus vulnerability!
	if pain_drug_timer > 0.0:
		dmg *= 1.60
	elif not ignore_armor and endurance > 0.0:
		dmg *= (1.0 - endurance)

	# A commander with bodyguards near takes far less damage: kill them first
	if shield_on and tier >= 3:
		dmg *= TIER_GUARD_DR[tier]
		if _shield_hint_cd <= 0.0:
			_shield_hint_cd = 0.2
			GameState.play_sfx("ricochet", -9.0, randf_range(1.25, 1.45))
		var now := Time.get_ticks_msec() / 1000.0
		if now - _shield_tip_t > 25.0 and (net_puppet or not Net.is_online() or _net_attacker == Net.my_id()):
			_shield_tip_t = now
			var lp := get_tree().get_first_node_in_group("player")
			if lp and lp.has_signal("status_banner_requested"):
				lp.status_banner_requested.emit("BODYGUARDS ARE SHIELDING %s — KILL THEM FIRST" % commander_name, TIER_COLORS[tier])

	# Insta-Kill power-up: any hit drops a regular zombie.
	if not is_boss and GameState.is_powerup_active("insta_kill"):
		dmg = maxf(dmg, hp)

	if net_puppet:
		return _puppet_damage(dmg, raw_amount, hit_pos, ignore_armor, kind, is_headshot)

	if Net.is_online():
		dmg_by[_net_attacker] = float(dmg_by.get(_net_attacker, 0.0)) + minf(dmg, hp)
	hp = maxf(0.0, hp - dmg)
	if is_headshot and commander and hp > 0.0:
		commander.on_headshot()
	if tier >= 2 and not is_boss and hp > 0.0 and _dodge_cd <= 0.0 and kind == "bullet" and stun_timer <= 0.0 and entry_stage >= 3 \
			and order_kind != "feast" and order_kind != "build" and not is_crawler and not is_bloater and (commander == null or commander.casting == ""):
		_start_dodge()
	if is_boss:
		boss_damaged.emit(self)
	_hit_feedback(hit_pos, dmg, is_headshot, kind)
	if not is_boss and dmg >= 48.0 and kind != "electric":
		velocity += -last_hit_from * clampf(dmg / 52.0, 1.3, 5.2)
	if Net.is_online() and net_id > 0:
		var ng := _net_game()
		if ng:
			ng.zombie_hit(self, hit_pos, dmg, _net_attacker)

	if hp <= 0.0:
		_die(is_headshot)
		return {"dealt": dmg, "headshot": is_headshot, "killed": true}

	return {"dealt": dmg, "headshot": is_headshot, "killed": false}


# Flash, blood, flesh sound and the rig's flinch for a hit (no HP change).
func _hit_feedback(hit_pos: Vector3, dmg: float, is_headshot: bool, kind: String) -> void:
	if net_puppet or not Net.is_online() or _net_attacker == Net.my_id():
		FX.damage_number(self, hit_pos if hit_pos != Vector3.ZERO else global_position + Vector3(0, 1.6 * model_scale, 0), minf(dmg, _pre_hit_hp), is_headshot, hp <= 0.0)
	_set_flash(true)
	hit_flash_timer = 0.07
	if hit_pos != Vector3.ZERO:
		_spawn_blood(hit_pos, is_headshot)
		if randf() < 0.3:
			FX.blood_decal(Vector3(hit_pos.x + randf_range(-0.4, 0.4), global_position.y + 0.02, hit_pos.z + randf_range(-0.4, 0.4)), Vector3.UP, 0.55)
	if _flesh_sfx_cd <= 0.0 and kind != "explosive":
		_flesh_sfx_cd = 0.07
		GameState.play_sfx("flesh_hit", -9.0, randf_range(0.85, 1.15))

	# Where did it come from? (the shooter, or the hit point for blasts)
	var src := hit_pos
	var shooter: Node3D = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(shooter) and kind != "explosive":
		src = shooter.global_position
	var away := global_position - src
	away.y = 0.0
	last_hit_from = -away.normalized() if away.length_squared() > 0.001 else -global_basis.z
	last_damage_amount = dmg
	if rig and hp > dmg:
		var local_from := global_basis.inverse() * last_hit_from
		var region := _hit_region(hit_pos) if hit_pos != Vector3.ZERO and kind != "explosive" else "torso"
		rig.hit(clampf(dmg / 60.0 * 1.35, 0.4, 2.7), local_from, region)


# Which part of the body a hit landed on (model space, scale-independent).
func _hit_region(p: Vector3) -> String:
	var l: Vector3 = (global_basis.inverse() * (p - global_position)) / maxf(0.1, model_scale)
	if l.y >= 1.5:
		return "head"
	if l.y < 0.92:
		return "leg_l" if l.x < 0.0 else "leg_r"
	if absf(l.x) > 0.2 and l.y > 1.0:
		return "arm_l" if l.x < 0.0 else "arm_r"
	return "torso"


# Bosses shrug off stuns; only a special operator ability (boss_ok) holds them.
func apply_stun(duration: float, boss_ok: bool = false) -> void:
	if is_dead or (is_boss and not boss_ok):
		return
	if net_puppet:
		var ng := _net_game()
		if ng:
			ng.forward_status(self, "boss_stun" if boss_ok else "stun", duration)
		return
	stun_timer = maxf(stun_timer, duration)
	# Interrupt any Boss windup / laser lock immediately!
	if action_state == BossAction.WINDUP or action_state == BossAction.FIRING:
		action_state = BossAction.CHASE
		attack_cooldown = 1.1
	if is_boss:
		boss_damaged.emit(self)


func apply_pain_drug(duration: float) -> void:
	if is_dead:
		return
	if net_puppet:
		GameState.play_sfx("pain_drug", -1.0, 1.0)
		var ng := _net_game()
		if ng:
			ng.forward_status(self, "drug", duration)
		return
	pain_drug_duration = duration
	pain_drug_timer = maxf(pain_drug_timer, duration)
	GameState.play_sfx("pain_drug", -1.0, 1.0)
	if is_boss:
		boss_damaged.emit(self)


func _die(was_headshot: bool) -> void:
	is_dead = true
	collision_layer = 0
	collision_mask = 0
	if laser_beam:
		laser_beam.visible = false
	if telegraph_ring:
		telegraph_ring.visible = false
	if flame_cone:
		flame_cone.visible = false
	stun_halo.visible = false
	drug_aura.visible = false
	drug_light.visible = false
	_set_flash(false)
	for n in [_shield_mesh, _aura_ring, _tier_label, _tier_light]:
		if n:
			n.visible = false
	for eye in _eye_nodes:
		if is_instance_valid(eye):
			eye.visible = false
	if is_instance_valid(_warn_node):
		_warn_node.queue_free()

	died.emit(self, was_headshot)
	_net_notify_death(was_headshot)

	# Death gurgle + blood pool
	if roar_audio_3d:
		var st := GameState.get_sfx_stream("zombie_death")
		if st and not is_boss:
			roar_audio_3d.stream = st
			roar_audio_3d.pitch_scale = randf_range(0.85, 1.15)
			roar_audio_3d.play()
	FX.blood_decal(Vector3(global_position.x, global_position.y + 0.02, global_position.z), Vector3.UP, 1.6 if is_boss else 1.2)

	if rig == null:
		if was_headshot and node_head:
			node_head.scale = Vector3.ZERO
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(visual_root, "rotation:x", deg_to_rad(-82.0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual_root, "position:y", 0.16, 0.34)
		tw.chain().tween_interval(1.0)
		tw.tween_property(visual_root, "position:y", -1.4, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
		return
	_rig_death(was_headshot)


func _rig_death(was_headshot: bool) -> void:
	var center := global_position + Vector3(0, 1.1 * model_scale, 0)
	# Bloaters burst into a toxic cloud
	if is_bloater:
		visual_root.visible = false
		FX.gore_burst(center, 12, 5.0)
		FX.splat(Vector3(global_position.x, global_position.y + 0.02, global_position.z), 2.6, Color(0.45, 0.75, 0.15, 0.9))
		GameState.play_sfx("bloater_pop", 0.0, randf_range(0.92, 1.05))
		var gas: Node3D = GasCloudScript.new()
		get_tree().current_scene.add_child(gas)
		gas.global_position = global_position
		if is_instance_valid(target_player) and target_player.has_method("add_camera_shake"):
			if global_position.distance_to(target_player.global_position) < 8.0:
				target_player.add_camera_shake(0.35)
		create_tween().tween_callback(queue_free).set_delay(2.0)
		return
	# Explosions blow regular zombies apart
	if last_damage_kind == "explosive" and not is_crawler and randf() < 0.75:
		visual_root.visible = false
		FX.gore_burst(center, 10, 6.5)
		GameState.play_sfx("gore_splat", -2.0, randf_range(0.85, 1.1))
		create_tween().tween_callback(queue_free).set_delay(0.6)
		return

	if was_headshot and rig.nodes.has("Head"):
		var head: Node3D = rig.nodes["Head"]
		var hp_pos := head.global_position + Vector3(0, 0.15, 0)
		head.scale = Vector3.ONE * 0.001
		FX.gore_burst(hp_pos, 5, 3.5)
		GameState.play_sfx("gore_splat", -5.0, randf_range(1.0, 1.25))

	if last_damage_kind == "electric":
		# Flickering arc glow while the body convulses, then charred
		var zap := MaterialLib.get_emissive(Color(0.45, 0.75, 1.0), 1.1, 0.45)
		var ztw := create_tween()
		for k in range(5):
			ztw.tween_callback(func():
				for m in _meshes:
					if is_instance_valid(m):
						m.material_overlay = zap if k % 2 == 0 else null
			)
			ztw.tween_interval(0.12)
		ztw.tween_callback(func():
			for m in _meshes:
				if is_instance_valid(m):
					m.material_overlay = MaterialLib.get_emissive(Color(0.05, 0.04, 0.03), 0.0, 0.6)
		)

	if _try_ragdoll():
		return

	var kind := "crumple"
	var tw := create_tween()
	tw.set_parallel(true)
	if is_crawler:
		kind = "flat"
		tw.tween_property(visual_root, "position:y", -0.05, 0.3)
	else:
		# Shot from the front falls backward, from behind falls forward
		var local_from := global_basis.inverse() * last_hit_from
		var r := randf()
		if last_damage_kind == "electric" or r < 0.25:
			kind = "crumple"
		elif local_from.z < 0.0:
			kind = "back"
		else:
			kind = "forward"
		var fall_time := randf_range(0.5, 0.7)
		match kind:
			"back":
				tw.tween_property(visual_root, "rotation:x", deg_to_rad(84.0), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			"forward":
				tw.tween_property(visual_root, "rotation:x", deg_to_rad(-84.0), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_:
				var side := -1.0 if randf() < 0.5 else 1.0
				tw.tween_property(visual_root, "position:y", -0.45, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(visual_root, "rotation:z", deg_to_rad(80.0) * side, 0.45).set_delay(0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if kind != "crumple":
			tw.tween_property(visual_root, "position:y", 0.14, fall_time)
			tw.tween_property(visual_root, "rotation:y", randf_range(-0.4, 0.4), fall_time)
	rig.set_dead_pose(kind)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(visual_root, "position:y", -1.2, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


# Hands the body to physics: the killing shot knocks it over, explosions
# throw it, electricity makes it spasm. Falls back to the scripted death when
# too many ragdolls are already active.
func _try_ragdoll() -> bool:
	if rig == null or not RagdollScript.can_spawn():
		return false
	var rd = RagdollScript.new()
	get_tree().current_scene.add_child(rd)
	var shot_dir := -last_hit_from
	shot_dir.y = 0.0
	shot_dir = shot_dir.normalized() if shot_dir.length_squared() > 0.001 else global_basis.z
	var force := clampf(last_damage_amount / 35.0, 2.5, 16.0)
	var impulse := (shot_dir * force + Vector3.UP * force * 0.15) * 2.2
	var blast_center := Vector3.INF
	var blast := 0.0
	if last_damage_kind == "explosive":
		blast_center = last_hit_point - Vector3(0, 0.6, 0)
		blast = 5.5
		impulse = Vector3.ZERO
	var shock := 0.7 if last_damage_kind == "electric" else 0.0
	var base_vel := Vector3(velocity.x, 0.0, velocity.z) * 0.8
	if not rd.build(rig.nodes, global_basis, model_scale, base_vel, last_hit_point, impulse, blast_center, blast, shock):
		rd.queue_free()
		return false
	ragdolled = true
	# The skinned mesh stays under this node while the ragdoll drives its
	# proxies, so stay alive until the ragdoll has tumbled and sunk (3.4+1.4s).
	create_tween().tween_callback(queue_free).set_delay(5.1)
	return true


var _flash_saved: Dictionary = {} # mesh -> overlay to restore after the flash


func _set_flash(on: bool) -> void:
	if on and _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1.0, 0.85, 0.8, 0.55)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in _meshes:
		if not is_instance_valid(m):
			continue
		if on:
			if not _flash_saved.has(m):
				_flash_saved[m] = m.material_overlay
			m.material_overlay = _flash_mat
		elif m.material_overlay == _flash_mat:
			# Restore the tier glow / spitter tint, unless something else
			# already replaced the overlay while the flash was up.
			m.material_overlay = _flash_saved.get(m)
			_flash_saved.erase(m)


func _spawn_blood(pt: Vector3, big: bool) -> void:
	if _blood_mat == null:
		_blood_mat = StandardMaterial3D.new()
		_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blood_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_blood_mat.albedo_color = Color(0.55, 0.02, 0.02)
		_blood_mat.vertex_color_use_as_albedo = true
		if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
			_blood_mat.albedo_texture = load("res://assets/textures/soft_particle.png")
			_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 18 if big else 8
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -14.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5 if big else 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = _blood_mat
	p.mesh = quad
	get_tree().current_scene.add_child(p)
	p.global_position = pt
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_tracer(from_pt: Vector3, to_pt: Vector3, col: Color) -> void:
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = from_pt.distance_to(to_pt)
	beam.mesh = cm
	beam.material_override = MaterialLib.get_emissive(col, 6.0, 0.85)
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from_pt + to_pt) * 0.5
	beam.look_at(to_pt, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	var tw := beam.create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(beam.queue_free)


func _spawn_shockwave_ring(center: Vector3, max_radius: float, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.72
	tm.outer_radius = 1.0
	ring.mesh = tm
	ring.material_override = MaterialLib.get_emissive(col, 6.0, 0.85)
	get_tree().current_scene.add_child(ring)
	ring.global_position = Vector3(center.x, center.y + 0.12, center.z)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(max_radius, 1.0, max_radius), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free).set_delay(0.33)


# ---------------------------------------------------------------------------
# CO-OP
# ---------------------------------------------------------------------------
func _net_game() -> Node:
	if not is_instance_valid(_ng_cache):
		_ng_cache = get_tree().get_first_node_in_group("net_game")
	return _ng_cache


func _valid_target(t) -> bool:
	return is_instance_valid(t) and t.has_method("is_valid_target") and t.is_valid_target()


# Host: go after the closest player who is still standing.
func _retarget() -> void:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("net_players"):
		if not p.is_valid_target():
			continue
		var d := global_position.distance_squared_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	if best:
		target_player = best


func _net_notify_death(was_headshot: bool) -> void:
	if Net.is_online() and not net_puppet and net_id > 0:
		var ng := _net_game()
		if ng:
			ng.zombie_died(self, was_headshot)


# Host: animation state packed into one byte for the snapshot.
func net_anim_byte() -> int:
	var m := 2 # idle
	if rig:
		m = maxi(0, NET_MODES.find(rig.last_mode))
		if rig.attack_t >= 0.0:
			m |= 16 | ((int(rig.attack_kind) & 3) << 5)
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		m = 0
	if stun_timer > 0.0:
		m |= 128
	if shield_on:
		m |= 8
	return m


# Client: a new snapshot state for this puppet.
func net_push(t: float, pos: Vector3, yaw: float, spd: float, anim: int, hp_frac: float) -> void:
	if net_buf == null:
		net_buf = NetBuffer.new()
	net_buf.push(t, pos, yaw)
	_net_anim = anim
	_net_speed = spd
	var before := hp
	var snap_hp := hp_frac * max_hp
	# Our own recent hits haven't reached the host yet: don't undo them
	if Net.local_time() - _net_hit_t > 0.6:
		hp = snap_hp
	else:
		hp = minf(hp, snap_hp)
	if is_boss and absf(before - hp) > 0.01:
		boss_damaged.emit(self)


# Client: our shot hit this zombie. Feel it now, tell the host.
func _puppet_damage(dmg: float, raw_amount: float, hit_pos: Vector3, ignore_armor: bool, kind: String, is_headshot: bool) -> Dictionary:
	hp = maxf(0.0, hp - dmg)
	_net_hit_t = Net.local_time()
	if is_boss:
		boss_damaged.emit(self)
	_hit_feedback(hit_pos, dmg, is_headshot, kind)
	var killed := hp <= 0.0
	var ng := _net_game()
	if ng:
		ng.forward_damage(self, raw_amount, hit_pos, ignore_armor, kind, killed, is_headshot)
	if killed:
		_die(is_headshot)
	return {"dealt": dmg, "headshot": is_headshot, "killed": killed}


# Client: someone else's hit, as reported by the host (cosmetic only).
func net_remote_hit(hit_pos: Vector3, dmg: float) -> void:
	if is_dead:
		return
	_hit_feedback(hit_pos, dmg, false, "bullet")


# Client: the host says this zombie died.
func net_remote_die(was_headshot: bool, point: Vector3, from_dir: Vector3, dmg: float, kind: String) -> void:
	if is_dead:
		return
	last_hit_point = point
	last_hit_from = from_dir
	last_damage_amount = dmg
	last_damage_kind = kind
	hp = 0.0
	_die(was_headshot)


func _puppet_process(delta: float) -> void:
	_flesh_sfx_cd = maxf(0.0, _flesh_sfx_cd - delta)
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			_set_flash(false)
	if net_buf == null or not net_buf.has_data():
		return
	var s: Array = net_buf.sample(Net.host_time() - NetGame.render_delay)
	global_position = s[0]
	rotation.y = s[1]
	velocity = s[2]
	_yaw_rate = lerpf(_yaw_rate, wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001), clampf(10.0 * delta, 0.0, 1.0))
	_prev_yaw = rotation.y
	if telegraph_ring and telegraph_ring.visible:
		var pulse := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.02)
		telegraph_ring.scale = Vector3(pulse, 1.0, pulse)
	var stunned := (_net_anim & 128) != 0
	if tier >= 3:
		shield_on = (_net_anim & 8) != 0
		_update_tier_fx(delta)
	if stun_halo:
		stun_halo.visible = stunned
		if stunned:
			stun_halo.rotate_y(delta * 5.8)

	roar_timer -= delta
	if roar_timer <= 0.0:
		roar_timer = randf_range(5.0, 10.0)
		var lp := get_tree().get_first_node_in_group("player") as Node3D
		if is_boss:
			_play_3d_roar("boss_roar", randf_range(0.88, 1.06))
		elif lp and global_position.distance_to(lp.global_position) <= 24.0 and GameState.request_zombie_vocal(1.05):
			var clips := ["zombie_roar_1", "zombie_roar_2", "zombie_groan"]
			_play_3d_roar(clips[randi() % clips.size()], randf_range(0.88, 1.14))

	if rig:
		var attacking := (_net_anim & 16) != 0
		if attacking and not _net_attack_seen:
			rig.start_attack(rig.attack_len)
			rig.attack_kind = (_net_anim >> 5) & 3
		_net_attack_seen = attacking
		var mode: String = NET_MODES[clampi(_net_anim & 7, 0, NET_MODES.size() - 1)]
		if mode == "walk" or mode == "run":
			_animate_walk(delta, _net_speed)
		else:
			rig.update(delta, mode, _net_speed, {"vel": global_basis.inverse() * velocity, "yaw_rate": _yaw_rate})
	elif stunned:
		_animate_stunned(delta)
	elif boss_type == "gorilla":
		_animate_gorilla_walk(delta, _net_speed)
	else:
		_animate_walk(delta, _net_speed)


# Host: tell clients when the boss's warning ring / flame cone shows.
var _fx_ring_sent: bool = false
var _fx_flame_sent: bool = false


func _net_sync_fx() -> void:
	var ng := _net_game()
	if ng == null:
		return
	var ring_on := telegraph_ring != null and telegraph_ring.visible
	if ring_on != _fx_ring_sent:
		_fx_ring_sent = ring_on
		ng.boss_fx(self, "ring", ring_on, telegraph_ring.global_position if ring_on else Vector3.ZERO, 0.0)
	var flame_on := flame_cone != null and flame_cone.visible
	if flame_on != _fx_flame_sent:
		_fx_flame_sent = flame_on
		ng.boss_fx(self, "flame", flame_on, Vector3.ZERO, 0.0)


# Client: the host's boss effect, mirrored.
func net_boss_fx(kind: String, on: bool, pos: Vector3, amount: float) -> void:
	match kind:
		"ring":
			if telegraph_ring:
				telegraph_ring.visible = on
				if on:
					telegraph_ring.global_position = pos
		"flame":
			if flame_cone:
				flame_cone.visible = on
		"acid":
			_spawn_acid_pool(pos, amount)
		"spit":
			_spit_visual(pos, amount)
		_:
			_commander_fx_local(kind, pos, amount)


# ---------------------------------------------------------------------------
# SPECIALS
# ---------------------------------------------------------------------------
func _shooter_pos() -> Vector3:
	if Net.is_online() and not net_puppet and _net_attacker != Net.my_id():
		var ng := _net_game()
		if ng and ng.avatars.has(_net_attacker):
			return (ng.avatars[_net_attacker] as Node3D).global_position
	var lp := get_tree().get_first_node_in_group("player") as Node3D
	return lp.global_position if lp else global_position - global_basis.z


func _add_riot_shield() -> void:
	var holder: Node3D = visual_root
	if rig and rig.nodes.has("Chest"):
		holder = rig.nodes["Chest"]
	var shield := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 1.0, 0.05)
	shield.mesh = bm
	shield.material_override = MaterialLib.get_pbr("rusted_metal", 1.6, Color(0.38, 0.4, 0.44), 0.7, 0.6, false)
	holder.add_child(shield)
	shield.position = Vector3(0.0, -0.12, -0.3)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.42, 0.12, 0.02)
	visor.mesh = vm
	visor.material_override = MaterialLib.get_emissive(Color(0.25, 0.45, 0.6), 0.6, 0.6)
	shield.add_child(visor)
	visor.position = Vector3(0, 0.3, -0.03)


func _tint_spitter() -> void:
	for m in _meshes:
		m.material_overlay = MaterialLib.get_emissive(Color(0.35, 1.0, 0.2), 0.35, 0.18)
	_spitter_tinted = true


# Keeps its distance and lobs acid at the target.
func _process_spitter(delta: float, speed_mult: float) -> void:
	var to_p := target_player.global_position - global_position
	var flat := Vector2(to_p.x, to_p.z).length()
	var move := Vector3.ZERO
	if flat > 11.0:
		move = _get_nav_dir(target_player.global_position)
	elif flat < 6.0:
		move = Vector3(-to_p.x, 0.0, -to_p.z).normalized()
	var spd := base_speed * speed_mult * 0.8 * _stagger_mult()
	velocity.x = lerp(velocity.x, move.x * spd, 6.0 * delta)
	velocity.z = lerp(velocity.z, move.z * spd, 6.0 * delta)
	_face_direction(Vector3(to_p.x, 0.0, to_p.z).normalized(), delta * 8.0)
	_animate_walk(delta, move.length() * spd)
	if attack_cooldown <= 0.0 and flat < 16.0:
		attack_cooldown = 3.4 / speed_mult
		_play_3d_roar("zombie_attack_roar", 1.3)
		var dmg := base_damage * 0.22
		var tp := target_player.global_position
		if Net.is_online():
			var ng := _net_game()
			if ng:
				ng.boss_fx(self, "spit", true, tp, dmg)
		_spit_visual(tp, dmg)


func _spit_visual(target_pos: Vector3, dmg: float, radius: float = 1.6) -> void:
	var glob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	glob.mesh = sm
	glob.material_override = MaterialLib.get_emissive(Color(0.35, 1.0, 0.2), 4.0)
	get_tree().current_scene.add_child(glob)
	var from := global_position + Vector3(0, 1.6 * model_scale, 0)
	glob.global_position = from
	var tw := glob.create_tween()
	tw.tween_method(func(f: float):
		if is_instance_valid(glob):
			glob.global_position = from.lerp(target_pos, f) + Vector3(0, sin(f * PI) * 2.2, 0)
	, 0.0, 1.0, 0.75)
	tw.tween_callback(func():
		glob.queue_free()
		if is_instance_valid(self) and is_inside_tree():
			_spawn_acid_pool(target_pos, dmg, radius)
	)



# ---------------------------------------------------------------------------
# TIERS
# ---------------------------------------------------------------------------
# Sets the tier: stats scale on the host; everyone sees the glow and the name.
func apply_tier(t: int, scale_stats: bool = true) -> void:
	t = clampi(t, 1, 5)
	if scale_stats and not is_boss:
		var ratio := hp / maxf(1.0, max_hp)
		max_hp = max_hp / TIER_HP[tier] * TIER_HP[t]
		hp = maxf(1.0, max_hp * maxf(ratio, 0.6 if t > tier else ratio))
		base_damage = base_damage / TIER_DMG[tier] * TIER_DMG[t]
		base_speed = base_speed / TIER_SPEED[tier] * TIER_SPEED[t]
		point_reward = 60 + 120 * (t - 1) * (t - 1)
	tier = t
	if tier >= 3 and not is_boss:
		add_to_group("commanders")
		if not net_puppet:
			if commander_name == "":
				commander_name = CommanderBrain.random_name()
			if stolen_skill == "":
				stolen_skill = CommanderBrain.random_skill()
	# Clients must know the tier before the brain says its first words
	if Net.is_online() and not net_puppet and net_id > 0:
		var ng := _net_game()
		if ng:
			ng.zombie_tier(self, tier, commander_name, stolen_skill)
	if tier >= 3 and commander == null and not is_boss:
		var brain: Node = CommanderBrain.new()
		brain.name = "Commander"
		add_child(brain)
		commander = brain
		brain.setup(self)
	_tier_visuals()


func _tier_visuals() -> void:
	if tier <= 1:
		return
	var col: Color = TIER_COLORS[tier]
	var grow := 1.0 + 0.07 * float(tier - 1)
	if visual_root:
		if _base_vscale == Vector3.ZERO:
			_base_vscale = visual_root.scale
		visual_root.scale = _base_vscale * grow
	if tier == 2:
		# Stalkers lurk without neon outlines; only crimson pinprick eyes give them away
		var eye_mat := MaterialLib.get_emissive(Color(1.0, 0.14, 0.10), 1.45)
		for eye in _eye_nodes:
			if is_instance_valid(eye):
				eye.material_override = eye_mat
		return
	for m in _meshes:
		if is_instance_valid(m) and not _spitter_tinted: # spitters keep their green
			m.material_overlay = MaterialLib.get_rim(col, 0.3 + 0.14 * float(tier - 2), 3.0)
	if _tier_light == null:
		# Lights the ground around it in its tier colour, not its own body
		# (the body keeps its look and gets a glowing outline instead)
		_tier_light = OmniLight3D.new()
		_tier_light.omni_range = 3.2
		_tier_light.light_cull_mask = 1
		_tier_light.position = Vector3(0, 0.7 * model_scale, 0)
		add_child(_tier_light)
	_tier_light.light_color = col
	_tier_light.light_energy = 0.35 + 0.18 * float(tier)
	if is_boss:
		return
	if _tier_label == null:
		_tier_label = Label3D.new()
		_tier_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tier_label.no_depth_test = false
		_tier_label.font_size = 40
		_tier_label.outline_size = 10
		_tier_label.pixel_size = 0.004
		add_child(_tier_label)
	_tier_label.position = Vector3(0, 2.45 * model_scale * grow, 0)
	_tier_label.modulate = col
	var title: String = commander_name if commander_name != "" else "COMMANDER"
	_tier_label.text = "%s%s\n%s %s" % ["NEMESIS\n" if is_nemesis else "", title, "★".repeat(tier), TIER_NAMES[tier]]
	# The ring on the ground shows how far its aura reaches
	if _aura_ring == null:
		_aura_ring = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * CommanderBrain.AURA_R * 2.0
		_aura_ring.mesh = pm
		_aura_ring.position.y = 0.05
		_aura_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura_ring.material_override = MaterialLib.new_warn_zone(Color(col.r, col.g, col.b, 0.45), 0.012, 0.0)
		add_child(_aura_ring)
	(_aura_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col.r, col.g, col.b, 0.45))
	# Bubble shown while bodyguards stand near (damage shield)
	if _shield_mesh == null:
		_shield_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.15
		sm.height = 2.5
		sm.radial_segments = 20
		sm.rings = 10
		_shield_mesh.mesh = sm
		_shield_mesh.position.y = 1.05 * model_scale
		_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shield_mesh.visible = false
		add_child(_shield_mesh)
	_shield_mesh.material_override = MaterialLib.get_rim(col, 1.7, 1.7, 0.05, 1.0)
	if roar_audio_3d:
		roar_audio_3d.unit_size = 11.0
		roar_audio_3d.max_distance = 46.0
		roar_audio_3d.volume_db = 1.5


# A rank-up everyone can see and hear
func tier_up_fx() -> void:
	if is_dead:
		return
	_spawn_shockwave_ring(global_position, 2.6, TIER_COLORS[tier])
	_play_3d_roar("boss_roar" if tier >= 3 else "zombie_roar_2", 1.3 if tier >= 3 else 0.8)
	FX.blood_spray(global_position + Vector3(0, 1.5 * model_scale, 0), Vector3.UP, 10)
	if _tier_light:
		var e := _tier_light.light_energy
		_tier_light.light_energy = e * 5.0
		var tw := create_tween()
		tw.tween_property(_tier_light, "light_energy", e, 0.8)


# Commander voice: a deep growl you can locate by ear
func speak() -> void:
	if roar_audio_3d == null or is_dead:
		return
	var clips := ["zombie_groan", "zombie_roar_1", "zombie_groan"]
	var st := GameState.get_sfx_stream(clips[randi() % clips.size()])
	if st:
		roar_audio_3d.stream = st
		roar_audio_3d.pitch_scale = randf_range(0.5, 0.62)
		roar_audio_3d.play()


func _update_tier_fx(delta: float) -> void:
	_shield_hint_cd = maxf(0.0, _shield_hint_cd - delta)
	fx_cast_t = maxf(0.0, fx_cast_t - delta)
	if _shield_mesh:
		_shield_mesh.visible = shield_on
		if shield_on:
			_shield_mesh.rotate_y(delta * 1.5)


# Commanders lead from behind: stay 9-14 m from the target and circle it
func _commander_move(delta: float, speed_mult: float, to_p: Vector3, flat_dist: float) -> void:
	var dir_to_p := Vector3(to_p.x, 0.0, to_p.z).normalized()
	var side := dir_to_p.cross(Vector3.UP)
	strafe_switch_timer -= delta
	if strafe_switch_timer <= 0.0:
		strafe_switch_timer = randf_range(2.0, 4.5)
		strafe_dir = -strafe_dir
	var desired := Vector3.ZERO
	if flat_dist > 14.0:
		desired = _get_nav_dir(target_player.global_position)
	elif flat_dist < 9.0:
		desired = (-dir_to_p + side * strafe_dir * 0.5).normalized() * 0.85
	else:
		desired = side * strafe_dir * 0.45
	var spd := base_speed * speed_mult * _stagger_mult()
	velocity.x = lerp(velocity.x, desired.x * spd, 6.0 * delta)
	velocity.z = lerp(velocity.z, desired.z * spd, 6.0 * delta)
	_face_direction(dir_to_p, delta * 7.0)
	_animate_walk(delta, desired.length() * spd)


# Tier 2+: hop sideways out of the line of fire when shot
func _start_dodge() -> void:
	var to_s := _shooter_pos() - global_position
	to_s.y = 0.0
	if to_s.length() < 2.5:
		return
	_dodge_dir = to_s.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	_dodge_t = 0.26
	_dodge_cd = randf_range(2.6, 4.2) - 0.35 * float(tier - 2)


# Zombies that hurt players get a taste for it and grow smarter
func _taste_blood() -> void:
	blood_hits += 1
	if blood_hits < (3 if tier == 1 else 6):
		return
	blood_hits = 0
	var wm := get_tree().current_scene.get_node_or_null("WaveManager")
	if wm and wm.has_method("blood_evolve"):
		wm.blood_evolve(self)


# ---------------------------------------------------------------------------
# COMMANDER SKILL EFFECTS (run on every machine; each hurts its own player)
# ---------------------------------------------------------------------------
func commander_fx(kind: String, pos: Vector3, amount: float) -> void:
	if Net.is_online() and not net_puppet and net_id > 0:
		var ng := _net_game()
		if ng:
			ng.boss_fx(self, kind, true, pos, amount)
	_commander_fx_local(kind, pos, amount)


func _commander_fx_local(kind: String, pos: Vector3, amount: float) -> void:
	if kind.begins_with("cwarn_"):
		fx_cast = kind.substr(6)
		fx_cast_t = 1.5
	elif kind == "ccancel":
		fx_cast_t = 0.0
	elif kind == "cenrage":
		fx_enraged = true
	match kind:
		"cwarn_slam":
			_warn_ring(pos, amount, Color(1.0, 0.4, 0.1), 0.9)
			_play_3d_roar("zombie_attack_roar", 0.6)
			if rig:
				rig.start_attack(0.9)
		"cwarn_arc":
			_warn_ring(pos, amount, Color(0.35, 0.7, 1.0), 1.15)
			_sfx_at("trap_zap", pos, -4.0, 1.3)
			if rig:
				rig.start_attack(1.0)
		"cwarn_scream":
			_warn_ring(pos, amount, Color(0.75, 0.3, 1.0), 1.5)
			_play_3d_roar("boss_roar", 1.5)
		"ccancel":
			if is_instance_valid(_warn_node):
				_warn_node.queue_free()
		"cslam":
			_sfx_at("gorilla_slam", pos, 0.0, 1.15)
			_spawn_shockwave_ring(pos, 5.0, Color(1.0, 0.4, 0.1))
			_hurt_local_in(pos, 5.0, amount, 1.2, true)
		"carc":
			_sfx_at("electrocute", pos, 0.0, 1.1)
			_spawn_shockwave_ring(pos, 3.6, Color(0.4, 0.75, 1.0))
			_flash_light(pos + Vector3(0, 1.0, 0), Color(0.5, 0.8, 1.0), 9.0)
			_hurt_local_in(pos, 3.6, amount, 1.5, false)
		"cscream":
			_sfx_at("scream_far", pos, 6.0, 0.75)
			_spawn_shockwave_ring(pos, 12.0, Color(0.75, 0.3, 1.0))
			_flash_light(pos + Vector3(0, 1.5, 0), Color(0.75, 0.3, 1.0), 14.0)
			_hurt_local_in(pos, 12.0, amount, 2.5, false)
			var lp := get_tree().get_first_node_in_group("player")
			if lp and lp.has_method("jam_flashlight") and (lp as Node3D).global_position.distance_to(pos) < 16.0:
				lp.jam_flashlight(5.0) # the scream kills your light
		"ctoxin":
			_play_3d_roar("zombie_attack_roar", 0.8)
			if rig:
				rig.start_attack(0.6)
			_spit_visual(pos, amount, 2.4)
		"cdevour":
			FX.gore_burst(pos, 6, 3.0)
			FX.blood_spray(pos, Vector3.UP, 16)
			_sfx_at("gore_splat", pos, 2.0, 0.8)
			_spawn_shockwave_ring(global_position, 1.8, Color(0.4, 1.0, 0.4))
		"craise":
			_spawn_shockwave_ring(pos, 1.6, Color(0.6, 0.2, 0.9))
			_sfx_at("zombie_groan", pos, -2.0, 0.5)
		"crally":
			_spawn_shockwave_ring(pos, amount, TIER_COLORS[tier])
			_play_3d_roar("boss_roar", 1.2)
		"cenrage":
			_spawn_shockwave_ring(pos, 3.0, Color(1.0, 0.1, 0.1))
			_play_3d_roar("boss_roar", 1.35)
			if _tier_light:
				_tier_light.light_energy = 3.5
				_tier_light.omni_range = 4.5


# A plain sound that gets quieter with distance from the camera
func _sfx_at(clip: String, pos: Vector3, db: float, pitch: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(pos) if cam else 0.0
	if d < 50.0:
		GameState.play_sfx(clip, db - d * 0.45, pitch)


func _flash_light(pos: Vector3, col: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 9.0
	get_tree().current_scene.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


# Warning circle on the ground that fills in while the attack charges
func _warn_ring(pos: Vector3, radius: float, col: Color, time: float) -> void:
	if is_instance_valid(_warn_node):
		_warn_node.queue_free()
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = Vector3(pos.x, pos.y + 0.08, pos.z)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * radius * 2.0
	disc.mesh = pm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := MaterialLib.new_warn_zone(Color(col.r, col.g, col.b, 0.9))
	disc.material_override = mat
	root.add_child(disc)
	var tw := root.create_tween()
	tw.tween_method(func(f: float): mat.set_shader_parameter("fill", f), 0.0, 1.0, time)
	tw.tween_callback(root.queue_free)
	_warn_node = root


# Hurts this machine's own player if they stand in the area.
# ground = true: jumping over it dodges (shockwaves).
func _hurt_local_in(pos: Vector3, radius: float, dmg: float, slow: float, ground: bool) -> void:
	var lp := get_tree().get_first_node_in_group("player") as Node3D
	if lp == null or lp.get("is_dead") == true or lp.get("is_downed") == true:
		return
	var d := Vector2(lp.global_position.x - pos.x, lp.global_position.z - pos.z).length()
	if d > radius + 12.0:
		return
	if lp.has_method("add_camera_shake"):
		lp.add_camera_shake(0.35)
	if d > radius or (ground and ZombieEnemy.is_airborne(lp)):
		return
	lp.take_damage(dmg, pos)
	if slow > 0.0:
		lp.set("trap_slow_t", maxf(float(lp.get("trap_slow_t")), slow))


# Commander orders and the brain feast: go somewhere else than the player.
# Returns true while the order is running this frame.
func _process_order(delta: float, speed_mult: float) -> bool:
	if order_kind == "flank_run":
		return false # handled by the normal chase with extra speed
	var goal := order_pos
	if (order_kind == "guard" or order_kind == "serve") and is_instance_valid(order_from):
		goal = order_from.global_position + order_pos # ring offset around the commander
	var off := goal - global_position
	off.y = 0.0
	var reach := 1.6 if order_kind != "guard" else 1.0
	if off.length() > reach:
		var dir := _get_nav_dir(goal)
		dir = (dir + _separation_push() * 0.6).normalized()
		var spd := base_speed * speed_mult * _stagger_mult() * (1.25 if order_kind == "feast" else 1.0)
		velocity.x = lerp(velocity.x, dir.x * spd, 8.0 * delta)
		velocity.z = lerp(velocity.z, dir.z * spd, 8.0 * delta)
		_face_direction(dir, delta * 8.0)
		_animate_walk(delta, spd)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		if order_kind == "feast" or order_kind == "build":
			# Hunched over the body / the trap, clawing
			_face_direction((order_pos - global_position).normalized() if (order_pos - global_position).length() > 0.2 else -global_basis.z, delta * 6.0)
			_animate_melee_swipe(delta)
		elif (order_kind == "guard" or order_kind == "serve") and is_instance_valid(target_player):
			_face_direction((target_player.global_position - global_position).normalized(), delta * 6.0)
			_animate_walk(delta, 0.0)
	if order_t <= 0.0:
		order_kind = ""
	return order_kind != ""


func give_order(kind: String, pos: Vector3, duration: float, from: Node3D = null) -> void:
	if is_dead or is_boss:
		return
	order_kind = kind
	order_pos = pos
	order_t = duration
	order_from = from


func at_order_spot(dist: float = 1.8) -> bool:
	var off := order_pos - global_position
	off.y = 0.0
	return order_t > 0.0 and off.length() <= dist


# Tier 2+: zig-zag when the player aims at you, get away from live explosives
func _smart_dir(move_dir: Vector3, flat_dist: float, delta: float) -> Vector3:
	for g in get_tree().get_nodes_in_group("live_explosives"):
		var off := global_position - (g as Node3D).global_position
		off.y = 0.0
		if off.length() < 6.5:
			return (off.normalized() * 1.4 + move_dir * 0.3).normalized()
	if flat_dist > 4.0 and target_player is PlayerController:
		var pc := target_player as PlayerController
		if pc.is_ads and is_instance_valid(pc.camera):
			var look := -pc.camera.global_basis.z
			var to_me := (global_position + Vector3(0, 1.2, 0) - pc.camera.global_position).normalized()
			if look.dot(to_me) > 0.985:
				_zig += delta * (3.5 + float(tier))
				var side := move_dir.cross(Vector3.UP).normalized()
				return (move_dir + side * sin(_zig) * (0.6 + 0.15 * float(tier))).normalized()
	return move_dir



# In the air (jumping) = ground attacks like acid pools and slams miss you
static func is_airborne(p: Node3D) -> bool:
	if p is CharacterBody3D:
		return not (p as CharacterBody3D).is_on_floor() or float(p.get("air_grace") if p.get("air_grace") != null else 0.0) > 0.0
	return p.global_position.y > 0.6 # teammates' avatars: judge by height
