extends Node
# Global visual effects: decals (blood, bullet holes, scorch), ejected shell
# casings, gore chunks, dust puffs and blood sprays. Everything is capped so
# long fights don't pile up nodes.

const MAX_BLOOD := 72
const MAX_HOLES := 60
const MAX_GORE := 24
const MAX_PUFFS := 24
const MAX_CASINGS := 30

var _blood: Array[Node3D] = []
var _holes: Array[Node3D] = []
var _gore: Array[Node3D] = []
var _casings: Array[Node3D] = []

var _tex_blood: Array[Texture2D] = []
var _tex_hole: Texture2D
var _tex_scorch: Texture2D
var _mat_brass: StandardMaterial3D
var _mat_shell: StandardMaterial3D
var _mat_gore: StandardMaterial3D
var _mat_gore2: StandardMaterial3D
var _mat_dust: StandardMaterial3D
var _mat_spray: StandardMaterial3D
var _mat_spark_metal: StandardMaterial3D
var _mat_splinter_wood: StandardMaterial3D
var _mat_sand_puff: StandardMaterial3D
var _mesh_casing: CylinderMesh
var _mesh_shell: CylinderMesh


func _ready() -> void:
	for i in range(1, 4):
		var p := "res://assets/textures/decal_blood_%d.png" % i
		if ResourceLoader.exists(p):
			_tex_blood.append(load(p))
	if ResourceLoader.exists("res://assets/textures/decal_bullet_hole.png"):
		_tex_hole = load("res://assets/textures/decal_bullet_hole.png")
	if ResourceLoader.exists("res://assets/textures/decal_scorch.png"):
		_tex_scorch = load("res://assets/textures/decal_scorch.png")

	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color(0.85, 0.62, 0.25)
	_mat_brass.metallic = 0.9
	_mat_brass.roughness = 0.3
	_mat_shell = StandardMaterial3D.new()
	_mat_shell.albedo_color = Color(0.7, 0.1, 0.08)
	_mat_shell.roughness = 0.5
	_mat_gore = StandardMaterial3D.new()
	_mat_gore.albedo_color = Color(0.28, 0.02, 0.02)
	_mat_gore.roughness = 0.35
	_mat_gore2 = StandardMaterial3D.new()
	_mat_gore2.albedo_color = Color(0.45, 0.32, 0.28)
	_mat_gore2.roughness = 0.6
	_mat_dust = _sprite_mat(Color(0.55, 0.52, 0.48, 0.5))
	_mat_spray = _sprite_mat(Color(0.16, 0.006, 0.006, 0.92))
	_mat_spark_metal = _sprite_mat(Color(1.0, 0.76, 0.28, 0.95))
	_mat_splinter_wood = _sprite_mat(Color(0.68, 0.48, 0.26, 0.90))
	_mat_sand_puff = _sprite_mat(Color(0.76, 0.66, 0.46, 0.62))

	_mesh_casing = CylinderMesh.new()
	_mesh_casing.top_radius = 0.005
	_mesh_casing.bottom_radius = 0.005
	_mesh_casing.height = 0.024
	_mesh_casing.radial_segments = 6
	_mesh_shell = CylinderMesh.new()
	_mesh_shell.top_radius = 0.011
	_mesh_shell.bottom_radius = 0.011
	_mesh_shell.height = 0.06
	_mesh_shell.radial_segments = 8


func _sprite_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	if ResourceLoader.exists("res://assets/textures/soft_particle.png"):
		m.albedo_texture = load("res://assets/textures/soft_particle.png")
	return m


func _scene() -> Node:
	return get_tree().current_scene


const DMG_POOL := 32
var _dmg_pool: Array[Label3D] = []
var _dmg_next: int = 0
var _dmg_last: Dictionary = {} # target instance id -> {i: pool index, value, t}


