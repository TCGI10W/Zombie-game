class_name HoundEnemy
extends ZombieEnemy
# Blight hound: a fast skeletal dog that arrives in a lightning strike during
# hound raids. It gallops straight at the player, leaps in to bite, snarls
# while circling, and bursts into embers when it dies.
#
# Pivot axes (model faces -Z): legs +X swing forward, lower legs -X fold
# back, paws +X curl, neck/head +X lift, jaw -X opens, tail -X lifts,
# body +X pitches nose-up.

const MODEL := "res://assets/models/enemy_hound.glb"
const PIVOTS := ["Body", "Neck", "Head", "Jaw", "Tail", "TailTip",
	"FrontUpperL", "FrontLowerL", "FrontPawL", "FrontUpperR", "FrontLowerR", "FrontPawR",
	"HindUpperL", "HindLowerL", "HindPawL", "HindUpperR", "HindLowerR", "HindPawR"]

var pv: Dictionary = {}
var body_rest: Vector3 = Vector3.ZERO
var gallop: float = 0.0
var _anim_t: float = 0.0
var _last_half: int = 0
var leap_t: float = -1.0
var leap_dir: Vector3 = Vector3.ZERO
var bit_this_leap: bool = false
var appear_t: float = 0.45
var _ember_mat: StandardMaterial3D


