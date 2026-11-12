class_name RemotePlayer
extends CharacterBody3D
# A teammate as seen on this machine: survivor body animated by the zombie
# rig (neutral personality, rifle-ready arms), a gun, a name plate, muzzle
# flashes and shot sounds. It is also what zombies on the host chase and hit
# (damage is forwarded to the teammate's own machine), and while the
# teammate is down it is the "station" you hold [E] on to revive them.

const ZombieRigScript := preload("res://scripts/enemies/zombie_rig.gd")
const MODEL := "res://assets/models/player_survivor.glb"
const REVIVE_TIME := 3.0
const GUN_LENGTH := {"pistol": 0.24, "revolver": 0.3, "smg": 0.5, "rifle": 0.86, "shotgun": 0.9, "lmg": 1.0, "sniper": 1.1, "volt": 0.62}

var peer_id: int = 0
var display_name: String = ""
var color: Color = Color.WHITE
var buffer := NetBuffer.new()

# Mirrored state (from the teammate's own machine)
var is_downed: bool = false
var is_dead: bool = false
var spectated: bool = false # this machine is watching through their eyes
var extracted: bool = false
var self_reviving: bool = false
var crouching: bool = false
var hp_ratio: float = 1.0
var points: int = 0
var kills: int = 0
var downs: int = 0
var weapon_id: String = "pistol"
var pitch: float = 0.0
var bleed_left: float = 0.0

var interact_radius: float = 2.3
var revive_progress: float = 0.0
var _revive_hold_t: float = 0.0
var gift_progress: float = 0.0
var _gift_hold_t: float = 0.0
var _last_gift_tap: float = -10.0

var rig = null
var model: Node3D
var gun: Node3D
var muzzle: Node3D
var flash_light: OmniLight3D
var nameplate: Label3D
var fire_audio: AudioStreamPlayer3D
var _yaw_rate: float = 0.0
var _prev_yaw: float = 0.0
var _flash_t: float = 0.0
var _last_sfx_t: float = 0.0


func setup(p_id: int, p_name: String, p_color: Color) -> void:
	peer_id = p_id
	display_name = p_name
	color = p_color
	name = "Remote%d" % p_id


const GIFT_POINTS := 500
const GIFT_TAP_WINDOW := 0.4
const GIFT_ALL_TIME := 3.0


func _ready() -> void:
	add_to_group("net_players")
	add_to_group("wall_stations") # revive when down, give points when standing
	collision_layer = 2
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)

	model = Node3D.new()
	add_child(model)
	if ResourceLoader.exists(MODEL):
		var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
		model.add_child(inst)
		rig = ZombieRigScript.new()
		var proxies := SkinRigAdapter.attach(inst)
		if rig.bind(proxies if proxies else inst):
			rig.limp = 0.0
			rig.hunch = 0.0
			rig.arm_style = 2
			rig.sway = 0.25
			rig.head_tilt = 0.0
			rig.stride_mult = 1.0
			rig.gait_mult = 1.0
		else:
			rig = null
	_build_gun()

	nameplate = Label3D.new()
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	nameplate.fixed_size = true
	nameplate.pixel_size = 0.0011
	nameplate.font_size = 26
	nameplate.outline_size = 8
	nameplate.modulate = color
	nameplate.position.y = 2.15
	add_child(nameplate)

	fire_audio = AudioStreamPlayer3D.new()
	fire_audio.bus = &"SFX"
	fire_audio.unit_size = 9.0
	fire_audio.max_distance = 90.0
	fire_audio.position.y = 1.4
	add_child(fire_audio)

	# A coloured lamp on the shoulder so squadmates are easy to tell apart
	var tag := OmniLight3D.new()
	tag.light_color = color
	tag.light_energy = 0.35
	tag.omni_range = 1.6
	tag.position = Vector3(0, 1.6, 0.1)
	add_child(tag)


func _build_gun() -> void:
	gun = Node3D.new()
	var mat := MaterialLib.get_pbr("gunmetal", 3.0, Color(0.16, 0.17, 0.19), 0.8, 0.5, false)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.12, 0.5)
	body.mesh = bm
	body.material_override = mat
	gun.add_child(body)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.016
	cm.height = 0.5
	barrel.mesh = cm
	barrel.material_override = mat
	barrel.rotation.x = PI * 0.5
	gun.add_child(barrel)
	muzzle = Node3D.new()
	gun.add_child(muzzle)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.75, 0.4)
	flash_light.light_energy = 0.0
	flash_light.omni_range = 5.0
	muzzle.add_child(flash_light)
	# On the body root (the rig's joints carry import rotations); aimed in _process
	add_child(gun)
	gun.position = Vector3(0.12, 1.36, -0.34)
	_set_gun_shape("pistol")


func _set_gun_shape(w_id: String) -> void:
	var length: float = GUN_LENGTH.get(w_id, 0.7)
	var body := gun.get_child(0) as MeshInstance3D
	var barrel := gun.get_child(1) as MeshInstance3D
	(body.mesh as BoxMesh).size = Vector3(0.06, 0.12 if length > 0.4 else 0.1, length * 0.62)
	body.position.z = length * 0.1
	(barrel.mesh as CylinderMesh).height = length * 0.45
	barrel.position.z = -length * 0.38
	muzzle.position = Vector3(0, 0.0, -length * 0.62)