func _dmg_label() -> Label3D:
	var lbl: Label3D = null
	if _dmg_pool.size() < DMG_POOL:
		lbl = Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.0011
		lbl.outline_size = 9
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.render_priority = 10
		_dmg_pool.append(lbl)
	else:
		lbl = _dmg_pool[_dmg_next]
		_dmg_next = (_dmg_next + 1) % DMG_POOL
	if not is_instance_valid(lbl):
		return null
	if lbl.get_parent() != _scene():
		if lbl.get_parent():
			lbl.get_parent().remove_child(lbl)
		_scene().add_child(lbl)
	return lbl


# Floating number over a zombie the local player hit. Labels come from a small
# reused pool and quick hits on the same zombie add up into one number.
func damage_number(target: Node3D, pos: Vector3, amount: float, headshot: bool, killed: bool) -> void:
	if (not GameState.damage_numbers and not GameState.is_overdrive()) or amount <= 0.0 or _scene() == null:
		return
	for i in range(_dmg_pool.size() - 1, -1, -1):
		if not is_instance_valid(_dmg_pool[i]):
			_dmg_pool.remove_at(i) # freed with an old scene
	_dmg_next = mini(_dmg_next, maxi(0, _dmg_pool.size() - 1))
	var key := target.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	var lbl: Label3D = null
	var e: Dictionary = _dmg_last.get(key, {})
	if not e.is_empty() and now - float(e["t"]) < 0.12:
		var idx: int = e["i"]
		if idx < _dmg_pool.size() and is_instance_valid(_dmg_pool[idx]) and _dmg_pool[idx].get_meta("owner_id", 0) == key:
			lbl = _dmg_pool[idx]
			amount += float(e["value"])
	if lbl == null:
		lbl = _dmg_label()
		if lbl == null:
			return
		lbl.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0.25, randf_range(-0.25, 0.25))
	lbl.set_meta("owner_id", key)
	_dmg_last[key] = {"i": _dmg_pool.find(lbl), "value": amount, "t": now}
	if _dmg_last.size() > 96:
		_dmg_last.clear()
	lbl.visible = true
	lbl.text = str(roundi(amount))
	var col := Color(1, 1, 1)
	var fs := 30
	if headshot:
		col = Color(1.0, 0.85, 0.25)
		fs = 36
	if killed:
		col = Color(1.0, 0.32, 0.22) if not headshot else Color(1.0, 0.6, 0.15)
		fs += 8
	lbl.modulate = col
	lbl.font_size = fs
	lbl.scale = Vector3.ONE * 1.5
	if lbl.has_meta("tw"):
		var old: Tween = lbl.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var start := lbl.global_position
	var tw := lbl.create_tween()
	lbl.set_meta("tw", tw)
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "global_position", start + Vector3(0, 0.7, 0), 0.75).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tw.chain().tween_callback(func(): lbl.visible = false)


func _push(list: Array[Node3D], node: Node3D, cap: int) -> void:
	list.append(node)
	while list.size() > cap:
		var old = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# drop references to nodes freed by a scene change
	if list.size() > 0 and not is_instance_valid(list[0]):
		list.assign(list.filter(func(n): return is_instance_valid(n)))


func _decal(tex: Texture2D, pos: Vector3, normal: Vector3, size: float, depth: float, tint: Color) -> Decal:
	if tex == null or _scene() == null:
		return null
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = tint
	d.size = Vector3(size, depth, size)
	d.cull_mask = 1 # world only; zombies render on layer 2
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	_scene().add_child(d)
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var tangent := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var bitan := tangent.cross(n).normalized()
	var basis := Basis(tangent, n, bitan).rotated(n, randf() * TAU)
	d.global_transform = Transform3D(basis, pos)
	return d


func blood_decal(pos: Vector3, normal: Vector3 = Vector3.UP, size: float = 1.2) -> void:
	if _tex_blood.is_empty():
		return
	var d := _decal(_tex_blood[randi() % _tex_blood.size()], pos, normal, size * randf_range(0.8, 1.3), 0.6, Color(1, 1, 1, randf_range(0.75, 1.0)))
	if d:
		_push(_blood, d, MAX_BLOOD)


