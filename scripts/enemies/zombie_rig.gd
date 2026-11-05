extends RefCounted
# Procedural animation for the jointed zombie models (zombie_*_v2.glb and
# zombie_bloater.glb).
#
# Legs are solved with two-bone IK against a planted-foot gait cycle, so the
# feet stay on the ground instead of sliding. The pelvis sways and twists with
# each step, the shoulders counter-rotate, and the arms, head and jaw are
# driven by springs that react to the body's acceleration, turns and hits.
#
# Joint axes (Godot space, model faces -Z):
#   arms/legs  +X = swing forward      shins  -X = bend knee
#   spine/chest -X = lean forward      head   +X = look up    jaw -X = open
#   feet +X = toe up
#   +Z rolls a limb toward +X, so left-arm "outward" is -Z, right-arm is +Z.

const JOINTS := ["Hips", "Spine", "Chest", "Head", "Jaw",
	"UpperArmL", "ForearmL", "HandL", "UpperArmR", "ForearmR", "HandR",
	"ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]

# How fast each joint follows its target. Legs track the IK almost exactly;
# the upper body lags a little, which reads as weight and follow-through.
const FOLLOW := {"ThighL": 60.0, "ShinL": 60.0, "FootL": 60.0, "ThighR": 60.0, "ShinR": 60.0, "FootR": 60.0,
	"Hips": 24.0, "Spine": 14.0, "Chest": 12.0, "Head": 9.0, "Jaw": 16.0,
	"UpperArmL": 10.0, "ForearmL": 9.0, "HandL": 8.0, "UpperArmR": 10.0, "ForearmR": 9.0, "HandR": 8.0}

var nodes: Dictionary = {}
var hips_rest: Vector3 = Vector3.ZERO
var thigh_len: float = 0.42
var shin_len: float = 0.42
var hip_h: float = 0.94
var ankle_h: float = 0.10

var phase: float = 0.0
var t: float = 0.0
var _u_prev: Array[float] = [0.0, 0.5]

# Per-zombie personality
var limp: float = 0.0 # 0..0.55, weakens one leg
var limp_left: bool = true
var arm_style: int = 0 # 0 reach both, 1 reach one, 2 dangle
var head_tilt: float = 0.0
var gait_mult: float = 1.0
var hunch: float = 0.2
var sway: float = 1.0
var stride_mult: float = 1.0

# Springs: torso flinch, head snap, arm jerks, dangling-arm pendulums
var flinch: Vector3 = Vector3.ZERO
var flinch_vel: Vector3 = Vector3.ZERO
var head_hit: Vector3 = Vector3.ZERO
var head_hit_vel: Vector3 = Vector3.ZERO
var arm_hit: Vector2 = Vector2.ZERO # (left, right)
var arm_hit_vel: Vector2 = Vector2.ZERO
var pend: Vector2 = Vector2.ZERO # dangling-arm swing (left, right)
var pend_vel: Vector2 = Vector2.ZERO
var stagger: float = 0.0 # 0..1 after leg hits; the owner slows down while > 0
var stagger_left: bool = true
var lean: Vector2 = Vector2.ZERO # (forward, roll) from acceleration and turning
var _prev_vel: Vector3 = Vector3.ZERO
var _move_w: float = 0.0

# Attack animation progress (-1 = not attacking)
var attack_t: float = -1.0
var attack_len: float = 0.75
var attack_kind: int = 0
var last_mode: String = "idle" # sent to co-op clients

# Death
var dead_pose: Dictionary = {}


func bind(model: Node) -> bool:
	for j in JOINTS:
		var n := model.find_child(j, true, false) as Node3D
		if n:
			nodes[j] = n
	if nodes.has("Hips"):
		hips_rest = (nodes["Hips"] as Node3D).position
	if nodes.has("ThighL") and nodes.has("ShinL") and nodes.has("FootL"):
		var thigh_p: Vector3 = (nodes["ThighL"] as Node3D).position
		var shin_p: Vector3 = (nodes["ShinL"] as Node3D).position
		var foot_p: Vector3 = (nodes["FootL"] as Node3D).position
		thigh_len = maxf(0.2, shin_p.length())
		shin_len = maxf(0.2, foot_p.length())
		hip_h = hips_rest.y + thigh_p.y
		ankle_h = maxf(0.02, hip_h + shin_p.y + foot_p.y)
	limp = randf_range(0.15, 0.55) if randf() < 0.4 else 0.0
	limp_left = randf() < 0.5
	var r := randf()
	arm_style = 0 if r < 0.5 else (1 if r < 0.75 else 2)
	head_tilt = randf_range(-0.3, 0.3)
	gait_mult = randf_range(0.88, 1.12)
	hunch = randf_range(0.1, 0.38)
	sway = randf_range(0.6, 1.5)
	stride_mult = randf_range(0.85, 1.1)
	phase = randf() * TAU
	t = randf() * 10.0
	return nodes.size() >= 15


func hide_legs() -> void:
	for j in ["ThighL", "ThighR"]:
		if nodes.has(j):
			(nodes[j] as Node3D).visible = false


# region: "head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"
func hit(strength: float, from_dir_local: Vector3, region: String = "torso") -> void:
	var s := clampf(strength, 0.2, 2.5)
	var side := from_dir_local.x
	match region:
		"head":
			head_hit_vel += Vector3(6.5 * s, -side * 4.0 * s, randf_range(-2.5, 2.5) * s)
			flinch_vel += Vector3(1.2 * s, 0.0, side * 0.8 * s)
		"arm_l":
			arm_hit_vel.x -= 7.0 * s
			flinch_vel += Vector3(0.8 * s, 1.4 * s, -0.8 * s)
		"arm_r":
			arm_hit_vel.y -= 7.0 * s
			flinch_vel += Vector3(0.8 * s, -1.4 * s, 0.8 * s)
		"leg_l", "leg_r":
			stagger = minf(1.0, stagger + 0.35 * s)
			stagger_left = region == "leg_l"
			flinch_vel += Vector3(-1.6 * s, 0.0, (1.5 if stagger_left else -1.5) * s)
		_:
			flinch_vel += Vector3(2.6 * s, -side * 2.0 * s, side * 2.2 * s + randf_range(-0.6, 0.6))


func start_attack(length: float = 0.75) -> void:
	attack_t = 0.0
	attack_len = length
	attack_kind = randi() % 3


func is_attacking() -> bool:
	return attack_t >= 0.0


func set_dead_pose(kind: String) -> void:
	# A limp, random pose the body settles into while it falls
	var sign_side := -1.0 if randf() < 0.5 else 1.0
	dead_pose = {
		"Spine": Vector3(randf_range(-0.3, 0.2), randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)),
		"Chest": Vector3(randf_range(-0.2, 0.2), 0, 0),
		"Head": Vector3(randf_range(-0.5, 0.4), randf_range(-0.9, 0.9), randf_range(-0.5, 0.5)),
		"Jaw": Vector3(-0.45, 0, 0),
		"UpperArmL": Vector3(randf_range(-0.3, 2.6), 0, randf_range(-1.4, -0.3)),
		"UpperArmR": Vector3(randf_range(-0.3, 2.6), 0, randf_range(0.3, 1.4)),
		"ForearmL": Vector3(randf_range(0.1, 1.2), 0, 0),
		"ForearmR": Vector3(randf_range(0.1, 1.2), 0, 0),
		"ThighL": Vector3(randf_range(-0.2, 0.9), 0, randf_range(-0.4, 0.0)),
		"ThighR": Vector3(randf_range(-0.2, 0.9), 0, randf_range(0.0, 0.4)),
		"ShinL": Vector3(randf_range(-1.2, -0.1), 0, 0),
		"ShinR": Vector3(randf_range(-1.2, -0.1), 0, 0),
	}
	if kind == "crumple":
		dead_pose["ThighL"] = Vector3(1.4, 0, -0.2)
		dead_pose["ThighR"] = Vector3(1.2, 0, 0.2)
		dead_pose["ShinL"] = Vector3(-2.2, 0, 0)
		dead_pose["ShinR"] = Vector3(-2.0, 0, 0)
	dead_pose["_side"] = sign_side