func setup_hound(round_num: int) -> void:
	is_boss = false
	is_sprinter = true
	add_to_group("hounds")
	display_name = "BLIGHT HOUND"
	max_hp = 80.0 + float(round_num) * 24.0
	hp = max_hp
	base_speed = 7.2 + minf(1.6, float(round_num) * 0.08)
	base_damage = 14.0 + float(round_num) * 1.4
	point_reward = 70
	model_scale = randf_range(0.95, 1.08)
	voice_pitch = randf_range(0.9, 1.1)
	collision_layer = 4
	collision_mask = 1 | 2 | 4

	# Long body capsule plus a head sphere (so head shots register)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34 * model_scale
	cap.height = 1.3 * model_scale
	col.shape = cap
	col.rotation.x = PI * 0.5
	col.position = Vector3(0, cap.radius, -0.05)
	add_child(col)
	var hcol := CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = 0.17 * model_scale
	hcol.shape = hs
	hcol.position = Vector3(0, 0.86 * model_scale, -0.72 * model_scale)
	add_child(hcol)

	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.8
	nav_agent.target_desired_distance = 1.0
	nav_agent.radius = 0.4
	add_child(nav_agent)

	visual_root = Node3D.new()
	add_child(visual_root)
	if ResourceLoader.exists(MODEL):
		var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
		visual_root.add_child(inst)
		for nm in PIVOTS:
			var n := inst.find_child(nm, true, false) as Node3D
			if n:
				pv[nm] = n
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(m as MeshInstance3D)
			(m as MeshInstance3D).layers = 2
	if pv.has("Body"):
		body_rest = (pv["Body"] as Node3D).position

	_build_status_vfx(0.9, Color(1.0, 0.45, 0.1))
	_build_3d_audio(0.9)
	roar_timer = randf_range(0.6, 2.0)
	gallop = randf() * TAU

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.42, 0.1)
	glow.light_energy = 0.45
	glow.omni_range = 2.2
	glow.position = Vector3(0, 0.95, -0.75)
	add_child(glow)

	# Materialise out of the lightning strike
	visual_root.scale = Vector3.ONE * 0.01
	create_tween().tween_property(visual_root, "scale", Vector3.ONE * model_scale, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func head_y() -> float:
	return global_position.y + 0.72 * model_scale


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if net_puppet:
		_hound_puppet(delta)
		return
	if Net.is_online():
		_retarget_t -= delta
		if _retarget_t <= 0.0 or not _valid_target(target_player):
			_retarget_t = 0.5
			_retarget()
	_flesh_sfx_cd = maxf(0.0, _flesh_sfx_cd - delta)
	_anim_t += delta
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif leap_t < 0.0:
		velocity.y = 0.0
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0.0:
			_set_flash(false)
	if pain_drug_timer > 0.0:
		pain_drug_timer = maxf(0.0, pain_drug_timer - delta)

	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		stun_halo.visible = true
		stun_halo.rotate_y(delta * 5.8)
		leap_t = -1.0
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		move_and_slide()
		_animate_hound(delta, 0.0, true)
		return
	stun_halo.visible = false

	appear_t -= delta
	if appear_t > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_animate_hound(delta, 0.0, false)
		return

	if not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
		if not is_instance_valid(target_player):
			return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)

	var to_p := target_player.global_position - global_position
	var flat := Vector2(to_p.x, to_p.z).length()
	var dir := Vector3(to_p.x, 0.0, to_p.z).normalized() if flat > 0.01 else -global_basis.z
	var face := dir
	if leap_t >= 0.0:
		leap_t += delta / 0.6
		var k := clampf(1.0 - leap_t, 0.0, 1.0)
		velocity.x = leap_dir.x * (8.5 * k + 1.2)
		velocity.z = leap_dir.z * (8.5 * k + 1.2)
		if not bit_this_leap and leap_t > 0.3 and flat < 1.75:
			bit_this_leap = true
			if target_player.has_method("take_damage"):
				target_player.take_damage(base_damage * (0.45 if pain_drug_timer > 0.0 else 1.0), global_position)
			_play_3d_roar("hound_bite", randf_range(0.9, 1.1))
		if leap_t >= 1.0:
			leap_t = -1.0
			attack_cooldown = randf_range(0.6, 1.0)
		face = leap_dir
	elif flat < 2.9 and attack_cooldown <= 0.0 and is_on_floor():
		leap_t = 0.0
		bit_this_leap = false
		leap_dir = dir
		velocity.y = 3.4
		_play_3d_roar("hound_bark", randf_range(0.95, 1.15))
	else:
		var move_dir := _get_nav_dir(target_player.global_position)
		if flat < 6.0:
			move_dir = (move_dir + _separation_push() * 0.8).normalized()
		var spd := base_speed * (0.55 if pain_drug_timer > 0.0 else 1.0)
		if flat < 1.5:
			spd = 0.0 # snarling in your face, waiting to lunge again
		velocity.x = lerp(velocity.x, move_dir.x * spd, 6.0 * delta)
		velocity.z = lerp(velocity.z, move_dir.z * spd, 6.0 * delta)
		if flat > 4.0:
			face = move_dir
	_face_direction(face, delta * 9.0)

	roar_timer -= delta
	if roar_timer <= 0.0:
		roar_timer = randf_range(2.0, 4.0)
		if GameState.request_zombie_vocal(1.0):
			_play_3d_roar("hound_growl" if randf() < 0.6 else "hound_bark", randf_range(0.9, 1.1))

	move_and_slide()
	_animate_hound(delta, Vector2(velocity.x, velocity.z).length(), false)


