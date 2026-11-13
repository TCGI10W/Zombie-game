class_name HitboxRig
extends RefCounted
## Precision per-bone hurtboxes and cached exact trimesh world ballistic colliders.
##
## Separates coarse movement/navigation physics (layers 1..32, where layer 32 is
## ragdolls and layer 16 is barricade blockers) from pixel-exact bullet raycasts
## and sweeps:
##   - Layer 7 (64):  HITBOX_LAYER — animated per-limb / per-part Area3D hurtboxes.
##   - Layer 8 (128): BALLISTIC_WORLD_LAYER — exact trimesh prop meshes & architecture.

const HITBOX_LAYER: int = 64
const BALLISTIC_WORLD_LAYER: int = 128
const BULLET_MASK: int = HITBOX_LAYER | BALLISTIC_WORLD_LAYER

static var _trimesh_cache: Dictionary = {}


static func _basis_y_along(dir: Vector3) -> Basis:
	var y_axis: Vector3 = dir.normalized()
	if y_axis.length_squared() < 0.0001:
		return Basis.IDENTITY
	var ref_z := Vector3.FORWARD if absf(y_axis.dot(Vector3.FORWARD)) < 0.94 else Vector3.RIGHT
	var x_axis := y_axis.cross(ref_z).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


static func _make_hurtbox(owner_node: Node3D, zone: String, dmg_mult: float, shape: Shape3D, local_xf: Transform3D, surface: String = "flesh") -> Area3D:
	var area := Area3D.new()
	area.name = "HB_%s" % zone
	area.monitoring = false
	area.monitorable = true
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = 0
	area.set_meta("hit_owner", owner_node)
	area.set_meta("hit_zone", zone)
	area.set_meta("dmg_mult", dmg_mult)
	area.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = local_xf
	area.add_child(cs)
	return area


static func register_hurtbox(area: Area3D, owner_node: Node3D, zone: String = "torso", dmg_mult: float = 1.0, surface: String = "flesh") -> Area3D:
	area.monitoring = false
	area.monitorable = true
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = 0
	area.set_meta("hit_owner", owner_node)
	area.set_meta("hit_zone", zone)
	area.set_meta("dmg_mult", dmg_mult)
	area.set_meta("surface", surface)
	return area


static func _add_segment_capsule(parent_joint: Node3D, end_local: Vector3, radius: float, extra_tail: float, owner_node: Node3D, zone: String, dmg_mult: float) -> Area3D:
	var dir_vec := end_local
	if dir_vec.length_squared() < 0.0016:
		dir_vec = Vector3(0.0, -0.28, 0.0)
	var seg_end := dir_vec + dir_vec.normalized() * extra_tail
	var len_seg := seg_end.length()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(len_seg + radius * 2.0, radius * 2.15)
	var xf := Transform3D(_basis_y_along(seg_end), seg_end * 0.5)
	var area := _make_hurtbox(owner_node, zone, dmg_mult, cap, xf)
	parent_joint.add_child(area)
	return area