# Advances the animation. Returns true when a foot plants.
# extra: {"vel": velocity in model space, "yaw_rate": turn speed (rad/s)}
func update(delta: float, mode: String, speed: float, extra: Dictionary = {}) -> bool:
	last_mode = mode
	t += delta
	var footstep := false
	var tgt: Dictionary = {}
	var hips_off := Vector3.ZERO

	_update_springs(delta, extra, speed)

	match mode:
		"walk", "run":
			var res := _pose_gait(tgt, speed, mode == "run", delta)
			hips_off = res[0]
			footstep = res[1]
		"climb":
			phase += delta * (3.4 + speed * 0.8)
			hips_off = _pose_climb(tgt)
			footstep = _contact_check()
		"crawl":
			phase += delta * (2.0 + speed * 0.9)
			hips_off = _pose_crawl(tgt)
		"stunned":
			hips_off = _pose_stunned(tgt)
		"rise":
			_pose_rise(tgt)
		"dead":
			for k in dead_pose:
				if k != "_side":
					tgt[k] = dead_pose[k]
		_:
			hips_off = _pose_idle(tgt)

	# Attack overlay (blends on top of the locomotion pose)
	if attack_t >= 0.0 and mode != "dead":
		attack_t += delta / attack_len
		if attack_t >= 1.0:
			attack_t = -1.0
		else:
			_pose_attack(tgt, attack_t, mode == "crawl")

	if mode != "dead":
		_apply_reactions(tgt, mode)
		if stagger > 0.0 and mode != "crawl":
			hips_off.y -= 0.1 * stagger

	for j in nodes:
		var n: Node3D = nodes[j]
		var target: Vector3 = tgt.get(j, Vector3.ZERO)
		var rate: float = 6.0 if mode == "dead" else float(FOLLOW.get(j, 14.0))
		n.rotation = n.rotation.lerp(target, clampf(rate * delta, 0.0, 1.0))
	if nodes.has("Hips"):
		var h: Node3D = nodes["Hips"]
		h.position = h.position.lerp(hips_rest + hips_off, clampf((6.0 if mode == "dead" else 30.0) * delta, 0.0, 1.0))
	return footstep


