class_name SkinRigAdapter
extends Node
# Bridges skinned characters (one smooth mesh on a Skeleton3D) to the
# game's joint-based systems. It builds invisible "proxy" joint nodes that
# mirror the skeleton's rest pose (same names: Hips, Chest, ThighL...).
# The procedural rig rotates those proxies and ragdolls carry them around
# exactly as they did the old rigid body-part pivots; every frame this node
# copies the proxies onto the bones, so the mesh bends smoothly with them.
# A proxy that is hidden or scaled to zero collapses its bone (crawlers).

var skel: Skeleton3D
var proxy_root: Node3D
var _order: Array[int] = []
var _proxies: Array[Node3D] = []
var _rest: Array[Basis] = []
var _globals: Array[Transform3D] = []


# Returns the node to bind the rig to (the proxy root), or null when the
# model has no skeleton (old rigid models are used as before).
static func attach(model: Node) -> Node3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var a := SkinRigAdapter.new()
	a.name = "SkinRigAdapter"
	a.process_priority = 100 # after the rig has posed the proxies
	a._setup(found[0] as Skeleton3D)
	model.add_child(a)
	return a.proxy_root


func _setup(s: Skeleton3D) -> void:
	skel = s
	proxy_root = Node3D.new()
	proxy_root.name = "JointProxies"
	s.get_parent().add_child(proxy_root)
	proxy_root.transform = s.transform
	var n := s.get_bone_count()
	_proxies.resize(n)
	_rest.resize(n)
	_globals.resize(n)
	var done: Array[bool] = []
	done.resize(n)
	done.fill(false)
	while _order.size() < n:
		for i in range(n):
			if done[i]:
				continue
			var par := s.get_bone_parent(i)
			if par >= 0 and not done[par]:
				continue
			var g := s.get_bone_global_rest(i)
			var p := Node3D.new()
			p.name = s.get_bone_name(i)
			var parent_node: Node3D = proxy_root if par < 0 else _proxies[par]
			var parent_origin := Vector3.ZERO if par < 0 else s.get_bone_global_rest(par).origin
			parent_node.add_child(p)
			p.position = g.origin - parent_origin
			_proxies[i] = p
			_rest[i] = g.basis.orthonormalized()
			done[i] = true
			_order.append(i)


var _skip: int = 0
var _last_phys: int = -1


func _process(_delta: float) -> void:
	if not is_instance_valid(skel) or not skel.is_visible_in_tree():
		return # hidden (dead, sunk): nothing to draw
	# The rig and ragdoll move the joints in physics steps (60/s); copying them
	# again on frames in between (144 Hz screens) is wasted work.
	var pf := Engine.get_physics_frames()
	if pf == _last_phys:
		return
	_last_phys = pf
	# Far away or behind the camera: update the pose less often
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to := skel.global_position - cam.global_position
		var d2 := to.length_squared()
		var every := 1
		if d2 > 900.0:
			every = 3
		elif d2 > 225.0:
			every = 2
		if d2 > 16.0 and to.dot(-cam.global_basis.z) < 0.0:
			every = 4
		_skip += 1
		if _skip < every:
			return
		_skip = 0
	var inv := skel.global_transform.affine_inverse()
	for i in _order:
		var px := _proxies[i]
		if not is_instance_valid(px):
			continue
		var gp := inv * px.global_transform
		if not px.is_visible_in_tree():
			gp.basis = gp.basis.scaled(Vector3(0.001, 0.001, 0.001))
		var desired := Transform3D(gp.basis * _rest[i], gp.origin)
		_globals[i] = desired
		var par := skel.get_bone_parent(i)
		var local := desired if par < 0 else _globals[par].affine_inverse() * desired
		var sc := local.basis.get_scale()
		skel.set_bone_pose_position(i, local.origin)
		if sc.x > 0.0001 and sc.y > 0.0001 and sc.z > 0.0001:
			skel.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())
		skel.set_bone_pose_scale(i, sc)