## Attach animated per-bone Area3D hurtboxes directly onto SkinRigAdapter proxy joints.
static func attach_humanoid(owner_node: Node3D, nodes: Dictionary, is_crawler: bool = false) -> Array[Area3D]:
	var areas: Array[Area3D] = []
	if owner_node == null or nodes.is_empty():
		return areas

	if nodes.has("Head") and is_instance_valid(nodes["Head"]):
		var cap_h := CapsuleShape3D.new()
		cap_h.radius = 0.125
		cap_h.height = 0.28
		var a_h := _make_hurtbox(owner_node, "head", 1.0, cap_h, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.14, -0.02)))
		(nodes["Head"] as Node3D).add_child(a_h)
		areas.append(a_h)

	if nodes.has("Chest") and is_instance_valid(nodes["Chest"]):
		var bx_c := BoxShape3D.new()
		bx_c.size = Vector3(0.34, 0.26, 0.24)
		var a_c := _make_hurtbox(owner_node, "torso", 1.0, bx_c, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)))
		(nodes["Chest"] as Node3D).add_child(a_c)
		areas.append(a_c)

	if nodes.has("Spine") and is_instance_valid(nodes["Spine"]):
		var bx_s := BoxShape3D.new()
		bx_s.size = Vector3(0.31, 0.20, 0.23)
		var a_s := _make_hurtbox(owner_node, "torso", 1.0, bx_s, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.09, 0.0)))
		(nodes["Spine"] as Node3D).add_child(a_s)
		areas.append(a_s)

	if nodes.has("Hips") and is_instance_valid(nodes["Hips"]):
		var bx_p := BoxShape3D.new()
		bx_p.size = Vector3(0.32, 0.22, 0.24)
		var a_p := _make_hurtbox(owner_node, "pelvis", 0.95, bx_p, Transform3D(Basis.IDENTITY, Vector3.ZERO))
		(nodes["Hips"] as Node3D).add_child(a_p)
		areas.append(a_p)

	if nodes.has("UpperArmL") and is_instance_valid(nodes["UpperArmL"]):
		var end_l: Vector3 = (nodes["ForearmL"] as Node3D).position if nodes.has("ForearmL") else Vector3(0.0, -0.26, 0.0)
		areas.append(_add_segment_capsule(nodes["UpperArmL"] as Node3D, end_l, 0.068, 0.0, owner_node, "arm_l", 0.85))
	if nodes.has("ForearmL") and is_instance_valid(nodes["ForearmL"]):
		var end_hl: Vector3 = (nodes["HandL"] as Node3D).position if nodes.has("HandL") else Vector3(0.0, -0.24, 0.0)
		areas.append(_add_segment_capsule(nodes["ForearmL"] as Node3D, end_hl, 0.060, 0.09, owner_node, "arm_l", 0.85))

	if nodes.has("UpperArmR") and is_instance_valid(nodes["UpperArmR"]):
		var end_r: Vector3 = (nodes["ForearmR"] as Node3D).position if nodes.has("ForearmR") else Vector3(0.0, -0.26, 0.0)
		areas.append(_add_segment_capsule(nodes["UpperArmR"] as Node3D, end_r, 0.068, 0.0, owner_node, "arm_r", 0.85))
	if nodes.has("ForearmR") and is_instance_valid(nodes["ForearmR"]):
		var end_hr: Vector3 = (nodes["HandR"] as Node3D).position if nodes.has("HandR") else Vector3(0.0, -0.24, 0.0)
		areas.append(_add_segment_capsule(nodes["ForearmR"] as Node3D, end_hr, 0.060, 0.09, owner_node, "arm_r", 0.85))

	if not is_crawler:
		if nodes.has("ThighL") and is_instance_valid(nodes["ThighL"]):
			var end_sl: Vector3 = (nodes["ShinL"] as Node3D).position if nodes.has("ShinL") else Vector3(0.0, -0.42, 0.0)
			areas.append(_add_segment_capsule(nodes["ThighL"] as Node3D, end_sl, 0.092, 0.0, owner_node, "leg_l", 0.82))
		if nodes.has("ShinL") and is_instance_valid(nodes["ShinL"]):
			var end_fl: Vector3 = (nodes["FootL"] as Node3D).position if nodes.has("FootL") else Vector3(0.0, -0.42, 0.0)
			areas.append(_add_segment_capsule(nodes["ShinL"] as Node3D, end_fl, 0.078, 0.07, owner_node, "leg_l", 0.82))
		if nodes.has("ThighR") and is_instance_valid(nodes["ThighR"]):
			var end_sr: Vector3 = (nodes["ShinR"] as Node3D).position if nodes.has("ShinR") else Vector3(0.0, -0.42, 0.0)
			areas.append(_add_segment_capsule(nodes["ThighR"] as Node3D, end_sr, 0.092, 0.0, owner_node, "leg_r", 0.82))
		if nodes.has("ShinR") and is_instance_valid(nodes["ShinR"]):
			var end_fr: Vector3 = (nodes["FootR"] as Node3D).position if nodes.has("FootR") else Vector3(0.0, -0.42, 0.0)
			areas.append(_add_segment_capsule(nodes["ShinR"] as Node3D, end_fr, 0.078, 0.07, owner_node, "leg_r", 0.82))

	return areas