# --- Springs & reactions -----------------------------------------------------
func _update_springs(delta: float, extra: Dictionary, speed: float) -> void:
	flinch_vel += (-flinch * 140.0 - flinch_vel * 13.0) * delta
	flinch += flinch_vel * delta
	head_hit_vel += (-head_hit * 170.0 - head_hit_vel * 12.0) * delta
	head_hit += head_hit_vel * delta
	arm_hit_vel += (-arm_hit * 120.0 - arm_hit_vel * 10.0) * delta
	arm_hit += arm_hit_vel * delta
	stagger = maxf(0.0, stagger - delta * 0.9)

	var vel: Vector3 = extra.get("vel", Vector3.ZERO)
	var acc := (vel - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = vel
	var acc_fwd := clampf(-acc.z, -25.0, 25.0)
	# Dangling arms lag behind the body like pendulums
	pend_vel += (-pend * 55.0 - pend_vel * 5.5 - Vector2.ONE * acc_fwd * 0.12) * delta
	pend += pend_vel * delta
	# Lean into acceleration and into turns
	var yaw_rate: float = extra.get("yaw_rate", 0.0)
	var want := Vector2(clampf(acc_fwd * 0.02, -0.18, 0.25), clampf(yaw_rate * speed * 0.035, -0.28, 0.28))
	lean = lean.lerp(want, clampf(5.0 * delta, 0.0, 1.0))
	_move_w = move_toward(_move_w, clampf(speed / 1.2, 0.0, 1.0), delta * 4.0)


func _apply_reactions(tgt: Dictionary, mode: String) -> void:
	var lean_x := -lean.x if mode != "crawl" else 0.0
	tgt["Spine"] = tgt.get("Spine", Vector3.ZERO) + Vector3(flinch.x * 0.6 + lean_x, flinch.y * 0.5, flinch.z * 0.5 + lean.y * 0.6)
	tgt["Chest"] = tgt.get("Chest", Vector3.ZERO) + Vector3(flinch.x * 0.4, flinch.y * 0.4, flinch.z * 0.3 + lean.y * 0.4)
	tgt["Head"] = tgt.get("Head", Vector3.ZERO) + Vector3(flinch.x * 0.8, flinch.y * 0.3, flinch.z * 0.6) + head_hit
	tgt["UpperArmL"] = tgt.get("UpperArmL", Vector3.ZERO) + Vector3(arm_hit.x, 0.0, arm_hit.x * 0.3)
	tgt["UpperArmR"] = tgt.get("UpperArmR", Vector3.ZERO) + Vector3(arm_hit.y, 0.0, -arm_hit.y * 0.3)
	if stagger > 0.0 and mode != "crawl":
		var k := "ShinL" if stagger_left else "ShinR"
		tgt[k] = tgt.get(k, Vector3.ZERO) + Vector3(-0.9 * stagger, 0, 0)
		var th := "ThighL" if stagger_left else "ThighR"
		tgt[th] = tgt.get(th, Vector3.ZERO) + Vector3(0.45 * stagger, 0, 0)
		tgt["Spine"] = tgt["Spine"] + Vector3(-0.25 * stagger, 0, (0.2 if stagger_left else -0.2) * stagger)


# --- Leg IK --------------------------------------------------------------------
# Returns (thigh swing, knee bend) that put the ankle `fwd` ahead of and `down`
# below the hip joint. The knee always bends forward like a real knee.
func _solve_leg(fwd: float, down: float) -> Vector2:
	var d := clampf(sqrt(fwd * fwd + down * down), 0.25, thigh_len + shin_len - 0.003)
	var cos_k := (thigh_len * thigh_len + shin_len * shin_len - d * d) / (2.0 * thigh_len * shin_len)
	var knee := PI - acos(clampf(cos_k, -1.0, 1.0))
	var cos_a := (thigh_len * thigh_len + d * d - shin_len * shin_len) / (2.0 * thigh_len * d)
	var alpha := acos(clampf(cos_a, -1.0, 1.0))
	return Vector2(atan2(fwd, down) + alpha, knee)


func _contact_check() -> bool:
	var hit_ground := false
	for i in range(2):
		var u := fposmod(phase / TAU + (0.0 if i == 0 else 0.5), 1.0)
		if u < _u_prev[i]:
			hit_ground = true
		_u_prev[i] = u
	return hit_ground


# --- Poses -----------------------------------------------------------------
func _pose_gait(tgt: Dictionary, speed: float, running: bool, delta: float) -> Array:
	var spd := maxf(speed, 0.0)
	var stride: float
	# Stride is capped by leg reach; faster movement means quicker steps,
	# so the planted foot travels exactly as far as the body does.
	if running:
		stride = clampf(1.4 + 0.25 * spd, 1.8, 2.8)
	else:
		stride = minf(clampf(0.9 + 0.15 * spd, 0.95, 1.35) * stride_mult, 1.35)
	var freq := spd / stride
	phase += TAU * freq * delta
	var duty := 0.4 if running else 0.62
	var step_len := duty * stride * clampf(spd / 0.3, 0.0, 1.0)
	var w := _move_w
	var lift := (0.26 if running else 0.11) * w
	var crouch := (0.13 if running else 0.04 + hunch * 0.06)
	var bob := (0.05 if running else 0.025) * clampf(spd / 3.0, 0.0, 1.0)
	var hips_y := -crouch - bob * (0.5 + 0.5 * cos(2.0 * phase))
	var mid := duty * PI
	var shift := cos(phase - mid)
	var hips_x := -0.035 * sway * shift * w
	var hips_roll := -0.06 * sway * shift * w
	var hips_yaw := 0.13 * sin(phase) * w * (0.6 if running else 1.0)
	if limp > 0.0:
		# Dip onto the bad leg and favour the good one
		hips_roll += (0.07 if limp_left else -0.07) * limp
	var hips_pitch := -0.08 if running else 0.0
	tgt["Hips"] = Vector3(hips_pitch, hips_yaw, hips_roll)

	var footstep := false
	for i in range(2):
		var sfx := "L" if i == 0 else "R"
		var u := fposmod(phase / TAU + (0.0 if i == 0 else 0.5), 1.0)
		if u < _u_prev[i] and spd > 0.4:
			footstep = true
		_u_prev[i] = u
		var bad := limp > 0.0 and ((i == 0) == limp_left)
		var fw: float
		var up := 0.0
		var toe: float
		if u < duty:
			var s := u / duty
			fw = step_len * (0.5 - s)
			toe = -0.35 * smoothstep(0.7, 1.0, s) * w
		else:
			var s2 := (u - duty) / (1.0 - duty)
			var e := s2 * s2 * (3.0 - 2.0 * s2)
			fw = step_len * (-0.5 + e)
			var l := lift * ((1.0 - limp * 1.4) if bad else 1.0)
			up = maxf(l, 0.012 * w) * sin(PI * s2)
			toe = (0.35 * sin(PI * s2) + 0.15 * smoothstep(0.7, 1.0, s2)) * w
			if bad:
				toe -= 0.35 * limp # dragged foot: toes scrape the ground
		var side_drop := -hips_roll * (0.11 if i == 0 else -0.11)
		var down := hip_h + hips_y + side_drop - (ankle_h + up)
		var ik := _solve_leg(fw + 0.02, down)
		var thigh := ik.x - hips_pitch
		# Cancel the pelvis sway and roll so planted feet don't skate sideways
		var lat := -hips_roll - hips_x / maxf(down, 0.3)
		tgt["Thigh" + sfx] = Vector3(thigh, -hips_yaw, (-0.04 if i == 0 else 0.04) + lat)
		tgt["Shin" + sfx] = Vector3(-ik.y, 0, 0)
		tgt["Foot" + sfx] = Vector3(-(ik.x - ik.y) + toe, 0, -lat - hips_roll)

	var s3 := sin(phase)
	if running:
		tgt["Spine"] = Vector3(-0.4 - hunch * 0.3, -hips_yaw * 0.6, -hips_roll * 0.4)
		tgt["Chest"] = Vector3(-0.15, -hips_yaw * 0.9, 0)
		_head_and_jaw(tgt, 0.55, 6.0, -0.4)
		tgt["UpperArmL"] = Vector3(0.9 - s3 * 0.75 + sin(t * 11.0) * 0.12, 0, -0.25)
		tgt["UpperArmR"] = Vector3(0.9 + s3 * 0.75 + sin(t * 10.0) * 0.12, 0, 0.25)
		tgt["ForearmL"] = Vector3(1.0 + maxf(0.0, -s3) * 0.4, 0, 0)
		tgt["ForearmR"] = Vector3(1.0 + maxf(0.0, s3) * 0.4, 0, 0)
		tgt["HandL"] = Vector3(0.4, 0, 0)
		tgt["HandR"] = Vector3(0.4, 0, 0)
	else:
		tgt["Spine"] = Vector3(-hunch - 0.06, -hips_yaw * 0.5, -hips_roll * 0.5)
		tgt["Chest"] = Vector3(-0.1, -hips_yaw * 0.8, -hips_roll * 0.3)
		_head_and_jaw(tgt, 0.3 + hunch * 0.8, 2.3, -hunch - 0.16)
		_arms_shamble(tgt, s3, step_len)
	return [Vector3(hips_x, hips_y, 0.0), footstep]


func _head_and_jaw(tgt: Dictionary, look_up: float, chatter: float, chest_pitch: float) -> void:
	# Keep the eyes roughly level (head counters the torso lean), with a lazy
	# look-around on top
	var stab := -chest_pitch * 0.55
	tgt["Head"] = Vector3(look_up * 0.5 + stab + sin(t * 1.3) * 0.06, sin(t * 0.7) * 0.2, head_tilt + sin(t * 0.9) * 0.08)
	tgt["Jaw"] = Vector3(-(0.08 + maxf(0.0, sin(t * chatter)) * 0.3), 0, 0)


func _arms_shamble(tgt: Dictionary, s: float, step_len: float) -> void:
	var reach_l := arm_style == 0
	var reach_r := arm_style <= 1
	var swing := clampf(step_len * 0.7, 0.0, 0.55)
	var bounce := sin(2.0 * phase) * 0.05
	if reach_l:
		tgt["UpperArmL"] = Vector3(1.28 + sin(t * 1.7) * 0.07 + bounce + pend.x * 0.4, 0, -0.14)
		tgt["ForearmL"] = Vector3(0.22 + sin(t * 2.1) * 0.08, 0, 0)
		tgt["HandL"] = Vector3(-0.25 + sin(t * 3.0) * 0.15, 0, 0)
	else:
		tgt["UpperArmL"] = Vector3(0.06 - s * swing + pend.x, 0, -0.1)
		tgt["ForearmL"] = Vector3(0.22 + maxf(0.0, -s) * 0.35, 0, 0)
		tgt["HandL"] = Vector3(sin(t * 3.0) * 0.15, 0, 0)
	if reach_r:
		tgt["UpperArmR"] = Vector3(1.24 + sin(t * 1.9 + 1.0) * 0.07 - bounce + pend.y * 0.4, 0, 0.14)
		tgt["ForearmR"] = Vector3(0.25 + sin(t * 2.3 + 1.0) * 0.08, 0, 0)
		tgt["HandR"] = Vector3(-0.25 + sin(t * 3.3 + 1.0) * 0.15, 0, 0)
	else:
		tgt["UpperArmR"] = Vector3(0.06 + s * swing + pend.y, 0, 0.1)
		tgt["ForearmR"] = Vector3(0.22 + maxf(0.0, s) * 0.35, 0, 0)
		tgt["HandR"] = Vector3(sin(t * 3.3 + 1.0) * 0.15, 0, 0)


func _pose_climb(tgt: Dictionary) -> Vector3:
	var s := sin(phase)
	tgt["ThighL"] = Vector3(maxf(0.0, s) * 1.3, 0, -0.05)
	tgt["ThighR"] = Vector3(maxf(0.0, -s) * 1.3, 0, 0.05)
	tgt["ShinL"] = Vector3(-maxf(0.0, s) * 1.5 - 0.1, 0, 0)
	tgt["ShinR"] = Vector3(-maxf(0.0, -s) * 1.5 - 0.1, 0, 0)
	tgt["Spine"] = Vector3(-0.45, 0, s * 0.1)
	tgt["Chest"] = Vector3(-0.2, 0, 0)
	tgt["UpperArmL"] = Vector3(1.5 + s * 0.3, 0, -0.2)
	tgt["UpperArmR"] = Vector3(1.5 - s * 0.3, 0, 0.2)
	tgt["ForearmL"] = Vector3(0.5, 0, 0)
	tgt["ForearmR"] = Vector3(0.5, 0, 0)
	_head_and_jaw(tgt, 0.5, 4.0, -0.45)
	return Vector3(0, -0.08, 0)


func _pose_crawl(tgt: Dictionary) -> Vector3:
	var s := sin(phase)
	var c := cos(phase)
	# Body lies face-down; arms reach, plant and drag it forward
	tgt["Hips"] = Vector3(-1.42, s * 0.08, s * 0.05)
	tgt["Spine"] = Vector3(0.18, s * 0.12, -s * 0.06)
	tgt["Chest"] = Vector3(0.12, s * 0.15, 0)
	tgt["Head"] = Vector3(1.0 + sin(t * 1.4) * 0.1, sin(t * 0.8) * 0.2, head_tilt * 0.5)
	tgt["Jaw"] = Vector3(-(0.15 + maxf(0.0, sin(t * 3.0)) * 0.35), 0, 0)
	tgt["UpperArmL"] = Vector3(2.45 + s * 0.55, 0, -0.35)
	tgt["UpperArmR"] = Vector3(2.45 - s * 0.55, 0, 0.35)
	tgt["ForearmL"] = Vector3(0.25 + maxf(0.0, c) * 0.7, 0, 0)
	tgt["ForearmR"] = Vector3(0.25 + maxf(0.0, -c) * 0.7, 0, 0)
	tgt["HandL"] = Vector3(-0.4 * maxf(0.0, c), 0, 0)
	tgt["HandR"] = Vector3(-0.4 * maxf(0.0, -c), 0, 0)
	tgt["ThighL"] = Vector3(-0.15, 0, -0.1)
	tgt["ThighR"] = Vector3(-0.1, 0, 0.1)
	return Vector3(0, -0.66, 0)


func _pose_stunned(tgt: Dictionary) -> Vector3:
	var sw := sin(t * 2.2)
	tgt["Spine"] = Vector3(-0.42, sw * 0.1, sw * 0.12)
	tgt["Chest"] = Vector3(-0.2, 0, sw * 0.06)
	tgt["Head"] = Vector3(-0.55, sin(t * 1.3) * 0.3, cos(t * 1.7) * 0.35)
	tgt["Jaw"] = Vector3(-0.35, 0, 0)
	tgt["UpperArmL"] = Vector3(0.1 + sw * 0.1, 0, -0.05)
	tgt["UpperArmR"] = Vector3(0.1 - sw * 0.1, 0, 0.05)
	tgt["ForearmL"] = Vector3(0.2, 0, 0)
	tgt["ForearmR"] = Vector3(0.2, 0, 0)
	# Knees buckled, feet still flat on the ground
	for i in range(2):
		var sfx := "L" if i == 0 else "R"
		var ik := _solve_leg(0.06 + (0.05 if i == 0 else -0.02), hip_h - 0.16 + sw * 0.02 * (1.0 if i == 0 else -1.0) - ankle_h)
		tgt["Thigh" + sfx] = Vector3(ik.x, 0, -0.05 if i == 0 else 0.05)
		tgt["Shin" + sfx] = Vector3(-ik.y, 0, 0)
		tgt["Foot" + sfx] = Vector3(-(ik.x - ik.y), 0, 0)
	return Vector3(sw * 0.03, -0.16, 0)


func _pose_rise(tgt: Dictionary) -> void:
	# Clawing out of the ground
	tgt["UpperArmL"] = Vector3(2.7 + sin(t * 9.0) * 0.35, 0, -0.35)
	tgt["UpperArmR"] = Vector3(2.7 + sin(t * 9.0 + 1.6) * 0.35, 0, 0.35)
	tgt["ForearmL"] = Vector3(0.6, 0, 0)
	tgt["ForearmR"] = Vector3(0.6, 0, 0)
	tgt["Spine"] = Vector3(-0.35, 0, sin(t * 4.0) * 0.1)
	tgt["Head"] = Vector3(0.6, 0, 0.2)
	tgt["Jaw"] = Vector3(-0.5, 0, 0)


func _pose_idle(tgt: Dictionary) -> Vector3:
	# Breathing, slow weight shifts from foot to foot, feet planted
	var b := sin(t * 1.4)
	var shift := sin(t * 0.45)
	tgt["Hips"] = Vector3(0, shift * 0.05, -shift * 0.05 * sway)
	tgt["Spine"] = Vector3(-hunch - 0.1 + b * 0.04, -shift * 0.04, shift * 0.04)
	tgt["Chest"] = Vector3(-0.1 + b * 0.025, 0, 0)
	_head_and_jaw(tgt, 0.35 + hunch, 2.0, -hunch - 0.2)
	tgt["UpperArmL"] = Vector3(1.0 + b * 0.06 + pend.x * 0.4, 0, -0.15)
	tgt["UpperArmR"] = Vector3(1.0 - b * 0.06 + pend.y * 0.4, 0, 0.15)
	tgt["ForearmL"] = Vector3(0.4, 0, 0)
	tgt["ForearmR"] = Vector3(0.4, 0, 0)
	for i in range(2):
		var sfx := "L" if i == 0 else "R"
		var load := shift * (1.0 if i == 0 else -1.0)
		var ik := _solve_leg(0.04 + (0.08 if i == 0 else -0.03), hip_h - 0.05 - ankle_h - 0.03 * maxf(0.0, -load))
		tgt["Thigh" + sfx] = Vector3(ik.x, 0, -0.06 if i == 0 else 0.06)
		tgt["Shin" + sfx] = Vector3(-ik.y, 0, 0)
		tgt["Foot" + sfx] = Vector3(-(ik.x - ik.y), 0, 0)
	return Vector3(shift * 0.03 * sway, -0.05, 0)


# Three attacks: a two-arm overhead slam, a swinging hook with the right arm,
# and a lunge that grabs with both hands and bites.
func _pose_attack(tgt: Dictionary, a: float, crawling: bool) -> void:
	var wind := smoothstep(0.0, 0.38, a) * (1.0 - smoothstep(0.38, 0.5, a))
	var strike := smoothstep(0.38, 0.5, a) * (1.0 - smoothstep(0.62, 1.0, a))
	if crawling:
		tgt["UpperArmL"] = tgt.get("UpperArmL", Vector3.ZERO).lerp(Vector3(3.0, 0, -0.6), wind).lerp(Vector3(2.2, 0, 0.1), strike)
		tgt["UpperArmR"] = tgt.get("UpperArmR", Vector3.ZERO).lerp(Vector3(3.0, 0, 0.6), wind).lerp(Vector3(2.2, 0, -0.1), strike)
		tgt["Jaw"] = Vector3(-0.6 * strike, 0, 0)
		return
	match attack_kind:
		1:
			# Right hook: arm cocks out to the side, then sweeps across the body
			tgt["UpperArmR"] = tgt.get("UpperArmR", Vector3.ZERO).lerp(Vector3(1.4, -0.6, 1.3), wind).lerp(Vector3(1.3, 0.9, -0.5), strike)
			tgt["ForearmR"] = tgt.get("ForearmR", Vector3.ZERO).lerp(Vector3(1.2, 0, 0), wind).lerp(Vector3(0.3, 0, 0), strike)
			tgt["Chest"] = tgt.get("Chest", Vector3.ZERO).lerp(Vector3(0.05, 0.45, 0), wind).lerp(Vector3(-0.2, -0.55, 0), strike)
			tgt["Spine"] = tgt.get("Spine", Vector3.ZERO).lerp(Vector3(0.0, 0.25, 0), wind).lerp(Vector3(-0.35, -0.3, 0), strike)
			tgt["UpperArmL"] = tgt.get("UpperArmL", Vector3.ZERO).lerp(Vector3(0.6, 0, -0.3), maxf(wind, strike))
			tgt["Jaw"] = Vector3(-0.15 - 0.4 * strike, 0, 0)
		2:
			# Lunge: both hands grab forward, head darts in and bites
			var grab := smoothstep(0.0, 0.45, a) * (1.0 - smoothstep(0.75, 1.0, a))
			var bite := smoothstep(0.45, 0.6, a) * (1.0 - smoothstep(0.7, 0.95, a))
			tgt["UpperArmL"] = tgt.get("UpperArmL", Vector3.ZERO).lerp(Vector3(1.55, 0, 0.18), grab)
			tgt["UpperArmR"] = tgt.get("UpperArmR", Vector3.ZERO).lerp(Vector3(1.55, 0, -0.18), grab)
			tgt["ForearmL"] = tgt.get("ForearmL", Vector3.ZERO).lerp(Vector3(0.9, 0, 0), bite)
			tgt["ForearmR"] = tgt.get("ForearmR", Vector3.ZERO).lerp(Vector3(0.9, 0, 0), bite)
			tgt["Spine"] = tgt.get("Spine", Vector3.ZERO).lerp(Vector3(-0.55, 0, 0), grab)
			tgt["Head"] = tgt.get("Head", Vector3.ZERO).lerp(Vector3(0.75, 0, 0), bite)
			tgt["Jaw"] = Vector3(-0.1 - 0.7 * bite, 0, 0)
		_:
			var up_l := Vector3(2.5, 0, -0.45)
			var up_r := Vector3(2.5, 0, 0.45)
			var down_l := Vector3(0.75, 0, 0.25)
			var down_r := Vector3(0.75, 0, -0.25)
			tgt["UpperArmL"] = tgt.get("UpperArmL", Vector3.ZERO).lerp(up_l, wind).lerp(down_l, strike)
			tgt["UpperArmR"] = tgt.get("UpperArmR", Vector3.ZERO).lerp(up_r, wind).lerp(down_r, strike)
			tgt["ForearmL"] = tgt.get("ForearmL", Vector3.ZERO).lerp(Vector3(0.6, 0, 0), wind).lerp(Vector3(0.15, 0, 0), strike)
			tgt["ForearmR"] = tgt.get("ForearmR", Vector3.ZERO).lerp(Vector3(0.6, 0, 0), wind).lerp(Vector3(0.15, 0, 0), strike)
			tgt["Spine"] = tgt.get("Spine", Vector3.ZERO).lerp(Vector3(0.12, 0, 0), wind).lerp(Vector3(-0.6, 0, 0), strike)
			tgt["Chest"] = tgt.get("Chest", Vector3.ZERO).lerp(Vector3(0.08, 0, 0), wind).lerp(Vector3(-0.25, 0, 0), strike)
			tgt["Head"] = tgt.get("Head", Vector3.ZERO).lerp(Vector3(0.5, 0, 0), wind).lerp(Vector3(0.1, 0, 0), strike)
			tgt["Jaw"] = Vector3(-0.15 - 0.55 * strike, 0, 0)
