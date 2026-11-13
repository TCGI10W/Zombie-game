extends Node3D
# Physics ragdoll built on the fly from a dead zombie's jointed model. Every
# limb pivot becomes a rigid body with a capsule, linked by cone-twist joints
# (waist, neck, shoulders, hips) and limited hinges (elbows, knees). The
# zombie's own pivots are re-parented onto the bodies, so the same meshes
# tumble with the force of the killing shot. Bodies sleep, then sink away.

const LAYER := 32 # ragdoll parts only collide with the world
const MAX_ACTIVE := 10
const LIFETIME := 3.4
const SINK_TIME := 1.4

# [pivot, parent segment, mass, radius, capsule end pivot]
const SEGMENTS := [
	["Hips", "", 11.0, 0.13, ""],
	["Spine", "Hips", 16.0, 0.155, "Head"],
	["Head", "Spine", 4.5, 0.11, ""],
	["UpperArmL", "Spine", 2.4, 0.055, "ForearmL"],
	["ForearmL", "UpperArmL", 1.7, 0.045, "HandL"],
	["UpperArmR", "Spine", 2.4, 0.055, "ForearmR"],
	["ForearmR", "UpperArmR", 1.7, 0.045, "HandR"],
	["ThighL", "Hips", 7.0, 0.075, "ShinL"],
	["ShinL", "ThighL", 4.0, 0.055, "FootL"],
	["ThighR", "Hips", 7.0, 0.075, "ShinR"],
	["ShinR", "ThighR", 4.0, 0.055, "FootR"],
]
# Cone limits in degrees: [swing, twist]
const CONES := {"Spine": [28.0, 22.0], "Head": [45.0, 35.0], "UpperArmL": [85.0, 45.0], "UpperArmR": [85.0, 45.0],
	"ThighL": [65.0, 20.0], "ThighR": [65.0, 20.0]}
# Hinge limits in radians around the body's right axis: knees fold back,
# elbows fold forward.
const HINGES := {"ShinL": Vector2(-0.05, 2.3), "ShinR": Vector2(-0.05, 2.3),
	"ForearmL": Vector2(-2.4, 0.05), "ForearmR": Vector2(-2.4, 0.05)}

static var active_count: int = 0
static var _phys_mat: PhysicsMaterial

var bodies: Dictionary = {}
var persist_corpse: bool = false
var _t: float = 0.0
var _frozen: bool = false
var _shock: float = 0.0
var _consumed: bool = false


static var _spawn_frame: int = -1
static var _spawned_this_frame: int = 0


# At most 2 new ragdolls per frame so a big blast doesn't stall one frame;
# the rest play the normal death animation.
static func can_spawn() -> bool:
	if active_count >= MAX_ACTIVE:
		return false
	var f := Engine.get_physics_frames()
	if f != _spawn_frame:
		_spawn_frame = f
		_spawned_this_frame = 0
	if _spawned_this_frame >= 2:
		return false
	_spawned_this_frame += 1
	return true


func _enter_tree() -> void:
	active_count += 1


func _exit_tree() -> void:
	active_count = maxi(0, active_count - 1)


