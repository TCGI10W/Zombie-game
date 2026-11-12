class_name OpenTerrain
extends Node3D
# Seeded height field for the open world. Every location pad and road is
# flattened to y = 0 (so buildings, doors and stations sit on flat ground at
# the same height the old map used); between them the land rolls into hills,
# and the map edge climbs into mountains that wall the world in.
# Mesh: 64 m chunks of 4 m cells (vertex colours drive grass/dirt/rock), each
# with its own concave collider so the navmesh and physics follow the land.

const SIZE := 1024.0
const STEP := 4.0
const CHUNK := 16  # cells per chunk side (64 m)
const N := int(SIZE / STEP) + 1

var flats: Array = []  # [{"rect": Rect2, "fade": float}]
var roads: Array = []  # [{"pts": PackedVector2Array, "w": float}]
var heights := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _patch := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = 1987
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 4
	_detail.seed = 77
	_detail.frequency = 0.03
	_patch.seed = 5
	_patch.frequency = 0.02


func add_flat(rect: Rect2, fade: float = 28.0) -> void:
	flats.append({"rect": rect, "fade": fade})


func add_road(pts: PackedVector2Array, width: float) -> void:
	roads.append({"pts": pts, "w": width})


# Distance (m) from p to the nearest flattened area.
func _flat_dist(p: Vector2) -> float:
	var best := 1e9
	for f in flats:
		var r: Rect2 = f["rect"]
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz) * 28.0 / float(f["fade"]))
	for rd in roads:
		var pts: PackedVector2Array = rd["pts"]
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, maxf(p.distance_to(q) - float(rd["w"]) * 0.5 - 2.0, 0.0))
	return best


func _raw_height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 26.0 + _detail.get_noise_2d(x, z) * 1.6
	h = maxf(h, -4.0)
	var mask := smoothstep(0.0, 34.0, _flat_dist(Vector2(x, z)))
	var edge := maxf(absf(x), absf(z))
	var mountain := smoothstep(380.0, 500.0, edge) * (60.0 + _noise.get_noise_2d(x * 2.0, z * 2.0) * 30.0)
	return h * mask + mountain


func build() -> void:
	heights.resize(N * N)
	for j in range(N):
		for i in range(N):
			heights[j * N + i] = _raw_height(-SIZE * 0.5 + i * STEP, -SIZE * 0.5 + j * STEP)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ps1_terrain.gdshader")
	mat.set_shader_parameter("grass_tex", load("res://art/textures/grass_albedo.png"))
	mat.set_shader_parameter("dirt_tex", load("res://art/textures/dirt_albedo.png"))
	mat.set_shader_parameter("rock_tex", load("res://art/textures/rock_albedo.png"))
	var chunks := (N - 1) / CHUNK
	for cj in range(chunks):
		for ci in range(chunks):
			_build_chunk(ci, cj, mat)


# Bilinear height at any world point (props, trees, vehicles use this).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + SIZE * 0.5) / STEP, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(heights[j * N + i], heights[j * N + i + 1], tx)
	var b := lerpf(heights[(j + 1) * N + i], heights[(j + 1) * N + i + 1], tx)
	return lerpf(a, b, tz)


func _h(i: int, j: int) -> float:
	return heights[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]


func _build_chunk(ci: int, cj: int, mat: Material) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var i0 := ci * CHUNK
	var j0 := cj * CHUNK
	for j in range(CHUNK + 1):
		for i in range(CHUNK + 1):
			var gi := i0 + i
			var gj := j0 + j
			var x := -SIZE * 0.5 + gi * STEP
			var z := -SIZE * 0.5 + gj * STEP
			var h := _h(gi, gj)
			verts.append(Vector3(x, h, z))
			var n := Vector3(_h(gi - 1, gj) - _h(gi + 1, gj), 2.0 * STEP, _h(gi, gj - 1) - _h(gi, gj + 1)).normalized()
			norms.append(n)
			var rock := clampf((1.0 - n.y) * 6.0, 0.0, 1.0)
			var dirt := clampf(_patch.get_noise_2d(x, z) * 1.4 + 0.45, 0.0, 1.0)
			if _flat_dist(Vector2(x, z)) < 6.0:
				dirt = maxf(dirt, 0.7)  # trodden ground around towns and roads
			cols.append(Color(rock, dirt, 0.0))
	var row := CHUNK + 1
	for j in range(CHUNK):
		for i in range(CHUNK):
			var a := j * row + i
			idx.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)