# ---------------------------------------------------------------------------
# NETWORK INPUT
# ---------------------------------------------------------------------------
var _arrival_lag: float = -1.0


func apply_state(t: float, pos: Vector3, yaw: float, s: Dictionary) -> void:
	# How far behind the (estimated) host clock this teammate's states arrive;
	# follow the fastest packets quickly, ease up slowly after spikes.
	var lag := Net.host_time() - t
	if _arrival_lag < 0.0 or absf(lag - _arrival_lag) > 2.0:
		_arrival_lag = lag
	elif lag < _arrival_lag:
		_arrival_lag = lerpf(_arrival_lag, lag, 0.3)
	else:
		_arrival_lag = lerpf(_arrival_lag, lag, 0.03)
	buffer.push(t, pos, yaw, s)
	pitch = s.get("pitch", 0.0)
	_set_flashlight(s.get("light", false))
	var was_down := is_downed
	is_downed = s.get("downed", false)
	is_dead = s.get("dead", false)
	extracted = s.get("extracted", false)
	self_reviving = s.get("self_revive", false)
	crouching = s.get("crouch", false)
	hp_ratio = s.get("hp", 1.0)
	points = s.get("points", 0)
	bleed_left = s.get("bleed", 0.0)
	var w: String = s.get("weapon", weapon_id)
	if w != weapon_id:
		weapon_id = w
		_set_gun_shape(w)
	if not is_downed and was_down:
		revive_progress = 0.0


func play_fire(w_id: String, end_points: Array) -> void:
	_flash_t = 0.06
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_sfx_t > 0.05:
		_last_sfx_t = now
		var cfg: Dictionary = GameState.WEAPONS.get(w_id, {})
		var st := GameState.get_sfx_stream(String(cfg.get("sfx", "gun_pistol")))
		if st:
			fire_audio.stream = st
			fire_audio.pitch_scale = randf_range(0.95, 1.05)
			fire_audio.play()
	var from := muzzle.global_position
	for p in end_points:
		_tracer(from, p)


func _tracer(a: Vector3, b: Vector3) -> void:
	var d := a.distance_to(b)
	if d < 0.3:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.008
	cm.height = d
	cm.radial_segments = 4
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = MaterialLib.get_emissive(Color(1.0, 0.8, 0.45), 6.0, 0.7)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


# ---------------------------------------------------------------------------
# ZOMBIE-FACING API (host side)
# ---------------------------------------------------------------------------
func is_valid_target() -> bool:
	return not is_dead and not is_downed and not extracted