# A tinted splatter (bloater bile, scorched hound remains, ...)
func splat(pos: Vector3, size: float, tint: Color) -> void:
	if _tex_blood.is_empty():
		return
	var d := _decal(_tex_blood[randi() % _tex_blood.size()], pos, Vector3.UP, size, 0.6, tint)
	if d:
		_push(_blood, d, MAX_BLOOD)


func bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var d := _decal(_tex_hole, pos, normal, randf_range(0.07, 0.1), 0.12, Color(1, 1, 1, 0.95))
	if d:
		_push(_holes, d, MAX_HOLES)


func scorch(pos: Vector3, size: float = 3.0) -> void:
	var d := _decal(_tex_scorch, pos, Vector3.UP, size, 1.0, Color(1, 1, 1, 0.85))
	if d:
		_push(_blood, d, MAX_BLOOD)


# Bullet hitting the world: hole + dust puff + spark
func impact(pos: Vector3, normal: Vector3) -> void:
	bullet_hole(pos, normal)
	_puff(pos + normal * 0.03, normal, _mat_dust, 6, 0.5, 1.6, 0.12)


func surface_impact(_parent: Node, pos: Vector3, normal: Vector3, surface: String = "concrete") -> void:
	bullet_hole(pos, normal)
	var surf := surface.to_lower()
	match surf:
		"metal":
			_puff(pos + normal * 0.03, normal, _mat_spark_metal, 9, 0.24, 5.2, 0.045, Vector3(0, -11.0, 0))
			_puff(pos + normal * 0.03, normal, _mat_dust, 3, 0.35, 1.0, 0.08)
		"wood":
			_puff(pos + normal * 0.03, normal, _mat_splinter_wood, 7, 0.36, 2.8, 0.065, Vector3(0, -8.5, 0))
		"sand", "dirt":
			_puff(pos + normal * 0.04, normal, _mat_sand_puff, 9, 0.62, 2.1, 0.16, Vector3(0, -1.8, 0))
		_:
			_puff(pos + normal * 0.03, normal, _mat_dust, 7, 0.48, 2.0, 0.12, Vector3(0, -2.2, 0))


func blood_spray(pos: Vector3, dir: Vector3, amount: int = 10) -> void:
	_puff(pos, dir, _mat_spray, amount, 0.45, 3.2, 0.06, Vector3(0, -9.0, 0))


var _gore_meshes: Dictionary = {}
var _quads: Dictionary = {}
var _puff_curve: Curve
var _puffs: Array[Node3D] = []


func _gore_mesh(bone: bool) -> Mesh:
	if not _gore_meshes.has(bone):
		if bone:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.12
			cm.bottom_radius = 0.2
			cm.height = 2.2
			cm.radial_segments = 5
			cm.rings = 1
			_gore_meshes[bone] = cm
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.6
			sm.height = 1.2
			sm.radial_segments = 7
			sm.rings = 4
			_gore_meshes[bone] = sm
	return _gore_meshes[bone]


func _puff(pos: Vector3, dir: Vector3, mat: Material, amount: int, life: float, speed: float, size: float, grav: Vector3 = Vector3(0, 0.6, 0)) -> void:
	if _scene() == null:
		return
	for i in range(_puffs.size() - 1, -1, -1):
		if not is_instance_valid(_puffs[i]):
			_puffs.remove_at(i)
	if _puffs.size() >= MAX_PUFFS:
		return # plenty of particles on screen already
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = dir.normalized() if dir.length_squared() > 0.01 else Vector3.UP
	p.spread = 35.0
	p.gravity = grav
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	if _puff_curve == null:
		_puff_curve = Curve.new()
		_puff_curve.add_point(Vector2(0, 0.6))
		_puff_curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = _puff_curve
	var qkey := "%d:%.3f" % [mat.get_instance_id(), size]
	if not _quads.has(qkey):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		q.material = mat
		_quads[qkey] = q
	p.mesh = _quads[qkey]
	_puffs.append(p)
	_scene().add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# Brass (or a shotgun shell) flies out of the ejection port, arcs and lands.