## Attach per-part AABB hurtboxes directly to rigid boss pivot nodes.
static func attach_boss(owner_node: Node3D, visual_root: Node3D, boss_type: String = "") -> Array[Area3D]:
	var areas: Array[Area3D] = []
	if owner_node == null or visual_root == null:
		return areas
	var parts := [
		["Head", "head", 1.0],
		["Torso", "torso", 1.0],
		["ArmL", "arm_l", 0.85],
		["ArmR", "arm_r", 0.85],
		["LegL", "leg_l", 0.82],
		["LegR", "leg_r", 0.82],
	]
	var torso_piv: Node3D = null
	for entry in parts:
		var piv_name: String = entry[0]
		var zone: String = entry[1]
		var mult: float = float(entry[2])
		var piv := visual_root.find_child(piv_name, true, false) as Node3D
		if piv == null:
			continue
		if piv_name == "Torso":
			torso_piv = piv
		var has_aabb := false
		var union_aabb := AABB()
		for ch in piv.get_children():
			var mi := ch as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var aabb := mi.mesh.get_aabb()
			var xf := mi.transform
			var corners := [
				xf * aabb.position,
				xf * (aabb.position + Vector3(aabb.size.x, 0, 0)),
				xf * (aabb.position + Vector3(0, aabb.size.y, 0)),
				xf * (aabb.position + Vector3(0, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
				xf * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
				xf * (aabb.position + aabb.size),
			]
			for c in corners:
				if not has_aabb:
					union_aabb = AABB(c, Vector3.ZERO)
					has_aabb = true
				else:
					union_aabb = union_aabb.expand(c)
		if has_aabb and union_aabb.size.length_squared() > 0.001:
			var bx := BoxShape3D.new()
			bx.size = union_aabb.size.max(Vector3(0.14, 0.14, 0.14)) * 0.94
			var a := _make_hurtbox(owner_node, zone, mult, bx, Transform3D(Basis.IDENTITY, union_aabb.get_center()))
			piv.add_child(a)
			areas.append(a)

	if boss_type == "juggernaut" and torso_piv != null:
		var wp_box := BoxShape3D.new()
		wp_box.size = Vector3(0.38, 0.38, 0.24)
		var a_wp := _make_hurtbox(owner_node, "weakpoint", 1.35, wp_box, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, -0.36)))
		torso_piv.add_child(a_wp)
		areas.append(a_wp)

	return areas


## Attach per-part hurtboxes to HoundEnemy pivots.
static func attach_hound(owner_node: Node3D, pv: Dictionary) -> Array[Area3D]:
	var areas: Array[Area3D] = []
	if owner_node == null or pv.is_empty():
		return areas
	if pv.has("Head") and is_instance_valid(pv["Head"]):
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.24, 0.24, 0.32)
		var a := _make_hurtbox(owner_node, "head", 1.0, bx, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, -0.10)))
		(pv["Head"] as Node3D).add_child(a)
		areas.append(a)
	if pv.has("Neck") and is_instance_valid(pv["Neck"]):
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.24, 0.24, 0.26)
		var a := _make_hurtbox(owner_node, "torso", 1.0, bx, Transform3D(Basis.IDENTITY, Vector3.ZERO))
		(pv["Neck"] as Node3D).add_child(a)
		areas.append(a)
	if pv.has("Body") and is_instance_valid(pv["Body"]):
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.36, 0.34, 0.72)
		var a := _make_hurtbox(owner_node, "torso", 1.0, bx, Transform3D(Basis.IDENTITY, Vector3.ZERO))
		(pv["Body"] as Node3D).add_child(a)
		areas.append(a)
	for leg_key in ["FrontUpperL", "FrontUpperR", "HindUpperL", "HindUpperR"]:
		if pv.has(leg_key) and is_instance_valid(pv[leg_key]):
			var cap := CapsuleShape3D.new()
			cap.radius = 0.065
			cap.height = 0.38
			var zone := "leg_l" if leg_key.ends_with("L") else "leg_r"
			var a := _make_hurtbox(owner_node, zone, 0.85, cap, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.16, 0.0)))
			(pv[leg_key] as Node3D).add_child(a)
			areas.append(a)
	return areas


## Attach physical metal hurtbox to a zombie's Riot Shield mesh.
static func attach_shield(owner_node: Node3D, shield_mesh: Node3D) -> Area3D:
	if owner_node == null or shield_mesh == null:
		return null
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.64, 1.02, 0.08)
	var a := _make_hurtbox(owner_node, "shield", 0.08, bx, Transform3D(Basis.IDENTITY, Vector3.ZERO), "metal")
	shield_mesh.add_child(a)
	return a


## Attach dynamic crouch-aware hurtboxes on local PlayerController for PvP bot hitscan.
static func attach_local_player(player: Node3D) -> Dictionary:
	var out: Dictionary = {"head": null, "torso": null, "legs": null, "areas": []}
	if player == null:
		return out
	var sp_h := SphereShape3D.new()
	sp_h.radius = 0.14
	var a_h := _make_hurtbox(player, "head", 1.0, sp_h, Transform3D.IDENTITY)
	a_h.position = Vector3(0.0, 1.62, 0.0)
	player.add_child(a_h)

	var cap_t := CapsuleShape3D.new()
	cap_t.radius = 0.21
	cap_t.height = 0.68
	var a_t := _make_hurtbox(player, "torso", 1.0, cap_t, Transform3D.IDENTITY)
	a_t.position = Vector3(0.0, 1.15, 0.0)
	player.add_child(a_t)

	var cap_l := CapsuleShape3D.new()
	cap_l.radius = 0.20
	cap_l.height = 0.76
	var a_l := _make_hurtbox(player, "leg_l", 0.82, cap_l, Transform3D.IDENTITY)
	a_l.position = Vector3(0.0, 0.42, 0.0)
	player.add_child(a_l)

	out["head"] = a_h
	out["torso"] = a_t
	out["legs"] = a_l
	out["areas"] = [a_h, a_t, a_l]
	return out