func take_damage(amount: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if not is_valid_target():
		return
	var ng := get_tree().get_first_node_in_group("net_game")
	if ng:
		ng.hurt_peer(peer_id, amount, from_pos)


func add_camera_shake(_amount: float) -> void:
	pass


func apply_stun(_d: float) -> void:
	pass


# ---------------------------------------------------------------------------
# REVIVE + POINT SHARING (this machine's player presses [E] on a teammate)
#   downed teammate : hold [E] to revive
#   standing mate   : double-tap [E] shares 500, hold [E] 3s sends everything
# ---------------------------------------------------------------------------
func get_prompt(p: Node3D) -> String:
	if is_dead or extracted or p.is_downed or p.is_dead:
		return ""
	if is_downed:
		return "[HOLD E] REVIVE %s  (+150 PTS)" % display_name
	if GameState.points <= 0:
		return ""
	return "[E] x2 SHARE %d · HOLD 3s SEND ALL → %s" % [GIFT_POINTS, display_name]


func try_purchase(p: Node3D) -> void:
	if is_downed or is_dead or extracted:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_gift_tap > GIFT_TAP_WINDOW:
		_last_gift_tap = now
		return
	_last_gift_tap = -10.0
	_gift(p, mini(GIFT_POINTS, GameState.points))


func interact_hold(p: Node3D, delta: float) -> void:
	if is_downed:
		_revive_hold_t = 0.15
		revive_progress += delta / REVIVE_TIME
		var ng := get_tree().get_first_node_in_group("net_game")
		if ng:
			ng.send_revive_progress(peer_id, revive_progress)
			if revive_progress >= 1.0:
				revive_progress = 0.0
				ng.send_revive(peer_id)
				# Reward for the rescue
				GameState.add_points(150)
				if is_instance_valid(p):
					p.hp = minf(p.max_hp, p.hp + 20.0)
					p.hp_changed.emit(p.hp, p.max_hp, p.overshield)
					p.status_banner_requested.emit("REVIVED %s  +150" % display_name, Color(0.4, 1.0, 0.6))
		return
	if is_dead or extracted or GameState.points <= 0:
		return
	_gift_hold_t = 0.15
	gift_progress = clampf(gift_progress + delta / GIFT_ALL_TIME, 0.0, 1.0)
	if gift_progress >= 1.0:
		gift_progress = 0.0
		_gift_hold_t = 0.0
		_send_all(p)


func _gift(p: Node3D, amount: int) -> void:
	var ng := get_tree().get_first_node_in_group("net_game")
	if ng == null or amount <= 0 or not GameState.try_pay(p, amount):
		return
	ng.send_points(peer_id, amount)
	p.status_banner_requested.emit("SENT %d POINTS TO %s" % [amount, display_name], Color(0.95, 0.85, 0.35))


# Everything you carry, split evenly between the standing mates around you.
func _send_all(p: Node3D) -> void:
	var total := GameState.points
	var mates := _standing_mates(p)
	var ng := get_tree().get_first_node_in_group("net_game")
	if total <= 0 or mates.is_empty() or ng == null or not GameState.try_pay(p, total):
		return
	var each: int = total / mates.size()
	var left: int = total - each * mates.size()
	for i in mates.size():
		var amt: int = each + (left if i == 0 else 0)
		if amt > 0:
			ng.send_points(int(mates[i]), amt)
	p.status_banner_requested.emit("SENT ALL %d POINTS TO THE SQUAD" % total, Color(0.95, 0.85, 0.35))


# The local player is a PlayerController, so the cast drops it; every avatar
# in range is a recipient, including the one you are holding [E] on.
func _standing_mates(p: Node3D) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("net_players"):
		var av := n as RemotePlayer
		if av == null or av.is_downed or av.is_dead or av.extracted:
			continue
		if p.global_position.distance_to(av.global_position) <= interact_radius * 1.5:
			out.append(av.peer_id)
	return out


# ---------------------------------------------------------------------------
# PRESENTATION
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _revive_hold_t > 0.0:
		_revive_hold_t -= delta
		if _revive_hold_t <= 0.0:
			revive_progress = 0.0
	if _gift_hold_t > 0.0:
		_gift_hold_t -= delta
		if _gift_hold_t <= 0.0:
			gift_progress = 0.0
	# Dead teammates vanish; the one we're watching through is hidden too
	visible = not extracted and not is_dead and not spectated
	if not buffer.has_data():
		return
	var s: Array = buffer.sample(Net.host_time() - maxf(0.0, _arrival_lag) - 0.08)
	var pos: Vector3 = s[0]
	var yaw: float = s[1]
	var vel: Vector3 = s[2]
	global_position = pos
	rotation.y = yaw
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.001), clampf(10.0 * delta, 0.0, 1.0))
	_prev_yaw = yaw

	var tag := display_name
	if is_dead:
		tag += "  ✖"
	elif is_downed:
		tag += "  ▼ %ds" % int(ceil(bleed_left)) if not self_reviving else "  ▼"
	nameplate.text = tag
	nameplate.modulate = Color(1.0, 0.3, 0.25) if is_downed else color

	if _flash_t > 0.0:
		_flash_t -= delta
		flash_light.light_energy = 3.0
	else:
		flash_light.light_energy = 0.0

	if rig == null:
		return
	var ground := Vector2(vel.x, vel.z).length()
	var mode := "idle"
	if is_dead:
		mode = "dead"
	elif is_downed:
		mode = "crawl"
	elif ground > 4.2:
		mode = "run"
	elif ground > 0.3:
		mode = "walk"
	var local_vel: Vector3 = global_basis.inverse() * vel
	rig.update(delta, mode, ground, {"vel": local_vel, "yaw_rate": _yaw_rate})
	model.position.y = -0.25 if crouching and not is_downed else 0.0
	gun.position.y = 1.36 + model.position.y
	gun.rotation.x = clampf(pitch, -1.2, 1.2) * 0.8
	gun.visible = not is_dead and not is_downed
	if not is_dead and not is_downed:
		_pose_aim()


# Rifle-ready arms and the chest/head following the aim pitch.
func _pose_aim() -> void:
	var n: Dictionary = rig.nodes
	var p := clampf(pitch, -1.2, 1.2)
	if n.has("Chest"):
		n["Chest"].rotation.x = p * 0.45
	if n.has("Head"):
		n["Head"].rotation.x = p * 0.45
	if n.has("UpperArmR"):
		n["UpperArmR"].rotation = Vector3(1.15, 0.0, -0.18)
	if n.has("ForearmR"):
		n["ForearmR"].rotation = Vector3(0.75, 0.0, 0.0)
	if n.has("UpperArmL"):
		n["UpperArmL"].rotation = Vector3(1.3, 0.0, 0.55)
	if n.has("ForearmL"):
		n["ForearmL"].rotation = Vector3(0.45, 0.0, 0.0)


# A teammate's flashlight: a beam from their head, where they look
var _spot: SpotLight3D


func _set_flashlight(on: bool) -> void:
	if _spot == null:
		if not on:
			return
		_spot = SpotLight3D.new()
		_spot.light_color = Color(1.0, 0.95, 0.85)
		_spot.light_energy = 3.0
		_spot.spot_range = 26.0
		_spot.spot_angle = 27.0
		_spot.spot_angle_attenuation = 0.7
		_spot.position = Vector3(0, 1.55, -0.3)
		add_child(_spot)
	_spot.visible = on and not is_dead
	_spot.rotation.x = pitch