func casing(origin: Vector3, right: Vector3, up: Vector3, is_shell: bool = false) -> void:
	var sc := _scene()
	if sc == null:
		return
	var m := MeshInstance3D.new()
	m.mesh = _mesh_shell if is_shell else _mesh_casing
	m.material_override = _mat_shell if is_shell else _mat_brass
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(m)
	m.global_position = origin
	var vel := right * randf_range(1.6, 2.6) + up * randf_range(1.4, 2.4) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	# Find the floor under the casing so it lands on it
	var floor_y := origin.y - 1.6
	var space: PhysicsDirectSpaceState3D = null
	if sc is Node3D:
		space = (sc as Node3D).get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(origin + Vector3(vel.x, 0, vel.z) * 0.35, origin + Vector3(vel.x * 0.35, -4.0, vel.z * 0.35), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			floor_y = hit["position"].y + 0.006
	var g := 9.8
	# solve origin.y + vy t - g t^2 / 2 = floor_y
	var a := 0.5 * g
	var disc := vel.y * vel.y + 4.0 * a * (origin.y - floor_y)
	var land_t := (vel.y + sqrt(maxf(disc, 0.0))) / (2.0 * a)
	land_t = clampf(land_t, 0.15, 1.5)
	var tw := m.create_tween()
	tw.tween_method(func(tt: float):
		if is_instance_valid(m):
			m.global_position = origin + Vector3(vel.x * tt, vel.y * tt - a * tt * tt, vel.z * tt)
			m.rotation = spin * tt
	, 0.0, land_t, land_t)
	tw.tween_callback(func():
		if is_instance_valid(m):
			m.rotation = Vector3(PI * 0.5, randf() * TAU, 0)
			GameState.play_sfx("shell_tink", -20.0 if not is_shell else -16.0, randf_range(0.9, 1.15))
	)
	tw.tween_interval(6.0)
	tw.tween_callback(m.queue_free)
	_push(_casings, m, MAX_CASINGS)


var _bone_mat: StandardMaterial3D


func _mat_bone_chunk() -> StandardMaterial3D:
	if _bone_mat == null:
		_bone_mat = StandardMaterial3D.new()
		_bone_mat.albedo_color = Color(0.62, 0.55, 0.42)
		_bone_mat.roughness = 0.5
	return _bone_mat


# Flesh and bone chunks that bounce around and fade.
var _gore_frame: int = -1
var _gore_budget: int = 0


func gore_burst(pos: Vector3, amount: int = 6, force: float = 4.0) -> void:
	var sc := _scene()
	if sc == null:
		return
	# Big blasts kill many at once: share a per-frame chunk budget between them
	var f := Engine.get_process_frames()
	if f != _gore_frame:
		_gore_frame = f
		_gore_budget = 16
	amount = mini(amount, _gore_budget)
	_gore_budget -= amount
	if amount <= 0:
		blood_spray(pos, Vector3.UP, 12)
		return
	for i in range(amount):
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = 0.2
		var s := randf_range(0.03, 0.075)
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = s * 0.5
		cs.shape = sph
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shared unit meshes, sized per chunk with scale (no new mesh per chunk)
		if i % 4 == 3:
			mi.mesh = _gore_mesh(true)
			mi.scale = Vector3.ONE * s
			mi.material_override = _mat_bone_chunk()
		else:
			mi.mesh = _gore_mesh(false)
			mi.scale = Vector3(randf_range(0.7, 1.3), randf_range(0.45, 0.8), randf_range(0.8, 1.5)) * s
			mi.material_override = _mat_gore if i % 3 != 0 else _mat_gore2
		rb.add_child(mi)
		sc.add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-0.15, 0.15), randf_range(0, 0.2), randf_range(-0.15, 0.15))
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.3, 0.9), randf_range(-1, 1)).normalized() * force * randf_range(0.45, 0.9)
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		var tw := rb.create_tween()
		tw.tween_interval(2.6)
		tw.tween_property(rb, "scale", Vector3.ONE * 0.01, 0.5)
		tw.tween_callback(rb.queue_free)
		_push(_gore, rb, MAX_GORE)
	blood_spray(pos, Vector3.UP, 16)