func _animate_hound(delta: float, spd: float, stunned: bool) -> void:
	var tgt: Dictionary = {}
	var body_off := Vector3.ZERO
	var t := _anim_t
	if leap_t >= 0.0:
		# Lunge: forelegs reach, hind legs drive back, jaws gape mid-air
		var a := leap_t
		var stretch := sin(a * PI)
		for sd in ["L", "R"]:
			var o := 0.0 if sd == "L" else 0.12
			tgt["FrontUpper" + sd] = Vector3(1.05 * stretch + 0.15 + o, 0, 0)
			tgt["FrontLower" + sd] = Vector3(-0.25 * stretch, 0, 0)
			tgt["FrontPaw" + sd] = Vector3(0.3 * stretch, 0, 0)
			tgt["HindUpper" + sd] = Vector3(-0.85 * stretch - o, 0, 0)
			tgt["HindLower" + sd] = Vector3(0.35 * stretch, 0, 0)
			tgt["HindPaw" + sd] = Vector3(-0.3 * stretch, 0, 0)
		tgt["Body"] = Vector3(0.28 * (1.0 - 2.0 * a), 0, 0)
		tgt["Neck"] = Vector3(0.05, 0, 0)
		tgt["Head"] = Vector3(-0.12, 0, 0)
		tgt["Jaw"] = Vector3(-0.8 * smoothstep(0.08, 0.3, a) * (1.0 - smoothstep(0.5, 0.75, a)), 0, 0)
		tgt["Tail"] = Vector3(-0.55, 0, 0)
		tgt["TailTip"] = Vector3(-0.3, 0, 0)
		body_off.y = 0.06 * stretch
	elif stunned:
		var shake := sin(t * 14.0) * 0.06
		for sd in ["L", "R"]:
			tgt["FrontLower" + sd] = Vector3(-0.45, 0, 0)
			tgt["FrontPaw" + sd] = Vector3(0.45, 0, 0)
			tgt["HindUpper" + sd] = Vector3(0.45, 0, 0)
			tgt["HindLower" + sd] = Vector3(-0.75, 0, 0)
			tgt["HindPaw" + sd] = Vector3(0.35, 0, 0)
		tgt["Body"] = Vector3(-0.05, 0, shake)
		tgt["Neck"] = Vector3(-0.45, shake * 3.0, 0)
		tgt["Head"] = Vector3(-0.2, 0, shake * 2.0)
		tgt["Jaw"] = Vector3(-0.15, 0, 0)
		tgt["Tail"] = Vector3(0.7, 0, 0)
		body_off.y = -0.13
	elif spd > 0.6:
		# Rotary gallop: forelegs a beat apart, hind legs half a stride later
		var stride := 1.75
		gallop += TAU * (spd / stride) * delta
		var g := gallop
		var sw := clampf(spd / 7.0, 0.35, 1.0)
		for sd in ["L", "R"]:
			var fth := g + (0.0 if sd == "L" else 0.13 * TAU)
			var hth := g + (0.52 if sd == "L" else 0.64) * TAU
			tgt["FrontUpper" + sd] = Vector3(0.78 * sw * sin(fth), 0, 0)
			tgt["FrontLower" + sd] = Vector3(-1.25 * sw * maxf(0.0, cos(fth)), 0, 0)
			tgt["FrontPaw" + sd] = Vector3(0.75 * sw * maxf(0.0, cos(fth)), 0, 0)
			tgt["HindUpper" + sd] = Vector3(0.72 * sw * sin(hth), 0, 0)
			tgt["HindLower" + sd] = Vector3(-0.95 * sw * maxf(0.0, cos(hth)), 0, 0)
			tgt["HindPaw" + sd] = Vector3(0.85 * sw * maxf(0.0, cos(hth)), 0, 0)
		var pitch := 0.1 * sw * sin(g + 0.6)
		tgt["Body"] = Vector3(pitch, 0, 0)
		tgt["Neck"] = Vector3(-0.12 - pitch * 0.9, 0, 0)
		tgt["Head"] = Vector3(0.05 + 0.04 * sin(2.0 * g), 0, 0)
		tgt["Jaw"] = Vector3(-0.18 - 0.16 * maxf(0.0, sin(2.0 * g)), 0, 0)
		tgt["Tail"] = Vector3(-0.4 + 0.15 * sin(2.0 * g), 0.1 * sin(g), 0)
		tgt["TailTip"] = Vector3(0.25 * sin(2.0 * g + 1.0), 0, 0)
		body_off.y = 0.045 * sw * absf(sin(g))
		var half := int(floor(g / PI))
		if half != _last_half:
			_last_half = half
			_step_count += 1
			_play_3d_footstep(_step_count)
	else:
		# Stalking crouch: hackles up, head low, jaw snapping
		var br := sin(t * 3.0)
		for sd in ["L", "R"]:
			tgt["FrontUpper" + sd] = Vector3(-0.12, 0, 0)
			tgt["FrontLower" + sd] = Vector3(-0.15, 0, 0)
			tgt["FrontPaw" + sd] = Vector3(0.2, 0, 0)
			tgt["HindUpper" + sd] = Vector3(0.3, 0, 0)
			tgt["HindLower" + sd] = Vector3(-0.5, 0, 0)
			tgt["HindPaw" + sd] = Vector3(0.35, 0, 0)
		tgt["Body"] = Vector3(-0.09 + br * 0.015, 0, 0)
		tgt["Neck"] = Vector3(-0.28, sin(t * 1.3) * 0.15, 0)
		tgt["Head"] = Vector3(0.18 + sin(t * 9.0) * 0.035, 0, sin(t * 7.0) * 0.04)
		tgt["Jaw"] = Vector3(-0.22 - 0.25 * maxf(0.0, sin(t * 6.5)), 0, 0)
		tgt["Tail"] = Vector3(0.2, sin(t * 2.0) * 0.2, 0)
		body_off.y = -0.06 + br * 0.008

	var k := clampf(16.0 * delta, 0.0, 1.0)
	for nm in pv:
		var n: Node3D = pv[nm]
		n.rotation = n.rotation.lerp(tgt.get(nm, Vector3.ZERO), k)
	if pv.has("Body"):
		var b: Node3D = pv["Body"]
		b.position = b.position.lerp(body_rest + body_off, k)