static func update_local_player(hb: Dictionary, crouch_t: float, alive: bool = true) -> void:
	if hb.is_empty():
		return
	var ct := clampf(crouch_t, 0.0, 1.0)
	var a_h := hb.get("head") as Area3D
	var a_t := hb.get("torso") as Area3D
	var a_l := hb.get("legs") as Area3D
	if a_h:
		a_h.position.y = lerpf(1.62, 1.14, ct)
		a_h.monitorable = alive
		a_h.collision_layer = HITBOX_LAYER if alive else 0
	if a_t:
		a_t.position.y = lerpf(1.15, 0.76, ct)
		a_t.monitorable = alive
		a_t.collision_layer = HITBOX_LAYER if alive else 0
	if a_l:
		a_l.position.y = lerpf(0.42, 0.28, ct)
		a_l.monitorable = alive
		a_l.collision_layer = HITBOX_LAYER if alive else 0


static func set_enabled(areas: Array, enabled: bool) -> void:
	for item in areas:
		var a := item as Area3D
		if is_instance_valid(a):
			a.monitorable = enabled
			a.collision_layer = HITBOX_LAYER if enabled else 0


static func release_and_free(areas: Array) -> void:
	for item in areas:
		var a := item as Area3D
		if is_instance_valid(a):
			a.monitorable = false
			a.collision_layer = 0
			var par := a.get_parent()
			if par != null:
				par.remove_child(a)
			a.queue_free()
	areas.clear()


## Attach a cached exact ConcavePolygonShape3D StaticBody3D on BALLISTIC_WORLD_LAYER
## matching every MeshInstance3D in `visual_root`.
static func attach_ballistic_trimesh(visual_root: Node3D, surface: String = "metal") -> StaticBody3D:
	if visual_root == null:
		return null
	var meshes := visual_root.find_children("*", "MeshInstance3D", true, false)
	if visual_root is MeshInstance3D:
		meshes.push_front(visual_root)
	if meshes.is_empty():
		return null

	var sb := StaticBody3D.new()
	sb.name = "BallisticMesh"
	sb.collision_layer = BALLISTIC_WORLD_LAYER
	sb.collision_mask = 0
	sb.set_meta("surface", surface)

	var added := 0
	for item in meshes:
		var mi := item as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var key := mi.mesh.resource_path
		if key == "":
			key = "id:%d" % mi.mesh.get_instance_id()
		var shape: ConcavePolygonShape3D = _trimesh_cache.get(key) as ConcavePolygonShape3D
		if shape == null:
			var gen := mi.mesh.create_trimesh_shape()
			if gen == null:
				continue
			gen.backface_collision = true
			_trimesh_cache[key] = gen
			shape = gen
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = _relative_transform(visual_root, mi)
		sb.add_child(cs)
		added += 1

	if added == 0:
		sb.free()
		return null
	visual_root.add_child(sb)
	return sb


static func _relative_transform(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = descendant
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Resolve a physics ray/sweep collider into owner, zone, damage multiplier, surface, and penetrability.
static func resolve_hit(collider: Object) -> Dictionary:
	if collider == null:
		return {"owner": null, "zone": "", "dmg_mult": 1.0, "surface": "stone", "penetrable": false}
	if collider.has_meta("hit_owner"):
		var zone := String(collider.get_meta("hit_zone", "torso"))
		var default_surf := "metal" if zone == "shield" else "flesh"
		return {
			"owner": collider.get_meta("hit_owner"),
			"zone": zone,
			"dmg_mult": float(collider.get_meta("dmg_mult", 1.0)),
			"surface": String(collider.get_meta("surface", default_surf)),
			"penetrable": false,
		}
	return {
		"owner": collider,
		"zone": "",
		"dmg_mult": 1.0,
		"surface": String(collider.get_meta("surface", "stone")),
		"penetrable": bool(collider.get_meta("penetrable", false)),
	}