# nodes: the rig's joint pivots. root_basis: the zombie's orientation.
# Returns false when the skeleton is incomplete (caller falls back).
func build(nodes: Dictionary, root_basis: Basis, scale_f: float, base_vel: Vector3, hit_point: Vector3, impulse: Vector3, blast_center: Vector3 = Vector3.INF, blast_force: float = 0.0, shock: float = 0.0) -> bool:
	if not (nodes.has("Hips") and nodes.has("Spine") and nodes.has("Head")):
		return false
	if _phys_mat == null:
		_phys_mat = PhysicsMaterial.new()
		_phys_mat.friction = 0.9
		_phys_mat.bounce = 0.05
	_shock = shock
	var right := root_basis.x.normalized()
	var up := root_basis.y.normalized()

	# Read every pivot's pose before anything is re-parented
	var pos: Dictionary = {}
	for j in nodes:
		pos[j] = (nodes[j] as Node3D).global_position

	for seg in SEGMENTS:
		var nm: String = seg[0]
		if not nodes.has(nm):
			continue
		var piv: Node3D = nodes[nm]
		if not piv.is_visible_in_tree() and nm != "Head":
			continue
		if seg[1] != "" and not bodies.has(seg[1]):
			continue
		var body := RigidBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = 1
		body.mass = float(seg[2])
		body.linear_damp = 0.12
		body.angular_damp = 1.6
		body.physics_material_override = _phys_mat
		body.continuous_cd = true
		add_child(body)
		body.global_transform = Transform3D(piv.global_basis.orthonormalized(), pos[nm])

		var start: Vector3 = pos[nm]
		var r: float = float(seg[3]) * scale_f
		var cs := CollisionShape3D.new()
		if nm == "Hips":
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.34, 0.2, 0.22) * scale_f
			cs.shape = bx
			body.add_child(cs)
			cs.global_transform = Transform3D(Basis(right, up, right.cross(up)), start - up * 0.04 * scale_f)
		elif nm == "Head":
			var sp := SphereShape3D.new()
			sp.radius = r
			cs.shape = sp
			body.add_child(cs)
			cs.global_position = start + up * 0.14 * scale_f
		else:
			var end: Vector3 = pos.get(seg[4], start - up * 0.3 * scale_f)
			var dir := end - start
			if nm.begins_with("Forearm"):
				end += dir.normalized() * (0.09 * scale_f) # hand
				dir = end - start
			var ln := maxf(dir.length(), 0.05)
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(ln + r * 2.0, r * 2.0 + 0.01)
			cs.shape = cap
			body.add_child(cs)
			cs.global_transform = Transform3D(_basis_along(dir.normalized(), Vector3.FORWARD), (start + end) * 0.5)

		piv.reparent(body, true)
		bodies[nm] = body
		body.linear_velocity = base_vel

	if bodies.size() < 3:
		return false

	# Joints at each child pivot
	for seg in SEGMENTS:
		var nm: String = seg[0]
		if seg[1] == "" or not bodies.has(nm) or not bodies.has(seg[1]):
			continue
		var anchor: Vector3 = pos[nm]
		var end2: Vector3 = pos.get(seg[4], anchor - up * 0.3)
		var dir2 := (end2 - anchor).normalized() if nm != "Head" else up
		var joint: Joint3D
		if HINGES.has(nm):
			var hj := HingeJoint3D.new()
			var lim: Vector2 = HINGES[nm]
			hj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lim.x)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, lim.y)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_BIAS, 0.6)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
			var x := (dir2 - right * dir2.dot(right)).normalized()
			joint = hj
			add_child(hj)
			hj.global_transform = Transform3D(Basis(x, right.cross(x), right), anchor)
		else:
			var cj := ConeTwistJoint3D.new()
			var lim2: Array = CONES.get(nm, [40.0, 20.0])
			cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(float(lim2[0])))
			cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(float(lim2[1])))
			cj.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
			cj.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.9)
			joint = cj
			add_child(cj)
			cj.global_transform = Transform3D(_basis_along_x(dir2, up), anchor)
		joint.node_a = joint.get_path_to(bodies[seg[1]])
		joint.node_b = joint.get_path_to(bodies[nm])
		# Remember the anchor on both bodies to hold the joint together
		var pb: RigidBody3D = bodies[seg[1]]
		var cb: RigidBody3D = bodies[nm]
		_links.append([pb, cb, pb.global_transform.affine_inverse() * anchor, cb.global_transform.affine_inverse() * anchor])

	# The killing blow: push the body part nearest the hit
	if impulse != Vector3.ZERO:
		var best: RigidBody3D = null
		var best_d := 1e9
		for nm2 in bodies:
			var b: RigidBody3D = bodies[nm2]
			var d := b.global_position.distance_to(hit_point)
			if d < best_d:
				best_d = d
				best = b
		# Most of the shove moves the whole body; only a part twists the hit limb,
		# so big hits don't tear the joints apart
		var total_mass := 0.0
		for nm4 in bodies:
			total_mass += (bodies[nm4] as RigidBody3D).mass
		for nm4 in bodies:
			var bb4: RigidBody3D = bodies[nm4]
			bb4.apply_central_impulse(impulse * 0.75 * bb4.mass / maxf(total_mass, 0.1))
		if best:
			best.apply_impulse(impulse * 0.25, hit_point - best.global_position)
	if blast_center != Vector3.INF and blast_force > 0.0:
		for nm3 in bodies:
			var b2: RigidBody3D = bodies[nm3]
			var away := b2.global_position - blast_center
			var dist := maxf(away.length(), 0.5)
			var push := (away.normalized() + Vector3.UP * 0.8).normalized() * blast_force * b2.mass / dist
			b2.apply_central_impulse(push)
			b2.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	return true