func _die(was_headshot: bool) -> void:
	is_dead = true
	collision_layer = 0
	collision_mask = 0
	stun_halo.visible = false
	drug_aura.visible = false
	drug_light.visible = false
	_set_flash(false)
	died.emit(self, was_headshot)
	_net_notify_death(was_headshot)

	var center := global_position + Vector3(0, 0.6, 0)
	_ember_burst(center)
	FX.gore_burst(center, 4, 3.0)
	FX.scorch(Vector3(global_position.x, global_position.y + 0.02, global_position.z), 1.7)
	if roar_audio_3d:
		roar_audio_3d.stream = GameState.get_sfx_stream("hound_death")
		roar_audio_3d.pitch_scale = randf_range(0.9, 1.1)
		roar_audio_3d.play()
	# The flare-up singes anyone standing right next to it
	if is_instance_valid(target_player) and target_player.global_position.distance_to(global_position) < 2.0 and target_player.has_method("take_damage"):
		target_player.take_damage(10.0, global_position)
	var tw := create_tween()
	tw.tween_property(visual_root, "scale", Vector3(model_scale * 1.2, model_scale * 0.15, model_scale * 1.2), 0.16)
	tw.tween_callback(func(): visual_root.visible = false)
	tw.tween_interval(1.8)
	tw.tween_callback(queue_free)


func _ember_burst(pos: Vector3) -> void:
	if _ember_mat == null:
		_ember_mat = MaterialLib.get_emissive(Color(1.0, 0.5, 0.12), 6.0)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 46
	p.lifetime = 1.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -3.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 6.0
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = _ember_mat
	p.mesh = sm
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 6.0
	light.omni_range = 6.0
	get_tree().current_scene.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)


# ---------------------------------------------------------------------------
# CO-OP
# ---------------------------------------------------------------------------
func net_anim_byte() -> int:
	var m := 2
	if leap_t >= 0.0:
		m |= 16
	if stun_timer > 0.0:
		m |= 128
	return m


func _hound_puppet(delta: float) -> void:
	_anim_t += delta
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
	var stunned := (_net_anim & 128) != 0
	stun_halo.visible = stunned
	leap_t = 0.5 if (_net_anim & 16) != 0 else -1.0
	_animate_hound(delta, 0.0 if stunned else _net_speed, stunned)