func _physics_process(delta: float) -> void:
	_t += delta
	_hold_joints()
	# Safety: never let a solver hiccup fling a body across the map
	for nm0 in bodies:
		var bb: RigidBody3D = bodies[nm0]
		if bb.linear_velocity.length() > 14.0:
			bb.linear_velocity = bb.linear_velocity.limit_length(14.0)
		if bb.angular_velocity.length() > 25.0:
			bb.angular_velocity = bb.angular_velocity.limit_length(25.0)
		if not _frozen and bb.global_position.y < 0.04:
			# Never sink through the floor slab
			bb.global_position.y = 0.06
			if bb.linear_velocity.y < 0.0:
				bb.linear_velocity.y = 0.0
	if _shock > 0.0:
		# Electrocution: limbs spasm for a moment before going limp
		_shock -= delta
		for nm in bodies:
			if randf() < 0.25:
				var b: RigidBody3D = bodies[nm]
				b.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(0.1, 0.6), randf_range(-1, 1)) * b.mass * 0.16)
	if not _frozen and _t > LIFETIME:
		_frozen = true
		for nm in bodies:
			var b: RigidBody3D = bodies[nm]
			if not is_instance_valid(b):
				continue
			b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			b.freeze = true
			b.collision_layer = 0
			if not persist_corpse:
				b.create_tween().tween_property(b, "global_position:y", b.global_position.y - 1.1, SINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if not persist_corpse:
			create_tween().tween_callback(queue_free).set_delay(SINK_TIME + 0.1)


func corpse_center() -> Vector3:
	for k in ["Spine", "Hips", "Head"]:
		if bodies.has(k) and is_instance_valid(bodies[k]):
			return (bodies[k] as RigidBody3D).global_position
	return global_position + Vector3(0, 0.25, 0)


func twitch_corpse(intensity: float = 1.0) -> void:
	if _consumed:
		return
	for nm in bodies:
		var b: RigidBody3D = bodies[nm]
		if not is_instance_valid(b) or b.freeze:
			continue
		if randf() < 0.45:
			b.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), randf_range(0.35, 1.1), randf_range(-0.6, 0.6)) * b.mass * intensity * 0.45)


func consume_and_free(dur: float = 0.35) -> void:
	if _consumed:
		return
	_consumed = true
	_frozen = true
	var d := maxf(dur, 0.05)
	for nm in bodies:
		var b: RigidBody3D = bodies[nm]
		if not is_instance_valid(b):
			continue
		b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		b.freeze = true
		b.collision_layer = 0
		var tw := b.create_tween()
		tw.tween_property(b, "global_position:y", b.global_position.y - 0.85, d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	create_tween().tween_callback(queue_free).set_delay(d + 0.05)


# Basis whose Y axis points along `dir` (for capsules).
static func _basis_along(dir: Vector3, hint: Vector3) -> Basis:
	var y := dir
	var h := hint if absf(y.dot(hint)) < 0.95 else Vector3.RIGHT
	var x := y.cross(h).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# Basis whose X axis points along `dir` (cone-twist axis).
static func _basis_along_x(dir: Vector3, hint: Vector3) -> Basis:
	var x := dir.normalized()
	var h := hint if absf(x.dot(hint)) < 0.95 else Vector3.FORWARD
	var z := x.cross(h).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


var _links: Array = [] # [parent body, child body, anchor in parent, anchor in child]


# The physics joints are soft; on big hits they stretch, which tears a
# skinned body into long shards. Pull every child body back onto its joint
# each step (parents first) and share velocity across the joint.
func _hold_joints() -> void:
	if _frozen:
		return
	for l in _links:
		var pb: RigidBody3D = l[0]
		var cb: RigidBody3D = l[1]
		if not is_instance_valid(pb) or not is_instance_valid(cb):
			continue
		var ap: Vector3 = pb.global_transform * (l[2] as Vector3)
		var ac: Vector3 = cb.global_transform * (l[3] as Vector3)
		var gap := ap - ac
		if gap.length() > 0.02:
			cb.global_position += gap
			cb.linear_velocity = cb.linear_velocity.lerp(pb.linear_velocity, 0.5)
